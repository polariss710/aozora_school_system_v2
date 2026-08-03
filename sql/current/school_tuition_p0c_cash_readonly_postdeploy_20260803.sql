\set ON_ERROR_STOP on
\pset pager off
-- Cash DB only: no writes. Confirm the synthetic/real protected references have no request or transaction.
select count(*) as p0c_fixture_cash_request_count
from public.home_external_transaction_requests
where external_source='aozora_school'
  and external_reference_type='school_income_records'
  and external_reference_id='c0c00000-0000-4000-8000-000000007101';
select
  (select count(*) from public.home_jpy_transactions
    where external_source='aozora_school' and external_reference_id='c0c00000-0000-4000-8000-000000007101')
  +
  (select count(*) from public.home_cny_transactions
    where external_source='aozora_school' and external_reference_id='c0c00000-0000-4000-8000-000000007101')
  as p0c_fixture_cash_transaction_count;
