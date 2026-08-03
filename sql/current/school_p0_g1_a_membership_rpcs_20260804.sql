-- School V2 P0-G1-A membership authority RPCs.
\set ON_ERROR_STOP on
\pset pager off

begin;

create function public.school_get_current_app_membership()
returns table (
  user_id uuid,
  role text,
  is_active boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select m.user_id,m.role,m.is_active
  from public.school_app_memberships m
  where m.user_id=auth.uid();
$function$;

create function public.school_require_current_app_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception using
      errcode='42501',
      message='P0G1_AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.school_app_memberships m
    where m.user_id=v_actor
      and m.is_active
      and m.role='admin'
  ) then
    raise exception using
      errcode='42501',
      message='P0G1_ACTIVE_ADMIN_REQUIRED';
  end if;

  return v_actor;
end;
$function$;

create function public.school_admin_set_app_membership(
  p_user_id uuid,
  p_role text,
  p_is_active boolean,
  p_note text
)
returns table (
  user_id uuid,
  role text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  created_by_user_id uuid,
  updated_by_user_id uuid,
  note text
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid;
  v_now timestamptz := clock_timestamp();
begin
  v_actor := public.school_require_current_app_admin();

  if p_user_id is null or p_role is null or p_is_active is null then
    raise exception using
      errcode='22023',
      message='P0G1_MEMBERSHIP_INPUT_REQUIRED';
  end if;
  if p_role not in ('admin','operator','read_only') then
    raise exception using
      errcode='22023',
      message='P0G1_MEMBERSHIP_ROLE_INVALID';
  end if;
  if not exists (select 1 from auth.users u where u.id=p_user_id) then
    raise exception using
      errcode='22023',
      message='P0G1_AUTH_USER_NOT_FOUND';
  end if;

  lock table public.school_app_memberships in share row exclusive mode;

  insert into public.school_app_memberships (
    user_id,role,is_active,created_at,updated_at,
    created_by_user_id,updated_by_user_id,note
  ) values (
    p_user_id,p_role,p_is_active,v_now,v_now,
    v_actor,v_actor,p_note
  )
  on conflict on constraint school_app_memberships_pkey do update
  set role=excluded.role,
      is_active=excluded.is_active,
      updated_at=v_now,
      updated_by_user_id=v_actor,
      note=excluded.note;

  if not exists (
    select 1 from public.school_app_memberships m
    where m.is_active and m.role='admin'
  ) then
    raise exception using
      errcode='23514',
      message='P0G1_LAST_ACTIVE_ADMIN_REQUIRED';
  end if;

  return query
  select m.user_id,m.role,m.is_active,m.created_at,m.updated_at,
         m.created_by_user_id,m.updated_by_user_id,m.note
  from public.school_app_memberships m
  where m.user_id=p_user_id;
end;
$function$;

revoke all on function public.school_get_current_app_membership()
  from public,anon,authenticated,service_role;
grant execute on function public.school_get_current_app_membership()
  to authenticated;

revoke all on function public.school_require_current_app_admin()
  from public,anon,authenticated,service_role;

revoke all on function public.school_admin_set_app_membership(uuid,text,boolean,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_admin_set_app_membership(uuid,text,boolean,text)
  to authenticated;

comment on function public.school_get_current_app_membership() is
  'Returns only the current auth.uid membership; never accepts email or caller-supplied user identity.';
comment on function public.school_require_current_app_admin() is
  'Owner-only P0-G1 admin assertion requiring auth.uid active admin membership.';
comment on function public.school_admin_set_app_membership(uuid,text,boolean,text) is
  'Controlled post-bootstrap membership maintenance; actor is always auth.uid and updated_at is DB authoritative.';

commit;
