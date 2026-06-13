#!/usr/bin/env zsh
set -euo pipefail

LIMIT=5
EVENT_ID=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: scripts/sync-personal-cash-linkage.zsh [--limit N] [--event-id UUID] [--dry-run]

Synchronize personal-business school outbox events to Cash System JPY transactions.

Scope:
- payment linkage: reads pending school_personal_cash_linkage_events for
  teacher_wage_payment_confirm and creates Cash JPY expense transactions
- income linkage: reads pending school_personal_cash_income_linkage_events for
  tuition_income_received and creates Cash JPY income transactions
- requires personal business and JPY currency
- calls Cash RPC home_create_external_jpy_transaction
- updates school event to synced or failed
- does not process CNY, company / 青空塾, reimbursements, reversals, or synced events
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --event-id)
      EVENT_ID="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$LIMIT" =~ '^[0-9]+$' ]] || [[ "$LIMIT" -lt 1 ]]; then
  echo "--limit must be a positive integer" >&2
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

source "${HOME}/.zshrc" >/dev/null 2>&1 || true

if ! typeset -f load_school_db >/dev/null 2>&1; then
  echo "load_school_db is not available" >&2
  exit 2
fi

if ! typeset -f load_cash_db >/dev/null 2>&1; then
  echo "load_cash_db is not available" >&2
  exit 2
fi

psql_json() {
  psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -tA "$@"
}

load_school() {
  load_school_db >/dev/null
}

load_cash() {
  load_cash_db >/dev/null
}

fetch_pending_payment_events() {
  load_school

  if [[ -n "$EVENT_ID" ]]; then
    psql_json -v event_id="$EVENT_ID" -v limit="$LIMIT" <<'SQL'
with candidates as (
  select
    'payment_linkage' as linkage_type,
    e.id,
    e.payment_request_id,
    null::uuid as income_record_id,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.amount,
    e.idempotency_key,
    e.source_event_type,
    p.paid_at::date as transacted_at,
    p.request_month,
    p.payee_name,
    p.business_name,
    concat(coalesce(p.request_month, ''), ' ', coalesce(p.payee_name, ''), ' 老师工资') as description,
    concat('school_payment_request_id=', p.id::text, '; school_linkage_event_id=', e.id::text) as cash_note,
    concat('school payment linkage event ', e.id::text) as external_note
  from public.school_personal_cash_linkage_events e
  join public.school_payment_requests p
    on p.id = e.payment_request_id
  join public.school_business_entities b
    on b.id = e.business_entity_id
  where e.id = :'event_id'::uuid
    and e.sync_status = 'pending'
    and e.cash_transaction_id is null
    and e.source_table = 'school_payment_requests'
    and e.source_event_type = 'teacher_wage_payment_confirm'
    and e.currency = 'JPY'
    and e.amount > 0
    and p.status = 'paid'
    and p.source_type = 'teacher_wage'
    and p.currency = 'JPY'
    and p.reversed_at is null
    and b.entity_type = 'personal'
  order by e.created_at asc, e.id asc
  limit :'limit'::integer
)
select coalesce(jsonb_agg(to_jsonb(candidates)), '[]'::jsonb)::text
from candidates;
SQL
  else
    psql_json -v limit="$LIMIT" <<'SQL'
with candidates as (
  select
    'payment_linkage' as linkage_type,
    e.id,
    e.payment_request_id,
    null::uuid as income_record_id,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.amount,
    e.idempotency_key,
    e.source_event_type,
    p.paid_at::date as transacted_at,
    p.request_month,
    p.payee_name,
    p.business_name,
    concat(coalesce(p.request_month, ''), ' ', coalesce(p.payee_name, ''), ' 老师工资') as description,
    concat('school_payment_request_id=', p.id::text, '; school_linkage_event_id=', e.id::text) as cash_note,
    concat('school payment linkage event ', e.id::text) as external_note
  from public.school_personal_cash_linkage_events e
  join public.school_payment_requests p
    on p.id = e.payment_request_id
  join public.school_business_entities b
    on b.id = e.business_entity_id
  where e.sync_status = 'pending'
    and e.cash_transaction_id is null
    and e.source_table = 'school_payment_requests'
    and e.source_event_type = 'teacher_wage_payment_confirm'
    and e.currency = 'JPY'
    and e.amount > 0
    and p.status = 'paid'
    and p.source_type = 'teacher_wage'
    and p.currency = 'JPY'
    and p.reversed_at is null
    and b.entity_type = 'personal'
  order by e.created_at asc, e.id asc
  limit :'limit'::integer
)
select coalesce(jsonb_agg(to_jsonb(candidates)), '[]'::jsonb)::text
from candidates;
SQL
  fi
}

