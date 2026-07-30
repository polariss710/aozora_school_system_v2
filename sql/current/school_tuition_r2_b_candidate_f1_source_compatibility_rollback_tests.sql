-- R2-B rollback-only F1 source compatibility fixtures.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_b_tests_existing_tx}
  \echo 'R2_B_TESTS_USING_CALLER_TRANSACTION'
\else
  BEGIN;
\endif

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '240s';

CREATE TEMPORARY TABLE r2_b_test_baseline ON COMMIT DROP AS
SELECT jsonb_build_object(
  'lessons',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_lesson_records t),
  'bills',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_tuition_bills t),
  'income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_income_records t),
  'relations',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_tuition_bill_lessons t),
  'historical_exclusions',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.planned_lesson_id::text),''))) FROM public.school_student_tuition_historical_lesson_exclusions t),
  'gates',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.feature_key),''))) FROM public.school_feature_gates t)
) AS fingerprint;

CREATE TEMPORARY TABLE r2_b_test_ids (
  test_kind text PRIMARY KEY,
  lesson_id uuid NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_scheduled_id uuid;
  v_explicit_id uuid;
  v_detail record;
  v_preview record;
  v_partial_reason text;
  v_candidate_count integer;
  v_candidate_distinct integer;
  v_candidate_hours numeric;
  v_candidate_fee numeric;
BEGIN
  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type = 'school'
    AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned'
    AND lesson.voided_at IS NULL
    AND lesson.is_billable = true
    AND lesson.student_id IS NOT NULL
    AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id IS NOT NULL
    AND lesson.billing_month_source IN (
      'approved_r1c_a_manifest','approved_r1c_c_b_manifest'
    )
  ORDER BY lesson.id LIMIT 1;

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.student_id = v_fixture.student_id
      AND lesson.business_entity_id = v_fixture.business_entity_id
      AND lesson.billing_month = '2032-07'
  ) THEN
    RAISE EXCEPTION 'R2_B_TEST_FUTURE_SCOPE_NOT_EMPTY';
  END IF;

  SELECT created.lesson_id INTO STRICT v_scheduled_id
  FROM public.school_create_planned_lesson_record(
    DATE '2032-08-01',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,NULL,NULL,2,
    1000,NULL,'planned',1,'codex-test R2-B scheduled source',
    'codex-test r2-b rollback-only'
  ) created;
  INSERT INTO r2_b_test_ids VALUES ('scheduled',v_scheduled_id);

  SELECT generated.created_lesson_id INTO STRICT v_explicit_id
  FROM public.school_generate_planned_lessons_batch(
    'b2000000-0000-4000-8000-00000000b001'::uuid,
    v_fixture.student_id,v_fixture.business_entity_id,
    DATE '2032-07-26',DATE '2032-07-26',
    jsonb_build_array(jsonb_build_object(
      'pattern_index',1,'weekday',1,'status','planned',
      'teacher_id',v_fixture.teacher_id,'subject_id',v_fixture.subject_id,
      'start_time',NULL,'end_time',NULL,'duration_hours',2,
      'unit_price',1000,'occurrence_count',1,'lesson_count',1,
      'lesson_content','codex-test R2-B explicit source',
      'note','codex-test r2-b rollback-only'
    )),'[]'::jsonb,'codex-test r2-b rollback-only'
  ) generated
  WHERE generated.batch_committed
    AND generated.created_lesson_id IS NOT NULL;
  INSERT INTO r2_b_test_ids VALUES ('explicit',v_explicit_id);

  UPDATE public.school_lesson_records
  SET lesson_date = DATE '2032-08-01',
      note = 'codex-test r2-b explicit cross-month rollback-only'
  WHERE id = v_explicit_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id = v_scheduled_id
      AND lesson.billing_month_source = 'scheduled_date_at_create'
      AND lesson.billing_week_start_date = DATE '2032-07-26'
      AND lesson.billing_month = '2032-07'
      AND lesson.student_settlement_month = '2032-07'
      AND lesson.billing_month_decided_at IS NOT NULL
      AND lesson.lesson_date = DATE '2032-08-01'
  ) THEN
    RAISE EXCEPTION 'R2_B_TEST_SCHEDULED_ATTRIBUTION_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id = v_explicit_id
      AND lesson.billing_month_source = 'explicit_billing_week_at_create'
      AND lesson.billing_week_start_date = DATE '2032-07-26'
      AND lesson.billing_month = '2032-07'
      AND lesson.student_settlement_month = '2032-07'
      AND lesson.billing_month_decided_at IS NOT NULL
      AND lesson.lesson_date = DATE '2032-08-01'
  ) THEN
    RAISE EXCEPTION 'R2_B_TEST_EXPLICIT_ATTRIBUTION_FAILED';
  END IF;

  SELECT count(*),count(DISTINCT candidate.planned_lesson_id),
         sum(candidate.duration_hours),sum(candidate.lesson_fee)
  INTO v_candidate_count,v_candidate_distinct,v_candidate_hours,v_candidate_fee
  FROM public.school_list_student_tuition_candidates(
    v_fixture.student_id,v_fixture.business_entity_id,'2032-07',false
  ) candidate;
  IF v_candidate_count <> 2 OR v_candidate_distinct <> 2
     OR NOT EXISTS (
       SELECT 1 FROM public.school_list_student_tuition_candidates(
         v_fixture.student_id,v_fixture.business_entity_id,'2032-07',false
       ) candidate WHERE candidate.planned_lesson_id = v_scheduled_id
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.school_list_student_tuition_candidates(
         v_fixture.student_id,v_fixture.business_entity_id,'2032-07',false
       ) candidate WHERE candidate.planned_lesson_id = v_explicit_id
     )
     OR EXISTS (
       SELECT 1 FROM public.school_list_student_tuition_candidates(
         v_fixture.student_id,v_fixture.business_entity_id,'2032-08',false
       ) candidate WHERE candidate.planned_lesson_id IN (v_scheduled_id,v_explicit_id)
     ) THEN
    RAISE EXCEPTION 'R2_B_TEST_F1_CANDIDATE_MONTH_FAILED';
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
    RAISE EXCEPTION 'R2_B_TEST_2026_CROSS_MONTH_WEEK_FAILED';
  END IF;

  SELECT public.school_classify_student_tuition_candidate(
    true,false,'{}'::text[],false,false,'planned','planned',NULL,true,false
  ) INTO STRICT v_partial_reason;
  IF v_partial_reason <> 'invalid_or_incomplete_data'
     OR EXISTS (
       SELECT 1 FROM public.school_lesson_records lesson
       WHERE lesson.lesson_type = 'planned'
         AND num_nonnulls(
           lesson.billing_month,lesson.billing_week_start_date,
           lesson.student_settlement_month,lesson.billing_month_source,
           lesson.billing_month_decided_at
         ) BETWEEN 1 AND 4
     ) THEN
    RAISE EXCEPTION 'R2_B_TEST_PARTIAL_BUNDLE_FAIL_CLOSED_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence) <= 0
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <= 0
     OR (SELECT count(*) FROM public.school_student_tuition_bills) <= 0
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) <= 0 THEN
    RAISE EXCEPTION 'R2_B_TEST_EXISTING_EVIDENCE_MISSING';
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
    WHERE EXISTS (SELECT 1 FROM public.school_legacy_planned_settlement_evidence legacy
                  WHERE legacy.planned_lesson_id = candidate.planned_lesson_id)
       OR EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons relation
                  WHERE relation.planned_lesson_id = candidate.planned_lesson_id)
       OR EXISTS (SELECT 1 FROM snapshot_rows snapshot
                  WHERE snapshot.planned_lesson_id = candidate.planned_lesson_id)
       OR EXISTS (SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions exclusion
                  WHERE exclusion.planned_lesson_id = candidate.planned_lesson_id)
  ) THEN
    RAISE EXCEPTION 'R2_B_TEST_EXISTING_EVIDENCE_EXCLUSION_FAILED';
  END IF;

  SELECT * INTO STRICT v_preview
  FROM public.school_preview_student_tuition_bill(
    v_fixture.student_id,'2032-07',0.05
  );
  IF v_preview.planned_lesson_count <> v_candidate_count
     OR v_preview.planned_lesson_hours <> v_candidate_hours
     OR v_preview.planned_lesson_fee_jpy <> v_candidate_fee
     OR v_preview.bill_amount_jpy <> v_candidate_fee THEN
    RAISE EXCEPTION 'R2_B_TEST_PREVIEW_CANDIDATE_SUMMARY_FAILED';
  END IF;

  SELECT * INTO STRICT v_detail
  FROM public.school_get_student_tuition_validation_preview_details(
    v_fixture.student_id,'2032-07',0.05
  );
  IF v_detail.candidate_count <> 2
     OR v_detail.candidate_count <> jsonb_array_length(v_detail.candidates)
     OR v_detail.total_duration_hours <> v_candidate_hours
     OR v_detail.total_fee_jpy <> v_candidate_fee
     OR (SELECT count(DISTINCT lesson.billing_month_source)
         FROM jsonb_to_recordset(v_detail.candidates) candidate(planned_lesson_id uuid)
         JOIN public.school_lesson_records lesson ON lesson.id = candidate.planned_lesson_id
         WHERE lesson.billing_month_source IN (
           'scheduled_date_at_create','explicit_billing_week_at_create'
         )) <> 2 THEN
    RAISE EXCEPTION 'R2_B_TEST_DETAIL_F1_SOURCE_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3
     OR has_function_privilege(
       'authenticated',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'R2_B_TEST_R0_OR_ACL_FAILED';
  END IF;
END
$tests$;

SELECT test_kind,lesson.id,lesson.lesson_date,lesson.billing_week_start_date,
       lesson.billing_month,lesson.billing_month_source
FROM r2_b_test_ids test
JOIN public.school_lesson_records lesson ON lesson.id = test.lesson_id
ORDER BY test_kind;

\if :{?r2_b_tests_existing_tx}
  \echo 'R2_B_TESTS_COMPLETE_IN_CALLER_TRANSACTION'
\else
  ROLLBACK;
  DO $residue$
  BEGIN
    IF EXISTS (
      SELECT 1 FROM public.school_lesson_records
      WHERE note LIKE 'codex-test r2-b%'
         OR lesson_content LIKE 'codex-test R2-B%'
    ) THEN
      RAISE EXCEPTION 'R2_B_TEST_RESIDUE';
    END IF;
  END
  $residue$;
  \echo 'R2_B_ROLLBACK_TESTS_PASSED_RESIDUE_0'
\endif
