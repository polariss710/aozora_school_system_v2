-- School V2 R2-F-F: enable authoritative tuition preview and atomic generate.
-- Required psql variable: r2_f_f_gate_commit=0 rehearsal or 1 deploy.
-- Only the feature-gate configuration and preview function contract change.
-- This file never calls generate and never creates bill/income business rows.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_f_gate_commit}
\else
  \echo 'R2_F_F_GATE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

\echo 'R2_F_F_GATE_BEGIN'
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     ))<>'c203b2d21385bf3425a6ae74ef9515e3'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure
     ))<>'36bdadc9af59637c9d336ce68d9afb4c'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
     ))<>'c6bd995a4703306d049ea30a9fb2ae17'
     OR md5(pg_get_functiondef(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
     ))<>'bd1e8aebbe3038ff7423a1f8868b9220' THEN
    RAISE EXCEPTION 'R2_F_F_GATE_PROTECTED_FUNCTION_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F_GATE_BASELINE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_venues
      WHERE (code='Regus办公室' AND aircon_eligible)
         OR (code='Regus公共区' AND NOT aircon_eligible))<>2
     OR to_regprocedure(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,text,uuid,text,numeric,numeric,integer)'
     ) IS NULL THEN
    RAISE EXCEPTION 'R2_F_F_GATE_AIRCON_POLICY_NOT_READY';
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
    RAISE EXCEPTION 'R2_F_F_GATE_LEGACY_ENTRY_NOT_PERMANENTLY_BLOCKED';
  END IF;
END
$preflight$;

\echo 'R2_F_F_GATE_EXPAND_STATE_CONSTRAINT'
ALTER TABLE public.school_feature_gates
  DROP CONSTRAINT school_feature_gates_state_check,
  ADD CONSTRAINT school_feature_gates_state_check CHECK (
    state IN ('validation_preview_only','blocked','enabled')
  );
COMMENT ON CONSTRAINT school_feature_gates_state_check
ON public.school_feature_gates IS
  'R2-F-F permits reviewed preview/generate enablement while Cash remains independently fail-closed.';

