-- Phase 2C-C atomic production deployment wrapper.
\set ON_ERROR_STOP on
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('school_phase2c_c_20260817',0));
\set PHASE2C_C_REHEARSAL 1
\ir school_phase2c_c_lesson_clearance_schema_migration_20260817.sql
\ir school_phase2c_c_lesson_clearance_backend_migration_20260817.sql
do $deployment_gate$
begin
  if to_regclass('public.school_lesson_clearances') is null
     or to_regclass('public.school_lesson_clearance_details') is null
     or to_regprocedure('public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)') is null
     or to_regprocedure('public.school_reverse_lesson_clearance(uuid,date,text,text)') is null then
    raise exception 'PHASE2C_C_ATOMIC_DEPLOYMENT_OBJECT_MISSING';
  end if;
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_C_ATOMIC_DEPLOYMENT_BUSINESS_FACT_PRESENT';
  end if;
  if not exists(select 1 from public.school_student_package_credit_lots
    where id='2a000000-0000-4000-8000-202608170002'
      and initial_minutes=1200 and consumed_minutes=0 and remaining_minutes=1200
      and status='active') then
    raise exception 'PHASE2C_C_ATOMIC_DEPLOYMENT_P002_MISMATCH';
  end if;
end
$deployment_gate$;
commit;