fetch_pending_income_events() {
  load_school

  if [[ -n "$EVENT_ID" ]]; then
    psql_json -v event_id="$EVENT_ID" -v limit="$LIMIT" <<'SQL'
with candidates as (
  select
    'income_linkage' as linkage_type,
    e.id,
    null::uuid as payment_request_id,
    e.income_record_id,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.amount,
    e.idempotency_key,
    e.source_event_type,
    i.income_date::date as transacted_at,
    i.settlement_month as request_month,
    null::text as payee_name,
    b.name as business_name,
    coalesce(nullif(trim(i.description), ''), concat(coalesce(i.settlement_month, ''), ' 学费收入')) as description,
    concat('school_income_record_id=', i.id::text, '; school_income_linkage_event_id=', e.id::text) as cash_note,
    concat('school income linkage event ', e.id::text) as external_note
  from public.school_personal_cash_income_linkage_events e
  join public.school_income_records i
    on i.id = e.income_record_id
  join public.school_business_entities b
    on b.id = e.business_entity_id
  join public.school_personal_cash_account_mappings m
    on m.id = e.cash_account_mapping_id
  where e.id = :'event_id'::uuid
    and e.sync_status = 'pending'
    and e.cash_transaction_id is null
    and e.source_table = 'school_income_records'
    and e.source_event_type = 'tuition_income_received'
    and e.currency = 'JPY'
    and e.amount > 0
    and i.status = 'received'
    and i.income_category = 'tuition'
    and i.currency = 'JPY'
    and i.payment_currency = 'JPY'
    and i.reversed_at is null
    and b.entity_type = 'personal'
    and m.flow_type = 'tuition_income'
    and m.school_currency = 'JPY'
    and m.cash_currency = 'JPY'
    and m.is_active is true
  order by e.created_at asc, e.id asc
  limit :'limit'::integer
)
select coalesce(jsonb_agg(to_jsonb(candidates)), '[]'::jsonb)::text
from candidates;
SQL
  else
    psql_json -v limit="$LIMIT" <<'SQL'
with candidates as (
  select
    'income_linkage' as linkage_type,
    e.id,
    null::uuid as payment_request_id,
    e.income_record_id,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.amount,
    e.idempotency_key,
    e.source_event_type,
    i.income_date::date as transacted_at,
    i.settlement_month as request_month,
    null::text as payee_name,
    b.name as business_name,
    coalesce(nullif(trim(i.description), ''), concat(coalesce(i.settlement_month, ''), ' 学费收入')) as description,
    concat('school_income_record_id=', i.id::text, '; school_income_linkage_event_id=', e.id::text) as cash_note,
    concat('school income linkage event ', e.id::text) as external_note
  from public.school_personal_cash_income_linkage_events e
  join public.school_income_records i
    on i.id = e.income_record_id
  join public.school_business_entities b
    on b.id = e.business_entity_id
  join public.school_personal_cash_account_mappings m
    on m.id = e.cash_account_mapping_id
  where e.sync_status = 'pending'
    and e.cash_transaction_id is null
    and e.source_table = 'school_income_records'
    and e.source_event_type = 'tuition_income_received'
    and e.currency = 'JPY'
    and e.amount > 0
    and i.status = 'received'
    and i.income_category = 'tuition'
    and i.currency = 'JPY'
    and i.payment_currency = 'JPY'
    and i.reversed_at is null
    and b.entity_type = 'personal'
    and m.flow_type = 'tuition_income'
    and m.school_currency = 'JPY'
    and m.cash_currency = 'JPY'
    and m.is_active is true
  order by e.created_at asc, e.id asc
  limit :'limit'::integer
)
select coalesce(jsonb_agg(to_jsonb(candidates)), '[]'::jsonb)::text
from candidates;
SQL
  fi
}

