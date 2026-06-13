-- school_request_personal_cash_payment_confirmation_rpc.sql
-- Status: pending apply on school DB.
-- Purpose:
-- - Create or reuse a School-side Cash confirmation request event for one
--   personal-business teacher_wage JPY payment request.
-- - Do not mark the payment request paid.
-- - Do not write school account ledgers, school expense records, or Cash DB.
-- - Prepare the first writeback step after the future Edge Function creates a
--   Cash pending external transaction request.

create or replace function public.school_request_personal_cash_payment_confirmation(
  p_payment_request_id uuid,
  p_cash_account_mapping_id uuid,
  p_note text default null
)
returns table (
  payment_request_id uuid,
  linkage_event_id uuid,
  sync_status text,
  idempotency_key text,
  amount numeric,
  currency text,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  cash_request_id uuid,
  cash_request_status text,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.school_payment_requests%rowtype;
  v_entity public.school_business_entities%rowtype;
  v_mapping public.school_personal_cash_account_mappings%rowtype;
  v_existing public.school_personal_cash_linkage_events%rowtype;
  v_event_id uuid;
  v_idempotency_key text;
  v_now timestamptz := now();
begin
  if p_payment_request_id is null then
    raise exception 'payment request id is required';
  end if;

  if p_cash_account_mapping_id is null then
    raise exception 'Cash account mapping id is required';
  end if;

  select *
    into v_payment
    from public.school_payment_requests
   where school_payment_requests.id = p_payment_request_id
   for update;

  if not found then
    raise exception 'payment request not found: %', p_payment_request_id;
  end if;

  if coalesce(v_payment.status, '') <> 'pending' then
    raise exception 'payment request status must be pending before Cash confirmation request. current status: %', v_payment.status;
  end if;

  if coalesce(v_payment.source_type, '') <> 'teacher_wage' then
    raise exception 'only teacher_wage payment requests can request personal Cash confirmation. current source_type: %', v_payment.source_type;
  end if;

  if coalesce(v_payment.currency, '') <> 'JPY' then
    raise exception 'personal Cash confirmation request supports only JPY. current currency: %', v_payment.currency;
  end if;

  if coalesce(v_payment.amount, 0) <= 0 then
    raise exception 'payment request amount must be greater than 0';
  end if;

  if v_payment.paid_at is not null
     or v_payment.paid_expense_id is not null
     or v_payment.paid_account_transaction_id is not null
     or v_payment.account_id is not null then
    raise exception 'payment request already has payment side effects';
  end if;

  if v_payment.reversed_at is not null then
    raise exception 'reversed payment requests cannot request personal Cash confirmation';
  end if;

  if v_payment.business_entity_id is null then
    raise exception 'payment request has no business_entity_id: %', p_payment_request_id;
  end if;

  select *
    into v_entity
    from public.school_business_entities
   where school_business_entities.id = v_payment.business_entity_id;

  if not found then
    raise exception 'business entity not found: %', v_payment.business_entity_id;
  end if;

  if v_entity.is_active is not true then
    raise exception 'business entity is inactive: %', v_entity.id;
  end if;

  if coalesce(v_entity.entity_type, '') <> 'personal' then
    raise exception 'personal Cash confirmation is allowed only for personal business entities. entity_type: %', v_entity.entity_type;
  end if;

  select *
    into v_mapping
    from public.school_personal_cash_account_mappings
   where school_personal_cash_account_mappings.id = p_cash_account_mapping_id
   for update;

  if not found then
    raise exception 'personal Cash account mapping not found: %', p_cash_account_mapping_id;
  end if;

  if v_mapping.is_active is not true then
    raise exception 'personal Cash account mapping is inactive: %', p_cash_account_mapping_id;
  end if;

  if v_mapping.business_entity_id is distinct from v_payment.business_entity_id then
    raise exception 'Cash account mapping business entity does not match payment request';
  end if;

  if v_mapping.flow_type <> 'teacher_wage_payment'
     or v_mapping.school_currency <> 'JPY'
     or v_mapping.cash_currency <> 'JPY' then
    raise exception 'Cash account mapping is not valid for teacher_wage_payment JPY confirmation requests';
  end if;

  v_idempotency_key := concat(
    'aozora_school:school_payment_requests:',
    p_payment_request_id::text,
    ':teacher_wage_payment_confirm'
  );

  select *
    into v_existing
    from public.school_personal_cash_linkage_events e
   where e.source_table = 'school_payment_requests'
     and e.source_id = p_payment_request_id
     and e.source_event_type = 'teacher_wage_payment_confirm'
   for update;

  if found then
    if v_existing.payment_request_id is distinct from p_payment_request_id
       or v_existing.business_entity_id is distinct from v_payment.business_entity_id
       or v_existing.cash_account_mapping_id is distinct from p_cash_account_mapping_id
       or v_existing.cash_user_id is distinct from v_mapping.cash_user_id
       or v_existing.cash_account_id is distinct from v_mapping.cash_account_id
       or v_existing.currency is distinct from 'JPY'
       or v_existing.amount is distinct from v_payment.amount
       or v_existing.idempotency_key is distinct from v_idempotency_key then
      raise exception 'existing Cash linkage event conflicts with requested mapping or payment snapshot: %', v_existing.id;
    end if;

    if v_existing.cash_transaction_id is not null then
      raise exception 'existing Cash linkage event already has a Cash transaction: %', v_existing.id;
    end if;

    if v_existing.sync_status not in ('pending_cash_request', 'awaiting_cash_confirmation') then
      raise exception 'existing Cash linkage event is not in a requestable v2 state: %', v_existing.sync_status;
    end if;

    v_event_id := v_existing.id;
  else
    insert into public.school_personal_cash_linkage_events (
      source_table,
      source_id,
      source_event_type,
      payment_request_id,
      business_entity_id,
      cash_account_mapping_id,
      school_account_id,
      cash_user_id,
      cash_account_id,
      cash_account_name_snapshot,
      cash_transaction_table,
      cash_transaction_id,
      currency,
      amount,
      idempotency_key,
      sync_status,
      cash_request_id,
      cash_request_status,
      requested_at,
      confirmed_at,
      rejected_at,
      rejected_reason,
      cash_request_last_checked_at,
      attempt_count,
      last_error,
      note,
      created_at,
      updated_at,
      synced_at
    )
    values (
      'school_payment_requests',
      p_payment_request_id,
      'teacher_wage_payment_confirm',
      p_payment_request_id,
      v_payment.business_entity_id,
      p_cash_account_mapping_id,
      null,
      v_mapping.cash_user_id,
      v_mapping.cash_account_id,
      v_mapping.cash_account_name_snapshot,
      'home_jpy_transactions',
      null,
      'JPY',
      v_payment.amount,
      v_idempotency_key,
      'pending_cash_request',
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      0,
      null,
      nullif(trim(coalesce(p_note, '')), ''),
      v_now,
      v_now,
      null
    )
    returning school_personal_cash_linkage_events.id into v_event_id;
  end if;

  return query
  select
    e.payment_request_id,
    e.id,
    e.sync_status,
    e.idempotency_key,
    e.amount,
    e.currency,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.cash_request_id,
    e.cash_request_status,
    case
      when e.sync_status = 'awaiting_cash_confirmation' then 'Cash confirmation request already submitted'
      else 'School Cash confirmation request event is ready to submit'
    end::text
  from public.school_personal_cash_linkage_events e
  where e.id = v_event_id;
end;
$$;

comment on function public.school_request_personal_cash_payment_confirmation(uuid, uuid, text) is
  'Creates or returns a v2 personal-business teacher_wage JPY Cash confirmation request event. Does not mark the payment request paid, write school ledgers, create school expenses, or write Cash DB.';

grant execute on function public.school_request_personal_cash_payment_confirmation(uuid, uuid, text) to authenticated;

create or replace function public.school_mark_personal_cash_payment_request_submitted(
  p_event_id uuid,
  p_cash_request_id uuid,
  p_cash_request_status text default 'pending'
)
returns table (
  payment_request_id uuid,
  linkage_event_id uuid,
  sync_status text,
  cash_request_id uuid,
  cash_request_status text,
  requested_at timestamptz,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.school_personal_cash_linkage_events%rowtype;
  v_payment public.school_payment_requests%rowtype;
  v_status text := nullif(trim(coalesce(p_cash_request_status, '')), '');
  v_now timestamptz := now();
begin
  if p_event_id is null then
    raise exception 'linkage event id is required';
  end if;

  if p_cash_request_id is null then
    raise exception 'Cash request id is required';
  end if;

  if v_status is null or v_status <> 'pending' then
    raise exception 'submitted Cash request status must be pending. current status: %', p_cash_request_status;
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
    raise exception 'unsupported Cash linkage event source for payment confirmation request: %.%', v_event.source_table, v_event.source_event_type;
  end if;

  if v_event.cash_transaction_id is not null then
    raise exception 'Cash linkage event already has a Cash transaction: %', p_event_id;
  end if;

  if v_event.sync_status not in ('pending_cash_request', 'awaiting_cash_confirmation') then
    raise exception 'Cash linkage event cannot be marked submitted from status: %', v_event.sync_status;
  end if;

  if v_event.cash_request_id is not null
     and v_event.cash_request_id is distinct from p_cash_request_id then
    raise exception 'Cash linkage event already references a different Cash request: %', v_event.cash_request_id;
  end if;

  select *
    into v_payment
    from public.school_payment_requests
   where school_payment_requests.id = v_event.payment_request_id
   for update;

  if not found then
    raise exception 'payment request not found for Cash linkage event: %', v_event.payment_request_id;
  end if;

  if coalesce(v_payment.status, '') <> 'pending' then
    raise exception 'payment request must remain pending while awaiting Cash confirmation. current status: %', v_payment.status;
  end if;

  if v_payment.paid_at is not null
     or v_payment.paid_expense_id is not null
     or v_payment.paid_account_transaction_id is not null
     or v_payment.account_id is not null then
    raise exception 'payment request already has payment side effects';
  end if;

  update public.school_personal_cash_linkage_events as e
     set cash_request_id = p_cash_request_id,
         cash_request_status = 'pending',
         sync_status = 'awaiting_cash_confirmation',
         requested_at = coalesce(e.requested_at, v_now),
         cash_request_last_checked_at = v_now,
         last_error = null,
         updated_at = v_now
   where e.id = p_event_id;

  return query
  select
    e.payment_request_id,
    e.id,
    e.sync_status,
    e.cash_request_id,
    e.cash_request_status,
    e.requested_at,
    'Cash confirmation request submitted; payment request remains pending until Cash approval'::text
  from public.school_personal_cash_linkage_events e
  where e.id = p_event_id;
end;
$$;

comment on function public.school_mark_personal_cash_payment_request_submitted(uuid, uuid, text) is
  'Marks a v2 personal-business teacher_wage payment Cash linkage event as submitted to Cash pending request. Does not mark the payment request paid and does not write Cash DB.';

grant execute on function public.school_mark_personal_cash_payment_request_submitted(uuid, uuid, text) to authenticated;
