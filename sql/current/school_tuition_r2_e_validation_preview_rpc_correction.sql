-- Aozora School System V2 R2-E
-- Independent correction for the deployed validation-preview details RPC.
-- Required psql variable:
--   r2_e_preview_fix_commit=0  same-byte rehearsal and explicit ROLLBACK
--   r2_e_preview_fix_commit=1  formal correction and explicit COMMIT

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_e_preview_fix_commit}
\else
  \echo 'R2_E_PREVIEW_FIX_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

\echo 'R2_E_PREVIEW_FIX_BEGIN'
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';

DO $preflight$
DECLARE
  v_proc pg_proc%ROWTYPE;
BEGIN
  SELECT function_row.* INTO STRICT v_proc
  FROM pg_proc function_row
  WHERE function_row.oid =
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure;

  IF md5(pg_get_functiondef(v_proc.oid))
       <> 'a9f7bf4ab6b4aa323af699dd61e94ba7' THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_UNEXPECTED_DEPLOYED_DEFINITION';
  END IF;
  IF v_proc.provolatile <> 's'
     OR NOT v_proc.prosecdef
     OR v_proc.prokind <> 'f'
     OR v_proc.proowner::regrole::text <> 'postgres'
     OR v_proc.proconfig
          IS DISTINCT FROM ARRAY['search_path=pg_catalog, public']::text[] THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_FUNCTION_METADATA_DRIFT';
  END IF;
  IF NOT has_function_privilege(
       'authenticated',
       v_proc.oid,
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       v_proc.oid,
       'EXECUTE'
     )
     OR has_function_privilege('anon',v_proc.oid,'EXECUTE')
     OR v_proc.proacl::text <>
          '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_ACL_DRIFT';
  END IF;
  IF obj_description(v_proc.oid,'pg_proc') IS DISTINCT FROM
       'R2-E R0 validation-only details: one authoritative candidate snapshot with explicit base/rate/aircon/total and fail-closed UUID/manifest/summary consistency.' THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_COMMENT_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 654
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_lesson_records row_value)
          <> '9a787d2819b24fe4dece792b55b35ba5'
     OR (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_tuition_bills row_value)
          <> 'b91c381ea7c42d8dc60e8a6af189f86a'
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_income_records row_value)
          <> '3ee88b3e883359e819a93d80ea0204b2'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_tuition_bill_lessons row_value)
          <> 'ff626f1677571c76406b4bc7b5122391'
     OR (SELECT count(*) FROM public.school_teacher_wage_lock_details) <> 556
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_teacher_wage_lock_details row_value)
          <> '6d68749bc1f0fbb908d2dfdb43dcc774' THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_BUSINESS_BASELINE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked'))
       <> 3 THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_R0_DRIFT';
  END IF;
END
$preflight$;

