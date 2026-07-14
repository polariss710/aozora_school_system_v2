-- school_historical_part_time_work_import_schema.sql
-- Version: v10.3.82-historical-part-time-work-import-schema-20260714
-- Status: executed on School DB 2026-07-14; schema and unchanged-row verification passed.
-- Scope:
-- - Add an immutable audit batch table for guarded historical part-time-work imports.
-- - Add per-lesson source provenance columns.
-- - Add historical_confirmed as an explicit pre-Cash-system income linkage status.
-- - Keep normal Cash linkage rows subject to their existing required Cash context.
-- - Does not create functions/RPCs and does not insert or update business rows.

begin;

create table if not exists public.school_historical_part_time_work_import_batches (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  source_sha256 text not null,
  source_filename text not null,
  import_kind text not null,
  workplace_name text not null,
  period_start text not null,
  period_end text not null,
  expected_lesson_count integer not null,
  expected_total_jpy integer not null,
  expected_total_cny numeric not null,
  status text not null default 'completed',
  result_snapshot jsonb not null default '{}'::jsonb,
  imported_by text not null default current_user,
  imported_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.school_historical_part_time_work_import_batches
  drop constraint if exists school_historical_ptw_batches_source_key_check,
  drop constraint if exists school_historical_ptw_batches_sha256_check,
  drop constraint if exists school_historical_ptw_batches_filename_check,
  drop constraint if exists school_historical_ptw_batches_kind_check,
  drop constraint if exists school_historical_ptw_batches_workplace_check,
  drop constraint if exists school_historical_ptw_batches_period_check,
  drop constraint if exists school_historical_ptw_batches_totals_check,
  drop constraint if exists school_historical_ptw_batches_status_check,
  add constraint school_historical_ptw_batches_source_key_check
    check (length(trim(source_key)) between 8 and 240),
  add constraint school_historical_ptw_batches_sha256_check
    check (source_sha256 ~ '^[0-9a-f]{64}$'),
  add constraint school_historical_ptw_batches_filename_check
    check (length(trim(source_filename)) between 1 and 240),
  add constraint school_historical_ptw_batches_kind_check
    check (import_kind in ('historical', 'test')),
  add constraint school_historical_ptw_batches_workplace_check
    check (workplace_name in ('诺应教育', '致远教育', '新领域')),
  add constraint school_historical_ptw_batches_period_check
    check (
      period_start ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
      and period_end ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
      and period_start <= period_end
    ),
  add constraint school_historical_ptw_batches_totals_check
    check (expected_lesson_count > 0 and expected_total_jpy > 0 and expected_total_cny > 0),
  add constraint school_historical_ptw_batches_status_check
    check (status = 'completed');

comment on table public.school_historical_part_time_work_import_batches is
  'Owner-only audit record for an all-or-nothing historical external part-time-work import.';
comment on column public.school_historical_part_time_work_import_batches.result_snapshot is
  'DB-generated identifiers and aggregate verification only; the raw personal-data manifest is not stored here.';

alter table public.school_part_time_work_lessons
  add column if not exists historical_import_batch_id uuid
    references public.school_historical_part_time_work_import_batches(id),
  add column if not exists historical_source_row integer;

alter table public.school_part_time_work_lessons
  drop constraint if exists school_part_time_work_lessons_historical_source_check,
  add constraint school_part_time_work_lessons_historical_source_check
    check (
      (historical_import_batch_id is null and historical_source_row is null)
      or (historical_import_batch_id is not null and historical_source_row > 0)
    );

create unique index if not exists school_part_time_work_lessons_historical_source_idx
  on public.school_part_time_work_lessons (
    historical_import_batch_id,
    historical_source_row,
    record_kind
  )
  where historical_import_batch_id is not null;

alter table public.school_personal_cash_income_linkage_events
  alter column cash_user_id drop not null,
  alter column cash_account_id drop not null,
  alter column cash_account_name_snapshot drop not null,
  alter column cash_transaction_table drop not null;

alter table public.school_personal_cash_income_linkage_events
  drop constraint if exists school_pc_income_events_account_name_not_blank_check,
  drop constraint if exists school_pc_income_events_cash_table_check,
  drop constraint if exists school_pc_income_events_status_check,
  drop constraint if exists school_pc_income_events_synced_id_check,
  drop constraint if exists school_pc_income_events_context_check,
  add constraint school_pc_income_events_account_name_not_blank_check
    check (cash_account_name_snapshot is null or length(trim(cash_account_name_snapshot)) > 0),
  add constraint school_pc_income_events_cash_table_check
    check (
      cash_transaction_table is null
      or cash_transaction_table in ('home_jpy_transactions', 'home_cny_transactions')
    ),
  add constraint school_pc_income_events_status_check
    check (
      sync_status in (
        'pending',
        'pending_cash_request',
        'awaiting_cash_confirmation',
        'synced',
        'historical_confirmed',
        'cash_rejected',
        'failed',
        'blocked'
      )
    ),
  add constraint school_pc_income_events_synced_id_check
    check (sync_status <> 'synced' or cash_transaction_id is not null),
  add constraint school_pc_income_events_context_check
    check (
      (
        sync_status = 'historical_confirmed'
        and cash_user_id is null
        and cash_account_id is null
        and cash_account_name_snapshot is null
        and cash_account_type_snapshot is null
        and cash_transaction_table is null
        and cash_transaction_id is null
        and cash_request_id is null
        and cash_request_status is null
        and payment_currency in ('JPY', 'CNY')
        and payment_amount > 0
        and confirmed_at is not null
        and synced_at is not null
      )
      or (
        sync_status <> 'historical_confirmed'
        and cash_user_id is not null
        and cash_account_id is not null
        and cash_account_name_snapshot is not null
        and cash_transaction_table is not null
      )
    );

revoke all on table public.school_historical_part_time_work_import_batches from anon, authenticated;

commit;
