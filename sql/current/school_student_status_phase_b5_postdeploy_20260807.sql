\set ON_ERROR_STOP on
\pset pager off

begin read only;

do $postdeploy$
declare
  v_signature regprocedure;
begin
  foreach v_signature in array array[
    'public.school_preview_student_status_transition_v1(uuid,text,date,uuid)'::regprocedure,
    'public.school_preview_student_status_correction_v1(uuid,uuid,uuid,date,text)'::regprocedure,
    'public.school_list_student_status_management_v1()'::regprocedure,
    'public.school_list_student_status_history_v1(uuid)'::regprocedure
  ] loop
    if not has_function_privilege('authenticated',v_signature,'EXECUTE')
       or has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'B5_READER_PREVIEW_ACL_INVALID:%',v_signature;
    end if;
  end loop;

  foreach v_signature in array array[
    'public.school_transition_student_status_v1(uuid,text,date,text,uuid,text)'::regprocedure,
    'public.school_correct_student_status_event_v1(uuid,uuid,uuid,date,text,text,text,text)'::regprocedure
  ] loop
    if not has_function_privilege('authenticated',v_signature,'EXECUTE')
       or has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'B5_WRITER_ACL_INVALID:%',v_signature;
    end if;
  end loop;

  foreach v_signature in array array[
    'public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)'::regprocedure,
    'public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)'::regprocedure
  ] loop
    if has_function_privilege('authenticated',v_signature,'EXECUTE')
       or has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'B5_RAW_WRITER_EXPOSED:%',v_signature;
    end if;
  end loop;

  if has_table_privilege('authenticated','public.school_student_status_events','INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','public.school_student_status_events','INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated','public.school_students','INSERT,UPDATE,DELETE') then
    raise exception 'B5_TABLE_DML_PRIVILEGE_REGRESSION';
  end if;
  if position('STUDENT_LEGACY_STATUS_IMMUTABLE' in pg_get_functiondef(
       'public.school_guard_legacy_student_status_immutable_v1()'::regprocedure
     )) = 0 then
    raise exception 'B5_LEGACY_STATUS_GUARD_MISSING';
  end if;
end;
$postdeploy$;

rollback;

select 'STUDENT_STATUS_PHASE_B5_POSTDEPLOY_PASS' result;
