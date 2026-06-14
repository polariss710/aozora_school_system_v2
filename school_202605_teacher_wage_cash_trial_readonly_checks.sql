-- school_202605_teacher_wage_cash_trial_readonly_checks.sql
-- Purpose:
-- - Read-only preflight checks before the real 2026-05 teacher_wage Cash trial.
-- - This file contains two independent sections:
--   1) School DB checks
--   2) Cash DB checks
--
-- Usage:
--   School DB:
--     psql "<school-db-url>" -v ON_ERROR_STOP=1 -v run_school=true -v run_cash=false -f school_202605_teacher_wage_cash_trial_readonly_checks.sql
--
--   Cash DB:
--     psql "<cash-db-url>" -v ON_ERROR_STOP=1 -v run_school=false -v run_cash=true -f school_202605_teacher_wage_cash_trial_readonly_checks.sql
--
-- Safety:
-- - Do not run both sections against one DB.
-- - This file is intentionally SELECT-only, plus psql meta commands.
-- - It does not approve, reject, retry, rollback, insert, update, delete, or call RPCs.

\if :run_school

\echo '=== School DB: 2026-05 teacher_wage Cash trial read-only checks ==='

select
  'school:target_payment_request_summary' as check_name,
  count(*) as request_count,
  count(*) filter (where p.status = 'pending') as pending_count,
  count(*) filter (where p.status = 'paid') as paid_count,
  count(*) filter (where p.status = 'cancelled') as cancelled_count,
  count(*) filter (where p.status = 'reversed') as reversed_count,
  count(*) filter (where p.currency = 'JPY') as jpy_currency_count,
  count(*) filter (where p.currency = 'CNY') as cny_currency_count,
  coalesce(sum(p.amount) filter (where p.currency = 'JPY'), 0) as jpy_amount_total,
  coalesce(sum(p.amount_cny) filter (where coalesce(p.amount_cny, 0) > 0), 0) as cny_amount_total_snapshot,
  coalesce(sum(p.amount_jpy), 0) as school_amount_jpy_total
from public.school_payment_requests p
where p.source_type = 'teacher_wage'
  and p.request_month = '2026-05';

select
  'school:target_payment_request_detail' as check_name,
  p.id as payment_request_id,
  p.source_id as wage_lock_id,
  p.payee_id as teacher_id,
  p.payee_name as teacher_name,
  p.business_entity_id,
  p.business_name,
  b.entity_type,
  p.request_month,
  p.currency,
  p.amount,
  p.amount_jpy,
  p.amount_cny,
  p.status,
  p.paid_at,
  p.paid_expense_id,
  p.paid_account_transaction_id,
  p.account_id,
  p.created_at,
  p.updated_at
from public.school_payment_requests p
left join public.school_business_entities b
  on b.id = p.business_entity_id
where p.source_type = 'teacher_wage'
  and p.request_month = '2026-05'
order by p.payee_name, p.business_name, p.created_at, p.id;

with historical_void_requests as (
  select
    p.id as payment_request_id,
    p.source_id as wage_lock_id,
    p.payee_name as teacher_name,
    p.business_name,
    p.currency,
    p.amount,
    p.amount_jpy,
    p.amount_cny,
    p.status,
    w.status as wage_lock_status,
    w.voided_at,
    w.void_reason
  from public.school_payment_requests p
  left join public.school_teacher_wage_locks w
    on w.id = p.source_id
  where p.source_type = 'teacher_wage'
    and p.request_month = '2026-05'
    and p.status = 'void'
)
select
  'school:historical_void_requests_summary' as check_name,
  count(*) as void_request_count,
  count(*) filter (where currency = 'JPY') as jpy_count,
  count(*) filter (where currency = 'CNY') as cny_count,
  coalesce(sum(amount) filter (where currency = 'JPY'), 0) as jpy_amount_total,
  coalesce(sum(amount) filter (where currency = 'CNY'), 0) as cny_amount_total,
  coalesce(sum(amount_jpy), 0) as school_amount_jpy_total,
  count(*) filter (where nullif(trim(coalesce(void_reason, '')), '') is not null) as with_void_reason_count,
  min(voided_at) as first_voided_at,
  max(voided_at) as last_voided_at
from historical_void_requests;

