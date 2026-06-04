-- school_expense_records_reversal_fields.sql
-- Purpose: Add reversal metadata fields to public.school_expense_records.
-- Status: EXECUTED ON SUPABASE. Verified.
-- Verified: v2.25.6-expense-reversal-schema-supabase-execution-20260604
-- Verification:
--   - New reversal metadata columns are readable.
--   - Existing expense records keep reversal fields as null.
--   - FK constraint exists and references school_account_transactions(id).
-- Version: v2.25.3-expense-reversal-schema-sql-draft-20260604
--
-- Scope:
--   - Add nullable reversal metadata fields.
--   - Add FK reference from reversal_account_transaction_id to school_account_transactions(id).
--   - Add column comments.
--   - Does not create reverse expense RPC.
--   - Does not update existing data.
--   - Does not add frontend changes.
--
-- Review before execution:
--   - Confirm school_account_transactions.id is uuid primary key or unique.
--   - Confirm no existing column name conflicts.
--   - Confirm FK constraint name is unique.

alter table public.school_expense_records
  add column if not exists reversed_at timestamptz,
  add column if not exists reversal_reason text,
  add column if not exists reversal_account_transaction_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fk_school_expense_records_reversal_transaction'
  ) then
    alter table public.school_expense_records
      add constraint fk_school_expense_records_reversal_transaction
      foreign key (reversal_account_transaction_id)
      references public.school_account_transactions(id);
  end if;
end $$;

comment on column public.school_expense_records.reversed_at
  is 'Timestamp when the paid expense record was logically reversed. Null for active paid expenses.';

comment on column public.school_expense_records.reversal_reason
  is 'Optional reason for reversing the expense record.';

comment on column public.school_expense_records.reversal_account_transaction_id
  is 'Account transaction id for the positive reversal transaction that restores the original expense account balance. Expected transaction_type: expense_reversal.';
