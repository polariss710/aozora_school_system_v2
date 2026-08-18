-- Independent connection proof that the production rehearsal fully rolled back.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

do $assertions$
declare
  v_preview jsonb;
begin
  if md5(pg_get_functiondef(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure::oid
     ))<>'d24b82f51053b3960ce0e4839613ddc7' then
    raise exception 'POSTREHEARSAL_OLD_DEFINITION_NOT_RESTORED';
  end if;
  v_preview:=public.school_preview_student_settlement_adjustment_dialog(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',
    'separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  );
  if (v_preview#>>'{preview,system_difference_cny}')::numeric<>373.50
     or (v_preview#>>'{preview,registered_overage_hours}')::numeric<>0
     or (select count(*) from public.school_lesson_clearances)<>1
     or (select count(*) from public.school_lesson_clearance_details)<>1
     or (select count(*) from public.school_lesson_clearances
         where clearance_type='reversal')<>0
     or not exists(select 1 from public.school_student_package_credit_lots
       where id='2a000000-0000-4000-8000-202608170002'
         and initial_minutes=1200 and consumed_minutes=0 and remaining_minutes=1200) then
    raise exception 'POSTREHEARSAL_BUSINESS_BASELINE_CHANGED';
  end if;
  raise notice 'CLEARANCE_AWARE_OVERAGE_POSTREHEARSAL_READONLY_PASS';
end
$assertions$;

rollback;
