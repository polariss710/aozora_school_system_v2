\set ON_ERROR_STOP on
\pset pager off

-- Use only before B1-B creates any exclusion constraint or other dependency.
-- Once B1-B depends on btree_gist, this file must not be executed directly.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

WITH extension_members AS (
  SELECT d.classid,d.objid,d.objsubid
  FROM pg_depend d JOIN pg_extension x ON x.oid = d.refobjid
  WHERE x.extname = 'btree_gist' AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e'
), external_dependencies AS (
  SELECT d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.refobjsubid
  FROM pg_depend d JOIN extension_members m
    ON m.classid = d.refclassid AND m.objid = d.refobjid AND m.objsubid = d.refobjsubid
  WHERE NOT EXISTS (SELECT 1 FROM extension_members own
    WHERE own.classid = d.classid AND own.objid = d.objid AND own.objsubid = d.objsubid)
  UNION
  SELECT d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.refobjsubid
  FROM pg_depend d JOIN pg_extension x ON d.refclassid = 'pg_extension'::regclass AND d.refobjid = x.oid
  WHERE x.extname = 'btree_gist' AND d.deptype <> 'e'
)
SELECT pg_describe_object(classid,objid,objsubid) AS dependent_object,
  pg_describe_object(refclassid,refobjid,refobjsubid) AS referenced_extension_object
FROM external_dependencies
ORDER BY 1,2;

DO $guard$
DECLARE v_external bigint; v_b1 bigint;
BEGIN
  WITH extension_members AS (
    SELECT d.classid,d.objid,d.objsubid
    FROM pg_depend d JOIN pg_extension x ON x.oid = d.refobjid
    WHERE x.extname = 'btree_gist' AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e'
  ), external_dependencies AS (
    SELECT d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.refobjsubid
    FROM pg_depend d JOIN extension_members m
      ON m.classid = d.refclassid AND m.objid = d.refobjid AND m.objsubid = d.refobjsubid
    WHERE NOT EXISTS (SELECT 1 FROM extension_members own
      WHERE own.classid = d.classid AND own.objid = d.objid AND own.objsubid = d.objsubid)
    UNION
    SELECT d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.refobjsubid
    FROM pg_depend d JOIN pg_extension x ON d.refclassid = 'pg_extension'::regclass AND d.refobjid = x.oid
    WHERE x.extname = 'btree_gist' AND d.deptype <> 'e'
  ) SELECT count(*) INTO v_external FROM external_dependencies;
  IF v_external <> 0 THEN
    RAISE EXCEPTION 'X5 rollback refused: % external dependencies exist', v_external;
  END IF;
  SELECT
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND (c.relname IN ('school_lesson_venues','school_student_aircon_rates','school_planned_writer_commands','school_planned_writer_command_items') OR c.relname ILIKE 'school_%aircon%'))
    +(SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public'
     AND (column_name ILIKE '%aircon%' OR column_name IN ('base_lesson_fee_jpy','lesson_venue_id','fee_calculation_version','fee_block_reason_code','fee_components_frozen_at')))
    +(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
     AND (p.proname ILIKE 'school_resolve_planned_%' OR p.proname ILIKE 'school_calculate_planned_fee_components%'))
  INTO v_b1;
  IF v_b1 <> 0 THEN
    RAISE EXCEPTION 'X5 rollback refused: B1-B target objects exist';
  END IF;
END
$guard$;

DROP EXTENSION btree_gist;

DO $verify$
BEGIN
  IF (SELECT count(*) FROM pg_extension WHERE extname = 'btree_gist') <> 0
     OR (SELECT count(*) FROM pg_opclass WHERE opcname = 'gist_uuid_ops') <> 0 THEN
    RAISE EXCEPTION 'X5 rollback verify: extension or gist_uuid_ops remains';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates WHERE
      (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only') OR
      (feature_key = 'student_tuition_generate' AND state = 'blocked') OR
      (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3
     OR md5(pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure)) <> '8981a2ce07abf8c28231bfaf05451368'
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) = 5) <> 118
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) = 0) <> 279
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) BETWEEN 1 AND 4) <> 0 THEN
    RAISE EXCEPTION 'X5 rollback verify: R0 or business boundary changed';
  END IF;
END
$verify$;

COMMIT;
