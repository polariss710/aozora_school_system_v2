-- School V2 R2-F-F: venue-aware, whole-hour planned aircon policy.
-- Required psql variable: r2_f_f_policy_commit=0 rehearsal or 1 deploy.
-- Configuration writes are limited to two venue-master rows. No lesson,
-- settlement, bill, income, identity, relation, wage, account or Cash row is updated.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_f_policy_commit}
\else
  \echo 'R2_F_F_POLICY_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

\echo 'R2_F_F_POLICY_BEGIN'
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='240s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,numeric,numeric,integer)'::regprocedure
     ))<>'842a2000b6a7aaa64750a0577877181b'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))<>'9124204f047c87b231f78e20e1fd73b6'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'::regprocedure
     ))<>'e79f8b9d562837417d7daf588f2a340b'
     OR md5(pg_get_functiondef(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
     ))<>'3ec44f91bce3493c15663d59226e1dd1'
     OR md5(pg_get_functiondef(
       'public.school_validate_tuition_bill_lessons_for_bill(uuid)'::regprocedure
     ))<>'3f8141bfe8541c984e157a337f61813b' THEN
    RAISE EXCEPTION 'R2_F_F_POLICY_PROTECTED_FUNCTION_DRIFT';
  END IF;
  IF to_regprocedure(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,text,uuid,text,numeric,numeric,integer)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'R2_F_F_POLICY_V2_CALCULATOR_ALREADY_EXISTS';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_venues)<>0 THEN
    RAISE EXCEPTION 'R2_F_F_POLICY_VENUE_CONFIG_BASELINE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.school_student_tuition_bill_lessons
      WHERE aircon_fee_jpy_snapshot>0)<>0 THEN
    RAISE EXCEPTION 'R2_F_F_POLICY_HISTORICAL_BILLED_AIRCON_REQUIRES_REVIEW';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id='6c70c4c1-1895-453d-b9b0-591e9f004f86'
      AND lesson.lesson_type='planned' AND lesson.status='planned'
      AND lesson.lesson_date=DATE '2026-08-08'
      AND lesson.lesson_delivery_mode='onsite'
      AND lesson.lesson_venue='Regus办公室'
      AND lesson.duration_hours=2
      AND lesson.aircon_unit_price_jpy_snapshot=330
      AND lesson.aircon_billable_hours_snapshot=2
      AND lesson.aircon_fee_jpy=660
      AND lesson.base_lesson_fee_jpy=17000
      AND lesson.lesson_total_fee_jpy=17660
      AND lesson.fee_calculation_version='planned_weekend_aircon_v1'
  ) THEN
    RAISE EXCEPTION 'R2_F_F_POLICY_SUN_CONFIRMED_AIRCON_FACT_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F_POLICY_GATE_BASELINE_DRIFT';
  END IF;
END
$preflight$;

\echo 'R2_F_F_POLICY_CONFIGURE_VENUES'
INSERT INTO public.school_lesson_venues(
  id,code,display_name,delivery_mode,aircon_eligible,
  effective_from,effective_to,is_active,created_by
) VALUES
  ('f2ff0000-0000-4000-8000-202608010001','Regus办公室','Regus办公室',
   'onsite',true,DATE '2026-08-01',NULL,true,NULL),
  ('f2ff0000-0000-4000-8000-202608010002','Regus公共区','Regus公共区',
   'onsite',false,DATE '2026-08-01',NULL,true,NULL);

COMMENT ON TABLE public.school_lesson_venues IS
  'Structured lesson venue master. R2-F-F uses exact ID/code plus aircon_eligible and effective dates; fuzzy venue-name matching is forbidden.';
COMMENT ON COLUMN public.school_lesson_venues.aircon_eligible IS
  'True only when this configured onsite venue may accrue planned weekend aircon fees under the active policy.';

