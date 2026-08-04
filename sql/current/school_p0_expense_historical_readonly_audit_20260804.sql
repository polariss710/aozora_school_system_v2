-- School side: ordinary-expense Cash historical audit, 2026-08-04.
-- SELECT only. Do not call writers or repair any record from this file.
\set ON_ERROR_STOP on
\pset pager off

begin read only;

select
  case
    when expense_category = 'teacher_wage' or source_type = 'teacher_wage'
      then 'teacher_wage'
    else 'ordinary'
  end as expense_route,
  status,
  coalesce(cash_request_status, '(null)') as cash_request_status,
  count(*) as expense_count
from public.school_expense_records
where app_type = 'school'
group by 1, 2, 3
order by 1, 2, 3;

select
  count(*) filter (where status = 'pending') as pending_count,
  count(*) filter (where status = 'pending' and cash_request_status = 'pending_cash_request')
    as pending_cash_request_count,
  count(*) filter (where status = 'paid') as paid_count,
  count(*) filter (where status = 'rejected' or cash_request_status = 'rejected')
    as rejected_count,
  count(*) filter (
    where status = 'pending'
      and not (expense_category = 'teacher_wage' or source_type = 'teacher_wage')
      and reversed_at is null
      and reversal_account_transaction_id is null
      and cash_transaction_id is null
      and coalesce(cash_request_status, '') not in ('pending', 'approved', 'synced')
  ) as ordinary_cash_requestable_count
from public.school_expense_records
where app_type = 'school';

select
  count(*) filter (
    where cash_request_status is not null
      or cash_request_id is not null
      or cash_request_event_id is not null
      or cash_transaction_id is not null
  ) as any_cash_link_count,
  count(*) filter (
    where cash_request_status = 'pending_cash_request'
      and cash_request_event_id is null
  ) as pending_attempt_missing_event,
  count(*) filter (
    where cash_request_status in ('pending', 'approved', 'rejected', 'synced')
      and cash_request_id is null
  ) as terminal_or_submitted_missing_request,
  count(*) filter (
    where cash_transaction_id is not null
      and cash_request_id is null
  ) as transaction_missing_request,
  count(*) filter (
    where cash_request_status in ('approved', 'synced')
      and (status <> 'paid' or cash_transaction_id is null)
  ) as approved_not_paid_or_missing_transaction,
  count(*) filter (
    where status = 'paid'
      and cash_request_id is not null
      and cash_request_status not in ('approved', 'synced')
  ) as paid_but_request_not_approved,
  count(*) filter (
    where cash_request_status = 'rejected'
      and (cash_transaction_id is not null or status = 'paid')
  ) as rejected_but_paid_or_has_transaction,
  count(*) filter (
    where cash_request_status = 'rejected'
      and cash_synced_at is null
  ) as rejected_missing_sync_timestamp
from public.school_expense_records
where app_type = 'school';

select count(*) as duplicate_event_groups
from (
  select cash_request_event_id
  from public.school_expense_records
  where app_type = 'school'
    and cash_request_event_id is not null
  group by cash_request_event_id
  having count(*) > 1
) duplicate_group;

select count(*) as duplicate_request_groups
from (
  select cash_request_id
  from public.school_expense_records
  where app_type = 'school'
    and cash_request_id is not null
  group by cash_request_id
  having count(*) > 1
) duplicate_group;

select count(*) as duplicate_transaction_groups
from (
  select cash_transaction_id
  from public.school_expense_records
  where app_type = 'school'
    and cash_transaction_id is not null
  group by cash_transaction_id
  having count(*) > 1
) duplicate_group;

select
  count(*) filter (
    where e.status = 'paid'
      and e.cash_transaction_id is null
      and not (e.expense_category = 'teacher_wage' or e.source_type = 'teacher_wage')
      and (
        e.account_id is null
        or a.id is null
        or ledger.expense_adjust_count <> 1
        or ledger.expense_adjust_amount is distinct from -e.amount
      )
  ) as ordinary_school_paid_ledger_orphan_count,
  count(*) filter (
    where e.cash_transaction_id is not null
      and ledger.school_ledger_count <> 0
  ) as cash_linked_with_school_ledger_count
from public.school_expense_records e
left join public.school_accounts a on a.id = e.account_id
left join lateral (
  select
    count(*) filter (where t.transaction_type = 'expense_adjust') as expense_adjust_count,
    max(t.amount) filter (where t.transaction_type = 'expense_adjust') as expense_adjust_amount,
    count(*) as school_ledger_count
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = e.id
    and t.app_type = 'school'
) ledger on true
where e.app_type = 'school';

select
  count(*) as teacher_wage_expense_count,
  count(*) filter (where w.id is null) as missing_wage_lock_count,
  count(*) filter (
    where w.id is not null
      and (
        e.teacher_id is distinct from w.teacher_id
        or e.business_entity_id is distinct from w.business_entity_id
        or e.year_month is distinct from w.settlement_month
        or e.currency is distinct from 'JPY'
        or e.amount is distinct from w.total_jpy
      )
  ) as wage_snapshot_mismatch_count,
  count(*) filter (where e.status = 'pending' and e.cash_request_id is null)
    as pending_not_submitted_count,
  count(*) filter (
    where e.status = 'paid'
      and e.cash_request_status in ('approved', 'synced')
      and e.cash_transaction_id is not null
  ) as paid_cash_complete_count
from public.school_expense_records e
left join public.school_teacher_wage_locks w on w.id = e.source_id
where e.app_type = 'school'
  and (e.expense_category = 'teacher_wage' or e.source_type = 'teacher_wage');

select
  id as school_expense_id,
  expense_category,
  source_type,
  status,
  cash_request_status,
  cash_request_event_id,
  cash_request_attempt_no,
  cash_request_id,
  cash_transaction_id,
  currency,
  amount,
  cash_payment_currency,
  cash_payment_amount,
  business_entity_id,
  account_id,
  created_at,
  cash_requested_at,
  cash_synced_at
from public.school_expense_records
where app_type = 'school'
  and (
    cash_request_status is not null
    or cash_request_id is not null
    or cash_request_event_id is not null
    or cash_transaction_id is not null
  )
order by created_at, id;

select
  count(*) as preclosure_expense_count,
  count(*) filter (where created_at < timestamptz '2026-08-04 00:00:00+09')
    as definitely_preclosure_count,
  count(*) filter (where created_at >= timestamptz '2026-08-04 00:00:00+09')
    as closure_day_count,
  count(*) filter (where created_at is null) as missing_created_at_count,
  false as creator_identity_recorded
from public.school_expense_records
where app_type = 'school';

select
  count(*) filter (
    where id::text like 'e4100000-%'
      or note = 'codex-test p0-expense rollback-only'
  ) as fixture_expense_residue,
  (
    select count(*) from public.school_accounts
    where id::text like 'e4100000-%'
      or note = 'codex-test p0-expense rollback-only'
  )
    as fixture_account_residue,
  (
    select count(*) from public.school_account_transactions
    where id::text like 'e4100000-%'
      or account_id::text like 'e4100000-%'
      or related_id::text like 'e4100000-%'
      or note = 'codex-test p0-expense rollback-only'
  )
    as fixture_transaction_residue
from public.school_expense_records;

select 'SCHOOL_P0_EXPENSE_HISTORICAL_READONLY_AUDIT_PASS' as result;
rollback;
