-- school_personal_cash_income_linkage_schema.sql
-- Status: executed on School DB 2026-06-13 for historical Phase 2 personal tuition linkage.
-- Purpose:
-- - Add school-side outbox table for Phase 2 personal-business tuition
--   JPY income linkage to Cash System.
-- - Extend the personal Cash account mapping allowlist for tuition income.
-- - Store Cash account identifiers/snapshots only; never store Cash DB URLs or secrets.
-- - Do not write Cash System and do not alter existing income/payment UI flows.

alter table public.school_personal_cash_account_mappings
  drop constraint if exists school_personal_cash_account_mappings_flow_type_check;

alter table public.school_personal_cash_account_mappings
  add constraint school_personal_cash_account_mappings_flow_type_check
  check (flow_type in ('teacher_wage_payment', 'tuition_income'));

create table public.school_personal_cash_income_linkage_events (
  id uuid primary key default gen_random_uuid(),
  source_table text not null default 'school_income_records',
  source_id uuid not null,
  source_event_type text not null default 'tuition_income_received',
  income_record_id uuid not null references public.school_income_records(id),
  business_entity_id uuid not null references public.school_business_entities(id),
  cash_account_mapping_id uuid not null references public.school_personal_cash_account_mappings(id),
  cash_user_id uuid not null,
  cash_account_id uuid not null,
  cash_account_name_snapshot text not null,
  cash_transaction_table text not null default 'home_jpy_transactions',
  cash_transaction_id uuid,
  currency text not null default 'JPY',
  amount numeric not null,
  idempotency_key text not null,
  sync_status text not null default 'pending',
  retry_count integer not null default 0,
  last_error text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz,
  constraint school_pc_income_events_source_table_check
    check (source_table = 'school_income_records'),
  constraint school_pc_income_events_source_id_check
    check (source_id = income_record_id),
  constraint school_pc_income_events_event_type_check
    check (source_event_type = 'tuition_income_received'),
  constraint school_pc_income_events_cash_table_check
    check (cash_transaction_table = 'home_jpy_transactions'),
  constraint school_pc_income_events_currency_check
    check (currency = 'JPY'),
  constraint school_pc_income_events_amount_check
    check (amount > 0),
  constraint school_pc_income_events_status_check
    check (sync_status in ('pending', 'synced', 'failed')),
  constraint school_pc_income_events_retry_count_check
    check (retry_count >= 0),
  constraint school_pc_income_events_idempotency_not_blank_check
    check (length(trim(idempotency_key)) > 0),
  constraint school_pc_income_events_account_name_not_blank_check
    check (length(trim(cash_account_name_snapshot)) > 0),
  constraint school_pc_income_events_synced_id_check
    check (sync_status <> 'synced' or cash_transaction_id is not null)
);

create unique index school_pc_income_events_idempotency_uniq
  on public.school_personal_cash_income_linkage_events (idempotency_key);

create unique index school_pc_income_events_income_event_uniq
  on public.school_personal_cash_income_linkage_events (
    income_record_id,
    source_event_type
  );

create unique index school_pc_income_events_source_event_uniq
  on public.school_personal_cash_income_linkage_events (
    source_table,
    source_id,
    source_event_type
  );

create index school_pc_income_events_income_record_idx
  on public.school_personal_cash_income_linkage_events (income_record_id);

create index school_pc_income_events_business_idx
  on public.school_personal_cash_income_linkage_events (business_entity_id);

create index school_pc_income_events_mapping_idx
  on public.school_personal_cash_income_linkage_events (cash_account_mapping_id);

create index school_pc_income_events_status_idx
  on public.school_personal_cash_income_linkage_events (sync_status, created_at);

comment on column public.school_personal_cash_account_mappings.flow_type is
  'Allowed personal-business Cash linkage flow. Phase 1 supports teacher_wage_payment; Phase 2 adds tuition_income. Both are JPY-only by table constraints.';

comment on table public.school_personal_cash_income_linkage_events is
  'School-side outbox for Phase 2 personal-business tuition JPY income linkage to Cash System. Stores only school-side event state and Cash account identifiers/snapshots; does not write Cash DB.';
comment on column public.school_personal_cash_income_linkage_events.source_table is
  'Fixed to school_income_records for Phase 2 tuition income linkage.';
comment on column public.school_personal_cash_income_linkage_events.source_event_type is
  'Fixed to tuition_income_received and maps to Cash external_event_type.';
comment on column public.school_personal_cash_income_linkage_events.income_record_id is
  'Source school_income_records id for the tuition income row.';
comment on column public.school_personal_cash_income_linkage_events.cash_account_mapping_id is
  'References the personal-business Cash account mapping. Creation RPC must require flow_type = tuition_income and JPY currencies.';
comment on column public.school_personal_cash_income_linkage_events.cash_user_id is
  'Cash System home_accounts.user_id snapshot/identifier; no cross-DB FK.';
comment on column public.school_personal_cash_income_linkage_events.cash_account_id is
  'Cash System home_accounts.id snapshot/identifier; no cross-DB FK.';
comment on column public.school_personal_cash_income_linkage_events.idempotency_key is
  'Deterministic external key passed to Cash System to prevent duplicate JPY income transaction creation.';
comment on column public.school_personal_cash_income_linkage_events.sync_status is
  'School-side Cash sync lifecycle for Phase 2 tuition income: pending, synced, or failed.';
comment on column public.school_personal_cash_income_linkage_events.retry_count is
  'Manual retry counter for failed sync attempts; no automatic background retry in Phase 2 v1.';
