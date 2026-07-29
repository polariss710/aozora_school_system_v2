-- School V2 tuition P0 R1D-D-B1-A planned-writer / aircon schema inventory.
-- Target: School PostgreSQL only.
-- This file is intentionally read-only: catalog and business-table evidence only.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

SELECT
  'transaction_identity' AS check_name,
  current_database() AS database_name,
  current_user AS database_user,
  session_user AS session_user,
  current_setting('transaction_isolation') AS isolation_level,
  current_setting('transaction_read_only') AS read_only,
  transaction_timestamp() AS snapshot_at,
  current_setting('TimeZone') AS database_timezone,
  current_setting('transaction_read_only') = 'on' AS all_expected;

SELECT
  'r0_feature_gates_start' AS check_name,
  feature_key,
  state,
  CASE feature_key
    WHEN 'student_tuition_preview' THEN state = 'validation_preview_only'
    WHEN 'student_tuition_generate' THEN state = 'blocked'
    WHEN 'student_tuition_cash_submit' THEN state = 'blocked'
    ELSE false
  END AS expected_state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

SELECT
  'candidate_definition' AS check_name,
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) AS definition_md5,
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) = '8981a2ce07abf8c28231bfaf05451368' AS all_expected;

SELECT
  'required_objects' AS check_name,
  to_regclass('public.school_lesson_records') IS NOT NULL AS lesson_table,
  to_regclass('public.school_students') IS NOT NULL AS student_table,
  to_regclass('public.school_student_tuition_bills') IS NOT NULL AS bill_table,
  to_regclass('public.school_student_tuition_bill_lessons') IS NOT NULL AS bill_lesson_table,
  to_regclass('public.school_student_tuition_historical_lesson_exclusions') IS NOT NULL AS historical_exclusion_table,
  to_regclass('public.school_lesson_date_semantics') IS NOT NULL AS date_semantics_view,
  to_regprocedure('public.school_iso_week_start(date)') IS NOT NULL AS iso_week_helper,
  to_regprocedure('public.school_is_valid_tuition_billing_period(text,date)') IS NOT NULL AS billing_period_helper;

SELECT
  'lesson_columns' AS check_name,
  column_row.ordinal_position,
  column_row.column_name,
  column_row.data_type,
  column_row.udt_name,
  column_row.is_nullable,
  column_row.column_default,
  pg_catalog.col_description('public.school_lesson_records'::regclass, column_row.ordinal_position)
    AS column_comment
FROM information_schema.columns column_row
WHERE column_row.table_schema = 'public'
  AND column_row.table_name = 'school_lesson_records'
ORDER BY column_row.ordinal_position;

SELECT
  'lesson_constraints' AS check_name,
  constraint_row.conname AS constraint_name,
  constraint_row.contype AS constraint_type,
  constraint_row.convalidated AS validated,
  constraint_row.condeferrable AS deferrable,
  constraint_row.condeferred AS initially_deferred,
  pg_get_constraintdef(constraint_row.oid, true) AS definition
FROM pg_constraint constraint_row
WHERE constraint_row.conrelid = 'public.school_lesson_records'::regclass
ORDER BY constraint_row.conname;

SELECT
  'lesson_indexes' AS check_name,
  index_row.indexname,
  index_row.indexdef
FROM pg_indexes index_row
WHERE index_row.schemaname = 'public'
  AND index_row.tablename = 'school_lesson_records'
ORDER BY index_row.indexname;

SELECT
  'lesson_triggers' AS check_name,
  trigger_row.tgname AS trigger_name,
  trigger_row.tgenabled AS enabled_state,
  pg_get_triggerdef(trigger_row.oid, true) AS definition,
  function_row.proname AS function_name,
  md5(pg_get_functiondef(function_row.oid)) AS function_definition_md5
FROM pg_trigger trigger_row
JOIN pg_proc function_row ON function_row.oid = trigger_row.tgfoid
WHERE trigger_row.tgrelid = 'public.school_lesson_records'::regclass
  AND NOT trigger_row.tgisinternal
ORDER BY trigger_row.tgname;

WITH relevant_function AS (
  SELECT
    function_row.oid,
    namespace_row.nspname,
    function_row.proname,
    pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
    pg_get_function_result(function_row.oid) AS result_type,
    owner_row.rolname AS owner_name,
    function_row.prosecdef,
    function_row.provolatile,
    function_row.proparallel,
    function_row.proconfig,
    function_row.proacl,
    pg_get_functiondef(function_row.oid) AS definition
  FROM pg_proc function_row
  JOIN pg_namespace namespace_row ON namespace_row.oid = function_row.pronamespace
  JOIN pg_roles owner_row ON owner_row.oid = function_row.proowner
  WHERE namespace_row.nspname = 'public'
    AND (
      function_row.proname IN (
        'school_create_planned_lesson_record',
        'school_create_planned_lesson_record_with_venue',
        'school_generate_planned_lessons_batch',
        'school_generate_planned_lessons_batch_with_venue',
        'school_import_lesson_records_batch',
        'school_import_lesson_records_batch_with_venue',
        'school_update_lesson_record_guarded',
        'school_update_lesson_record_guarded_with_venue',
        'school_normalize_lesson_schedule_venue',
        'school_create_actual_lesson_from_planned',
        'school_create_cancelled_actual_lesson_from_planned',
        'school_create_makeup_completed_actual_lesson_from_planned',
        'school_create_cross_month_makeup_completed_actual_from_planned',
        'school_create_partial_completed_actual_from_planned',
        'school_create_lesson_credit_makeup_actual',
        'school_generate_student_tuition_bill',
        'school_list_student_tuition_candidates',
        'school_iso_week_start',
        'school_is_valid_tuition_billing_period'
      )
      OR pg_get_functiondef(function_row.oid) ILIKE '%school_lesson_records%'
         AND pg_get_functiondef(function_row.oid) ~* '(insert[[:space:]]+into|update[[:space:]]+)public[.]school_lesson_records'
    )
)
SELECT
  'relevant_functions' AS check_name,
  nspname AS function_schema,
  proname AS function_name,
  identity_arguments,
  result_type,
  owner_name,
  prosecdef AS security_definer,
  provolatile AS volatility_code,
  proparallel AS parallel_code,
  proconfig AS function_config,
  proacl AS acl,
  md5(definition) AS definition_md5,
  definition ~* 'insert[[:space:]]+into[[:space:]]+public[.]school_lesson_records' AS inserts_lesson,
  definition ~* 'update[[:space:]]+public[.]school_lesson_records' AS updates_lesson,
  definition ILIKE '%p_lesson_fee%' AS accepts_lesson_fee,
  definition ILIKE '%billing_week_start_date%' AS references_billing_week,
  definition ILIKE '%scheduled_lesson_date%' AS references_scheduled_date
