-- Phase BE-UI production read-only postdeploy verification.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

do $postdeploy$
declare
  v_actor uuid;
  v_result jsonb;
begin
  if to_regprocedure('public.school_get_profit_summary_schoolwide_v1(text,text)') is null then
    raise exception 'BE_UI_PROFIT_READER_MISSING';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid='public.school_get_profit_summary_schoolwide_v1(text,text)'::regprocedure
      and pg_get_userbyid(p.proowner)='postgres'
      and p.prosecdef
      and p.provolatile='s'
      and p.proconfig='{"search_path=pg_catalog, public"}'::text[]
  ) then
    raise exception 'BE_UI_PROFIT_READER_SECURITY_INVALID';
  end if;

  if exists (
       select 1
       from aclexplode(coalesce(
         (select p.proacl from pg_proc p where p.oid='public.school_get_profit_summary_schoolwide_v1(text,text)'::regprocedure),
         acldefault('f',(select p.proowner from pg_proc p where p.oid='public.school_get_profit_summary_schoolwide_v1(text,text)'::regprocedure))
       )) acl
       where acl.grantee=0 and acl.privilege_type='EXECUTE'
     )
     or has_function_privilege('anon','public.school_get_profit_summary_schoolwide_v1(text,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.school_get_profit_summary_schoolwide_v1(text,text)','EXECUTE')
     or has_function_privilege('service_role','public.school_get_profit_summary_schoolwide_v1(text,text)','EXECUTE') then
    raise exception 'BE_UI_PROFIT_READER_ACL_INVALID';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('school_create_business_entity_profile','school_update_business_entity_profile')
      and (
        exists (
          select 1
          from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
          where acl.grantee=0 and acl.privilege_type='EXECUTE'
        )
        or has_function_privilege('anon',p.oid,'EXECUTE')
        or has_function_privilege('authenticated',p.oid,'EXECUTE')
        or has_function_privilege('service_role',p.oid,'EXECUTE')
      )
  ) then
    raise exception 'BE_UI_PROFILE_WRITER_ACL_NOT_CLOSED';
  end if;

  select membership.user_id into v_actor
  from public.school_app_memberships membership
  where membership.is_active
    and membership.role in ('admin','operator','read_only')
  order by case membership.role when 'admin' then 1 when 'operator' then 2 else 3 end,membership.user_id
  limit 1;
  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  v_result := public.school_get_profit_summary_schoolwide_v1('2026-01','2026-12');

  if jsonb_array_length(v_result->'summary_rows')<>2
     or jsonb_array_length(v_result->'audit_rows')<>7 then
    raise exception 'BE_UI_PROFIT_READER_RESULT_INVALID';
  end if;

  if (select count(*) from public.school_business_entities)<>2
     or (select md5(coalesce(string_agg(to_jsonb(be)::text,'|' order by be.id),''))
         from public.school_business_entities be)<>'3bc3425c4bd152bafe7a528a2762d33e' then
    raise exception 'BE_UI_BUSINESS_ENTITY_FINGERPRINT_CHANGED';
  end if;

  if (select count(*) from public.school_lesson_records where business_entity_id='886a8f7c-0fea-45ac-97d2-15c976ede996')<>142
     or (select count(*) from public.school_student_monthly_settlements where business_entity_id='886a8f7c-0fea-45ac-97d2-15c976ede996')<>11
     or (select count(*) from public.school_student_tuition_bills where business_entity_id='886a8f7c-0fea-45ac-97d2-15c976ede996')<>2
     or (select count(*) from public.school_student_tuition_bill_lessons where business_entity_id_snapshot='886a8f7c-0fea-45ac-97d2-15c976ede996')<>42
     or (select count(*) from public.school_teacher_wage_locks where business_entity_id='886a8f7c-0fea-45ac-97d2-15c976ede996')<>77
     or (select count(*) from public.school_teacher_wage_lock_details where business_entity_id='886a8f7c-0fea-45ac-97d2-15c976ede996')<>463
     or (select count(*) from public.school_income_records where business_entity_id='886a8f7c-0fea-45ac-97d2-15c976ede996')<>29
     or (select count(*) from public.school_expense_records where business_entity_id='886a8f7c-0fea-45ac-97d2-15c976ede996')<>9
     or (select count(*) from public.school_payment_requests where business_entity_id='886a8f7c-0fea-45ac-97d2-15c976ede996')<>43
     or (select count(*) from public.school_personal_cash_income_linkage_events where business_entity_id='886a8f7c-0fea-45ac-97d2-15c976ede996')<>30 then
    raise exception 'BE_UI_PERSONAL_REFERENCE_COUNTS_CHANGED';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key,state) in (
        ('student_tuition_preview','enabled'),
        ('student_tuition_generate','blocked'),
        ('student_tuition_cash_submit','enabled')
      ))<>3 then
    raise exception 'BE_UI_TUITION_GATES_CHANGED';
  end if;
end;
$postdeploy$;

select p.oid::regprocedure::text signature,pg_get_userbyid(p.proowner) owner,
       p.prosecdef,p.provolatile,p.proconfig,p.proacl,md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'school_get_profit_summary_schoolwide_v1',
    'school_create_business_entity_profile',
    'school_update_business_entity_profile'
  )
order by signature;

select feature_key,state,updated_at
from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

select 'BE_UI_POSTDEPLOY_PASS' result;
rollback;
