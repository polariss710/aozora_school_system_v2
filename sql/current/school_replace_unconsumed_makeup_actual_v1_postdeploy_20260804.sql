-- Read-only deployment and production preflight acceptance.

\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $verify$
DECLARE
  v_proc pg_proc%ROWTYPE;
  v_definition text;
BEGIN
  SELECT p.* INTO STRICT v_proc
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.oid='public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)'::regprocedure;
  v_definition:=pg_get_functiondef(v_proc.oid);

  IF v_proc.prosecdef IS DISTINCT FROM true
     OR NOT ('search_path=pg_catalog, public'=ANY(v_proc.proconfig))
     OR position('DELETE FROM public.school_lesson_records' IN v_definition)=0
     OR position('public.school_create_lesson_credit_makeup_actual(' IN v_definition)=0
     OR position('public.school_tuition_p0b1_lock_lesson_scopes' IN v_definition)=0
     OR position('MAKEUP_ACTUAL_REPLACEMENT_SERVICE_ROLE_REQUIRED' IN v_definition)=0 THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_POSTDEPLOY_DEFINITION_FAILED';
  END IF;
  IF EXISTS (
       SELECT 1
       FROM aclexplode(coalesce(v_proc.proacl,acldefault('f',v_proc.proowner))) a
       WHERE a.grantee=0 AND a.privilege_type='EXECUTE'
     )
     OR has_function_privilege('anon',v_proc.oid,'EXECUTE')
     OR has_function_privilege('authenticated',v_proc.oid,'EXECUTE')
     OR NOT has_function_privilege('service_role',v_proc.oid,'EXECUTE') THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_POSTDEPLOY_ACL_FAILED';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM public.school_lesson_records a
       WHERE a.id='d1c60932-0f8a-43e3-98b8-bb362921ccf8'
         AND a.updated_at='2026-08-04 00:19:03.535682+00'::timestamptz
         AND a.planned_lesson_id='d4e3e060-1951-4fdd-9340-e6feb6687b7f'
         AND a.lesson_type='actual' AND a.status='makeup_completed'
         AND a.lesson_date='2026-07-31' AND a.start_time='13:00'
         AND a.end_time='14:00' AND a.duration_hours=1
         AND a.is_billable=false AND a.lesson_fee=0
         AND md5(to_jsonb(a)::text)='77b35e350c60c4ae1dc33b0f45a7656e'
     ) THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_POSTDEPLOY_TARGET_DRIFT';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.school_lesson_records p
       WHERE p.id='d4e3e060-1951-4fdd-9340-e6feb6687b7f'
         AND p.lesson_date='2026-07-20' AND p.duration_hours=2
         AND p.status='pending_makeup'
         AND md5(to_jsonb(p)::text)='349111f8a6818c44a0cf4e1886cda97d'
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.school_lesson_records a
       WHERE a.id='e28d255d-4f6b-45e4-9766-d8d16f97d37b'
         AND a.planned_lesson_id='d4e3e060-1951-4fdd-9340-e6feb6687b7f'
         AND md5(to_jsonb(a)::text)='0813f33689c87d799fe967826e37a8a2'
     )
     OR public.school_get_lesson_credit_remaining_hours(
          'd4e3e060-1951-4fdd-9340-e6feb6687b7f'
        )<>0 THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_POSTDEPLOY_SOURCE_DRIFT';
  END IF;

  IF EXISTS (SELECT 1 FROM public.school_teacher_wage_lock_details
             WHERE lesson_record_id='d1c60932-0f8a-43e3-98b8-bb362921ccf8')
     OR EXISTS (SELECT 1 FROM public.school_student_monthly_settlements
               WHERE student_id='eceb2c59-9689-4ec8-9d3f-799b90bfdb27'
                 AND year_month IN ('2026-07','2026-08'))
     OR EXISTS (SELECT 1 FROM public.school_student_settlement_lesson_variance_claims
               WHERE source_actual_lesson_id='d1c60932-0f8a-43e3-98b8-bb362921ccf8')
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons
               WHERE planned_lesson_id='d1c60932-0f8a-43e3-98b8-bb362921ccf8')
     OR EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence
               WHERE actual_lesson_id='d1c60932-0f8a-43e3-98b8-bb362921ccf8')
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions
               WHERE linked_actual_lesson_id='d1c60932-0f8a-43e3-98b8-bb362921ccf8')
     OR EXISTS (SELECT 1 FROM public.school_business_entity_migration_items
               WHERE lesson_record_id='d1c60932-0f8a-43e3-98b8-bb362921ccf8') THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_POSTDEPLOY_TARGET_CONSUMED';
  END IF;

  IF (SELECT md5(to_jsonb(b)::text) FROM public.school_student_tuition_bills b
      WHERE b.id='7472f73f-fa19-4565-9180-a517c7151835')
       IS DISTINCT FROM 'bfa62da082009fbcef7fa8612152fc0a'
     OR (SELECT md5(to_jsonb(i)::text) FROM public.school_income_records i
         WHERE i.id='3a5542c5-5397-4688-999e-a08bb678f40d')
       IS DISTINCT FROM '9071f5eb1b0ad2c0108b6673e375f751'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons r
         WHERE r.tuition_bill_id='7472f73f-fa19-4565-9180-a517c7151835'
           AND r.planned_lesson_id='d4e3e060-1951-4fdd-9340-e6feb6687b7f')<>1 THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_POSTDEPLOY_PLANNED_FINANCE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='enabled'))<>3 THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_POSTDEPLOY_GATE_DRIFT';
  END IF;
END
$verify$;

SELECT
  md5(pg_get_functiondef(
    'public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)'::regprocedure
  )) AS writer_md5,
  true AS security_definer_safe_path,
  true AS service_role_only,
  true AS production_target_unique_and_unconsumed,
  true AS planned_bill_income_unchanged,
  true AS gates_unchanged;

ROLLBACK;
\echo 'MAKEUP_REPLACEMENT_POSTDEPLOY_READ_ONLY_ROLLED_BACK'
