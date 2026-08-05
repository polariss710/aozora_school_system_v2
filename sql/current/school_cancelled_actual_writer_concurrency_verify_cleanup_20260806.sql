-- Verify one atomic result, then delete only the exact committed c609 fixture.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='15s';
set local statement_timeout='60s';

do $verify$
begin
  if (select count(*) from public.school_lesson_records
      where planned_lesson_id='c6090000-0000-4000-8000-000000001101')<>1
     or not exists(
       select 1 from public.school_lesson_records actual
       join public.school_lesson_records planned on planned.id=actual.planned_lesson_id
       where planned.id='c6090000-0000-4000-8000-000000001101'
         and planned.status='pending_makeup'
         and actual.lesson_type='actual' and actual.status='cancelled'
         and actual.start_time='15:00' and actual.end_time='17:15'
         and actual.duration_hours=2.25 and actual.actual_minutes=0
         and not actual.is_billable and actual.lesson_fee=0
         and actual.note='codex-test cancellation concurrency 20260806'
     ) then
    raise exception 'CANCELLATION_CONCURRENCY_ATOMIC_RESULT_INVALID';
  end if;
end;
$verify$;

with deleted as (
  delete from public.school_lesson_records
  where planned_lesson_id='c6090000-0000-4000-8000-000000001101'
    and lesson_type='actual' and status='cancelled'
    and note='codex-test cancellation concurrency 20260806'
  returning id
)
select 1/case when count(*)=1 then 1 else 0 end exact_actual_delete from deleted;

with deleted as (
  delete from public.school_lesson_records
  where id='c6090000-0000-4000-8000-000000001101'
    and lesson_type='planned' and status='pending_makeup'
    and note='codex-test cancellation concurrency 20260806'
  returning id
)
select 1/case when count(*)=1 then 1 else 0 end exact_planned_delete from deleted;

with deleted as (
  delete from public.school_students
  where id='c6090000-0000-4000-8000-00000000a001'
    and note='codex-test cancellation concurrency 20260806'
  returning id
)
select 1/case when count(*)=1 then 1 else 0 end exact_student_delete from deleted;
with deleted as (
  delete from public.school_teachers
  where id='c6090000-0000-4000-8000-000000007001'
    and note='codex-test cancellation concurrency 20260806'
  returning id
)
select 1/case when count(*)=1 then 1 else 0 end exact_teacher_delete from deleted;
with deleted as (
  delete from public.school_subjects
  where id='c6090000-0000-4000-8000-00000000d001'
    and note='codex-test cancellation concurrency 20260806'
  returning id
)
select 1/case when count(*)=1 then 1 else 0 end exact_subject_delete from deleted;

do $residue$
begin
  if exists(select 1 from public.school_lesson_records where id::text like 'c6090000-%' or planned_lesson_id::text like 'c6090000-%')
     or exists(select 1 from public.school_students where id::text like 'c6090000-%')
     or exists(select 1 from public.school_teachers where id::text like 'c6090000-%')
     or exists(select 1 from public.school_subjects where id::text like 'c6090000-%') then
    raise exception 'CANCELLATION_CONCURRENCY_CLEANUP_RESIDUE';
  end if;
end;
$residue$;

commit;
select 'CANCELLATION_CONCURRENCY_VERIFY_CLEANUP_COMMIT_PASS' result;
