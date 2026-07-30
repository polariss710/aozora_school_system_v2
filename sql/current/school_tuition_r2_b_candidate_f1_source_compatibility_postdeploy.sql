-- R2-B current read-only postdeploy acceptance.

\set ON_ERROR_STOP on
\pset pager off

DO $postdeploy$
DECLARE
  v_definition text;
  v_detail record;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  ) INTO STRICT v_definition;

  IF md5(v_definition) <> '1770f3469dbc3bc030a977381b853deb'
     OR position('approved_r1c_a_manifest' IN v_definition) = 0
     OR position('approved_r1c_c_b_manifest' IN v_definition) = 0
     OR position('scheduled_date_at_create' IN v_definition) = 0
     OR position('explicit_billing_week_at_create' IN v_definition) = 0
     OR position('school_student_tuition_bill_lessons' IN v_definition) = 0
     OR position('planned_lesson_ids' IN v_definition) = 0
     OR position('school_student_tuition_historical_lesson_exclusions' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_DEFINITION_MISMATCH';
  END IF;

  IF has_function_privilege(
       'authenticated',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'authenticated',
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_ACL_MISMATCH';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
     )) <> 'ea71010c17f880ee61092bb8e01ea920'
     OR md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     )) <> '13fbc4d680d3b223cd2c6b59d66f2384' THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_PREVIEW_WRAPPER_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_R0_MISMATCH';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_lesson_records lesson
    WHERE lesson.lesson_type = 'planned'
      AND num_nonnulls(
        lesson.billing_month,lesson.billing_week_start_date,
        lesson.student_settlement_month,lesson.billing_month_source,
        lesson.billing_month_decided_at
      ) BETWEEN 1 AND 4
  )
  OR EXISTS (
    SELECT 1
    FROM public.school_lesson_records lesson
    WHERE lesson.lesson_type = 'planned'
      AND num_nonnulls(
        lesson.billing_month,lesson.billing_week_start_date,
        lesson.student_settlement_month,lesson.billing_month_source,
        lesson.billing_month_decided_at
      ) = 5
      AND lesson.billing_month_source NOT IN (
        'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
        'scheduled_date_at_create','explicit_billing_week_at_create'
      )
  ) THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_ATTRIBUTION_SOURCE_MISMATCH';
  END IF;

  IF EXISTS (
    WITH scopes AS (
      SELECT DISTINCT student_id,business_entity_id,billing_month
      FROM public.school_lesson_records
      WHERE app_type = 'school' AND lesson_type = 'planned'
        AND billing_month IS NOT NULL
    ), classified AS (
      SELECT candidate.*,lesson.billing_month_source
      FROM scopes scope
      CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
        scope.student_id,scope.business_entity_id,scope.billing_month,true
      ) candidate
      JOIN public.school_lesson_records lesson
        ON lesson.id = candidate.planned_lesson_id
    )
    SELECT 1 FROM classified
    WHERE billing_month_source IN (
      'scheduled_date_at_create','explicit_billing_week_at_create'
    )
      AND exclusion_reason = 'invalid_or_incomplete_data'
  ) THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_F1_SOURCE_STILL_INVALID';
  END IF;

  IF EXISTS (
    WITH scopes AS (
      SELECT DISTINCT student_id,business_entity_id,billing_month
      FROM public.school_lesson_records
      WHERE app_type = 'school' AND lesson_type = 'planned'
        AND billing_month IS NOT NULL
    ), candidates AS (
      SELECT candidate.*
      FROM scopes scope
      CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
        scope.student_id,scope.business_entity_id,scope.billing_month,false
      ) candidate
    )
    SELECT 1
    FROM candidates candidate
    JOIN public.school_lesson_records lesson
      ON lesson.id = candidate.planned_lesson_id
    WHERE lesson.app_type <> 'school'
       OR lesson.lesson_type <> 'planned'
       OR lesson.status <> 'planned'
       OR lesson.voided_at IS NOT NULL
       OR lesson.is_billable IS DISTINCT FROM true
       OR num_nonnulls(
         lesson.billing_month,lesson.billing_week_start_date,
         lesson.student_settlement_month,lesson.billing_month_source,
         lesson.billing_month_decided_at
       ) <> 5
       OR lesson.billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
       OR lesson.student_settlement_month <> lesson.billing_month
       OR extract(isodow FROM lesson.billing_week_start_date) <> 1
       OR to_char(lesson.billing_week_start_date,'YYYY-MM') <> lesson.billing_month
       OR lesson.billing_month_source NOT IN (
         'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
         'scheduled_date_at_create','explicit_billing_week_at_create'
       )
       OR lesson.student_id IS NULL OR lesson.business_entity_id IS NULL
       OR lesson.lesson_date IS NULL OR lesson.teacher_id IS NULL
       OR lesson.subject_id IS NULL OR lesson.lesson_count <= 0
       OR lesson.duration_hours <= 0 OR lesson.unit_price <= 0
       OR lesson.lesson_fee <= 0
  ) THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_CANDIDATE_INVARIANT_MISMATCH';
  END IF;

  IF EXISTS (
    WITH scopes AS (
      SELECT DISTINCT student_id,business_entity_id,billing_month
      FROM public.school_lesson_records
      WHERE app_type = 'school' AND lesson_type = 'planned'
        AND billing_month IS NOT NULL
    ), candidates AS (
      SELECT candidate.planned_lesson_id
      FROM scopes scope
      CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
        scope.student_id,scope.business_entity_id,scope.billing_month,false
      ) candidate
    )
    SELECT 1 FROM candidates
    GROUP BY planned_lesson_id HAVING count(*) <> 1
  ) THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_DUPLICATE_UUID';
  END IF;

  IF EXISTS (
    WITH scopes AS (
      SELECT DISTINCT student_id,business_entity_id,billing_month
      FROM public.school_lesson_records
      WHERE app_type = 'school' AND lesson_type = 'planned'
        AND billing_month IS NOT NULL
    ), candidates AS (
      SELECT candidate.planned_lesson_id
      FROM scopes scope
      CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
        scope.student_id,scope.business_entity_id,scope.billing_month,false
      ) candidate
    ), snapshot_rows AS (
      SELECT snapshot.value::uuid AS planned_lesson_id
      FROM public.school_student_tuition_bills bill
      CROSS JOIN LATERAL jsonb_array_elements_text(
        bill.source_snapshot -> 'planned_lesson_ids'
      ) snapshot(value)
    )
    SELECT 1 FROM candidates candidate
    WHERE EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons relation
                  WHERE relation.planned_lesson_id = candidate.planned_lesson_id)
       OR EXISTS (SELECT 1 FROM snapshot_rows snapshot
                  WHERE snapshot.planned_lesson_id = candidate.planned_lesson_id)
       OR EXISTS (SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions exclusion
                  WHERE exclusion.planned_lesson_id = candidate.planned_lesson_id)
       OR EXISTS (SELECT 1 FROM public.school_legacy_planned_settlement_evidence legacy
                  WHERE legacy.planned_lesson_id = candidate.planned_lesson_id)
  ) THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_EVIDENCE_EXCLUSION_BYPASS';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_lesson_records lesson
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
      lesson.student_id,lesson.business_entity_id,'2026-08',false
    ) candidate
    WHERE lesson.billing_week_start_date = DATE '2026-07-27'
      AND lesson.id = candidate.planned_lesson_id
  )
  OR NOT EXISTS (
    SELECT 1
    FROM public.school_lesson_records lesson
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
      lesson.student_id,lesson.business_entity_id,'2026-08',false
    ) candidate
    WHERE lesson.billing_week_start_date = DATE '2026-08-31'
      AND lesson.id = candidate.planned_lesson_id
  )
  OR NOT EXISTS (
    SELECT 1
    FROM public.school_lesson_records lesson
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
      lesson.student_id,lesson.business_entity_id,'2026-07',false
    ) candidate
    WHERE lesson.billing_week_start_date = DATE '2026-07-27'
      AND lesson.id = candidate.planned_lesson_id
  ) THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_CROSS_MONTH_WEEK_MISMATCH';
  END IF;

  SELECT * INTO STRICT v_detail
  FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.05
  );
  IF v_detail.feature_state <> 'validation_preview_only'
     OR v_detail.candidate_count <= 0
     OR v_detail.candidate_count <> jsonb_array_length(v_detail.candidates)
     OR v_detail.candidate_count <> (
       SELECT count(DISTINCT candidate.planned_lesson_id)
       FROM jsonb_to_recordset(v_detail.candidates) candidate(planned_lesson_id uuid)
     )
     OR v_detail.total_lesson_count <> (
       SELECT sum(candidate.lesson_count)
       FROM jsonb_to_recordset(v_detail.candidates) candidate(lesson_count integer)
     )
     OR v_detail.total_duration_hours <> (
       SELECT sum(candidate.duration_hours)
       FROM jsonb_to_recordset(v_detail.candidates) candidate(duration_hours numeric)
     )
     OR v_detail.total_fee_jpy <> (
       SELECT sum(candidate.lesson_fee)
       FROM jsonb_to_recordset(v_detail.candidates) candidate(lesson_fee numeric)
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_to_recordset(v_detail.candidates) candidate(
         billing_month text,billing_week_start_date date
       )
       WHERE candidate.billing_month <> '2026-08'
          OR candidate.billing_week_start_date = DATE '2026-07-27'
     )
     OR NOT EXISTS (
       SELECT 1 FROM jsonb_to_recordset(v_detail.candidates) candidate(
         billing_week_start_date date
       ) WHERE candidate.billing_week_start_date = DATE '2026-08-31'
     ) THEN
    RAISE EXCEPTION 'R2_B_POSTDEPLOY_REAL_PREVIEW_MISMATCH';
  END IF;
