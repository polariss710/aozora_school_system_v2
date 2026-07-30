\set ON_ERROR_STOP on
\pset pager off

-- Rollback-only normal RPC matrix for S1-B approved legacy source compatibility.
-- Synthetic legacy fixtures are created with narrowly disabled immutable/F1 row
-- triggers, immediately re-enabled before the writer call, and fully rolled back.

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '300s';

CREATE TEMPORARY TABLE s1_b_legacy_compat_test_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_actual public.school_lesson_records%ROWTYPE;
  v_legacy_before public.school_lesson_records%ROWTYPE;
  v_other_entity_id uuid;
  v_source_canonical uuid;
  v_source_partial uuid;
  v_source_locked uuid;
  v_source_legacy uuid := 'd4100000-0000-4000-8000-000000000001'::uuid;
  v_source_unapproved uuid := 'd4100000-0000-4000-8000-000000000002'::uuid;
  v_source_other_entity uuid := 'd4100000-0000-4000-8000-000000000003'::uuid;
  v_actual_canonical uuid;
  v_actual_legacy uuid;
  v_legacy_before_md5 text;
  v_bill_before text;
  v_income_before text;
  v_historical_overage_before bigint;
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) <> '149634304f5407de81f23717b913be7e' THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_TEST_WRITER_DRIFT';
  END IF;

  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type = 'school'
    AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned'
    AND lesson.voided_at IS NULL
    AND lesson.student_id IS NOT NULL
    AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id = public.school_primary_business_entity_id()
    AND num_nonnulls(
      lesson.billing_month,
      lesson.billing_week_start_date,
      lesson.student_settlement_month,
      lesson.billing_month_source,
      lesson.billing_month_decided_at
    ) = 5
    AND EXISTS (
      SELECT 1 FROM public.school_students s
      WHERE s.id = lesson.student_id
        AND s.app_type = 'school'
        AND coalesce(s.status, 'active') NOT IN ('inactive', 'graduated')
        AND (s.business_entity_id IS NULL
             OR s.business_entity_id = lesson.business_entity_id)
    )
    AND EXISTS (
      SELECT 1 FROM public.school_teachers t
      WHERE t.id = lesson.teacher_id
        AND t.app_type = 'school'
        AND coalesce(t.status, 'employed') NOT IN ('inactive', 'retired')
    )
    AND EXISTS (
      SELECT 1 FROM public.school_subjects s
      WHERE s.id = lesson.subject_id
        AND coalesce(s.is_active, true)
    )
  ORDER BY lesson.id
  LIMIT 1;

  SELECT b.id INTO STRICT v_other_entity_id
  FROM public.school_business_entities b
  WHERE b.id <> public.school_primary_business_entity_id()
    AND coalesce(b.is_active, true)
  ORDER BY b.id
  LIMIT 1;

  SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
  INTO v_bill_before
  FROM public.school_student_tuition_bills x;

  SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
  INTO v_income_before
  FROM public.school_income_records x;

  SELECT count(*) INTO v_historical_overage_before
  FROM public.school_lesson_records l
  WHERE l.lesson_type = 'actual'
    AND num_nonnulls(
      l.student_duration_overage_minutes,
      l.student_duration_overage_fee_jpy,
      l.student_duration_overage_policy_version,
      l.student_duration_overage_source,
      l.student_duration_overage_decided_at
    ) > 0;

  SELECT lesson_id INTO STRICT v_source_canonical
  FROM public.school_create_planned_lesson_record(
    DATE '2036-01-07', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '15:00', '17:00', 0, 10000, NULL, 'planned', 1,
    'codex-test S1-B legacy compat canonical source',
    'codex-test s1-b-legacy-compat'
  );

  SELECT lesson_id INTO STRICT v_source_partial
  FROM public.school_create_planned_lesson_record(
    DATE '2036-02-04', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '15:00', '17:00', 0, 10000, NULL, 'planned', 1,
    'codex-test S1-B legacy compat partial source',
    'codex-test s1-b-legacy-compat'
  );

  SELECT lesson_id INTO STRICT v_source_locked
  FROM public.school_create_planned_lesson_record(
    DATE '2036-10-07', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '15:00', '17:00', 0, 10000, NULL, 'planned', 1,
    'codex-test S1-B legacy compat locked source',
    'codex-test s1-b-legacy-compat'
  );

  PERFORM * FROM public.school_lock_student_monthly_settlement(
    v_fixture.student_id,
    '2036-10',
    'codex-test s1-b-legacy-compat locked source'
  );

  ALTER TABLE public.school_lesson_records
    DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;

  INSERT INTO public.school_lesson_records (
    id, lesson_type, lesson_date, year_month, student_id, teacher_id,
    subject_id, business_entity_id, start_time, end_time, duration_hours,
    lesson_content, status, is_billable, note, app_type, unit_price,
    lesson_fee, lesson_count, lesson_delivery_mode, lesson_venue
  ) VALUES
  (
    v_source_legacy, 'planned', DATE '2036-07-01', '2036-07',
    v_fixture.student_id, v_fixture.teacher_id, v_fixture.subject_id,
    v_fixture.business_entity_id, '15:00', '17:00', 2,
    'codex-test S1-B legacy compat approved legacy source', 'planned', true,
    'codex-test s1-b-legacy-compat', 'school', 10000, 20000, 1,
    'online', NULL
  ),
  (
    v_source_unapproved, 'planned', DATE '2036-08-05', '2036-08',
    v_fixture.student_id, v_fixture.teacher_id, v_fixture.subject_id,
    v_fixture.business_entity_id, '15:00', '17:00', 2,
    'codex-test S1-B legacy compat unapproved legacy source', 'planned', true,
    'codex-test s1-b-legacy-compat', 'school', 10000, 20000, 1,
    'online', NULL
  ),
  (
    v_source_other_entity, 'planned', DATE '2036-09-02', '2036-09',
    v_fixture.student_id, v_fixture.teacher_id, v_fixture.subject_id,
    v_other_entity_id, '15:00', '17:00', 2,
    'codex-test S1-B legacy compat other entity source', 'planned', true,
    'codex-test s1-b-legacy-compat', 'school', 10000, 20000, 1,
    'online', NULL
  );

  ALTER TABLE public.school_lesson_records
    ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;

  ALTER TABLE public.school_legacy_planned_settlement_evidence
    DISABLE TRIGGER school_legacy_planned_evidence_row_immutable;

  INSERT INTO public.school_legacy_planned_settlement_evidence (
    planned_lesson_id,
    student_id_snapshot,
    business_entity_id_snapshot,
    legacy_student_settlement_month,
    lesson_identity_md5,
    approved_manifest,
    evidence_source,
    evidence_version
  )
  SELECT
    p.id,
    p.student_id,
    p.business_entity_id,
    p.year_month,
    md5(concat_ws('|',
      p.id::text,
      coalesce(p.student_id::text, '<NULL>'),
      coalesce(p.business_entity_id::text, '<NULL>'),
      coalesce(p.year_month, '<NULL>'),
      p.lesson_type,
      p.app_type
    )),
    true,
    'r1d_e_b1_fixed_legacy_279',
    'legacy_settlement_evidence_v1'
  FROM public.school_lesson_records p
  WHERE p.id = v_source_legacy;

  ALTER TABLE public.school_legacy_planned_settlement_evidence
    ENABLE TRIGGER school_legacy_planned_evidence_row_immutable;

  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE (t.tgrelid = 'public.school_lesson_records'::regclass
           AND t.tgname = 'trg_school_lesson_r1d_f1_planned_attribution'
           AND t.tgenabled <> 'O')
       OR (t.tgrelid = 'public.school_legacy_planned_settlement_evidence'::regclass
           AND t.tgname = 'school_legacy_planned_evidence_row_immutable'
           AND t.tgenabled <> 'O')
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_FIXTURE_TRIGGER_NOT_REENABLED';
  END IF;

  IF public.school_resolve_r1d_e_b2_actual_student_month(v_source_legacy)
       <> '2036-07' THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_FIXTURE_RESOLVER_FAILED';
  END IF;

  SELECT p.*
  INTO STRICT v_legacy_before
  FROM public.school_lesson_records p
  WHERE p.id = v_source_legacy;
  v_legacy_before_md5 := md5(to_jsonb(v_legacy_before)::text);

  SELECT lesson_id INTO STRICT v_actual_canonical
  FROM public.school_create_actual_lesson_from_planned(
    v_source_canonical, DATE '2036-03-07', '15:00', '17:15', 2.25,
    10000, NULL, 1,
    'codex-test S1-B legacy compat canonical actual',
    'codex-test s1-b-legacy-compat'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_lesson_records a
    JOIN public.school_lesson_records p ON p.id = a.planned_lesson_id
    WHERE a.id = v_actual_canonical
      AND a.status = 'completed'
      AND a.student_settlement_month = p.student_settlement_month
      AND a.year_month = p.student_settlement_month
      AND a.duration_hours = 2.25
      AND a.student_duration_overage_minutes = 15
      AND a.student_duration_overage_fee_jpy = 2500
      AND a.student_duration_overage_policy_version =
        'student_duration_overage_v1'
      AND a.student_duration_overage_source = 'ordinary_actual_rpc'
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_CANONICAL_BRANCH_FAILED';
  END IF;

  SELECT lesson_id INTO STRICT v_actual_legacy
  FROM public.school_create_actual_lesson_from_planned(
    v_source_legacy, DATE '2036-09-12', '15:00', '17:15', 2.25,
    10000, NULL, 1,
    'codex-test S1-B legacy compat approved legacy actual',
    'codex-test s1-b-legacy-compat'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_lesson_records a
    WHERE a.id = v_actual_legacy
      AND a.status = 'completed'
      AND a.is_billable IS TRUE
      AND a.business_entity_id = public.school_primary_business_entity_id()
      AND a.duration_hours = 2.25
      AND a.lesson_fee = 22500
      AND a.student_settlement_month = '2036-07'
      AND a.year_month = '2036-07'
      AND a.teacher_settlement_month = '2036-09'
      AND a.student_duration_overage_minutes = 15
      AND a.student_duration_overage_fee_jpy = 2500
      AND a.student_duration_overage_policy_version =
        'student_duration_overage_v1'
      AND a.student_duration_overage_source = 'ordinary_actual_rpc'
      AND a.student_duration_overage_decided_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_APPROVED_LEGACY_BRANCH_FAILED';
  END IF;

  IF (SELECT md5(to_jsonb(p)::text)
      FROM public.school_lesson_records p
      WHERE p.id = v_source_legacy) <> v_legacy_before_md5
     OR EXISTS (
       SELECT 1 FROM public.school_lesson_records p
       WHERE p.id = v_source_legacy
         AND p.status = 'pending_makeup'
     ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_SOURCE_PLANNED_CHANGED';
  END IF;

  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_source_unapproved, DATE '2036-08-05', '15:00', '17:15', 2.25,
      10000, NULL, 1,
      'codex-test S1-B legacy compat unapproved actual',
      'codex-test s1-b-legacy-compat'
    );
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_EXPECTED_UNAPPROVED_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'S1_B_OVERAGE_APPROVED_LEGACY_SOURCE_REQUIRED' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_source_other_entity, DATE '2036-09-02', '15:00', '17:15', 2.25,
      10000, NULL, 1,
      'codex-test S1-B legacy compat other entity actual',
      'codex-test s1-b-legacy-compat'
    );
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_EXPECTED_ENTITY_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'S1_B_OVERAGE_PRIMARY_BUSINESS_ENTITY_REQUIRED' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    ALTER TABLE public.school_lesson_records
      DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    ALTER TABLE public.school_lesson_records
      DROP CONSTRAINT school_lesson_records_billing_pair_complete_chk;
    ALTER TABLE public.school_lesson_records
      DROP CONSTRAINT school_lesson_records_billing_source_metadata_chk;
    UPDATE public.school_lesson_records
    SET billing_month = NULL
    WHERE id = v_source_partial;
    ALTER TABLE public.school_lesson_records
      ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;

    BEGIN
      PERFORM * FROM public.school_create_actual_lesson_from_planned(
        v_source_partial, DATE '2036-02-04', '15:00', '17:15', 2.25,
        10000, NULL, 1,
        'codex-test S1-B legacy compat partial bundle actual',
        'codex-test s1-b-legacy-compat'
      );
      RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_EXPECTED_PARTIAL_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM <> 'S1_B_OVERAGE_PARTIAL_SOURCE_ATTRIBUTION_REJECTED' THEN
        RAISE;
      END IF;
    END;

    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_PARTIAL_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'S1_B_LEGACY_COMPAT_PARTIAL_SUBTX_COMPLETE' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_source_locked, DATE '2036-12-07', '15:00', '17:15', 2.25,
      10000, NULL, 1,
      'codex-test S1-B legacy compat locked actual',
      'codex-test s1-b-legacy-compat'
    );
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_EXPECTED_LOCKED_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '目标学生月度结算已锁定，不能生成 actual。' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_source_canonical, DATE '2036-03-07', '15:00', '17:15', 2.25,
      10000, NULL, 1,
      'codex-test S1-B legacy compat duplicate actual',
      'codex-test s1-b-legacy-compat'
    );
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_EXPECTED_DUPLICATE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '该预定课时已有关联 actual，不能重复生成。' THEN
      RAISE;
    END IF;
  END;

  IF (SELECT count(*)
      FROM public.school_lesson_records l
      WHERE l.lesson_type = 'actual'
        AND l.id NOT IN (v_actual_canonical, v_actual_legacy)
        AND num_nonnulls(
          l.student_duration_overage_minutes,
          l.student_duration_overage_fee_jpy,
          l.student_duration_overage_policy_version,
          l.student_duration_overage_source,
          l.student_duration_overage_decided_at
        ) > 0) <> v_historical_overage_before THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_EXISTING_ACTUAL_WAS_SCANNED';
  END IF;

  IF (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
      FROM public.school_student_tuition_bills x) <> v_bill_before
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_income_records x) <> v_income_before THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_BILL_OR_INCOME_CHANGED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure
     )) <> 'd24b82f51053b3960ce0e4839613ddc7'
     OR md5(pg_get_functiondef(
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure
     )) <> 'f9f5e0fffc2d0fcb5f917cc374c9e9ac'
     OR md5(pg_get_functiondef(
       'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure
     )) <> '523058b631837025101d558668ce10c8'
     OR md5(pg_get_functiondef(
       'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure
     )) <> '5b313cc696057a4a1f960ed8f1b50124' THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_S1_C_FUNCTION_CHANGED';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_R0_CHANGED_IN_TEST';
  END IF;

  INSERT INTO s1_b_legacy_compat_test_results VALUES
    ('canonical_overage', true,
      'complete canonical source still creates a 15-minute JPY 2500 overage'),
    ('approved_legacy_overage', true,
      'synthetic approved legacy source resolves 2036-07 and creates the same frozen bundle'),
    ('legacy_rejections', true,
      'unapproved legacy, partial attribution and non-Aozora sources fail closed'),
    ('duplicate_and_lock', true,
      'duplicate actual and locked authoritative source month are rejected'),
    ('source_and_history', true,
      'legacy planned remains unchanged, no pending_makeup is created, existing actuals are not scanned'),
    ('protected_boundaries', true,
      'S1-C functions, bill, income and R0 remain unchanged');

  RAISE NOTICE 'S1_B_LEGACY_COMPAT_TEST_SOURCE_IDS=%,%,%,%,%,%',
    v_source_canonical, v_source_legacy, v_source_unapproved,
    v_source_other_entity, v_source_partial, v_source_locked;
  RAISE NOTICE 'S1_B_LEGACY_COMPAT_TEST_ACTUAL_IDS=%,%',
    v_actual_canonical, v_actual_legacy;
