\set ON_ERROR_STOP on
\pset pager off

begin;
set local statement_timeout = '30s';
select set_config('request.jwt.claims','{"sub":"b5010000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_backend_pid() session_b_pid;
select * from public.school_transition_student_status_v1(
  'b5010000-0000-4000-8000-000000000100','paused','2026-08-01',
  'codex-test b5 concurrency session B',null,'TRANSITION_STUDENT_STATUS_V1'
);
commit;
