-- School V2 tuition P0 R1D-F1: minimal planned attribution writer cutover.
-- Required psql variable: r1d_f1_commit=0 for caller-owned rehearsal transaction,
-- or r1d_f1_commit=1 for formal deployment.
-- No lesson row, evidence row, aircon row, settlement, financial row, or R0 gate
-- is changed by the formal deployment.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_f1_commit}
\else
  \echo 'R1D_F1_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
DECLARE
  v_writer_count bigint;
  v_writer_hash text;
BEGIN
  IF to_regprocedure('public.school_r1d_f1_planned_attribution_cutover_version()') IS NOT NULL
     OR to_regprocedure('public.school_enforce_r1d_f1_planned_attribution()') IS NOT NULL
     OR to_regprocedure('public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)') IS NOT NULL
     OR to_regprocedure('public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)') IS NOT NULL
     OR to_regprocedure('public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger
                WHERE tgrelid = 'public.school_lesson_records'::regclass
                  AND tgname = 'trg_school_lesson_r1d_f1_planned_attribution'
                  AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'R1D_F1_TARGET_OBJECT_ALREADY_EXISTS';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R1D_F1_R0_OR_CANDIDATE_CHANGED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_resolve_planned_billing_attribution(date,date)'::regprocedure
     )) <> '529c7387e63dcdb2e6972398c2d74dae'
     OR md5(pg_get_functiondef(
       'public.school_resolve_planned_duration(text,text,numeric)'::regprocedure
     )) <> '4f5b754585c9e3752639e6b0f2fa7a34' THEN
    RAISE EXCEPTION 'R1D_F1_APPROVED_HELPER_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type = 'planned'
        AND num_nonnulls(billing_month,billing_week_start_date,
          student_settlement_month,billing_month_source,billing_month_decided_at) = 5) <> 118
     OR (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type = 'planned'
        AND num_nonnulls(billing_month,billing_week_start_date,
          student_settlement_month,billing_month_source,billing_month_decided_at) = 0) <> 279
     OR (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type = 'planned'
        AND num_nonnulls(billing_month,billing_week_start_date,
          student_settlement_month,billing_month_source,billing_month_decided_at)
          BETWEEN 1 AND 4) <> 0
     OR (SELECT md5(string_agg(id::text,',' ORDER BY id::text))
         FROM public.school_lesson_records
         WHERE lesson_type = 'planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at) = 0)
        <> '0975fdc91b533680e5ccc909f076ac62' THEN
    RAISE EXCEPTION 'R1D_F1_PLANNED_BASELINE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence) <> 279
     OR (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence) <> 15 THEN
    RAISE EXCEPTION 'R1D_F1_EVIDENCE_COUNT_CHANGED';
  END IF;

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text,'<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(ARRAY[
      'school_create_planned_lesson_record','school_create_planned_lesson_record_with_venue',
      'school_generate_planned_lessons_batch','school_generate_planned_lessons_batch_with_venue',
      'school_import_lesson_records_batch','school_import_lesson_records_batch_with_venue',
      'school_update_lesson_record_guarded','school_update_lesson_record_guarded_with_venue'
    ]::text[])
  )
  SELECT count(*),md5(string_agg(concat_ws('|',signature,definition_md5,acl),E'\n' ORDER BY signature))
  INTO v_writer_count,v_writer_hash FROM functions;
  IF v_writer_count <> 8 OR v_writer_hash <> 'a3925ad6065af7900adaf4b3420df0c2' THEN
    RAISE EXCEPTION 'R1D_F1_PLANNED_WRITER_BASELINE_CHANGED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure
     )) <> '9f43c43cf0c98c2c1225e74fa8d8d49f'
     OR md5(pg_get_functiondef(
       'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure
     )) <> '693b1ef8c5adeff45bc94f03c5d9766e'
     OR md5(pg_get_functiondef(
       'public.school_import_lesson_records_batch(uuid,text,text,jsonb,text)'::regprocedure
     )) <> 'ce8f7d92b1558cc09d1027914c2983ef'
     OR md5(pg_get_functiondef(
       'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)'::regprocedure
     )) <> '73da60c85e9f74d20b601a0d1339badf'
     OR md5(pg_get_functiondef(
       'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure
     )) <> '5ae14921f400bf404eebfabcefdb631b'
     OR md5(pg_get_functiondef(
       'public.school_import_lesson_records_batch_with_venue(uuid,text,text,jsonb,text)'::regprocedure
     )) <> '448346b2f3949aa9e217fc5d9b512410'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> '4721315f96a96c47b2751c5cc75b5843'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure
     )) <> 'dca22a58c3efad550d87597385a143df' THEN
    RAISE EXCEPTION 'R1D_F1_INDIVIDUAL_WRITER_BASELINE_CHANGED';
  END IF;
