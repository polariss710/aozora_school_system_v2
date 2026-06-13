-- school_personal_cash_income_linkage_rpcs.sql
-- Status: prepared 2026-06-13; not executed in this checkpoint.
-- Purpose:
-- - Provide the Phase 2 status-update RPC for personal-business tuition
--   JPY income linkage events.
-- - Provide a narrow operator retry RPC for failed tuition income linkage
--   events; retry only resets failed events to pending.
-- - Do not write Cash System and do not affect Phase 1 payment linkage RPCs.

create or replace function public.school_update_personal_cash_income_linkage_event_status(
  p_event_id uuid,
  p_sync_status text,
  p_cash_transaction_id uuid default null,
  p_last_error text default null
)
returns table (
  id uuid,
  income_record_id uuid,
  sync_status text,
  cash_transaction_id uuid,
  retry_count integer,
  last_error text,
  updated_at timestamptz,
  synced_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.school_personal_cash_income_linkage_events%rowtype;
  v_status text := nullif(trim(coalesce(p_sync_status, '')), '');
  v_now timestamptz := now();
begin
  if p_event_id is null then
    raise exception 'income linkage event id is required';
  end if;

  if v_status is null or v_status not in ('pending', 'synced', 'failed') then
    raise exception 'invalid sync status: %', p_sync_status;
  end if;

  select *
    into v_event
    from public.school_personal_cash_income_linkage_events
   where school_personal_cash_income_linkage_events.id = p_event_id
   for update;

  if not found then
    raise exception 'personal Cash income linkage event not found: %', p_event_id;
  end if;

  if v_status = 'synced' and coalesce(p_cash_transaction_id, v_event.cash_transaction_id) is null then
    raise exception 'cash_transaction_id is required when sync_status = synced';
  end if;

  update public.school_personal_cash_income_linkage_events as e
     set sync_status = v_status,
         cash_transaction_id = case
           when p_cash_transaction_id is not null then p_cash_transaction_id
           else e.cash_transaction_id
         end,
         retry_count = case
           when v_status = 'failed' then e.retry_count + 1
           else e.retry_count
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
    e.income_record_id,
    e.sync_status,
    e.cash_transaction_id,
    e.retry_count,
    e.last_error,
    e.updated_at,
    e.synced_at
  from public.school_personal_cash_income_linkage_events e
  where e.id = p_event_id;
end;
$$;

comment on function public.school_update_personal_cash_income_linkage_event_status(uuid, text, uuid, text) is
  'Updates school-side Phase 2 personal-business tuition income Cash linkage event sync status/result after an external integration step. Does not write Cash DB.';

grant execute on function public.school_update_personal_cash_income_linkage_event_status(uuid, text, uuid, text) to authenticated;

create or replace function public.school_retry_personal_cash_income_linkage_event(
  p_event_id uuid
)
returns table (
  id uuid,
  income_record_id uuid,
  sync_status text,
  cash_transaction_id uuid,
  retry_count integer,
  last_error text,
  updated_at timestamptz,
  synced_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.school_personal_cash_income_linkage_events%rowtype;
  v_now timestamptz := now();
begin
  if p_event_id is null then
    raise exception 'income linkage event id is required';
  end if;

  select *
    into v_event
    from public.school_personal_cash_income_linkage_events
   where school_personal_cash_income_linkage_events.id = p_event_id
   for update;

  if not found then
    raise exception 'personal Cash income linkage event not found: %', p_event_id;
  end if;

  if v_event.source_table <> 'school_income_records'
     or v_event.source_event_type <> 'tuition_income_received' then
    raise exception 'only tuition income linkage events can be retried';
  end if;

  if v_event.sync_status = 'pending' then
    raise exception 'income linkage event is already pending';
  end if;

  if v_event.sync_status = 'synced' then
    raise exception 'synced income linkage event cannot be retried';
  end if;

  if v_event.sync_status <> 'failed' then
    raise exception 'only failed income linkage events can be retried';
  end if;

  if v_event.cash_transaction_id is not null then
    raise exception 'income linkage event with cash_transaction_id cannot be retried';
  end if;

  update public.school_personal_cash_income_linkage_events as e
     set sync_status = 'pending',
         last_error = null,
         updated_at = v_now,
         synced_at = null
   where e.id = p_event_id;

  return query
  select
    e.id,
    e.income_record_id,
    e.sync_status,
    e.cash_transaction_id,
    e.retry_count,
    e.last_error,
    e.updated_at,
    e.synced_at
  from public.school_personal_cash_income_linkage_events e
  where e.id = p_event_id;
end;
$$;

comment on function public.school_retry_personal_cash_income_linkage_event(uuid) is
  'Resets a failed Phase 2 personal-business tuition income Cash linkage event back to pending for manual sync executor retry. Does not write Cash DB or create transactions.';

grant execute on function public.school_retry_personal_cash_income_linkage_event(uuid) to authenticated;
