\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='15s';
set local statement_timeout='45s';
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',
  true
);
do $second_call$
declare v_denied boolean:=false;
begin
  begin
    perform * from public.school_create_cancelled_actual_lesson_from_planned(
      'c6090000-0000-4000-8000-000000001101','2020-06-01','15:00','17:15',
      2.25,1000,1,'codex-test concurrency session B','codex-test cancellation concurrency 20260806'
    );
  exception when others then
    if sqlerrm='LESSON_CANCELLATION_LINKED_ACTUAL_EXISTS' then
      v_denied:=true;
    else
      raise;
    end if;
  end;
  if not v_denied then raise exception 'CANCELLATION_CONCURRENCY_SECOND_CALL_ALLOWED'; end if;
end;
$second_call$;
commit;
select 'CANCELLATION_CONCURRENCY_SESSION_B_REJECT_PASS' result;
