-- P0-G1-B1 read-only authority verification. expected_cash_gate_state is blocked/enabled.
\set ON_ERROR_STOP on
\pset pager off

\if :{?expected_cash_gate_state}
\else
  \echo 'EXPECTED_CASH_GATE_STATE_REQUIRED'
  \quit
\endif

begin read only;

select (
  :'expected_cash_gate_state' in ('blocked','enabled')
  and (select state from public.school_feature_gates
       where feature_key='student_tuition_cash_submit')=:'expected_cash_gate_state'
  and (select state from public.school_feature_gates
       where feature_key='student_tuition_generate')='blocked'
  and (select state from public.school_feature_gates
       where feature_key='student_tuition_preview')='enabled'
)::int as p0g1b1_gate_state_ok \gset
\if :p0g1b1_gate_state_ok
\else
  \echo 'P0G1B1_GATE_STATE_INVALID'
  \quit
\endif

do $verify$
begin
  if has_function_privilege('anon','public.school_require_current_app_admin()','EXECUTE')
     or not has_function_privilege('authenticated','public.school_require_current_app_admin()','EXECUTE')
     or has_function_privilege('service_role','public.school_require_current_app_admin()','EXECUTE') then
    raise exception 'P0G1B1_ADMIN_ASSERTION_ACL_INVALID';
  end if;
  if has_function_privilege('anon','public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','EXECUTE')
     or not has_function_privilege('service_role','public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','EXECUTE')
     or has_function_privilege('anon','public.school_mark_cash_income_request_submitted(uuid,uuid,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_mark_cash_income_request_submitted(uuid,uuid,text)','EXECUTE')
     or not has_function_privilege('service_role','public.school_mark_cash_income_request_submitted(uuid,uuid,text)','EXECUTE') then
    raise exception 'P0G1B1_SCHOOL_WRITER_ACL_INVALID';
  end if;
  if has_table_privilege('anon','public.school_app_memberships','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated','public.school_app_memberships','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','public.school_app_memberships','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'P0G1B1_MEMBERSHIP_TABLE_ACL_INVALID';
  end if;
end;
$verify$;

select p.oid::regprocedure signature,p.prosecdef,p.provolatile,p.proconfig,
       coalesce(array_to_string(p.proacl,','),'NULL_DEFAULT_ACL') acl
from pg_proc p
where p.oid in (
  'public.school_require_current_app_admin()'::regprocedure,
  'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)'::regprocedure,
  'public.school_mark_cash_income_request_submitted(uuid,uuid,text)'::regprocedure
)
order by p.oid::regprocedure::text;

select 'P0G1B1_ADMIN_CASH_AUTHORITY_POSTDEPLOY_PASS' result;
rollback;
