-- School V2 R2-F-E: lesson operations closure cutover.
-- Required psql variable:
--   r2_f_e_commit=0  same-byte rehearsal with explicit ROLLBACK
--   r2_f_e_commit=1  formal code-only DDL deployment with explicit COMMIT
--
-- This file performs code-only DDL. It never updates lesson, settlement,
-- tuition, income, wage, account, or Cash business rows.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_e_commit}
\else
  \echo 'R2_F_E_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

\echo 'R2_F_E_BEGIN'
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     )) <> '5aa64dfc7362184052f8051cc7929bf2' THEN
    RAISE EXCEPTION 'R2_F_E_R2_E_GUARD_DEFINITION_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> 'ca52667c94a86608b4ab712f543b04b1' THEN
    RAISE EXCEPTION 'R2_F_E_GUARDED_UPDATE_DEFINITION_DRIFT';
  END IF;
  IF to_regprocedure(
       'public.school_enforce_r2_f_e_actual_completion_date()'
     ) IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgrelid='public.school_lesson_records'::regclass
         AND tgname='trg_school_lesson_r2_f_e_actual_completion_date'
         AND NOT tgisinternal
     ) THEN
    RAISE EXCEPTION 'R2_F_E_ACTUAL_COMPLETION_GUARD_ALREADY_EXISTS';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_F_E_R0_DRIFT';
  END IF;
END
$preflight$;

