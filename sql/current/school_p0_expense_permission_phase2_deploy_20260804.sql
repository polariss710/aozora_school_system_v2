-- School V2 ordinary expense permission P0 phase 2 deployment order.
\set ON_ERROR_STOP on
\pset pager off

begin;

\ir school_update_expense_record_rpc.sql
\ir school_reverse_expense_record_rpc.sql
\ir school_create_reimbursement_record_rpc.sql
\ir school_reverse_reimbursement_record_rpc.sql
\ir school_create_expense_attachment_metadata_rpc.sql

\ir school_generate_teacher_monthly_wage_business_scope.sql
\ir school_adjust_teacher_wage_detail_rpc.sql
\ir school_create_teacher_wage_rule_config_rpc.sql
\ir school_update_teacher_wage_rule_config_rpc.sql
\ir school_set_teacher_wage_rule_active_state_rpc.sql
\ir school_confirm_payment_request_rpc.sql
\ir school_reverse_paid_payment_request_rpc.sql
\ir school_payment_status_actions_rpc.sql

\ir school_p0_expense_permission_phase2_closure_20260804.sql

commit;
