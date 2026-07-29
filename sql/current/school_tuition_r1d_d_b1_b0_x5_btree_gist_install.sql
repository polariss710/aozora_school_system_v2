\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
DECLARE
  v_b1_count bigint;
BEGIN
  IF (SELECT count(*) FROM pg_extension WHERE extname = 'btree_gist') <> 0 THEN
    RAISE EXCEPTION 'X5 preflight: btree_gist is already installed';
  END IF;
  IF (SELECT default_version FROM pg_available_extensions WHERE name = 'btree_gist') IS DISTINCT FROM '1.7' THEN
    RAISE EXCEPTION 'X5 preflight: btree_gist default version is not 1.7';
  END IF;
  IF to_regnamespace('extensions') IS NULL THEN
    RAISE EXCEPTION 'X5 preflight: extensions schema is absent';
  END IF;
  IF NOT has_database_privilege(current_user, current_database(), 'CREATE')
     OR NOT has_schema_privilege(current_user, to_regnamespace('extensions'), 'USAGE')
     OR NOT has_schema_privilege(current_user, to_regnamespace('extensions'), 'CREATE') THEN
    RAISE EXCEPTION 'X5 preflight: required database/schema privileges are absent';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_stat_activity
    WHERE pid <> pg_backend_pid() AND datname = current_database()
      AND (xact_start < clock_timestamp() - interval '5 minutes'
        OR cardinality(pg_blocking_pids(pid)) > 0 OR wait_event_type = 'Lock')
  ) THEN
    RAISE EXCEPTION 'X5 preflight: dangerous lock, blocker, or long transaction exists';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates WHERE
      (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only') OR
      (feature_key = 'student_tuition_generate' AND state = 'blocked') OR
      (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'X5 preflight: R0 feature gates do not match';
  END IF;
  IF md5(pg_get_functiondef(
      'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
    )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'X5 preflight: candidate function MD5 does not match';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) = 5) <> 118
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) = 0) <> 279
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) BETWEEN 1 AND 4) <> 0 THEN
    RAISE EXCEPTION 'X5 preflight: planned five-field counts do not match 118/279/0';
  END IF;
  SELECT
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND (c.relname IN ('school_lesson_venues','school_student_aircon_rates','school_planned_writer_commands','school_planned_writer_command_items') OR c.relname ILIKE 'school_%aircon%'))
    +(SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public'
     AND (column_name ILIKE '%aircon%' OR column_name IN ('base_lesson_fee_jpy','lesson_venue_id','fee_calculation_version','fee_block_reason_code','fee_components_frozen_at')))
    +(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
     AND (p.proname ILIKE 'school_resolve_planned_%' OR p.proname ILIKE 'school_calculate_planned_fee_components%'))
    +(SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
     WHERE n.nspname = 'public' AND c.conname ~* 'aircon|lesson_venue|planned_writer')
    +(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'i' AND c.relname ~* 'aircon|lesson_venue|planned_writer')
  INTO v_b1_count;
  IF v_b1_count <> 0 THEN
    RAISE EXCEPTION 'X5 preflight: B1-B target object count is %', v_b1_count;
  END IF;
  PERFORM set_config('x5.role_count', (SELECT count(*)::text FROM pg_roles), true);
  PERFORM set_config('x5.role_hash', (SELECT md5(coalesce(string_agg(md5(to_jsonb(r)::text), '' ORDER BY r.rolname), '')) FROM pg_roles r), true);
END
$preflight$;

CREATE EXTENSION btree_gist
WITH SCHEMA extensions
VERSION '1.7';

DO $verify$
BEGIN
  IF (SELECT count(*) FROM pg_extension x
      JOIN pg_namespace n ON n.oid = x.extnamespace
      JOIN pg_roles r ON r.oid = x.extowner
      WHERE x.extname = 'btree_gist' AND x.extversion = '1.7'
        AND n.nspname = 'extensions' AND r.rolname = 'supabase_admin') <> 1 THEN
    RAISE EXCEPTION 'X5 verify: extension version/schema/owner mismatch';
  END IF;
  IF (SELECT count(*) FROM pg_depend d JOIN pg_extension x ON x.oid = d.refobjid
      WHERE x.extname = 'btree_gist' AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e') <> 264 THEN
    RAISE EXCEPTION 'X5 verify: extension member count is not 264';
  END IF;
  IF (SELECT count(*) FROM pg_opclass o JOIN pg_am a ON a.oid = o.opcmethod
      JOIN pg_namespace n ON n.oid = o.opcnamespace
      WHERE n.nspname = 'extensions' AND o.opcname = 'gist_uuid_ops'
        AND o.opcintype = 'uuid'::regtype AND a.amname = 'gist') <> 1 THEN
    RAISE EXCEPTION 'X5 verify: extensions.gist_uuid_ops GiST support is absent';
  END IF;
  IF (SELECT count(*) FROM pg_opclass o JOIN pg_am a ON a.oid = o.opcmethod
      JOIN pg_namespace n ON n.oid = o.opcnamespace
      WHERE n.nspname = 'pg_catalog' AND o.opcname = 'range_ops'
        AND o.opcintype = 'anyrange'::regtype AND a.amname = 'gist') <> 1
     OR (SELECT count(*) FROM pg_operator o JOIN pg_namespace n ON n.oid = o.oprnamespace
      WHERE n.nspname = 'pg_catalog' AND o.oprname = '&&'
        AND o.oprleft = 'anyrange'::regtype AND o.oprright = 'anyrange'::regtype) <> 1 THEN
    RAISE EXCEPTION 'X5 verify: built-in range GiST/overlap support is absent';
  END IF;
  IF (SELECT count(*) FROM pg_roles) <> current_setting('x5.role_count')::bigint
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(r)::text), '' ORDER BY r.rolname), '')) FROM pg_roles r) <> current_setting('x5.role_hash') THEN
    RAISE EXCEPTION 'X5 verify: database roles changed during installation';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates WHERE
      (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only') OR
      (feature_key = 'student_tuition_generate' AND state = 'blocked') OR
      (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'X5 verify: R0 feature gates changed';
  END IF;
END
$verify$;

SELECT x.extversion AS version, n.nspname AS schema, r.rolname AS owner,
  (SELECT count(*) FROM pg_depend d WHERE d.refclassid = 'pg_extension'::regclass
    AND d.refobjid = x.oid AND d.deptype = 'e') AS members
FROM pg_extension x
JOIN pg_namespace n ON n.oid = x.extnamespace
JOIN pg_roles r ON r.oid = x.extowner
WHERE x.extname = 'btree_gist';

COMMIT;
