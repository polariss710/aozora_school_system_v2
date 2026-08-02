-- Cash tuition Cash hardening rollback tests, 2026-08-02.
-- Uses the canonical references emitted by the School Atomic Writer rollback test.
-- Every Cash fixture write is inside this transaction and must roll back.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

insert into public.home_accounts (
  id, user_id, currency, name, account_type, opening_balance,
  is_active, sort_order, allow_school_requests
) values
  ('f2fc0000-0000-4000-8000-00000000c001', '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'CNY', 'codex-test tuition Cash CNY', 'bank', 0, true, 9001, true),
  ('f2fc0000-0000-4000-8000-00000000c002', '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'CNY', 'codex-test tuition Cash inactive', 'bank', 0, false, 9002, true),
  ('f2fc0000-0000-4000-8000-00000000c003', '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'CNY', 'codex-test tuition Cash blocked', 'bank', 0, true, 9003, false),
  ('f2fc0000-0000-4000-8000-00000000c004', '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'JPY', 'codex-test tuition Cash JPY', 'bank', 0, true, 9004, true);

create temporary table cash_test_result (
  flow text primary key,
  request_id uuid,
  transaction_id uuid,
  amount numeric,
  transaction_count integer,
  transaction_sum numeric
) on commit drop;

select set_config('request.jwt.claims',
  '{"role":"service_role"}', true);

do $create$
declare v_first jsonb; v_second jsonb; v_request uuid;
begin
  select public.home_create_external_transaction_request(
    '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001',
    'aozora_school', '2b379efc-b462-4e16-86bb-7725e8c6907e',
    'school_income_records', 'fbd0b98c-f5eb-43a9-8cb0-471b6acaae4f',
    'tuition_income_received', 'income', date '2099-08-31', 1000.00,
    'aozora_school:school_income_records:fbd0b98c-f5eb-43a9-8cb0-471b6acaae4f:tuition_income_received:attempt:1',
    'codex-test tuition Cash approve', 'codex-test rollback',
    jsonb_build_object('payment_currency', 'CNY', 'payment_amount', 1000.00,
      'payment_exchange_rate', 0.05), 'CNY'
  ) into v_first;
  select public.home_create_external_transaction_request(
    '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001',
    'aozora_school', '2b379efc-b462-4e16-86bb-7725e8c6907e',
    'school_income_records', 'fbd0b98c-f5eb-43a9-8cb0-471b6acaae4f',
    'tuition_income_received', 'income', date '2099-08-31', 1000.00,
    'aozora_school:school_income_records:fbd0b98c-f5eb-43a9-8cb0-471b6acaae4f:tuition_income_received:attempt:1',
    'codex-test tuition Cash approve', 'codex-test rollback',
    jsonb_build_object('payment_currency', 'CNY', 'payment_amount', 1000.00,
      'payment_exchange_rate', 0.05), 'CNY'
  ) into v_second;
  v_request := (v_first ->> 'request_id')::uuid;
  if coalesce((v_first ->> 'ok')::boolean, false) is not true
     or coalesce((v_first ->> 'inserted')::boolean, false) is not true
     or coalesce((v_second ->> 'inserted')::boolean, true) is not false
     or (v_second ->> 'request_id')::uuid is distinct from v_request
     or (select count(*) from public.home_external_transaction_requests
         where external_reference_id = 'fbd0b98c-f5eb-43a9-8cb0-471b6acaae4f') <> 1 then
    raise exception 'CASH_TUITION_DUPLICATE_CREATE_FAILED first=% second=%', v_first, v_second;
  end if;
  insert into cash_test_result(flow, request_id, amount)
  values ('approve', v_request, 1000.00);
end
$create$;

-- Wrong, inactive, School-disabled, non-CNY and legacy inputs fail closed.
do $invalid$
declare v_result jsonb; v_account uuid; v_currency text; v_index integer := 0;
begin
  for v_account, v_currency in
    select * from (values
      ('f2fc0000-0000-4000-8000-00000000c002'::uuid, 'CNY'::text),
      ('f2fc0000-0000-4000-8000-00000000c003'::uuid, 'CNY'::text),
      ('f2fc0000-0000-4000-8000-00000000c004'::uuid, 'CNY'::text),
      ('f2fc0000-0000-4000-8000-00000000c001'::uuid, 'JPY'::text)
    ) rows(account_id, requested_currency)
  loop
    v_index := v_index + 1;
    select public.home_create_external_transaction_request(
      '8596a708-d99f-4264-8f8c-5b89af9254b6', v_account,
      'aozora_school', ('f2fc0000-0000-4000-8000-' || lpad((1000 + v_index)::text, 12, '0'))::uuid,
      'school_income_records', ('f2fc0000-0000-4000-8000-' || lpad((2000 + v_index)::text, 12, '0'))::uuid,
      'tuition_income_received', 'income', date '2099-08-31', 1,
      'codex-test-invalid-' || v_index, null, null, '{}'::jsonb, v_currency
    ) into v_result;
    if coalesce((v_result ->> 'ok')::boolean, false) then
      raise exception 'CASH_TUITION_INVALID_ACCOUNT_ACCEPTED result=%', v_result;
    end if;
  end loop;

  select public.home_create_external_transaction_request(
    '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001', 'aozora_school',
    'f2fc0000-0000-4000-8000-000000003001', 'school_payment_requests',
    'f2fc0000-0000-4000-8000-000000003002', 'teacher_wage_payment_confirm',
    'expense', date '2099-08-31', 1, 'codex-test-legacy', null, null,
    '{}'::jsonb, 'CNY'
  ) into v_result;
  if coalesce((v_result ->> 'ok')::boolean, false) then
    raise exception 'CASH_LEGACY_REQUEST_ACCEPTED';
  end if;
end
$invalid$;

-- Authenticated owner approve creates one immutable CNY transaction.
select set_config('request.jwt.claims',
  '{"role":"authenticated","sub":"8596a708-d99f-4264-8f8c-5b89af9254b6"}', true);
do $approve$
declare v_request uuid; v_first jsonb; v_second jsonb; v_transaction uuid;
        v_count1 integer; v_count2 integer; v_sum1 numeric; v_sum2 numeric;
begin
  select request_id into strict v_request from cash_test_result where flow = 'approve';
  select public.home_approve_external_transaction_request(v_request) into v_first;
  v_transaction := (v_first ->> 'transaction_id')::uuid;
  select count(*)::integer, coalesce(sum(amount), 0)
    into v_count1, v_sum1
  from public.home_cny_transactions
  where account_id = 'f2fc0000-0000-4000-8000-00000000c001';
  select public.home_approve_external_transaction_request(v_request) into v_second;
  select count(*)::integer, coalesce(sum(amount), 0)
    into v_count2, v_sum2
  from public.home_cny_transactions
  where account_id = 'f2fc0000-0000-4000-8000-00000000c001';
  if coalesce((v_first ->> 'ok')::boolean, false) is not true
     or (v_second ->> 'transaction_id')::uuid is distinct from v_transaction
     or coalesce((v_second ->> 'transaction_inserted')::boolean, true) is not false
     or v_count1 <> 1 or v_count2 <> 1 or v_sum1 <> 1000.00 or v_sum2 <> 1000.00
     or (select amount from public.home_cny_transactions where id = v_transaction) <> 1000.00 then
    raise exception 'CASH_TUITION_APPROVE_IDEMPOTENCY_FAILED first=% second=% counts=%/% sums=%/%',
      v_first, v_second, v_count1, v_count2, v_sum1, v_sum2;
  end if;
  update cash_test_result set transaction_id = v_transaction,
    transaction_count = v_count2, transaction_sum = v_sum2
  where flow = 'approve';
end
$approve$;

-- Rejected attempt is terminal and next attempt creates a different request.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $reject_create$
declare v_result jsonb;
begin
  select public.home_create_external_transaction_request(
    '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001', 'aozora_school',
    '0d408545-b695-4c60-968e-8242aa8835a7', 'school_income_records',
    'bee0017b-cd6b-417b-a6a8-7b1ebf910e61', 'tuition_income_received',
    'income', date '2099-09-30', 640.00,
    'aozora_school:school_income_records:bee0017b-cd6b-417b-a6a8-7b1ebf910e61:tuition_income_received:attempt:1',
    'codex-test tuition Cash reject', 'codex-test rollback',
    jsonb_build_object('payment_currency', 'CNY', 'payment_amount', 640.00,
      'payment_exchange_rate', 0.04), 'CNY'
  ) into v_result;
  insert into cash_test_result(flow, request_id, amount)
  values ('reject_retry', (v_result ->> 'request_id')::uuid, 640.00);
end
$reject_create$;

-- Forged owner fails closed without state change.
select set_config('request.jwt.claims',
  '{"role":"authenticated","sub":"0b90204b-6ec5-4dc5-b63b-24110a4e4ad9"}', true);
do $forged$
declare v_request uuid; v_result jsonb;
begin
  select request_id into strict v_request from cash_test_result where flow = 'reject_retry';
  select public.home_approve_external_transaction_request(v_request) into v_result;
  if coalesce((v_result ->> 'ok')::boolean, false)
     or (select status from public.home_external_transaction_requests where id = v_request) <> 'pending' then
    raise exception 'CASH_FORGED_OWNER_NOT_REJECTED result=%', v_result;
  end if;
end
$forged$;

select set_config('request.jwt.claims',
  '{"role":"authenticated","sub":"8596a708-d99f-4264-8f8c-5b89af9254b6"}', true);
do $reject$
declare v_attempt1 uuid; v_attempt2 uuid; v_result jsonb;
        v_before_count integer; v_after_count integer;
begin
  select request_id into strict v_attempt1 from cash_test_result where flow = 'reject_retry';
  select count(*)::integer into v_before_count
  from public.home_cny_transactions
  where account_id = 'f2fc0000-0000-4000-8000-00000000c001';
  select public.home_reject_external_transaction_request(v_attempt1, 'codex-test rejected') into v_result;
  select count(*)::integer into v_after_count
  from public.home_cny_transactions
  where account_id = 'f2fc0000-0000-4000-8000-00000000c001';
  if coalesce((v_result ->> 'ok')::boolean, false) is not true
     or v_before_count <> v_after_count
     or (select created_transaction_id from public.home_external_transaction_requests where id = v_attempt1) is not null then
    raise exception 'CASH_TUITION_REJECT_SIDE_EFFECT_FAILED result=%', v_result;
  end if;

  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  select public.home_create_external_transaction_request(
    '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001', 'aozora_school',
    'f2fc0000-0000-4000-8000-000000004002', 'school_income_records',
    'bee0017b-cd6b-417b-a6a8-7b1ebf910e61', 'tuition_income_received',
    'income', date '2099-09-30', 640.00,
    'aozora_school:school_income_records:bee0017b-cd6b-417b-a6a8-7b1ebf910e61:tuition_income_received:attempt:2',
    'codex-test tuition Cash retry', 'codex-test rollback',
    jsonb_build_object('payment_currency', 'CNY', 'payment_amount', 640.00,
      'payment_exchange_rate', 0.04), 'CNY'
  ) into v_result;
  v_attempt2 := (v_result ->> 'request_id')::uuid;
  if v_attempt2 is null or v_attempt2 = v_attempt1
     or (select status from public.home_external_transaction_requests where id = v_attempt1) <> 'rejected'
     or (select count(*) from public.home_external_transaction_requests
         where external_reference_id = 'bee0017b-cd6b-417b-a6a8-7b1ebf910e61') <> 2 then
    raise exception 'CASH_TUITION_REJECT_RETRY_FAILED result=%', v_result;
  end if;
end
$reject$;

do $acl$
begin
  if has_function_privilege('anon',
      'public.home_create_external_transaction_request(uuid,uuid,text,uuid,text,uuid,text,text,date,numeric,text,text,text,jsonb,text)', 'EXECUTE')
     or has_function_privilege('authenticated',
      'public.home_create_external_transaction_request(uuid,uuid,text,uuid,text,uuid,text,text,date,numeric,text,text,text,jsonb,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.home_approve_external_transaction_request(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.home_reject_external_transaction_request(uuid,text)', 'EXECUTE')
     or has_function_privilege('authenticated',
      'public.home_create_external_cny_transaction(uuid,uuid,text,date,numeric,text,text,text,uuid,text,text,text,uuid,text,text)', 'EXECUTE')
     or not has_function_privilege('service_role',
      'public.home_create_external_transaction_request(uuid,uuid,text,uuid,text,uuid,text,text,date,numeric,text,text,text,jsonb,text)', 'EXECUTE') then
    raise exception 'CASH_TUITION_ACL_FAILED';
  end if;
end
$acl$;

select * from cash_test_result order by flow;
select status, count(*) from public.home_external_transaction_requests
where external_reference_id in (
  'fbd0b98c-f5eb-43a9-8cb0-471b6acaae4f',
  'bee0017b-cd6b-417b-a6a8-7b1ebf910e61'
) group by status order by status;
rollback;

begin transaction read only;
select
  (select count(*) from public.home_accounts where id::text like 'f2fc0000-0000-4000-8000-00000000c00%') +
  (select count(*) from public.home_external_transaction_requests where external_reference_id in (
    'fbd0b98c-f5eb-43a9-8cb0-471b6acaae4f',
    'bee0017b-cd6b-417b-a6a8-7b1ebf910e61')) +
  (select count(*) from public.home_cny_transactions where account_id = 'f2fc0000-0000-4000-8000-00000000c001')
  as cash_fixture_residue;
rollback;