\echo 'R2_F_E_REPLACE_PLANNED_CHARGE_GUARD'
CREATE OR REPLACE FUNCTION public.school_enforce_r2_e_planned_aircon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
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
         NEW.aircon_unit_price_jpy_snapshot,
         NEW.aircon_billable_hours_snapshot,NEW.aircon_fee_jpy,
         NEW.aircon_calculated_at,NEW.fee_calculation_version,
         NEW.fee_block_reason_code,NEW.fee_components_frozen_at,
         NEW.lesson_total_fee_jpy
       ) <> 0 THEN
      RAISE EXCEPTION 'R2_E_ACTUAL_AIRCON_FIELDS_FORBIDDEN';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF num_nonnulls(
         NEW.base_lesson_fee_jpy,NEW.aircon_charge_status,NEW.aircon_rate_id,
         NEW.aircon_billable_hours_snapshot,NEW.aircon_fee_jpy,
         NEW.aircon_calculated_at,NEW.fee_calculation_version,
         NEW.fee_block_reason_code,NEW.fee_components_frozen_at,
         NEW.lesson_total_fee_jpy
       ) <> 0 THEN
      RAISE EXCEPTION 'R2_E_DIRECT_AUTHORITY_FIELDS_FORBIDDEN';
    END IF;
  ELSE
    v_charge_fields_changed :=
      NEW.base_lesson_fee_jpy IS DISTINCT FROM OLD.base_lesson_fee_jpy
      OR NEW.aircon_charge_status IS DISTINCT FROM OLD.aircon_charge_status
      OR NEW.aircon_rate_id IS DISTINCT FROM OLD.aircon_rate_id
      OR NEW.aircon_billable_hours_snapshot
           IS DISTINCT FROM OLD.aircon_billable_hours_snapshot
      OR NEW.aircon_fee_jpy IS DISTINCT FROM OLD.aircon_fee_jpy
      OR NEW.aircon_calculated_at IS DISTINCT FROM OLD.aircon_calculated_at
      OR NEW.fee_calculation_version
           IS DISTINCT FROM OLD.fee_calculation_version
      OR NEW.fee_block_reason_code IS DISTINCT FROM OLD.fee_block_reason_code
      OR NEW.fee_components_frozen_at
           IS DISTINCT FROM OLD.fee_components_frozen_at
      OR NEW.lesson_total_fee_jpy IS DISTINCT FROM OLD.lesson_total_fee_jpy;
    IF v_charge_fields_changed THEN
      RAISE EXCEPTION 'R2_E_DIRECT_AUTHORITY_FIELDS_FORBIDDEN';
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM public.school_legacy_planned_settlement_evidence evidence
      WHERE evidence.planned_lesson_id=OLD.id
    ) INTO v_is_legacy_charge;
    SELECT EXISTS (
      SELECT 1
      FROM public.school_student_tuition_bill_lessons relation
      WHERE relation.planned_lesson_id=OLD.id
    ) INTO v_has_relation;
    SELECT EXISTS (
      SELECT 1
      FROM public.school_student_tuition_bills bill
      WHERE (bill.source_snapshot -> 'planned_lesson_ids') ? OLD.id::text
    ) INTO v_has_bill_snapshot;
    v_is_billed:=v_is_legacy_charge OR v_has_relation OR v_has_bill_snapshot;

    IF v_is_billed THEN
      SELECT min(relation.week_start_date_snapshot)
      INTO v_charge_week_start
      FROM public.school_student_tuition_bill_lessons relation
      WHERE relation.planned_lesson_id=OLD.id;
      v_charge_week_start:=coalesce(
        v_charge_week_start,
        date_trunc('week',OLD.lesson_date::timestamp)::date
      );

      IF NEW.lesson_type IS DISTINCT FROM OLD.lesson_type
         OR NEW.planned_lesson_id IS DISTINCT FROM OLD.planned_lesson_id
         OR NEW.student_id IS DISTINCT FROM OLD.student_id
         OR NEW.business_entity_id IS DISTINCT FROM OLD.business_entity_id
         OR NEW.subject_id IS DISTINCT FROM OLD.subject_id
         OR NEW.year_month IS DISTINCT FROM OLD.year_month
         OR NEW.billing_month IS DISTINCT FROM OLD.billing_month
         OR NEW.billing_week_start_date
              IS DISTINCT FROM OLD.billing_week_start_date
         OR NEW.student_settlement_month
              IS DISTINCT FROM OLD.student_settlement_month
         OR NEW.billing_month_source IS DISTINCT FROM OLD.billing_month_source
         OR NEW.billing_month_decided_at
              IS DISTINCT FROM OLD.billing_month_decided_at
         OR NEW.lesson_count IS DISTINCT FROM OLD.lesson_count
         OR NEW.duration_hours IS DISTINCT FROM OLD.duration_hours
         OR NEW.unit_price IS DISTINCT FROM OLD.unit_price
         OR NEW.lesson_fee IS DISTINCT FROM OLD.lesson_fee
         OR NEW.is_billable IS DISTINCT FROM OLD.is_billable
         OR NEW.aircon_unit_price_jpy_snapshot
              IS DISTINCT FROM OLD.aircon_unit_price_jpy_snapshot THEN
        RAISE EXCEPTION 'R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE';
      END IF;
      IF NEW.lesson_date < v_charge_week_start
         OR NEW.lesson_date > v_charge_week_start + 6 THEN
        RAISE EXCEPTION 'R2_F_E_BILLED_PLANNED_DATE_OUTSIDE_CHARGE_WEEK';
      END IF;
      IF NEW.status IS DISTINCT FROM OLD.status
         AND NOT (OLD.status='planned' AND NEW.status='pending_makeup') THEN
        RAISE EXCEPTION 'R2_F_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN';
      END IF;

      -- Teacher, lesson date/time inside the frozen charge week, and the single
      -- planned -> pending_makeup fulfilment transition are operational facts.
      -- All charge facts and DB fee snapshots above remain byte-for-byte frozen.
      RETURN NEW;
    END IF;

    IF NEW.aircon_unit_price_jpy_snapshot
         IS DISTINCT FROM OLD.aircon_unit_price_jpy_snapshot
       OR NEW.lesson_date IS DISTINCT FROM OLD.lesson_date
       OR NEW.duration_hours IS DISTINCT FROM OLD.duration_hours
       OR NEW.lesson_fee IS DISTINCT FROM OLD.lesson_fee
       OR NEW.student_settlement_month
            IS DISTINCT FROM OLD.student_settlement_month THEN
      SELECT
        EXISTS (
          SELECT 1
          FROM public.school_student_monthly_settlements settlement
          WHERE settlement.student_id=OLD.student_id
            AND settlement.business_entity_id
                  IS NOT DISTINCT FROM OLD.business_entity_id
            AND settlement.year_month
                  =coalesce(OLD.student_settlement_month,OLD.year_month)
            AND settlement.settlement_status='locked'
        )
        OR OLD.fee_components_frozen_at IS NOT NULL
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
    NEW.lesson_date,
    NEW.student_settlement_month,
    NEW.duration_hours,
    NEW.lesson_fee,
    v_requested_rate
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

COMMENT ON FUNCTION public.school_enforce_r2_e_planned_aircon() IS
  'R2-F-E charged planned guard: freezes tuition identity, attribution and fee facts while allowing teacher/time changes, schedule movement inside the frozen charge week, and planned to pending_makeup exactly once.';

\echo 'R2_F_E_PRESERVE_BILLED_PLANNED_STUDENT_MONTH'
DO $replace_guarded_update$
DECLARE
  v_definition text;
  v_replaced text;
  v_old_fragment text := $old$
  else
    v_year_month := to_char(p_lesson_date, 'YYYY-MM');
    v_old_year_month := coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date, 'YYYY-MM'));
  end if;
