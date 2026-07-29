\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

WITH candidate AS (
  SELECT l.id,l.student_id,l.billing_month,l.billing_week_start_date,l.duration_hours,
    l.unit_price,l.lesson_fee,l.billing_month_source,l.billing_month_decided_at
  FROM public.school_lesson_records l
  WHERE l.app_type = 'school' AND l.lesson_type = 'planned' AND l.status = 'planned'
    AND l.voided_at IS NULL AND l.is_billable IS true
    AND l.student_id IS NOT NULL AND l.business_entity_id IS NOT NULL
    AND l.billing_month IS NOT NULL AND l.billing_week_start_date IS NOT NULL
    AND extract(isodow FROM l.billing_week_start_date) = 1
    AND to_char(l.billing_week_start_date, 'YYYY-MM') = l.billing_month
    AND l.student_settlement_month = l.billing_month
    AND l.billing_month_source IN ('approved_r1c_a_manifest','approved_r1c_c_b_manifest')
    AND l.billing_month_decided_at IS NOT NULL AND l.lesson_date IS NOT NULL
    AND l.teacher_id IS NOT NULL AND l.subject_id IS NOT NULL
    AND l.lesson_count > 0 AND l.duration_hours > 0 AND l.unit_price > 0 AND l.lesson_fee > 0
    AND l.created_at IS NOT NULL AND l.updated_at IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons r WHERE r.planned_lesson_id = l.id)
    AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bills b WHERE (b.source_snapshot -> 'planned_lesson_ids') ? l.id::text)
    AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions e WHERE e.planned_lesson_id = l.id)
), b1 AS (
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
     WHERE n.nspname = 'public' AND c.relkind = 'i' AND c.relname ~* 'aircon|lesson_venue|planned_writer') AS n
), event_md5 AS (
  SELECT count(*) AS total,
    count(*) FILTER (WHERE
      (e.evtname = 'issue_pg_cron_access' AND md5(pg_get_functiondef(p.oid)) = '7f2c6e369fa7d2b6757c21ace6692e4e') OR
      (e.evtname = 'issue_pg_graphql_access' AND md5(pg_get_functiondef(p.oid)) = '2be0ce49a11c5163eb837b1f21901124') OR
      (e.evtname = 'issue_pg_net_access' AND md5(pg_get_functiondef(p.oid)) = 'ac0f4432b3074530c78380f30e56aa16') OR
      (e.evtname = 'pgrst_ddl_watch' AND md5(pg_get_functiondef(p.oid)) = 'c87f2ceb165e84c9f894808613facb4d') OR
      (e.evtname = 'issue_graphql_placeholder' AND md5(pg_get_functiondef(p.oid)) = '4f4a0b1162d1c629f29d40d8fd787e30') OR
      (e.evtname = 'pgrst_drop_watch' AND md5(pg_get_functiondef(p.oid)) = '7d26bc43b1e03b4de5aa79cb5b8cb28a')) AS matched
  FROM pg_event_trigger e JOIN pg_proc p ON p.oid = e.evtfoid
  WHERE e.evtname IN ('issue_pg_cron_access','issue_pg_graphql_access','issue_pg_net_access','pgrst_ddl_watch','issue_graphql_placeholder','pgrst_drop_watch')
), facts AS (
  SELECT
    (SELECT count(*) FROM pg_extension WHERE extname = 'btree_gist') AS extension_count,
    (SELECT x.extversion FROM pg_extension x WHERE x.extname = 'btree_gist') AS version,
    (SELECT n.nspname FROM pg_extension x JOIN pg_namespace n ON n.oid = x.extnamespace WHERE x.extname = 'btree_gist') AS schema,
    (SELECT r.rolname FROM pg_extension x JOIN pg_roles r ON r.oid = x.extowner WHERE x.extname = 'btree_gist') AS owner,
    (SELECT count(*) FROM pg_depend d JOIN pg_extension x ON x.oid = d.refobjid
      WHERE x.extname = 'btree_gist' AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e') AS members,
    (SELECT trusted FROM pg_available_extension_versions WHERE name = 'btree_gist' AND version = '1.7') AS trusted,
    (SELECT relocatable FROM pg_available_extension_versions WHERE name = 'btree_gist' AND version = '1.7') AS relocatable,
    EXISTS (SELECT 1 FROM pg_opclass o JOIN pg_am a ON a.oid = o.opcmethod JOIN pg_namespace n ON n.oid = o.opcnamespace
      WHERE n.nspname = 'extensions' AND o.opcname = 'gist_uuid_ops' AND o.opcintype = 'uuid'::regtype AND a.amname = 'gist') AS uuid_gist,
    EXISTS (SELECT 1 FROM pg_opclass o JOIN pg_am a ON a.oid = o.opcmethod JOIN pg_namespace n ON n.oid = o.opcnamespace
      WHERE n.nspname = 'pg_catalog' AND o.opcname = 'range_ops' AND o.opcintype = 'anyrange'::regtype AND a.amname = 'gist') AS range_gist,
    EXISTS (SELECT 1 FROM pg_operator o JOIN pg_namespace n ON n.oid = o.oprnamespace
      WHERE n.nspname = 'pg_catalog' AND o.oprname = '&&' AND o.oprleft = 'anyrange'::regtype AND o.oprright = 'anyrange'::regtype) AS range_overlap,
    (SELECT total FROM event_md5) AS event_total,(SELECT matched FROM event_md5) AS event_matched,
    (SELECT count(*) FROM pg_roles WHERE rolname ILIKE '%btree_gist%' OR rolname ILIKE '%gist_uuid%') AS abnormal_roles,
    (SELECT count(*) FROM pg_depend d JOIN pg_extension x ON x.oid = d.refobjid
      JOIN pg_class c ON d.classid = 'pg_class'::regclass AND c.oid = d.objid JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE x.extname = 'btree_gist' AND d.deptype = 'e' AND n.nspname = 'public')
    +(SELECT count(*) FROM pg_depend d JOIN pg_extension x ON x.oid = d.refobjid
      JOIN pg_proc p ON d.classid = 'pg_proc'::regclass AND p.oid = d.objid JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE x.extname = 'btree_gist' AND d.deptype = 'e' AND n.nspname = 'public') AS public_extension_members,
    (SELECT n FROM b1) AS b1_count,
    (SELECT count(*) FROM public.school_feature_gates WHERE
      (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only') OR
      (feature_key = 'student_tuition_generate' AND state = 'blocked') OR
      (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) AS r0,
    md5(pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure)) AS candidate_function_md5,
    (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned') AS planned,
    (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'actual') AS actual,
    (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned' AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) = 5) AS complete,
    (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned' AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) = 0) AS legacy,
    (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned' AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) BETWEEN 1 AND 4) AS partial,
    (SELECT count(*) FROM candidate) AS candidate_count,(SELECT sum(duration_hours) FROM candidate) AS candidate_hours,(SELECT sum(lesson_fee) FROM candidate) AS candidate_fee,
    (SELECT md5(string_agg(id::text, ',' ORDER BY id::text)) FROM candidate) AS candidate_uuid_md5,
    (SELECT encode(sha256(convert_to(string_agg(concat_ws('|',id::text,student_id::text,billing_month,billing_week_start_date::text,duration_hours::text,unit_price::text,lesson_fee::text,billing_month_source,to_char(billing_month_decided_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),E'\n' ORDER BY student_id::text,billing_month,billing_week_start_date,id::text)||E'\n','UTF8')),'hex') FROM candidate) AS manifest_sha256,
    (SELECT md5(string_agg(id::text, ',' ORDER BY id::text)) FROM public.school_lesson_records
      WHERE lesson_type = 'planned' AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,billing_month_source,billing_month_decided_at) = 0) AS legacy_md5,
    (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
    (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bills x) AS bill_hash,
    (SELECT count(*) FROM public.school_income_records) AS income_count,
    (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_income_records x) AS income_hash,
    (SELECT count(*) FROM public.school_student_tuition_bill_lessons) AS relation_count,
    (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bill_lessons x) AS relation_hash,
    (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) AS exclusion_count,
    (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_historical_lesson_exclusions x) AS exclusion_hash
)
SELECT *, extension_count = 1 AND version = '1.7' AND schema = 'extensions' AND owner = 'supabase_admin' AND members = 264
  AND trusted AND relocatable AND uuid_gist AND range_gist AND range_overlap
  AND event_total = 6 AND event_matched = 6 AND abnormal_roles = 0 AND public_extension_members = 0 AND b1_count = 0
  AND r0 = 3 AND candidate_function_md5 = '8981a2ce07abf8c28231bfaf05451368'
  AND planned = 397 AND complete = 118 AND legacy = 279 AND partial = 0
  AND candidate_count = 118 AND candidate_hours = 254 AND candidate_fee = 2474000
  AND candidate_uuid_md5 = '77f697f82e547d84dcabf88a3c868aa1'
  AND manifest_sha256 = 'f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1'
  AND legacy_md5 = '0975fdc91b533680e5ccc909f076ac62'
  AND bill_count = 9 AND bill_hash = '0f0323b79e7ff1c47ff6b90c75477a2d'
  AND income_count = 42 AND income_hash = '2a4897b752f272b1f192045418b4940c'
  AND relation_count = 121 AND relation_hash = '09dfee7d8833e09384fb41a84f2959e0'
  AND exclusion_count = 42 AND exclusion_hash = '680b6e5aaa718569aee4c36fe1cdc058' AS postdeploy_ok
FROM facts
\gset post_

SELECT jsonb_build_object(
  'postdeploy_ok', :'post_postdeploy_ok'::boolean,
  'extension', jsonb_build_array(:'post_version',:'post_schema',:'post_owner',:'post_members'::integer),
  'trusted_relocatable', jsonb_build_array(:'post_trusted'::boolean,:'post_relocatable'::boolean),
  'operator_support', jsonb_build_array(:'post_uuid_gist'::boolean,:'post_range_gist'::boolean,:'post_range_overlap'::boolean),
  'event_md5', jsonb_build_array(:'post_event_matched'::integer,:'post_event_total'::integer),
  'b1_count', :'post_b1_count'::integer,'r0', :'post_r0'::integer,
  'planned_actual', jsonb_build_array(:'post_planned'::integer,:'post_actual'::integer),
  'five_fields', jsonb_build_array(:'post_complete'::integer,:'post_legacy'::integer,:'post_partial'::integer),
  'candidate', jsonb_build_array(:'post_candidate_count'::integer,:'post_candidate_hours'::numeric,:'post_candidate_fee'::numeric),
  'financial_counts', jsonb_build_array(:'post_bill_count'::integer,:'post_income_count'::integer,:'post_relation_count'::integer,:'post_exclusion_count'::integer)
);

ROLLBACK;

\if :post_postdeploy_ok
\else
  \echo 'X5 postdeploy verification failed'
  \quit 3
\endif
