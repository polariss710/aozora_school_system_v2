# Write RPC Flow

Version: v2.27.0-write-rpc-flow-doc-20260606

This workflow documents the standard development path for verified write-operation RPCs in this project. It is intended for future Codex task prompts and may later become the basis for a Codex skill. This document does not grant permission to execute SQL, write business data, edit frontend code, commit, or push; each task phase must explicitly allow its own actions.

## Core Rules

- Keep each phase narrow. Do not mix analysis, SQL execution, RPC testing, frontend implementation, and git operations in one step unless the task explicitly allows it.
- Page modules must not call Supabase `.rpc()` directly.
- Write operations must go through the API layer and verified RPCs.
- Page modules must not directly insert, update, delete, or upsert database rows.
- Never print, save, or commit `SUPABASE_DB_URL` or other secrets.
- Before SQL execution or commit work, check `git status --short`.
- Reports must state whether files changed, whether SQL/RPC was executed, whether the database was written, whether commit/push happened, current git status, and whether the next step can proceed.

## Standard Sequence

1. Analysis
2. Schema design
3. Schema execution
4. RPC design
5. SQL draft
6. Static review
7. Rollback test
8. Commit test
9. SQL archive
10. Frontend minimal implementation
11. Checkpoint

## 1. Analysis

Allowed:

- Read project docs, existing SQL, API modules, page modules, and relevant archived commits.
- Inspect current behavior and data model with read-only queries when explicitly allowed.
- Identify source records, target records, expected linkage, reversal behavior, status transitions, and audit fields.

Forbidden:

- Editing business code or SQL files unless the task explicitly moves into a draft phase.
- Executing schema SQL, creating RPCs, calling business RPCs, or writing database rows.
- Committing or pushing.

Output:

- Scope summary.
- Existing patterns to reuse.
- Required tables, fields, constraints, and RPC contracts.
- Open risks or assumptions.
- Current git status and whether drafting can proceed.

## 2. Schema Design

Allowed:

- Draft the intended schema shape in prose.
- Define required columns, nullable flags, indexes, foreign keys, check constraints, and historical-data expectations.
- Compare with existing schema conventions and completed write flows.

Forbidden:

- Creating or executing SQL unless the task explicitly allows draft SQL.
- Creating RPC/function definitions.
- Editing frontend/API modules.
- Writing business data.

Output:

- Schema change list.
- Compatibility and historical-data notes.
- Verification plan for columns, constraints, and unchanged existing rows.
- Whether schema SQL drafting can proceed.

## 3. Schema Execution

Allowed only when explicitly requested:

- Execute schema-only SQL with `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <file>`.
- Run read-only verification for columns, nullable flags, constraints, indexes, foreign keys, and unchanged historical data.

Forbidden:

- Creating or replacing RPC functions unless the task explicitly requires it.
- Calling business RPCs.
- Editing frontend/API modules.
- Writing business data beyond the schema migration itself.
- Committing or pushing unless explicitly requested.

Output:

- Confirmation that the SQL file was schema-only.
- SQL execution result summary without secrets.
- Read-only verification results.
- Current git status and whether RPC design can proceed.

## 4. RPC Design

Allowed:

- Define RPC name, parameters, return shape, validation rules, lock strategy, transaction boundaries, and error messages.
- Map every write to the required business invariant.
- Specify how account transactions, source links, reversal links, status fields, notes, and audit fields are handled.

Forbidden:

- Creating SQL files unless the task explicitly allows SQL drafting.
- Executing SQL or calling business RPCs.
- Editing frontend/API modules.

Output:

- RPC contract.
- Validation and error behavior.
- Write set and rollback expectations.
- Test cases for rollback and commit paths.

## 5. SQL Draft

Allowed:

- Create or update draft SQL files for RPC definitions and supporting comments.
- Keep SQL idempotent where appropriate.
- Use established project patterns for `security definer`, search path, validation, locking, and returned payloads.

Forbidden:

- Executing SQL.
- Calling business RPCs.
- Editing frontend/API modules.
- Archiving SQL before tests pass.
- Committing or pushing.

Output:

