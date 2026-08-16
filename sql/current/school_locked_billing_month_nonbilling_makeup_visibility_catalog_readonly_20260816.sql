-- R2 visibility diagnosis: catalog only, no writer calls.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

select c.oid::regclass relation_name,c.relrowsecurity,c.relforcerowsecurity,
       pg_get_userbyid(c.relowner) owner,coalesce(array_to_string(c.relacl,','),'') acl
from pg_class c
where c.oid='public.school_lesson_records'::regclass;

select grantee,privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='school_lesson_records'
  and grantee in ('anon','authenticated','service_role','postgres')
order by grantee,privilege_type;

select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
from pg_policies
where schemaname='public' and tablename='school_lesson_records'
order by policyname;

select role_name,
       has_table_privilege(role_name,'public.school_lesson_records','SELECT') can_select,
       has_table_privilege(role_name,'public.school_lesson_records','INSERT') can_insert,
       has_table_privilege(role_name,'public.school_lesson_records','UPDATE') can_update,
       has_table_privilege(role_name,'public.school_lesson_records','DELETE') can_delete
from unnest(array['anon','authenticated','service_role','postgres']) role_name;

select p.oid::regprocedure signature,md5(pg_get_functiondef(p.oid)) definition_md5,
       pg_get_userbyid(p.proowner) owner,p.prosecdef,
       coalesce(array_to_string(p.proconfig,','),'') settings,
       coalesce(array_to_string(p.proacl,','),'') acl,
       pg_get_functiondef(p.oid) definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'school_list_lesson_management_records_authoritative',
  'school_create_lesson_credit_makeup_actual'
) order by p.oid::regprocedure::text;

select 'SCHOOL_LOCKED_MAKEUP_VISIBILITY_CATALOG_READONLY_PASS' result;
rollback;
