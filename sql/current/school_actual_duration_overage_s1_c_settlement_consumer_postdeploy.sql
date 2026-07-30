\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '180s';

DO $verify$
DECLARE
  v_helper_definition text;
  v_summary_definition text;
  v_lock_definition text;
  v_relock_definition text;
  v_constraint record;
  v_expected_md5 text;
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'S1_C_POSTDEPLOY_NOT_READ_ONLY';
  END IF;

  IF to_regprocedure(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'
     ) IS NULL THEN
    RAISE EXCEPTION 'S1_C_AGGREGATE_HELPER_MISSING';
  END IF;

  SELECT pg_get_functiondef(
    'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure
  ) INTO STRICT v_helper_definition;
  SELECT pg_get_functiondef(
    'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure
  ) INTO STRICT v_summary_definition;
  SELECT pg_get_functiondef(
    'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure
  ) INTO STRICT v_lock_definition;
  SELECT pg_get_functiondef(
    'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure
  ) INTO STRICT v_relock_definition;

  IF md5(v_helper_definition) <> 'd24b82f51053b3960ce0e4839613ddc7'
     OR md5(v_summary_definition) <> 'f9f5e0fffc2d0fcb5f917cc374c9e9ac'
     OR md5(v_lock_definition) <> '523058b631837025101d558668ce10c8'
     OR md5(v_relock_definition) <> '5b313cc696057a4a1f960ed8f1b50124' THEN
    RAISE EXCEPTION 'S1_C_DEPLOYED_FUNCTION_MD5_MISMATCH';
  END IF;

  IF position('student_duration_overage_minutes' IN v_helper_definition) = 0
     OR position('student_duration_overage_fee_jpy' IN v_helper_definition) = 0
     OR position('student_settlement_month' IN v_helper_definition) = 0
     OR position('student_duration_overage_v1' IN v_helper_definition) = 0
     OR position('ordinary_actual_rpc' IN v_helper_definition) = 0
     OR position('school_primary_business_entity_id' IN v_helper_definition) = 0
     OR position('locked_snapshot' IN v_helper_definition) = 0
     OR position('legacy_locked_null_snapshot' IN v_helper_definition) = 0 THEN
    RAISE EXCEPTION 'S1_C_HELPER_ELIGIBILITY_OR_SNAPSHOT_LOGIC_MISSING';
  END IF;

  IF position('unit_price' IN v_helper_definition) > 0
     OR position('lesson_fee' IN v_helper_definition) > 0
     OR position('lesson_date' IN v_helper_definition) > 0
     OR position('planned_lesson_id' IN v_helper_definition) > 0
     OR position('aircon' IN v_helper_definition) > 0
     OR position('base_lesson_fee' IN v_helper_definition) > 0 THEN
    RAISE EXCEPTION 'S1_C_HELPER_RECOMPUTES_OR_USES_ADDONS';
  END IF;

  IF position('school_get_student_duration_overage_aggregate' IN
       v_summary_definition) = 0
     OR position('r.planned_fee_cny + r.duration_overage_fee_cny + r.carryover_cny' IN
       v_summary_definition) = 0
     OR position('actual_fee_cny + ' IN v_summary_definition) > 0 THEN
    RAISE EXCEPTION 'S1_C_SUMMARY_FORMULA_MISMATCH';
  END IF;

  IF position('duration_overage_minutes' IN v_lock_definition) = 0
     OR position('duration_overage_fee_jpy' IN v_lock_definition) = 0
     OR position('duration_overage_fee_cny' IN v_lock_definition) = 0
     OR position('duration_overage_actual_count' IN v_lock_definition) = 0
     OR position('student_duration_overage_v1' IN v_lock_definition) = 0
     OR position('monthly_settlement_lock' IN v_lock_definition) = 0
     OR position('duration_overage_minutes' IN v_relock_definition) = 0
     OR position('monthly_settlement_lock' IN v_relock_definition) = 0 THEN
    RAISE EXCEPTION 'S1_C_LOCK_OR_RELOCK_SNAPSHOT_LOGIC_MISSING';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_get_student_monthly_settlement_preview(uuid,text)'::regprocedure
     )) <> '1ddcfdd0344ba0ea3cf06d12058796ba'
     OR md5(pg_get_functiondef(
       'public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure
     )) <> 'dfeaa0243b27999724cc06bd1f1efbb6'
     OR md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) <> 'e3d9dd24f3fd7c533301bb5c1a27fa4f'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> 'ca52667c94a86608b4ab712f543b04b1'
     OR md5(pg_get_functiondef(
       'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
     )) <> '12ed369b1af2de6860ae88ce143312a3'
     OR md5(pg_get_functiondef(
       'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure
     )) <> 'ec7bdebb8b2eacf0527c603a32650af9'
     OR md5(pg_get_functiondef(
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
     )) <> '3b9378e01900b0e73b9d0b1c2d1e7209' THEN
    RAISE EXCEPTION 'S1_C_PROTECTED_WRITER_OR_READER_CHANGED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     )) <> '4a163f6691c779531a65a10be0f4422e'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     )) <> '08f3c60890d4afab8d9c730eec286c8d'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     )) <> '8de65e9787d8d66f2cd7b65eb2479a8c'
     OR md5(pg_get_functiondef(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)'::regprocedure
     )) <> '155e831118acbeadfd04b6640324c7cd' THEN
    RAISE EXCEPTION 'S1_C_AUTHORITY_CHAIN_CHANGED';
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
      WHEN 'school_lesson_records_duration_overage_amount_chk'
        THEN 'aeb662dbbe94f4edc762fc7f0cce01af'
      WHEN 'school_lesson_records_duration_overage_bundle_chk'
        THEN '11734ff65bfe2cd11245b97badc6031e'
      WHEN 'school_lesson_records_duration_overage_context_chk'
        THEN '8f4ed33a0acde88149edcb3b2a53abba'
      WHEN 'school_student_settlements_duration_overage_amount_chk'
        THEN '4162bb6cd2c2306524673657e7daa6de'
      WHEN 'school_student_settlements_duration_overage_bundle_chk'
        THEN 'e9b4974c90d80a032ff56f500276a25a'
      WHEN 'school_student_settlements_duration_overage_policy_chk'
        THEN '3275c0d1fb1b72e5261019a1f505d00d'
      ELSE NULL
    END;
    IF v_constraint.definition_md5 IS DISTINCT FROM v_expected_md5 THEN
      RAISE EXCEPTION 'S1_C_S1_A_CONSTRAINT_CHANGED: %',
        v_constraint.conname;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM pg_constraint WHERE conname IN (
      'school_lesson_records_duration_overage_bundle_chk',
      'school_lesson_records_duration_overage_context_chk',
      'school_lesson_records_duration_overage_amount_chk',
      'school_student_settlements_duration_overage_bundle_chk',
      'school_student_settlements_duration_overage_policy_chk',
      'school_student_settlements_duration_overage_amount_chk')) <> 6 THEN
    RAISE EXCEPTION 'S1_C_S1_A_CONSTRAINT_COUNT_CHANGED';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.school_get_student_duration_overage_aggregate(uuid,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.school_get_student_duration_overage_aggregate(uuid,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.school_get_student_duration_overage_aggregate(uuid,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'S1_C_HELPER_ACL_MISMATCH';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND NOT t.tgisinternal
      AND (t.tgname ILIKE '%overage%'
           OR pg_get_triggerdef(t.oid, true) ILIKE '%overage%')
  ) THEN
    RAISE EXCEPTION 'S1_C_UNEXPECTED_OVERAGE_TRIGGER';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE student_duration_overage_policy_version IS NOT NULL) <> 0
     OR (SELECT count(*) FROM public.school_student_monthly_settlements
         WHERE duration_overage_policy_version IS NOT NULL) <> 0 THEN
    RAISE EXCEPTION 'S1_C_DEPLOY_FILLED_OVERAGE_HISTORY';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_C_R0_CHANGED';
  END IF;
END
$verify$;

SELECT p.oid::regprocedure::text AS signature,
       md5(pg_get_functiondef(p.oid)) AS definition_md5,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer,
       p.provolatile AS volatility,
       coalesce(p.proacl::text, '<NULL>') AS acl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'school_get_student_duration_overage_aggregate',
    'school_get_student_monthly_settlement_summary',
    'school_get_student_monthly_settlement_preview',
    'school_lock_student_monthly_settlement',
    'school_unlock_student_monthly_settlement',
    'school_relock_student_monthly_settlement'
  )
ORDER BY signature;

SELECT
  (SELECT count(*) FROM public.school_lesson_records
   WHERE student_duration_overage_policy_version IS NOT NULL)
    AS lesson_overage_nonnull,
  (SELECT count(*) FROM public.school_student_monthly_settlements
   WHERE duration_overage_policy_version IS NOT NULL)
    AS settlement_overage_nonnull,
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT count(*) FROM public.school_income_records) AS income_count;

SELECT feature_key, state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

ROLLBACK;