with historical_void_requests as (
  select
    p.id as payment_request_id,
    p.source_id as wage_lock_id,
    p.payee_name as teacher_name,
    p.business_name,
    p.currency,
    p.amount,
    p.amount_jpy,
    p.amount_cny,
    p.status,
    w.status as wage_lock_status,
    w.voided_at,
    w.void_reason
  from public.school_payment_requests p
  left join public.school_teacher_wage_locks w
    on w.id = p.source_id
  where p.source_type = 'teacher_wage'
    and p.request_month = '2026-05'
    and p.status = 'void'
)
select
  'school:historical_void_requests_detail' as check_name,
  payment_request_id,
  wage_lock_id,
  teacher_name,
  business_name,
  amount,
  amount_jpy,
  amount_cny,
  currency,
  status,
  wage_lock_status,
  voided_at,
  void_reason
from historical_void_requests
order by teacher_name, business_name, voided_at, payment_request_id;

with duplicate_requests as (
  select
    p.source_id as wage_lock_id,
    count(*) as request_count,
    array_agg(p.id order by p.created_at, p.id) as payment_request_ids,
    array_agg(p.status order by p.created_at, p.id) as statuses
  from public.school_payment_requests p
  where p.source_type = 'teacher_wage'
    and p.request_month = '2026-05'
  group by p.source_id
  having count(*) > 1
)
select
  'school:duplicate_payment_requests_by_wage_lock' as check_name,
  *
from duplicate_requests
order by request_count desc, wage_lock_id;

with target_requests as (
  select p.*
  from public.school_payment_requests p
  where p.source_type = 'teacher_wage'
    and p.request_month = '2026-05'
),
blocking_target_requests as (
  select *
  from target_requests
  where status is distinct from 'void'
),
anomalies as (
  select
    'missing_or_mismatched_wage_lock' as issue,
    p.id as payment_request_id,
    p.source_id as wage_lock_id,
    p.payee_name,
    p.business_name,
    p.status,
    p.amount,
    p.amount_jpy,
    w.total_jpy,
    w.status as wage_lock_status,
    w.voided_at,
    case
      when w.id is null then 'payment request source wage lock not found'
      when w.settlement_month is distinct from p.request_month then 'wage lock month differs from request month'
      when w.teacher_id is distinct from p.payee_id then 'teacher differs from wage lock'
      when w.business_entity_id is distinct from p.business_entity_id then 'business entity differs from wage lock'
      when round(coalesce(w.total_jpy, 0)) is distinct from coalesce(p.amount_jpy, p.amount) then 'amount differs from wage lock total_jpy'
      when coalesce(w.status, '') <> 'locked' then 'wage lock is not locked'
      when w.voided_at is not null then 'wage lock is voided'
      else 'unknown'
    end as detail
  from blocking_target_requests p
  left join public.school_teacher_wage_locks w
    on w.id = p.source_id
  where w.id is null
     or w.settlement_month is distinct from p.request_month
     or w.teacher_id is distinct from p.payee_id
     or w.business_entity_id is distinct from p.business_entity_id
     or round(coalesce(w.total_jpy, 0)) is distinct from coalesce(p.amount_jpy, p.amount)
     or coalesce(w.status, '') <> 'locked'
     or w.voided_at is not null
  union all
  select
    'invalid_payment_request_required_fields' as issue,
    p.id,
    p.source_id,
    p.payee_name,
    p.business_name,
    p.status,
    p.amount,
    p.amount_jpy,
    null::numeric as total_jpy,
    null::text as wage_lock_status,
    null::timestamptz as voided_at,
    concat_ws(
      '; ',
      case when p.id is null then 'id is null' end,
      case when p.source_id is null then 'source_id is null' end,
      case when p.payee_id is null then 'payee_id is null' end,
      case when nullif(trim(coalesce(p.payee_name, '')), '') is null then 'payee_name blank' end,
      case when p.business_entity_id is null then 'business_entity_id is null' end,
      case when nullif(trim(coalesce(p.business_name, '')), '') is null then 'business_name blank' end,
      case when p.currency is null then 'currency is null' end,
      case when p.currency not in ('JPY', 'CNY') then 'currency not JPY/CNY' end,
      case when coalesce(p.amount, 0) <= 0 then 'amount <= 0' end,
      case when coalesce(p.amount_jpy, 0) <= 0 then 'amount_jpy <= 0' end,
      case when p.status not in ('pending', 'paid', 'cancelled', 'reversed') then 'unexpected status' end
    ) as detail
  from blocking_target_requests p
  where p.source_id is null
     or p.payee_id is null
     or nullif(trim(coalesce(p.payee_name, '')), '') is null
     or p.business_entity_id is null
     or nullif(trim(coalesce(p.business_name, '')), '') is null
     or p.currency is null
     or p.currency not in ('JPY', 'CNY')
     or coalesce(p.amount, 0) <= 0
     or coalesce(p.amount_jpy, 0) <= 0
     or p.status not in ('pending', 'paid', 'cancelled', 'reversed')
  union all
  select
    'paid_status_without_cash_synced_event' as issue,
    p.id,
    p.source_id,
    p.payee_name,
    p.business_name,
    p.status,
    p.amount,
    p.amount_jpy,
    null::numeric,
    null::text,
    null::timestamptz,
    'paid teacher_wage request has no synced Cash linkage event'
  from target_requests p
  where p.status = 'paid'
    and not exists (
      select 1
      from public.school_personal_cash_linkage_events e
      where e.payment_request_id = p.id
        and e.source_table = 'school_payment_requests'
        and e.source_event_type = 'teacher_wage_payment_confirm'
        and e.sync_status = 'synced'
        and e.cash_request_status = 'approved'
        and e.cash_transaction_id is not null
    )
  union all
  select
    'pending_status_with_synced_cash_event' as issue,
    p.id,
    p.source_id,
    p.payee_name,
    p.business_name,
    p.status,
    p.amount,
    p.amount_jpy,
    null::numeric,
    null::text,
    null::timestamptz,
    'pending teacher_wage request already has synced approved Cash linkage event'
  from target_requests p
  where p.status = 'pending'
    and exists (
      select 1
      from public.school_personal_cash_linkage_events e
      where e.payment_request_id = p.id
        and e.source_table = 'school_payment_requests'
        and e.source_event_type = 'teacher_wage_payment_confirm'
        and e.sync_status = 'synced'
        and e.cash_request_status = 'approved'
        and e.cash_transaction_id is not null
    )
)
select *
from anomalies
order by issue, payee_name, payment_request_id;

