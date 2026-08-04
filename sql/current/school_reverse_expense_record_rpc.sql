-- school_reverse_expense_record_rpc.sql
-- Purpose: Reverse a paid ordinary expense record by inserting a positive account transaction,
--          restoring the original expense account balance, and marking the expense as reversed.
-- Status: EXECUTED ON SUPABASE. Rollback-tested. Commit-tested.
-- Verified: v2.25.14-expense-reversal-rpc-verified-sql-commit-20260604
-- Scope:
--   - Reverse paid ordinary school expense records only.
--   - Keep original expense records and original expense_adjust account transactions.
--   - Insert one positive expense_reversal account transaction.
--   - Update expense reversal metadata fields.
--   - Does not delete historical data.
--   - Does not support teacher_wage, partial reversal, frontend, attachments, OCR, or statistics.
-- Review before execution:
--   - Confirm transaction_type value expense_reversal.
--   - Confirm status value reversed is accepted.
--   - Confirm expense reimbursement_status rules with reimbursement history.

create or replace function public.school_reverse_expense_record(
  p_expense_id uuid,
  p_reversal_date date,
  p_reason text default null
)
returns table (
  expense_id uuid,
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
set search_path = pg_catalog, public
as $$
declare
  v_now timestamptz := now();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_year_month text;
  v_expense public.school_expense_records%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_account public.school_accounts%rowtype;
  v_original_transaction_count integer := 0;
  v_existing_reversal_count integer := 0;
  v_paid_reimbursement_count integer := 0;
  v_new_balance numeric;
  v_reversal_transaction_id uuid;
begin
  perform public.school_require_current_app_admin();

  if p_expense_id is null then
    raise exception '请选择要撤销的支出记录。';
  end if;

  if p_reversal_date is null then
    raise exception '请选择撤销日期。';
  end if;

  select *
  into v_expense
  from public.school_expense_records e
  where e.id = p_expense_id
    and coalesce(e.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '支出记录不存在。';
  end if;

  if v_expense.status = 'reversed'
    or v_expense.reversed_at is not null
    or v_expense.reversal_account_transaction_id is not null then
    raise exception '该支出已撤销，不能重复撤销。';
  end if;

  if v_expense.cash_transaction_id is not null
    or v_expense.cash_request_status in ('approved', 'synced') then
    raise exception 'expense record has been synced to Cash and cannot be edited or deleted directly';
  end if;

  if v_expense.cash_request_status in ('pending', 'pending_cash_request') then
    raise exception 'expense record has a pending Cash request and cannot be reversed directly';
  end if;

  if v_expense.status is distinct from 'paid' then
    raise exception '只能撤销已支付支出。';
  end if;

  if v_expense.expense_category = 'teacher_wage' then
    raise exception '老师工资支出不能通过普通支出撤销处理。';
  end if;

  if coalesce(v_expense.amount, 0) <= 0
    or nullif(trim(coalesce(v_expense.currency, '')), '') is null then
    raise exception '支出记录金额或币种无效，不能撤销。';
  end if;

  if v_expense.reimbursement_status is distinct from 'pending'
    and v_expense.reimbursement_status is distinct from 'not_required' then
    if v_expense.reimbursement_status = 'paid' then
      raise exception '该支出已被报销确认，请先撤销报销记录。';
    end if;

    raise exception '只能撤销待报销或无需报销的普通支出。';
  end if;

  select count(*)::integer
  into v_existing_reversal_count
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = v_expense.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'expense_reversal';

  if v_existing_reversal_count > 0 then
    raise exception '该支出已撤销，不能重复撤销。';
  end if;

  select count(*)::integer
  into v_original_transaction_count
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = v_expense.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'expense_adjust';

  if v_original_transaction_count <> 1 then
    raise exception '支出原始账户流水不存在或不唯一。';
  end if;

  select *
  into v_original_transaction
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = v_expense.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'expense_adjust'
  for update;

  if v_original_transaction.amount is distinct from -v_expense.amount then
    raise exception '支出原始账户流水金额不一致，不能撤销。';
  end if;

  if v_original_transaction.account_id is distinct from v_expense.account_id
    or v_original_transaction.currency is distinct from v_expense.currency then
    raise exception '支出原始账户流水账户或币种不一致，不能撤销。';
  end if;

  select *
  into v_account
  from public.school_accounts a
  where a.id = v_expense.account_id
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '支出账户不存在或不可用。';
  end if;

  if v_account.is_active is not true
    or v_account.business_entity_id is distinct from v_expense.business_entity_id
    or v_account.currency is distinct from v_expense.currency then
    raise exception '支出账户不存在或不可用。';
  end if;

  select count(*)::integer
  into v_paid_reimbursement_count
  from public.school_reimbursement_items items
  join public.school_reimbursements r
    on r.id = items.reimbursement_id
  where items.expense_id = v_expense.id
    and coalesce(items.app_type, '') = 'school'
    and coalesce(r.app_type, '') = 'school'
    and r.status = 'paid';

  if v_paid_reimbursement_count > 0 then
    raise exception '该支出已被报销确认，请先撤销报销记录。';
  end if;

  v_year_month := to_char(p_reversal_date, 'YYYY-MM');
  v_new_balance := coalesce(v_account.current_balance, 0) + v_expense.amount;

  update public.school_accounts a
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where a.id = v_expense.account_id;

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
    v_expense.account_id,
    v_expense.business_entity_id,
    p_reversal_date,
    v_year_month,
    'expense_reversal',
    'school_expense_records',
    v_expense.id,
    v_expense.currency,
    v_expense.amount,
    v_new_balance,
    '支出撤销：' || coalesce(v_expense.description, ''),
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_transaction_id;

  update public.school_expense_records e
  set
    status = 'reversed',
    reversed_at = v_now,
    reversal_reason = v_reason,
    reversal_account_transaction_id = v_reversal_transaction_id,
    updated_at = v_now
  where e.id = v_expense.id;

  return query
  select
    v_expense.id,
    v_reversal_transaction_id,
    v_expense.account_id,
    v_new_balance,
    v_expense.amount,
    v_expense.currency,
    v_year_month,
    'reversed'::text;
end;
$$;

comment on function public.school_reverse_expense_record(
  uuid,
  date,
  text
) is
  'Active-admin v2 ordinary expense reversal: marks a paid expense as reversed, restores account balance, and inserts a positive expense_reversal transaction.';

revoke all on function public.school_reverse_expense_record(uuid,date,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_reverse_expense_record(uuid,date,text)
  to authenticated;
