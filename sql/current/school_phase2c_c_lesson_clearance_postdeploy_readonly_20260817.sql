-- School V2 Phase 2C-C postdeploy read-only acceptance.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

do $catalog_contract$
declare
  v_table text;
  v_signature regprocedure;
begin
  foreach v_table in array array[
    'school_lesson_clearances','school_lesson_clearance_details'
  ] loop
    if to_regclass('public.'||v_table) is null then
      raise exception 'PHASE2C_C_TABLE_MISSING:%',v_table;
    end if;
    if (select pg_get_userbyid(relowner)<>'postgres' or not relrowsecurity
        from pg_class where oid=to_regclass('public.'||v_table)) then
      raise exception 'PHASE2C_C_TABLE_OWNER_OR_RLS_INVALID:%',v_table;
    end if;
    if has_table_privilege('anon','public.'||v_table,'SELECT,INSERT,UPDATE,DELETE')
       or has_table_privilege('authenticated','public.'||v_table,'SELECT,INSERT,UPDATE,DELETE')
       or has_table_privilege('service_role','public.'||v_table,'SELECT,INSERT,UPDATE,DELETE') then
      raise exception 'PHASE2C_C_APPLICATION_TABLE_PRIVILEGE_PRESENT:%',v_table;
    end if;
  end loop;
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_C_PRODUCTION_CLEARANCE_FACT_NOT_ZERO';
  end if;
  foreach v_signature in array array[
    'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure,
    'public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure
  ] loop
    if not has_function_privilege('authenticated',v_signature,'EXECUTE')
       or has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'PHASE2C_C_WRITER_ACL_INVALID:%',v_signature;
    end if;
  end loop;
  foreach v_signature in array array[
    'public.school_suggest_lesson_clearance_targets(uuid)'::regprocedure,
    'public.school_list_lesson_clearance_pending_balances(uuid,boolean)'::regprocedure,
    'public.school_list_lesson_clearance_available_overages(uuid,boolean)'::regprocedure,
    'public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text)'::regprocedure,
    'public.school_list_lesson_clearance_history(uuid)'::regprocedure,
    'public.school_list_lesson_clearance_forward_manifest(uuid,uuid,text)'::regprocedure,
    'public.school_list_cross_month_makeup_projection(uuid,text)'::regprocedure
  ] loop
    if not has_function_privilege('authenticated',v_signature,'EXECUTE')
       or has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'PHASE2C_C_READER_ACL_INVALID:%',v_signature;
    end if;
  end loop;
  foreach v_signature in array array[
    'public.school_create_lesson_clearance_core(text,uuid,uuid,integer,date,text,text,text,text,text,uuid,text)'::regprocedure,
    'public.school_reverse_lesson_clearance_core(uuid,date,text,text,uuid,text)'::regprocedure,
    'public.school_assert_lesson_clearance_actor()'::regprocedure,
    'public.school_assert_lesson_clearance_reader()'::regprocedure,
    'public.school_suggest_lesson_clearance_targets_core(uuid)'::regprocedure,
    'public.school_get_lesson_clearance_allocated_minutes(uuid)'::regprocedure,
    'public.school_get_lesson_clearance_overtime_allocated_minutes(uuid)'::regprocedure,
    'public.school_get_lesson_clearance_pending_remaining_minutes(uuid)'::regprocedure,
    'public.school_get_lesson_clearance_overtime_remaining_minutes(uuid)'::regprocedure,
    'public.school_get_lesson_clearance_source_manifest(uuid,uuid)'::regprocedure
  ] loop
    if has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('authenticated',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'PHASE2C_C_INTERNAL_FUNCTION_EXPOSED:%',v_signature;
    end if;
  end loop;
  if not exists(select 1 from public.school_student_package_credit_lots
    where id='2a000000-0000-4000-8000-202608170002'
      and initial_minutes=1200 and consumed_minutes=0 and remaining_minutes=1200
      and status='active') then
    raise exception 'PHASE2C_C_P002_REGRESSION';
  end if;
  if exists(select 1 from pg_proc p
    where p.pronamespace='public'::regnamespace
      and p.proname~'package.*(consume|reserve)|(consume|reserve).*package'
      and (has_function_privilege('authenticated',p.oid,'EXECUTE')
        or has_function_privilege('service_role',p.oid,'EXECUTE'))) then
    raise exception 'PHASE2C_C_PACKAGE_CONSUMPTION_ENTRY_PRESENT';
  end if;
end
$catalog_contract$;

select p.oid::regprocedure signature,pg_get_userbyid(p.proowner) owner,
  p.prosecdef security_definer,p.proconfig function_config,p.proacl acl,
  md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p
where p.pronamespace='public'::regnamespace
  and (p.proname like 'school%lesson_clearance%'
    or p.oid in (
      'public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure,
      'public.school_get_lesson_credit_remaining_hours(uuid)'::regprocedure,
      'public.school_list_student_lesson_credit_balances(uuid)'::regprocedure,
      'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure,
      'public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure
    ))
order by 1;

select 'school_lesson_clearances' object_name,count(*) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id),'')) row_hash
from public.school_lesson_clearances row_value
union all
select 'school_lesson_clearance_details',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id),''))
from public.school_lesson_clearance_details row_value
union all
select 'school_student_package_credit_lots',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id),''))
from public.school_student_package_credit_lots row_value;

rollback;
