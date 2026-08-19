-- Phase 3C3-B School fixed-attempt rollback-only matrix.
-- Caller owns BEGIN/ROLLBACK and installed the exact Phase 3C3-B core first.

do $history_unchanged$
begin
  if (select count(*) from phase3c3b_school_attempt_before b join public.school_expense_cash_attempts a using(id)) <> 24
     or exists (
       select 1 from phase3c3b_school_attempt_before b
       join public.school_expense_cash_attempts a on a.id=b.id
       where to_jsonb(a) is distinct from b.row_json
     ) then raise exception 'PHASE3C3B_SCHOOL_EXISTING_ATTEMPT_CHANGED'; end if;
end;
$history_unchanged$;

do $acl$
declare
  v_prepare regprocedure := 'public.school_request_cash_fixed_expense_payment_confirmation_v2(uuid,uuid,uuid,date,date,date,date,text,text,text,uuid,text,text,uuid,text)'::regprocedure;
  v_submitted regprocedure := 'public.school_mark_cash_fixed_expense_request_submitted_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid)'::regprocedure;
  v_rejected regprocedure := 'public.school_mark_cash_fixed_expense_rejected_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,timestamptz)'::regprocedure;
  v_core regprocedure := 'public.school_apply_expense_cash_fixed_attempt_transition_v2(text,uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,timestamptz,text)'::regprocedure;
begin
  if has_function_privilege('public',v_prepare,'EXECUTE') or has_function_privilege('anon',v_prepare,'EXECUTE') or has_function_privilege('authenticated',v_prepare,'EXECUTE') or not has_function_privilege('service_role',v_prepare,'EXECUTE') then raise exception 'PHASE3C3B_FIXED_PREPARE_ACL_INVALID'; end if;
  if has_function_privilege('public',v_submitted,'EXECUTE') or has_function_privilege('authenticated',v_submitted,'EXECUTE') or not has_function_privilege('service_role',v_submitted,'EXECUTE') then raise exception 'PHASE3C3B_FIXED_SUBMITTED_ACL_INVALID'; end if;
  if has_function_privilege('public',v_rejected,'EXECUTE') or has_function_privilege('authenticated',v_rejected,'EXECUTE') or not has_function_privilege('service_role',v_rejected,'EXECUTE') then raise exception 'PHASE3C3B_FIXED_REJECTED_ACL_INVALID'; end if;
  if has_function_privilege('public',v_core,'EXECUTE') or has_function_privilege('anon',v_core,'EXECUTE') or has_function_privilege('authenticated',v_core,'EXECUTE') or has_function_privilege('service_role',v_core,'EXECUTE') then raise exception 'PHASE3C3B_FIXED_CORE_ACL_INVALID'; end if;
end;
$acl$;

-- Reuse the rollback-only admin created by the immediate regression matrix.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub','c3200000-0000-4000-8000-000000000001','role','authenticated')::text,true);
create temp table phase3c3b_fixed_fixture as
select * from public.school_create_pending_cash_expense_record_v1(
  'c33b0000-0000-4000-8000-000000000201','2099-10-01',public.school_primary_business_entity_id(),
  'classroom','codex-test phase3c3b fixed','JPY',6100,'not_required',null,true,null,
  '待确认',null,null,'codex-test phase3c3b rollback-only'
);
insert into phase3c3b_fixed_fixture
select * from public.school_create_pending_cash_expense_record_v1(
  'c33b0000-0000-4000-8000-000000000202','2099-10-02',public.school_primary_business_entity_id(),
  'other','codex-test phase3c3b atomic','JPY',6200,'not_required',null,true,null,
  '待确认',null,null,'codex-test phase3c3b rollback-only'
);
reset role;

set local role service_role;
do $gate_blocked$
declare v_expense uuid; v_before jsonb;
begin
  select id,to_jsonb(e) into v_expense,v_before from public.school_expense_records e where cash_creation_event_id='c33b0000-0000-4000-8000-000000000201';
  begin
    perform * from public.school_request_cash_fixed_expense_payment_confirmation_v2(
      v_expense,'8596a708-d99f-4264-8f8c-5b89af9254b6','9b27347e-2dce-4caf-bac0-67f053ef6c3b',
      '2099-10-09','2099-10-01','2099-10-01','2099-10-25','blocked');
    raise exception 'PHASE3C3B_FIXED_GATE_DID_NOT_BLOCK';
  exception when sqlstate '55000' then if sqlerrm<>'SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED' then raise; end if; end;
  if (select to_jsonb(e) from public.school_expense_records e where id=v_expense) is distinct from v_before then
    raise exception 'PHASE3C3B_FIXED_GATE_PARTIAL_WRITE';
  end if;
