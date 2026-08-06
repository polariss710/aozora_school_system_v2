\set ON_ERROR_STOP on
begin read only;

do $postdeploy$
declare
  v_writer text;
begin
  select pg_get_functiondef(
    'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure
  ) into v_writer;
  if position('school_expand_planned_lesson_batch_occurrences_v1' in v_writer)=0
     or position('school_resolve_student_status_at_month_core_v1' in v_writer)=0
     or position('school_resolve_planned_billing_attribution' in v_writer)=0 then
    raise exception 'B4_LESSON_BATCH_WRITER_SHARED_AUTHORITY_MISSING';
  end if;

  if has_function_privilege('anon','public.school_list_planned_lesson_student_candidates_v1(date,uuid,uuid)','EXECUTE')
     or has_function_privilege('service_role','public.school_list_planned_lesson_student_candidates_v1(date,uuid,uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.school_list_planned_lesson_student_candidates_v1(date,uuid,uuid)','EXECUTE')
     or has_function_privilege('anon','public.school_preflight_planned_lesson_batch_student_candidates_v1(date,date,jsonb,jsonb,uuid,uuid)','EXECUTE')
     or has_function_privilege('service_role','public.school_preflight_planned_lesson_batch_student_candidates_v1(date,date,jsonb,jsonb,uuid,uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.school_preflight_planned_lesson_batch_student_candidates_v1(date,date,jsonb,jsonb,uuid,uuid)','EXECUTE')
     or has_function_privilege('authenticated','public.school_expand_planned_lesson_batch_occurrences_v1(date,date,jsonb,jsonb)','EXECUTE') then
    raise exception 'B4_LESSON_READER_ACL_MISMATCH';
  end if;

  if has_function_privilege('authenticated','public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)','EXECUTE') then
    raise exception 'B4_LESSON_EVENT_WRITER_FREEZE_REGRESSION';
  end if;
end;
$postdeploy$;

select
  p.oid::regprocedure::text as signature,
  md5(pg_get_functiondef(p.oid)) as definition_md5,
  r.rolname as owner,
  p.prosecdef as security_definer,
  p.proconfig,
  p.proacl
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
join pg_roles r on r.oid=p.proowner
where n.nspname='public' and p.proname in (
  'school_expand_planned_lesson_batch_occurrences_v1',
  'school_list_planned_lesson_student_candidates_v1',
  'school_preflight_planned_lesson_batch_student_candidates_v1',
  'school_generate_planned_lessons_batch_r1d_f1_legacy_core'
)
order by signature;

select 'STUDENT_STATUS_PHASE_B4_LESSON_POSTDEPLOY_PASS' as result;
rollback;
