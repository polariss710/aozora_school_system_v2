#!/usr/bin/env zsh
set -euo pipefail

readonly OPERATOR_AUTHORITY='local_trusted_business_owner_v1'
readonly UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
readonly SHA_RE='^[0-9a-f]{64}$'

usage() {
  cat <<'USAGE'
Usage: scripts/manage-student-settlement.zsh COMMAND [exact options]

Commands:
  status       --student UUID --entity UUID --month YYYY-MM
  history      --student UUID --entity UUID --month YYYY-MM
  preview      --student UUID --entity UUID --month YYYY-MM --source-mode MODE
               --rate NUMERIC --rate-source TEXT --rate-date YYYY-MM-DD
               --adjustment-mode MODE [--explicit-amount-cny NUMERIC]
  save-draft   preview options plus all expected facts, --reason TEXT [--note TEXT]
               [--execute --confirm 'SAVE STUDENT SETTLEMENT DRAFT ...']
  lock         save-draft expected facts plus --source-draft UUID
               --source-draft-updated-at TIMESTAMPTZ --adjustment-draft UUID
               --adjustment-draft-updated-at TIMESTAMPTZ [--note TEXT]
               [--execute --confirm 'LOCK STUDENT SETTLEMENT ...']

Expected facts required by save-draft and lock:
  --preview-manifest SHA256 --lesson-manifest SHA256 --source-count N
  --expected-unused-jpy NUMERIC --expected-overage-jpy NUMERIC
  --expected-net-jpy NUMERIC --expected-net-cny NUMERIC
  --expected-system-difference-cny NUMERIC --expected-final-carryover-cny NUMERIC

save-draft and lock are dry-run unless --execute is present. After an ambiguous
network result, run status before considering any retry.
USAGE
}

