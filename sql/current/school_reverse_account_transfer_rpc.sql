-- school_reverse_account_transfer_rpc.sql
-- RPC: public.school_reverse_account_transfer
-- Purpose: Reverse a posted account-to-account transfer with two reversal
--          account transactions and two account balance updates.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Verified: v2.34.1-account-transfer-reversal-full-autopilot-trial-20260606
-- Version: v2.34.1-account-transfer-reversal-full-autopilot-trial-20260606
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - school_account_transactions has no transaction_type check constraint blocking transfer_reverse_in / transfer_reverse_out.
-- - Rollback test succeeded with no persisted transfer, account transaction, or account balance changes.
-- - Commit test succeeded with one whitelisted codex-test transfer, two reversal account transactions, and account balance consistency verified.
-- - Duplicate reversal is rejected without a second write.
-- - Null reversal date and missing transfer id are rejected.
--
-- Scope:
-- - Reverse one posted school account transfer.
-- - Keep the original transfer record and original transfer_out / transfer_in
--   account transactions.
-- - Insert one transfer_reverse_in transaction for the original from_account.
-- - Insert one transfer_reverse_out transaction for the original to_account.
-- - Update from_account current_balance by +amount and to_account current_balance by -amount.
-- - Update school_account_transfers reversal metadata fields.
-- - Run all operations in one DB transaction.
--
-- Not supported in this first version:
-- - Deleting transfer records.
-- - Partial reversal.
-- - Reversing non-transfer business facts.
-- - Idempotency keys for duplicate submit protection.
--
-- Review before execution:
-- - Confirm public.school_account_transfers exists with reversal fields.
-- - Confirm transaction_type values transfer_reverse_in / transfer_reverse_out.
-- - Confirm negative balance_after is intentionally allowed.
-- - Confirm permissions / grants separately before enabling.

