#!/bin/zsh
set -euo pipefail
zmodload zsh/datetime

[[ -n "${SCHOOL_SUPABASE_DB_URL:-}" ]] || { print -u2 'SCHOOL_SUPABASE_DB_URL is required'; exit 1; }

typeset -a scenarios=(
  reissue_vs_settlement_mutation
  reissue_vs_void
  duplicate_reissue
  reissue_vs_lesson_edit
  reissue_vs_cash_reservation
  ordinary_vs_p0e_reissue
  adjustment_duplicate_race
  manifest_mismatch_race
)
typeset output_dir
output_dir="$(mktemp -d)"
typeset one_rows=''

for scenario in "${scenarios[@]}"; do
  psql "$SCHOOL_SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v p0e_scenario="$scenario" \
    -f sql/current/school_tuition_p0e_concurrency_session_a_20260803.sql \
    >"$output_dir/${scenario}-a.log" 2>&1 &
  typeset session_a_pid=$!
  sleep 1.5
  typeset started=$EPOCHSECONDS
  psql "$SCHOOL_SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v p0e_scenario="$scenario" \
    -f sql/current/school_tuition_p0e_concurrency_session_b_20260803.sql \
    >"$output_dir/${scenario}-b.log" 2>&1
  typeset elapsed=$(( EPOCHSECONDS - started ))
  wait "$session_a_pid"
  (( elapsed >= 2 )) || { print -u2 "P0E_CONCURRENCY_DID_NOT_BLOCK: $scenario ($elapsed s)"; exit 1; }
  rg -q 'active_revision_count' "$output_dir/${scenario}-b.log"
  rg -q 'adjustment_count' "$output_dir/${scenario}-b.log"
  one_rows="$(rg -c '^[[:space:]]*1[[:space:]]*$' "$output_dir/${scenario}-b.log")"
  (( one_rows >= 2 )) || { print -u2 "P0E_CONCURRENCY_CARDINALITY_FAILED: $scenario"; exit 1; }
  print "P0E_CONCURRENCY_PASSED $scenario blocked=${elapsed}s"
done

print 'P0E_ALL_8_CONCURRENCY_SCENARIOS_PASSED'