FROM relevant_function
ORDER BY proname, identity_arguments;

SELECT
  'relevant_function_grants' AS check_name,
  grant_row.routine_name,
  grant_row.grantee,
  grant_row.privilege_type,
  grant_row.is_grantable
FROM information_schema.routine_privileges grant_row
WHERE grant_row.specific_schema = 'public'
  AND grant_row.routine_name IN (
    'school_create_planned_lesson_record',
    'school_create_planned_lesson_record_with_venue',
    'school_generate_planned_lessons_batch',
    'school_generate_planned_lessons_batch_with_venue',
    'school_import_lesson_records_batch',
    'school_import_lesson_records_batch_with_venue',
    'school_update_lesson_record_guarded',
    'school_update_lesson_record_guarded_with_venue',
    'school_normalize_lesson_schedule_venue',
    'school_generate_student_tuition_bill',
    'school_iso_week_start',
    'school_is_valid_tuition_billing_period'
  )
ORDER BY grant_row.routine_name, grant_row.grantee, grant_row.privilege_type;

SELECT
  'relevant_table_security' AS check_name,
  namespace_row.nspname AS table_schema,
  class_row.relname AS object_name,
  class_row.relkind AS object_kind,
  class_row.relrowsecurity AS rls_enabled,
  class_row.relforcerowsecurity AS rls_forced,
  owner_row.rolname AS owner_name,
  class_row.relacl AS acl
FROM pg_class class_row
JOIN pg_namespace namespace_row ON namespace_row.oid = class_row.relnamespace
JOIN pg_roles owner_row ON owner_row.oid = class_row.relowner
WHERE namespace_row.nspname = 'public'
  AND class_row.relname IN (
    'school_lesson_records',
    'school_students',
    'school_student_tuition_bills',
    'school_student_tuition_bill_lessons',
    'school_tuition_billing_attribution_override_audit',
    'school_student_tuition_historical_lesson_exclusions',
    'school_lesson_date_semantics'
  )
ORDER BY class_row.relname;

SELECT
  'relevant_table_grants' AS check_name,
  grant_row.table_name,
  grant_row.grantee,
  grant_row.privilege_type,
  grant_row.is_grantable
FROM information_schema.table_privileges grant_row
WHERE grant_row.table_schema = 'public'
  AND grant_row.table_name IN (
    'school_lesson_records',
    'school_students',
    'school_student_tuition_bills',
    'school_student_tuition_bill_lessons',
    'school_tuition_billing_attribution_override_audit',
    'school_student_tuition_historical_lesson_exclusions',
    'school_lesson_date_semantics'
  )
ORDER BY grant_row.table_name, grant_row.grantee, grant_row.privilege_type;

SELECT
  'relevant_policies' AS check_name,
  policy_row.schemaname,
  policy_row.tablename,
  policy_row.policyname,
  policy_row.permissive,
  policy_row.roles,
  policy_row.cmd,
  policy_row.qual,
  policy_row.with_check
FROM pg_policies policy_row
WHERE policy_row.schemaname = 'public'
  AND policy_row.tablename IN (
    'school_lesson_records',
    'school_students',
    'school_student_tuition_bills',
    'school_student_tuition_bill_lessons',
    'school_tuition_billing_attribution_override_audit',
    'school_student_tuition_historical_lesson_exclusions'
  )
ORDER BY policy_row.tablename, policy_row.policyname;

SELECT
  'possible_reusable_config_objects' AS check_name,
  namespace_row.nspname AS object_schema,
  class_row.relname AS object_name,
  class_row.relkind AS object_kind
FROM pg_class class_row
JOIN pg_namespace namespace_row ON namespace_row.oid = class_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND class_row.relkind IN ('r', 'p', 'v', 'm')
  AND class_row.relname ~* '(venue|location|rate|price|pricing|config|effective)'
ORDER BY class_row.relname;

SELECT
  'possible_reusable_config_columns' AS check_name,
  column_row.table_name,
  column_row.ordinal_position,
  column_row.column_name,
  column_row.data_type,
  column_row.is_nullable,
  column_row.column_default
FROM information_schema.columns column_row
WHERE column_row.table_schema = 'public'
  AND (
    column_row.table_name ~* '(venue|location|rate|price|pricing|config|effective)'
    OR column_row.column_name ~* '(venue|location|rate|price|effective_from|effective_to)'
  )
ORDER BY column_row.table_name, column_row.ordinal_position;

SELECT
  'snapshot_table_columns' AS check_name,
  column_row.table_name,
  column_row.ordinal_position,
  column_row.column_name,
  column_row.data_type,
  column_row.is_nullable,
  column_row.column_default
