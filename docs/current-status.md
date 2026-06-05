# Current Status

- Stable checkpoint: write-operation phase is complete through account transfer frontend checkpoint; full autopilot workflow trial is now enabled for upcoming small write-operation features.
- Latest stable commit before full autopilot trial: `f5d67d9 docs: update current status after account transfer`.
- Completed write flows: income creation, income reversal, expense creation, expense reversal, reimbursement confirmation, reimbursement reversal, account adjustment, account adjustment reversal, account transfer, teacher wage payment confirmation, and teacher wage payment reversal.
- Write flows use API-layer wrappers and verified RPCs; page modules must not call Supabase `.rpc()` directly or directly insert, update, delete, or upsert rows.
- Account transaction linkage and account transaction detail source summaries cover income, expense, reimbursement, payment request, account adjustment, and account transfer sources.
- Account transfer completed schema, RPC SQL draft/static review, schema/RPC execution, rollback test, commit test, verified SQL archive, frontend minimum implementation, frontend static checkpoint/push, and feature checkpoint.
- Account transfer commit test used whitelisted test data only: dedicated `codex-test / v2.33.10 / 账户转账测试` accounts.
- Write RPC run-until-gate workflow was validated through the account transfer stage, then replaced by full autopilot trial in `docs/workflows/write-rpc-flow.md`.
- Full autopilot trial default: Codex should continue through analysis, schema/RPC work, DB execution, rollback test, whitelisted commit test, SQL/frontend commits, feature checkpoint, and current-status update unless a hard stop condition is hit.
- Account transfer frontend has static and online file checks, but no real local browser interaction test yet.
- Account transfer does not yet have a standalone detail page; the first version shows its source summary in account transaction detail.
- The write RPC workflow has been standardized and reset to full autopilot trial in `docs/workflows/write-rpc-flow.md`.
- Default Codex guardrails and approval guidance in AGENTS.md now reflect the full autopilot trial while preserving secrets, test-data, and dangerous-operation hard stops.
- Expected repository state at the start of the next task: clean worktree.
- Next planned stage: use the next small write-operation candidate to test full autopilot end to end.