\echo 'R2_F_F_POLICY_REPLACE_CONSTRAINTS'
ALTER TABLE public.school_lesson_records
  DROP CONSTRAINT school_lesson_records_r2_e_aircon_context_check,
  ADD CONSTRAINT school_lesson_records_r2_e_aircon_context_check CHECK (
    fee_calculation_version IS NULL
    OR (
      lesson_type='planned'
      AND aircon_rate_id IS NULL
      AND base_lesson_fee_jpy=lesson_fee
      AND lesson_total_fee_jpy=base_lesson_fee_jpy+aircon_fee_jpy
      AND (
        (
          fee_calculation_version='planned_weekend_aircon_v1'
          AND aircon_billable_hours_snapshot=duration_hours
          AND aircon_fee_jpy=CASE
            WHEN student_settlement_month>='2026-08'
             AND lesson_date IS NOT NULL
             AND extract(isodow FROM lesson_date) IN (6,7)
            THEN aircon_unit_price_jpy_snapshot*duration_hours
            ELSE 0
          END
        )
        OR (
          fee_calculation_version='planned_weekend_venue_whole_hour_aircon_v2'
          AND aircon_billable_hours_snapshot=trunc(aircon_billable_hours_snapshot)
          AND aircon_billable_hours_snapshot BETWEEN 0 AND floor(duration_hours)
          AND aircon_fee_jpy=
            aircon_unit_price_jpy_snapshot*aircon_billable_hours_snapshot
        )
      )
    )
  ) NOT VALID;
ALTER TABLE public.school_lesson_records
  VALIDATE CONSTRAINT school_lesson_records_r2_e_aircon_context_check;

ALTER TABLE public.school_student_tuition_bill_lessons
  DROP CONSTRAINT school_tuition_bill_lessons_r2_f_b_fee_context_check,
  ADD CONSTRAINT school_tuition_bill_lessons_r2_f_b_fee_context_check CHECK (
    fee_calculation_version_snapshot IS NULL
    OR (
      aircon_rate_id_snapshot IS NULL
      AND lesson_fee_jpy_snapshot=
        base_lesson_fee_jpy_snapshot+aircon_fee_jpy_snapshot
      AND (
        (
          fee_calculation_version_snapshot IN (
            'planned_weekend_aircon_v1',
            'planned_weekend_venue_whole_hour_aircon_v2'
          )
          AND aircon_billable_hours_snapshot=
            trunc(aircon_billable_hours_snapshot)
          AND aircon_fee_jpy_snapshot=
            aircon_unit_price_jpy_snapshot*aircon_billable_hours_snapshot
        )
        OR (
          fee_calculation_version_snapshot='legacy_base_only'
          AND aircon_unit_price_jpy_snapshot=0
          AND aircon_billable_hours_snapshot=0
          AND aircon_fee_jpy_snapshot=0
        )
      )
    )
  ) NOT VALID;
ALTER TABLE public.school_student_tuition_bill_lessons
  VALIDATE CONSTRAINT school_tuition_bill_lessons_r2_f_b_fee_context_check;

