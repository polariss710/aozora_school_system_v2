-- School V2 R2-F-F1 read-only postdeploy acceptance.
\set ON_ERROR_STOP on
\pset pager off
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

SELECT feature_key,state,reason,release_version
FROM public.school_feature_gates
WHERE feature_key LIKE 'student_tuition_%'
ORDER BY feature_key;

SELECT p.oid::regprocedure AS signature,md5(pg_get_functiondef(p.oid)) AS md5,
       p.prosecdef,array_to_string(p.proacl,',') AS acl
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN (
  'school_enforce_r2_e_planned_aircon',
  'school_r2_e_calculate_planned_aircon_fee',
  'school_update_lesson_record_guarded_with_venue',
  'school_list_student_tuition_charge_candidates',
  'school_build_student_tuition_generation_snapshot',
  'school_get_student_tuition_validation_preview_details'
)
ORDER BY p.oid::regprocedure::text;

SELECT lesson.id,lesson.lesson_date,lesson.start_time,lesson.end_time,
       teacher.name AS teacher_name,subject.name AS subject_name,
       lesson.status,lesson.student_id,lesson.business_entity_id,
       lesson.billing_month,lesson.billing_week_start_date,
       lesson.duration_hours,lesson.unit_price,lesson.base_lesson_fee_jpy,
       lesson.lesson_fee,lesson.lesson_delivery_mode,lesson.lesson_venue,
       lesson.lesson_venue_id,venue.code AS venue_code,
       venue.aircon_eligible,lesson.aircon_unit_price_jpy_snapshot,
       lesson.aircon_billable_hours_snapshot,lesson.aircon_fee_jpy,
       lesson.lesson_total_fee_jpy,lesson.fee_calculation_version,
       lesson.billing_month_source,lesson.import_batch_id,lesson.import_source,
       lesson.updated_at
FROM public.school_lesson_records lesson
LEFT JOIN public.school_teachers teacher ON teacher.id=lesson.teacher_id
LEFT JOIN public.school_subjects subject ON subject.id=lesson.subject_id
LEFT JOIN public.school_lesson_venues venue ON venue.id=lesson.lesson_venue_id
WHERE lesson.id IN (
  '6c70c4c1-1895-453d-b9b0-591e9f004f86',
  '89da310d-4f17-4a40-8315-659838aec59c',
  '397446aa-b195-43ff-9506-a560e7d12d93'
)
ORDER BY lesson.lesson_date,lesson.start_time,lesson.id;

