-- Phase 2C-C concurrency session B.
\set ON_ERROR_STOP on
select pg_sleep(0.25);
do $pending_loser$
begin
  begin
    perform * from public.school_create_lesson_clearance_core(
      'overtime_offset','30000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000104',60,'2026-02-15',
      'manual_business_choice','concurrency pending loser',
      'codex-test Phase2C-C concurrency B pending',null,'concurrency-b-pending',
      '90000000-0000-4000-8000-000000000001','owner');
    raise exception 'EXPECTED_PENDING_CONCURRENCY_DENIAL_MISSING';
  exception when others then
    if sqlerrm='EXPECTED_PENDING_CONCURRENCY_DENIAL_MISSING'
       or position('LESSON_CLEARANCE_PENDING_BALANCE_INSUFFICIENT' in sqlerrm)=0 then
      raise;
    end if;
  end;
end
$pending_loser$;

select pg_sleep(1.25);
do $overtime_loser$
begin
  begin
    perform * from public.school_create_lesson_clearance_core(
      'overtime_offset','30000000-0000-4000-8000-000000000008',
      '40000000-0000-4000-8000-000000000102',60,'2026-02-15',
      'manual_business_choice','concurrency overtime loser',
      'codex-test Phase2C-C concurrency B overtime',null,'concurrency-b-overtime',
      '90000000-0000-4000-8000-000000000001','owner');
    raise exception 'EXPECTED_OVERTIME_CONCURRENCY_DENIAL_MISSING';
  exception when others then
    if sqlerrm='EXPECTED_OVERTIME_CONCURRENCY_DENIAL_MISSING'
       or position('LESSON_CLEARANCE_OVERTIME_BALANCE_INSUFFICIENT' in sqlerrm)=0 then
      raise;
    end if;
  end;
end
$overtime_loser$;
