-- school_part_time_work_cash_request_workflow.sql
-- Status: executed on School DB 2026-06-15; installed as the part-time work Cash request workflow extension.
-- Purpose:
-- - Extend external part-time work income requests with actual received Cash
--   request fields.
-- - Keep locked JPY settlement totals immutable and separate from actual Cash
--   received amount/currency.
-- - Provide RPCs used by the dedicated request-cash-part-time-income-confirmation
--   Edge Function and sync-cash-request-result callback.
-- Safety:
-- - No real business data is inserted by this file.
-- - DML only appears inside guarded RPC bodies.

begin;

alter table public.school_part_time_work_income_requests
  add column if not exists actual_received_amount numeric,
  add column if not exists actual_received_currency text,
  add column if not exists actual_exchange_rate numeric,
  add column if not exists cash_user_id uuid,
  add column if not exists cash_account_id uuid,
  add column if not exists cash_account_name_snapshot text,
  add column if not exists cash_account_type_snapshot text,
  add column if not exists cash_request_status text,
  add column if not exists requested_at timestamptz,
  add column if not exists synced_at timestamptz,
  add column if not exists rejected_at timestamptz,
  add column if not exists cash_error_message text,
  add column if not exists cash_attempt_no integer not null default 0;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'school_part_time_work_income_requests'
      and column_name = 'cash_request_id'
      and data_type <> 'uuid'
  ) then
    alter table public.school_part_time_work_income_requests
      alter column cash_request_id type uuid using nullif(trim(cash_request_id), '')::uuid;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'school_part_time_work_income_requests'
      and column_name = 'cash_transaction_id'
      and data_type <> 'uuid'
  ) then
    alter table public.school_part_time_work_income_requests
      alter column cash_transaction_id type uuid using nullif(trim(cash_transaction_id), '')::uuid;
  end if;
end $$;

alter table public.school_part_time_work_income_requests
  drop constraint if exists school_part_time_work_income_requests_actual_currency_check,
  drop constraint if exists school_part_time_work_income_requests_actual_amount_check,
  drop constraint if exists school_part_time_work_income_requests_actual_exchange_check,
  drop constraint if exists school_part_time_work_income_requests_cash_attempt_check,
  drop constraint if exists school_part_time_work_income_requests_cash_status_check,
  add constraint school_part_time_work_income_requests_actual_currency_check
    check (actual_received_currency is null or actual_received_currency in ('JPY', 'CNY')),
  add constraint school_part_time_work_income_requests_actual_amount_check
    check (actual_received_amount is null or actual_received_amount > 0),
  add constraint school_part_time_work_income_requests_actual_exchange_check
    check (actual_exchange_rate is null or actual_exchange_rate > 0),
  add constraint school_part_time_work_income_requests_cash_attempt_check
    check (cash_attempt_no >= 0),
  add constraint school_part_time_work_income_requests_cash_status_check
    check (cash_request_status is null or cash_request_status in ('pending', 'approved', 'rejected'));

create index if not exists school_part_time_work_income_requests_cash_request_idx
  on public.school_part_time_work_income_requests (cash_request_id)
  where cash_request_id is not null;

drop function if exists public.school_get_part_time_work_cash_request_context(uuid);
drop function if exists public.school_mark_part_time_work_cash_request_submitted(uuid, numeric, text, numeric, uuid, uuid, text, text, uuid, text, text);
drop function if exists public.school_mark_part_time_work_cash_income_confirmed(uuid, uuid, uuid, timestamptz);
drop function if exists public.school_mark_part_time_work_cash_income_rejected(uuid, uuid, text, timestamptz);

