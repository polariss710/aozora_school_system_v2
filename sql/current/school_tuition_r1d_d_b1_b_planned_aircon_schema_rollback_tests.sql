\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $pretest$
BEGIN
  IF (SELECT count(*) FROM public.school_lesson_venues)
     +(SELECT count(*) FROM public.school_student_aircon_rates)
     +(SELECT count(*) FROM public.school_planned_writer_commands)
     +(SELECT count(*) FROM public.school_venue_rate_change_audit) <> 0 THEN
    RAISE EXCEPTION 'B1-B rollback tests: new tables must be empty before testing';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_records WHERE
      num_nonnulls(base_lesson_fee_jpy,lesson_venue_id,aircon_charge_status,aircon_rate_id,
        aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,aircon_fee_jpy,
        aircon_calculated_at,fee_calculation_version,fee_block_reason_code,
        fee_components_frozen_at) > 0) <> 0
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons WHERE
      num_nonnulls(base_lesson_fee_jpy_snapshot,aircon_rate_id_snapshot,
        aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
        aircon_fee_jpy_snapshot,fee_calculation_version_snapshot,
        lesson_venue_id_snapshot,lesson_venue_code_snapshot) > 0) <> 0 THEN
    RAISE EXCEPTION 'B1-B rollback tests: historical additive fields are not all null';
  END IF;
END
$pretest$;

SET CONSTRAINTS school_student_aircon_rates_student_id_fkey DEFERRED;

INSERT INTO public.school_lesson_venues
  (id,code,display_name,delivery_mode,aircon_eligible,effective_from,effective_to,is_active,created_by)
VALUES
  ('a2000000-0000-4000-8000-000000000001','codex-test-onsite-rb','Codex Test Onsite','onsite',true,'2026-01-01',NULL,true,NULL),
  ('a2000000-0000-4000-8000-000000000002','codex-test-online-rb','Codex Test Online','online',false,'2026-01-01',NULL,true,NULL);

INSERT INTO public.school_student_aircon_rates
  (id,student_id,unit_price_jpy,effective_from,effective_to,reason)
VALUES
  ('b2000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001',0,'2026-08-01','2026-09-01','codex-test zero rate'),
  ('b2000000-0000-4000-8000-000000000002','c2000000-0000-4000-8000-000000000001',660,'2026-09-01',NULL,'codex-test max rate'),
  ('b2000000-0000-4000-8000-000000000003','c2000000-0000-4000-8000-000000000002',660,'2026-08-01','2026-09-01','codex-test different student');

INSERT INTO public.school_planned_writer_commands
  (id,request_id,operation_type,payload_hash,status,created_by)
VALUES
  ('d2000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000002',
    'codex-test','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','pending',NULL);

INSERT INTO public.school_venue_rate_change_audit
  (id,action,target_type,target_id,old_snapshot,new_snapshot,actor_id,reason)
VALUES
  ('e2000000-0000-4000-8000-000000000001','codex-test','venue',
    'a2000000-0000-4000-8000-000000000001',NULL,'{"test":true}'::jsonb,NULL,'codex-test rollback');

DO $tests$
DECLARE
  v_result record;
  v_function record;
