-- Aozora School V2 tuition P0 R2-B.
-- Extends the single canonical candidate reader to accept both F1 writer sources.
-- Required psql variable: r2_b_commit=0 for full rollback rehearsal or 1 for deployment.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_b_commit}
\else
  \echo 'R2_B_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '240s';

DO $preflight$
DECLARE
  v_definition text;
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368'
     OR md5(pg_get_functiondef(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
     )) <> 'ea71010c17f880ee61092bb8e01ea920'
     OR md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     )) <> '13fbc4d680d3b223cd2c6b59d66f2384' THEN
    RAISE EXCEPTION 'R2_B_PROTECTED_READER_DRIFT';
  END IF;

  SELECT pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  ) INTO STRICT v_definition;
  IF position('approved_r1c_a_manifest' IN v_definition) = 0
     OR position('approved_r1c_c_b_manifest' IN v_definition) = 0
     OR position('scheduled_date_at_create' IN v_definition) > 0
     OR position('explicit_billing_week_at_create' IN v_definition) > 0 THEN
    RAISE EXCEPTION 'R2_B_EXPECTED_OLD_SOURCE_RULE_MISSING';
  END IF;

  IF public.school_r1d_f1_planned_attribution_cutover_version()
       <> 'r1d_f1_planned_attribution_v1'
     OR has_function_privilege(
       'authenticated',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'R2_B_F1_OR_CANDIDATE_ACL_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_B_R0_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.lesson_type = 'planned'
      AND num_nonnulls(
        lesson.billing_month,lesson.billing_week_start_date,
        lesson.student_settlement_month,lesson.billing_month_source,
        lesson.billing_month_decided_at
      ) BETWEEN 1 AND 4
  ) THEN
    RAISE EXCEPTION 'R2_B_EXISTING_PARTIAL_ATTRIBUTION_BUNDLE';
  END IF;
END
$preflight$;

CREATE TEMPORARY TABLE r2_b_business_before ON COMMIT DROP AS
SELECT jsonb_build_object(
  'lessons',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_lesson_records t),
  'bills',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_tuition_bills t),
  'income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_income_records t),
  'relations',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_tuition_bill_lessons t),
  'historical_exclusions',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.planned_lesson_id::text),''))) FROM public.school_student_tuition_historical_lesson_exclusions t),
  'gates',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.feature_key),''))) FROM public.school_feature_gates t)
) AS fingerprint;