\echo 'R2_E_PREVIEW_FIX_CREATE_OR_REPLACE'
CREATE OR REPLACE FUNCTION public.school_get_student_tuition_validation_preview_details(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric
)
RETURNS TABLE (
  feature_state text,
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
  candidates jsonb,
  message text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_month text := nullif(pg_catalog.btrim(coalesce(p_billing_month,'')),'');
  v_preview record;
  v_count integer;
  v_distinct_count integer;
  v_lesson_count integer;
  v_hours numeric;
  v_base numeric;
  v_aircon numeric;
  v_total numeric;
  v_uuid_md5 text;
  v_manifest text;
  v_candidates jsonb;
  v_contract_valid boolean;
BEGIN
  PERFORM public.school_require_feature_gate_state(
    'student_tuition_preview','validation_preview_only',
    'TUITION_PREVIEW_BLOCKED',
    '学费预览 gate 不可用，已按 fail-closed 拒绝。'
  );
  SELECT * INTO STRICT v_preview
  FROM public.school_preview_student_tuition_bill(
    p_student_id,v_month,p_billing_exchange_rate
  );

  WITH candidate_rows AS MATERIALIZED (
    SELECT * FROM public.school_list_student_tuition_charge_candidates(
      p_student_id,v_preview.business_entity_id,v_month,false
    )
  ), aggregated AS (
    SELECT
      count(*)::integer AS candidate_count,
      count(DISTINCT detail.planned_lesson_id)::integer AS distinct_count,
      coalesce(sum(detail.lesson_count),0)::integer AS lesson_count,
      coalesce(sum(detail.duration_hours),0)::numeric AS hours,
      coalesce(sum(detail.base_lesson_fee_jpy),0)::numeric AS base_fee,
      coalesce(sum(detail.aircon_fee_jpy),0)::numeric AS aircon_fee,
      coalesce(sum(detail.lesson_total_fee_jpy),0)::numeric AS total_fee,
      md5(string_agg(detail.planned_lesson_id::text,','
        ORDER BY detail.planned_lesson_id::text)) AS uuid_md5,
      encode(pg_catalog.sha256(pg_catalog.convert_to(
        string_agg(concat_ws('|',
          detail.planned_lesson_id::text,
          detail.student_id::text,
          detail.business_entity_id::text,
          detail.candidate_billing_month,
          detail.billing_week_start_date::text,
          detail.lesson_date::text,
          detail.lesson_count::text,
          detail.duration_hours::text,
          detail.base_lesson_fee_jpy::text,
          detail.aircon_rate_jpy_per_hour::text,
          detail.aircon_fee_jpy::text,
          detail.lesson_total_fee_jpy::text,
          coalesce(detail.aircon_policy_version,'legacy_base_only')
        ),E'\n' ORDER BY detail.billing_week_start_date,
          detail.lesson_date,detail.planned_lesson_id) || E'\n','UTF8'
      )),'hex') AS manifest,
      jsonb_agg(jsonb_build_object(
        'planned_lesson_id',detail.planned_lesson_id,
        'student_id',detail.student_id,
        'business_entity_id',detail.business_entity_id,
        'billing_month',detail.candidate_billing_month,
        'billing_week_start_date',detail.billing_week_start_date,
        'lesson_date',detail.lesson_date,
        'lesson_count',detail.lesson_count,
        'duration_hours',detail.duration_hours,
        'unit_price',detail.unit_price,
        'base_lesson_fee_jpy',detail.base_lesson_fee_jpy,
        'aircon_rate_jpy_per_hour',detail.aircon_rate_jpy_per_hour,
        'aircon_fee_jpy',detail.aircon_fee_jpy,
        'lesson_total_fee_jpy',detail.lesson_total_fee_jpy,
        'aircon_charge_status',detail.aircon_charge_status,
        'aircon_policy_version',detail.aircon_policy_version,
        'lesson_fee',detail.lesson_total_fee_jpy
      ) ORDER BY detail.billing_week_start_date,
        detail.lesson_date,detail.planned_lesson_id) AS candidates,
      bool_and(
        detail.student_id = p_student_id
        AND detail.business_entity_id = v_preview.business_entity_id
        AND detail.candidate_billing_month = v_month
        AND detail.billing_week_start_date IS NOT NULL
        AND extract(isodow FROM detail.billing_week_start_date) = 1
        AND to_char(detail.billing_week_start_date,'YYYY-MM') = v_month
        AND detail.lesson_total_fee_jpy
              = detail.base_lesson_fee_jpy + detail.aircon_fee_jpy
      ) AS contract_valid
    FROM candidate_rows detail
  )
  SELECT
    aggregated.candidate_count,
    aggregated.distinct_count,
    aggregated.lesson_count,
    aggregated.hours,
    aggregated.base_fee,
    aggregated.aircon_fee,
    aggregated.total_fee,
    aggregated.uuid_md5,
    aggregated.manifest,
    aggregated.candidates,
    aggregated.contract_valid
  INTO
    v_count,v_distinct_count,v_lesson_count,v_hours,v_base,v_aircon,
    v_total,v_uuid_md5,v_manifest,v_candidates,v_contract_valid
  FROM aggregated;

  IF v_count IS NULL OR v_count <= 0 THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_CANDIDATES_EMPTY';
  END IF;
  IF v_count IS DISTINCT FROM v_distinct_count THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_DUPLICATE_PLANNED_UUID';
  END IF;
  IF v_contract_valid IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_CANDIDATE_CONTRACT_MISMATCH';
  END IF;
  IF v_preview.planned_lesson_count IS DISTINCT FROM v_count
     OR v_preview.planned_lesson_hours IS DISTINCT FROM v_hours
     OR v_preview.planned_lesson_fee_jpy IS DISTINCT FROM v_total
     OR v_preview.bill_amount_jpy IS DISTINCT FROM v_total
     OR v_total IS DISTINCT FROM v_base + v_aircon
     OR jsonb_array_length(v_candidates) IS DISTINCT FROM v_count THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_SUMMARY_DETAIL_MISMATCH';
  END IF;

  RETURN QUERY SELECT
    'validation_preview_only'::text,
    v_preview.student_id,v_preview.business_entity_id,v_preview.billing_month,
    v_preview.previous_settlement_month,v_preview.previous_settlement_id,
    v_preview.previous_carryover_cny,v_count,v_lesson_count,v_hours,
    v_base,v_aircon,v_total,v_preview.bill_amount_jpy,v_preview.currency,
    v_preview.billing_exchange_rate,v_preview.billing_amount_cny,
    v_preview.billing_amount_currency,v_preview.existing_tuition_bill_id,
    v_preview.existing_tuition_bill_status,v_preview.existing_income_record_id,
    v_preview.existing_income_status,v_uuid_md5,v_manifest,v_candidates,
    v_preview.message;
END
$function$;

\echo 'R2_E_PREVIEW_FIX_TARGET_CALL'
DO $verify$
DECLARE
  v_proc pg_proc%ROWTYPE;
  v_preview record;
BEGIN
  SELECT function_row.* INTO STRICT v_proc
  FROM pg_proc function_row
  WHERE function_row.oid =
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure;

  IF md5(pg_get_functiondef(v_proc.oid))
       = 'a9f7bf4ab6b4aa323af699dd61e94ba7'
     OR pg_get_functiondef(v_proc.oid)
          NOT LIKE '%aggregated.candidate_count%'
     OR pg_get_functiondef(v_proc.oid)
          NOT LIKE '%aggregated.candidates%' THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_DEFINITION_NOT_CORRECTED';
  END IF;
  IF v_proc.provolatile <> 's'
     OR NOT v_proc.prosecdef
     OR v_proc.prokind <> 'f'
     OR v_proc.proowner::regrole::text <> 'postgres'
     OR v_proc.proconfig
          IS DISTINCT FROM ARRAY['search_path=pg_catalog, public']::text[] THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_METADATA_CHANGED';
  END IF;
  IF NOT has_function_privilege('authenticated',v_proc.oid,'EXECUTE')
     OR NOT has_function_privilege('service_role',v_proc.oid,'EXECUTE')
     OR has_function_privilege('anon',v_proc.oid,'EXECUTE')
     OR v_proc.proacl::text <>
          '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_ACL_CHANGED';
  END IF;

  SELECT preview_row.* INTO STRICT v_preview
  FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.05
  ) preview_row;
  RAISE NOTICE
    'R2_E_PREVIEW_FIX_RESULT feature=%, candidates=%, lesson_count=%, hours=%, base=%, aircon=%, total=%, bill=%, json=%',
    v_preview.feature_state,
    v_preview.candidate_count,
    v_preview.total_lesson_count,
    v_preview.total_duration_hours,
    v_preview.total_base_lesson_fee_jpy,
    v_preview.total_aircon_fee_jpy,
    v_preview.total_fee_jpy,
    v_preview.bill_amount_jpy,
    jsonb_array_length(v_preview.candidates);
  IF v_preview.feature_state <> 'validation_preview_only'
     OR v_preview.candidate_count <> 30
     OR v_preview.total_lesson_count <> 35
     OR v_preview.total_duration_hours <> 65
     OR v_preview.total_base_lesson_fee_jpy <> 650000
     OR v_preview.total_aircon_fee_jpy <> 0
     OR v_preview.total_fee_jpy <> 650000
     OR v_preview.bill_amount_jpy <> 650000
     OR jsonb_array_length(v_preview.candidates) <> 30 THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_TARGET_CALL_MISMATCH';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 654
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_lesson_records row_value)
          <> '9a787d2819b24fe4dece792b55b35ba5'
     OR (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_tuition_bills row_value)
          <> 'b91c381ea7c42d8dc60e8a6af189f86a'
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_income_records row_value)
          <> '3ee88b3e883359e819a93d80ea0204b2'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_tuition_bill_lessons row_value)
          <> 'ff626f1677571c76406b4bc7b5122391'
     OR (SELECT count(*) FROM public.school_teacher_wage_lock_details) <> 556
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_teacher_wage_lock_details row_value)
          <> '6d68749bc1f0fbb908d2dfdb43dcc774' THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_BUSINESS_DATA_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked'))
       <> 3 THEN
    RAISE EXCEPTION 'R2_E_PREVIEW_FIX_R0_CHANGED';
  END IF;
END
$verify$;

SELECT
  md5(pg_get_functiondef(
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
  )) AS corrected_definition_md5,
  preview_row.feature_state,
  preview_row.candidate_count,
  preview_row.total_lesson_count,
  preview_row.total_duration_hours,
  preview_row.total_base_lesson_fee_jpy,
  preview_row.total_aircon_fee_jpy,
  preview_row.total_fee_jpy,
  preview_row.bill_amount_jpy,
  jsonb_array_length(preview_row.candidates) AS candidate_json_count
FROM public.school_get_student_tuition_validation_preview_details(
  '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.05
) preview_row;

\if :r2_e_preview_fix_commit
  \echo 'R2_E_PREVIEW_FIX_COMMIT'
  COMMIT;
\else
  \echo 'R2_E_PREVIEW_FIX_ROLLBACK'
  ROLLBACK;
\endif
