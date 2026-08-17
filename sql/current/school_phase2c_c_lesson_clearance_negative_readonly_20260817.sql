-- Phase 2C-C production negative acceptance without invoking any writer.
\set ON_ERROR_STOP on
begin transaction read only;

do $negative_acl$
declare v_signature regprocedure;
begin
  foreach v_signature in array array[
    'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure,
    'public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure
  ] loop
    if has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'PHASE2C_C_NEGATIVE_WRITER_BYPASS:%',v_signature;
    end if;
  end loop;
  if has_table_privilege('anon','public.school_lesson_clearances','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated','public.school_lesson_clearances','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','public.school_lesson_clearances','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('anon','public.school_lesson_clearance_details','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated','public.school_lesson_clearance_details','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','public.school_lesson_clearance_details','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'PHASE2C_C_NEGATIVE_TABLE_BYPASS';
  end if;
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_C_NEGATIVE_CLEARANCE_NOT_EMPTY';
  end if;
end
$negative_acl$;

select 'PHASE2C_C_NEGATIVE_READONLY_PASS' result;
rollback;
