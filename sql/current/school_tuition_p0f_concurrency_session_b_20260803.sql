\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='30s';
do $session_b$
declare v_start timestamptz:=clock_timestamp(); v_elapsed numeric;
begin
  perform * from public.school_create_lesson_credit_makeup_actual(
    'f0f10000-0000-4000-8000-000000001001','2026-08-03',
    'f0f10000-0000-4000-8000-000000007001',
    'f0f10000-0000-4000-8000-00000000d001',
    '10:00','11:00',1,'codex-test P0-F concurrency makeup',
    'codex-test P0-F concurrency makeup',1,'online','codex-test'
  );
  v_elapsed:=extract(epoch from clock_timestamp()-v_start);
  if v_elapsed<2 then
    raise exception 'P0F_EXPECTED_BLOCKING_MISSING: elapsed=%',v_elapsed;
  end if;
  raise notice 'P0F_SESSION_B_BLOCKED_THEN_COMPLETED elapsed=% pid=%',v_elapsed,pg_backend_pid();
end
$session_b$;
rollback;
\echo 'P0F_SESSION_B_ROLLED_BACK'
