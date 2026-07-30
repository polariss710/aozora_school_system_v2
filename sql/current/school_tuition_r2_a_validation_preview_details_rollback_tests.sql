-- R2-A rollback tests. The only DML is a feature-gate negative fixture and is rolled back.

\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL statement_timeout = '180s';

CREATE TEMPORARY TABLE r2_a_rollback_baseline ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM public.school_lesson_records) AS lesson_count,
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT count(*) FROM public.school_income_records) AS income_count,
  (SELECT md5(string_agg(concat_ws('|', feature_key, state), E'\n'
    ORDER BY feature_key)) FROM public.school_feature_gates) AS gate_md5;

SET LOCAL ROLE authenticated;
SELECT
  feature_state,
  billing_month,
  candidate_count,
  total_lesson_count,
  total_duration_hours,
  total_fee_jpy,
  candidate_uuid_md5,
  candidate_manifest_sha256
FROM public.school_get_student_tuition_validation_preview_details(
  '7aef8061-7037-4881-a847-a2cdb031c0f4',
  '2026-08',
  0.05
);
RESET ROLE;

DO $positive_tests$
DECLARE
  v_result record;
BEGIN
  SELECT * INTO STRICT v_result
  FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4',
    '2026-08',
    0.05
  );

  IF v_result.candidate_count <= 0
     OR v_result.candidate_count <> (
       SELECT count(DISTINCT planned_lesson_id)
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         planned_lesson_id uuid
       )
     )
     OR v_result.total_lesson_count <> (
       SELECT sum(lesson_count)
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         lesson_count integer
       )
     )
     OR v_result.total_duration_hours <> (
       SELECT sum(duration_hours)
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         duration_hours numeric
       )
     )
     OR v_result.total_fee_jpy <> (
       SELECT sum(lesson_fee)
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         lesson_fee numeric
       )
     ) THEN
    RAISE EXCEPTION 'R2_A_ROLLBACK_SUMMARY_DETAIL_MISMATCH';
  END IF;

  IF EXISTS (
       SELECT 1
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         billing_month text,
         billing_week_start_date date
       )
       WHERE candidate.billing_month <> '2026-08'
          OR candidate.billing_week_start_date = '2026-07-27'::date
     )
     OR NOT EXISTS (
       SELECT 1
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         billing_week_start_date date
       )
       WHERE candidate.billing_week_start_date = '2026-08-31'::date
     )
     OR NOT public.school_is_valid_tuition_billing_period(
       '2026-07', '2026-07-27'::date
     )
     OR public.school_is_valid_tuition_billing_period(
       '2026-08', '2026-07-27'::date
     ) THEN
    RAISE EXCEPTION 'R2_A_ROLLBACK_CROSS_MONTH_MISMATCH';
  END IF;
END
$positive_tests$;

UPDATE public.school_feature_gates
SET state = 'blocked'
WHERE feature_key = 'student_tuition_preview'
  AND state = 'validation_preview_only';

DO $r0_negative_test$
BEGIN
  BEGIN
    PERFORM *
    FROM public.school_get_student_tuition_validation_preview_details(
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      '2026-08',
      0.05
    );
    RAISE EXCEPTION 'R2_A_EXPECTED_R0_FAILURE_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'R2_A_EXPECTED_R0_FAILURE_MISSING'
       OR position('TUITION_PREVIEW_BLOCKED' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
END
$r0_negative_test$;

ROLLBACK;
