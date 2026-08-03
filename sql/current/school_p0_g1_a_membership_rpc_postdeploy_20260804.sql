-- P0-G1-A membership RPC read-only postdeploy verification.
\set ON_ERROR_STOP on
\pset pager off

do $verify$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.school_get_current_app_membership()',
    'public.school_require_current_app_admin()',
    'public.school_admin_set_app_membership(uuid,text,boolean,text)'
  ] loop
    if not exists (
      select 1
      from pg_proc p
      where p.oid=v_signature::regprocedure
        and p.prosecdef
        and p.proconfig @> array['search_path=pg_catalog, public']
    ) then
      raise exception 'P0G1_RPC_SECURITY_CONTRACT_INVALID: %',v_signature;
    end if;
  end loop;

  if has_function_privilege('anon','public.school_get_current_app_membership()','EXECUTE')
     or not has_function_privilege('authenticated','public.school_get_current_app_membership()','EXECUTE')
     or has_function_privilege('service_role','public.school_get_current_app_membership()','EXECUTE')
     or has_function_privilege('anon','public.school_require_current_app_admin()','EXECUTE')
     or has_function_privilege('authenticated','public.school_require_current_app_admin()','EXECUTE')
     or has_function_privilege('service_role','public.school_require_current_app_admin()','EXECUTE')
     or has_function_privilege('anon','public.school_admin_set_app_membership(uuid,text,boolean,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.school_admin_set_app_membership(uuid,text,boolean,text)','EXECUTE')
     or has_function_privilege('service_role','public.school_admin_set_app_membership(uuid,text,boolean,text)','EXECUTE') then
    raise exception 'P0G1_RPC_ACL_INVALID';
  end if;

  if has_table_privilege('anon','public.school_app_memberships','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated','public.school_app_memberships','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','public.school_app_memberships','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'P0G1_MEMBERSHIP_TABLE_ACL_INVALID';
  end if;
end;
$verify$;

select p.oid::regprocedure signature,p.prosecdef,p.proconfig,
  coalesce(array_to_string(p.proacl,','),'NULL_DEFAULT_ACL') acl
from pg_proc p
where p.oid in (
  'public.school_get_current_app_membership()'::regprocedure,
  'public.school_require_current_app_admin()'::regprocedure,
  'public.school_admin_set_app_membership(uuid,text,boolean,text)'::regprocedure
)
order by p.oid::regprocedure::text;

select 'P0G1_MEMBERSHIP_RPC_POSTDEPLOY_PASS' result;
