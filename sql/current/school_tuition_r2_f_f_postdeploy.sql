-- School V2 R2-F-F readonly postdeploy acceptance.
\set ON_ERROR_STOP on
\pset pager off
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

\echo 'R2_F_F_POSTDEPLOY_GATES'
SELECT feature_key,state,reason,release_version,evidence_hash
FROM public.school_feature_gates ORDER BY feature_key;

\echo 'R2_F_F_POSTDEPLOY_VENUES'
SELECT id,code,display_name,delivery_mode,aircon_eligible,
       effective_from,effective_to,is_active
FROM public.school_lesson_venues ORDER BY code;

\echo 'R2_F_F_POSTDEPLOY_FUNCTIONS'
SELECT p.oid::regprocedure AS signature,md5(pg_get_functiondef(p.oid)) AS md5,
       p.prosecdef,array_to_string(p.proacl,',') AS acl
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN (
 'school_r2_e_calculate_planned_aircon_fee','school_enforce_r2_e_planned_aircon',
 'school_list_student_tuition_charge_candidates',
 'school_build_student_tuition_generation_snapshot',
 'school_validate_tuition_bill_lessons_for_bill',
 'school_get_student_tuition_validation_preview_details',
 'school_generate_student_tuition_bill_atomic',
 'school_generate_student_tuition_bill_atomic_core',
 'school_generate_student_tuition_bill',
 'school_create_student_tuition_bill_income_record',
 'school_create_personal_cash_tuition_income_record'
)
ORDER BY p.oid::regprocedure::text;

\echo 'R2_F_F_POSTDEPLOY_TARGET_PREVIEWS'
WITH target(student_name,student_id,rate) AS (
  VALUES
    ('孙陈锋'::text,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,0.042::numeric),
    ('张倬闻','7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,0.043::numeric)
)
SELECT target.student_name,preview.feature_state,preview.generate_feature_state,
       preview.candidate_count,preview.total_lesson_count,
       preview.total_duration_hours,preview.total_base_lesson_fee_jpy,
       preview.total_aircon_fee_jpy,preview.total_fee_jpy,
       preview.previous_carryover_cny,preview.billing_exchange_rate,
       preview.billing_amount_cny,preview.candidate_uuid_md5,
       preview.generation_manifest_sha256
FROM target
CROSS JOIN LATERAL public.school_get_student_tuition_validation_preview_details(
  target.student_id,'2026-08',target.rate
) preview
ORDER BY target.student_name;

\echo 'R2_F_F_POSTDEPLOY_CROSS_MONTH_EXCLUSION'
SELECT lesson.id,lesson.lesson_date,lesson.lesson_type,lesson.status,
       lesson.year_month,lesson.student_settlement_month,
       EXISTS(
         SELECT 1 FROM public.school_list_student_tuition_charge_candidates(
           'b17abc58-2f64-4bad-bf20-c9643ead60bc',
           '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',false
         ) candidate WHERE candidate.planned_lesson_id=lesson.id
       ) AS august_candidate
FROM public.school_lesson_records lesson
WHERE lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'
  AND lesson.lesson_date IN (DATE '2026-08-01',DATE '2026-08-02')
ORDER BY lesson.lesson_date,lesson.lesson_type,lesson.id;

\echo 'R2_F_F_POSTDEPLOY_FINGERPRINTS'
WITH fingerprints AS (
 SELECT 'lesson' object,count(*)::integer row_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) hash FROM public.school_lesson_records t
 UNION ALL SELECT 'settlement',count(*)::integer,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) FROM public.school_student_monthly_settlements t
 UNION ALL SELECT 'bill',count(*)::integer,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) FROM public.school_student_tuition_bills t
 UNION ALL SELECT 'income',count(*)::integer,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) FROM public.school_income_records t
 UNION ALL SELECT 'identity',count(*)::integer,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) FROM public.school_student_tuition_billing_identities t
 UNION ALL SELECT 'relation',count(*)::integer,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) FROM public.school_student_tuition_bill_lessons t
 UNION ALL SELECT 'wage_detail',count(*)::integer,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) FROM public.school_teacher_wage_lock_details t
 UNION ALL SELECT 'wage_lock',count(*)::integer,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) FROM public.school_teacher_wage_locks t
 UNION ALL SELECT 'account_transaction',count(*)::integer,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) FROM public.school_account_transactions t
 UNION ALL SELECT 'cash_linkage',count(*)::integer,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) FROM public.school_personal_cash_income_linkage_events t
)
SELECT * FROM fingerprints ORDER BY object;

