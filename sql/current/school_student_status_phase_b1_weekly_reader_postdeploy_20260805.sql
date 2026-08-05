-- Phase B1 read-only postdeploy verification.
\set ON_ERROR_STOP on
\pset pager off

do $phase_b1_postdeploy$
declare
  v_proc record;
  v_definition text;
  v_result text;
  v_comment text;
begin
  select p.*, r.rolname owner_name
  into v_proc
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_roles r on r.oid = p.proowner
  where n.nspname = 'public'
    and p.oid = 'public.school_get_weekly_lesson_operations(date)'::regprocedure;

  if not found then
    raise exception 'PHASE_B1_FUNCTION_MISSING';
  end if;

  v_definition := pg_get_functiondef(v_proc.oid);
  v_result := pg_get_function_result(v_proc.oid);
  select obj_description(v_proc.oid, 'pg_proc') into v_comment;

  if pg_get_function_identity_arguments(v_proc.oid) <> 'p_week_start date'
     or v_result <> 'TABLE(student_id uuid, business_entity_id uuid, weekly_planned_count bigint, weekly_planned_hours numeric, weekly_registered_count bigint, weekly_completed_hours numeric, weekly_cancelled_count bigint, overdue_unregistered_count bigint, upcoming_unregistered_count bigint, open_credit_source_count bigint, open_credit_hours numeric, oldest_credit_date date)'
     or v_proc.owner_name <> 'postgres'
     or v_proc.prosecdef
     or v_proc.provolatile <> 's'
     or v_proc.proparallel <> 'u'
     or v_proc.proleakproof
     or v_proc.proconfig is distinct from array['search_path=public']::text[] then
    raise exception 'PHASE_B1_FUNCTION_ABI_OR_ATTRIBUTE_CHANGED';
  end if;

  if v_definition !~* 'school_students as'
     or v_definition ~* 'active_students'
     or v_definition ~* 'coalesce\(s\.status[^\n]*active'
     or v_definition ~* 'school_resolve_student_status|school_list_student_(month|range)_candidates' then
    raise exception 'PHASE_B1_FUNCTION_STATUS_FILTER_OR_RESOLVER_REGRESSION';
  end if;

  if v_comment <> 'Returns school-student weekly planned/registration operations and all open lesson-credit balances for the Monday-starting week. Student status never filters historical business facts. All counts and hours are DB-derived; this function writes no business rows.' then
    raise exception 'PHASE_B1_FUNCTION_COMMENT_MISMATCH';
  end if;

  if not has_function_privilege('postgres', v_proc.oid, 'EXECUTE')
     or not has_function_privilege('anon', v_proc.oid, 'EXECUTE')
     or not has_function_privilege('authenticated', v_proc.oid, 'EXECUTE')
     or not has_function_privilege('service_role', v_proc.oid, 'EXECUTE') then
    raise exception 'PHASE_B1_FUNCTION_EXECUTE_ACL_CHANGED';
  end if;

  if (select count(*) from public.school_students) <> 8
     or (select count(*) from public.school_student_status_events) <> 1 then
    raise exception 'PHASE_B1_STUDENT_OR_EVENT_COUNT_CHANGED';
  end if;

  if exists (
    select 1
    from public.school_feature_gates
    where (feature_key = 'student_tuition_preview' and state <> 'enabled')
       or (feature_key = 'student_tuition_generate' and state <> 'blocked')
       or (feature_key = 'student_tuition_cash_submit' and state <> 'enabled')
  ) then
    raise exception 'PHASE_B1_GATE_CHANGED';
  end if;

  if exists (select 1 from public.school_students where id::text like 'b1010000-%')
     or exists (select 1 from public.school_lesson_records where id::text like 'b1020000-%' or id::text like 'b1030000-%')
     or exists (select 1 from public.school_student_status_events where id::text like 'b1040000-%') then
    raise exception 'PHASE_B1_FIXTURE_RESIDUE';
  end if;
end;
$phase_b1_postdeploy$;

select p.oid::regprocedure signature,
       pg_get_function_result(p.oid) return_type,
       r.rolname owner_name,
       p.prosecdef security_definer,
       p.provolatile volatility,
       p.proparallel parallel_safety,
       p.proleakproof leakproof,
       p.proconfig,
       p.proacl,
       md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_roles r on r.oid = p.proowner
where n.nspname = 'public'
  and p.oid = 'public.school_get_weekly_lesson_operations(date)'::regprocedure;

select 'STUDENT_STATUS_PHASE_B1_WEEKLY_READER_POSTDEPLOY_PASS' result;
