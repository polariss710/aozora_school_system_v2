-- school_personal_cash_linkage_rpcs.sql
-- Status: executed on school DB 2026-06-13; rollback-tested and
-- whitelist commit-tested for Phase 1 mapping/outbox CRUD.
-- Purpose:
-- - Provide guarded school-side RPCs for Phase 1 personal-business Cash linkage mapping/outbox.
-- - Do not write Cash System and do not change existing payment confirmation behavior.

create or replace function public.school_create_personal_cash_account_mapping(
  p_business_entity_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text,
  p_note text default null
)
returns table (
  id uuid,
  business_entity_id uuid,
  flow_type text,
  school_currency text,
  cash_currency text,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  cash_account_type_snapshot text,
  is_active boolean,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity public.school_business_entities%rowtype;
  v_mapping_id uuid;
  v_now timestamptz := now();
  v_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
begin
  if p_business_entity_id is null then
    raise exception 'business entity id is required';
  end if;

  if p_cash_user_id is null then
    raise exception 'Cash user id is required';
  end if;

  if p_cash_account_id is null then
    raise exception 'Cash account id is required';
  end if;

  if v_account_name is null then
    raise exception 'Cash account name snapshot is required';
  end if;

  if v_account_type is null then
    raise exception 'Cash account type snapshot is required';
  end if;

  select *
    into v_entity
    from public.school_business_entities
   where school_business_entities.id = p_business_entity_id;

  if not found then
    raise exception 'business entity not found: %', p_business_entity_id;
  end if;

  if v_entity.is_active is not true then
    raise exception 'business entity is inactive: %', p_business_entity_id;
  end if;

  if coalesce(v_entity.entity_type, '') <> 'personal' then
    raise exception 'Cash linkage mappings are allowed only for personal business entities. entity_type: %', v_entity.entity_type;
  end if;

  select m.id
    into v_mapping_id
    from public.school_personal_cash_account_mappings m
   where m.business_entity_id = p_business_entity_id
     and m.flow_type = 'teacher_wage_payment'
     and m.school_currency = 'JPY'
     and m.cash_currency = 'JPY'
     and m.cash_account_id = p_cash_account_id
     and m.is_active is true
   order by m.created_at asc
   limit 1;

  if v_mapping_id is null then
    insert into public.school_personal_cash_account_mappings (
      business_entity_id,
      flow_type,
      school_currency,
      cash_currency,
      cash_user_id,
      cash_account_id,
      cash_account_name_snapshot,
      cash_account_type_snapshot,
      is_active,
      note,
      created_at,
      updated_at
    )
    values (
      p_business_entity_id,
      'teacher_wage_payment',
      'JPY',
      'JPY',
      p_cash_user_id,
      p_cash_account_id,
      v_account_name,
      v_account_type,
      true,
      nullif(trim(coalesce(p_note, '')), ''),
      v_now,
      v_now
    )
    returning school_personal_cash_account_mappings.id into v_mapping_id;
  end if;

  return query
  select
    m.id,
    m.business_entity_id,
    m.flow_type,
    m.school_currency,
    m.cash_currency,
    m.cash_user_id,
    m.cash_account_id,
    m.cash_account_name_snapshot,
    m.cash_account_type_snapshot,
    m.is_active,
    m.note,
    m.created_at,
    m.updated_at
  from public.school_personal_cash_account_mappings m
  where m.id = v_mapping_id;
end;
$$;

comment on function public.school_create_personal_cash_account_mapping(uuid, uuid, uuid, text, text, text) is
  'Creates or returns an active Phase 1 personal-business teacher_wage_payment JPY Cash account mapping. Does not write Cash DB.';

grant execute on function public.school_create_personal_cash_account_mapping(uuid, uuid, uuid, text, text, text) to authenticated;

create or replace function public.school_update_personal_cash_account_mapping(
  p_mapping_id uuid,
  p_cash_account_name_snapshot text default null,
  p_cash_account_type_snapshot text default null,
  p_is_active boolean default null,
  p_note text default null
)
returns table (
  id uuid,
  business_entity_id uuid,
  flow_type text,
  school_currency text,
  cash_currency text,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  cash_account_type_snapshot text,
  is_active boolean,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mapping public.school_personal_cash_account_mappings%rowtype;
  v_entity public.school_business_entities%rowtype;
  v_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_now timestamptz := now();
begin
  if p_mapping_id is null then
    raise exception 'mapping id is required';
  end if;

  select *
    into v_mapping
    from public.school_personal_cash_account_mappings
   where school_personal_cash_account_mappings.id = p_mapping_id
   for update;

  if not found then
    raise exception 'personal Cash account mapping not found: %', p_mapping_id;
  end if;

  select *
    into v_entity
    from public.school_business_entities
   where school_business_entities.id = v_mapping.business_entity_id;

  if not found or coalesce(v_entity.entity_type, '') <> 'personal' then
    raise exception 'mapping business entity is not a personal business entity: %', v_mapping.business_entity_id;
  end if;

  if p_cash_account_name_snapshot is not null and v_account_name is null then
    raise exception 'Cash account name snapshot cannot be blank';
  end if;

  if p_cash_account_type_snapshot is not null and v_account_type is null then
    raise exception 'Cash account type snapshot cannot be blank';
  end if;

  update public.school_personal_cash_account_mappings as m
     set cash_account_name_snapshot = coalesce(v_account_name, m.cash_account_name_snapshot),
         cash_account_type_snapshot = coalesce(v_account_type, m.cash_account_type_snapshot),
         is_active = coalesce(p_is_active, m.is_active),
         note = case
           when p_note is null then m.note
           else nullif(trim(coalesce(p_note, '')), '')
         end,
         updated_at = v_now
   where m.id = p_mapping_id;

  return query
  select
    m.id,
    m.business_entity_id,
    m.flow_type,
    m.school_currency,
    m.cash_currency,
    m.cash_user_id,
    m.cash_account_id,
    m.cash_account_name_snapshot,
    m.cash_account_type_snapshot,
    m.is_active,
    m.note,
    m.created_at,
    m.updated_at
  from public.school_personal_cash_account_mappings m
  where m.id = p_mapping_id;
end;
$$;

comment on function public.school_update_personal_cash_account_mapping(uuid, text, text, boolean, text) is
  'Updates display snapshots/active state/note for a personal-business Cash account mapping. Does not change Cash ids or write Cash DB.';

grant execute on function public.school_update_personal_cash_account_mapping(uuid, text, text, boolean, text) to authenticated;

create or replace function public.school_list_personal_cash_account_mappings(
  p_business_entity_id uuid default null,
  p_include_inactive boolean default false
)
returns table (
  id uuid,
  business_entity_id uuid,
  business_name text,
  flow_type text,
  school_currency text,
  cash_currency text,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  cash_account_type_snapshot text,
  is_active boolean,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    m.id,
    m.business_entity_id,
    b.name as business_name,
    m.flow_type,
    m.school_currency,
    m.cash_currency,
    m.cash_user_id,
    m.cash_account_id,
    m.cash_account_name_snapshot,
    m.cash_account_type_snapshot,
    m.is_active,
    m.note,
    m.created_at,
    m.updated_at
  from public.school_personal_cash_account_mappings m
  join public.school_business_entities b
    on b.id = m.business_entity_id
  where b.entity_type = 'personal'
    and (p_business_entity_id is null or m.business_entity_id = p_business_entity_id)
    and (p_include_inactive is true or m.is_active is true)
  order by b.name asc, m.cash_account_name_snapshot asc, m.created_at asc;
$$;

comment on function public.school_list_personal_cash_account_mappings(uuid, boolean) is
  'Lists personal-business Cash account mappings for the school API layer. Does not write Cash DB.';

grant execute on function public.school_list_personal_cash_account_mappings(uuid, boolean) to authenticated;

create or replace function public.school_create_personal_cash_linkage_event(
  p_payment_request_id uuid,
  p_cash_account_mapping_id uuid,
  p_note text default null
)
returns table (
  id uuid,
  payment_request_id uuid,
  business_entity_id uuid,
  cash_account_mapping_id uuid,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  currency text,
  amount numeric,
  idempotency_key text,
  sync_status text,
  cash_transaction_id uuid,
  attempt_count integer,
  last_error text,
  note text,
  created_at timestamptz,
  updated_at timestamptz,
  synced_at timestamptz
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

  if coalesce(v_payment.source_type, '') <> 'teacher_wage' then
    raise exception 'only teacher_wage payment requests can create personal Cash linkage events. current source_type: %', v_payment.source_type;
  end if;

  if coalesce(v_payment.currency, '') <> 'JPY' then
    raise exception 'Phase 1 supports only JPY payment requests. current currency: %', v_payment.currency;
  end if;

  if coalesce(v_payment.amount, 0) <= 0 then
    raise exception 'payment request amount must be greater than 0';
  end if;

  if coalesce(v_payment.status, '') <> 'paid' or v_payment.paid_at is null then
    raise exception 'personal Cash linkage event requires a paid payment request. current status: %', v_payment.status;
  end if;

  if v_payment.reversed_at is not null then
    raise exception 'reversed payment requests cannot create Phase 1 Cash linkage events';
  end if;

  if v_payment.business_entity_id is null then
    raise exception 'payment request has no business_entity_id: %', p_payment_request_id;
  end if;

  select *
    into v_entity
    from public.school_business_entities
   where school_business_entities.id = v_payment.business_entity_id;

  if not found then
    raise exception 'business entity not found for payment request: %', v_payment.business_entity_id;
  end if;

  if v_entity.is_active is not true then
    raise exception 'business entity is inactive: %', v_entity.id;
  end if;

  if coalesce(v_entity.entity_type, '') <> 'personal' then
    raise exception 'Cash linkage is allowed only for personal business entities. entity_type: %', v_entity.entity_type;
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
    raise exception 'Cash account mapping is not valid for Phase 1 teacher_wage_payment JPY linkage';
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
       or v_existing.cash_account_id is distinct from v_mapping.cash_account_id
       or v_existing.currency is distinct from 'JPY'
       or v_existing.amount is distinct from v_payment.amount
       or v_existing.idempotency_key is distinct from v_idempotency_key then
      raise exception 'existing Cash linkage event conflicts with requested mapping or payment snapshot: %', v_existing.id;
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
      v_payment.account_id,
      v_mapping.cash_user_id,
      v_mapping.cash_account_id,
      v_mapping.cash_account_name_snapshot,
      'home_jpy_transactions',
      null,
      'JPY',
      v_payment.amount,
      v_idempotency_key,
      'pending',
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
    e.id,
    e.payment_request_id,
    e.business_entity_id,
    e.cash_account_mapping_id,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.currency,
    e.amount,
    e.idempotency_key,
    e.sync_status,
    e.cash_transaction_id,
    e.attempt_count,
    e.last_error,
    e.note,
    e.created_at,
    e.updated_at,
    e.synced_at
  from public.school_personal_cash_linkage_events e
  where e.id = v_event_id;
end;
$$;

comment on function public.school_create_personal_cash_linkage_event(uuid, uuid, text) is
  'Creates or returns a Phase 1 personal-business teacher wage JPY Cash linkage event for a paid school_payment_requests row. Does not write Cash DB.';

grant execute on function public.school_create_personal_cash_linkage_event(uuid, uuid, text) to authenticated;

drop function if exists public.school_get_personal_cash_linkage_events(uuid, text);

create or replace function public.school_get_personal_cash_linkage_events(
  p_payment_request_id uuid default null,
  p_sync_status text default null
)
returns table (
  id uuid,
  source_table text,
  source_id uuid,
  source_event_type text,
  payment_request_id uuid,
  business_entity_id uuid,
  business_name text,
  cash_account_mapping_id uuid,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  cash_account_type_snapshot text,
  cash_transaction_table text,
  cash_transaction_id uuid,
  currency text,
  amount numeric,
  school_amount_jpy numeric,
  payment_currency text,
  payment_exchange_rate numeric,
  payment_amount numeric,
  idempotency_key text,
  sync_status text,
  attempt_no integer,
  attempt_count integer,
  cash_request_id uuid,
  cash_request_status text,
  requested_at timestamptz,
  confirmed_at timestamptz,
  rejected_at timestamptz,
  rejected_reason text,
  cash_request_last_checked_at timestamptz,
  last_error text,
  note text,
  created_at timestamptz,
  updated_at timestamptz,
  synced_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    e.id,
    e.source_table,
    e.source_id,
    e.source_event_type,
    e.payment_request_id,
    e.business_entity_id,
    b.name as business_name,
    e.cash_account_mapping_id,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.cash_account_type_snapshot,
    e.cash_transaction_table,
    e.cash_transaction_id,
    e.currency,
    e.amount,
    e.school_amount_jpy,
    e.payment_currency,
    e.payment_exchange_rate,
    e.payment_amount,
    e.idempotency_key,
    e.sync_status,
    e.attempt_no,
    e.attempt_count,
    e.cash_request_id,
    e.cash_request_status,
    e.requested_at,
    e.confirmed_at,
    e.rejected_at,
    e.rejected_reason,
    e.cash_request_last_checked_at,
    e.last_error,
    e.note,
    e.created_at,
    e.updated_at,
    e.synced_at
  from public.school_personal_cash_linkage_events e
  join public.school_business_entities b
    on b.id = e.business_entity_id
  where (p_payment_request_id is null or e.payment_request_id = p_payment_request_id)
    and (p_sync_status is null or e.sync_status = p_sync_status)
  order by e.attempt_no desc, e.created_at desc, e.id desc;
$$;

comment on function public.school_get_personal_cash_linkage_events(uuid, text) is
  'Lists school-side Cash linkage events for teacher wage payment confirmation attempts. Does not write Cash DB.';

grant execute on function public.school_get_personal_cash_linkage_events(uuid, text) to authenticated;

create or replace function public.school_update_personal_cash_linkage_event_status(
  p_event_id uuid,
  p_sync_status text,
  p_cash_transaction_id uuid default null,
  p_last_error text default null
)
returns table (
  id uuid,
  payment_request_id uuid,
  sync_status text,
  cash_transaction_id uuid,
  attempt_count integer,
  last_error text,
  updated_at timestamptz,
  synced_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.school_personal_cash_linkage_events%rowtype;
  v_status text := nullif(trim(coalesce(p_sync_status, '')), '');
  v_now timestamptz := now();
begin
  if p_event_id is null then
    raise exception 'linkage event id is required';
  end if;

  if v_status is null or v_status not in ('pending', 'synced', 'failed', 'blocked') then
    raise exception 'invalid sync status: %', p_sync_status;
  end if;

  select *
    into v_event
    from public.school_personal_cash_linkage_events
   where school_personal_cash_linkage_events.id = p_event_id
   for update;

  if not found then
    raise exception 'personal Cash linkage event not found: %', p_event_id;
  end if;

  if v_status = 'synced' and coalesce(p_cash_transaction_id, v_event.cash_transaction_id) is null then
    raise exception 'cash_transaction_id is required when sync_status = synced';
  end if;

  update public.school_personal_cash_linkage_events as e
     set sync_status = v_status,
         cash_transaction_id = case
           when p_cash_transaction_id is not null then p_cash_transaction_id
           else e.cash_transaction_id
         end,
         attempt_count = case
           when v_status in ('failed', 'blocked') then e.attempt_count + 1
           else e.attempt_count
         end,
         last_error = case
           when v_status = 'synced' then null
           when p_last_error is not null then nullif(trim(coalesce(p_last_error, '')), '')
           else e.last_error
         end,
         synced_at = case
           when v_status = 'synced' then coalesce(e.synced_at, v_now)
           else e.synced_at
         end,
         updated_at = v_now
   where e.id = p_event_id;

  return query
  select
    e.id,
    e.payment_request_id,
    e.sync_status,
    e.cash_transaction_id,
    e.attempt_count,
    e.last_error,
    e.updated_at,
    e.synced_at
  from public.school_personal_cash_linkage_events e
  where e.id = p_event_id;
end;
$$;

comment on function public.school_update_personal_cash_linkage_event_status(uuid, text, uuid, text) is
  'Updates school-side Cash linkage event sync status/result after an external integration step. Does not write Cash DB.';

grant execute on function public.school_update_personal_cash_linkage_event_status(uuid, text, uuid, text) to authenticated;