call_cash_payment_rpc() {
  local row="$1"

  local event_id payment_request_id cash_user_id cash_account_id amount idempotency_key event_type transacted_at description cash_note external_note
  event_id="$(jq -r '.id' <<<"$row")"
  payment_request_id="$(jq -r '.payment_request_id' <<<"$row")"
  cash_user_id="$(jq -r '.cash_user_id' <<<"$row")"
  cash_account_id="$(jq -r '.cash_account_id' <<<"$row")"
  amount="$(jq -r '.amount' <<<"$row")"
  idempotency_key="$(jq -r '.idempotency_key' <<<"$row")"
  event_type="$(jq -r '.source_event_type' <<<"$row")"
  transacted_at="$(jq -r '.transacted_at' <<<"$row")"
  description="$(jq -r '.description' <<<"$row")"
  cash_note="$(jq -r '.cash_note' <<<"$row")"
  external_note="$(jq -r '.external_note' <<<"$row")"

  load_cash
  psql_json \
    -v user_id="$cash_user_id" \
    -v account_id="$cash_account_id" \
    -v event_id="$event_id" \
    -v payment_request_id="$payment_request_id" \
    -v amount="$amount" \
    -v idempotency_key="$idempotency_key" \
    -v event_type="$event_type" \
    -v transacted_at="$transacted_at" \
    -v description="$description" \
    -v cash_note="$cash_note" \
    -v external_note="$external_note" <<'SQL'
select public.home_create_external_jpy_transaction(
  :'user_id'::uuid,
  :'account_id'::uuid,
  'expense',
  :'transacted_at'::date,
  :'amount'::numeric,
  :'description',
  :'cash_note',
  'aozora_school',
  :'event_id'::uuid,
  :'event_type',
  :'idempotency_key',
  'school_payment_requests',
  :'payment_request_id'::uuid,
  :'external_note',
  null
)::text;
SQL
}

call_cash_income_rpc() {
  local row="$1"

  local event_id income_record_id cash_user_id cash_account_id amount idempotency_key event_type transacted_at description cash_note external_note
  event_id="$(jq -r '.id' <<<"$row")"
  income_record_id="$(jq -r '.income_record_id' <<<"$row")"
  cash_user_id="$(jq -r '.cash_user_id' <<<"$row")"
  cash_account_id="$(jq -r '.cash_account_id' <<<"$row")"
  amount="$(jq -r '.amount' <<<"$row")"
  idempotency_key="$(jq -r '.idempotency_key' <<<"$row")"
  event_type="$(jq -r '.source_event_type' <<<"$row")"
  transacted_at="$(jq -r '.transacted_at' <<<"$row")"
  description="$(jq -r '.description' <<<"$row")"
  cash_note="$(jq -r '.cash_note' <<<"$row")"
  external_note="$(jq -r '.external_note' <<<"$row")"

  load_cash
  psql_json \
    -v user_id="$cash_user_id" \
    -v account_id="$cash_account_id" \
    -v event_id="$event_id" \
    -v income_record_id="$income_record_id" \
    -v amount="$amount" \
    -v idempotency_key="$idempotency_key" \
    -v event_type="$event_type" \
    -v transacted_at="$transacted_at" \
    -v description="$description" \
    -v cash_note="$cash_note" \
    -v external_note="$external_note" <<'SQL'
select public.home_create_external_jpy_transaction(
  :'user_id'::uuid,
  :'account_id'::uuid,
  'income',
  :'transacted_at'::date,
  :'amount'::numeric,
  :'description',
  :'cash_note',
  'aozora_school',
  :'event_id'::uuid,
  :'event_type',
  :'idempotency_key',
  'school_income_records',
  :'income_record_id'::uuid,
  :'external_note',
  null
)::text;
SQL
}

mark_payment_synced() {
  local event_id="$1"
  local transaction_id="$2"
  load_school
  psql_json -v event_id="$event_id" -v transaction_id="$transaction_id" <<'SQL' >/dev/null
select *
from public.school_update_personal_cash_linkage_event_status(
  :'event_id'::uuid,
  'synced',
  :'transaction_id'::uuid,
  null
);
SQL
}

mark_payment_failed() {
  local event_id="$1"
  local message="$2"
  local trimmed="${message:0:800}"
  load_school
  psql_json -v event_id="$event_id" -v message="$trimmed" <<'SQL' >/dev/null
select *
from public.school_update_personal_cash_linkage_event_status(
  :'event_id'::uuid,
  'failed',
  null,
  :'message'
);
SQL
}

