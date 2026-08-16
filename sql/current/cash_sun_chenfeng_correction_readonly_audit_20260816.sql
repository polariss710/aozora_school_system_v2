-- Cash database is out of the write scope; this file is read-only evidence.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

select object_name,row_count,row_hash from (
  select 1 sort_order,'external_requests' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.home_external_transaction_requests x
  union all select 2,'cny_transactions',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_cny_transactions x
  union all select 3,'jpy_transactions',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_jpy_transactions x
  union all select 4,'accounts',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_accounts x
) f order by sort_order;

select 'target_cash_request' object_name,count(*) row_count,
       max(md5(to_jsonb(x)::text)) row_hash
from public.home_external_transaction_requests x
where x.id='b0baf105-c98f-4b8d-ae23-1f9f6e35ac44'::uuid
union all select 'target_cash_transaction',count(*),max(md5(to_jsonb(x)::text))
from public.home_cny_transactions x
where x.id='c37665ea-e8bc-4b90-859c-292ef37c35eb'::uuid;

select 'CASH_SUN_CHENFENG_CORRECTION_READONLY_AUDIT_PASS' result;
rollback;