$old$;
  v_new_fragment text := $new$
  else
    v_old_year_month := public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id);
    if exists (
         select 1 from public.school_legacy_planned_settlement_evidence e
         where e.planned_lesson_id=v_lesson.id
       ) or exists (
         select 1 from public.school_student_tuition_bill_lessons r
         where r.planned_lesson_id=v_lesson.id
       ) or exists (
         select 1 from public.school_student_tuition_bills b
         where (b.source_snapshot -> 'planned_lesson_ids') ? v_lesson.id::text
       ) then
      v_year_month := v_old_year_month;
    else
      v_year_month := to_char(p_lesson_date, 'YYYY-MM');
    end if;
  end if;
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
  ) INTO v_definition;
  IF md5(v_definition)<>'ca52667c94a86608b4ab712f543b04b1'
     OR position(v_old_fragment IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_E_GUARDED_UPDATE_SOURCE_FRAGMENT_DRIFT';
  END IF;
  v_replaced:=replace(v_definition,v_old_fragment,v_new_fragment);
  IF v_replaced=v_definition
     OR position('school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)'
          IN v_replaced)=0
     OR position(v_old_fragment IN v_replaced)>0 THEN
    RAISE EXCEPTION 'R2_F_E_GUARDED_UPDATE_REPLACEMENT_FAILED';
  END IF;
  EXECUTE v_replaced;
END
$replace_guarded_update$;

COMMENT ON FUNCTION public.school_update_lesson_record_guarded(
  uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,
  text,boolean,integer,text,text
) IS
  'R2-F-E guarded updater. Existing actual attribution and overage protection remain; a billed planned schedule edit preserves its DB-resolved student settlement year_month while teacher date/time and planned-to-pending_makeup remain table-guarded.';

\echo 'R2_F_E_CREATE_FUTURE_ACTUAL_GUARD'
CREATE FUNCTION public.school_enforce_r2_f_e_actual_completion_date()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
BEGIN
  IF NEW.app_type='school'
     AND NEW.lesson_type='actual'
     AND NEW.status IN ('completed','makeup_completed')
     AND NEW.lesson_date > (statement_timestamp() AT TIME ZONE 'Asia/Tokyo')::date THEN
    RAISE EXCEPTION 'FUTURE_ACTUAL_COMPLETION_FORBIDDEN';
  END IF;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.school_enforce_r2_f_e_actual_completion_date()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER trg_school_lesson_r2_f_e_actual_completion_date
BEFORE INSERT OR UPDATE OF app_type,lesson_type,status,lesson_date
ON public.school_lesson_records
FOR EACH ROW EXECUTE FUNCTION
  public.school_enforce_r2_f_e_actual_completion_date();

COMMENT ON FUNCTION public.school_enforce_r2_f_e_actual_completion_date() IS
  'R2-F-E DB-authoritative Tokyo-date guard for completed and makeup_completed actual lessons.';
COMMENT ON TRIGGER trg_school_lesson_r2_f_e_actual_completion_date
ON public.school_lesson_records IS
  'Rejects every RPC and direct-DML path that would persist a future Tokyo-date actual as completed or makeup_completed.';

DO $verify$
BEGIN
  IF position('R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE' IN
       pg_get_functiondef('public.school_enforce_r2_e_planned_aircon()'::regprocedure))=0
     OR position('school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)' IN
       pg_get_functiondef(
         'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
       ))=0
     OR position('FUTURE_ACTUAL_COMPLETION_FORBIDDEN' IN
       pg_get_functiondef(
         'public.school_enforce_r2_f_e_actual_completion_date()'::regprocedure
       ))=0 THEN
    RAISE EXCEPTION 'R2_F_E_DEPLOYED_MARKER_MISSING';
  END IF;
  IF (SELECT count(*) FROM pg_trigger
      WHERE tgrelid='public.school_lesson_records'::regclass
        AND tgname='trg_school_lesson_r2_f_e_actual_completion_date'
        AND tgenabled='O' AND NOT tgisinternal)<>1 THEN
    RAISE EXCEPTION 'R2_F_E_TRIGGER_INSTALL_FAILED';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_E_R0_CHANGED';
  END IF;
END
$verify$;

SELECT
  md5(pg_get_functiondef(
    'public.school_enforce_r2_e_planned_aircon()'::regprocedure
  )) AS planned_charge_guard_md5,
  md5(pg_get_functiondef(
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
  )) AS guarded_update_md5,
  md5(pg_get_functiondef(
    'public.school_enforce_r2_f_e_actual_completion_date()'::regprocedure
  )) AS future_actual_guard_md5;

\if :r2_f_e_commit
  COMMIT;
  \echo 'R2_F_E_DEPLOYMENT_COMMITTED'
\else
  ROLLBACK;
  \echo 'R2_F_E_REHEARSAL_ROLLED_BACK'
\endif
