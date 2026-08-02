-- School V2 duplicate-generation preview contract cutover.
-- Required psql variable: tuition_duplicate_preview_commit=0 rehearsal or 1 deploy.
\set ON_ERROR_STOP on
\pset pager off

\if :{?tuition_duplicate_preview_commit}
\else
  \echo 'TUITION_DUPLICATE_PREVIEW_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     ))<>'11ef7b45932e6cd418c03c91da104fd0' THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_BASELINE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
     ))<>'083bcb58c2b92f34ded07dceafbbbbfe'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
     ))<>'b88f6d960d920c10b914fe8e58cf38cb'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure
     ))<>'36bdadc9af59637c9d336ce68d9afb4c'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'::regprocedure
     ))<>'65e718ba8d2e4cb46ebb0dc84b11bc2e' THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_UNAUTHORIZED_FUNCTION_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='enabled')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_GATE_DRIFT';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.school_get_student_tuition_validation_preview_details(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric
)
RETURNS TABLE(
  feature_state text,
  generate_feature_state text,
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  candidate_count integer,
  total_lesson_count integer,
  total_duration_hours numeric,
  total_base_lesson_fee_jpy numeric,
  total_aircon_fee_jpy numeric,
  total_fee_jpy numeric,
  bill_amount_jpy numeric,
  currency text,
  billing_exchange_rate numeric,
  billing_amount_cny numeric,
  billing_amount_currency text,
  existing_tuition_bill_id uuid,
  existing_tuition_bill_status text,
  existing_income_record_id uuid,
  existing_income_status text,
  candidate_uuid_md5 text,
  candidate_manifest_sha256 text,
  generation_manifest_sha256 text,
  candidates jsonb,
  message text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_preview_state text;
  v_generate_state text;
  v_month text := nullif(pg_catalog.btrim(coalesce(p_billing_month,'')),'');
  v_student public.school_students%ROWTYPE;
  v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_bill public.school_student_tuition_bills%ROWTYPE;
  v_income public.school_income_records%ROWTYPE;
  v_snapshot record;
  v_identity_count integer := 0;
  v_target_bill_count integer := 0;
  v_target_income_count integer := 0;
  v_related_income_count integer := 0;
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

  IF p_student_id IS NULL THEN RAISE EXCEPTION 'R2_F_B_STUDENT_REQUIRED'; END IF;
  IF v_month IS NULL OR v_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R2_F_B_BILLING_MONTH_INVALID';
  END IF;
  IF p_billing_exchange_rate IS NULL OR p_billing_exchange_rate<=0 THEN
    RAISE EXCEPTION 'R2_F_B_EXCHANGE_RATE_INVALID';
  END IF;

  SELECT student.* INTO v_student
  FROM public.school_students student
  WHERE student.id=p_student_id AND student.app_type='school';
  IF NOT FOUND THEN RAISE EXCEPTION 'R2_F_B_STUDENT_NOT_FOUND'; END IF;
  IF coalesce(v_student.status,'') IN ('inactive','disabled','archived') THEN
    RAISE EXCEPTION 'R2_F_B_STUDENT_INACTIVE';
  END IF;
  IF v_student.business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R2_F_B_BUSINESS_ENTITY_REQUIRED';
  END IF;

  SELECT count(*)::integer INTO v_identity_count
  FROM public.school_student_tuition_billing_identities identity_row
  WHERE identity_row.student_id=p_student_id
    AND identity_row.billing_month=v_month;

  SELECT count(*)::integer INTO v_target_bill_count
  FROM public.school_student_tuition_bills bill
  WHERE bill.student_id=p_student_id
    AND bill.business_entity_id=v_student.business_entity_id
    AND bill.billing_month=v_month
    AND (bill.billing_role='canonical_charge'
      OR bill.source_snapshot->>'generation_source'='student_tuition_atomic_generate_v1');

  SELECT count(*)::integer INTO v_target_income_count
  FROM public.school_income_records income
  WHERE income.student_id=p_student_id
    AND income.business_entity_id=v_student.business_entity_id
    AND income.source_type='student_tuition_bill'
    AND income.source_snapshot->>'generation_source'='student_tuition_atomic_generate_v1'
    AND income.source_snapshot->>'billing_month'=v_month;

  IF v_identity_count>1 THEN
    RAISE EXCEPTION 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
  END IF;

  IF v_identity_count=1 THEN
    BEGIN
      SELECT identity_row.* INTO STRICT v_identity
      FROM public.school_student_tuition_billing_identities identity_row
      WHERE identity_row.student_id=p_student_id
        AND identity_row.billing_month=v_month;

      SELECT bill.* INTO v_bill
      FROM public.school_student_tuition_bills bill
      WHERE bill.id=v_identity.canonical_bill_id;

      IF v_bill.id IS NOT NULL THEN
        SELECT income.* INTO v_income
        FROM public.school_income_records income
        WHERE income.id=v_bill.income_record_id;

        SELECT count(*)::integer INTO v_related_income_count
        FROM public.school_income_records income
        WHERE income.id=v_bill.income_record_id
           OR (income.source_type='student_tuition_bill'
             AND (income.source_id=v_bill.id OR income.tuition_bill_id=v_bill.id));
      END IF;

      IF v_target_bill_count<>1 OR v_target_income_count<>1
         OR v_identity.student_id IS DISTINCT FROM p_student_id
         OR v_identity.billing_month IS DISTINCT FROM v_month
         OR v_identity.source IS DISTINCT FROM 'atomic_charge'
         OR v_identity.evidence->>'generation_source'
              IS DISTINCT FROM 'student_tuition_atomic_generate_v1'
         OR v_bill.id IS NULL
         OR v_identity.canonical_bill_id IS DISTINCT FROM v_bill.id
         OR v_bill.student_id IS DISTINCT FROM p_student_id
         OR v_bill.business_entity_id IS DISTINCT FROM v_student.business_entity_id
         OR v_bill.billing_month IS DISTINCT FROM v_month
         OR v_bill.billing_role IS DISTINCT FROM 'canonical_charge'
         OR v_bill.status IS DISTINCT FROM 'income_created'
         OR v_bill.cancelled_at IS NOT NULL
         OR v_bill.incident_locked_at IS NOT NULL
         OR v_bill.billing_exchange_rate IS NULL
         OR v_bill.billing_exchange_rate<=0
         OR v_bill.source_snapshot->>'generation_source'
              IS DISTINCT FROM 'student_tuition_atomic_generate_v1'
         OR coalesce(v_bill.source_snapshot->>'generation_manifest_sha256','')
              !~ '^[0-9a-f]{64}$'
         OR coalesce(v_bill.source_snapshot->>'candidate_manifest_sha256','')
              !~ '^[0-9a-f]{64}$'
         OR coalesce(v_bill.source_snapshot->>'carryover_evidence_sha256','')
              !~ '^[0-9a-f]{64}$'
         OR v_identity.evidence->>'generation_manifest_sha256'
              IS DISTINCT FROM v_bill.source_snapshot->>'generation_manifest_sha256'
         OR v_identity.evidence->>'candidate_manifest_sha256'
              IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
         OR v_identity.evidence->>'carryover_evidence_sha256'
              IS DISTINCT FROM v_bill.source_snapshot->>'carryover_evidence_sha256'
         OR v_identity.evidence->>'business_entity_id'
              IS DISTINCT FROM v_bill.business_entity_id::text
         OR (v_bill.source_snapshot->>'billing_exchange_rate')::numeric
              IS DISTINCT FROM v_bill.billing_exchange_rate
         OR (v_bill.source_snapshot->>'total_fee_jpy')::numeric
              IS DISTINCT FROM v_bill.bill_amount_jpy
         OR v_bill.planned_lesson_fee_jpy IS DISTINCT FROM v_bill.bill_amount_jpy
         OR (v_bill.source_snapshot->>'previous_carryover_cny')::numeric
              IS DISTINCT FROM v_bill.previous_carryover_cny
         OR v_bill.source_snapshot->>'previous_settlement_month'
              IS DISTINCT FROM v_bill.previous_settlement_month
         OR nullif(v_bill.source_snapshot->>'previous_settlement_id','')::uuid
              IS DISTINCT FROM v_bill.previous_settlement_id
         OR jsonb_typeof(v_bill.source_snapshot->'carryover_evidence') IS DISTINCT FROM 'object'
         OR encode(sha256(convert_to(
              (v_bill.source_snapshot->'carryover_evidence')::text,'UTF8'
            )),'hex') IS DISTINCT FROM v_bill.source_snapshot->>'carryover_evidence_sha256'
         OR v_bill.billing_amount_cny IS DISTINCT FROM round(
              v_bill.bill_amount_jpy*v_bill.billing_exchange_rate
                +v_bill.previous_carryover_cny,2
            )
         OR (v_bill.source_snapshot->>'billing_amount_cny')::numeric
              IS DISTINCT FROM v_bill.billing_amount_cny
         OR v_income.id IS NULL
         OR v_bill.income_record_id IS DISTINCT FROM v_income.id
         OR v_related_income_count<>1
         OR v_income.status NOT IN ('pending','received')
         OR v_income.cancelled_at IS NOT NULL
         OR v_income.reversed_at IS NOT NULL
         OR v_income.incident_type IS NOT NULL
         OR v_income.incident_quarantined_at IS NOT NULL
         OR v_income.operational_excluded
         OR v_income.student_id IS DISTINCT FROM p_student_id
         OR v_income.business_entity_id IS DISTINCT FROM v_bill.business_entity_id
         OR v_income.source_type IS DISTINCT FROM 'student_tuition_bill'
         OR v_income.source_id IS DISTINCT FROM v_bill.id
         OR v_income.tuition_bill_id IS DISTINCT FROM v_bill.id
         OR v_income.amount IS DISTINCT FROM v_bill.bill_amount_jpy
         OR v_income.amount_jpy IS DISTINCT FROM v_bill.bill_amount_jpy
         OR v_income.source_snapshot->>'generation_manifest_sha256'
              IS DISTINCT FROM v_bill.source_snapshot->>'generation_manifest_sha256'
         OR v_income.source_snapshot->>'candidate_manifest_sha256'
              IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
         OR v_income.source_snapshot->>'carryover_evidence_sha256'
              IS DISTINCT FROM v_bill.source_snapshot->>'carryover_evidence_sha256'
         OR (v_income.source_snapshot->>'billing_exchange_rate')::numeric
              IS DISTINCT FROM v_bill.billing_exchange_rate
         OR (v_income.source_snapshot->>'billing_amount_cny')::numeric
              IS DISTINCT FROM v_bill.billing_amount_cny
         OR (v_income.source_snapshot->>'previous_carryover_cny')::numeric
              IS DISTINCT FROM v_bill.previous_carryover_cny
         OR v_income.source_snapshot->>'previous_settlement_month'
              IS DISTINCT FROM v_bill.previous_settlement_month
         OR nullif(v_income.source_snapshot->>'previous_settlement_id','')::uuid
              IS DISTINCT FROM v_bill.previous_settlement_id THEN
        RAISE EXCEPTION 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
      END IF;

      PERFORM public.school_validate_tuition_identity_for_bill(v_bill.id);
      PERFORM public.school_validate_tuition_bill_income_for_bill(v_bill.id);
      PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
    END;
    RAISE EXCEPTION 'R2_F_B_ALREADY_BILLED';
  END IF;

  IF v_target_bill_count<>0 OR v_target_income_count<>0 THEN
    RAISE EXCEPTION 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
  END IF;

  SELECT * INTO STRICT v_snapshot
  FROM public.school_build_student_tuition_generation_snapshot(
    p_student_id,v_month,p_billing_exchange_rate
  );

  v_message:=CASE WHEN v_generate_state='enabled'
    THEN 'authoritative preview ready for atomic generation; no business data written'
    ELSE 'validation preview only; no business data written' END;

  RETURN QUERY SELECT v_preview_state,v_generate_state,
    v_snapshot.student_id,v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
    v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,
    v_snapshot.total_lesson_count,v_snapshot.total_duration_hours,
    v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,'JPY'::text,
    v_snapshot.billing_exchange_rate,v_snapshot.billing_amount_cny,'CNY'::text,
    NULL::uuid,NULL::text,NULL::uuid,NULL::text,
    v_snapshot.candidate_uuid_md5,v_snapshot.candidate_manifest_sha256,
    v_snapshot.generation_manifest_sha256,v_snapshot.candidates,v_message;
END
$function$;

REVOKE ALL ON FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  TO authenticated,service_role;

COMMENT ON FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric) IS
  'Validation preview checks the existing atomic billing identity and its canonical bill/income chain before candidate snapshot construction. A complete chain raises R2_F_B_ALREADY_BILLED; an incomplete or conflicting chain fails closed.';