fail() { print -u2 -- "$1"; exit "${2:-2}"; }
need_value() { [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value"; }
need_uuid() { [[ "$2" =~ $UUID_RE ]] || fail "$1 must be a UUID"; }
need_sha() { [[ "$2" =~ $SHA_RE ]] || fail "$1 must be a lowercase SHA-256"; }
need_month() { [[ "$2" =~ '^[0-9]{4}-(0[1-9]|1[0-2])$' ]] || fail "$1 must be YYYY-MM"; }
need_date() { [[ "$2" =~ '^[0-9]{4}-(0[1-9]|1[0-2])-[0-9]{2}$' ]] || fail "$1 must be YYYY-MM-DD"; }
need_number() { [[ "$2" =~ '^-?[0-9]+([.][0-9]+)?$' ]] || fail "$1 must be numeric"; }
need_integer() { [[ "$2" =~ '^[0-9]+$' ]] || fail "$1 must be a non-negative integer"; }

command -v psql >/dev/null 2>&1 || fail 'psql is required'
command -v jq >/dev/null 2>&1 || fail 'jq is required'
[[ -n "${SCHOOL_SUPABASE_DB_URL:-}" ]] || fail 'SCHOOL_SUPABASE_DB_URL is required'

psql_json() { psql "$SCHOOL_SUPABASE_DB_URL" -X -q -v ON_ERROR_STOP=1 -P pager=off -tA "$@"; }

CMD="${1:-}"; [[ -n "$CMD" ]] || { usage; exit 2; }; shift
STUDENT='' ENTITY='' MONTH='' SOURCE_MODE='' RATE='' RATE_SOURCE='' RATE_DATE=''
ADJUSTMENT_MODE='' EXPLICIT_AMOUNT='' PREVIEW_MANIFEST='' LESSON_MANIFEST=''
SOURCE_COUNT='' EXPECTED_UNUSED_JPY='' EXPECTED_OVERAGE_JPY='' EXPECTED_NET_JPY=''
EXPECTED_NET_CNY='' EXPECTED_SYSTEM_DIFFERENCE='' EXPECTED_FINAL_CARRYOVER=''
SOURCE_DRAFT='' SOURCE_DRAFT_UPDATED_AT='' ADJUSTMENT_DRAFT=''
ADJUSTMENT_DRAFT_UPDATED_AT='' REASON='' NOTE='' CONFIRM='' EXECUTE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --student|--entity|--source-draft|--adjustment-draft)
      need_value "$1" "${2:-}"; need_uuid "$1" "$2"
      [[ "$1" == '--student' ]] && STUDENT="$2"
      [[ "$1" == '--entity' ]] && ENTITY="$2"
      [[ "$1" == '--source-draft' ]] && SOURCE_DRAFT="$2"
      [[ "$1" == '--adjustment-draft' ]] && ADJUSTMENT_DRAFT="$2"
      shift 2;;
    --month) need_value "$1" "${2:-}"; need_month "$1" "$2"; MONTH="$2"; shift 2;;
    --rate-date) need_value "$1" "${2:-}"; need_date "$1" "$2"; RATE_DATE="$2"; shift 2;;
    --preview-manifest|--lesson-manifest)
      need_value "$1" "${2:-}"; need_sha "$1" "$2"
      [[ "$1" == '--preview-manifest' ]] && PREVIEW_MANIFEST="$2" || LESSON_MANIFEST="$2"
      shift 2;;
    --rate|--explicit-amount-cny|--expected-unused-jpy|--expected-overage-jpy|--expected-net-jpy|--expected-net-cny|--expected-system-difference-cny|--expected-final-carryover-cny)
      need_value "$1" "${2:-}"; need_number "$1" "$2"
      case "$1" in
        --rate) RATE="$2";; --explicit-amount-cny) EXPLICIT_AMOUNT="$2";;
        --expected-unused-jpy) EXPECTED_UNUSED_JPY="$2";;
        --expected-overage-jpy) EXPECTED_OVERAGE_JPY="$2";;
        --expected-net-jpy) EXPECTED_NET_JPY="$2";;
        --expected-net-cny) EXPECTED_NET_CNY="$2";;
        --expected-system-difference-cny) EXPECTED_SYSTEM_DIFFERENCE="$2";;
        --expected-final-carryover-cny) EXPECTED_FINAL_CARRYOVER="$2";;
      esac
      shift 2;;
    --source-count) need_value "$1" "${2:-}"; need_integer "$1" "$2"; SOURCE_COUNT="$2"; shift 2;;
    --source-mode) need_value "$1" "${2:-}"; SOURCE_MODE="$2"; shift 2;;
    --rate-source) need_value "$1" "${2:-}"; RATE_SOURCE="$2"; shift 2;;
    --adjustment-mode) need_value "$1" "${2:-}"; ADJUSTMENT_MODE="$2"; shift 2;;
    --source-draft-updated-at) need_value "$1" "${2:-}"; SOURCE_DRAFT_UPDATED_AT="$2"; shift 2;;
    --adjustment-draft-updated-at) need_value "$1" "${2:-}"; ADJUSTMENT_DRAFT_UPDATED_AT="$2"; shift 2;;
    --reason) need_value "$1" "${2:-}"; REASON="$2"; shift 2;;
    --note) need_value "$1" "${2:-}"; NOTE="$2"; shift 2;;
    --confirm) need_value "$1" "${2:-}"; CONFIRM="$2"; shift 2;;
    --execute) EXECUTE=1; shift;;
    -h|--help) usage; exit 0;;
    *) fail "Unknown option: $1";;
  esac
done

require_scope() {
  [[ -n "$STUDENT" && -n "$ENTITY" && -n "$MONTH" ]] || fail "$CMD requires --student --entity --month"
}

require_preview_input() {
  require_scope
  [[ -n "$SOURCE_MODE" && -n "$RATE" && -n "$RATE_SOURCE" && -n "$RATE_DATE" && -n "$ADJUSTMENT_MODE" ]] \
    || fail "$CMD requires source mode, rate, rate source/date and adjustment mode"
  [[ "$ADJUSTMENT_MODE" == 'manual_adjustment' || -z "$EXPLICIT_AMOUNT" ]] \
    || fail 'explicit amount is only allowed for manual_adjustment'
  [[ "$ADJUSTMENT_MODE" != 'manual_adjustment' || -n "$EXPLICIT_AMOUNT" ]] \
    || fail 'manual_adjustment requires --explicit-amount-cny'
}

