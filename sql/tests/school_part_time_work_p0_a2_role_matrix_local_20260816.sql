-- Disposable local PostgreSQL role-matrix test for PTW-P0-A2 guards.
-- Never execute against production; creates only synthetic local fixture rows and rolls back.
\set ON_ERROR_STOP on
\pset pager off

begin;

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create schema auth;
create function auth.uid() returns uuid language sql stable as $function$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$function$;

create table public.school_app_memberships (
  user_id uuid primary key,
  role text not null,
  is_active boolean not null
);

create function public.school_require_current_part_time_work_operator()
returns uuid language plpgsql stable security definer
set search_path=pg_catalog,public as $function$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_active boolean;
begin
  if v_actor is null then
    raise exception using errcode='42501',message='PTW_WRITER_AUTH_REQUIRED';
  end if;
  select m.role,m.is_active into v_role,v_active
  from public.school_app_memberships m where m.user_id=v_actor;
  if not found then
    raise exception using errcode='42501',message='PTW_WRITER_MEMBERSHIP_REQUIRED';
  end if;
  if v_active is distinct from true then
    raise exception using errcode='42501',message='PTW_WRITER_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_role not in ('admin','operator') then
    raise exception using errcode='42501',message='PTW_WRITER_OPERATOR_ROLE_REQUIRED';
  end if;
  return v_actor;
end
$function$;

create function public.school_require_current_part_time_work_admin()
returns uuid language plpgsql stable security definer
set search_path=pg_catalog,public as $function$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_active boolean;
begin
  if v_actor is null then
    raise exception using errcode='42501',message='PTW_WRITER_AUTH_REQUIRED';
  end if;
  select m.role,m.is_active into v_role,v_active
  from public.school_app_memberships m where m.user_id=v_actor;
  if not found then
    raise exception using errcode='42501',message='PTW_WRITER_MEMBERSHIP_REQUIRED';
  end if;
  if v_active is distinct from true then
    raise exception using errcode='42501',message='PTW_WRITER_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_role is distinct from 'admin' then
    raise exception using errcode='42501',message='PTW_WRITER_ADMIN_ROLE_REQUIRED';
  end if;
  return v_actor;
end
$function$;

create function public.ptw_p0_a2_operator_writer_fixture()
returns uuid language sql security definer
set search_path=pg_catalog,public as $function$
  select public.school_require_current_part_time_work_operator()
$function$;

create function public.ptw_p0_a2_admin_writer_fixture()
returns uuid language sql security definer
set search_path=pg_catalog,public as $function$
  select public.school_require_current_part_time_work_admin()
$function$;

create function public.ptw_p0_a2_retired_writer_fixture()
returns void language sql security definer
set search_path=pg_catalog,public as $function$
  select
$function$;

create function public.ptw_p0_a2_import_writer_fixture()
returns void language sql security definer
set search_path=pg_catalog,public as $function$
  select
$function$;

revoke all on function public.ptw_p0_a2_operator_writer_fixture() from public,anon,authenticated,service_role;
grant execute on function public.ptw_p0_a2_operator_writer_fixture() to authenticated;
revoke all on function public.ptw_p0_a2_admin_writer_fixture() from public,anon,authenticated,service_role;
grant execute on function public.ptw_p0_a2_admin_writer_fixture() to authenticated;
revoke all on function public.ptw_p0_a2_retired_writer_fixture() from public,anon,authenticated,service_role;
revoke all on function public.ptw_p0_a2_import_writer_fixture() from public,anon,authenticated,service_role;
grant execute on function public.ptw_p0_a2_import_writer_fixture() to service_role;

insert into public.school_app_memberships(user_id,role,is_active) values
  ('a0000000-0000-0000-0000-000000000001','admin',true),
  ('a0000000-0000-0000-0000-000000000002','operator',true),
  ('a0000000-0000-0000-0000-000000000003','read_only',true),
  ('a0000000-0000-0000-0000-000000000004','admin',false),
  ('a0000000-0000-0000-0000-000000000005','unknown_future_role',true);

