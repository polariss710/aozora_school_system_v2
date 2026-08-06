-- Postdeploy-only identity and ACL matrix. Synthetic auth rows are fully rolled back.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='120s';

do $preflight$
begin
  if exists(select 1 from auth.users where id::text like 'be110000-%')
     or exists(select 1 from public.school_app_memberships where user_id::text like 'be110000-%') then
    raise exception 'LESSON_WRITER_P0_ROLE_FIXTURE_COLLISION';
  end if;
end;
$preflight$;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('be110000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-postdeploy-admin"}',now(),now()),
 ('be110000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-postdeploy-operator"}',now(),now()),
 ('be110000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-postdeploy-read-only"}',now(),now()),
 ('be110000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-postdeploy-inactive-admin"}',now(),now()),
 ('be110000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-postdeploy-inactive-operator"}',now(),now()),
 ('be110000-0000-4000-8000-000000000006','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-postdeploy-no-membership"}',now(),now());

insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
 ('be110000-0000-4000-8000-000000000001','admin',true,'be110000-0000-4000-8000-000000000001','be110000-0000-4000-8000-000000000001','codex-test lesson writer p0 postdeploy'),
 ('be110000-0000-4000-8000-000000000002','operator',true,'be110000-0000-4000-8000-000000000001','be110000-0000-4000-8000-000000000001','codex-test lesson writer p0 postdeploy'),
 ('be110000-0000-4000-8000-000000000003','read_only',true,'be110000-0000-4000-8000-000000000001','be110000-0000-4000-8000-000000000001','codex-test lesson writer p0 postdeploy'),
 ('be110000-0000-4000-8000-000000000004','admin',false,'be110000-0000-4000-8000-000000000001','be110000-0000-4000-8000-000000000001','codex-test lesson writer p0 postdeploy'),
 ('be110000-0000-4000-8000-000000000005','operator',false,'be110000-0000-4000-8000-000000000001','be110000-0000-4000-8000-000000000001','codex-test lesson writer p0 postdeploy');

set local role anon;
do $anon$
begin
  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      null,null,null,null,null,null,null,null,null,null,null,null);
    raise exception 'LESSON_WRITER_P0_ANON_ALLOWED';
  exception when insufficient_privilege then null;
  end;
end;
$anon$;
reset role;

set local role service_role;
do $service$
begin
  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      null,null,null,null,null,null,null,null,null,null,null,null);
    raise exception 'LESSON_WRITER_P0_SERVICE_ALLOWED';
  exception when insufficient_privilege then null;
  end;
end;
$service$;
reset role;

set local role authenticated;
do $matrix$
declare
  v_actor uuid;
  v_expected text;
  v_error text;
begin
  begin
    perform * from public.school_create_makeup_completed_actual_lesson_from_planned(
      null,null,null,null,null,null,null,null,null,null,null);
    raise exception 'LESSON_WRITER_P0_LEGACY_WRAPPER_ALLOWED';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.school_get_lesson_credit_raw_remaining_hours(null);
    raise exception 'LESSON_WRITER_P0_OWNER_HELPER_ALLOWED';
  exception when insufficient_privilege then null;
  end;

  for v_actor,v_expected in select * from (values
    ('be110000-0000-4000-8000-000000000006'::uuid,'LESSON_WRITER_MEMBERSHIP_REQUIRED'),
    ('be110000-0000-4000-8000-000000000003'::uuid,'LESSON_WRITER_ROLE_REQUIRED'),
    ('be110000-0000-4000-8000-000000000004'::uuid,'LESSON_WRITER_ACTIVE_MEMBERSHIP_REQUIRED'),
    ('be110000-0000-4000-8000-000000000005'::uuid,'LESSON_WRITER_ACTIVE_MEMBERSHIP_REQUIRED'),
    (null::uuid,'LESSON_WRITER_AUTH_REQUIRED')
  ) x(actor,expected)
  loop
    perform set_config('request.jwt.claims',
      case when v_actor is null then '{"role":"authenticated"}'
           else jsonb_build_object('sub',v_actor,'role','authenticated')::text end,true);
    v_error:=null;
    begin
      perform * from public.school_create_lesson_credit_makeup_actual(
        null,null,null,null,null,null,null,null,null,null,null,null);
    exception when others then v_error:=sqlerrm;
    end;
    if position(v_expected in coalesce(v_error,''))=0 then
      raise exception 'LESSON_WRITER_P0_ROLE_MATRIX:%:%',v_expected,v_error;
    end if;
  end loop;

  for v_actor in select unnest(array[
    'be110000-0000-4000-8000-000000000001'::uuid,
    'be110000-0000-4000-8000-000000000002'::uuid
  ])
  loop
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_error:=null;
    begin
      perform * from public.school_create_lesson_credit_makeup_actual(
        null,null,null,null,null,null,null,null,null,null,null,null);
    exception when others then v_error:=sqlerrm;
    end;
    if position('LESSON_MAKEUP_SOURCE_REQUIRED' in coalesce(v_error,''))=0 then
      raise exception 'LESSON_WRITER_P0_ACTIVE_ROLE_REJECTED:%:%',v_actor,v_error;
    end if;
  end loop;
end;
$matrix$;
reset role;

select 'LESSON_WRITER_P0_POSTDEPLOY_ROLE_MATRIX_PASS' result;
rollback;
