-- school_repair_zhiyuan_202605_cny_amount.sql
-- Guarded one-time repair for the 2026-05 Zhiyuan external-work actual CNY receipt.
-- Default execution rolls back. Pass -v repair_commit=1 only for the authorized repair.

\if :{?repair_commit}
\else
  \set repair_commit 0
\endif

begin;

do $$
declare
  v_settlement_id constant uuid := 'e4b8bbdb-3f5c-4e6f-b73c-dce0a4378941'::uuid;
  v_income_id constant uuid := '7786630e-4173-4a93-8da3-023749822ea7'::uuid;
  v_linkage_id constant uuid := 'c3139df9-b4af-4c78-83fd-a4034485d06f'::uuid;
  v_cash_request_id constant uuid := 'a4d8404e-7c11-4a72-b9d6-c98274f77c48'::uuid;
  v_cash_transaction_id constant uuid := '2c2145e1-8bf4-4295-b520-a99dfb9cf5f0'::uuid;
  v_cash_user_id constant uuid := '8596a708-d99f-4264-8f8c-5b89af9254b6'::uuid;
  v_cash_account_id constant uuid := 'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid;
  v_old_amount constant numeric := 7327;
  v_new_amount constant numeric := 7372;
  v_old_text constant text := '7,327.00';
  v_new_text constant text := '7,372.00';
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
  v_income public.school_income_records%rowtype;
  v_linkage public.school_personal_cash_income_linkage_events%rowtype;
  v_updated_count integer;
begin
  select *
    into v_settlement
  from public.school_part_time_work_monthly_settlements
  where id = v_settlement_id
  for update;

  if not found
     or v_settlement.workplace_name <> '致远教育'
     or v_settlement.year_month <> '2026-05'
     or v_settlement.total_wage_jpy <> 172860
     or v_settlement.status <> 'income_request_created'
     or v_settlement.income_record_id is distinct from v_income_id then
    raise exception 'School settlement target or protected facts do not match the approved repair scope';
  end if;

  select *
    into v_income
  from public.school_income_records
  where id = v_income_id
  for update;

  if not found
     or v_income.status <> 'received'
     or v_income.currency <> 'JPY'
     or v_income.amount <> 172860
     or v_income.amount_jpy <> 172860
     or v_income.receipt_status <> 'Cash已确认' then
    raise exception 'School income target or protected facts do not match the approved repair scope';
  end if;

  select *
    into v_linkage
  from public.school_personal_cash_income_linkage_events
  where id = v_linkage_id
  for update;

  if not found
     or v_linkage.income_record_id is distinct from v_income_id
     or v_linkage.sync_status <> 'synced'
     or v_linkage.cash_request_status <> 'approved'
     or v_linkage.payment_currency <> 'CNY'
     or v_linkage.payment_amount <> v_old_amount
     or v_linkage.payment_exchange_rate <> 0.04189
     or v_linkage.cash_request_id is distinct from v_cash_request_id
     or v_linkage.cash_transaction_id is distinct from v_cash_transaction_id
     or v_linkage.cash_user_id is distinct from v_cash_user_id
     or v_linkage.cash_account_id is distinct from v_cash_account_id
     or (length(v_linkage.note) - length(replace(v_linkage.note, v_old_text, ''))) / length(v_old_text) <> 1 then
    raise exception 'School linkage target or protected facts do not match the approved repair scope';
  end if;

  update public.school_personal_cash_income_linkage_events
  set
    payment_amount = v_new_amount,
    note = replace(note, v_old_text, v_new_text)
  where id = v_linkage_id
    and payment_amount = v_old_amount;

  get diagnostics v_updated_count = row_count;
  if v_updated_count <> 1 then
    raise exception 'expected exactly one School linkage update, updated %', v_updated_count;
  end if;

  select *
    into v_linkage
  from public.school_personal_cash_income_linkage_events
  where id = v_linkage_id;

  if v_linkage.payment_amount <> v_new_amount
     or position(v_old_text in v_linkage.note) <> 0
     or (length(v_linkage.note) - length(replace(v_linkage.note, v_new_text, ''))) / length(v_new_text) <> 1
     or v_linkage.payment_exchange_rate <> 0.04189
     or v_linkage.cash_request_id is distinct from v_cash_request_id
     or v_linkage.cash_transaction_id is distinct from v_cash_transaction_id then
    raise exception 'School post-repair verification failed';
  end if;
end $$;

select
  s.id as settlement_id,
  s.workplace_name,
  s.year_month,
  s.total_wage_jpy,
  i.id as income_record_id,
  e.id as linkage_event_id,
  e.payment_currency,
  e.payment_amount,
  e.payment_exchange_rate,
  e.cash_request_id,
  e.cash_transaction_id,
  position('7,327.00' in e.note) = 0 as old_text_removed,
  position('7,372.00' in e.note) > 0 as new_text_present
from public.school_part_time_work_monthly_settlements s
join public.school_income_records i on i.id = s.income_record_id
join public.school_personal_cash_income_linkage_events e on e.income_record_id = i.id
where s.id = 'e4b8bbdb-3f5c-4e6f-b73c-dce0a4378941'::uuid
  and i.id = '7786630e-4173-4a93-8da3-023749822ea7'::uuid
  and e.id = 'c3139df9-b4af-4c78-83fd-a4034485d06f'::uuid;

\if :repair_commit
  commit;
\else
  rollback;
\endif
