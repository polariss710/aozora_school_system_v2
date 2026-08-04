#!/usr/bin/env zsh
set -euo pipefail

readonly ACTUAL_ID='d1c60932-0f8a-43e3-98b8-bb362921ccf8'
readonly SOURCE_ID='d4e3e060-1951-4fdd-9340-e6feb6687b7f'
readonly CORRECT_DATE='2026-08-02'
readonly CONFIRMATION='REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
readonly REASON='Correct business date for cross-month makeup actually completed on 2026-08-02.'

usage() {
  print -- 'Usage:'
  print -- '  scripts/manage-chen-hongzhuo-makeup-correction.zsh status'
  print -- '  scripts/manage-chen-hongzhuo-makeup-correction.zsh execute --expected-updated-at TIMESTAMPTZ --execute --confirm REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
}

fail() { print -u2 -- "$1"; exit "${2:-2}"; }
command -v psql >/dev/null 2>&1 || fail 'psql is required'
[[ -n "${SCHOOL_SUPABASE_DB_URL:-}" ]] || fail 'SCHOOL_SUPABASE_DB_URL is required'
[[ -n "${CASH_SUPABASE_DB_URL:-}" ]] || fail 'CASH_SUPABASE_DB_URL is required'

psql_school() {
  psql "$SCHOOL_SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off "$@"
}
psql_cash() {
  psql "$CASH_SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off "$@"
}

status() {
  psql_school -v actual="$ACTUAL_ID" -v source="$SOURCE_ID" <<'SQL'
select jsonb_pretty(jsonb_build_object(
  'actual',(select to_jsonb(a) from public.school_lesson_records a where a.id=:'actual'::uuid),
  'source',(select to_jsonb(p) from public.school_lesson_records p where p.id=:'source'::uuid),
  'linked_actuals',(select coalesce(jsonb_agg(to_jsonb(a) order by a.lesson_date,a.created_at),'[]'::jsonb)
    from public.school_lesson_records a where a.planned_lesson_id=:'source'::uuid),
  'remaining_hours',public.school_get_lesson_credit_remaining_hours(:'source'::uuid),
  'wage_detail_count',(select count(*) from public.school_teacher_wage_lock_details where lesson_record_id=:'actual'::uuid),
  'settlement_count',(select count(*) from public.school_student_monthly_settlements
    where student_id='eceb2c59-9689-4ec8-9d3f-799b90bfdb27' and year_month in ('2026-07','2026-08')),
  'claim_count',(select count(*) from public.school_student_settlement_lesson_variance_claims
    where source_actual_lesson_id=:'actual'::uuid),
  'actual_bill_relation_count',(select count(*) from public.school_student_tuition_bill_lessons
    where planned_lesson_id=:'actual'::uuid),
  'legacy_evidence_count',(select count(*) from public.school_legacy_actual_settlement_evidence
    where actual_lesson_id=:'actual'::uuid),
  'historical_exclusion_count',(select count(*) from public.school_student_tuition_historical_lesson_exclusions
    where linked_actual_lesson_id=:'actual'::uuid),
  'migration_count',(select count(*) from public.school_business_entity_migration_items
    where lesson_record_id=:'actual'::uuid),
  'bill_md5',(select md5(to_jsonb(b)::text) from public.school_student_tuition_bills b
    where b.id='7472f73f-fa19-4565-9180-a517c7151835'),
  'income_md5',(select md5(to_jsonb(i)::text) from public.school_income_records i
    where i.id='3a5542c5-5397-4688-999e-a08bb678f40d'),
  'gates',(select jsonb_object_agg(feature_key,state) from public.school_feature_gates
    where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit'))
))::text;
SQL
  psql_cash -v actual="$ACTUAL_ID" <<'SQL'
select jsonb_pretty(jsonb_build_object(
  'request_reference_count',(select count(*) from public.home_external_transaction_requests r
    where position(:'actual' in to_jsonb(r)::text)>0),
  'cny_reference_count',(select count(*) from public.home_cny_transactions t
    where position(:'actual' in to_jsonb(t)::text)>0),
  'jpy_reference_count',(select count(*) from public.home_jpy_transactions t
    where position(:'actual' in to_jsonb(t)::text)>0),
  'approved_request_md5',(select md5(to_jsonb(r)::text) from public.home_external_transaction_requests r
    where r.id='eae797ff-b271-47c8-b534-7d764e7d5ffe'),
  'confirmed_transaction_md5',(select md5(to_jsonb(t)::text) from public.home_cny_transactions t
    where t.id='b06cfd54-f374-4d3d-a0e5-2f93c92d0577')
))::text;
SQL
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 2; }
shift

case "$cmd" in
  status)
    [[ $# -eq 0 ]] || fail 'status does not accept options'
    status
    ;;
  execute)
    expected_updated_at=''
    confirm=''
    execute_flag=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --expected-updated-at)
          [[ $# -ge 2 && -n "$2" ]] || fail '--expected-updated-at requires a value'
          expected_updated_at="$2"
          shift 2
          ;;
        --confirm)
          [[ $# -ge 2 && -n "$2" ]] || fail '--confirm requires a value'
          confirm="$2"
          shift 2
          ;;
        --execute)
          execute_flag=1
          shift
          ;;
        *) fail "Unknown option: $1";;
      esac
    done
    [[ -n "$expected_updated_at" ]] || fail '--expected-updated-at is required'
    [[ "$execute_flag" -eq 1 ]] || fail 'execute is dry-run blocked unless --execute is present'
    [[ "$confirm" == "$CONFIRMATION" ]] || fail 'confirmation mismatch'

    cash_refs="$(psql_cash -qAt -v actual="$ACTUAL_ID" <<'SQL'
select
  (select count(*) from public.home_external_transaction_requests r where position(:'actual' in to_jsonb(r)::text)>0)
  +(select count(*) from public.home_cny_transactions t where position(:'actual' in to_jsonb(t)::text)>0)
  +(select count(*) from public.home_jpy_transactions t where position(:'actual' in to_jsonb(t)::text)>0);
SQL
)"
    [[ "$cash_refs" == '0' ]] || fail "Cash actual UUID reference count is not zero: $cash_refs" 1

    psql_school -v actual="$ACTUAL_ID" -v source="$SOURCE_ID" \
      -v expected_updated_at="$expected_updated_at" -v correct_date="$CORRECT_DATE" \
      -v reason="$REASON" -v confirmation="$CONFIRMATION" <<'SQL'
begin;
set local request.jwt.claims='{"role":"service_role"}';
select * from public.school_replace_unconsumed_makeup_actual_v1(
  :'actual'::uuid,
  :'expected_updated_at'::timestamptz,
  :'source'::uuid,
  :'correct_date'::date,
  :'reason',
  :'confirmation'
);
commit;
SQL
    ;;
  -h|--help) usage;;
  *) usage; exit 2;;
esac
