-- Session A: the one authorized production event. Run concurrently with session B.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);

do $preflight$
begin
  if (select count(*) from public.school_students where app_type='school' and status='paused')<>1
     or not exists (select 1 from public.school_students where id='cff85c52-6acc-4b0f-8c92-3db280a5dd77' and app_type='school' and status='paused')
     or exists (select 1 from public.school_student_status_events where student_id='cff85c52-6acc-4b0f-8c92-3db280a5dd77' and voided_at is null) then
    raise exception 'STATUS_PRODUCTION_EVENT_PREFLIGHT_FAILED';
  end if;
end;
$preflight$;

select * from public.school_record_student_status_event_v1(
  'cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-07-01','paused',
  '2026年6月为最后在读月份，从2026年7月起暂停上课。',null,
  'RECORD_STUDENT_STATUS_EVENT_V1'
);
select pg_sleep(5);
commit;

select 'STUDENT_STATUS_PRODUCTION_EVENT_SESSION_A_COMMIT' result;
