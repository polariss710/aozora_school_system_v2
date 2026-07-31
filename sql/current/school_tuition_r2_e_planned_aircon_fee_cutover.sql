-- Aozora School System V2 R2-E
-- Planned-lesson independent weekend air-conditioning fee cutover.
-- Required psql variable: r2_e_commit=0 (same-byte rehearsal) or 1 (deploy).

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_e_commit}
\else
  \echo 'R2_E_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '240s';

DO $preflight$
BEGIN
  IF to_regprocedure(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,numeric,numeric,integer)'
     ) IS NOT NULL
     OR to_regprocedure(
       'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'
     ) IS NOT NULL
     OR EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'school_lesson_records'
         AND column_name = 'lesson_total_fee_jpy'
     ) THEN
    RAISE EXCEPTION 'R2_E_ALREADY_DEPLOYED_OR_OBJECT_COLLISION';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     )) <> '08f3c60890d4afab8d9c730eec286c8d'
     OR md5(pg_get_functiondef(
       'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure
     )) <> 'd37839bb96797fb4f7a91246eb96f0ba'
     OR md5(pg_get_functiondef(
       'public.school_import_lesson_records_batch(uuid,text,text,jsonb,text)'::regprocedure
     )) <> '78176ed41f87b8ad9ac1bba5e456a8b8'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '1770f3469dbc3bc030a977381b853deb'
     OR md5(pg_get_functiondef(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
     )) <> 'ea71010c17f880ee61092bb8e01ea920'
     OR md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     )) <> '13fbc4d680d3b223cd2c6b59d66f2384' THEN
    RAISE EXCEPTION 'R2_E_PROTECTED_FUNCTION_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_venues) <> 0
     OR (SELECT count(*) FROM public.school_student_aircon_rates) <> 0
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(
           base_lesson_fee_jpy,aircon_charge_status,aircon_rate_id,
           aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
           aircon_fee_jpy,aircon_calculated_at,fee_calculation_version,
           fee_components_frozen_at
         ) > 0) <> 0 THEN
    RAISE EXCEPTION 'R2_E_AIRCON_ZERO_BASELINE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_E_R0_GATE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 654
     OR (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) <> 42 THEN
    RAISE EXCEPTION 'R2_E_BUSINESS_ROW_COUNT_DRIFT';
  END IF;
END
$preflight$;

ALTER TABLE public.school_lesson_records
  ADD COLUMN lesson_total_fee_jpy numeric;

COMMENT ON COLUMN public.school_lesson_records.lesson_fee IS
  'Base lesson fee only. R2-E explicitly forbids storing aircon-inclusive totals in this legacy authority column.';
COMMENT ON COLUMN public.school_lesson_records.base_lesson_fee_jpy IS
  'R2-E DB snapshot of the unchanged base lesson_fee for a componentized planned lesson.';
COMMENT ON COLUMN public.school_lesson_records.aircon_unit_price_jpy_snapshot IS
  'R2-E independent per-planned-lesson saved aircon rate in JPY per planned hour; not a student-level dynamic rate.';
COMMENT ON COLUMN public.school_lesson_records.aircon_fee_jpy IS
  'R2-E DB-authoritative planned aircon fee; actual duration and actual date never participate.';
COMMENT ON COLUMN public.school_lesson_records.lesson_total_fee_jpy IS
  'R2-E DB-authoritative student charge total: base lesson_fee plus planned aircon_fee_jpy.';

ALTER TABLE public.school_lesson_records
  DROP CONSTRAINT school_lesson_records_aircon_unit_price_check,
  ADD CONSTRAINT school_lesson_records_aircon_unit_price_check
    CHECK (
      aircon_unit_price_jpy_snapshot IS NULL
      OR aircon_unit_price_jpy_snapshot >= 0
    ),
  ADD CONSTRAINT school_lesson_records_total_fee_nonnegative
    CHECK (lesson_total_fee_jpy IS NULL OR lesson_total_fee_jpy >= 0),
  ADD CONSTRAINT school_lesson_records_r2_e_aircon_bundle_check
    CHECK (
      num_nonnulls(
        base_lesson_fee_jpy,
        aircon_charge_status,
        aircon_unit_price_jpy_snapshot,
        aircon_billable_hours_snapshot,
        aircon_fee_jpy,
        aircon_calculated_at,
        fee_calculation_version,
        lesson_total_fee_jpy
      ) IN (0,8)
    ),
  ADD CONSTRAINT school_lesson_records_r2_e_aircon_context_check
    CHECK (
      fee_calculation_version IS NULL
      OR (
        lesson_type = 'planned'
        AND fee_calculation_version = 'planned_weekend_aircon_v1'
        AND aircon_rate_id IS NULL
        AND base_lesson_fee_jpy = lesson_fee
        AND aircon_billable_hours_snapshot = duration_hours
        AND lesson_total_fee_jpy = base_lesson_fee_jpy + aircon_fee_jpy
        AND aircon_fee_jpy = CASE
          WHEN student_settlement_month >= '2026-08'
               AND lesson_date IS NOT NULL
               AND extract(isodow FROM lesson_date) IN (6,7)
            THEN aircon_unit_price_jpy_snapshot * duration_hours
          ELSE 0
        END
      )
    );

