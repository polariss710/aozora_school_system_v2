-- school_income_cash_confirmation_preflight_readonly_checks.sql
-- Purpose:
-- - Read-only preflight checks before applying
--   school_income_cash_confirmation_workflow.sql.
-- - Detect current School/Cash compatibility risks for income Cash
--   confirmation before any schema/RPC execution.
--
-- Usage:
--   School DB:
--     psql "<school-db-url>" -v ON_ERROR_STOP=1 -v run_school=true -v run_cash=false -f school_income_cash_confirmation_preflight_readonly_checks.sql
--
--   Cash DB:
--     psql "<cash-db-url>" -v ON_ERROR_STOP=1 -v run_school=false -v run_cash=true -f school_income_cash_confirmation_preflight_readonly_checks.sql
--
-- Safety:
-- - Do not run both sections against one DB.
-- - This file is intentionally SELECT-only, plus psql meta commands.
-- - It does not modify data, call business RPCs, or create Cash transactions.

\if :run_school

\echo '=== School DB: income Cash confirmation workflow preflight read-only checks ==='

select
  'school:preflight_scope' as check_name,
  current_database() as database_name,
  current_user as database_user,
  now() as checked_at,
  'Checks compatibility before school_income_cash_confirmation_workflow.sql; SELECT-only' as note;

select
  'school:required_table_presence' as check_name,
  required.table_name,
  (t.table_name is not null) as exists_now
from (
  values
    ('school_income_records'),
    ('school_personal_cash_income_linkage_events'),
    ('school_business_entities'),
    ('school_students'),
    ('school_student_monthly_settlements')
) as required(table_name)
left join information_schema.tables t
  on t.table_schema = 'public'
 and t.table_name = required.table_name
order by required.table_name;

select
  case when exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'school_income_records'
  ) then 'true' else 'false' end as school_income_records_table_exists
\gset

\if :school_income_records_table_exists

select
  'school:income_status_distribution' as check_name,
  coalesce(status, '<null>') as status,
  count(*) as row_count
from public.school_income_records
group by coalesce(status, '<null>')
order by row_count desc, status;

select
  'school:income_status_constraint_blockers' as check_name,
  count(*) as blocking_row_count
from public.school_income_records
where coalesce(status, '') not in ('pending', 'received', 'reversed');

select
  'school:income_status_constraint_blocker_detail' as check_name,
  id as income_id,
  income_date,
  settlement_month,
  income_category,
  currency,
  amount,
  status,
  receipt_status,
  business_entity_id,
  student_id,
  account_id,
  created_at,
  updated_at
from public.school_income_records
where coalesce(status, '') not in ('pending', 'received', 'reversed')
order by created_at, id
limit 100;

select
  'school:pending_income_without_cash_linkage_summary' as check_name,
  count(*) filter (where status = 'pending') as pending_income_count,
  count(*) filter (where status = 'pending' and account_id is null) as pending_without_school_account_count,
  count(*) filter (where status = 'pending' and account_id is not null) as pending_with_school_account_count
from public.school_income_records;

\else

select
  'school:income_records_missing' as check_name,
  'public.school_income_records does not exist; stop before workflow execution' as issue;

\endif

select
  case when exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'school_personal_cash_income_linkage_events'
  ) then 'true' else 'false' end as school_income_linkage_table_exists
\gset

\if :school_income_linkage_table_exists

select
  'school:income_linkage_column_matrix' as check_name,
  expected.column_name,
  expected.required_after_workflow,
  (c.column_name is not null) as exists_now,
  c.data_type,
  c.is_nullable,
  c.column_default
