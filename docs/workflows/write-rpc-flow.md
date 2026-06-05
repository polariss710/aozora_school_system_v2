# Write RPC Flow

Version: v2.29.1-write-rpc-flow-standardization-20260606

This document is the project standard for write-operation RPC development. It does not grant permission to execute SQL, call business RPCs, write data, edit frontend files, commit, or push. Each task prompt must explicitly allow the current phase actions.

## Core Rules

- Keep one phase narrow. Do not mix design, SQL execution, RPC testing, frontend implementation, and git operations unless the task explicitly allows it.
- Page modules must not call Supabase `.rpc()` directly.
- Page modules must not directly insert, update, delete, or upsert database rows.
- Write operations must go through the API layer and verified RPCs.
- Never print, save, or commit `SUPABASE_DB_URL` or other secrets.
- Start each phase by checking `git status --short`; SQL execution and commit phases must also confirm the latest commit.
- Every phase report must state: files changed, SQL/RPC executed, database written, commit/push performed, current git status, and whether the next phase can proceed.

## Standard Sequence

1. Analysis
2. Schema design
3. Schema SQL draft
4. Schema static review
5. Schema execution
6. Schema verified commit
7. RPC design
8. RPC SQL draft
9. RPC static review
10. RPC execution and rollback test
11. RPC commit test
12. Verified SQL commit
13. Frontend analysis
14. Frontend minimal implementation
15. Frontend checkpoint and push
16. Feature checkpoint

Skip schema phases only when the analysis concludes no schema change is needed.

## Phase Template

Each phase should use this structure:

- Goal: one concrete objective.
- Allowed: what may be read, edited, executed, or written.
- Forbidden: actions outside the phase.
- Required checks: commands or verifications that must be done.
- Output: concise report fields.
- Next phase gate: the condition that must be true before proceeding.

## 1. Analysis

Goal: decide the business scope, invariants, existing patterns, and whether schema/RPC/frontend work is needed.

Allowed:

- Read project docs, SQL files, API modules, page modules, detail pages, and recent commits.
- Use read-only DB queries only when the prompt explicitly allows them.
- Identify source records, target records, account transaction effects, status transitions, audit fields, and reversal behavior.

Forbidden:

- Editing files.
- Executing SQL files, creating RPCs, calling business RPCs, or writing DB rows.
- Committing or pushing.

Required checks:

- `git status --short`
- Latest commit when relevant to the phase history.

Output:

- Git status and latest commit.
- Business conclusion and recommended design direction.
- Existing patterns to reuse.
- Risks, assumptions, and open questions.
- Whether schema design or RPC design can proceed.

Next phase gate: scope is narrow, no blocking unknowns remain, and the required next phase is clear.

## 2. Schema Design

Goal: define schema shape in prose before writing SQL.

Allowed:

- Specify tables, columns, types, nullable flags, defaults, foreign keys, check constraints, indexes, comments, and historical-data expectations.
- Decide whether reversal/status/audit fields are needed.

Forbidden:

- Creating or executing SQL.
- Creating RPC/function definitions.
- Editing frontend/API modules.
- Writing business data.

Required checks:

- Compare with existing schema conventions.
- Confirm whether historical data must remain unchanged.

Output:

- Schema design conclusion.
- Proposed SQL draft filename.
- Verification plan.
- Risks.
- Whether schema SQL draft can proceed.

Next phase gate: column/constraint/index design is explicit enough to draft SQL without guessing.

## 3. Schema SQL Draft

Goal: create schema-only SQL that is not executed.

Allowed:

- Add or update the explicitly named schema SQL file.
- Include table/column/index/constraint/comment definitions.
- Mark file header as draft only / not executed.

Forbidden:

- Executing SQL.
- Creating RPC/function definitions.
- Updating historical data unless explicitly required.
- Editing frontend/API modules.
- Committing or pushing.

Required checks:

- Confirm the SQL file contains no `create function`, `create procedure`, or business data writes unless explicitly allowed.
- Keep comments and names consistent with existing SQL files.