require_expected() {
  require_preview_input
  [[ -n "$PREVIEW_MANIFEST" && -n "$LESSON_MANIFEST" && -n "$SOURCE_COUNT" \
     && -n "$EXPECTED_UNUSED_JPY" && -n "$EXPECTED_OVERAGE_JPY" && -n "$EXPECTED_NET_JPY" \
     && -n "$EXPECTED_NET_CNY" && -n "$EXPECTED_SYSTEM_DIFFERENCE" \
     && -n "$EXPECTED_FINAL_CARRYOVER" ]] || fail "$CMD requires every expected fact"
}

preview_json() {
  local explicit_sql='null'
  [[ -n "$EXPLICIT_AMOUNT" ]] && explicit_sql=":'explicit'::numeric"
  psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" \
    -v source_mode="$SOURCE_MODE" -v rate="$RATE" -v rate_source="$RATE_SOURCE" \
    -v rate_date="$RATE_DATE" -v adjustment_mode="$ADJUSTMENT_MODE" \
    -v explicit="$EXPLICIT_AMOUNT" <<SQL
select jsonb_pretty(public.school_preview_student_settlement_adjustment_dialog(
  :'student'::uuid,:'entity'::uuid,:'month',:'source_mode',:'rate'::numeric,
  :'rate_source',:'rate_date'::date,:'adjustment_mode',$explicit_sql
))::text;
SQL
}

verify_preview() {
  local preview="$1"
  print -- "$preview" | jq -e \
    --arg preview_manifest "$PREVIEW_MANIFEST" --arg lesson_manifest "$LESSON_MANIFEST" \
    --argjson source_count "$SOURCE_COUNT" --argjson unused "$EXPECTED_UNUSED_JPY" \
    --argjson overage "$EXPECTED_OVERAGE_JPY" --argjson net_jpy "$EXPECTED_NET_JPY" \
    --argjson net_cny "$EXPECTED_NET_CNY" --argjson difference "$EXPECTED_SYSTEM_DIFFERENCE" \
    --argjson carry "$EXPECTED_FINAL_CARRYOVER" '
      .preview_manifest_sha256 == $preview_manifest
      and .preview_expected_facts.lesson_variance_manifest_sha256 == $lesson_manifest
      and .preview.lesson_variance_source_count == $source_count
      and .preview.unused_planned_credit_jpy == $unused
      and .preview.overage_charge_jpy == $overage
      and .preview.net_lesson_variance_jpy == $net_jpy
      and .preview.net_lesson_variance_cny == $net_cny
      and .preview_expected_facts.system_difference_cny == $difference
      and .preview.projected_final_carryover_cny == $carry' >/dev/null \
    || fail 'Fresh DB preview does not match the supplied expected facts' 1
}

save_execute_json() {
  local explicit_sql='null'
  [[ -n "$EXPLICIT_AMOUNT" ]] && explicit_sql=":'explicit'::numeric"
  psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" \
    -v source_mode="$SOURCE_MODE" -v rate="$RATE" -v rate_source="$RATE_SOURCE" \
    -v rate_date="$RATE_DATE" -v adjustment_mode="$ADJUSTMENT_MODE" -v explicit="$EXPLICIT_AMOUNT" \
    -v preview_manifest="$PREVIEW_MANIFEST" -v lesson_manifest="$LESSON_MANIFEST" \
    -v source_count="$SOURCE_COUNT" -v unused="$EXPECTED_UNUSED_JPY" \
    -v overage="$EXPECTED_OVERAGE_JPY" -v net_jpy="$EXPECTED_NET_JPY" \
    -v net_cny="$EXPECTED_NET_CNY" -v difference="$EXPECTED_SYSTEM_DIFFERENCE" \
    -v carry="$EXPECTED_FINAL_CARRYOVER" -v reason="$REASON" -v note="$NOTE" \
    -v authority="$OPERATOR_AUTHORITY" -v confirmation="$CONFIRM" <<SQL
begin;
set local request.jwt.claims='{"role":"service_role"}';
select jsonb_pretty(public.school_save_student_settlement_draft_local(
  :'student'::uuid,:'entity'::uuid,:'month',:'source_mode',:'rate'::numeric,
  :'rate_source',:'rate_date'::date,:'adjustment_mode',$explicit_sql,
  :'preview_manifest',:'lesson_manifest',:'source_count'::integer,
  :'unused'::numeric,:'overage'::numeric,:'net_jpy'::numeric,:'net_cny'::numeric,
  :'difference'::numeric,:'carry'::numeric,:'reason',nullif(:'note',''),
  :'authority',:'confirmation'
))::text;
commit;
SQL
}

