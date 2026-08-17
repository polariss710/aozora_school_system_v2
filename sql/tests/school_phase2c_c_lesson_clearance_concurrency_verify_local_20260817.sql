-- Phase 2C-C concurrency verification.
\set ON_ERROR_STOP on
do $verify$
begin
  if (select count(*) from public.school_lesson_clearances
      where idempotency_key in ('concurrency-a-pending','concurrency-a-overtime'))<>2
     or exists(select 1 from public.school_lesson_clearances
      where idempotency_key in ('concurrency-b-pending','concurrency-b-overtime')) then
    raise exception 'LESSON_CLEARANCE_CONCURRENCY_WINNER_COUNT_INVALID';
  end if;
  if public.school_get_lesson_clearance_pending_remaining_minutes(
       '30000000-0000-4000-8000-000000000001')<>0
     or public.school_get_lesson_clearance_overtime_remaining_minutes(
       '40000000-0000-4000-8000-000000000101')<>0 then
    raise exception 'LESSON_CLEARANCE_PENDING_CONCURRENCY_BALANCE_INVALID';
  end if;
  if public.school_get_lesson_clearance_overtime_remaining_minutes(
       '40000000-0000-4000-8000-000000000102')<>0
     or public.school_get_lesson_clearance_pending_remaining_minutes(
       '30000000-0000-4000-8000-000000000008')<>90 then
    raise exception 'LESSON_CLEARANCE_OVERTIME_CONCURRENCY_BALANCE_INVALID';
  end if;
end
$verify$;
select '14/15 concurrent pending and overtime double-spend: exactly one succeeds' result;