mark_income_synced() {
  local event_id="$1"
  local transaction_id="$2"
  load_school
  psql_json -v event_id="$event_id" -v transaction_id="$transaction_id" <<'SQL' >/dev/null
select *
from public.school_update_personal_cash_income_linkage_event_status(
  :'event_id'::uuid,
  'synced',
  :'transaction_id'::uuid,
  null
);
SQL
}

mark_income_failed() {
  local event_id="$1"
  local message="$2"
  local trimmed="${message:0:800}"
  load_school
  psql_json -v event_id="$event_id" -v message="$trimmed" <<'SQL' >/dev/null
select *
from public.school_update_personal_cash_income_linkage_event_status(
  :'event_id'::uuid,
  'failed',
  null,
  :'message'
);
SQL
}

process_events() {
  local linkage_type="$1"
  local events_json="$2"
  local event_count
  event_count="$(jq 'length' <<<"$events_json")"

  if [[ "$event_count" -eq 0 ]]; then
    echo "No pending eligible ${linkage_type} event(s) found."
    return 0
  fi

  echo "Found ${event_count} pending eligible ${linkage_type} event(s)."

  while IFS= read -r row; do
    event_id="$(jq -r '.id' <<<"$row")"

    if [[ "$linkage_type" == "payment_linkage" ]]; then
      reference_id="$(jq -r '.payment_request_id' <<<"$row")"
      reference_label="payment_request"
    else
      reference_id="$(jq -r '.income_record_id' <<<"$row")"
      reference_label="income_record"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "DRY RUN ${linkage_type} event=${event_id} ${reference_label}=${reference_id}"
      continue
    fi

    cash_result=""
    cash_error=""
    if [[ "$linkage_type" == "payment_linkage" ]]; then
      if ! cash_result="$(call_cash_payment_rpc "$row" 2>&1)"; then
        cash_error="$cash_result"
        mark_payment_failed "$event_id" "Cash RPC execution failed: ${cash_error}"
        echo "FAILED ${linkage_type} event=${event_id} ${reference_label}=${reference_id}"
        continue
      fi
    else
      if ! cash_result="$(call_cash_income_rpc "$row" 2>&1)"; then
        cash_error="$cash_result"
        mark_income_failed "$event_id" "Cash RPC execution failed: ${cash_error}"
        echo "FAILED ${linkage_type} event=${event_id} ${reference_label}=${reference_id}"
        continue
      fi
    fi

    if ! ok="$(jq -r '.ok // false' <<<"$cash_result" 2>/dev/null)"; then
      if [[ "$linkage_type" == "payment_linkage" ]]; then
        mark_payment_failed "$event_id" "Cash RPC returned non-JSON response"
      else
        mark_income_failed "$event_id" "Cash RPC returned non-JSON response"
      fi
      echo "FAILED ${linkage_type} event=${event_id} ${reference_label}=${reference_id} message=non-json-response"
      continue
    fi

    transaction_id="$(jq -r '.transaction_id // empty' <<<"$cash_result")"
    message="$(jq -r '.message // empty' <<<"$cash_result")"

    if [[ "$ok" != "true" || -z "$transaction_id" ]]; then
      if [[ "$linkage_type" == "payment_linkage" ]]; then
        mark_payment_failed "$event_id" "Cash RPC returned ok=false: ${message}"
      else
        mark_income_failed "$event_id" "Cash RPC returned ok=false: ${message}"
      fi
      echo "FAILED ${linkage_type} event=${event_id} ${reference_label}=${reference_id} message=${message}"
      continue
    fi

    if [[ "$linkage_type" == "payment_linkage" ]]; then
      mark_payment_synced "$event_id" "$transaction_id"
    else
      mark_income_synced "$event_id" "$transaction_id"
    fi

    inserted="$(jq -r '.inserted // false' <<<"$cash_result")"
    echo "SYNCED ${linkage_type} event=${event_id} ${reference_label}=${reference_id} cash_transaction=${transaction_id} inserted=${inserted}"
  done < <(jq -c '.[]' <<<"$events_json")
}

payment_events_json="$(fetch_pending_payment_events)"
process_events "payment_linkage" "$payment_events_json"

income_events_json="$(fetch_pending_income_events)"
process_events "income_linkage" "$income_events_json"
