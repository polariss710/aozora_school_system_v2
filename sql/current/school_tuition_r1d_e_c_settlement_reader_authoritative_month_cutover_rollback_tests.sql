-- School V2 tuition P0 R1D-E-C rollback-only resolver/reader/lock matrix.
-- Define r1d_e_c_tests_existing_tx when rehearsal owns BEGIN/ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_e_c_tests_existing_tx}
  \echo 'R1D_E_C_TESTS_USING_CALLER_TRANSACTION'
\else
  BEGIN;
\endif

SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';
LOCK TABLE public.school_lesson_records IN SHARE ROW EXCLUSIVE MODE;

CREATE TEMPORARY TABLE r1d_e_c_test_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_legacy_planned public.school_lesson_records%ROWTYPE;
  v_legacy_actual public.school_lesson_records%ROWTYPE;
  v_wage_actual public.school_lesson_records%ROWTYPE;
  v_legacy_snapshot public.school_student_monthly_settlements%ROWTYPE;
  v_legacy_planned_hash text;
  v_legacy_actual_hash text;
  v_source_ordinary uuid;
  v_source_cancel uuid;
  v_source_partial uuid;
  v_source_makeup uuid;
  v_source_draft uuid;
  v_actual_ordinary uuid;
  v_actual_cancel uuid;
  v_actual_partial uuid;
  v_actual_makeup uuid;
  v_settlement_id uuid;
  v_summary record;
  v_preview record;
  v_locked record;
  v_unlocked record;
  v_relocked record;
  v_target_month text;
  v_actual_month text;
  v_legacy_month text;
  v_count bigint;
