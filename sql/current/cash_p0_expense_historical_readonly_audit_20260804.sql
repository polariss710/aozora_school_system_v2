-- Cash side: ordinary-expense historical audit, 2026-08-04.
-- SELECT only. Do not call create/approve/reject RPCs from this file.
\set ON_ERROR_STOP on
\pset pager off

begin read only;

with expense_requests as (
  select *
  from public.home_external_transaction_requests
  where external_source = 'aozora_school'
    and external_reference_type = 'school_expense_records'
    and request_type = 'expense_paid'
), transaction_rows as (
  select id, user_id, currency, transaction_type, account_id, amount,
    external_source, external_source_id, external_event_type,
    external_reference_type, external_reference_id,
    external_idempotency_key, created_by_external
  from public.home_cny_transactions
  union all
  select id, user_id, currency, transaction_type, account_id, amount,
    external_source, external_source_id, external_event_type,
    external_reference_type, external_reference_id,
    external_idempotency_key, created_by_external
  from public.home_jpy_transactions
)
select
  count(*) as request_count,
  count(*) filter (where r.status = 'pending') as pending_count,
  count(*) filter (where r.status = 'approved') as approved_count,
  count(*) filter (where r.status = 'rejected') as rejected_count,
  count(*) filter (where r.status not in ('pending', 'approved', 'rejected'))
    as other_status_count,
  count(*) filter (where r.status = 'approved' and r.created_transaction_id is null)
    as approved_missing_transaction_id,
  count(*) filter (where r.status = 'rejected' and r.created_transaction_id is not null)
    as rejected_with_transaction_id,
  count(*) filter (where r.status = 'pending' and r.created_transaction_id is not null)
    as pending_with_transaction_id,
  count(*) filter (
    where r.created_transaction_id is not null and t.id is null
  ) as referenced_transaction_missing,
  count(*) filter (
    where t.id is not null
      and (
        t.user_id is distinct from r.user_id
        or t.amount is distinct from r.amount
        or t.currency is distinct from r.currency
        or t.transaction_type is distinct from r.transaction_type
        or t.account_id is distinct from r.account_id
        or t.external_source is distinct from r.external_source
        or t.external_source_id is distinct from r.external_event_id
        or t.external_event_type is distinct from r.request_type
        or t.external_reference_type is distinct from r.external_reference_type
        or t.external_reference_id is distinct from r.external_reference_id
        or t.external_idempotency_key is distinct from r.idempotency_key
        or t.created_by_external is distinct from true
      )
  ) as transaction_mismatch_count,
  count(*) filter (
    where r.status = 'pending'
      and r.requested_at < now() - interval '24 hours'
  ) as pending_older_than_24h,
  count(*) filter (
    where r.status = 'pending'
      and r.requested_at < now() - interval '7 days'
  ) as pending_older_than_7d
from expense_requests r
left join transaction_rows t on t.id = r.created_transaction_id;

select count(*) as duplicate_idempotency_groups
from (
  select idempotency_key
  from public.home_external_transaction_requests
  where external_source = 'aozora_school'
    and external_reference_type = 'school_expense_records'
    and request_type = 'expense_paid'
  group by idempotency_key
  having count(*) > 1
) duplicate_group;

select count(*) as duplicate_event_groups
from (
  select external_event_id
  from public.home_external_transaction_requests
  where external_source = 'aozora_school'
    and external_reference_type = 'school_expense_records'
    and request_type = 'expense_paid'
  group by external_event_id
  having count(*) > 1
) duplicate_group;

select count(*) as multiple_request_per_school_expense_groups
from (
  select external_reference_id
  from public.home_external_transaction_requests
  where external_source = 'aozora_school'
    and external_reference_type = 'school_expense_records'
    and request_type = 'expense_paid'
  group by external_reference_id
  having count(*) > 1
) duplicate_group;

with transaction_rows as (
  select id, external_idempotency_key, external_reference_id
  from public.home_cny_transactions
  where external_source = 'aozora_school'
    and external_reference_type = 'school_expense_records'
  union all
  select id, external_idempotency_key, external_reference_id
  from public.home_jpy_transactions
  where external_source = 'aozora_school'
    and external_reference_type = 'school_expense_records'
)
select
  count(*) filter (where transaction_count > 1) as request_with_multiple_transactions,
  count(*) filter (where request_id is null) as orphan_cash_transaction_count
from (
  select
    r.id as request_id,
    count(t.id) as transaction_count
  from public.home_external_transaction_requests r
  left join transaction_rows t
    on t.external_idempotency_key = r.idempotency_key
    and t.external_reference_id = r.external_reference_id
  where r.external_source = 'aozora_school'
    and r.external_reference_type = 'school_expense_records'
    and r.request_type = 'expense_paid'
  group by r.id

  union all

  select
    null::uuid as request_id,
    count(t.id) as transaction_count
  from transaction_rows t
  where not exists (
    select 1
    from public.home_external_transaction_requests r
    where r.external_source = 'aozora_school'
      and r.external_reference_type = 'school_expense_records'
      and r.request_type = 'expense_paid'
      and r.idempotency_key = t.external_idempotency_key
      and r.external_reference_id = t.external_reference_id
  )
  group by t.id
) linkage;

select
  r.id as cash_request_id,
  r.external_event_id,
  r.external_reference_id as school_expense_id,
  r.status,
  r.created_transaction_id,
  r.idempotency_key,
  r.currency,
  r.amount,
  r.account_id,
  r.transacted_at,
  r.requested_at,
  r.approved_at,
  r.rejected_at,
  r.payload_snapshot ->> 'school_expense_status' as school_status_snapshot,
  r.payload_snapshot ->> 'original_currency' as original_currency_snapshot,
  r.payload_snapshot ->> 'original_amount' as original_amount_snapshot,
  r.payload_snapshot ->> 'expense_category' as expense_category_snapshot,
  r.payload_snapshot ->> 'source_type' as source_type_snapshot,
  r.payload_snapshot ->> 'source_id' as source_id_snapshot
from public.home_external_transaction_requests r
where r.external_source = 'aozora_school'
  and r.external_reference_type = 'school_expense_records'
  and r.request_type = 'expense_paid'
order by r.created_at, r.id;

select
  count(*) filter (where id::text like 'e4100000-%') as fixture_request_residue,
  (
    select count(*)
    from public.home_cny_transactions
    where id::text like 'e4100000-%'
      or external_reference_id::text like 'e4100000-%'
  ) as fixture_cny_transaction_residue,
  (
    select count(*)
    from public.home_jpy_transactions
    where id::text like 'e4100000-%'
      or external_reference_id::text like 'e4100000-%'
  ) as fixture_jpy_transaction_residue
from public.home_external_transaction_requests;

select 'CASH_P0_EXPENSE_HISTORICAL_READONLY_AUDIT_PASS' as result;
rollback;
