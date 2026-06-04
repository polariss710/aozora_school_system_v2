# Codex Project Rules

- Default to Chinese for progress updates and final reports.
- Keep prompts, plans, and outputs concise. Prefer high-signal summaries over long history.
- Start each work turn by checking `git status --short`.
- For SQL/RPC work, follow this sequence before archiving: analysis, draft, static review, rollback test, commit test, then verified SQL commit.
- Page modules must not call Supabase `.rpc()` directly.
- Write operations must go through the API layer and/or verified RPCs. Page modules must not directly insert, update, delete, or upsert database rows.
- Never print, save, or commit `SUPABASE_DB_URL` or other secrets.
- Each turn report must state whether files were changed, whether SQL/RPC was executed, whether the database was written, and whether commit/push was performed.

## Schema Execution Workflow

- Before running schema-only SQL, check `git status --short` and the latest commit.
- Confirm the target SQL does not contain RPC/function creation unless the task explicitly requires it.
- Execute schema SQL with `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <file>`.
- Never print, save, or commit `SUPABASE_DB_URL`.
- After execution, run read-only verification for columns, nullable flags, FK/constraints, and unchanged historical data.
- Do not create RPCs, call business RPCs, edit frontend files, write business data, or commit/push unless explicitly requested.
- Report SQL output, verification results, git status, and whether the next step can proceed.

## Default Guardrails

- Unless the current task explicitly allows it, do not edit business code, add SQL/RPC, execute SQL/RPC, write the database, call business RPCs, commit/push, or edit non-target modules such as income, account, reimbursement, or payment.
- Never print, save, or commit `SUPABASE_DB_URL` or any other secret.
- Analysis phases are read-only by default and should not change files.
- SQL draft phases may write draft SQL files only; do not execute them.
- Schema execution phases may execute schema-only SQL only; do not create RPCs or write business data.
- Frontend implementation phases may edit only the explicitly allowed frontend/API files; do not edit SQL/RPC files.
- Every turn output must state whether files changed, whether SQL/RPC was executed, whether the database was written, whether commit/push happened, the current git status, and whether the next step can proceed.
