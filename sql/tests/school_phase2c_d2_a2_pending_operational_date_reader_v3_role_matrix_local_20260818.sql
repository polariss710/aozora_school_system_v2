-- Phase 2C-D2-A2 local V3 reader role matrix. No business writes.
\set ON_ERROR_STOP on
\pset pager off
begin;

do $allowed$
declare
  v_actor uuid;
  v_payload jsonb;
begin
  foreach v_actor in array array[
    '90000000-0000-4000-8000-000000000001'::uuid,
    '90000000-0000-4000-8000-000000000002'::uuid,
    '90000000-0000-4000-8000-000000000003'::uuid
  ] loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    set local role authenticated;
    v_payload:=public.school_list_lesson_clearance_pending_balances_v3(null,false);
    if v_payload->>'contract_version'<>'lesson_clearance_pending_balances_v3' then
      raise exception 'D2_A2_ALLOWED_ROLE_INVALID:%',v_actor;
    end if;
    reset role;
  end loop;
end
$allowed$;

do $denied_membership$
declare
  v_actor uuid;
  v_expected text;
  v_error text;
begin
  for v_actor,v_expected in select * from (values
    ('90000000-0000-4000-8000-000000000004'::uuid,
      'LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED'),
    ('90000000-0000-4000-8000-000000000099'::uuid,
      'LESSON_CLEARANCE_MEMBERSHIP_REQUIRED')
  ) denied(actor,expected) loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    set local role authenticated;
    begin
      perform public.school_list_lesson_clearance_pending_balances_v3(null,false);
      raise exception 'D2_A2_DENIAL_MISSING';
    exception when others then
      get stacked diagnostics v_error=message_text;
      if v_error='D2_A2_DENIAL_MISSING'
         or position(v_expected in v_error)=0 then raise; end if;
    end;
    reset role;
  end loop;
end
$denied_membership$;

do $authless$
declare v_error text;
begin
  perform set_config('request.jwt.claim.sub','',true);
  set local role authenticated;
  begin
    perform public.school_list_lesson_clearance_pending_balances_v3(null,false);
    raise exception 'D2_A2_AUTHLESS_DENIAL_MISSING';
  exception when others then
    get stacked diagnostics v_error=message_text;
    if v_error='D2_A2_AUTHLESS_DENIAL_MISSING'
       or position('LESSON_CLEARANCE_AUTH_REQUIRED' in v_error)=0 then raise; end if;
  end;
  reset role;
end
$authless$;

do $acl$
declare
  v_signature regprocedure:=
    'public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)'::regprocedure;
begin
  if not has_function_privilege('authenticated',v_signature,'EXECUTE')
     or has_function_privilege('anon',v_signature,'EXECUTE')
     or has_function_privilege('service_role',v_signature,'EXECUTE') then
    raise exception 'D2_A2_ROLE_MATRIX_ACL_INVALID';
  end if;
end
$acl$;

select 'PHASE2C_D2_A2_ROLE_MATRIX_PASS' result;
rollback;
