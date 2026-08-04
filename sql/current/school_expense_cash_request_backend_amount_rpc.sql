-- school_expense_cash_request_backend_amount_rpc.sql
-- Purpose: Let DB/RPC compute Cash expense request payment_amount when the
-- frontend sends a calculation intent instead of an explicit user amount.

drop function if exists public.school_request_cash_expense_payment_confirmation(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  text
);

create or replace function public.school_request_cash_expense_payment_confirmation(
  p_expense_record_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text default null,
  p_payment_amount numeric default null,
  p_payment_currency text default null,
  p_note text default null,
  p_exchange_rate numeric default null,
  p_payment_rounding_mode text default null
)
returns table (
  expense_id uuid,
  request_event_id uuid,
  attempt_no integer,
  idempotency_key text,
  request_type text,
  expense_status text,
  expense_category text,
  source_type text,
  source_id uuid,
  payee_name_snapshot text,
  year_month text,
  expense_date date,
  description text,
  original_amount numeric,
  original_currency text,
  original_amount_jpy numeric,
  original_amount_cny numeric,
  payment_amount numeric,
  payment_currency text,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  cash_account_type_snapshot text,
  cash_request_id uuid,
  cash_request_status text,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_expense public.school_expense_records%rowtype;
  v_now timestamptz := now();
  v_payment_amount numeric := p_payment_amount;
  v_payment_currency text := upper(nullif(trim(coalesce(p_payment_currency, '')), ''));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_rounding_mode text := lower(trim(coalesce(p_payment_rounding_mode, '')));
  v_computed_amount numeric;
  v_reuse_pending boolean := false;
begin
  if p_expense_record_id is null then
    raise exception 'expense_record_id is required.';
  end if;

  if p_cash_user_id is null or p_cash_account_id is null then
    raise exception 'Cash user/account is required.';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception 'exchange rate must be greater than 0.';
  end if;

  select *
    into v_expense
    from public.school_expense_records e
   where e.id = p_expense_record_id
     and e.app_type = 'school'
   for update;

  if not found then
    raise exception 'school expense record not found: %', p_expense_record_id;
  end if;

  if v_expense.reversed_at is not null or v_expense.status = 'reversed' then
    raise exception 'reversed expense records cannot request Cash confirmation.';
  end if;

  if v_expense.status = 'paid' then
    raise exception 'paid expense records cannot request Cash confirmation again.';
  end if;

  if v_expense.cash_transaction_id is not null then
    raise exception 'expense record already has Cash transaction: %', v_expense.cash_transaction_id;
  end if;

  if v_expense.cash_request_status in ('pending', 'approved', 'synced') then
    raise exception 'expense record already has active or completed Cash request: %', v_expense.cash_request_status;
  end if;

  if v_payment_currency is null then
    v_payment_currency := upper(coalesce(v_expense.currency, 'JPY'));
  end if;

  if v_payment_currency not in ('JPY', 'CNY') then
    raise exception 'payment currency must be JPY or CNY. current: %', v_payment_currency;
  end if;

  if v_expense.currency not in ('JPY', 'CNY') then
    raise exception 'original expense currency must be JPY or CNY. current: %', v_expense.currency;
  end if;

  if v_expense.currency <> v_payment_currency and (p_exchange_rate is null or p_exchange_rate <= 0) then
    raise exception 'cross-currency payment requires exchange rate.';
  end if;

  if v_expense.currency = v_payment_currency then
    if p_exchange_rate is not null and p_exchange_rate <> 1 then
      raise exception 'same-currency payment exchange rate must be empty or 1.';
    end if;

    if v_payment_amount is null then
      v_payment_amount := v_expense.amount;
    end if;
  elsif v_payment_amount is null then
    if v_rounding_mode not in ('round', 'ceil', 'floor') then
      raise exception 'backend-calculated payment amount requires rounding mode.';
    end if;

    v_computed_amount := case
      when v_expense.currency = 'JPY' and v_payment_currency = 'CNY' then v_expense.amount * p_exchange_rate
      when v_expense.currency = 'CNY' and v_payment_currency = 'JPY' then v_expense.amount / p_exchange_rate
      else null
    end;

    if v_computed_amount is null or v_computed_amount <= 0 then
      raise exception 'payment amount calculation failed.';
    end if;

    if v_rounding_mode = 'ceil' then
      v_payment_amount := ceil(v_computed_amount);
    elsif v_rounding_mode = 'floor' then
      v_payment_amount := floor(v_computed_amount);
    else
      v_payment_amount := round(v_computed_amount);
    end if;
  end if;

  if coalesce(v_payment_amount, 0) <= 0 then
    raise exception 'payment amount must be greater than 0.';
  end if;

  if v_account_name is null then
    raise exception 'Cash account name snapshot is required.';
  end if;

  v_reuse_pending :=
    v_expense.cash_request_status = 'pending_cash_request'
    and v_expense.cash_request_event_id is not null
    and v_expense.cash_request_id is null;

  if not v_reuse_pending then
    v_expense.cash_request_attempt_no := coalesce(v_expense.cash_request_attempt_no, 0) + 1;
    v_expense.cash_request_event_id := gen_random_uuid();
  end if;

  update public.school_expense_records e
     set cash_request_event_id = v_expense.cash_request_event_id,
         cash_request_attempt_no = v_expense.cash_request_attempt_no,
         cash_request_status = 'pending_cash_request',
         cash_request_id = null,
         cash_transaction_id = null,
         cash_requested_at = v_now,
         cash_payment_amount = v_payment_amount,
         cash_payment_currency = v_payment_currency,
         cash_payment_note = v_note,
         cash_error_message = null,
         updated_at = v_now
   where e.id = v_expense.id
   returning * into v_expense;

  return query
  select
    v_expense.id,
    v_expense.cash_request_event_id,
    v_expense.cash_request_attempt_no,
    format(
      'aozora_school:school_expense_records:%s:expense_paid:attempt:%s',
      v_expense.id,
      v_expense.cash_request_attempt_no
    ),
    'expense_paid'::text,
    v_expense.status,
    v_expense.expense_category,
    v_expense.source_type,
    v_expense.source_id,
    v_expense.payee_name_snapshot,
    v_expense.year_month,
    v_expense.expense_date,
    v_expense.description,
    v_expense.amount,
    v_expense.currency,
    v_expense.amount_jpy,
    v_expense.amount_cny,
    v_payment_amount,
    v_payment_currency,
    p_cash_user_id,
    p_cash_account_id,
    v_account_name,
    v_account_type,
    v_expense.cash_request_id,
    v_expense.cash_request_status,
    case
      when v_reuse_pending then 'existing pending Cash expense request attempt reused'
      else 'Cash expense request attempt prepared'
    end;
end;
$$;

comment on function public.school_request_cash_expense_payment_confirmation(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  text,
  numeric,
  text
) is
  'Prepares a Cash pending request attempt for a canonical school_expense_records row. If payment_amount is null, DB/RPC computes it from the expense amount, payment currency, exchange rate, and rounding mode.';

revoke all on function public.school_request_cash_expense_payment_confirmation(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  text,
  numeric,
  text
) from public, anon, authenticated, service_role;

grant execute on function public.school_request_cash_expense_payment_confirmation(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  text,
  numeric,
  text
) to service_role;