- Draft SQL file path.
- Summary of function behavior.
- Known review points.
- Current git status and whether static review can proceed.

## 6. Static Review

Allowed:

- Read and review SQL draft files.
- Check for syntax risks, unsafe writes, missing validations, missing locks, ambiguous joins, incorrect account balance effects, and inconsistent return shapes.
- Confirm no secrets are present.

Forbidden:

- Executing SQL unless the task explicitly moves to test execution.
- Calling business RPCs.
- Editing frontend/API modules.
- Committing or pushing.

Output:

- Findings ordered by severity.
- Required fixes or confirmation that no blocking issues were found.
- Current git status and whether rollback testing can proceed.

## 7. Rollback Test

Allowed only when explicitly requested:

- Install or replace the RPC in the database if needed for the test phase.
- Call the business RPC with intentionally invalid or controlled failure inputs.
- Verify that partial writes do not persist and balances/statuses remain unchanged.
- Use read-only verification queries after the attempted rollback.

Forbidden:

- Running uncontrolled test data writes.
- Skipping before/after verification.
- Archiving, committing, or pushing before commit tests pass.
- Printing secrets.

Output:

- Test input summary.
- Expected failure.
- Verification that no unintended rows or balance changes persisted.
- Current git status and whether commit testing can proceed.

## 8. Commit Test

Allowed only when explicitly requested:

- Call the business RPC with a controlled valid input.
- Verify every intended row, status, balance, link, note, and audit field.
- Confirm detail-page source chains or related lookup surfaces when relevant.

Forbidden:

- Running broad or repeated writes without a clear cleanup or reversal plan.
- Editing frontend/API modules during SQL validation.
- Archiving or committing before verification is complete.
- Printing secrets.

Output:

- Test input summary.
- RPC result summary.
- Verification results for all expected writes.
- Residual test data impact, if any.
- Current git status and whether SQL archive can proceed.

## 9. SQL Archive

Allowed:

- Move or copy verified SQL into the project archive path used by the current feature.
- Keep draft and archived filenames consistent with the version/tag convention.
- Include only verified SQL, not exploratory notes or secrets.

Forbidden:

- Archiving untested SQL.
- Editing business frontend/API modules unless the task explicitly moves to frontend implementation.
- Committing or pushing unless explicitly requested.

Output:

- Archived SQL path.
- Confirmation that rollback and commit tests passed before archive.
- Current git status and whether frontend implementation can proceed.

## 10. Frontend Minimal Implementation

Allowed only for explicitly named frontend/API files:

- Add API-layer wrappers that call verified RPCs.
- Wire page modules to API-layer functions.
- Add minimal UI states, validation, loading, success, and error handling needed for the write flow.
- Preserve existing design and module patterns.

Forbidden:

- Page modules calling Supabase `.rpc()` directly.
- Page modules directly inserting, updating, deleting, or upserting database rows.
- Editing unrelated modules.
- Editing SQL/RPC files during frontend implementation unless explicitly requested.
- Writing database data from exploratory browser actions unless explicitly allowed.

Output:

- Changed frontend/API files.
- Behavior summary.
- Verification performed, including browser checks when applicable.
- Current git status and whether checkpoint can proceed.

## 11. Checkpoint

Allowed when explicitly requested:

- Run final static checks, targeted tests, and read-only verification.
- Update status documentation if the task includes it.
- Commit and push only after explicit permission and a clean review scope.

Forbidden:

- Hiding unverified SQL or business-code changes inside a checkpoint.
- Committing unrelated user changes.
- Pushing without explicit permission.
- Omitting database-write and SQL/RPC execution status from the report.

Output:

- Final change summary.
- Verification summary.
- Files changed.
- Whether SQL/RPC was executed.
- Whether the database was written.
- Whether commit/push was performed.
- Current git status.
- Whether review, commit, or push can proceed.

## Phase Prompt Template

Use concise prompts with this shape:

- Phase name.
- Goal.
- Focus points.
- Explicit allowances for any exception to the default guardrails.
- Required output.

Do not repeat the full project background when `docs/current-status.md` already captures the stable checkpoint. Refer to `AGENTS.md` for default guardrails.
