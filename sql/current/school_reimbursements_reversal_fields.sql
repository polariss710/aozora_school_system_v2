-- school_reimbursements_reversal_fields.sql
-- Purpose: Add reversal metadata fields to public.school_reimbursements.
-- Status: EXECUTED ON SUPABASE. Verified.
-- Verified: v2.24.7-reimbursement-reversal-schema-verified-commit-20260604
-- Version: v2.24.4-reimbursement-reversal-schema-sql-draft-20260604
-- Verification:
--   - New reversal metadata columns are readable via Supabase REST.
--   - Existing paid reimbursement records keep reversal fields as null.
-- Scope:
--   - Add nullable reversal metadata fields.
--   - Add FK references from reversal transaction ids to school_account_transactions(id).
--   - Add column comments.
--   - Does not create reverse RPC.
--   - Does not update existing data.
--   - Does not add frontend changes.
-- Review before execution:
--   - Confirm school_account_transactions.id is uuid primary key or unique.
--   - Confirm no existing column name conflicts.
--   - Confirm FK names are unique.

alter table public.school_reimbursements
  add column if not exists reversed_at timestamptz,
  add column if not exists reversal_reason text,
  add column if not exists reversal_from_account_transaction_id uuid,
  add column if not exists reversal_to_account_transaction_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fk_school_reimbursements_reversal_from_transaction'
  ) then
    alter table public.school_reimbursements
      add constraint fk_school_reimbursements_reversal_from_transaction
      foreign key (reversal_from_account_transaction_id)
      references public.school_account_transactions(id);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'fk_school_reimbursements_reversal_to_transaction'
  ) then
    alter table public.school_reimbursements
      add constraint fk_school_reimbursements_reversal_to_transaction
      foreign key (reversal_to_account_transaction_id)
      references public.school_account_transactions(id);
  end if;
end $$;

comment on column public.school_reimbursements.reversed_at
  is 'Timestamp when the paid reimbursement was logically reversed. Null for active paid reimbursements.';

comment on column public.school_reimbursements.reversal_reason
  is 'Optional reason for reversing the reimbursement.';

comment on column public.school_reimbursements.reversal_from_account_transaction_id
  is 'Account transaction id for reversal inflow to the original from account. Expected transaction_type: reimbursement_reverse_in.';

comment on column public.school_reimbursements.reversal_to_account_transaction_id
  is 'Account transaction id for reversal outflow from the original to account. Expected transaction_type: reimbursement_reverse_out.';
