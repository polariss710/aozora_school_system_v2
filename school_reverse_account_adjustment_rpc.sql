-- school_reverse_account_adjustment_rpc.sql
-- RPC: public.school_reverse_account_adjustment
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Verified: v2.30.6-account-adjustment-reversal-rpc-commit-test-20260606
-- Version: v2.30.3-account-adjustment-reversal-rpc-sql-draft-20260606
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test succeeded with no persisted adjustment, account transaction, or account balance changes.
-- - Commit test succeeded with adjustment, account, and account transaction consistency verified.
-- - Duplicate reversal is rejected without a second write.
-- - Null reversal date rejected.
-- - Missing adjustment id rejected.
--
-- Scope:
-- - Reverse one posted manual school account adjustment.
-- - Keep the original adjustment record and original account_adjustment transaction.
-- - Insert one related account_adjustment_reversal account transaction.
-- - Update school account current_balance by subtracting the original adjustment amount.
-- - Update school_account_adjustments reversal metadata fields.
-- - Run all operations in one DB transaction.
--
-- Not supported in this first version:
-- - Deleting adjustment records.
-- - Partial reversal.
-- - Reversing non-account-adjustment business facts.
-- - Frontend implementation.
-- - Idempotency keys for duplicate submit protection.
--
-- Review before execution:
-- - Confirm public.school_account_adjustments exists with reversal fields.
-- - Confirm transaction_type value account_adjustment_reversal.
-- - Confirm negative balance_after is intentionally allowed.
-- - Confirm permissions / grants separately before enabling.

create or replace function public.school_reverse_account_adjustment(
  p_adjustment_id uuid,
  p_reversal_date date,
  p_reason text default null
)
returns table (
  adjustment_id uuid,
  reversal_account_transaction_id uuid,
  account_id uuid,
  business_entity_id uuid,
  account_old_balance numeric,
  account_new_balance numeric,
  original_amount numeric,
  reversal_amount numeric,
  currency text,
  year_month text,
  status text,
  transaction_type text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_year_month text;
  v_adjustment public.school_account_adjustments%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_account public.school_accounts%rowtype;
  v_original_transaction_count integer := 0;
  v_existing_reversal_count integer := 0;
  v_account_old_balance numeric;
  v_account_new_balance numeric;
  v_reversal_amount numeric;
  v_reversal_transaction_id uuid;
begin
  if p_adjustment_id is null then
    raise exception '请选择要撤销的账户调整。';
  end if;

  if p_reversal_date is null then
    raise exception '请选择撤销日期。';
  end if;

  select *
  into v_adjustment
  from public.school_account_adjustments a
  where a.id = p_adjustment_id
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '账户调整记录不存在。';
  end if;

  if v_adjustment.status = 'reversed'
    or v_adjustment.reversed_at is not null
    or v_adjustment.reversal_account_transaction_id is not null then
    raise exception '该账户调整已撤销，不能重复撤销。';
  end if;

  if v_adjustment.status is distinct from 'posted' then
    raise exception '只能撤销已过账的账户调整。';
  end if;

  if v_adjustment.account_transaction_id is null then
    raise exception '账户调整原始流水缺失，不能撤销。';
  end if;

  if coalesce(v_adjustment.amount, 0) = 0
    or nullif(trim(coalesce(v_adjustment.currency, '')), '') is null then
    raise exception '账户调整金额或币种无效，不能撤销。';
  end if;

  select count(*)::integer
  into v_existing_reversal_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_adjustments'
    and t.related_id = v_adjustment.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'account_adjustment_reversal';

  if v_existing_reversal_count > 0 then
    raise exception '该账户调整已撤销，不能重复撤销。';
  end if;

  select count(*)::integer
  into v_original_transaction_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_adjustments'
    and t.related_id = v_adjustment.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'account_adjustment';

  if v_original_transaction_count <> 1 then
    raise exception '账户调整原始流水不存在或不唯一。';
  end if;

  select *
  into v_original_transaction
  from public.school_account_transactions t
  where t.id = v_adjustment.account_transaction_id
    and t.related_table = 'school_account_adjustments'
    and t.related_id = v_adjustment.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'account_adjustment'
  for update;

  if not found then
    raise exception '账户调整原始流水不存在或不唯一。';
  end if;

  if v_original_transaction.amount is distinct from v_adjustment.amount then
    raise exception '账户调整原始流水金额不一致，不能撤销。';
  end if;

  if v_original_transaction.account_id is distinct from v_adjustment.account_id
    or v_original_transaction.business_entity_id is distinct from v_adjustment.business_entity_id
    or v_original_transaction.currency is distinct from v_adjustment.currency then
    raise exception '账户调整原始流水账户、业务归属或币种不一致，不能撤销。';
  end if;

  select *
  into v_account
  from public.school_accounts a
  where a.id = v_adjustment.account_id
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '调整账户不存在或不可用。';
  end if;

  if v_account.is_active is not true then
    raise exception '调整账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from v_adjustment.business_entity_id
    or v_account.currency is distinct from v_adjustment.currency then
    raise exception '调整账户业务归属或币种不一致。';
  end if;

  v_year_month := to_char(p_reversal_date, 'YYYY-MM');
  v_account_old_balance := coalesce(v_account.current_balance, 0);
  v_reversal_amount := -v_adjustment.amount;
  v_account_new_balance := v_account_old_balance + v_reversal_amount;

  update public.school_accounts a
  set
    current_balance = v_account_new_balance,
    updated_at = v_now
  where a.id = v_adjustment.account_id;

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
    v_adjustment.account_id,
    v_adjustment.business_entity_id,
    p_reversal_date,
    v_year_month,
    'account_adjustment_reversal',
    'school_account_adjustments',
    v_adjustment.id,
    v_adjustment.currency,
    v_reversal_amount,
    v_account_new_balance,
    '账户调整撤销：' || coalesce(v_reason, v_adjustment.reason, ''),
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_transaction_id;

  update public.school_account_adjustments a
  set
    status = 'reversed',
    reversed_at = v_now,
    reversal_reason = v_reason,
    reversal_account_transaction_id = v_reversal_transaction_id,
    updated_at = v_now
  where a.id = v_adjustment.id;

  return query
  select
    v_adjustment.id,
    v_reversal_transaction_id,
    v_adjustment.account_id,
    v_adjustment.business_entity_id,
    v_account_old_balance,
    v_account_new_balance,
    v_adjustment.amount,
    v_reversal_amount,
    v_adjustment.currency,
    v_year_month,
    'reversed'::text,
    'account_adjustment_reversal'::text;
end;
$$;

comment on function public.school_reverse_account_adjustment(
  uuid,
  date,
  text
) is
  'Draft RPC for v2 account adjustment reversal: marks an account adjustment as reversed, restores account balance by the opposite amount, and inserts an account_adjustment_reversal transaction.';

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
-- from public.school_reverse_account_adjustment(
--   p_adjustment_id := '00000000-0000-0000-0000-000000000000',
--   p_reversal_date := date '2026-06-06',
--   p_reason := 'manual account adjustment reversal'
-- );
