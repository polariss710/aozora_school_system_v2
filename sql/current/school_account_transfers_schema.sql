-- school_account_transfers_schema.sql
-- Purpose: Create public.school_account_transfers for account-to-account transfers.
-- Status: EXECUTED ON SUPABASE. Verified.
-- Verified: v2.33.5-account-transfer-schema-execution-20260606
-- Version: v2.33.3-account-transfer-schema-sql-draft-20260606
-- Verification:
-- - Table exists with expected columns, nullable flags, and defaults.
-- - FK, check, unique constraints, indexes, and comments verified.
-- - gen_random_uuid() is available.
-- - No account transfer RPC/function was created.
-- - Existing account, account transaction, and business entity row counts were unchanged.
--
-- Scope:
-- - Create a dedicated account transfer event table.
-- - Add FK references to business entities, from/to accounts, and account transactions.
-- - Add check constraints, indexes, and comments.
-- - Reserve reversal metadata fields for a future reversal RPC.
-- - Does not create RPC/function definitions.
-- - Does not update historical data.
--
-- Review before execution:
-- - Confirm gen_random_uuid() is available in the Supabase project.
-- - Confirm school_account_transactions.id is uuid primary key or unique.
-- - Confirm status values posted / reversed are acceptable.
-- - Confirm transaction_type values transfer_out / transfer_in.
-- - Confirm negative from_balance_after is intentionally allowed.

create table if not exists public.school_account_transfers (
  id uuid primary key default gen_random_uuid(),
  business_entity_id uuid not null
    references public.school_business_entities(id),
  from_account_id uuid not null
    references public.school_accounts(id),
  to_account_id uuid not null
    references public.school_accounts(id),
  transfer_date date not null,
  year_month text not null,
  currency text not null,
  amount numeric not null,
  from_balance_before numeric not null,
  from_balance_after numeric not null,
  to_balance_before numeric not null,
  to_balance_after numeric not null,
  reason text not null,
  note text,
  status text not null default 'posted',
  from_account_transaction_id uuid
    references public.school_account_transactions(id),
  to_account_transaction_id uuid
    references public.school_account_transactions(id),
  reversed_at timestamptz,
  reversal_reason text,
  reversal_from_account_transaction_id uuid
    references public.school_account_transactions(id),
  reversal_to_account_transaction_id uuid
    references public.school_account_transactions(id),
  app_type text not null default 'school',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint school_account_transfers_amount_positive
    check (amount > 0),
  constraint school_account_transfers_accounts_different
    check (from_account_id <> to_account_id),
  constraint school_account_transfers_year_month_format
    check (year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_account_transfers_currency_supported
    check (currency in ('JPY', 'CNY')),
  constraint school_account_transfers_status_valid
    check (status in ('posted', 'reversed')),
  constraint school_account_transfers_app_type_school
    check (app_type = 'school'),
  constraint school_account_transfers_reason_nonempty
    check (length(btrim(reason)) > 0),
  constraint school_account_transfers_tx_pair
    check (
      (from_account_transaction_id is null and to_account_transaction_id is null)
      or (from_account_transaction_id is not null and to_account_transaction_id is not null)
    ),
  constraint school_account_transfers_reversal_tx_pair
    check (
      (reversal_from_account_transaction_id is null and reversal_to_account_transaction_id is null)
      or (reversal_from_account_transaction_id is not null and reversal_to_account_transaction_id is not null)
    ),
  constraint school_account_transfers_from_tx_unique
    unique (from_account_transaction_id),
  constraint school_account_transfers_to_tx_unique
    unique (to_account_transaction_id),
  constraint school_account_transfers_reversal_from_tx_unique
    unique (reversal_from_account_transaction_id),
  constraint school_account_transfers_reversal_to_tx_unique
    unique (reversal_to_account_transaction_id)
);

create index if not exists idx_school_account_transfers_business_month
  on public.school_account_transfers (business_entity_id, year_month);

create index if not exists idx_school_account_transfers_from_account_date
  on public.school_account_transfers (from_account_id, transfer_date desc, created_at desc);

create index if not exists idx_school_account_transfers_to_account_date
  on public.school_account_transfers (to_account_id, transfer_date desc, created_at desc);

create index if not exists idx_school_account_transfers_status
  on public.school_account_transfers (status);

comment on table public.school_account_transfers
  is 'School account-to-account transfer events. These records move balance between two accounts and do not represent income, expense, reimbursement, payment, or manual adjustment facts.';

comment on column public.school_account_transfers.id
  is 'Primary key for the account transfer event.';

comment on column public.school_account_transfers.business_entity_id
  is 'Business entity that owns both transfer accounts.';

comment on column public.school_account_transfers.from_account_id
  is 'Source account for the transfer. Expected account transaction type: transfer_out.';

comment on column public.school_account_transfers.to_account_id
  is 'Destination account for the transfer. Expected account transaction type: transfer_in.';

comment on column public.school_account_transfers.transfer_date
  is 'Business date of the account transfer.';

comment on column public.school_account_transfers.year_month
  is 'Year-month derived from transfer_date in YYYY-MM format.';

comment on column public.school_account_transfers.currency
  is 'Currency shared by the source and destination accounts.';

comment on column public.school_account_transfers.amount
  is 'Positive transfer amount. The source account transaction records the negative amount and the destination account transaction records the positive amount.';

comment on column public.school_account_transfers.from_balance_before
  is 'Source account current_balance snapshot before applying the transfer.';

comment on column public.school_account_transfers.from_balance_after
  is 'Source account current_balance snapshot after applying the transfer. Negative balances are allowed by schema.';

comment on column public.school_account_transfers.to_balance_before
  is 'Destination account current_balance snapshot before applying the transfer.';

comment on column public.school_account_transfers.to_balance_after
  is 'Destination account current_balance snapshot after applying the transfer.';

comment on column public.school_account_transfers.reason
  is 'Required reason for the account transfer.';

comment on column public.school_account_transfers.note
  is 'Optional operator note for the account transfer.';

comment on column public.school_account_transfers.status
  is 'Transfer status. Expected values: posted for active transfers, reversed for future reversed transfers.';

comment on column public.school_account_transfers.from_account_transaction_id
  is 'Source account transaction created for this transfer. Expected transaction_type: transfer_out.';

comment on column public.school_account_transfers.to_account_transaction_id
  is 'Destination account transaction created for this transfer. Expected transaction_type: transfer_in.';

comment on column public.school_account_transfers.reversed_at
  is 'Timestamp when the account transfer is logically reversed. Null for posted transfers.';

comment on column public.school_account_transfers.reversal_reason
  is 'Optional reason for reversing the account transfer.';

comment on column public.school_account_transfers.reversal_from_account_transaction_id
  is 'Source-side account transaction created by a future reversal RPC.';

comment on column public.school_account_transfers.reversal_to_account_transaction_id
  is 'Destination-side account transaction created by a future reversal RPC.';

comment on column public.school_account_transfers.app_type
  is 'Application namespace. This table is restricted to school records.';

comment on column public.school_account_transfers.created_at
  is 'Timestamp when the transfer record was created.';

comment on column public.school_account_transfers.updated_at
  is 'Timestamp when the transfer record was last updated.';
