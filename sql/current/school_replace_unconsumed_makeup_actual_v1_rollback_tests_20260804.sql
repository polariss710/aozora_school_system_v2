-- Rollback-only test matrix for school_replace_unconsumed_makeup_actual_v1.
-- All fixture rows are codex-test scoped and this file always ends in ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL school.makeup_actual_replacement_test_scope =
  'codex-test makeup-actual-replacement-v1-20260804';

DO $tests$
DECLARE
  v_marker constant text := 'codex-test makeup-actual-replacement-v1-20260804';
  v_student constant uuid := 'a4a40000-0000-4000-8000-000000000001';
  v_claim_student constant uuid := 'a4a40000-0000-4000-8000-000000000002';
  v_teacher constant uuid := 'a4a40000-0000-4000-8000-000000000003';
  v_subject constant uuid := 'a4a40000-0000-4000-8000-000000000004';
  v_entity constant uuid := '2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_source public.school_lesson_records%ROWTYPE;
  v_original public.school_lesson_records%ROWTYPE;
  v_wrong public.school_lesson_records%ROWTYPE;
  v_new public.school_lesson_records%ROWTYPE;
  v_result record;
  v_source_before jsonb;
  v_original_before jsonb;
  v_wrong_before jsonb;
  v_settlement_id uuid;
  v_error text;
  v_open_count integer;
