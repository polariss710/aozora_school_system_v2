-- Phase 2C-D2-A2 final Cash evidence. SELECT only.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

select object_name,row_count,row_hash from (
  select 1 n,'home_cny_transactions' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash from public.home_cny_transactions x
  union all select 2,'home_jpy_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.home_jpy_transactions x
  union all select 3,'home_external_transaction_requests',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.home_external_transaction_requests x
  union all select 4,'home_accounts',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.home_accounts x
  union all select 5,'storage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from storage.objects x
) evidence order by n;

select count(*) open_related_transactions
from pg_stat_activity activity
where activity.datname=current_database() and activity.pid<>pg_backend_pid()
  and activity.xact_start is not null and activity.state<>'idle'
  and (activity.query ilike '%home_external_transaction_requests%'
    or activity.query ilike '%home_cny_transactions%'
    or activity.query ilike '%home_jpy_transactions%');

rollback;
