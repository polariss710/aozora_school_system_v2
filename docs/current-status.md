# Current Status

- Stable checkpoint: write-operation phase is complete through account adjustment frontend.
- Completed write flows: income creation, income reversal, expense creation, expense reversal, reimbursement confirmation, reimbursement reversal, account adjustment, teacher wage payment confirmation, and teacher wage payment reversal.
- Write flows use API-layer wrappers and verified RPCs; page modules must not call Supabase `.rpc()` directly or directly insert, update, delete, or upsert rows.
- Account transaction linkage and account transaction detail source summaries cover income, expense, reimbursement, payment request, and account adjustment sources.
- Account adjustment does not yet have a standalone detail page; the first version shows its source summary in account transaction detail.
- The write RPC workflow has been standardized in `docs/workflows/write-rpc-flow.md`.
- Default Codex guardrails have been added to AGENTS.md and pushed.
- Expected repository state at the start of the next task: clean worktree.
- Next planned stage: fixed workflow documentation review / commit.
