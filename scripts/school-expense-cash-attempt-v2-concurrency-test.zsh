#!/bin/zsh
set -euo pipefail

[[ -n "${SCHOOL_SUPABASE_DB_URL:-}" ]] || { print -u2 'SCHOOL_SUPABASE_DB_URL is required'; exit 2; }

TASK_TMPDIR=$(mktemp -d /private/tmp/phase3c2r-concurrency.XXXXXX)
PGDATA_DIR="$TASK_TMPDIR/pgdata"
PGSOCKET_DIR="$TASK_TMPDIR/socket"
PGPORT_NUMBER=55439
mkdir -p "$PGSOCKET_DIR"

cleanup() {
  /opt/homebrew/opt/postgresql@17/bin/pg_ctl -D "$PGDATA_DIR" -m fast stop >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

/opt/homebrew/opt/postgresql@17/bin/initdb -D "$PGDATA_DIR" --no-locale --encoding=UTF8 -U postgres >/dev/null
/opt/homebrew/opt/postgresql@17/bin/pg_ctl -D "$PGDATA_DIR" -l "$TASK_TMPDIR/postgres.log" \
  -o "-F -p $PGPORT_NUMBER -k $PGSOCKET_DIR" start >/dev/null

LOCAL_DB_URL="postgresql://postgres@/postgres?host=$PGSOCKET_DIR&port=$PGPORT_NUMBER"
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off <<'SQL' >/dev/null
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema extensions;
create extension pgcrypto with schema extensions;
SQL

TABLE_ARGS=(
  --table=public.school_feature_gates
  --table=public.school_expense_records
  --table=public.school_expense_cash_attempts
)
pg_dump "$SCHOOL_SUPABASE_DB_URL" --section=pre-data --no-owner --no-privileges "${TABLE_ARGS[@]}" \
  | psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off >/dev/null
pg_dump "$SCHOOL_SUPABASE_DB_URL" --section=data --data-only --column-inserts --no-owner --no-privileges "${TABLE_ARGS[@]}" \
  | psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off >/dev/null
pg_dump "$SCHOOL_SUPABASE_DB_URL" --section=post-data --no-owner --no-privileges "${TABLE_ARGS[@]}" \
  | psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=0 -P pager=off >"$TASK_TMPDIR/post-data.log" 2>&1

psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off <<'SQL' >/dev/null
create or replace function public.school_guard_expense_cash_attempt_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$ begin if tg_op='DELETE' then raise exception 'delete forbidden'; end if; return new; end $function$;
do $trigger$
begin
  if not exists(select 1 from pg_trigger where tgrelid='public.school_expense_cash_attempts'::regclass and tgname='school_guard_expense_cash_attempt_v1') then
    execute 'create trigger school_guard_expense_cash_attempt_v1 before insert or update or delete on public.school_expense_cash_attempts for each row execute function public.school_guard_expense_cash_attempt_v1()';
  end if;
end;
$trigger$;
do $constraint$
begin
  if not exists(select 1 from pg_constraint where conrelid='public.school_feature_gates'::regclass and conname='school_feature_gates_key_check') then
    alter table public.school_feature_gates add constraint school_feature_gates_key_check check(feature_key in('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit','cash_fixed_credit_card_route_enabled'));
  end if;
end;
$constraint$;
SQL

psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off \
  -f sql/current/school_expense_cash_attempt_v2_deploy_20260819.sql >/dev/null
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off <<'SQL' >/dev/null
update public.school_feature_gates set state='enabled' where feature_key='cash_expense_attempt_writer_v2_enabled';

insert into public.school_expense_records
select (jsonb_populate_record(
  null::public.school_expense_records,
  to_jsonb(e) || jsonb_build_object(
    'id','c3210000-0000-4000-8000-000000000101',
    'expense_date','2099-07-01','year_month','2099-07','status','pending',
    'description','codex-test phase3c2r concurrent prepare','note','codex-test phase3c2r local-only',
    'currency','JPY','amount',6100,'amount_jpy',6100,'amount_cny',null,
    'source_type','manual_cash','source_id',null,'account_id',null,'payment_method',null,
    'cash_request_id',null,'cash_request_status',null,'cash_transaction_id',null,
    'cash_requested_at',null,'cash_synced_at',null,'cash_error_message',null,
    'cash_request_event_id',null,'cash_request_attempt_no',0,'cash_payment_amount',null,
    'cash_payment_currency',null,'cash_payment_note',null,'reversed_at',null,
    'cash_creation_event_id','c3210000-0000-4000-8000-000000000111',
    'created_by_user_id','c3210000-0000-4000-8000-000000000001'
  )
)).*
from public.school_expense_records e where e.source_type='manual_cash' limit 1;
SQL

PREPARE_SQL="select attempt_id,attempt_no from public.school_request_cash_expense_payment_confirmation_v2('c3210000-0000-4000-8000-000000000101','c3210000-0000-4000-8000-000000000201','c3210000-0000-4000-8000-000000000301','local Cash JPY','2099-07-25','cash',6100,'JPY','local concurrency',1);"
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -c "begin; $PREPARE_SQL select pg_sleep(2); commit;" >"$TASK_TMPDIR/prepare-a.log" 2>&1 &
SESSION_A=$!
sleep 0.25
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -c "$PREPARE_SQL" >"$TASK_TMPDIR/prepare-b.log" 2>&1 &
SESSION_B=$!
wait $SESSION_A
wait $SESSION_B

SUBMITTED_SQL="select attempt_status,attempt_version,idempotent from public.school_mark_cash_expense_request_submitted_v2('c3210000-0000-4000-8000-000000000101','c3210000-0000-4000-8000-000000000401','pending','aozora_school',(select request_event_id from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000101'),(select idempotency_key from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000101'),'school_expense_records','c3210000-0000-4000-8000-000000000101','expense_paid','expense',6100,'JPY','c3210000-0000-4000-8000-000000000301','2099-07-25',(select request_payload_fingerprint from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000101'));"
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -c "begin; $SUBMITTED_SQL select pg_sleep(2); commit;" >"$TASK_TMPDIR/submitted-a.log" 2>&1 &
SESSION_A=$!
sleep 0.25
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -c "$SUBMITTED_SQL" >"$TASK_TMPDIR/submitted-b.log" 2>&1 &
SESSION_B=$!
wait $SESSION_A
wait $SESSION_B

APPROVED_SQL="select attempt_status,attempt_version,idempotent from public.school_mark_cash_expense_confirmed_v2('c3210000-0000-4000-8000-000000000101','c3210000-0000-4000-8000-000000000401','approved','aozora_school',(select request_event_id from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000101'),(select idempotency_key from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000101'),'school_expense_records','c3210000-0000-4000-8000-000000000101','expense_paid','expense',6100,'JPY','c3210000-0000-4000-8000-000000000301','2099-07-25',(select request_payload_fingerprint from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000101'),'c3210000-0000-4000-8000-000000000501','2099-07-26',null);"
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -c "begin; $APPROVED_SQL select pg_sleep(2); commit;" >"$TASK_TMPDIR/approved-a.log" 2>&1 &
SESSION_A=$!
sleep 0.25
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -c "$APPROVED_SQL" >"$TASK_TMPDIR/approved-b.log" 2>&1 &
SESSION_B=$!
wait $SESSION_A
wait $SESSION_B

psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -Atc "
do \$verify\$
begin
  if (select count(*) from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000101')<>1
     or not exists(select 1 from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000101' and attempt_status='approved_immediate' and version=3)
     or not exists(select 1 from public.school_expense_records where id='c3210000-0000-4000-8000-000000000101' and status='paid' and cash_request_status='approved') then
    raise exception 'PHASE3C2R_LOCAL_CONCURRENCY_STATE_INVALID';
  end if;
end;
\$verify\$;
select 'PHASE3C2R_LOCAL_TWO_SESSION_CONCURRENCY_PASS';"

psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off <<'SQL' >/dev/null
insert into public.school_expense_records
select (jsonb_populate_record(
  null::public.school_expense_records,
  to_jsonb(e) || jsonb_build_object(
    'id','c3210000-0000-4000-8000-000000000102',
    'expense_date','2099-08-01','year_month','2099-08','status','pending',
    'description','codex-test phase3c2r approved rejected race',
    'currency','JPY','amount',6200,'amount_jpy',6200,'amount_cny',null,
    'cash_request_id',null,'cash_request_status',null,'cash_transaction_id',null,
    'cash_requested_at',null,'cash_synced_at',null,'cash_error_message',null,
    'cash_request_event_id',null,'cash_request_attempt_no',0,'cash_payment_amount',null,
    'cash_payment_currency',null,'cash_payment_note',null,'reversed_at',null,
    'cash_creation_event_id','c3210000-0000-4000-8000-000000000112'
  )
)).*
from public.school_expense_records e where e.id='c3210000-0000-4000-8000-000000000101';

select * from public.school_request_cash_expense_payment_confirmation_v2(
  'c3210000-0000-4000-8000-000000000102','c3210000-0000-4000-8000-000000000201',
  'c3210000-0000-4000-8000-000000000301','local Cash JPY','2099-08-25','cash',6200,'JPY','local race',1
);
select * from public.school_mark_cash_expense_request_submitted_v2(
  'c3210000-0000-4000-8000-000000000102','c3210000-0000-4000-8000-000000000402','pending','aozora_school',
  (select request_event_id from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102'),
  (select idempotency_key from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102'),
  'school_expense_records','c3210000-0000-4000-8000-000000000102','expense_paid','expense',6200,'JPY',
  'c3210000-0000-4000-8000-000000000301','2099-08-25',
  (select request_payload_fingerprint from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102')
);
SQL

RACE_APPROVE_SQL="select * from public.school_mark_cash_expense_confirmed_v2('c3210000-0000-4000-8000-000000000102','c3210000-0000-4000-8000-000000000402','approved','aozora_school',(select request_event_id from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102'),(select idempotency_key from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102'),'school_expense_records','c3210000-0000-4000-8000-000000000102','expense_paid','expense',6200,'JPY','c3210000-0000-4000-8000-000000000301','2099-08-25',(select request_payload_fingerprint from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102'),'c3210000-0000-4000-8000-000000000502','2099-08-26',null);"
RACE_REJECT_SQL="select * from public.school_mark_cash_expense_rejected_v2('c3210000-0000-4000-8000-000000000102','c3210000-0000-4000-8000-000000000402','rejected','aozora_school',(select request_event_id from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102'),(select idempotency_key from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102'),'school_expense_records','c3210000-0000-4000-8000-000000000102','expense_paid','expense',6200,'JPY','c3210000-0000-4000-8000-000000000301','2099-08-25',(select request_payload_fingerprint from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102'),'race reject','2099-08-26',null);"
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -c "begin; $RACE_APPROVE_SQL select pg_sleep(2); commit;" >"$TASK_TMPDIR/race-approved.log" 2>&1 &
SESSION_A=$!
sleep 0.25
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -c "$RACE_REJECT_SQL" >"$TASK_TMPDIR/race-rejected.log" 2>&1 &
SESSION_B=$!
wait $SESSION_A
if wait $SESSION_B; then
  print -u2 'approved/rejected race unexpectedly allowed both terminal transitions'
  exit 1
fi
psql "$LOCAL_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -Atc "
do \$verify\$
begin
  if not exists(select 1 from public.school_expense_cash_attempts where expense_id='c3210000-0000-4000-8000-000000000102' and attempt_status='approved_immediate' and version=3)
     or not exists(select 1 from public.school_expense_records where id='c3210000-0000-4000-8000-000000000102' and status='paid' and cash_request_status='approved') then
    raise exception 'PHASE3C2R_APPROVED_REJECTED_RACE_INVALID';
  end if;
end;
\$verify\$;
select 'PHASE3C2R_APPROVED_REJECTED_RACE_PASS';"
