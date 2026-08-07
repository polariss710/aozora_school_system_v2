\set ON_ERROR_STOP on
\pset pager off

begin;
lock table public.school_student_status_events in access exclusive mode;

do $preflight$
begin
  if (select count(*) from public.school_student_status_events
      where student_id = 'b5010000-0000-4000-8000-000000000100') <> 1
     or (select count(*) from public.school_student_status_events
         where student_id = 'b5010000-0000-4000-8000-000000000100'
           and effective_month = '2026-09-01' and status = 'paused'
           and reason = 'codex-test b5 concurrency session A'
           and voided_at is null) <> 1 then
    raise exception 'B5_CONCURRENCY_CLEANUP_EVENT_MISMATCH';
  end if;
  if exists (select 1 from public.school_lesson_records where student_id = 'b5010000-0000-4000-8000-000000000100')
     or exists (select 1 from public.school_student_monthly_settlements where student_id = 'b5010000-0000-4000-8000-000000000100')
     or exists (select 1 from public.school_income_records where student_id = 'b5010000-0000-4000-8000-000000000100')
     or exists (select 1 from public.school_expense_records where student_id = 'b5010000-0000-4000-8000-000000000100')
     or exists (select 1 from public.school_student_tuition_bills where student_id = 'b5010000-0000-4000-8000-000000000100')
     or exists (select 1 from public.school_teacher_wage_rules where student_id = 'b5010000-0000-4000-8000-000000000100') then
    raise exception 'B5_CONCURRENCY_FIXTURE_HAS_BUSINESS_REFERENCES';
  end if;
end;
$preflight$;

set local session_replication_role = replica;
delete from public.school_student_status_events
where student_id = 'b5010000-0000-4000-8000-000000000100'
  and effective_month = '2026-09-01'
  and status = 'paused'
  and reason = 'codex-test b5 concurrency session A'
  and voided_at is null;
set local session_replication_role = origin;

delete from public.school_students
where id = 'b5010000-0000-4000-8000-000000000100'
  and student_code = 'CODEX-B5-CONCURRENCY'
  and note = 'codex-test b5 concurrency exact cleanup';
delete from public.school_app_memberships
where user_id = 'b5010000-0000-4000-8000-000000000001'
  and note = 'codex-test b5 concurrency';
delete from auth.users
where id = 'b5010000-0000-4000-8000-000000000001'
  and email = 'b5-concurrency@codex.test';

commit;

do $residue$
begin
  if exists (select 1 from auth.users where id::text like 'b5010000-%')
     or exists (select 1 from public.school_app_memberships where user_id::text like 'b5010000-%')
     or exists (select 1 from public.school_students where id::text like 'b5010000-%')
     or exists (select 1 from public.school_student_status_events where student_id::text like 'b5010000-%') then
    raise exception 'B5_CONCURRENCY_CLEANUP_RESIDUE';
  end if;
end;
$residue$;

select 'STUDENT_STATUS_PHASE_B5_CONCURRENCY_CLEANUP_PASS' result;