lock_execute_json() {
  local explicit_sql='null'
  [[ -n "$EXPLICIT_AMOUNT" ]] && explicit_sql=":'explicit'::numeric"
  psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" \
    -v source_mode="$SOURCE_MODE" -v rate="$RATE" -v rate_source="$RATE_SOURCE" \
    -v rate_date="$RATE_DATE" -v adjustment_mode="$ADJUSTMENT_MODE" -v explicit="$EXPLICIT_AMOUNT" \
    -v preview_manifest="$PREVIEW_MANIFEST" -v lesson_manifest="$LESSON_MANIFEST" \
    -v source_count="$SOURCE_COUNT" -v unused="$EXPECTED_UNUSED_JPY" \
    -v overage="$EXPECTED_OVERAGE_JPY" -v net_jpy="$EXPECTED_NET_JPY" \
    -v net_cny="$EXPECTED_NET_CNY" -v difference="$EXPECTED_SYSTEM_DIFFERENCE" \
    -v carry="$EXPECTED_FINAL_CARRYOVER" -v source_draft="$SOURCE_DRAFT" \
    -v source_updated="$SOURCE_DRAFT_UPDATED_AT" -v adjustment_draft="$ADJUSTMENT_DRAFT" \
    -v adjustment_updated="$ADJUSTMENT_DRAFT_UPDATED_AT" -v note="$NOTE" \
    -v authority="$OPERATOR_AUTHORITY" -v confirmation="$CONFIRM" <<SQL
begin;
set local request.jwt.claims='{"role":"service_role"}';
select jsonb_pretty(public.school_lock_student_monthly_settlement_local(
  :'student'::uuid,:'entity'::uuid,:'month',:'source_mode',:'rate'::numeric,
  :'rate_source',:'rate_date'::date,:'adjustment_mode',$explicit_sql,
  :'preview_manifest',:'lesson_manifest',:'source_count'::integer,
  :'unused'::numeric,:'overage'::numeric,:'net_jpy'::numeric,:'net_cny'::numeric,
  :'difference'::numeric,:'carry'::numeric,:'source_draft'::uuid,:'source_updated'::timestamptz,
  :'adjustment_draft'::uuid,:'adjustment_updated'::timestamptz,nullif(:'note',''),
  :'authority',:'confirmation'
))::text;
commit;
SQL
}

locked_settlement_json() {
  psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" <<'SQL'
select coalesce((
  select to_jsonb(s) from public.school_student_monthly_settlements s
  where s.student_id=:'student'::uuid
    and s.business_entity_id=:'entity'::uuid
    and s.year_month=:'month'
    and s.settlement_status='locked'
), 'null'::jsonb)::text;
SQL
}

case "$CMD" in
  status)
    require_scope
    psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" <<'SQL'
