-- school_income_cash_request_backend_amount_rpc.sql
-- Purpose: Let DB/RPC compute Cash income request payment_amount when the
-- frontend sends a calculation intent instead of an explicit user amount.

drop function if exists public.school_request_cash_income_confirmation_for_record(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  text
);

create or replace function public.school_request_cash_income_confirmation_for_record(
  p_income_record_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text,
  p_payment_amount numeric,
  p_payment_currency text,
  p_exchange_rate numeric default null,
  p_note text default null,
  p_payment_rounding_mode text default null
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  sync_status text,
  attempt_no integer,
  idempotency_key text,
  request_type text,
  amount numeric,
  currency text,
  payment_currency text,
  payment_exchange_rate numeric,
  payment_amount numeric,
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
set search_path = public
as $$
declare
  v_income public.school_income_records%rowtype;
  v_existing public.school_personal_cash_income_linkage_events%rowtype;
  v_latest public.school_personal_cash_income_linkage_events%rowtype;
  v_event_id uuid;
  v_attempt_no integer;
  v_request_type text;
  v_idempotency_key text;
  v_cash_transaction_table text;
  v_cash_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_cash_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_rounding_mode text := lower(trim(coalesce(p_payment_rounding_mode, '')));
  v_payment_amount numeric := p_payment_amount;
  v_computed_amount numeric;
  v_now timestamptz := now();
begin
  if p_income_record_id is null then
    raise exception 'income record id is required';
  end if;

  if p_cash_user_id is null or p_cash_account_id is null then
    raise exception '请选择 Cash System 账户。';
  end if;

  if v_cash_account_name is null then
    raise exception 'Cash account name snapshot is required';
  end if;

  if v_payment_currency not in ('JPY', 'CNY') then
    raise exception '实际到账币种必须是 JPY 或 CNY。';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  select *
    into v_income
    from public.school_income_records
   where id = p_income_record_id
     and coalesce(app_type, '') = 'school'
   for update;

  if not found then
    raise exception 'income record not found: %', p_income_record_id;
  end if;

  if coalesce(v_income.status, '') <> 'pending' then
    raise exception 'Cash income request requires pending School income. current status: %', v_income.status;
  end if;

  if v_income.account_id is not null then
    raise exception 'Cash income must not have a School account id.';
  end if;

  if v_income.currency not in ('JPY', 'CNY') then
    raise exception 'School income original currency must be JPY or CNY.';
  end if;

  if v_income.currency <> v_payment_currency and (p_exchange_rate is null or p_exchange_rate <= 0) then
    raise exception '跨币种实际到账必须填写本次汇率。';
  end if;

  if v_income.currency = v_payment_currency then
    if p_exchange_rate is not null and p_exchange_rate <> 1 then
      raise exception '同币种实际到账汇率应为空或 1。';
    end if;

    if v_payment_amount is null then
      v_payment_amount := v_income.amount;
    end if;
  elsif v_payment_amount is null then
    if v_rounding_mode not in ('round', 'ceil', 'floor') then
      raise exception '后端计算实际到账金额时必须指定取整方式。';
    end if;

    v_computed_amount := case
      when v_income.currency = 'JPY' and v_payment_currency = 'CNY' then v_income.amount * p_exchange_rate
      when v_income.currency = 'CNY' and v_payment_currency = 'JPY' then v_income.amount / p_exchange_rate
      else null
    end;

    if v_computed_amount is null or v_computed_amount <= 0 then
      raise exception '实际到账金额计算失败。';
    end if;

    if v_rounding_mode = 'ceil' then
      v_payment_amount := ceil(v_computed_amount);
    elsif v_rounding_mode = 'floor' then
      v_payment_amount := floor(v_computed_amount);
    else
      v_payment_amount := round(v_computed_amount);
    end if;
  end if;

  if v_payment_amount is null or v_payment_amount <= 0 then
    raise exception '实际到账金额必须大于 0。';
  end if;

  v_request_type := case
    when v_income.income_category = 'tuition' then 'tuition_income_received'
    else 'income_received'
  end;

  v_cash_transaction_table := case
    when v_payment_currency = 'JPY' then 'home_jpy_transactions'
    else 'home_cny_transactions'
  end;

  select *
    into v_existing
    from public.school_personal_cash_income_linkage_events e
   where e.source_table = 'school_income_records'
     and e.source_id = p_income_record_id
     and e.source_event_type = v_request_type
     and e.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
   for update;

  if found then
    if v_existing.cash_user_id is distinct from p_cash_user_id
       or v_existing.cash_account_id is distinct from p_cash_account_id
       or v_existing.cash_account_name_snapshot is distinct from v_cash_account_name
       or v_existing.cash_account_type_snapshot is distinct from v_cash_account_type
       or v_existing.currency is distinct from v_income.currency
       or v_existing.amount is distinct from v_income.amount
       or v_existing.payment_currency is distinct from v_payment_currency
       or v_existing.payment_amount is distinct from v_payment_amount then
      raise exception 'existing Cash income linkage event conflicts with requested snapshot: %', v_existing.id;
    end if;

    if v_existing.cash_transaction_id is not null then
      raise exception 'existing Cash income linkage event already has a Cash transaction: %', v_existing.id;
    end if;

    v_event_id := v_existing.id;
  else
    select *
      into v_latest
      from public.school_personal_cash_income_linkage_events e
     where e.source_table = 'school_income_records'
       and e.source_id = p_income_record_id
       and e.source_event_type = v_request_type
     order by e.attempt_no desc, e.created_at desc, e.id desc
     limit 1
     for update;

    if found and v_latest.sync_status <> 'cash_rejected' then
      raise exception 'latest Cash income linkage event is not rejected or requestable: %', v_latest.sync_status;
    end if;

    v_attempt_no := coalesce(v_latest.attempt_no, 0) + 1;
    v_idempotency_key := concat(
      'aozora_school:school_income_records:',
      p_income_record_id::text,
      ':',
      v_request_type,
      ':attempt:',
      v_attempt_no::text
    );

    insert into public.school_personal_cash_income_linkage_events (
      source_table,
      source_id,
      source_event_type,
      income_record_id,
      business_entity_id,
      cash_user_id,
      cash_account_id,
      cash_account_name_snapshot,
      cash_account_type_snapshot,
      cash_transaction_table,
      currency,
      amount,
      payment_currency,
      payment_exchange_rate,
      payment_amount,
      idempotency_key,
      sync_status,
      attempt_no,
      retry_count,
      note,
      created_at,
      updated_at
    )
    values (
      'school_income_records',
      p_income_record_id,
      v_request_type,
      p_income_record_id,
      v_income.business_entity_id,
      p_cash_user_id,
      p_cash_account_id,
      v_cash_account_name,
      v_cash_account_type,
      v_cash_transaction_table,
      v_income.currency,
      v_income.amount,
      v_payment_currency,
      case when v_income.currency = v_payment_currency then coalesce(p_exchange_rate, 1) else p_exchange_rate end,
      v_payment_amount,
      v_idempotency_key,
      'pending_cash_request',
      v_attempt_no,
      coalesce(v_latest.retry_count, 0) + case when found then 1 else 0 end,
      v_note,
      v_now,
      v_now
    )
    returning id into v_event_id;
  end if;

  update public.school_income_records
     set receipt_status = 'Cash待确认',
         updated_at = v_now
   where id = p_income_record_id;

  return query
  select
    i.id,
    e.id,
    e.sync_status,
    e.attempt_no,
    e.idempotency_key,
    e.source_event_type,
    e.amount,
    e.currency,
    e.payment_currency,
    e.payment_exchange_rate,
    e.payment_amount,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.cash_account_type_snapshot,
    e.cash_request_id,
    e.cash_request_status,
    case
      when e.sync_status = 'awaiting_cash_confirmation' then 'Cash income confirmation request already submitted'
      else 'School Cash income confirmation request event is ready to submit'
    end::text
  from public.school_income_records i
  join public.school_personal_cash_income_linkage_events e
    on e.id = v_event_id
  where i.id = p_income_record_id;
end;
$$;

revoke all on function public.school_request_cash_income_confirmation_for_record(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  text,
  text
) from public, anon, authenticated;

grant execute on function public.school_request_cash_income_confirmation_for_record(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  text,
  text
) to authenticated;

comment on function public.school_request_cash_income_confirmation_for_record(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  text,
  text
) is
  'Creates/reuses a Cash income linkage event for an existing pending school_income_records row. If payment_amount is null, DB/RPC computes it from the income amount, payment currency, exchange rate, and rounding mode.';
