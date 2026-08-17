-- Independent post-rehearsal zero-residue verification.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

do $verify$
begin
  if to_regprocedure('public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)') is not null
     or to_regprocedure('public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)') is not null
     or to_regprocedure('public.school_list_student_package_credit_lots_v2(uuid)') is not null
     or to_regprocedure('public.school_list_cross_month_makeup_projection_v2(uuid,text)') is not null
     or to_regprocedure('public.school_get_lesson_clearance_dashboard_summary_v1(uuid)') is not null then
    raise exception 'PHASE2C_C_R2_POSTREHEARSAL_OBJECT_REMAINS';
  end if;
  if exists(select 1 from auth.users where id::text like '2c220000-%')
     or exists(select 1 from public.school_lesson_records where id::text like '2c220000-%')
     or exists(select 1 from public.school_lesson_clearances where id::text like '2c220000-%')
     or exists(select 1 from public.school_lesson_clearance_details where id::text like '2c220000-%')
     or exists(select 1 from public.school_student_settlement_lesson_variance_claims where id::text like '2c220000-%') then
    raise exception 'PHASE2C_C_R2_POSTREHEARSAL_FIXTURE_REMAINS';
  end if;
  if md5(pg_get_functiondef(
      'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure
    ))<>'f3706ef036a48de97a187c5e0d4e8e40'
     or md5(pg_get_functiondef(
      'public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure
    ))<>'07aefc153a1b2f9f2faacbf28f29447f' then
    raise exception 'PHASE2C_C_R2_POSTREHEARSAL_WRITER_DRIFT';
  end if;
end
$verify$;
select count(*) clearance_count from public.school_lesson_clearances;
select count(*) clearance_detail_count from public.school_lesson_clearance_details;
rollback;
