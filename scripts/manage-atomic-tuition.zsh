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
                     [--forward-adjustment-mode neutralize-historical-carryover
                      --reason TEXT]
  reissue            --student UUID --entity UUID --month YYYY-MM --generation UUID
                     --previous-revision UUID --candidate-manifest SHA256
                     --generation-manifest SHA256 --rate NUMERIC --expected-jpy NUMERIC
                     --expected-exchange-cny NUMERIC --expected-cny NUMERIC --note TEXT
                     [--forward-adjustment-mode neutralize-historical-carryover
                      --expected-source-settlement-id UUID --expected-source-revision-id UUID
                      --expected-historical-carryover-cny NUMERIC
                      --expected-forward-adjustment-cny SIGNED_NUMERIC
                      --adjustment-line-manifest SHA256 --reason TEXT]
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
need_signed_number() { [[ "$2" =~ '^-?[0-9]+([.][0-9]+)?$' ]] || fail "$1 must be a numeric"; }

command -v psql >/dev/null 2>&1 || fail 'psql is required'
command -v jq >/dev/null 2>&1 || fail 'jq is required'
command -v curl >/dev/null 2>&1 || fail 'curl is required'
[[ -n "${SCHOOL_SUPABASE_DB_URL:-}" ]] || fail 'SCHOOL_SUPABASE_DB_URL is required'

psql_json() { psql "$SCHOOL_SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -tA "$@"; }

CMD="${1:-}"; [[ -n "$CMD" ]] || { usage; exit 2; }; shift
STUDENT='' ENTITY='' MONTH='' GENERATION='' REVISION='' PREVIOUS_REVISION=''
EXPECTED_REVISION='' BILL='' INCOME='' MANIFEST='' CANDIDATE_MANIFEST=''
GENERATION_MANIFEST='' RATE='' EXPECTED_JPY='' EXPECTED_CNY='' REASON='' NOTE=''
EXPECTED_EXCHANGE_CNY='' FORWARD_ADJUSTMENT_MODE='' EXPECTED_SOURCE_SETTLEMENT=''
EXPECTED_SOURCE_REVISION='' EXPECTED_HISTORICAL_CARRYOVER='' EXPECTED_FORWARD_ADJUSTMENT=''
ADJUSTMENT_LINE_MANIFEST=''
CONFIRM='' EXECUTE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --student|--entity|--generation|--revision|--previous-revision|--bill|--income|--expected-source-settlement-id|--expected-source-revision-id)
      need_value "$1" "${2:-}"; need_uuid "$1" "$2"
      case "$1" in
        --student) STUDENT="$2";; --entity) ENTITY="$2";; --generation) GENERATION="$2";;
        --revision) REVISION="$2";; --previous-revision) PREVIOUS_REVISION="$2";;
        --bill) BILL="$2";; --income) INCOME="$2";;
        --expected-source-settlement-id) EXPECTED_SOURCE_SETTLEMENT="$2";;
        --expected-source-revision-id) EXPECTED_SOURCE_REVISION="$2";;
      esac; shift 2;;
    --month) need_value "$1" "${2:-}"; need_month "$1" "$2"; MONTH="$2"; shift 2;;
    --manifest|--candidate-manifest|--generation-manifest|--adjustment-line-manifest)
      need_value "$1" "${2:-}"; need_sha "$1" "$2"
      [[ "$1" == '--manifest' ]] && MANIFEST="$2"
      [[ "$1" == '--candidate-manifest' ]] && CANDIDATE_MANIFEST="$2"
      [[ "$1" == '--generation-manifest' ]] && GENERATION_MANIFEST="$2"
      [[ "$1" == '--adjustment-line-manifest' ]] && ADJUSTMENT_LINE_MANIFEST="$2"
      shift 2;;
    --rate|--expected-jpy|--expected-cny|--expected-exchange-cny|--expected-historical-carryover-cny)
      need_value "$1" "${2:-}"; need_number "$1" "$2"
      [[ "$1" == '--rate' ]] && RATE="$2"
      [[ "$1" == '--expected-jpy' ]] && EXPECTED_JPY="$2"
      [[ "$1" == '--expected-cny' ]] && EXPECTED_CNY="$2"
      [[ "$1" == '--expected-exchange-cny' ]] && EXPECTED_EXCHANGE_CNY="$2"
      [[ "$1" == '--expected-historical-carryover-cny' ]] && EXPECTED_HISTORICAL_CARRYOVER="$2"
      shift 2;;
    --expected-forward-adjustment-cny)
      need_value "$1" "${2:-}"; need_signed_number "$1" "$2"; EXPECTED_FORWARD_ADJUSTMENT="$2"; shift 2;;
    --forward-adjustment-mode)
      need_value "$1" "${2:-}"
      [[ "$2" == 'neutralize-historical-carryover' ]] || fail '--forward-adjustment-mode only accepts neutralize-historical-carryover'
      FORWARD_ADJUSTMENT_MODE="$2"; shift 2;;
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
    a.id forward_adjustment_id,a.adjustment_type forward_adjustment_type,
    a.amount_cny forward_adjustment_cny,a.source_historical_carryover_cny,
    a.source_settlement_id forward_adjustment_source_settlement_id,a.line_manifest_sha256,
    (select count(*) from public.school_student_tuition_bill_lessons x where x.tuition_bill_id=b.id) lesson_claim_count,
    (select count(*) from public.school_personal_cash_income_linkage_events e where e.income_record_id=i.id or (e.source_table='school_income_records' and e.source_id=i.id)) school_cash_blocker_count,
    r.created_at,r.voided_at
  from scope g join public.school_student_tuition_generation_revisions r on r.generation_identity_id=g.id
  join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
  join public.school_income_records i on i.id=b.income_record_id
  left join public.school_student_tuition_generation_revision_adjustments a on a.target_revision_id=r.id
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
    [[ -z "$FORWARD_ADJUSTMENT_MODE" || -n "${REASON//[[:space:]]/}" ]] || fail 'forward-adjustment preview requires --reason'
    DB_ADJUSTMENT_TYPE=''
    [[ "$FORWARD_ADJUSTMENT_MODE" == 'neutralize-historical-carryover' ]] && DB_ADJUSTMENT_TYPE='neutralize_historical_carryover_v1'
    if [[ -z "$DB_ADJUSTMENT_TYPE" ]]; then
      psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" -v generation="$GENERATION" -v rate="$RATE" <<'SQL'