from (
  values
    ('id', true),
    ('source_table', true),
    ('source_id', true),
    ('source_event_type', true),
    ('income_record_id', true),
    ('business_entity_id', true),
    ('cash_account_mapping_id', false),
    ('cash_user_id', true),
    ('cash_account_id', true),
    ('cash_account_name_snapshot', true),
    ('cash_account_type_snapshot', true),
    ('cash_transaction_table', true),
    ('cash_transaction_id', true),
    ('currency', true),
    ('amount', true),
    ('payment_currency', true),
    ('payment_exchange_rate', true),
    ('payment_amount', true),
    ('idempotency_key', true),
    ('sync_status', true),
    ('attempt_no', true),
    ('cash_request_id', true),
    ('cash_request_status', true),
    ('requested_at', true),
    ('confirmed_at', true),
    ('rejected_at', true),
    ('rejected_reason', true),
    ('cash_request_last_checked_at', true),
    ('retry_count', true),
    ('last_error', true),
    ('note', true),
    ('created_at', true),
    ('updated_at', true),
    ('synced_at', true)
) as expected(column_name, required_after_workflow)
left join information_schema.columns c
  on c.table_schema = 'public'
 and c.table_name = 'school_personal_cash_income_linkage_events'
 and c.column_name = expected.column_name
order by expected.column_name;

select
  case when exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'school_personal_cash_income_linkage_events'
      and column_name = 'attempt_no'
  ) then 'true' else 'false' end as school_income_linkage_has_attempt_no
\gset

select
  'school:income_linkage_sync_status_distribution' as check_name,
  coalesce(sync_status, '<null>') as sync_status,
  count(*) as row_count
from public.school_personal_cash_income_linkage_events
group by coalesce(sync_status, '<null>')
order by row_count desc, sync_status;

