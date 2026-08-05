-- Session B: concurrent duplicate call; must reject after session A commits.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);

do $concurrent_duplicate$
declare v_denied boolean:=false;
begin
  begin
    perform * from public.school_record_student_status_event_v1(
      'cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-07-01','paused',
      '2026年6月为最后在读月份，从2026年7月起暂停上课。',null,
      'RECORD_STUDENT_STATUS_EVENT_V1'
    );
  exception
    when serialization_failure or unique_violation or check_violation then
      v_denied:=true;
  end;
  if not v_denied then
    raise exception 'STATUS_CONCURRENT_DUPLICATE_UNEXPECTEDLY_SUCCEEDED';
  end if;
end;
$concurrent_duplicate$;
commit;

select 'STUDENT_STATUS_PRODUCTION_EVENT_SESSION_B_REJECT_PASS' result;
