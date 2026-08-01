-- School V2 2026-08 read-only postdeploy acceptance.
-- Required psql variable: tuition_202608_expected_generate_state=blocked|enabled.
\set ON_ERROR_STOP on
\pset pager off

\if :{?tuition_202608_expected_generate_state}
\else
  \echo 'TUITION_202608_EXPECTED_GENERATE_STATE_REQUIRED'
  \quit
\endif

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout='240s';
SELECT set_config('school.tuition_202608_expected_generate_state',
                  :'tuition_202608_expected_generate_state',true);

DO $assert$
DECLARE
  v_snapshot_definition text;
  v_core_definition text;
  v_candidate_count integer;
  v_candidate_hash text;
BEGIN
  IF current_setting('school.tuition_202608_expected_generate_state')
       NOT IN ('blocked','enabled') THEN
    RAISE EXCEPTION 'TUITION_202608_EXPECTED_GATE_INVALID';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate'
             AND state=current_setting('school.tuition_202608_expected_generate_state'))
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'TUITION_202608_GATE_STATE_FAILED';
  END IF;

  v_snapshot_definition:=pg_get_functiondef(
    'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
  );
  v_core_definition:=pg_get_functiondef(
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
  );
  IF md5(v_snapshot_definition)<>'083bcb58c2b92f34ded07dceafbbbbfe'
     OR md5(v_core_definition)<>'b88f6d960d920c10b914fe8e58cf38cb'
     OR md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     ))<>'11ef7b45932e6cd418c03c91da104fd0'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure
     ))<>'36bdadc9af59637c9d336ce68d9afb4c' THEN
    RAISE EXCEPTION 'TUITION_202608_FUNCTION_FINGERPRINT_FAILED';
  END IF;
  IF position('locked_previous_settlement_only' IN v_snapshot_definition)=0
     OR position('school_get_student_monthly_settlement_preview' IN v_snapshot_definition)>0
     OR position('school_get_student_duration_overage_aggregate' IN v_snapshot_definition)>0
     OR position('R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED' IN v_snapshot_definition)>0
     OR position('locked_previous_settlement_only' IN v_core_definition)=0
     OR position('active_adjustment_draft_count' IN v_core_definition)>0
     OR position('duration_overage_fee_cny' IN v_core_definition)>0 THEN
    RAISE EXCEPTION 'TUITION_202608_CARRYOVER_AUTHORITY_FAILED';
  END IF;

  WITH all_candidates AS (
    SELECT student.id AS student_id,candidate.planned_lesson_id
    FROM public.school_students student
    CROSS JOIN LATERAL public.school_list_student_tuition_charge_candidates(
      student.id,student.business_entity_id,'2026-08',false
    ) candidate
    WHERE student.app_type='school' AND student.status='active'
  )
  SELECT count(*)::integer,encode(digest(string_agg(planned_lesson_id::text,'|'
           ORDER BY student_id::text,planned_lesson_id::text),'sha256'),'hex')
  INTO v_candidate_count,v_candidate_hash
  FROM all_candidates;
  IF v_candidate_count<>114
     OR v_candidate_hash<>'cb3451c2f9482c202ffd02f2364ac4c2f84a29c821c1a3e6a0a9c8f864e3f3e3' THEN
    RAISE EXCEPTION 'TUITION_202608_FIXED_CANDIDATE_SET_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_students student
    CROSS JOIN LATERAL public.school_list_student_tuition_charge_candidates(
      student.id,student.business_entity_id,'2026-08',false
    ) candidate
    JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
    LEFT JOIN public.school_student_tuition_historical_lesson_exclusions exclusion
      ON exclusion.planned_lesson_id=lesson.id
    LEFT JOIN public.school_student_tuition_bill_lessons relation
      ON relation.planned_lesson_id=lesson.id AND relation.relation_role='canonical_charge'
    WHERE student.app_type='school' AND student.status='active'
      AND (lesson.lesson_type<>'planned'
        OR lesson.billing_month<>'2026-08'
        OR lesson.student_settlement_month<>'2026-08'
        OR lesson.billing_week_start_date IS NULL
        OR extract(isodow FROM lesson.billing_week_start_date)<>1
        OR lesson.status IN ('voided','cancelled','pending_makeup','makeup_completed')
        OR lesson.voided_at IS NOT NULL
        OR exclusion.id IS NOT NULL
        OR relation.id IS NOT NULL
        OR length(candidate.complete_row_hash)<>32)
  ) THEN
    RAISE EXCEPTION 'TUITION_202608_CANDIDATE_INVARIANT_FAILED';
  END IF;
  IF (SELECT count(*) FROM public.school_students student
      CROSS JOIN LATERAL public.school_list_student_tuition_charge_candidates(
        student.id,student.business_entity_id,'2026-08',false
      ) candidate
      JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
      WHERE student.status='active' AND lesson.billing_week_start_date=DATE '2026-08-31')<>20
     OR (SELECT count(*) FROM public.school_students student
      CROSS JOIN LATERAL public.school_list_student_tuition_charge_candidates(
        student.id,student.business_entity_id,'2026-08',false
      ) candidate
      JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
      WHERE student.status='active' AND lesson.lesson_date>=DATE '2026-09-01'
        AND lesson.billing_week_start_date=DATE '2026-08-31')<>5
     OR EXISTS (
       SELECT 1 FROM public.school_list_student_tuition_charge_candidates(
         'b17abc58-2f64-4bad-bf20-c9643ead60bc',
         '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',false
       ) candidate
       JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
       WHERE lesson.lesson_date IN (DATE '2026-08-01',DATE '2026-08-02')
     ) THEN
    RAISE EXCEPTION 'TUITION_202608_NATURAL_WEEK_BOUNDARY_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_students student
    CROSS JOIN (VALUES ('2026-05'::text),('2026-06'::text)) month_scope(month)
    CROSS JOIN LATERAL public.school_list_student_tuition_charge_candidates(
      student.id,student.business_entity_id,month_scope.month,false
    ) candidate
    WHERE student.app_type='school' AND student.status='active'
  )
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions)<>106
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE manifest_version='school-v2-2026-05-06-fixed-64-already-charged-20260802-v1')<>64
     OR to_regprocedure('public.school_20260802_fixed_64_already_charged_manifest()') IS NOT NULL
     OR position('TUITION_HISTORICAL_LESSON_EXCLUSION_INSERT_RETIRED' IN
          pg_get_functiondef('public.school_guard_tuition_historical_lesson_exclusion_insert()'::regprocedure))=0 THEN
    RAISE EXCEPTION 'TUITION_202608_HISTORICAL_EXCLUSION_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_billing_identities
      WHERE billing_month='2026-08' GROUP BY student_id,billing_month HAVING count(*)>1)>0
     OR (SELECT count(*) FROM public.school_student_tuition_billing_identities
         WHERE billing_month='2026-08')<>1
     OR NOT EXISTS (
       SELECT 1 FROM public.school_student_tuition_billing_identities identity_row
       JOIN public.school_student_tuition_bills bill ON bill.id=identity_row.canonical_bill_id
       JOIN public.school_income_records income ON income.id=bill.income_record_id
       WHERE identity_row.student_id='881dd60c-b92b-44ae-98e1-98448567a8d2'
         AND identity_row.billing_month='2026-08'
         AND bill.id='1b546782-1b39-4c73-a85d-27ab1e5086ad'
         AND income.id='cdf3da68-e578-4f1b-b759-2fff394e1906'
         AND income.status='received'
     ) THEN
    RAISE EXCEPTION 'TUITION_202608_EXISTING_IDENTITY_FAILED';
  END IF;

  IF position('R0 does not provide an enabled generation path' IN pg_get_functiondef(
       'public.school_generate_student_tuition_bill(uuid,text,text)'::regprocedure))=0
     OR position('R0 does not provide an enabled generation path' IN pg_get_functiondef(
       'public.school_generate_student_tuition_bill(uuid,text,numeric,text)'::regprocedure))=0
     OR position('R0 does not provide an enabled income-generation path' IN pg_get_functiondef(
       'public.school_create_student_tuition_bill_income_record(uuid,date,text)'::regprocedure))=0
     OR position('R0 does not provide an enabled legacy personal-Cash tuition income path' IN pg_get_functiondef(
       'public.school_create_personal_cash_tuition_income_record(date,text,uuid,uuid,uuid,numeric,text,text,text,text,text,boolean,text,text,text)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'TUITION_202608_LEGACY_WRITER_NOT_BLOCKED';
  END IF;

  IF (SELECT count(*)<>706 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'9b1644dbb1605164c5c3672106d6ba9f' FROM public.school_lesson_records x)
     OR (SELECT count(*)<>9 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'0f0323b79e7ff1c47ff6b90c75477a2d' FROM public.school_student_tuition_bills x)
     OR (SELECT count(*)<>42 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'2a4897b752f272b1f192045418b4940c' FROM public.school_income_records x)
     OR (SELECT count(*)<>121 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'285172fedeb923c67ea9a179480d8692' FROM public.school_student_tuition_bill_lessons x)
     OR (SELECT count(*)<>7 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'4d91a5a1074f90389822fc367a7e5467' FROM public.school_student_tuition_billing_identities x)
     OR (SELECT count(*)<>17 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'1d7328654f6488952dba20640072c3e2' FROM public.school_student_monthly_settlements x)
     OR (SELECT count(*)<>185 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'8f4f6c4365035f6c36bac59ba986b28b' FROM public.school_account_transactions x)
     OR (SELECT count(*)<>35 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'6e76a4dc2fc2954b28b7ad0a8d203ba0' FROM public.school_personal_cash_income_linkage_events x)
     OR (SELECT count(*)<>95 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'7bbe108d3ac73d4f21530793bf141bc6' FROM public.school_teacher_wage_locks x)
     OR (SELECT count(*)<>556 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'6204dc666b3b8e0f64fac901ecf0686a' FROM public.school_teacher_wage_lock_details x)
     OR (SELECT count(*)<>279 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.planned_lesson_id::text),''))<>'380ee5e6cb419572379a0cfa4dfe6821' FROM public.school_legacy_planned_settlement_evidence x)
     OR (SELECT count(*)<>234 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.actual_lesson_id::text),''))<>'e685566ddeb27bc9deb8ceb20a272374' FROM public.school_legacy_actual_settlement_evidence x)
     OR (SELECT count(*)<>106 OR md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))<>'e97642f2031aa4fa000d5cd8ac4196bf' FROM public.school_student_tuition_historical_lesson_exclusions x) THEN
    RAISE EXCEPTION 'TUITION_202608_HISTORY_FINGERPRINT_DRIFT';
  END IF;

  IF EXISTS (SELECT 1 FROM public.school_students
      WHERE id::text LIKE 'f2fb0000-0000-4000-8000-00000000a00%')
     OR EXISTS (SELECT 1 FROM public.school_lesson_records WHERE note='codex-test r2-f-b')
     OR EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'TUITION_202608_FIXTURE_RESIDUE';
  END IF;
