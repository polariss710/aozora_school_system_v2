-- school_teacher_wage_detail_adjustments_schema.sql
-- Purpose: Create append-only audit records for manual teacher wage detail adjustments.
-- Status: DRAFT. Execute through the full autopilot SQL workflow.
-- Version: v2.86.0-teacher-wage-detail-adjustment-schema-20260611
--
-- Scope:
-- - Create public.school_teacher_wage_detail_adjustments.
-- - Store before/after detail values and before/after wage-lock aggregate totals.
-- - Preserve historical wage locks/details unless a verified RPC inserts an audit row
--   and updates the targeted detail/lock together.
--
-- Not included:
-- - RPC/function creation.
-- - Backfill, cleanup, delete, or repair of existing wage data.
-- - Payment, expense, account, account transaction, income, student settlement,
--   lesson, or wage rule writes.

create table if not exists public.school_teacher_wage_detail_adjustments (
  id uuid primary key default gen_random_uuid(),
  wage_lock_id uuid not null references public.school_teacher_wage_locks(id),
  wage_detail_id uuid not null references public.school_teacher_wage_lock_details(id),
  reason text not null,
  old_pay_hours numeric not null,
  new_pay_hours numeric not null,
  old_lesson_wage_jpy numeric not null,
  new_lesson_wage_jpy numeric not null,
  old_lesson_wage_cny numeric not null,
  new_lesson_wage_cny numeric not null,
  old_transport_fee_jpy numeric not null,
  new_transport_fee_jpy numeric not null,
  old_classroom_fee_jpy numeric not null,
  new_classroom_fee_jpy numeric not null,
  old_total_jpy numeric not null,
  new_total_jpy numeric not null,
  old_total_cny numeric not null,
  new_total_cny numeric not null,
  old_lock_pay_hours numeric not null,
  new_lock_pay_hours numeric not null,
  old_lock_lesson_wage_jpy numeric not null,
  new_lock_lesson_wage_jpy numeric not null,
  old_lock_lesson_wage_cny numeric not null,
  new_lock_lesson_wage_cny numeric not null,
  old_lock_fee_jpy numeric not null,
  new_lock_fee_jpy numeric not null,
  old_lock_total_jpy numeric not null,
  new_lock_total_jpy numeric not null,
  old_lock_total_cny numeric not null,
  new_lock_total_cny numeric not null,
  created_at timestamptz not null default now(),
  constraint school_teacher_wage_detail_adjustments_reason_nonempty
    check (length(trim(reason)) > 0),
  constraint school_teacher_wage_detail_adjustments_values_nonnegative
    check (
      old_pay_hours >= 0
      and new_pay_hours >= 0
      and old_transport_fee_jpy >= 0
      and new_transport_fee_jpy >= 0
      and old_classroom_fee_jpy >= 0
      and new_classroom_fee_jpy >= 0
      and old_total_jpy >= 0
      and new_total_jpy >= 0
      and old_lock_total_jpy >= 0
      and new_lock_total_jpy >= 0
    )
);

create index if not exists idx_school_teacher_wage_detail_adjustments_lock
  on public.school_teacher_wage_detail_adjustments (wage_lock_id, created_at desc);

create index if not exists idx_school_teacher_wage_detail_adjustments_detail
  on public.school_teacher_wage_detail_adjustments (wage_detail_id, created_at desc);

comment on table public.school_teacher_wage_detail_adjustments
  is 'Append-only audit records for manual teacher wage detail adjustments. Each row records before/after detail values and before/after wage-lock aggregate totals.';

comment on column public.school_teacher_wage_detail_adjustments.wage_lock_id
  is 'Teacher wage snapshot header affected by the adjustment.';

comment on column public.school_teacher_wage_detail_adjustments.wage_detail_id
  is 'Teacher wage snapshot detail row affected by the adjustment.';

comment on column public.school_teacher_wage_detail_adjustments.reason
  is 'Required operator reason or audit note for the manual adjustment.';

comment on column public.school_teacher_wage_detail_adjustments.created_at
  is 'Timestamp when the manual adjustment audit row was created.';
