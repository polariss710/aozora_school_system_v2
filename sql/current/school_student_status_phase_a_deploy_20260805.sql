-- School V2 student monthly status Phase A formal deployment wrapper.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_status_phase_a_schema_20260805.sql
\ir school_student_status_phase_a_rpcs_20260805.sql
commit;

select 'STUDENT_STATUS_PHASE_A_DEPLOY_COMMIT' result;