CREATE OR REPLACE FUNCTION public.school_list_student_tuition_candidates(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_billing_month text,
  p_include_excluded boolean DEFAULT false
)
RETURNS TABLE (
  planned_lesson_id uuid,
  student_id uuid,
  business_entity_id uuid,
  candidate_billing_month text,
  lesson_date date,
  year_month text,
  teacher_id uuid,
  subject_id uuid,
  lesson_count integer,
  duration_hours numeric,
  unit_price numeric,
  lesson_fee numeric,
  candidate_status text,
  exclusion_reason text,
  has_normalized_bill_relation boolean,
  relation_roles text[],
  associated_bill_ids uuid[],
  associated_billing_identity_ids uuid[],
  has_bill_snapshot_evidence boolean,
  snapshot_bill_ids uuid[],
  bill_evidence_conflict boolean,
  complete_row_hash text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_billing_month text := nullif(trim(coalesce(p_billing_month, '')), '');
BEGIN
  IF p_student_id IS NULL THEN
    RAISE EXCEPTION 'R1C_B_STUDENT_REQUIRED';
  END IF;

  IF p_business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R1C_B_BUSINESS_ENTITY_REQUIRED';
  END IF;

  IF v_billing_month IS NULL
     OR v_billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R1C_B_BILLING_MONTH_INVALID';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_student_tuition_bills bill
    WHERE bill.source_snapshot IS NULL
       OR NOT (bill.source_snapshot ? 'planned_lesson_ids')
       OR jsonb_typeof(bill.source_snapshot -> 'planned_lesson_ids') <> 'array'
  ) THEN
    RAISE EXCEPTION 'R1C_B_BILL_SNAPSHOT_FORMAT_UNSAFE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_student_tuition_bills bill
    CROSS JOIN LATERAL jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) snapshot_lesson(lesson_id_text)
    WHERE snapshot_lesson.lesson_id_text
      !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ) THEN
    RAISE EXCEPTION 'R1C_B_BILL_SNAPSHOT_LESSON_ID_UNSAFE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_student_tuition_bills bill
    CROSS JOIN LATERAL jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) snapshot_lesson(lesson_id_text)
    GROUP BY bill.id, snapshot_lesson.lesson_id_text
    HAVING count(*) <> 1
  ) THEN
    RAISE EXCEPTION 'R1C_B_BILL_SNAPSHOT_DUPLICATE_LESSON_ID';
  END IF;

  RETURN QUERY
  WITH snapshot_rows AS (
    SELECT
      bill.id AS bill_id,
      snapshot_lesson.lesson_id_text::uuid AS planned_lesson_id,
      snapshot_lesson.line_no::integer AS line_no
    FROM public.school_student_tuition_bills bill
    CROSS JOIN LATERAL jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) WITH ORDINALITY snapshot_lesson(lesson_id_text, line_no)
  ),
  relation_evidence AS (
    SELECT
      relation.planned_lesson_id,
      array_agg(DISTINCT relation.relation_role ORDER BY relation.relation_role) AS relation_roles,
      array_agg(DISTINCT relation.tuition_bill_id ORDER BY relation.tuition_bill_id) AS bill_ids,
      coalesce(
        array_agg(DISTINCT identity.id ORDER BY identity.id)
          FILTER (WHERE identity.id IS NOT NULL),
        '{}'::uuid[]
      ) AS identity_ids,
      bool_or(
        snapshot.bill_id IS NULL
        OR snapshot.line_no IS DISTINCT FROM relation.line_no
      ) AS relation_snapshot_mismatch
    FROM public.school_student_tuition_bill_lessons relation
    LEFT JOIN snapshot_rows snapshot
      ON snapshot.bill_id = relation.tuition_bill_id
     AND snapshot.planned_lesson_id = relation.planned_lesson_id
    LEFT JOIN public.school_student_tuition_billing_identities identity
      ON identity.canonical_bill_id = relation.tuition_bill_id
    GROUP BY relation.planned_lesson_id
  ),
  snapshot_evidence AS (
    SELECT
      snapshot.planned_lesson_id,
      array_agg(DISTINCT snapshot.bill_id ORDER BY snapshot.bill_id) AS bill_ids
    FROM snapshot_rows snapshot
    GROUP BY snapshot.planned_lesson_id
  ),
  evidence_rows AS (
    SELECT
      lesson.*,
      relation.planned_lesson_id IS NOT NULL AS has_relation,
      coalesce(relation.relation_roles, '{}'::text[]) AS normalized_relation_roles,
      coalesce(relation.bill_ids, '{}'::uuid[]) AS normalized_bill_ids,
      coalesce(relation.identity_ids, '{}'::uuid[]) AS billing_identity_ids,
      snapshot.planned_lesson_id IS NOT NULL AS has_snapshot,
      coalesce(snapshot.bill_ids, '{}'::uuid[]) AS historical_snapshot_bill_ids,
      (
        coalesce(relation.relation_snapshot_mismatch, false)
        OR coalesce(relation.bill_ids, '{}'::uuid[])
           IS DISTINCT FROM coalesce(snapshot.bill_ids, '{}'::uuid[])
      ) AS evidence_conflict,
      exclusion.planned_lesson_id IS NOT NULL AS has_historical_paid_exclusion
    FROM public.school_lesson_records lesson
    LEFT JOIN relation_evidence relation
      ON relation.planned_lesson_id = lesson.id
    LEFT JOIN snapshot_evidence snapshot
      ON snapshot.planned_lesson_id = lesson.id
    LEFT JOIN public.school_student_tuition_historical_lesson_exclusions exclusion
      ON exclusion.planned_lesson_id = lesson.id
    WHERE lesson.student_id = p_student_id
      AND lesson.billing_month = v_billing_month
  ),
  classified AS (
    SELECT
      evidence.*,
      CASE
        WHEN evidence.app_type IS DISTINCT FROM 'school'
          OR evidence.business_entity_id IS DISTINCT FROM p_business_entity_id
          THEN 'scope_mismatch'
        WHEN evidence.has_historical_paid_exclusion
          THEN 'historical_paid_exclusion'
        ELSE public.school_classify_student_tuition_candidate(
          true,
          evidence.has_relation,
          evidence.normalized_relation_roles,
          evidence.has_snapshot,
          evidence.evidence_conflict,
          evidence.lesson_type,
          evidence.status,
          evidence.voided_at,
          evidence.is_billable,
          evidence.student_id IS NOT NULL
            AND evidence.business_entity_id IS NOT NULL
            AND evidence.billing_month = v_billing_month
            AND evidence.billing_week_start_date IS NOT NULL
            AND public.school_is_valid_tuition_billing_period(
              evidence.billing_month,evidence.billing_week_start_date
            )
            AND evidence.student_settlement_month = evidence.billing_month
            AND evidence.billing_month_source IN (
              'approved_r1c_a_manifest',
              'approved_r1c_c_b_manifest',
              'scheduled_date_at_create',
              'explicit_billing_week_at_create'
            )
            AND evidence.billing_month_decided_at IS NOT NULL
            AND evidence.lesson_date IS NOT NULL
            AND evidence.teacher_id IS NOT NULL
            AND evidence.subject_id IS NOT NULL
            AND evidence.lesson_count IS NOT NULL
            AND evidence.lesson_count > 0
            AND evidence.duration_hours > 0
            AND evidence.unit_price IS NOT NULL
            AND evidence.unit_price > 0
            AND evidence.lesson_fee IS NOT NULL
            AND evidence.lesson_fee > 0
            AND evidence.created_at IS NOT NULL
            AND evidence.updated_at IS NOT NULL
        )
      END AS reason_code
    FROM evidence_rows evidence
  )
  SELECT
    classified.id,
    classified.student_id,
    classified.business_entity_id,
    classified.billing_month,
    classified.lesson_date,
    classified.year_month,
    classified.teacher_id,
    classified.subject_id,
    classified.lesson_count,
    classified.duration_hours,
    classified.unit_price,
    classified.lesson_fee,
    CASE WHEN classified.reason_code = 'candidate' THEN 'candidate' ELSE 'excluded' END,
    CASE WHEN classified.reason_code = 'candidate' THEN NULL ELSE classified.reason_code END,
    classified.has_relation,
    classified.normalized_relation_roles,
    classified.normalized_bill_ids,
    classified.billing_identity_ids,
    classified.has_snapshot,
    classified.historical_snapshot_bill_ids,
    classified.evidence_conflict,
    md5((to_jsonb(classified) - ARRAY[
      'has_relation',
      'normalized_relation_roles',
      'normalized_bill_ids',
      'billing_identity_ids',
      'has_snapshot',
      'historical_snapshot_bill_ids',
      'evidence_conflict',
      'has_historical_paid_exclusion',
      'reason_code'
    ]::text[])::text)
  FROM classified
  WHERE coalesce(p_include_excluded, false)
     OR classified.reason_code = 'candidate'
  ORDER BY classified.billing_week_start_date,classified.lesson_date,classified.id;
