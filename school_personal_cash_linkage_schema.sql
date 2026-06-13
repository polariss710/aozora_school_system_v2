-- school_personal_cash_linkage_schema.sql
-- Status: executed on school DB 2026-06-13; verified by schema checks,
-- rollback dry-run, and Phase 1 whitelist commit test.
-- Purpose:
-- - Add school-side mapping and outbox tables for Phase 1 personal-business
--   teacher wage JPY payment linkage to Cash System.
-- - Store Cash account identifiers/snapshots only; never store Cash DB URLs or secrets.
-- - Do not write Cash System and do not alter existing payment/wage/reimbursement flows.

create table public.school_personal_cash_account_mappings (
  id uuid primary key default gen_random_uuid(),
  business_entity_id uuid not null references public.school_business_entities(id),
  flow_type text not null default 'teacher_wage_payment',
  school_currency text not null default 'JPY',
  cash_currency text not null default 'JPY',
  cash_user_id uuid not null,
  cash_account_id uuid not null,
  cash_account_name_snapshot text not null,
  cash_account_type_snapshot text not null,
  is_active boolean not null default true,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint school_personal_cash_account_mappings_flow_type_check
    check (flow_type in ('teacher_wage_payment')),
  constraint school_personal_cash_account_mappings_school_currency_check
    check (school_currency = 'JPY'),
  constraint school_personal_cash_account_mappings_cash_currency_check
    check (cash_currency = 'JPY'),
  constraint school_personal_cash_account_mappings_name_not_blank_check
    check (length(trim(cash_account_name_snapshot)) > 0),
  constraint school_personal_cash_account_mappings_type_not_blank_check
    check (length(trim(cash_account_type_snapshot)) > 0)
);

create unique index school_personal_cash_account_mappings_active_uniq
  on public.school_personal_cash_account_mappings (
    business_entity_id,
    flow_type,
    school_currency,
    cash_account_id
  )
  where is_active;

create index school_personal_cash_account_mappings_business_idx
  on public.school_personal_cash_account_mappings (business_entity_id, flow_type, is_active);

create table public.school_personal_cash_linkage_events (
  id uuid primary key default gen_random_uuid(),
  source_table text not null default 'school_payment_requests',
  source_id uuid not null,
  source_event_type text not null default 'teacher_wage_payment_confirm',
  payment_request_id uuid not null references public.school_payment_requests(id),
  business_entity_id uuid not null references public.school_business_entities(id),
  cash_account_mapping_id uuid not null references public.school_personal_cash_account_mappings(id),
  school_account_id uuid references public.school_accounts(id),
  cash_user_id uuid not null,
  cash_account_id uuid not null,
  cash_account_name_snapshot text not null,
  cash_transaction_table text not null default 'home_jpy_transactions',
  cash_transaction_id uuid,
  currency text not null default 'JPY',
  amount numeric not null,
  idempotency_key text not null,
  sync_status text not null default 'pending',
  attempt_no integer not null default 1,
  attempt_count integer not null default 0,
  last_error text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz,
  constraint school_personal_cash_linkage_events_source_table_check
    check (source_table = 'school_payment_requests'),
  constraint school_personal_cash_linkage_events_event_type_check
    check (source_event_type in ('teacher_wage_payment_confirm')),
  constraint school_personal_cash_linkage_events_cash_table_check
    check (cash_transaction_table = 'home_jpy_transactions'),
  constraint school_personal_cash_linkage_events_currency_check
    check (currency = 'JPY'),
  constraint school_personal_cash_linkage_events_amount_check
    check (amount > 0),
  constraint school_personal_cash_linkage_events_status_check
    check (sync_status in ('pending', 'synced', 'failed', 'blocked')),
  constraint school_personal_cash_linkage_events_attempt_no_check
    check (attempt_no > 0),
  constraint school_personal_cash_linkage_events_attempt_count_check
    check (attempt_count >= 0),
  constraint school_personal_cash_linkage_events_synced_id_check
    check (sync_status <> 'synced' or cash_transaction_id is not null)
);

create unique index school_personal_cash_linkage_events_idempotency_uniq
  on public.school_personal_cash_linkage_events (idempotency_key);

create unique index school_personal_cash_linkage_events_source_event_attempt_uniq
  on public.school_personal_cash_linkage_events (
    source_table,
    source_id,
    source_event_type,
    attempt_no
  );

create unique index school_personal_cash_linkage_events_active_attempt_uniq
  on public.school_personal_cash_linkage_events (
    source_table,
    source_id,
    source_event_type
  )
  where sync_status in ('pending_cash_request', 'awaiting_cash_confirmation');

create index school_personal_cash_linkage_events_payment_request_idx
  on public.school_personal_cash_linkage_events (payment_request_id);

create index school_personal_cash_linkage_events_status_idx
  on public.school_personal_cash_linkage_events (sync_status, created_at);

comment on table public.school_personal_cash_account_mappings is
  'Allowlist mapping from personal-business school flows to Cash System accounts. Stores Cash account identifiers and display snapshots only; no Cash DB credentials.';
comment on column public.school_personal_cash_account_mappings.business_entity_id is
  'Must reference an active school_business_entities row with entity_type = personal; enforced by RPC guards.';
comment on column public.school_personal_cash_account_mappings.flow_type is
  'Phase 1 supports teacher_wage_payment only.';
comment on column public.school_personal_cash_account_mappings.cash_user_id is
  'Cash System home_accounts.user_id snapshot/identifier; no cross-DB FK.';
comment on column public.school_personal_cash_account_mappings.cash_account_id is
  'Cash System home_accounts.id snapshot/identifier; no cross-DB FK.';

comment on table public.school_personal_cash_linkage_events is
  'School-side outbox for personal-business Cash System linkage. Phase 1 records teacher wage JPY payment events only and does not write Cash DB.';
comment on column public.school_personal_cash_linkage_events.idempotency_key is
  'Deterministic external key passed to Cash System to prevent duplicate JPY transaction creation.';
comment on column public.school_personal_cash_linkage_events.sync_status is
  'School-side Cash sync lifecycle: pending, synced, failed, or blocked. No automatic background retry in Phase 1.';
