-- Phase A real-overlap fixture cleanup rehearsal. Rollback only.
-- session_replication_role is transaction-local replica only around one exact event DELETE.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='30s';

do $preflight$
begin
  if exists (select 1 from public.school_students where id='a0520000-0000-4000-8000-000000000100')
     or exists (select 1 from public.school_student_status_events where id='a0520000-0000-4000-8000-000000000200')
     or not exists (
       select 1 from public.school_app_memberships
       where user_id='25331ae9-3412-48b9-bdc3-e516caeaeba4' and role='admin' and is_active
     ) then
    raise exception 'STATUS_CONCURRENCY_REHEARSAL_PREFLIGHT_FAILED';
  end if;
end;
$preflight$;

insert into public.school_students (
  id,student_code,name,display_name,status,business_entity_id,default_currency,
  preset_exchange_rate,note,app_type,created_at,updated_at
) values (
  'a0520000-0000-4000-8000-000000000100',
  'CODEX-STATUS-CONCURRENCY-20260805',
  '__TEST_STUDENT_MONTHLY_STATUS_CONCURRENCY__',
  '__TEST_STUDENT_MONTHLY_STATUS_CONCURRENCY__',
  'active',public.school_primary_business_entity_id(),'CNY',0,
  'codex-test synthetic monthly status concurrency fixture','school',clock_timestamp(),clock_timestamp()
);

insert into public.school_student_status_events (
  id,student_id,effective_month,status,reason,created_by_user_id,created_by_membership_id
) values (
  'a0520000-0000-4000-8000-000000000200',
  'a0520000-0000-4000-8000-000000000100','2026-07-01','paused',
  'codex-test synthetic monthly status concurrency cleanup rehearsal',
  '25331ae9-3412-48b9-bdc3-e516caeaeba4','25331ae9-3412-48b9-bdc3-e516caeaeba4'
);

lock table public.school_student_status_events in access exclusive mode;

do $guard_before$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_student_status_events'::regclass
      and tgname='school_student_status_events_delete_guard' and tgenabled='O'
  ) then
    raise exception 'STATUS_CONCURRENCY_DELETE_GUARD_NOT_ENABLED_BEFORE_REHEARSAL';
  end if;
end;
$guard_before$;

set local session_replication_role='replica';

with deleted as (
  delete from public.school_student_status_events
  where id='a0520000-0000-4000-8000-000000000200'
    and student_id='a0520000-0000-4000-8000-000000000100'
    and effective_month='2026-07-01'
    and status='paused'
    and reason='codex-test synthetic monthly status concurrency cleanup rehearsal'
    and created_by_user_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'
    and created_by_membership_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'
  returning id
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

do $inside_zero$
begin
  if exists (select 1 from public.school_student_status_events where id='a0520000-0000-4000-8000-000000000200')
     or exists (select 1 from public.school_students where id='a0520000-0000-4000-8000-000000000100')
     or current_setting('session_replication_role')<>'origin'
     or not exists (
       select 1 from pg_trigger
       where tgrelid='public.school_student_status_events'::regclass
         and tgname='school_student_status_events_delete_guard' and tgenabled='O'
     ) then
    raise exception 'STATUS_CONCURRENCY_REHEARSAL_INSIDE_ZERO_FAILED';
  end if;
end;
$inside_zero$;

rollback;

do $after_zero$
begin
  if exists (select 1 from public.school_student_status_events where id='a0520000-0000-4000-8000-000000000200')
     or exists (select 1 from public.school_students where id='a0520000-0000-4000-8000-000000000100')
     or current_setting('session_replication_role')<>'origin'
     or not exists (
       select 1 from pg_trigger
       where tgrelid='public.school_student_status_events'::regclass
         and tgname='school_student_status_events_delete_guard' and tgenabled='O'
     ) then
    raise exception 'STATUS_CONCURRENCY_REHEARSAL_ROLLBACK_RESIDUE';
  end if;
end;
$after_zero$;

select 'STUDENT_STATUS_CONCURRENCY_CLEANUP_REHEARSAL_ROLLBACK_PASS' result;
