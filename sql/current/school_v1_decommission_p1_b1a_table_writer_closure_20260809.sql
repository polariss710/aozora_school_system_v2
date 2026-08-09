-- School V1 decommission P1-B1A table-writer bypass closure, 2026-08-09.
-- ACL/RLS policy changes only. This file never writes business rows.
--
-- Business-model expansion declaration
-- New tables/columns/status/date/identity/source/snapshot/writable facts: none.
-- Field semantics/mutability/locking/historical interpretation/dual write: unchanged.
-- Changed writer authority: PUBLIC, anon and authenticated lose direct
-- INSERT/UPDATE/DELETE/TRUNCATE on the four exact target tables. Existing
-- SECURITY DEFINER RPC, owner and service_role authority remains unchanged.
-- Approval: current P1-B1A business-owner instruction, sections I, VI and IX.

\set ON_ERROR_STOP on

begin;

do $preflight$
declare
  v_table text;
  v_expected_policy_md5 text;
  v_expected_policy_count integer;
  v_actual_policy_md5 text;
  v_actual_policy_count integer;
begin
  foreach v_table in array array[
    'school_income_records',
    'school_settings',
    'school_subjects',
    'school_teachers'
  ] loop
    if not exists (
      select 1
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public'
        and c.relname=v_table
        and c.relkind='r'
        and pg_catalog.pg_get_userbyid(c.relowner)='postgres'
        and c.relrowsecurity
        and not c.relforcerowsecurity
        and (
          select md5(string_agg(
            concat_ws('|',
              case when acl.grantee=0
                then 'PUBLIC'
                else pg_catalog.pg_get_userbyid(acl.grantee)
              end,
              acl.privilege_type,
              acl.is_grantable::text
            ),
            E'\n' order by
              case when acl.grantee=0
                then 'PUBLIC'
                else pg_catalog.pg_get_userbyid(acl.grantee)
              end,
              acl.privilege_type,
              acl.is_grantable::text
          ))
          from pg_catalog.aclexplode(
            coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))
          ) acl
        )='916c9ecaffa9dda176f71280173b43bd'
        and (
          select count(*)
          from pg_catalog.aclexplode(
            coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))
          ) acl
        )=32
    ) then
      raise exception 'P1_B1A_TABLE_STATE_OR_ACL_DRIFT: %',v_table;
    end if;

    if not (
      pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'SELECT')
      and pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'SELECT')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'SELECT')
      and pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'INSERT')
      and pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'UPDATE')
      and pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'DELETE')
      and pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'TRUNCATE')
      and pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'INSERT')
      and pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'UPDATE')
      and pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'DELETE')
      and pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'TRUNCATE')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'INSERT')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'UPDATE')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'DELETE')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'TRUNCATE')
    ) then
      raise exception 'P1_B1A_EFFECTIVE_PRIVILEGE_DRIFT: %',v_table;
    end if;
  end loop;

  for v_table,v_expected_policy_md5 in
    select * from (values
      ('school_income_records','3c03f65691cd0e7fd264a29647d5c498'),
      ('school_settings','37017143beec0fa6dc2c365de65b09c2'),
      ('school_subjects','2d4df94ba0c3bd9ec5bf84dfc59c452e'),
      ('school_teachers','9f288113558df0a645e61c0c1c0c151f')
    ) expected(table_name,policy_md5)
  loop
    if v_table='school_income_records' then
      v_expected_policy_count:=4;
    else
      v_expected_policy_count:=1;
    end if;

    select
      md5(string_agg(
        concat_ws('|',policyname,permissive,array_to_string(roles,','),cmd,
          coalesce(qual,''),coalesce(with_check,'')),
        E'\n' order by policyname
      )),
      count(*)::integer
    into v_actual_policy_md5,v_actual_policy_count
    from pg_catalog.pg_policies
    where schemaname='public'
      and tablename=v_table;

    if v_actual_policy_md5 is distinct from v_expected_policy_md5
       or v_actual_policy_count <> v_expected_policy_count then
      raise exception 'P1_B1A_POLICY_DRIFT: %',v_table;
    end if;
  end loop;

  if exists (
    select 1
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    join information_schema.views v
      on v.table_schema=n.nspname and v.table_name=c.relname
    cross join (values ('anon'),('authenticated')) role_name(name)
    where c.relkind='v'
      and (
        pg_catalog.pg_get_viewdef(c.oid,true) ilike '%school_income_records%'
        or pg_catalog.pg_get_viewdef(c.oid,true) ilike '%school_subjects%'
        or pg_catalog.pg_get_viewdef(c.oid,true) ilike '%school_teachers%'
        or pg_catalog.pg_get_viewdef(c.oid,true) ilike '%school_settings%'
      )
      and (v.is_updatable='YES' or v.is_insertable_into='YES')
      and (
        pg_catalog.has_table_privilege(role_name.name,format('%I.%I',n.nspname,c.relname),'INSERT')
        or pg_catalog.has_table_privilege(role_name.name,format('%I.%I',n.nspname,c.relname),'UPDATE')
        or pg_catalog.has_table_privilege(role_name.name,format('%I.%I',n.nspname,c.relname),'DELETE')
      )
  ) then
    raise exception 'P1_B1A_UPDATABLE_VIEW_DML_BYPASS';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    cross join (values
      ('school_income_records'),('school_settings'),('school_subjects'),('school_teachers')
    ) target(name)
    where n.nspname='public'
      and lower(p.prosrc) like '%'||target.name||'%'
      and lower(p.prosrc) ~ (
        '(insert[[:space:]]+into|update|delete[[:space:]]+from)'
        ||'[[:space:][:alnum:]_.\"$]*'||target.name
      )
      and not p.prosecdef
  ) then
    raise exception 'P1_B1A_INVOKER_WRITER_DEPENDS_ON_CALLER_TABLE_DML';
  end if;