Output:

- SQL draft file path.
- Schema summary.
- Draft-only confirmation.
- Current git status.
- Whether static review can proceed.

Next phase gate: SQL file is schema-only and complete enough for review.

## 4. Schema Static Review

Goal: review schema SQL without executing it.

Allowed:

- Read the schema SQL file.
- Check object names, types, nullable flags, defaults, constraints, indexes, comments, and extension assumptions.

Forbidden:

- Executing SQL.
- Editing frontend/API modules.
- Calling business RPCs.
- Committing or pushing.

Required checks:

- No RPC/function definitions.
- No historical data updates unless explicitly intended.
- No dangerous statements or secrets.
- No likely table, constraint, or index name conflicts.

Output:

- Static review result.
- Findings ordered by severity.
- Read-only confirmation.
- Risks.
- Whether schema execution can proceed.

Next phase gate: no blocking review findings remain.

## 5. Schema Execution

Goal: execute verified schema-only SQL and verify the DB state.

Allowed only when explicitly requested:

- Execute `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <file>`.
- Run read-only verification for created/changed schema objects.

Forbidden:

- Creating or replacing RPC functions unless the task explicitly requires it.
- Calling business RPCs.
- Editing frontend/API modules.
- Writing business data beyond the schema migration itself.
- Committing or pushing unless explicitly requested.

Required checks:

- `git status --short` and latest commit before execution.
- Confirm target SQL is schema-only.
- Verify columns, nullable flags, defaults, constraints, indexes, comments, extension requirements, and unchanged historical data where relevant.
- Verify no unexpected RPC/function was created.

Output:

- SQL execution result summary without secrets.
- Verification results.
- Current git status.
- Whether schema verified commit can proceed.

Next phase gate: execution succeeded and read-only verification matches the design.

## 6. Schema Verified Commit

Goal: archive the executed schema SQL state in git.

Allowed:

- Update the schema SQL file header/status only.
- Run `git diff --check`.
- Commit and push only when explicitly requested.

Forbidden:

- Changing SQL logic after execution.
- Editing business code.
- Executing SQL or calling business RPCs.

Required checks:

- Confirm SQL logic did not change.
- Confirm only intended files are staged.

Output:

- File header update summary.
- Commit hash and push result when applicable.
- Final git status.
- Whether RPC design can proceed.

Next phase gate: executed schema SQL is committed/pushed and worktree is clean.

## 7. RPC Design

Goal: define RPC contract and write behavior before drafting SQL.

Allowed:

- Define RPC name, parameters, return columns, validation rules, lock order, account balance rules, source links, audit fields, and error behavior.
- Plan rollback and commit tests.

Forbidden:

- Creating SQL files unless the task explicitly allows it.
- Executing SQL or calling business RPCs.
- Editing frontend/API modules.

Required checks:

- Map every write to a business invariant.
- Confirm page/API boundary expectations.
- Define positive/negative amount semantics where relevant.

Output:

- RPC signature and return value design.
- Write set and validation rules.
- Rollback/commit test plan.
- Risks.
- Whether RPC SQL draft can proceed.

Next phase gate: contract and write behavior are precise enough to draft SQL.

## 8. RPC SQL Draft

Goal: create RPC SQL that is not executed.

Allowed:

- Add or update the explicitly named RPC SQL file.
- Use established project patterns for `security definer`, `search_path`, validation, locking, writes, comments, and return payloads.
- Mark file header as draft only / not executed.

Forbidden:

- Executing SQL.
- Calling business RPCs.
- Editing frontend/API modules.
- Committing or pushing.

Required checks:

- Confirm parameters, return order, locks, balance calculations, `related_table` / `related_id`, status updates, and error messages match design.
- Avoid ambiguous column references.

Output:

- SQL draft file path.
- Implementation summary.
- Known review points.
- Current git status.
- Whether RPC static review can proceed.

