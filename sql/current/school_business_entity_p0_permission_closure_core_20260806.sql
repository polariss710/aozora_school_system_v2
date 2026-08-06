-- School V2 Phase BE-P0 business-entity permission closure core, 2026-08-06.
-- ACL/RLS/function-definition changes only; never writes business-entity rows.

do $preflight$
begin
  if to_regclass('public.school_business_entities') is null
     or to_regclass('public.school_app_memberships') is null
     or to_regprocedure('public.school_get_current_app_membership()') is null
     or to_regprocedure('public.school_require_current_app_admin()') is null then
    raise exception 'BE_P0_AUTHORITY_PREFLIGHT_FAILED';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname='school_create_business_entity_profile'
  ) <> 2 then
    raise exception 'BE_P0_CREATE_OVERLOAD_DRIFT';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname='school_update_business_entity_profile'
  ) <> 2 then
    raise exception 'BE_P0_UPDATE_OVERLOAD_DRIFT';
  end if;

  if not exists (
    select 1
    from pg_proc p
    where p.oid='public.school_get_current_app_membership()'::regprocedure
      and p.prosecdef
      and p.proconfig='{"search_path=pg_catalog, public"}'::text[]
  ) or not exists (
    select 1
    from pg_proc p
    where p.oid='public.school_require_current_app_admin()'::regprocedure
      and p.prosecdef
      and p.proconfig='{"search_path=pg_catalog, public"}'::text[]
  ) then
    raise exception 'BE_P0_MEMBERSHIP_HELPER_DRIFT';
  end if;
end;
$preflight$;

\ir school_create_business_entity_profile_rpc.sql
\ir school_update_business_entity_profile_rpc.sql

alter table public.school_business_entities enable row level security;

drop policy if exists school_allow_all_business_entities
  on public.school_business_entities;
drop policy if exists school_business_entities_active_membership_select
  on public.school_business_entities;
create policy school_business_entities_active_membership_select
  on public.school_business_entities
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.school_get_current_app_membership() membership
      where membership.is_active
        and membership.role in ('admin','operator','read_only')
    )
  );

revoke all privileges on table public.school_business_entities
  from public,anon,authenticated,service_role;
grant select on table public.school_business_entities to authenticated;

revoke all on function public.school_create_business_entity_profile(
  text,text,text,text,boolean,text
) from public,anon,authenticated,service_role;
revoke all on function public.school_create_business_entity_profile(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.school_create_business_entity_profile(jsonb)
  to authenticated;

revoke all on function public.school_update_business_entity_profile(
  uuid,text,text,text,boolean,text
) from public,anon,authenticated,service_role;
revoke all on function public.school_update_business_entity_profile(uuid,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.school_update_business_entity_profile(uuid,jsonb)
  to authenticated;

comment on policy school_business_entities_active_membership_select
  on public.school_business_entities is
  'Business-entity names are readable only by authenticated users with a current active admin, operator, or read_only membership.';
comment on function public.school_create_business_entity_profile(jsonb) is
  'Interactive business-entity create writer. Authenticated callers must be current active admins; direct anon and service-role use is denied.';
comment on function public.school_update_business_entity_profile(uuid,jsonb) is
  'Interactive business-entity update writer. Authenticated callers must be current active admins; direct anon and service-role use is denied.';
