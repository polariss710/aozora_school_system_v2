-- Phase 3C2-R complete production ROLLBACK rehearsal.
\set ON_ERROR_STOP on
\pset pager off

begin;
create temp table phase3c2r_attempt_before as
select id,to_jsonb(a) as row_json from public.school_expense_cash_attempts a;
create temp table phase3c2r_expense_before as
select id,to_jsonb(e) as row_json from public.school_expense_records e;
\ir school_expense_cash_attempt_v2_fingerprint_helper_20260819.sql
\ir school_expense_cash_attempt_v2_schema_backfill_20260819.sql
\ir school_expense_cash_attempt_v2_rpcs_20260819.sql
\ir school_expense_cash_request_backend_amount_rpc.sql
\ir school_expense_cash_attempt_v2_rollback_tests_20260819.sql
rollback;
