-- Phase 2C-C-R1 local role/ACL matrix. Read-only RPC calls only; transaction rolls back.
\set ON_ERROR_STOP on
begin;

create function pg_temp.expect_error(p_sql text,p_pattern text)
returns void language plpgsql as $function$
begin
  begin execute p_sql; raise exception 'EXPECTED_ERROR_MISSING:%',p_pattern;
  exception when others then
    if sqlerrm like 'EXPECTED_ERROR_MISSING:%' or position(p_pattern in sqlerrm)=0 then raise; end if;
  end;
end
$function$;

do $acl$
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
      raise exception 'R1 ACL invalid:%',v_signature;
    end if;
  end loop;
end
$acl$;

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select (public.school_preview_lesson_clearance_v2(
  'ab000000-0000-4000-8000-000000000001','overtime_offset',
  '30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000101',
  30,'2026-02-10','manual_choice','role matrix','admin role',null
)->'authorization'->>'can_execute_for_current_actor')::boolean admin_can_execute \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000002',true);
select (public.school_preview_lesson_clearance_v2(
  'ab000000-0000-4000-8000-000000000002','overtime_offset',
  '30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000101',
  30,'2026-02-10','manual_choice','role matrix','operator role',null
)->'authorization'->>'can_execute_for_current_actor')::boolean operator_can_execute \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000003',true);
select not (public.school_preview_lesson_clearance_v2(
  'ab000000-0000-4000-8000-000000000003','overtime_offset',
  '30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000101',
  30,'2026-02-10','manual_choice','role matrix','readonly role',null
)->'authorization'->>'can_execute_for_current_actor')::boolean readonly_blocked \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000004',true);
select pg_temp.expect_error($sql$
  select public.school_list_lesson_clearance_history_v2(null)$sql$,
  'LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000099',true);
select pg_temp.expect_error($sql$
  select public.school_list_lesson_clearance_history_v2(null)$sql$,
  'LESSON_CLEARANCE_MEMBERSHIP_REQUIRED');
reset role;

select 1 / case when :'admin_can_execute'::boolean
  and :'operator_can_execute'::boolean and :'readonly_blocked'::boolean
  then 1 else 0 end role_matrix_assertion;

select 'PHASE2C_C_R1_ROLE_MATRIX_PASS' result;
rollback;