with active_attempts as (
  select
    e.payment_request_id,
    count(*) as active_attempt_count,
    array_agg(e.id order by e.created_at, e.id) as active_event_ids,
    array_agg(e.attempt_no order by e.created_at, e.id) as active_attempt_nos
  from public.school_personal_cash_linkage_events e
  join public.school_payment_requests p
    on p.id = e.payment_request_id
  where p.source_type = 'teacher_wage'
    and p.request_month = '2026-05'
    and e.source_table = 'school_payment_requests'
    and e.source_event_type = 'teacher_wage_payment_confirm'
    and e.sync_status in ('pending_cash_request', 'awaiting_cash_confirmation')
  group by e.payment_request_id
)
select
  'school:active_attempts_before_trial' as check_name,
  *
from active_attempts
order by active_attempt_count desc, payment_request_id;

with duplicate_active_attempts as (
  select *
  from (
    select
      e.source_table,
      e.source_id,
      e.source_event_type,
      count(*) as active_attempt_count,
      array_agg(e.id order by e.created_at, e.id) as event_ids,
      array_agg(e.attempt_no order by e.created_at, e.id) as attempt_nos
    from public.school_personal_cash_linkage_events e
    join public.school_payment_requests p
      on p.id = e.payment_request_id
    where p.source_type = 'teacher_wage'
      and p.request_month = '2026-05'
      and e.sync_status in ('pending_cash_request', 'awaiting_cash_confirmation')
    group by e.source_table, e.source_id, e.source_event_type
  ) x
  where x.active_attempt_count > 1
)
select
  'school:duplicate_active_attempts' as check_name,
  *
from duplicate_active_attempts
order by active_attempt_count desc, source_id;

with attempt_sequence as (
  select
    e.payment_request_id,
    e.id as linkage_event_id,
    e.attempt_no,
    row_number() over (
      partition by e.payment_request_id
      order by e.attempt_no, e.created_at, e.id
    ) as expected_attempt_no,
    e.sync_status,
    e.cash_request_status,
    e.cash_request_id,
    e.cash_transaction_id,
    e.created_at
  from public.school_personal_cash_linkage_events e
  join public.school_payment_requests p
    on p.id = e.payment_request_id
  where p.source_type = 'teacher_wage'
    and p.request_month = '2026-05'
    and e.source_table = 'school_payment_requests'
    and e.source_event_type = 'teacher_wage_payment_confirm'
)
select
  'school:attempt_no_gaps_or_duplicates' as check_name,
  *
