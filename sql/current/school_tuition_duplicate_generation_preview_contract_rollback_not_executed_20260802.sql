-- Targeted rollback for the duplicate-generation preview error contract.
-- NOT EXECUTED. Requires fresh business-owner authorization before use.
-- Restores only the immediately previous validation-preview function body.
\set ON_ERROR_STOP on
\pset pager off

\if :{?tuition_duplicate_preview_rollback_commit}
\else
  \echo 'TUITION_DUPLICATE_PREVIEW_ROLLBACK_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     ))<>'c90ce637c055b7322f278d89ff9fbed6' THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_ROLLBACK_BASELINE_DRIFT';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.school_get_student_tuition_validation_preview_details(
  p_student_id uuid,p_billing_month text,p_billing_exchange_rate numeric
)
RETURNS TABLE(
  feature_state text,generate_feature_state text,student_id uuid,
  business_entity_id uuid,billing_month text,previous_settlement_month text,
  previous_settlement_id uuid,previous_carryover_cny numeric,
  candidate_count integer,total_lesson_count integer,
  total_duration_hours numeric,total_base_lesson_fee_jpy numeric,
  total_aircon_fee_jpy numeric,total_fee_jpy numeric,bill_amount_jpy numeric,
  currency text,billing_exchange_rate numeric,billing_amount_cny numeric,
  billing_amount_currency text,existing_tuition_bill_id uuid,
  existing_tuition_bill_status text,existing_income_record_id uuid,
  existing_income_status text,candidate_uuid_md5 text,
  candidate_manifest_sha256 text,generation_manifest_sha256 text,
  candidates jsonb,message text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
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

REVOKE ALL ON FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  TO authenticated,service_role;

DO $verify$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     ))<>'11ef7b45932e6cd418c03c91da104fd0' THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_ROLLBACK_VERIFY_FAILED';
  END IF;
END
$verify$;

\if :tuition_duplicate_preview_rollback_commit
  COMMIT;
  \echo 'TUITION_DUPLICATE_PREVIEW_ROLLBACK_EXECUTED'
\else
  ROLLBACK;
  \echo 'TUITION_DUPLICATE_PREVIEW_ROLLBACK_REHEARSAL_ONLY'
\endif