select jsonb_pretty(jsonb_build_object(
  'student_id',:'student'::uuid,
  'business_entity_id',:'entity'::uuid,
  'year_month',:'month',
  'source_treatment_drafts',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at)
    from public.school_student_settlement_source_treatment_drafts d
    where d.student_id=:'student'::uuid and d.year_month=:'month'),'[]'::jsonb),
  'adjustment_drafts',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at)
    from public.school_student_settlement_adjustment_drafts d
    where d.student_id=:'student'::uuid and d.year_month=:'month'),'[]'::jsonb),
  'settlements',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at)
    from public.school_student_monthly_settlements s
    where s.student_id=:'student'::uuid and s.year_month=:'month'),'[]'::jsonb),
  'claims',coalesce((select jsonb_agg(to_jsonb(c) order by c.source_type,c.source_planned_lesson_id)
    from public.school_student_settlement_lesson_variance_claims c
    where c.student_id=:'student'::uuid and c.year_month=:'month'),'[]'::jsonb),
  'next_month_active_revision_count',(select count(*) from public.school_student_tuition_generation_identities g
    join public.school_student_tuition_generation_revisions r on r.generation_identity_id=g.id
    where g.student_id=:'student'::uuid and g.business_entity_id=:'entity'::uuid
      and g.billing_month=(to_date(:'month'||'-01','YYYY-MM-DD')+interval '1 month')::date
      and r.lifecycle_status='active'),
  'gate',(select jsonb_object_agg(feature_key,state) from public.school_feature_gates
    where feature_key like 'student_tuition_%'),
  'authoritative_state',jsonb_build_object(
    'source_treatment_mode',coalesce(
      (select s.source_treatment_mode from public.school_student_monthly_settlements s
       where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
         and s.year_month=:'month' order by s.created_at desc limit 1),
      (select d.source_treatment_mode from public.school_student_settlement_source_treatment_drafts d
       where d.student_id=:'student'::uuid and d.business_entity_id=:'entity'::uuid
         and d.year_month=:'month' order by d.created_at desc limit 1)),
    'settlement_exchange_rate',coalesce(
      (select s.settlement_exchange_rate from public.school_student_monthly_settlements s
       where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
         and s.year_month=:'month' order by s.created_at desc limit 1),
      (select d.settlement_exchange_rate from public.school_student_settlement_source_treatment_drafts d
       where d.student_id=:'student'::uuid and d.business_entity_id=:'entity'::uuid
         and d.year_month=:'month' order by d.created_at desc limit 1)),
    'adjustment_mode',(select d.adjustment_source from public.school_student_settlement_adjustment_drafts d
      where d.student_id=:'student'::uuid and d.business_entity_id=:'entity'::uuid
        and d.year_month=:'month' order by d.created_at desc limit 1),
    'source_count',(select s.lesson_variance_source_count from public.school_student_monthly_settlements s
      where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
        and s.year_month=:'month' order by s.created_at desc limit 1),
    'source_manifest_sha256',(select s.lesson_variance_manifest_sha256 from public.school_student_monthly_settlements s
      where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
        and s.year_month=:'month' order by s.created_at desc limit 1),
    'unused_planned_credit_jpy',(select s.unused_planned_credit_jpy from public.school_student_monthly_settlements s
      where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
        and s.year_month=:'month' order by s.created_at desc limit 1),
    'net_lesson_variance_jpy',(select s.net_lesson_variance_jpy from public.school_student_monthly_settlements s
      where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
        and s.year_month=:'month' order by s.created_at desc limit 1),
    'net_lesson_variance_cny',(select s.net_lesson_variance_cny from public.school_student_monthly_settlements s
      where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
        and s.year_month=:'month' order by s.created_at desc limit 1),
    'final_carryover_cny',(select s.carryover_amount_cny from public.school_student_monthly_settlements s
      where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
        and s.year_month=:'month' order by s.created_at desc limit 1),
    'historical_consumed_blocker_count',(select count(*) from public.school_student_tuition_generation_revisions r
      join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
      where b.previous_settlement_id in (select s.id from public.school_student_monthly_settlements s
        where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
          and s.year_month=:'month')),
    'active_tuition_claim_count',(select count(*) from public.school_student_tuition_generation_revisions r
      join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
      where r.lifecycle_status='active' and b.previous_settlement_id in (
        select s.id from public.school_student_monthly_settlements s
        where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
          and s.year_month=:'month')),
    'lock_eligibility',case
      when exists(select 1 from public.school_student_monthly_settlements s
        where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid
          and s.year_month=:'month' and s.settlement_status='locked')
        then 'already_locked'
      when exists(select 1 from public.school_student_tuition_generation_identities g
        join public.school_student_tuition_generation_revisions r on r.generation_identity_id=g.id
        where g.student_id=:'student'::uuid and g.business_entity_id=:'entity'::uuid
          and g.billing_month=(to_date(:'month'||'-01','YYYY-MM-DD')+interval '1 month')::date
          and r.lifecycle_status='active') then 'blocked_by_active_tuition_revision'
      else 'requires_fresh_preview_and_exact_facts'
    end
  )
))::text;
SQL
    ;;
  history)
    require_scope
    psql_json -v student="$STUDENT" -v entity="$ENTITY" -v month="$MONTH" <<'SQL'