select
  'school:income_linkage_legacy_pending_summary' as check_name,
  count(*) filter (where sync_status = 'pending') as legacy_pending_count,
  count(*) filter (where sync_status = 'synced') as synced_count,
  count(*) filter (where sync_status = 'failed') as failed_count,
  count(*) filter (where sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')) as active_new_status_count,
  count(*) filter (where sync_status = 'cash_rejected') as cash_rejected_count
from public.school_personal_cash_income_linkage_events;

select
  'school:income_linkage_target_constraint_blockers' as check_name,
  count(*) as blocking_row_count
from public.school_personal_cash_income_linkage_events e
where e.source_table is distinct from 'school_income_records'
   or e.source_id is distinct from e.income_record_id
   or e.source_event_type not in ('tuition_income_received', 'income_received')
   or e.cash_transaction_table not in ('home_jpy_transactions', 'home_cny_transactions')
   or e.currency not in ('JPY', 'CNY')
   or coalesce(e.amount, 0) <= 0
   or e.sync_status not in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation', 'synced', 'cash_rejected', 'failed', 'blocked')
   or coalesce(e.retry_count, -1) < 0
   or nullif(trim(coalesce(e.idempotency_key, '')), '') is null
   or nullif(trim(coalesce(e.cash_account_name_snapshot, '')), '') is null
   or (e.sync_status = 'synced' and e.cash_transaction_id is null);

select
  'school:income_linkage_target_constraint_blocker_detail' as check_name,
  e.id as linkage_event_id,
  e.income_record_id,
  e.source_table,
  e.source_id,
  e.source_event_type,
  e.cash_transaction_table,
  e.cash_transaction_id,
  e.currency,
  e.amount,
  e.idempotency_key,
  e.sync_status,
  e.retry_count,
  e.last_error,
  concat_ws(
    '; ',
    case when e.source_table is distinct from 'school_income_records' then 'source_table target constraint blocker' end,
    case when e.source_id is distinct from e.income_record_id then 'source_id differs from income_record_id' end,
    case when e.source_event_type not in ('tuition_income_received', 'income_received') then 'unsupported source_event_type' end,
    case when e.cash_transaction_table not in ('home_jpy_transactions', 'home_cny_transactions') then 'unsupported cash_transaction_table' end,
    case when e.currency not in ('JPY', 'CNY') then 'unsupported currency' end,
    case when coalesce(e.amount, 0) <= 0 then 'non-positive amount' end,
    case when e.sync_status not in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation', 'synced', 'cash_rejected', 'failed', 'blocked') then 'unsupported sync_status for target workflow' end,
    case when coalesce(e.retry_count, -1) < 0 then 'negative retry_count' end,
    case when nullif(trim(coalesce(e.idempotency_key, '')), '') is null then 'blank idempotency_key' end,
    case when nullif(trim(coalesce(e.cash_account_name_snapshot, '')), '') is null then 'blank cash_account_name_snapshot' end,
    case when e.sync_status = 'synced' and e.cash_transaction_id is null then 'synced without cash_transaction_id' end
  ) as issue
from public.school_personal_cash_income_linkage_events e
where e.source_table is distinct from 'school_income_records'
   or e.source_id is distinct from e.income_record_id
   or e.source_event_type not in ('tuition_income_received', 'income_received')
   or e.cash_transaction_table not in ('home_jpy_transactions', 'home_cny_transactions')
   or e.currency not in ('JPY', 'CNY')
   or coalesce(e.amount, 0) <= 0
   or e.sync_status not in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation', 'synced', 'cash_rejected', 'failed', 'blocked')
   or coalesce(e.retry_count, -1) < 0
   or nullif(trim(coalesce(e.idempotency_key, '')), '') is null
   or nullif(trim(coalesce(e.cash_account_name_snapshot, '')), '') is null
   or (e.sync_status = 'synced' and e.cash_transaction_id is null)
order by e.created_at, e.id
limit 100;

select
  'school:income_linkage_active_attempt_duplicates' as check_name,
  e.source_table,
  e.source_id,
  e.source_event_type,
  count(*) as active_attempt_count,
  array_agg(e.id order by e.created_at, e.id) as linkage_event_ids,
  array_agg(e.sync_status order by e.created_at, e.id) as sync_statuses
from public.school_personal_cash_income_linkage_events e
where e.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
group by e.source_table, e.source_id, e.source_event_type
having count(*) > 1
order by active_attempt_count desc, e.source_id;

\if :school_income_linkage_has_attempt_no

select
  'school:income_linkage_source_event_attempt_duplicates' as check_name,
  e.source_table,
  e.source_id,
  e.source_event_type,
  e.attempt_no,
  count(*) as duplicate_count,
  array_agg(e.id order by e.created_at, e.id) as linkage_event_ids
from public.school_personal_cash_income_linkage_events e
group by e.source_table, e.source_id, e.source_event_type, e.attempt_no
having count(*) > 1
order by duplicate_count desc, e.source_id, e.attempt_no;

select
  'school:income_linkage_attempt_no_blockers' as check_name,
  count(*) as blocking_row_count
from public.school_personal_cash_income_linkage_events e
where e.attempt_no is null
   or e.attempt_no <= 0;

\else

select
  'school:income_linkage_attempt_no_not_present' as check_name,
  'attempt_no column is not present now; workflow adds attempt_no default 1. Existing source-event uniqueness should be reviewed before execution.' as note;

select
  'school:income_linkage_source_event_duplicates_without_attempt_no' as check_name,
  e.source_table,
  e.source_id,
  e.source_event_type,
  count(*) as duplicate_count,
  array_agg(e.id order by e.created_at, e.id) as linkage_event_ids
from public.school_personal_cash_income_linkage_events e
group by e.source_table, e.source_id, e.source_event_type
having count(*) > 1
order by duplicate_count desc, e.source_id;

\endif

select
  'school:income_linkage_current_unique_index_collision_risk' as check_name,
  e.idempotency_key,
  count(*) as duplicate_count,
  array_agg(e.id order by e.created_at, e.id) as linkage_event_ids
from public.school_personal_cash_income_linkage_events e
group by e.idempotency_key
having count(*) > 1
order by duplicate_count desc, e.idempotency_key;

select
  'school:income_linkage_orphan_summary' as check_name,
  count(*) as orphan_event_count
from public.school_personal_cash_income_linkage_events e
left join public.school_income_records i
  on i.id = e.income_record_id
where i.id is null;

select
  'school:income_linkage_orphan_detail' as check_name,
  e.id as linkage_event_id,
  e.income_record_id,
  e.source_event_type,
  e.sync_status,
  e.created_at
from public.school_personal_cash_income_linkage_events e
left join public.school_income_records i
  on i.id = e.income_record_id
where i.id is null
order by e.created_at, e.id
limit 100;

select
  'school:cash_linked_income_ordinary_edit_reverse_guard_gap' as check_name,
  e.source_event_type,
  count(*) as linked_income_count,
  count(*) filter (where e.source_event_type = 'income_received') as currently_not_guarded_by_old_tuition_only_checks
from public.school_personal_cash_income_linkage_events e
group by e.source_event_type
order by e.source_event_type;

\else

select
  'school:income_linkage_table_missing' as check_name,
  'public.school_personal_cash_income_linkage_events does not exist; workflow will create it if income status constraints pass' as note;

\endif

select
  'school:income_cash_rpc_presence' as check_name,
  expected.proname,
  count(p.oid) as matching_function_count,
  array_agg(pg_get_function_identity_arguments(p.oid) order by p.oid) filter (where p.oid is not null) as signatures
from (
  values
    ('school_create_cash_income_confirmation'),
    ('school_request_cash_income_confirmation'),
    ('school_mark_cash_income_request_submitted'),
    ('school_mark_cash_income_confirmed'),
    ('school_mark_cash_income_rejected'),
    ('school_create_personal_cash_tuition_income_record'),
    ('school_update_personal_cash_income_linkage_event_status'),
    ('school_retry_personal_cash_income_linkage_event')
) as expected(proname)
left join pg_proc p
  on p.pronamespace = 'public'::regnamespace
 and p.proname = expected.proname
group by expected.proname
order by expected.proname;

\if :school_income_records_table_exists

\if :school_income_linkage_table_exists

select
  'school:income_cash_workflow_preflight_rollup' as check_name,
  (
    select count(*)
    from public.school_income_records
    where coalesce(status, '') not in ('pending', 'received', 'reversed')
  ) as income_status_blockers,
  (
    select count(*)
    from public.school_personal_cash_income_linkage_events
    where sync_status = 'pending'
  ) as legacy_pending_linkage_rows,
  (
    select count(*)
    from public.school_personal_cash_income_linkage_events e
    where e.sync_status not in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation', 'synced', 'cash_rejected', 'failed', 'blocked')
  ) as target_sync_status_blockers,
  (
    select count(*)
    from public.school_personal_cash_income_linkage_events e
    where e.source_event_type = 'income_received'
  ) as income_received_linkage_rows_need_detail_update_reverse_review;

\else

select
  'school:income_cash_workflow_preflight_rollup' as check_name,
  (
    select count(*)
    from public.school_income_records
    where coalesce(status, '') not in ('pending', 'received', 'reversed')
  ) as income_status_blockers,
  null::bigint as legacy_pending_linkage_rows,
  null::bigint as target_sync_status_blockers,
  null::bigint as income_received_linkage_rows_need_detail_update_reverse_review;

\endif

\else

select
  'school:income_cash_workflow_preflight_rollup' as check_name,
  null::bigint as income_status_blockers,
  null::bigint as legacy_pending_linkage_rows,
  null::bigint as target_sync_status_blockers,
  null::bigint as income_received_linkage_rows_need_detail_update_reverse_review;

\endif

\endif

\if :run_cash

\echo '=== Cash DB: income Cash confirmation workflow preflight read-only checks ==='

select
  'cash:preflight_scope' as check_name,
  current_database() as database_name,
  current_user as database_user,
  now() as checked_at,
  'Checks Cash-side support for School income receipt confirmation; SELECT-only' as note;

select
  'cash:required_table_presence' as check_name,
  required.table_name,
  (t.table_name is not null) as exists_now
from (
  values
    ('home_accounts'),
    ('home_external_transaction_requests'),
    ('home_jpy_transactions'),
    ('home_cny_transactions')
) as required(table_name)
left join information_schema.tables t
  on t.table_schema = 'public'
 and t.table_name = required.table_name
order by required.table_name;

select
  'cash:required_function_presence' as check_name,
  expected.proname,
  count(p.oid) as matching_function_count,
  array_agg(pg_get_function_identity_arguments(p.oid) order by p.oid) filter (where p.oid is not null) as signatures
from (
  values
    ('home_create_external_transaction_request'),
    ('home_approve_external_transaction_request'),
    ('home_create_external_jpy_transaction'),
    ('home_create_external_cny_transaction'),
    ('home_list_school_eligible_cash_accounts')
) as expected(proname)
left join pg_proc p
  on p.pronamespace = 'public'::regnamespace
 and p.proname = expected.proname
group by expected.proname
order by expected.proname;

select
  case when exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'home_accounts'
      and column_name = 'allow_school_requests'
  ) then 'true' else 'false' end as cash_home_accounts_has_allow_school_requests
