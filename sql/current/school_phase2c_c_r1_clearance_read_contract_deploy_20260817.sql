-- Atomic production deployment wrapper for Phase 2C-C-R1 read-only contracts.
\set ON_ERROR_STOP on
begin;
select pg_advisory_xact_lock(hashtextextended('school_phase2c_c_r1_clearance_read_contract_20260817',0));
\set PHASE2C_C_R1_REHEARSAL 1
\ir school_phase2c_c_r1_clearance_read_contract_migration_20260817.sql
\unset PHASE2C_C_R1_REHEARSAL
do $gate$
begin
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_C_R1_PRODUCTION_CLEARANCE_NOT_EMPTY';
  end if;
end
$gate$;
commit;
