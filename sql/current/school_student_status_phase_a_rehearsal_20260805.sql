-- Same-byte schema/RPC rehearsal plus full rollback-only test matrix.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_status_phase_a_schema_20260805.sql
\ir school_student_status_phase_a_guards_20260805.sql
\ir school_student_status_phase_a_rpcs_20260805.sql
\ir school_student_status_phase_a_test_matrix_20260805.sql
rollback;

do $residue$
begin
  if to_regclass('public.school_student_status_events') is not null
     or to_regprocedure('public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)') is not null
     or exists (select 1 from auth.users where id::text like 'a0510000-%')
     or exists (select 1 from public.school_students where id::text like 'a0510000-%') then
    raise exception 'STUDENT_STATUS_REHEARSAL_RESIDUE';
  end if;
end;
$residue$;

select 'STUDENT_STATUS_PHASE_A_REHEARSAL_ROLLBACK_PASS' result;
