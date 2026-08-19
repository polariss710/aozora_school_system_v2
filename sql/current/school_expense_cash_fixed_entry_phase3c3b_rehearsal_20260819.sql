-- Phase 3C3-B School complete production ROLLBACK rehearsal.
\set ON_ERROR_STOP on
\pset pager off
begin;
create temp table phase3c3b_school_attempt_before as select id,to_jsonb(a) row_json from public.school_expense_cash_attempts a;
create temp table phase3c3b_school_expense_before as select id,to_jsonb(e) row_json from public.school_expense_records e;
-- First prove all existing immediate-account behavior against the new route-aware schema.
create temp table phase3c2r_attempt_before as
select id,to_jsonb(a)-array['payment_amount','payment_currency','request_payload_fingerprint','callback_recovered_from_prepared','callback_recovered_at','callback_recovery_source'] row_json
from public.school_expense_cash_attempts a;
create temp table phase3c2r_expense_before as select id,to_jsonb(e) row_json from public.school_expense_records e;
\ir school_expense_cash_fixed_entry_phase3c3b_20260819.sql
\ir school_expense_cash_attempt_v2_rollback_tests_20260819.sql
\ir school_expense_cash_fixed_entry_phase3c3b_rollback_tests_20260819.sql
rollback;
