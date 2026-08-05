-- Session B: expected NULL becomes stale after waiting for Session A's student row lock.
\set ON_ERROR_STOP off
\pset pager off
\set VERBOSITY verbose

begin;
set local lock_timeout='30s';
set local statement_timeout='45s';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);

select 'SESSION_B_BEGIN' marker,pg_backend_pid() pid,clock_timestamp() observed_at;
select * from public.school_record_student_status_event_v1(
  'a0520000-0000-4000-8000-000000000100','2026-07-01','paused',
  'codex-test synthetic monthly status concurrency session B',null,
  'RECORD_STUDENT_STATUS_EVENT_V1'
);
\set b_writer_sqlstate :SQLSTATE
\echo SESSION_B_WRITER_SQLSTATE :SQLSTATE
\echo SESSION_B_WRITER_ERROR :LAST_ERROR_MESSAGE
rollback;

select :'b_writer_sqlstate' captured_writer_sqlstate,
       1/case when :'b_writer_sqlstate'='40001' then 1 else 0 end expected_mismatch_assertion;
select 'SESSION_B_REJECT_OBSERVED_AFTER_ROLLBACK' marker,pg_backend_pid() pid,clock_timestamp() observed_at;
