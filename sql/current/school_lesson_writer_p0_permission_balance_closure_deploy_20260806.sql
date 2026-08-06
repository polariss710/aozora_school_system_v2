-- Single-transaction production deployment wrapper.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
\ir school_lesson_writer_p0_permission_balance_closure_core_20260806.sql
commit;
