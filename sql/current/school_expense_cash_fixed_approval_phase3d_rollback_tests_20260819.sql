-- Phase 3D School fixed callback rollback matrix.
-- Run after the Phase 3D production body in the same outer transaction.

create or replace function pg_temp.phase3d_create_expense(
  p_charge_date date,
  p_amount numeric,
  p_marker text
)
returns uuid
language plpgsql
as $function$
declare
  v_id uuid := gen_random_uuid();
  v_user uuid := (select id from auth.users order by created_at limit 1);
begin
  insert into public.school_expense_records(
    id,expense_date,year_month,expense_category,description,currency,amount,
    amount_jpy,status,note,app_type,source_type,payee_name_snapshot,
    cash_creation_event_id,created_by_user_id
  ) values (
    v_id,p_charge_date,to_char(p_charge_date,'YYYY-MM'),'classroom',p_marker,
    'JPY',p_amount,p_amount,'pending',p_marker,'school','manual_cash',
    'Phase 3D test payee',gen_random_uuid(),v_user
  );
  return v_id;
end;
$function$;

create or replace function pg_temp.phase3d_prepare_fixed(
  p_expense uuid,
  p_card uuid,
  p_charge date,
  p_month date,
  p_funding date
)
returns jsonb
language plpgsql
as $function$
declare v_result jsonb;
begin
  select to_jsonb(x) into v_result
  from public.school_request_cash_fixed_expense_payment_confirmation_v2(
    p_expense,gen_random_uuid(),p_card,p_charge,p_month,p_month,p_funding,
    'phase3d','aozora_school','school_expense_records',p_expense,
    'expense_paid','expense',null,null
  ) x;
  return v_result;
end;
$function$;

create or replace function pg_temp.phase3d_submit_fixed(
  p_prepare jsonb,
  p_request uuid
)
returns jsonb
language plpgsql
as $function$
declare v_result jsonb;
begin
  select to_jsonb(x) into v_result
  from public.school_mark_cash_fixed_expense_request_submitted_v2(
    (p_prepare->>'expense_id')::uuid,p_request,'pending','fixed_credit_card',
    'aozora_school',(p_prepare->>'request_event_id')::uuid,p_prepare->>'idempotency_key',
    'school_expense_records',(p_prepare->>'expense_id')::uuid,'expense_paid','expense',
    (p_prepare->>'settlement_amount')::numeric,p_prepare->>'settlement_currency',
    (p_prepare->>'card_instrument_id')::uuid,(p_prepare->>'charge_date')::date,
    (p_prepare->>'suggested_fixed_month')::date,(p_prepare->>'target_fixed_month')::date,
    (p_prepare->>'funding_date')::date,null,null,p_prepare->>'request_payload_fingerprint',
    null,null
  ) x;
  return v_result;
end;
$function$;

create or replace function pg_temp.phase3d_approve_fixed(
  p_prepare jsonb,
  p_request uuid,
  p_projection uuid,
  p_item uuid,
  p_channel uuid,
  p_group text,
  p_approved_at timestamptz,
  p_scope text default 'school',
  p_item_amount numeric default null
)
returns jsonb
language plpgsql
as $function$
declare v_result jsonb;
begin
  select to_jsonb(x) into v_result
  from public.school_mark_cash_fixed_expense_approved_v2(
    (p_prepare->>'expense_id')::uuid,p_request,'approved','fixed_credit_card',
    'aozora_school',(p_prepare->>'request_event_id')::uuid,p_prepare->>'idempotency_key',
    'school_expense_records',(p_prepare->>'expense_id')::uuid,'expense_paid','expense',
    (p_prepare->>'original_amount')::numeric,p_prepare->>'original_currency',
    (p_prepare->>'settlement_amount')::numeric,p_prepare->>'settlement_currency',
    (p_prepare->>'card_instrument_id')::uuid,(p_prepare->>'charge_date')::date,
    (p_prepare->>'suggested_fixed_month')::date,(p_prepare->>'target_fixed_month')::date,
    (p_prepare->>'funding_date')::date,null,null,p_prepare->>'request_payload_fingerprint',
    null,p_projection,'projected',1,'unfunded',p_channel,null,p_item,null,p_scope,
    'JPY','expense',coalesce(p_item_amount,(p_prepare->>'settlement_amount')::numeric),
    to_char((p_prepare->>'target_fixed_month')::date,'YYYY-MM'),
    (p_prepare->>'funding_date')::date,p_group,'unpaid',null,null,null,
    gen_random_uuid(),p_approved_at
  ) x;
  return v_result;
