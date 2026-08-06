-- Exact rollback rehearsal: deploy and exact-restore inside one outer transaction.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
\ir school_lesson_writer_p0_permission_balance_closure_core_20260806.sql
\set lesson_writer_p0_rollback_rehearsal 1
\ir school_lesson_writer_p0_permission_balance_closure_exact_rollback_20260806.sql

do $verify_exact_rollback$
begin
  if to_regprocedure('public.school_assert_active_lesson_writer()') is not null
     or to_regprocedure('public.school_get_lesson_credit_raw_remaining_hours(uuid)') is not null
     or to_regprocedure('public.school_lesson_writer_p0_validate_row()') is not null
     or exists(select 1 from pg_trigger where tgrelid='public.school_lesson_records'::regclass
       and tgname='trg_school_lesson_writer_p0_validate')
     or md5(pg_get_functiondef('public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure))<>'ff5181679cda96b26d2f27c17f6b9665'
     or md5(pg_get_functiondef('public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure))<>'23ee5d41a11f8a7b6ebf46283f3b0f6a'
     or md5(pg_get_functiondef('public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure))<>'b84dab8220d68fbbac03d164bf18f0f9'
     or not has_function_privilege('anon','public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)','execute')
     or not has_function_privilege('service_role','public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)','execute') then
    raise exception 'LESSON_WRITER_P0_EXACT_ROLLBACK_INVALID';
  end if;
end;
$verify_exact_rollback$;
select 'LESSON_WRITER_P0_EXACT_ROLLBACK_TEST_PASS' result;
rollback;