from attempt_sequence
where attempt_no is distinct from expected_attempt_no
order by payment_request_id, attempt_no, created_at;

with linkage_anomalies as (
  select
    e.id as linkage_event_id,
    e.payment_request_id,
    p.payee_name,
    p.business_name,
    e.sync_status,
    e.cash_request_status,
    e.attempt_no,
    e.cash_request_id,
    e.cash_transaction_id,
    e.currency,
    e.amount,
    e.school_amount_jpy,
    e.payment_currency,
    e.payment_exchange_rate,
    e.payment_amount,
    case
      when e.sync_status = 'cash_rejected' and p.status <> 'pending' then 'rejected attempt but School payment request is not pending'
      when e.sync_status = 'cash_rejected' and e.cash_transaction_id is not null then 'rejected attempt has Cash transaction id'
      when e.sync_status = 'cash_rejected' and e.rejected_at is null then 'rejected attempt missing rejected_at'
      when e.sync_status = 'synced' and p.status <> 'paid' then 'synced event but School payment request is not paid'
      when e.sync_status = 'synced' and e.cash_request_status <> 'approved' then 'synced event not marked approved'
      when e.sync_status = 'synced' and e.cash_transaction_id is null then 'synced event missing Cash transaction id'
      when e.sync_status in ('pending_cash_request', 'awaiting_cash_confirmation') and e.cash_transaction_id is not null then 'active attempt already has Cash transaction id'
      when e.payment_currency not in ('JPY', 'CNY') then 'invalid payment_currency'
      when e.payment_currency = 'JPY' and e.cash_transaction_table <> 'home_jpy_transactions' then 'JPY event points to non-JPY transaction table'
      when e.payment_currency = 'CNY' and e.cash_transaction_table <> 'home_cny_transactions' then 'CNY event points to non-CNY transaction table'
      when e.payment_currency = 'JPY' and coalesce(e.payment_exchange_rate, 1) <> 1 then 'JPY event exchange rate is not 1'
      when e.payment_currency = 'JPY' and e.payment_amount is distinct from e.school_amount_jpy then 'JPY event payment amount differs from School JPY amount'
      when e.payment_currency = 'CNY' and coalesce(e.payment_exchange_rate, 0) <= 0 then 'CNY event missing positive exchange rate'
      when coalesce(e.payment_amount, 0) <= 0 then 'payment_amount <= 0'
      when coalesce(e.school_amount_jpy, e.amount, 0) <= 0 then 'school_amount_jpy/amount <= 0'
      else null
    end as issue
  from public.school_personal_cash_linkage_events e
  join public.school_payment_requests p
    on p.id = e.payment_request_id
  where p.source_type = 'teacher_wage'
    and p.request_month = '2026-05'
    and e.source_table = 'school_payment_requests'
    and e.source_event_type = 'teacher_wage_payment_confirm'
)
select
  'school:cash_linkage_event_anomalies' as check_name,
  *
from linkage_anomalies
where issue is not null
order by issue, payee_name, linkage_event_id;

select
  'school:cash_linkage_event_history' as check_name,
  e.payment_request_id,
  p.payee_name,
  p.business_name,
  p.status as payment_status,
  e.id as linkage_event_id,
  e.attempt_no,
  e.sync_status,
  e.cash_request_status,
  e.cash_request_id,
  e.cash_transaction_id,
  e.currency,
  e.amount,
  e.school_amount_jpy,
  e.payment_currency,
  e.payment_exchange_rate,
  e.payment_amount,
  e.cash_account_id,
  e.cash_account_name_snapshot,
  e.cash_account_type_snapshot,
  e.requested_at,
  e.confirmed_at,
  e.rejected_at,
  e.rejected_reason,
  e.idempotency_key,
  e.created_at,
  e.updated_at
from public.school_personal_cash_linkage_events e
join public.school_payment_requests p
  on p.id = e.payment_request_id
where p.source_type = 'teacher_wage'
  and p.request_month = '2026-05'
  and e.source_table = 'school_payment_requests'
  and e.source_event_type = 'teacher_wage_payment_confirm'
