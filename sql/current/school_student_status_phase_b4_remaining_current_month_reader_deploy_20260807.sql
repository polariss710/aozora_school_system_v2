\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_status_phase_b4_remaining_current_month_reader_core_20260807.sql
commit;

select 'STUDENT_STATUS_PHASE_B4_REMAINING_CURRENT_MONTH_READER_DEPLOY_PASS' result;