\gset

\if :cash_home_accounts_has_allow_school_requests

select
  'cash:school_eligible_accounts' as check_name,
  id as account_id,
  user_id,
  name,
  currency,
  account_type,
  is_active,
  allow_school_requests
from public.home_accounts
where is_active is true
  and allow_school_requests is true
order by currency, name, id;

select
  'cash:expected_school_eligible_account_names' as check_name,
  expected.name,
  expected.currency,
  count(a.id) as matching_active_allowed_count,
  array_agg(a.id order by a.id) filter (where a.id is not null) as account_ids
from (
  values
    ('余额宝', 'CNY'),
    ('日元现金', 'JPY'),
    ('日元三菱卡', 'JPY'),
    ('日元乐天卡', 'JPY')
) as expected(name, currency)
left join public.home_accounts a
  on a.name = expected.name
 and a.currency = expected.currency
 and a.is_active is true
 and a.allow_school_requests is true
group by expected.name, expected.currency
order by expected.currency, expected.name;

select
  'cash:excluded_school_account_names' as check_name,
  a.id as account_id,
  a.name,
  a.currency,
  a.account_type,
  a.is_active,
  a.allow_school_requests,
  case
    when a.allow_school_requests is true then 'blocker: excluded account is allowed for School requests'
    else 'ok: excluded from School requests'
  end as result
