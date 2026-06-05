# Current Status

- Stable checkpoint: write-operation phase is complete through account adjustment reversal frontend.
- Latest stable commit: `f9d31b9 docs: add write RPC commit test whitelist`.
- Completed write flows: income creation, income reversal, expense creation, expense reversal, reimbursement confirmation, reimbursement reversal, account adjustment, account adjustment reversal, teacher wage payment confirmation, and teacher wage payment reversal.
- Write flows use API-layer wrappers and verified RPCs; page modules must not call Supabase `.rpc()` directly or directly insert, update, delete, or upsert rows.
- Account transaction linkage and account transaction detail source summaries cover income, expense, reimbursement, payment request, and account adjustment sources.
- Account adjustment reversal frontend is implemented and checkpointed; it has static and online file checks, but no real local browser interaction test yet.
- Account adjustment does not yet have a standalone detail page; the first version shows its source summary and reversal entry in account transaction detail.
- The write RPC workflow has been standardized in `docs/workflows/write-rpc-flow.md`.
- Write RPC run-until-gate dry run passed: Codex completed read-only analysis for the account transfer / transfer RPC candidate and stopped at the human gate before schema/RPC design.
- The dry run did not edit files, execute SQL/RPC, write DB rows, commit, or push.
- Default Codex guardrails have been added to AGENTS.md and pushed.
- Expected repository state at the start of the next task: clean worktree.
- Next planned stage: account transfer analysis.
