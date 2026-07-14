-- cash_repair_zhiyuan_202605_cny_amount.sql
-- Guarded one-time repair for the 2026-05 Zhiyuan external-work actual CNY receipt.
-- Default execution rolls back. Pass -v repair_commit=1 only for the authorized repair.

\if :{?repair_commit}
\else
  \set repair_commit 0
\endif

begin;

do $$
declare
  v_request_id constant uuid := 'a4d8404e-7c11-4a72-b9d6-c98274f77c48'::uuid;
  v_transaction_id constant uuid := '2c2145e1-8bf4-4295-b520-a99dfb9cf5f0'::uuid;
  v_school_event_id constant uuid := 'c3139df9-b4af-4c78-83fd-a4034485d06f'::uuid;
  v_school_income_id constant uuid := '7786630e-4173-4a93-8da3-023749822ea7'::uuid;
  v_user_id constant uuid := '8596a708-d99f-4264-8f8c-5b89af9254b6'::uuid;
  v_account_id constant uuid := 'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid;
  v_old_amount constant numeric := 7327;
  v_new_amount constant numeric := 7372;
  v_old_text constant text := '7,327.00';
  v_new_text constant text := '7,372.00';
  v_request public.home_external_transaction_requests%rowtype;
  v_transaction public.home_cny_transactions%rowtype;
  v_new_payload jsonb;
  v_updated_count integer;
