-- School V2 student monthly status Phase A read-only postdeploy.
\set ON_ERROR_STOP on
\pset pager off

do $postdeploy$
declare
  v_oid oid;
  v_target constant uuid:='cff85c52-6acc-4b0f-8c92-3db280a5dd77';
  v_reason constant text:='2026年6月为最后在读月份，从2026年7月起暂停上课。';
begin
  if to_regclass('public.school_student_status_events') is null then
    raise exception 'STATUS_POSTDEPLOY_TABLE_MISSING';
  end if;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='school_student_status_events')<>14 then
    raise exception 'STATUS_POSTDEPLOY_COLUMN_COUNT_INVALID';
  end if;
  if not (select c.relrowsecurity from pg_class c where c.oid='public.school_student_status_events'::regclass)
     or exists (select 1 from pg_policies where schemaname='public' and tablename='school_student_status_events') then
    raise exception 'STATUS_POSTDEPLOY_RLS_INVALID';
  end if;
  if has_table_privilege('anon','public.school_student_status_events','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('authenticated','public.school_student_status_events','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('service_role','public.school_student_status_events','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
    raise exception 'STATUS_POSTDEPLOY_TABLE_ACL_INVALID';
  end if;
  if (select count(*) from pg_trigger where tgrelid='public.school_student_status_events'::regclass and not tgisinternal)<>3 then
    raise exception 'STATUS_POSTDEPLOY_TRIGGER_COUNT_INVALID';
  end if;
  if (select count(*) from pg_indexes where schemaname='public' and tablename='school_student_status_events')<>5 then
    raise exception 'STATUS_POSTDEPLOY_INDEX_COUNT_INVALID';
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.school_student_status_events'::regclass
      and conname='school_student_status_events_replacement_fkey'
      and condeferrable and condeferred
  ) then
    raise exception 'STATUS_POSTDEPLOY_REPLACEMENT_FK_INVALID';
  end if;

  foreach v_oid in array array[
    'public.school_resolve_student_status_at_month_v1(uuid,date)'::regprocedure::oid,
    'public.school_list_student_month_candidates_v1(date,boolean,uuid)'::regprocedure::oid,
    'public.school_list_student_range_candidates_v1(date,date,boolean,uuid)'::regprocedure::oid,
    'public.school_list_student_status_shadow_v1(date)'::regprocedure::oid,
    'public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)'::regprocedure::oid,
    'public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)'::regprocedure::oid
  ] loop
    if not (select p.prosecdef and p.proconfig='{"search_path=pg_catalog, public"}'::text[] from pg_proc p where p.oid=v_oid)
       or has_function_privilege('anon',v_oid,'EXECUTE')
       or not has_function_privilege('authenticated',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'STATUS_POSTDEPLOY_PUBLIC_FUNCTION_INVALID:%',v_oid::regprocedure;
    end if;
  end loop;

  foreach v_oid in array array[
    'public.school_require_current_app_student_reader_v1()'::regprocedure::oid,
    'public.school_resolve_student_status_at_month_core_v1(uuid,date)'::regprocedure::oid,
    'public.school_assert_student_status_sequence_v1(uuid)'::regprocedure::oid,
    'public.school_guard_student_status_event_mutation_v1()'::regprocedure::oid
  ] loop
    if has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('authenticated',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'STATUS_POSTDEPLOY_INTERNAL_FUNCTION_EXPOSED:%',v_oid::regprocedure;
    end if;
  end loop;

  if (select count(*) from public.school_student_status_events)>1
     or exists (
       select 1 from public.school_student_status_events e
       where e.student_id<>v_target or e.effective_month<>'2026-07-01' or e.status<>'paused'
          or e.reason<>v_reason or e.voided_at is not null
          or e.created_by_user_id<>'25331ae9-3412-48b9-bdc3-e516caeaeba4'
          or e.created_by_membership_id<>'25331ae9-3412-48b9-bdc3-e516caeaeba4'
     ) then
    raise exception 'STATUS_POSTDEPLOY_PRODUCTION_EVENT_INVALID';
  end if;

  if (select count(*) from public.school_students)<>8
     or (select md5(coalesce(string_agg(to_jsonb(s)::text,'|' order by s.id),'')) from public.school_students s)<>'431ae7f350902dde0642ddc4982054ed'
     or (select count(*) from public.school_lesson_records)<>733
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_lesson_records t)<>'4d0c327cc0d7b2c6cbdae10ede6a3fd4'
     or (select count(*) from public.school_student_monthly_settlements)<>18
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_student_monthly_settlements t)<>'7986db5dd35c0ecfa180a04aef7f4051'
     or (select count(*) from public.school_income_records where student_id is not null)<>30
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_income_records t where t.student_id is not null)<>'0380f2e4ab967d37ad898a4e534195a4'
     or (select count(*) from public.school_student_tuition_bills)<>22
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_student_tuition_bills t)<>'d079f068c0fa19fc07d4dcd94094fae2'
     or (select count(*) from public.school_teacher_wage_lock_details)<>556
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_teacher_wage_lock_details t)<>'0b2976f8005835d66b2db25b0b3c1939'
     or (select count(*) from public.school_teacher_wage_rules)<>20
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_teacher_wage_rules t)<>'2dc430ca4a58416235f2ba771b91b9f1'
     or (select count(*) from public.school_income_records)<>55
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_income_records t)<>'bd2d538d1de901621ff0e6757984a41e'
     or (select count(*) from public.school_expense_records)<>47
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_expense_records t)<>'141c76e4cf6148007e182704941a0c4a'
     or (select count(*) from public.school_accounts)<>3
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_accounts t)<>'443b3170f50bc23a56834d398069c565'
     or (select count(*) from public.school_account_transactions)<>187
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_account_transactions t)<>'21694ff060e23289566f0a6e9fe3e449' then
    raise exception 'STATUS_POSTDEPLOY_PROTECTED_BUSINESS_FACT_CHANGED';
  end if;
  if (select count(*) from storage.objects where bucket_id='school-expense-files')<>57
     or (select count(*) from storage.objects o left join public.school_expense_records e on e.id::text=split_part(o.name,'/',3) and e.app_type='school' where o.bucket_id='school-expense-files' and e.id is null)<>30 then
    raise exception 'STATUS_POSTDEPLOY_STORAGE_CHANGED';
  end if;
  if (select count(*) from public.school_feature_gates where
      (feature_key='student_tuition_preview' and state='enabled') or
      (feature_key='student_tuition_generate' and state='blocked') or
      (feature_key='student_tuition_cash_submit' and state='enabled'))<>3 then
    raise exception 'STATUS_POSTDEPLOY_GATE_CHANGED';
  end if;
end;
$postdeploy$;

select p.oid::regprocedure::text signature,pg_get_userbyid(p.proowner) owner,
       p.prosecdef,p.provolatile,p.proconfig,
       has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') service_execute,
       md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname like 'school%student%status%v1'
order by signature;

select 'STUDENT_STATUS_PHASE_A_POSTDEPLOY_PASS' result;
