#!/usr/bin/env zsh
set -euo pipefail

readonly OPERATOR_AUTHORITY='local_trusted_business_owner_v1'
readonly UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
readonly SHA_RE='^[0-9a-f]{64}$'

usage() {
  cat <<'USAGE'
Usage: scripts/manage-atomic-tuition.zsh COMMAND [exact options]

Commands:
  status             --student UUID --entity UUID --month YYYY-MM [--generation UUID]
  void-preflight     --income UUID
  void               --student UUID --entity UUID --month YYYY-MM --revision UUID
                     --expected-revision N --bill UUID --income UUID --manifest SHA256
                     --reason TEXT [--execute --confirm 'VOID ATOMIC TUITION ...']
  reissue-preview    --student UUID --entity UUID --month YYYY-MM --generation UUID
                     --rate NUMERIC --note TEXT
  reissue            --student UUID --entity UUID --month YYYY-MM --generation UUID
                     --previous-revision UUID --candidate-manifest SHA256
                     --generation-manifest SHA256 --rate NUMERIC --expected-jpy NUMERIC
                     --expected-cny NUMERIC --note TEXT
                     [--execute --confirm 'REISSUE ATOMIC TUITION ...']
  history            --generation UUID

Void and reissue are dry-run unless --execute is present. There is no combined command.
After any network/RPC error, run status before deciding whether to retry.
USAGE
}

fail() { print -u2 -- "$1"; exit "${2:-2}"; }
need_value() { [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value"; }
need_uuid() { [[ "$2" =~ $UUID_RE ]] || fail "$1 must be a UUID"; }
need_sha() { [[ "$2" =~ $SHA_RE ]] || fail "$1 must be a lowercase SHA-256"; }
need_month() { [[ "$2" =~ '^[0-9]{4}-(0[1-9]|1[0-2])$' ]] || fail "$1 must be YYYY-MM"; }
need_number() { [[ "$2" =~ '^[0-9]+([.][0-9]+)?$' ]] || fail "$1 must be a non-negative numeric"; }

command -v psql >/dev/null 2>&1 || fail 'psql is required'
command -v jq >/dev/null 2>&1 || fail 'jq is required'
command -v curl >/dev/null 2>&1 || fail 'curl is required'
[[ -n "${SCHOOL_SUPABASE_DB_URL:-}" ]] || fail 'SCHOOL_SUPABASE_DB_URL is required'

psql_json() { psql "$SCHOOL_SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -tA "$@"; }

CMD="${1:-}"; [[ -n "$CMD" ]] || { usage; exit 2; }; shift
STUDENT='' ENTITY='' MONTH='' GENERATION='' REVISION='' PREVIOUS_REVISION=''
EXPECTED_REVISION='' BILL='' INCOME='' MANIFEST='' CANDIDATE_MANIFEST=''
GENERATION_MANIFEST='' RATE='' EXPECTED_JPY='' EXPECTED_CNY='' REASON='' NOTE=''
CONFIRM='' EXECUTE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --student|--entity|--generation|--revision|--previous-revision|--bill|--income)
      need_value "$1" "${2:-}"; need_uuid "$1" "$2"
      case "$1" in
        --student) STUDENT="$2";; --entity) ENTITY="$2";; --generation) GENERATION="$2";;
        --revision) REVISION="$2";; --previous-revision) PREVIOUS_REVISION="$2";;
        --bill) BILL="$2";; --income) INCOME="$2";;
      esac; shift 2;;
    --month) need_value "$1" "${2:-}"; need_month "$1" "$2"; MONTH="$2"; shift 2;;
    --manifest|--candidate-manifest|--generation-manifest)
      need_value "$1" "${2:-}"; need_sha "$1" "$2"
      [[ "$1" == '--manifest' ]] && MANIFEST="$2"
      [[ "$1" == '--candidate-manifest' ]] && CANDIDATE_MANIFEST="$2"
      [[ "$1" == '--generation-manifest' ]] && GENERATION_MANIFEST="$2"
      shift 2;;
    --rate|--expected-jpy|--expected-cny)
      need_value "$1" "${2:-}"; need_number "$1" "$2"
      [[ "$1" == '--rate' ]] && RATE="$2"
      [[ "$1" == '--expected-jpy' ]] && EXPECTED_JPY="$2"
      [[ "$1" == '--expected-cny' ]] && EXPECTED_CNY="$2"
      shift 2;;
    --expected-revision) need_value "$1" "${2:-}"; [[ "$2" =~ '^[1-9][0-9]*$' ]] || fail '--expected-revision must be positive'; EXPECTED_REVISION="$2"; shift 2;;
    --reason) need_value "$1" "${2:-}"; REASON="$2"; shift 2;;
    --note) need_value "$1" "${2:-}"; NOTE="$2"; shift 2;;
    --confirm) need_value "$1" "${2:-}"; CONFIRM="$2"; shift 2;;
    --execute) EXECUTE=1; shift;;
    -h|--help) usage; exit 0;;
    *) fail "Unknown option: $1";;
  esac
done

