-- Phase 3C2-R rollback-only functional, idempotency, recovery, ACL and atomicity matrix.
-- The caller owns BEGIN/ROLLBACK and creates phase3c2r_attempt_before / expense_before.

do $history_backfill_check$
begin
  if (select count(*) from public.school_expense_cash_attempts) <> 24
     or (select count(*) from public.school_expense_cash_attempts where payment_amount > 0 and payment_currency in ('JPY','CNY') and length(request_payload_fingerprint)=64) <> 24
     or exists (select 1 from public.school_expense_cash_attempts where callback_recovered_from_prepared) then
    raise exception 'PHASE3C2R_HISTORY_BACKFILL_INVALID';
  end if;
  if exists (
    select 1
    from phase3c2r_attempt_before b
    join public.school_expense_cash_attempts a on a.id=b.id
    where (to_jsonb(a) - array[
      'payment_amount','payment_currency','request_payload_fingerprint',
      'callback_recovered_from_prepared','callback_recovered_at','callback_recovery_source'
    ]) is distinct from b.row_json
  ) then
    raise exception 'PHASE3C2R_HISTORY_EXISTING_FIELDS_CHANGED';
  end if;
end;
$history_backfill_check$;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values(
  'c3200000-0000-4000-8000-000000000001','authenticated','authenticated',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"codex_test":"phase3c2r-rollback-admin"}'::jsonb,now(),now()
);
insert into public.school_app_memberships(user_id,role,is_active,created_by_user_id,updated_by_user_id,note)
values(
  'c3200000-0000-4000-8000-000000000001','admin',true,
  'c3200000-0000-4000-8000-000000000001','c3200000-0000-4000-8000-000000000001',
  'codex-test phase3c2r rollback-only'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub','c3200000-0000-4000-8000-000000000001','role','authenticated')::text,
  true
);

create temp table phase3c2r_fixture_expenses as
select * from public.school_create_pending_cash_expense_record_v1(
  'c3200000-0000-4000-8000-000000000101','2099-01-01',public.school_primary_business_entity_id(),
  'other','codex-test phase3c2r approve','JPY',1000,'not_required',null,true,null,
  '待确认',null,null,'codex-test phase3c2r rollback-only'
);
insert into phase3c2r_fixture_expenses
select * from public.school_create_pending_cash_expense_record_v1(
  'c3200000-0000-4000-8000-000000000102','2099-01-02',public.school_primary_business_entity_id(),
  'other','codex-test phase3c2r reject-retry','JPY',2000,'not_required',null,true,null,
  '待确认',null,null,'codex-test phase3c2r rollback-only'
);
insert into phase3c2r_fixture_expenses
select * from public.school_create_pending_cash_expense_record_v1(
  'c3200000-0000-4000-8000-000000000103','2099-01-03',public.school_primary_business_entity_id(),
  'other','codex-test phase3c2r approved recovery','JPY',3000,'not_required',null,true,null,
  '待确认',null,null,'codex-test phase3c2r rollback-only'
);
insert into phase3c2r_fixture_expenses
select * from public.school_create_pending_cash_expense_record_v1(
  'c3200000-0000-4000-8000-000000000104','2099-01-04',public.school_primary_business_entity_id(),
  'other','codex-test phase3c2r rejected recovery','JPY',4000,'not_required',null,true,null,
  '待确认',null,null,'codex-test phase3c2r rollback-only'
);
insert into phase3c2r_fixture_expenses
select * from public.school_create_pending_cash_expense_record_v1(
  'c3200000-0000-4000-8000-000000000105','2099-01-05',public.school_primary_business_entity_id(),
  'other','codex-test phase3c2r atomic rollback','JPY',5000,'not_required',null,true,null,
  '待确认',null,null,'codex-test phase3c2r rollback-only'
);
reset role;

update public.school_feature_gates
set state='enabled',updated_at=now(),updated_by=current_user
where feature_key='cash_expense_attempt_writer_v2_enabled' and state='blocked';

set local role service_role;

do $approve_matrix$
declare
  v_expense uuid;
  v_prepare record; v_retry record; v_submitted record; v_replay record; v_approved record;
  v_conflicts integer := 0;
