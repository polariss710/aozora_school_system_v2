-- School V2 ordinary-expense P0 permission closure formal deployment.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_p0_expense_permission_closure_core_20260804.sql
commit;