with guard as (
 select g.id,
   (select r.id from public.school_student_tuition_generation_revisions r
    where r.generation_identity_id=g.id order by r.revision_no desc limit 1) previous_revision_id,
   (select r.revision_no+1 from public.school_student_tuition_generation_revisions r
    where r.generation_identity_id=g.id order by r.revision_no desc limit 1) next_revision_no
 from public.school_student_tuition_generation_identities g
 where g.id=:'generation'::uuid and g.student_id=:'student'::uuid
   and g.business_entity_id=:'entity'::uuid
   and g.billing_month=to_date(:'month'||'-01','YYYY-MM-DD')
   and not exists(select 1 from public.school_student_tuition_generation_revisions r
     where r.generation_identity_id=g.id and r.lifecycle_status='active')
   and exists(select 1 from public.school_student_tuition_generation_revisions r
     where r.generation_identity_id=g.id and r.lifecycle_status='voided'
       and r.manifest_kind='atomic_generation_v1')
), preview as (
 select p.* from guard cross join lateral public.school_build_student_tuition_generation_snapshot(
   :'student'::uuid,:'month',:'rate'::numeric
 ) p
)
select jsonb_pretty(to_jsonb(preview)||jsonb_build_object(
  'generation_identity_id',(select id from guard),
  'previous_revision_id',(select previous_revision_id from guard),
  'next_revision_no',(select next_revision_no from guard),
  'script_forward_adjustment_mode',null,
  'amount_authority','database','dry_run',true
))::text from preview;
SQL
      exit 0
    fi
    psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" -v generation="$GENERATION" -v rate="$RATE" -v adjustment_type="$DB_ADJUSTMENT_TYPE" -v reason="$REASON" <<'SQL'
