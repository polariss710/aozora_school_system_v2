-- Installed-object runtime rollback tests. All fixtures and event writes roll back.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_status_phase_a_test_matrix_20260805.sql
rollback;

do $residue$
begin
  if exists (select 1 from auth.users where id::text like 'a0510000-%')
     or exists (select 1 from public.school_students where id::text like 'a0510000-%')
     or exists (select 1 from public.school_student_status_events where student_id::text like 'a0510000-%') then
    raise exception 'STUDENT_STATUS_RUNTIME_TEST_RESIDUE';
  end if;
end;
$residue$;

select 'STUDENT_STATUS_PHASE_A_RUNTIME_ROLLBACK_PASS' result;