FROM information_schema.columns column_row
WHERE column_row.table_schema = 'public'
  AND column_row.table_name IN (
    'school_student_tuition_bills',
    'school_student_tuition_bill_lessons',
    'school_student_tuition_historical_lesson_exclusions'
  )
ORDER BY column_row.table_name, column_row.ordinal_position;

WITH lesson_counts AS (
  SELECT
    count(*) AS lesson_count,
    count(*) FILTER (WHERE lesson_type = 'planned') AS planned_count,
    count(*) FILTER (WHERE lesson_type = 'actual') AS actual_count,
    count(*) FILTER (
      WHERE lesson_type = 'planned'
        AND billing_month IS NOT NULL
        AND billing_week_start_date IS NOT NULL
        AND student_settlement_month IS NOT NULL
        AND billing_month_source IS NOT NULL
        AND billing_month_decided_at IS NOT NULL
    ) AS planned_complete_five_count,
    count(*) FILTER (
      WHERE lesson_type = 'planned'
        AND billing_month IS NULL
        AND billing_week_start_date IS NULL
        AND student_settlement_month IS NULL
        AND billing_month_source IS NULL
        AND billing_month_decided_at IS NULL
    ) AS planned_null_five_count,
    count(*) FILTER (
      WHERE lesson_type = 'planned'
        AND num_nonnulls(
          billing_month,
          billing_week_start_date,
          student_settlement_month,
          billing_month_source,
          billing_month_decided_at
        ) BETWEEN 1 AND 4
    ) AS planned_partial_five_count,
    count(*) FILTER (WHERE scheduled_lesson_date IS NOT NULL) AS scheduled_nonnull_count
  FROM public.school_lesson_records
)
SELECT
  'lesson_boundary' AS check_name,
  lesson_counts.*,
  planned_count = 397
    AND planned_complete_five_count = 118
    AND planned_null_five_count = 279
    AND planned_partial_five_count = 0
    AND scheduled_nonnull_count = 0 AS all_expected
FROM lesson_counts;

