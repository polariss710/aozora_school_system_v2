-- school_reverse_reimbursement_record_rpc.sql
-- Purpose: Reverse a paid reimbursement record by inserting reversal account transactions,
--          updating account balances, marking the reimbursement as reversed,
--          and returning related expenses to pending reimbursement status.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Verified: v2.24.12-reimbursement-reversal-rpc-commit-test-20260604
-- Version: v2.24.8-reimbursement-reversal-rpc-sql-draft-20260604
-- Verification:
--   - Function created in public schema.
--   - Failure smoke tests returned expected business errors.
--   - Rollback reverse test moved related expense reimbursement_status to pending inside transaction.
--   - Rollback left reimbursement status paid, reversal fields null, reverse transaction count 0,
--     and related expense reimbursement_status paid.
--   - Commit reverse test reversed the test reimbursement, inserted two reverse transactions,
--     updated account balances, and returned the related expense to pending reimbursement status.
--   - Duplicate reverse attempt is rejected.
-- Scope:
--   - Reverse paid reimbursement records only.
--   - Keep original reimbursement, items, and original account transactions.
--   - Insert two reversal account transactions.
--   - Update reimbursement reversal metadata fields.
--   - Return related expenses to reimbursement_status = 'pending'.
--   - Does not delete historical data.
--   - Does not support partial reversal, batch reversal, frontend, attachments, OCR, or statistics.
-- Review before execution:
--   - Confirm transaction_type values reimbursement_reverse_in / reimbursement_reverse_out.
--   - Confirm status value reversed is accepted.
--   - Confirm reimbursement_status pending is accepted for reversed expenses.