WITH target(student_name,student_id,rate) AS (
  VALUES
    ('孙陈锋'::text,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,0.042::numeric),
    ('张倬闻','7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,0.043::numeric)
)
SELECT target.student_name,preview.feature_state,preview.generate_feature_state,
       preview.candidate_count,preview.total_lesson_count,
       preview.total_duration_hours,preview.total_base_lesson_fee_jpy,
       preview.total_aircon_fee_jpy,preview.total_fee_jpy,
       preview.previous_carryover_cny,preview.billing_amount_cny,
       preview.generation_manifest_sha256
FROM target
CROSS JOIN LATERAL public.school_get_student_tuition_validation_preview_details(
  target.student_id,'2026-08',target.rate
) preview
ORDER BY target.student_name;

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
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F1_GATE_FAILED';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))<>'33d0a36904ef02f595c69caafefe4f92'
     OR position('OLD.fee_calculation_version IS NULL' IN pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))>0
     OR md5(pg_get_functiondef(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,text,uuid,text,numeric,numeric,integer)'::regprocedure
     ))<>'533ead6b181d64aee88ec5674ae4e8b0'
     OR position('R2_F_F_AIRCON_VENUE_CONTEXT_REQUIRED' IN pg_get_functiondef(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,numeric,numeric,integer)'::regprocedure
     ))=0 THEN
    RAISE EXCEPTION 'R2_F_F1_FUNCTION_CONTRACT_FAILED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id='6c70c4c1-1895-453d-b9b0-591e9f004f86'
      AND lesson.fee_calculation_version='planned_weekend_aircon_v1'
      AND lesson.aircon_unit_price_jpy_snapshot=330
      AND lesson.aircon_billable_hours_snapshot=2
      AND lesson.aircon_fee_jpy=660 AND lesson.lesson_total_fee_jpy=17660
  ) OR (SELECT count(*) FROM public.school_lesson_records lesson
        WHERE lesson.id IN (
          '89da310d-4f17-4a40-8315-659838aec59c',
          '397446aa-b195-43ff-9506-a560e7d12d93'
        )
          AND lesson.fee_calculation_version='planned_weekend_venue_whole_hour_aircon_v2'
          AND lesson.lesson_delivery_mode='onsite'
          AND lesson.lesson_venue='Regus办公室'
          AND lesson.aircon_unit_price_jpy_snapshot=330
          AND lesson.aircon_billable_hours_snapshot=2
          AND lesson.aircon_fee_jpy=660
          AND lesson.base_lesson_fee_jpy=17000
          AND lesson.lesson_total_fee_jpy=17660)<>2 THEN
    RAISE EXCEPTION 'R2_F_F1_REAL_LESSON_FAILED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_student_tuition_bill_lessons relation
    WHERE relation.planned_lesson_id IN (
      '6c70c4c1-1895-453d-b9b0-591e9f004f86',
      '89da310d-4f17-4a40-8315-659838aec59c',
      '397446aa-b195-43ff-9506-a560e7d12d93'
    )
  ) THEN RAISE EXCEPTION 'R2_F_F1_REAL_LESSON_ALREADY_BILLED'; END IF;
  SELECT * INTO STRICT v_sun
  FROM public.school_get_student_tuition_validation_preview_details(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.042
  );
  SELECT * INTO STRICT v_zhang
  FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.043
  );
  IF v_sun.feature_state<>'enabled' OR v_sun.generate_feature_state<>'blocked'
     OR v_sun.candidate_count<>23 OR v_sun.total_lesson_count<>26
     OR v_sun.total_duration_hours<>46
     OR v_sun.total_base_lesson_fee_jpy<>391000
     OR v_sun.total_aircon_fee_jpy<>1980 OR v_sun.total_fee_jpy<>392980
     OR v_sun.previous_carryover_cny<>0 OR v_sun.billing_amount_cny<>16505.16
     OR v_zhang.feature_state<>'enabled' OR v_zhang.generate_feature_state<>'blocked'
     OR v_zhang.candidate_count<>30 OR v_zhang.total_lesson_count<>35
     OR v_zhang.total_duration_hours<>65
     OR v_zhang.total_base_lesson_fee_jpy<>650000
     OR v_zhang.total_aircon_fee_jpy<>0 OR v_zhang.total_fee_jpy<>650000
     OR v_zhang.previous_carryover_cny<>107.50
     OR v_zhang.billing_amount_cny<>28057.50 THEN
    RAISE EXCEPTION 'R2_F_F1_PREVIEW_FAILED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_list_student_tuition_charge_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',false
    ) candidate WHERE candidate.lesson_date IN (DATE '2026-08-01',DATE '2026-08-02')
  ) THEN RAISE EXCEPTION 'R2_F_F1_CROSS_MONTH_INCLUDED'; END IF;
  IF (SELECT count(*)<>660 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'23c996ac9ce14153c590ce2a57f09be9' FROM public.school_lesson_records t)
     OR (SELECT count(*)<>17 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'1d7328654f6488952dba20640072c3e2' FROM public.school_student_monthly_settlements t)
     OR (SELECT count(*)<>9 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'0f0323b79e7ff1c47ff6b90c75477a2d' FROM public.school_student_tuition_bills t)
     OR (SELECT count(*)<>42 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'2a4897b752f272b1f192045418b4940c' FROM public.school_income_records t)
     OR (SELECT count(*)<>7 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'4d91a5a1074f90389822fc367a7e5467' FROM public.school_student_tuition_billing_identities t)
     OR (SELECT count(*)<>121 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'285172fedeb923c67ea9a179480d8692' FROM public.school_student_tuition_bill_lessons t)
     OR (SELECT count(*)<>556 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'6204dc666b3b8e0f64fac901ecf0686a' FROM public.school_teacher_wage_lock_details t)
     OR (SELECT count(*)<>95 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'7bbe108d3ac73d4f21530793bf141bc6' FROM public.school_teacher_wage_locks t)
     OR (SELECT count(*)<>185 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'8f4f6c4365035f6c36bac59ba986b28b' FROM public.school_account_transactions t)
     OR (SELECT count(*)<>35 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'6e76a4dc2fc2954b28b7ad0a8d203ba0' FROM public.school_personal_cash_income_linkage_events t) THEN
    RAISE EXCEPTION 'R2_F_F1_HISTORY_DRIFT';
  END IF;
  IF EXISTS(SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_F1_WRITER_CONTEXT_RESIDUE';
  END IF;
END
$assert$;

SELECT true AS postdeploy_pass;
ROLLBACK;