create or replace function public.school_get_part_time_work_cash_request_context(
  p_income_request_id uuid
)
returns table (
  income_request_id uuid,
  settlement_id uuid,
  year_month text,
  workplace_name text,
  teacher_name text,
  original_amount_jpy integer,
  income_request_status text,
  cash_request_id uuid,
  cash_request_status text,
  cash_transaction_id uuid,
  actual_received_amount numeric,
  actual_received_currency text,
  actual_exchange_rate numeric,
  cash_attempt_no integer,
  request_type text,
  transaction_type text,
  idempotency_key text,
  memo text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.school_part_time_work_income_requests%rowtype;
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
begin
  if p_income_request_id is null then
    raise exception 'income request id is required';
  end if;

  select *
    into v_request
    from public.school_part_time_work_income_requests ir
   where ir.id = p_income_request_id
     and ir.deleted_at is null;

  if not found then
    raise exception 'part-time work income request not found: %', p_income_request_id;
  end if;

  select *
    into v_settlement
    from public.school_part_time_work_monthly_settlements s
   where s.id = v_request.settlement_id
     and s.deleted_at is null;

  if not found then
    raise exception 'part-time work settlement not found: %', v_request.settlement_id;
  end if;

  if v_settlement.status <> 'income_request_created'
     or v_settlement.income_request_id is distinct from v_request.id then
    raise exception 'part-time work settlement is not ready for Cash request.';
  end if;

  if v_request.currency <> 'JPY' then
    raise exception 'part-time work income request original currency must be JPY.';
  end if;

  return query
  select
    v_request.id,
    v_request.settlement_id,
    v_request.year_month,
    v_request.workplace_name,
    v_request.teacher_name,
    v_request.amount_jpy,
    v_request.status,
    v_request.cash_request_id,
    v_request.cash_request_status,
    v_request.cash_transaction_id,
    v_request.actual_received_amount,
    v_request.actual_received_currency,
    v_request.actual_exchange_rate,
    v_request.cash_attempt_no,
    'part_time_work_income_received'::text,
    'income'::text,
    concat(
      'aozora_school:school_part_time_work_income_requests:',
      v_request.id::text,
      ':part_time_work_income_received:attempt:',
      (v_request.cash_attempt_no + 1)::text
    )::text,
    v_request.memo;
end;
$$;

create or replace function public.school_mark_part_time_work_cash_request_submitted(
  p_income_request_id uuid,
  p_actual_received_amount numeric,
  p_actual_received_currency text,
  p_exchange_rate numeric,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text,
  p_cash_request_id uuid,
  p_cash_request_status text default 'pending',
  p_note text default null
)
returns table (
  income_request_id uuid,
  settlement_id uuid,
  status text,
  cash_request_id uuid,
  cash_request_status text,
  actual_received_amount numeric,
  actual_received_currency text,
  actual_exchange_rate numeric,
  cash_attempt_no integer,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.school_part_time_work_income_requests%rowtype;
  v_currency text := upper(trim(coalesce(p_actual_received_currency, '')));
  v_cash_status text := nullif(trim(coalesce(p_cash_request_status, '')), '');
  v_cash_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_cash_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
begin
  if p_income_request_id is null or p_cash_request_id is null then
    raise exception 'income request id and Cash request id are required';
  end if;

  if p_actual_received_amount is null or p_actual_received_amount <= 0 then
    raise exception 'actual received amount must be greater than 0';
  end if;

  if v_currency not in ('JPY', 'CNY') then
    raise exception 'actual received currency must be JPY or CNY';
  end if;

  if v_currency = 'CNY' and (p_exchange_rate is null or p_exchange_rate <= 0) then
    raise exception 'CNY actual received amount requires a positive exchange rate';
  end if;

  if v_currency = 'JPY' and p_exchange_rate is not null and p_exchange_rate <> 1 then
    raise exception 'JPY actual received exchange rate must be empty or 1';
  end if;

  if p_cash_user_id is null or p_cash_account_id is null or v_cash_account_name is null then
    raise exception 'Cash account snapshot is required';
  end if;

  if v_cash_status <> 'pending' then
    raise exception 'Cash request status must be pending when submitted';
  end if;

  select *
    into v_request
    from public.school_part_time_work_income_requests ir
   where ir.id = p_income_request_id
     and ir.deleted_at is null
   for update;

  if not found then
    raise exception 'part-time work income request not found: %', p_income_request_id;
  end if;

  if v_request.status not in ('pending_cash_request', 'cash_rejected', 'failed', 'blocked') then
    raise exception 'part-time work income request is not requestable: %', v_request.status;
  end if;

  if v_request.cash_transaction_id is not null then
    raise exception 'part-time work income request already has a Cash transaction: %', v_request.cash_transaction_id;
  end if;

  if v_request.cash_request_id is not null
     and v_request.cash_request_id is distinct from p_cash_request_id
     and v_request.status <> 'cash_rejected' then
    raise exception 'part-time work income request already references active Cash request: %', v_request.cash_request_id;
  end if;

  update public.school_part_time_work_income_requests as ir
     set status = 'awaiting_cash_confirmation',
         actual_received_amount = p_actual_received_amount,
         actual_received_currency = v_currency,
         actual_exchange_rate = case when v_currency = 'JPY' then coalesce(p_exchange_rate, 1) else p_exchange_rate end,
         cash_user_id = p_cash_user_id,
         cash_account_id = p_cash_account_id,
         cash_account_name_snapshot = v_cash_account_name,
         cash_account_type_snapshot = v_cash_account_type,
         cash_request_id = p_cash_request_id,
         cash_request_status = 'pending',
         requested_at = now(),
         rejected_at = null,
         cash_error_message = nullif(trim(coalesce(p_note, '')), ''),
         cash_attempt_no = coalesce(ir.cash_attempt_no, 0) + 1,
         updated_at = now()
   where ir.id = v_request.id
   returning * into v_request;

  return query
  select
    v_request.id,
    v_request.settlement_id,
    v_request.status,
    v_request.cash_request_id,
    v_request.cash_request_status,
    v_request.actual_received_amount,
    v_request.actual_received_currency,
    v_request.actual_exchange_rate,
    v_request.cash_attempt_no,
    'Part-time work Cash income request submitted and awaiting Cash confirmation'::text;
end;
$$;

create or replace function public.school_mark_part_time_work_cash_income_confirmed(
  p_income_request_id uuid,
  p_cash_request_id uuid,
  p_cash_transaction_id uuid,
  p_confirmed_at timestamptz default now()
)
returns table (
  income_request_id uuid,
  settlement_id uuid,
  status text,
  cash_request_id uuid,
  cash_request_status text,
  cash_transaction_id uuid,
  synced_at timestamptz,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.school_part_time_work_income_requests%rowtype;
  v_now timestamptz := coalesce(p_confirmed_at, now());
begin
  if p_income_request_id is null or p_cash_request_id is null or p_cash_transaction_id is null then
    raise exception 'income request id, Cash request id, and Cash transaction id are required';
  end if;

  select *
    into v_request
    from public.school_part_time_work_income_requests ir
   where ir.id = p_income_request_id
     and ir.deleted_at is null
   for update;

  if not found then
    raise exception 'part-time work income request not found: %', p_income_request_id;
  end if;

  if v_request.cash_request_id is not null
     and v_request.cash_request_id is distinct from p_cash_request_id then
    raise exception 'part-time work income request references a different Cash request: %', v_request.cash_request_id;
  end if;

  if v_request.cash_transaction_id is not null
     and v_request.cash_transaction_id is distinct from p_cash_transaction_id then
    raise exception 'part-time work income request already references a different Cash transaction: %', v_request.cash_transaction_id;
  end if;

  if v_request.status = 'synced' then
    return query
    select
      v_request.id,
      v_request.settlement_id,
      v_request.status,
      v_request.cash_request_id,
      v_request.cash_request_status,
      v_request.cash_transaction_id,
      v_request.synced_at,
      'Part-time work Cash income approval was already reflected in School'::text;
    return;
  end if;

  if v_request.status <> 'awaiting_cash_confirmation' then
    raise exception 'part-time work income request is not awaiting Cash confirmation: %', v_request.status;
  end if;

  update public.school_part_time_work_income_requests as ir
     set status = 'synced',
         cash_request_id = p_cash_request_id,
         cash_request_status = 'approved',
         cash_transaction_id = p_cash_transaction_id,
         synced_at = v_now,
         cash_error_message = null,
         updated_at = now()
   where ir.id = v_request.id
   returning * into v_request;

  return query
  select
    v_request.id,
    v_request.settlement_id,
    v_request.status,
    v_request.cash_request_id,
    v_request.cash_request_status,
    v_request.cash_transaction_id,
    v_request.synced_at,
    'Part-time work Cash income approval reflected in School without changing locked settlement totals'::text;
end;
$$;

create or replace function public.school_mark_part_time_work_cash_income_rejected(
  p_income_request_id uuid,
  p_cash_request_id uuid,
  p_rejected_reason text default null,
  p_rejected_at timestamptz default now()
)
returns table (
  income_request_id uuid,
  settlement_id uuid,
  status text,
  cash_request_id uuid,
  cash_request_status text,
  cash_error_message text,
  rejected_at timestamptz,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.school_part_time_work_income_requests%rowtype;
  v_now timestamptz := coalesce(p_rejected_at, now());
  v_reason text := nullif(trim(coalesce(p_rejected_reason, '')), '');
begin
  if p_income_request_id is null or p_cash_request_id is null then
    raise exception 'income request id and Cash request id are required';
  end if;

  select *
    into v_request
    from public.school_part_time_work_income_requests ir
   where ir.id = p_income_request_id
     and ir.deleted_at is null
   for update;

  if not found then
    raise exception 'part-time work income request not found: %', p_income_request_id;
  end if;

  if v_request.cash_request_id is not null
     and v_request.cash_request_id is distinct from p_cash_request_id then
    raise exception 'part-time work income request references a different Cash request: %', v_request.cash_request_id;
  end if;

  if v_request.cash_transaction_id is not null then
    raise exception 'rejected Cash request must not have a Cash transaction: %', v_request.cash_transaction_id;
  end if;

  if v_request.status = 'cash_rejected' then
    return query
    select
      v_request.id,
      v_request.settlement_id,
      v_request.status,
      v_request.cash_request_id,
      v_request.cash_request_status,
      v_request.cash_error_message,
      v_request.rejected_at,
      'Part-time work Cash income rejection was already reflected in School'::text;
    return;
  end if;

  if v_request.status <> 'awaiting_cash_confirmation' then
    raise exception 'part-time work income request is not awaiting Cash confirmation: %', v_request.status;
  end if;

  update public.school_part_time_work_income_requests as ir
     set status = 'cash_rejected',
         cash_request_id = p_cash_request_id,
         cash_request_status = 'rejected',
         rejected_at = v_now,
         cash_error_message = v_reason,
         updated_at = now()
   where ir.id = v_request.id
   returning * into v_request;

  return query
  select
    v_request.id,
    v_request.settlement_id,
    v_request.status,
    v_request.cash_request_id,
    v_request.cash_request_status,
    v_request.cash_error_message,
    v_request.rejected_at,
    'Part-time work Cash income rejection reflected in School; locked settlement totals unchanged'::text;
end;
$$;

comment on function public.school_get_part_time_work_cash_request_context(uuid) is
  'Returns locked part-time work income request context for creating a Cash pending income request. Original School amount remains JPY.';

comment on function public.school_mark_part_time_work_cash_request_submitted(uuid, numeric, text, numeric, uuid, uuid, text, text, uuid, text, text) is
  'Marks a part-time work income request as awaiting Cash confirmation after a Cash pending request is created. Stores actual received amount/currency separately from original JPY wage.';

comment on function public.school_mark_part_time_work_cash_income_confirmed(uuid, uuid, uuid, timestamptz) is
  'Reflects Cash approval for part-time work income. Does not modify locked JPY settlement totals.';

comment on function public.school_mark_part_time_work_cash_income_rejected(uuid, uuid, text, timestamptz) is
  'Reflects Cash rejection for part-time work income. Does not modify locked JPY settlement totals.';

revoke all on function public.school_get_part_time_work_cash_request_context(uuid)
  from public, anon, authenticated;
revoke all on function public.school_mark_part_time_work_cash_request_submitted(uuid, numeric, text, numeric, uuid, uuid, text, text, uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.school_mark_part_time_work_cash_income_confirmed(uuid, uuid, uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.school_mark_part_time_work_cash_income_rejected(uuid, uuid, text, timestamptz)
  from public, anon, authenticated;

grant execute on function public.school_get_part_time_work_cash_request_context(uuid) to authenticated;
grant execute on function public.school_mark_part_time_work_cash_request_submitted(uuid, numeric, text, numeric, uuid, uuid, text, text, uuid, text, text) to authenticated;
grant execute on function public.school_mark_part_time_work_cash_income_confirmed(uuid, uuid, uuid, timestamptz) to authenticated;
grant execute on function public.school_mark_part_time_work_cash_income_rejected(uuid, uuid, text, timestamptz) to authenticated;

commit;
