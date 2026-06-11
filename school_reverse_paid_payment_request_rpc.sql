-- school_reverse_paid_payment_request_rpc.sql
-- Purpose: Reverse one paid teacher_wage payment request while keeping the
--          cash reversal, payment request status, and generated teacher_wage
--          expense status consistent.
-- Scope:
-- - Future-safe logic only. This file does not repair historical reversed
--   payment requests whose generated teacher_wage expenses are still paid.
-- - Supports teacher_wage payment requests only.
-- - Preserves original payment request, original expense, and original account
--   transaction.
-- - Inserts one positive payment_reversal account transaction.
-- - Marks the payment request reversed.
-- - Marks the generated teacher_wage expense reversed and links it to the same
--   payment_reversal transaction through reversal_account_transaction_id.
-- - Does not write wage locks/details, income, student settlements,
--   reimbursements, or ordinary expense records.

create or replace function public.school_reverse_paid_payment_request(
  p_payment_request_id uuid,
  p_reason text default null,
  p_reverse_date date default current_date
)
returns table (
  payment_request_id uuid,
  old_status text,
  new_status text,
  expense_id uuid,
  original_transaction_id uuid,
  reversal_transaction_id uuid,
  account_id uuid,
  reversal_amount numeric,
  balance_after numeric,
  reversed_at timestamptz
)
language plpgsql
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_payment public.school_payment_requests%rowtype;
  v_expense public.school_expense_records%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_account public.school_accounts%rowtype;
  v_existing_reversal_count integer := 0;
  v_reimbursement_item_count integer := 0;
  v_old_status text;
  v_reversal_amount numeric;
  v_balance_after numeric;
  v_reversal_transaction_id uuid;
  v_reverse_year_month text;
  v_description text;
  v_note text;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if p_payment_request_id is null then
    raise exception 'payment request id is required';
  end if;

  if p_reverse_date is null then
    raise exception 'reverse date is required';
  end if;

  select *
    into v_payment
    from public.school_payment_requests
   where id = p_payment_request_id
   for update;

  if not found then
    raise exception 'payment request not found: %', p_payment_request_id;
  end if;

  if coalesce(v_payment.source_type, '') <> 'teacher_wage' then
    raise exception 'only teacher_wage payment requests can be reversed here. current source_type: %', v_payment.source_type;
  end if;

  if coalesce(v_payment.status, '') = 'reversed' then
    raise exception 'payment request is already reversed: %', p_payment_request_id;
  end if;

  if coalesce(v_payment.status, '') <> 'paid' then
    raise exception 'payment request status must be paid. current status: %', v_payment.status;
  end if;

  if v_payment.reversal_transaction_id is not null then
    raise exception 'payment request already has reversal transaction: %', v_payment.reversal_transaction_id;
  end if;

  if v_payment.paid_expense_id is null then
    raise exception 'paid expense id is required for reversal';
  end if;

  if v_payment.paid_account_transaction_id is null then
    raise exception 'paid account transaction id is required for reversal';
  end if;

  if v_payment.account_id is null then
    raise exception 'payment account id is required for reversal';
  end if;

  if coalesce(v_payment.amount, 0) <= 0 then
    raise exception 'payment amount must be greater than 0';
  end if;

  select count(*)::integer
    into v_existing_reversal_count
    from public.school_account_transactions t
   where t.related_table = 'school_payment_requests'
     and t.related_id = v_payment.id
     and t.transaction_type = 'payment_reversal'
     and coalesce(t.app_type, '') = 'school';

  if v_existing_reversal_count > 0 then
    raise exception 'payment request already has reversal transaction';
  end if;

  select *
    into v_expense
    from public.school_expense_records e
   where e.id = v_payment.paid_expense_id
     and coalesce(e.app_type, '') = 'school'
   for update;

  if not found then
    raise exception 'paid expense not found: %', v_payment.paid_expense_id;
  end if;

  if v_expense.expense_category is distinct from 'teacher_wage' then
    raise exception 'paid expense must be teacher_wage. current category: %', v_expense.expense_category;
  end if;

  if v_expense.status is distinct from 'paid'
    or v_expense.reversed_at is not null
    or v_expense.reversal_account_transaction_id is not null then
    raise exception 'paid expense is not reversible. current status: %', v_expense.status;
  end if;

  if v_expense.business_entity_id is distinct from v_payment.business_entity_id
    or v_expense.account_id is distinct from v_payment.account_id
    or v_expense.currency is distinct from v_payment.currency
    or v_expense.amount is distinct from v_payment.amount then
    raise exception 'paid expense does not match payment request side effects';
  end if;

  select count(*)::integer
    into v_reimbursement_item_count
    from public.school_reimbursement_items items
   where items.expense_id = v_expense.id
     and coalesce(items.app_type, '') = 'school';

  if v_reimbursement_item_count > 0 then
    raise exception 'paid expense is linked to reimbursement items and cannot be reversed by payment reversal';
  end if;

  select *
    into v_original_transaction
    from public.school_account_transactions t
   where t.id = v_payment.paid_account_transaction_id
     and coalesce(t.app_type, '') = 'school'
   for update;

  if not found then
    raise exception 'original account transaction not found: %', v_payment.paid_account_transaction_id;
  end if;

  if v_original_transaction.transaction_type is distinct from 'expense_adjust'
    or v_original_transaction.related_table is distinct from 'school_expense_records'
    or v_original_transaction.related_id is distinct from v_expense.id
    or v_original_transaction.account_id is distinct from v_payment.account_id
    or v_original_transaction.business_entity_id is distinct from v_payment.business_entity_id
    or v_original_transaction.currency is distinct from v_payment.currency
    or v_original_transaction.amount is distinct from -v_payment.amount then
    raise exception 'original account transaction does not match payment request side effects';
  end if;

  select *
    into v_account
    from public.school_accounts a
   where a.id = v_payment.account_id
     and coalesce(a.app_type, '') = 'school'
   for update;

  if not found then
    raise exception 'account not found: %', v_payment.account_id;
  end if;

  if v_account.business_entity_id is distinct from v_payment.business_entity_id
    or v_account.currency is distinct from v_payment.currency then
    raise exception 'payment account does not match payment request';
  end if;

  v_old_status := v_payment.status;
  v_reversal_amount := -v_original_transaction.amount;

  if v_reversal_amount is distinct from v_payment.amount then
    raise exception 'reversal amount does not match payment request amount';
  end if;

  v_balance_after := coalesce(v_account.current_balance, v_account.opening_balance, 0) + v_reversal_amount;
  v_reverse_year_month := to_char(p_reverse_date, 'YYYY-MM');
  v_description := trim(both from concat('支付要求撤销：', coalesce(v_payment.payee_name, ''), ' 老师工资'));
  v_note := trim(both from concat(
    '撤销支付要求ID：',
    v_payment.id::text,
    E'\n原支出ID：',
    v_expense.id::text,
    E'\n原账户流水ID：',
    v_original_transaction.id::text,
    case when v_reason is not null then concat(E'\n原因：', v_reason) else '' end
  ));

  update public.school_accounts
     set current_balance = v_balance_after,
         updated_at = v_now
   where id = v_payment.account_id;

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
    v_payment.account_id,
    v_payment.business_entity_id,
    p_reverse_date,
    v_reverse_year_month,
    'payment_reversal',
    'school_payment_requests',
    v_payment.id,
    v_original_transaction.currency,
    v_reversal_amount,
    v_balance_after,
    v_description,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_transaction_id;

  update public.school_payment_requests
     set status = 'reversed',
         reversed_at = v_now,
         reversal_transaction_id = v_reversal_transaction_id,
         reversal_reason = v_reason,
         updated_at = v_now
   where id = p_payment_request_id;

  update public.school_expense_records
     set status = 'reversed',
         reversed_at = v_now,
         reversal_reason = v_reason,
         reversal_account_transaction_id = v_reversal_transaction_id,
         updated_at = v_now
   where id = v_expense.id;

  return query
  select
    v_payment.id,
    v_old_status,
    'reversed'::text,
    v_expense.id,
    v_original_transaction.id,
    v_reversal_transaction_id,
    v_payment.account_id,
    v_reversal_amount,
    v_balance_after,
    v_now;
end;
$$;

comment on function public.school_reverse_paid_payment_request(
  uuid,
  text,
  date
) is
  'Reverses one paid teacher_wage payment request, restores cash through payment_reversal, and marks the generated teacher_wage expense reversed.';

grant execute on function public.school_reverse_paid_payment_request(
  uuid,
  text,
  date
) to anon, authenticated;