DO $verify$
DECLARE v_definition text;
BEGIN
  v_definition:=pg_get_functiondef(
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
  );
  IF position('R2_F_B_ALREADY_BILLED' IN v_definition)=0
     OR position('R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE' IN v_definition)=0
     OR position('school_validate_tuition_bill_lessons_for_bill' IN v_definition)=0
     OR position('school_build_student_tuition_generation_snapshot' IN v_definition)=0
     OR position('R2_F_B_ALREADY_BILLED' IN v_definition)>
        position('school_build_student_tuition_generation_snapshot' IN v_definition) THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_CONTRACT_VERIFY_FAILED';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
     ))<>'083bcb58c2b92f34ded07dceafbbbbfe'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
     ))<>'b88f6d960d920c10b914fe8e58cf38cb'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure
     ))<>'36bdadc9af59637c9d336ce68d9afb4c'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'::regprocedure
     ))<>'65e718ba8d2e4cb46ebb0dc84b11bc2e' THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_PROTECTED_FUNCTION_CHANGED';
  END IF;
END
$verify$;

SAVEPOINT tuition_duplicate_preview_fixture_matrix;
\ir school_tuition_duplicate_generation_preview_contract_rollback_tests_20260802.sql
ROLLBACK TO SAVEPOINT tuition_duplicate_preview_fixture_matrix;
RELEASE SAVEPOINT tuition_duplicate_preview_fixture_matrix;

DO $fixture_residual$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.school_students
    WHERE id::text LIKE 'f2fd0000-0000-4000-8000-00000000a00%'
  ) OR EXISTS (
    SELECT 1 FROM public.school_lesson_records
    WHERE note='codex-test duplicate preview contract'
  ) OR EXISTS (
    SELECT 1 FROM public.school_tuition_atomic_writer_context
  ) THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_FIXTURE_RESIDUE';
  END IF;
END
$fixture_residual$;

\if :tuition_duplicate_preview_commit
  COMMIT;
  \echo 'TUITION_DUPLICATE_PREVIEW_CONTRACT_DEPLOYED'
\else
  ROLLBACK;
  \echo 'TUITION_DUPLICATE_PREVIEW_CONTRACT_REHEARSAL_ROLLED_BACK'
\endif