begin
  -- Select by deterministic creation event rather than generated expense UUID order.
  select e.id into v_expense from public.school_expense_records e where e.cash_creation_event_id='c3200000-0000-4000-8000-000000000101';
  select * into v_prepare from public.school_request_cash_expense_payment_confirmation_v2(
    v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301',
    'codex-test Cash JPY','2099-01-25','cash',1000,'JPY','phase3c2r',1,null,
    'aozora_school','school_expense_records',v_expense,'expense_paid','expense',null,null
  );
  if v_prepare.attempt_status<>'prepared' or v_prepare.attempt_version<>1
     or v_prepare.actual_payment_date<>'2099-01-25'::date
     or v_prepare.payment_amount<>1000 or v_prepare.payment_currency<>'JPY'
     or length(v_prepare.request_payload_fingerprint)<>64
     or v_prepare.cash_payload_snapshot->>'school_attempt_payload_fingerprint' is distinct from v_prepare.request_payload_fingerprint then
    raise exception 'PHASE3C2R_PREPARE_RESULT_INVALID';
  end if;

  select * into v_retry from public.school_request_cash_expense_payment_confirmation_v2(
    v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301',
    'codex-test Cash JPY','2099-01-25','cash',1000,'JPY','phase3c2r',1,null,
    'aozora_school','school_expense_records',v_expense,'expense_paid','expense',
    v_prepare.request_event_id,v_prepare.idempotency_key
  );
  if v_retry.attempt_id is distinct from v_prepare.attempt_id or v_retry.attempt_version<>1 then raise exception 'PHASE3C2R_PREPARE_RETRY_NOT_IDEMPOTENT'; end if;

  begin
    perform * from public.school_request_cash_expense_payment_confirmation_v2(
      v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301',
      'codex-test Cash JPY','2099-01-25','cash',1001,'JPY','phase3c2r',1
    );
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_PREPARE_V2_PAYLOAD_CONFLICT' then v_conflicts:=v_conflicts+1; else raise; end if; end;
  begin
    perform * from public.school_request_cash_expense_payment_confirmation_v2(
      v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301',
      'codex-test Cash JPY','2099-01-25','cash',1000,'CNY','phase3c2r',0.05
    );
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_PREPARE_V2_PAYLOAD_CONFLICT' then v_conflicts:=v_conflicts+1; else raise; end if; end;
  begin
    perform * from public.school_request_cash_expense_payment_confirmation_v2(
      v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000302',
      'codex-test Cash JPY 2','2099-01-25','cash',1000,'JPY','phase3c2r',1
    );
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_PREPARE_V2_PAYLOAD_CONFLICT' then v_conflicts:=v_conflicts+1; else raise; end if; end;
  begin
    perform * from public.school_request_cash_expense_payment_confirmation_v2(
      v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301',
      'codex-test Cash JPY','2099-01-26','cash',1000,'JPY','phase3c2r',1
    );
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_PREPARE_V2_PAYLOAD_CONFLICT' then v_conflicts:=v_conflicts+1; else raise; end if; end;
  begin
    perform * from public.school_request_cash_expense_payment_confirmation_v2(
      v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301',
      'codex-test Cash JPY','2099-01-25','cash',1000,'JPY','phase3c2r',1,null,
      'aozora_school','school_expense_records','c3200000-0000-4000-8000-000000009999'
    );
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_ATTEMPT_EXTERNAL_IDENTITY_CONFLICT' then v_conflicts:=v_conflicts+1; else raise; end if; end;
  if v_conflicts<>5 then raise exception 'PHASE3C2R_PREPARE_CONFLICT_MATRIX_INCOMPLETE:%',v_conflicts; end if;

  select * into v_submitted from public.school_mark_cash_expense_request_submitted_v2(
    v_expense,'c3200000-0000-4000-8000-000000000401','pending','aozora_school',
    v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,
    'expense_paid','expense',1000,'JPY','c3200000-0000-4000-8000-000000000301',
    '2099-01-25',v_prepare.request_payload_fingerprint
  );
  if v_submitted.attempt_status<>'submitted' or v_submitted.attempt_version<>2 or v_submitted.idempotent then raise exception 'PHASE3C2R_SUBMITTED_INVALID'; end if;
  select * into v_replay from public.school_mark_cash_expense_request_submitted_v2(
    v_expense,'c3200000-0000-4000-8000-000000000401','pending','aozora_school',
    v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,
    'expense_paid','expense',1000,'JPY','c3200000-0000-4000-8000-000000000301',
    '2099-01-25',v_prepare.request_payload_fingerprint
  );
  if not v_replay.idempotent or v_replay.attempt_version<>2 then raise exception 'PHASE3C2R_SUBMITTED_REPLAY_INVALID'; end if;

  select * into v_approved from public.school_mark_cash_expense_confirmed_v2(
    v_expense,'c3200000-0000-4000-8000-000000000401','approved','aozora_school',
    v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,
    'expense_paid','expense',1000,'JPY','c3200000-0000-4000-8000-000000000301',
    '2099-01-25',v_prepare.request_payload_fingerprint,'c3200000-0000-4000-8000-000000000501','2099-01-26',null
  );
  if v_approved.attempt_status<>'approved_immediate' or v_approved.attempt_version<>3 or v_approved.expense_status<>'paid' then raise exception 'PHASE3C2R_APPROVED_INVALID'; end if;
  select * into v_replay from public.school_mark_cash_expense_confirmed_v2(
    v_expense,'c3200000-0000-4000-8000-000000000401','approved','aozora_school',
    v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,
    'expense_paid','expense',1000,'JPY','c3200000-0000-4000-8000-000000000301',
    '2099-01-25',v_prepare.request_payload_fingerprint,'c3200000-0000-4000-8000-000000000501','2099-01-26',null
  );
  if not v_replay.idempotent or v_replay.attempt_version<>3 then raise exception 'PHASE3C2R_APPROVED_REPLAY_INVALID'; end if;
  begin
    perform * from public.school_mark_cash_expense_rejected_v2(
      v_expense,'c3200000-0000-4000-8000-000000000401','rejected','aozora_school',v_prepare.request_event_id,v_prepare.idempotency_key,
      'school_expense_records',v_expense,'expense_paid','expense',1000,'JPY','c3200000-0000-4000-8000-000000000301','2099-01-25',v_prepare.request_payload_fingerprint,'no','2099-01-26',null
    );
  exception when sqlstate '55000' then if sqlerrm<>'SCHOOL_EXPENSE_CASH_ATTEMPT_APPROVED_CANNOT_REJECT' then raise; end if; end;
