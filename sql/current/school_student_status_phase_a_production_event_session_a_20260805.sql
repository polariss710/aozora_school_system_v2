-- Session A: synthetic real-overlap writer. Run with a PTY and hold at \prompt until observer proof exists.
\set ON_ERROR_STOP on
\pset pager off
\set VERBOSITY verbose

begin;
set local lock_timeout='15s';
set local statement_timeout='45s';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);

select 'SESSION_A_BEGIN' marker,pg_backend_pid() pid,clock_timestamp() observed_at;

select * from public.school_record_student_status_event_v1(
  'a0520000-0000-4000-8000-000000000100','2026-07-01','paused',
  'codex-test synthetic monthly status concurrency session A',null,
  'RECORD_STUDENT_STATUS_EVENT_V1'
);
select 'SESSION_A_WRITER_RETURNED_HOLDING_TRANSACTION' marker,pg_backend_pid() pid,clock_timestamp() observed_at;
\prompt 'SESSION_A_HOLD: wait for lock observer, then press return to COMMIT > ' release_after_observer
commit;

select 'SESSION_A_COMMITTED' marker,pg_backend_pid() pid,clock_timestamp() observed_at;
