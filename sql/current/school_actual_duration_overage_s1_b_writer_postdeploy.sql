\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

DO $postdeploy$
DECLARE
  v_constraint record;
  v_expected_md5 text;
  v_count bigint;
  v_hash text;
BEGIN
  IF position('S1_B_OVERAGE_CANONICAL_SOURCE_REQUIRED' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) = 0
     OR position('v_overage_duration := v_duration_hours - v_planned.duration_hours' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) = 0
     OR position('v_overage_fee_jpy := round(v_overage_duration * v_planned.unit_price)' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) = 0
     OR position('student_duration_overage_decided_at' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) = 0
     OR position('aircon' IN lower(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     ))) > 0 THEN
    RAISE EXCEPTION 'S1_B_ORDINARY_WRITER_DEFINITION_INVALID';
  END IF;

  IF position('S1_B_OVERAGE_CHARGE_FIELDS_IMMUTABLE' IN pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) = 0
     OR position('R1D_E_B2_GUARDED_ACTUAL_STUDENT_MONTH_UNCLASSIFIED' IN pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) = 0 THEN
    RAISE EXCEPTION 'S1_B_GUARDED_WRITER_DEFINITION_INVALID';
  END IF;

  IF (SELECT pg_get_userbyid(proowner) FROM pg_proc
      WHERE oid = 'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure) <> 'postgres'
     OR NOT (SELECT prosecdef FROM pg_proc
      WHERE oid = 'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure)
     OR (SELECT proconfig::text FROM pg_proc
      WHERE oid = 'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure) <> '{search_path=public}'
     OR (SELECT proacl::text FROM pg_proc
      WHERE oid = 'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure)
        <> '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
     OR (SELECT pg_get_userbyid(proowner) FROM pg_proc
      WHERE oid = 'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure) <> 'postgres'
     OR NOT (SELECT prosecdef FROM pg_proc
      WHERE oid = 'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure)
     OR (SELECT proconfig::text FROM pg_proc
      WHERE oid = 'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure) <> '{search_path=public}'
     OR (SELECT proacl::text FROM pg_proc
      WHERE oid = 'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure)
        <> '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'S1_B_FUNCTION_OWNER_SECURITY_SEARCH_PATH_OR_ACL_CHANGED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
     )) <> '12ed369b1af2de6860ae88ce143312a3'
     OR md5(pg_get_functiondef(
       'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure
     )) <> 'ec7bdebb8b2eacf0527c603a32650af9'
     OR md5(pg_get_functiondef(
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
     )) <> '3b9378e01900b0e73b9d0b1c2d1e7209'
     OR md5(pg_get_functiondef(
       'public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure
     )) <> '7f82002b32e9a540d1d2372ecfcdf8ce'
     OR md5(pg_get_functiondef(
       'public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure
     )) <> 'e4ccad383d6fff19ca811bb97ebe87f7'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure
     )) <> 'dca22a58c3efad550d87597385a143df' THEN
    RAISE EXCEPTION 'S1_B_NON_TARGET_ACTUAL_WRITER_CHANGED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     )) <> '4a163f6691c779531a65a10be0f4422e'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     )) <> '08f3c60890d4afab8d9c730eec286c8d'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure
     )) <> 'b83f0a270a79c4ed07663ab2c296360e'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     )) <> '8de65e9787d8d66f2cd7b65eb2479a8c'
     OR md5(pg_get_functiondef(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)'::regprocedure
     )) <> '155e831118acbeadfd04b6640324c7cd'
     OR md5(pg_get_functiondef(
       'public.school_resolve_planned_duration(text,text,numeric)'::regprocedure
     )) <> '4f5b754585c9e3752639e6b0f2fa7a34'
     OR md5(pg_get_functiondef(
       'public.school_calculate_planned_fee_components(uuid,date,uuid,numeric,numeric)'::regprocedure
     )) <> '2dfabf4a920f7138043079855347207b' THEN
    RAISE EXCEPTION 'S1_B_PROTECTED_AUTHORITY_FUNCTION_CHANGED';
  END IF;

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text, '<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(ARRAY[
      'school_get_student_monthly_settlement_summary',
      'school_get_student_monthly_settlement_preview',
      'school_get_student_monthly_settlement_wage_blockers',
      'school_assert_student_monthly_settlement_no_wage_blocker',
      'school_lock_student_monthly_settlement',
      'school_unlock_student_monthly_settlement',
      'school_relock_student_monthly_settlement',
      'school_set_student_monthly_settlement_draft_adjustment']::text[])
  )
  SELECT count(*), md5(string_agg(concat_ws('|', signature, definition_md5, acl), E'\n' ORDER BY signature))
  INTO v_count, v_hash FROM functions;
  IF v_count <> 8 OR v_hash <> 'b3818fc1119b5b2c1069d78164760e95' THEN
    RAISE EXCEPTION 'S1_B_E_C_READER_GROUP_CHANGED';
  END IF;

  FOR v_constraint IN
    SELECT conname, md5(pg_get_constraintdef(oid, true)) AS definition_md5
    FROM pg_constraint
    WHERE conname IN (
      'school_lesson_records_duration_overage_bundle_chk',
      'school_lesson_records_duration_overage_context_chk',
      'school_lesson_records_duration_overage_amount_chk',
      'school_student_settlements_duration_overage_bundle_chk',
      'school_student_settlements_duration_overage_policy_chk',
      'school_student_settlements_duration_overage_amount_chk'
    )
  LOOP
    v_expected_md5 := CASE v_constraint.conname
      WHEN 'school_lesson_records_duration_overage_amount_chk' THEN 'aeb662dbbe94f4edc762fc7f0cce01af'
      WHEN 'school_lesson_records_duration_overage_bundle_chk' THEN '11734ff65bfe2cd11245b97badc6031e'
      WHEN 'school_lesson_records_duration_overage_context_chk' THEN '8f4ed33a0acde88149edcb3b2a53abba'
      WHEN 'school_student_settlements_duration_overage_amount_chk' THEN '4162bb6cd2c2306524673657e7daa6de'
      WHEN 'school_student_settlements_duration_overage_bundle_chk' THEN 'e9b4974c90d80a032ff56f500276a25a'
      WHEN 'school_student_settlements_duration_overage_policy_chk' THEN '3275c0d1fb1b72e5261019a1f505d00d'
      ELSE NULL
    END;
    IF v_constraint.definition_md5 IS DISTINCT FROM v_expected_md5 THEN
      RAISE EXCEPTION 'S1_B_S1_A_CONSTRAINT_CHANGED: %', v_constraint.conname;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_constraint WHERE conname IN (
      'school_lesson_records_duration_overage_bundle_chk',
      'school_lesson_records_duration_overage_context_chk',
      'school_lesson_records_duration_overage_amount_chk',
      'school_student_settlements_duration_overage_bundle_chk',
      'school_student_settlements_duration_overage_policy_chk',
      'school_student_settlements_duration_overage_amount_chk')) <> 6 THEN
    RAISE EXCEPTION 'S1_B_S1_A_CONSTRAINT_COUNT_CHANGED';
  END IF;

  IF (SELECT count(*)
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_lesson_records'
        AND ((column_name = 'student_duration_overage_minutes' AND data_type = 'integer')
          OR (column_name = 'student_duration_overage_fee_jpy' AND data_type = 'numeric')
          OR (column_name = 'student_duration_overage_policy_version' AND data_type = 'text')
          OR (column_name = 'student_duration_overage_source' AND data_type = 'text')
          OR (column_name = 'student_duration_overage_decided_at' AND data_type = 'timestamp with time zone'))
        AND is_nullable = 'YES'
        AND column_default IS NULL) <> 5
     OR (SELECT count(*)
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_student_monthly_settlements'
        AND ((column_name = 'duration_overage_minutes' AND data_type = 'integer')
          OR (column_name = 'duration_overage_fee_jpy' AND data_type = 'numeric')
          OR (column_name = 'duration_overage_fee_cny' AND data_type = 'numeric')
          OR (column_name = 'duration_overage_actual_count' AND data_type = 'integer')
          OR (column_name = 'duration_overage_policy_version' AND data_type = 'text')
          OR (column_name = 'duration_overage_source' AND data_type = 'text'))
        AND is_nullable = 'YES'
        AND column_default IS NULL) <> 6 THEN
    RAISE EXCEPTION 'S1_B_S1_A_COLUMN_CONTRACT_CHANGED';
  END IF;

  IF (SELECT count(*)
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'school_lesson_records_duration_overage_month_idx'
        AND NOT i.indisunique
        AND position('(student_id, business_entity_id, student_settlement_month)' IN pg_get_indexdef(i.indexrelid)) > 0
        AND position('student_duration_overage_policy_version' IN pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_source' IN pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_fee_jpy' IN pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_v1' IN pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('ordinary_actual_rpc' IN pg_get_expr(i.indpred, i.indrelid)) > 0) <> 1
     OR (SELECT count(*)
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'school_lesson_records_duration_overage_planned_uidx'
        AND i.indisunique
        AND position('(planned_lesson_id)' IN pg_get_indexdef(i.indexrelid)) > 0
        AND position('student_duration_overage_policy_version' IN pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_source' IN pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_v1' IN pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('ordinary_actual_rpc' IN pg_get_expr(i.indpred, i.indrelid)) > 0) <> 1 THEN
    RAISE EXCEPTION 'S1_B_S1_A_INDEX_CONTRACT_CHANGED';
  END IF;

  IF (SELECT count(*)
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'school_lesson_records'
        AND NOT t.tgisinternal) <> 5
     OR EXISTS (
       WITH expected(
         trigger_name,
         trigger_function_name,
         trigger_function_md5,
         trigger_definition
       ) AS (
         VALUES
           (
             'trg_school_lesson_actual_minutes_sync',
             'school_sync_lesson_actual_minutes',
             'db4f27badd7f5394aef95ada41ae8494',
             'CREATE TRIGGER trg_school_lesson_actual_minutes_sync BEFORE INSERT OR UPDATE OF app_type, lesson_type, status, duration_hours, actual_minutes ON school_lesson_records FOR EACH ROW EXECUTE FUNCTION school_sync_lesson_actual_minutes()'
           ),
           (
             'trg_school_lesson_inherit_schedule_venue',
             'school_lesson_inherit_schedule_venue',
             'a4380763f876ff986d3f39e42edf905a',
             'CREATE TRIGGER trg_school_lesson_inherit_schedule_venue BEFORE INSERT ON school_lesson_records FOR EACH ROW EXECUTE FUNCTION school_lesson_inherit_schedule_venue()'
           ),
           (
             'trg_school_lesson_r1d_e_b2_actual_attribution',
             'school_enforce_r1d_e_b2_actual_attribution',
             '4a163f6691c779531a65a10be0f4422e',
             'CREATE TRIGGER trg_school_lesson_r1d_e_b2_actual_attribution BEFORE INSERT OR UPDATE ON school_lesson_records FOR EACH ROW EXECUTE FUNCTION school_enforce_r1d_e_b2_actual_attribution()'
           ),
           (
             'trg_school_lesson_r1d_f1_planned_attribution',
             'school_enforce_r1d_f1_planned_attribution',
             '08f3c60890d4afab8d9c730eec286c8d',
             'CREATE TRIGGER trg_school_lesson_r1d_f1_planned_attribution BEFORE INSERT OR UPDATE ON school_lesson_records FOR EACH ROW EXECUTE FUNCTION school_enforce_r1d_f1_planned_attribution()'
           ),
           (
             'trg_school_lesson_records_updated_at',
             'school_set_updated_at',
             '902d1d51a8bce287ee0f12cdcfc3bffb',
             'CREATE TRIGGER trg_school_lesson_records_updated_at BEFORE UPDATE ON school_lesson_records FOR EACH ROW EXECUTE FUNCTION school_set_updated_at()'
           )
       ), actual AS (
         SELECT
           t.tgname AS trigger_name,
           p.proname AS trigger_function_name,
           md5(pg_get_functiondef(p.oid)) AS trigger_function_md5,
           pg_get_triggerdef(t.oid, true) AS trigger_definition
         FROM pg_trigger t
         JOIN pg_class c ON c.oid = t.tgrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         JOIN pg_proc p ON p.oid = t.tgfoid
         WHERE n.nspname = 'public'
           AND c.relname = 'school_lesson_records'
           AND NOT t.tgisinternal
       )
       SELECT 1
       FROM expected e
       FULL JOIN actual a USING (trigger_name)
       WHERE a.trigger_name IS NULL
          OR e.trigger_name IS NULL
          OR a.trigger_function_name IS DISTINCT FROM e.trigger_function_name
          OR a.trigger_function_md5 IS DISTINCT FROM e.trigger_function_md5
          OR a.trigger_definition IS DISTINCT FROM e.trigger_definition
     )
     OR EXISTS (
       SELECT 1
       FROM pg_trigger t
       JOIN pg_class c ON c.oid = t.tgrelid
       JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public'
         AND c.relname = 'school_lesson_records'
         AND NOT t.tgisinternal
         AND t.tgname LIKE '%overage%'
     ) THEN
    RAISE EXCEPTION 'S1_B_UNEXPECTED_TRIGGER_CHANGE';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 649
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned') <> 414
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'actual') <> 235
     OR (SELECT count(*) FROM public.school_student_monthly_settlements) <> 15
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(
           student_duration_overage_minutes,
           student_duration_overage_fee_jpy,
           student_duration_overage_policy_version,
           student_duration_overage_source,
           student_duration_overage_decided_at
         ) > 0) <> 0
     OR (SELECT count(*) FROM public.school_student_monthly_settlements
         WHERE num_nonnulls(
           duration_overage_minutes,
           duration_overage_fee_jpy,
           duration_overage_fee_cny,
           duration_overage_actual_count,
           duration_overage_policy_version,
           duration_overage_source
         ) > 0) <> 0 THEN
    RAISE EXCEPTION 'S1_B_DEPLOYMENT_DATA_BOUNDARY_CHANGED';
  END IF;

  IF (SELECT md5(coalesce(string_agg(md5((to_jsonb(l) - ARRAY[
        'student_duration_overage_minutes',
        'student_duration_overage_fee_jpy',
        'student_duration_overage_policy_version',
        'student_duration_overage_source',
        'student_duration_overage_decided_at'
      ])::text), '' ORDER BY l.id::text), ''))
      FROM public.school_lesson_records l
      WHERE l.created_at <= TIMESTAMPTZ '2026-07-29 18:37:10.228629+00')
      <> 'fd8b5570f42d618f136b2f6408704ae8'
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(s) - ARRAY[
        'duration_overage_minutes',
        'duration_overage_fee_jpy',
        'duration_overage_fee_cny',
        'duration_overage_actual_count',
        'duration_overage_policy_version',
        'duration_overage_source'
      ])::text), '' ORDER BY s.id::text), ''))
      FROM public.school_student_monthly_settlements s
      WHERE s.created_at <= TIMESTAMPTZ '2026-07-29 18:37:10.228629+00')
      <> '7925cf3018bd0e669cd29710f6593238'
     OR (SELECT md5(string_agg(l.id::text || ':' || l.duration_hours::text || ':' ||
        l.lesson_fee::text || ':' || l.updated_at::text, ',' ORDER BY l.id::text))
      FROM public.school_lesson_records l
      WHERE l.id IN (
        '14f0ad66-6a72-4562-bdf6-f867f5e7901d','1cb708d2-404b-4fed-a9cb-fb9b974da41c',
        '4645f239-d6f7-473f-96e0-75647cf2b937','4c0214ac-6ce5-4afd-b518-e3d6bd9ab978',
        '555faff7-6658-4860-8277-22f2bc4a9c65','5e0786c6-8b10-4e10-9e84-addaedd5509e',
        '6a3641db-4740-4d95-b1c9-8e3ae77516c2','6e16fea8-c408-421a-adc2-05107f987f5b',
        '714c671d-b98a-464f-afe2-629ed4ba148b','78301f55-e157-4219-8c29-8a87f5a8fa0b',
        '7f468446-13e2-489d-aec5-2b64aeca4f9a','a13b216e-4524-4315-b5aa-c1d2cc053082',
        'a7275d9c-15f1-4829-a78e-fc48b9e88e14','a97f7d25-061d-4504-a47e-53490ba81061',
        'acbc65c8-ba47-4595-b2db-244ae74f83d0','ae53ba74-3cb6-4090-ac7d-d19332dcad9d',
        'b74f743a-0acc-4156-9f00-2d6dfe388ce2','bb4a9aa8-f3dc-4681-a934-e049ff3dce33',
        'eefe54b0-5a01-4836-b1d1-ffcca570447d'
      )) <> '352e72ac33d648a23be84bb27b3580d1' THEN
    RAISE EXCEPTION 'S1_B_STABLE_HISTORY_HASH_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE num_nonnulls(base_lesson_fee_jpy, aircon_fee_jpy, fee_calculation_version) > 0) <> 0
     OR (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121 THEN
    RAISE EXCEPTION 'S1_B_AIRCON_OR_FINANCIAL_BOUNDARY_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_B_R0_CHANGED';
  END IF;

  IF (SELECT relacl::text FROM pg_class WHERE oid = 'public.school_lesson_records'::regclass)
       <> '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'
     OR (SELECT count(*) FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'school_lesson_records'
           AND policyname = 'school_allow_all_lesson_records'
           AND cmd = 'ALL' AND qual = 'true' AND with_check = 'true') <> 1 THEN
    RAISE EXCEPTION 'S1_B_RECORDED_ACL_RLS_DEBT_CHANGED';
  END IF;
END
$postdeploy$;

WITH actual_functions AS (
  SELECT p.oid::regprocedure::text AS signature,
    md5(pg_get_functiondef(p.oid)) AS definition_md5,
    coalesce(p.proacl::text, '<NULL>') AS acl
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = ANY(ARRAY[
    'school_create_actual_lesson_from_planned',
    'school_create_cancelled_actual_lesson_from_planned',
    'school_create_partial_completed_actual_from_planned',
    'school_create_lesson_credit_makeup_actual',
    'school_create_makeup_completed_actual_lesson_from_planned',
    'school_create_cross_month_makeup_completed_actual_from_planned',
    'school_update_lesson_record_guarded',
    'school_update_lesson_record_guarded_with_venue']::text[])
)
SELECT
  md5(pg_get_functiondef(
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
  )) AS ordinary_writer_md5,
  md5(pg_get_functiondef(
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
  )) AS guarded_writer_md5,
  md5(string_agg(concat_ws('|', signature, definition_md5, acl), E'\n' ORDER BY signature)) AS actual_writer_group_md5
FROM actual_functions;

SELECT
  (SELECT count(*) FROM public.school_lesson_records) AS lesson_count,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE num_nonnulls(
     student_duration_overage_minutes,
     student_duration_overage_fee_jpy,
     student_duration_overage_policy_version,
     student_duration_overage_source,
     student_duration_overage_decided_at
   ) > 0) AS populated_overage_count,
  (SELECT count(*) FROM public.school_student_monthly_settlements) AS settlement_count,
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT count(*) FROM public.school_income_records) AS income_count,
  (SELECT count(*) FROM public.school_student_tuition_bill_lessons) AS bill_lesson_count;

SELECT feature_key, state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

ROLLBACK;