end;
$approve_matrix$;

reset role;

do $reject_retry_matrix$
declare
  v_expense uuid; v_prepare record; v_rejected record; v_retry record; v_second record;
begin
  select id into v_expense from public.school_expense_records where cash_creation_event_id='c3200000-0000-4000-8000-000000000102';
  select * into v_prepare from public.school_request_cash_expense_payment_confirmation_v2(v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301','codex-test Cash JPY','2099-02-25','cash',2000,'JPY','phase3c2r',1);
  perform * from public.school_mark_cash_expense_request_submitted_v2(v_expense,'c3200000-0000-4000-8000-000000000402','pending','aozora_school',v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',2000,'JPY','c3200000-0000-4000-8000-000000000301','2099-02-25',v_prepare.request_payload_fingerprint);
  select * into v_rejected from public.school_mark_cash_expense_rejected_v2(v_expense,'c3200000-0000-4000-8000-000000000402','rejected','aozora_school',v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',2000,'JPY','c3200000-0000-4000-8000-000000000301','2099-02-25',v_prepare.request_payload_fingerprint,'codex reject','2099-02-26',null);
  select * into v_retry from public.school_mark_cash_expense_rejected_v2(v_expense,'c3200000-0000-4000-8000-000000000402','rejected','aozora_school',v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',2000,'JPY','c3200000-0000-4000-8000-000000000301','2099-02-25',v_prepare.request_payload_fingerprint,'codex reject','2099-02-26',null);
  if v_rejected.attempt_version<>3 or not v_retry.idempotent or v_retry.attempt_version<>3 then raise exception 'PHASE3C2R_REJECT_REPLAY_INVALID'; end if;
  select * into v_second from public.school_request_cash_expense_payment_confirmation_v2(v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000302','codex-test Cash JPY 2','2099-03-25','cash',2100,'JPY','phase3c2r second',1);
  if v_second.attempt_no<>2 or v_second.request_event_id=v_prepare.request_event_id or v_second.idempotency_key=v_prepare.idempotency_key then raise exception 'PHASE3C2R_REJECTED_NEW_ATTEMPT_INVALID'; end if;
  if not exists(select 1 from public.school_expense_cash_attempts where id=v_prepare.attempt_id and payment_amount=2000 and charge_date='2099-02-25' and attempt_status='rejected') then raise exception 'PHASE3C2R_OLD_ATTEMPT_SNAPSHOT_CHANGED'; end if;
end;
$reject_retry_matrix$;

do $callback_recovery_matrix$
declare
  v_expense uuid; v_prepare record; v_result record; v_denied boolean := false;
begin
  select id into v_expense from public.school_expense_records where cash_creation_event_id='c3200000-0000-4000-8000-000000000103';
  select * into v_prepare from public.school_request_cash_expense_payment_confirmation_v2(v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301','codex-test Cash JPY','2099-04-25','cash',3000,'JPY','phase3c2r',1);
  begin
    perform * from public.school_mark_cash_expense_confirmed_v2(v_expense,'c3200000-0000-4000-8000-000000000403','approved','aozora_school',v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',3001,'JPY','c3200000-0000-4000-8000-000000000301','2099-04-25',v_prepare.request_payload_fingerprint,'c3200000-0000-4000-8000-000000000503','2099-04-26','sync-cash-request-result-v2');
  exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_ATTEMPT_PAYLOAD_CONFLICT' then v_denied:=true; else raise; end if; end;
  if not v_denied then raise exception 'PHASE3C2R_BAD_RECOVERY_ACCEPTED'; end if;
  select * into v_result from public.school_mark_cash_expense_confirmed_v2(v_expense,'c3200000-0000-4000-8000-000000000403','approved','aozora_school',v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',3000,'JPY','c3200000-0000-4000-8000-000000000301','2099-04-25',v_prepare.request_payload_fingerprint,'c3200000-0000-4000-8000-000000000503','2099-04-26','sync-cash-request-result-v2');
  if not v_result.callback_recovered_from_prepared or v_result.attempt_version<>3 or v_result.attempt_status<>'approved_immediate' then raise exception 'PHASE3C2R_APPROVED_RECOVERY_INVALID'; end if;

  select id into v_expense from public.school_expense_records where cash_creation_event_id='c3200000-0000-4000-8000-000000000104';
  select * into v_prepare from public.school_request_cash_expense_payment_confirmation_v2(v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301','codex-test Cash JPY','2099-05-25','cash',4000,'JPY','phase3c2r',1);
  select * into v_result from public.school_mark_cash_expense_rejected_v2(v_expense,'c3200000-0000-4000-8000-000000000404','rejected','aozora_school',v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',4000,'JPY','c3200000-0000-4000-8000-000000000301','2099-05-25',v_prepare.request_payload_fingerprint,'codex recovery reject','2099-05-26','sync-cash-request-result-v2');
  if not v_result.callback_recovered_from_prepared or v_result.attempt_version<>3 or v_result.attempt_status<>'rejected' then raise exception 'PHASE3C2R_REJECTED_RECOVERY_INVALID'; end if;
end;
$callback_recovery_matrix$;

do $negative_acl_fixed_matrix$
declare v_denied integer := 0; v_expense uuid; v_prepare record;
begin
  select id into v_expense from public.school_expense_records where cash_creation_event_id='c3200000-0000-4000-8000-000000000105';
  select * into v_prepare from public.school_request_cash_expense_payment_confirmation_v2(v_expense,'c3200000-0000-4000-8000-000000000201','c3200000-0000-4000-8000-000000000301','codex-test Cash JPY','2099-06-25','cash',5000,'JPY','phase3c2r',1);
  begin perform * from public.school_mark_cash_expense_request_submitted_v2(v_expense,'c3200000-0000-4000-8000-000000000405','pending','aozora_school',v_prepare.request_event_id,v_prepare.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',5000,'JPY','c3200000-0000-4000-8000-000000000301','2099-06-25',repeat('0',64)); exception when sqlstate '55000' then v_denied:=v_denied+1; end;
  begin perform * from public.school_mark_cash_expense_request_submitted(v_expense,'c3200000-0000-4000-8000-000000000405','pending'); exception when sqlstate '55000' then if sqlerrm='SCHOOL_EXPENSE_CASH_LEGACY_RPC_DISABLED' then v_denied:=v_denied+1; else raise; end if; end;
  begin insert into public.school_expense_cash_attempts(expense_id,attempt_no,payment_route,request_type,request_event_id,idempotency_key,cash_card_instrument_id,cash_funding_account_id,original_amount,original_currency,payment_amount,payment_currency,charge_date,suggested_fixed_month,target_fixed_month,funding_date,attempt_status) values(v_expense,99,'fixed_credit_card','expense_paid',gen_random_uuid(),'phase3c2r-fixed-blocked','c3200000-0000-4000-8000-000000000601','c3200000-0000-4000-8000-000000000301',5000,'JPY',5000,'JPY','2099-06-25','2099-07-01','2099-07-01','2099-07-25','prepared'); exception when sqlstate '55000' then if sqlerrm='SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED' then v_denied:=v_denied+1; else raise; end if; end;
  if v_denied<>3 then raise exception 'PHASE3C2R_NEGATIVE_MATRIX_INCOMPLETE:%',v_denied; end if;
end;
$negative_acl_fixed_matrix$;

reset role;

do $acl_matrix$
declare
  v_prepare regprocedure := 'public.school_request_cash_expense_payment_confirmation_v2(uuid,uuid,uuid,text,date,text,numeric,text,text,numeric,text,text,text,uuid,text,text,uuid,text)'::regprocedure;
  v_core regprocedure := 'public.school_apply_expense_cash_attempt_transition_v2(text,uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,uuid,timestamptz,text,text)'::regprocedure;
begin
  if has_function_privilege('public',v_prepare,'EXECUTE') or has_function_privilege('anon',v_prepare,'EXECUTE') or has_function_privilege('authenticated',v_prepare,'EXECUTE') or not has_function_privilege('service_role',v_prepare,'EXECUTE') then raise exception 'PHASE3C2R_PREPARE_ACL_INVALID'; end if;
  if has_function_privilege('public',v_core,'EXECUTE') or has_function_privilege('anon',v_core,'EXECUTE') or has_function_privilege('authenticated',v_core,'EXECUTE') or has_function_privilege('service_role',v_core,'EXECUTE') then raise exception 'PHASE3C2R_CORE_ACL_INVALID'; end if;
  if has_table_privilege('anon','public.school_expense_cash_attempts','INSERT,UPDATE,DELETE') or has_table_privilege('authenticated','public.school_expense_cash_attempts','INSERT,UPDATE,DELETE') or has_table_privilege('service_role','public.school_expense_cash_attempts','INSERT,UPDATE,DELETE') then raise exception 'PHASE3C2R_ATTEMPT_DML_ACL_INVALID'; end if;
end;
$acl_matrix$;

-- Install a rollback-only trigger after the functional matrix to force the expense
-- half of submitted to fail after the attempt UPDATE. The statement exception must
-- roll back the attempt transition as well.
create function pg_temp.phase3c2r_force_expense_failure()
returns trigger language plpgsql as $function$
begin
  if old.cash_creation_event_id='c3200000-0000-4000-8000-000000000105'::uuid then
    raise exception using errcode='55000',message='PHASE3C2R_FORCED_EXPENSE_FAILURE';
  end if;
  return new;
end;
$function$;
create trigger phase3c2r_force_expense_failure
before update on public.school_expense_records
for each row execute function pg_temp.phase3c2r_force_expense_failure();

do $atomic_failure_matrix$
declare v_expense uuid; v_attempt public.school_expense_cash_attempts%rowtype; v_failed boolean := false;
begin
  select e.id into v_expense from public.school_expense_records e where e.cash_creation_event_id='c3200000-0000-4000-8000-000000000105';
  select * into v_attempt from public.school_expense_cash_attempts where expense_id=v_expense;
  begin
    perform * from public.school_mark_cash_expense_request_submitted_v2(v_expense,'c3200000-0000-4000-8000-000000000405','pending','aozora_school',v_attempt.request_event_id,v_attempt.idempotency_key,'school_expense_records',v_expense,'expense_paid','expense',5000,'JPY','c3200000-0000-4000-8000-000000000301','2099-06-25',v_attempt.request_payload_fingerprint);
  exception when sqlstate '55000' then if sqlerrm='PHASE3C2R_FORCED_EXPENSE_FAILURE' then v_failed:=true; else raise; end if; end;
  if not v_failed or not exists(select 1 from public.school_expense_cash_attempts where id=v_attempt.id and attempt_status='prepared' and version=1 and cash_request_id is null) or not exists(select 1 from public.school_expense_records where id=v_expense and cash_request_status='pending_cash_request' and cash_request_id is null) then raise exception 'PHASE3C2R_ATOMIC_ROLLBACK_FAILED'; end if;
end;
$atomic_failure_matrix$;

do $original_rows_unchanged$
begin
  if exists (
    select 1 from phase3c2r_expense_before b
    join public.school_expense_records e on e.id=b.id
    where to_jsonb(e) is distinct from b.row_json
  ) then raise exception 'PHASE3C2R_EXISTING_EXPENSE_CHANGED'; end if;
end;
$original_rows_unchanged$;

select 'PHASE3C2R_ROLLBACK_MATRIX_PASS' as result;
