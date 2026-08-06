-- Cash-side read-only fingerprint for the School lesson writer P0 phase.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;
select object_name,row_count,row_hash from (
  select 1 sort_order,'school_external_requests' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.home_external_transaction_requests x where x.external_source='aozora_school'
  union all
  select 2,'school_cny_transactions',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_cny_transactions x where x.external_source='aozora_school'
  union all
  select 3,'school_jpy_transactions',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.home_jpy_transactions x where x.external_source='aozora_school'
) fingerprints order by sort_order;

with target(id) as (values
  ('f759623b-ce28-4c5f-8556-95c4381b6b1b'),
  ('dc06b98c-360f-4661-a294-52ecb82830a7'),
  ('c582a187-32f6-4a24-bb7b-d590b25c1854'),
  ('39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'),
  ('1a370095-dd14-444f-8ffb-778e92e03c88'),
  ('d4e3e060-1951-4fdd-9340-e6feb6687b7f'),
  ('9d26220e-813a-43da-b48d-1e34cfa9324e')
)
select
  (select count(*) from public.home_external_transaction_requests x,target t
    where position(t.id in to_jsonb(x)::text)>0) request_references,
  (select count(*) from public.home_cny_transactions x,target t
    where position(t.id in to_jsonb(x)::text)>0) cny_references,
  (select count(*) from public.home_jpy_transactions x,target t
    where position(t.id in to_jsonb(x)::text)>0) jpy_references;
select 'LESSON_WRITER_P0_CASH_BASELINE_READONLY_PASS' result;
rollback;
