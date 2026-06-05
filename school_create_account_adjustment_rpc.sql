-- school_create_account_adjustment_rpc.sql
-- RPC: public.school_create_account_adjustment
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Verified: v2.28.10-account-adjustment-rpc-commit-test-20260606
-- Version: v2.28.7-account-adjustment-rpc-sql-draft-20260606
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test succeeded with no persisted adjustment, account transaction, or account balance changes.
-- - Commit test succeeded with adjustment, account, and account transaction consistency verified.
-- - amount = 0 rejected.
-- - Empty reason rejected.
--
-- Scope:
-- - Create one manual school account adjustment record.
-- - Update school account current_balance.
-- - Insert one related account_adjustment account transaction.
-- - Link the adjustment record back to the account transaction.
-- - Run all operations in one DB transaction.
--
-- Not supported in this first version:
-- - Adjustment edit/delete/reversal.
-- - Cross-account transfer.
-- - Income, expense, reimbursement, payment, or settlement creation.
-- - Frontend implementation.
-- - Idempotency keys for duplicate submit protection.
--
-- Review before execution:
-- - Confirm public.school_account_adjustments exists and was verified.
-- - Confirm transaction_type value account_adjustment.
-- - Confirm negative balance_after is intentionally allowed.
-- - Confirm permissions / grants separately before enabling.

create or replace function public.school_create_account_adjustment(
  p_adjustment_date date,
  p_business_entity_id uuid,
  p_account_id uuid,
  p_amount numeric,
  p_reason text,
  p_note text default null
)
returns table (
  adjustment_id uuid,
  account_transaction_id uuid,
  account_id uuid,
  business_entity_id uuid,
  old_balance numeric,
  new_balance numeric,
  amount numeric,
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
  v_business_entity public.school_business_entities%rowtype;
  v_account public.school_accounts%rowtype;
  v_adjustment_id uuid;
  v_account_transaction_id uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_year_month text;
  v_old_balance numeric;
  v_new_balance numeric;
begin
  if p_adjustment_date is null then
    raise exception '请选择调整日期。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_account_id is null then
    raise exception '请选择调整账户。';
  end if;

  if p_amount is null or p_amount = 0 then
    raise exception '调整金额不能为 0。';
  end if;

  if v_reason is null then
    raise exception '调整原因不能为空。';
  end if;

  select *
  into v_business_entity
  from public.school_business_entities be
  where be.id = p_business_entity_id
    and be.is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  select *
  into v_account
  from public.school_accounts a
  where a.id = p_account_id
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '调整账户不存在或不可用。';
  end if;

  if v_account.is_active is not true then
    raise exception '调整账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '调整账户与业务归属不一致。';
  end if;

  if v_account.currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该账户币种：%。', v_account.currency;
  end if;

  v_year_month := to_char(p_adjustment_date, 'YYYY-MM');
  v_old_balance := coalesce(v_account.current_balance, 0);
  v_new_balance := v_old_balance + p_amount;

  insert into public.school_account_adjustments (
    business_entity_id,
    account_id,
    adjustment_date,
    year_month,
    currency,
    amount,
    balance_before,
    balance_after,
    reason,
    note,
    status,
    account_transaction_id,
    reversed_at,
    reversal_reason,
    reversal_account_transaction_id,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    v_account.id,
    p_adjustment_date,
    v_year_month,
    v_account.currency,
    p_amount,
    v_old_balance,
    v_new_balance,
    v_reason,
    v_note,
    'posted',
    null,
    null,
    null,
    null,
    'school',
    v_now,
    v_now
  )
  returning id into v_adjustment_id;

  update public.school_accounts a
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where a.id = v_account.id;

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
    v_account.id,
    p_business_entity_id,
    p_adjustment_date,
    v_year_month,
    'account_adjustment',
    'school_account_adjustments',
    v_adjustment_id,
    v_account.currency,
    p_amount,
    v_new_balance,
    '账户调整：' || v_reason,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_account_transaction_id;

  update public.school_account_adjustments a
  set
    account_transaction_id = v_account_transaction_id,
    updated_at = v_now
  where a.id = v_adjustment_id;

  return query
  select
    v_adjustment_id,
    v_account_transaction_id,
    v_account.id,
    p_business_entity_id,
    v_old_balance,
    v_new_balance,
    p_amount,
    v_account.currency,
    v_year_month,
    'posted'::text,
    'account_adjustment'::text;
end;
$$;

comment on function public.school_create_account_adjustment(
  date,
  uuid,
  uuid,
  numeric,
  text,
  text
) is
  'Draft RPC for v2 account adjustment creation: creates account adjustment, updates account balance, and inserts account_adjustment transaction.';

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
-- from public.school_create_account_adjustment(
--   p_adjustment_date := date '2026-06-06',
--   p_business_entity_id := '00000000-0000-0000-0000-000000000000',
--   p_account_id := '00000000-0000-0000-0000-000000000000',
--   p_amount := 1000,
--   p_reason := 'manual balance correction',
--   p_note := null
-- );