order by p.payee_name, p.business_name, e.attempt_no, e.created_at, e.id;

select
  'school:suggested_small_batch_candidates' as check_name,
  p.id as payment_request_id,
  p.source_id as wage_lock_id,
  p.payee_name as teacher_name,
  p.business_name,
  b.entity_type,
  p.currency,
  p.amount,
  p.amount_jpy,
  p.amount_cny,
  p.status,
  p.created_at
from public.school_payment_requests p
left join public.school_business_entities b
  on b.id = p.business_entity_id
where p.source_type = 'teacher_wage'
  and p.request_month = '2026-05'
  and p.status = 'pending'
  and not exists (
    select 1
    from public.school_personal_cash_linkage_events e
    where e.payment_request_id = p.id
      and e.source_table = 'school_payment_requests'
      and e.source_event_type = 'teacher_wage_payment_confirm'
      and e.sync_status in ('pending_cash_request', 'awaiting_cash_confirmation', 'synced')
  )
order by
  case when b.entity_type = 'personal' then 0 else 1 end,
  p.amount asc,
  p.payee_name,
  p.id
limit 20;

\endif

\if :run_cash

\echo '=== Cash DB: 2026-05 teacher_wage Cash trial read-only checks ==='

select
  'cash:school_eligible_account_whitelist' as check_name,
  id as cash_account_id,
  name,
  currency,
  account_type,
  is_active,
  allow_school_requests,
  sort_order
from public.home_accounts
where name in ('余额宝', '日元现金', '日元三菱卡', '日元乐天卡', '余利宝', '医生处兑换日元先行支付')
order by allow_school_requests desc, currency, sort_order, name;

with expected_accounts(name, currency, should_allow) as (
  values
    ('余额宝'::text, 'CNY'::text, true),
    ('日元现金'::text, 'JPY'::text, true),
    ('日元三菱卡'::text, 'JPY'::text, true),
    ('日元乐天卡'::text, 'JPY'::text, true),
    ('余利宝'::text, null::text, false),
    ('医生处兑换日元先行支付'::text, null::text, false)
),
account_check as (
  select
    e.name,
    e.currency as expected_currency,
    e.should_allow,
    a.id as cash_account_id,
    a.currency as actual_currency,
    a.account_type,
    a.is_active,
    a.allow_school_requests,
    case
      when a.id is null then 'account missing'
      when e.should_allow and a.is_active is not true then 'allowed account is not active'
      when e.should_allow and a.allow_school_requests is not true then 'allowed account is not allow_school_requests'
      when e.should_allow and a.currency is distinct from e.currency then 'allowed account currency mismatch'
      when not e.should_allow and a.allow_school_requests is true then 'excluded account is allow_school_requests'
      else null
    end as issue
  from expected_accounts e
  left join public.home_accounts a
    on a.name = e.name
)
select
  'cash:school_eligible_account_whitelist_anomalies' as check_name,
  *
from account_check
where issue is not null
order by name;

select
  'cash:teacher_wage_external_request_summary' as check_name,
  count(*) as request_count,
  count(*) filter (where status = 'pending') as pending_count,
  count(*) filter (where status = 'approved') as approved_count,
  count(*) filter (where status = 'rejected') as rejected_count,
  count(*) filter (where currency = 'JPY') as jpy_count,
  count(*) filter (where currency = 'CNY') as cny_count,
  coalesce(sum(amount) filter (where currency = 'JPY'), 0) as jpy_amount_total,
  coalesce(sum(amount) filter (where currency = 'CNY'), 0) as cny_amount_total
from public.home_external_transaction_requests r
where r.external_source = 'aozora_school'
  and r.external_reference_type = 'school_payment_requests'
  and r.request_type = 'teacher_wage_payment_confirm'
  and (
    r.payload_snapshot->>'request_month' = '2026-05'
    or r.payload_snapshot->>'settlement_month' = '2026-05'
    or r.description ilike '%2026-05%'
    or r.note ilike '%2026-05%'
  );

select
  'cash:teacher_wage_external_request_detail' as check_name,
  r.id as cash_request_id,
  r.external_event_id,
  r.external_reference_id as school_payment_request_id,
  r.status,
  r.currency,
  r.amount,
  r.account_id,
  a.name as account_name,
  a.currency as account_currency,
  a.allow_school_requests,
  r.transacted_at,
  r.requested_at,
  r.approved_at,
  r.rejected_at,
  r.rejected_reason,
  r.created_transaction_id,
  r.idempotency_key,
  r.payload_snapshot,
  r.description,
  r.note