from public.home_accounts a
where a.name in ('余利宝', '医生处兑换日元先行支付')
order by a.name, a.currency, a.id;

\else

select
  'cash:allow_school_requests_missing' as check_name,
  'home_accounts.allow_school_requests column is missing; stop before income Cash workflow rollout' as issue;

\endif

select
  case when exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'home_external_transaction_requests'
  ) then 'true' else 'false' end as cash_external_requests_table_exists
\gset

\if :cash_external_requests_table_exists

select
  'cash:external_request_column_matrix' as check_name,
  expected.column_name,
  (c.column_name is not null) as exists_now,
  c.data_type,
  c.is_nullable
from (
  values
    ('id'),
    ('user_id'),
    ('external_source'),
    ('external_event_id'),
    ('external_reference_type'),
    ('external_reference_id'),
    ('request_type'),
    ('transaction_type'),
    ('currency'),
    ('amount'),
    ('account_id'),
    ('transacted_at'),
    ('status'),
    ('idempotency_key'),
    ('payload_snapshot'),
    ('description'),
    ('note'),
    ('approved_at'),
    ('rejected_at'),
    ('rejected_reason'),
    ('created_transaction_id')
) as expected(column_name)
left join information_schema.columns c
  on c.table_schema = 'public'
 and c.table_name = 'home_external_transaction_requests'
 and c.column_name = expected.column_name
order by expected.column_name;

