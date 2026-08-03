\set ON_ERROR_STOP on
\pset pager off
begin read only;

select 'cash_request' object_name,count(*) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) full_hash
from public.home_external_transaction_requests t
union all select 'cny_transaction',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.home_cny_transactions t
union all select 'jpy_transaction',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.home_jpy_transactions t
order by object_name;

select count(*) as p0f_cash_fact_count
from (
  select id from public.home_external_transaction_requests
  where to_jsonb(home_external_transaction_requests)::text like '%tuition-p0f%'
  union all
  select id from public.home_cny_transactions
  where to_jsonb(home_cny_transactions)::text like '%tuition-p0f%'
  union all
  select id from public.home_jpy_transactions
  where to_jsonb(home_jpy_transactions)::text like '%tuition-p0f%'
) facts;

rollback;
