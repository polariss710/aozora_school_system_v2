-- school_create_account_transfer_rpc.sql
-- RPC: public.school_create_account_transfer
-- Purpose: Create a posted account-to-account transfer with two account
--          transactions and two account balance updates.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Verified: v2.33.11-account-transfer-rpc-commit-test-20260606
-- Version: v2.33.8-account-transfer-rpc-sql-draft-20260606
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - school_account_transactions has no transaction_type check constraint blocking transfer_out / transfer_in.
-- - Rollback test succeeded with no persisted transfer, account transaction, or account balance changes.
-- - Commit test succeeded with one whitelisted test transfer, two account transactions, and account balance consistency verified.
-- - transfer_out / transfer_in amount direction, related_table / related_id, and balance_after were verified.
-- - Negative source account balance after transfer is allowed and was verified with test data.
-- - Failure cases for same from/to account and amount <= 0 were rejected without extra writes.
--
-- Scope:
-- - Create one school account transfer record.
-- - Deduct from_account current_balance and add to_account current_balance.
-- - Insert one transfer_out and one transfer_in account transaction.
-- - Link the transfer record back to both account transactions.
-- - Run all operations in one DB transaction.
--
-- Not supported in this first version:
-- - Transfer edit/delete/reversal.
-- - Cross-business transfer.
-- - Cross-currency transfer.
-- - Income, expense, reimbursement, payment, adjustment, or settlement creation.
-- - Frontend implementation.
-- - Idempotency keys for duplicate submit protection.
--
-- Review before execution:
-- - Confirm public.school_account_transfers exists and was verified.
-- - Confirm transaction_type values transfer_out / transfer_in are allowed.
-- - Confirm negative from_account balance is intentionally allowed.
-- - Confirm permissions / grants separately before enabling.

