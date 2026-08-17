#!/bin/zsh
# Phase 2C-C isolated two-session concurrency runner.
set -euo pipefail

: "${PHASE2CC_PGHOST:?set PHASE2CC_PGHOST to the disposable local socket directory}"
: "${PHASE2CC_PGPORT:?set PHASE2CC_PGPORT}"
: "${PHASE2CC_PGDATABASE:=postgres}"
: "${PHASE2CC_PGUSER:=postgres}"

repo_root="${0:A:h:h}"
psql_bin="${PHASE2CC_PSQL_BIN:-psql}"
log_dir="$(mktemp -d /private/tmp/phase2cc-concurrency.XXXXXX)"
psql_args=(-X -h "$PHASE2CC_PGHOST" -p "$PHASE2CC_PGPORT" \
  -U "$PHASE2CC_PGUSER" -d "$PHASE2CC_PGDATABASE" -v ON_ERROR_STOP=1)

"$psql_bin" "${psql_args[@]}" \
  -f "$repo_root/sql/tests/school_phase2c_c_lesson_clearance_concurrency_session_a_local_20260817.sql" \
  >"$log_dir/session-a.log" 2>&1 &
session_a_pid=$!
"$psql_bin" "${psql_args[@]}" \
  -f "$repo_root/sql/tests/school_phase2c_c_lesson_clearance_concurrency_session_b_local_20260817.sql" \
  >"$log_dir/session-b.log" 2>&1 &
session_b_pid=$!

wait "$session_a_pid"
wait "$session_b_pid"
"$psql_bin" "${psql_args[@]}" \
  -f "$repo_root/sql/tests/school_phase2c_c_lesson_clearance_concurrency_verify_local_20260817.sql"
print "Phase 2C-C concurrency contract: PASS (logs: $log_dir)"
