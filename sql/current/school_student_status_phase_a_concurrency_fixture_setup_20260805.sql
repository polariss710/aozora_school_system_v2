-- Commit exactly one authorized synthetic student for the real-overlap test.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='30s';

do $preflight$
begin
  if exists (select 1 from public.school_students where id='a0520000-0000-4000-8000-000000000100')
     or exists (select 1 from public.school_students where student_code='CODEX-STATUS-CONCURRENCY-20260805')
     or exists (select 1 from public.school_students where name='__TEST_STUDENT_MONTHLY_STATUS_CONCURRENCY__')
     or exists (select 1 from public.school_student_status_events where student_id='a0520000-0000-4000-8000-000000000100')
     or not exists (
       select 1 from public.school_app_memberships
       where user_id='25331ae9-3412-48b9-bdc3-e516caeaeba4' and role='admin' and is_active
     ) then
    raise exception 'STATUS_CONCURRENCY_FIXTURE_PREFLIGHT_FAILED';
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

commit;

select id,student_code,name,status,note,app_type
from public.school_students
where id='a0520000-0000-4000-8000-000000000100';
select count(*) synthetic_event_count
from public.school_student_status_events
where student_id='a0520000-0000-4000-8000-000000000100';
select 'STUDENT_STATUS_CONCURRENCY_FIXTURE_COMMIT_PASS' result;
