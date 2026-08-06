-- Read-only postdeploy verification for lesson writer P0 closure.
\set ON_ERROR_STOP on
\pset pager off

do $verify$
declare
  v_signature regprocedure;
begin
  if pg_get_userbyid((select proowner from pg_proc where oid=
       'public.school_assert_active_lesson_writer()'::regprocedure))<>'postgres'
     or not (select prosecdef from pg_proc where oid=
       'public.school_assert_active_lesson_writer()'::regprocedure)
     or (select proconfig from pg_proc where oid=
       'public.school_assert_active_lesson_writer()'::regprocedure)
       <>array['search_path=pg_catalog, public']::text[] then
    raise exception 'LESSON_WRITER_P0_ASSERTION_CATALOG_INVALID';
  end if;

  if not exists(select 1 from pg_trigger where tgrelid='public.school_lesson_records'::regclass
      and tgname='trg_school_lesson_writer_p0_validate' and tgenabled='O')
     or position('LESSON_TIME_GRID_INVALID' in pg_get_functiondef(
       'public.school_lesson_writer_p0_validate_row()'::regprocedure))=0
     or position('LESSON_MAKEUP_CREDIT_EXCEEDED' in pg_get_functiondef(
       'public.school_lesson_writer_p0_validate_row()'::regprocedure))=0
     or position('LESSON_MAKEUP_SOURCE_STATUS_INVALID' in pg_get_functiondef(
       'public.school_lesson_writer_p0_validate_row()'::regprocedure))=0
     or position('new.voided_at' in pg_get_functiondef(
       'public.school_lesson_writer_p0_validate_row()'::regprocedure))=0 then
    raise exception 'LESSON_WRITER_P0_TRIGGER_INVALID';
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
    if not has_function_privilege('authenticated',v_signature,'execute')
       or has_function_privilege('public',v_signature,'execute')
       or has_function_privilege('anon',v_signature,'execute')
       or has_function_privilege('service_role',v_signature,'execute')
       or pg_get_userbyid((select proowner from pg_proc where oid=v_signature))<>'postgres'
       or not (select prosecdef from pg_proc where oid=v_signature)
       or (select proconfig from pg_proc where oid=v_signature)
         <>array['search_path=pg_catalog, public']::text[]
       or position('school_assert_active_lesson_writer()' in pg_get_functiondef(v_signature::oid))=0 then
      raise exception 'LESSON_WRITER_P0_CANONICAL_INVALID:%',v_signature;
    end if;
  end loop;

  for v_signature in select unnest(array[
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer)'::regprocedure,
    'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
    'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,integer)'::regprocedure,
    'public.school_p0c_baseline_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,
    'public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_import_lesson_records_batch(uuid,text,text,jsonb,text)'::regprocedure,
    'public.school_import_lesson_records_batch_with_venue(uuid,text,text,jsonb,text)'::regprocedure,
    'public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)'::regprocedure,
    'public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)'::regprocedure,
    'public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text)'::regprocedure,
    'public.school_void_planned_lesson_p0f_legacy(uuid,timestamp with time zone,text)'::regprocedure,
    'public.school_backfill_actual_minutes_from_duration(text)'::regprocedure,
    'public.school_assert_active_lesson_writer()'::regprocedure,
    'public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure,
    'public.school_lesson_writer_p0_validate_row()'::regprocedure
  ]::regprocedure[])
  loop
    if has_function_privilege('public',v_signature,'execute')
       or has_function_privilege('anon',v_signature,'execute')
       or has_function_privilege('authenticated',v_signature,'execute')
       or has_function_privilege('service_role',v_signature,'execute') then
      raise exception 'LESSON_WRITER_P0_OWNER_ONLY_INVALID:%',v_signature;
    end if;
  end loop;

  if (select relacl from pg_class where oid='public.school_lesson_records'::regclass)
       <>array['postgres=arwdDxtm/postgres','anon=r/postgres','authenticated=r/postgres','service_role=r/postgres']::aclitem[]
     or not (select relrowsecurity from pg_class where oid='public.school_lesson_records'::regclass)
     or (select relforcerowsecurity from pg_class where oid='public.school_lesson_records'::regclass) then
    raise exception 'LESSON_WRITER_P0_TABLE_ACL_RLS_DRIFT';
  end if;
  if (select count(*) from public.school_feature_gates where
      (feature_key='student_tuition_preview' and state='enabled') or
      (feature_key='student_tuition_generate' and state='blocked') or
      (feature_key='student_tuition_cash_submit' and state='enabled'))<>3 then
    raise exception 'LESSON_WRITER_P0_GATE_DRIFT';
  end if;
end;
$verify$;

select p.oid::regprocedure::text signature,pg_get_userbyid(p.proowner) owner,
       p.prosecdef security_definer,p.proconfig,p.proacl,md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p
where p.oid in (
  'public.school_assert_active_lesson_writer()'::regprocedure,
  'public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure,
  'public.school_lesson_writer_p0_validate_row()'::regprocedure,
  'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,
  'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)'::regprocedure,
  'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
  'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure,
  'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)'::regprocedure,
  'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,
  'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
  'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,
  'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure,
  'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure
)
order by signature;
select feature_key,state,updated_at from public.school_feature_gates order by feature_key;
select 'LESSON_WRITER_P0_POSTDEPLOY_PASS' result;
