\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_status_phase_b5_core_20260807.sql
commit;

select 'STUDENT_STATUS_PHASE_B5_BACKEND_FAIL_CLOSED_DEPLOY_PASS' result;