with guard as (
 select g.id,(select id from public.school_student_tuition_generation_revisions r where r.generation_identity_id=g.id order by revision_no desc limit 1) previous_revision_id
 from public.school_student_tuition_generation_identities g
 where g.id=:'generation'::uuid and g.student_id=:'student'::uuid and g.business_entity_id=:'entity'::uuid
   and g.billing_month=to_date(:'month'||'-01','YYYY-MM-DD')
   and not exists(select 1 from public.school_student_tuition_generation_revisions r where r.generation_identity_id=g.id and r.lifecycle_status='active')
   and exists(select 1 from public.school_student_tuition_generation_revisions r where r.generation_identity_id=g.id and r.lifecycle_status='voided' and r.manifest_kind='atomic_generation_v1')
), preview as (
 select p.* from guard cross join lateral public.school_get_atomic_tuition_reissue_preview_p0e(
   (select id from guard),(select previous_revision_id from guard),:'student'::uuid,:'entity'::uuid,
   :'month',:'rate'::numeric,nullif(:'adjustment_type',''),nullif(:'reason','')
 ) p
)
select jsonb_pretty(to_jsonb(preview)||jsonb_build_object(
  'script_forward_adjustment_mode',nullif(:'adjustment_type',''),
  'amount_authority','database','dry_run',true
))::text from preview;
SQL
    ;;
  reissue)
    [[ -n "$STUDENT" && -n "$ENTITY" && -n "$MONTH" && -n "$GENERATION" && -n "$PREVIOUS_REVISION" && -n "$CANDIDATE_MANIFEST" && -n "$GENERATION_MANIFEST" && -n "$RATE" && -n "$EXPECTED_JPY" && -n "$EXPECTED_CNY" && -n "${NOTE//[[:space:]]/}" ]] || fail 'reissue requires every exact expected fact and note'
    if [[ -n "$FORWARD_ADJUSTMENT_MODE" ]]; then
      [[ -n "$EXPECTED_EXCHANGE_CNY" && -n "$EXPECTED_SOURCE_SETTLEMENT" && -n "$EXPECTED_SOURCE_REVISION" && -n "$EXPECTED_HISTORICAL_CARRYOVER" && -n "$EXPECTED_FORWARD_ADJUSTMENT" && -n "$ADJUSTMENT_LINE_MANIFEST" && -n "${REASON//[[:space:]]/}" ]] || fail 'P0-E reissue requires complete source, exchange, carry, forward adjustment, line manifest and reason expected facts'
      [[ "$EXPECTED_SOURCE_REVISION" == "$PREVIOUS_REVISION" ]] || fail '--expected-source-revision-id must equal --previous-revision'
    fi
    if (( ! EXECUTE )); then print -- 'DRY-RUN: run reissue-preview and compare every DB-authoritative expected fact; no write performed.'; exit 0; fi
    if [[ -n "$FORWARD_ADJUSTMENT_MODE" ]]; then
      EXPECTED_CONFIRM="REISSUE ATOMIC TUITION $STUDENT $MONTH RATE $RATE CARRY $EXPECTED_HISTORICAL_CARRYOVER FORWARD $EXPECTED_FORWARD_ADJUSTMENT FINAL $EXPECTED_CNY"
    else
      EXPECTED_CONFIRM="REISSUE ATOMIC TUITION $GENERATION AFTER $PREVIOUS_REVISION"
    fi
    [[ "$CONFIRM" == "$EXPECTED_CONFIRM" ]] || fail "Confirmation mismatch; expected: $EXPECTED_CONFIRM"
    if [[ -n "$FORWARD_ADJUSTMENT_MODE" ]]; then
      psql_json -v generation="$GENERATION" -v previous="$PREVIOUS_REVISION" -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" -v candidate="$CANDIDATE_MANIFEST" -v manifest="$GENERATION_MANIFEST" -v rate="$RATE" -v jpy="$EXPECTED_JPY" -v exchange="$EXPECTED_EXCHANGE_CNY" -v source_settlement="$EXPECTED_SOURCE_SETTLEMENT" -v carry="$EXPECTED_HISTORICAL_CARRYOVER" -v adjustment="$EXPECTED_FORWARD_ADJUSTMENT" -v line_manifest="$ADJUSTMENT_LINE_MANIFEST" -v cny="$EXPECTED_CNY" -v reason="$REASON" -v note="$NOTE" <<'SQL'
select jsonb_pretty(to_jsonb(r))::text
from public.school_reissue_atomic_student_tuition_generation_p0e_local(
 :'generation'::uuid,:'previous'::uuid,:'student'::uuid,:'entity'::uuid,:'month',
 :'candidate',:'manifest',:'rate'::numeric,:'jpy'::numeric,:'exchange'::numeric,
 :'source_settlement'::uuid,:'carry'::numeric,'neutralize_historical_carryover_v1',
 :'adjustment'::numeric,:'line_manifest',:'cny'::numeric,:'reason',:'note'
) r;
SQL
      status_json
      exit 0
    fi
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
 'forward_adjustments',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at,a.id) from public.school_student_tuition_generation_revision_adjustments a where a.generation_identity_id=:'generation'::uuid),'[]'::jsonb),
 'void_events',coalesce((select jsonb_agg(to_jsonb(e) order by created_at) from public.school_student_tuition_generation_void_events e where e.generation_identity_id=:'generation'::uuid),'[]'::jsonb)
))::text;
SQL
    ;;
  *) usage; fail "Unknown command: $CMD";;
esac