begin
  select *
    into v_request
  from public.home_external_transaction_requests
  where id = v_request_id
  for update;

  if not found
     or v_request.user_id is distinct from v_user_id
     or v_request.account_id is distinct from v_account_id
     or v_request.external_source <> 'aozora_school'
     or v_request.external_event_id is distinct from v_school_event_id
     or v_request.external_reference_type <> 'school_income_records'
     or v_request.external_reference_id is distinct from v_school_income_id
     or v_request.request_type <> 'income_received'
     or v_request.transaction_type <> 'income'
     or v_request.currency <> 'CNY'
     or v_request.amount <> v_old_amount
     or v_request.status <> 'approved'
     or v_request.created_transaction_id is distinct from v_transaction_id
     or (v_request.payload_snapshot ->> 'amount')::numeric <> v_old_amount
     or (v_request.payload_snapshot ->> 'payment_amount')::numeric <> v_old_amount
     or (v_request.payload_snapshot ->> 'payment_exchange_rate')::numeric <> 0.04189
     or (length(v_request.description) - length(replace(v_request.description, v_old_text, ''))) / length(v_old_text) <> 1
     or (length(v_request.note) - length(replace(v_request.note, v_old_text, ''))) / length(v_old_text) <> 1
     or (length(v_request.payload_snapshot ->> 'note') - length(replace(v_request.payload_snapshot ->> 'note', v_old_text, ''))) / length(v_old_text) <> 1 then
    raise exception 'Cash request target or protected facts do not match the approved repair scope';
  end if;

  select *
    into v_transaction
  from public.home_cny_transactions
  where id = v_transaction_id
  for update;

  if not found
     or v_transaction.user_id is distinct from v_user_id
     or v_transaction.account_id is distinct from v_account_id
     or v_transaction.currency <> 'CNY'
     or v_transaction.transaction_type <> 'income'
     or v_transaction.amount <> v_old_amount
     or v_transaction.external_source <> 'aozora_school'
     or v_transaction.external_source_id is distinct from v_school_event_id
     or v_transaction.external_event_type <> 'income_received'
     or v_transaction.external_reference_id is distinct from v_school_income_id
     or v_transaction.external_payload_hash <> md5(v_request.payload_snapshot::text)
     or (length(v_transaction.description) - length(replace(v_transaction.description, v_old_text, ''))) / length(v_old_text) <> 1
     or (length(v_transaction.note) - length(replace(v_transaction.note, v_old_text, ''))) / length(v_old_text) <> 1
     or (length(v_transaction.external_note) - length(replace(v_transaction.external_note, v_old_text, ''))) / length(v_old_text) <> 1 then
    raise exception 'Cash transaction target or protected facts do not match the approved repair scope';
  end if;

  v_new_payload := jsonb_set(
    jsonb_set(
      jsonb_set(v_request.payload_snapshot, '{amount}', to_jsonb(v_new_amount), false),
      '{payment_amount}',
      to_jsonb(v_new_amount),
      false
    ),
    '{note}',
    to_jsonb(replace(v_request.payload_snapshot ->> 'note', v_old_text, v_new_text)),
    false
  );

  update public.home_external_transaction_requests
  set
    amount = v_new_amount,
    description = replace(description, v_old_text, v_new_text),
    note = replace(note, v_old_text, v_new_text),
    payload_snapshot = v_new_payload
  where id = v_request_id
    and amount = v_old_amount;

  get diagnostics v_updated_count = row_count;
  if v_updated_count <> 1 then
    raise exception 'expected exactly one Cash request update, updated %', v_updated_count;
  end if;

  update public.home_cny_transactions
  set
    amount = v_new_amount,
    description = replace(description, v_old_text, v_new_text),
    note = replace(note, v_old_text, v_new_text),
    external_note = replace(external_note, v_old_text, v_new_text),
    external_payload_hash = md5(v_new_payload::text)
  where id = v_transaction_id
    and amount = v_old_amount
    and external_payload_hash = md5(v_request.payload_snapshot::text);

  get diagnostics v_updated_count = row_count;
  if v_updated_count <> 1 then
    raise exception 'expected exactly one Cash transaction update, updated %', v_updated_count;
  end if;

  select *
    into v_request
  from public.home_external_transaction_requests
  where id = v_request_id;

  select *
    into v_transaction
  from public.home_cny_transactions
  where id = v_transaction_id;

  if v_request.amount <> v_new_amount
     or (v_request.payload_snapshot ->> 'amount')::numeric <> v_new_amount
     or (v_request.payload_snapshot ->> 'payment_amount')::numeric <> v_new_amount
     or (v_request.payload_snapshot ->> 'payment_exchange_rate')::numeric <> 0.04189
     or position(v_old_text in v_request.description) <> 0
     or position(v_old_text in v_request.note) <> 0
     or position(v_old_text in v_request.payload_snapshot ->> 'note') <> 0
     or v_transaction.amount <> v_new_amount
     or v_transaction.external_payload_hash <> md5(v_request.payload_snapshot::text)
     or position(v_old_text in v_transaction.description) <> 0
     or position(v_old_text in v_transaction.note) <> 0
     or position(v_old_text in v_transaction.external_note) <> 0 then
    raise exception 'Cash post-repair verification failed';
  end if;
end $$;

select
  r.id as request_id,
  r.amount as request_amount,
  (r.payload_snapshot ->> 'amount')::numeric as payload_amount,
  (r.payload_snapshot ->> 'payment_amount')::numeric as payload_payment_amount,
  (r.payload_snapshot ->> 'payment_exchange_rate')::numeric as payment_exchange_rate,
  t.id as transaction_id,
  t.amount as transaction_amount,
  t.external_payload_hash = md5(r.payload_snapshot::text) as payload_hash_matches,
  position('7,327.00' in concat_ws(' ', r.description, r.note, r.payload_snapshot ->> 'note', t.description, t.note, t.external_note)) = 0 as old_text_removed,
  position('7,372.00' in concat_ws(' ', r.description, r.note, r.payload_snapshot ->> 'note', t.description, t.note, t.external_note)) > 0 as new_text_present
from public.home_external_transaction_requests r
join public.home_cny_transactions t on t.id = r.created_transaction_id
where r.id = 'a4d8404e-7c11-4a72-b9d6-c98274f77c48'::uuid
  and t.id = '2c2145e1-8bf4-4295-b520-a99dfb9cf5f0'::uuid;

\if :repair_commit
  commit;
\else
  rollback;
\endif
