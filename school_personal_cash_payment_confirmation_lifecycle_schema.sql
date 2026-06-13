-- school_personal_cash_payment_confirmation_lifecycle_schema.sql
-- Status: pending apply on school DB.
-- Purpose:
-- - Prepare School-side lifecycle metadata for Cash linkage v2 page-driven
--   teacher_wage payment confirmation.
-- - School requests Cash confirmation first; Cash approval, not School request,
--   will later mark the payment request paid.
-- - Keep the existing Phase 1 pending/synced/failed/blocked states compatible
--   for the manual zsh verification/operations tool.

alter table public.school_personal_cash_linkage_events
  add column if not exists cash_request_id uuid,
  add column if not exists cash_request_status text,
  add column if not exists requested_at timestamptz,
  add column if not exists confirmed_at timestamptz,
  add column if not exists rejected_at timestamptz,
  add column if not exists rejected_reason text,
  add column if not exists cash_request_last_checked_at timestamptz,
  add column if not exists attempt_no integer;

with ranked_events as (
  select
    id,
    row_number() over (
      partition by source_table, source_id, source_event_type
      order by created_at, id
    ) as derived_attempt_no
  from public.school_personal_cash_linkage_events
)
update public.school_personal_cash_linkage_events as e
   set attempt_no = ranked_events.derived_attempt_no
  from ranked_events
 where e.id = ranked_events.id
   and e.attempt_no is null;

alter table public.school_personal_cash_linkage_events
  alter column attempt_no set default 1,
  alter column attempt_no set not null;

alter table public.school_personal_cash_linkage_events
  drop constraint if exists school_personal_cash_linkage_events_attempt_no_check;

alter table public.school_personal_cash_linkage_events
  add constraint school_personal_cash_linkage_events_attempt_no_check
  check (attempt_no > 0);

drop index if exists public.school_personal_cash_linkage_events_source_event_uniq;

create unique index if not exists school_personal_cash_linkage_events_source_event_attempt_uniq
  on public.school_personal_cash_linkage_events (
    source_table,
    source_id,
    source_event_type,
    attempt_no
  );

create unique index if not exists school_personal_cash_linkage_events_active_attempt_uniq
  on public.school_personal_cash_linkage_events (
    source_table,
    source_id,
    source_event_type
  )
  where sync_status in ('pending_cash_request', 'awaiting_cash_confirmation');

alter table public.school_personal_cash_linkage_events
  drop constraint if exists school_personal_cash_linkage_events_status_check;

alter table public.school_personal_cash_linkage_events
  add constraint school_personal_cash_linkage_events_status_check
  check (
    sync_status in (
      'pending',
      'pending_cash_request',
      'awaiting_cash_confirmation',
      'synced',
      'cash_rejected',
      'failed',
      'blocked'
    )
  );

alter table public.school_personal_cash_linkage_events
  drop constraint if exists school_personal_cash_linkage_events_cash_request_status_check;

alter table public.school_personal_cash_linkage_events
  add constraint school_personal_cash_linkage_events_cash_request_status_check
  check (
    cash_request_status is null
    or cash_request_status in ('pending', 'approved', 'rejected')
  );

alter table public.school_personal_cash_linkage_events
  drop constraint if exists school_personal_cash_linkage_events_request_no_transaction_check;

alter table public.school_personal_cash_linkage_events
  add constraint school_personal_cash_linkage_events_request_no_transaction_check
  check (
    sync_status not in (
      'pending_cash_request',
      'awaiting_cash_confirmation',
      'cash_rejected'
    )
    or cash_transaction_id is null
  );

alter table public.school_personal_cash_linkage_events
  drop constraint if exists school_personal_cash_linkage_events_awaiting_request_id_check;

alter table public.school_personal_cash_linkage_events
  add constraint school_personal_cash_linkage_events_awaiting_request_id_check
  check (
    sync_status <> 'awaiting_cash_confirmation'
    or cash_request_id is not null
  );

alter table public.school_personal_cash_linkage_events
  drop constraint if exists school_personal_cash_linkage_events_rejected_at_check;

alter table public.school_personal_cash_linkage_events
  add constraint school_personal_cash_linkage_events_rejected_at_check
  check (
    sync_status <> 'cash_rejected'
    or rejected_at is not null
  );

alter table public.school_personal_cash_linkage_events
  drop constraint if exists school_personal_cash_linkage_events_cash_request_requested_at_check;

alter table public.school_personal_cash_linkage_events
  add constraint school_personal_cash_linkage_events_cash_request_requested_at_check
  check (
    cash_request_id is null
    or requested_at is not null
  );

create index if not exists school_personal_cash_linkage_events_cash_request_idx
  on public.school_personal_cash_linkage_events (cash_request_id)
  where cash_request_id is not null;

create index if not exists school_personal_cash_linkage_events_cash_lifecycle_idx
  on public.school_personal_cash_linkage_events (
    sync_status,
    cash_request_status,
    requested_at
  );

comment on column public.school_personal_cash_linkage_events.cash_request_id is
  'Cash System home_external_transaction_requests.id snapshot. No cross-DB FK.';
comment on column public.school_personal_cash_linkage_events.cash_request_status is
  'Cash request status snapshot: pending, approved, or rejected.';
comment on column public.school_personal_cash_linkage_events.requested_at is
  'Time when the School event was submitted to Cash System as a pending confirmation request.';
comment on column public.school_personal_cash_linkage_events.confirmed_at is
  'Time when Cash approval was reflected back to School.';
comment on column public.school_personal_cash_linkage_events.rejected_at is
  'Time when Cash rejection was reflected back to School.';
comment on column public.school_personal_cash_linkage_events.rejected_reason is
  'Cash rejection reason snapshot, if any.';
comment on column public.school_personal_cash_linkage_events.cash_request_last_checked_at is
  'Last time School checked or refreshed the Cash request status.';
comment on column public.school_personal_cash_linkage_events.attempt_no is
  'Business retry attempt number for one School source event. Rejected attempts are retained; new Cash submissions create later attempts.';

comment on column public.school_personal_cash_linkage_events.sync_status is
  'School-side Cash linkage lifecycle. Phase 1 operation states remain pending/synced/failed/blocked. Cash linkage v2 adds pending_cash_request, awaiting_cash_confirmation, and cash_rejected for page-driven Cash approval.';