do $test$
declare
  v_message text;
begin
  if has_function_privilege('anon','public.ptw_p0_a2_operator_writer_fixture()','EXECUTE')
     or not has_function_privilege('authenticated','public.ptw_p0_a2_operator_writer_fixture()','EXECUTE')
     or has_function_privilege('service_role','public.ptw_p0_a2_operator_writer_fixture()','EXECUTE')
     or not has_function_privilege(current_user,'public.ptw_p0_a2_operator_writer_fixture()','EXECUTE')
     or has_function_privilege('anon','public.ptw_p0_a2_admin_writer_fixture()','EXECUTE')
     or not has_function_privilege('authenticated','public.ptw_p0_a2_admin_writer_fixture()','EXECUTE')
     or has_function_privilege('service_role','public.ptw_p0_a2_admin_writer_fixture()','EXECUTE')
     or has_function_privilege('anon','public.ptw_p0_a2_retired_writer_fixture()','EXECUTE')
     or has_function_privilege('authenticated','public.ptw_p0_a2_retired_writer_fixture()','EXECUTE')
     or has_function_privilege('service_role','public.ptw_p0_a2_retired_writer_fixture()','EXECUTE')
     or not has_function_privilege(current_user,'public.ptw_p0_a2_retired_writer_fixture()','EXECUTE')
     or has_function_privilege('anon','public.ptw_p0_a2_import_writer_fixture()','EXECUTE')
     or has_function_privilege('authenticated','public.ptw_p0_a2_import_writer_fixture()','EXECUTE')
     or not has_function_privilege('service_role','public.ptw_p0_a2_import_writer_fixture()','EXECUTE') then
    raise exception 'database role ACL matrix failed';
  end if;

  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',true);
  if public.school_require_current_part_time_work_operator()<>'a0000000-0000-0000-0000-000000000001'::uuid
     or public.school_require_current_part_time_work_admin()<>'a0000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'active admin matrix failed';
  end if;

  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000002',true);
  if public.school_require_current_part_time_work_operator()<>'a0000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'active operator operational matrix failed';
  end if;
  begin
    perform public.school_require_current_part_time_work_admin();
    raise exception 'active operator unexpectedly passed admin guard';
  exception when sqlstate '42501' then
    get stacked diagnostics v_message=message_text;
    if v_message<>'PTW_WRITER_ADMIN_ROLE_REQUIRED' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000003',true);
  begin perform public.school_require_current_part_time_work_operator(); raise exception 'read_only passed';
  exception when sqlstate '42501' then
    get stacked diagnostics v_message=message_text;
    if v_message<>'PTW_WRITER_OPERATOR_ROLE_REQUIRED' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000004',true);
  begin perform public.school_require_current_part_time_work_operator(); raise exception 'inactive passed';
  exception when sqlstate '42501' then
    get stacked diagnostics v_message=message_text;
    if v_message<>'PTW_WRITER_ACTIVE_MEMBERSHIP_REQUIRED' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000005',true);
  begin perform public.school_require_current_part_time_work_operator(); raise exception 'unknown role passed';
  exception when sqlstate '42501' then
    get stacked diagnostics v_message=message_text;
    if v_message<>'PTW_WRITER_OPERATOR_ROLE_REQUIRED' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000099',true);
  begin perform public.school_require_current_part_time_work_operator(); raise exception 'no membership passed';
  exception when sqlstate '42501' then
    get stacked diagnostics v_message=message_text;
    if v_message<>'PTW_WRITER_MEMBERSHIP_REQUIRED' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.school_require_current_part_time_work_operator(); raise exception 'authless passed';
  exception when sqlstate '42501' then
    get stacked diagnostics v_message=message_text;
    if v_message<>'PTW_WRITER_AUTH_REQUIRED' then raise; end if;
  end;
end
$test$;

select 'PTW_P0_A2_LOCAL_ROLE_MATRIX_PASS' as result;
rollback;
