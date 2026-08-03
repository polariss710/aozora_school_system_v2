-- Predeploy rollback test for the P0-F anon lesson-history reader ACL repair.
-- Contains no business DML and leaves the original ACL unchanged.
\set ON_ERROR_STOP on
\pset pager off

begin;

revoke all on function public.school_get_planned_lesson_tuition_history_state(uuid[])
  from public,anon,authenticated,service_role;
grant execute on function public.school_get_planned_lesson_tuition_history_state(uuid[])
  to anon,authenticated,service_role;

set local role anon;
select count(*) as anon_reader_row_count
from public.school_get_planned_lesson_tuition_history_state(
  array['d147d783-8c20-4d9e-bb94-03ea03c19a21'::uuid]
);
reset role;

do $assert$
begin
  if not has_function_privilege('anon',
       'public.school_get_planned_lesson_tuition_history_state(uuid[])','EXECUTE')
     or has_function_privilege('anon',
       'public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text)','EXECUTE')
     or has_function_privilege('anon',
       'public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)','EXECUTE')
     or has_table_privilege('anon',
       'public.school_student_settlement_source_treatment_drafts','INSERT,UPDATE,DELETE')
     or has_table_privilege('anon',
       'public.school_student_settlement_lesson_variance_claims','INSERT,UPDATE,DELETE') then
    raise exception 'P0F_ANON_ACL_ROLLBACK_ASSERTION_FAILED';
  end if;
end
$assert$;

rollback;

do $residue$
begin
  if has_function_privilege('anon',
       'public.school_get_planned_lesson_tuition_history_state(uuid[])','EXECUTE') then
    raise exception 'P0F_ANON_ACL_ROLLBACK_RESIDUE';
  end if;
end
$residue$;

select 'P0F_ANON_ACL_ROLLBACK_TEST_PASSED' result;
