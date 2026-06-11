-- school_fix_historical_reversed_teacher_wage_expenses_20260611.sql
-- Purpose:
--   Guarded one-time repair for historical teacher_wage payment requests that
--   are already reversed while their generated teacher_wage expense rows are
--   still paid.
--
-- Scope:
--   - Exact five historical target payment requests from the 2026-06-11
--     finance history repair dry-run.
--   - Marks only the generated teacher_wage expense rows reversed.
--   - Links each expense to the already-existing payment_reversal transaction.
--   - Does not insert account transactions.
--   - Does not update payment requests, wage locks/details, lessons, income,
--     ordinary expenses, reimbursements, accounts, or account balances.

select
  'pre_fix_target_summary' as check_name,
  count(*) as target_count,
  coalesce(sum(e.amount), 0) as target_amount,
  count(*) filter (
    where p.status = 'reversed'
      and p.source_type = 'teacher_wage'
      and e.status = 'paid'
      and e.expense_category = 'teacher_wage'
  ) as matching_status_count,
  count(*) filter (
    where p.reversal_transaction_id is not null
      and rt.id = p.reversal_transaction_id
      and rt.transaction_type = 'payment_reversal'
      and rt.related_table = 'school_payment_requests'
      and rt.related_id = p.id
      and rt.amount = p.amount
      and rt.currency = p.currency
      and rt.account_id = p.account_id
      and rt.business_entity_id = p.business_entity_id
  ) as reversal_transaction_match_count,
  count(*) filter (
    where e.amount = p.amount
      and e.currency = p.currency
      and e.account_id = p.account_id
      and e.business_entity_id = p.business_entity_id
  ) as expense_payment_match_count
from public.school_payment_requests p
join public.school_expense_records e
  on e.id = p.paid_expense_id
join public.school_account_transactions rt
  on rt.id = p.reversal_transaction_id
where p.id = any (array[
  '15373c20-2656-44cc-b9a8-f11d5651a0f2'::uuid,
  '8af4125f-a458-4ee7-ac71-b88593f6fd55'::uuid,
  'bb07d665-d943-494f-87be-5c29c5d41ee9'::uuid,
  '6eb0995e-03a1-4a69-8b24-389190630622'::uuid,
  'df34abf1-ccf9-4300-b132-fcefe4538ad9'::uuid
]);

do $$
declare
  v_expected_payment_ids uuid[] := array[
    '15373c20-2656-44cc-b9a8-f11d5651a0f2'::uuid,
    '8af4125f-a458-4ee7-ac71-b88593f6fd55'::uuid,
    'bb07d665-d943-494f-87be-5c29c5d41ee9'::uuid,
    '6eb0995e-03a1-4a69-8b24-389190630622'::uuid,
    'df34abf1-ccf9-4300-b132-fcefe4538ad9'::uuid
  ];
  v_expected_expense_ids uuid[] := array[
    '8d05119c-cd87-418f-affa-20e2e0591905'::uuid,
    '984f4636-1bca-4631-8678-18e24eedb437'::uuid,
    '636a43bb-476d-46bb-bcc4-a9a7eb84b398'::uuid,
    '5602a74f-71cf-4d34-acbf-61eecc036058'::uuid,
    'a0c7e93b-5078-40a2-8479-0df70606b2a0'::uuid
  ];
  v_target_count integer;
  v_target_amount numeric;
  v_bad_count integer;
  v_updated_count integer;
