-- Cash DB companion baseline for School V2 tuition P0 R1A.
-- SELECT-only. R1A deploys no Cash DB object and performs no Cash write.

select
  'home_external_transaction_requests' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as business_hash
from public.home_external_transaction_requests t;

select
  'home_cny_transactions' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as business_hash
from public.home_cny_transactions t;

select
  'home_jpy_transactions' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as business_hash
from public.home_jpy_transactions t;
