\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $postdeploy$
DECLARE
  v_candidate_count bigint;
  v_candidate_hours numeric;
  v_candidate_fee numeric;
  v_candidate_md5 text;
  v_manifest_sha text;
  v_legacy_count bigint;
  v_legacy_md5 text;
  v_function record;
  v_billing record;
BEGIN
  IF (SELECT count(*) FROM pg_extension x
      JOIN pg_namespace n ON n.oid = x.extnamespace
      JOIN pg_roles r ON r.oid = x.extowner
      WHERE x.extname = 'btree_gist' AND x.extversion = '1.7'
        AND n.nspname = 'extensions' AND r.rolname = 'supabase_admin') <> 1
     OR (SELECT count(*) FROM pg_depend d JOIN pg_extension x ON x.oid = d.refobjid
      WHERE x.extname = 'btree_gist' AND d.refclassid = 'pg_extension'::regclass
        AND d.deptype = 'e') <> 264
     OR (SELECT count(*) FROM pg_opclass o JOIN pg_am a ON a.oid = o.opcmethod
      JOIN pg_namespace n ON n.oid = o.opcnamespace
      WHERE n.nspname = 'extensions' AND o.opcname = 'gist_uuid_ops'
        AND o.opcintype = 'uuid'::regtype AND a.amname = 'gist') <> 1 THEN
    RAISE EXCEPTION 'B1-B postdeploy: btree_gist state mismatch';
  END IF;

  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname IN (
        'school_lesson_venues','school_student_aircon_rates',
        'school_planned_writer_commands','school_venue_rate_change_audit')) <> 4 THEN
    RAISE EXCEPTION 'B1-B postdeploy: new table count mismatch';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_lesson_records'
        AND column_name IN ('base_lesson_fee_jpy','lesson_venue_id','aircon_charge_status',
          'aircon_rate_id','aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy','aircon_calculated_at','fee_calculation_version',
          'fee_block_reason_code','fee_components_frozen_at')
        AND is_nullable = 'YES' AND column_default IS NULL) <> 11 THEN
    RAISE EXCEPTION 'B1-B postdeploy: lesson additive columns mismatch';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'school_student_tuition_bill_lessons'
        AND column_name IN ('base_lesson_fee_jpy_snapshot','aircon_rate_id_snapshot',
          'aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy_snapshot','fee_calculation_version_snapshot',
          'lesson_venue_id_snapshot','lesson_venue_code_snapshot')
        AND is_nullable = 'YES' AND column_default IS NULL) <> 8 THEN
    RAISE EXCEPTION 'B1-B postdeploy: relation additive columns mismatch';
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
    RAISE EXCEPTION 'B1-B postdeploy: reused relation mapping changed';
  END IF;

  IF (SELECT count(*) FROM pg_constraint WHERE conname IN (
      'school_student_aircon_rates_no_overlap',
      'school_lesson_records_lesson_venue_id_fkey','school_lesson_records_aircon_rate_id_fkey',
      'school_student_aircon_rates_student_id_fkey','school_student_aircon_rates_superseded_by_fkey')) <> 5 THEN
    RAISE EXCEPTION 'B1-B postdeploy: required FK/exclusion constraints mismatch';
  END IF;
  IF (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname IN (
      'school_lesson_venues_active_effective_idx',
      'school_student_aircon_rates_student_effective_idx',
      'school_student_aircon_rates_superseded_by_idx',
      'school_lesson_records_lesson_venue_id_idx','school_lesson_records_aircon_rate_id_idx',
      'school_bill_lessons_aircon_rate_snapshot_idx','school_bill_lessons_venue_snapshot_idx',
      'school_planned_writer_commands_status_created_idx',
      'school_planned_writer_commands_result_lesson_idx',
      'school_venue_rate_change_audit_target_created_idx')) <> 10 THEN
    RAISE EXCEPTION 'B1-B postdeploy: required index count mismatch';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_venues)
     +(SELECT count(*) FROM public.school_student_aircon_rates)
     +(SELECT count(*) FROM public.school_planned_writer_commands)
     +(SELECT count(*) FROM public.school_venue_rate_change_audit) <> 0 THEN
    RAISE EXCEPTION 'B1-B postdeploy: a new table is not empty';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_records WHERE
      num_nonnulls(base_lesson_fee_jpy,lesson_venue_id,aircon_charge_status,aircon_rate_id,
        aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,aircon_fee_jpy,
        aircon_calculated_at,fee_calculation_version,fee_block_reason_code,
        fee_components_frozen_at) > 0) <> 0 THEN
    RAISE EXCEPTION 'B1-B postdeploy: lesson history was populated';
  END IF;
  IF (SELECT count(*) FROM public.school_student_tuition_bill_lessons WHERE
      num_nonnulls(base_lesson_fee_jpy_snapshot,aircon_rate_id_snapshot,
        aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
        aircon_fee_jpy_snapshot,fee_calculation_version_snapshot,
        lesson_venue_id_snapshot,lesson_venue_code_snapshot) > 0) <> 0 THEN
    RAISE EXCEPTION 'B1-B postdeploy: relation history was populated';
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
       OR NOT coalesce(v_function.proconfig @> ARRAY['search_path=pg_catalog, public'],false)
       OR EXISTS (SELECT 1 FROM aclexplode(coalesce(
          (SELECT proacl FROM pg_proc WHERE oid = v_function.oid),
          acldefault('f',v_function.proowner))) a
        WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
       OR has_function_privilege('anon',v_function.oid,'EXECUTE')
       OR has_function_privilege('authenticated',v_function.oid,'EXECUTE')
       OR has_function_privilege('service_role',v_function.oid,'EXECUTE') THEN
      RAISE EXCEPTION 'B1-B postdeploy: helper owner/security/search_path/ACL mismatch';
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname IN (
        'school_resolve_planned_billing_attribution','school_resolve_planned_duration',
        'school_calculate_planned_fee_components')) <> 3 THEN
    RAISE EXCEPTION 'B1-B postdeploy: helper count mismatch';
  END IF;
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
    RAISE EXCEPTION 'B1-B postdeploy: unapproved write privilege on new table';
  END IF;

  IF public.school_resolve_planned_duration(NULL,NULL,2) <> 2
     OR public.school_resolve_planned_duration(NULL,NULL,3) <> 3
     OR public.school_resolve_planned_duration('15:00','17:00',NULL) <> 2 THEN
    RAISE EXCEPTION 'B1-B postdeploy: duration helper smoke test mismatch';
  END IF;
  SELECT * INTO v_billing
  FROM public.school_resolve_planned_billing_attribution('2026-08-06',NULL);
  IF v_billing.billing_week_start_date <> DATE '2026-08-03'
     OR v_billing.billing_month <> '2026-08'
     OR v_billing.student_settlement_month <> '2026-08'
     OR v_billing.billing_month_source <> 'scheduled_date_at_create' THEN
    RAISE EXCEPTION 'B1-B postdeploy: billing helper smoke test mismatch';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates WHERE
      (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only') OR
      (feature_key = 'student_tuition_generate' AND state = 'blocked') OR
      (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'B1-B postdeploy: R0 feature gates mismatch';
  END IF;
  IF md5(pg_get_functiondef(
      'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
    )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'B1-B postdeploy: candidate function MD5 mismatch';
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
    RAISE EXCEPTION 'B1-B postdeploy: planned/118/279/partial boundary mismatch';
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
    RAISE EXCEPTION 'B1-B postdeploy: fixed candidate boundary mismatch';
  END IF;
  SELECT count(*),md5(string_agg(id::text,',' ORDER BY id::text))
  INTO v_legacy_count,v_legacy_md5
  FROM public.school_lesson_records
  WHERE lesson_type = 'planned' AND num_nonnulls(billing_month,billing_week_start_date,
    student_settlement_month,billing_month_source,billing_month_decided_at) = 0;
  IF v_legacy_count <> 279 OR v_legacy_md5 <> '0975fdc91b533680e5ccc909f076ac62' THEN
    RAISE EXCEPTION 'B1-B postdeploy: legacy 279 boundary mismatch';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
       FROM public.school_student_tuition_bills x) <> '0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
       FROM public.school_income_records x) <> '2a4897b752f272b1f192045418b4940c'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(x) - ARRAY[
          'base_lesson_fee_jpy_snapshot','aircon_rate_id_snapshot',
          'aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy_snapshot','fee_calculation_version_snapshot',
          'lesson_venue_id_snapshot','lesson_venue_code_snapshot'])::text),'' ORDER BY x.id::text),''))
       FROM public.school_student_tuition_bill_lessons x) <> '09dfee7d8833e09384fb41a84f2959e0'
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) <> 42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
       FROM public.school_student_tuition_historical_lesson_exclusions x) <> '680b6e5aaa718569aee4c36fe1cdc058' THEN
    RAISE EXCEPTION 'B1-B postdeploy: School financial-chain snapshot mismatch';
  END IF;
END
$postdeploy$;

DO $old_boundary$
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
    RAISE EXCEPTION 'B1-B postdeploy: old RPC/ACL/RLS/trigger fingerprint mismatch';
  END IF;
END
$old_boundary$;

SELECT jsonb_build_object(
  'postdeploy_ok',true,
  'old_rpc_acl_rls_trigger_unchanged',true,
  'actual_count_disclosure',(SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'actual'),
  'new_table_rows',0,
  'historical_new_values',0
) AS postdeploy_summary;

ROLLBACK;
