-- school_student_settlement_adjustments_schema.sql
-- Purpose: Add audit records for student monthly settlement difference adjustments.
-- Status: EXECUTED ON SUPABASE. Read-verified after execution.
--
-- Scope:
-- - Add append-only adjustment audit table for school_student_monthly_settlements.
-- - No business data repair, backfill, cleanup, or destructive operation.

create table if not exists public.school_student_settlement_adjustments (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.school_student_monthly_settlements(id),
  student_id uuid not null references public.school_students(id),
  year_month text not null,
  business_entity_id uuid references public.school_business_entities(id),
  adjustment_amount_cny numeric not null,
  adjustment_source text not null default 'manual',
  adjustment_reason text not null,
  note text,
  status text not null default 'posted',
  app_type text not null default 'school',
  created_by text not null default current_user,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint school_student_settlement_adjustments_month_format_chk
    check (year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_student_settlement_adjustments_status_chk
    check (status in ('posted')),
  constraint school_student_settlement_adjustments_app_type_chk
    check (app_type = 'school')
);

create index if not exists school_student_settlement_adjustments_settlement_idx
  on public.school_student_settlement_adjustments(settlement_id, created_at);

create index if not exists school_student_settlement_adjustments_student_month_idx
  on public.school_student_settlement_adjustments(student_id, year_month);

comment on table public.school_student_settlement_adjustments is
  'Append-only audit records for manual CNY difference adjustments on locked student monthly settlement snapshots.';

comment on column public.school_student_settlement_adjustments.adjustment_amount_cny is
  'Signed CNY adjustment amount. Positive increases carryover; negative decreases carryover; zero is allowed for explicit audit notes.';

comment on column public.school_student_settlement_adjustments.adjustment_source is
  'Operator-entered source/category for the adjustment, for example actual_receipt_difference or manual.';
