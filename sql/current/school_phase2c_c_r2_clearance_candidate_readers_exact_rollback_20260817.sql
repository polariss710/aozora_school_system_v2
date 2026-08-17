-- Exact rollback for Phase 2C-C-R2. Old readers/writers were never replaced.
\set ON_ERROR_STOP on

\if :{?PHASE2C_C_R2_ROLLBACK_IN_EXISTING_TRANSACTION}
\else
begin;
\endif

drop function if exists public.school_get_lesson_clearance_dashboard_summary_v1(uuid);
drop function if exists public.school_list_cross_month_makeup_projection_v2(uuid,text);
drop function if exists public.school_list_student_package_credit_lots_v2(uuid);
drop function if exists public.school_list_lesson_clearance_available_overages_v2(uuid,boolean);
drop function if exists public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean);

do $verify$
begin
  if to_regprocedure('public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)') is not null
     or to_regprocedure('public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)') is not null
     or to_regprocedure('public.school_list_student_package_credit_lots_v2(uuid)') is not null
     or to_regprocedure('public.school_list_cross_month_makeup_projection_v2(uuid,text)') is not null
     or to_regprocedure('public.school_get_lesson_clearance_dashboard_summary_v1(uuid)') is not null then
    raise exception 'PHASE2C_C_R2_EXACT_ROLLBACK_OBJECT_REMAINS';
  end if;
end
$verify$;

\if :{?PHASE2C_C_R2_SKIP_PRODUCTION_MD5}
\else
do $dependency_md5$
begin
  if md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_pending_balances(uuid,boolean)'::regprocedure
    ))<>'59dcc6bdbc72488c5f0f25dfcdd7b7bc'
     or md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_available_overages(uuid,boolean)'::regprocedure
    ))<>'c7c1c5c2c9e2e36a2587476b063a192e'
     or md5(pg_get_functiondef(
      'public.school_list_student_package_credit_lots(uuid)'::regprocedure
    ))<>'ed3645856732070335827b4329dfecf0'
     or md5(pg_get_functiondef(
      'public.school_list_cross_month_makeup_projection(uuid,text)'::regprocedure
    ))<>'9008b9e1bf2c42953ce05cb2ae343517'
     or md5(pg_get_functiondef(
      'public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)'::regprocedure
    ))<>'ffeab2952a86c3c40d39cd3a5c806e19'
     or md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_history_v2(uuid)'::regprocedure
    ))<>'0f0068b523ca6c1c142b6ae55b41bc4d'
     or md5(pg_get_functiondef(
      'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure
    ))<>'f3706ef036a48de97a187c5e0d4e8e40'
     or md5(pg_get_functiondef(
      'public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure
    ))<>'07aefc153a1b2f9f2faacbf28f29447f' then
    raise exception 'PHASE2C_C_R2_EXACT_ROLLBACK_DEPENDENCY_DRIFT';
  end if;
end
$dependency_md5$;
\endif

\if :{?PHASE2C_C_R2_ROLLBACK_IN_EXISTING_TRANSACTION}
\else
commit;
\endif
