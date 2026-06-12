#!/usr/bin/env zsh
set -euo pipefail

LIMIT=5
EVENT_ID=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: scripts/sync-personal-cash-linkage.zsh [--limit N] [--event-id UUID] [--dry-run]

Synchronize Phase 1 personal-business teacher wage JPY school outbox events to
Cash System JPY transactions.

Scope:
- reads only school_personal_cash_linkage_events with sync_status = pending
- requires personal business, teacher_wage payment request, JPY currency
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

fetch_pending_events() {
  load_school

  if [[ -n "$EVENT_ID" ]]; then
    psql_json -v event_id="$EVENT_ID" -v limit="$LIMIT" <<'SQL'
with candidates as (
  select
    e.id,
    e.payment_request_id,
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
    concat('school linkage event ', e.id::text) as external_note
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
    e.id,
    e.payment_request_id,
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
    concat('school linkage event ', e.id::text) as external_note
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

call_cash_rpc() {
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

mark_school_synced() {
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

mark_school_failed() {
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

events_json="$(fetch_pending_events)"
event_count="$(jq 'length' <<<"$events_json")"

if [[ "$event_count" -eq 0 ]]; then
  echo "No pending eligible personal Cash linkage events found."
  exit 0
fi

echo "Found ${event_count} pending eligible event(s)."

while IFS= read -r row; do
  event_id="$(jq -r '.id' <<<"$row")"
  payment_request_id="$(jq -r '.payment_request_id' <<<"$row")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN event=${event_id} payment_request=${payment_request_id}"
    continue
  fi

  cash_result=""
  cash_error=""
  if ! cash_result="$(call_cash_rpc "$row" 2>&1)"; then
    cash_error="$cash_result"
    mark_school_failed "$event_id" "Cash RPC execution failed: ${cash_error}"
    echo "FAILED event=${event_id} payment_request=${payment_request_id}"
    continue
  fi

  ok="$(jq -r '.ok // false' <<<"$cash_result")"
  transaction_id="$(jq -r '.transaction_id // empty' <<<"$cash_result")"
  message="$(jq -r '.message // empty' <<<"$cash_result")"

  if [[ "$ok" != "true" || -z "$transaction_id" ]]; then
    mark_school_failed "$event_id" "Cash RPC returned ok=false: ${message}"
    echo "FAILED event=${event_id} payment_request=${payment_request_id} message=${message}"
    continue
  fi

  mark_school_synced "$event_id" "$transaction_id"
  inserted="$(jq -r '.inserted // false' <<<"$cash_result")"
  echo "SYNCED event=${event_id} payment_request=${payment_request_id} cash_transaction=${transaction_id} inserted=${inserted}"
done < <(jq -c '.[]' <<<"$events_json")
