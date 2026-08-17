\set ON_ERROR_STOP on
begin transaction isolation level repeatable read read only;

do $verify$
declare v_preview jsonb;
begin
  if to_regclass('public.school_student_package_credit_lots') is null
     or to_regprocedure('public.school_list_student_package_credit_lots(uuid)') is null
     or to_regprocedure('public.school_is_active_package_credit_origin(uuid)') is null then
    raise exception 'PHASE2I_A_POSTDEPLOY_PACKAGE_OBJECT_MISSING';
  end if;
  if to_regclass('public.school_lesson_clearances') is not null
     or to_regclass('public.school_lesson_clearance_details') is not null
     or exists(select 1 from pg_proc procedure
       where procedure.pronamespace='public'::regnamespace
         and procedure.proname~'package.*(consume|reserve)|(consume|reserve).*package') then
    raise exception 'PHASE2I_A_POSTDEPLOY_FORBIDDEN_OBJECT';
  end if;
  if (select count(*) from public.school_student_package_credit_lots)<>1
     or not exists(select 1 from public.school_student_package_credit_lots lot
       where lot.id='2a000000-0000-4000-8000-202608170002'
         and lot.origin_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
         and lot.initial_minutes=1200 and lot.consumed_minutes=0
         and lot.remaining_minutes=1200 and lot.unit_price_jpy=13000
         and lot.total_price_jpy=260000 and lot.student_billing_month='2026-07'
         and lot.status='active'
         and lot.origin_lesson_row_md5='686cbf3a566160bf0de0e30abbdaafa5') then
    raise exception 'PHASE2I_A_POSTDEPLOY_PACKAGE_FACT_MISMATCH';
  end if;
  if public.school_get_lesson_credit_raw_remaining_hours('8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')<>0
     or public.school_get_lesson_credit_remaining_hours('8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')<>0
     or exists(select 1 from public.school_list_open_lesson_credit_sources('2026-07','2026-07','2026-07') source
       where source.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')
     or exists(select 1 from public.school_tuition_p0f_source_lines(
       'a7b163a0-201e-4867-9b94-372343356a80','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-07',0.045,false) source
       where source.source_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9') then
    raise exception 'PHASE2I_A_POSTDEPLOY_ORDINARY_CHAIN_NOT_ISOLATED';
  end if;
  select public.school_preview_student_settlement_adjustment_dialog(
    'a7b163a0-201e-4867-9b94-372343356a80','2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
    '2026-07','separate_makeup_and_overage_v1',null,null,null,'carry_final_balance',null)
    into v_preview;
  if (v_preview#>>'{preview,registered_source_count}')::integer<>0
     or (v_preview#>>'{preview,registered_pending_hours}')::numeric<>0
     or (v_preview#>>'{preview,registered_pending_amount_jpy}')::numeric<>0 then
    raise exception 'PHASE2I_A_POSTDEPLOY_PREVIEW_MISMATCH';
  end if;
  if md5((select to_jsonb(x)::text from public.school_lesson_records x
      where x.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'))<>'686cbf3a566160bf0de0e30abbdaafa5'
     or (select count(*) from public.school_lesson_records)<>771 then
    raise exception 'PHASE2I_A_POSTDEPLOY_LESSON_DRIFT';
  end if;
  if has_table_privilege('anon','public.school_student_package_credit_lots','SELECT')
     or has_table_privilege('authenticated','public.school_student_package_credit_lots','SELECT')
     or has_table_privilege('service_role','public.school_student_package_credit_lots','SELECT')
     or has_table_privilege('authenticated','public.school_student_package_credit_lots','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_function_privilege('anon','public.school_list_student_package_credit_lots(uuid)','EXECUTE')
     or has_function_privilege('service_role','public.school_list_student_package_credit_lots(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.school_list_student_package_credit_lots(uuid)','EXECUTE')
     or has_function_privilege('authenticated','public.school_is_active_package_credit_origin(uuid)','EXECUTE') then
    raise exception 'PHASE2I_A_POSTDEPLOY_ACL_MISMATCH';
  end if;
end
$verify$;

set local role authenticated;
select set_config('request.jwt.claim.sub','25331ae9-3412-48b9-bdc3-e516caeaeba4',true);
select * from public.school_list_student_package_credit_lots(
  'a7b163a0-201e-4867-9b94-372343356a80');
select public.school_get_lesson_credit_remaining_hours(
  '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9') authenticated_p002_remaining;
select * from public.school_list_student_lesson_credit_balances(
  'a7b163a0-201e-4867-9b94-372343356a80');
reset role;

select procedure.oid::regprocedure::text signature,
  pg_get_userbyid(procedure.proowner) owner,procedure.prosecdef security_definer,
  coalesce(array_to_string(procedure.proconfig,','),'') settings,
  coalesce(array_to_string(procedure.proacl,','),'') acl,
  md5(pg_get_functiondef(procedure.oid)) definition_md5
from pg_proc procedure
where procedure.pronamespace='public'::regnamespace
  and procedure.proname in (
    'school_is_active_package_credit_origin',
    'school_list_student_package_credit_lots',
    'school_get_lesson_credit_raw_remaining_hours',
    'school_get_lesson_credit_remaining_hours',
    'school_list_student_lesson_credit_balances',
    'school_list_open_lesson_credit_sources',
    'school_tuition_p0f_source_lines',
    'school_create_lesson_credit_makeup_actual',
    'school_create_lesson_credit_makeup_actual_phase2i_a_legacy',
    'school_guard_package_credit_actual_insert'
  ) order by signature;

select object_name,row_count,row_hash from (
  select 1 n,'lessons' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash from public.school_lesson_records x
  union all select 2,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 3,'claims',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_lesson_variance_claims x
  union all select 4,'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 5,'bill_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bill_lessons x
  union all select 6,'revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_generation_revisions x
  union all select 7,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
  union all select 8,'cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_personal_cash_income_linkage_events x
  union all select 9,'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
  union all select 10,'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
  union all select 11,'storage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from storage.objects x
  union all select 12,'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.feature_key),'')) from public.school_feature_gates x
) evidence order by n;
rollback;
