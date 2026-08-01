-- School V2 2026-08: align tuition preview/generate with the approved carryover authority.
-- Required psql variable: tuition_202608_snapshot_commit=0 rehearsal or 1 deploy.
-- This file replaces one reader/snapshot function only. It writes no lesson, bill,
-- income, settlement, wage, account, Cash, or tuition relation business row.

\set ON_ERROR_STOP on
\pset pager off

\if :{?tuition_202608_snapshot_commit}
\else
  \echo 'TUITION_202608_SNAPSHOT_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
     ))<>'bd1e8aebbe3038ff7423a1f8868b9220' THEN
    RAISE EXCEPTION 'TUITION_202608_SNAPSHOT_SOURCE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'TUITION_202608_SNAPSHOT_GATE_BASELINE_DRIFT';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.school_build_student_tuition_generation_snapshot(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric
)
RETURNS TABLE (
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  carryover_evidence jsonb,
  candidate_count integer,
  total_lesson_count integer,
  total_duration_hours numeric,
  total_base_lesson_fee_jpy numeric,
  total_aircon_fee_jpy numeric,
  total_fee_jpy numeric,
  billing_exchange_rate numeric,
  billing_amount_cny numeric,
  candidate_uuid_md5 text,
  candidate_manifest_sha256 text,
  generation_manifest_sha256 text,
  candidates jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_student public.school_students%ROWTYPE;
  v_month text := nullif(pg_catalog.btrim(coalesce(p_billing_month,'')),'');
  v_previous_month text;
  v_previous_settlement public.school_student_monthly_settlements%ROWTYPE;
  v_locked_count integer;
  v_carryover numeric;
  v_carryover_evidence jsonb;
  v_carryover_evidence_sha text;
  v_count integer;
  v_distinct_count integer;
  v_lesson_count integer;
  v_hours numeric;
  v_base numeric;
  v_aircon numeric;
  v_total numeric;
  v_uuid_md5 text;
  v_candidate_manifest text;
  v_generation_manifest text;
  v_candidates jsonb;
  v_contract_valid boolean;
  v_amount_cny numeric;
BEGIN
  IF p_student_id IS NULL THEN RAISE EXCEPTION 'R2_F_B_STUDENT_REQUIRED'; END IF;
  IF v_month IS NULL OR v_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R2_F_B_BILLING_MONTH_INVALID';
  END IF;
  IF p_billing_exchange_rate IS NULL OR p_billing_exchange_rate <= 0 THEN
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

  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements settlement
    WHERE settlement.student_id=p_student_id
      AND settlement.business_entity_id=v_student.business_entity_id
      AND settlement.year_month=v_month
      AND settlement.settlement_status='locked'
  ) THEN
    RAISE EXCEPTION 'R2_F_B_TARGET_SETTLEMENT_LOCKED';
  END IF;

  v_previous_month := pg_catalog.to_char(
    (pg_catalog.to_date(v_month||'-01','YYYY-MM-DD')-interval '1 month')::date,
    'YYYY-MM'
  );

  SELECT count(*)::integer INTO v_locked_count
  FROM public.school_student_monthly_settlements settlement
  WHERE settlement.student_id=p_student_id
    AND settlement.business_entity_id=v_student.business_entity_id
    AND settlement.year_month=v_previous_month
    AND settlement.settlement_status='locked';
  IF v_locked_count > 1 THEN
    RAISE EXCEPTION 'R2_F_B_MULTIPLE_PREVIOUS_LOCKED_SETTLEMENTS';
  END IF;

  SELECT settlement.* INTO v_previous_settlement
  FROM public.school_student_monthly_settlements settlement
  WHERE settlement.student_id=p_student_id
    AND settlement.business_entity_id=v_student.business_entity_id
    AND settlement.year_month=v_previous_month
    AND settlement.settlement_status='locked'
  ORDER BY settlement.locked_at DESC NULLS LAST,
    settlement.updated_at DESC NULLS LAST,settlement.created_at DESC NULLS LAST
  LIMIT 1;

  IF FOUND THEN
    v_carryover := pg_catalog.round(coalesce(v_previous_settlement.carryover_amount_cny,0),2);
    v_carryover_evidence := jsonb_build_object(
      'mode','locked_settlement_v1',
      'authority','locked_previous_settlement_only',
      'settlement_month',v_previous_month,
      'settlement_id',v_previous_settlement.id,
      'settlement_status',v_previous_settlement.settlement_status,
      'locked_at',v_previous_settlement.locked_at,
      'updated_at',v_previous_settlement.updated_at,
      'carryover_amount_cny',v_carryover
    );
  ELSE
    v_carryover := 0;
    v_carryover_evidence := jsonb_build_object(
      'mode','zero_carryover_verified_v1',
      'authority','locked_previous_settlement_only',
      'settlement_month',v_previous_month,
      'locked_settlement_count',v_locked_count,
      'carryover_amount_cny',v_carryover
    );
  END IF;

  v_carryover_evidence_sha := encode(sha256(convert_to(v_carryover_evidence::text,'UTF8')),'hex');

  WITH candidate_rows AS MATERIALIZED (
    SELECT candidate.*,
      lesson.teacher_id,lesson.subject_id,lesson.updated_at AS source_updated_at,
      coalesce(lesson.aircon_billable_hours_snapshot,0)::numeric AS aircon_billable_hours,
      lesson.lesson_venue_id,lesson.lesson_venue AS lesson_venue_code
    FROM public.school_list_student_tuition_charge_candidates(
      p_student_id,v_student.business_entity_id,v_month,false
    ) candidate
    JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
  ), canonical_lines AS (
    SELECT detail.*,
      jsonb_build_object(
        'planned_lesson_id',detail.planned_lesson_id,
        'student_id',detail.student_id,
        'business_entity_id',detail.business_entity_id,
        'billing_month',detail.candidate_billing_month,
        'billing_week_start_date',detail.billing_week_start_date,
        'lesson_date',detail.lesson_date,
        'teacher_id',detail.teacher_id,
        'subject_id',detail.subject_id,
        'lesson_count',detail.lesson_count,
        'duration_hours',detail.duration_hours,
        'unit_price_jpy',detail.unit_price,
        'base_lesson_fee_jpy',detail.base_lesson_fee_jpy,
        'aircon_rate_jpy_per_hour',detail.aircon_rate_jpy_per_hour,
        'aircon_billable_hours',detail.aircon_billable_hours,
        'aircon_fee_jpy',detail.aircon_fee_jpy,
        'course_total_jpy',detail.lesson_total_fee_jpy,
        'fee_policy_version',coalesce(detail.aircon_policy_version,'legacy_base_only'),
        'aircon_charge_status',detail.aircon_charge_status,
        'lesson_venue_id',detail.lesson_venue_id,
        'lesson_venue_code',detail.lesson_venue_code,
        'source_lesson_updated_at',detail.source_updated_at,
        'complete_row_hash',detail.complete_row_hash
      ) AS canonical_line
    FROM candidate_rows detail
  ), hashed_lines AS (
    SELECT line.*,
      encode(sha256(convert_to(line.canonical_line::text,'UTF8')),'hex')
        AS candidate_line_hash
    FROM canonical_lines line
  ), aggregated AS (
    SELECT count(*)::integer AS candidate_count,
      count(DISTINCT detail.planned_lesson_id)::integer AS distinct_count,
      coalesce(sum(detail.lesson_count),0)::integer AS lesson_count,
      coalesce(sum(detail.duration_hours),0)::numeric AS hours,
      coalesce(sum(detail.base_lesson_fee_jpy),0)::numeric AS base_fee,
      coalesce(sum(detail.aircon_fee_jpy),0)::numeric AS aircon_fee,
      coalesce(sum(detail.lesson_total_fee_jpy),0)::numeric AS total_fee,
      md5(string_agg(detail.planned_lesson_id::text,',' ORDER BY detail.planned_lesson_id::text)) AS uuid_md5,
      encode(sha256(convert_to(
        string_agg(detail.candidate_line_hash,E'\n'
          ORDER BY detail.billing_week_start_date,detail.lesson_date,
          detail.planned_lesson_id)||E'\n','UTF8')),'hex') AS candidate_manifest,
      jsonb_agg(detail.canonical_line||jsonb_build_object(
        'candidate_line_hash',detail.candidate_line_hash
      ) ORDER BY detail.billing_week_start_date,detail.lesson_date,
        detail.planned_lesson_id) AS candidates,
      bool_and(detail.student_id=p_student_id
        AND detail.business_entity_id=v_student.business_entity_id
        AND detail.candidate_billing_month=v_month
        AND detail.billing_week_start_date IS NOT NULL
        AND extract(isodow FROM detail.billing_week_start_date)=1
        AND to_char(detail.billing_week_start_date,'YYYY-MM')=v_month
        AND detail.lesson_total_fee_jpy=detail.base_lesson_fee_jpy+detail.aircon_fee_jpy
        AND detail.aircon_rate_jpy_per_hour>=0
        AND detail.aircon_billable_hours>=0
        AND detail.aircon_fee_jpy>=0
        AND (coalesce(detail.aircon_policy_version,'legacy_base_only')<>'planned_weekend_aircon_v1'
             OR detail.aircon_fee_jpy=detail.aircon_rate_jpy_per_hour*detail.aircon_billable_hours)
      ) AS contract_valid
    FROM hashed_lines detail
  )
  SELECT aggregated.candidate_count,aggregated.distinct_count,
    aggregated.lesson_count,aggregated.hours,aggregated.base_fee,
    aggregated.aircon_fee,aggregated.total_fee,aggregated.uuid_md5,
    aggregated.candidate_manifest,aggregated.candidates,
    aggregated.contract_valid
  INTO v_count,v_distinct_count,v_lesson_count,v_hours,v_base,v_aircon,
    v_total,v_uuid_md5,v_candidate_manifest,v_candidates,v_contract_valid
  FROM aggregated;

  IF v_count IS NULL OR v_count<=0 THEN RAISE EXCEPTION 'R2_F_B_CANDIDATES_EMPTY'; END IF;
  IF v_count IS DISTINCT FROM v_distinct_count THEN RAISE EXCEPTION 'R2_F_B_DUPLICATE_CANDIDATE_UUID'; END IF;
  IF v_contract_valid IS DISTINCT FROM true OR v_total IS DISTINCT FROM v_base+v_aircon THEN
    RAISE EXCEPTION 'R2_F_B_CANDIDATE_CONTRACT_MISMATCH';
  END IF;

  v_amount_cny := round(v_total*p_billing_exchange_rate+v_carryover,2);
  IF v_amount_cny<=0 THEN RAISE EXCEPTION 'R2_F_B_BILLING_AMOUNT_INVALID'; END IF;

  v_generation_manifest := encode(sha256(convert_to(concat_ws('|',
    'student_tuition_atomic_generate_v1',p_student_id::text,
    v_student.business_entity_id::text,v_month,v_candidate_manifest,
    v_uuid_md5,v_count::text,v_lesson_count::text,v_hours::text,
    v_base::text,v_aircon::text,v_total::text,p_billing_exchange_rate::text,
    v_previous_month,coalesce(v_previous_settlement.id::text,'zero'),
    v_carryover::text,v_carryover_evidence_sha,v_amount_cny::text
  ),'UTF8')),'hex');

  RETURN QUERY SELECT p_student_id,v_student.business_entity_id,v_month,
    v_previous_month,v_previous_settlement.id,v_carryover,v_carryover_evidence,
    v_count,v_lesson_count,v_hours,v_base,v_aircon,v_total,
    p_billing_exchange_rate,v_amount_cny,v_uuid_md5,v_candidate_manifest,
    v_generation_manifest,v_candidates;