Next phase gate: SQL draft implements the agreed RPC design and is ready for review.

## 9. RPC Static Review

Goal: review RPC SQL without executing it.

Allowed:

- Read and review SQL draft files.
- Suggest SQL fixes only when the task explicitly allows editing during review.

Forbidden:

- Executing SQL.
- Calling business RPCs.
- Editing frontend/API modules.
- Committing or pushing.

Required checks:

- RPC signature and return order.
- Parameter validation.
- Lock order and concurrency behavior.
- Account balance before/after consistency.
- Source table writes and account transaction writes.
- Reversal/status behavior where relevant.
- Ambiguous column risks.
- No dangerous statements or secrets.

Output:

- Static review result.
- Findings ordered by severity.
- Risks.
- Whether RPC execution and rollback test can proceed.

Next phase gate: no blocking SQL findings remain.

## 10. RPC Execution And Rollback Test

Goal: install the RPC and prove failed/rolled-back writes leave no residue.

Allowed only when explicitly requested:

- Execute the RPC SQL file with `psql`.
- Smoke test function existence.
- Choose controlled test candidates.
- Run `begin` / RPC / verification / `rollback` tests.
- Run 1-2 expected failure cases.
- Update SQL file header to executed / rollback-tested when requested.

Forbidden:

- Running uncontrolled writes.
- Skipping before/after verification.
- Committing or pushing before commit tests pass.
- Printing secrets.

Required checks:

- Transaction-internal expected rows and balance changes appear.
- After rollback, source rows, account transactions, statuses, and balances have no residue.
- Failure cases do not write rows.

Output:

- SQL execution result.
- Test candidate.
- Rollback RPC result.
- In-transaction verification.
- After-rollback verification.
- Failure case results.
- Current git status.
- Whether commit test can proceed.

Next phase gate: rollback and failure cases prove no unintended persistence.

## 11. RPC Commit Test

Goal: perform one controlled real write and verify every intended effect.

Allowed only when explicitly requested:

- Call the business RPC with controlled valid input.
- Run read-only before/after verification.
- Run failure cases that should not create additional writes.

Forbidden:

- Broad or repeated writes without an explicit plan.
- Editing frontend/API modules.
- Archiving or committing before verification is complete.
- Printing secrets.

Required checks:

- Source/main table row count and values.
- Account transaction row count and values.
- Account balance change.
- `balance_before` / `balance_after`.
- `related_table` / `related_id`.
- Status, note, reason, date, and audit fields.
- Residual test data impact.

Output:

- Test candidate.
- Before state.
- RPC result.
- After verification.
- Failure case verification.
- Current git status.
- Whether verified SQL commit can proceed.

Next phase gate: intended write is fully verified and residual impact is understood.

## 12. Verified SQL Commit

Goal: commit and push the verified RPC SQL.

Allowed:

- Update SQL file header/status only.
- Run `git diff --check`.
- Commit and push only when explicitly requested.

Forbidden:

- Changing SQL logic after verification.
- Editing frontend/API modules.
- Executing SQL or calling business RPCs.

Required checks:

- Header says executed / rollback-tested / commit-tested.
- SQL logic unchanged.
- Only intended SQL files are staged.

Output:

- File header update summary.
- Commit hash.
- Push result.
- Final git status.
- Whether frontend analysis can proceed.

Next phase gate: verified SQL is committed/pushed and worktree is clean.

## 13. Frontend Analysis

Goal: decide the minimal frontend/API integration without editing files.

Allowed:

- Read HTML, page modules, API modules, detail pages, styles, and existing write-flow patterns.
- Define entry points, dialog fields, validation, refresh behavior, error display, and detail/source-link behavior.

Forbidden:

- Editing files.
- Calling business RPCs.
- Writing DB rows.
- Committing or pushing.

Required checks:

- Page modules must not directly `.rpc()`.
- Writes must go through API wrappers.
- Identify exact allowed file range for implementation.

Output:

