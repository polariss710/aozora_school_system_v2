-- school_part_time_work_records_schema.sql
-- Purpose: Define the standalone external cram-school part-time work table.
-- Status: executed on School DB 2026-06-15; verified by read-only schema inspection.
--
-- Scope:
-- - Standalone records for external cram-school / external institution work.
-- - Does not reference students, lesson management, teacher_wage, payment requests, or Cash.
-- - V1 stores hours and wage amounts on the same record.
-- - Soft delete uses deleted_at; deleted records are excluded by RPC list/stats.
-- - No real business data or test data is inserted by this file.

begin;

create table if not exists public.school_part_time_work_records (
  id uuid primary key default gen_random_uuid(),
  work_date date not null,
  year_month text not null,
  workplace_name text not null,
  teacher_name text,
  subject_name text,
  class_description text,
  hours numeric(8,2) not null default 0,
  hourly_rate_jpy integer not null default 0,
  lesson_wage_jpy integer not null default 0,
  transportation_fee_jpy integer not null default 0,
  adjustment_jpy integer not null default 0,
  total_wage_jpy integer not null default 0,
  payment_status text not null default 'unpaid',
  paid_date date,
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.school_part_time_work_records
  add column if not exists work_date date,
  add column if not exists year_month text,
  add column if not exists workplace_name text,
  add column if not exists teacher_name text,
  add column if not exists subject_name text,
  add column if not exists class_description text,
  add column if not exists hours numeric(8,2) default 0,
  add column if not exists hourly_rate_jpy integer default 0,
  add column if not exists lesson_wage_jpy integer default 0,
  add column if not exists transportation_fee_jpy integer default 0,
  add column if not exists adjustment_jpy integer default 0,
  add column if not exists total_wage_jpy integer default 0,
  add column if not exists payment_status text default 'unpaid',
  add column if not exists paid_date date,
  add column if not exists memo text,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now(),
  add column if not exists deleted_at timestamptz;

alter table public.school_part_time_work_records
  alter column work_date set not null,
  alter column year_month set not null,
  alter column workplace_name set not null,
  alter column hours set default 0,
  alter column hours set not null,
  alter column hourly_rate_jpy set default 0,
  alter column hourly_rate_jpy set not null,
  alter column lesson_wage_jpy set default 0,
  alter column lesson_wage_jpy set not null,
  alter column transportation_fee_jpy set default 0,
  alter column transportation_fee_jpy set not null,
  alter column adjustment_jpy set default 0,
  alter column adjustment_jpy set not null,
  alter column total_wage_jpy set default 0,
  alter column total_wage_jpy set not null,
  alter column payment_status set default 'unpaid',
  alter column payment_status set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

alter table public.school_part_time_work_records
  drop constraint if exists school_part_time_work_records_year_month_check,
  drop constraint if exists school_part_time_work_records_workplace_name_check,
  drop constraint if exists school_part_time_work_records_hours_check,
  drop constraint if exists school_part_time_work_records_hourly_rate_check,
  drop constraint if exists school_part_time_work_records_lesson_wage_check,
  drop constraint if exists school_part_time_work_records_transport_check,
  drop constraint if exists school_part_time_work_records_total_wage_check,
  drop constraint if exists school_part_time_work_records_payment_status_check,
  add constraint school_part_time_work_records_year_month_check
    check (year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  add constraint school_part_time_work_records_workplace_name_check
    check (length(trim(workplace_name)) > 0),
  add constraint school_part_time_work_records_hours_check
    check (hours >= 0),
  add constraint school_part_time_work_records_hourly_rate_check
    check (hourly_rate_jpy >= 0),
  add constraint school_part_time_work_records_lesson_wage_check
    check (lesson_wage_jpy >= 0),
  add constraint school_part_time_work_records_transport_check
    check (transportation_fee_jpy >= 0),
  add constraint school_part_time_work_records_total_wage_check
    check (total_wage_jpy >= 0),
  add constraint school_part_time_work_records_payment_status_check
    check (payment_status in ('unpaid', 'paid', 'cancelled'));

create index if not exists school_part_time_work_records_month_date_idx
  on public.school_part_time_work_records (year_month, work_date desc, created_at desc)
  where deleted_at is null;

create index if not exists school_part_time_work_records_workplace_idx
  on public.school_part_time_work_records (workplace_name)
  where deleted_at is null;

create index if not exists school_part_time_work_records_payment_status_idx
  on public.school_part_time_work_records (payment_status)
  where deleted_at is null;

revoke all on table public.school_part_time_work_records from anon;
revoke all on table public.school_part_time_work_records from authenticated;

commit;