\echo 'R2_F_F_POLICY_CREATE_V2_CALCULATOR'
CREATE FUNCTION public.school_r2_e_calculate_planned_aircon_fee(
  p_lesson_date date,
  p_student_settlement_month text,
  p_lesson_delivery_mode text,
  p_lesson_venue_id uuid,
  p_lesson_venue_code text,
  p_planned_duration_hours numeric,
  p_base_lesson_fee_jpy numeric,
  p_aircon_rate_jpy_per_hour integer
)
RETURNS TABLE(
  base_lesson_fee_jpy numeric,
  aircon_charge_status text,
  aircon_rate_jpy_per_hour integer,
  aircon_billable_hours numeric,
  aircon_fee_jpy numeric,
  lesson_total_fee_jpy numeric,
  aircon_policy_version text,
  fee_block_reason_code text
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog,public
AS $function$
DECLARE
  v_duration numeric:=p_planned_duration_hours;
  v_whole_hours numeric;
  v_rate integer:=coalesce(p_aircon_rate_jpy_per_hour,0);
  v_mode text:=lower(nullif(btrim(coalesce(p_lesson_delivery_mode,'')),''));
  v_venue_code text:=nullif(btrim(coalesce(p_lesson_venue_code,'')),'');
  v_venue public.school_lesson_venues%ROWTYPE;
BEGIN
  IF v_duration IS NULL OR v_duration<=0 THEN
    RAISE EXCEPTION 'R2_E_PLANNED_DURATION_INVALID';
  END IF;
  IF p_base_lesson_fee_jpy IS NULL OR p_base_lesson_fee_jpy<0 THEN
    RAISE EXCEPTION 'R2_E_BASE_LESSON_FEE_INVALID';
  END IF;
  IF v_rate<0 THEN RAISE EXCEPTION 'R2_E_AIRCON_RATE_INVALID'; END IF;
  IF p_student_settlement_month IS NOT NULL
     AND p_student_settlement_month!~'^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R2_E_STUDENT_SETTLEMENT_MONTH_INVALID';
  END IF;

  v_whole_hours:=floor(v_duration);
  base_lesson_fee_jpy:=p_base_lesson_fee_jpy;
  aircon_rate_jpy_per_hour:=v_rate;
  aircon_billable_hours:=0;
  aircon_fee_jpy:=0;
  aircon_policy_version:='planned_weekend_venue_whole_hour_aircon_v2';
  aircon_charge_status:='not_applicable';

  IF p_lesson_date IS NULL THEN
    fee_block_reason_code:='AIRCON_DATE_REQUIRED';
  ELSIF p_student_settlement_month IS NULL
        OR p_student_settlement_month<'2026-08' THEN
    fee_block_reason_code:='AIRCON_BEFORE_POLICY_MONTH';
  ELSIF extract(isodow FROM p_lesson_date) NOT IN (6,7) THEN
    fee_block_reason_code:='AIRCON_WEEKDAY';
  ELSIF v_mode IS DISTINCT FROM 'onsite' THEN
    fee_block_reason_code:='AIRCON_NOT_ONSITE';
  ELSE
    SELECT venue.* INTO v_venue
    FROM public.school_lesson_venues venue
    WHERE venue.is_active
      AND venue.delivery_mode='onsite'
      AND p_lesson_date>=venue.effective_from
      AND (venue.effective_to IS NULL OR p_lesson_date<venue.effective_to)
      AND (
        (p_lesson_venue_id IS NOT NULL
         AND venue.id=p_lesson_venue_id
         AND (v_venue_code IS NULL OR venue.code=v_venue_code))
        OR
        (p_lesson_venue_id IS NULL
         AND v_venue_code IS NOT NULL
         AND venue.code=v_venue_code)
      )
    ORDER BY CASE WHEN venue.id=p_lesson_venue_id THEN 0 ELSE 1 END,venue.id
    LIMIT 1;

    IF NOT FOUND OR v_venue.aircon_eligible IS DISTINCT FROM true THEN
      fee_block_reason_code:='AIRCON_VENUE_NOT_ELIGIBLE';
    ELSIF v_whole_hours<=0 THEN
      fee_block_reason_code:='AIRCON_NO_WHOLE_HOUR';
    ELSE
      aircon_billable_hours:=v_whole_hours;
      IF v_rate=0 THEN
        aircon_charge_status:='configured_zero';
        fee_block_reason_code:='AIRCON_RATE_ZERO';
      ELSE
        aircon_charge_status:='calculated';
        aircon_fee_jpy:=v_rate*v_whole_hours;
        fee_block_reason_code:=NULL;
      END IF;
    END IF;
  END IF;

  lesson_total_fee_jpy:=base_lesson_fee_jpy+aircon_fee_jpy;
  RETURN NEXT;
END
$function$;

REVOKE ALL ON FUNCTION public.school_r2_e_calculate_planned_aircon_fee(
  date,text,text,uuid,text,numeric,numeric,integer
) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION public.school_r2_e_calculate_planned_aircon_fee(
  date,text,text,uuid,text,numeric,numeric,integer
) IS
  'R2-F-F authoritative planned aircon v2: exact active venue ID/code config, onsite weekend, saved nonnegative rate, and floor(planned duration). Actual facts are never read.';

CREATE OR REPLACE FUNCTION public.school_r2_e_calculate_planned_aircon_fee(
  p_lesson_date date,p_student_settlement_month text,
  p_planned_duration_hours numeric,p_base_lesson_fee_jpy numeric,
  p_aircon_rate_jpy_per_hour integer
)
RETURNS TABLE(
  base_lesson_fee_jpy numeric,aircon_charge_status text,
  aircon_rate_jpy_per_hour integer,aircon_billable_hours numeric,
  aircon_fee_jpy numeric,lesson_total_fee_jpy numeric,
  aircon_policy_version text,fee_block_reason_code text
)
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path=pg_catalog,public
AS $function$
BEGIN
  RAISE EXCEPTION 'R2_F_F_AIRCON_VENUE_CONTEXT_REQUIRED';
END
$function$;
REVOKE ALL ON FUNCTION public.school_r2_e_calculate_planned_aircon_fee(
  date,text,numeric,numeric,integer
) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION public.school_r2_e_calculate_planned_aircon_fee(
  date,text,numeric,numeric,integer
) IS
  'R2-F-F permanently blocked compatibility overload: charging without explicit delivery and structured venue context is forbidden.';

\echo 'R2_F_F_POLICY_REPLACE_PLANNED_GUARD'
CREATE OR REPLACE FUNCTION public.school_enforce_r2_e_planned_aircon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
DECLARE
  v_result record;
  v_requested_rate integer;
  v_charge_fields_changed boolean;
  v_charge_locked boolean;
  v_is_legacy_charge boolean;
  v_has_relation boolean;
  v_has_bill_snapshot boolean;
  v_is_billed boolean;
  v_charge_week_start date;
BEGIN
  IF NEW.lesson_type IS DISTINCT FROM 'planned' THEN
    IF num_nonnulls(
      NEW.base_lesson_fee_jpy,NEW.aircon_charge_status,NEW.aircon_rate_id,
      NEW.aircon_unit_price_jpy_snapshot,NEW.aircon_billable_hours_snapshot,
      NEW.aircon_fee_jpy,NEW.aircon_calculated_at,NEW.fee_calculation_version,
      NEW.fee_block_reason_code,NEW.fee_components_frozen_at,
      NEW.lesson_total_fee_jpy
    )<>0 THEN
      RAISE EXCEPTION 'R2_E_ACTUAL_AIRCON_FIELDS_FORBIDDEN';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP='INSERT' THEN
    IF num_nonnulls(
      NEW.base_lesson_fee_jpy,NEW.aircon_charge_status,NEW.aircon_rate_id,
      NEW.aircon_billable_hours_snapshot,NEW.aircon_fee_jpy,
      NEW.aircon_calculated_at,NEW.fee_calculation_version,
      NEW.fee_block_reason_code,NEW.fee_components_frozen_at,
      NEW.lesson_total_fee_jpy
    )<>0 THEN
      RAISE EXCEPTION 'R2_E_DIRECT_AUTHORITY_FIELDS_FORBIDDEN';
    END IF;
  ELSE
    v_charge_fields_changed:=
      NEW.base_lesson_fee_jpy IS DISTINCT FROM OLD.base_lesson_fee_jpy
      OR NEW.aircon_charge_status IS DISTINCT FROM OLD.aircon_charge_status
      OR NEW.aircon_rate_id IS DISTINCT FROM OLD.aircon_rate_id
      OR NEW.aircon_billable_hours_snapshot IS DISTINCT FROM OLD.aircon_billable_hours_snapshot
      OR NEW.aircon_fee_jpy IS DISTINCT FROM OLD.aircon_fee_jpy
      OR NEW.aircon_calculated_at IS DISTINCT FROM OLD.aircon_calculated_at
      OR NEW.fee_calculation_version IS DISTINCT FROM OLD.fee_calculation_version
      OR NEW.fee_block_reason_code IS DISTINCT FROM OLD.fee_block_reason_code
      OR NEW.fee_components_frozen_at IS DISTINCT FROM OLD.fee_components_frozen_at
      OR NEW.lesson_total_fee_jpy IS DISTINCT FROM OLD.lesson_total_fee_jpy;
    IF v_charge_fields_changed THEN
      RAISE EXCEPTION 'R2_E_DIRECT_AUTHORITY_FIELDS_FORBIDDEN';
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.school_legacy_planned_settlement_evidence evidence
      WHERE evidence.planned_lesson_id=OLD.id) INTO v_is_legacy_charge;
    SELECT EXISTS(SELECT 1 FROM public.school_student_tuition_bill_lessons relation
      WHERE relation.planned_lesson_id=OLD.id) INTO v_has_relation;
    SELECT EXISTS(SELECT 1 FROM public.school_student_tuition_bills bill
      WHERE (bill.source_snapshot->'planned_lesson_ids')?OLD.id::text)
      INTO v_has_bill_snapshot;
    v_is_billed:=v_is_legacy_charge OR v_has_relation OR v_has_bill_snapshot;

    IF v_is_billed THEN
      SELECT min(relation.week_start_date_snapshot) INTO v_charge_week_start
      FROM public.school_student_tuition_bill_lessons relation
      WHERE relation.planned_lesson_id=OLD.id;
      v_charge_week_start:=coalesce(
        v_charge_week_start,date_trunc('week',OLD.lesson_date::timestamp)::date
      );
      IF NEW.lesson_type IS DISTINCT FROM OLD.lesson_type
         OR NEW.planned_lesson_id IS DISTINCT FROM OLD.planned_lesson_id
         OR NEW.student_id IS DISTINCT FROM OLD.student_id
         OR NEW.business_entity_id IS DISTINCT FROM OLD.business_entity_id
         OR NEW.subject_id IS DISTINCT FROM OLD.subject_id
         OR NEW.year_month IS DISTINCT FROM OLD.year_month
         OR NEW.billing_month IS DISTINCT FROM OLD.billing_month
         OR NEW.billing_week_start_date IS DISTINCT FROM OLD.billing_week_start_date
         OR NEW.student_settlement_month IS DISTINCT FROM OLD.student_settlement_month
         OR NEW.billing_month_source IS DISTINCT FROM OLD.billing_month_source
         OR NEW.billing_month_decided_at IS DISTINCT FROM OLD.billing_month_decided_at
         OR NEW.lesson_count IS DISTINCT FROM OLD.lesson_count
         OR NEW.duration_hours IS DISTINCT FROM OLD.duration_hours
         OR NEW.unit_price IS DISTINCT FROM OLD.unit_price
         OR NEW.lesson_fee IS DISTINCT FROM OLD.lesson_fee
         OR NEW.is_billable IS DISTINCT FROM OLD.is_billable
         OR NEW.lesson_delivery_mode IS DISTINCT FROM OLD.lesson_delivery_mode
         OR NEW.lesson_venue IS DISTINCT FROM OLD.lesson_venue
         OR NEW.lesson_venue_id IS DISTINCT FROM OLD.lesson_venue_id
         OR NEW.aircon_unit_price_jpy_snapshot IS DISTINCT FROM OLD.aircon_unit_price_jpy_snapshot THEN
        RAISE EXCEPTION 'R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE';
      END IF;
      IF NEW.lesson_date<v_charge_week_start
         OR NEW.lesson_date>v_charge_week_start+6 THEN
        RAISE EXCEPTION 'R2_F_E_BILLED_PLANNED_DATE_OUTSIDE_CHARGE_WEEK';
      END IF;
      IF NEW.status IS DISTINCT FROM OLD.status
         AND NOT (OLD.status='planned' AND NEW.status='pending_makeup') THEN
        RAISE EXCEPTION 'R2_F_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN';
      END IF;
      RETURN NEW;
    END IF;

    IF NEW.aircon_unit_price_jpy_snapshot IS DISTINCT FROM OLD.aircon_unit_price_jpy_snapshot
       OR NEW.lesson_date IS DISTINCT FROM OLD.lesson_date
       OR NEW.duration_hours IS DISTINCT FROM OLD.duration_hours
       OR NEW.lesson_fee IS DISTINCT FROM OLD.lesson_fee
       OR NEW.student_settlement_month IS DISTINCT FROM OLD.student_settlement_month
       OR NEW.lesson_delivery_mode IS DISTINCT FROM OLD.lesson_delivery_mode
       OR NEW.lesson_venue IS DISTINCT FROM OLD.lesson_venue
       OR NEW.lesson_venue_id IS DISTINCT FROM OLD.lesson_venue_id THEN
      SELECT EXISTS(
        SELECT 1 FROM public.school_student_monthly_settlements settlement
        WHERE settlement.student_id=OLD.student_id
          AND settlement.business_entity_id IS NOT DISTINCT FROM OLD.business_entity_id
          AND settlement.year_month=coalesce(OLD.student_settlement_month,OLD.year_month)
          AND settlement.settlement_status='locked'
      ) OR OLD.fee_components_frozen_at IS NOT NULL
      INTO v_charge_locked;
      IF v_charge_locked THEN
        RAISE EXCEPTION 'R2_E_BILLED_OR_LOCKED_PLANNED_CHARGE_IMMUTABLE';
      END IF;
    END IF;
  END IF;

  IF TG_OP='UPDATE'
     AND OLD.fee_calculation_version IS NULL
     AND NEW.aircon_unit_price_jpy_snapshot IS NULL THEN
    RETURN NEW;
  END IF;

  v_requested_rate:=coalesce(NEW.aircon_unit_price_jpy_snapshot,0);
  SELECT * INTO STRICT v_result
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    NEW.lesson_date,NEW.student_settlement_month,
    NEW.lesson_delivery_mode,NEW.lesson_venue_id,NEW.lesson_venue,
    NEW.duration_hours,NEW.lesson_fee,v_requested_rate
  );
  NEW.base_lesson_fee_jpy:=v_result.base_lesson_fee_jpy;
  NEW.aircon_charge_status:=v_result.aircon_charge_status;
  NEW.aircon_rate_id:=NULL;
  NEW.aircon_unit_price_jpy_snapshot:=v_result.aircon_rate_jpy_per_hour;
  NEW.aircon_billable_hours_snapshot:=v_result.aircon_billable_hours;
  NEW.aircon_fee_jpy:=v_result.aircon_fee_jpy;
  NEW.aircon_calculated_at:=statement_timestamp();
  NEW.fee_calculation_version:=v_result.aircon_policy_version;
  NEW.fee_block_reason_code:=v_result.fee_block_reason_code;
  NEW.lesson_total_fee_jpy:=v_result.lesson_total_fee_jpy;
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION public.school_enforce_r2_e_planned_aircon()
  FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION public.school_enforce_r2_e_planned_aircon() IS
  'R2-F-F planned fee authority. All table writers share exact venue-aware whole-hour v2 calculation; billed charge facts remain frozen while R2-F-E fulfilment transitions stay intact.';