select
  'cash:existing_school_income_external_requests_summary' as check_name,
  request_type,
  transaction_type,
  currency,
  status,
  count(*) as request_count,
  coalesce(sum(amount), 0) as amount_total,
  min(created_at) as first_created_at,
  max(created_at) as last_created_at
from public.home_external_transaction_requests
where external_source = 'aozora_school'
  and external_reference_type = 'school_income_records'
group by request_type, transaction_type, currency, status
order by request_type, transaction_type, currency, status;

select
  'cash:school_income_external_request_anomalies' as check_name,
  id as cash_request_id,
  external_event_id,
  external_reference_id as income_record_id,
  request_type,
  transaction_type,
  currency,
  amount,
  status,
  created_transaction_id,
  idempotency_key,
  created_at,
  concat_ws(
    '; ',
    case when request_type not in ('tuition_income_received', 'income_received') then 'unsupported request_type' end,
    case when transaction_type <> 'income' then 'transaction_type is not income' end,
    case when currency not in ('JPY', 'CNY') then 'unsupported currency' end,
    case when coalesce(amount, 0) <= 0 then 'non-positive amount' end,
    case when status = 'pending' and created_transaction_id is not null then 'pending request has transaction id' end,
    case when status = 'rejected' and created_transaction_id is not null then 'rejected request has transaction id' end,
    case when status = 'approved' and created_transaction_id is null then 'approved request missing transaction id' end,
    case when nullif(trim(coalesce(idempotency_key, '')), '') is null then 'blank idempotency_key' end
  ) as issue
from public.home_external_transaction_requests
where external_source = 'aozora_school'
  and external_reference_type = 'school_income_records'
  and (
    request_type not in ('tuition_income_received', 'income_received')
    or transaction_type <> 'income'
    or currency not in ('JPY', 'CNY')
    or coalesce(amount, 0) <= 0
    or (status = 'pending' and created_transaction_id is not null)
    or (status = 'rejected' and created_transaction_id is not null)
    or (status = 'approved' and created_transaction_id is null)
    or nullif(trim(coalesce(idempotency_key, '')), '') is null
  )
order by created_at, id
limit 100;

select
  'cash:school_income_external_request_idempotency_duplicates' as check_name,
  idempotency_key,
  count(*) as duplicate_count,
  array_agg(id order by created_at, id) as cash_request_ids,
  array_agg(status order by created_at, id) as statuses
from public.home_external_transaction_requests
where external_source = 'aozora_school'
  and external_reference_type = 'school_income_records'
group by idempotency_key
having count(*) > 1
order by duplicate_count desc, idempotency_key;

\else

select
  'cash:external_requests_table_missing' as check_name,
  'home_external_transaction_requests table is missing; stop before income Cash workflow rollout' as issue;

\endif

select
  'cash:transaction_external_column_matrix' as check_name,
  expected.table_name,
  expected.column_name,
  (c.column_name is not null) as exists_now,
  c.data_type,
  c.is_nullable
from (
  values
    ('home_jpy_transactions', 'created_by_external'),
    ('home_jpy_transactions', 'external_source'),
    ('home_jpy_transactions', 'external_source_id'),
    ('home_jpy_transactions', 'external_event_type'),
    ('home_jpy_transactions', 'external_idempotency_key'),
    ('home_jpy_transactions', 'external_reference_type'),
    ('home_jpy_transactions', 'external_reference_id'),
    ('home_cny_transactions', 'created_by_external'),
    ('home_cny_transactions', 'external_source'),
    ('home_cny_transactions', 'external_source_id'),
    ('home_cny_transactions', 'external_event_type'),
    ('home_cny_transactions', 'external_idempotency_key'),
    ('home_cny_transactions', 'external_reference_type'),
    ('home_cny_transactions', 'external_reference_id')
) as expected(table_name, column_name)
left join information_schema.columns c
  on c.table_schema = 'public'
 and c.table_name = expected.table_name
 and c.column_name = expected.column_name
order by expected.table_name, expected.column_name;

\endif
