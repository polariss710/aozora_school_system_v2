-- School V2 student monthly status Phase B2 formal deployment wrapper.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_status_phase_b2_legacy_freeze_core_20260806.sql
commit;

select 'STUDENT_STATUS_PHASE_B2_LEGACY_FREEZE_DEPLOY_COMMIT' result;
