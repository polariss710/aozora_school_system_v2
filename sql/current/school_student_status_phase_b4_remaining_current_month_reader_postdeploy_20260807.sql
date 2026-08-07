\set ON_ERROR_STOP on
\pset pager off

begin read only;

do $acl_postdeploy$
declare
  v_oid oid := 'public.school_list_current_student_month_candidates_v1(boolean,uuid)'::regprocedure::oid;
begin
  if not (select p.prosecdef and p.provolatile = 's' and p.proconfig = '{"search_path=pg_catalog, public"}'::text[]
          from pg_proc p where p.oid = v_oid)
     or pg_get_userbyid((select p.proowner from pg_proc p where p.oid = v_oid)) <> 'postgres'
     or has_function_privilege('anon', v_oid, 'EXECUTE')
     or not has_function_privilege('authenticated', v_oid, 'EXECUTE')
     or has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'B4_REMAINING_CURRENT_MONTH_READER_POSTDEPLOY_ACL_INVALID';
  end if;

end;
$acl_postdeploy$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',
  true
);

do $candidate_postdeploy$
begin
  if (select count(*) from public.school_list_current_student_month_candidates_v1(false, null)) <> 7
     or (select count(*) from public.school_list_current_student_month_candidates_v1(true, null)) <> 8
     or not exists (
       select 1
       from public.school_list_current_student_month_candidates_v1(
         false,
         'cff85c52-6acc-4b0f-8c92-3db280a5dd77'
       )
       where student_id = 'cff85c52-6acc-4b0f-8c92-3db280a5dd77'
         and resolved_status = 'paused'
         and is_selected_override
     ) then
    raise exception 'B4_REMAINING_CURRENT_MONTH_READER_POSTDEPLOY_CANDIDATE_INVALID';
  end if;
end;
$candidate_postdeploy$;

rollback;
select 'STUDENT_STATUS_PHASE_B4_REMAINING_CURRENT_MONTH_READER_POSTDEPLOY_PASS' result;
