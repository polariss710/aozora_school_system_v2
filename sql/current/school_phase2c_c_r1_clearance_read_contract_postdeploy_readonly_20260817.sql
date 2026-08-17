-- Phase 2C-C-R1 postdeploy catalog and zero-write acceptance.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

do $contract$
declare v_signature regprocedure;
begin
  foreach v_signature in array array[
    'public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)'::regprocedure,
    'public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)'::regprocedure,
    'public.school_list_lesson_clearance_history_v2(uuid)'::regprocedure
  ] loop
    if not has_function_privilege('authenticated',v_signature,'EXECUTE')
       or has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'PHASE2C_C_R1_ACL_INVALID:%',v_signature;
    end if;
    if exists(select 1 from pg_proc p where p.oid=v_signature
      and (pg_get_userbyid(p.proowner)<>'postgres' or not p.prosecdef
        or p.proconfig is distinct from array['search_path=pg_catalog, public'])) then
      raise exception 'PHASE2C_C_R1_FUNCTION_SECURITY_INVALID:%',v_signature;
    end if;
  end loop;
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_C_R1_CLEARANCE_ROWS_NOT_ZERO';
  end if;
end
$contract$;

select p.oid::regprocedure signature,pg_get_userbyid(p.proowner) owner,
  p.prosecdef security_definer,p.proconfig function_config,p.proacl acl,
  md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p
where p.oid in (
  'public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)'::regprocedure,
  'public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)'::regprocedure,
  'public.school_list_lesson_clearance_history_v2(uuid)'::regprocedure
)
order by p.oid::regprocedure::text;

select count(*) clearance_count from public.school_lesson_clearances;
select count(*) clearance_detail_count from public.school_lesson_clearance_details;
select count(*) package_count,
  min(initial_minutes) filter(where id='2a000000-0000-4000-8000-202608170002') p002_initial,
  min(consumed_minutes) filter(where id='2a000000-0000-4000-8000-202608170002') p002_consumed,
  min(remaining_minutes) filter(where id='2a000000-0000-4000-8000-202608170002') p002_remaining
from public.school_student_package_credit_lots;

rollback;
