\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='45s';
do $session_a$
declare v_locked record;
begin
  select * into strict v_locked
  from public.school_lock_student_monthly_settlement(
    'f0f10000-0000-4000-8000-00000000a001','2036-07',
    'codex-test P0-F concurrency lock holder'
  );
  raise notice 'P0F_SESSION_A_LOCKED settlement=% pid=%',v_locked.settlement_id,pg_backend_pid();
  perform pg_sleep(12);
end
$session_a$;
rollback;
\echo 'P0F_SESSION_A_ROLLED_BACK'
