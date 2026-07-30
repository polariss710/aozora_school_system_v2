\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '300s';

CREATE TEMPORARY TABLE s1_c_test_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_source_equal uuid;
  v_source_overage_one uuid;
  v_source_overage_two uuid;
  v_source_cancel uuid;
  v_source_partial uuid;
  v_actual_equal uuid;
  v_actual_overage_one uuid;
  v_actual_overage_two uuid;
  v_actual_cancel uuid;
  v_actual_partial uuid;
  v_actual_makeup uuid;
  v_source_month text;
  v_next_month text;
  v_zero_aggregate record;
  v_live_aggregate record;
  v_locked_aggregate record;
  v_preview_before record;
  v_preview_after record;
  v_preview_locked_one record;
  v_preview_locked_two record;
  v_preview_next_one record;
  v_preview_next_two record;
  v_locked record;
  v_unlocked record;
  v_relocked record;
  v_snapshot public.school_student_monthly_settlements%ROWTYPE;
  v_expected_cny numeric;
  v_bill_count_before bigint;
  v_income_count_before bigint;
BEGIN
  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type = 'school'
    AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned'
    AND lesson.voided_at IS NULL
    AND lesson.billing_month_source IN (
      'approved_r1c_a_manifest',
      'approved_r1c_c_b_manifest'
    )
    AND lesson.student_id IS NOT NULL
    AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id =
      public.school_primary_business_entity_id()
  ORDER BY lesson.id
  LIMIT 1;

  SELECT count(*) INTO v_bill_count_before
  FROM public.school_student_tuition_bills;
  SELECT count(*) INTO v_income_count_before
  FROM public.school_income_records;

  SELECT lesson_id INTO STRICT v_source_equal
  FROM public.school_create_planned_lesson_record(
    DATE '2035-02-05', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '09:00', '11:00', 0, 1000, NULL, 'planned', 1,
    'codex-test S1-C equal source', 'codex-test s1-c'
  );
  SELECT lesson_id INTO STRICT v_source_overage_one
  FROM public.school_create_planned_lesson_record(
    DATE '2035-02-12', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '09:00', '11:00', 0, 1000, NULL, 'planned', 1,
    'codex-test S1-C overage one source', 'codex-test s1-c'
  );
  SELECT lesson_id INTO STRICT v_source_overage_two
  FROM public.school_create_planned_lesson_record(
    DATE '2035-02-19', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '09:00', '11:00', 0, 1200, NULL, 'planned', 1,
    'codex-test S1-C overage two source', 'codex-test s1-c'
  );
  SELECT lesson_id INTO STRICT v_source_cancel
  FROM public.school_create_planned_lesson_record(
    DATE '2035-02-26', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '09:00', '11:00', 0, 1000, NULL, 'planned', 1,
    'codex-test S1-C cancelled source', 'codex-test s1-c'
  );
  SELECT lesson_id INTO STRICT v_source_partial
  FROM public.school_create_planned_lesson_record(
    DATE '2035-02-27', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '09:00', '11:00', 0, 1000, NULL, 'planned', 1,
    'codex-test S1-C partial source', 'codex-test s1-c'
  );

  SELECT student_settlement_month INTO STRICT v_source_month
  FROM public.school_lesson_records
  WHERE id = v_source_equal;
  v_next_month := to_char(
    (to_date(v_source_month || '-01', 'YYYY-MM-DD')
      + interval '1 month')::date,
    'YYYY-MM'
  );

  IF v_source_month <> '2035-02'
     OR EXISTS (
       SELECT 1 FROM public.school_lesson_records l
       WHERE l.id IN (
         v_source_overage_one, v_source_overage_two,
         v_source_cancel, v_source_partial
       )
         AND l.student_settlement_month IS DISTINCT FROM v_source_month
     ) THEN
    RAISE EXCEPTION 'S1_C_FIXTURE_SOURCE_MONTH_MISMATCH';
  END IF;

  SELECT lesson_id INTO STRICT v_actual_equal
  FROM public.school_create_actual_lesson_from_planned(
    v_source_equal, DATE '2035-03-05', '09:00', '11:00',
    2, 9999, NULL, 1,
    'codex-test S1-C equal actual', 'codex-test s1-c'
  );
  SELECT lesson_id INTO STRICT v_actual_cancel
  FROM public.school_create_cancelled_actual_lesson_from_planned(
    v_source_cancel, DATE '2035-03-26', '09:00', '11:00',
    2, 1000, 1,
    'codex-test S1-C cancelled actual', 'codex-test s1-c'
  );
  SELECT id INTO STRICT v_actual_partial
  FROM public.school_create_partial_completed_actual_from_planned(
    v_source_partial, DATE '2035-03-27', '09:00', '10:00', 1,
    'codex-test S1-C partial actual', 'codex-test s1-c'
  );
  SELECT id INTO STRICT v_actual_makeup
  FROM public.school_create_lesson_credit_makeup_actual(
    v_source_partial, DATE '2035-03-28', NULL, NULL,
    '09:00', '10:00', 1,
    'codex-test S1-C makeup actual', 'codex-test s1-c',
    1, NULL, NULL
  );

  SELECT * INTO STRICT v_zero_aggregate
  FROM public.school_get_student_duration_overage_aggregate(
    v_fixture.student_id, v_source_month
  );
  SELECT * INTO STRICT v_preview_before
  FROM public.school_get_student_monthly_settlement_preview(
    v_fixture.student_id, v_source_month
  );

  IF v_zero_aggregate.duration_overage_minutes <> 0
     OR v_zero_aggregate.duration_overage_fee_jpy <> 0
     OR v_zero_aggregate.duration_overage_fee_cny <> 0
     OR v_zero_aggregate.duration_overage_actual_count <> 0
     OR v_zero_aggregate.aggregation_basis <>
       'live_s1_b_actual_aggregate' THEN
    RAISE EXCEPTION 'S1_C_ZERO_OR_EXCLUSION_PREVIEW_FAILED';
  END IF;
  INSERT INTO s1_c_test_results VALUES
    ('zero_and_exclusions', true,
     'equal, partial, makeup, cancelled and NULL policy facts aggregate to zero');

  SELECT lesson_id INTO STRICT v_actual_overage_one
  FROM public.school_create_actual_lesson_from_planned(
    v_source_overage_one, DATE '2035-03-12', '09:00', '11:30',
    2.5, 9999, NULL, 1,
    'codex-test S1-C overage one actual', 'codex-test s1-c'
  );
  SELECT lesson_id INTO STRICT v_actual_overage_two
  FROM public.school_create_actual_lesson_from_planned(
    v_source_overage_two, DATE '2035-03-19', '09:00', '11:15',
    2.25, 8888, NULL, 1,
    'codex-test S1-C overage two actual', 'codex-test s1-c'
  );

  SELECT * INTO STRICT v_live_aggregate
  FROM public.school_get_student_duration_overage_aggregate(
    v_fixture.student_id, v_source_month
  );
  SELECT * INTO STRICT v_preview_after
  FROM public.school_get_student_monthly_settlement_preview(
    v_fixture.student_id, v_source_month
  );
  v_expected_cny := round(
    800 * coalesce(v_preview_after.exchange_rate, 0),
    2
  );

  IF v_live_aggregate.duration_overage_minutes <> 45
     OR v_live_aggregate.duration_overage_fee_jpy <> 800
     OR v_live_aggregate.duration_overage_fee_cny <> v_expected_cny
     OR v_live_aggregate.duration_overage_actual_count <> 2
     OR v_live_aggregate.aggregation_basis <>
       'live_s1_b_actual_aggregate' THEN
    RAISE EXCEPTION 'S1_C_LIVE_AGGREGATE_OR_RATE_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    WHERE a.id IN (v_actual_overage_one, v_actual_overage_two)
      AND (
        a.student_settlement_month IS DISTINCT FROM v_source_month
        OR a.teacher_settlement_month <> '2035-03'
      )
  ) THEN
    RAISE EXCEPTION 'S1_C_ACTUAL_DATE_CHANGED_SOURCE_MONTH';
  END IF;

  IF v_preview_after.final_due_cny - v_preview_before.final_due_cny
       <> v_expected_cny
     OR v_preview_after.planned_fee_cny IS DISTINCT FROM
       v_preview_before.planned_fee_cny
     OR v_preview_after.actual_fee_cny <= v_preview_before.actual_fee_cny THEN
    RAISE EXCEPTION 'S1_C_FINAL_DUE_POSITIVE_OVERAGE_FORMULA_FAILED';
  END IF;
  INSERT INTO s1_c_test_results VALUES
    ('live_aggregate', true, 'two frozen facts sum to 45 minutes and JPY 800'),
    ('source_month', true, 'March actual dates remain in February student month'),
    ('source_rate', true, 'JPY 800 converted once with source-month preview rate'),
    ('positive_final_due', true,
     'planned base is unchanged and final due increases only by overage CNY');

  SELECT * INTO STRICT v_locked
  FROM public.school_lock_student_monthly_settlement(
    v_fixture.student_id, v_source_month, 'codex-test S1-C lock'
  );
  SELECT * INTO STRICT v_snapshot
  FROM public.school_student_monthly_settlements
  WHERE id = v_locked.settlement_id;

  IF v_snapshot.duration_overage_minutes <> 45
     OR v_snapshot.duration_overage_fee_jpy <> 800
     OR v_snapshot.duration_overage_fee_cny <> v_expected_cny
     OR v_snapshot.duration_overage_actual_count <> 2
     OR v_snapshot.duration_overage_policy_version <>
       'student_duration_overage_v1'
     OR v_snapshot.duration_overage_source <> 'monthly_settlement_lock'
     OR v_snapshot.system_difference_cny IS DISTINCT FROM
       v_preview_after.final_due_cny
     OR v_snapshot.carryover_amount_cny IS DISTINCT FROM
       v_preview_after.locked_carryover_cny THEN
    RAISE EXCEPTION 'S1_C_LOCK_SNAPSHOT_FAILED';
  END IF;

  SELECT * INTO STRICT v_locked_aggregate
  FROM public.school_get_student_duration_overage_aggregate(
    v_fixture.student_id, v_source_month
  );
  SELECT * INTO STRICT v_preview_locked_one
  FROM public.school_get_student_monthly_settlement_preview(
    v_fixture.student_id, v_source_month
  );
  SELECT * INTO STRICT v_preview_locked_two
  FROM public.school_get_student_monthly_settlement_preview(
    v_fixture.student_id, v_source_month
  );

  IF v_locked_aggregate.aggregation_basis <> 'locked_snapshot'
     OR v_locked_aggregate.duration_overage_fee_cny <> v_expected_cny
     OR v_preview_locked_one.final_due_cny IS DISTINCT FROM
       v_preview_after.final_due_cny
     OR v_preview_locked_two.final_due_cny IS DISTINCT FROM
       v_preview_locked_one.final_due_cny THEN
    RAISE EXCEPTION 'S1_C_LOCKED_READ_DUPLICATED_OVERAGE';
  END IF;
  INSERT INTO s1_c_test_results VALUES
    ('lock_snapshot', true, 'lock atomically writes all six overage fields'),
    ('locked_read_once', true, 'repeated locked previews consume one snapshot');

  SELECT * INTO STRICT v_unlocked
  FROM public.school_unlock_student_monthly_settlement(
    v_locked.settlement_id, 'codex-test S1-C unlock'
  );
  SELECT * INTO STRICT v_relocked
  FROM public.school_relock_student_monthly_settlement(
    v_locked.settlement_id, 'codex-test S1-C relock'
  );
  SELECT * INTO STRICT v_snapshot
  FROM public.school_student_monthly_settlements
  WHERE id = v_locked.settlement_id;

  IF v_unlocked.settlement_status <> 'unlocked'
     OR v_relocked.settlement_status <> 'locked'
     OR v_snapshot.duration_overage_minutes <> 45
     OR v_snapshot.duration_overage_fee_jpy <> 800
     OR v_snapshot.duration_overage_fee_cny <> v_expected_cny
     OR v_snapshot.duration_overage_actual_count <> 2
     OR v_snapshot.system_difference_cny IS DISTINCT FROM
       v_preview_after.final_due_cny THEN
    RAISE EXCEPTION 'S1_C_RELOCK_REPLACEMENT_FAILED';
  END IF;
  INSERT INTO s1_c_test_results VALUES
    ('relock_replaces_snapshot', true,
     'relock recomputes and replaces the same six-field snapshot');

  SELECT * INTO STRICT v_preview_next_one
  FROM public.school_get_student_monthly_settlement_preview(
    v_fixture.student_id, v_next_month
  );
  SELECT * INTO STRICT v_preview_next_two
  FROM public.school_get_student_monthly_settlement_preview(
    v_fixture.student_id, v_next_month
  );

  IF v_preview_next_one.carryover_cny IS DISTINCT FROM
       v_relocked.carryover_amount_cny
     OR v_preview_next_two.carryover_cny IS DISTINCT FROM
       v_preview_next_one.carryover_cny
     OR v_preview_next_one.final_due_cny IS DISTINCT FROM
       v_preview_next_one.carryover_cny
     OR v_preview_next_two.final_due_cny IS DISTINCT FROM
       v_preview_next_one.final_due_cny THEN
    RAISE EXCEPTION 'S1_C_NEXT_MONTH_CARRYOVER_DUPLICATED';
  END IF;
  INSERT INTO s1_c_test_results VALUES
    ('next_month_carryover_once', true,
     'next month reads the prior locked balance exactly once');

  IF (SELECT count(*) FROM public.school_student_tuition_bills)
       <> v_bill_count_before
     OR (SELECT count(*) FROM public.school_income_records)
       <> v_income_count_before THEN
    RAISE EXCEPTION 'S1_C_TEST_CHANGED_BILL_OR_INCOME';
  END IF;
  INSERT INTO s1_c_test_results VALUES
    ('bill_income_unchanged', true, 'no bill or income rows were written');

  IF md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) <> 'e3d9dd24f3fd7c533301bb5c1a27fa4f'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> 'ca52667c94a86608b4ab712f543b04b1' THEN
    RAISE EXCEPTION 'S1_C_TEST_CHANGED_S1_B_WRITER';
  END IF;
  INSERT INTO s1_c_test_results VALUES
    ('s1_b_writer_unchanged', true, 'ordinary writer and guarded updater MD5 unchanged');

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_C_TEST_CHANGED_R0';
  END IF;
  INSERT INTO s1_c_test_results VALUES
    ('r0_unchanged', true, 'validation_preview_only / blocked / blocked');

  RAISE NOTICE 'S1_C_TEST_ACTUAL_IDS=%,%,%,%,%,%',
    v_actual_equal, v_actual_overage_one, v_actual_overage_two,
    v_actual_cancel, v_actual_partial, v_actual_makeup;
END
$tests$;

SELECT test_name, passed, detail
FROM s1_c_test_results
ORDER BY test_name;

ROLLBACK;

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
DO $postrollback$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records l
    WHERE l.note = 'codex-test s1-c'
       OR l.lesson_content LIKE 'codex-test S1-C%'
  ) OR EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements s
    WHERE s.note LIKE 'codex-test S1-C%'
  ) THEN
    RAISE EXCEPTION 'S1_C_ROLLBACK_MARKER_RESIDUE';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_C_POSTROLLBACK_R0_CHANGED';
  END IF;
END
$postrollback$;

SELECT true AS s1_c_rollback_tests_pass,
       0 AS persisted_test_rows;
ROLLBACK;
