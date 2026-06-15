-- school_reverse_income_record_rpc.sql
-- Purpose: Reverse a received income record by inserting a negative account transaction,
--          restoring the original income account balance, and marking the income as reversed.
-- Status: EXECUTED ON SUPABASE. Rollback-tested. Commit-tested.
-- Verified: v2.26.11-income-reversal-rpc-verified-sql-commit-20260605
-- Version: v2.26.7-income-reversal-rpc-sql-draft-20260605
-- Verification:
--   - Function exists with expected signature and return columns.
--   - Rollback test succeeded with no persisted income, account, or account transaction changes.
--   - Commit test succeeded with income, account, and account transaction consistency verified.
--   - Duplicate reversal is rejected without a second write.
--   - Expected failure cases rejected.
-- Scope:
--   - Reverse received income records only.
--   - Keep original income records and original income_adjust account transactions.
--   - Insert one negative income_reversal account transaction.
--   - Update income reversal metadata fields.
--   - Does not delete historical data.
--   - Does not support student_payment linked income, personal Cash-linked
--     tuition income, partial reversal, frontend, attachments, OCR, or statistics.
-- Review before execution:
--   - Confirm transaction_type value income_reversal.
--   - Confirm status value reversed is accepted.
--   - Confirm locked student monthly settlement rules.

create or replace function public.school_reverse_income_record(
  p_income_id uuid,
  p_reversal_date date,
  p_reason text default null
)
returns table (
  income_id uuid,
  reversal_account_transaction_id uuid,
  account_id uuid,
  account_new_balance numeric,
  amount numeric,
  currency text,
  year_month text,
  status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_year_month text;
  v_income public.school_income_records%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_account public.school_accounts%rowtype;
  v_original_transaction_count integer := 0;
  v_existing_reversal_count integer := 0;
  v_locked_settlement_count integer := 0;
  v_new_balance numeric;
  v_reversal_transaction_id uuid;
begin
  if p_income_id is null then
    raise exception '请选择要撤销的收入记录。';
  end if;

  if p_reversal_date is null then
    raise exception '请选择撤销日期。';
  end if;

  select *
  into v_income
  from public.school_income_records i
  where i.id = p_income_id
    and coalesce(i.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '收入记录不存在。';
  end if;

  if v_income.status = 'reversed'
    or v_income.reversed_at is not null
    or v_income.reversal_account_transaction_id is not null then
    raise exception '该收入已撤销，不能重复撤销。';
  end if;

  if v_income.status is distinct from 'received' then
    raise exception '只能撤销已收款收入。';
  end if;

  if v_income.student_payment_id is not null then
    raise exception '关联学生收款链路的收入暂不支持通过普通收入撤销处理。';
  end if;

  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = v_income.id
      and e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
      and (
        e.cash_transaction_id is not null
        or e.sync_status = 'synced'
        or e.cash_request_status in ('approved', 'synced')
      )
  ) then
    raise exception 'income record has been synced to Cash and cannot be edited or deleted directly';
  end if;

  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = v_income.id
      and e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
      and (
        e.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
        or e.cash_request_status = 'pending'
      )
  ) then
    raise exception 'income record has a pending Cash request and cannot be reversed directly';
  end if;

  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = v_income.id
      and e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
  ) then
    raise exception '该收入已进入 Cash System 联动流程，当前版本暂不支持普通收入撤销。';
  end if;

  if coalesce(v_income.amount, 0) <= 0
    or nullif(trim(coalesce(v_income.currency, '')), '') is null then
    raise exception '收入记录金额或币种无效，不能撤销。';
  end if;

  select count(*)::integer
  into v_existing_reversal_count
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_reversal';

  if v_existing_reversal_count > 0 then
    raise exception '该收入已撤销，不能重复撤销。';
  end if;

  select count(*)::integer
  into v_original_transaction_count
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_adjust';

  if v_original_transaction_count <> 1 then
    raise exception '收入原始账户流水不存在或不唯一。';
  end if;

  select *
  into v_original_transaction
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_adjust'
  for update;

  if v_original_transaction.amount is distinct from v_income.amount then
    raise exception '收入原始账户流水金额不一致，不能撤销。';
  end if;

  if v_original_transaction.account_id is distinct from v_income.account_id
    or v_original_transaction.currency is distinct from v_income.currency then
    raise exception '收入原始账户流水账户或币种不一致，不能撤销。';
  end if;

  select *
  into v_account
  from public.school_accounts a
  where a.id = v_income.account_id
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '入账账户不存在或不可用。';
  end if;

  if v_account.is_active is not true
    or v_account.business_entity_id is distinct from v_income.business_entity_id
    or v_account.currency is distinct from v_income.currency then
    raise exception '入账账户不存在或不可用。';
  end if;

  if coalesce(v_income.include_in_student_settlement, false)
    and v_income.student_id is not null
    and nullif(trim(coalesce(v_income.settlement_month, '')), '') is not null
    and v_income.business_entity_id is not null then
    select count(*)::integer
    into v_locked_settlement_count
    from public.school_student_monthly_settlements s
    where s.student_id = v_income.student_id
      and s.business_entity_id = v_income.business_entity_id
      and s.year_month = v_income.settlement_month
      and s.settlement_status = 'locked';

    if v_locked_settlement_count > 0 then
      raise exception '目标学生月度结算已锁定，不能撤销收入。';
    end if;
  end if;

  v_year_month := to_char(p_reversal_date, 'YYYY-MM');
  v_new_balance := coalesce(v_account.current_balance, 0) - v_income.amount;

  update public.school_accounts a
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where a.id = v_income.account_id;

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
    v_income.account_id,
    v_income.business_entity_id,
    p_reversal_date,
    v_year_month,
    'income_reversal',
    'school_income_records',
    v_income.id,
    v_income.currency,
    -v_income.amount,
    v_new_balance,
    '收入撤销：' || coalesce(v_income.description, ''),
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_transaction_id;

  update public.school_income_records i
  set
    status = 'reversed',
    reversed_at = v_now,
    reversal_reason = v_reason,
    reversal_account_transaction_id = v_reversal_transaction_id,
    updated_at = v_now
  where i.id = v_income.id;

  return query
  select
    v_income.id,
    v_reversal_transaction_id,
    v_income.account_id,
    v_new_balance,
    v_income.amount,
    v_income.currency,
    v_year_month,
    'reversed'::text;
end;
$$;

comment on function public.school_reverse_income_record(
  uuid,
  date,
  text
) is
  'Guarded RPC for v2 income reversal: marks a received income as reversed, restores account balance, inserts a negative income_reversal transaction, and rejects personal Cash-linked tuition income.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