END
$tests$;

SELECT test_name, passed, detail
FROM s1_b_legacy_compat_test_results
ORDER BY test_name;

ROLLBACK;

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $postrollback$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.school_lesson_records l
    WHERE l.note = 'codex-test s1-b-legacy-compat'
       OR l.lesson_content LIKE 'codex-test S1-B legacy compat%'
       OR l.id IN (
         'd4100000-0000-4000-8000-000000000001'::uuid,
         'd4100000-0000-4000-8000-000000000002'::uuid,
         'd4100000-0000-4000-8000-000000000003'::uuid
       )
  )
     OR EXISTS (
       SELECT 1
       FROM public.school_legacy_planned_settlement_evidence e
       WHERE e.planned_lesson_id IN (
         'd4100000-0000-4000-8000-000000000001'::uuid,
         'd4100000-0000-4000-8000-000000000002'::uuid,
         'd4100000-0000-4000-8000-000000000003'::uuid
       )
     )
     OR EXISTS (
       SELECT 1
       FROM public.school_student_monthly_settlements s
       WHERE s.note = 'codex-test s1-b-legacy-compat locked source'
     )
     OR EXISTS (
       SELECT 1
       FROM pg_trigger t
       WHERE (t.tgrelid = 'public.school_lesson_records'::regclass
              AND t.tgname = 'trg_school_lesson_r1d_f1_planned_attribution'
              AND t.tgenabled <> 'O')
          OR (t.tgrelid = 'public.school_legacy_planned_settlement_evidence'::regclass
              AND t.tgname = 'school_legacy_planned_evidence_row_immutable'
              AND t.tgenabled <> 'O')
     )
     OR EXISTS (
       SELECT 1
       FROM public.school_lesson_records a
       WHERE a.lesson_type = 'actual'
         AND a.planned_lesson_id =
           '20533154-0de9-49b7-bbbd-907aa2a254ee'::uuid
     )
     OR md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) <> '149634304f5407de81f23717b913be7e'
     OR (SELECT count(*)
         FROM public.school_feature_gates
         WHERE (feature_key = 'student_tuition_preview'
                AND state = 'validation_preview_only')
            OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
            OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_ROLLBACK_RESIDUE_OR_BOUNDARY_CHANGE';
  END IF;
END
$postrollback$;

SELECT true AS s1_b_legacy_compat_rollback_tests_pass,
       0 AS persisted_test_rows;

ROLLBACK;
