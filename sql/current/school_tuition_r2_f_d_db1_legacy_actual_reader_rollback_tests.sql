-- School V2 R2-F-D-DB1 rollback-only acceptance tests.
-- Uses existing rows read-only and always rolls back; creates no fixture.

\set ON_ERROR_STOP on
\pset pager off

\echo 'R2_F_D_DB1_ROLLBACK_TESTS_BEGIN'
BEGIN TRANSACTION READ ONLY ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='180s';

DO $tests$
DECLARE
  v_error text;
  v_actual record;
  v_candidate record;
BEGIN
  IF (SELECT count(*)
      FROM public.school_legacy_actual_settlement_evidence evidence
      WHERE public.school_resolve_r1d_e_c_lesson_student_month(
        evidence.actual_lesson_id)=evidence.legacy_year_month)<>234 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_TEST_LEGACY_234_RESOLUTION_FAILED';
  END IF;

  FOR v_actual IN
    SELECT actual.id,actual.student_settlement_month
    FROM public.school_lesson_records actual
    WHERE actual.app_type='school' AND actual.lesson_type='actual'
      AND NOT EXISTS (
        SELECT 1 FROM public.school_legacy_actual_settlement_evidence evidence
        WHERE evidence.actual_lesson_id=actual.id)
    ORDER BY actual.id
  LOOP
    IF public.school_resolve_r1d_e_c_lesson_student_month(v_actual.id)
         IS DISTINCT FROM v_actual.student_settlement_month THEN
      RAISE EXCEPTION 'R2_F_D_DB1_TEST_CANONICAL_ACTUAL_MONTH_FAILED:%',
        v_actual.id;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM public.school_lesson_records actual
      WHERE actual.app_type='school' AND actual.lesson_type='actual'
        AND NOT EXISTS (
          SELECT 1 FROM public.school_legacy_actual_settlement_evidence evidence
          WHERE evidence.actual_lesson_id=actual.id))<>6
     OR (SELECT count(*) FROM public.school_lesson_records actual
         WHERE actual.app_type='school' AND actual.lesson_type='actual'
           AND num_nonnulls(actual.student_duration_overage_minutes,
             actual.student_duration_overage_fee_jpy,
             actual.student_duration_overage_policy_version,
             actual.student_duration_overage_source,
             actual.student_duration_overage_decided_at)=5)<>2 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_TEST_CANONICAL_ACTUAL_COUNTS_CHANGED';
  END IF;

  PERFORM * FROM public.school_get_student_monthly_settlement_preview(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-07');
  PERFORM * FROM public.school_get_student_monthly_settlement_preview(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-07');

  SELECT count(*)::integer AS candidate_count,
    coalesce(sum(candidate.lesson_count),0)::integer AS lesson_count,
    coalesce(sum(candidate.duration_hours),0)::numeric AS duration_hours,
    coalesce(sum(candidate.base_lesson_fee_jpy),0)::numeric AS base_fee_jpy,
    coalesce(sum(candidate.aircon_fee_jpy),0)::numeric AS aircon_fee_jpy,
    count(DISTINCT candidate.planned_lesson_id)::integer AS distinct_count
  INTO STRICT v_candidate
  FROM public.school_list_student_tuition_charge_candidates(
    '7aef8061-7037-4881-a847-a2cdb031c0f4',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',false) candidate;
  IF v_candidate.candidate_count<>30 OR v_candidate.distinct_count<>30
     OR v_candidate.lesson_count<>35 OR v_candidate.duration_hours<>65
     OR v_candidate.base_fee_jpy<>650000 OR v_candidate.aircon_fee_jpy<>0 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_TEST_ZHANG_CANDIDATE_FAILED:%',
      to_jsonb(v_candidate);
  END IF;

  SELECT count(*)::integer AS candidate_count,
    coalesce(sum(candidate.lesson_count),0)::integer AS lesson_count,
    coalesce(sum(candidate.duration_hours),0)::numeric AS duration_hours,
    coalesce(sum(candidate.base_lesson_fee_jpy),0)::numeric AS base_fee_jpy,
    coalesce(sum(candidate.aircon_fee_jpy),0)::numeric AS aircon_fee_jpy,
    count(DISTINCT candidate.planned_lesson_id)::integer AS distinct_count
  INTO STRICT v_candidate
  FROM public.school_list_student_tuition_charge_candidates(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',false) candidate;
  IF v_candidate.candidate_count<>22 OR v_candidate.distinct_count<>22
     OR v_candidate.lesson_count<>24 OR v_candidate.duration_hours<>44
     OR v_candidate.base_fee_jpy<>374000 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_TEST_SUN_CANDIDATE_FAILED:%',
      to_jsonb(v_candidate);
  END IF;
  RAISE NOTICE 'R2_F_D_DB1_SUN_CANDIDATE=%',to_jsonb(v_candidate);

  IF EXISTS (
    SELECT 1
    FROM public.school_list_student_tuition_charge_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',false) candidate
    WHERE candidate.lesson_date IN (DATE '2026-08-01',DATE '2026-08-02')
  ) THEN
    RAISE EXCEPTION 'R2_F_D_DB1_TEST_SUN_CROSS_MONTH_SCOPE_FAILED';
  END IF;

  BEGIN
    PERFORM * FROM public.school_get_student_tuition_validation_preview_details(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.043);
    RAISE EXCEPTION 'R2_F_D_DB1_TEST_SUN_EXPECTED_PREVIOUS_SETTLEMENT_REQUIRED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_get_student_tuition_validation_preview_details(
      '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.043);
    RAISE EXCEPTION 'R2_F_D_DB1_TEST_ZHANG_EXPECTED_PREVIOUS_SETTLEMENT_REQUIRED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED' THEN RAISE; END IF;
  END;

  IF EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_D_DB1_TEST_WRITER_CONTEXT_NOT_EMPTY';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_TEST_R0_CHANGED';
  END IF;
END
$tests$;

\echo 'R2_F_D_DB1_ROLLBACK_TESTS_ROLLBACK'
ROLLBACK;
