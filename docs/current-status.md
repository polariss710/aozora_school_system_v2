# Current Status

- Stable checkpoint: write-operation phase is complete through account transfer frontend checkpoint.
- Latest stable commit: `4fe0a05 feat: add account transfer frontend`.
- Completed write flows: income creation, income reversal, expense creation, expense reversal, reimbursement confirmation, reimbursement reversal, account adjustment, account adjustment reversal, account transfer, teacher wage payment confirmation, and teacher wage payment reversal.
- Write flows use API-layer wrappers and verified RPCs; page modules must not call Supabase `.rpc()` directly or directly insert, update, delete, or upsert rows.
- Account transaction linkage and account transaction detail source summaries cover income, expense, reimbursement, payment request, account adjustment, and account transfer sources.
- Account transfer completed schema, RPC SQL draft/static review, schema/RPC execution, rollback test, commit test, verified SQL archive, frontend minimum implementation, frontend static checkpoint/push, and feature checkpoint.
- Account transfer commit test used whitelisted test data only: dedicated `codex-test / v2.33.10 / 账户转账测试` accounts.
- Write RPC run-until-gate workflow was validated through the account transfer stage: Codex proceeded through read-only/static phases and stopped at human gates for schema/RPC execution, rollback test, commit test, and commit/push.
- Account transfer frontend has static and online file checks, but no real local browser interaction test yet.
- Account transfer does not yet have a standalone detail page; the first version shows its source summary in account transaction detail.
- The write RPC workflow has been standardized in `docs/workflows/write-rpc-flow.md`.
- Default Codex guardrails have been added to AGENTS.md and pushed.
- Expected repository state at the start of the next task: clean worktree.
- Next planned stage: choose the next write-operation candidate or update project status/checkpoint docs.
