-- School V2 student status Phase B2 read-only postdeploy verification.
\set ON_ERROR_STOP on
\pset pager off

do $postdeploy$
declare
  v_oid oid;
  v_definition text;
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'school_create_student_profile') <> 3
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'school_update_student_profile') <> 6 then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_OVERLOAD_COUNT_INVALID';
  end if;

  foreach v_oid in array array[
    'public.school_create_student_profile_v2(text,uuid,text,numeric,text,text,date,text,text)'::regprocedure::oid,
    'public.school_update_student_profile_v2(uuid,text,uuid,text,numeric,text,text,date,text,text,timestamptz)'::regprocedure::oid
  ] loop
    select lower(pg_get_functiondef(p.oid)) into strict v_definition
    from pg_proc p where p.oid = v_oid;
    if not (select p.prosecdef and p.proconfig = '{"search_path=pg_catalog, public"}'::text[]
            from pg_proc p where p.oid = v_oid)
       or position('school_require_current_app_admin' in v_definition) = 0
       or not has_function_privilege('authenticated',v_oid,'EXECUTE')
       or has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_CANONICAL_INVALID:%',v_oid::regprocedure;
    end if;
  end loop;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('school_create_student_profile','school_update_student_profile')
      and (
        has_function_privilege('anon',p.oid,'EXECUTE')
        or has_function_privilege('authenticated',p.oid,'EXECUTE')
        or has_function_privilege('service_role',p.oid,'EXECUTE')
      )
  ) then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_LEGACY_OVERLOAD_EXPOSED';
  end if;

  foreach v_oid in array array[
    'public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)'::regprocedure::oid,
    'public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)'::regprocedure::oid
  ] loop
    if has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('authenticated',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE')
       or not has_function_privilege('postgres',v_oid,'EXECUTE') then
      raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_EVENT_FREEZE_INVALID:%',v_oid::regprocedure;
    end if;
  end loop;

  if md5(pg_get_functiondef('public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)'::regprocedure))
       <> '2ce0885969021516a804d5c887b6af39'
     or md5(pg_get_functiondef('public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)'::regprocedure))
       <> '4ba55f37406f7d2d3a4d0d8e24a7496b' then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_EVENT_BODY_CHANGED';
  end if;

  if (select count(*) from pg_trigger
      where tgrelid = 'public.school_students'::regclass
        and not tgisinternal
        and tgname = 'school_students_legacy_status_immutable_guard'
        and tgenabled = 'O') <> 1
     or has_function_privilege('anon','public.school_guard_legacy_student_status_immutable_v1()','EXECUTE')
     or has_function_privilege('authenticated','public.school_guard_legacy_student_status_immutable_v1()','EXECUTE')
     or has_function_privilege('service_role','public.school_guard_legacy_student_status_immutable_v1()','EXECUTE') then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_IMMUTABLE_GUARD_INVALID';
  end if;

  if has_table_privilege('anon','public.school_students','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('authenticated','public.school_students','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('service_role','public.school_students','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or not has_table_privilege('authenticated','public.school_students','SELECT')
     or not has_table_privilege('service_role','public.school_students','SELECT') then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_TABLE_ACL_CHANGED';
  end if;

  if (select count(*) from public.school_students) <> 8
     or (select count(*) from public.school_students where status = 'active') <> 7
     or (select count(*) from public.school_students where status = 'paused') <> 1
     or (select md5(coalesce(string_agg(to_jsonb(s)::text,'|' order by s.id),''))
         from public.school_students s) <> '431ae7f350902dde0642ddc4982054ed'
     or (select count(*) from public.school_student_status_events) <> 1
     or (select md5(coalesce(string_agg(to_jsonb(e)::text,'|' order by e.id),''))
         from public.school_student_status_events e) <> 'eeeb492ac7577ff85eb0926aa0b57301' then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_STUDENT_OR_EVENT_CHANGED';
  end if;

  if not exists (
    select 1
    from public.school_resolve_student_status_at_month_core_v1(
      'cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-06-01'
    ) r
    where r.resolved_status = 'active' and r.is_legacy_fallback
  ) or not exists (
    select 1
    from public.school_resolve_student_status_at_month_core_v1(
      'cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-07-01'
    ) r
    where r.resolved_status = 'paused'
      and r.source_event_id = '4190bddf-d995-4e6a-af6b-85997e6f999b'
  ) or not exists (
    select 1
    from public.school_resolve_student_status_at_month_core_v1(
      'cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-08-01'
    ) r
    where r.resolved_status = 'paused'
      and r.source_event_id = '4190bddf-d995-4e6a-af6b-85997e6f999b'
  ) then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_RESOLVER_CHANGED';
  end if;

  if (select count(*) from public.school_lesson_records) <> 738
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),''))
         from public.school_lesson_records t) <> 'fc802f6d7da3ece1182bd2c217955562'
     or md5(pg_get_functiondef('public.school_get_weekly_lesson_operations(date)'::regprocedure))
       <> 'e7eac5f3bb07c31ad15e750e8721c01f' then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_LESSON_OR_WEEKLY_CHANGED';
  end if;

  if (select count(*) from public.school_student_monthly_settlements) <> 18
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_student_monthly_settlements t) <> '7986db5dd35c0ecfa180a04aef7f4051'
     or (select count(*) from public.school_income_records where student_id is not null) <> 30
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_income_records t where student_id is not null) <> '0380f2e4ab967d37ad898a4e534195a4'
     or (select count(*) from public.school_student_tuition_bills) <> 22
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_student_tuition_bills t) <> 'd079f068c0fa19fc07d4dcd94094fae2'
     or (select count(*) from public.school_teacher_wage_lock_details) <> 556
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_teacher_wage_lock_details t) <> '0b2976f8005835d66b2db25b0b3c1939'
     or (select count(*) from public.school_teacher_wage_rules) <> 20
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_teacher_wage_rules t) <> '2dc430ca4a58416235f2ba771b91b9f1'
     or (select count(*) from public.school_income_records) <> 55
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_income_records t) <> 'bd2d538d1de901621ff0e6757984a41e'
     or (select count(*) from public.school_expense_records) <> 47
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_expense_records t) <> '141c76e4cf6148007e182704941a0c4a'
     or (select count(*) from public.school_accounts) <> 3
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_accounts t) <> '443b3170f50bc23a56834d398069c565'
     or (select count(*) from public.school_account_transactions) <> 187
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_account_transactions t) <> '21694ff060e23289566f0a6e9fe3e449' then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_BUSINESS_FACT_CHANGED';
  end if;

  if (select count(*) from storage.objects where bucket_id = 'school-expense-files') <> 57
     or (select md5(coalesce(string_agg(to_jsonb(o)::text,'|' order by o.id),''))
         from storage.objects o where o.bucket_id = 'school-expense-files') <> 'c2852a4dbcd13b9cddb1da0b1115b18f'
     or (select count(*)
         from storage.objects o
         left join public.school_expense_records e
           on e.id::text = split_part(o.name,'/',3) and e.app_type = 'school'
         where o.bucket_id = 'school-expense-files' and e.id is null) <> 30 then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_STORAGE_CHANGED';
  end if;

  if (select count(*) from public.school_feature_gates where
      (feature_key = 'student_tuition_preview' and state = 'enabled') or
      (feature_key = 'student_tuition_generate' and state = 'blocked') or
      (feature_key = 'student_tuition_cash_submit' and state = 'enabled')) <> 3 then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_GATE_CHANGED';
  end if;

  if exists (select 1 from auth.users where id::text like 'b2010000-%')
     or exists (select 1 from public.school_students where id::text like 'b2020000-%')
     or exists (select 1 from public.school_student_status_events where student_id::text like 'b2020000-%') then
    raise exception 'STUDENT_STATUS_B2_POSTDEPLOY_FIXTURE_RESIDUE';
  end if;
end;
$postdeploy$;

select p.oid::regprocedure::text signature,
       pg_get_userbyid(p.proowner) owner,
       p.prosecdef,p.proconfig,p.pronargdefaults,p.proacl,
       has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') service_role_execute,
       md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'school_create_student_profile','school_update_student_profile',
    'school_create_student_profile_v2','school_update_student_profile_v2',
    'school_record_student_status_event_v1','school_correct_student_status_event_v1'
  )
order by signature;

select 'STUDENT_STATUS_PHASE_B2_LEGACY_FREEZE_POSTDEPLOY_PASS' result;