from public.home_external_transaction_requests r
left join public.home_accounts a
  on a.id = r.account_id
where r.external_source = 'aozora_school'
  and r.external_reference_type = 'school_payment_requests'
  and r.request_type = 'teacher_wage_payment_confirm'
  and (
    r.payload_snapshot->>'request_month' = '2026-05'
    or r.payload_snapshot->>'settlement_month' = '2026-05'
    or r.description ilike '%2026-05%'
    or r.note ilike '%2026-05%'
  )
order by r.requested_at, r.id;

with request_anomalies as (
  select
    r.id as cash_request_id,
    r.external_reference_id as school_payment_request_id,
    r.status,
    r.currency,
    r.amount,
    r.account_id,
    a.name as account_name,
    a.currency as account_currency,
    a.allow_school_requests,
    r.created_transaction_id,
    r.approved_at,
    r.rejected_at,
    r.rejected_reason,
    r.idempotency_key,
    case
      when a.id is null then 'request account missing'
      when a.is_active is not true then 'request account inactive'
      when a.allow_school_requests is not true then 'request account not allow_school_requests'
      when a.currency is distinct from r.currency then 'request currency differs from account currency'
      when r.currency not in ('JPY', 'CNY') then 'request currency not JPY/CNY'
      when coalesce(r.amount, 0) <= 0 then 'request amount <= 0'
      when r.status = 'pending' and r.created_transaction_id is not null then 'pending request has transaction id'
      when r.status = 'pending' and (r.approved_at is not null or r.rejected_at is not null) then 'pending request has terminal timestamp'
      when r.status = 'approved' and (r.approved_at is null or r.created_transaction_id is null) then 'approved request missing approved_at or transaction id'
      when r.status = 'approved' and r.rejected_at is not null then 'approved request has rejected_at'
      when r.status = 'rejected' and (r.rejected_at is null or r.created_transaction_id is not null) then 'rejected request missing rejected_at or has transaction id'
      when r.status = 'rejected' and nullif(trim(coalesce(r.rejected_reason, '')), '') is null then 'rejected request missing reason'
      else null
    end as issue
  from public.home_external_transaction_requests r
  left join public.home_accounts a
    on a.id = r.account_id
  where r.external_source = 'aozora_school'
    and r.external_reference_type = 'school_payment_requests'
    and r.request_type = 'teacher_wage_payment_confirm'
    and (
      r.payload_snapshot->>'request_month' = '2026-05'
      or r.payload_snapshot->>'settlement_month' = '2026-05'
      or r.description ilike '%2026-05%'
      or r.note ilike '%2026-05%'
    )
)
select
  'cash:teacher_wage_external_request_anomalies' as check_name,
  *
from request_anomalies
where issue is not null
order by issue, cash_request_id;

with active_duplicates as (
  select
    r.external_reference_id as school_payment_request_id,
    count(*) as active_request_count,
    array_agg(r.id order by r.requested_at, r.id) as cash_request_ids,
    array_agg(r.status order by r.requested_at, r.id) as statuses
  from public.home_external_transaction_requests r
  where r.external_source = 'aozora_school'
    and r.external_reference_type = 'school_payment_requests'
    and r.request_type = 'teacher_wage_payment_confirm'
    and r.status = 'pending'
  group by r.external_reference_id
  having count(*) > 1
)
select
  'cash:duplicate_active_requests_by_school_payment_request' as check_name,
  *
from active_duplicates
order by active_request_count desc, school_payment_request_id;

select
  'cash:duplicate_request_idempotency_keys' as check_name,
  idempotency_key,
  count(*) as row_count,
  array_agg(id order by requested_at, id) as cash_request_ids
from public.home_external_transaction_requests
where external_source = 'aozora_school'
  and external_reference_type = 'school_payment_requests'
  and request_type = 'teacher_wage_payment_confirm'
group by idempotency_key
having count(*) > 1
order by row_count desc, idempotency_key;

select
  'cash:duplicate_transaction_idempotency_keys_jpy' as check_name,
  external_idempotency_key,
  count(*) as row_count,
  array_agg(id order by created_at, id) as transaction_ids