END
$assert$;

WITH expected(student_name,student_id,rate,expected_candidates,expected_lessons,expected_hours,expected_base_fee,expected_aircon_fee,expected_total_fee,expected_carryover,expected_notice) AS (VALUES
  ('孙陈锋','b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,0.042::numeric,25,30,50::numeric,425000::numeric,9240::numeric,434240::numeric,0::numeric,18238.08::numeric),
  ('张倬闻','7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,0.043::numeric,30,35,65::numeric,650000::numeric,0::numeric,650000::numeric,107.50::numeric,28057.50::numeric),
  ('彭宇晗','eb705aad-de4d-45e6-a391-42dcdd89aeda'::uuid,0.0435::numeric,15,15,30::numeric,255000::numeric,0::numeric,255000::numeric,0::numeric,11092.50::numeric),
  ('李天伦','a7b163a0-201e-4867-9b94-372343356a80'::uuid,0.05::numeric,16,21,32::numeric,352000::numeric,0::numeric,352000::numeric,0::numeric,17600::numeric),
  ('袁振轩','4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,0.0415::numeric,16,19,37::numeric,333000::numeric,0::numeric,333000::numeric,0::numeric,13819.50::numeric),
  ('陈红卓','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,0.043::numeric,12,12,24::numeric,204000::numeric,0::numeric,204000::numeric,0::numeric,8772::numeric)
), actual AS (
  SELECT expected.*,preview.*
  FROM expected
  CROSS JOIN LATERAL public.school_get_student_tuition_validation_preview_details(
    expected.student_id,'2026-08',expected.rate
  ) preview
)
SELECT student_name,candidate_count,total_lesson_count,total_duration_hours,
       total_base_lesson_fee_jpy,total_aircon_fee_jpy,total_fee_jpy,
       billing_exchange_rate,previous_carryover_cny,billing_amount_cny,
       candidate_manifest_sha256,generation_manifest_sha256,
       CASE WHEN candidate_count=expected_candidates AND total_lesson_count=expected_lessons
          AND total_duration_hours=expected_hours AND total_base_lesson_fee_jpy=expected_base_fee
          AND total_aircon_fee_jpy=expected_aircon_fee AND total_fee_jpy=expected_total_fee
          AND previous_carryover_cny=expected_carryover AND billing_amount_cny=expected_notice
          AND feature_state='enabled'
          AND generate_feature_state=:'tuition_202608_expected_generate_state'
         THEN 'PASS' ELSE 'FAIL' END AS acceptance
FROM actual
ORDER BY student_name;

DO $preview_assert$
DECLARE v_failed integer;
BEGIN
  WITH expected(student_id,rate,candidates,lessons,hours,base_fee,aircon_fee,total_fee,carryover,notice) AS (VALUES
    ('b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,0.042::numeric,25,30,50::numeric,425000::numeric,9240::numeric,434240::numeric,0::numeric,18238.08::numeric),
    ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,0.043::numeric,30,35,65::numeric,650000::numeric,0::numeric,650000::numeric,107.50::numeric,28057.50::numeric),
    ('eb705aad-de4d-45e6-a391-42dcdd89aeda'::uuid,0.0435::numeric,15,15,30::numeric,255000::numeric,0::numeric,255000::numeric,0::numeric,11092.50::numeric),
    ('a7b163a0-201e-4867-9b94-372343356a80'::uuid,0.05::numeric,16,21,32::numeric,352000::numeric,0::numeric,352000::numeric,0::numeric,17600::numeric),
    ('4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,0.0415::numeric,16,19,37::numeric,333000::numeric,0::numeric,333000::numeric,0::numeric,13819.50::numeric),
    ('eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,0.043::numeric,12,12,24::numeric,204000::numeric,0::numeric,204000::numeric,0::numeric,8772::numeric)
  )
  SELECT count(*) INTO v_failed FROM expected
  CROSS JOIN LATERAL public.school_get_student_tuition_validation_preview_details(
    expected.student_id,'2026-08',expected.rate
  ) preview
  WHERE preview.candidate_count<>expected.candidates
     OR preview.total_lesson_count<>expected.lessons
     OR preview.total_duration_hours<>expected.hours
     OR preview.total_base_lesson_fee_jpy<>expected.base_fee
     OR preview.total_aircon_fee_jpy<>expected.aircon_fee
     OR preview.total_fee_jpy<>expected.total_fee
     OR preview.previous_carryover_cny<>expected.carryover
     OR preview.billing_amount_cny<>expected.notice
     OR preview.feature_state<>'enabled'
     OR preview.generate_feature_state<>
          current_setting('school.tuition_202608_expected_generate_state');
  IF v_failed<>0 THEN RAISE EXCEPTION 'TUITION_202608_ALL_PREVIEWS_FAILED'; END IF;
END
$preview_assert$;

SELECT true AS postdeploy_pass,0 AS real_bill_income_created_by_acceptance,
       0 AS cash_calls,0 AS persisted_fixture_rows;
COMMIT;
