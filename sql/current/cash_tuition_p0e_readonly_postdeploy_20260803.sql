\set ON_ERROR_STOP on
\pset pager off
begin read only;
select 'request' object_name,count(*) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) full_hash
from public.home_external_transaction_requests t
union all select 'cny_transaction',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.home_cny_transactions t
union all select 'jpy_transaction',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.home_jpy_transactions t;
do $verify$
begin
  if (select count(*) from public.home_external_transaction_requests)<>39
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.home_external_transaction_requests t)<>'303e10bc1a28a0abd8b27afd3929cfd8'
     or (select count(*) from public.home_cny_transactions)<>71
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.home_cny_transactions t)<>'d7e72182970de4ea8849c994b67e8dcc'
     or (select count(*) from public.home_jpy_transactions)<>31
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.home_jpy_transactions t)<>'95ab7cf8a8d167e9b052d3fc6b64614b' then
    raise exception 'P0E_CASH_BASELINE_DRIFT';
  end if;
  if exists(select 1 from public.home_external_transaction_requests where to_jsonb(home_external_transaction_requests)::text like '%tuition-p0e-forward-adjustment%')
     or exists(select 1 from public.home_cny_transactions where to_jsonb(home_cny_transactions)::text like '%tuition-p0e-forward-adjustment%')
     or exists(select 1 from public.home_jpy_transactions where to_jsonb(home_jpy_transactions)::text like '%tuition-p0e-forward-adjustment%') then
    raise exception 'P0E_CASH_MARKER_RESIDUE';
  end if;
end;
$verify$;
rollback;
