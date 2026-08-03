-- P0-F emergency read-chain repair.
-- Grants anon only the stable, read-only lesson history state reader required by
-- lesson.html. No table privileges or writer/helper privileges are changed.
\set ON_ERROR_STOP on
\pset pager off

begin;

do $verify$
declare
  v_proc regprocedure :=
    'public.school_get_planned_lesson_tuition_history_state(uuid[])'::regprocedure;
begin
  if (select p.provolatile <> 's' or not p.prosecdef
      from pg_catalog.pg_proc p where p.oid=v_proc) then
    raise exception 'P0F_LESSON_HISTORY_READER_CONTRACT_INVALID';
  end if;
  if not exists(
    select 1 from pg_catalog.pg_proc p
    where p.oid=v_proc
      and p.proconfig=array['search_path=pg_catalog, public']
      and position('school_lesson_records' in pg_catalog.pg_get_functiondef(p.oid))>0
      and position('school_student_tuition_bill_lessons' in pg_catalog.pg_get_functiondef(p.oid))>0
      and position('school_student_tuition_generation_revisions' in pg_catalog.pg_get_functiondef(p.oid))>0
      and position('lesson.id=any' in pg_catalog.pg_get_functiondef(p.oid))>0
      and position('lesson.lesson_type=''planned''' in pg_catalog.pg_get_functiondef(p.oid))>0
  ) then
    raise exception 'P0F_LESSON_HISTORY_READER_SCOPE_INVALID';
  end if;
end
$verify$;

revoke all on function public.school_get_planned_lesson_tuition_history_state(uuid[])
  from public,anon,authenticated,service_role;
grant execute on function public.school_get_planned_lesson_tuition_history_state(uuid[])
  to anon,authenticated,service_role;

comment on function public.school_get_planned_lesson_tuition_history_state(uuid[]) is
  'Read-only lesson-page routing facts. Anon/authenticated may read counts only for caller-supplied planned lesson ids already visible to the lesson page. No writer or owner helper is exposed.';

commit;
