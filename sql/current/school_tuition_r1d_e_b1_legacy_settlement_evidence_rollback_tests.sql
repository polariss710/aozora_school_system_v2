-- School V2 tuition P0 R1D-E-B1 rollback-only negative tests.
-- All fictional-UUID attempts and owner/role tests are enclosed by one ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $owner_tests$
DECLARE
  v_planned uuid;
  v_snapshot uuid;
BEGIN
  SELECT planned_lesson_id INTO v_planned
  FROM public.school_legacy_planned_settlement_evidence
  ORDER BY planned_lesson_id LIMIT 1;
  SELECT settlement_snapshot_id INTO v_snapshot
  FROM public.school_legacy_settlement_snapshot_basis_evidence
  ORDER BY settlement_snapshot_id LIMIT 1;

  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence) <> 279
     OR (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence) <> 15 THEN
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_BASELINE_FAILED';
  END IF;

  IF public.school_get_legacy_planned_student_settlement_month(
       '00000000-0000-4000-8000-00000000eb11'::uuid) IS NOT NULL
     OR public.school_is_legacy_settlement_snapshot_basis(
       '00000000-0000-4000-8000-00000000eb12'::uuid) THEN
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_FAKE_HELPER_RESULT';
  END IF;

  BEGIN
    INSERT INTO public.school_legacy_planned_settlement_evidence (
      planned_lesson_id, student_id_snapshot, business_entity_id_snapshot,
      legacy_student_settlement_month, lesson_identity_md5
    ) VALUES (
      '00000000-0000-4000-8000-00000000eb11'::uuid,
      '00000000-0000-4000-8000-00000000eb21'::uuid,
      '00000000-0000-4000-8000-00000000eb31'::uuid,
      '2026-01', repeat('0', 32)
    );
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_PLANNED_INSERT_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.school_legacy_settlement_snapshot_basis_evidence (
      settlement_snapshot_id, student_id_snapshot, business_entity_id_snapshot,
      settlement_month_snapshot, settlement_status_snapshot, lesson_count,
      planned_lesson_count, actual_lesson_count, lesson_uuid_md5,
      amount_basis_md5, settlement_structure_md5
    ) VALUES (
      '00000000-0000-4000-8000-00000000eb12'::uuid,
      '00000000-0000-4000-8000-00000000eb22'::uuid,
      '00000000-0000-4000-8000-00000000eb32'::uuid,
      '2026-01', 'locked', 0, 0, 0,
      repeat('0', 32), repeat('1', 32), repeat('2', 32)
    );
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_SNAPSHOT_INSERT_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE public.school_legacy_planned_settlement_evidence
    SET recorded_at = recorded_at WHERE planned_lesson_id = v_planned;
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_PLANNED_UPDATE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE public.school_legacy_settlement_snapshot_basis_evidence
    SET recorded_at = recorded_at WHERE settlement_snapshot_id = v_snapshot;
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_SNAPSHOT_UPDATE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    DELETE FROM public.school_legacy_planned_settlement_evidence
    WHERE planned_lesson_id = v_planned;
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_PLANNED_DELETE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    DELETE FROM public.school_legacy_settlement_snapshot_basis_evidence
    WHERE settlement_snapshot_id = v_snapshot;
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_SNAPSHOT_DELETE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    EXECUTE 'TRUNCATE TABLE public.school_legacy_planned_settlement_evidence';
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_PLANNED_TRUNCATE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    EXECUTE 'TRUNCATE TABLE public.school_legacy_settlement_snapshot_basis_evidence';
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_SNAPSHOT_TRUNCATE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;
END
$owner_tests$;

SET LOCAL ROLE anon;
DO $anon_tests$
BEGIN
  BEGIN
    PERFORM count(*) FROM public.school_legacy_planned_settlement_evidence;
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_ANON_SELECT_DENIAL_MISSING';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    PERFORM public.school_get_legacy_planned_student_settlement_month(
      '00000000-0000-4000-8000-00000000eb11'::uuid);
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_ANON_EXECUTE_DENIAL_MISSING';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END
$anon_tests$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $authenticated_tests$
BEGIN
  BEGIN
    PERFORM count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence;
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_AUTH_SELECT_DENIAL_MISSING';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    PERFORM public.school_is_legacy_settlement_snapshot_basis(
      '00000000-0000-4000-8000-00000000eb12'::uuid);
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_AUTH_EXECUTE_DENIAL_MISSING';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END
$authenticated_tests$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_tests$
BEGIN
  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence) <> 279
     OR (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence) <> 15
     OR public.school_is_legacy_settlement_snapshot_basis(
          '00000000-0000-4000-8000-00000000eb12'::uuid) THEN
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_SERVICE_READ_FAILED';
  END IF;

  BEGIN
    INSERT INTO public.school_legacy_planned_settlement_evidence (
      planned_lesson_id, legacy_student_settlement_month, lesson_identity_md5
    ) VALUES (
      '00000000-0000-4000-8000-00000000eb11'::uuid,
      '2026-01', repeat('0', 32)
    );
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_EXPECTED_SERVICE_INSERT_DENIAL_MISSING';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END
$service_tests$;
RESET ROLE;

DO $final_in_transaction$
BEGIN
  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence) <> 279
     OR (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence) <> 15
     OR EXISTS (SELECT 1 FROM public.school_legacy_planned_settlement_evidence
                WHERE planned_lesson_id = '00000000-0000-4000-8000-00000000eb11'::uuid)
     OR EXISTS (SELECT 1 FROM public.school_legacy_settlement_snapshot_basis_evidence
                WHERE settlement_snapshot_id = '00000000-0000-4000-8000-00000000eb12'::uuid) THEN
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_IN_TRANSACTION_RESIDUE';
  END IF;
END
$final_in_transaction$;

SELECT true AS owner_immutable_tests,
       true AS anon_authenticated_denial_tests,
       true AS service_read_only_tests,
       true AS fictional_uuid_residue_zero;

ROLLBACK;

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $postrollback$
BEGIN
  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence) <> 279
     OR (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence) <> 15
     OR EXISTS (SELECT 1 FROM public.school_legacy_planned_settlement_evidence
                WHERE planned_lesson_id = '00000000-0000-4000-8000-00000000eb11'::uuid)
     OR EXISTS (SELECT 1 FROM public.school_legacy_settlement_snapshot_basis_evidence
                WHERE settlement_snapshot_id = '00000000-0000-4000-8000-00000000eb12'::uuid)
     OR (SELECT count(*) FROM public.school_feature_gates
         WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
            OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
            OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R1D_E_B1_ROLLBACK_TEST_POSTROLLBACK_FAILED';
  END IF;
END
$postrollback$;

SELECT true AS rollback_tests_pass,
       0 AS fictional_uuid_residual_rows,
       true AS business_boundary_unchanged;

ROLLBACK;
