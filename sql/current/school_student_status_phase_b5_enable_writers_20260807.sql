\set ON_ERROR_STOP on
\pset pager off

begin;

revoke all on function public.school_transition_student_status_v1(uuid,text,date,text,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_correct_student_status_event_v1(uuid,uuid,uuid,date,text,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_transition_student_status_v1(uuid,text,date,text,uuid,text)
  to authenticated;
grant execute on function public.school_correct_student_status_event_v1(uuid,uuid,uuid,date,text,text,text,text)
  to authenticated;

commit;

select 'STUDENT_STATUS_PHASE_B5_INTERACTIVE_WRITERS_ENABLED' result;