\echo 'R2_F_F_GATE_REPLACE_PREVIEW_CONTRACT'
DROP FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric);
CREATE FUNCTION public.school_get_student_tuition_validation_preview_details(
  p_student_id uuid,p_billing_month text,p_billing_exchange_rate numeric
)
RETURNS TABLE(
  feature_state text,generate_feature_state text,
  student_id uuid,business_entity_id uuid,billing_month text,
  previous_settlement_month text,previous_settlement_id uuid,
  previous_carryover_cny numeric,candidate_count integer,
  total_lesson_count integer,total_duration_hours numeric,
  total_base_lesson_fee_jpy numeric,total_aircon_fee_jpy numeric,
  total_fee_jpy numeric,bill_amount_jpy numeric,currency text,
  billing_exchange_rate numeric,billing_amount_cny numeric,
  billing_amount_currency text,existing_tuition_bill_id uuid,
  existing_tuition_bill_status text,existing_income_record_id uuid,
  existing_income_status text,candidate_uuid_md5 text,
  candidate_manifest_sha256 text,generation_manifest_sha256 text,
  candidates jsonb,message text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
DECLARE
  v_preview_state text;
  v_generate_state text;
  v_snapshot record;
  v_existing public.school_student_tuition_bills%ROWTYPE;
  v_income public.school_income_records%ROWTYPE;
  v_message text;
BEGIN
  BEGIN
    SELECT gate.state INTO STRICT v_preview_state
    FROM public.school_feature_gates gate
    WHERE gate.feature_key='student_tuition_preview';
    SELECT gate.state INTO STRICT v_generate_state
    FROM public.school_feature_gates gate
    WHERE gate.feature_key='student_tuition_generate';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'TUITION_PREVIEW_BLOCKED: 学费预览gate读取失败，已按fail-closed拒绝。';
  END;
  IF v_preview_state NOT IN ('validation_preview_only','enabled') THEN
    RAISE EXCEPTION 'TUITION_PREVIEW_BLOCKED: 学费预览尚未开放。';
  END IF;
  IF v_generate_state NOT IN ('blocked','enabled') THEN
    RAISE EXCEPTION 'TUITION_PREVIEW_BLOCKED: 学费生成gate状态无效。';
  END IF;

  SELECT * INTO STRICT v_snapshot
  FROM public.school_build_student_tuition_generation_snapshot(
    p_student_id,p_billing_month,p_billing_exchange_rate
  );
  SELECT bill.* INTO v_existing
  FROM public.school_student_tuition_bills bill
  WHERE bill.student_id=v_snapshot.student_id
    AND bill.business_entity_id=v_snapshot.business_entity_id
    AND bill.billing_month=v_snapshot.billing_month
    AND bill.status IN ('draft','income_created')
  ORDER BY bill.updated_at DESC NULLS LAST,bill.created_at DESC NULLS LAST
  LIMIT 1;
  IF FOUND THEN
    SELECT income.* INTO v_income FROM public.school_income_records income
    WHERE income.id=v_existing.income_record_id;
    v_message:='existing tuition billing identity requires idempotent writer resolution';
  ELSE
    v_message:=CASE WHEN v_generate_state='enabled'
      THEN 'authoritative preview ready for atomic generation; no business data written'
      ELSE 'validation preview only; no business data written' END;
  END IF;

  RETURN QUERY SELECT v_preview_state,v_generate_state,
    v_snapshot.student_id,v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
    v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,
    v_snapshot.total_lesson_count,v_snapshot.total_duration_hours,
    v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,'JPY'::text,
    v_snapshot.billing_exchange_rate,v_snapshot.billing_amount_cny,'CNY'::text,
    v_existing.id,v_existing.status,v_existing.income_record_id,v_income.status,
    v_snapshot.candidate_uuid_md5,v_snapshot.candidate_manifest_sha256,
    v_snapshot.generation_manifest_sha256,v_snapshot.candidates,v_message;
END
$function$;
REVOKE ALL ON FUNCTION public.school_get_student_tuition_validation_preview_details(
  uuid,text,numeric
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.school_get_student_tuition_validation_preview_details(
  uuid,text,numeric
) TO authenticated,service_role;
COMMENT ON FUNCTION public.school_get_student_tuition_validation_preview_details(
  uuid,text,numeric
) IS
  'R2-F-F authoritative preview. Returns both preview and atomic-generate DB gate states plus canonical candidate and generation manifests; writes nothing.';

\echo 'R2_F_F_GATE_ENABLE'
UPDATE public.school_feature_gates
SET state='enabled',
    reason='R2-F-F权威preview与唯一atomic generate已完成数据库及前端验收。',
    release_version='r2-f-f-20260801',
    evidence_hash='aircon-v2-atomic-generate-reviewed',
    updated_at=statement_timestamp(),updated_by=current_user
WHERE feature_key IN ('student_tuition_preview','student_tuition_generate');
UPDATE public.school_feature_gates
SET state='blocked',
    reason='R2-F-F仅恢复学费preview与atomic generate；Cash提交继续禁止。',
    release_version='r2-f-f-20260801',
    evidence_hash='cash-submit-remains-blocked',
    updated_at=statement_timestamp(),updated_by=current_user
WHERE feature_key='student_tuition_cash_submit';

\echo 'R2_F_F_GATE_VERIFY'
DO $verify$
DECLARE
  v_sun record;
  v_zhang record;
  v_blocked integer:=0;
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='enabled')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F_GATE_TARGET_STATE_FAILED';
  END IF;
  SELECT * INTO STRICT v_sun
  FROM public.school_get_student_tuition_validation_preview_details(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.042
  );
  SELECT * INTO STRICT v_zhang
  FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.043
  );
  IF v_sun.feature_state<>'enabled' OR v_sun.generate_feature_state<>'enabled'
     OR v_sun.candidate_count<>22 OR v_sun.total_lesson_count<>24
     OR v_sun.total_duration_hours<>44 OR v_sun.total_base_lesson_fee_jpy<>374000
     OR v_sun.total_aircon_fee_jpy<>660 OR v_sun.total_fee_jpy<>374660
     OR v_sun.previous_carryover_cny<>0 OR v_sun.billing_amount_cny<>15735.72 THEN
    RAISE EXCEPTION 'R2_F_F_GATE_SUN_PREVIEW_FAILED';
  END IF;
  IF v_zhang.feature_state<>'enabled' OR v_zhang.generate_feature_state<>'enabled'
     OR v_zhang.candidate_count<>30 OR v_zhang.total_lesson_count<>35
     OR v_zhang.total_duration_hours<>65 OR v_zhang.total_base_lesson_fee_jpy<>650000
     OR v_zhang.total_aircon_fee_jpy<>0 OR v_zhang.total_fee_jpy<>650000
     OR v_zhang.previous_carryover_cny<>107.50
     OR v_zhang.billing_amount_cny<>28057.50 THEN
    RAISE EXCEPTION 'R2_F_F_GATE_ZHANG_PREVIEW_FAILED';
  END IF;

  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',NULL::text
    );
  EXCEPTION WHEN OTHERS THEN
    IF position('R0 does not provide an enabled generation path' IN SQLERRM)>0
      THEN v_blocked:=v_blocked+1; ELSE RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.042,NULL
    );
  EXCEPTION WHEN OTHERS THEN
    IF position('R0 does not provide an enabled generation path' IN SQLERRM)>0
      THEN v_blocked:=v_blocked+1; ELSE RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_student_tuition_bill_income_record(
      '00000000-0000-4000-8000-000000000000',CURRENT_DATE,NULL
    );
  EXCEPTION WHEN OTHERS THEN
    IF position('R0 does not provide an enabled income-generation path' IN SQLERRM)>0
      THEN v_blocked:=v_blocked+1; ELSE RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_personal_cash_tuition_income_record(
      CURRENT_DATE,'2026-08',NULL,NULL,NULL,1,
      'tuition',NULL,'JPY','JPY',NULL,false,NULL,NULL,NULL
    );
  EXCEPTION WHEN OTHERS THEN
    IF position('R0 does not provide an enabled legacy personal-Cash tuition income path' IN SQLERRM)>0
      THEN v_blocked:=v_blocked+1; ELSE RAISE; END IF;
  END;
  IF v_blocked<>4 THEN RAISE EXCEPTION 'R2_F_F_LEGACY_ENTRY_VERIFY_FAILED'; END IF;
  IF EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_F_GATE_WRITER_CONTEXT_RESIDUE';
  END IF;
END
$verify$;

\if :r2_f_f_gate_commit
  \echo 'R2_F_F_GATE_COMMIT'
  COMMIT;
\else
  \echo 'R2_F_F_GATE_ROLLBACK'
  ROLLBACK;
\endif