status_json() {
  psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" -v generation="$GENERATION" <<'SQL'
with scope as (
  select g.* from public.school_student_tuition_generation_identities g
  where g.student_id=:'student'::uuid and g.business_entity_id=:'entity'::uuid
    and g.billing_month=to_date(:'month'||'-01','YYYY-MM-DD')
    and (nullif(:'generation','') is null or g.id=nullif(:'generation','')::uuid)
), rows as (
  select g.id generation_identity_id,r.id generation_revision_id,r.revision_no,
    r.lifecycle_status,r.manifest_kind,r.generation_manifest_sha256,b.id tuition_bill_id,
    i.id income_record_id,b.bill_amount_jpy,b.billing_amount_cny,b.billing_exchange_rate,
    b.previous_carryover_cny,b.previous_settlement_id,b.previous_settlement_month,
    b.status bill_status,i.status income_status,
    (select count(*) from public.school_student_tuition_bill_lessons x where x.tuition_bill_id=b.id) lesson_claim_count,
    (select count(*) from public.school_personal_cash_income_linkage_events e where e.income_record_id=i.id or (e.source_table='school_income_records' and e.source_id=i.id)) school_cash_blocker_count,
    r.created_at,r.voided_at
  from scope g join public.school_student_tuition_generation_revisions r on r.generation_identity_id=g.id
  join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
  join public.school_income_records i on i.id=b.income_record_id
)
select jsonb_pretty(jsonb_build_object(
  'operator_authority','local_trusted_business_owner_v1',
  'gate',(select jsonb_object_agg(feature_key,state) from public.school_feature_gates where feature_key like 'student_tuition_%'),
  'revisions',coalesce((select jsonb_agg(to_jsonb(rows) order by revision_no) from rows),'[]'::jsonb)
))::text;
SQL
}

preflight_json() {
  psql_json -v income="$INCOME" <<'SQL'
select jsonb_pretty(to_jsonb(p)||jsonb_build_object(
  'settlement_notice','Any settlement consumed by any revision remains permanently immutable.',
  'reason_required',true
))::text from public.school_get_atomic_tuition_void_preflight(:'income'::uuid) p;
SQL
}

edge_preflight_json() {
  [[ -n "${SCHOOL_SUPABASE_URL:-}" && -n "${SCHOOL_SUPABASE_SERVICE_ROLE_KEY:-}" ]] || fail 'Cash-authoritative preflight requires SCHOOL_SUPABASE_URL and SCHOOL_SUPABASE_SERVICE_ROLE_KEY'
  local school_preview body
  school_preview="$(preflight_json)" || fail 'School Void preflight failed; zero writes performed' 1
  body="$(print -- "$school_preview" | jq -c '{generation_revision_id:.generation_revision_id,tuition_bill_id:.tuition_bill_id,income_record_id:.income_record_id,expected_generation_manifest_sha256:.generation_manifest_sha256,preflight_only:true}')"
  curl --fail-with-body --silent --show-error -X POST "$SCHOOL_SUPABASE_URL/functions/v1/void-atomic-tuition-generation" \
    -H "Authorization: Bearer $SCHOOL_SUPABASE_SERVICE_ROLE_KEY" \
    -H "apikey: $SCHOOL_SUPABASE_SERVICE_ROLE_KEY" \
    -H 'Content-Type: application/json' --data-binary "$body"
}

case "$CMD" in
  status)
    [[ -n "$STUDENT" && -n "$ENTITY" && -n "$MONTH" ]] || fail 'status requires --student --entity --month'
    status_json;;
  void-preflight)
    [[ -n "$INCOME" ]] || fail 'void-preflight requires --income'
    edge_preflight_json | jq .;;
  void)
    [[ -n "$STUDENT" && -n "$ENTITY" && -n "$MONTH" && -n "$REVISION" && -n "$EXPECTED_REVISION" && -n "$BILL" && -n "$INCOME" && -n "$MANIFEST" && -n "${REASON//[[:space:]]/}" ]] || fail 'void requires every exact expected fact and a non-empty reason'
    PREVIEW="$(edge_preflight_json)" || fail 'Void preflight failed; zero writes performed' 1
    print -- "$PREVIEW"
    if (( ! EXECUTE )); then print -- 'DRY-RUN: no write performed.'; exit 0; fi
    [[ -n "${SCHOOL_SUPABASE_URL:-}" && -n "${SCHOOL_SUPABASE_SERVICE_ROLE_KEY:-}" ]] || fail 'Execute requires SCHOOL_SUPABASE_URL and SCHOOL_SUPABASE_SERVICE_ROLE_KEY'
    EXPECTED_CONFIRM="VOID ATOMIC TUITION $STUDENT $MONTH REVISION $EXPECTED_REVISION"
    [[ "$CONFIRM" == "$EXPECTED_CONFIRM" ]] || fail "Confirmation mismatch; expected: $EXPECTED_CONFIRM"
    print -- "$PREVIEW" | jq -e --arg r "$REVISION" --arg b "$BILL" --arg i "$INCOME" --arg m "$MANIFEST" --argjson n "$EXPECTED_REVISION" '.ok == true and .cash_fact_count == 0 and .preflight.eligible == true and .preflight.generation_revision_id == $r and .preflight.tuition_bill_id == $b and .preflight.income_record_id == $i and .preflight.generation_manifest_sha256 == $m and .preflight.revision_no == $n' >/dev/null || fail 'Fresh preflight does not match exact expected facts' 1
    BODY="$(jq -nc --arg r "$REVISION" --arg b "$BILL" --arg i "$INCOME" --arg m "$MANIFEST" --arg reason "$REASON" '{generation_revision_id:$r,tuition_bill_id:$b,income_record_id:$i,expected_generation_manifest_sha256:$m,reason:$reason}')"
    RESULT="$(curl --fail-with-body --silent --show-error -X POST "$SCHOOL_SUPABASE_URL/functions/v1/void-atomic-tuition-generation" -H "Authorization: Bearer $SCHOOL_SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SCHOOL_SUPABASE_SERVICE_ROLE_KEY" -H 'Content-Type: application/json' --data-binary "$BODY")" || fail 'Void network/RPC failure. Run status before any retry.' 1
    print -- "$RESULT" | jq -e '.ok == true' >/dev/null || { print -- "$RESULT"; fail 'Void RPC rejected. No automatic retry.' 1; }
    print -- "$RESULT" | jq .
    status_json;;
  reissue-preview)
    [[ -n "$STUDENT" && -n "$ENTITY" && -n "$MONTH" && -n "$GENERATION" && -n "$RATE" && -n "${NOTE//[[:space:]]/}" ]] || fail 'reissue-preview requires exact scope, --rate and --note'
    psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" -v generation="$GENERATION" -v rate="$RATE" <<'SQL'
