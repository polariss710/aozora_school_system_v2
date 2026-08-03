-- P0-G1-B1 user-scoped active-admin assertion reachability.
-- This changes only the assertion helper ACL. School/Cash business writers stay
-- service-role-only, and membership table DML remains owner-only.
\set ON_ERROR_STOP on
\pset pager off

begin;

do $verify$
begin
  if to_regprocedure('public.school_require_current_app_admin()') is null then
    raise exception 'P0G1B1_ADMIN_ASSERTION_HELPER_MISSING';
  end if;
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    join pg_roles r on r.oid=p.proowner
    where p.oid='public.school_require_current_app_admin()'::regprocedure
      and n.nspname='public'
      and r.rolname='postgres'
      and p.prosecdef
      and p.provolatile='s'
      and p.proconfig @> array['search_path=pg_catalog, public']
  ) then
    raise exception 'P0G1B1_ADMIN_ASSERTION_HELPER_CONTRACT_DRIFT';
  end if;
end;
$verify$;

revoke all on function public.school_require_current_app_admin()
  from public,anon,authenticated,service_role;
grant execute on function public.school_require_current_app_admin()
  to authenticated;

comment on function public.school_require_current_app_admin() is
  'P0-G1 active-admin assertion for the current authenticated auth.uid; callable only by authenticated user-scoped School clients.';

commit;
