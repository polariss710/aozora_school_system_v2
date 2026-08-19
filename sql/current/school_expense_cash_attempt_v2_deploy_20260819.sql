-- Phase 3C2-R atomic School DB deployment. Gate remains blocked after COMMIT.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_expense_cash_attempt_v2_fingerprint_helper_20260819.sql
\ir school_expense_cash_attempt_v2_schema_backfill_20260819.sql
\ir school_expense_cash_attempt_v2_rpcs_20260819.sql
\ir school_expense_cash_request_backend_amount_rpc.sql
commit;
