-- Postdeploy negative/positive matrix; synthetic fixtures only, always rollback.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='600s';
\ir ../tests/school_locked_billing_month_nonbilling_makeup_rollback_test_body_20260816.sql
rollback;
select 'LOCKED_BILLING_MONTH_NONBILLING_MAKEUP_POSTDEPLOY_TESTS_ROLLED_BACK' result;
