-- school_create_expense_record_rpc.sql
-- RPC: public.school_create_expense_record
-- Status: Executed on Supabase and verified by RPC unit tests.
-- Version: v2.22.4-expense-create-rpc-verified-20260604
--
-- Scope:
-- - Create one ordinary paid school expense record.
-- - Deduct school account current_balance.
-- - Insert one related negative account transaction.
-- - Run all operations in one DB transaction.
--
-- Verified tests:
-- - Function exists in public schema.
-- - Rollback create test succeeded.
-- - Commit create test succeeded.
-- - Expense / account / account transaction consistency verified.
-- - teacher_wage category rejected.
-- - Unknown expense category rejected.
-- - amount <= 0 rejected.
-- - exchange_rate <= 0 rejected.
-- - account currency mismatch rejected.
-- - Invalid reimbursement_status rejected.
-- - Invalid receipt_status rejected.
--
-- Notes:
-- - First version only supports ordinary paid expense creation.
-- - No edit/delete/void/reversal support.
-- - No reimbursement flow creation.
-- - No attachment/OCR support.
-- - No teacher_wage manual creation; teacher wage expenses must be generated
--   by the teacher wage payment RPC flow.
-- - No complex cross-currency posting.
-- - account.currency must match expense currency.
-- - Account balance may become negative to support advance payment /
--   reimbursement scenarios.

create or replace function public.school_create_expense_record(
  p_expense_date date,
  p_business_entity_id uuid,
  p_account_id uuid,
  p_expense_category text,
  p_description text,
  p_currency text,
  p_amount numeric,
  p_exchange_rate numeric default null,
  p_payment_method text default null,
  p_is_business_expense boolean default true,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_reimbursement_status text default null,
  p_teacher_id uuid default null,
  p_student_id uuid default null,
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
  v_business_entity public.school_business_entities%rowtype;
  v_account public.school_accounts%rowtype;
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
  v_old_balance numeric;
  v_new_balance numeric;
  v_expense_id uuid;
  v_account_transaction_id uuid;
begin
  if p_expense_date is null then
    raise exception '请选择支出日期。';
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
    raise exception '老师工资支出请通过老师工资支付流程生成。';
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

  if v_receipt_status not in ('有', '无需收据', '待确认') then
    raise exception '收据状态无效。';
  end if;

  select *
  into v_business_entity
  from public.school_business_entities
  where id = p_business_entity_id
    and is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  if p_teacher_id is not null and not exists (
    select 1
    from public.school_teachers
    where id = p_teacher_id
      and app_type = 'school'
  ) then
    raise exception '老师无效或不可用。';
  end if;

  if p_student_id is not null and not exists (
    select 1
    from public.school_students
    where id = p_student_id
      and app_type = 'school'
  ) then
    raise exception '学生无效或不可用。';
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

  if v_reimbursement_status is null then
    v_reimbursement_status := case
      when coalesce(v_account.is_company_account, false) then 'not_required'
      else 'pending'
    end;
  end if;

  if v_reimbursement_status not in ('not_required', 'pending') then
    raise exception '报销状态无效。';
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
  v_old_balance := coalesce(v_account.current_balance, 0);
  v_new_balance := v_old_balance - p_amount;

  insert into public.school_expense_records (
    business_entity_id,
    teacher_id,
    student_id,
    salary_payment_id,
    account_id,
    expense_date,
    year_month,
    expense_category,
    description,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    exchange_rate,
    payment_method,
    status,
    is_business_expense,
    tax_category,
    receipt_status,
    reimbursement_status,
    reimbursement_note,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    p_teacher_id,
    p_student_id,
    null,
    v_account.id,
    p_expense_date,
    v_year_month,
    v_category,
    v_description,
    v_currency,
    p_amount,
    v_amount_jpy,
    v_amount_cny,
    p_exchange_rate,
    v_payment_method,
    'paid',
    coalesce(p_is_business_expense, true),
    v_tax_category,
    v_receipt_status,
    v_reimbursement_status,
    null,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_expense_id;

  update public.school_accounts
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where id = v_account.id;

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
    p_expense_date,
    v_year_month,
    'expense_adjust',
    'school_expense_records',
    v_expense_id,
    v_account.currency,
    -p_amount,
    v_new_balance,
    '支出出账：' || v_description,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_account_transaction_id;

  return query
  select
    v_expense_id,
    v_account_transaction_id,
    v_account.id,
    v_new_balance,
    'paid'::text,
    'expense_adjust'::text,
    v_year_month,
    v_reimbursement_status;
end;
$$;

comment on function public.school_create_expense_record(
  date,
  uuid,
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  boolean,
  text,
  text,
  text,
  uuid,
  uuid,
  text
) is
  'Verified RPC for v2 ordinary expense creation: creates paid expense, deducts account balance, and inserts a negative expense_adjust transaction.';

-- Permission note:
-- Keep execute permission management explicit. If permissions need to be
-- re-applied in another environment, review before enabling:
-- grant execute on function public.school_create_expense_record(
--   date, uuid, uuid, text, text, text, numeric, numeric, text, boolean,
--   text, text, text, uuid, uuid, text
-- ) to authenticated;
--
-- This file intentionally does not include executable test insert/update/delete
-- statements.

-- Reference call example with placeholder IDs only. Do not run as-is.
--
-- select *
-- from public.school_create_expense_record(
--   p_expense_date := date '2026-06-04',
--   p_business_entity_id := '00000000-0000-0000-0000-000000000000',
--   p_account_id := '00000000-0000-0000-0000-000000000000',
--   p_expense_category := 'classroom',
--   p_description := '教室费用',
--   p_currency := 'JPY',
--   p_amount := 1000,
--   p_payment_method := 'card',
--   p_receipt_status := '待确认',
--   p_reimbursement_status := null,
--   p_note := null
-- );
