-- school_update_expense_record_rpc.sql
-- RPC: public.school_update_expense_record
-- Purpose: guarded v2 edit for ordinary paid expense records.
-- Status: EXECUTED ON SUPABASE. Rollback-tested, whitelist commit-tested,
--         and browser-verified through API/frontend on 2026-06-12.
--
-- Scope:
-- - Update one ordinary paid expense row.
-- - Keep writes inside expense/account/account-transaction chain.
-- - Adjust the linked account current_balance and original expense_adjust
--   transaction only when the original transaction is still the latest
--   transaction for the account.
-- - Reject reversed expenses, teacher wage / payment request source expenses,
--   reimbursed expenses, reimbursement-linked expenses, account changes,
--   currency mismatches, Cash-synced or Cash-pending expenses, and abnormal
--   account transaction history.
--
-- Notes:
-- - Account currency is not user-maintained. The selected account owns the
--   currency; the dialog does not expose account currency as a field.
-- - Teacher/student/is_business_expense are not ordinary v2 edit fields.
--   Existing hidden values are preserved by this RPC.
-- - If the account must change, use the reversal flow and create a new expense.
--
-- Verified test data:
-- - business_entity_id f500595d-5455-4460-b826-757c8f834d20
-- - account_id 7ea665f1-74b0-4177-90d8-6e79002e3082
-- - expense_id e37287bc-81f2-4714-b79c-a31894b8144b
-- - account_transaction_id f444efb6-7f32-4b39-93d7-69ed3ce9b235

