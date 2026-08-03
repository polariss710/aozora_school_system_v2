-- P0-G1-A membership schema read-only verification.
\set ON_ERROR_STOP on
\pset pager off

select c.column_name,c.data_type,c.is_nullable,c.column_default
from information_schema.columns c
where c.table_schema='public' and c.table_name='school_app_memberships'
order by c.ordinal_position;

select con.conname,pg_get_constraintdef(con.oid,true) definition
from pg_constraint con
where con.conrelid='public.school_app_memberships'::regclass
order by con.conname;

select indexname,indexdef
from pg_indexes
where schemaname='public' and tablename='school_app_memberships'
order by indexname;

select c.relrowsecurity,c.relforcerowsecurity,
  coalesce(array_to_string(c.relacl,','),'NULL_DEFAULT_ACL') raw_acl
from pg_class c
where c.oid='public.school_app_memberships'::regclass;

select role_name,
  has_table_privilege(role_name,'public.school_app_memberships','SELECT') can_select,
  has_table_privilege(role_name,'public.school_app_memberships','INSERT') can_insert,
  has_table_privilege(role_name,'public.school_app_memberships','UPDATE') can_update,
  has_table_privilege(role_name,'public.school_app_memberships','DELETE') can_delete
from (values ('anon'),('authenticated'),('service_role')) roles(role_name)
order by role_name;

select count(*) as bootstrap_membership_count
from public.school_app_memberships;