WITH fixed_manifest(manifest_order, lesson_id) AS (
  VALUES
    (1, '23d4b46b-eb1c-48b7-8001-d208ce14f08d'::uuid),
    (2, '637ba833-830f-42a6-81ed-47a6f9902523'::uuid),
    (3, '7175780c-b179-4f96-a42e-99ba11bdaed8'::uuid),
    (4, '80384c28-5044-4c56-94cd-5099aa852032'::uuid),
    (5, '920808f2-5629-4fcc-957c-6bdcee48808e'::uuid),
    (6, 'd06f136e-d4c5-44fb-ae5e-d87efa26bbfb'::uuid),
    (7, '3db3ad8b-44b6-4be7-a3ea-611362b82488'::uuid),
    (8, '6997acdc-fec4-4e14-a22b-d9f5291b1e0b'::uuid),
    (9, '69ecc019-9f8f-474e-8dc9-1dced16e41a6'::uuid),
    (10, '72ffebba-ecb3-4a96-9550-f02a5f64cf62'::uuid),
    (11, 'c0e9fd95-7833-44ef-a282-61611976b089'::uuid),
    (12, 'e6aaf546-bb9c-4e71-980e-40f78f2e1e11'::uuid),
    (13, '12d70ee9-8221-4b8e-a01c-61548340c42d'::uuid),
    (14, '1927b6ba-6ca6-4ef9-b1c0-0246067c7d41'::uuid),
    (15, '3920fdea-2f9d-4b17-abd0-f788b0d7d29e'::uuid),
    (16, '95dff1ab-544d-43be-bc0e-a95232f06935'::uuid),
    (17, 'a10744fc-173a-4b25-9bc3-99d6437797c5'::uuid),
    (18, 'a601916b-6add-4be6-adcc-5c232425f686'::uuid),
    (19, '286344d1-c603-4990-aba3-814996535319'::uuid),
    (20, '9a76aed4-058f-4801-90b5-b2637387fb3e'::uuid),
    (21, '9f755093-8f4d-4337-80ed-23d0e555c835'::uuid),
    (22, 'e2540bb3-5c1f-45bc-b964-9727a6ed3e48'::uuid),
    (23, 'ee6c1383-4259-44e0-923c-1ee6b8749820'::uuid),
    (24, 'ee86e691-2c96-48c2-ad57-512f9eef4b3c'::uuid),
    (25, '01490eb7-1bd7-430a-ba26-3ccc81d45796'::uuid),
    (26, '80e03531-5eaa-40e1-a435-0132dd62d5c0'::uuid),
    (27, '8c6da1a7-69a9-45b6-9a77-daa2bfd7f9e9'::uuid),
    (28, '9efe2def-ff59-467a-bb76-a49537ec8e0f'::uuid),
    (29, 'adc0b06c-eee3-40ca-8992-592f5d4b009b'::uuid),
    (30, 'dbe16731-803b-49db-8cc0-f826e911bb41'::uuid),
    (31, '15f8147e-5bb0-4cf9-9ba7-3e12f115774e'::uuid),
    (32, '224015ce-b435-4233-8113-0e6c712b1a18'::uuid),
    (33, '2bd402cb-fc4d-48cc-b166-400ee4945703'::uuid),
    (34, 'c1f5c7e9-70e4-4c2d-99c8-aadd986cda15'::uuid),
    (35, 'dadcf864-5343-403d-a111-e68b8617f413'::uuid),
    (36, 'f91ecdd8-7442-4879-97b6-67ad8ea99f23'::uuid),
    (37, '10b62cc8-dd74-4665-a6cd-02cc02924a65'::uuid),
    (38, '57948b80-89d9-45f2-a99f-3b92aed9f4e8'::uuid),
    (39, '68da4912-72a8-418c-b30b-335bb9896c63'::uuid),
    (40, 'a9de94c0-954b-452d-95b0-6a8b7d1a5a9e'::uuid),
    (41, 'c79e2ade-4026-4ab3-a316-ba26354abfe2'::uuid),
    (42, 'f693a3d9-fada-48f2-8203-bc33d46ee4dd'::uuid),
    (43, '5591fb92-2333-460c-95f3-85c6511d6fd4'::uuid),
    (44, '645cccaf-ae0f-41b3-84d1-e40882a8c85f'::uuid),
    (45, '82e81ecc-dd23-471e-8402-a45bd8b20eb1'::uuid),
    (46, 'bf38024e-2a5f-422c-ad41-01ec9922e701'::uuid),
    (47, 'dbd6f35a-b0ee-4af8-bcda-e065330f0413'::uuid),
    (48, 'fb066255-82b5-4eb1-9f76-a776c04becc2'::uuid),
    (49, '1eeb937e-a7ad-4e7c-955d-797b9d979882'::uuid),
    (50, '21e97cbd-3e18-4c9e-9790-981f885af03a'::uuid),
    (51, '371e41c5-a659-44a6-87e0-c3a85c9c1b75'::uuid),
    (52, '966119c6-09c8-4ac5-9c16-6cda13137d87'::uuid),
    (53, 'a9e861d3-6bd6-4b76-ba78-4cc1f3265b43'::uuid),
    (54, 'fd803263-07b6-4b1f-b668-43a482f21c89'::uuid),
    (55, '0386bf22-8619-41f2-be6c-5106b8c17cd0'::uuid),
    (56, '4254095b-9ec1-4651-a9ff-0dffb3a4520f'::uuid),
    (57, '7e833e2c-3bc0-4c6d-a1ab-204229f43a77'::uuid),
    (58, 'aea933f5-5e3b-4476-b1f0-d781d41312a3'::uuid),
    (59, 'b33f023c-4b0c-495e-8f0b-934ead526421'::uuid),
    (60, 'ff368fb5-94a8-4ea4-b3fc-d62ce499732b'::uuid),
    (61, '17e58b7d-3fb8-4874-8071-0b1f808e8430'::uuid),
    (62, '30271ef0-51ee-43ca-9103-1b5ec34255e1'::uuid),
    (63, 'a3a7dd70-1a1e-4078-bce8-d54f10fc57af'::uuid),
    (64, 'cfb5e237-51a3-48b2-a12e-e8f0628e2c51'::uuid),
    (65, 'd9d11e4b-a01c-4535-93cf-bc51cf08b900'::uuid),
    (66, 'eec50614-788d-429b-99a4-fc8938a86dda'::uuid),
    (67, '0ea530e7-12ac-41fa-9f6e-972b24662a72'::uuid),
    (68, '297c7ed8-4aca-40d5-b4de-5fcb3e2ddb83'::uuid),
    (69, '3048b190-31e0-49b1-a255-ce73e6e15fc0'::uuid),
    (70, '70c31ae5-6083-46cb-90ad-fdc24726b6b6'::uuid),
    (71, '812979d0-43ac-4075-b38f-4c9aa455cd4b'::uuid),
    (72, 'd1961919-8c05-42e8-8a06-4ed1fabb13c0'::uuid),
    (73, '0a3a8c13-12cb-4430-a933-2941221c0c77'::uuid),
    (74, '4505777b-13e3-4187-9839-618ebe186f22'::uuid),
    (75, '895ebf6e-6bf0-419d-bf9a-418d048a42a7'::uuid),
    (76, '92a0f909-6458-4d34-9144-9d60eeede33f'::uuid),
    (77, 'c48478ef-8b3d-4c7f-bd48-cc99659e99f7'::uuid),
    (78, 'd8ed3671-6865-42b6-a4a2-06b31c9051e6'::uuid),
    (79, '0624fabe-a3c8-4930-aa41-8ed800a28eea'::uuid),
    (80, '3f5884ea-ca12-41dc-89ce-ebc67db27fe8'::uuid),
    (81, '89797ce3-58e0-4c9d-b107-79eca71e4161'::uuid),
    (82, 'a42b1b2e-4f55-4915-a20b-bd411b4d81a0'::uuid),
    (83, 'd2307a35-1f41-4402-ab4d-c03ed4305f50'::uuid),
    (84, 'fd34b0d7-86c2-4d0e-a519-de2317e0ab26'::uuid),
    (85, '207430a6-c9cd-4acb-9a7d-962c078b0623'::uuid),
    (86, '5666a624-05b5-4408-bc11-5d208851b216'::uuid),
    (87, 'a57bf7af-43e1-46ba-9bb6-9ee511b81e05'::uuid),
    (88, '73dd0453-aec2-4612-b710-071a372f88ad'::uuid),
    (89, 'bc718d5f-dc21-4e7d-914a-dd3a6debaeb6'::uuid),
    (90, 'f1a321d8-5528-4afe-8fb7-79204f49f3dc'::uuid),
    (91, '584ef4d6-fa9d-4dd8-803c-cab68ac67a67'::uuid),
    (92, 'a4cd05e7-47e7-4e0d-8af8-dad6c7505744'::uuid),
    (93, 'fc138193-f76a-476c-a394-b49d2e68dde2'::uuid),
    (94, '0f168663-afb1-49a7-90a8-39197ad7729e'::uuid),
    (95, '594a4559-c1b1-4ad1-88e6-4c7834052831'::uuid),
    (96, 'def65ad3-6f87-4889-802f-202550a9af49'::uuid),
    (97, '222c4ad5-b6fe-4e4e-b192-8db8c65b61fa'::uuid),
    (98, '6c70c4c1-1895-453d-b9b0-591e9f004f86'::uuid),
    (99, '89da310d-4f17-4a40-8315-659838aec59c'::uuid),
    (100, '9efb8862-e8c5-4f3d-9d55-b0be4317ad19'::uuid),
    (101, '37a2083e-bb28-45d1-802a-f98f4564887f'::uuid),
    (102, '63ca3a2b-7c2f-4eed-a997-71840357f8f6'::uuid),
    (103, 'a3ee5595-6dd5-4737-8605-ff5a8d7d0333'::uuid),
    (104, 'ea766c1d-f152-4b3f-9400-0d5b5aa64614'::uuid),
    (105, 'fcbf1be4-567b-4876-9cc6-19cd0d395da0'::uuid),
    (106, '1df61ad9-742f-4fd6-b883-b3a8bbb0c4e8'::uuid),
    (107, '68bbce4e-f6bb-45c6-9798-ee72b6f75179'::uuid),
    (108, '9bdb88c1-9c08-4716-b146-e98cf149978b'::uuid),
    (109, 'fa7883c8-35e6-40bd-92d1-70adcdcce078'::uuid),
    (110, '1f9c027a-6db2-4aa2-8bef-215f3ed2bbb9'::uuid),
    (111, '475853f0-2004-4375-ae72-013c5a86987c'::uuid),
    (112, '6e005bee-2d14-4722-8b76-9dbe7f836e12'::uuid),
    (113, 'cde683d3-06f2-46ec-8b8a-4f2ed4b4962e'::uuid),
    (114, 'e65b7d1d-45b2-4485-ae6d-7000fe92ce78'::uuid),
    (115, '02b9e85e-2e03-404d-93a6-9bfef3bf186d'::uuid),
    (116, '0d048cbf-a5f5-458c-88aa-ce0c3a1c667c'::uuid),
    (117, '196c9d86-500b-4687-a051-88dcc12fa2a9'::uuid),
    (118, 'aa55dc2e-3b1b-4d2d-863f-9f64e84b8578'::uuid)
), live_manifest AS (
  SELECT
    manifest.manifest_order,
    manifest.lesson_id AS manifest_lesson_id,
    lesson.*
  FROM fixed_manifest manifest
  LEFT JOIN public.school_lesson_records lesson
    ON lesson.id = manifest.lesson_id
), manifest_summary AS (
  SELECT
    (SELECT count(*) FROM fixed_manifest) AS manifest_value_count,
    (SELECT count(DISTINCT lesson_id) FROM fixed_manifest) AS manifest_distinct_uuid_count,
    count(id) AS matched_count,
    count(*) FILTER (WHERE id IS NULL) AS missing_count,
    count(*) FILTER (
      WHERE lesson_type = 'planned'
        AND app_type = 'school'
        AND status = 'planned'
        AND voided_at IS NULL
        AND is_billable IS true
    ) AS active_planned_billable_count,
    count(*) FILTER (WHERE id IS NOT NULL AND duration_hours IS NULL) AS duration_null_count,
    count(*) FILTER (WHERE id IS NOT NULL AND duration_hours < 2) AS duration_below_two_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND duration_hours IS NOT NULL
        AND duration_hours <> trunc(duration_hours)
    ) AS non_integer_duration_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND duration_hours >= 2
        AND duration_hours = trunc(duration_hours)
    ) AS valid_integer_duration_count,
    min(duration_hours) FILTER (WHERE id IS NOT NULL) AS minimum_duration_hours,
    max(duration_hours) FILTER (WHERE id IS NOT NULL) AS maximum_duration_hours,
    sum(duration_hours) FILTER (WHERE id IS NOT NULL) AS total_duration_hours,
    sum(lesson_fee) FILTER (WHERE id IS NOT NULL) AS current_base_lesson_fee_jpy,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND lesson_fee IS DISTINCT FROM round(duration_hours * unit_price)
    ) AS base_fee_formula_mismatch_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.school_lesson_records actual
          WHERE actual.planned_lesson_id = live_manifest.id
        )
    ) AS has_actual_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.school_student_tuition_bill_lessons relation
          WHERE relation.planned_lesson_id = live_manifest.id
        )
    ) AS has_bill_relation_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.school_student_tuition_bills bill
          WHERE (bill.source_snapshot -> 'planned_lesson_ids') ? live_manifest.id::text
        )
    ) AS has_bill_json_snapshot_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.school_student_tuition_historical_lesson_exclusions exclusion
          WHERE exclusion.planned_lesson_id = live_manifest.id
        )
    ) AS has_historical_exclusion_count,
    md5(string_agg(id::text, ',' ORDER BY id::text)
      FILTER (WHERE id IS NOT NULL)) AS uuid_set_md5,
    encode(sha256(convert_to(
      string_agg(
        concat_ws('|',
          coalesce(id::text, 'NULL'),
          coalesce(student_id::text, 'NULL'),
          coalesce(billing_month, 'NULL'),
          coalesce(billing_week_start_date::text, 'NULL'),
          coalesce(duration_hours::text, 'NULL'),
          coalesce(unit_price::text, 'NULL'),
          coalesce(lesson_fee::text, 'NULL'),
          coalesce(billing_month_source, 'NULL'),
          coalesce(
            to_char(
              billing_month_decided_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
            'NULL'
          )
        ),
        E'\n' ORDER BY student_id::text, billing_month,
          billing_week_start_date, id::text
      ) FILTER (WHERE id IS NOT NULL) || E'\n',
      'UTF8'
    )), 'hex') AS business_manifest_sha256
  FROM live_manifest
), duration_distribution AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'duration_hours', duration_hours,
      'row_count', row_count
    )
    ORDER BY duration_hours
  ) AS distribution
  FROM (
    SELECT duration_hours, count(*) AS row_count
    FROM live_manifest
    WHERE id IS NOT NULL
    GROUP BY duration_hours
  ) grouped
)
SELECT
  'fixed_118_integer_preflight' AS check_name,
  manifest_summary.*,
  duration_distribution.distribution AS duration_distribution,
  manifest_value_count = 118
    AND manifest_distinct_uuid_count = 118
    AND matched_count = 118
    AND missing_count = 0
    AND active_planned_billable_count = 118
    AND duration_null_count = 0
    AND duration_below_two_count = 0
    AND non_integer_duration_count = 0
    AND valid_integer_duration_count = 118
    AND minimum_duration_hours >= 2
    AND maximum_duration_hours = trunc(maximum_duration_hours)
    AND total_duration_hours = 254
    AND current_base_lesson_fee_jpy = 2474000
    AND base_fee_formula_mismatch_count = 0
    AND has_actual_count = 0
    AND has_bill_relation_count = 0
    AND has_bill_json_snapshot_count = 0
    AND has_historical_exclusion_count = 0
    AND uuid_set_md5 = '77f697f82e547d84dcabf88a3c868aa1'
    AND business_manifest_sha256 =
      'f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1'
    AS all_expected