end;
$preflight$;

revoke insert,update,delete,truncate
  on table public.school_income_records,
           public.school_settings,
           public.school_subjects,
           public.school_teachers
  from public,anon,authenticated;

drop policy school_delete_non_tuition_income_records
  on public.school_income_records;
drop policy school_insert_non_tuition_income_records
  on public.school_income_records;
drop policy school_update_non_tuition_income_records
  on public.school_income_records;

drop policy school_allow_all_settings on public.school_settings;
create policy school_settings_public_select
  on public.school_settings
  for select
  to public
  using (true);

drop policy school_allow_all_subjects on public.school_subjects;
create policy school_subjects_public_select
  on public.school_subjects
  for select
  to public
  using (true);

drop policy school_allow_all_teachers on public.school_teachers;
create policy school_teachers_public_select
  on public.school_teachers
  for select
  to public
  using (true);

comment on policy school_settings_public_select on public.school_settings is
  'P1-B1A: preserve legacy/V2 reads while PUBLIC, anon and authenticated direct business DML is denied by table ACL.';
comment on policy school_subjects_public_select on public.school_subjects is
  'P1-B1A: preserve legacy/V2 reads while PUBLIC, anon and authenticated direct business DML is denied by table ACL.';
comment on policy school_teachers_public_select on public.school_teachers is
  'P1-B1A: preserve legacy/V2 reads while PUBLIC, anon and authenticated direct business DML is denied by table ACL.';

do $postdeploy$
declare
  v_table text;
begin
  foreach v_table in array array[
    'school_income_records',
    'school_settings',
    'school_subjects',
    'school_teachers'
  ] loop
    if not (
      pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'SELECT')
      and pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'SELECT')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'SELECT')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'INSERT')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'UPDATE')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'DELETE')
      and pg_catalog.has_table_privilege('service_role',format('%I.%I','public',v_table),'TRUNCATE')
    ) then
      raise exception 'P1_B1A_REQUIRED_READER_OR_BACKEND_PRIVILEGE_MISSING: %',v_table;
    end if;

    if pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'INSERT')
       or pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'UPDATE')
       or pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'DELETE')
       or pg_catalog.has_table_privilege('anon',format('%I.%I','public',v_table),'TRUNCATE')
       or pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'INSERT')
       or pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'UPDATE')
       or pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'DELETE')
       or pg_catalog.has_table_privilege('authenticated',format('%I.%I','public',v_table),'TRUNCATE') then
      raise exception 'P1_B1A_DIRECT_DML_STILL_EFFECTIVE: %',v_table;
    end if;
  end loop;

  if exists (
    select 1
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))
    ) acl
    where n.nspname='public'
      and c.relname in (
        'school_income_records','school_settings','school_subjects','school_teachers'
      )
      and acl.grantee=0
      and acl.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')
  ) then
    raise exception 'P1_B1A_PUBLIC_DIRECT_DML_STILL_GRANTED';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname='public'
      and tablename in (
        'school_income_records','school_settings','school_subjects','school_teachers'
      )
  ) <> 4 then
    raise exception 'P1_B1A_UNEXPECTED_POSTDEPLOY_POLICY_COUNT';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname='public'
      and tablename in (
        'school_income_records','school_settings','school_subjects','school_teachers'
      )
      and (
        cmd <> 'SELECT'
        or permissive <> 'PERMISSIVE'
        or roles <> array['public']::name[]
        or with_check is not null
      )
  ) then
    raise exception 'P1_B1A_NONSELECT_POLICY_REMAINS';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname='public'
      and tablename='school_income_records'
      and policyname='school_select_operational_income_records'
      and cmd='SELECT'
  ) or not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname='public'
      and tablename='school_settings'
      and policyname='school_settings_public_select'
      and cmd='SELECT' and qual='true'
  ) or not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname='public'
      and tablename='school_subjects'
      and policyname='school_subjects_public_select'
      and cmd='SELECT' and qual='true'
  ) or not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname='public'
      and tablename='school_teachers'
      and policyname='school_teachers_public_select'
      and cmd='SELECT' and qual='true'
  ) then
    raise exception 'P1_B1A_REQUIRED_SELECT_POLICY_MISSING';
  end if;
end;
$postdeploy$;

commit;