BEGIN
  BEGIN
    INSERT INTO public.school_student_aircon_rates
      (id,student_id,unit_price_jpy,effective_from,effective_to,reason)
    VALUES ('b2000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000003',-1,'2026-08-01','2026-09-01','codex-test negative');
    RAISE EXCEPTION 'rollback tests: negative rate unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.school_student_aircon_rates
      (id,student_id,unit_price_jpy,effective_from,effective_to,reason)
    VALUES ('b2000000-0000-4000-8000-000000000005','c2000000-0000-4000-8000-000000000003',661,'2026-08-01','2026-09-01','codex-test above max');
    RAISE EXCEPTION 'rollback tests: rate 661 unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.school_student_aircon_rates
      (id,student_id,unit_price_jpy,effective_from,effective_to,reason)
    VALUES ('b2000000-0000-4000-8000-000000000006','c2000000-0000-4000-8000-000000000001',100,'2026-08-15','2026-08-20','codex-test overlap');
    RAISE EXCEPTION 'rollback tests: overlapping rate unexpectedly accepted';
  EXCEPTION WHEN exclusion_violation THEN NULL;
  END;

  IF public.school_resolve_planned_duration(NULL,NULL,2) <> 2
     OR public.school_resolve_planned_duration(NULL,NULL,3) <> 3
     OR public.school_resolve_planned_duration('15:00','17:00',NULL) <> 2 THEN
    RAISE EXCEPTION 'rollback tests: approved duration case mismatch';
  END IF;
  BEGIN PERFORM public.school_resolve_planned_duration(NULL,NULL,1);
    RAISE EXCEPTION 'rollback tests: duration 1 unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rollback tests:%' THEN RAISE; END IF; END;
  BEGIN PERFORM public.school_resolve_planned_duration(NULL,NULL,1.5);
    RAISE EXCEPTION 'rollback tests: duration 1.5 unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rollback tests:%' THEN RAISE; END IF; END;
  BEGIN PERFORM public.school_resolve_planned_duration(NULL,NULL,2.5);
    RAISE EXCEPTION 'rollback tests: duration 2.5 unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rollback tests:%' THEN RAISE; END IF; END;
  BEGIN PERFORM public.school_resolve_planned_duration('15:00','17:15',NULL);
    RAISE EXCEPTION 'rollback tests: 15:00-17:15 unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rollback tests:%' THEN RAISE; END IF; END;
  BEGIN PERFORM public.school_resolve_planned_duration('15:00',NULL,NULL);
    RAISE EXCEPTION 'rollback tests: one-sided time unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rollback tests:%' THEN RAISE; END IF; END;
  BEGIN PERFORM public.school_resolve_planned_duration('17:00','15:00',NULL);
    RAISE EXCEPTION 'rollback tests: reversed time unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rollback tests:%' THEN RAISE; END IF; END;

  SELECT * INTO v_result FROM public.school_resolve_planned_billing_attribution('2026-08-06',NULL);
  IF v_result.billing_week_start_date <> DATE '2026-08-03'
     OR v_result.billing_month <> '2026-08'
     OR v_result.student_settlement_month <> '2026-08'
     OR v_result.billing_month_source <> 'scheduled_date_at_create' THEN
    RAISE EXCEPTION 'rollback tests: scheduled billing attribution mismatch';
  END IF;
  SELECT * INTO v_result FROM public.school_resolve_planned_billing_attribution(NULL,'2026-08-03');
  IF v_result.billing_month_source <> 'explicit_billing_week_at_create' THEN
    RAISE EXCEPTION 'rollback tests: explicit billing attribution mismatch';
  END IF;
  BEGIN PERFORM * FROM public.school_resolve_planned_billing_attribution(NULL,'2026-08-04');
    RAISE EXCEPTION 'rollback tests: non-Monday explicit week unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rollback tests:%' THEN RAISE; END IF; END;
  BEGIN PERFORM * FROM public.school_resolve_planned_billing_attribution(NULL,NULL);
    RAISE EXCEPTION 'rollback tests: empty billing inputs unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rollback tests:%' THEN RAISE; END IF; END;
  BEGIN PERFORM * FROM public.school_resolve_planned_billing_attribution('2026-08-06','2026-08-03');
    RAISE EXCEPTION 'rollback tests: dual billing inputs unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'rollback tests:%' THEN RAISE; END IF; END;

  SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
    'c2000000-0000-4000-8000-000000000001','2026-08-01',
    'a2000000-0000-4000-8000-000000000001',2,1000);
  IF v_result.base_lesson_fee_jpy <> 2000 OR v_result.aircon_charge_status <> 'configured_zero'
     OR v_result.aircon_unit_price_jpy_snapshot <> 0
     OR v_result.aircon_billable_hours_snapshot <> 2 OR v_result.aircon_fee_jpy <> 0
     OR v_result.lesson_total_fee_jpy <> 2000 THEN
    RAISE EXCEPTION 'rollback tests: configured-zero fee components mismatch';
  END IF;
  SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
    'c2000000-0000-4000-8000-000000000001','2026-09-05',
    'a2000000-0000-4000-8000-000000000001',3,1000);
  IF v_result.base_lesson_fee_jpy <> 3000 OR v_result.aircon_charge_status <> 'calculated'
     OR v_result.aircon_unit_price_jpy_snapshot <> 660
     OR v_result.aircon_billable_hours_snapshot <> 3 OR v_result.aircon_fee_jpy <> 1980
     OR v_result.lesson_total_fee_jpy <> 4980 THEN
    RAISE EXCEPTION 'rollback tests: calculated fee components mismatch';
  END IF;
  SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
    'c2000000-0000-4000-8000-000000000099','2026-09-05',
    'a2000000-0000-4000-8000-000000000001',2,1000);
  IF v_result.aircon_charge_status <> 'unconfigured' OR v_result.aircon_unit_price_jpy_snapshot IS NOT NULL
     OR v_result.aircon_billable_hours_snapshot IS NOT NULL OR v_result.aircon_fee_jpy IS NOT NULL
     OR v_result.lesson_total_fee_jpy IS NOT NULL THEN
    RAISE EXCEPTION 'rollback tests: missing rate was not distinguished from zero';
  END IF;
  SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
    'c2000000-0000-4000-8000-000000000001',NULL,
    'a2000000-0000-4000-8000-000000000001',2,1000);
  IF v_result.aircon_charge_status <> 'pending_schedule' OR v_result.lesson_total_fee_jpy IS NOT NULL THEN
    RAISE EXCEPTION 'rollback tests: pending schedule mismatch';
  END IF;
  SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
    'c2000000-0000-4000-8000-000000000001','2026-08-01',NULL,2,1000);
  IF v_result.aircon_charge_status <> 'pending_venue' OR v_result.lesson_total_fee_jpy IS NOT NULL THEN
    RAISE EXCEPTION 'rollback tests: pending venue mismatch';
  END IF;
  SELECT * INTO v_result FROM public.school_calculate_planned_fee_components(
    'c2000000-0000-4000-8000-000000000001','2026-08-03',
    'a2000000-0000-4000-8000-000000000001',2,1000);
  IF v_result.aircon_charge_status <> 'not_applicable' OR v_result.aircon_fee_jpy <> 0
     OR v_result.lesson_total_fee_jpy <> 2000 THEN
    RAISE EXCEPTION 'rollback tests: weekday not-applicable mismatch';
  END IF;

  FOR v_function IN
    SELECT p.oid,p.proowner FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN (
      'school_resolve_planned_billing_attribution','school_resolve_planned_duration',
      'school_calculate_planned_fee_components')
  LOOP
    IF EXISTS (SELECT 1 FROM aclexplode(coalesce(
          (SELECT proacl FROM pg_proc WHERE oid = v_function.oid),
          acldefault('f',v_function.proowner))) a
        WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
       OR has_function_privilege('anon',v_function.oid,'EXECUTE')
       OR has_function_privilege('authenticated',v_function.oid,'EXECUTE') THEN
      RAISE EXCEPTION 'rollback tests: client execute privilege was not denied';
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
  ) THEN
    RAISE EXCEPTION 'rollback tests: client write privilege was not denied';
  END IF;

  IF md5(pg_get_functiondef(
      'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
    )) <> '8981a2ce07abf8c28231bfaf05451368'
     OR (SELECT count(*) FROM public.school_feature_gates WHERE
      (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only') OR
      (feature_key = 'student_tuition_generate' AND state = 'blocked') OR
      (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned') <> 397
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,
        billing_month_source,billing_month_decided_at) = 5) <> 118
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned'
      AND num_nonnulls(billing_month,billing_week_start_date,student_settlement_month,
        billing_month_source,billing_month_decided_at) = 0) <> 279 THEN
    RAISE EXCEPTION 'rollback tests: R0/candidate/planned boundary changed';
  END IF;
