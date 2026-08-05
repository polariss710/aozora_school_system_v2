-- School V2 student-master P0 permission closure rollback and role matrix.
-- All auth, membership and student fixtures plus ACL/RLS/function changes roll back.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_master_p0_permission_closure_core_20260805.sql

insert into auth.users (id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('a0500000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-p0-operator"}'::jsonb,now(),now()),
  ('a0500000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-p0-read-only"}'::jsonb,now(),now()),
  ('a0500000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-p0-inactive-admin"}'::jsonb,now(),now()),
  ('a0500000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-p0-active-admin"}'::jsonb,now(),now()),
  ('a0500000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-p0-no-membership"}'::jsonb,now(),now());

insert into public.school_app_memberships (
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
  ('a0500000-0000-4000-8000-000000000001','operator',true,'a0500000-0000-4000-8000-000000000004','a0500000-0000-4000-8000-000000000004','codex-test student-p0 operator'),
  ('a0500000-0000-4000-8000-000000000002','read_only',true,'a0500000-0000-4000-8000-000000000004','a0500000-0000-4000-8000-000000000004','codex-test student-p0 read-only'),
  ('a0500000-0000-4000-8000-000000000003','admin',false,'a0500000-0000-4000-8000-000000000004','a0500000-0000-4000-8000-000000000004','codex-test student-p0 inactive admin'),
  ('a0500000-0000-4000-8000-000000000004','admin',true,'a0500000-0000-4000-8000-000000000004','a0500000-0000-4000-8000-000000000004','codex-test student-p0 active admin');

insert into public.school_students (
  id,student_code,name,display_name,status,business_entity_id,default_currency,
  preset_exchange_rate,note,app_type,created_at,updated_at
) values (
  'a0500000-0000-4000-8000-000000000100','CODEX-STUDENT-P0-FIXTURE',
  'codex-test student-p0 fixture','codex-test student-p0 fixture','active',
  public.school_primary_business_entity_id(),'CNY',0,
  'codex-test student-p0 rollback-only','school',now()-interval '1 day',now()-interval '1 day'
);

set local role anon;
do $anon_matrix$
declare v_denied boolean;
begin
  v_denied:=false;
  begin perform count(*) from public.school_students;
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STUDENT_P0_ANON_SELECT_ALLOWED'; end if;

  v_denied:=false;
  begin
    perform * from public.school_create_student_profile(
      'codex-test anon denied',null,null,0,null,null,null,null,null,'active'
    );
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STUDENT_P0_ANON_RPC_ALLOWED'; end if;
end;
$anon_matrix$;
reset role;

set local role authenticated;
do $authenticated_matrix$
declare
  v_actor uuid;
  v_count bigint;
  v_denied boolean;
  v_created record;
  v_updated record;
  v_fixture_updated_at timestamptz;
begin
  foreach v_actor in array array[
    'a0500000-0000-4000-8000-000000000005'::uuid,
    'a0500000-0000-4000-8000-000000000003'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    select count(*) into v_count from public.school_students;
    if v_count<>0 then raise exception 'STUDENT_P0_INELIGIBLE_READ_ALLOWED:%',v_actor; end if;
  end loop;

  foreach v_actor in array array[
    'a0500000-0000-4000-8000-000000000005'::uuid,
    'a0500000-0000-4000-8000-000000000003'::uuid,
    'a0500000-0000-4000-8000-000000000001'::uuid,
    'a0500000-0000-4000-8000-000000000002'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_denied:=false;
    begin
      perform * from public.school_create_student_profile(
        'codex-test denied student',null,null,0,null,null,null,null,null,'active'
      );
    exception when insufficient_privilege then
      if sqlerrm='P0G1_ACTIVE_ADMIN_REQUIRED' then v_denied:=true; else raise; end if;
    end;
    if not v_denied then raise exception 'STUDENT_P0_NON_ADMIN_CREATE_ALLOWED:%',v_actor; end if;
  end loop;

  foreach v_actor in array array[
    'a0500000-0000-4000-8000-000000000004'::uuid,
    'a0500000-0000-4000-8000-000000000001'::uuid,
    'a0500000-0000-4000-8000-000000000002'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    select count(*) into v_count from public.school_students;
    if v_count<1 then raise exception 'STUDENT_P0_ACTIVE_MEMBER_READ_DENIED:%',v_actor; end if;

    v_denied:=false;
    begin update public.school_students set note=note where id='a0500000-0000-4000-8000-000000000100';
    exception when insufficient_privilege then v_denied:=true; end;
    if not v_denied then raise exception 'STUDENT_P0_DIRECT_UPDATE_ALLOWED:%',v_actor; end if;

    v_denied:=false;
    begin delete from public.school_students where id='a0500000-0000-4000-8000-000000000100';
    exception when insufficient_privilege then v_denied:=true; end;
    if not v_denied then raise exception 'STUDENT_P0_DIRECT_DELETE_ALLOWED:%',v_actor; end if;

    v_denied:=false;
    begin truncate table public.school_students;
    exception when insufficient_privilege then v_denied:=true; end;
    if not v_denied then raise exception 'STUDENT_P0_DIRECT_TRUNCATE_ALLOWED:%',v_actor; end if;
  end loop;

  v_actor:='a0500000-0000-4000-8000-000000000004'::uuid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);

  select * into strict v_created
  from public.school_create_student_profile(
    'codex-test student-p0 created',public.school_primary_business_entity_id(),
    'science',0,null,null,current_date,null,'codex-test rollback-only','paused'
  );
  if v_created.status<>'paused' then raise exception 'STUDENT_P0_ADMIN_CREATE_INVALID'; end if;

  select updated_at into strict v_fixture_updated_at
  from public.school_students where id='a0500000-0000-4000-8000-000000000100';
  select * into strict v_updated
  from public.school_update_student_profile(
    'a0500000-0000-4000-8000-000000000100','codex-test student-p0 updated',
    public.school_primary_business_entity_id(),'humanities',0,null,null,current_date,
    null,'codex-test student-p0 rollback-updated','withdrawn',v_fixture_updated_at
  );
  if v_updated.status<>'withdrawn' or v_updated.name<>'codex-test student-p0 updated' then
    raise exception 'STUDENT_P0_ADMIN_UPDATE_INVALID';
  end if;

  v_denied:=false;
  begin
    perform * from public.school_update_student_profile(
      'a0500000-0000-4000-8000-000000000100','codex-test stale rejected',
      public.school_primary_business_entity_id(),'humanities',0,null,null,current_date,
      null,'codex-test stale rejected','active',v_fixture_updated_at
    );
  exception when serialization_failure then v_denied:=true; end;
  if not v_denied then raise exception 'STUDENT_P0_STALE_UPDATE_ALLOWED'; end if;

  v_denied:=false;
  begin perform * from public.school_create_student_profile('','00000000-0000-0000-0000-000000000000'::uuid,null,0,null,null,null,null,null,'invalid');
  exception when invalid_parameter_value then v_denied:=true; end;
  if not v_denied then raise exception 'STUDENT_P0_INVALID_PAYLOAD_ALLOWED'; end if;

  v_denied:=false;
  begin
    perform * from public.school_create_student_profile(
      'codex-test invalid status',public.school_primary_business_entity_id(),null,0,
      null,null,null,null,'codex-test rollback-only','invalid'
    );
  exception when invalid_parameter_value then v_denied:=true; end;
  if not v_denied then raise exception 'STUDENT_P0_INVALID_STATUS_ALLOWED'; end if;

  v_denied:=false;
  begin
    perform * from public.school_update_student_profile(
      '00000000-0000-0000-0000-000000000000','missing',null,null,0,null,null,null,null,null,'active',now()
    );
  exception when no_data_found then v_denied:=true; end;
  if not v_denied then raise exception 'STUDENT_P0_MISSING_STUDENT_ALLOWED'; end if;
end;
$authenticated_matrix$;
reset role;

set local role service_role;
do $service_matrix$
declare v_count bigint; v_denied boolean;
begin
  select count(*) into v_count from public.school_students;
  if v_count<1 then raise exception 'STUDENT_P0_SERVICE_SELECT_DENIED'; end if;
  v_denied:=false;
  begin update public.school_students set note=note where id='a0500000-0000-4000-8000-000000000100';
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STUDENT_P0_SERVICE_DIRECT_UPDATE_ALLOWED'; end if;
  v_denied:=false;
  begin
    perform * from public.school_create_student_profile(
      'codex-test service denied',null,null,0,null,null,null,null,null,'active'
    );
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STUDENT_P0_SERVICE_RPC_ALLOWED'; end if;
end;
$service_matrix$;
reset role;

do $acl_matrix$
declare v_oid oid;
begin
  if has_table_privilege('anon','public.school_students','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('authenticated','public.school_students','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('service_role','public.school_students','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or not has_table_privilege('authenticated','public.school_students','SELECT')
     or not has_table_privilege('service_role','public.school_students','SELECT') then
    raise exception 'STUDENT_P0_TABLE_ACL_MATRIX_INVALID';
  end if;

  for v_oid in
    select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('school_create_student_profile','school_update_student_profile')
  loop
    if has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'STUDENT_P0_ANON_OR_SERVICE_OVERLOAD_EXECUTE:%',v_oid::regprocedure;
    end if;
  end loop;
end;
$acl_matrix$;

select 'STUDENT_P0_PERMISSION_CLOSURE_ROLLBACK_TEST_PASS' result;
rollback;