END
$preflight$;

CREATE FUNCTION pg_temp.r1d_f1_existing_business_fingerprint()
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $fingerprint$
  SELECT jsonb_build_object(
    'lessons',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_lesson_records t),
    'planned_evidence',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.planned_lesson_id::text),''))) FROM public.school_legacy_planned_settlement_evidence t),
    'snapshot_evidence',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.settlement_snapshot_id::text),''))) FROM public.school_legacy_settlement_snapshot_basis_evidence t),
    'settlements',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_monthly_settlements t),
    'bills',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_tuition_bills t),
    'income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_income_records t),
    'relations',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_tuition_bill_lessons t),
    'historical_exclusions',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))) FROM public.school_student_tuition_historical_lesson_exclusions t),
    'gates',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.feature_key),''))) FROM public.school_feature_gates t),
    'aircon_tables',jsonb_build_array(
      (SELECT count(*) FROM public.school_lesson_venues),
      (SELECT count(*) FROM public.school_student_aircon_rates),
      (SELECT count(*) FROM public.school_planned_writer_commands),
      (SELECT count(*) FROM public.school_venue_rate_change_audit)
    )
  );
$fingerprint$;

CREATE TEMPORARY TABLE r1d_f1_existing_business_before ON COMMIT DROP AS
SELECT pg_temp.r1d_f1_existing_business_fingerprint() AS fingerprint;

ALTER FUNCTION public.school_create_planned_lesson_record(
  date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text
) RENAME TO school_create_planned_lesson_record_r1d_f1_legacy_core;

ALTER FUNCTION public.school_generate_planned_lessons_batch(
  uuid,uuid,uuid,date,date,jsonb,jsonb,text
) RENAME TO school_generate_planned_lessons_batch_r1d_f1_legacy_core;

ALTER FUNCTION public.school_import_lesson_records_batch(
  uuid,text,text,jsonb,text
) RENAME TO school_import_lesson_records_batch_r1d_f1_legacy_core;

