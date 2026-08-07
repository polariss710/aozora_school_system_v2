\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_status_phase_b4_remaining_current_month_reader_core_20260807.sql

do $acl_test$
declare
  v_oid oid := 'public.school_list_current_student_month_candidates_v1(boolean,uuid)'::regprocedure::oid;
begin
  if not (select p.prosecdef and p.provolatile = 's' and p.proconfig = '{"search_path=pg_catalog, public"}'::text[]
          from pg_proc p where p.oid = v_oid)
     or pg_get_userbyid((select p.proowner from pg_proc p where p.oid = v_oid)) <> 'postgres'
     or has_function_privilege('anon', v_oid, 'EXECUTE')
     or not has_function_privilege('authenticated', v_oid, 'EXECUTE')
     or has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'B4_REMAINING_CURRENT_MONTH_READER_ACL_INVALID';
  end if;

end;
$acl_test$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',
  true
);

do $candidate_test$
declare
  v_target_month date := date_trunc('month', statement_timestamp() at time zone 'Asia/Tokyo')::date;
  v_direct_count integer;
  v_wrapper_count integer;
begin
  select count(*) into v_direct_count
  from public.school_list_student_month_candidates_v1(v_target_month, true, null);
  select count(*) into v_wrapper_count
  from public.school_list_current_student_month_candidates_v1(true, null)
  where target_month = v_target_month;

  if v_wrapper_count <> v_direct_count or v_wrapper_count <> 8 then
    raise exception 'B4_REMAINING_CURRENT_MONTH_READER_PARITY_INVALID:%/%', v_wrapper_count, v_direct_count;
  end if;

  if (select count(*) from public.school_list_current_student_month_candidates_v1(false, null)
      where resolved_status = 'active') <> 7
     or exists (select 1 from public.school_list_current_student_month_candidates_v1(false, null)
                where resolved_status <> 'active')
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
    raise exception 'B4_REMAINING_CURRENT_MONTH_READER_CANDIDATE_INVALID';
  end if;
end;
$candidate_test$;

rollback;
select 'STUDENT_STATUS_PHASE_B4_REMAINING_CURRENT_MONTH_READER_ROLLBACK_TEST_PASS' result;