create or replace function public.school_create_account_transfer(
  p_transfer_date date,
  p_business_entity_id uuid,
  p_from_account_id uuid,
  p_to_account_id uuid,
  p_amount numeric,
  p_reason text,
  p_note text default null
)
returns table (
  transfer_id uuid,
  from_account_transaction_id uuid,
  to_account_transaction_id uuid,
  from_account_id uuid,
  to_account_id uuid,
  business_entity_id uuid,
  from_account_old_balance numeric,
  from_account_new_balance numeric,
  to_account_old_balance numeric,
  to_account_new_balance numeric,
  amount numeric,
  currency text,
  year_month text,
  status text,
  from_transaction_type text,
  to_transaction_type text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_business_entity public.school_business_entities%rowtype;
  v_account public.school_accounts%rowtype;
  v_from_account public.school_accounts%rowtype;
  v_to_account public.school_accounts%rowtype;
  v_account_count integer := 0;
  v_transfer_id uuid;
  v_from_account_transaction_id uuid;
  v_to_account_transaction_id uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_year_month text;
  v_from_account_old_balance numeric;
  v_from_account_new_balance numeric;
  v_to_account_old_balance numeric;
  v_to_account_new_balance numeric;
begin
  if p_transfer_date is null then
    raise exception '请选择转账日期。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_from_account_id is null then
    raise exception '请选择转出账户。';
  end if;

  if p_to_account_id is null then
    raise exception '请选择转入账户。';
  end if;

  if p_from_account_id = p_to_account_id then
    raise exception '转出账户和转入账户不能相同。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '转账金额必须大于 0。';
  end if;

  if v_reason is null then
    raise exception '转账原因不能为空。';
  end if;

  select *
  into v_business_entity
  from public.school_business_entities be
  where be.id = p_business_entity_id
    and be.is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  for v_account in
    select *
    from public.school_accounts a
    where a.id = any (array[p_from_account_id, p_to_account_id])
    order by a.id
    for update
  loop
    v_account_count := v_account_count + 1;

    if v_account.id = p_from_account_id then
      v_from_account := v_account;
    elsif v_account.id = p_to_account_id then
      v_to_account := v_account;
    end if;
  end loop;

  if v_account_count <> 2 then
    raise exception '转账账户不存在或不可用。';
  end if;

  if coalesce(v_from_account.app_type, '') <> 'school'
    or coalesce(v_to_account.app_type, '') <> 'school' then
    raise exception '转账账户不存在或不可用。';
  end if;

  if v_from_account.is_active is not true
    or v_to_account.is_active is not true then
    raise exception '转账账户已停用。';
  end if;

  if v_from_account.business_entity_id is distinct from p_business_entity_id
    or v_to_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '转账账户必须属于同一业务归属。';
  end if;

  if v_from_account.currency is distinct from v_to_account.currency then
    raise exception '转出账户和转入账户币种必须一致。';
  end if;

  if coalesce(v_from_account.currency, '') not in ('JPY', 'CNY') then
    raise exception '暂不支持该账户币种：%。', v_from_account.currency;
  end if;

  v_year_month := to_char(p_transfer_date, 'YYYY-MM');
  v_from_account_old_balance := coalesce(v_from_account.current_balance, 0);
  v_to_account_old_balance := coalesce(v_to_account.current_balance, 0);
  v_from_account_new_balance := v_from_account_old_balance - p_amount;
  v_to_account_new_balance := v_to_account_old_balance + p_amount;

  insert into public.school_account_transfers (
    business_entity_id,
    from_account_id,
    to_account_id,
    transfer_date,
    year_month,
    currency,
    amount,
    from_balance_before,
    from_balance_after,
    to_balance_before,
    to_balance_after,
    reason,
    note,
    status,
    from_account_transaction_id,
    to_account_transaction_id,
    reversed_at,
    reversal_reason,
    reversal_from_account_transaction_id,
    reversal_to_account_transaction_id,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    p_from_account_id,
    p_to_account_id,
    p_transfer_date,
    v_year_month,
    v_from_account.currency,
    p_amount,
    v_from_account_old_balance,
    v_from_account_new_balance,
    v_to_account_old_balance,
    v_to_account_new_balance,
    v_reason,
    v_note,
    'posted',
    null,
    null,
    null,
    null,
    null,
    null,
    'school',
    v_now,
    v_now
  )
  returning id into v_transfer_id;

  update public.school_accounts a
  set
    current_balance = v_from_account_new_balance,
    updated_at = v_now
  where a.id = p_from_account_id;

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
    p_from_account_id,
    p_business_entity_id,
    p_transfer_date,
    v_year_month,
    'transfer_out',
    'school_account_transfers',
    v_transfer_id,
    v_from_account.currency,
    -p_amount,
    v_from_account_new_balance,
    '账户转账转出：' || v_reason,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_from_account_transaction_id;

  update public.school_accounts a
  set
    current_balance = v_to_account_new_balance,
    updated_at = v_now
  where a.id = p_to_account_id;

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
    p_to_account_id,
    p_business_entity_id,
    p_transfer_date,
    v_year_month,
    'transfer_in',
    'school_account_transfers',
    v_transfer_id,
    v_to_account.currency,
    p_amount,
    v_to_account_new_balance,
    '账户转账转入：' || v_reason,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_to_account_transaction_id;

  update public.school_account_transfers t
  set
    from_account_transaction_id = v_from_account_transaction_id,
    to_account_transaction_id = v_to_account_transaction_id,
    updated_at = v_now
  where t.id = v_transfer_id;

  return query
  select
    v_transfer_id,
    v_from_account_transaction_id,
    v_to_account_transaction_id,
    p_from_account_id,
    p_to_account_id,
    p_business_entity_id,
    v_from_account_old_balance,
    v_from_account_new_balance,
    v_to_account_old_balance,
    v_to_account_new_balance,
    p_amount,
    v_from_account.currency,
    v_year_month,
    'posted'::text,
    'transfer_out'::text,
    'transfer_in'::text;
end;
$$;

comment on function public.school_create_account_transfer(
  date,
  uuid,
  uuid,
  uuid,
  numeric,
  text,
  text
) is
  'Draft RPC for v2 account transfer creation: creates a posted transfer, updates two account balances, and inserts transfer_out / transfer_in transactions.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
--
-- This draft intentionally does not include executable test insert/update/delete
-- statements.
--
-- Reference call example with placeholder IDs only. Do not run as-is.
--
-- select *
-- from public.school_create_account_transfer(
--   p_transfer_date := date '2026-06-06',
--   p_business_entity_id := '00000000-0000-0000-0000-000000000000',
--   p_from_account_id := '00000000-0000-0000-0000-000000000000',
--   p_to_account_id := '00000000-0000-0000-0000-000000000001',
--   p_amount := 1000,
--   p_reason := 'account transfer',
--   p_note := null
-- );