FROM manifest_summary
CROSS JOIN duration_distribution;

WITH fixed_scope AS (
  SELECT lesson.*
  FROM public.school_lesson_records lesson
  WHERE lesson.lesson_type = 'planned'
    AND lesson.billing_month IS NOT NULL
    AND lesson.billing_week_start_date IS NOT NULL
    AND lesson.student_settlement_month IS NOT NULL
    AND lesson.billing_month_source IS NOT NULL
    AND lesson.billing_month_decided_at IS NOT NULL
), manifest_hash AS (
  SELECT
    count(*) AS lesson_count,
    sum(duration_hours) AS duration_hours,
    sum(lesson_fee) AS lesson_fee_jpy,
    md5(string_agg(id::text, ',' ORDER BY id::text)) AS uuid_set_md5,
    encode(sha256(convert_to(
      string_agg(
        concat_ws('|',
          coalesce(id::text, 'NULL'),
          coalesce(student_id::text, 'NULL'),
          coalesce(billing_month, 'NULL'),
          coalesce(billing_week_start_date::text, 'NULL'),
          coalesce(duration_hours::text, 'NULL'),
          coalesce(unit_price::text, 'NULL'),
          coalesce(lesson_fee::text, 'NULL'),
          coalesce(billing_month_source, 'NULL'),
          coalesce(
            to_char(
              billing_month_decided_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
            'NULL'
          )
        ),
        E'\n' ORDER BY student_id::text, billing_month,
          billing_week_start_date, id::text
      ) || E'\n',
      'UTF8'
    )), 'hex') AS business_manifest_sha256,
    count(*) FILTER (
      WHERE app_type IS DISTINCT FROM 'school'
        OR status IS DISTINCT FROM 'planned'
        OR voided_at IS NOT NULL
        OR is_billable IS DISTINCT FROM true
        OR student_id NOT IN (
          '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
          'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid
        )
        OR business_entity_id IS DISTINCT FROM
          '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
        OR student_settlement_month IS DISTINCT FROM billing_month
        OR billing_month_source NOT IN (
          'approved_r1c_a_manifest',
          'approved_r1c_c_b_manifest'
        )
        OR extract(isodow FROM billing_week_start_date) <> 1
        OR to_char(billing_week_start_date, 'YYYY-MM') <> billing_month
        OR lesson_date IS DISTINCT FROM billing_week_start_date
        OR scheduled_lesson_date IS NOT NULL
        OR lesson_delivery_mode IS NOT NULL
        OR lesson_venue IS NOT NULL
        OR teacher_id IS NULL
        OR subject_id IS NULL
        OR lesson_count IS NULL
        OR lesson_count <= 0
        OR duration_hours IS NULL
        OR duration_hours <= 0
        OR unit_price IS NULL
        OR unit_price <= 0
        OR lesson_fee IS NULL
        OR lesson_fee <= 0
        OR created_at IS NULL
        OR updated_at IS NULL
    ) AS invalid_business_row_count,
    count(*) FILTER (
      WHERE EXISTS (
        SELECT 1 FROM public.school_lesson_records actual
        WHERE actual.planned_lesson_id = fixed_scope.id
      )
    ) AS has_actual_count,
    count(*) FILTER (
      WHERE EXISTS (
        SELECT 1 FROM public.school_student_tuition_bill_lessons relation
        WHERE relation.planned_lesson_id = fixed_scope.id
      )
    ) AS has_bill_relation_count,
    count(*) FILTER (
      WHERE EXISTS (
        SELECT 1 FROM public.school_student_tuition_bills bill
        WHERE (bill.source_snapshot -> 'planned_lesson_ids') ? fixed_scope.id::text
      )
    ) AS has_bill_snapshot_count,
    count(*) FILTER (
      WHERE EXISTS (
        SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions exclusion
        WHERE exclusion.planned_lesson_id = fixed_scope.id
      )
    ) AS has_historical_exclusion_count
  FROM fixed_scope
)
SELECT
  'fixed_118_boundary' AS check_name,
  manifest_hash.*,
  lesson_count = 118
    AND duration_hours = 254
    AND lesson_fee_jpy = 2474000
    AND uuid_set_md5 = '77f697f82e547d84dcabf88a3c868aa1'
    AND business_manifest_sha256 =
      'f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1'
    AND invalid_business_row_count = 0
    AND has_actual_count = 0
    AND has_bill_relation_count = 0
    AND has_bill_snapshot_count = 0
    AND has_historical_exclusion_count = 0 AS all_expected
FROM manifest_hash;

WITH legacy_scope AS (
  SELECT lesson.id
  FROM public.school_lesson_records lesson
  WHERE lesson.lesson_type = 'planned'
    AND lesson.billing_month IS NULL
    AND lesson.billing_week_start_date IS NULL
    AND lesson.student_settlement_month IS NULL
    AND lesson.billing_month_source IS NULL
    AND lesson.billing_month_decided_at IS NULL
), partial_scope AS (
  SELECT lesson.id
  FROM public.school_lesson_records lesson
  WHERE lesson.lesson_type = 'planned'
    AND num_nonnulls(
      lesson.billing_month,
      lesson.billing_week_start_date,
      lesson.student_settlement_month,
      lesson.billing_month_source,
      lesson.billing_month_decided_at
    ) BETWEEN 1 AND 4
)
SELECT
  'legacy_279_boundary' AS check_name,
  (SELECT count(*) FROM legacy_scope) AS legacy_count,
  (SELECT md5(string_agg(id::text, ',' ORDER BY id::text)) FROM legacy_scope)
    AS legacy_uuid_set_md5,
  (SELECT count(*) FROM partial_scope) AS partial_count,
  (SELECT count(*) FROM legacy_scope) = 279
    AND (SELECT md5(string_agg(id::text, ',' ORDER BY id::text)) FROM legacy_scope) =
      '0975fdc91b533680e5ccc909f076ac62'
    AND (SELECT count(*) FROM partial_scope) = 0 AS all_expected;

WITH eligible_candidate AS (
  SELECT lesson.id, lesson.duration_hours, lesson.lesson_fee
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type = 'school'
    AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned'
    AND lesson.voided_at IS NULL
    AND lesson.is_billable IS true
    AND lesson.student_id IS NOT NULL
    AND lesson.business_entity_id IS NOT NULL
    AND lesson.billing_month IS NOT NULL
    AND lesson.billing_week_start_date IS NOT NULL
    AND extract(isodow FROM lesson.billing_week_start_date) = 1
    AND to_char(lesson.billing_week_start_date, 'YYYY-MM') = lesson.billing_month
    AND lesson.student_settlement_month = lesson.billing_month
    AND lesson.billing_month_source IN (
      'approved_r1c_a_manifest',
      'approved_r1c_c_b_manifest'
    )
    AND lesson.billing_month_decided_at IS NOT NULL
    AND lesson.lesson_date IS NOT NULL
    AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.lesson_count IS NOT NULL
    AND lesson.lesson_count > 0
    AND lesson.duration_hours > 0
    AND lesson.unit_price IS NOT NULL
    AND lesson.unit_price > 0
    AND lesson.lesson_fee IS NOT NULL
    AND lesson.lesson_fee > 0
    AND lesson.created_at IS NOT NULL
    AND lesson.updated_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.school_student_tuition_bill_lessons relation
      WHERE relation.planned_lesson_id = lesson.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.school_student_tuition_bills bill
      WHERE (bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions exclusion
      WHERE exclusion.planned_lesson_id = lesson.id
    )
)
SELECT
  'candidate_table_emulation' AS check_name,
  count(*) AS candidate_count,
  sum(duration_hours) AS duration_hours,
  sum(lesson_fee) AS lesson_fee_jpy,
  md5(string_agg(id::text, ',' ORDER BY id::text)) AS uuid_set_md5,
  count(*) = 118
    AND sum(duration_hours) = 254
    AND sum(lesson_fee) = 2474000
    AND md5(string_agg(id::text, ',' ORDER BY id::text)) =
      '77f697f82e547d84dcabf88a3c868aa1' AS all_expected
FROM eligible_candidate;

SELECT
  'lesson_type_status_distribution' AS check_name,
  lesson_type,
  status,
  is_billable,
  count(*) AS row_count
FROM public.school_lesson_records
GROUP BY lesson_type, status, is_billable
ORDER BY lesson_type, status, is_billable;

SELECT
  'lesson_mode_venue_distribution' AS check_name,
  lesson_type,
  coalesce(lesson_delivery_mode, '<NULL>') AS delivery_mode,
  coalesce(lesson_venue, '<NULL>') AS venue,
  count(*) AS row_count
FROM public.school_lesson_records
GROUP BY lesson_type, lesson_delivery_mode, lesson_venue
ORDER BY lesson_type, delivery_mode, venue;

WITH planned_time AS (
  SELECT lesson.*,
    start_time::text AS start_text,
    end_time::text AS end_text
  FROM public.school_lesson_records lesson
  WHERE lesson.lesson_type = 'planned'
)
SELECT
  'planned_time_duration_conflicts' AS check_name,
  count(*) AS planned_count,
  count(*) FILTER (WHERE start_time IS NULL AND end_time IS NULL) AS both_time_null_count,
  count(*) FILTER (WHERE num_nonnulls(start_time, end_time) = 1) AS partial_time_count,
  count(*) FILTER (WHERE start_time IS NOT NULL AND end_time IS NOT NULL) AS complete_time_count,
  count(*) FILTER (
    WHERE CASE
      WHEN start_text ~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$'
       AND end_text ~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$'
      THEN end_text::time <= start_text::time
      ELSE false
    END
  ) AS cross_midnight_or_nonpositive_count,
  count(*) FILTER (WHERE duration_hours IS NULL) AS duration_null_count,
  count(*) FILTER (WHERE duration_hours < 2) AS duration_below_two_count,
  count(*) FILTER (WHERE duration_hours > 0 AND trunc(duration_hours * 60) <> duration_hours * 60)
    AS duration_subminute_count,
  count(*) FILTER (WHERE duration_hours > 0 AND mod(duration_hours * 60, 15) <> 0)
    AS duration_not_quarter_hour_count,
  count(*) FILTER (WHERE duration_hours > 0 AND mod(duration_hours, 1) <> 0)
    AS non_integer_hour_count,
  count(*) FILTER (
    WHERE lesson_fee IS DISTINCT FROM round(coalesce(duration_hours, 0) * coalesce(unit_price, 0))
  ) AS base_fee_formula_mismatch_count
FROM planned_time;

SELECT
  'planned_duration_distribution' AS check_name,
  duration_hours,
  count(*) AS row_count
FROM public.school_lesson_records
WHERE lesson_type = 'planned'
GROUP BY duration_hours
ORDER BY duration_hours NULLS FIRST;

SELECT
  'scheduled_billing_pair_conflicts' AS check_name,
  count(*) FILTER (
    WHERE lesson_type = 'planned'
      AND scheduled_lesson_date IS NOT NULL
      AND (
        billing_week_start_date IS NULL
        OR scheduled_lesson_date < billing_week_start_date
        OR scheduled_lesson_date > billing_week_start_date + 6
      )
  ) AS scheduled_outside_frozen_week_count,
  count(*) FILTER (
    WHERE lesson_type = 'planned'
      AND billing_week_start_date IS NOT NULL
      AND extract(isodow FROM billing_week_start_date) <> 1
  ) AS non_monday_billing_week_count,
  count(*) FILTER (
    WHERE lesson_type = 'planned'
      AND billing_week_start_date IS NOT NULL
      AND billing_month IS DISTINCT FROM to_char(billing_week_start_date, 'YYYY-MM')
  ) AS billing_month_week_mismatch_count,
  count(*) FILTER (
    WHERE lesson_type = 'planned'
      AND student_settlement_month IS NOT NULL
      AND billing_month IS DISTINCT FROM student_settlement_month
  ) AS student_settlement_billing_mismatch_count
FROM public.school_lesson_records;

SELECT
  'bill_relation_freeze_inventory' AS check_name,
  relation.relation_role,
  bill.status AS bill_status,
  count(*) AS relation_count,
  count(*) FILTER (WHERE relation.week_start_date_snapshot IS NOT NULL) AS week_snapshot_count,
  count(*) FILTER (WHERE relation.scheduled_lesson_date_snapshot IS NOT NULL) AS scheduled_snapshot_count,
  count(*) FILTER (WHERE relation.source_snapshot IS NOT NULL) AS source_snapshot_count,
  count(*) FILTER (WHERE relation.lesson_fee_jpy_snapshot IS NOT NULL) AS fee_snapshot_count
FROM public.school_student_tuition_bill_lessons relation
JOIN public.school_student_tuition_bills bill ON bill.id = relation.tuition_bill_id
GROUP BY relation.relation_role, bill.status
ORDER BY relation.relation_role, bill.status;

SELECT
  'billed_planned_mutability_inventory' AS check_name,
  count(DISTINCT relation.planned_lesson_id) AS billed_planned_count,
  count(*) FILTER (WHERE lesson.status IN ('planned', 'pending_makeup')) AS currently_editable_status_count,
  count(*) FILTER (WHERE lesson.voided_at IS NULL) AS not_voided_count,
  count(*) FILTER (
    WHERE NOT EXISTS (
      SELECT 1 FROM public.school_lesson_records actual
      WHERE actual.planned_lesson_id = lesson.id
    )
  ) AS no_linked_actual_count
FROM public.school_student_tuition_bill_lessons relation
JOIN public.school_lesson_records lesson ON lesson.id = relation.planned_lesson_id;

SELECT
  'bill_snapshot_inventory' AS check_name,
  count(*) AS bill_count,
  count(*) FILTER (WHERE source_snapshot ? 'planned_lesson_ids') AS has_planned_ids_count,
  count(*) FILTER (WHERE source_snapshot ? 'planned_lesson_fee_jpy') AS has_planned_fee_count,
  count(*) FILTER (WHERE source_snapshot ? 'aircon_fee_jpy') AS has_aircon_fee_count,
  count(*) FILTER (WHERE source_snapshot ? 'calculation_version') AS has_calculation_version_count
FROM public.school_student_tuition_bills;

SELECT
  'school_financial_chain_snapshot' AS check_name,
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
   FROM public.school_student_tuition_bills row_value) AS bill_hash,
  (SELECT count(*) FROM public.school_income_records) AS income_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
   FROM public.school_income_records row_value) AS income_hash,
  (SELECT count(*) FROM public.school_student_tuition_bill_lessons) AS relation_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
   FROM public.school_student_tuition_bill_lessons row_value) AS relation_hash,
  (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) AS exclusion_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
   FROM public.school_student_tuition_historical_lesson_exclusions row_value) AS exclusion_hash;

SELECT
  'lesson_snapshot' AS check_name,
  count(*) AS lesson_count,
  count(*) FILTER (WHERE lesson_type = 'planned') AS planned_count,
  count(*) FILTER (WHERE lesson_type = 'actual') AS actual_count,
  md5(coalesce(string_agg(md5(to_jsonb(lesson)::text), '' ORDER BY lesson.id::text), '')) AS lesson_hash
FROM public.school_lesson_records lesson;

SELECT
  'r0_feature_gates_end' AS check_name,
  feature_key,
  state,
  CASE feature_key
    WHEN 'student_tuition_preview' THEN state = 'validation_preview_only'
    WHEN 'student_tuition_generate' THEN state = 'blocked'
    WHEN 'student_tuition_cash_submit' THEN state = 'blocked'
    ELSE false
  END AS expected_state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

SELECT
  'candidate_definition_end' AS check_name,
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) AS definition_md5,
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) = '8981a2ce07abf8c28231bfaf05451368' AS all_expected;

SELECT
  'final_read_only_state' AS check_name,
  current_setting('transaction_isolation') AS isolation_level,
  current_setting('transaction_read_only') AS read_only,
  current_setting('transaction_read_only') = 'on' AS all_expected;

ROLLBACK;
