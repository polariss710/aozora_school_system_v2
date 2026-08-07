\set ON_ERROR_STOP on
\pset pager off

do $verify$
begin
  if (select count(*) from public.school_student_status_events
      where student_id = 'b5010000-0000-4000-8000-000000000100') <> 1
     or (select count(*) from public.school_student_status_events
         where student_id = 'b5010000-0000-4000-8000-000000000100'
           and effective_month = '2026-09-01' and status = 'paused'
           and reason = 'codex-test b5 concurrency session A'
           and voided_at is null) <> 1
     or exists (select 1 from public.school_student_status_events
         where student_id = 'b5010000-0000-4000-8000-000000000100'
           and reason = 'codex-test b5 concurrency session B') then
    raise exception 'B5_CONCURRENCY_RESULT_INVALID';
  end if;
end;
$verify$;

select 'STUDENT_STATUS_PHASE_B5_CONCURRENCY_ONE_WINNER_PASS' result;