with guard as (
 select g.id,(select id from public.school_student_tuition_generation_revisions r where r.generation_identity_id=g.id order by revision_no desc limit 1) previous_revision_id
 from public.school_student_tuition_generation_identities g
 where g.id=:'generation'::uuid and g.student_id=:'student'::uuid and g.business_entity_id=:'entity'::uuid
   and g.billing_month=to_date(:'month'||'-01','YYYY-MM-DD')
   and not exists(select 1 from public.school_student_tuition_generation_revisions r where r.generation_identity_id=g.id and r.lifecycle_status='active')
   and exists(select 1 from public.school_student_tuition_generation_revisions r where r.generation_identity_id=g.id and r.lifecycle_status='voided' and r.manifest_kind='atomic_generation_v1')
), preview as (select p.* from guard cross join lateral public.school_get_student_tuition_validation_preview_details(:'student'::uuid,:'month',:'rate'::numeric) p)
select jsonb_pretty(to_jsonb(preview)||jsonb_build_object('generation_identity_id',(select id from guard),'previous_revision_id',(select previous_revision_id from guard)))::text from preview;
SQL
    ;;
  reissue)
    [[ -n "$STUDENT" && -n "$ENTITY" && -n "$MONTH" && -n "$GENERATION" && -n "$PREVIOUS_REVISION" && -n "$CANDIDATE_MANIFEST" && -n "$GENERATION_MANIFEST" && -n "$RATE" && -n "$EXPECTED_JPY" && -n "$EXPECTED_CNY" && -n "${NOTE//[[:space:]]/}" ]] || fail 'reissue requires every exact expected fact and note'
    if (( ! EXECUTE )); then print -- 'DRY-RUN: run reissue-preview and compare every DB-authoritative expected fact; no write performed.'; exit 0; fi
    EXPECTED_CONFIRM="REISSUE ATOMIC TUITION $GENERATION AFTER $PREVIOUS_REVISION"
    [[ "$CONFIRM" == "$EXPECTED_CONFIRM" ]] || fail "Confirmation mismatch; expected: $EXPECTED_CONFIRM"
    psql_json -v generation="$GENERATION" -v previous="$PREVIOUS_REVISION" -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" -v candidate="$CANDIDATE_MANIFEST" -v manifest="$GENERATION_MANIFEST" -v rate="$RATE" -v jpy="$EXPECTED_JPY" -v cny="$EXPECTED_CNY" -v note="$NOTE" <<'SQL'
select jsonb_pretty(to_jsonb(r))::text
from public.school_reissue_atomic_student_tuition_generation_local(
 :'generation'::uuid,:'previous'::uuid,:'student'::uuid,:'entity'::uuid,:'month',
 :'candidate',:'manifest',:'rate'::numeric,:'jpy'::numeric,:'cny'::numeric,:'note'
) r;
SQL
    status_json;;
  history)
    [[ -n "$GENERATION" ]] || fail 'history requires --generation'
    psql_json -v generation="$GENERATION" <<'SQL'
select jsonb_pretty(jsonb_build_object(
 'revisions',coalesce((select jsonb_agg(to_jsonb(r) order by revision_no) from public.school_student_tuition_generation_revisions r where r.generation_identity_id=:'generation'::uuid),'[]'::jsonb),
 'void_events',coalesce((select jsonb_agg(to_jsonb(e) order by created_at) from public.school_student_tuition_generation_void_events e where e.generation_identity_id=:'generation'::uuid),'[]'::jsonb)
))::text;
SQL
    ;;
  *) usage; fail "Unknown command: $CMD";;
esac
