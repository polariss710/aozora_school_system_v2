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

## Codex CLI Approval Guidance

- Read-only DB verification commands may use "Yes, and don't ask again" when the command is clearly a `select` query only. Examples include `information_schema`, `pg_constraint`, `pg_indexes`, `pg_description`, `pg_proc`, `count(*)`, and `exists` checks.
- This read-only approval guidance is limited to explicit `select` queries. It does not include `psql -f`, business RPC calls, or statements containing `insert`, `update`, `delete`, `drop`, `truncate`, `alter`, `create`, or `grant`.
- Schema execution commands such as `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <file>` must be approved one time per execution. Do not approve them permanently.
- Business RPC calls or any command that may write DB rows must be approved one time per execution. Do not approve them permanently.
- Schema execution, RPC execution, rollback tests, and commit tests remain human-gated even when their verification queries are read-only.
- `commit` and `push` may be approved according to the current task phase, but they still require explicit user confirmation by default.
- Do not use a fully approval-free mode for this project.
- Do not permanently approve all `psql` commands. Only narrowly scoped read-only verification commands are candidates for persistent approval.

## Default Guardrails

- Unless the current task explicitly allows it, do not edit business code, add SQL/RPC, execute SQL/RPC, write the database, call business RPCs, commit/push, or edit non-target modules such as income, account, reimbursement, or payment.
- Never print, save, or commit `SUPABASE_DB_URL` or any other secret.
- Analysis phases are read-only by default and should not change files.
- SQL draft phases may write draft SQL files only; do not execute them.
- Schema execution phases may execute schema-only SQL only; do not create RPCs or write business data.
- Frontend implementation phases may edit only the explicitly allowed frontend/API files; do not edit SQL/RPC files.
- Every turn output must state whether files changed, whether SQL/RPC was executed, whether the database was written, whether commit/push happened, the current git status, and whether the next step can proceed.

## Prompt Style

- Future task prompts should default to: phase name, goal, focus points, and required output.
- Do not repeat long background context when `docs/current-status.md` already captures the stable checkpoint.
- Do not repeat default prohibitions in every prompt; `AGENTS.md` is the source of truth for default guardrails.
- State explicit allowances only when the current task is an exception to the default guardrails.
