#!/bin/zsh
set -euo pipefail

if [[ -z "${SCHOOL_SUPABASE_DB_URL:-}" ]]; then
  print -u2 'SCHOOL_SUPABASE_DB_URL is required'
  exit 1
fi

typeset -a scenarios=(
  draft_edit
  draft_actual
  draft_lock
  lock_generate
  draft_pair
  unlock_draft
  preview_edit
  source_change_lock
)
typeset output_dir
output_dir="$(mktemp -d)"

for scenario in "${scenarios[@]}"; do
  psql "$SCHOOL_SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
    -v p0b2_scenario="$scenario" \
    -f sql/current/school_tuition_p0b2_concurrency_session_a_20260803.sql \
    >"$output_dir/${scenario}-a.log" 2>&1 &
  typeset session_a_pid=$!
  sleep 1
  psql "$SCHOOL_SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
    -v p0b2_scenario="$scenario" \
    -f sql/current/school_tuition_p0b2_concurrency_session_b_20260803.sql
  wait "$session_a_pid"
  tail -n 8 "$output_dir/${scenario}-a.log"
done

print 'P0B2_ALL_8_CONCURRENCY_SCENARIOS_PASSED'