create or replace function public.school_reverse_reimbursement_record(
  p_reimbursement_id uuid,
  p_reversal_date date,
  p_reason text default null
)
returns table (
  reimbursement_id uuid,
  from_reverse_transaction_id uuid,
  to_reverse_transaction_id uuid,
  from_account_id uuid,
  to_account_id uuid,
  from_account_new_balance numeric,
  to_account_new_balance numeric,
  amount numeric,
  currency text,
  year_month text,
  status text,
  expense_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_year_month text;
  v_reimbursement public.school_reimbursements%rowtype;
  v_original_out public.school_account_transactions%rowtype;
  v_original_in public.school_account_transactions%rowtype;
  v_account public.school_accounts%rowtype;
  v_from_account public.school_accounts%rowtype;
  v_to_account public.school_accounts%rowtype;
  v_account_count integer := 0;
  v_original_out_count integer := 0;
  v_original_in_count integer := 0;
  v_existing_reverse_count integer := 0;
  v_item_count integer := 0;
  v_distinct_expense_count integer := 0;
  v_null_expense_count integer := 0;
  v_expense_ids uuid[];
  v_expense_count integer := 0;
  v_bad_expense_app_type_count integer := 0;
  v_bad_expense_status_count integer := 0;
  v_bad_expense_reimbursement_status_count integer := 0;
  v_bad_expense_business_entity_count integer := 0;
  v_bad_expense_currency_count integer := 0;
  v_other_reimbursement_item_count integer := 0;
  v_item_total_amount numeric := 0;
  v_from_account_new_balance numeric;
  v_to_account_new_balance numeric;
  v_from_reverse_transaction_id uuid;
  v_to_reverse_transaction_id uuid;
begin
  if p_reimbursement_id is null then
    raise exception '请选择要撤销的报销记录。';
  end if;

  if p_reversal_date is null then
    raise exception '请选择撤销日期。';
  end if;

  select *
  into v_reimbursement
  from public.school_reimbursements r
  where r.id = p_reimbursement_id
    and coalesce(r.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '报销记录不存在。';
  end if;

  if v_reimbursement.status = 'reversed'
    or v_reimbursement.reversed_at is not null
    or v_reimbursement.reversal_from_account_transaction_id is not null
    or v_reimbursement.reversal_to_account_transaction_id is not null then
    raise exception '该报销记录已撤销，不能重复撤销。';
  end if;

  if v_reimbursement.status is distinct from 'paid' then
    raise exception '只能撤销已支付报销记录。';
  end if;

  if coalesce(v_reimbursement.amount, 0) <= 0
    or nullif(trim(coalesce(v_reimbursement.currency, '')), '') is null then
    raise exception '报销记录金额或币种无效，不能撤销。';
  end if;

  select count(*)::integer
  into v_existing_reverse_count
  from public.school_account_transactions t
  where t.related_table = 'school_reimbursements'
    and t.related_id = p_reimbursement_id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type in ('reimbursement_reverse_in', 'reimbursement_reverse_out');

  if v_existing_reverse_count > 0 then
    raise exception '该报销记录已撤销，不能重复撤销。';
  end if;

  select count(*)::integer
  into v_original_out_count
  from public.school_account_transactions t
  where t.related_table = 'school_reimbursements'
    and t.related_id = p_reimbursement_id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'reimbursement_out';

  if v_original_out_count <> 1 then
    raise exception '原报销出金流水不存在或不唯一。';
  end if;

  select *
  into v_original_out
  from public.school_account_transactions t
  where t.related_table = 'school_reimbursements'
    and t.related_id = p_reimbursement_id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'reimbursement_out'
  for update;

  select count(*)::integer
  into v_original_in_count
  from public.school_account_transactions t
  where t.related_table = 'school_reimbursements'
    and t.related_id = p_reimbursement_id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'reimbursement_in';

  if v_original_in_count <> 1 then
    raise exception '原报销入金流水不存在或不唯一。';
  end if;

  select *
  into v_original_in
  from public.school_account_transactions t
  where t.related_table = 'school_reimbursements'
    and t.related_id = p_reimbursement_id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'reimbursement_in'
  for update;

  if v_original_out.account_id is distinct from v_reimbursement.from_account_id
    or v_original_out.currency is distinct from v_reimbursement.currency
    or v_original_out.amount is distinct from -v_reimbursement.amount
    or v_original_in.account_id is distinct from v_reimbursement.to_account_id
    or v_original_in.currency is distinct from v_reimbursement.currency
    or v_original_in.amount is distinct from v_reimbursement.amount then
    raise exception '原报销流水金额不一致，不能撤销。';
  end if;

  select
    array_agg(items.expense_id order by items.expense_id),
    count(*)::integer,
    count(distinct items.expense_id)::integer,
    count(*) filter (where items.expense_id is null)::integer,
    coalesce(sum(coalesce(items.amount, 0)), 0)::numeric
  into
    v_expense_ids,
    v_item_count,
    v_distinct_expense_count,
    v_null_expense_count,
    v_item_total_amount
  from public.school_reimbursement_items items
  where items.reimbursement_id = p_reimbursement_id
    and coalesce(items.app_type, '') = 'school';

  if v_item_count = 0 then
    raise exception '报销记录没有关联支出，不能撤销。';
  end if;

  if v_null_expense_count > 0 or v_distinct_expense_count <> v_item_count then
    raise exception '关联支出不存在或数量不一致。';
  end if;

  if v_item_total_amount is distinct from v_reimbursement.amount then
    raise exception '原报销流水金额不一致，不能撤销。';
  end if;

  for v_account in
    select *
    from public.school_accounts a
    where a.id = any (array[v_reimbursement.from_account_id, v_reimbursement.to_account_id])
    order by a.id
    for update
  loop
    v_account_count := v_account_count + 1;

    if v_account.id = v_reimbursement.from_account_id then
      v_from_account := v_account;
    elsif v_account.id = v_reimbursement.to_account_id then
      v_to_account := v_account;
    end if;
  end loop;

  if v_account_count <> 2 then
    raise exception '报销账户不存在或不可用。';
  end if;

  if coalesce(v_from_account.app_type, '') <> 'school'
    or coalesce(v_to_account.app_type, '') <> 'school'
    or v_from_account.is_active is not true
    or v_to_account.is_active is not true then
    raise exception '报销账户不存在或不可用。';
  end if;

  if v_from_account.business_entity_id is distinct from v_reimbursement.business_entity_id
    or v_to_account.business_entity_id is distinct from v_reimbursement.business_entity_id then
    raise exception '报销账户不存在或不可用。';
  end if;

  if v_from_account.currency is distinct from v_reimbursement.currency
    or v_to_account.currency is distinct from v_reimbursement.currency then
    raise exception '报销账户币种不一致。';
  end if;

  with locked_expenses as (
    select *
    from public.school_expense_records e
    where e.id = any (v_expense_ids)
    order by e.id
    for update
  )
  select
    count(*)::integer,
    count(*) filter (where coalesce(locked_expenses.app_type, '') <> 'school')::integer,
    count(*) filter (where locked_expenses.status is distinct from 'paid')::integer,
    count(*) filter (where locked_expenses.reimbursement_status is distinct from 'paid')::integer,
    count(*) filter (where locked_expenses.business_entity_id is distinct from v_reimbursement.business_entity_id)::integer,
    count(*) filter (where locked_expenses.currency is distinct from v_reimbursement.currency)::integer
  into
    v_expense_count,
    v_bad_expense_app_type_count,
    v_bad_expense_status_count,
    v_bad_expense_reimbursement_status_count,
    v_bad_expense_business_entity_count,
    v_bad_expense_currency_count
  from locked_expenses;

  if v_expense_count <> v_item_count
    or v_bad_expense_app_type_count > 0
    or v_bad_expense_status_count > 0
    or v_bad_expense_business_entity_count > 0
    or v_bad_expense_currency_count > 0 then
    raise exception '关联支出不存在或数量不一致。';
  end if;

  if v_bad_expense_reimbursement_status_count > 0 then
    raise exception '只能撤销仍处于已报销状态的支出。';
  end if;

  select count(*)::integer
  into v_other_reimbursement_item_count
  from public.school_reimbursement_items items
  where items.expense_id = any (v_expense_ids)
    and items.reimbursement_id <> p_reimbursement_id;

  if v_other_reimbursement_item_count > 0 then
    raise exception '支出已关联其他报销记录，不能安全撤销。';
  end if;

  v_year_month := to_char(p_reversal_date, 'YYYY-MM');
  v_from_account_new_balance := coalesce(v_from_account.current_balance, 0) + v_reimbursement.amount;
  v_to_account_new_balance := coalesce(v_to_account.current_balance, 0) - v_reimbursement.amount;

  update public.school_accounts a
  set
    current_balance = v_from_account_new_balance,
    updated_at = v_now
  where a.id = v_reimbursement.from_account_id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_reimbursement.from_account_id,
    v_reimbursement.business_entity_id,
    p_reversal_date,
    v_year_month,
    'reimbursement_reverse_in',
    'school_reimbursements',
    v_reimbursement.id,
    v_reimbursement.currency,
    v_reimbursement.amount,
    v_from_account_new_balance,
    '报销撤销入金',
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_from_reverse_transaction_id;

  update public.school_accounts a
  set
    current_balance = v_to_account_new_balance,
    updated_at = v_now
  where a.id = v_reimbursement.to_account_id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_reimbursement.to_account_id,
    v_reimbursement.business_entity_id,
    p_reversal_date,
    v_year_month,
    'reimbursement_reverse_out',
    'school_reimbursements',
    v_reimbursement.id,
    v_reimbursement.currency,
    -v_reimbursement.amount,
    v_to_account_new_balance,
    '报销撤销出金',
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_to_reverse_transaction_id;

  update public.school_reimbursements r
  set
    status = 'reversed',
    reversed_at = v_now,
    reversal_reason = v_reason,
    reversal_from_account_transaction_id = v_from_reverse_transaction_id,
    reversal_to_account_transaction_id = v_to_reverse_transaction_id,
    updated_at = v_now
  where r.id = v_reimbursement.id;

  update public.school_expense_records e
  set
    reimbursement_status = 'pending',
    updated_at = v_now
  where e.id = any (v_expense_ids);

  return query
  select
    v_reimbursement.id,
    v_from_reverse_transaction_id,
    v_to_reverse_transaction_id,
    v_reimbursement.from_account_id,
    v_reimbursement.to_account_id,
    v_from_account_new_balance,
    v_to_account_new_balance,
    v_reimbursement.amount,
    v_reimbursement.currency,
    v_year_month,
    'reversed'::text,
    v_item_count;
end;
$$;

comment on function public.school_reverse_reimbursement_record(uuid, date, text) is
  'DRAFT RPC for v2 reimbursement reversal: logically reverses a paid reimbursement with two reversal account transactions and returns related expenses to pending reimbursement status.';