\echo 'R2_F_F_POLICY_REPLACE_CANDIDATE_READER'
CREATE OR REPLACE FUNCTION public.school_list_student_tuition_charge_candidates(
  p_student_id uuid,p_business_entity_id uuid,p_billing_month text,
  p_include_excluded boolean DEFAULT false
)
RETURNS TABLE(
  planned_lesson_id uuid,student_id uuid,business_entity_id uuid,
  candidate_billing_month text,billing_week_start_date date,lesson_date date,
  lesson_count integer,duration_hours numeric,unit_price numeric,
  base_lesson_fee_jpy numeric,aircon_rate_jpy_per_hour integer,
  aircon_fee_jpy numeric,lesson_total_fee_jpy numeric,
  aircon_charge_status text,aircon_policy_version text,candidate_status text,
  exclusion_reason text,complete_row_hash text
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
  SELECT candidate.planned_lesson_id,candidate.student_id,
    candidate.business_entity_id,candidate.candidate_billing_month,
    lesson.billing_week_start_date,candidate.lesson_date,candidate.lesson_count,
    candidate.duration_hours,candidate.unit_price,candidate.lesson_fee,
    coalesce(lesson.aircon_unit_price_jpy_snapshot,0),
    coalesce(lesson.aircon_fee_jpy,0),
    coalesce(lesson.lesson_total_fee_jpy,candidate.lesson_fee),
    coalesce(lesson.aircon_charge_status,'legacy_base_only'),
    lesson.fee_calculation_version,candidate.candidate_status,
    candidate.exclusion_reason,
    md5(concat_ws('|',candidate.complete_row_hash,candidate.lesson_fee::text,
      coalesce(lesson.aircon_unit_price_jpy_snapshot,0)::text,
      coalesce(lesson.aircon_billable_hours_snapshot,0)::text,
      coalesce(lesson.aircon_fee_jpy,0)::text,
      coalesce(lesson.lesson_total_fee_jpy,candidate.lesson_fee)::text,
      coalesce(lesson.fee_calculation_version,'legacy_base_only'),
      coalesce(lesson.lesson_delivery_mode,''),
      coalesce(lesson.lesson_venue_id::text,''),coalesce(lesson.lesson_venue,'')))
  FROM public.school_list_student_tuition_candidates(
    p_student_id,p_business_entity_id,p_billing_month,p_include_excluded
  ) candidate
  JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
  WHERE lesson.fee_calculation_version IS NULL
     OR (
       lesson.fee_calculation_version IN (
         'planned_weekend_aircon_v1',
         'planned_weekend_venue_whole_hour_aircon_v2'
       )
       AND lesson.base_lesson_fee_jpy=candidate.lesson_fee
       AND lesson.lesson_total_fee_jpy=
         lesson.base_lesson_fee_jpy+lesson.aircon_fee_jpy
       AND lesson.aircon_fee_jpy=
         lesson.aircon_unit_price_jpy_snapshot*
         lesson.aircon_billable_hours_snapshot
     )
  ORDER BY lesson.billing_week_start_date,lesson.lesson_date,lesson.id;
$function$;
REVOKE ALL ON FUNCTION public.school_list_student_tuition_charge_candidates(
  uuid,uuid,text,boolean
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.school_list_student_tuition_charge_candidates(
  uuid,uuid,text,boolean
) TO service_role;
COMMENT ON FUNCTION public.school_list_student_tuition_charge_candidates(
  uuid,uuid,text,boolean
) IS
  'R2-F-F canonical reader: legacy base-only, frozen v1, and exact-venue whole-hour v2 bundles only; complete row evidence includes venue, billable hours and policy.';

\echo 'R2_F_F_POLICY_HARDEN_SNAPSHOT_AND_RELATION_VALIDATOR'
DO $patch_snapshot$
DECLARE
  v_definition text;
  v_replaced text;
  v_old text:='coalesce(detail.aircon_policy_version,''legacy_base_only'')<>''planned_weekend_aircon_v1''';
  v_new text:='coalesce(detail.aircon_policy_version,''legacy_base_only'') NOT IN (''planned_weekend_aircon_v1'',''planned_weekend_venue_whole_hour_aircon_v2'')';
BEGIN
  SELECT pg_get_functiondef(
    'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
  ) INTO v_definition;
  IF md5(v_definition)<>'3ec44f91bce3493c15663d59226e1dd1'
     OR position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_F_SNAPSHOT_SOURCE_DRIFT';
  END IF;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition OR position(v_new IN v_replaced)=0 THEN
    RAISE EXCEPTION 'R2_F_F_SNAPSHOT_PATCH_FAILED';
  END IF;
  EXECUTE v_replaced;
END
$patch_snapshot$;

DO $patch_validator$
DECLARE
  v_definition text;
  v_replaced text;
  v_old text:=$old$IS DISTINCT FROM rel.fee_calculation_version_snapshot
$old$;
  v_new text:=$new$IS DISTINCT FROM rel.fee_calculation_version_snapshot
        OR (rel.fee_calculation_version_snapshot IN (
              'planned_weekend_aircon_v1',
              'planned_weekend_venue_whole_hour_aircon_v2'
            )
            AND rel.aircon_fee_jpy_snapshot IS DISTINCT FROM
              rel.aircon_unit_price_jpy_snapshot*rel.aircon_billable_hours_snapshot)
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_validate_tuition_bill_lessons_for_bill(uuid)'::regprocedure
  ) INTO v_definition;
  IF md5(v_definition)<>'3f8141bfe8541c984e157a337f61813b'
     OR position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_F_RELATION_VALIDATOR_SOURCE_DRIFT';
  END IF;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition OR position('planned_weekend_venue_whole_hour_aircon_v2' IN v_replaced)=0 THEN
    RAISE EXCEPTION 'R2_F_F_RELATION_VALIDATOR_PATCH_FAILED';
  END IF;
  EXECUTE v_replaced;
END
$patch_validator$;

COMMENT ON FUNCTION public.school_build_student_tuition_generation_snapshot(uuid,text,numeric) IS
  'R2-F-F generation snapshot: canonical line and generation manifests cover v1/v2 aircon rate, whole billable hours, fee, venue and source evidence.';
COMMENT ON FUNCTION public.school_validate_tuition_bill_lessons_for_bill(uuid) IS
  'R2-F-F atomic relation validator: JSON, normalized relation, complete/candidate hashes, generation manifest and v1/v2 aircon multiplication must agree.';

\echo 'R2_F_F_POLICY_VERIFY'
DO $verify$
DECLARE
  v_calc record;
  v_preview record;
BEGIN
  IF (SELECT count(*) FROM public.school_lesson_venues
      WHERE code='Regus办公室' AND aircon_eligible AND delivery_mode='onsite'
        AND is_active AND effective_from=DATE '2026-08-01')<>1
     OR (SELECT count(*) FROM public.school_lesson_venues
      WHERE code='Regus公共区' AND NOT aircon_eligible AND delivery_mode='onsite'
        AND is_active AND effective_from=DATE '2026-08-01')<>1 THEN
    RAISE EXCEPTION 'R2_F_F_VENUE_CONFIG_VERIFY_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-08','2026-08','onsite',NULL,'Regus办公室',2,17000,330
  );
  IF v_calc.aircon_billable_hours<>2 OR v_calc.aircon_fee_jpy<>660
     OR v_calc.lesson_total_fee_jpy<>17660
     OR v_calc.aircon_policy_version<>'planned_weekend_venue_whole_hour_aircon_v2' THEN
    RAISE EXCEPTION 'R2_F_F_POLICY_EXAMPLE_VERIFY_FAILED';
  END IF;
  SELECT * INTO STRICT v_preview
  FROM public.school_get_student_tuition_validation_preview_details(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.042
  );
  IF v_preview.candidate_count<>22 OR v_preview.total_lesson_count<>24
     OR v_preview.total_duration_hours<>44
     OR v_preview.total_base_lesson_fee_jpy<>374000
     OR v_preview.total_aircon_fee_jpy<>660
     OR v_preview.total_fee_jpy<>374660
     OR v_preview.billing_amount_cny<>15735.72 THEN
    RAISE EXCEPTION 'R2_F_F_POLICY_SUN_PREVIEW_DRIFT';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id='6c70c4c1-1895-453d-b9b0-591e9f004f86'
      AND lesson.aircon_fee_jpy=660
      AND lesson.fee_calculation_version='planned_weekend_aircon_v1'
  ) THEN
    RAISE EXCEPTION 'R2_F_F_POLICY_SUN_ROW_WAS_MODIFIED';
  END IF;
END
$verify$;

\if :r2_f_f_policy_commit
  \echo 'R2_F_F_POLICY_COMMIT'
  COMMIT;
\else
  \echo 'R2_F_F_POLICY_ROLLBACK'
  ROLLBACK;
\endif
