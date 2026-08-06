-- Local/isolated PostgreSQL fixture for School V2 Phase BE-P0.
-- This entire fixture, including roles and schemas, rolls back.
\set ON_ERROR_STOP on
\pset pager off

begin;

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role be_p0_public_probe nologin;

create schema auth;
create function auth.uid()
returns uuid
language sql
stable
set search_path = pg_catalog
as $function$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$function$;

create table public.school_app_memberships (
  user_id uuid primary key,
  role text not null,
  is_active boolean not null
);

create table public.school_business_entities (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  code text not null unique,
  name text not null,
  entity_type text not null default 'company',
  default_currency text default 'JPY',
  is_company_report boolean not null default false,
  is_active boolean not null default true,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create function public.school_set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $function$
begin
  new.updated_at=clock_timestamp();
  return new;
end;
$function$;
create trigger trg_school_business_entities_updated_at
before update on public.school_business_entities
for each row execute function public.school_set_updated_at();

create function public.school_get_current_app_membership()
returns table(user_id uuid,role text,is_active boolean)
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
    raise exception using errcode='42501',message='P0G1_AUTH_REQUIRED';
  end if;
  if not exists (
    select 1 from public.school_app_memberships m
    where m.user_id=v_actor and m.is_active and m.role='admin'
  ) then
    raise exception using errcode='42501',message='P0G1_ACTIVE_ADMIN_REQUIRED';
  end if;
  return v_actor;
end;
$function$;

revoke all on table public.school_app_memberships from public,anon,authenticated,service_role;
revoke all on function public.school_get_current_app_membership() from public,anon,authenticated,service_role;
grant execute on function public.school_get_current_app_membership() to authenticated;
revoke all on function public.school_require_current_app_admin() from public,anon,authenticated,service_role;

insert into public.school_app_memberships(user_id,role,is_active) values
  ('be000000-0000-4000-8000-000000000001','operator',true),
  ('be000000-0000-4000-8000-000000000002','read_only',true),
  ('be000000-0000-4000-8000-000000000003','admin',false),
  ('be000000-0000-4000-8000-000000000004','admin',true);

insert into public.school_business_entities(
  id,code,name,entity_type,default_currency,is_company_report,is_active,note,created_at,updated_at
) values
  ('2cf7b72f-6e3c-4d09-80f7-7c58593cd466','aosora','青空进学塾','company','JPY',true,true,null,'2026-05-17 06:48:19.596049+00','2026-05-17 06:48:19.596049+00'),
  ('886a8f7c-0fea-45ac-97d2-15c976ede996','personal','个人名义','personal','CNY',false,true,null,'2026-05-17 06:48:19.596049+00','2026-05-17 06:48:19.596049+00');

alter table public.school_business_entities enable row level security;
create policy school_allow_all_business_entities on public.school_business_entities
for all to public using (true) with check (true);
grant all on table public.school_business_entities to anon,authenticated,service_role;

\ir ../current/school_create_business_entity_profile_rpc.sql
\ir ../current/school_update_business_entity_profile_rpc.sql
grant execute on function public.school_create_business_entity_profile(text,text,text,text,boolean,text)
  to anon,authenticated,service_role;
grant execute on function public.school_create_business_entity_profile(jsonb)
  to anon,authenticated,service_role;
grant execute on function public.school_update_business_entity_profile(uuid,text,text,text,boolean,text)
  to anon,authenticated,service_role;
grant execute on function public.school_update_business_entity_profile(uuid,jsonb)
  to anon,authenticated,service_role;

\ir ../current/school_business_entity_p0_permission_closure_core_20260806.sql

set local role be_p0_public_probe;
do $public_matrix$
declare v_denied boolean;
begin
  v_denied:=false;
  begin perform count(*) from public.school_business_entities;
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_PUBLIC_SELECT_ALLOWED'; end if;

  v_denied:=false;
  begin perform * from public.school_create_business_entity_profile('{"name":"public denied"}'::jsonb);
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_PUBLIC_CREATE_RPC_ALLOWED'; end if;
end;
$public_matrix$;
reset role;

set local role anon;
do $anon_matrix$
declare v_denied boolean;
begin
  v_denied:=false;
  begin perform count(*) from public.school_business_entities;
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_ANON_SELECT_ALLOWED'; end if;

  v_denied:=false;
  begin perform * from public.school_create_business_entity_profile('{"name":"anon denied"}'::jsonb);
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_ANON_CREATE_RPC_ALLOWED'; end if;

  v_denied:=false;
  begin perform * from public.school_update_business_entity_profile(
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','{"name":"anon denied","entity_type":"company","is_active":true}'::jsonb
  ); exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_ANON_UPDATE_RPC_ALLOWED'; end if;
end;
$anon_matrix$;
reset role;

set local role authenticated;
do $membership_matrix$
declare
  v_actor uuid;
  v_count bigint;
  v_denied boolean;
begin
  foreach v_actor in array array[
    'be000000-0000-4000-8000-000000000005'::uuid,
    'be000000-0000-4000-8000-000000000003'::uuid
  ] loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    select count(*) into v_count from public.school_business_entities;
    if v_count<>0 then raise exception 'BE_P0_INELIGIBLE_SELECT_ALLOWED:%',v_actor; end if;

    v_denied:=false;
    begin
      perform * from public.school_create_business_entity_profile('{}'::jsonb);
    exception when insufficient_privilege then
      if sqlerrm='P0G1_ACTIVE_ADMIN_REQUIRED' then v_denied:=true; else raise; end if;
    end;
    if not v_denied then raise exception 'BE_P0_INELIGIBLE_CREATE_ALLOWED:%',v_actor; end if;

    v_denied:=false;
    begin
      perform * from public.school_update_business_entity_profile(null,'{}'::jsonb);
    exception when insufficient_privilege then
      if sqlerrm='P0G1_ACTIVE_ADMIN_REQUIRED' then v_denied:=true; else raise; end if;
    end;
    if not v_denied then raise exception 'BE_P0_INELIGIBLE_UPDATE_ALLOWED:%',v_actor; end if;
  end loop;

  foreach v_actor in array array[
    'be000000-0000-4000-8000-000000000001'::uuid,
    'be000000-0000-4000-8000-000000000002'::uuid
  ] loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    select count(*) into v_count from public.school_business_entities;
    if v_count<>2 then raise exception 'BE_P0_ACTIVE_READER_DENIED:%',v_actor; end if;

    v_denied:=false;
    begin
      perform * from public.school_create_business_entity_profile('{}'::jsonb);
    exception when insufficient_privilege then
      if sqlerrm='P0G1_ACTIVE_ADMIN_REQUIRED' then v_denied:=true; else raise; end if;
    end;
    if not v_denied then raise exception 'BE_P0_NON_ADMIN_CREATE_ALLOWED:%',v_actor; end if;

    v_denied:=false;
    begin
      perform * from public.school_update_business_entity_profile(null,'{}'::jsonb);
    exception when insufficient_privilege then
      if sqlerrm='P0G1_ACTIVE_ADMIN_REQUIRED' then v_denied:=true; else raise; end if;
    end;
    if not v_denied then raise exception 'BE_P0_NON_ADMIN_UPDATE_ALLOWED:%',v_actor; end if;
  end loop;

  if (select count(*) from public.school_business_entities)<>2 then
    raise exception 'BE_P0_DENIAL_PARTIAL_WRITE';
  end if;
end;
$membership_matrix$;

select set_config('request.jwt.claim.sub','be000000-0000-4000-8000-000000000004',true);
do $admin_matrix$
declare
  v_count bigint;
  v_denied boolean;
  v_created record;
  v_updated record;
begin
  select count(*) into v_count from public.school_business_entities;
  if v_count<>2 then raise exception 'BE_P0_ADMIN_SELECT_DENIED'; end if;

  v_denied:=false;
  begin
    insert into public.school_business_entities(code,name) values('direct-denied','direct denied');
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_ADMIN_DIRECT_INSERT_ALLOWED'; end if;

  v_denied:=false;
  begin
    update public.school_business_entities set note=note
    where id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_ADMIN_DIRECT_UPDATE_ALLOWED'; end if;

  v_denied:=false;
  begin
    delete from public.school_business_entities
    where id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_ADMIN_DIRECT_DELETE_ALLOWED'; end if;

  v_denied:=false;
  begin truncate table public.school_business_entities;
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_ADMIN_DIRECT_TRUNCATE_ALLOWED'; end if;

  select * into strict v_created
  from public.school_create_business_entity_profile(
    '{"name":"codex-test BE-P0","entity_type":"company","is_active":true,"note":"rollback-only"}'::jsonb
  );
  if v_created.name<>'codex-test BE-P0' then raise exception 'BE_P0_ADMIN_CREATE_INVALID'; end if;

  select * into strict v_updated
  from public.school_update_business_entity_profile(
    v_created.business_entity_id,
    '{"name":"codex-test BE-P0 updated","entity_type":"company","is_active":true,"note":"rollback-only updated"}'::jsonb
  );
  if v_updated.name<>'codex-test BE-P0 updated' then raise exception 'BE_P0_ADMIN_UPDATE_INVALID'; end if;
end;
$admin_matrix$;
reset role;

grant insert,update,delete on public.school_business_entities to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','be000000-0000-4000-8000-000000000004',true);
do $rls_write_backstop$
declare v_denied boolean;
begin
  v_denied:=false;
  begin
    insert into public.school_business_entities(code,name) values('rls-denied','rls denied');
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_RLS_INSERT_BACKSTOP_FAILED'; end if;
end;
$rls_write_backstop$;
reset role;
revoke insert,update,delete on public.school_business_entities from authenticated;

set local role service_role;
do $service_matrix$
declare v_denied boolean;
begin
  v_denied:=false;
  begin perform count(*) from public.school_business_entities;
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_SERVICE_SELECT_ALLOWED'; end if;

  v_denied:=false;
  begin perform * from public.school_create_business_entity_profile('{"name":"service denied"}'::jsonb);
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'BE_P0_SERVICE_CREATE_ALLOWED'; end if;
end;
$service_matrix$;
reset role;

do $catalog_matrix$
declare
  v_oid oid;
  v_def text;
begin
  if has_table_privilege('anon','public.school_business_entities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('authenticated','public.school_business_entities','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('service_role','public.school_business_entities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or not has_table_privilege('authenticated','public.school_business_entities','SELECT') then
    raise exception 'BE_P0_TABLE_ACL_MATRIX_INVALID';
  end if;

  if (select count(*) from pg_policies where schemaname='public' and tablename='school_business_entities')<>1
     or not exists (
       select 1 from pg_policies
       where schemaname='public' and tablename='school_business_entities'
         and policyname='school_business_entities_active_membership_select'
         and cmd='SELECT' and roles='{authenticated}'
         and qual ilike '%school_get_current_app_membership%'
     ) then
    raise exception 'BE_P0_RLS_MATRIX_INVALID';
  end if;

  for v_oid in
    select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('school_create_business_entity_profile','school_update_business_entity_profile')
  loop
    select lower(pg_get_functiondef(v_oid)) into v_def;
    if not (select p.prosecdef and p.proconfig='{"search_path=pg_catalog, public"}'::text[]
            from pg_proc p where p.oid=v_oid)
       or position('perform public.school_require_current_app_admin();' in v_def)=0
       or has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'BE_P0_WRITER_SECURITY_INVALID:%',v_oid::regprocedure;
    end if;
  end loop;

  if not has_function_privilege('authenticated','public.school_create_business_entity_profile(jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','public.school_update_business_entity_profile(uuid,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.school_create_business_entity_profile(text,text,text,text,boolean,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_update_business_entity_profile(uuid,text,text,text,boolean,text)','EXECUTE') then
    raise exception 'BE_P0_OVERLOAD_ACL_INVALID';
  end if;
end;
$catalog_matrix$;

select 'BE_P0_PERMISSION_CLOSURE_LOCAL_ROLLBACK_TEST_PASS' result;
rollback;
