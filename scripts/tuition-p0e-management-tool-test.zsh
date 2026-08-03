#!/bin/zsh
set -euo pipefail

readonly ZERO_SHA='0000000000000000000000000000000000000000000000000000000000000000'
readonly STUDENT='d0d00000-0000-4000-8000-00000000a001'
readonly ENTITY='d0d00000-0000-4000-8000-00000000e001'
readonly GENERATION='d0d00000-0000-4000-8000-000000003001'
readonly PREVIOUS='d0d00000-0000-4000-8000-000000004001'
readonly SETTLEMENT='d0d00000-0000-4000-8000-00000000b001'

scripts/manage-atomic-tuition.zsh status \
  --student "$STUDENT" --entity "$ENTITY" --month 2020-08 --generation "$GENERATION" \
  | jq -e '.revisions | length == 2 and .[1].forward_adjustment_cny == -107.50' >/dev/null
scripts/manage-atomic-tuition.zsh history --generation "$GENERATION" \
  | jq -e '.forward_adjustments | length == 1 and .[0].amount_cny == -107.50' >/dev/null

typeset -a exact_args=(
  --student "$STUDENT" --entity "$ENTITY" --month 2020-08 --generation "$GENERATION"
  --previous-revision "$PREVIOUS" --candidate-manifest "$ZERO_SHA"
  --generation-manifest "$ZERO_SHA" --rate 0.043 --expected-jpy 650000
  --expected-exchange-cny 27950 --expected-cny 27950 --note codex-test
  --forward-adjustment-mode neutralize-historical-carryover
  --expected-source-settlement-id "$SETTLEMENT" --expected-source-revision-id "$PREVIOUS"
  --expected-historical-carryover-cny 107.50 --expected-forward-adjustment-cny -107.50
  --adjustment-line-manifest "$ZERO_SHA" --reason codex-test
)
scripts/manage-atomic-tuition.zsh reissue "${exact_args[@]}" | rg -q 'DRY-RUN'

typeset -a incomplete_args=("${exact_args[@]}")
incomplete_args=(${incomplete_args:#--expected-exchange-cny})
if scripts/manage-atomic-tuition.zsh reissue \
  --student "$STUDENT" --entity "$ENTITY" --month 2020-08 --generation "$GENERATION" \
  --previous-revision "$PREVIOUS" --candidate-manifest "$ZERO_SHA" --generation-manifest "$ZERO_SHA" \
  --rate 0.043 --expected-jpy 650000 --expected-cny 27950 --note codex-test \
  --forward-adjustment-mode neutralize-historical-carryover >/dev/null 2>&1; then
  print -u2 'P0E_INCOMPLETE_EXPECTED_FACTS_ACCEPTED'
  exit 1
fi

if scripts/manage-atomic-tuition.zsh reissue "${exact_args[@]}" \
  --execute --confirm WRONG >/dev/null 2>&1; then
  print -u2 'P0E_WRONG_CONFIRMATION_ACCEPTED'
  exit 1
fi

print 'P0E_MANAGEMENT_TOOL_TESTS_PASSED'