END
$postdeploy$;

WITH scopes AS (
  SELECT DISTINCT student_id,business_entity_id,billing_month
  FROM public.school_lesson_records
  WHERE app_type = 'school' AND lesson_type = 'planned'
    AND billing_month IS NOT NULL
), candidates AS (
  SELECT candidate.*,lesson.billing_month_source
  FROM scopes scope
  CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
    scope.student_id,scope.business_entity_id,scope.billing_month,false
  ) candidate
  JOIN public.school_lesson_records lesson ON lesson.id = candidate.planned_lesson_id
)
SELECT billing_month_source,count(*) AS candidate_count,
       sum(lesson_count) AS lesson_count,sum(duration_hours) AS duration_hours,
       sum(lesson_fee) AS fee_jpy
FROM candidates GROUP BY billing_month_source ORDER BY billing_month_source;

SELECT
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) AS candidate_definition_md5,
  (SELECT jsonb_object_agg(feature_key,state ORDER BY feature_key)
   FROM public.school_feature_gates
   WHERE feature_key IN (
     'student_tuition_preview','student_tuition_generate','student_tuition_cash_submit'
   )) AS r0_states,
  (SELECT count(*) FROM public.school_lesson_records) AS lesson_count,
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT count(*) FROM public.school_income_records) AS income_count;
