# Codex Project Rules

- Default to Chinese for progress updates and final reports.
- Keep prompts, plans, and outputs concise. Prefer high-signal summaries over long history.
- Start each work turn by checking `git status --short`.
- P0 highest-priority rule: frontend/page JavaScript must not decide, derive, round, or otherwise compute business facts that will be saved or passed as write RPC parameters. This includes monetary amounts, settlement differences, carryovers, wages, fees, exchange-derived amounts, locked totals, Cash request amounts, and other persisted business-result fields. Such values must come from DB/RPC or backend API authoritative results, or from explicit user input. Frontend may format display values and may show non-persisted previews only when the saved value is still computed/validated by DB/RPC.
- For write-operation SQL/RPC work, use the full autopilot workflow by default: analysis, DB verification, schema/RPC design, SQL draft, static review, SQL/RPC execution, rollback test, whitelist commit test, verified SQL commit, frontend implementation, checkpoint, current-status update, commit, and push.
- Page modules must not call Supabase `.rpc()` directly.
- Write operations must go through the API layer and/or verified RPCs. Page modules must not directly insert, update, delete, or upsert database rows.
- V2 / V3 must not use `SUPABASE_DB_URL`. School DB uses `SCHOOL_SUPABASE_DB_URL`; Cash DB uses `CASH_SUPABASE_DB_URL`. If available, run `load_both_db >/dev/null` first. Never print, save, or commit any DB URL or secret.
- Each turn report must state whether files were changed, executed SQL files and called RPCs if any, whether the database was written, whether writes were limited to test whitelist data, test record ids when relevant, whether commit/push happened, commit hashes when relevant, the current git status, and whether the workflow completed or stopped.

## Full Autopilot

- Write-operation features default to full autopilot.
- The initial task prompt is the phase-level authorization for the requested feature. Do not stop at ordinary phase transitions for user confirmation. Continue through the standard workflow until completion unless a hard stop condition is hit.
- Do not ask for confirmation only because the next step is schema execution, RPC execution, rollback test, whitelisted commit test, frontend implementation, checkpoint commit, current-status update, or push, when required checks have passed and the action is inside the requested feature scope.
- Automatically run read-only DB verification, schema SQL execution, RPC SQL execution, rollback tests, and commit tests when the commit test candidate is proven to match the test data whitelist.
- If rollback or commit test candidates do not match the test data whitelist, Codex may create narrowly scoped test data with explicit markers such as `codex-test`, `v2-test`, `sandbox`, the current phase id, `测试账户`, `测试学生`, or `测试业务归属`.
- Automatically commit and push document updates, verified SQL archives, frontend static checkpoints, feature checkpoints, and `docs/current-status.md` updates after required checks pass.
- Stop immediately and report when any hard stop condition occurs: the phase-required `SCHOOL_SUPABASE_DB_URL` or `CASH_SUPABASE_DB_URL` is missing, unavailable `psql`, static check failure, rollback/commit test failure, abnormal git status, uncertain test-data ownership that cannot be solved by creating safe test data, need for non-whitelisted real business data, frontend/page JS computing persisted business-result values instead of DB/RPC or backend API authority, broad refactor, non-target module changes, `delete`, `truncate`, `drop`, destructive cleanup, broad historical-data modification, historical data repair, broad backfill, secrets exposure, broad permission changes, production irreversible action, or a request/documentation conflict that cannot be safely interpreted.
- If full autopilot shows clear problems, stop at the hard stop and tighten the documented workflow before continuing.

## Schema And RPC Execution Workflow

- Before running schema or RPC SQL, check `git status --short` and the latest commit.
- Confirm the target SQL file matches the current phase: schema-only files must not contain RPC/function creation; RPC files must not include unrelated schema or data repair.
- Execute School DB SQL files with `psql "$SCHOOL_SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <file>` and Cash DB SQL files with `psql "$CASH_SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <file>`.
- Never print, save, or commit any DB URL or secret; `SUPABASE_DB_URL` is not authoritative for V2 / V3 and must not be used.
- After schema execution, run read-only verification for columns, nullable flags, FK/constraints, indexes, comments, and unchanged historical data.
- After RPC execution, smoke test function existence, run rollback tests, then run a commit test only against whitelisted test data.
- Report SQL output summaries, verification results, git status, and whether the workflow completed or stopped.

## Codex CLI Approval Guidance

- DB safety is phase-based, not command-by-command. Codex must classify each DB command before running it as `read-only verification`, `schema/RPC execution`, `rollback test`, `whitelist commit test`, or `prohibited real-data/destructive operation`.
- Do not rely on the user to inspect each `psql` command for business safety. If the command fits the current workflow phase and required checks have passed, continue; if it exceeds the current phase authorization, hard stop.
- Read-only DB verification commands may use "Yes, and don't ask again" when the command is clearly a `select` query only. Examples include `information_schema`, `pg_constraint`, `pg_indexes`, `pg_description`, `pg_proc`, `count(*)`, and `exists` checks.
- This read-only approval guidance is limited to explicit `select` queries. It does not include `psql -f`, business RPC calls, or statements containing `insert`, `update`, `delete`, `drop`, `truncate`, `alter`, `create`, or `grant`.
- During full autopilot, schema execution, RPC execution, rollback tests, whitelisted commit tests, `commit`, and `push` are phase-authorized by the initial prompt when the workflow phase requires them and all required checks have passed.
- Approval prompts should still be scoped narrowly. Do not permanently approve all `psql` commands or broad shell access.
- Do not use a fully approval-free mode for this project.
- Do not bypass Codex CLI approvals. If the CLI asks, approve only the specific safe action or the existing narrow read-only verification class.

## Default Guardrails

- For write-operation feature work, default to the full autopilot workflow in `docs/workflows/write-rpc-flow.md`.
- For non-write-operation tasks, keep the requested scope narrow and do not edit unrelated modules.
- Never print, save, or commit any DB URL or other secret. Use only the phase-specific School / Cash variables above.
- Do not use real business data for automatic rollback or commit tests. Tests must prove whitelisted test scope before writing, or create clearly marked test data first.
- Do not run `delete`, `truncate`, `drop`, historical data repair, broad backfill, or cleanup automatically.
- Do not skip static review, rollback test, commit test, final checkpoint, or current-status update for a write-operation feature.
- Page/API boundaries remain mandatory: page modules must not directly `.rpc()` or directly insert/update/delete/upsert rows.
- P0 business-calculation boundary remains mandatory: page/frontend JS must not compute values that become saved business facts or write RPC parameters. If a UI needs a default value such as "clear balance", "suggested adjustment", calculated wage, converted amount, settlement total, or rounded amount, the authoritative value must be returned by DB/RPC or backend API, or typed explicitly by the user; otherwise stop and redesign before implementation.
- Every turn output must state whether files changed, executed SQL files and called RPCs if any, whether the database was written, whether writes were limited to test whitelist data, test record ids when relevant, whether commit/push happened, commit hashes when relevant, the current git status, and whether the workflow completed or stopped.

## Prompt Style

- Future task prompts should default to: phase name, goal, focus points, and required output.
- Do not repeat long background context when `docs/current-status.md` already captures the stable checkpoint.
- Do not repeat default prohibitions in every prompt; `AGENTS.md` is the source of truth for default guardrails.
- State explicit restrictions only when the current task is narrower than full autopilot or is not a write-operation feature.
