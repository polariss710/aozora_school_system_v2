-- school_lesson_records_void_fields_schema.sql
-- Purpose: Add planned lesson soft-void audit fields.
-- Status: EXECUTED ON SUPABASE.
-- Version: v2.63.0-lesson-planned-void-schema-rpc-20260609
--
-- Scope:
-- - Add nullable voided_at and void_reason to public.school_lesson_records.
-- - No status rewrite, no cancelled-status reuse, no voided_by, no backfill.
-- - Existing import_batch_id/import_source/imported_at values are preserved.

alter table public.school_lesson_records
  add column if not exists voided_at timestamptz,
  add column if not exists void_reason text;

comment on column public.school_lesson_records.voided_at is
  'Timestamp when a planned-only lesson was soft-voided. Null means not voided.';

comment on column public.school_lesson_records.void_reason is
  'Required reason recorded by the guarded planned lesson void RPC.';
