\set ON_ERROR_STOP on
\pset pager off
begin read only;
select 'request' object_name,count(*) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) full_hash
from public.home_external_transaction_requests t
union all
select 'cny_transaction',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.home_cny_transactions t
union all
select 'jpy_transaction',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.home_jpy_transactions t;
do $verify$
begin
  if (select count(*) from public.home_external_transaction_requests)<>39
     or (select count(*) from public.home_cny_transactions)<>68
     or (select count(*) from public.home_jpy_transactions)<>31 then
    raise exception 'P0B1_CASH_COUNT_DRIFT';
  end if;
  if exists(select 1 from public.home_external_transaction_requests
            where to_jsonb(home_external_transaction_requests)::text like '%tuition-p0b1-lesson-authority-20260803%')
     or exists(select 1 from public.home_cny_transactions
            where to_jsonb(home_cny_transactions)::text like '%tuition-p0b1-lesson-authority-20260803%')
     or exists(select 1 from public.home_jpy_transactions
            where to_jsonb(home_jpy_transactions)::text like '%tuition-p0b1-lesson-authority-20260803%') then
    raise exception 'P0B1_CASH_MARKER_RESIDUE';
  end if;
end
$verify$;
rollback;