end;
$gate_blocked$;
reset role;

do $gate_blocked_no_attempt$
declare v_expense uuid;
begin
  select id into v_expense from public.school_expense_records where cash_creation_event_id='c33b0000-0000-4000-8000-000000000201';
  if exists(select 1 from public.school_expense_cash_attempts where expense_id=v_expense) then
    raise exception 'PHASE3C3B_FIXED_GATE_CREATED_ATTEMPT';
  end if;
end;
$gate_blocked_no_attempt$;

update public.school_feature_gates set state='enabled',updated_at=now(),updated_by=current_user
where feature_key='cash_fixed_credit_card_route_enabled';

set local role service_role;
do $fixed_lifecycle$
declare
  v_expense uuid; p record; r record; s record; j record;
  v_request uuid := 'c33b0000-0000-4000-8000-000000000301';
  v_denied integer := 0;
begin
  select id into v_expense from public.school_expense_records where cash_creation_event_id='c33b0000-0000-4000-8000-000000000201';
  select * into p from public.school_request_cash_fixed_expense_payment_confirmation_v2(
    v_expense,'8596a708-d99f-4264-8f8c-5b89af9254b6','9b27347e-2dce-4caf-bac0-67f053ef6c3b',
    '2099-10-09','2099-10-01','2099-10-01','2099-10-25','fixed note');
  if p.payment_route<>'fixed_credit_card' or p.attempt_status<>'prepared' or p.attempt_version<>1
     or p.settlement_amount<>6100 or p.settlement_currency<>'JPY'
     or p.cash_payload_snapshot->>'account_id' is not null
     or p.cash_payload_snapshot->>'funding_account_id' is not null
     or p.cash_payload_snapshot->>'school_attempt_payload_fingerprint' is distinct from p.request_payload_fingerprint
     or length(p.request_payload_fingerprint)<>64 then raise exception 'PHASE3C3B_FIXED_PREPARE_INVALID'; end if;
  select * into r from public.school_request_cash_fixed_expense_payment_confirmation_v2(
    v_expense,'8596a708-d99f-4264-8f8c-5b89af9254b6','9b27347e-2dce-4caf-bac0-67f053ef6c3b',
    '2099-10-09','2099-10-01','2099-10-01','2099-10-25','fixed note',
    'aozora_school','school_expense_records',v_expense,'expense_paid','expense',p.request_event_id,p.idempotency_key);
  if r.attempt_id is distinct from p.attempt_id or r.attempt_version<>1 then raise exception 'PHASE3C3B_FIXED_PREPARE_REPLAY_INVALID'; end if;

  begin perform * from public.school_request_cash_fixed_expense_payment_confirmation_v2(v_expense,'8596a708-d99f-4264-8f8c-5b89af9254b6','9b27347e-2dce-4caf-bac0-67f053ef6c3b','2099-10-10','2099-10-01','2099-10-01','2099-10-25','fixed note');
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_FIXED_PREPARE_PAYLOAD_CONFLICT' then v_denied:=v_denied+1; else raise; end if; end;
  begin perform * from public.school_request_cash_fixed_expense_payment_confirmation_v2(v_expense,'8596a708-d99f-4264-8f8c-5b89af9254b6','c33b0000-0000-4000-8000-000000009999','2099-10-09','2099-10-01','2099-10-01','2099-10-25','fixed note');
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_FIXED_PREPARE_PAYLOAD_CONFLICT' then v_denied:=v_denied+1; else raise; end if; end;

  select * into s from public.school_mark_cash_fixed_expense_request_submitted_v2(
    v_expense,v_request,'pending','fixed_credit_card','aozora_school',p.request_event_id,p.idempotency_key,
    'school_expense_records',v_expense,'expense_paid','expense',6100,'JPY',p.card_instrument_id,
    p.charge_date,p.suggested_fixed_month,p.target_fixed_month,p.funding_date,null,null,p.request_payload_fingerprint,null,null);
  if s.attempt_status<>'submitted' or s.attempt_version<>2 or s.idempotent then raise exception 'PHASE3C3B_FIXED_SUBMITTED_INVALID'; end if;
  select * into r from public.school_mark_cash_fixed_expense_request_submitted_v2(
    v_expense,v_request,'pending','fixed_credit_card','aozora_school',p.request_event_id,p.idempotency_key,
    'school_expense_records',v_expense,'expense_paid','expense',6100,'JPY',p.card_instrument_id,
    p.charge_date,p.suggested_fixed_month,p.target_fixed_month,p.funding_date,null,null,p.request_payload_fingerprint,null,null);
  if not r.idempotent or r.attempt_version<>2 then raise exception 'PHASE3C3B_FIXED_SUBMITTED_REPLAY_INVALID'; end if;
  select * into r from public.school_request_cash_fixed_expense_payment_confirmation_v2(
    v_expense,'8596a708-d99f-4264-8f8c-5b89af9254b6','9b27347e-2dce-4caf-bac0-67f053ef6c3b',
    '2099-10-09','2099-10-01','2099-10-01','2099-10-25','fixed note',
    'aozora_school','school_expense_records',v_expense,'expense_paid','expense',p.request_event_id,p.idempotency_key);
  if r.attempt_id is distinct from p.attempt_id or r.attempt_status<>'submitted' or r.attempt_version<>2
     or r.cash_request_id is distinct from v_request then raise exception 'PHASE3C3B_FIXED_SUBMITTED_PREPARE_RETRY_INVALID'; end if;
  begin perform * from public.school_mark_cash_fixed_expense_request_submitted_v2(v_expense,v_request,'pending','fixed_credit_card','aozora_school',p.request_event_id,p.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',6101,'JPY',p.card_instrument_id,p.charge_date,p.suggested_fixed_month,p.target_fixed_month,p.funding_date,null,null,p.request_payload_fingerprint,null,null);
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_FIXED_PAYLOAD_CONFLICT' then v_denied:=v_denied+1; else raise; end if; end;
  begin perform * from public.school_mark_cash_fixed_expense_request_submitted_v2(v_expense,v_request,'pending','fixed_credit_card','aozora_school',p.request_event_id,p.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',6100,'JPY',p.card_instrument_id,p.charge_date,p.suggested_fixed_month,p.target_fixed_month,p.funding_date,'c33b0000-0000-4000-8000-000000000999',null,p.request_payload_fingerprint,null,null);
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_FIXED_EXTERNAL_IDENTITY_CONFLICT' then v_denied:=v_denied+1; else raise; end if; end;

  select * into j from public.school_mark_cash_fixed_expense_rejected_v2(
    v_expense,v_request,'rejected','fixed_credit_card','aozora_school',p.request_event_id,p.idempotency_key,
    'school_expense_records',v_expense,'expense_paid','expense',6100,'JPY',p.card_instrument_id,
    p.charge_date,p.suggested_fixed_month,p.target_fixed_month,p.funding_date,null,null,
    p.request_payload_fingerprint,null,null,'fixed rejected','2099-10-10 00:00:00+00');
  if j.attempt_status<>'rejected' or j.attempt_version<>3 or j.idempotent then raise exception 'PHASE3C3B_FIXED_REJECTED_INVALID'; end if;
  select * into r from public.school_mark_cash_fixed_expense_rejected_v2(
    v_expense,v_request,'rejected','fixed_credit_card','aozora_school',p.request_event_id,p.idempotency_key,
    'school_expense_records',v_expense,'expense_paid','expense',6100,'JPY',p.card_instrument_id,
    p.charge_date,p.suggested_fixed_month,p.target_fixed_month,p.funding_date,null,null,
    p.request_payload_fingerprint,null,null,'fixed rejected','2099-10-10 00:00:00+00');
  if not r.idempotent or r.attempt_version<>3 then raise exception 'PHASE3C3B_FIXED_REJECTED_REPLAY_INVALID'; end if;
  begin perform * from public.school_mark_cash_fixed_expense_rejected_v2(v_expense,v_request,'rejected','fixed_credit_card','aozora_school',p.request_event_id,p.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',6100,'JPY',p.card_instrument_id,p.charge_date,p.suggested_fixed_month,p.target_fixed_month,p.funding_date,null,null,p.request_payload_fingerprint,null,null,'different','2099-10-10 00:00:00+00');
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_REPLAY_CONFLICT' then v_denied:=v_denied+1; else raise; end if; end;

  select * into r from public.school_request_cash_fixed_expense_payment_confirmation_v2(
    v_expense,'8596a708-d99f-4264-8f8c-5b89af9254b6','9b27347e-2dce-4caf-bac0-67f053ef6c3b',
    '2099-11-09','2099-11-01','2099-11-01','2099-11-25','retry');
  if r.attempt_no<>2 or r.attempt_status<>'prepared' then raise exception 'PHASE3C3B_FIXED_NEW_ATTEMPT_INVALID'; end if;

  if v_denied<>5 then raise exception 'PHASE3C3B_FIXED_NEGATIVE_MATRIX_INCOMPLETE:%',v_denied; end if;
end;
$fixed_lifecycle$;
reset role;

do $future_states_closed$
declare v_attempt uuid; v_denied integer:=0;
begin
  select a.id into v_attempt
  from public.school_expense_cash_attempts a
  join public.school_expense_records e on e.id=a.expense_id
  where e.cash_creation_event_id='c33b0000-0000-4000-8000-000000000201'
  order by a.attempt_no desc limit 1;
  begin update public.school_expense_cash_attempts set attempt_status='approved_fixed',version=version+1 where id=v_attempt;
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_TRANSITION_FORBIDDEN' then v_denied:=v_denied+1; else raise; end if; end;
  begin update public.school_expense_cash_attempts set attempt_status='funded_fixed',version=version+1 where id=v_attempt;
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_TRANSITION_FORBIDDEN' then v_denied:=v_denied+1; else raise; end if; end;
  begin update public.school_expense_cash_attempts set attempt_status='corrected',version=version+1 where id=v_attempt;
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_TRANSITION_FORBIDDEN' then v_denied:=v_denied+1; else raise; end if; end;
  if v_denied<>3 then raise exception 'PHASE3C3B_FIXED_FUTURE_STATE_GATES_INCOMPLETE:%',v_denied; end if;
end;
$future_states_closed$;

-- Force failure on the expense half after the attempt UPDATE; both halves must roll back.
create function pg_temp.phase3c3b_force_expense_failure() returns trigger language plpgsql as $f$
begin
  if old.cash_creation_event_id='c33b0000-0000-4000-8000-000000000202'::uuid
     and old.cash_request_status='pending_cash_request' and new.cash_request_status='pending' then
    raise exception using errcode='55000',message='PHASE3C3B_FORCED_EXPENSE_FAILURE';
  end if;
  return new;
end;$f$;
create trigger phase3c3b_force_expense_failure before update on public.school_expense_records for each row execute function pg_temp.phase3c3b_force_expense_failure();

set local role service_role;
do $atomicity$
declare v_expense uuid; p record; v_failed boolean:=false;
begin
  select id into v_expense from public.school_expense_records where cash_creation_event_id='c33b0000-0000-4000-8000-000000000202';
  select * into p from public.school_request_cash_fixed_expense_payment_confirmation_v2(v_expense,'8596a708-d99f-4264-8f8c-5b89af9254b6','9b27347e-2dce-4caf-bac0-67f053ef6c3b','2099-12-09','2099-12-01','2099-12-01','2099-12-25','atomic');
  begin
    perform * from public.school_mark_cash_fixed_expense_request_submitted_v2(v_expense,'c33b0000-0000-4000-8000-000000000302','pending','fixed_credit_card','aozora_school',p.request_event_id,p.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',6200,'JPY',p.card_instrument_id,p.charge_date,p.suggested_fixed_month,p.target_fixed_month,p.funding_date,null,null,p.request_payload_fingerprint,null,null);
  exception when sqlstate '55000' then if sqlerrm='PHASE3C3B_FORCED_EXPENSE_FAILURE' then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'PHASE3C3B_FIXED_ATOMIC_FAILURE_NOT_RAISED'; end if;
end;
$atomicity$;
reset role;

do $atomicity_postcheck$
declare v_expense uuid;
begin
  select id into v_expense from public.school_expense_records where cash_creation_event_id='c33b0000-0000-4000-8000-000000000202';
  if not exists(select 1 from public.school_expense_cash_attempts where expense_id=v_expense and attempt_status='prepared' and version=1 and cash_request_id is null)
     or not exists(select 1 from public.school_expense_records where id=v_expense and cash_request_status='pending_cash_request' and cash_request_id is null) then
    raise exception 'PHASE3C3B_FIXED_ATOMIC_ROLLBACK_FAILED';
  end if;
end;
$atomicity_postcheck$;

select 'PHASE3C3B_SCHOOL_FIXED_ROLLBACK_MATRIX_PASS' result;
