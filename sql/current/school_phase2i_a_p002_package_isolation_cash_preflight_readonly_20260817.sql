-- Phase 2I-A exact P002 Cash evidence and zero-change baseline. SELECT only.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

select to_jsonb(request_row) cash_request_fact,
  md5(to_jsonb(request_row)::text) cash_request_row_md5
from public.home_external_transaction_requests request_row
where request_row.id='a0bee5be-761b-4bc0-a666-411f033e1eba';
select to_jsonb(transaction_row) cash_transaction_fact,
  md5(to_jsonb(transaction_row)::text) cash_transaction_row_md5
from public.home_cny_transactions transaction_row
where transaction_row.id='f500dbe4-07a9-4a4d-ac99-e68592a8af6a';

select object_name,row_count,row_hash from (
  select 1 sort_order,'home_cny_transactions' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.home_cny_transactions x
  union all select 2,'home_jpy_transactions',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_jpy_transactions x
  union all select 3,'home_external_transaction_requests',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_external_transaction_requests x
  union all select 4,'home_accounts',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_accounts x
  union all select 5,'storage',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from storage.objects x
) fingerprints order by sort_order;

select count(*) open_related_transactions
from pg_stat_activity activity
where activity.datname=current_database() and activity.pid<>pg_backend_pid()
  and activity.xact_start is not null and activity.state<>'idle'
  and (activity.query ilike '%home_external_transaction_requests%'
    or activity.query ilike '%home_cny_transactions%');

rollback;
