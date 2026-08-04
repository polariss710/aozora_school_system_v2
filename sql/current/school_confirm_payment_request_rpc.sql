-- school_confirm_payment_request_rpc.sql
-- RPC: public.school_confirm_payment_request
-- Purpose:
-- - Confirm one pending teacher wage payment request.
-- - Create one paid teacher_wage expense, one account transaction, and mark
--   the payment request as paid.
-- - Set expense reimbursement_status from the selected account type:
--   company account => not_required, advance/personal account => pending.
-- - Treat exchange_rate as optional metadata. If JPY/CNY amounts do not allow
--   deriving a positive exchange rate, store NULL and do not block payment.
-- - Do not create reimbursements, reimbursement items, income, student
--   settlements, teacher wage locks, or teacher wage details.
-- Status: re-executed on 2026-06-12 for optional exchange_rate behavior.

create or replace function public.school_confirm_payment_request(
  p_payment_request_id uuid,
  p_account_id uuid,
  p_pay_date date,
  p_amount numeric default null,
  p_note text default null,
  p_payment_method text default 'bank_transfer'
)
returns table (
  payment_request_id uuid,
  expense_id uuid,
  account_transaction_id uuid,
  status text,
  paid_at timestamptz,
  account_id uuid,
  balance_after numeric
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_payment public.school_payment_requests%rowtype;
  v_account public.school_accounts%rowtype;
  v_amount numeric;
  v_year_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_exchange_rate numeric;
  v_delta numeric;
  v_balance_after numeric;
  v_expense_id uuid;
  v_transaction_id uuid;
  v_paid_at timestamptz;
  v_note text;
  v_payment_method text := nullif(trim(coalesce(p_payment_method, 'bank_transfer')), '');
  v_reimbursement_status text;
  v_now timestamptz := now();
begin
  perform public.school_require_current_app_admin();

  if p_payment_request_id is null then
    raise exception 'payment request id is required';
  end if;

  if p_account_id is null then
    raise exception 'account id is required';
  end if;

  if p_pay_date is null then
    raise exception 'pay date is required';
  end if;

  select *
    into v_payment
    from public.school_payment_requests
   where id = p_payment_request_id
   for update;

  if not found then
    raise exception 'payment request not found: %', p_payment_request_id;
  end if;

  if coalesce(v_payment.status, '') <> 'pending' then
    raise exception 'payment request status must be pending. current status: %', v_payment.status;
  end if;

  if coalesce(v_payment.source_type, '') <> 'teacher_wage' then
    raise exception 'only teacher_wage payment requests are supported. current source_type: %', v_payment.source_type;
  end if;

  if v_payment.paid_at is not null
     or v_payment.paid_expense_id is not null
     or v_payment.paid_account_transaction_id is not null
     or v_payment.account_id is not null then
    raise exception 'payment request already has payment side effects';
  end if;

  if v_payment.business_entity_id is null then
    raise exception 'payment request has no business_entity_id: %', p_payment_request_id;
  end if;

  if nullif(trim(coalesce(v_payment.currency, '')), '') is null then
    raise exception 'payment request has no currency: %', p_payment_request_id;
  end if;

  select *
    into v_account
    from public.school_accounts
   where id = p_account_id
     and coalesce(app_type, '') = 'school'
   for update;

  if not found then
    raise exception 'account not found: %', p_account_id;
  end if;

  if v_account.is_active is not true then
    raise exception 'payment account is inactive: %', p_account_id;
  end if;

  if v_account.business_entity_id is distinct from v_payment.business_entity_id then
    raise exception 'payment account business entity does not match payment request';
  end if;

  if v_account.currency is distinct from v_payment.currency then
    raise exception 'payment account currency must match payment request currency';
  end if;

  v_amount := coalesce(p_amount, v_payment.amount, 0);
  if v_amount <= 0 then
    raise exception 'payment amount must be greater than 0';
  end if;

  if v_amount is distinct from v_payment.amount then
    raise exception 'payment amount must equal request amount. request %, input %', v_payment.amount, v_amount;
  end if;

  v_year_month := coalesce(v_payment.request_month, to_char(p_pay_date, 'YYYY-MM'));

  if v_year_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'invalid payment request month: %', v_year_month;
  end if;

  v_amount_jpy := case
    when v_payment.currency = 'JPY' then round(v_amount)
    else round(coalesce(v_payment.amount_jpy, 0))
  end;

  v_amount_cny := case
    when v_payment.currency = 'CNY' then round(v_amount * 100) / 100
    else round(coalesce(v_payment.amount_cny, 0) * 100) / 100
  end;

  v_exchange_rate := case
    when coalesce(v_amount_jpy, 0) > 0 and coalesce(v_amount_cny, 0) > 0
      then round((v_amount_cny / v_amount_jpy) * 1000000) / 1000000
    else null
  end;

  v_reimbursement_status := case
    when coalesce(v_account.is_company_account, false) then 'not_required'
    else 'pending'
  end;

  v_note := trim(both from concat(coalesce(p_note, ''), E'\n支付要求ID：', v_payment.id::text));

  insert into public.school_expense_records (
    expense_date,
    year_month,
    business_entity_id,
    account_id,
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
    p_pay_date,
    v_year_month,
    v_payment.business_entity_id,
    p_account_id,
    'teacher_wage',
    trim(both from concat(coalesce(v_payment.request_month, ''), ' ', coalesce(v_payment.payee_name, ''), ' 老师工资')),
    v_payment.currency,
    v_amount,
    v_amount_jpy,
    v_amount_cny,
    v_exchange_rate,
    coalesce(v_payment_method, 'bank_transfer'),
    'paid',
    true,
    '給与',
    '无需收据',
    v_reimbursement_status,
    null,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_expense_id;

  v_delta := -v_amount;
  v_balance_after := coalesce(v_account.current_balance, v_account.opening_balance, 0) + v_delta;

  update public.school_accounts
     set current_balance = v_balance_after,
         updated_at = v_now
   where id = p_account_id;

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
    app_type,
    created_at
  )
  values (
    p_account_id,
    v_payment.business_entity_id,
    p_pay_date,
    v_year_month,
    'expense_adjust',
    'school_expense_records',
    v_expense_id,
    v_account.currency,
    v_delta,
    v_balance_after,
    trim(both from concat('支付要求确认：', coalesce(v_payment.payee_name, ''), ' 老师工资')),
    'school',
    v_now
  )
  returning id into v_transaction_id;

  v_paid_at := p_pay_date::timestamptz;

  update public.school_payment_requests
     set status = 'paid',
         paid_at = v_paid_at,
         note = coalesce(p_note, v_payment.note, ''),
         updated_at = v_now,
         paid_expense_id = v_expense_id,
         paid_account_transaction_id = v_transaction_id,
         account_id = p_account_id
   where id = p_payment_request_id;

  return query
  select
    p_payment_request_id,
    v_expense_id,
    v_transaction_id,
    'paid'::text,
    v_paid_at,
    p_account_id,
    v_balance_after;
end;
$$;

comment on function public.school_confirm_payment_request(
  uuid,
  uuid,
  date,
  numeric,
  text,
  text
) is
  'Confirms one pending teacher wage payment request. Creates one teacher_wage expense and one account transaction, marks the request paid, sets expense reimbursement_status by account type, and treats exchange_rate as optional metadata.';

revoke all on function public.school_confirm_payment_request(
  uuid,
  uuid,
  date,
  numeric,
  text,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.school_confirm_payment_request(
  uuid,
  uuid,
  date,
  numeric,
  text,
  text
) to authenticated;