END
$function$;

REVOKE ALL ON FUNCTION public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)
  TO service_role;
COMMENT ON FUNCTION public.school_build_student_tuition_generation_snapshot(uuid,text,numeric) IS
  '2026-08 approved authority: canonical planned candidates define base tuition; only a locked previous settlement supplies carryover, and no locked row means zero. Unlocked settlement previews are never read.';

DO $verify$
DECLARE v_definition text;
BEGIN
  v_definition:=pg_get_functiondef(
    'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
  );
  IF position('locked_previous_settlement_only' IN v_definition)=0
     OR position('zero_carryover_verified_v1' IN v_definition)=0
     OR position('school_get_student_monthly_settlement_preview' IN v_definition)>0
     OR position('school_get_student_duration_overage_aggregate' IN v_definition)>0
     OR position('R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED' IN v_definition)>0 THEN
    RAISE EXCEPTION 'TUITION_202608_SNAPSHOT_AUTHORITY_VERIFY_FAILED';
  END IF;
END
$verify$;

SELECT md5(pg_get_functiondef(
  'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
)) AS target_snapshot_definition_md5;

\if :tuition_202608_snapshot_commit
  COMMIT;
  \echo 'TUITION_202608_SNAPSHOT_DEPLOYED'
\else
  ROLLBACK;
  \echo 'TUITION_202608_SNAPSHOT_REHEARSAL_ROLLED_BACK'
\endif
