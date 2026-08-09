#!/usr/bin/env zsh
set -euo pipefail

readonly ENTITY_ID='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
readonly SETTLEMENT_MONTH='2026-07'
readonly UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'

usage() {
  cat <<'USAGE'
Usage:
  scripts/manage-historical-zero-carry-evidence.zsh status --student UUID
  scripts/manage-historical-zero-carry-evidence.zsh create --student UUID --actor UUID
    --reason TEXT --confirm EXACT_TEXT [--execute]

The create command is dry-run unless --execute is supplied. It always reloads
the DB-authoritative School candidate, verifies the approved Cash request and
transaction in Cash DB, then calls the service-role-only School wrapper.
After any ambiguous result, run status before retrying.
USAGE
}

fail() { print -u2 -- "$1"; exit "${2:-2}"; }
need_value() { [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value"; }
need_uuid() { [[ "$2" =~ $UUID_RE ]] || fail "$1 must be a UUID"; }

command -v psql >/dev/null 2>&1 || fail 'psql is required'
command -v jq >/dev/null 2>&1 || fail 'jq is required'
[[ -n "${SCHOOL_SUPABASE_DB_URL:-}" ]] || fail 'SCHOOL_SUPABASE_DB_URL is required'
[[ -n "${CASH_SUPABASE_DB_URL:-}" ]] || fail 'CASH_SUPABASE_DB_URL is required'

CMD="${1:-}"; [[ -n "$CMD" ]] || { usage; exit 2; }; shift
STUDENT='' ACTOR='' REASON='' CONFIRM='' EXECUTE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --student|--actor)
      need_value "$1" "${2:-}"; need_uuid "$1" "$2"
      [[ "$1" == '--student' ]] && STUDENT="$2" || ACTOR="$2"
      shift 2;;
    --reason) need_value "$1" "${2:-}"; REASON="$2"; shift 2;;
    --confirm) need_value "$1" "${2:-}"; CONFIRM="$2"; shift 2;;
    --execute) EXECUTE=1; shift;;
    -h|--help) usage; exit 0;;
    *) fail "Unknown option: $1";;
  esac
done
[[ -n "$STUDENT" ]] || fail "$CMD requires --student"

school_json() { psql "$SCHOOL_SUPABASE_DB_URL" -X -q -v ON_ERROR_STOP=1 -P pager=off -tA "$@"; }
cash_json() { psql "$CASH_SUPABASE_DB_URL" -X -q -v ON_ERROR_STOP=1 -P pager=off -tA "$@"; }

candidate_json() {
  school_json -v student="$STUDENT" -v entity="$ENTITY_ID" -v month="$SETTLEMENT_MONTH" <<'SQL'
begin read only;
set local request.jwt.claims='{"role":"service_role"}';
select public.school_get_student_monthly_settlement_historical_completion_candidate(
  :'student'::uuid, :'month', :'entity'::uuid
)::text;
commit;
SQL
}

status_json() {
  school_json -v student="$STUDENT" -v entity="$ENTITY_ID" -v month="$SETTLEMENT_MONTH" <<'SQL'
select jsonb_build_object(
  'scope',jsonb_build_object('student_id',:'student'::uuid,'settlement_month',:'month','business_entity_id',:'entity'::uuid),
  'evidence',coalesce((select jsonb_build_object(
    'id',e.id,'final_carry_cny',e.final_carry_cny,'lesson_count',e.lesson_count,
    'lesson_manifest_sha256',e.lesson_manifest_sha256,
    'makeup_source_count',e.makeup_source_count,
    'makeup_remaining_hours',e.makeup_remaining_hours,
    'makeup_manifest_sha256',e.makeup_manifest_sha256,
    'active_revision_id',e.active_revision_id,'tuition_bill_id',e.tuition_bill_id,
    'income_record_id',e.income_record_id,'cash_linkage_event_id',e.cash_linkage_event_id,
    'cash_request_id',e.cash_request_id,'cash_transaction_id',e.cash_transaction_id,
    'cash_transaction_currency',e.cash_transaction_currency,
    'evidence_version',e.evidence_version,
    'evidence_manifest_sha256',e.evidence_manifest_sha256,
    'idempotency_key',e.idempotency_key,'payload_sha256',e.payload_sha256,
    'created_by_actor_id',e.created_by_actor_id,'reason',e.reason,'created_at',e.created_at
  ) from public.school_student_monthly_settlement_historical_completion_evidence e where e.student_id=:'student'::uuid and e.settlement_month=:'month' and e.business_entity_id=:'entity'::uuid),'null'::jsonb),
  'effective_state',(select to_jsonb(r) from public.school_resolve_student_monthly_settlement_effective_state(:'student'::uuid,:'month',:'entity'::uuid) r)
)::text;
SQL
}

