\set ON_ERROR_STOP on
\pset pager off

\if :{?b1_b_rehearsal}
\else
  \set b1_b_rehearsal false
\endif

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

-- B1_B_DDL_BODY_BEGIN
DO $preflight$
DECLARE
  v_collision_count bigint;
  v_candidate_count bigint;
  v_candidate_hours numeric;
  v_candidate_fee numeric;
  v_candidate_md5 text;
  v_manifest_sha text;
  v_legacy_count bigint;
  v_legacy_md5 text;
BEGIN
  IF (SELECT count(*) FROM pg_extension x
      JOIN pg_namespace n ON n.oid = x.extnamespace
      JOIN pg_roles r ON r.oid = x.extowner
      WHERE x.extname = 'btree_gist' AND x.extversion = '1.7'
        AND n.nspname = 'extensions' AND r.rolname = 'supabase_admin') <> 1 THEN
    RAISE EXCEPTION 'B1-B schema preflight: btree_gist version/schema/owner mismatch';
  END IF;
  IF (SELECT count(*) FROM pg_depend d JOIN pg_extension x ON x.oid = d.refobjid
      WHERE x.extname = 'btree_gist' AND d.refclassid = 'pg_extension'::regclass
        AND d.deptype = 'e') <> 264 THEN
    RAISE EXCEPTION 'B1-B schema preflight: btree_gist member count is not 264';
  END IF;
  IF (SELECT count(*) FROM pg_opclass o JOIN pg_am a ON a.oid = o.opcmethod
      JOIN pg_namespace n ON n.oid = o.opcnamespace
      WHERE n.nspname = 'extensions' AND o.opcname = 'gist_uuid_ops'
        AND o.opcintype = 'uuid'::regtype AND a.amname = 'gist') <> 1 THEN
    RAISE EXCEPTION 'B1-B schema preflight: extensions.gist_uuid_ops is unavailable';
  END IF;

  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
        AND column_name = 'duration_hours_snapshot' AND data_type = 'numeric'
        AND is_nullable = 'NO' AND column_default IS NULL) <> 1
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
        AND column_name = 'unit_price_jpy_snapshot' AND data_type = 'numeric'
        AND is_nullable = 'NO' AND column_default IS NULL) <> 1
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
        AND column_name = 'lesson_fee_jpy_snapshot' AND data_type = 'numeric'
        AND is_nullable = 'NO' AND column_default IS NULL) <> 1
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
        AND column_name = 'week_start_date_snapshot' AND data_type = 'date'
        AND is_nullable = 'YES' AND column_default IS NULL) <> 1
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
        AND column_name = 'scheduled_lesson_date_snapshot' AND data_type = 'date'
        AND is_nullable = 'YES' AND column_default IS NULL) <> 1
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
        AND column_name = 'source_snapshot' AND data_type = 'jsonb'
        AND is_nullable = 'NO' AND column_default = '''{}''::jsonb') <> 1 THEN
    RAISE EXCEPTION 'B1-B schema preflight: frozen reused relation mapping mismatch';
  END IF;

  SELECT
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname IN (
       'school_lesson_venues','school_student_aircon_rates',
       'school_planned_writer_commands','school_venue_rate_change_audit'))
    +(SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_lesson_records'
        AND column_name IN ('base_lesson_fee_jpy','lesson_venue_id','aircon_charge_status',
          'aircon_rate_id','aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy','aircon_calculated_at','fee_calculation_version',
          'fee_block_reason_code','fee_components_frozen_at'))
    +(SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
        AND column_name IN ('base_lesson_fee_jpy_snapshot','aircon_rate_id_snapshot',
          'aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy_snapshot','fee_calculation_version_snapshot',
          'lesson_venue_id_snapshot','lesson_venue_code_snapshot'))
    +(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname IN (
        'school_resolve_planned_billing_attribution','school_resolve_planned_duration',
        'school_calculate_planned_fee_components'))
  INTO v_collision_count;
  IF v_collision_count <> 0 THEN
    RAISE EXCEPTION 'B1-B schema preflight: exact new-object collision count is %', v_collision_count;
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates WHERE
      (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only') OR
      (feature_key = 'student_tuition_generate' AND state = 'blocked') OR
      (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'B1-B schema preflight: R0 feature gates mismatch';
  END IF;
  IF md5(pg_get_functiondef(
      'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
    )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'B1-B schema preflight: candidate function MD5 mismatch';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned') <> 397
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,
        billing_month_source,billing_month_decided_at) = 5) <> 118
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,
        billing_month_source,billing_month_decided_at) = 0) <> 279
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,
        billing_month_source,billing_month_decided_at) BETWEEN 1 AND 4) <> 0 THEN
    RAISE EXCEPTION 'B1-B schema preflight: planned/118/279/partial boundary mismatch';
  END IF;

  WITH candidate AS (
    SELECT l.id,l.student_id,l.billing_month,l.billing_week_start_date,l.duration_hours,
      l.unit_price,l.lesson_fee,l.billing_month_source,l.billing_month_decided_at
    FROM public.school_lesson_records l
    WHERE l.app_type = 'school' AND l.lesson_type = 'planned' AND l.status = 'planned'
      AND l.voided_at IS NULL AND l.is_billable IS true
      AND l.student_id IS NOT NULL AND l.business_entity_id IS NOT NULL
      AND l.billing_month IS NOT NULL AND l.billing_week_start_date IS NOT NULL
      AND extract(isodow FROM l.billing_week_start_date) = 1
      AND to_char(l.billing_week_start_date,'YYYY-MM') = l.billing_month
      AND l.student_settlement_month = l.billing_month
      AND l.billing_month_source IN ('approved_r1c_a_manifest','approved_r1c_c_b_manifest')
      AND l.billing_month_decided_at IS NOT NULL AND l.lesson_date IS NOT NULL
      AND l.teacher_id IS NOT NULL AND l.subject_id IS NOT NULL
      AND l.lesson_count > 0 AND l.duration_hours > 0 AND l.unit_price > 0 AND l.lesson_fee > 0
      AND l.created_at IS NOT NULL AND l.updated_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons r
        WHERE r.planned_lesson_id = l.id)
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bills b
        WHERE (b.source_snapshot -> 'planned_lesson_ids') ? l.id::text)
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions e
        WHERE e.planned_lesson_id = l.id)
  )
  SELECT count(*),sum(duration_hours),sum(lesson_fee),
    md5(string_agg(id::text,',' ORDER BY id::text)),
    encode(sha256(convert_to(string_agg(concat_ws('|',id::text,student_id::text,
      billing_month,billing_week_start_date::text,duration_hours::text,unit_price::text,
      lesson_fee::text,billing_month_source,to_char(billing_month_decided_at AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),E'\n' ORDER BY student_id::text,billing_month,
      billing_week_start_date,id::text)||E'\n','UTF8')),'hex')
  INTO v_candidate_count,v_candidate_hours,v_candidate_fee,v_candidate_md5,v_manifest_sha
  FROM candidate;
  IF v_candidate_count <> 118 OR v_candidate_hours <> 254 OR v_candidate_fee <> 2474000
     OR v_candidate_md5 <> '77f697f82e547d84dcabf88a3c868aa1'
     OR v_manifest_sha <> 'f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1' THEN
    RAISE EXCEPTION 'B1-B schema preflight: fixed candidate boundary mismatch';
  END IF;
  SELECT count(*),md5(string_agg(id::text,',' ORDER BY id::text))
  INTO v_legacy_count,v_legacy_md5
  FROM public.school_lesson_records
  WHERE lesson_type = 'planned' AND num_nonnulls(billing_month,billing_week_start_date,
    student_settlement_month,billing_month_source,billing_month_decided_at) = 0;
  IF v_legacy_count <> 279 OR v_legacy_md5 <> '0975fdc91b533680e5ccc909f076ac62' THEN
    RAISE EXCEPTION 'B1-B schema preflight: legacy 279 boundary mismatch';
  END IF;
  IF (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
       FROM public.school_student_tuition_bills x) <> '0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
       FROM public.school_income_records x) <> '2a4897b752f272b1f192045418b4940c'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
       FROM public.school_student_tuition_bill_lessons x) <> '09dfee7d8833e09384fb41a84f2959e0'
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) <> 42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
       FROM public.school_student_tuition_historical_lesson_exclusions x) <> '680b6e5aaa718569aee4c36fe1cdc058' THEN
    RAISE EXCEPTION 'B1-B schema preflight: School financial-chain snapshot mismatch';
  END IF;
END
$preflight$;

CREATE TABLE public.school_lesson_venues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  display_name text NOT NULL,
  delivery_mode text NOT NULL,
  aircon_eligible boolean NOT NULL,
  effective_from date NOT NULL,
  effective_to date,
  is_active boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  created_by uuid,
  CONSTRAINT school_lesson_venues_code_key UNIQUE (code),
  CONSTRAINT school_lesson_venues_code_nonblank CHECK (btrim(code) <> ''),
  CONSTRAINT school_lesson_venues_display_name_nonblank CHECK (btrim(display_name) <> ''),
  CONSTRAINT school_lesson_venues_delivery_mode_check CHECK (delivery_mode IN ('onsite','online')),
  CONSTRAINT school_lesson_venues_effective_period_check CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX school_lesson_venues_active_effective_idx
  ON public.school_lesson_venues (is_active, effective_from, effective_to);

CREATE TABLE public.school_student_aircon_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL,
  unit_price_jpy integer NOT NULL,
  effective_from date NOT NULL,
  effective_to date,
  effective_period daterange GENERATED ALWAYS AS
    (daterange(effective_from, effective_to, '[)')) STORED,
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  created_by uuid,
  closed_at timestamptz,
  closed_by uuid,
  superseded_by_rate_id uuid,
  CONSTRAINT school_student_aircon_rates_student_id_fkey
    FOREIGN KEY (student_id) REFERENCES public.school_students(id)
    ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT school_student_aircon_rates_superseded_by_fkey
    FOREIGN KEY (superseded_by_rate_id) REFERENCES public.school_student_aircon_rates(id)
    ON DELETE RESTRICT,
  CONSTRAINT school_student_aircon_rates_unit_price_check
    CHECK (unit_price_jpy BETWEEN 0 AND 660),
  CONSTRAINT school_student_aircon_rates_effective_period_check
    CHECK (effective_to IS NULL OR effective_to > effective_from),
  CONSTRAINT school_student_aircon_rates_reason_nonblank CHECK (btrim(reason) <> ''),
  CONSTRAINT school_student_aircon_rates_no_overlap
    EXCLUDE USING gist (
      student_id extensions.gist_uuid_ops WITH =,
      effective_period pg_catalog.range_ops WITH &&
    )
);

CREATE INDEX school_student_aircon_rates_student_effective_idx
  ON public.school_student_aircon_rates (student_id, effective_from, effective_to);
CREATE INDEX school_student_aircon_rates_superseded_by_idx
  ON public.school_student_aircon_rates (superseded_by_rate_id);

ALTER TABLE public.school_lesson_records
  ADD COLUMN base_lesson_fee_jpy numeric,
  ADD COLUMN lesson_venue_id uuid,
  ADD COLUMN aircon_charge_status text,
  ADD COLUMN aircon_rate_id uuid,
  ADD COLUMN aircon_unit_price_jpy_snapshot integer,
  ADD COLUMN aircon_billable_hours_snapshot numeric,
  ADD COLUMN aircon_fee_jpy numeric,
  ADD COLUMN aircon_calculated_at timestamptz,
  ADD COLUMN fee_calculation_version text,
  ADD COLUMN fee_block_reason_code text,
  ADD COLUMN fee_components_frozen_at timestamptz,
  ADD CONSTRAINT school_lesson_records_lesson_venue_id_fkey
    FOREIGN KEY (lesson_venue_id) REFERENCES public.school_lesson_venues(id) ON DELETE RESTRICT,
  ADD CONSTRAINT school_lesson_records_aircon_rate_id_fkey
    FOREIGN KEY (aircon_rate_id) REFERENCES public.school_student_aircon_rates(id) ON DELETE RESTRICT,
  ADD CONSTRAINT school_lesson_records_base_fee_nonnegative
    CHECK (base_lesson_fee_jpy IS NULL OR base_lesson_fee_jpy >= 0),
  ADD CONSTRAINT school_lesson_records_aircon_status_check
    CHECK (aircon_charge_status IS NULL OR aircon_charge_status IN (
      'pending_schedule','pending_venue','unconfigured','not_applicable','configured_zero','calculated')),
  ADD CONSTRAINT school_lesson_records_aircon_unit_price_check
    CHECK (aircon_unit_price_jpy_snapshot IS NULL OR aircon_unit_price_jpy_snapshot BETWEEN 0 AND 660),
  ADD CONSTRAINT school_lesson_records_aircon_hours_nonnegative
    CHECK (aircon_billable_hours_snapshot IS NULL OR aircon_billable_hours_snapshot >= 0),
  ADD CONSTRAINT school_lesson_records_aircon_fee_nonnegative
    CHECK (aircon_fee_jpy IS NULL OR aircon_fee_jpy >= 0),
  ADD CONSTRAINT school_lesson_records_fee_version_nonblank
    CHECK (fee_calculation_version IS NULL OR btrim(fee_calculation_version) <> ''),
  ADD CONSTRAINT school_lesson_records_fee_block_reason_nonblank
    CHECK (fee_block_reason_code IS NULL OR btrim(fee_block_reason_code) <> '');

CREATE INDEX school_lesson_records_lesson_venue_id_idx
  ON public.school_lesson_records (lesson_venue_id) WHERE lesson_venue_id IS NOT NULL;
CREATE INDEX school_lesson_records_aircon_rate_id_idx
  ON public.school_lesson_records (aircon_rate_id) WHERE aircon_rate_id IS NOT NULL;

ALTER TABLE public.school_student_tuition_bill_lessons
  ADD COLUMN base_lesson_fee_jpy_snapshot numeric,
  ADD COLUMN aircon_rate_id_snapshot uuid,
  ADD COLUMN aircon_unit_price_jpy_snapshot integer,
  ADD COLUMN aircon_billable_hours_snapshot numeric,
  ADD COLUMN aircon_fee_jpy_snapshot numeric,
  ADD COLUMN fee_calculation_version_snapshot text,
  ADD COLUMN lesson_venue_id_snapshot uuid,
  ADD COLUMN lesson_venue_code_snapshot text,
  ADD CONSTRAINT school_bill_lessons_base_fee_nonnegative
    CHECK (base_lesson_fee_jpy_snapshot IS NULL OR base_lesson_fee_jpy_snapshot >= 0),
  ADD CONSTRAINT school_bill_lessons_aircon_unit_price_check
    CHECK (aircon_unit_price_jpy_snapshot IS NULL OR aircon_unit_price_jpy_snapshot BETWEEN 0 AND 660),
  ADD CONSTRAINT school_bill_lessons_aircon_hours_nonnegative
    CHECK (aircon_billable_hours_snapshot IS NULL OR aircon_billable_hours_snapshot >= 0),
  ADD CONSTRAINT school_bill_lessons_aircon_fee_nonnegative
    CHECK (aircon_fee_jpy_snapshot IS NULL OR aircon_fee_jpy_snapshot >= 0),
  ADD CONSTRAINT school_bill_lessons_fee_version_nonblank
    CHECK (fee_calculation_version_snapshot IS NULL OR btrim(fee_calculation_version_snapshot) <> ''),
  ADD CONSTRAINT school_bill_lessons_venue_code_nonblank
    CHECK (lesson_venue_code_snapshot IS NULL OR btrim(lesson_venue_code_snapshot) <> '');

CREATE INDEX school_bill_lessons_aircon_rate_snapshot_idx
  ON public.school_student_tuition_bill_lessons (aircon_rate_id_snapshot)
  WHERE aircon_rate_id_snapshot IS NOT NULL;
CREATE INDEX school_bill_lessons_venue_snapshot_idx
  ON public.school_student_tuition_bill_lessons (lesson_venue_id_snapshot)
  WHERE lesson_venue_id_snapshot IS NOT NULL;

CREATE TABLE public.school_planned_writer_commands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL,
  operation_type text NOT NULL,
  payload_hash text NOT NULL,
  status text NOT NULL,
  result_lesson_id uuid,
  result_batch_id uuid,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  created_by uuid,
  completed_at timestamptz,
  error_code text,
  CONSTRAINT school_planned_writer_commands_request_id_key UNIQUE (request_id),
  CONSTRAINT school_planned_writer_commands_operation_nonblank CHECK (btrim(operation_type) <> ''),
  CONSTRAINT school_planned_writer_commands_payload_hash_check CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT school_planned_writer_commands_status_check CHECK (status IN ('pending','completed','failed')),
  CONSTRAINT school_planned_writer_commands_result_lesson_fkey
    FOREIGN KEY (result_lesson_id) REFERENCES public.school_lesson_records(id) ON DELETE RESTRICT,
  CONSTRAINT school_planned_writer_commands_error_code_nonblank
    CHECK (error_code IS NULL OR btrim(error_code) <> '')
);

CREATE INDEX school_planned_writer_commands_status_created_idx
  ON public.school_planned_writer_commands (status, created_at);
CREATE INDEX school_planned_writer_commands_result_lesson_idx
  ON public.school_planned_writer_commands (result_lesson_id)
  WHERE result_lesson_id IS NOT NULL;

CREATE TABLE public.school_venue_rate_change_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action text NOT NULL,
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  old_snapshot jsonb,
  new_snapshot jsonb,
  actor_id uuid,
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CONSTRAINT school_venue_rate_change_audit_action_nonblank CHECK (btrim(action) <> ''),
  CONSTRAINT school_venue_rate_change_audit_target_type_check CHECK (target_type IN ('venue','rate')),
  CONSTRAINT school_venue_rate_change_audit_reason_nonblank CHECK (btrim(reason) <> '')
);

CREATE INDEX school_venue_rate_change_audit_target_created_idx
  ON public.school_venue_rate_change_audit (target_type, target_id, created_at);

CREATE FUNCTION public.school_resolve_planned_billing_attribution(
  p_scheduled_lesson_date date,
  p_billing_week_start_date date
)
RETURNS TABLE (
  billing_week_start_date date,
  billing_month text,
  student_settlement_month text,
  billing_month_source text
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF (p_scheduled_lesson_date IS NULL) = (p_billing_week_start_date IS NULL) THEN
    RAISE EXCEPTION 'exactly one of scheduled lesson date or billing week start date is required';
  END IF;
  IF p_scheduled_lesson_date IS NOT NULL THEN
    billing_week_start_date := p_scheduled_lesson_date
      - ((extract(isodow FROM p_scheduled_lesson_date)::integer - 1));
    billing_month_source := 'scheduled_date_at_create';
  ELSE
    IF extract(isodow FROM p_billing_week_start_date) <> 1 THEN
      RAISE EXCEPTION 'explicit billing week start date must be an ISO Monday';
    END IF;
    billing_week_start_date := p_billing_week_start_date;
    billing_month_source := 'explicit_billing_week_at_create';
  END IF;
  billing_month := to_char(billing_week_start_date, 'YYYY-MM');
  student_settlement_month := billing_month;
  RETURN NEXT;
END
$function$;

CREATE FUNCTION public.school_resolve_planned_duration(
  p_start_time text,
  p_end_time text,
  p_explicit_duration_hours numeric
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_start time without time zone;
  v_end time without time zone;
  v_duration numeric;
BEGIN
  IF p_start_time IS NULL AND p_end_time IS NULL THEN
    IF p_explicit_duration_hours IS NULL THEN
      RAISE EXCEPTION 'explicit duration is required when both times are absent';
    END IF;
    v_duration := p_explicit_duration_hours;
  ELSIF p_start_time IS NULL OR p_end_time IS NULL THEN
    RAISE EXCEPTION 'start time and end time must be supplied together';
  ELSE
    IF p_explicit_duration_hours IS NOT NULL THEN
      RAISE EXCEPTION 'explicit duration must be null when both times are supplied';
    END IF;
    IF p_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       OR p_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
      RAISE EXCEPTION 'times must use strict HH24:MI format';
    END IF;
    v_start := p_start_time::time;
    v_end := p_end_time::time;
    IF v_end <= v_start THEN
      RAISE EXCEPTION 'end time must be later than start time; cross-midnight is not allowed';
    END IF;
    v_duration := extract(epoch FROM (v_end - v_start)) / 3600;
  END IF;
  IF v_duration < 2 OR v_duration <> trunc(v_duration) THEN
    RAISE EXCEPTION 'planned duration must be an integer number of hours and at least 2';
  END IF;
  RETURN v_duration;
END
$function$;

CREATE FUNCTION public.school_calculate_planned_fee_components(
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
DECLARE
  v_duration numeric;
  v_venue public.school_lesson_venues%ROWTYPE;
  v_rate_id uuid;
  v_rate_price integer;
BEGIN
  v_duration := public.school_resolve_planned_duration(NULL, NULL, p_authoritative_duration_hours);
  IF p_unit_price IS NULL OR p_unit_price < 0 THEN
    RAISE EXCEPTION 'unit price must be non-null and nonnegative';
  END IF;
  base_lesson_fee_jpy := p_unit_price * v_duration;
  fee_calculation_version := 'planned_fee_components_v1';

  IF p_scheduled_lesson_date IS NULL THEN
    aircon_charge_status := 'pending_schedule';
    fee_block_reason_code := 'AIRCON_SCHEDULE_REQUIRED';
    RETURN NEXT;
    RETURN;
  END IF;
  IF p_lesson_venue_id IS NULL THEN
    aircon_charge_status := 'pending_venue';
    fee_block_reason_code := 'AIRCON_VENUE_REQUIRED';
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT v.* INTO v_venue
  FROM public.school_lesson_venues v
  WHERE v.id = p_lesson_venue_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lesson venue does not exist';
  END IF;

  IF p_scheduled_lesson_date < DATE '2026-08-01'
     OR extract(isodow FROM p_scheduled_lesson_date) NOT IN (6,7)
     OR v_venue.delivery_mode <> 'onsite'
     OR v_venue.aircon_eligible IS NOT TRUE
     OR v_venue.is_active IS NOT TRUE
     OR p_scheduled_lesson_date < v_venue.effective_from
     OR (v_venue.effective_to IS NOT NULL AND p_scheduled_lesson_date >= v_venue.effective_to) THEN
    aircon_charge_status := 'not_applicable';
    aircon_fee_jpy := 0;
    lesson_total_fee_jpy := base_lesson_fee_jpy;
    fee_block_reason_code := 'AIRCON_NOT_APPLICABLE';
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT r.id,r.unit_price_jpy INTO v_rate_id,v_rate_price
  FROM public.school_student_aircon_rates r
  WHERE r.student_id = p_student_id
    AND p_scheduled_lesson_date <@ r.effective_period;
  IF NOT FOUND THEN
    aircon_charge_status := 'unconfigured';
    fee_block_reason_code := 'AIRCON_RATE_UNCONFIGURED';
    RETURN NEXT;
    RETURN;
  END IF;

  aircon_rate_id := v_rate_id;
  aircon_unit_price_jpy_snapshot := v_rate_price;
  aircon_billable_hours_snapshot := v_duration;
  aircon_fee_jpy := v_rate_price * v_duration;
  lesson_total_fee_jpy := base_lesson_fee_jpy + aircon_fee_jpy;
  IF v_rate_price = 0 THEN
    aircon_charge_status := 'configured_zero';
  ELSE
    aircon_charge_status := 'calculated';
  END IF;
  RETURN NEXT;
END
$function$;

ALTER TABLE public.school_lesson_venues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_student_aircon_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_planned_writer_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_venue_rate_change_audit ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.school_lesson_venues FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.school_student_aircon_rates FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.school_planned_writer_commands FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.school_venue_rate_change_audit FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.school_resolve_planned_billing_attribution(date,date)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.school_resolve_planned_duration(text,text,numeric)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.school_calculate_planned_fee_components(uuid,date,uuid,numeric,numeric)
  FROM PUBLIC, anon, authenticated, service_role;

DO $verify$
DECLARE
  v_function record;
BEGIN
  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname IN (
        'school_lesson_venues','school_student_aircon_rates',
        'school_planned_writer_commands','school_venue_rate_change_audit')) <> 4 THEN
    RAISE EXCEPTION 'B1-B schema verify: four new tables were not created exactly';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_lesson_records'
        AND column_name IN ('base_lesson_fee_jpy','lesson_venue_id','aircon_charge_status',
          'aircon_rate_id','aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy','aircon_calculated_at','fee_calculation_version',
          'fee_block_reason_code','fee_components_frozen_at')
        AND is_nullable = 'YES' AND column_default IS NULL) <> 11 THEN
    RAISE EXCEPTION 'B1-B schema verify: lesson additive columns mismatch';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
        AND column_name IN ('base_lesson_fee_jpy_snapshot','aircon_rate_id_snapshot',
          'aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy_snapshot','fee_calculation_version_snapshot',
          'lesson_venue_id_snapshot','lesson_venue_code_snapshot')
        AND is_nullable = 'YES' AND column_default IS NULL) <> 8 THEN
    RAISE EXCEPTION 'B1-B schema verify: relation additive columns mismatch';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname IN (
        'school_resolve_planned_billing_attribution','school_resolve_planned_duration',
        'school_calculate_planned_fee_components')) <> 3 THEN
    RAISE EXCEPTION 'B1-B schema verify: helper count mismatch';
  END IF;
  IF (SELECT count(*) FROM pg_constraint
      WHERE conname = 'school_student_aircon_rates_no_overlap'
        AND contype = 'x' AND conrelid = 'public.school_student_aircon_rates'::regclass) <> 1 THEN
    RAISE EXCEPTION 'B1-B schema verify: rate exclusion constraint missing';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_venues)
     +(SELECT count(*) FROM public.school_student_aircon_rates)
     +(SELECT count(*) FROM public.school_planned_writer_commands)
     +(SELECT count(*) FROM public.school_venue_rate_change_audit) <> 0 THEN
    RAISE EXCEPTION 'B1-B schema verify: a new table is not empty';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_records WHERE
      num_nonnulls(base_lesson_fee_jpy,lesson_venue_id,aircon_charge_status,aircon_rate_id,
        aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,aircon_fee_jpy,
        aircon_calculated_at,fee_calculation_version,fee_block_reason_code,
        fee_components_frozen_at) > 0) <> 0 THEN
    RAISE EXCEPTION 'B1-B schema verify: historical lesson component values are not all null';
  END IF;
  IF (SELECT count(*) FROM public.school_student_tuition_bill_lessons WHERE
      num_nonnulls(base_lesson_fee_jpy_snapshot,aircon_rate_id_snapshot,
        aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
        aircon_fee_jpy_snapshot,fee_calculation_version_snapshot,
        lesson_venue_id_snapshot,lesson_venue_code_snapshot) > 0) <> 0 THEN
    RAISE EXCEPTION 'B1-B schema verify: historical relation component values are not all null';
  END IF;

  FOR v_function IN
    SELECT p.oid,p.proowner,p.prosecdef,p.proconfig,r.rolname AS owner
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'public' AND p.proname IN (
      'school_resolve_planned_billing_attribution','school_resolve_planned_duration',
      'school_calculate_planned_fee_components')
  LOOP
    IF v_function.prosecdef OR v_function.owner NOT IN ('postgres','supabase_admin')
       OR NOT coalesce(v_function.proconfig @> ARRAY['search_path=pg_catalog, public'],false) THEN
      RAISE EXCEPTION 'B1-B schema verify: helper owner/security/search_path mismatch for %', v_function.oid;
    END IF;
    IF EXISTS (SELECT 1 FROM aclexplode(coalesce(
          (SELECT proacl FROM pg_proc WHERE oid = v_function.oid),
          acldefault('f',v_function.proowner))) a
        WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
       OR has_function_privilege('anon',v_function.oid,'EXECUTE')
       OR has_function_privilege('authenticated',v_function.oid,'EXECUTE')
       OR has_function_privilege('service_role',v_function.oid,'EXECUTE') THEN
      RAISE EXCEPTION 'B1-B schema verify: helper has an unapproved execute grant for %', v_function.oid;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
    WHERE n.nspname = 'public' AND c.relname IN (
      'school_lesson_venues','school_student_aircon_rates',
      'school_planned_writer_commands','school_venue_rate_change_audit')
      AND a.grantee = 0 AND a.privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE')
  ) OR EXISTS (
    SELECT 1 FROM unnest(ARRAY[
      'public.school_lesson_venues','public.school_student_aircon_rates',
      'public.school_planned_writer_commands','public.school_venue_rate_change_audit']) AS x(tab)
    WHERE has_table_privilege('anon',x.tab,'INSERT,UPDATE,DELETE,TRUNCATE')
       OR has_table_privilege('authenticated',x.tab,'INSERT,UPDATE,DELETE,TRUNCATE')
       OR has_table_privilege('service_role',x.tab,'INSERT,UPDATE,DELETE,TRUNCATE')
  ) THEN
    RAISE EXCEPTION 'B1-B schema verify: a new table has an unapproved write grant';
  END IF;
  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname IN (
        'school_lesson_venues','school_student_aircon_rates',
        'school_planned_writer_commands','school_venue_rate_change_audit')
        AND c.relrowsecurity) <> 4 THEN
    RAISE EXCEPTION 'B1-B schema verify: RLS is not enabled on every new table';
  END IF;
END
$verify$;

DO $unchanged_boundary$
DECLARE
  v_old_rpc_count bigint;
  v_old_rpc_definition_md5 text;
  v_old_rpc_acl_md5 text;
  v_lesson_acl_md5 text;
  v_lesson_policy_count bigint;
  v_lesson_policy_md5 text;
  v_relation_trigger_md5 text;
BEGIN
  WITH rpc AS (
    SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS args,
      pg_get_functiondef(p.oid) AS definition,p.proacl,p.prosecdef,p.proconfig,r.rolname AS owner
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'public' AND p.proname IN (
      'school_create_planned_lesson_record','school_create_planned_lesson_record_with_venue',
      'school_generate_planned_lessons_batch','school_generate_planned_lessons_batch_with_venue',
      'school_import_lesson_records_batch','school_import_lesson_records_batch_with_venue',
      'school_update_lesson_record_guarded','school_update_lesson_record_guarded_with_venue',
      'school_normalize_lesson_schedule_venue','school_generate_student_tuition_bill')
  ), policies AS (
    SELECT policyname,permissive,roles,cmd,qual,with_check
    FROM pg_policies WHERE schemaname = 'public' AND tablename = 'school_lesson_records'
  )
  SELECT
    (SELECT count(*) FROM rpc),
    (SELECT md5(string_agg(proname||'|'||args||'|'||md5(definition),E'\n' ORDER BY proname,args)) FROM rpc),
    (SELECT md5(string_agg(proname||'|'||args||'|'||coalesce(proacl::text,'NULL')||'|'||prosecdef||'|'||coalesce(proconfig::text,'NULL')||'|'||owner,E'\n' ORDER BY proname,args)) FROM rpc),
    (SELECT md5(coalesce(relacl::text,'NULL')||'|'||relrowsecurity||'|'||relforcerowsecurity) FROM pg_class WHERE oid = 'public.school_lesson_records'::regclass),
    (SELECT count(*) FROM policies),
    (SELECT md5(coalesce(string_agg(policyname||'|'||permissive||'|'||roles::text||'|'||cmd||'|'||coalesce(qual,'NULL')||'|'||coalesce(with_check,'NULL'),E'\n' ORDER BY policyname),'')) FROM policies),
    (SELECT md5(coalesce(string_agg(t.tgname||'|'||pg_get_triggerdef(t.oid,true)||'|'||md5(pg_get_functiondef(t.tgfoid)),E'\n' ORDER BY t.tgname),'')) FROM pg_trigger t WHERE t.tgrelid = 'public.school_student_tuition_bill_lessons'::regclass AND NOT t.tgisinternal)
  INTO v_old_rpc_count,v_old_rpc_definition_md5,v_old_rpc_acl_md5,
    v_lesson_acl_md5,v_lesson_policy_count,v_lesson_policy_md5,v_relation_trigger_md5;
  IF v_old_rpc_count <> 11
     OR v_old_rpc_definition_md5 <> '8ecb87eeab8dbf2953a985038927375d'
     OR v_old_rpc_acl_md5 <> '200f9f7c5cb7983b2aa90aeec65693b2'
     OR v_lesson_acl_md5 <> 'e4b4638d16b9a1a0e6c2662833bed732'
     OR v_lesson_policy_count <> 1
     OR v_lesson_policy_md5 <> '664065c128a736b78af24bec527dbf2c'
     OR v_relation_trigger_md5 <> '5948fe7078a69ef943990208bd5aa532' THEN
    RAISE EXCEPTION 'B1-B schema verify: old RPC/ACL/RLS/trigger fingerprint changed';
  END IF;
END
$unchanged_boundary$;
-- B1_B_DDL_BODY_END

\if :b1_b_rehearsal
  SET CONSTRAINTS school_student_aircon_rates_student_id_fkey DEFERRED;

  INSERT INTO public.school_lesson_venues
    (id,code,display_name,delivery_mode,aircon_eligible,effective_from,effective_to,is_active,created_by)
  VALUES
    ('a1000000-0000-4000-8000-000000000001','codex-test-onsite','Codex Test Onsite','onsite',true,'2026-01-01',NULL,true,NULL),
    ('a1000000-0000-4000-8000-000000000002','codex-test-online','Codex Test Online','online',false,'2026-01-01',NULL,true,NULL);

  INSERT INTO public.school_student_aircon_rates
    (id,student_id,unit_price_jpy,effective_from,effective_to,reason)
  VALUES
    ('b1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',0,'2026-08-01','2026-09-01','codex-test zero rate'),
    ('b1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000001',660,'2026-09-01',NULL,'codex-test max rate'),
    ('b1000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000002',660,'2026-08-01','2026-09-01','codex-test other student');

  INSERT INTO public.school_planned_writer_commands
    (id,request_id,operation_type,payload_hash,status,created_by)
  VALUES
    ('d1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000002',
      'codex-test','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','pending',NULL);
  INSERT INTO public.school_venue_rate_change_audit
    (id,action,target_type,target_id,old_snapshot,new_snapshot,actor_id,reason)
  VALUES
    ('e1000000-0000-4000-8000-000000000001','codex-test','venue',
      'a1000000-0000-4000-8000-000000000001',NULL,'{"test":true}'::jsonb,NULL,'codex-test rehearsal');

  DO $rehearsal_tests$
  DECLARE
    v_result record;
  BEGIN
    BEGIN
      INSERT INTO public.school_student_aircon_rates
        (id,student_id,unit_price_jpy,effective_from,effective_to,reason)
      VALUES ('b1000000-0000-4000-8000-000000000004','c1000000-0000-4000-8000-000000000003',-1,'2026-08-01','2026-09-01','codex-test negative');
      RAISE EXCEPTION 'rehearsal: negative rate unexpectedly accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
      INSERT INTO public.school_student_aircon_rates
        (id,student_id,unit_price_jpy,effective_from,effective_to,reason)
      VALUES ('b1000000-0000-4000-8000-000000000005','c1000000-0000-4000-8000-000000000003',661,'2026-08-01','2026-09-01','codex-test above max');
      RAISE EXCEPTION 'rehearsal: rate 661 unexpectedly accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
      INSERT INTO public.school_student_aircon_rates
        (id,student_id,unit_price_jpy,effective_from,effective_to,reason)
      VALUES ('b1000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000001',100,'2026-08-15','2026-08-20','codex-test overlap');
      RAISE EXCEPTION 'rehearsal: overlapping rate unexpectedly accepted';
    EXCEPTION WHEN exclusion_violation THEN NULL;
    END;

    IF public.school_resolve_planned_duration(NULL,NULL,2) <> 2
       OR public.school_resolve_planned_duration(NULL,NULL,3) <> 3
       OR public.school_resolve_planned_duration('15:00','17:00',NULL) <> 2 THEN
      RAISE EXCEPTION 'rehearsal: approved duration case mismatch';
    END IF;
    BEGIN PERFORM public.school_resolve_planned_duration(NULL,NULL,1);
      RAISE EXCEPTION 'rehearsal: duration 1 unexpectedly accepted';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rehearsal:%' THEN RAISE; END IF; END;
    BEGIN PERFORM public.school_resolve_planned_duration(NULL,NULL,1.5);
      RAISE EXCEPTION 'rehearsal: duration 1.5 unexpectedly accepted';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rehearsal:%' THEN RAISE; END IF; END;
    BEGIN PERFORM public.school_resolve_planned_duration(NULL,NULL,2.5);
      RAISE EXCEPTION 'rehearsal: duration 2.5 unexpectedly accepted';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rehearsal:%' THEN RAISE; END IF; END;
    BEGIN PERFORM public.school_resolve_planned_duration('15:00','17:15',NULL);
      RAISE EXCEPTION 'rehearsal: noninteger time duration unexpectedly accepted';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rehearsal:%' THEN RAISE; END IF; END;
    BEGIN PERFORM public.school_resolve_planned_duration('15:00',NULL,NULL);
      RAISE EXCEPTION 'rehearsal: one-sided time unexpectedly accepted';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rehearsal:%' THEN RAISE; END IF; END;
    BEGIN PERFORM public.school_resolve_planned_duration('17:00','15:00',NULL);
      RAISE EXCEPTION 'rehearsal: reversed time unexpectedly accepted';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rehearsal:%' THEN RAISE; END IF; END;

    SELECT * INTO v_result FROM public.school_resolve_planned_billing_attribution('2026-08-06',NULL);
    IF v_result.billing_week_start_date <> DATE '2026-08-03'
       OR v_result.billing_month <> '2026-08'
       OR v_result.student_settlement_month <> '2026-08'
       OR v_result.billing_month_source <> 'scheduled_date_at_create' THEN
      RAISE EXCEPTION 'rehearsal: scheduled billing attribution mismatch';
    END IF;
    SELECT * INTO v_result FROM public.school_resolve_planned_billing_attribution(NULL,'2026-08-03');
    IF v_result.billing_month_source <> 'explicit_billing_week_at_create' THEN
      RAISE EXCEPTION 'rehearsal: explicit billing attribution mismatch';
    END IF;
    BEGIN PERFORM * FROM public.school_resolve_planned_billing_attribution(NULL,'2026-08-04');
      RAISE EXCEPTION 'rehearsal: non-Monday week unexpectedly accepted';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rehearsal:%' THEN RAISE; END IF; END;
    BEGIN PERFORM * FROM public.school_resolve_planned_billing_attribution('2026-08-06','2026-08-03');
      RAISE EXCEPTION 'rehearsal: dual billing inputs unexpectedly accepted';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rehearsal:%' THEN RAISE; END IF; END;

    SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
      'c1000000-0000-4000-8000-000000000001','2026-08-01',
      'a1000000-0000-4000-8000-000000000001',2,1000);
    IF v_result.base_lesson_fee_jpy <> 2000 OR v_result.aircon_charge_status <> 'configured_zero'
       OR v_result.aircon_unit_price_jpy_snapshot <> 0
       OR v_result.aircon_billable_hours_snapshot <> 2 OR v_result.aircon_fee_jpy <> 0
       OR v_result.lesson_total_fee_jpy <> 2000 THEN
      RAISE EXCEPTION 'rehearsal: configured-zero fee components mismatch';
    END IF;
    SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
      'c1000000-0000-4000-8000-000000000001','2026-09-05',
      'a1000000-0000-4000-8000-000000000001',2,1000);
    IF v_result.base_lesson_fee_jpy <> 2000 OR v_result.aircon_charge_status <> 'calculated'
       OR v_result.aircon_unit_price_jpy_snapshot <> 660
       OR v_result.aircon_billable_hours_snapshot <> 2 OR v_result.aircon_fee_jpy <> 1320
       OR v_result.lesson_total_fee_jpy <> 3320 THEN
      RAISE EXCEPTION 'rehearsal: calculated fee components mismatch';
    END IF;
    SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
      'c1000000-0000-4000-8000-000000000099','2026-09-05',
      'a1000000-0000-4000-8000-000000000001',2,1000);
    IF v_result.aircon_charge_status <> 'unconfigured' OR v_result.aircon_fee_jpy IS NOT NULL
       OR v_result.lesson_total_fee_jpy IS NOT NULL THEN
      RAISE EXCEPTION 'rehearsal: missing rate was not distinguished from zero';
    END IF;
    SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
      'c1000000-0000-4000-8000-000000000001','2026-08-03',
      'a1000000-0000-4000-8000-000000000001',2,1000);
    IF v_result.aircon_charge_status <> 'not_applicable' OR v_result.aircon_fee_jpy <> 0
       OR v_result.lesson_total_fee_jpy <> 2000 THEN
      RAISE EXCEPTION 'rehearsal: weekday non-applicable fee mismatch';
    END IF;
  END
  $rehearsal_tests$;

  SELECT jsonb_build_object(
    'ddl_body_executed',true,
    'rate_zero_allowed',true,
    'rate_660_allowed',true,
    'rate_negative_rejected',true,
    'rate_661_rejected',true,
    'adjacent_allowed',true,
    'overlap_23p01_captured',true,
    'duration_tests',true,
    'billing_tests',true,
    'fee_tests',true,
    'permissions_tested',true
  ) AS rehearsal_summary;

  ROLLBACK;

  BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
  DO $residual$
  BEGIN
    IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname IN (
          'school_lesson_venues','school_student_aircon_rates',
          'school_planned_writer_commands','school_venue_rate_change_audit')) <> 0
       OR (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'school_lesson_records'
          AND column_name IN ('base_lesson_fee_jpy','lesson_venue_id','aircon_charge_status',
            'aircon_rate_id','aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
            'aircon_fee_jpy','aircon_calculated_at','fee_calculation_version',
            'fee_block_reason_code','fee_components_frozen_at')) <> 0
       OR (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
          AND column_name IN ('base_lesson_fee_jpy_snapshot','aircon_rate_id_snapshot',
            'aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
            'aircon_fee_jpy_snapshot','fee_calculation_version_snapshot',
            'lesson_venue_id_snapshot','lesson_venue_code_snapshot')) <> 0
       OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname IN (
          'school_resolve_planned_billing_attribution','school_resolve_planned_duration',
          'school_calculate_planned_fee_components')) <> 0 THEN
      RAISE EXCEPTION 'B1-B rehearsal residual: one or more B1-B objects persisted';
    END IF;
    IF (SELECT count(*) FROM pg_extension WHERE extname = 'btree_gist' AND extversion = '1.7') <> 1
       OR (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
       OR (SELECT count(*) FROM public.school_income_records) <> 42
       OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
       OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) <> 42 THEN
      RAISE EXCEPTION 'B1-B rehearsal residual: extension or business row counts changed';
    END IF;
  END
  $residual$;
  SELECT jsonb_build_object('rollback',true,'zero_residual',true,'extension_preserved',true) AS rehearsal_rollback;
  ROLLBACK;
\else
  COMMIT;
\endif