END
$tests$;

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
), frozen AS (
  SELECT
    (SELECT count(*) FROM rpc) AS old_rpc_count,
    (SELECT md5(string_agg(proname||'|'||args||'|'||md5(definition),E'\n' ORDER BY proname,args)) FROM rpc) AS old_rpc_definition_md5,
    (SELECT md5(string_agg(proname||'|'||args||'|'||coalesce(proacl::text,'NULL')||'|'||prosecdef||'|'||coalesce(proconfig::text,'NULL')||'|'||owner,E'\n' ORDER BY proname,args)) FROM rpc) AS old_rpc_acl_md5,
    (SELECT md5(coalesce(relacl::text,'NULL')||'|'||relrowsecurity||'|'||relforcerowsecurity) FROM pg_class WHERE oid = 'public.school_lesson_records'::regclass) AS lesson_acl_md5,
    (SELECT count(*) FROM policies) AS lesson_policy_count,
    (SELECT md5(coalesce(string_agg(policyname||'|'||permissive||'|'||roles::text||'|'||cmd||'|'||coalesce(qual,'NULL')||'|'||coalesce(with_check,'NULL'),E'\n' ORDER BY policyname),'')) FROM policies) AS lesson_policy_md5,
    (SELECT md5(coalesce(string_agg(t.tgname||'|'||pg_get_triggerdef(t.oid,true)||'|'||md5(pg_get_functiondef(t.tgfoid)),E'\n' ORDER BY t.tgname),'')) FROM pg_trigger t WHERE t.tgrelid = 'public.school_student_tuition_bill_lessons'::regclass AND NOT t.tgisinternal) AS relation_trigger_md5
)
SELECT CASE WHEN old_rpc_count = 11
  AND old_rpc_definition_md5 = '8ecb87eeab8dbf2953a985038927375d'
  AND old_rpc_acl_md5 = '200f9f7c5cb7983b2aa90aeec65693b2'
  AND lesson_acl_md5 = 'e4b4638d16b9a1a0e6c2662833bed732'
  AND lesson_policy_count = 1
  AND lesson_policy_md5 = '664065c128a736b78af24bec527dbf2c'
  AND relation_trigger_md5 = '5948fe7078a69ef943990208bd5aa532'
  THEN jsonb_build_object('rollback_tests_ok',true,'old_rpc_acl_rls_unchanged',true,
    'transactional_test_rows',7,'fake_student_ids',3)
  ELSE NULL END AS rollback_test_summary