ALTER TABLE public.school_student_tuition_bill_lessons
  ADD CONSTRAINT school_tuition_bill_lessons_r2_e_aircon_bundle_check
    CHECK (
      num_nonnulls(
        base_lesson_fee_jpy_snapshot,
        aircon_unit_price_jpy_snapshot,
        aircon_billable_hours_snapshot,
        aircon_fee_jpy_snapshot,
        fee_calculation_version_snapshot
      ) IN (0,5)
    ),
  ADD CONSTRAINT school_tuition_bill_lessons_r2_e_aircon_context_check
    CHECK (
      fee_calculation_version_snapshot IS NULL
      OR (
        fee_calculation_version_snapshot = 'planned_weekend_aircon_v1'
        AND aircon_rate_id_snapshot IS NULL
        AND lesson_fee_jpy_snapshot
          = base_lesson_fee_jpy_snapshot + aircon_fee_jpy_snapshot
      )
    );

COMMENT ON COLUMN public.school_student_tuition_bill_lessons.lesson_fee_jpy_snapshot IS
  'Bill-line total charge. For planned_weekend_aircon_v1 it must equal base_lesson_fee_jpy_snapshot plus aircon_fee_jpy_snapshot.';
COMMENT ON COLUMN public.school_student_tuition_bill_lessons.source_snapshot IS
  'R2-E future formal-generate JSON contract adds base_lesson_fee_jpy, aircon_rate_jpy_per_hour, aircon_billable_hours, aircon_fee_jpy, lesson_total_fee_jpy, aircon_policy_version, and aircon_decided_at. Existing snapshots remain unchanged.';

CREATE FUNCTION public.school_r2_e_calculate_planned_aircon_fee(
  p_lesson_date date,
  p_student_settlement_month text,
  p_planned_duration_hours numeric,
  p_base_lesson_fee_jpy numeric,
  p_aircon_rate_jpy_per_hour integer
)
RETURNS TABLE (
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
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_duration numeric;
  v_rate integer := coalesce(p_aircon_rate_jpy_per_hour,0);
BEGIN
  v_duration := public.school_resolve_planned_duration(
    NULL,NULL,p_planned_duration_hours
  );
  IF p_base_lesson_fee_jpy IS NULL OR p_base_lesson_fee_jpy < 0 THEN
    RAISE EXCEPTION 'R2_E_BASE_LESSON_FEE_INVALID';
  END IF;
  IF v_rate < 0 THEN
    RAISE EXCEPTION 'R2_E_AIRCON_RATE_INVALID';
  END IF;
  IF p_student_settlement_month IS NOT NULL
     AND p_student_settlement_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R2_E_STUDENT_SETTLEMENT_MONTH_INVALID';
  END IF;

  base_lesson_fee_jpy := p_base_lesson_fee_jpy;
  aircon_rate_jpy_per_hour := v_rate;
  aircon_billable_hours := v_duration;
  aircon_policy_version := 'planned_weekend_aircon_v1';

  IF p_lesson_date IS NULL THEN
    aircon_charge_status := 'not_applicable';
    aircon_fee_jpy := 0;
    fee_block_reason_code := 'AIRCON_DATE_REQUIRED';
  ELSIF p_student_settlement_month IS NULL
        OR p_student_settlement_month < '2026-08' THEN
    aircon_charge_status := 'not_applicable';
    aircon_fee_jpy := 0;
    fee_block_reason_code := 'AIRCON_BEFORE_POLICY_MONTH';
  ELSIF extract(isodow FROM p_lesson_date) NOT IN (6,7) THEN
    aircon_charge_status := 'not_applicable';
    aircon_fee_jpy := 0;
    fee_block_reason_code := 'AIRCON_WEEKDAY';
  ELSIF v_rate = 0 THEN
    aircon_charge_status := 'configured_zero';
    aircon_fee_jpy := 0;
    fee_block_reason_code := 'AIRCON_RATE_ZERO';
  ELSE
    aircon_charge_status := 'calculated';
    aircon_fee_jpy := v_rate * v_duration;
    fee_block_reason_code := NULL;
  END IF;

  lesson_total_fee_jpy := base_lesson_fee_jpy + aircon_fee_jpy;
  RETURN NEXT;
END
$function$;

COMMENT ON FUNCTION public.school_r2_e_calculate_planned_aircon_fee(
  date,text,numeric,numeric,integer
) IS
  'R2-E authoritative per-planned calculation. Uses student settlement month, planned date/duration, unchanged base fee, and the planned row saved rate. Never reads student rates, venue, or actual data.';

REVOKE ALL ON FUNCTION public.school_r2_e_calculate_planned_aircon_fee(
  date,text,numeric,numeric,integer
) FROM PUBLIC, anon, authenticated, service_role;

-- Disable the unused B1-B student-rate helper so no future caller can revive
-- a conflicting student-level dynamic pricing path.
CREATE OR REPLACE FUNCTION public.school_calculate_planned_fee_components(
  p_student_id uuid,
  p_scheduled_lesson_date date,
  p_lesson_venue_id uuid,
  p_authoritative_duration_hours numeric,
  p_unit_price numeric
)
RETURNS TABLE (
  base_lesson_fee_jpy numeric,
  aircon_charge_status text,
  aircon_rate_id uuid,
  aircon_unit_price_jpy_snapshot integer,
  aircon_billable_hours_snapshot numeric,
  aircon_fee_jpy numeric,
  lesson_total_fee_jpy numeric,
  fee_calculation_version text,
  fee_block_reason_code text
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  RAISE EXCEPTION 'R2_E_STUDENT_LEVEL_AIRCON_RATE_PATH_BLOCKED';
END
$function$;

CREATE FUNCTION public.school_enforce_r2_e_planned_aircon()
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

    IF EXISTS (
      SELECT 1
      FROM public.school_legacy_planned_settlement_evidence evidence
      WHERE evidence.planned_lesson_id = OLD.id
    ) THEN
      IF NEW.aircon_unit_price_jpy_snapshot
           IS DISTINCT FROM OLD.aircon_unit_price_jpy_snapshot
         OR NEW.lesson_date IS DISTINCT FROM OLD.lesson_date
         OR NEW.duration_hours IS DISTINCT FROM OLD.duration_hours
         OR NEW.lesson_fee IS DISTINCT FROM OLD.lesson_fee THEN
        RAISE EXCEPTION 'R2_E_LEGACY_PLANNED_CHARGE_FACT_IMMUTABLE';
      END IF;
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
          FROM public.school_student_tuition_bill_lessons relation
          WHERE relation.planned_lesson_id = OLD.id
        )
        OR EXISTS (
          SELECT 1
          FROM public.school_student_tuition_bills bill
          WHERE (bill.source_snapshot -> 'planned_lesson_ids') ? OLD.id::text
        )
        OR EXISTS (
          SELECT 1
          FROM public.school_student_monthly_settlements settlement
          WHERE settlement.student_id = OLD.student_id
            AND settlement.business_entity_id
                  IS NOT DISTINCT FROM OLD.business_entity_id
            AND settlement.year_month
                  = coalesce(OLD.student_settlement_month,OLD.year_month)
            AND settlement.settlement_status = 'locked'
        )
        OR OLD.fee_components_frozen_at IS NOT NULL
      INTO v_charge_locked;
      IF v_charge_locked THEN
        RAISE EXCEPTION 'R2_E_BILLED_OR_LOCKED_PLANNED_CHARGE_IMMUTABLE';
      END IF;
    END IF;
  END IF;

  -- Existing historical NULL bundles remain untouched unless an explicit
  -- per-planned rate is supplied. Every new planned INSERT receives a complete
  -- zero bundle.
  IF TG_OP = 'UPDATE'
     AND OLD.fee_calculation_version IS NULL
     AND NEW.aircon_unit_price_jpy_snapshot IS NULL THEN
    RETURN NEW;
  END IF;

  v_requested_rate := coalesce(NEW.aircon_unit_price_jpy_snapshot,0);
  SELECT * INTO STRICT v_result
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    NEW.lesson_date,
    NEW.student_settlement_month,
    NEW.duration_hours,
    NEW.lesson_fee,
    v_requested_rate
  );

  NEW.base_lesson_fee_jpy := v_result.base_lesson_fee_jpy;
  NEW.aircon_charge_status := v_result.aircon_charge_status;
  NEW.aircon_rate_id := NULL;
  NEW.aircon_unit_price_jpy_snapshot
    := v_result.aircon_rate_jpy_per_hour;
  NEW.aircon_billable_hours_snapshot := v_result.aircon_billable_hours;
  NEW.aircon_fee_jpy := v_result.aircon_fee_jpy;
  NEW.aircon_calculated_at := statement_timestamp();
  NEW.fee_calculation_version := v_result.aircon_policy_version;
  NEW.fee_block_reason_code := v_result.fee_block_reason_code;
  NEW.lesson_total_fee_jpy := v_result.lesson_total_fee_jpy;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.school_enforce_r2_e_planned_aircon()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_school_lesson_r2_e_planned_aircon