create or replace function public.school_reverse_account_transfer(
  p_transfer_id uuid,
  p_reversal_date date,
  p_reason text default null
)
returns table (
  transfer_id uuid,
  reversal_from_account_transaction_id uuid,
  reversal_to_account_transaction_id uuid,
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
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_year_month text;
  v_transfer public.school_account_transfers%rowtype;
  v_original_out public.school_account_transactions%rowtype;
  v_original_in public.school_account_transactions%rowtype;
  v_account public.school_accounts%rowtype;
  v_from_account public.school_accounts%rowtype;
  v_to_account public.school_accounts%rowtype;
  v_account_count integer := 0;
  v_original_out_count integer := 0;
  v_original_in_count integer := 0;
  v_existing_reverse_count integer := 0;
  v_from_account_old_balance numeric;
  v_from_account_new_balance numeric;
  v_to_account_old_balance numeric;
  v_to_account_new_balance numeric;
  v_reversal_from_transaction_id uuid;
  v_reversal_to_transaction_id uuid;
begin
  if p_transfer_id is null then
    raise exception '请选择要撤销的账户转账。';
  end if;

  if p_reversal_date is null then
    raise exception '请选择撤销日期。';
  end if;

  select *
  into v_transfer
  from public.school_account_transfers t
  where t.id = p_transfer_id
    and coalesce(t.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '账户转账记录不存在。';
  end if;

  if v_transfer.status = 'reversed'
    or v_transfer.reversed_at is not null
    or v_transfer.reversal_from_account_transaction_id is not null
    or v_transfer.reversal_to_account_transaction_id is not null then
    raise exception '该账户转账已撤销，不能重复撤销。';
  end if;

  if v_transfer.status is distinct from 'posted' then
    raise exception '只能撤销已过账的账户转账。';
  end if;

  if v_transfer.from_account_transaction_id is null
    or v_transfer.to_account_transaction_id is null then
    raise exception '账户转账原始流水缺失，不能撤销。';
  end if;

  if coalesce(v_transfer.amount, 0) <= 0
    or nullif(trim(coalesce(v_transfer.currency, '')), '') is null then
    raise exception '账户转账金额或币种无效，不能撤销。';
  end if;

  select count(*)::integer
  into v_existing_reverse_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type in ('transfer_reverse_in', 'transfer_reverse_out');

  if v_existing_reverse_count > 0 then
    raise exception '该账户转账已撤销，不能重复撤销。';
  end if;

  select count(*)::integer
  into v_original_out_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'transfer_out';

  if v_original_out_count <> 1 then
    raise exception '账户转账原始转出流水不存在或不唯一。';
  end if;

  select *
  into v_original_out
  from public.school_account_transactions t
  where t.id = v_transfer.from_account_transaction_id
    and t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'transfer_out'
  for update;

  if not found then
    raise exception '账户转账原始转出流水不存在或不唯一。';
  end if;

  select count(*)::integer
  into v_original_in_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'transfer_in';

  if v_original_in_count <> 1 then
    raise exception '账户转账原始转入流水不存在或不唯一。';
  end if;

  select *
  into v_original_in
  from public.school_account_transactions t
  where t.id = v_transfer.to_account_transaction_id
    and t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'transfer_in'
  for update;

  if not found then
    raise exception '账户转账原始转入流水不存在或不唯一。';
  end if;

  if v_original_out.account_id is distinct from v_transfer.from_account_id
    or v_original_out.business_entity_id is distinct from v_transfer.business_entity_id
    or v_original_out.currency is distinct from v_transfer.currency
    or v_original_out.amount is distinct from -v_transfer.amount
    or v_original_in.account_id is distinct from v_transfer.to_account_id
    or v_original_in.business_entity_id is distinct from v_transfer.business_entity_id
    or v_original_in.currency is distinct from v_transfer.currency
    or v_original_in.amount is distinct from v_transfer.amount then
    raise exception '账户转账原始流水金额、账户、业务归属或币种不一致，不能撤销。';
  end if;

  for v_account in
    select *
    from public.school_accounts a
    where a.id = any (array[v_transfer.from_account_id, v_transfer.to_account_id])
    order by a.id
    for update
  loop
    v_account_count := v_account_count + 1;

    if v_account.id = v_transfer.from_account_id then
      v_from_account := v_account;
    elsif v_account.id = v_transfer.to_account_id then
      v_to_account := v_account;
    end if;
  end loop;

  if v_account_count <> 2 then
    raise exception '账户转账账户不存在或不可用。';
  end if;

  if coalesce(v_from_account.app_type, '') <> 'school'
    or coalesce(v_to_account.app_type, '') <> 'school'
    or v_from_account.is_active is not true
    or v_to_account.is_active is not true then
    raise exception '账户转账账户不存在或不可用。';
  end if;

  if v_from_account.business_entity_id is distinct from v_transfer.business_entity_id
    or v_to_account.business_entity_id is distinct from v_transfer.business_entity_id
    or v_from_account.currency is distinct from v_transfer.currency
    or v_to_account.currency is distinct from v_transfer.currency then
    raise exception '账户转账账户业务归属或币种不一致。';
  end if;

  v_year_month := to_char(p_reversal_date, 'YYYY-MM');
  v_from_account_old_balance := coalesce(v_from_account.current_balance, 0);
  v_to_account_old_balance := coalesce(v_to_account.current_balance, 0);
  v_from_account_new_balance := v_from_account_old_balance + v_transfer.amount;
  v_to_account_new_balance := v_to_account_old_balance - v_transfer.amount;

  update public.school_accounts a
  set
    current_balance = v_from_account_new_balance,
    updated_at = v_now
  where a.id = v_transfer.from_account_id;

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
    v_transfer.from_account_id,
    v_transfer.business_entity_id,
    p_reversal_date,
    v_year_month,
    'transfer_reverse_in',
    'school_account_transfers',
    v_transfer.id,
    v_transfer.currency,
    v_transfer.amount,
    v_from_account_new_balance,
    '账户转账撤销入金：' || coalesce(v_reason, v_transfer.reason, ''),
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_from_transaction_id;

  update public.school_accounts a
  set
    current_balance = v_to_account_new_balance,
    updated_at = v_now
  where a.id = v_transfer.to_account_id;

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
    v_transfer.to_account_id,
    v_transfer.business_entity_id,
    p_reversal_date,
    v_year_month,
    'transfer_reverse_out',
    'school_account_transfers',
    v_transfer.id,
    v_transfer.currency,
    -v_transfer.amount,
    v_to_account_new_balance,
    '账户转账撤销出金：' || coalesce(v_reason, v_transfer.reason, ''),
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_to_transaction_id;

  update public.school_account_transfers t
  set
    status = 'reversed',
    reversed_at = v_now,
    reversal_reason = v_reason,
    reversal_from_account_transaction_id = v_reversal_from_transaction_id,
    reversal_to_account_transaction_id = v_reversal_to_transaction_id,
    updated_at = v_now
  where t.id = v_transfer.id;

  return query
  select
    v_transfer.id,
    v_reversal_from_transaction_id,
    v_reversal_to_transaction_id,
    v_transfer.from_account_id,
    v_transfer.to_account_id,
    v_transfer.business_entity_id,
    v_from_account_old_balance,
    v_from_account_new_balance,
    v_to_account_old_balance,
    v_to_account_new_balance,
    v_transfer.amount,
    v_transfer.currency,
    v_year_month,
    'reversed'::text,
    'transfer_reverse_in'::text,
    'transfer_reverse_out'::text;
end;
$$;

comment on function public.school_reverse_account_transfer(
  uuid,
  date,
  text
) is
  'Draft RPC for v2 account transfer reversal: marks an account transfer as reversed, restores the original from-account balance, reverses the original to-account balance, and inserts transfer_reverse_in / transfer_reverse_out transactions.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
--
-- This draft intentionally does not include executable test insert/update/delete
-- statements outside the function definition.
--
-- Reference call example with placeholder IDs only. Do not run as-is.
--
-- select *
-- from public.school_reverse_account_transfer(
--   p_transfer_id := '00000000-0000-0000-0000-000000000000',
--   p_reversal_date := date '2026-06-06',
--   p_reason := 'manual account transfer reversal'
-- );
