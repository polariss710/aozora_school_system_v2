-- school_personal_cash_payment_request_result_rpcs.sql
-- Status: pending apply on school DB.
-- Purpose:
-- - Reflect Cash-side approval/rejection of a v2 personal-business
--   teacher_wage JPY payment confirmation request back to School.
-- - Cash approval is the first point where the School payment request becomes
--   paid.
-- - Do not write school expense records, school account transactions, school
--   account balances, or Cash DB.

create or replace function public.school_mark_personal_cash_payment_request_confirmed(
  p_event_id uuid,
  p_cash_request_id uuid,
  p_cash_transaction_id uuid,
  p_confirmed_at timestamptz default null
)
returns table (
  payment_request_id uuid,
  linkage_event_id uuid,
  payment_status text,
  sync_status text,
  cash_request_id uuid,
  cash_request_status text,
  cash_transaction_id uuid,
  confirmed_at timestamptz,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.school_personal_cash_linkage_events%rowtype;
  v_payment public.school_payment_requests%rowtype;
  v_confirmed_at timestamptz := coalesce(p_confirmed_at, now());
  v_now timestamptz := now();
begin
  if p_event_id is null then
    raise exception 'linkage event id is required';
  end if;

  if p_cash_request_id is null then
    raise exception 'Cash request id is required';
  end if;

  if p_cash_transaction_id is null then
    raise exception 'Cash transaction id is required for approved Cash request';
  end if;

  select *
    into v_event
    from public.school_personal_cash_linkage_events
   where school_personal_cash_linkage_events.id = p_event_id
   for update;

  if not found then
    raise exception 'personal Cash linkage event not found: %', p_event_id;
  end if;

  if v_event.source_table <> 'school_payment_requests'
     or v_event.source_event_type <> 'teacher_wage_payment_confirm' then
    raise exception 'unsupported Cash linkage event source for payment confirmation result: %.%', v_event.source_table, v_event.source_event_type;
  end if;

  if v_event.cash_request_id is not null
     and v_event.cash_request_id is distinct from p_cash_request_id then
    raise exception 'Cash linkage event references a different Cash request: %', v_event.cash_request_id;
  end if;

  if v_event.cash_transaction_id is not null
     and v_event.cash_transaction_id is distinct from p_cash_transaction_id then
    raise exception 'Cash linkage event already references a different Cash transaction: %', v_event.cash_transaction_id;
  end if;

  select *
    into v_payment
    from public.school_payment_requests
   where school_payment_requests.id = v_event.payment_request_id
   for update;

  if not found then
    raise exception 'payment request not found for Cash linkage event: %', v_event.payment_request_id;
  end if;

  if v_event.sync_status = 'synced' then
    if coalesce(v_payment.status, '') <> 'paid'
       or v_payment.paid_at is null
       or v_event.cash_request_id is distinct from p_cash_request_id
       or v_event.cash_transaction_id is distinct from p_cash_transaction_id
       or v_event.cash_request_status is distinct from 'approved' then
      raise exception 'existing synced Cash linkage event conflicts with approved callback: %', p_event_id;
    end if;

    return query
    select
      v_payment.id,
      v_event.id,
      v_payment.status,
      v_event.sync_status,
      v_event.cash_request_id,
      v_event.cash_request_status,
      v_event.cash_transaction_id,
      v_event.confirmed_at,
      'Cash approval already reflected in School'::text;
    return;
  end if;

  if v_event.sync_status <> 'awaiting_cash_confirmation' then
    raise exception 'Cash linkage event must be awaiting Cash confirmation before approval callback. current status: %', v_event.sync_status;
  end if;

  if v_event.cash_transaction_id is not null then
    raise exception 'Cash linkage event already has a Cash transaction: %', p_event_id;
  end if;

  if coalesce(v_payment.status, '') <> 'pending' then
    raise exception 'payment request must remain pending before Cash approval. current status: %', v_payment.status;
  end if;

  if v_payment.paid_at is not null
     or v_payment.paid_expense_id is not null
     or v_payment.paid_account_transaction_id is not null
     or v_payment.account_id is not null then
    raise exception 'payment request already has payment side effects';
  end if;

  update public.school_payment_requests as p
     set status = 'paid',
         paid_at = v_confirmed_at,
         updated_at = v_now
   where p.id = v_payment.id;

  update public.school_personal_cash_linkage_events as e
     set cash_request_id = p_cash_request_id,
         cash_request_status = 'approved',
         sync_status = 'synced',
         cash_transaction_id = p_cash_transaction_id,
         confirmed_at = v_confirmed_at,
         synced_at = v_confirmed_at,
         cash_request_last_checked_at = v_now,
         last_error = null,
         updated_at = v_now
   where e.id = p_event_id;

  return query
  select
    p.id,
    e.id,
    p.status,
    e.sync_status,
    e.cash_request_id,
    e.cash_request_status,
    e.cash_transaction_id,
    e.confirmed_at,
    'Cash approval reflected in School; payment request marked paid without school ledger side effects'::text
  from public.school_payment_requests p
  join public.school_personal_cash_linkage_events e
    on e.id = p_event_id
  where p.id = v_payment.id;
end;
$$;

comment on function public.school_mark_personal_cash_payment_request_confirmed(uuid, uuid, uuid, timestamptz) is
  'Reflects Cash approval of a v2 personal-business teacher_wage JPY payment request. Marks the School payment request paid and linkage synced, without writing school ledgers or Cash DB.';

grant execute on function public.school_mark_personal_cash_payment_request_confirmed(uuid, uuid, uuid, timestamptz) to authenticated, service_role;

create or replace function public.school_mark_personal_cash_payment_request_rejected(
  p_event_id uuid,
  p_cash_request_id uuid,
  p_rejected_reason text default null,
  p_rejected_at timestamptz default null
)
returns table (
  payment_request_id uuid,
  linkage_event_id uuid,
  payment_status text,
  sync_status text,
  cash_request_id uuid,
  cash_request_status text,
  rejected_at timestamptz,
  rejected_reason text,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.school_personal_cash_linkage_events%rowtype;
  v_payment public.school_payment_requests%rowtype;
  v_rejected_at timestamptz := coalesce(p_rejected_at, now());
  v_reason text := nullif(trim(coalesce(p_rejected_reason, '')), '');
  v_now timestamptz := now();
begin
  if p_event_id is null then
    raise exception 'linkage event id is required';
  end if;

  if p_cash_request_id is null then
    raise exception 'Cash request id is required';
  end if;

  select *
    into v_event
    from public.school_personal_cash_linkage_events
   where school_personal_cash_linkage_events.id = p_event_id
   for update;

  if not found then
    raise exception 'personal Cash linkage event not found: %', p_event_id;
  end if;

  if v_event.source_table <> 'school_payment_requests'
     or v_event.source_event_type <> 'teacher_wage_payment_confirm' then
    raise exception 'unsupported Cash linkage event source for payment rejection result: %.%', v_event.source_table, v_event.source_event_type;
  end if;

  if v_event.cash_request_id is not null
     and v_event.cash_request_id is distinct from p_cash_request_id then
    raise exception 'Cash linkage event references a different Cash request: %', v_event.cash_request_id;
  end if;

  if v_event.cash_transaction_id is not null then
    raise exception 'Cash linkage event already has a Cash transaction and cannot be rejected: %', p_event_id;
  end if;

  select *
    into v_payment
    from public.school_payment_requests
   where school_payment_requests.id = v_event.payment_request_id
   for update;

  if not found then
    raise exception 'payment request not found for Cash linkage event: %', v_event.payment_request_id;
  end if;

  if v_event.sync_status = 'cash_rejected' then
    if coalesce(v_payment.status, '') <> 'pending'
       or v_payment.paid_at is not null
       or v_event.cash_request_id is distinct from p_cash_request_id
       or v_event.cash_request_status is distinct from 'rejected' then
      raise exception 'existing rejected Cash linkage event conflicts with rejection callback: %', p_event_id;
    end if;

    return query
    select
      v_payment.id,
      v_event.id,
      v_payment.status,
      v_event.sync_status,
      v_event.cash_request_id,
      v_event.cash_request_status,
      v_event.rejected_at,
      v_event.rejected_reason,
      'Cash rejection already reflected in School'::text;
    return;
  end if;

  if v_event.sync_status <> 'awaiting_cash_confirmation' then
    raise exception 'Cash linkage event must be awaiting Cash confirmation before rejection callback. current status: %', v_event.sync_status;
  end if;

  if coalesce(v_payment.status, '') <> 'pending' then
    raise exception 'payment request must remain pending for Cash rejection. current status: %', v_payment.status;
  end if;

  if v_payment.paid_at is not null
     or v_payment.paid_expense_id is not null
     or v_payment.paid_account_transaction_id is not null
     or v_payment.account_id is not null then
    raise exception 'payment request already has payment side effects';
  end if;

  update public.school_personal_cash_linkage_events as e
     set cash_request_id = p_cash_request_id,
         cash_request_status = 'rejected',
         sync_status = 'cash_rejected',
         rejected_at = v_rejected_at,
         rejected_reason = v_reason,
         cash_request_last_checked_at = v_now,
         last_error = null,
         updated_at = v_now
   where e.id = p_event_id;

  return query
  select
    p.id,
    e.id,
    p.status,
    e.sync_status,
    e.cash_request_id,
    e.cash_request_status,
    e.rejected_at,
    e.rejected_reason,
    'Cash rejection reflected in School; payment request remains pending'::text
  from public.school_payment_requests p
  join public.school_personal_cash_linkage_events e
    on e.id = p_event_id
  where p.id = v_payment.id;
end;
$$;

comment on function public.school_mark_personal_cash_payment_request_rejected(uuid, uuid, text, timestamptz) is
  'Reflects Cash rejection of a v2 personal-business teacher_wage JPY payment request. Keeps the School payment request pending and linkage cash_rejected, without writing school ledgers or Cash DB.';

grant execute on function public.school_mark_personal_cash_payment_request_rejected(uuid, uuid, text, timestamptz) to authenticated, service_role;