BEFORE INSERT OR UPDATE ON public.school_lesson_records
FOR EACH ROW EXECUTE FUNCTION public.school_enforce_r2_e_planned_aircon();

COMMENT ON TRIGGER trg_school_lesson_r2_e_planned_aircon
ON public.school_lesson_records IS
  'R2-E direct-table invariant: planned rate is the only accepted fee input; DB decides base snapshot, aircon fee, total, policy and time. Actual rows remain empty.';

-- New single-create overload. The legacy signature remains unchanged and the
-- INSERT trigger supplies its complete zero-rate state.
CREATE FUNCTION public.school_create_planned_lesson_record(
  p_lesson_date date,
  p_student_id uuid,
  p_teacher_id uuid,
  p_subject_id uuid,
  p_business_entity_id uuid,
  p_start_time text,
  p_end_time text,
  p_duration_hours numeric,
  p_unit_price numeric,
  p_lesson_fee numeric,
  p_status text,
  p_lesson_count integer,
  p_lesson_content text,
  p_note text,
  p_aircon_rate_jpy_per_hour integer
)
RETURNS TABLE (
  lesson_id uuid,lesson_type text,lesson_date date,year_month text,
  student_id uuid,teacher_id uuid,subject_id uuid,business_entity_id uuid,
  start_time text,end_time text,duration_hours numeric,unit_price numeric,
  lesson_fee numeric,status text,is_billable boolean,lesson_count integer,
  lesson_content text,note text,created_at timestamptz,updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_id uuid;
BEGIN
  IF p_aircon_rate_jpy_per_hour IS NULL
     OR p_aircon_rate_jpy_per_hour < 0 THEN
    RAISE EXCEPTION 'R2_E_AIRCON_RATE_INVALID';
  END IF;
  SELECT created.lesson_id INTO STRICT v_id
  FROM public.school_create_planned_lesson_record(
    p_lesson_date,p_student_id,p_teacher_id,p_subject_id,p_business_entity_id,
    p_start_time,p_end_time,p_duration_hours,p_unit_price,p_lesson_fee,p_status,
    p_lesson_count,p_lesson_content,p_note
  ) created;
  UPDATE public.school_lesson_records
  SET aircon_unit_price_jpy_snapshot = p_aircon_rate_jpy_per_hour
  WHERE id = v_id;
  RETURN QUERY
  SELECT
    l.id,l.lesson_type,l.lesson_date,l.year_month,l.student_id,l.teacher_id,
    l.subject_id,l.business_entity_id,l.start_time,l.end_time,l.duration_hours,
    l.unit_price,l.lesson_fee,l.status,l.is_billable,l.lesson_count,
    l.lesson_content,l.note,l.created_at,l.updated_at
  FROM public.school_lesson_records l WHERE l.id = v_id;
END
$function$;

REVOKE ALL ON FUNCTION public.school_create_planned_lesson_record(
  date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_create_planned_lesson_record(
  date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer
) TO PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.school_create_planned_lesson_record_with_venue(
  p_lesson_date date,
  p_student_id uuid,
  p_teacher_id uuid,
  p_subject_id uuid,
  p_business_entity_id uuid,
  p_start_time text,
  p_end_time text,
  p_duration_hours numeric,
  p_unit_price numeric,
  p_lesson_fee numeric,
  p_status text,
  p_lesson_count integer,
  p_lesson_content text,
  p_note text,
  p_lesson_delivery_mode text,
  p_lesson_venue text,
  p_aircon_rate_jpy_per_hour integer
)
RETURNS SETOF public.school_lesson_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_row public.school_lesson_records%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_row
  FROM public.school_create_planned_lesson_record_with_venue(
    p_lesson_date,p_student_id,p_teacher_id,p_subject_id,p_business_entity_id,
    p_start_time,p_end_time,p_duration_hours,p_unit_price,p_lesson_fee,p_status,
    p_lesson_count,p_lesson_content,p_note,p_lesson_delivery_mode,p_lesson_venue
  );
  UPDATE public.school_lesson_records
  SET aircon_unit_price_jpy_snapshot = p_aircon_rate_jpy_per_hour
  WHERE id = v_row.id;
  RETURN QUERY SELECT * FROM public.school_lesson_records WHERE id = v_row.id;
END
$function$;

REVOKE ALL ON FUNCTION public.school_create_planned_lesson_record_with_venue(
  date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_create_planned_lesson_record_with_venue(
  date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer
) TO PUBLIC, anon, authenticated, service_role;

-- Batch/import signatures remain unchanged. Each JSON row may carry
-- aircon_rate_jpy_per_hour; omitted means 0. The rate is copied to each created
-- lesson row independently after the legacy core returns.
CREATE OR REPLACE FUNCTION public.school_generate_planned_lessons_batch(
  p_generation_id uuid,p_student_id uuid,p_business_entity_id uuid,
  p_start_date date,p_end_date date,p_patterns jsonb,
  p_excluded_occurrences jsonb DEFAULT '[]'::jsonb,p_note text DEFAULT NULL
)
RETURNS TABLE (
  row_index integer,pattern_index integer,lesson_date date,row_valid boolean,
  batch_committed boolean,created_lesson_id uuid,status text,warnings text[],
  errors text[],generation_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_patterns jsonb := '[]'::jsonb;
  v_item record;
  v_result record;
  v_pattern jsonb;
  v_start text;
  v_end text;
  v_duration numeric;
  v_rate integer;
  v_weekday integer;
  v_scheduled_date date;
BEGIN
  IF p_patterns IS NULL OR jsonb_typeof(p_patterns) <> 'array' THEN
    RETURN QUERY SELECT *
    FROM public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(
      p_generation_id,p_student_id,p_business_entity_id,p_start_date,p_end_date,
      p_patterns,p_excluded_occurrences,p_note
    );
    RETURN;
  END IF;

  FOR v_item IN SELECT value,ordinality
                FROM jsonb_array_elements(p_patterns) WITH ORDINALITY
  LOOP
    v_start := nullif(trim(coalesce(v_item.value ->> 'start_time','')),'');
    v_end := nullif(trim(coalesce(v_item.value ->> 'end_time','')),'');
    v_duration := public.school_resolve_planned_duration(
      v_start,v_end,
      CASE WHEN v_start IS NULL AND v_end IS NULL
           THEN nullif(v_item.value ->> 'duration_hours','')::numeric ELSE NULL END
    );
    v_rate := coalesce(
      nullif(v_item.value ->> 'aircon_rate_jpy_per_hour','')::integer,0
    );
    IF v_rate < 0 THEN
      RAISE EXCEPTION 'R2_E_AIRCON_RATE_INVALID';
    END IF;
    v_patterns := v_patterns || jsonb_build_array(
      jsonb_set(
        jsonb_set(v_item.value,'{duration_hours}',to_jsonb(v_duration),true),
        '{aircon_rate_jpy_per_hour}',to_jsonb(v_rate),true
      )
    );
  END LOOP;

  FOR v_result IN
    SELECT * FROM public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(
      p_generation_id,p_student_id,p_business_entity_id,p_start_date,p_end_date,
      v_patterns,p_excluded_occurrences,p_note
    )
  LOOP
    IF v_result.batch_committed AND v_result.created_lesson_id IS NOT NULL THEN
      SELECT item.value INTO STRICT v_pattern
      FROM jsonb_array_elements(v_patterns) item(value)
      WHERE (item.value ->> 'pattern_index')::integer = v_result.pattern_index
      LIMIT 1;
      v_rate := coalesce(
        nullif(v_pattern ->> 'aircon_rate_jpy_per_hour','')::integer,0
      );
      v_weekday := (v_pattern ->> 'weekday')::integer;
      IF v_weekday < 0 OR v_weekday > 6 THEN
        RAISE EXCEPTION 'R2_E_BATCH_WEEKDAY_INVALID';
      END IF;
      v_scheduled_date := v_result.lesson_date
        + CASE WHEN v_weekday = 0 THEN 6 ELSE v_weekday - 1 END;
      UPDATE public.school_lesson_records
      SET lesson_date = v_scheduled_date,
          aircon_unit_price_jpy_snapshot = v_rate
      WHERE id = v_result.created_lesson_id;
    END IF;
    row_index := v_result.row_index;
    pattern_index := v_result.pattern_index;
    lesson_date := v_result.lesson_date;
    row_valid := v_result.row_valid;
    batch_committed := v_result.batch_committed;
    created_lesson_id := v_result.created_lesson_id;
    status := v_result.status;
    warnings := v_result.warnings;
    errors := v_result.errors;
    generation_id := v_result.generation_id;
    RETURN NEXT;
  END LOOP;
END
$function$;

CREATE OR REPLACE FUNCTION public.school_import_lesson_records_batch(
  p_import_batch_id uuid,p_source_file_name text,p_source_file_hash text,
  p_rows jsonb,p_note text DEFAULT NULL
)
RETURNS TABLE (
  row_index integer,source_row_no integer,row_valid boolean,batch_committed boolean,
  created_lesson_id uuid,lesson_type text,status text,planned_lesson_id uuid,
  warnings text[],errors text[],import_batch_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_rows jsonb := '[]'::jsonb;
  v_item record;
  v_result record;
  v_start text;
  v_end text;
  v_duration numeric;
  v_rate integer;
BEGIN
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RETURN QUERY SELECT *
    FROM public.school_import_lesson_records_batch_r1d_f1_legacy_core(
      p_import_batch_id,p_source_file_name,p_source_file_hash,p_rows,p_note
    );
    RETURN;
  END IF;

  FOR v_item IN SELECT value,ordinality
                FROM jsonb_array_elements(p_rows) WITH ORDINALITY
  LOOP
    v_start := nullif(trim(coalesce(v_item.value ->> 'start_time','')),'');
    v_end := nullif(trim(coalesce(v_item.value ->> 'end_time','')),'');
    v_duration := public.school_resolve_planned_duration(
      v_start,v_end,
      CASE WHEN v_start IS NULL AND v_end IS NULL
           THEN nullif(v_item.value ->> 'duration_hours','')::numeric ELSE NULL END
    );
    v_rate := coalesce(
      nullif(v_item.value ->> 'aircon_rate_jpy_per_hour','')::integer,0
    );
    IF v_rate < 0 THEN
      RAISE EXCEPTION 'R2_E_AIRCON_RATE_INVALID';
    END IF;
    v_rows := v_rows || jsonb_build_array(
      jsonb_set(
        jsonb_set(v_item.value,'{duration_hours}',to_jsonb(v_duration),true),
        '{aircon_rate_jpy_per_hour}',to_jsonb(v_rate),true
      )
    );
  END LOOP;

  FOR v_result IN
    SELECT * FROM public.school_import_lesson_records_batch_r1d_f1_legacy_core(
      p_import_batch_id,p_source_file_name,p_source_file_hash,v_rows,p_note
    )
  LOOP
    IF v_result.batch_committed AND v_result.created_lesson_id IS NOT NULL THEN
      SELECT coalesce(
        nullif(item.value ->> 'aircon_rate_jpy_per_hour','')::integer,0
      ) INTO STRICT v_rate
      FROM jsonb_array_elements(v_rows) item(value)
      WHERE (item.value ->> 'row_index')::integer = v_result.row_index
      LIMIT 1;
      UPDATE public.school_lesson_records
      SET aircon_unit_price_jpy_snapshot = v_rate
      WHERE id = v_result.created_lesson_id;
    END IF;
    row_index := v_result.row_index;
    source_row_no := v_result.source_row_no;
    row_valid := v_result.row_valid;
    batch_committed := v_result.batch_committed;
    created_lesson_id := v_result.created_lesson_id;
    lesson_type := v_result.lesson_type;
    status := v_result.status;
    planned_lesson_id := v_result.planned_lesson_id;
    warnings := v_result.warnings;
    errors := v_result.errors;
    import_batch_id := v_result.import_batch_id;
    RETURN NEXT;
  END LOOP;
END
$function$;

-- New guarded-update overloads. Legacy update signatures preserve existing
-- rates. The page calls the venue overload and supplies only the saved rate.
CREATE FUNCTION public.school_update_lesson_record_guarded(
  p_lesson_id uuid,p_expected_updated_at timestamptz,p_lesson_date date,
  p_student_id uuid,p_teacher_id uuid,p_subject_id uuid,p_business_entity_id uuid,
  p_start_time text,p_end_time text,p_duration_hours numeric,p_unit_price numeric,
  p_lesson_fee numeric,p_status text,p_is_billable boolean,p_lesson_count integer,
  p_lesson_content text,p_note text,p_aircon_rate_jpy_per_hour integer
)
RETURNS TABLE (
  lesson_id uuid,lesson_type text,lesson_date date,year_month text,
  student_id uuid,teacher_id uuid,subject_id uuid,business_entity_id uuid,
  start_time text,end_time text,duration_hours numeric,unit_price numeric,
  lesson_fee numeric,status text,is_billable boolean,lesson_count integer,
  actual_minutes integer,planned_lesson_id uuid,teacher_settlement_month text,
  lesson_content text,note text,created_at timestamptz,updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_id uuid;
  v_type text;
BEGIN
  SELECT lesson.lesson_type INTO STRICT v_type
  FROM public.school_lesson_records lesson
  WHERE lesson.id = p_lesson_id;
  IF v_type <> 'planned' THEN
    RAISE EXCEPTION 'R2_E_AIRCON_RATE_ONLY_ALLOWED_FOR_PLANNED';
  END IF;
  IF p_aircon_rate_jpy_per_hour IS NULL
     OR p_aircon_rate_jpy_per_hour < 0 THEN
    RAISE EXCEPTION 'R2_E_AIRCON_RATE_INVALID';
  END IF;
  SELECT updated.lesson_id INTO STRICT v_id
  FROM public.school_update_lesson_record_guarded(
    p_lesson_id,p_expected_updated_at,p_lesson_date,p_student_id,p_teacher_id,
    p_subject_id,p_business_entity_id,p_start_time,p_end_time,p_duration_hours,
    p_unit_price,p_lesson_fee,p_status,p_is_billable,p_lesson_count,
    p_lesson_content,p_note
  ) updated;
  UPDATE public.school_lesson_records lesson
  SET aircon_unit_price_jpy_snapshot = p_aircon_rate_jpy_per_hour
  WHERE lesson.id = v_id;
  RETURN QUERY
  SELECT
    l.id,l.lesson_type,l.lesson_date,l.year_month,l.student_id,l.teacher_id,
    l.subject_id,l.business_entity_id,l.start_time,l.end_time,l.duration_hours,
    l.unit_price,l.lesson_fee,l.status,l.is_billable,l.lesson_count,
    l.actual_minutes,l.planned_lesson_id,l.teacher_settlement_month,
    l.lesson_content,l.note,l.created_at,l.updated_at
  FROM public.school_lesson_records l WHERE l.id = v_id;
END
$function$;

REVOKE ALL ON FUNCTION public.school_update_lesson_record_guarded(
  uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,
  text,boolean,integer,text,text,integer
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_update_lesson_record_guarded(
  uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,
  text,boolean,integer,text,text,integer
) TO authenticated, service_role;

CREATE FUNCTION public.school_update_lesson_record_guarded_with_venue(
  p_lesson_id uuid,p_expected_updated_at timestamptz,p_lesson_date date,
  p_student_id uuid,p_teacher_id uuid,p_subject_id uuid,p_business_entity_id uuid,
  p_start_time text,p_end_time text,p_duration_hours numeric,p_unit_price numeric,
  p_lesson_fee numeric,p_status text,p_is_billable boolean,p_lesson_count integer,
  p_lesson_content text,p_note text,p_lesson_delivery_mode text,
  p_lesson_venue text,p_aircon_rate_jpy_per_hour integer
)
RETURNS SETOF public.school_lesson_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_row public.school_lesson_records%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    p_lesson_id,p_expected_updated_at,p_lesson_date,p_student_id,p_teacher_id,
    p_subject_id,p_business_entity_id,p_start_time,p_end_time,p_duration_hours,
    p_unit_price,p_lesson_fee,p_status,p_is_billable,p_lesson_count,
    p_lesson_content,p_note,p_lesson_delivery_mode,p_lesson_venue
  );
  UPDATE public.school_lesson_records
  SET aircon_unit_price_jpy_snapshot = p_aircon_rate_jpy_per_hour
  WHERE id = v_row.id;
  RETURN QUERY SELECT * FROM public.school_lesson_records WHERE id = v_row.id;
END
$function$;

REVOKE ALL ON FUNCTION public.school_update_lesson_record_guarded_with_venue(
  uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,
  text,boolean,integer,text,text,text,text,integer
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_update_lesson_record_guarded_with_venue(
  uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,
  text,boolean,integer,text,text,text,text,integer
) TO authenticated, service_role;

CREATE FUNCTION public.school_list_student_tuition_charge_candidates(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_billing_month text,
  p_include_excluded boolean DEFAULT false
)
RETURNS TABLE (
  planned_lesson_id uuid,
  student_id uuid,
  business_entity_id uuid,
  candidate_billing_month text,
  billing_week_start_date date,
  lesson_date date,
  lesson_count integer,
  duration_hours numeric,
  unit_price numeric,
  base_lesson_fee_jpy numeric,
  aircon_rate_jpy_per_hour integer,
  aircon_fee_jpy numeric,
  lesson_total_fee_jpy numeric,
  aircon_charge_status text,
  aircon_policy_version text,
  candidate_status text,
  exclusion_reason text,
  complete_row_hash text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT
    candidate.planned_lesson_id,
    candidate.student_id,
    candidate.business_entity_id,
    candidate.candidate_billing_month,
    lesson.billing_week_start_date,
    candidate.lesson_date,
    candidate.lesson_count,
    candidate.duration_hours,
    candidate.unit_price,
    candidate.lesson_fee,
    coalesce(lesson.aircon_unit_price_jpy_snapshot,0),
    coalesce(lesson.aircon_fee_jpy,0),
    coalesce(lesson.lesson_total_fee_jpy,candidate.lesson_fee),
    coalesce(lesson.aircon_charge_status,'legacy_base_only'),
    lesson.fee_calculation_version,
    candidate.candidate_status,
    candidate.exclusion_reason,
    md5(concat_ws('|',
      candidate.complete_row_hash,
      candidate.lesson_fee::text,
      coalesce(lesson.aircon_unit_price_jpy_snapshot,0)::text,
      coalesce(lesson.aircon_fee_jpy,0)::text,
      coalesce(lesson.lesson_total_fee_jpy,candidate.lesson_fee)::text,
      coalesce(lesson.fee_calculation_version,'legacy_base_only')
    ))
  FROM public.school_list_student_tuition_candidates(
    p_student_id,p_business_entity_id,p_billing_month,p_include_excluded
  ) candidate
  JOIN public.school_lesson_records lesson
    ON lesson.id = candidate.planned_lesson_id
  WHERE lesson.fee_calculation_version IS NULL
     OR (
       lesson.fee_calculation_version = 'planned_weekend_aircon_v1'
       AND lesson.base_lesson_fee_jpy = candidate.lesson_fee
       AND lesson.lesson_total_fee_jpy
             = lesson.base_lesson_fee_jpy + lesson.aircon_fee_jpy
     )
  ORDER BY lesson.billing_week_start_date,lesson.lesson_date,lesson.id;
$function$;

COMMENT ON FUNCTION public.school_list_student_tuition_charge_candidates(
  uuid,uuid,text,boolean
) IS
  'R2-E canonical student-charge reader. Reuses the fail-closed candidate classifier, preserves physical lesson_fee as base, and exposes authoritative base/rate/aircon/total. Legacy NULL bundles silently remain base-only.';

REVOKE ALL ON FUNCTION public.school_list_student_tuition_charge_candidates(
  uuid,uuid,text,boolean
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_list_student_tuition_charge_candidates(
  uuid,uuid,text,boolean
) TO service_role;

CREATE OR REPLACE FUNCTION public.school_preview_student_tuition_bill(
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
  planned_lesson_count integer,
  planned_lesson_hours numeric,
  planned_lesson_fee_jpy numeric,
  bill_amount_jpy numeric,
  currency text,
  billing_exchange_rate numeric,
  billing_amount_cny numeric,
  billing_amount_currency text,
  existing_tuition_bill_id uuid,
  existing_tuition_bill_status text,
  existing_income_record_id uuid,
  existing_income_status text,
  message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_student public.school_students%ROWTYPE;
  v_billing_month text := nullif(trim(coalesce(p_billing_month, '')), '');
  v_previous_month text;
  v_previous_settlement public.school_student_monthly_settlements%ROWTYPE;
  v_existing public.school_student_tuition_bills%ROWTYPE;
  v_existing_income public.school_income_records%ROWTYPE;
  v_count integer;
  v_hours numeric;
  v_total numeric;
  v_previous_carryover numeric;
  v_amount_cny numeric;
  v_existing_found boolean;
  v_existing_income_status text;
  v_message text := 'preview only; no business data written';
BEGIN
  PERFORM public.school_require_feature_gate_state(
    'student_tuition_preview','validation_preview_only',
    'TUITION_PREVIEW_BLOCKED',
    '学费预览 gate 不可用，已按 fail-closed 拒绝。'
  );
  IF p_student_id IS NULL THEN RAISE EXCEPTION '请选择学生。'; END IF;
  IF v_billing_month IS NULL
     OR v_billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION '学费月份格式无效，请使用 YYYY-MM。';
  END IF;
  IF p_billing_exchange_rate IS NULL OR p_billing_exchange_rate <= 0 THEN
    RAISE EXCEPTION '通知汇率必须大于 0。';
  END IF;

  SELECT * INTO v_student
  FROM public.school_students student
  WHERE student.id = p_student_id AND student.app_type = 'school';
  IF NOT FOUND THEN RAISE EXCEPTION '学生无效或不属于 School。'; END IF;
  IF coalesce(v_student.status,'') IN ('inactive','disabled','archived') THEN
    RAISE EXCEPTION '学生已停用，不能生成学费应收。';
  END IF;
  IF v_student.business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能生成学费应收。';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements settlement
    WHERE settlement.student_id = p_student_id
      AND settlement.business_entity_id = v_student.business_entity_id
      AND settlement.year_month = v_billing_month
      AND settlement.settlement_status = 'locked'
  ) THEN
    RAISE EXCEPTION '目标学生月度结算已锁定，不能生成新的学费应收。';
  END IF;

  v_previous_month := to_char(
    (to_date(v_billing_month || '-01','YYYY-MM-DD')
      - interval '1 month')::date,'YYYY-MM'
  );
  SELECT * INTO v_previous_settlement
  FROM public.school_student_monthly_settlements settlement
  WHERE settlement.student_id = p_student_id
    AND settlement.business_entity_id = v_student.business_entity_id
    AND settlement.year_month = v_previous_month
    AND settlement.settlement_status = 'locked'
  ORDER BY settlement.locked_at DESC NULLS LAST,
    settlement.updated_at DESC NULLS LAST,
    settlement.created_at DESC NULLS LAST
  LIMIT 1;

  SELECT count(*)::integer,
         coalesce(sum(candidate.duration_hours),0),
         coalesce(sum(candidate.lesson_total_fee_jpy),0)
  INTO v_count,v_hours,v_total
  FROM public.school_list_student_tuition_charge_candidates(
    p_student_id,v_student.business_entity_id,v_billing_month,false
  ) candidate;
  IF v_count <= 0 THEN
    RAISE EXCEPTION '该学生月份没有可生成学费应收的正式预定课时。';
  END IF;
  IF v_total <= 0 THEN
    RAISE EXCEPTION '该学生月份预定课时费为 0，不能生成学费应收。';
  END IF;

  v_previous_carryover := round(
    coalesce(v_previous_settlement.carryover_amount_cny,0),2
  );
  v_amount_cny := round(
    v_total * p_billing_exchange_rate + v_previous_carryover,2
  );
  IF v_amount_cny <= 0 THEN RAISE EXCEPTION '通知金额计算失败。'; END IF;

  SELECT * INTO v_existing
  FROM public.school_student_tuition_bills bill
  WHERE bill.student_id = p_student_id
    AND bill.business_entity_id = v_student.business_entity_id
    AND bill.billing_month = v_billing_month
    AND bill.status IN ('draft','income_created')
  ORDER BY bill.updated_at DESC NULLS LAST,bill.created_at DESC NULLS LAST
  LIMIT 1;
  v_existing_found := FOUND;
  IF v_existing_found AND v_existing.status = 'income_created' THEN
    SELECT * INTO v_existing_income
    FROM public.school_income_records income
    WHERE income.id = v_existing.income_record_id
      AND income.app_type = 'school';
    IF FOUND THEN v_existing_income_status := v_existing_income.status; END IF;
    IF NOT FOUND
       OR (v_existing_income.status <> 'cancelled'
           AND v_existing_income.cancelled_at IS NULL) THEN
      RAISE EXCEPTION '该学生月份已生成收入记录，不能重复生成学费应收。';
    END IF;
    v_message := 'existing income-created tuition bill has cancelled income; regenerate is allowed';
  ELSIF v_existing_found AND v_existing.status = 'draft' THEN
    v_message := 'existing draft tuition bill will be recalculated';
  END IF;

  RETURN QUERY SELECT
    v_student.id,v_student.business_entity_id,v_billing_month,
    v_previous_month,v_previous_settlement.id,v_previous_carryover,
    v_count,v_hours,v_total,v_total,'JPY'::text,p_billing_exchange_rate,
    v_amount_cny,'CNY'::text,
    CASE WHEN v_existing_found THEN v_existing.id ELSE NULL END,
    CASE WHEN v_existing_found THEN v_existing.status ELSE NULL END,
    CASE WHEN v_existing_found THEN v_existing.income_record_id ELSE NULL END,
    v_existing_income_status,v_message;
END
$function$;

COMMENT ON FUNCTION public.school_preview_student_tuition_bill(uuid,text,numeric)
IS 'R2-E validation-only preview. Aggregates canonical candidate lesson totals (base plus planned aircon) while preserving R0 and writing no business data.';

DROP FUNCTION public.school_get_student_tuition_validation_preview_details(
  uuid,text,numeric
);

CREATE FUNCTION public.school_get_student_tuition_validation_preview_details(
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

REVOKE ALL ON FUNCTION public.school_get_student_tuition_validation_preview_details(
  uuid,text,numeric
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_get_student_tuition_validation_preview_details(
  uuid,text,numeric
) TO authenticated, service_role;

COMMENT ON FUNCTION public.school_get_student_tuition_validation_preview_details(
  uuid,text,numeric
) IS
  'R2-E R0 validation-only details: one authoritative candidate snapshot with explicit base/rate/aircon/total and fail-closed UUID/manifest/summary consistency.';

DO $verify$
DECLARE
  v_calc record;
BEGIN
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-01','2026-08',2,17000,330
  );
  IF v_calc.aircon_fee_jpy <> 660
     OR v_calc.lesson_total_fee_jpy <> 17660
     OR v_calc.base_lesson_fee_jpy <> 17000 THEN
    RAISE EXCEPTION 'R2_E_EXAMPLE_CALCULATION_MISMATCH';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-03','2026-08',2,17000,330
  );
  IF v_calc.aircon_fee_jpy <> 0
     OR v_calc.aircon_rate_jpy_per_hour <> 330
     OR v_calc.lesson_total_fee_jpy <> 17000 THEN
    RAISE EXCEPTION 'R2_E_WEEKDAY_RATE_PRESERVATION_MISMATCH';
  END IF;
  IF (SELECT count(*) FROM public.school_student_aircon_rates) <> 0
     OR (SELECT count(*) FROM public.school_lesson_venues) <> 0
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE fee_calculation_version = 'planned_weekend_aircon_v1') <> 0 THEN
    RAISE EXCEPTION 'R2_E_HISTORY_WAS_POPULATED';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_E_R0_CHANGED';
  END IF;
END
$verify$;

\if :r2_e_commit
  COMMIT;
\else
  ROLLBACK;
\endif
