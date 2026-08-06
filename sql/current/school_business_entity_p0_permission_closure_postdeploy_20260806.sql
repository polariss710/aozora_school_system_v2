-- School V2 Phase BE-P0 production read-only catalog/data postdeploy.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

do $postdeploy$
declare
  v_oid oid;
  v_def text;
begin
  if not exists (
    select 1 from pg_class c
    where c.oid='public.school_business_entities'::regclass
      and pg_get_userbyid(c.relowner)='postgres'
      and c.relrowsecurity
  ) then
    raise exception 'BE_P0_TABLE_OWNER_OR_RLS_INVALID';
  end if;

  if exists (
    select 1
    from aclexplode(coalesce(
      (select c.relacl from pg_class c where c.oid='public.school_business_entities'::regclass),
      acldefault('r',(select c.relowner from pg_class c where c.oid='public.school_business_entities'::regclass))
    )) acl
    where acl.grantee=0
  ) or has_table_privilege('anon','public.school_business_entities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('authenticated','public.school_business_entities','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('service_role','public.school_business_entities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or not has_table_privilege('authenticated','public.school_business_entities','SELECT') then
    raise exception 'BE_P0_TABLE_ACL_INVALID';
  end if;

  if (select count(*) from pg_policies
      where schemaname='public' and tablename='school_business_entities')<>1
     or not exists (
       select 1 from pg_policies
       where schemaname='public' and tablename='school_business_entities'
         and policyname='school_business_entities_active_membership_select'
         and cmd='SELECT'
         and roles='{authenticated}'
         and qual ilike '%school_get_current_app_membership%'
         and qual ilike '%admin%'
         and qual ilike '%operator%'
         and qual ilike '%read_only%'
         and with_check is null
     ) then
    raise exception 'BE_P0_RLS_POLICY_INVALID';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='school_create_business_entity_profile')<>2
     or (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_update_business_entity_profile')<>2 then
    raise exception 'BE_P0_OVERLOAD_COUNT_INVALID';
  end if;

  for v_oid in
    select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('school_create_business_entity_profile','school_update_business_entity_profile')
  loop
    select lower(pg_get_functiondef(p.oid)) into strict v_def from pg_proc p where p.oid=v_oid;
    if not (select pg_get_userbyid(p.proowner)='postgres'
                   and p.prosecdef
                   and p.proconfig='{"search_path=pg_catalog, public"}'::text[]
            from pg_proc p where p.oid=v_oid)
       or position('perform public.school_require_current_app_admin();' in v_def)=0
       or position('perform public.school_require_current_app_admin();' in v_def)
          > position('from public.school_business_entities' in v_def)
       or exists (
         select 1
         from aclexplode(coalesce(
           (select p.proacl from pg_proc p where p.oid=v_oid),
           acldefault('f',(select p.proowner from pg_proc p where p.oid=v_oid))
         )) acl
         where acl.grantee=0 and acl.privilege_type='EXECUTE'
       )
       or has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'BE_P0_WRITER_SECURITY_INVALID:%',v_oid::regprocedure;
    end if;
  end loop;

  if not has_function_privilege('authenticated','public.school_create_business_entity_profile(jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','public.school_update_business_entity_profile(uuid,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.school_create_business_entity_profile(text,text,text,text,boolean,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_update_business_entity_profile(uuid,text,text,text,boolean,text)','EXECUTE') then
    raise exception 'BE_P0_RPC_EXECUTE_MATRIX_INVALID';
  end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname ~ '^school_(delete|merge|archive)_business_entity'
  ) then
    raise exception 'BE_P0_UNEXPECTED_MUTATOR_FOUND';
  end if;

  if (select count(*) from public.school_business_entities)<>2
     or (select md5(coalesce(string_agg(to_jsonb(be)::text,'|' order by be.id),''))
         from public.school_business_entities be)<>'3bc3425c4bd152bafe7a528a2762d33e' then
    raise exception 'BE_P0_BUSINESS_ENTITY_FINGERPRINT_CHANGED';
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
    raise exception 'BE_P0_PERSONAL_REFERENCE_COUNTS_CHANGED';
  end if;

  if (
    select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.bill_id,x.linkage_event_id),''))
    from (
      select b.id as bill_id,b.business_entity_id as bill_business_entity_id,b.status as bill_status,
             b.updated_at as bill_updated_at,
             i.id as income_id,i.business_entity_id as income_business_entity_id,
             i.status as income_status,i.updated_at as income_updated_at,
             g.id as generation_identity_id,g.business_entity_id as identity_business_entity_id,
             r.id as revision_id,r.lifecycle_status as revision_status,r.activated_at as revision_activated_at,
             e.id as linkage_event_id,e.business_entity_id as linkage_business_entity_id,
             e.sync_status as linkage_status,e.updated_at as linkage_updated_at
      from public.school_student_tuition_bills b
      left join public.school_income_records i on i.id=b.income_record_id
      left join public.school_student_tuition_generation_revisions r
        on r.tuition_bill_id=b.id and r.lifecycle_status='active'
      left join public.school_student_tuition_generation_identities g on g.id=r.generation_identity_id
      left join public.school_personal_cash_income_linkage_events e on e.income_record_id=i.id
      where b.id in (
        '2a9f1c25-a060-461e-ae10-b02295dec381',
        'fdf3cdfe-f715-4814-b500-9ff2bfe77a63'
      )
    ) x
  )<>'56745a8c13e441169d5c739dd250e18d' then
    raise exception 'BE_P0_KNOWN_TUITION_ANOMALY_FINGERPRINT_CHANGED';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key,state) in (
        ('student_tuition_preview','enabled'),
        ('student_tuition_generate','blocked'),
        ('student_tuition_cash_submit','enabled')
      ))<>3 then
    raise exception 'BE_P0_TUITION_GATES_CHANGED';
  end if;
end;
$postdeploy$;

select c.oid::regclass::text relation,pg_get_userbyid(c.relowner) owner,
       c.relrowsecurity,c.relforcerowsecurity,c.relacl
from pg_class c where c.oid='public.school_business_entities'::regclass;

select policyname,roles,cmd,qual,with_check
from pg_policies
where schemaname='public' and tablename='school_business_entities';

select p.oid::regprocedure::text signature,pg_get_userbyid(p.proowner) owner,
       p.prosecdef,p.proconfig,p.proacl,md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('school_create_business_entity_profile','school_update_business_entity_profile')
order by signature;

select id,code,name,entity_type,default_currency,is_company_report,is_active,
       note,created_at,updated_at
from public.school_business_entities order by id;

select feature_key,state,updated_at from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

select 'BE_P0_PERMISSION_CLOSURE_POSTDEPLOY_PASS' result;
rollback;
