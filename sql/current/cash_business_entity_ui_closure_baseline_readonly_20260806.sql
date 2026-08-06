-- Phase BE-UI Cash production baseline/reconciliation. SELECT only.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select object_name,row_count,row_hash
from (
  select 1 sort_order,'school_external_requests' object_name,count(*) row_count,
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.home_external_transaction_requests x
  where x.external_source='aozora_school'
  union all
  select 2,'school_cny_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_cny_transactions x where x.external_source='aozora_school'
  union all
  select 3,'school_jpy_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_jpy_transactions x where x.external_source='aozora_school'
) fingerprints
order by sort_order;

select external_reference_type,request_type,status,count(*) request_count
from public.home_external_transaction_requests
where external_source='aozora_school'
group by external_reference_type,request_type,status
order by external_reference_type,request_type,status;

select count(*) fixture_residue
from (
  select id from public.home_external_transaction_requests where id::text like '98000000-%'
  union all select id from public.home_cny_transactions where id::text like '98000000-%'
  union all select id from public.home_jpy_transactions where id::text like '98000000-%'
) residue;

select 'BE_UI_CASH_BASELINE_READONLY_PASS' result;
rollback;