- Git status and latest commit.
- Analysis conclusion.
- Suggested files.
- Risks.
- Whether frontend minimal implementation can proceed.

Next phase gate: UI/API scope is minimal and file range is explicit.

## 14. Frontend Minimal Implementation

Goal: wire the verified RPC into the UI with minimal, testable behavior.

Allowed only for explicitly named frontend/API files:

- Add API-layer RPC wrappers.
- Wire page modules to API functions.
- Add dialog/action entry, validation, loading state, success refresh, and in-dialog error handling.
- Add account transaction labels and detail source summaries where needed.

Forbidden:

- Page modules calling Supabase `.rpc()` directly.
- Page modules directly inserting, updating, deleting, or upserting rows.
- Editing SQL/RPC files.
- Editing unrelated modules.
- Writing DB data from exploratory UI actions unless explicitly allowed.

Required checks:

- `git diff --check`.
- `node --check` for changed JS.
- Scan page modules for `.rpc()`.
- Scan page modules for `.insert()` / `.update()` / `.delete()` / `.upsert()`.
- Browser or local server check when available; if unavailable, state the limitation.

Output:

- Modified files.
- Behavior summary.
- Check results.
- SQL/RPC execution and DB write status.
- Current git status.
- Whether frontend checkpoint can proceed.

Next phase gate: static checks pass, page/API boundary is clean, and no unintended DB write occurred.

## 15. Frontend Checkpoint And Push

Goal: run final static frontend checks, commit, and push.

Allowed only when explicitly requested:

- Run static checks and read-only online file checks.
- Commit and push the frontend implementation.

Forbidden:

- Calling the business RPC unless explicitly requested as UI test.
- Editing SQL/RPC files.
- Committing unrelated changes.

Required checks:

- `git diff --check`.
- `node --check` for related JS.
- Page-layer `.rpc()` scan.
- Direct write-method scan.
- Verify key online files return HTTP 200 after push when applicable.
- Record whether real UI testing was performed.

Output:

- Check results.
- Modified files.
- Commit hash.
- Push result.
- Final git status.
- Whether feature checkpoint can proceed.

Next phase gate: push succeeded and worktree is clean.

## 16. Feature Checkpoint

Goal: close the feature with a no-edit verification pass.

Allowed:

- Read docs and code.
- Run static scans and online file checks.
- Summarize DB/RPC/frontend coverage.

Forbidden:

- Editing files unless the prompt explicitly includes documentation updates.
- Calling business RPCs.
- Writing DB rows.
- Committing or pushing.

Required checks:

- `git status --short`.
- Latest commit.
- Page-layer `.rpc()` scan.
- Direct write-method scan.
- Account transaction labels and detail source coverage where relevant.
- Online key file availability when frontend changed.
- Record UI test status.

Output:

- Checkpoint result.
- Completed scope.
- Remaining risks or follow-up candidates.
- Final git status.
- Whether the feature stage can end.

Next phase gate: worktree is clean and no blocking verification gap remains.

## Documentation Placement Rules

- `AGENTS.md`: long-lived guardrails that every future turn must obey, such as secrets, page/API write boundaries, approval guidance, and required report fields.
- `docs/current-status.md`: short stable checkpoint only. Keep current completed scope, expected clean state, and next planned stage. Do not store long phase history.
- `docs/workflows/write-rpc-flow.md`: reusable standard workflow, phase templates, gates, and checklists. Do not include feature-specific logs.
- Current prompt: phase name, goal, focus points, explicit allowances for this phase, commit message when needed, and required output.

## Prompt Template

Use concise prompts with this shape:

- Read: `AGENTS.md`, `docs/current-status.md`, and this workflow when relevant.
- Phase: versioned phase name.
- Goal: one objective.
- Focus: phase-specific checks or design points.
- Allowed exceptions: only what differs from default guardrails.
- Output: required report fields.

Do not repeat stable background that belongs in `docs/current-status.md`. Do not create a Codex skill from this workflow unless a later task explicitly asks for it.
