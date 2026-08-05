-- Exact committed cleanup. session_replication_role is replica only around one exact event DELETE.
-- Supply the Session A event UUID via psql -v synthetic_event_id=...
\set ON_ERROR_STOP on
\pset pager off
\if :{?synthetic_event_id}
\else
  \echo 'synthetic_event_id is required'
  \quit 3
\endif

begin;
set local lock_timeout='15s';
set local statement_timeout='45s';

create temporary table cleanup_target(event_id uuid primary key) on commit drop;
insert into cleanup_target(event_id) values (:'synthetic_event_id'::uuid);

do $preflight$
begin
  if (select count(*) from public.school_student_status_events e join cleanup_target t on t.event_id=e.id
      where e.student_id='a0520000-0000-4000-8000-000000000100'
        and e.effective_month='2026-07-01' and e.status='paused'
        and e.reason='codex-test synthetic monthly status concurrency session A'
        and e.created_by_user_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'
        and e.created_by_membership_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'
        and e.voided_at is null)<>1
     or (select count(*) from public.school_student_status_events
         where student_id='a0520000-0000-4000-8000-000000000100')<>1
     or not exists (
       select 1 from public.school_students
       where id='a0520000-0000-4000-8000-000000000100'
         and student_code='CODEX-STATUS-CONCURRENCY-20260805'
         and name='__TEST_STUDENT_MONTHLY_STATUS_CONCURRENCY__'
         and display_name='__TEST_STUDENT_MONTHLY_STATUS_CONCURRENCY__'
         and status='active'
         and note='codex-test synthetic monthly status concurrency fixture'
         and app_type='school'
     ) then
    raise exception 'STATUS_CONCURRENCY_EXACT_CLEANUP_PREFLIGHT_FAILED';
  end if;
end;
$preflight$;

lock table public.school_student_status_events in access exclusive mode;

do $guard_before$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_student_status_events'::regclass
      and tgname='school_student_status_events_delete_guard' and tgenabled='O'
  ) then
    raise exception 'STATUS_CONCURRENCY_DELETE_GUARD_NOT_ENABLED_BEFORE_CLEANUP';
  end if;
end;
$guard_before$;

set local session_replication_role='replica';

with deleted as (
  delete from public.school_student_status_events e
  using cleanup_target t
  where e.id=t.event_id
    and e.student_id='a0520000-0000-4000-8000-000000000100'
    and e.effective_month='2026-07-01'
    and e.status='paused'
    and e.reason='codex-test synthetic monthly status concurrency session A'
    and e.created_by_user_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'
    and e.created_by_membership_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'
    and e.voided_at is null
  returning e.id
)
select 1/case when count(*)=1 then 1 else 0 end exact_event_delete_count from deleted;

set local session_replication_role='origin';

with deleted as (
  delete from public.school_students
  where id='a0520000-0000-4000-8000-000000000100'
    and student_code='CODEX-STATUS-CONCURRENCY-20260805'
    and name='__TEST_STUDENT_MONTHLY_STATUS_CONCURRENCY__'
    and display_name='__TEST_STUDENT_MONTHLY_STATUS_CONCURRENCY__'
    and status='active'
    and note='codex-test synthetic monthly status concurrency fixture'
    and app_type='school'
  returning id
)
select 1/case when count(*)=1 then 1 else 0 end exact_student_delete_count from deleted;

do $before_commit$
begin
  if exists (select 1 from public.school_student_status_events where student_id='a0520000-0000-4000-8000-000000000100')
     or exists (select 1 from public.school_students where id='a0520000-0000-4000-8000-000000000100')
     or current_setting('session_replication_role')<>'origin'
     or not exists (
       select 1 from pg_trigger
       where tgrelid='public.school_student_status_events'::regclass
         and tgname='school_student_status_events_delete_guard' and tgenabled='O'
     ) then
    raise exception 'STATUS_CONCURRENCY_EXACT_CLEANUP_BEFORE_COMMIT_FAILED';
  end if;
end;
$before_commit$;

commit;

select count(*) synthetic_student_count from public.school_students where id='a0520000-0000-4000-8000-000000000100';
select count(*) synthetic_event_count from public.school_student_status_events where student_id='a0520000-0000-4000-8000-000000000100';
select count(*) synthetic_membership_count from public.school_app_memberships where user_id='a0520000-0000-4000-8000-000000000100';
select count(*) synthetic_user_count from auth.users where id='a0520000-0000-4000-8000-000000000100';
select tgname,tgenabled from pg_trigger
where tgrelid='public.school_student_status_events'::regclass and not tgisinternal order by tgname;
select 'STUDENT_STATUS_CONCURRENCY_EXACT_CLEANUP_COMMIT_PASS' result;
