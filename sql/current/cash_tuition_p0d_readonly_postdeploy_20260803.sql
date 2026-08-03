\set ON_ERROR_STOP on
\pset pager off
begin read only;
select count(*) request_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) request_hash
from public.home_external_transaction_requests t;
select count(*) cny_transaction_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) cny_hash
from public.home_cny_transactions t;
select count(*) jpy_transaction_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) jpy_hash
from public.home_jpy_transactions t;
select count(*) p0d_fixture_cash_fact_count from (
  select id from public.home_external_transaction_requests where coalesce(note,'') ilike '%tuition-p0d-e2e-readiness-20260803%'
  union all select id from public.home_cny_transactions where coalesce(note,'') ilike '%tuition-p0d-e2e-readiness-20260803%'
  union all select id from public.home_jpy_transactions where coalesce(note,'') ilike '%tuition-p0d-e2e-readiness-20260803%'
) x;
rollback;