if [[ "$CMD" == 'status' ]]; then
  status_json | jq .
  exit 0
fi
[[ "$CMD" == 'create' ]] || fail "Unknown command: $CMD"
[[ -n "$ACTOR" && -n "$REASON" && -n "$CONFIRM" ]] || fail 'create requires --actor --reason --confirm'

CANDIDATE="$(candidate_json)"
print -- "$CANDIDATE" | jq -e . >/dev/null || fail 'School candidate did not return JSON' 1
EXPECTED_CONFIRM="$(print -- "$CANDIDATE" | jq -r '.expected_confirmation')"
[[ "$CONFIRM" == "$EXPECTED_CONFIRM" ]] || fail "Confirmation mismatch. Expected: $EXPECTED_CONFIRM" 1

REQUEST_ID="$(print -- "$CANDIDATE" | jq -r '.cash_request_id')"
TRANSACTION_ID="$(print -- "$CANDIDATE" | jq -r '.cash_transaction_id')"
INCOME_ID="$(print -- "$CANDIDATE" | jq -r '.income_record_id')"
EXPECTED_CNY="$(print -- "$CANDIDATE" | jq -r '.evidence_manifest.billing_amount_cny')"

CASH_FACT="$(cash_json -v request="$REQUEST_ID" -v tx="$TRANSACTION_ID" -v income="$INCOME_ID" <<'SQL'
select jsonb_build_object(
  'request',to_jsonb(r),
  'transaction',to_jsonb(t),
  'valid',(
    r.status='approved' and r.external_source='aozora_school'
    and r.external_reference_type='school_income_records'
    and r.external_reference_id=:'income'::uuid
    and r.currency='CNY' and r.created_transaction_id=:'tx'::uuid
    and t.id=:'tx'::uuid and t.external_source='aozora_school'
    and t.external_reference_type='school_income_records'
    and t.external_reference_id=:'income'::uuid and t.currency='CNY'
    and t.amount=r.amount
  )
)::text
from public.home_external_transaction_requests r
join public.home_cny_transactions t on t.id=r.created_transaction_id
where r.id=:'request'::uuid;
SQL
)"
print -- "$CASH_FACT" | jq -e --argjson expected "$EXPECTED_CNY" \
  '.valid == true and .request.amount == $expected and .transaction.amount == $expected' >/dev/null \
  || fail 'Cash approved request/transaction facts do not match the School frozen candidate' 1

if (( EXECUTE == 0 )); then
  print -- "$CANDIDATE" | jq '{student_id,settlement_month,business_entity_id,lesson_count,lesson_manifest_sha256,makeup_source_count,makeup_remaining_hours,makeup_manifest_sha256,active_revision_id,tuition_bill_id,income_record_id,cash_linkage_event_id,cash_request_id,cash_transaction_id,evidence_manifest_sha256,expected_idempotency_key,expected_confirmation}'
  print -- '{"dry_run":true,"cash_verified":true}'
  exit 0
fi

LESSON_HASH="$(print -- "$CANDIDATE" | jq -r '.lesson_manifest_sha256')"
MAKEUP_HASH="$(print -- "$CANDIDATE" | jq -r '.makeup_manifest_sha256')"
REVISION_ID="$(print -- "$CANDIDATE" | jq -r '.active_revision_id')"
BILL_ID="$(print -- "$CANDIDATE" | jq -r '.tuition_bill_id')"
LINKAGE_ID="$(print -- "$CANDIDATE" | jq -r '.cash_linkage_event_id')"
IDEMPOTENCY="$(print -- "$CANDIDATE" | jq -r '.expected_idempotency_key')"

school_json -v student="$STUDENT" -v entity="$ENTITY_ID" -v month="$SETTLEMENT_MONTH" \
  -v lesson_hash="$LESSON_HASH" -v makeup_hash="$MAKEUP_HASH" -v revision="$REVISION_ID" \
  -v bill="$BILL_ID" -v income="$INCOME_ID" -v linkage="$LINKAGE_ID" \
  -v request="$REQUEST_ID" -v tx="$TRANSACTION_ID" -v actor="$ACTOR" \
  -v reason="$REASON" -v confirmation="$CONFIRM" -v idempotency="$IDEMPOTENCY" <<'SQL' | jq .
begin;
set local request.jwt.claims='{"role":"service_role"}';
select public.school_local_create_student_monthly_settlement_historical_completion_evidence(
  :'student'::uuid,:'month',:'entity'::uuid,:'lesson_hash',:'makeup_hash',
  :'revision'::uuid,:'bill'::uuid,:'income'::uuid,:'linkage'::uuid,
  :'request'::uuid,:'tx'::uuid,:'actor'::uuid,:'reason',:'confirmation',:'idempotency'
)::text;
commit;
SQL

status_json | jq .
