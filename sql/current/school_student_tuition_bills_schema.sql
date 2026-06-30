-- school_student_tuition_bills_schema.sql
-- Purpose:
-- - Add a School-side student tuition bill snapshot table.
-- - A bill freezes the DB/RPC-authoritative JPY amount generated from planned
--   lessons and the previous-month CNY carryover used when submitting Cash.
-- - This schema file does not create functions and does not write business data.

begin;

create table if not exists public.school_student_tuition_bills (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.school_students(id),
  business_entity_id uuid not null references public.school_business_entities(id),
  billing_month text not null,
  previous_settlement_month text not null,
  previous_settlement_id uuid references public.school_student_monthly_settlements(id),
  previous_carryover_cny numeric not null default 0,
  planned_lesson_count integer not null default 0,
  planned_lesson_hours numeric not null default 0,
  planned_lesson_fee_jpy numeric not null default 0,
  bill_amount_jpy numeric not null default 0,
  currency text not null default 'JPY',
  status text not null default 'draft',
  income_record_id uuid references public.school_income_records(id),
  source_snapshot jsonb not null default '{}'::jsonb,
  note text,
  app_type text not null default 'school',
  created_by text default current_user,
  updated_by text default current_user,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  income_created_at timestamptz,
  cancelled_at timestamptz,
  cancelled_reason text,
  constraint school_student_tuition_bills_billing_month_check
    check (billing_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_student_tuition_bills_previous_month_check
    check (previous_settlement_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_student_tuition_bills_amount_check
    check (
      planned_lesson_count >= 0
      and planned_lesson_hours >= 0
      and planned_lesson_fee_jpy >= 0
      and bill_amount_jpy > 0
    ),
  constraint school_student_tuition_bills_currency_check
    check (currency = 'JPY'),
  constraint school_student_tuition_bills_status_check
    check (status in ('draft', 'income_created', 'cancelled')),
  constraint school_student_tuition_bills_income_status_check
    check (
      (status = 'income_created' and income_record_id is not null and income_created_at is not null)
      or (status <> 'income_created')
    ),
  constraint school_student_tuition_bills_app_type_check
    check (app_type = 'school')
);

create unique index if not exists school_student_tuition_bills_active_uniq
  on public.school_student_tuition_bills (student_id, business_entity_id, billing_month)
  where status in ('draft', 'income_created');

create index if not exists school_student_tuition_bills_month_idx
  on public.school_student_tuition_bills (billing_month, status, created_at);

create index if not exists school_student_tuition_bills_income_idx
  on public.school_student_tuition_bills (income_record_id)
  where income_record_id is not null;

comment on table public.school_student_tuition_bills is
  'School-side student tuition bill snapshots. DB/RPC generates JPY planned-lesson tuition and freezes previous-month CNY carryover before a pending income/Cash request is created.';

comment on column public.school_student_tuition_bills.billing_month is
  'Tuition bill month. Planned lessons are summed from this YYYY-MM month.';

comment on column public.school_student_tuition_bills.previous_carryover_cny is
  'CNY carryover copied from the previous locked student monthly settlement, or 0 when there is no previous locked settlement.';

comment on column public.school_student_tuition_bills.bill_amount_jpy is
  'JPY tuition amount generated from formal planned lessons. This is the School income original amount.';

comment on column public.school_student_tuition_bills.source_snapshot is
  'Immutable bill calculation evidence: planned lesson ids/counts, planned JPY amount, and previous settlement carryover reference.';

commit;