create or replace function public.school_update_expense_record(
  p_expense_id uuid,
  p_expense_date date,
  p_business_entity_id uuid,
  p_account_id uuid,
  p_expense_category text,
  p_description text,
  p_currency text,
  p_amount numeric,
  p_exchange_rate numeric default null,
  p_payment_method text default null,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_reimbursement_status text default null,
  p_note text default null
)
returns table (
  expense_id uuid,
  account_transaction_id uuid,
  account_id uuid,
  new_balance numeric,
  expense_status text,
  transaction_type text,
  year_month text,
  reimbursement_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_expense public.school_expense_records%rowtype;
  v_business_entity public.school_business_entities%rowtype;
  v_account public.school_accounts%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_category text := lower(trim(coalesce(p_expense_category, '')));
  v_description text := nullif(trim(coalesce(p_description, '')), '');
  v_payment_method text := nullif(trim(coalesce(p_payment_method, '')), '');
  v_tax_category text := nullif(trim(coalesce(p_tax_category, '')), '');
  v_receipt_status text := coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), '待确认');
  v_reimbursement_status text := nullif(trim(coalesce(p_reimbursement_status, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_year_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_amount_delta numeric;
  v_new_balance numeric;
  v_original_transaction_count integer := 0;
  v_existing_reversal_count integer := 0;
  v_payment_request_count integer := 0;
  v_reimbursement_item_count integer := 0;
begin
  if p_expense_id is null then
    raise exception '请选择要编辑的支出记录。';
  end if;

  if p_expense_date is null then
    raise exception '请选择支出日期。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_account_id is null then
    raise exception '请选择付款账户。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '支出金额必须大于 0。';
  end if;

  if v_description is null then
    raise exception '支出内容不能为空。';
  end if;

  if v_category = '' then
    raise exception '支出分类不能为空。';
  end if;

  if v_category = 'teacher_wage' then
    raise exception '老师工资支出请通过老师工资支付流程维护。';
  end if;

  if v_category not in ('classroom', 'other', 'tax_accounting', 'advertising', 'software') then
    raise exception '暂不支持该支出分类。';
  end if;

  if v_currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该支出币种：%。', v_currency;
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  if v_payment_method is null then
    raise exception '请选择支付方式。';
  end if;

  if v_payment_method not in ('cash', 'bank_transfer', 'card', 'alipay') then
    raise exception '支付方式无效。';
  end if;

  if v_receipt_status not in ('有', '无需收据', '待确认') then
    raise exception '收据状态无效。';
  end if;

  if v_reimbursement_status is null then
    raise exception '请选择报销状态。';
  end if;

  if v_reimbursement_status not in ('not_required', 'pending') then
    raise exception '报销状态无效。';
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
    raise exception '已撤销支出不能编辑。';
  end if;

  if v_expense.cash_transaction_id is not null
    or v_expense.cash_request_status in ('approved', 'synced') then
    raise exception 'expense record has been synced to Cash and cannot be edited or deleted directly';
  end if;

  if v_expense.cash_request_status in ('pending', 'pending_cash_request') then
    raise exception 'expense record has a pending Cash request and core fields cannot be edited directly';
  end if;

  if v_expense.status is distinct from 'paid' then
    raise exception '只能编辑已支付支出。';
  end if;

  if v_expense.expense_category = 'teacher_wage'
    or v_expense.salary_payment_id is not null then
    raise exception '老师工资或工资支付来源支出不能通过普通支出编辑。';
  end if;

  if v_expense.reimbursement_status = 'paid' then
    raise exception '已报销支出不能编辑。';
  end if;

  if p_account_id is distinct from v_expense.account_id then
    raise exception '已出账支出暂不支持更换付款账户。请撤销后重新新增。';
  end if;

  select count(*)::integer
  into v_payment_request_count
  from public.school_payment_requests pr
  where pr.paid_expense_id = v_expense.id;

  if v_payment_request_count > 0 then
    raise exception '来源支付请求生成的支出不能通过普通支出编辑。';
  end if;

  select count(*)::integer
  into v_reimbursement_item_count
  from public.school_reimbursement_items items
  where items.expense_id = v_expense.id
    and coalesce(items.app_type, '') = 'school';

  if v_reimbursement_item_count > 0 then
    raise exception '已进入报销链路的支出不能编辑。';
  end if;

  select count(*)::integer
  into v_existing_reversal_count
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = v_expense.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'expense_reversal';

  if v_existing_reversal_count > 0 then
    raise exception '已存在支出撤销流水，不能编辑。';
  end if;

  select count(*)::integer
  into v_original_transaction_count
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = v_expense.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'expense_adjust';

  if v_original_transaction_count <> 1 then
    raise exception '支出原始账户流水不存在或不唯一，不能编辑。';
  end if;

  select *
  into v_original_transaction
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = v_expense.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'expense_adjust'
  for update;

  if v_original_transaction.amount is distinct from -v_expense.amount
    or v_original_transaction.account_id is distinct from v_expense.account_id
    or v_original_transaction.currency is distinct from v_expense.currency then
    raise exception '支出原始账户流水与支出记录不一致，不能编辑。';
  end if;

  if exists (
    select 1
    from public.school_account_transactions t
    where t.account_id = v_original_transaction.account_id
      and coalesce(t.app_type, '') = 'school'
      and (
        t.created_at > v_original_transaction.created_at
        or (t.created_at = v_original_transaction.created_at and t.id::text > v_original_transaction.id::text)
      )
  ) then
    raise exception '该支出之后已有账户流水，不能直接编辑会影响余额的字段。请使用撤销后重新新增。';
  end if;

  select *
  into v_business_entity
  from public.school_business_entities
  where id = p_business_entity_id
    and is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  select *
  into v_account
  from public.school_accounts
  where id = p_account_id
    and app_type = 'school'
  for update;

  if not found then
    raise exception '付款账户无效。';
  end if;

  if v_account.is_active is not true then
    raise exception '付款账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '付款账户与业务归属不一致。';
  end if;

  if v_account.currency is distinct from v_currency then
    raise exception '付款账户币种必须与支出币种一致。';
  end if;

  if v_currency = 'JPY' then
    v_amount_jpy := p_amount;
    v_amount_cny := case
      when p_exchange_rate is not null then p_amount / p_exchange_rate
      else null
    end;
  else
    v_amount_cny := p_amount;
    v_amount_jpy := case
      when p_exchange_rate is not null then p_amount * p_exchange_rate
      else null
    end;
  end if;

  v_year_month := to_char(p_expense_date, 'YYYY-MM');
  v_amount_delta := p_amount - v_expense.amount;
  v_new_balance := coalesce(v_account.current_balance, 0) - v_amount_delta;

  update public.school_accounts a
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where a.id = v_account.id;

  update public.school_account_transactions t
  set
    business_entity_id = p_business_entity_id,
    transaction_date = p_expense_date,
    year_month = v_year_month,
    currency = v_account.currency,
    amount = -p_amount,
    balance_after = v_new_balance,
    description = '支出出账：' || v_description,
    note = v_note,
    updated_at = v_now
  where t.id = v_original_transaction.id;

  update public.school_expense_records e
  set
    business_entity_id = p_business_entity_id,
    account_id = p_account_id,
    expense_date = p_expense_date,
    year_month = v_year_month,
    expense_category = v_category,
    description = v_description,
    currency = v_account.currency,
    amount = p_amount,
    amount_jpy = v_amount_jpy,
    amount_cny = v_amount_cny,
    exchange_rate = p_exchange_rate,
    payment_method = v_payment_method,
    tax_category = v_tax_category,
    receipt_status = v_receipt_status,
    reimbursement_status = v_reimbursement_status,
    note = v_note,
    updated_at = v_now
  where e.id = v_expense.id;

  return query
  select
    v_expense.id,
    v_original_transaction.id,
    v_account.id,
    v_new_balance,
    'paid'::text,
    'expense_adjust'::text,
    v_year_month,
    v_reimbursement_status;
end;
$$;

comment on function public.school_update_expense_record(
  uuid,
  date,
  uuid,
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  text
) is
  'Guarded v2 expense edit: updates one ordinary paid expense and its original account transaction only when reimbursement/payment/account guards pass.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
