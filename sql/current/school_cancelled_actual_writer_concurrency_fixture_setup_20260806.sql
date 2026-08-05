-- Commit one exact synthetic fixture for the two-session concurrency test.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='45s';

do $preflight$
begin
  if exists(select 1 from public.school_lesson_records where id::text like 'c6090000-%')
     or exists(select 1 from public.school_students where id::text like 'c6090000-%')
     or not exists(
       select 1 from public.school_app_memberships
       where user_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'
         and role='admin' and is_active
     ) then
    raise exception 'CANCELLATION_CONCURRENCY_FIXTURE_PREFLIGHT_FAILED';
  end if;
end;
$preflight$;

insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values('c6090000-0000-4000-8000-00000000d001','codex-test cancellation concurrency subject','codex-test',true,'codex-test cancellation concurrency 20260806','班课');
insert into public.school_teachers(
  id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values(
  'c6090000-0000-4000-8000-000000007001','codex-cancel-concurrency','codex-test cancellation concurrency teacher',
  'codex-test cancellation concurrency teacher','c6090000-0000-4000-8000-00000000d001',
  public.school_primary_business_entity_id(),'active','codex-test cancellation concurrency 20260806','school'
);
insert into public.school_students(
  id,student_code,name,display_name,business_entity_id,status,app_type,
  preset_exchange_rate,previous_balance_cny,note
) values(
  'c6090000-0000-4000-8000-00000000a001','codex-cancel-concurrency',
  'codex-test cancellation concurrency student','codex-test cancellation concurrency student',
  public.school_primary_business_entity_id(),'active','school',0.05,0,
  'codex-test cancellation concurrency 20260806'
);
insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
  is_billable,app_type,unit_price,lesson_fee,lesson_count,
  lesson_delivery_mode,lesson_venue,note
) values(
  'c6090000-0000-4000-8000-000000001101','planned','2020-06-01','2020-06',
  'c6090000-0000-4000-8000-00000000a001','c6090000-0000-4000-8000-000000007001',
  'c6090000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),
  '15:00','17:00',2,'codex-test cancellation concurrency source','planned',true,
  'school',1000,2000,1,'online','Zoom','codex-test cancellation concurrency 20260806'
);

commit;
select 'CANCELLATION_CONCURRENCY_FIXTURE_COMMIT_PASS' result;
