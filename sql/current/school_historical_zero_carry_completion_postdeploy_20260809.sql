-- Read-only postdeploy for historical zero-carry completion and wage resolver.
\set ON_ERROR_STOP on
\pset pager off

do $checks$
declare
  v_table regclass;
  v_function regprocedure;
begin
  v_table := to_regclass('public.school_student_monthly_settlement_historical_completion_evidence');
  if v_table is null then raise exception 'HISTORICAL_ZERO_CARRY_TABLE_MISSING'; end if;
  if (select count(*) from pg_attribute
      where attrelid=v_table and attnum > 0 and not attisdropped) <> 28 then
    raise exception 'HISTORICAL_ZERO_CARRY_COLUMN_SET_MISMATCH';
  end if;
  if not exists(select 1 from pg_constraint where conrelid=v_table and conname='school_historical_zero_carry_scope_uniq')
     or not exists(select 1 from pg_constraint where conrelid=v_table and conname='school_historical_zero_carry_idempotency_uniq')
     or not exists(select 1 from pg_trigger where tgrelid=v_table and tgname='school_historical_zero_carry_evidence_immutable' and not tgisinternal) then
    raise exception 'HISTORICAL_ZERO_CARRY_CONSTRAINT_OR_TRIGGER_MISSING';
  end if;
  if exists (
    select 1 from (values('public'),('anon'),('authenticated'),('service_role')) role_name(role_name)
    where has_table_privilege(role_name,'public.school_student_monthly_settlement_historical_completion_evidence','INSERT')
       or has_table_privilege(role_name,'public.school_student_monthly_settlement_historical_completion_evidence','UPDATE')
       or has_table_privilege(role_name,'public.school_student_monthly_settlement_historical_completion_evidence','DELETE')
  ) then raise exception 'HISTORICAL_ZERO_CARRY_TABLE_DML_EXPOSED'; end if;

  foreach v_function in array array[
    'public.school_create_student_monthly_settlement_historical_completion_evidence_core(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)'::regprocedure,
    'public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)'::regprocedure,
    'public.school_resolve_student_monthly_settlement_effective_state(uuid,text,uuid)'::regprocedure,
    'public.school_get_teacher_monthly_wage_generation_candidate_facts(text,uuid,uuid)'::regprocedure,
    'public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)'::regprocedure,
    'public.school_generate_teacher_monthly_wage(text,uuid,uuid)'::regprocedure,
    'public.school_generate_teacher_monthly_wage(text,uuid)'::regprocedure
  ] loop
    if not exists(select 1 from pg_proc p where p.oid=v_function and p.prosecdef and p.proconfig @> array['search_path=pg_catalog, public']) then
      raise exception 'HISTORICAL_ZERO_CARRY_FUNCTION_SECURITY_MISMATCH: %',v_function;
    end if;
  end loop;

  if has_function_privilege('service_role','public.school_create_student_monthly_settlement_historical_completion_evidence_core(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
     or has_function_privilege('anon','public.school_create_student_monthly_settlement_historical_completion_evidence_core(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_create_student_monthly_settlement_historical_completion_evidence_core(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
     or not has_function_privilege('service_role','public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
     or has_function_privilege('anon','public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE') then
    raise exception 'HISTORICAL_ZERO_CARRY_WRITER_ACL_MISMATCH';
  end if;

  if not has_function_privilege('authenticated','public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)','EXECUTE')
     or has_function_privilege('anon','public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.school_generate_teacher_monthly_wage(text,uuid,uuid)','EXECUTE')
     or has_function_privilege('service_role','public.school_generate_teacher_monthly_wage(text,uuid,uuid)','EXECUTE') then
    raise exception 'WAGE_PREFLIGHT_OR_WRITER_ACL_MISMATCH';
  end if;

  if exists (
    select 1 from public.school_student_monthly_settlement_historical_completion_evidence e
    where not (
      e.settlement_month='2026-07'
      and e.business_entity_id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
      and e.student_id in (
        'eceb2c59-9689-4ec8-9d3f-799b90bfdb27',
        '881dd60c-b92b-44ae-98e1-98448567a8d2',
        'a7b163a0-201e-4867-9b94-372343356a80',
        '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'
      )
    )
  ) then raise exception 'HISTORICAL_ZERO_CARRY_UNAPPROVED_SCOPE_PRESENT'; end if;
  if (select count(*) from public.school_student_monthly_settlement_historical_completion_evidence) > 4 then
    raise exception 'HISTORICAL_ZERO_CARRY_TOO_MANY_ROWS';
  end if;

  if (select count(*) from public.school_feature_gates where
        (feature_key='student_tuition_preview' and state='enabled') or
        (feature_key='student_tuition_generate' and state='blocked') or
        (feature_key='student_tuition_cash_submit' and state='enabled')) <> 3 then
    raise exception 'HISTORICAL_ZERO_CARRY_GATE_DRIFT';
  end if;
end
$checks$;

select id,student_id,settlement_month,business_entity_id,final_carry_cny,
  lesson_count,lesson_manifest_sha256,makeup_source_count,makeup_remaining_hours,
  makeup_manifest_sha256,active_revision_id,tuition_bill_id,income_record_id,
  cash_linkage_event_id,cash_request_id,cash_transaction_id,
  evidence_manifest_sha256,payload_sha256,created_by_actor_id,created_at
from public.school_student_monthly_settlement_historical_completion_evidence
order by student_id;

select 'HISTORICAL_ZERO_CARRY_POSTDEPLOY_PASS' result;