select jsonb_pretty(jsonb_build_object(
  'student_id',:'student'::uuid,
  'business_entity_id',:'entity'::uuid,
  'year_month',:'month',
  'events',coalesce((
    select jsonb_agg(e.payload order by e.occurred_at,e.event_order)
    from (
      select s.created_at occurred_at,1 event_order,to_jsonb(s)||jsonb_build_object('event_type','settlement') payload
      from public.school_student_monthly_settlements s
      where s.student_id=:'student'::uuid and s.business_entity_id=:'entity'::uuid and s.year_month=:'month'
      union all
      select d.created_at,2,to_jsonb(d)||jsonb_build_object('event_type','source_treatment_draft')
      from public.school_student_settlement_source_treatment_drafts d
      where d.student_id=:'student'::uuid and d.business_entity_id=:'entity'::uuid and d.year_month=:'month'
      union all
      select d.created_at,3,to_jsonb(d)||jsonb_build_object('event_type','adjustment_draft')
      from public.school_student_settlement_adjustment_drafts d
      where d.student_id=:'student'::uuid and d.business_entity_id=:'entity'::uuid and d.year_month=:'month'
      union all
      select c.created_at,4,to_jsonb(c)||jsonb_build_object('event_type','lesson_variance_claim')
      from public.school_student_settlement_lesson_variance_claims c
      where c.student_id=:'student'::uuid and c.business_entity_id=:'entity'::uuid and c.year_month=:'month'
    ) e
  ),'[]'::jsonb)
))::text;
SQL
    ;;
  preview)
    require_preview_input
    preview_json;;
  save-draft)
    require_expected
    [[ -n "${REASON//[[:space:]]/}" ]] || fail 'save-draft requires --reason'
    PREVIEW="$(preview_json)"; print -- "$PREVIEW"; verify_preview "$PREVIEW"
    if (( ! EXECUTE )); then print -- 'DRY-RUN: exact facts match; no write performed.'; exit 0; fi
    EXPECTED_CONFIRM="SAVE STUDENT SETTLEMENT DRAFT $STUDENT $MONTH MANIFEST $PREVIEW_MANIFEST"
    [[ "$CONFIRM" == "$EXPECTED_CONFIRM" ]] || fail "Confirmation mismatch; expected: $EXPECTED_CONFIRM"
    RESULT="$(save_execute_json)" \
      || fail 'Save-draft transaction result is ambiguous. Run status before any retry.' 1
    print -- "$RESULT" | jq -e '.ok == true' >/dev/null || fail 'Save-draft RPC rejected' 1
    print -- "$RESULT" | jq .;;
  lock)
    require_expected
    [[ -n "$SOURCE_DRAFT" && -n "$SOURCE_DRAFT_UPDATED_AT" && -n "$ADJUSTMENT_DRAFT" && -n "$ADJUSTMENT_DRAFT_UPDATED_AT" ]] \
      || fail 'lock requires both expected draft UUIDs and updated_at values'
    LOCKED_SETTLEMENT="$(locked_settlement_json)"
    if [[ "$LOCKED_SETTLEMENT" == 'null' ]]; then
      PREVIEW="$(preview_json)"; print -- "$PREVIEW"; verify_preview "$PREVIEW"
      if (( ! EXECUTE )); then print -- 'DRY-RUN: exact facts match; no write performed.'; exit 0; fi
    else
      print -- "$LOCKED_SETTLEMENT" | jq .
      if (( ! EXECUTE )); then print -- 'DRY-RUN: existing locked settlement will be checked by the idempotent wrapper; no write performed.'; exit 0; fi
    fi
    EXPECTED_CONFIRM="LOCK STUDENT SETTLEMENT $STUDENT $MONTH MANIFEST $PREVIEW_MANIFEST CARRY $EXPECTED_FINAL_CARRYOVER"
    [[ "$CONFIRM" == "$EXPECTED_CONFIRM" ]] || fail "Confirmation mismatch; expected: $EXPECTED_CONFIRM"
    RESULT="$(lock_execute_json)" \
      || fail 'Lock transaction result is ambiguous. Run status before any retry.' 1
    print -- "$RESULT" | jq -e '.ok == true' >/dev/null || fail 'Lock RPC rejected' 1
    print -- "$RESULT" | jq .;;
  *) usage; exit 2;;
esac
