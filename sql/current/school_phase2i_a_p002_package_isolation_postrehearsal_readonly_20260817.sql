\set ON_ERROR_STOP on
begin transaction isolation level repeatable read read only;
do $verify$
begin
  if to_regclass('public.school_student_package_credit_lots') is not null
     or to_regprocedure('public.school_list_student_package_credit_lots(uuid)') is not null
     or to_regprocedure('public.school_is_active_package_credit_origin(uuid)') is not null
     or to_regprocedure('public.school_create_lesson_credit_makeup_actual_phase2i_a_legacy(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)') is not null then
    raise exception 'PHASE2I_A_REHEARSAL_OBJECT_RESIDUE';
  end if;
  if md5(pg_get_functiondef('public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure))<>'f5da14743858f89d37f17ba2646ab092'
     or md5(pg_get_functiondef('public.school_get_lesson_credit_remaining_hours(uuid)'::regprocedure))<>'2111a62f998abeeb6933b47fc5c512aa'
     or md5(pg_get_functiondef('public.school_list_student_lesson_credit_balances(uuid)'::regprocedure))<>'81823a464f235e72a439867a2c4d395a'
     or md5(pg_get_functiondef('public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure))<>'3b45f8f09d4d63a952ca5ec42f7214d7'
     or md5(pg_get_functiondef('public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure))<>'4859d04189893b1dfdecc6a3d66df192'
     or md5(pg_get_functiondef('public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure))<>'3434e8ece09ec210511aec8b8eb1960f' then
    raise exception 'PHASE2I_A_REHEARSAL_FUNCTION_RESIDUE';
  end if;
  if md5((select to_jsonb(x)::text from public.school_lesson_records x where x.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'))<>'686cbf3a566160bf0de0e30abbdaafa5' then
    raise exception 'PHASE2I_A_REHEARSAL_P002_DRIFT';
  end if;
end
$verify$;
select object_name,row_count,row_hash from (
  select 1 n,'lessons' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash from public.school_lesson_records x
  union all select 2,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 3,'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 4,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
) evidence order by n;
rollback;
