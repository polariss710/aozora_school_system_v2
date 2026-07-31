-- School V2 R2-F-E1 read-only postdeploy acceptance.
-- No business DML; all checks run in READ ONLY and end with ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $acceptance$
DECLARE
  v_definition text;
  v_sun record;
  v_zhang_candidate record;
  v_error text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
  ) INTO STRICT v_definition;
  IF position('R2-F-E1: the original charged planned row is the immutable credit source.' IN v_definition)=0
     OR position($old$
  IF public.school_get_lesson_credit_remaining_hours(v_planned.id)<=0 THEN
    UPDATE public.school_lesson_records SET status='makeup_completed'
    WHERE id=v_planned.id;
  END IF;
$old$ IN v_definition)>0 THEN
    RAISE EXCEPTION 'R2_F_E1_POSTDEPLOY_WRITER_FAILED';
  END IF;
  IF position('R2-F-E1 structured legacy contract' IN pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     ))=0
     OR position('to_jsonb(v_lesson)' IN pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     ))>0 THEN
    RAISE EXCEPTION 'R2_F_E1_POSTDEPLOY_STRUCTURED_RESOLVER_FAILED';
  END IF;

  IF NOT has_function_privilege('anon',
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)',
       'EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)',
       'EXECUTE')
     OR NOT has_function_privilege('service_role',
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)',
       'EXECUTE') THEN
    RAISE EXCEPTION 'R2_F_E1_POSTDEPLOY_ACL_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3
     OR EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_E1_POSTDEPLOY_R0_OR_CONTEXT_FAILED';
  END IF;

  IF (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_lesson_records x)
       IS DISTINCT FROM jsonb_build_array(658,'b54ba3d4c8608a597c8164673840266f')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_monthly_settlements x)
       IS DISTINCT FROM jsonb_build_array(17,'fe0b47c5534d0afd009ae7e70b370f70')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bills x)
       IS DISTINCT FROM jsonb_build_array(9,'0f0323b79e7ff1c47ff6b90c75477a2d')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_income_records x)
       IS DISTINCT FROM jsonb_build_array(42,'2a4897b752f272b1f192045418b4940c')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bill_lessons x)
       IS DISTINCT FROM jsonb_build_array(121,'285172fedeb923c67ea9a179480d8692')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_billing_identities x)
       IS DISTINCT FROM jsonb_build_array(7,'4d91a5a1074f90389822fc367a7e5467')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_teacher_wage_lock_details x)
       IS DISTINCT FROM jsonb_build_array(556,'6204dc666b3b8e0f64fac901ecf0686a')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_account_transactions x)
       IS DISTINCT FROM jsonb_build_array(185,'8f4f6c4365035f6c36bac59ba986b28b')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_personal_cash_income_linkage_events x)
       IS DISTINCT FROM jsonb_build_array(35,'6e76a4dc2fc2954b28b7ad0a8d203ba0') THEN
    RAISE EXCEPTION 'R2_F_E1_POSTDEPLOY_BUSINESS_FINGERPRINT_FAILED';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM public.school_lesson_records l
       WHERE l.id='1a370095-dd14-444f-8ffb-778e92e03c88'
         AND l.status='pending_makeup'
         AND l.duration_hours=2
         AND public.school_get_lesson_credit_remaining_hours(l.id)=2
         AND NOT EXISTS (SELECT 1 FROM public.school_lesson_records a
                         WHERE a.lesson_type='actual'
                           AND a.planned_lesson_id=l.id)
     ) THEN
    RAISE EXCEPTION 'R2_F_E1_POSTDEPLOY_REAL_PENG_EVIDENCE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records l
      WHERE l.app_type='school' AND l.lesson_type='actual'
        AND l.status IN ('completed','makeup_completed')
        AND l.lesson_date>(statement_timestamp() AT TIME ZONE 'Asia/Tokyo')::date)<>3 THEN
    RAISE EXCEPTION 'R2_F_E1_POSTDEPLOY_FUTURE_ACTUAL_EVIDENCE_CHANGED';
  END IF;

  SELECT p.* INTO STRICT v_sun
  FROM public.school_get_student_tuition_validation_preview_details(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.042
  ) p;
  IF v_sun.candidate_count<>22 OR v_sun.total_lesson_count<>24
     OR v_sun.total_duration_hours<>44
     OR v_sun.total_base_lesson_fee_jpy<>374000
     OR v_sun.total_aircon_fee_jpy<>0
     OR v_sun.previous_carryover_cny<>0 THEN
    RAISE EXCEPTION 'R2_F_E1_POSTDEPLOY_TUITION_PREVIEW_REGRESSION';
  END IF;

  -- The business owner explicitly unlocked Zhang's 2026-07 settlement before
  -- the authorized actual edit. The resolver mismatch must be gone, but the
  -- atomic preview must still fail closed until the owner relocks that month.
  BEGIN
    PERFORM *
    FROM public.school_get_student_tuition_validation_preview_details(
      '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.043
    );
    RAISE EXCEPTION 'R2_F_E1_EXPECTED_PREVIOUS_SETTLEMENT_REQUIRED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED' THEN RAISE; END IF;
  END;
  IF NOT EXISTS (
       SELECT 1 FROM public.school_student_monthly_settlements settlement
       WHERE settlement.id='b699209d-2f61-4cfa-959b-45686e2fe19b'
         AND settlement.student_id='7aef8061-7037-4881-a847-a2cdb031c0f4'
         AND settlement.year_month='2026-07'
         AND settlement.settlement_status='unlocked'
         AND settlement.preset_exchange_rate=0.043
         AND settlement.carryover_amount_cny=107.50
     ) THEN
    RAISE EXCEPTION 'R2_F_E1_ZHANG_UNLOCKED_SETTLEMENT_EVIDENCE_FAILED';
  END IF;
  SELECT count(*) AS candidate_count,
    coalesce(sum(candidate.lesson_count),0) AS lesson_count,
    coalesce(sum(candidate.duration_hours),0) AS duration_hours,
    coalesce(sum(candidate.lesson_fee),0) AS base_fee
  INTO STRICT v_zhang_candidate
  FROM public.school_list_student_tuition_candidates(
    '7aef8061-7037-4881-a847-a2cdb031c0f4',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',false
  ) candidate;
  IF v_zhang_candidate.candidate_count<>30
     OR v_zhang_candidate.lesson_count<>35
     OR v_zhang_candidate.duration_hours<>65
     OR v_zhang_candidate.base_fee<>650000 THEN
    RAISE EXCEPTION 'R2_F_E1_ZHANG_CANDIDATE_REGRESSION';
  END IF;
END
$acceptance$;

SELECT
  md5(pg_get_functiondef(
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
  )) AS makeup_credit_writer_md5,
  md5(pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
  )) AS legacy_actual_resolver_md5,
  3 AS retained_unlocked_future_actual_anomalies,
  true AS real_peng_attempt_left_no_actual,
  true AS business_fingerprints_unchanged,
  true AS sun_preview_and_zhang_candidates_unchanged,
  true AS zhang_unlocked_settlement_fails_closed,
  true AS r0_unchanged;

ROLLBACK;
\echo 'R2_F_E1_POSTDEPLOY_READ_ONLY_ROLLED_BACK'