BEGIN
  INSERT INTO public.school_subjects(id,name,category,note)
  VALUES (v_subject,'codex-test EJU日语','测试',v_marker);
  INSERT INTO public.school_teachers(
    id,name,status,app_type,default_subject_id,default_business_entity_id,note
  ) VALUES (
    v_teacher,'codex-test 王亚楠','active','school',v_subject,v_entity,v_marker
  );
  INSERT INTO public.school_students(id,name,status,app_type,business_entity_id,note)
  VALUES
    (v_student,'codex-test 陈红卓','active','school',v_entity,v_marker),
    (v_claim_student,'codex-test claim student','active','school',v_entity,v_marker);

  SELECT created.* INTO STRICT v_source
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2026-07-20',v_student,v_teacher,v_subject,v_entity,
    '13:00','15:00',2,8500,NULL,'planned',1,
    'codex-test EJU日语',v_marker,'online','codex-test online',0
  ) created;
  SELECT created.* INTO STRICT v_original
  FROM public.school_create_partial_completed_actual_from_planned(
    v_source.id,DATE '2026-07-20','20:00','21:00',1,
    'codex-test original completed actual',v_marker
  ) created;
  SELECT p.* INTO STRICT v_source
  FROM public.school_lesson_records p WHERE p.id=v_source.id;
  SELECT count(*) INTO v_open_count
  FROM public.school_list_open_lesson_credit_sources('2026-07','2026-07','2026-08') s
  WHERE s.id=v_source.id AND s.remaining_hours=1;
  IF v_open_count<>1 THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_TEST_CROSS_MONTH_READER_FAILED';
  END IF;

  SELECT created.* INTO STRICT v_wrong
  FROM public.school_create_lesson_credit_makeup_actual(
    v_source.id,DATE '2026-07-31',v_teacher,v_subject,
    '13:00','14:00',1,'codex-test EJU日语',v_marker,1,
    'online','codex-test online'
  ) created;
  v_source_before := to_jsonb(v_source);
  v_original_before := to_jsonb(v_original);
  v_wrong_before := to_jsonb(v_wrong);

  BEGIN
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,v_wrong.updated_at + interval '1 second',v_source.id,
      DATE '2026-08-02','codex-test stale','REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_STALE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_STALE_ACTUAL' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,v_wrong.updated_at,gen_random_uuid(),
      DATE '2026-08-02','codex-test wrong source','REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_SOURCE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_SOURCE_NOT_FOUND' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,v_wrong.updated_at,v_source.id,
      DATE '2026-08-02','codex-test confirmation','WRONG_CONFIRMATION'
    );
    RAISE EXCEPTION 'EXPECTED_CONFIRMATION_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_CONFIRMATION_MISMATCH' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,v_wrong.updated_at,v_source.id,
      DATE '2026-08-02','  ','REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_REASON_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_REASON_REQUIRED' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE public.school_lesson_records
      SET is_billable=true
    WHERE id=v_wrong.id;
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,(SELECT updated_at FROM public.school_lesson_records WHERE id=v_wrong.id),
      v_source.id,DATE '2026-08-02','codex-test billed actual',
      'REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_BILLED_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_ACTUAL_FACTS_MISMATCH' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE public.school_lesson_records
      SET status='completed'
    WHERE id=v_wrong.id;
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,(SELECT updated_at FROM public.school_lesson_records WHERE id=v_wrong.id),
      v_source.id,DATE '2026-08-02','codex-test non makeup actual',
      'REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_NON_MAKEUP_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_ACTUAL_FACTS_MISMATCH' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.school_teacher_wage_locks(
      id,settlement_month,teacher_id,business_entity_id
    ) VALUES (
      'a4a40000-0000-4000-8000-000000000101','2026-07',v_teacher,v_entity
    );
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,v_wrong.updated_at,v_source.id,
      DATE '2026-08-02','codex-test wage consumed',
      'REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_WAGE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_WAGE_CONSUMED' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.school_student_monthly_settlements(
      id,student_id,year_month,business_entity_id
    ) VALUES (
      'a4a40000-0000-4000-8000-000000000102',v_student,'2026-07',v_entity
    );
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,v_wrong.updated_at,v_source.id,
      DATE '2026-08-02','codex-test settlement consumed',
      'REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_SETTLEMENT_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_SETTLEMENT_CONSUMED' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.school_student_monthly_settlements(
      id,student_id,year_month,business_entity_id
    ) VALUES (
      'a4a40000-0000-4000-8000-000000000103',v_claim_student,'2026-06',v_entity
    ) RETURNING id INTO v_settlement_id;
    PERFORM set_config('school.p0f_claim_writer','on',true);
    INSERT INTO public.school_student_settlement_lesson_variance_claims(
      id,claim_batch_id,claim_batch_version,settlement_id,student_id,
      business_entity_id,year_month,source_type,source_planned_lesson_id,
      source_hours,source_amount_jpy,source_amount_cny,
      settlement_exchange_rate,calculation_version,line_manifest_sha256,
      claim_status,created_by
    ) VALUES (
      'a4a40000-0000-4000-8000-000000000104',
      'a4a40000-0000-4000-8000-000000000105',1,v_settlement_id,
      v_claim_student,v_entity,'2026-06','unused_planned_credit_v1',v_source.id,
      -1,-8500,-365.5,0.043,'lesson_variance_financial_netting_v1',
      repeat('a',64),'active',v_marker
    );
    PERFORM set_config('school.p0f_claim_writer','off',true);
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,v_wrong.updated_at,v_source.id,
      DATE '2026-08-02','codex-test claim consumed',
      'REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_CLAIM_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_CLAIM_CONSUMED' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.school_personal_cash_income_linkage_events(
      id,source_id,income_record_id,business_entity_id,currency,amount,
      idempotency_key,attempt_no,note,sync_status,payment_currency,
      payment_amount,confirmed_at,synced_at,cash_transaction_table
    ) VALUES (
      'a4a40000-0000-4000-8000-000000000106',
      '3a5542c5-5397-4688-999e-a08bb678f40d',
      '3a5542c5-5397-4688-999e-a08bb678f40d',v_entity,'JPY',1,
      'codex-test:makeup-actual-replacement-v1:cash-ref',999,
      v_marker||' '||v_wrong.id::text,'historical_confirmed','JPY',1,
      statement_timestamp(),statement_timestamp(),NULL
    );
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,v_wrong.updated_at,v_source.id,
      DATE '2026-08-02','codex-test cash consumed',
      'REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_CASH_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'MAKEUP_ACTUAL_REPLACEMENT_OTHER_IMMUTABLE_RELATION' THEN RAISE; END IF;
  END;

  -- Force the delegated authoritative writer to fail after the DELETE.
  -- The function call's subtransaction must restore the old actual.
  BEGIN
    UPDATE public.school_students SET status='inactive' WHERE id=v_student;
    PERFORM * FROM public.school_replace_unconsumed_makeup_actual_v1(
      v_wrong.id,v_wrong.updated_at,v_source.id,
      DATE '2026-08-02','codex-test delegated writer rollback',
      'REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
    );
    RAISE EXCEPTION 'EXPECTED_DELEGATED_WRITER_FAILURE_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'来源学生无效或业务归属不一致。' THEN RAISE; END IF;
  END;
  IF (SELECT to_jsonb(a) FROM public.school_lesson_records a WHERE a.id=v_wrong.id)
       IS DISTINCT FROM v_wrong_before THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_TEST_ATOMIC_ROLLBACK_FAILED';
  END IF;

  SELECT r.* INTO STRICT v_result
  FROM public.school_replace_unconsumed_makeup_actual_v1(
    v_wrong.id,v_wrong.updated_at,v_source.id,
    DATE '2026-08-02',
    'Correct business date for cross-month makeup actually completed on 2026-08-02.',
    'REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
  ) r;
  SELECT a.* INTO STRICT v_new
  FROM public.school_lesson_records a WHERE a.id=v_result.new_actual_id;

  IF v_result.replaced_actual_id IS DISTINCT FROM v_wrong.id
     OR v_result.source_planned_id IS DISTINCT FROM v_source.id
     OR v_result.correct_actual_date IS DISTINCT FROM DATE '2026-08-02'
     OR v_result.lesson_fee IS DISTINCT FROM 0::numeric
     OR v_result.teacher_settlement_month IS DISTINCT FROM '2026-08'
     OR v_result.remaining_makeup_hours IS DISTINCT FROM 0::numeric
     OR v_new.lesson_date IS DISTINCT FROM DATE '2026-08-02'
     OR v_new.start_time IS DISTINCT FROM '13:00'
     OR v_new.end_time IS DISTINCT FROM '14:00'
     OR v_new.duration_hours IS DISTINCT FROM 1::numeric
     OR v_new.status IS DISTINCT FROM 'makeup_completed'
     OR v_new.is_billable IS DISTINCT FROM false
     OR v_new.lesson_fee IS DISTINCT FROM 0::numeric
     OR v_new.teacher_settlement_month IS DISTINCT FROM '2026-08'
     OR v_new.planned_lesson_id IS DISTINCT FROM v_source.id
     OR EXISTS (SELECT 1 FROM public.school_lesson_records a WHERE a.id=v_wrong.id)
     OR (SELECT to_jsonb(p) FROM public.school_lesson_records p WHERE p.id=v_source.id)
          IS DISTINCT FROM v_source_before
     OR (SELECT to_jsonb(a) FROM public.school_lesson_records a WHERE a.id=v_original.id)
          IS DISTINCT FROM v_original_before THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_TEST_SUCCESS_FACTS_FAILED';
  END IF;

  IF EXISTS (
       SELECT 1
       FROM pg_proc p
       CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
       WHERE p.oid='public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)'::regprocedure
         AND a.grantee=0 AND a.privilege_type='EXECUTE'
     )
     OR has_function_privilege('anon',
       'public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)',
       'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)',
       'EXECUTE')
     OR NOT has_function_privilege('service_role',
       'public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)',
       'EXECUTE') THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_TEST_ACL_FAILED';
  END IF;

  RAISE NOTICE 'MAKEUP_REPLACEMENT_TEST_IDS source=%, original=%, wrong=%, new=%',
    v_source.id,v_original.id,v_wrong.id,v_new.id;
  RAISE NOTICE 'MAKEUP_REPLACEMENT_ROLLBACK_MATRIX=PASS';
END
$tests$;

ROLLBACK;
\echo 'MAKEUP_REPLACEMENT_ROLLBACK_TEST_ROLLED_BACK'
