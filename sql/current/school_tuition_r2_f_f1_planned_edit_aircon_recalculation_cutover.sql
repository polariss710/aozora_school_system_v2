-- School V2 R2-F-F1: recalculate every unbilled planned fee bundle on update.
-- Required psql variable: r2_f_f1_cutover_commit=0 rehearsal or 1 deploy.
-- Code-only DDL: replaces exactly one trigger function and writes no business rows.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_f1_cutover_commit}
\else
  \echo 'R2_F_F1_CUTOVER_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))<>'e7820acbf80b3e5b1c02bc3ad9664762' THEN
    RAISE EXCEPTION 'R2_F_F1_TRIGGER_BASELINE_DRIFT';
  END IF;
  IF position('R2_F_F_AIRCON_VENUE_CONTEXT_REQUIRED' IN pg_get_functiondef(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,numeric,numeric,integer)'::regprocedure
     ))=0
     OR md5(pg_get_functiondef(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,text,uuid,text,numeric,numeric,integer)'::regprocedure
     ))<>'533ead6b181d64aee88ec5674ae4e8b0' THEN
    RAISE EXCEPTION 'R2_F_F1_CALCULATOR_BASELINE_DRIFT';
  END IF;
END
$preflight$;

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
  'R2-F-F/F1 planned fee authority. Every unbilled planned update, including legacy NULL/zero bundles, uses exact venue-aware whole-hour v2 calculation; billed charge facts remain frozen while R2-F-E fulfilment transitions stay intact.';

DO $verify$
BEGIN
  IF position('OLD.fee_calculation_version IS NULL' IN pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))>0
     OR position('school_r2_e_calculate_planned_aircon_fee(' IN pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))=0
     OR position('NEW.lesson_venue_id' IN pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))=0 THEN
    RAISE EXCEPTION 'R2_F_F1_TRIGGER_REPLACEMENT_FAILED';
  END IF;
END
$verify$;

\if :r2_f_f1_cutover_commit
  COMMIT;
\else
  ROLLBACK;
\endif
