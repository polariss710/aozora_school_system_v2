-- P0-G1-A membership RPC rollback and role matrix tests.
-- All synthetic auth/membership fixtures remain inside this transaction.
\set ON_ERROR_STOP on
\pset pager off

begin;

insert into auth.users (id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('a0100000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-a-operator"}'::jsonb,now(),now()),
  ('a0100000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-a-read-only"}'::jsonb,now(),now()),
  ('a0100000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-a-inactive-admin"}'::jsonb,now(),now()),
  ('a0100000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-a-active-admin"}'::jsonb,now(),now()),
  ('a0100000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-a-maintenance-target"}'::jsonb,now(),now());

insert into public.school_app_memberships (
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
)
values
  ('a0100000-0000-4000-8000-000000000001','operator',true,'a0100000-0000-4000-8000-000000000001','a0100000-0000-4000-8000-000000000001','codex-test p0-g1-a operator'),
  ('a0100000-0000-4000-8000-000000000002','read_only',true,'a0100000-0000-4000-8000-000000000002','a0100000-0000-4000-8000-000000000002','codex-test p0-g1-a read-only'),
  ('a0100000-0000-4000-8000-000000000003','admin',false,'a0100000-0000-4000-8000-000000000003','a0100000-0000-4000-8000-000000000003','codex-test p0-g1-a inactive admin'),
  ('a0100000-0000-4000-8000-000000000004','admin',true,'a0100000-0000-4000-8000-000000000004','a0100000-0000-4000-8000-000000000004','codex-test p0-g1-a active admin');

do $test$
declare
  v_denied boolean;
  v_actor uuid;
  v_row record;
begin
  foreach v_actor in array array[
    'a0100000-0000-4000-8000-000000000001'::uuid,
    'a0100000-0000-4000-8000-000000000002'::uuid,
    'a0100000-0000-4000-8000-000000000003'::uuid,
    'a0100000-0000-4000-8000-000000000005'::uuid
  ] loop
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_denied := false;
    begin
      perform public.school_require_current_app_admin();
    exception when insufficient_privilege then
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'P0G1_NON_ADMIN_WAS_ACCEPTED: %',v_actor;
    end if;
  end loop;

  v_actor := 'a0100000-0000-4000-8000-000000000004'::uuid;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
  if public.school_require_current_app_admin() is distinct from v_actor then
    raise exception 'P0G1_ACTIVE_ADMIN_ASSERTION_FAILED';
  end if;

  select * into strict v_row
  from public.school_admin_set_app_membership(
    'a0100000-0000-4000-8000-000000000005','operator',true,
    'codex-test p0-g1-a controlled insert'
  );
  if v_row.role<>'operator' or not v_row.is_active
     or v_row.created_by_user_id<>v_actor or v_row.updated_by_user_id<>v_actor then
    raise exception 'P0G1_CONTROLLED_MAINTENANCE_AUDIT_FAILED';
  end if;

  v_denied := false;
  begin
    perform * from public.school_admin_set_app_membership(
      v_actor,'read_only',true,'codex-test p0-g1-a last admin rejection'
    );
  exception when check_violation then
    if sqlerrm='P0G1_LAST_ACTIVE_ADMIN_REQUIRED' then
      v_denied := true;
    else
      raise;
    end if;
  end;
  if not v_denied then
    raise exception 'P0G1_LAST_ACTIVE_ADMIN_GUARD_FAILED';
  end if;
end;
$test$;

select 'P0G1_MEMBERSHIP_RPC_ROLLBACK_TEST_PASS' result;
rollback;
