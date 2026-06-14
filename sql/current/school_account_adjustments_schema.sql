-- school_account_adjustments_schema.sql
-- Purpose: Create public.school_account_adjustments for manual account balance adjustments.
-- Status: EXECUTED ON SUPABASE. Verified.
-- Verified: v2.28.4-account-adjustment-schema-execution-20260606
-- Version: v2.28.2-account-adjustment-schema-sql-draft-20260606
-- Verification:
-- - Table exists with expected columns, nullable flags, and defaults.
-- - FK, check, unique constraints, indexes, and comments verified.
-- - gen_random_uuid() is available.
-- - No account adjustment RPC/function was created.
-- - Existing account, account transaction, and business entity row counts were unchanged.
--
-- Scope:
-- - Create a dedicated account adjustment event table.
-- - Add FK references to business entities, accounts, and account transactions.
-- - Add check constraints, indexes, and comments.
-- - Reserve reversal metadata fields for a future reversal RPC.
-- - Does not create RPC/function definitions.
-- - Does not update historical data.
--
-- Review before execution:
-- - Confirm gen_random_uuid() is available in the Supabase project.
-- - Confirm school_account_transactions.id is uuid primary key or unique.
-- - Confirm status values posted / reversed are acceptable.
-- - Confirm transaction_type value account_adjustment for the create RPC.
-- - Confirm whether negative balance_after is intentionally allowed.

create table if not exists public.school_account_adjustments (
  id uuid primary key default gen_random_uuid(),
  business_entity_id uuid not null
    references public.school_business_entities(id),
  account_id uuid not null
    references public.school_accounts(id),
  adjustment_date date not null,
  year_month text not null,
  currency text not null,
  amount numeric not null,
  balance_before numeric not null,
  balance_after numeric not null,
  reason text not null,
  note text,
  status text not null default 'posted',
  account_transaction_id uuid
    references public.school_account_transactions(id),
  reversed_at timestamptz,
  reversal_reason text,
  reversal_account_transaction_id uuid
    references public.school_account_transactions(id),
  app_type text not null default 'school',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint school_account_adjustments_amount_nonzero
    check (amount <> 0),
  constraint school_account_adjustments_year_month_format
    check (year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_account_adjustments_currency_supported
    check (currency in ('JPY', 'CNY')),
  constraint school_account_adjustments_status_valid
    check (status in ('posted', 'reversed')),
  constraint school_account_adjustments_app_type_school
    check (app_type = 'school'),
  constraint school_account_adjustments_reason_nonempty
    check (length(btrim(reason)) > 0),
  constraint school_account_adjustments_account_transaction_unique
    unique (account_transaction_id),
  constraint school_account_adjustments_reversal_transaction_unique
    unique (reversal_account_transaction_id)
);

create index if not exists idx_school_account_adjustments_account_date
  on public.school_account_adjustments (account_id, adjustment_date desc, created_at desc);

create index if not exists idx_school_account_adjustments_business_month
  on public.school_account_adjustments (business_entity_id, year_month);

create index if not exists idx_school_account_adjustments_status
  on public.school_account_adjustments (status);

comment on table public.school_account_adjustments
  is 'Manual school account balance adjustment events. These records correct account balances and do not represent income, expense, reimbursement, or payment business facts.';

comment on column public.school_account_adjustments.id
  is 'Primary key for the account adjustment event.';

comment on column public.school_account_adjustments.business_entity_id
  is 'Business entity that owns the adjusted account.';

comment on column public.school_account_adjustments.account_id
  is 'Adjusted school account.';

comment on column public.school_account_adjustments.adjustment_date
  is 'Business date of the manual account balance adjustment.';

comment on column public.school_account_adjustments.year_month
  is 'Year-month derived from adjustment_date in YYYY-MM format.';

comment on column public.school_account_adjustments.currency
  is 'Currency of the adjusted account and adjustment amount.';

comment on column public.school_account_adjustments.amount
  is 'Signed adjustment amount. Positive values increase balance; negative values decrease balance.';

comment on column public.school_account_adjustments.balance_before
  is 'Account current_balance snapshot before applying the adjustment.';

comment on column public.school_account_adjustments.balance_after
  is 'Account current_balance snapshot after applying the adjustment. Negative balances are allowed by schema.';

comment on column public.school_account_adjustments.reason
  is 'Required reason for the manual account adjustment.';

comment on column public.school_account_adjustments.note
  is 'Optional operator note for the manual account adjustment.';

comment on column public.school_account_adjustments.status
  is 'Adjustment status. Expected values: posted for active adjustments, reversed for future reversed adjustments.';

comment on column public.school_account_adjustments.account_transaction_id
  is 'Account transaction created for this adjustment. Expected transaction_type: account_adjustment.';

comment on column public.school_account_adjustments.reversed_at
  is 'Timestamp when the account adjustment is logically reversed. Null for posted adjustments.';

comment on column public.school_account_adjustments.reversal_reason
  is 'Optional reason for reversing the account adjustment.';

comment on column public.school_account_adjustments.reversal_account_transaction_id
  is 'Account transaction created by a future reversal RPC. Expected transaction_type: account_adjustment_reversal.';

comment on column public.school_account_adjustments.app_type
  is 'Application namespace. This table is restricted to school records.';

comment on column public.school_account_adjustments.created_at
  is 'Timestamp when the adjustment record was created.';

comment on column public.school_account_adjustments.updated_at
  is 'Timestamp when the adjustment record was last updated.';
