-- Exact P0-B1 code/ACL/RLS rollback. No business-row DML.
begin;

do $do$
declare
  v record;
  v_def text;
  v_new text;
begin
  for v in select * from (values
    ('public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,'  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);' || chr(10)),
    ('public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,'  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);' || chr(10)),
    ('public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,'  PERFORM public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);' || chr(10)),
    ('public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,'  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);' || chr(10)),
    ('public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,'  PERFORM public.school_tuition_p0b1_lock_new_planned_scope(p_student_id,p_business_entity_id,p_lesson_date);' || chr(10)),
    ('public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure,'  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id);' || chr(10)),
    ('public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,'  PERFORM public.school_tuition_p0b1_lock_new_planned_range(p_student_id,p_business_entity_id,p_start_date,p_end_date);' || chr(10)),
    ('public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,'  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id,p_student_id,p_business_entity_id,p_lesson_date);' || chr(10)),
    ('public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure,'  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id,p_student_id,p_business_entity_id,p_lesson_date);' || chr(10)),
    ('public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure,'  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id);' || chr(10))
  ) x(proc,injected)
  loop
    v_def:=pg_get_functiondef(v.proc);
    v_new:=replace(v_def,v.injected,'');
    if v_new=v_def or length(v_def)-length(v_new)<>length(v.injected) then
      raise exception 'P0B1_ROLLBACK_WRITER_PATCH_MISMATCH: %',v.proc;
    end if;
    execute v_new;
  end loop;
end
$do$;

drop trigger if exists trg_school_lesson_p0b1_financial_authority
on public.school_lesson_records;

drop policy if exists school_lesson_records_select on public.school_lesson_records;
create policy school_allow_all_lesson_records on public.school_lesson_records
for all to public using (true) with check (true);

grant insert,update,delete,truncate,references,trigger on public.school_lesson_records
to anon,authenticated,service_role;

do $do$
declare v_proc regprocedure;
begin
  foreach v_proc in array array[
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
    'public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,
    'public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer)'::regprocedure,
    'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)'::regprocedure,
    'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure,
    'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,integer)'::regprocedure,
    'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure,
    'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)'::regprocedure,
    'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure
  ] loop
    execute format('alter function %s security definer set search_path=public',v_proc);
  end loop;
end
$do$;

-- Restore the exact pre-P0-B1 execution shape.
grant execute on function public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text) to public,anon,authenticated,service_role;
grant execute on function public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text) to public,anon,authenticated,service_role;
grant execute on function public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text) to public,anon,authenticated,service_role;
grant execute on function public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text) to public,anon,authenticated,service_role;
grant execute on function public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text) to public,anon,authenticated,service_role;
grant execute on function public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text) to public,anon,authenticated,service_role;
grant execute on function public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text) to public,anon,authenticated,service_role;
grant execute on function public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer) to public,anon,authenticated,service_role;
grant execute on function public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer) to public,anon,authenticated,service_role;
grant execute on function public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text) to public,anon,authenticated,service_role;
grant execute on function public.school_void_planned_lesson(uuid,timestamp with time zone,text) to public,anon,authenticated,service_role;
grant execute on function public.school_import_lesson_records_batch(uuid,text,text,jsonb,text) to public,anon,authenticated,service_role;
grant execute on function public.school_import_lesson_records_batch_with_venue(uuid,text,text,jsonb,text) to authenticated,service_role;
grant execute on function public.school_backfill_actual_minutes_from_duration(text) to service_role;

drop function public.school_tuition_p0b1_lesson_financial_authority();
drop function public.school_tuition_p0b1_lock_existing_lesson_scope(uuid,uuid,uuid,date);
drop function public.school_tuition_p0b1_lock_new_planned_range(uuid,uuid,date,date);
drop function public.school_tuition_p0b1_lock_new_planned_scope(uuid,uuid,date);
drop function public.school_tuition_p0b1_lock_lesson_scopes(jsonb);

commit;
