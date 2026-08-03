#!/usr/bin/env zsh
set -euo pipefail
unsetopt BG_NICE

[[ -n "${SCHOOL_SUPABASE_DB_URL:-}" ]] || { print -u2 'SCHOOL_SUPABASE_DB_URL is required'; exit 2; }
readonly TASK_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TASK_TMPDIR"' EXIT

psql "$SCHOOL_SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off >"$TASK_TMPDIR/session-a.log" 2>&1 <<'SQL' &
begin;
set local statement_timeout='30s';
select public.school_lock_student_tuition_operation(
  'eb705aad-de4d-45e6-a391-42dcdd89aeda',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  '2026-07-01'::date
);
select clock_timestamp() as reissue_scope_locked;
select pg_sleep(8);
rollback;
SQL
SESSION_A_PID=$!

sleep 2

psql "$SCHOOL_SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
begin;
set local statement_timeout='30s';
do $test$
declare
  v_started timestamptz := clock_timestamp();
  v_elapsed numeric;
begin
  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    'eb705aad-de4d-45e6-a391-42dcdd89aeda',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
    '2026-07'
  );
  v_elapsed := extract(epoch from clock_timestamp()-v_started);
  if v_elapsed < 4 then
    raise exception 'P0F_REISSUE_SETTLEMENT_EXPECTED_BLOCKING_MISSING: elapsed=%',v_elapsed;
  end if;
  raise notice 'P0F_REISSUE_SETTLEMENT_BLOCKED_THEN_ACQUIRED elapsed=% pid=%',
    v_elapsed,pg_backend_pid();
end
$test$;
rollback;
SQL

wait "$SESSION_A_PID"
rg 'reissue_scope_locked|ROLLBACK' "$TASK_TMPDIR/session-a.log"
