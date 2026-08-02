-- Cash DB read-only non-interference verification for School tuition P0-A.
\set ON_ERROR_STOP on
\pset pager off
begin isolation level repeatable read read only;

select 'request' as object_name,count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) as full_hash
from public.home_external_transaction_requests t
union all
select 'cny_transaction',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.home_cny_transactions t
union all
select 'jpy_transaction',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.home_jpy_transactions t;

do $assertions$
begin
  if (select count(*) from public.home_external_transaction_requests)<>39
     or (select count(*) from public.home_cny_transactions)<>68
     or (select count(*) from public.home_jpy_transactions)<>31 then
    raise exception 'TUITION_P0A_CASH_COUNT_DRIFT';
  end if;
  if exists (
    select 1 from public.home_external_transaction_requests
    where to_jsonb(home_external_transaction_requests)::text like
      '%codex-test tuition-p0a-concurrency-20260803%'
    union all
    select 1 from public.home_cny_transactions
    where to_jsonb(home_cny_transactions)::text like
      '%codex-test tuition-p0a-concurrency-20260803%'
    union all
    select 1 from public.home_jpy_transactions
    where to_jsonb(home_jpy_transactions)::text like
      '%codex-test tuition-p0a-concurrency-20260803%'
  ) then raise exception 'TUITION_P0A_CASH_FIXTURE_RESIDUE'; end if;
end
$assertions$;

rollback;
