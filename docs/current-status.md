# Current Status

- Stable checkpoint: write-operation phase is complete through account transfer reversal frontend checkpoint; full autopilot workflow trial is active.
- Latest stable commit: `b9c4cd4 feat: add account transfer reversal frontend`.
- Completed write flows: income creation, income reversal, expense creation, expense reversal, reimbursement confirmation, reimbursement reversal, account adjustment, account adjustment reversal, account transfer, account transfer reversal, teacher wage payment confirmation, and teacher wage payment reversal.
- Write flows use API-layer wrappers and verified RPCs; page modules must not call Supabase `.rpc()` directly or directly insert, update, delete, or upsert rows.
- Account transaction linkage and account transaction detail source summaries cover income, expense, reimbursement, payment request, account adjustment, account adjustment reversal, account transfer, and account transfer reversal sources.
- Account transfer completed schema, RPC SQL draft/static review, schema/RPC execution, rollback test, commit test, verified SQL archive, frontend minimum implementation, frontend static checkpoint/push, and feature checkpoint.
- Account transfer commit test used whitelisted test data only: dedicated `codex-test / v2.33.10 / 账户转账测试` accounts.
- Account transfer reversal completed with no schema change, verified RPC SQL, rollback test, whitelisted commit test, frontend minimum implementation, static checkpoint, online file checks, and feature checkpoint.
- Account transfer reversal commit test used whitelisted test data only: transfer `372fe08d-0c9e-4b96-8e76-31a4e09ca9ac` on dedicated `codex-test / v2.33.10 / 账户转账测试` accounts.
- Write RPC run-until-gate workflow was validated through the account transfer stage, then replaced by full autopilot trial in `docs/workflows/write-rpc-flow.md`.
- Full autopilot trial default: Codex should continue through analysis, schema/RPC work, DB execution, rollback test, whitelisted commit test, SQL/frontend commits, feature checkpoint, and current-status update unless a hard stop condition is hit.
- If rollback/commit test candidates do not match the test data whitelist, Codex may create clearly marked test data; real business data must not be used as an automatic test candidate.
- Account transfer and account transfer reversal frontend have static and online file checks, but no real local browser interaction test yet.
- Account transfer does not yet have a standalone detail page; the first version shows its source summary in account transaction detail.
- The write RPC workflow has been standardized and reset to full autopilot trial in `docs/workflows/write-rpc-flow.md`.
- Default Codex guardrails and approval guidance in AGENTS.md now reflect the full autopilot trial while preserving secrets, test-data, and dangerous-operation hard stops.
- Expected repository state at the start of the next task: clean worktree.
- Next planned stage: use the next small write-operation candidate to test full autopilot end to end.