BEGIN
  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
    AND lesson.status='planned' AND lesson.voided_at IS NULL
    AND lesson.billing_month_source IN (
      'approved_r1c_a_manifest','approved_r1c_c_b_manifest')
    AND lesson.student_id IS NOT NULL AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id=public.school_primary_business_entity_id()
  ORDER BY lesson.id LIMIT 1;

  SELECT lesson.* INTO STRICT v_legacy_planned
  FROM public.school_legacy_planned_settlement_evidence evidence
  JOIN public.school_lesson_records lesson
    ON lesson.id=evidence.planned_lesson_id
  WHERE lesson.student_id IS NOT NULL AND lesson.business_entity_id IS NOT NULL
  ORDER BY lesson.id LIMIT 1;
  v_legacy_planned_hash:=md5(to_jsonb(v_legacy_planned)::text);

  SELECT actual.* INTO STRICT v_legacy_actual
  FROM public.school_legacy_actual_settlement_evidence evidence
  JOIN public.school_lesson_records actual
    ON actual.id=evidence.actual_lesson_id
  ORDER BY actual.id LIMIT 1;
  v_legacy_actual_hash:=md5(to_jsonb(v_legacy_actual)::text);

  SELECT actual.* INTO STRICT v_wage_actual
  FROM public.school_legacy_actual_settlement_evidence evidence
  JOIN public.school_lesson_records actual
    ON actual.id=evidence.actual_lesson_id
  JOIN public.school_teacher_wage_lock_details detail
    ON detail.lesson_record_id=actual.id
  JOIN public.school_teacher_wage_locks wage ON wage.id=detail.lock_id
  WHERE coalesce(wage.status,'')<>'void' AND wage.voided_at IS NULL
  ORDER BY actual.id LIMIT 1;

  SELECT settlement.* INTO STRICT v_legacy_snapshot
  FROM public.school_legacy_settlement_snapshot_basis_evidence evidence
  JOIN public.school_student_monthly_settlements settlement
    ON settlement.id=evidence.settlement_snapshot_id
  ORDER BY settlement.id LIMIT 1;

  SELECT lesson_id INTO STRICT v_source_ordinary
  FROM public.school_create_planned_lesson_record(
    DATE '2033-01-02',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'15:00','17:00',0,
    1000,NULL,'planned',1,'codex-test R1D-E-C ordinary',
    'codex-test r1d-e-c');
  SELECT lesson_id INTO STRICT v_source_cancel
  FROM public.school_create_planned_lesson_record(
    DATE '2033-01-02',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'17:00','19:00',0,
    1000,NULL,'planned',1,'codex-test R1D-E-C cancelled',
    'codex-test r1d-e-c');
  SELECT lesson_id INTO STRICT v_source_partial
  FROM public.school_create_planned_lesson_record(
    DATE '2033-01-02',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'19:00','21:00',0,
    1000,NULL,'planned',1,'codex-test R1D-E-C partial',
    'codex-test r1d-e-c');
  SELECT lesson_id INTO STRICT v_source_makeup
  FROM public.school_create_planned_lesson_record(
    DATE '2033-01-02',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,NULL,NULL,3,
    1000,NULL,'planned',1,'codex-test R1D-E-C makeup',
    'codex-test r1d-e-c');
  UPDATE public.school_lesson_records SET status='pending_makeup'
  WHERE id=v_source_makeup;
  SELECT lesson_id INTO STRICT v_source_draft
  FROM public.school_create_planned_lesson_record(
    DATE '2032-12-05',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,NULL,NULL,2,
    1000,NULL,'planned',1,'codex-test R1D-E-C draft',
    'codex-test r1d-e-c');

  SELECT student_settlement_month INTO STRICT v_target_month
  FROM public.school_lesson_records WHERE id=v_source_ordinary;
  IF v_target_month<>'2032-12'
     OR (SELECT year_month FROM public.school_lesson_records
         WHERE id=v_source_ordinary)<>'2033-01'
     OR public.school_resolve_r1d_e_c_lesson_student_month(
          v_source_ordinary)<>v_target_month THEN
    RAISE EXCEPTION 'R1D_E_C_CANONICAL_PLANNED_RESOLUTION_FAILED';
  END IF;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_canonical_planned',true,'uses student_settlement_month');

  SELECT lesson_id INTO STRICT v_actual_ordinary
  FROM public.school_create_actual_lesson_from_planned(
    v_source_ordinary,DATE '2033-02-01','15:00','17:00',2,1000,NULL,1,
    'codex-test R1D-E-C ordinary actual','codex-test r1d-e-c');
  SELECT lesson_id INTO STRICT v_actual_cancel
  FROM public.school_create_cancelled_actual_lesson_from_planned(
    v_source_cancel,DATE '2033-02-01','17:00','19:00',2,1000,1,
    'codex-test R1D-E-C cancelled actual','codex-test r1d-e-c');
  SELECT id INTO STRICT v_actual_partial
  FROM public.school_create_partial_completed_actual_from_planned(
    v_source_partial,DATE '2033-02-01','19:00','20:00',1,
    'codex-test R1D-E-C partial actual','codex-test r1d-e-c');
  SELECT id INTO STRICT v_actual_makeup
  FROM public.school_create_lesson_credit_makeup_actual(
    v_source_makeup,DATE '2033-02-01',NULL,NULL,'15:00','16:00',1,
    'codex-test R1D-E-C makeup actual','codex-test r1d-e-c',1,NULL,NULL);

  SELECT teacher_settlement_month INTO STRICT v_actual_month
  FROM public.school_lesson_records WHERE id=v_actual_ordinary;
  IF public.school_resolve_r1d_e_c_lesson_student_month(v_actual_ordinary)<>
       v_target_month
     OR v_actual_month<>'2033-02'
     OR NOT EXISTS (SELECT 1 FROM public.school_lesson_records
       WHERE id=v_actual_ordinary AND year_month=v_target_month
         AND student_settlement_month=v_target_month) THEN
    RAISE EXCEPTION 'R1D_E_C_CANONICAL_ACTUAL_RESOLUTION_FAILED';
  END IF;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_canonical_actual_cross_month',true,
     'student month inherited; teacher month remains actual date');

  SELECT evidence.legacy_student_settlement_month INTO STRICT v_legacy_month
  FROM public.school_legacy_planned_settlement_evidence evidence
  WHERE evidence.planned_lesson_id=v_legacy_planned.id;
  IF public.school_resolve_r1d_e_c_lesson_student_month(v_legacy_planned.id)<>
       v_legacy_month THEN
    RAISE EXCEPTION 'R1D_E_C_LEGACY_PLANNED_RESOLUTION_FAILED';
  END IF;
  SELECT evidence.legacy_year_month INTO STRICT v_legacy_month
  FROM public.school_legacy_actual_settlement_evidence evidence
  WHERE evidence.actual_lesson_id=v_legacy_actual.id;
  IF public.school_resolve_r1d_e_c_lesson_student_month(v_legacy_actual.id)<>
       v_legacy_month THEN
    RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_RESOLUTION_FAILED';
  END IF;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_legacy_planned',true,'immutable planned evidence month'),
    ('resolver_legacy_actual',true,'immutable actual evidence month');

  SELECT count(*) INTO v_count
  FROM public.school_list_r1d_e_c_student_month_lessons(
    v_fixture.student_id,v_target_month) resolved
  WHERE resolved.lesson_id IN (v_source_ordinary,v_source_cancel,
    v_source_partial,v_source_makeup,v_actual_ordinary,v_actual_cancel,
    v_actual_partial,v_actual_makeup);
  IF v_count<>8 THEN RAISE EXCEPTION 'R1D_E_C_TARGET_SET_COUNT_FAILED'; END IF;

  SELECT * INTO STRICT v_summary
  FROM public.school_get_student_monthly_settlement_summary(
    v_fixture.student_id,v_target_month);
  SELECT * INTO STRICT v_preview
  FROM public.school_get_student_monthly_settlement_preview(
    v_fixture.student_id,v_target_month);
  IF v_summary.planned_hours<>9 OR v_summary.actual_hours<>3
     OR v_summary.planned_fee_jpy<>9000 OR v_summary.actual_fee_jpy<>3000
     OR v_preview.planned_hours IS DISTINCT FROM v_summary.planned_hours
     OR v_preview.actual_hours IS DISTINCT FROM v_summary.actual_hours THEN
    RAISE EXCEPTION 'R1D_E_C_SUMMARY_STATUS_OR_AMOUNT_SEMANTICS_FAILED';
  END IF;
  SELECT * INTO STRICT v_summary
  FROM public.school_get_student_monthly_settlement_summary(
    v_fixture.student_id,'2033-01');
  IF v_summary.planned_hours<>0 OR v_summary.actual_hours<>0
     OR v_summary.planned_fee_jpy<>0 OR v_summary.actual_fee_jpy<>0 THEN
    RAISE EXCEPTION 'R1D_E_C_CROSS_MONTH_EXCLUSION_FAILED';
  END IF;
  INSERT INTO r1d_e_c_test_results VALUES
    ('summary_preview_authoritative_month',true,'8 lessons in authority month'),
    ('summary_status_semantics',true,'ordinary/partial billable; cancel/makeup excluded'),
    ('summary_actual_date_month_excluded',true,'no fallback to actual date/month');

  IF EXISTS (SELECT 1
    FROM public.school_get_student_monthly_settlement_wage_blockers(
      v_target_month,v_fixture.student_id)) THEN
    RAISE EXCEPTION 'R1D_E_C_UNEXPECTED_SYNTHETIC_WAGE_BLOCKER';
  END IF;
  PERFORM public.school_assert_student_monthly_settlement_no_wage_blocker(
    v_fixture.student_id,v_target_month,'codex-test R1D-E-C no blocker');
  IF NOT EXISTS (SELECT 1
    FROM public.school_get_student_monthly_settlement_wage_blockers(
      public.school_resolve_r1d_e_c_lesson_student_month(v_wage_actual.id),
      v_wage_actual.student_id)) THEN
    RAISE EXCEPTION 'R1D_E_C_EXISTING_WAGE_BLOCKER_MISSING';
  END IF;
  BEGIN
    PERFORM public.school_assert_student_monthly_settlement_no_wage_blocker(
      v_wage_actual.student_id,
      public.school_resolve_r1d_e_c_lesson_student_month(v_wage_actual.id),
      'codex-test R1D-E-C blocker');
    RAISE EXCEPTION 'R1D_E_C_EXPECTED_WAGE_BLOCKER_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_C_EXPECTED_%' THEN RAISE; END IF;
  END;
  INSERT INTO r1d_e_c_test_results VALUES
    ('blocker_none_passes',true,'no synthetic wage detail'),
    ('blocker_existing_rejects',true,'teacher wage facts preserved');

  SELECT * INTO STRICT v_locked
  FROM public.school_lock_student_monthly_settlement(
    v_fixture.student_id,v_target_month,'codex-test R1D-E-C lock');
  v_settlement_id:=v_locked.settlement_id;
  IF v_locked.settlement_status<>'locked'
     OR v_locked.planned_lesson_fee_jpy<>9000
     OR v_locked.actual_lesson_fee_jpy<>3000 THEN
    RAISE EXCEPTION 'R1D_E_C_LOCK_SNAPSHOT_FAILED';
  END IF;
  BEGIN
    PERFORM * FROM public.school_lock_student_monthly_settlement(
      v_fixture.student_id,v_target_month,'codex-test duplicate');
    RAISE EXCEPTION 'R1D_E_C_EXPECTED_DUPLICATE_LOCK_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_C_EXPECTED_%' THEN RAISE; END IF;
  END;
  SELECT * INTO STRICT v_unlocked
  FROM public.school_unlock_student_monthly_settlement(
    v_settlement_id,'codex-test R1D-E-C unlock');
  IF v_unlocked.settlement_status<>'unlocked' THEN
    RAISE EXCEPTION 'R1D_E_C_UNLOCK_FAILED';
  END IF;
  SELECT * INTO STRICT v_relocked
  FROM public.school_relock_student_monthly_settlement(
    v_settlement_id,'codex-test R1D-E-C relock');
  IF v_relocked.settlement_status<>'locked'
     OR v_relocked.planned_lesson_fee_jpy<>v_locked.planned_lesson_fee_jpy
     OR v_relocked.actual_lesson_fee_jpy<>v_locked.actual_lesson_fee_jpy THEN
    RAISE EXCEPTION 'R1D_E_C_RELOCK_AUTHORITY_FAILED';
  END IF;
  INSERT INTO r1d_e_c_test_results VALUES
    ('lock_authoritative_snapshot',true,'snapshot matches authoritative preview'),
    ('lock_duplicate_rejected',true,'existing idempotency/rejection preserved'),
    ('unlock_nonlegacy_allowed',true,'synthetic unlocked'),
    ('relock_authoritative_snapshot',true,'same authoritative amounts');

  BEGIN
    PERFORM * FROM public.school_unlock_student_monthly_settlement(
      v_legacy_snapshot.id,'codex-test must reject legacy snapshot');
    RAISE EXCEPTION 'R1D_E_C_EXPECTED_LEGACY_SNAPSHOT_UNLOCK_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE' THEN RAISE; END IF;
  END;
  INSERT INTO r1d_e_c_test_results VALUES
    ('legacy_snapshot_unlock_rejected',true,'fixed 15 explicitly immutable');

  SELECT * INTO STRICT v_preview
  FROM public.school_set_student_monthly_settlement_draft_adjustment(
    v_fixture.student_id,
    public.school_resolve_r1d_e_c_lesson_student_month(v_source_draft),
    1.235,'manual','codex-test R1D-E-C reason','codex-test note');
  IF v_preview.adjustment_amount_cny<>1.24
     OR v_preview.draft_status<>'active' THEN
    RAISE EXCEPTION 'R1D_E_C_DRAFT_ROUNDING_OR_AUTHORITY_FAILED';
  END IF;
  INSERT INTO r1d_e_c_test_results VALUES
    ('draft_adjustment_authoritative_month',true,'rounding and preview preserved');

  -- Partial canonical planned bundle: bypass only invariant triggers/constraints
  -- inside a subtransaction, assert resolver and lock fail closed, then restore.
  BEGIN
    ALTER TABLE public.school_lesson_records
      DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    ALTER TABLE public.school_lesson_records
      DROP CONSTRAINT school_lesson_records_billing_pair_complete_chk;
    ALTER TABLE public.school_lesson_records
      DROP CONSTRAINT school_lesson_records_billing_source_metadata_chk;
    UPDATE public.school_lesson_records SET billing_month=NULL
    WHERE id=v_source_draft;
    ALTER TABLE public.school_lesson_records
      ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    BEGIN
      PERFORM public.school_resolve_r1d_e_c_lesson_student_month(v_source_draft);
      RAISE EXCEPTION 'R1D_E_C_EXPECTED_PARTIAL_BUNDLE_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM<>'R1D_E_C_PARTIAL_PLANNED_ATTRIBUTION_REJECTED' THEN RAISE; END IF;
    END;
    BEGIN
      PERFORM * FROM public.school_lock_student_monthly_settlement(
        v_fixture.student_id,'2032-11','codex-test invalid must reject');
      RAISE EXCEPTION 'R1D_E_C_EXPECTED_INVALID_LOCK_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM<>'R1D_E_C_PARTIAL_PLANNED_ATTRIBUTION_REJECTED' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'R1D_E_C_PARTIAL_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R1D_E_C_PARTIAL_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_partial_planned_rejected',true,'fail closed'),
    ('lock_invalid_classification_rejected',true,'same resolver boundary');

  BEGIN
    ALTER TABLE public.school_lesson_records
      DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    UPDATE public.school_lesson_records SET billing_month=NULL,
      billing_week_start_date=NULL,student_settlement_month=NULL,
      billing_month_source=NULL,billing_month_decided_at=NULL
    WHERE id=v_source_draft;
    ALTER TABLE public.school_lesson_records
      ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    BEGIN
      PERFORM public.school_resolve_r1d_e_c_lesson_student_month(v_source_draft);
      RAISE EXCEPTION 'R1D_E_C_EXPECTED_UNEVIDENCED_NULL_PLANNED_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM<>'R1D_E_C_LEGACY_PLANNED_EVIDENCE_MISMATCH' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'R1D_E_C_NULL_PLANNED_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R1D_E_C_NULL_PLANNED_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_unevidenced_null_planned_rejected',true,'fail closed');

  BEGIN
    ALTER TABLE public.school_lesson_records
      DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    UPDATE public.school_lesson_records SET year_month='2099-01'
    WHERE id=v_legacy_planned.id;
    ALTER TABLE public.school_lesson_records
      ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    BEGIN
      PERFORM public.school_resolve_r1d_e_c_lesson_student_month(
        v_legacy_planned.id);
      RAISE EXCEPTION 'R1D_E_C_EXPECTED_LEGACY_PLANNED_DRIFT_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM<>'R1D_E_C_LEGACY_PLANNED_EVIDENCE_MISMATCH' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'R1D_E_C_LEGACY_PLANNED_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R1D_E_C_LEGACY_PLANNED_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_legacy_planned_drift_rejected',true,'identity evidence enforced');

  BEGIN
    ALTER TABLE public.school_lesson_records
      DISABLE TRIGGER trg_school_lesson_r1d_e_b2_actual_attribution;
    UPDATE public.school_lesson_records SET student_settlement_month='2099-01',
      year_month='2099-01' WHERE id=v_actual_ordinary;
    ALTER TABLE public.school_lesson_records
      ENABLE TRIGGER trg_school_lesson_r1d_e_b2_actual_attribution;
    BEGIN
      PERFORM public.school_resolve_r1d_e_c_lesson_student_month(
        v_actual_ordinary);
      RAISE EXCEPTION 'R1D_E_C_EXPECTED_CANONICAL_ACTUAL_DRIFT_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM<>'R1D_E_C_CANONICAL_ACTUAL_SOURCE_MONTH_MISMATCH' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'R1D_E_C_CANONICAL_ACTUAL_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R1D_E_C_CANONICAL_ACTUAL_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_canonical_actual_drift_rejected',true,'source month enforced');

  BEGIN
    ALTER TABLE public.school_lesson_records
      DISABLE TRIGGER trg_school_lesson_r1d_e_b2_actual_attribution;
    UPDATE public.school_lesson_records SET student_settlement_month=NULL
    WHERE id=v_actual_ordinary;
    ALTER TABLE public.school_lesson_records
      ENABLE TRIGGER trg_school_lesson_r1d_e_b2_actual_attribution;
    BEGIN
      PERFORM public.school_resolve_r1d_e_c_lesson_student_month(
        v_actual_ordinary);
      RAISE EXCEPTION 'R1D_E_C_EXPECTED_NULL_CANONICAL_ACTUAL_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM<>'R1D_E_C_CANONICAL_ACTUAL_ATTRIBUTION_INVALID' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'R1D_E_C_NULL_ACTUAL_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R1D_E_C_NULL_ACTUAL_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_unevidenced_null_actual_rejected',true,'fail closed');

  BEGIN
    ALTER TABLE public.school_lesson_records
      DISABLE TRIGGER trg_school_lesson_r1d_e_b2_actual_attribution;
    UPDATE public.school_lesson_records SET note=coalesce(note,'')||' drift'
    WHERE id=v_legacy_actual.id;
    ALTER TABLE public.school_lesson_records
      ENABLE TRIGGER trg_school_lesson_r1d_e_b2_actual_attribution;
    BEGIN
      PERFORM public.school_resolve_r1d_e_c_lesson_student_month(
        v_legacy_actual.id);
      RAISE EXCEPTION 'R1D_E_C_EXPECTED_LEGACY_ACTUAL_DRIFT_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM<>'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R1D_E_C_LEGACY_ACTUAL_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_legacy_actual_drift_rejected',true,'identity/full-row enforced');

  BEGIN
    UPDATE public.school_lesson_records SET app_type='cash'
    WHERE id=v_source_draft;
    BEGIN
      PERFORM public.school_resolve_r1d_e_c_lesson_student_month(v_source_draft);
      RAISE EXCEPTION 'R1D_E_C_EXPECTED_APP_TYPE_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM<>'R1D_E_C_LESSON_BASE_IDENTITY_INVALID' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'R1D_E_C_APP_TYPE_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R1D_E_C_APP_TYPE_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;
  INSERT INTO r1d_e_c_test_results VALUES
    ('resolver_illegal_app_type_rejected',true,'fail closed');

  IF md5(to_jsonb((SELECT lesson FROM public.school_lesson_records lesson
                    WHERE lesson.id=v_legacy_planned.id))::text)<>
       v_legacy_planned_hash
     OR md5(to_jsonb((SELECT actual FROM public.school_lesson_records actual
                      WHERE actual.id=v_legacy_actual.id))::text)<>
       v_legacy_actual_hash THEN
    RAISE EXCEPTION 'R1D_E_C_REAL_FIXTURE_NOT_RESTORED_IN_TRANSACTION';
  END IF;

  RAISE NOTICE 'R1D_E_C_TEST_SOURCE_IDS=%',ARRAY[
    v_source_ordinary,v_source_cancel,v_source_partial,v_source_makeup,
    v_source_draft];
  RAISE NOTICE 'R1D_E_C_TEST_ACTUAL_IDS=%',ARRAY[
    v_actual_ordinary,v_actual_cancel,v_actual_partial,v_actual_makeup];
  RAISE NOTICE 'R1D_E_C_TEST_SETTLEMENT_ID=%',v_settlement_id;
END
$tests$;

DO $result_guard$
DECLARE
  v_count bigint;
BEGIN
  SELECT count(*) INTO v_count FROM r1d_e_c_test_results WHERE passed;
  IF v_count<>23 OR EXISTS (
    SELECT 1 FROM r1d_e_c_test_results WHERE NOT passed) THEN
    RAISE EXCEPTION 'R1D_E_C_TEST_MATRIX_INCOMPLETE: %',v_count;
  END IF;
END
$result_guard$;

TABLE r1d_e_c_test_results;

\if :{?r1d_e_c_tests_existing_tx}
  \echo 'R1D_E_C_TESTS_COMPLETE_CALLER_MUST_ROLLBACK'
\else
  ROLLBACK;
\endif
