# Codex Project Rules

- Default to Chinese for progress updates and final reports.
- Keep prompts, plans, and outputs concise. Prefer high-signal summaries over long history.
- Start each work turn by checking `git status --short`.
- For write-operation SQL/RPC work, use the full autopilot trial workflow by default: analysis, schema/RPC design, SQL draft, static review, SQL/RPC execution, rollback test, whitelist commit test, verified SQL commit, frontend implementation, checkpoint, and status update.
- Page modules must not call Supabase `.rpc()` directly.
- Write operations must go through the API layer and/or verified RPCs. Page modules must not directly insert, update, delete, or upsert database rows.
- Never print, save, or commit `SUPABASE_DB_URL` or other secrets.
- Each turn report must state whether files were changed, executed SQL files and called RPCs if any, whether the database was written, whether writes were limited to test whitelist data, test record ids when relevant, whether commit/push happened, commit hashes when relevant, the current git status, and whether the workflow completed or stopped.

## Full Autopilot Trial

- Write-operation features now default to full autopilot trial for the next 2-3 small features.
- Do not stop at every phase for user confirmation. Continue through the standard workflow until completion unless a hard stop condition is hit.
- Automatically run read-only DB verification, schema SQL execution, RPC SQL execution, rollback tests, and commit tests when the commit test candidate is proven to match the test data whitelist.
- If rollback or commit test candidates do not match the test data whitelist, Codex may create narrowly scoped test data with explicit markers such as `codex-test`, `v2-test`, `sandbox`, the current phase id, `测试账户`, `测试学生`, or `测试业务归属`.
- Automatically commit and push document updates, verified SQL archives, frontend static checkpoints, feature checkpoints, and `docs/current-status.md` updates after required checks pass.
- Stop immediately and report when any hard stop condition occurs: missing `SUPABASE_DB_URL`, unavailable `psql`, static check failure, rollback/commit test failure, abnormal git status, uncertain test-data ownership that cannot be solved by creating safe test data, need for real business data, broad refactor, non-target module changes, `delete`, `truncate`, `drop`, or historical data repair.
- If full autopilot trial shows clear problems, revert to the last stable documented workflow and tighten the rules before continuing.

## Schema And RPC Execution Workflow

- Before running schema or RPC SQL, check `git status --short` and the latest commit.
- Confirm the target SQL file matches the current phase: schema-only files must not contain RPC/function creation; RPC files must not include unrelated schema or data repair.
- Execute SQL files with `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <file>`.
- Never print, save, or commit `SUPABASE_DB_URL`.
- After schema execution, run read-only verification for columns, nullable flags, FK/constraints, indexes, comments, and unchanged historical data.
- After RPC execution, smoke test function existence, run rollback tests, then run a commit test only against whitelisted test data.
- Report SQL output summaries, verification results, git status, and whether the workflow completed or stopped.

## Codex CLI Approval Guidance

- DB safety is phase-based, not command-by-command. Codex must classify each DB command before running it as `read-only verification`, `schema/RPC execution`, `rollback test`, `whitelist commit test`, or `prohibited real-data/destructive operation`.
- Do not rely on the user to inspect each `psql` command for business safety. If the command fits the current workflow phase and required checks have passed, continue; if it exceeds the current phase authorization, hard stop.
- Read-only DB verification commands may use "Yes, and don't ask again" when the command is clearly a `select` query only. Examples include `information_schema`, `pg_constraint`, `pg_indexes`, `pg_description`, `pg_proc`, `count(*)`, and `exists` checks.
- This read-only approval guidance is limited to explicit `select` queries. It does not include `psql -f`, business RPC calls, or statements containing `insert`, `update`, `delete`, `drop`, `truncate`, `alter`, `create`, or `grant`.
- During full autopilot trial, schema execution, RPC execution, rollback tests, whitelisted commit tests, `commit`, and `push` are phase-authorized when the workflow phase requires them and all required checks have passed.
- Approval prompts should still be scoped narrowly. Do not permanently approve all `psql` commands or broad shell access.
- Do not use a fully approval-free mode for this project.
- Do not bypass Codex CLI approvals. If the CLI asks, approve only the specific safe action or the existing narrow read-only verification class.

## Default Guardrails

- For write-operation feature work, default to the full autopilot trial workflow in `docs/workflows/write-rpc-flow.md`.
- For non-write-operation tasks, keep the requested scope narrow and do not edit unrelated modules.
- Never print, save, or commit `SUPABASE_DB_URL` or any other secret.
- Do not use real business data for automatic rollback or commit tests. Tests must prove whitelisted test scope before writing, or create clearly marked test data first.
- Do not run `delete`, `truncate`, `drop`, historical data repair, broad backfill, or cleanup automatically.
- Do not skip static review, rollback test, commit test, final checkpoint, or current-status update for a write-operation feature.
- Page/API boundaries remain mandatory: page modules must not directly `.rpc()` or directly insert/update/delete/upsert rows.
- Every turn output must state whether files changed, executed SQL files and called RPCs if any, whether the database was written, whether writes were limited to test whitelist data, test record ids when relevant, whether commit/push happened, commit hashes when relevant, the current git status, and whether the workflow completed or stopped.

## Prompt Style

- Future task prompts should default to: phase name, goal, focus points, and required output.
- Do not repeat long background context when `docs/current-status.md` already captures the stable checkpoint.
- Do not repeat default prohibitions in every prompt; `AGENTS.md` is the source of truth for default guardrails.
- State explicit restrictions only when the current task is narrower than full autopilot or is not a write-operation feature.
