\set ON_ERROR_STOP on
\pset pager off

begin;
select set_config('request.jwt.claims','{"sub":"b5010000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_backend_pid() session_a_pid;
select * from public.school_transition_student_status_v1(
  'b5010000-0000-4000-8000-000000000100','paused','2026-08-01',
  'codex-test b5 concurrency session A',null,'TRANSITION_STUDENT_STATUS_V1'
);
select 'B5_SESSION_A_LOCK_HELD' marker,clock_timestamp() observed_at;
select pg_sleep(15);
commit;
select 'B5_SESSION_A_COMMITTED' result,clock_timestamp() observed_at;
