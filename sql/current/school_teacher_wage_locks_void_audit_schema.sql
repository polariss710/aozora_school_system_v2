-- school_teacher_wage_locks_void_audit_schema.sql
-- Purpose:
--   Add minimal audit fields for guarded teacher wage snapshot voiding.
--
-- Scope:
--   - Schema-only.
--   - No data backfill.
--   - Does not change wage amount, payment, expense, account, income,
--     settlement, or lesson calculation rules.

alter table public.school_teacher_wage_locks
  add column if not exists void_reason text,
  add column if not exists voided_by text,
  add column if not exists void_source text;

comment on column public.school_teacher_wage_locks.void_reason is
  'Reason recorded when a teacher wage snapshot is voided through a guarded workflow.';

comment on column public.school_teacher_wage_locks.voided_by is
  'Operator or request identity recorded when a teacher wage snapshot is voided.';

comment on column public.school_teacher_wage_locks.void_source is
  'Source surface or workflow that voided the teacher wage snapshot.';