from public.home_jpy_transactions
where created_by_external is true
  and external_source = 'aozora_school'
  and external_event_type = 'teacher_wage_payment_confirm'
  and external_reference_type = 'school_payment_requests'
group by external_idempotency_key
having count(*) > 1
order by row_count desc, external_idempotency_key;

select
  'cash:duplicate_transaction_idempotency_keys_cny' as check_name,
  external_idempotency_key,
  count(*) as row_count,
  array_agg(id order by created_at, id) as transaction_ids
from public.home_cny_transactions
where created_by_external is true
  and external_source = 'aozora_school'
  and external_event_type = 'teacher_wage_payment_confirm'
  and external_reference_type = 'school_payment_requests'
group by external_idempotency_key
having count(*) > 1
order by row_count desc, external_idempotency_key;

with jpy_trial_transactions as (
  select
    t.id,
    t.external_reference_id as school_payment_request_id,
    t.external_idempotency_key,
    t.account_id,
    a.name as account_name,
    t.transacted_at,
    t.amount,
    t.description,
    t.note,
    t.created_at
  from public.home_jpy_transactions t
  left join public.home_accounts a
    on a.id = t.account_id
  where t.created_by_external is true
    and t.external_source = 'aozora_school'
    and t.external_event_type = 'teacher_wage_payment_confirm'
    and t.external_reference_type = 'school_payment_requests'
    and (
      t.external_note ilike '%2026-05%'
      or t.description ilike '%2026-05%'
      or t.note ilike '%2026-05%'
    )
),
cny_trial_transactions as (
  select
    t.id,
    t.external_reference_id as school_payment_request_id,
    t.external_idempotency_key,
    t.account_id,
    a.name as account_name,
    t.transacted_at,
    t.amount,
    t.description,
    t.note,
    t.created_at
  from public.home_cny_transactions t
  left join public.home_accounts a
    on a.id = t.account_id
  where t.created_by_external is true
    and t.external_source = 'aozora_school'
    and t.external_event_type = 'teacher_wage_payment_confirm'
    and t.external_reference_type = 'school_payment_requests'
    and (
      t.external_note ilike '%2026-05%'
      or t.description ilike '%2026-05%'
      or t.note ilike '%2026-05%'
    )
)
select
  'cash:preexisting_2026_05_teacher_wage_external_transactions' as check_name,
  'JPY' as currency,
  *
from jpy_trial_transactions
union all
select
  'cash:preexisting_2026_05_teacher_wage_external_transactions' as check_name,
  'CNY' as currency,
  *
from cny_trial_transactions
order by currency, created_at, id;

with approved_requests as (
  select *
  from public.home_external_transaction_requests r
  where r.external_source = 'aozora_school'
    and r.external_reference_type = 'school_payment_requests'
    and r.request_type = 'teacher_wage_payment_confirm'
    and r.status = 'approved'
    and (
      r.payload_snapshot->>'request_month' = '2026-05'
      or r.payload_snapshot->>'settlement_month' = '2026-05'
      or r.description ilike '%2026-05%'
      or r.note ilike '%2026-05%'
    )
),
approved_anomalies as (
  select
    r.id as cash_request_id,
    r.external_reference_id as school_payment_request_id,
    r.currency,
    r.amount as request_amount,
    r.created_transaction_id,
    coalesce(j.id, c.id) as transaction_id,
    coalesce(j.amount, c.amount) as transaction_amount,
    coalesce(j.account_id, c.account_id) as transaction_account_id,
    case
      when r.currency = 'JPY' and j.id is null then 'approved JPY request missing home_jpy_transactions row'
      when r.currency = 'CNY' and c.id is null then 'approved CNY request missing home_cny_transactions row'
      when coalesce(j.amount, c.amount) is distinct from r.amount then 'transaction amount differs from request amount'
      when coalesce(j.account_id, c.account_id) is distinct from r.account_id then 'transaction account differs from request account'
      else null
    end as issue
  from approved_requests r
  left join public.home_jpy_transactions j
    on r.currency = 'JPY'
   and j.id = r.created_transaction_id
  left join public.home_cny_transactions c
    on r.currency = 'CNY'
   and c.id = r.created_transaction_id
)
select
  'cash:approved_request_transaction_anomalies' as check_name,
  *
from approved_anomalies
where issue is not null
order by issue, cash_request_id;

\endif