END
$function$;

COMMENT ON FUNCTION public.school_list_student_tuition_candidates(uuid,uuid,text,boolean) IS
  'R2-B canonical service-role candidate reader. Accepts the two approved migration manifests and both F1 planned-writer sources only when the full immutable attribution bundle and all existing candidate/evidence invariants pass. No legacy year_month or lesson_date billing fallback.';

REVOKE ALL ON FUNCTION public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)
  TO service_role;

DO $verify$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  ) INTO STRICT v_definition;
  IF md5(v_definition) <> '1770f3469dbc3bc030a977381b853deb'
     OR position('scheduled_date_at_create' IN v_definition) = 0
     OR position('explicit_billing_week_at_create' IN v_definition) = 0
     OR position('approved_r1c_a_manifest' IN v_definition) = 0
     OR position('approved_r1c_c_b_manifest' IN v_definition) = 0
     OR position('school_student_tuition_bill_lessons' IN v_definition) = 0
     OR position('planned_lesson_ids' IN v_definition) = 0
     OR position('school_student_tuition_historical_lesson_exclusions' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'R2_B_NEW_READER_DEFINITION_INCOMPLETE';
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
     ) THEN
    RAISE EXCEPTION 'R2_B_CANDIDATE_READER_ACL_EXPANDED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
     )) <> 'ea71010c17f880ee61092bb8e01ea920'
     OR md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     )) <> '13fbc4d680d3b223cd2c6b59d66f2384' THEN
    RAISE EXCEPTION 'R2_B_PREVIEW_WRAPPER_CHANGED';
  END IF;

  SELECT fingerprint INTO STRICT v_before FROM r2_b_business_before;
  SELECT jsonb_build_object(
    'lessons',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_lesson_records t),
    'bills',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_tuition_bills t),
    'income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_income_records t),
    'relations',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_tuition_bill_lessons t),
    'historical_exclusions',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.planned_lesson_id::text),''))) FROM public.school_student_tuition_historical_lesson_exclusions t),
    'gates',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.feature_key),''))) FROM public.school_feature_gates t)
  ) INTO v_after;
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'R2_B_BUSINESS_DATA_CHANGED';
  END IF;
END
$verify$;

SELECT
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) AS candidate_definition_md5,
  md5(pg_get_functiondef(
    'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
  )) AS preview_definition_md5,
  md5(pg_get_functiondef(
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
  )) AS detail_definition_md5;

\if :r2_b_commit
  COMMIT;
  \echo 'R2_B_CANDIDATE_F1_SOURCE_COMPATIBILITY_COMMITTED'
\else
  \set r2_b_tests_existing_tx 1
  \ir school_tuition_r2_b_candidate_f1_source_compatibility_rollback_tests.sql
  \ir school_tuition_r2_b_candidate_f1_source_compatibility_postdeploy.sql
  ROLLBACK;
  \echo 'R2_B_CANDIDATE_F1_SOURCE_COMPATIBILITY_REHEARSAL_ROLLED_BACK'
\endif
