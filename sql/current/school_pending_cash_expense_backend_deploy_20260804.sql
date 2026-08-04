-- School V2 manual Cash pending-expense backend deployment wrapper.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_pending_cash_expense_identity_schema_20260804.sql
\ir school_pending_cash_expense_identity_guard_20260804.sql
\ir school_create_expense_record_rpc.sql
\ir school_create_pending_cash_expense_record_v1_rpc.sql
\ir school_expense_cash_request_backend_amount_rpc.sql
commit;
