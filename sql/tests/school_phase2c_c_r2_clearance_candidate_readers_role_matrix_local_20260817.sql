-- Phase 2C-C-R2 local reader role matrix. No writes.
\set ON_ERROR_STOP on
\pset pager off
begin;

do $allowed$
declare v_actor uuid;v_payload jsonb;
begin
  foreach v_actor in array array[
    '90000000-0000-4000-8000-000000000001'::uuid,
    '90000000-0000-4000-8000-000000000002'::uuid,
    '90000000-0000-4000-8000-000000000003'::uuid
  ] loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    set local role authenticated;
    v_payload:=public.school_list_lesson_clearance_pending_balances_v2(null,false);
    if v_payload is null then raise exception 'R2_ALLOWED_ROLE_EMPTY:%',v_actor; end if;
    v_payload:=public.school_list_lesson_clearance_available_overages_v2(null,false);
    v_payload:=public.school_list_student_package_credit_lots_v2(null);
    v_payload:=public.school_list_cross_month_makeup_projection_v2(null,null);
    v_payload:=public.school_get_lesson_clearance_dashboard_summary_v1(null);
    reset role;
  end loop;
end
$allowed$;

do $denied_membership$
declare v_actor uuid;v_expected text;v_error text;
begin
  for v_actor,v_expected in select * from (values
    ('90000000-0000-4000-8000-000000000004'::uuid,'LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED'),
    ('90000000-0000-4000-8000-000000000099'::uuid,'LESSON_CLEARANCE_MEMBERSHIP_REQUIRED')
  ) denied(actor,expected) loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    set local role authenticated;
    begin
      perform public.school_list_lesson_clearance_pending_balances_v2(null,false);
      raise exception 'R2_DENIAL_MISSING';
    exception when others then
      get stacked diagnostics v_error=message_text;
      if v_error='R2_DENIAL_MISSING' or position(v_expected in v_error)=0 then raise; end if;
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
    perform public.school_list_lesson_clearance_pending_balances_v2(null,false);
    raise exception 'R2_AUTHLESS_DENIAL_MISSING';
  exception when others then
    get stacked diagnostics v_error=message_text;
    if v_error='R2_AUTHLESS_DENIAL_MISSING'
       or position('LESSON_CLEARANCE_AUTH_REQUIRED' in v_error)=0 then raise; end if;
  end;
  reset role;
end
$authless$;

do $acl$
declare v_signature regprocedure;
begin
  foreach v_signature in array array[
    'public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)'::regprocedure,
    'public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)'::regprocedure,
    'public.school_list_student_package_credit_lots_v2(uuid)'::regprocedure,
    'public.school_list_cross_month_makeup_projection_v2(uuid,text)'::regprocedure,
    'public.school_get_lesson_clearance_dashboard_summary_v1(uuid)'::regprocedure
  ] loop
    if has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE')
       or not has_function_privilege('authenticated',v_signature,'EXECUTE') then
      raise exception 'R2_ROLE_MATRIX_ACL_INVALID:%',v_signature;
    end if;
  end loop;
end
$acl$;

select 'PHASE2C_C_R2_ROLE_MATRIX_PASS' result;
rollback;
