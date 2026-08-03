-- P0-G1-B1 active-admin authority matrix. All fixtures and role changes roll back.
\set ON_ERROR_STOP on
\pset pager off

begin;

insert into auth.users (id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('b1100000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-b1-operator"}'::jsonb,now(),now()),
  ('b1100000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-b1-read-only"}'::jsonb,now(),now()),
  ('b1100000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-b1-inactive-admin"}'::jsonb,now(),now()),
  ('b1100000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-b1-active-admin"}'::jsonb,now(),now()),
  ('b1100000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-g1-b1-no-membership"}'::jsonb,now(),now());

insert into public.school_app_memberships (
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
)
values
  ('b1100000-0000-4000-8000-000000000001','operator',true,'b1100000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','codex-test p0-g1-b1 operator'),
  ('b1100000-0000-4000-8000-000000000002','read_only',true,'b1100000-0000-4000-8000-000000000002','b1100000-0000-4000-8000-000000000002','codex-test p0-g1-b1 read-only'),
  ('b1100000-0000-4000-8000-000000000003','admin',false,'b1100000-0000-4000-8000-000000000003','b1100000-0000-4000-8000-000000000003','codex-test p0-g1-b1 inactive admin'),
  ('b1100000-0000-4000-8000-000000000004','admin',true,'b1100000-0000-4000-8000-000000000004','b1100000-0000-4000-8000-000000000004','codex-test p0-g1-b1 active admin');

set local role authenticated;

do $matrix$
declare
  v_actor uuid;
  v_denied boolean;
begin
  foreach v_actor in array array[
    'b1100000-0000-4000-8000-000000000001'::uuid,
    'b1100000-0000-4000-8000-000000000002'::uuid,
    'b1100000-0000-4000-8000-000000000003'::uuid,
    'b1100000-0000-4000-8000-000000000005'::uuid
  ] loop
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_denied:=false;
    begin
      perform public.school_require_current_app_admin();
    exception when insufficient_privilege then
      if sqlerrm='P0G1_ACTIVE_ADMIN_REQUIRED' then
        v_denied:=true;
      else
        raise;
      end if;
    end;
    if not v_denied then
      raise exception 'P0G1B1_NON_ADMIN_ACCEPTED: %',v_actor;
    end if;
  end loop;

  v_actor:='b1100000-0000-4000-8000-000000000004'::uuid;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
  if public.school_require_current_app_admin() is distinct from v_actor then
    raise exception 'P0G1B1_ACTIVE_ADMIN_ASSERTION_FAILED';
  end if;
end;
$matrix$;

reset role;

do $acl$
begin
  if has_function_privilege('anon','public.school_require_current_app_admin()','EXECUTE')
     or not has_function_privilege('authenticated','public.school_require_current_app_admin()','EXECUTE')
     or has_function_privilege('service_role','public.school_require_current_app_admin()','EXECUTE')
     or has_function_privilege('anon','public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','EXECUTE')
     or not has_function_privilege('service_role','public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','EXECUTE')
     or has_function_privilege('anon','public.school_mark_cash_income_request_submitted(uuid,uuid,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_mark_cash_income_request_submitted(uuid,uuid,text)','EXECUTE')
     or not has_function_privilege('service_role','public.school_mark_cash_income_request_submitted(uuid,uuid,text)','EXECUTE') then
    raise exception 'P0G1B1_SCHOOL_CASH_ACL_MATRIX_INVALID';
  end if;
end;
$acl$;

select 'P0G1B1_ADMIN_CASH_AUTHORITY_ROLLBACK_TEST_PASS' result;
rollback;
