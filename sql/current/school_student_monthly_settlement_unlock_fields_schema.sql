-- school_student_monthly_settlement_unlock_fields_schema.sql
-- Purpose: Add soft unlock audit fields for student monthly settlement snapshots.
-- Status: EXECUTED ON SUPABASE. Schema-only.
-- Version: v2.75.0-student-settlement-unlock-relock-rpc-20260609
--
-- Scope:
-- - Add nullable unlock audit fields to public.school_student_monthly_settlements.
-- - Keep unique(student_id, year_month) unchanged for same-row relock V1.
-- - No data backfill, no status rewrite, no carryover mutation.

alter table public.school_student_monthly_settlements
  add column if not exists unlocked_at timestamptz null,
  add column if not exists unlock_reason text null;

comment on column public.school_student_monthly_settlements.unlocked_at is
  'Timestamp when a locked student monthly settlement snapshot was soft-unlocked. Same-row relock V1 preserves this audit value.';

comment on column public.school_student_monthly_settlements.unlock_reason is
  'Required reason recorded by guarded unlock RPC when a student monthly settlement snapshot is soft-unlocked.';