FROM frozen;

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
    RAISE EXCEPTION 'B1-B rollback tests: old RPC/ACL/RLS/trigger fingerprint mismatch';
  END IF;
END
$old_boundary$;

ROLLBACK;

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
DO $residual$
BEGIN
  IF (SELECT count(*) FROM public.school_lesson_venues)
     +(SELECT count(*) FROM public.school_student_aircon_rates)
     +(SELECT count(*) FROM public.school_planned_writer_commands)
     +(SELECT count(*) FROM public.school_venue_rate_change_audit) <> 0 THEN
    RAISE EXCEPTION 'B1-B rollback tests: test rows remain after rollback';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_lesson_venues WHERE id IN (
      'a2000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000002'))
     OR EXISTS (SELECT 1 FROM public.school_student_aircon_rates WHERE id IN (
      'b2000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000002',
      'b2000000-0000-4000-8000-000000000003'))
     OR EXISTS (SELECT 1 FROM public.school_planned_writer_commands
      WHERE id = 'd2000000-0000-4000-8000-000000000001')
     OR EXISTS (SELECT 1 FROM public.school_venue_rate_change_audit
      WHERE id = 'e2000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'B1-B rollback tests: a known test ID remains';
  END IF;
END
$residual$;
SELECT jsonb_build_object('rollback_explicit',true,'test_residual_rows',0) AS rollback_residual_summary;
ROLLBACK;