REVOKE ALL ON FUNCTION public.school_create_planned_lesson_record_r1d_f1_legacy_core(
  date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(
  uuid,uuid,uuid,date,date,jsonb,jsonb,text
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.school_import_lesson_records_batch_r1d_f1_legacy_core(
  uuid,text,text,jsonb,text
) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.school_r1d_f1_planned_attribution_cutover_version()
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
  SELECT 'r1d_f1_planned_attribution_v1'::text;
$function$;

COMMENT ON FUNCTION public.school_r1d_f1_planned_attribution_cutover_version() IS
  'R1D-F1 immutable deployment version. New planned rows are canonical and must never be classified as legacy solely from null fields.';

REVOKE ALL ON FUNCTION public.school_r1d_f1_planned_attribution_cutover_version()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.school_enforce_r1d_f1_planned_attribution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_attribution record;
  v_duration numeric;
  v_evidence public.school_legacy_planned_settlement_evidence%ROWTYPE;
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.lesson_type IS DISTINCT FROM NEW.lesson_type
     AND (OLD.lesson_type = 'planned' OR NEW.lesson_type = 'planned') THEN
    RAISE EXCEPTION 'R1D_F1_PLANNED_LESSON_TYPE_IMMUTABLE';
  END IF;

  IF NEW.lesson_type IS DISTINCT FROM 'planned' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.lesson_date IS NULL THEN
      RAISE EXCEPTION 'R1D_F1_NEW_PLANNED_LESSON_DATE_REQUIRED';
    END IF;

    IF NEW.import_source LIKE 'lesson_planned_batch_generator%' THEN
      SELECT * INTO STRICT v_attribution
      FROM public.school_resolve_planned_billing_attribution(NULL,NEW.lesson_date);
    ELSE
      SELECT * INTO STRICT v_attribution
      FROM public.school_resolve_planned_billing_attribution(NEW.lesson_date,NULL);
    END IF;

    NEW.billing_week_start_date := v_attribution.billing_week_start_date;
    NEW.billing_month := v_attribution.billing_month;
    NEW.student_settlement_month := v_attribution.student_settlement_month;
    NEW.billing_month_source := v_attribution.billing_month_source;
    NEW.billing_month_decided_at := statement_timestamp();

    v_duration := public.school_resolve_planned_duration(
      NEW.start_time::text,
      NEW.end_time::text,
      CASE WHEN NEW.start_time IS NULL AND NEW.end_time IS NULL
           THEN NEW.duration_hours ELSE NULL END
    );
    IF NEW.duration_hours IS DISTINCT FROM v_duration THEN
      RAISE EXCEPTION 'R1D_F1_PLANNED_DURATION_NOT_DB_AUTHORITATIVE';
    END IF;
    RETURN NEW;
  END IF;

  SELECT evidence.* INTO v_evidence
  FROM public.school_legacy_planned_settlement_evidence evidence
  WHERE evidence.planned_lesson_id = OLD.id;

  IF FOUND THEN
    IF num_nonnulls(OLD.billing_month,OLD.billing_week_start_date,
         OLD.student_settlement_month,OLD.billing_month_source,
         OLD.billing_month_decided_at) <> 0
       OR num_nonnulls(NEW.billing_month,NEW.billing_week_start_date,
         NEW.student_settlement_month,NEW.billing_month_source,
         NEW.billing_month_decided_at) <> 0
       OR NEW.student_id IS DISTINCT FROM v_evidence.student_id_snapshot
       OR NEW.business_entity_id IS DISTINCT FROM v_evidence.business_entity_id_snapshot
       OR NEW.year_month IS DISTINCT FROM v_evidence.legacy_student_settlement_month
       OR md5(concat_ws('|',NEW.id::text,coalesce(NEW.student_id::text,'<NULL>'),
            coalesce(NEW.business_entity_id::text,'<NULL>'),
            coalesce(NEW.year_month,'<NULL>'),NEW.lesson_type,NEW.app_type))
          IS DISTINCT FROM v_evidence.lesson_identity_md5 THEN
      RAISE EXCEPTION 'R1D_F1_LEGACY_PLANNED_IDENTITY_OR_NULL_BUNDLE_IMMUTABLE';
    END IF;
    RETURN NEW;
  END IF;

  IF num_nonnulls(OLD.billing_month,OLD.billing_week_start_date,
       OLD.student_settlement_month,OLD.billing_month_source,
       OLD.billing_month_decided_at) <> 5
     OR NEW.billing_month IS DISTINCT FROM OLD.billing_month
     OR NEW.billing_week_start_date IS DISTINCT FROM OLD.billing_week_start_date
     OR NEW.student_settlement_month IS DISTINCT FROM OLD.student_settlement_month
     OR NEW.billing_month_source IS DISTINCT FROM OLD.billing_month_source
     OR NEW.billing_month_decided_at IS DISTINCT FROM OLD.billing_month_decided_at THEN
    RAISE EXCEPTION 'R1D_F1_CANONICAL_PLANNED_ATTRIBUTION_BUNDLE_IMMUTABLE';
  END IF;

  IF OLD.billing_month_source IN (
       'scheduled_date_at_create','explicit_billing_week_at_create'
     ) THEN
    v_duration := public.school_resolve_planned_duration(
      NEW.start_time::text,
      NEW.end_time::text,
      CASE WHEN NEW.start_time IS NULL AND NEW.end_time IS NULL
           THEN NEW.duration_hours ELSE NULL END
    );
    IF NEW.duration_hours IS DISTINCT FROM v_duration THEN
      RAISE EXCEPTION 'R1D_F1_CANONICAL_PLANNED_DURATION_INVALID';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

COMMENT ON FUNCTION public.school_enforce_r1d_f1_planned_attribution() IS
  'R1D-F1 table invariant: canonicalizes every new planned billing bundle, freezes canonical bundles, preserves fixed legacy evidence identities/null bundles, and isolates actual rows.';

REVOKE ALL ON FUNCTION public.school_enforce_r1d_f1_planned_attribution()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_school_lesson_r1d_f1_planned_attribution
BEFORE INSERT OR UPDATE ON public.school_lesson_records
FOR EACH ROW EXECUTE FUNCTION public.school_enforce_r1d_f1_planned_attribution();

COMMENT ON TRIGGER trg_school_lesson_r1d_f1_planned_attribution
ON public.school_lesson_records IS
  'R1D-F1 r1d_f1_planned_attribution_v1: new planned canonical attribution and duration invariant; existing legacy/canonical bundles remain frozen.';

CREATE FUNCTION public.school_create_planned_lesson_record(
  p_lesson_date date,
  p_student_id uuid,
  p_teacher_id uuid,
  p_subject_id uuid,
  p_business_entity_id uuid,
  p_start_time text DEFAULT NULL,
  p_end_time text DEFAULT NULL,
  p_duration_hours numeric DEFAULT 0,
  p_unit_price numeric DEFAULT 0,
  p_lesson_fee numeric DEFAULT NULL,
  p_status text DEFAULT 'planned',
  p_lesson_count integer DEFAULT NULL,
  p_lesson_content text DEFAULT NULL,
  p_note text DEFAULT NULL
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
  v_start text := nullif(trim(coalesce(p_start_time,'')),'');
  v_end text := nullif(trim(coalesce(p_end_time,'')),'');
  v_duration numeric;
BEGIN
  v_duration := public.school_resolve_planned_duration(
    v_start,v_end,
    CASE WHEN v_start IS NULL AND v_end IS NULL THEN p_duration_hours ELSE NULL END
  );
  RETURN QUERY SELECT *
  FROM public.school_create_planned_lesson_record_r1d_f1_legacy_core(
    p_lesson_date,p_student_id,p_teacher_id,p_subject_id,p_business_entity_id,
    v_start,v_end,v_duration,p_unit_price,p_lesson_fee,p_status,p_lesson_count,
    p_lesson_content,p_note
  );
END
$function$;

COMMENT ON FUNCTION public.school_create_planned_lesson_record(
  date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text
) IS
  'R1D-F1 planned-only facade. DB resolves integer duration; table invariant writes canonical billing attribution. External signature and return contract are unchanged.';

REVOKE ALL ON FUNCTION public.school_create_planned_lesson_record(
  date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_create_planned_lesson_record(
  date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text
) TO PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.school_generate_planned_lessons_batch(
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
  v_start text;
  v_end text;
  v_duration numeric;
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
    v_patterns := v_patterns || jsonb_build_array(
      jsonb_set(v_item.value,'{duration_hours}',to_jsonb(v_duration),true)
    );
  END LOOP;

  RETURN QUERY SELECT *
  FROM public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(
    p_generation_id,p_student_id,p_business_entity_id,p_start_date,p_end_date,
    v_patterns,p_excluded_occurrences,p_note
  );
END
$function$;

COMMENT ON FUNCTION public.school_generate_planned_lessons_batch(
  uuid,uuid,uuid,date,date,jsonb,jsonb,text
) IS
  'R1D-F1 batch facade. DB resolves each row integer duration; generated Monday is the explicit billing week used by the table invariant. Contract unchanged.';

REVOKE ALL ON FUNCTION public.school_generate_planned_lessons_batch(
  uuid,uuid,uuid,date,date,jsonb,jsonb,text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_generate_planned_lessons_batch(
  uuid,uuid,uuid,date,date,jsonb,jsonb,text
) TO authenticated, service_role;

CREATE FUNCTION public.school_import_lesson_records_batch(
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
  v_start text;
  v_end text;
  v_duration numeric;
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
    v_rows := v_rows || jsonb_build_array(
      jsonb_set(v_item.value,'{duration_hours}',to_jsonb(v_duration),true)
    );
  END LOOP;

  RETURN QUERY SELECT *
  FROM public.school_import_lesson_records_batch_r1d_f1_legacy_core(
    p_import_batch_id,p_source_file_name,p_source_file_hash,v_rows,p_note
  );
END
$function$;

COMMENT ON FUNCTION public.school_import_lesson_records_batch(
  uuid,text,text,jsonb,text
) IS
  'R1D-F1 import facade. DB resolves each row integer duration; imported lesson date is the scheduled-date attribution input. Contract unchanged.';

REVOKE ALL ON FUNCTION public.school_import_lesson_records_batch(
  uuid,text,text,jsonb,text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_import_lesson_records_batch(
  uuid,text,text,jsonb,text
) TO PUBLIC, anon, authenticated, service_role;

DO $verify$
DECLARE
  v_actual_count bigint;
  v_actual_hash text;
BEGIN
  IF public.school_r1d_f1_planned_attribution_cutover_version()
       <> 'r1d_f1_planned_attribution_v1'
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid = 'public.school_lesson_records'::regclass
           AND tgname = 'trg_school_lesson_r1d_f1_planned_attribution'
           AND NOT tgisinternal AND tgenabled = 'O') <> 1
     OR to_regprocedure('public.school_enforce_r1d_f1_planned_attribution()') IS NULL
     OR to_regprocedure('public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)') IS NULL
     OR to_regprocedure('public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)') IS NULL
     OR to_regprocedure('public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'R1D_F1_NEW_OBJECT_VERIFY_FAILED';
  END IF;

  IF has_function_privilege('anon',
       'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)','EXECUTE')
     OR has_function_privilege('authenticated',
       'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)','EXECUTE')
     OR has_function_privilege('service_role',
       'public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)','EXECUTE')
     OR has_function_privilege('anon',
       'public.school_enforce_r1d_f1_planned_attribution()','EXECUTE')
     OR has_function_privilege('authenticated',
       'public.school_r1d_f1_planned_attribution_cutover_version()','EXECUTE') THEN
    RAISE EXCEPTION 'R1D_F1_INTERNAL_FUNCTION_PRIVILEGE_FAILED';
  END IF;

  IF NOT has_function_privilege('authenticated',
       'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.school_import_lesson_records_batch(uuid,text,text,jsonb,text)','EXECUTE') THEN
    RAISE EXCEPTION 'R1D_F1_PUBLIC_WRITER_PRIVILEGE_FAILED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)'::regprocedure
     )) <> '73da60c85e9f74d20b601a0d1339badf'
     OR md5(pg_get_functiondef(
       'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure
     )) <> '5ae14921f400bf404eebfabcefdb631b'
     OR md5(pg_get_functiondef(
       'public.school_import_lesson_records_batch_with_venue(uuid,text,text,jsonb,text)'::regprocedure
     )) <> '448346b2f3949aa9e217fc5d9b512410'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> '4721315f96a96c47b2751c5cc75b5843'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure
     )) <> 'dca22a58c3efad550d87597385a143df' THEN
    RAISE EXCEPTION 'R1D_F1_UNCHANGED_WRAPPER_OR_UPDATE_FUNCTION_CHANGED';
  END IF;

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text,'<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(ARRAY[
      'school_create_actual_lesson_from_planned','school_create_cancelled_actual_lesson_from_planned',
      'school_create_partial_completed_actual_from_planned','school_create_lesson_credit_makeup_actual',
      'school_create_makeup_completed_actual_lesson_from_planned',
      'school_create_cross_month_makeup_completed_actual_from_planned',
      'school_update_lesson_record_guarded','school_update_lesson_record_guarded_with_venue'
    ]::text[])
  )
  SELECT count(*),md5(string_agg(concat_ws('|',signature,definition_md5,acl),E'\n' ORDER BY signature))
  INTO v_actual_count,v_actual_hash FROM functions;
  IF v_actual_count <> 8 OR v_actual_hash <> '4986090e0ba4e4706ea9ca4abd9580c5' THEN
    RAISE EXCEPTION 'R1D_F1_ACTUAL_WRITER_GROUP_CHANGED';
  END IF;

  IF (SELECT fingerprint FROM r1d_f1_existing_business_before)
       IS DISTINCT FROM pg_temp.r1d_f1_existing_business_fingerprint() THEN
    RAISE EXCEPTION 'R1D_F1_EXISTING_BUSINESS_DATA_CHANGED';
  END IF;
END
$verify$;

SELECT public.school_r1d_f1_planned_attribution_cutover_version() AS cutover_version,
       (SELECT count(*) FROM pg_trigger
        WHERE tgrelid = 'public.school_lesson_records'::regclass
          AND tgname = 'trg_school_lesson_r1d_f1_planned_attribution'
          AND NOT tgisinternal) AS invariant_trigger_count,
       true AS actual_writer_unchanged,
       true AS existing_business_data_unchanged;

\if :r1d_f1_commit
  COMMIT;
  \echo 'R1D_F1_DEPLOYMENT_COMMITTED'
\else
  \echo 'R1D_F1_REHEARSAL_TRANSACTION_OPEN'
\endif
