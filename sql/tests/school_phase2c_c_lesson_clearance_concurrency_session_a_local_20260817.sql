-- Phase 2C-C concurrency session A.
\set ON_ERROR_STOP on
begin;
select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000101',120,'2026-02-15',
  'manual_business_choice','concurrency pending winner',
  'codex-test Phase2C-C concurrency A pending',null,'concurrency-a-pending',
  '90000000-0000-4000-8000-000000000001','owner'
);
select pg_sleep(1.5);
commit;

select pg_sleep(1);
begin;
select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000002',
  '40000000-0000-4000-8000-000000000102',60,'2026-02-15',
  'manual_business_choice','concurrency overtime winner',
  'codex-test Phase2C-C concurrency A overtime',null,'concurrency-a-overtime',
  '90000000-0000-4000-8000-000000000001','owner'
);
select pg_sleep(1.5);
commit;