end;
$function$;

do $test$
declare
  v_card constant uuid := '9b27347e-2dce-4caf-bac0-67f053ef6c3b';
  v_channel constant uuid := '53af0c53-03d3-477a-944e-a9bdfbe441fc';
  v_group constant text := '邮局卡';
  v_expense uuid;
  v_request uuid;
  v_projection uuid;
  v_item uuid;
  v_prepare jsonb;
  v_immediate jsonb;
  v_result jsonb;
  v_at timestamptz;
  v_attempt_before text := (
    select md5(string_agg(to_jsonb(a)::text,'|' order by a.id))
    from public.school_expense_cash_attempts a
  );
  v_expense_before text := (
    select md5(string_agg(to_jsonb(e)::text,'|' order by e.id))
    from public.school_expense_records e
  );
begin
  -- 23/26: submitted -> approved_fixed, exact replay and expense mirror.
  update public.school_feature_gates set state='enabled'
  where feature_key='cash_fixed_credit_card_route_enabled';
  v_expense := pg_temp.phase3d_create_expense('2099-01-09',7101,'phase3d normal');
  v_prepare := pg_temp.phase3d_prepare_fixed(v_expense,v_card,'2099-01-09','2099-01-01','2099-01-25');
  v_request := gen_random_uuid(); v_projection := gen_random_uuid(); v_item := gen_random_uuid();
  v_result := pg_temp.phase3d_submit_fixed(v_prepare,v_request);
  if v_result->>'attempt_status'<>'submitted' or (v_result->>'attempt_version')::int<>2 then
    raise exception 'PHASE3D_SCHOOL_SUBMITTED_FAILED: %',v_result;
  end if;
  update public.school_feature_gates set state='blocked'
  where feature_key='cash_fixed_credit_card_route_enabled';
  v_at := '2099-01-10 01:02:03+00';
  v_result := pg_temp.phase3d_approve_fixed(v_prepare,v_request,v_projection,v_item,v_channel,v_group,v_at);
  if v_result->>'attempt_status'<>'approved_fixed'
     or (v_result->>'attempt_version')::int<>3
     or (v_result->>'callback_recovered_from_prepared')::boolean
     or v_result->>'expense_status'<>'paid'
     or v_result->>'cash_request_status'<>'approved'
     or v_result->>'cash_transaction_id' is not null
     or (v_result->>'fixed_projection_id')::uuid<>v_projection
     or (v_result->>'fixed_item_id')::uuid<>v_item
     or (select expense_date from public.school_expense_records where id=v_expense)<>'2099-01-09' then
    raise exception 'PHASE3D_SCHOOL_APPROVED_FAILED: %',v_result;
  end if;
  v_result := pg_temp.phase3d_approve_fixed(v_prepare,v_request,v_projection,v_item,v_channel,v_group,v_at);
  if not (v_result->>'idempotent')::boolean or (v_result->>'attempt_version')::int<>3 then
    raise exception 'PHASE3D_SCHOOL_APPROVED_REPLAY_FAILED: %',v_result;
  end if;

  -- 27/28: mismatched callback conflicts and approved_fixed cannot reject.
  begin
    perform pg_temp.phase3d_approve_fixed(v_prepare,v_request,v_projection,gen_random_uuid(),v_channel,v_group,v_at);
    raise exception 'PHASE3D_SCHOOL_MISMATCH_NOT_BLOCKED';
  exception when others then
    if sqlerrm='PHASE3D_SCHOOL_MISMATCH_NOT_BLOCKED' then raise; end if;
  end;
  begin
    perform * from public.school_mark_cash_fixed_expense_rejected_v2(
      v_expense,v_request,'rejected','fixed_credit_card','aozora_school',
      (v_prepare->>'request_event_id')::uuid,v_prepare->>'idempotency_key',
      'school_expense_records',v_expense,'expense_paid','expense',7101,'JPY',v_card,
      '2099-01-09','2099-01-01','2099-01-01','2099-01-25',null,null,
      v_prepare->>'request_payload_fingerprint',null,null,'bad','2099-01-11');
    raise exception 'PHASE3D_SCHOOL_APPROVED_REJECT_NOT_BLOCKED';
  exception when others then
    if sqlerrm='PHASE3D_SCHOOL_APPROVED_REJECT_NOT_BLOCKED' then raise; end if;
  end;

  -- 24: prepared -> submitted -> approved_fixed semantic recovery (+2).
  update public.school_feature_gates set state='enabled' where feature_key='cash_fixed_credit_card_route_enabled';
  v_expense := pg_temp.phase3d_create_expense('2099-02-09',7201,'phase3d approved recovery');
  v_prepare := pg_temp.phase3d_prepare_fixed(v_expense,v_card,'2099-02-09','2099-02-01','2099-02-25');
  update public.school_feature_gates set state='blocked' where feature_key='cash_fixed_credit_card_route_enabled';
  v_request:=gen_random_uuid(); v_projection:=gen_random_uuid(); v_item:=gen_random_uuid(); v_at:='2099-02-10 00:00:00+00';
  v_result := pg_temp.phase3d_approve_fixed(v_prepare,v_request,v_projection,v_item,v_channel,v_group,v_at);
  if v_result->>'attempt_status'<>'approved_fixed'
     or (v_result->>'attempt_version')::int<>3
     or not (v_result->>'callback_recovered_from_prepared')::boolean then
    raise exception 'PHASE3D_SCHOOL_APPROVED_RECOVERY_FAILED: %',v_result;
  end if;

  -- 25: prepared -> submitted -> rejected semantic recovery (+2), Gate blocked.
  update public.school_feature_gates set state='enabled' where feature_key='cash_fixed_credit_card_route_enabled';
  v_expense := pg_temp.phase3d_create_expense('2099-03-09',7301,'phase3d reject recovery');
  v_prepare := pg_temp.phase3d_prepare_fixed(v_expense,v_card,'2099-03-09','2099-03-01','2099-03-25');
  update public.school_feature_gates set state='blocked' where feature_key='cash_fixed_credit_card_route_enabled';
  v_request:=gen_random_uuid();
  select to_jsonb(x) into v_result
  from public.school_mark_cash_fixed_expense_rejected_v2(
    v_expense,v_request,'rejected','fixed_credit_card','aozora_school',
    (v_prepare->>'request_event_id')::uuid,v_prepare->>'idempotency_key',
    'school_expense_records',v_expense,'expense_paid','expense',7301,'JPY',v_card,
    '2099-03-09','2099-03-01','2099-03-01','2099-03-25',null,null,
    v_prepare->>'request_payload_fingerprint',null,null,'phase3d rejected','2099-03-10') x;
  if v_result->>'attempt_status'<>'rejected'
     or (v_result->>'attempt_version')::int<>3
     or not (select callback_recovered_from_prepared from public.school_expense_cash_attempts where expense_id=v_expense) then
    raise exception 'PHASE3D_SCHOOL_REJECT_RECOVERY_FAILED: %',v_result;
  end if;

  -- Full approval evidence rejects wrong scope and amount before state writes.
  update public.school_feature_gates set state='enabled' where feature_key='cash_fixed_credit_card_route_enabled';
  v_expense := pg_temp.phase3d_create_expense('2099-04-09',7401,'phase3d evidence conflict');
  v_prepare := pg_temp.phase3d_prepare_fixed(v_expense,v_card,'2099-04-09','2099-04-01','2099-04-25');
  v_request:=gen_random_uuid(); v_projection:=gen_random_uuid(); v_item:=gen_random_uuid();
  perform pg_temp.phase3d_submit_fixed(v_prepare,v_request);
  update public.school_feature_gates set state='blocked' where feature_key='cash_fixed_credit_card_route_enabled';
  begin
    perform pg_temp.phase3d_approve_fixed(v_prepare,v_request,v_projection,v_item,v_channel,v_group,'2099-04-10','household',7402);
    raise exception 'PHASE3D_SCHOOL_BAD_EVIDENCE_NOT_BLOCKED';
  exception when others then
    if sqlerrm='PHASE3D_SCHOOL_BAD_EVIDENCE_NOT_BLOCKED' then raise; end if;
  end;
  if not exists(select 1 from public.school_expense_cash_attempts where expense_id=v_expense and attempt_status='submitted' and version=2) then
    raise exception 'PHASE3D_SCHOOL_BAD_EVIDENCE_CHANGED_STATE';
  end if;

  -- 29: immediate submitted/approved path still passes through the replaced
  -- shared trigger without any fixed identity or version regression.
  v_expense := pg_temp.phase3d_create_expense('2099-05-09',7501,'phase3d immediate regression');
  select to_jsonb(x) into v_immediate
  from public.school_request_cash_expense_payment_confirmation_v2(
    v_expense,gen_random_uuid(),gen_random_uuid(),'Phase 3D Cash account','2099-05-09',
    'cash',7501,'JPY','phase3d',null,null,'aozora_school','school_expense_records',
    v_expense,'expense_paid','expense',null,null
  ) x;
  v_request := gen_random_uuid();
  select to_jsonb(x) into v_result
  from public.school_mark_cash_expense_request_submitted_v2(
    v_expense,v_request,'pending','aozora_school',(v_immediate->>'request_event_id')::uuid,
    v_immediate->>'idempotency_key','school_expense_records',v_expense,'expense_paid',
    'expense',7501,'JPY',(v_immediate->>'cash_account_id')::uuid,'2099-05-09',
    v_immediate->>'request_payload_fingerprint'
  ) x;
  if v_result->>'attempt_status'<>'submitted' or (v_result->>'attempt_version')::int<>2 then
    raise exception 'PHASE3D_IMMEDIATE_SUBMITTED_REGRESSION: %',v_result;
  end if;
  select to_jsonb(x) into v_result
  from public.school_mark_cash_expense_confirmed_v2(
    v_expense,v_request,'approved','aozora_school',(v_immediate->>'request_event_id')::uuid,
    v_immediate->>'idempotency_key','school_expense_records',v_expense,'expense_paid',
    'expense',7501,'JPY',(v_immediate->>'cash_account_id')::uuid,'2099-05-09',
    v_immediate->>'request_payload_fingerprint',gen_random_uuid(),'2099-05-10',null
  ) x;
  if v_result->>'attempt_status'<>'approved_immediate'
     or (v_result->>'attempt_version')::int<>3
     or v_result->>'expense_status'<>'paid'
     or v_result->>'cash_transaction_id' is null then
    raise exception 'PHASE3D_IMMEDIATE_APPROVED_REGRESSION: %',v_result;
  end if;

  if (select state from public.school_feature_gates where feature_key='cash_fixed_credit_card_route_enabled')<>'blocked' then
    raise exception 'PHASE3D_SCHOOL_FIXED_GATE_NOT_RESTORED';
  end if;
end;
$test$;

-- 29/31: existing immediate definitions/ACL stay unchanged; new fixed writer is
-- service-only and owner-only core/trigger remain uncallable.
do $acl$
begin
  if has_function_privilege('anon',
       'public.school_mark_cash_fixed_expense_approved_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz)','EXECUTE')
     or has_function_privilege('authenticated',
       'public.school_mark_cash_fixed_expense_approved_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz)','EXECUTE')
     or not has_function_privilege('service_role',
       'public.school_mark_cash_fixed_expense_approved_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz)','EXECUTE')
     or has_function_privilege('service_role',
       'public.school_apply_expense_cash_fixed_callback_v3(text,uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz,text)','EXECUTE') then
    raise exception 'PHASE3D_SCHOOL_ACL_INVALID';
  end if;
end;
$acl$;

select 'PHASE3D_SCHOOL_ROLLBACK_MATRIX_PASS' as result;