begin
  with target as (
    select
      p.id as payment_request_id,
      p.status as payment_status,
      p.source_type,
      p.amount as payment_amount,
      p.currency as payment_currency,
      p.account_id as payment_account_id,
      p.business_entity_id as payment_business_entity_id,
      p.reversed_at as payment_reversed_at,
      p.reversal_transaction_id,
      e.id as expense_id,
      e.status as expense_status,
      e.expense_category,
      e.amount as expense_amount,
      e.currency as expense_currency,
      e.account_id as expense_account_id,
      e.business_entity_id as expense_business_entity_id,
      e.reversed_at as expense_reversed_at,
      e.reversal_account_transaction_id,
      rt.id as reversal_tx_id,
      rt.transaction_type as reversal_tx_type,
      rt.related_table as reversal_related_table,
      rt.related_id as reversal_related_id,
      rt.amount as reversal_tx_amount,
      rt.currency as reversal_tx_currency,
      rt.account_id as reversal_tx_account_id,
      rt.business_entity_id as reversal_tx_business_entity_id
    from public.school_payment_requests p
    join public.school_expense_records e
      on e.id = p.paid_expense_id
    join public.school_account_transactions rt
      on rt.id = p.reversal_transaction_id
    where p.id = any (v_expected_payment_ids)
  )
  select
    count(*)::integer,
    coalesce(sum(expense_amount), 0),
    count(*) filter (
      where not (
        payment_status = 'reversed'
        and source_type = 'teacher_wage'
        and payment_reversed_at is not null
        and reversal_transaction_id is not null
        and expense_id = any (v_expected_expense_ids)
        and expense_status = 'paid'
        and expense_category = 'teacher_wage'
        and expense_amount = payment_amount
        and expense_currency = payment_currency
        and expense_account_id = payment_account_id
        and expense_business_entity_id = payment_business_entity_id
        and expense_reversed_at is null
        and reversal_account_transaction_id is null
        and reversal_tx_id = reversal_transaction_id
        and reversal_tx_type = 'payment_reversal'
        and reversal_related_table = 'school_payment_requests'
        and reversal_related_id = payment_request_id
        and reversal_tx_amount = payment_amount
        and reversal_tx_currency = payment_currency
        and reversal_tx_account_id = payment_account_id
        and reversal_tx_business_entity_id = payment_business_entity_id
      )
    )::integer
  into v_target_count, v_target_amount, v_bad_count
  from target;

  if v_target_count <> 5 then
    raise exception 'expected 5 target rows, got %', v_target_count;
  end if;

  if v_target_amount is distinct from 301500 then
    raise exception 'expected target amount 301500, got %', v_target_amount;
  end if;

  if v_bad_count <> 0 then
    raise exception 'target validation failed for % row(s)', v_bad_count;
  end if;

  update public.school_expense_records e
  set
    status = 'reversed',
    reversed_at = p.reversed_at,
    reversal_reason = 'historical teacher_wage payment reversal sync 2026-06-11',
    reversal_account_transaction_id = p.reversal_transaction_id,
    updated_at = now()
  from public.school_payment_requests p
  where p.paid_expense_id = e.id
    and p.id = any (v_expected_payment_ids)
    and e.id = any (v_expected_expense_ids)
    and p.source_type = 'teacher_wage'
    and p.status = 'reversed'
    and p.reversal_transaction_id is not null
    and e.status = 'paid'
    and e.expense_category = 'teacher_wage'
    and e.reversed_at is null
    and e.reversal_account_transaction_id is null;

  get diagnostics v_updated_count = row_count;

  if v_updated_count <> 5 then
    raise exception 'expected to update 5 expense rows, updated %', v_updated_count;
  end if;

  raise notice 'historical teacher_wage expense sync updated % rows, amount %', v_updated_count, v_target_amount;
end $$;

select
  'post_fix_target_summary' as check_name,
  count(*) as target_count,
  coalesce(sum(e.amount), 0) as target_amount,
  count(*) filter (
    where p.status = 'reversed'
      and p.source_type = 'teacher_wage'
      and e.status = 'reversed'
      and e.expense_category = 'teacher_wage'
      and e.reversal_account_transaction_id = p.reversal_transaction_id
  ) as synced_count
from public.school_payment_requests p
join public.school_expense_records e
  on e.id = p.paid_expense_id
where p.id = any (array[
  '15373c20-2656-44cc-b9a8-f11d5651a0f2'::uuid,
  '8af4125f-a458-4ee7-ac71-b88593f6fd55'::uuid,
  'bb07d665-d943-494f-87be-5c29c5d41ee9'::uuid,
  '6eb0995e-03a1-4a69-8b24-389190630622'::uuid,
  'df34abf1-ccf9-4300-b132-fcefe4538ad9'::uuid
]);