DO $assert$
DECLARE
  v_sun record;
  v_zhang record;
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='enabled')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_GATE_FAILED';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_venues
      WHERE (code='Regus办公室' AND aircon_eligible AND is_active)
         OR (code='Regus公共区' AND NOT aircon_eligible AND is_active))<>2 THEN
    RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_VENUE_FAILED';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     ))<>'11ef7b45932e6cd418c03c91da104fd0'
     OR md5(pg_get_functiondef(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,text,uuid,text,numeric,numeric,integer)'::regprocedure
     ))<>'533ead6b181d64aee88ec5674ae4e8b0'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))<>'e7820acbf80b3e5b1c02bc3ad9664762'
     OR md5(pg_get_functiondef(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
     ))<>'bd1e8aebbe3038ff7423a1f8868b9220'
     OR md5(pg_get_functiondef(
       'public.school_validate_tuition_bill_lessons_for_bill(uuid)'::regprocedure
     ))<>'a19303aa66034a8900fe1077f1a1adc9' THEN
    RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_FUNCTION_MD5_FAILED';
  END IF;
  IF position('R2_F_F_AIRCON_VENUE_CONTEXT_REQUIRED' IN pg_get_functiondef(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,numeric,numeric,integer)'::regprocedure
     ))=0 THEN
    RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_LEGACY_CALCULATOR_NOT_BLOCKED';
  END IF;
  IF position('R0 does not provide an enabled generation path' IN pg_get_functiondef(
       'public.school_generate_student_tuition_bill(uuid,text,text)'::regprocedure
     ))=0
     OR position('R0 does not provide an enabled generation path' IN pg_get_functiondef(
       'public.school_generate_student_tuition_bill(uuid,text,numeric,text)'::regprocedure
     ))=0
     OR position('R0 does not provide an enabled income-generation path' IN pg_get_functiondef(
       'public.school_create_student_tuition_bill_income_record(uuid,date,text)'::regprocedure
     ))=0
     OR position('R0 does not provide an enabled legacy personal-Cash tuition income path' IN pg_get_functiondef(
       'public.school_create_personal_cash_tuition_income_record(date,text,uuid,uuid,uuid,numeric,text,text,text,text,text,boolean,text,text,text)'::regprocedure
     ))=0 THEN
    RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_LEGACY_ENTRY_FAILED';
  END IF;
  IF (SELECT array_to_string(p.proacl,',') FROM pg_proc p
      WHERE p.oid='public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure)
       IS DISTINCT FROM 'postgres=X/postgres'
     OR position('authenticated=X/postgres' IN coalesce((SELECT array_to_string(p.proacl,',')
       FROM pg_proc p WHERE p.oid='public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure),''))=0 THEN
    RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_ATOMIC_ACL_FAILED';
  END IF;
  SELECT * INTO STRICT v_sun FROM public.school_get_student_tuition_validation_preview_details(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.042
  );
  SELECT * INTO STRICT v_zhang FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.043
  );
  IF v_sun.feature_state<>'enabled' OR v_sun.generate_feature_state<>'enabled'
     OR v_sun.candidate_count<>22 OR v_sun.total_lesson_count<>24
     OR v_sun.total_duration_hours<>44 OR v_sun.total_base_lesson_fee_jpy<>374000
     OR v_sun.total_aircon_fee_jpy<>660 OR v_sun.total_fee_jpy<>374660
     OR v_sun.previous_carryover_cny<>0 OR v_sun.billing_amount_cny<>15735.72
     OR v_zhang.feature_state<>'enabled' OR v_zhang.generate_feature_state<>'enabled'
     OR v_zhang.candidate_count<>30 OR v_zhang.total_lesson_count<>35
     OR v_zhang.total_duration_hours<>65 OR v_zhang.total_base_lesson_fee_jpy<>650000
     OR v_zhang.total_aircon_fee_jpy<>0 OR v_zhang.total_fee_jpy<>650000
     OR v_zhang.previous_carryover_cny<>107.50
     OR v_zhang.billing_amount_cny<>28057.50 THEN
    RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_TARGET_PREVIEW_FAILED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_list_student_tuition_charge_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',false
    ) candidate WHERE candidate.lesson_date IN (DATE '2026-08-01',DATE '2026-08-02')
  ) THEN RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_CROSS_MONTH_INCLUDED'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id='6c70c4c1-1895-453d-b9b0-591e9f004f86'
      AND lesson.aircon_fee_jpy=660 AND lesson.lesson_total_fee_jpy=17660
      AND lesson.fee_calculation_version='planned_weekend_aircon_v1'
  ) THEN RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_SUN_ROW_CHANGED'; END IF;
  IF (SELECT count(*)<>659 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'9ce7c36283cfa51f8b2a334801f646dd' FROM public.school_lesson_records t)
     OR (SELECT count(*)<>17 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'1d7328654f6488952dba20640072c3e2' FROM public.school_student_monthly_settlements t)
     OR (SELECT count(*)<>9 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'0f0323b79e7ff1c47ff6b90c75477a2d' FROM public.school_student_tuition_bills t)
     OR (SELECT count(*)<>42 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'2a4897b752f272b1f192045418b4940c' FROM public.school_income_records t)
     OR (SELECT count(*)<>7 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'4d91a5a1074f90389822fc367a7e5467' FROM public.school_student_tuition_billing_identities t)
     OR (SELECT count(*)<>121 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'285172fedeb923c67ea9a179480d8692' FROM public.school_student_tuition_bill_lessons t)
     OR (SELECT count(*)<>556 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'6204dc666b3b8e0f64fac901ecf0686a' FROM public.school_teacher_wage_lock_details t)
     OR (SELECT count(*)<>95 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'7bbe108d3ac73d4f21530793bf141bc6' FROM public.school_teacher_wage_locks t)
     OR (SELECT count(*)<>185 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'8f4f6c4365035f6c36bac59ba986b28b' FROM public.school_account_transactions t)
     OR (SELECT count(*)<>35 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'6e76a4dc2fc2954b28b7ad0a8d203ba0' FROM public.school_personal_cash_income_linkage_events t) THEN
    RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_HISTORY_DRIFT';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_F_POSTDEPLOY_WRITER_CONTEXT_RESIDUE';
  END IF;
END
$assert$;

SELECT true AS postdeploy_pass;
ROLLBACK;
\echo 'R2_F_F_POSTDEPLOY_ROLLED_BACK'
