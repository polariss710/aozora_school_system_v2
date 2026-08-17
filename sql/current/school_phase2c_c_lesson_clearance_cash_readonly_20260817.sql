-- Phase 2C-C production Cash baseline/zero-change probe. SELECT only.
\set ON_ERROR_STOP on
begin transaction read only;

select object_name,row_count,row_hash from (
  select 1 sort_order,'home_cny_transactions' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.home_cny_transactions x
  union all select 2,'home_external_transaction_requests',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_external_transaction_requests x
  union all select 3,'storage',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from storage.objects x
) fingerprints order by sort_order;

rollback;
