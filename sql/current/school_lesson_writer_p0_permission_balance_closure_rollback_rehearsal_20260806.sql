-- Rollback-only catalog rehearsal for lesson writer P0 closure.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
\ir school_lesson_writer_p0_permission_balance_closure_core_20260806.sql

do $verify_rehearsal$
declare
  v_signature regprocedure;
begin
  if to_regprocedure('public.school_assert_active_lesson_writer()') is null
     or to_regprocedure('public.school_get_lesson_credit_raw_remaining_hours(uuid)') is null
     or to_regprocedure('public.school_lesson_writer_p0_validate_row()') is null
     or not exists(
       select 1 from pg_trigger
       where tgrelid='public.school_lesson_records'::regclass
         and tgname='trg_school_lesson_writer_p0_validate'
         and tgenabled='O'
     ) then
    raise exception 'LESSON_WRITER_P0_REHEARSAL_OBJECT_MISSING';
  end if;

  for v_signature in select unnest(array[
    'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)'::regprocedure,
    'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure,
    'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)'::regprocedure,
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,
    'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,
    'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure,
    'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure
  ]::regprocedure[])
  loop
    if position('school_assert_active_lesson_writer()' in pg_get_functiondef(v_signature::oid))=0
       or not has_function_privilege('authenticated',v_signature,'execute')
       or has_function_privilege('anon',v_signature,'execute')
       or has_function_privilege('service_role',v_signature,'execute')
       or has_function_privilege('public',v_signature,'execute') then
      raise exception 'LESSON_WRITER_P0_REHEARSAL_CANONICAL_INVALID:%',v_signature;
    end if;
  end loop;

  if position('new.voided_at' in pg_get_functiondef(
       'public.school_lesson_writer_p0_validate_row()'::regprocedure))=0
     or position('LESSON_MAKEUP_SOURCE_STATUS_INVALID' in pg_get_functiondef(
       'public.school_lesson_writer_p0_validate_row()'::regprocedure))=0 then
    raise exception 'LESSON_WRITER_P0_REHEARSAL_PROPOSED_STATE_GAP';
  end if;
end;
$verify_rehearsal$;

select 'LESSON_WRITER_P0_ROLLBACK_REHEARSAL_PASS' result;
select md5(pg_get_functiondef(
  'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
)) makeup_post_md5;
rollback;
