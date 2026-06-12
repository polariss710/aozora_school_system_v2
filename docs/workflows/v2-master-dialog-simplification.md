# v2 Master Dialog Simplification Workflow

Status date: 2026-06-12

Use this workflow for v2 master-data create/edit dialog narrowing. Future prompts can reference this file instead of repeating the full rule set.

## Scope

Applies to ordinary master-data/profile/config dialogs such as students, teachers, subjects, accounts, business entities, and wage rules.

Does not authorize settlement, teacher wage generation/snapshot, payment request, reimbursement, income/expense, account transaction, lesson, locking, historical repair, destructive cleanup, delete, or merge changes.

## Field Rules

- Narrow create/edit fields to what current operations actually maintain.
- Keep historical, reserved, low-frequency, generated, derived, audit, and compatibility fields hidden or readonly.
- Do not physically delete retained DB fields unless a separate cleanup/migration phase is explicitly designed.
- Do not mix settlement, wage, payment, reimbursement, account transaction, income/expense, lesson, balance, or lock-derived fields into ordinary master-data edit dialogs.
- Keep create and edit fields unified when possible.
- Allow explicit exceptions when the business meaning is create-only, such as account initial balance.
- Hide module-local top summary areas such as code/id, readonly field lists, immutable-field explanations, and generated-field summaries when the narrowed dialog no longer needs them.
- If a requested field is not supported by current DB/API/RPC, do not guess, do not overload `note`, and do not invent hidden defaults beyond existing safe compatibility defaults. Record the unsupported field and reason in docs.

## Dialog Behavior

- Choose dialog size by field count and complexity:
  - `small`: short forms, usually 4 or fewer simple fields.
  - `medium`: ordinary profile forms, roughly 5-10 fields or two-column layout.
  - `large`: dense forms, lookup-heavy forms, or grouped fields that need more width.
- Desktop forms may use two columns when it improves scanning.
- Mobile must collapse or adapt to one column and must not create page-level horizontal overflow.
- Save failure must keep the dialog open, keep typed input, and show a clear inline error.
- Save success should preserve filters, pagination/list context, and scroll position as far as the page architecture reasonably allows.
- Loading states must disable duplicate submit and use clear button text.
- Cancel/close should be blocked while a submit is in progress unless the module has a deliberate force-close path after success.

## Boundary Rules

- Page modules must not call Supabase `.rpc()` directly and must not directly insert/update/delete/upsert rows.
- Write operations must go through `js/api/*-api.js` wrappers and verified RPC/API boundaries.
- v2 master data opens create/edit only. Delete/merge remain closed unless a separate audit-safe workflow opens them.
- Current/unclosed real business months must not be used for wage generation, snapshot generation, student settlement closing, locking, or lock-style validation.
- Validation should use transaction rollback or clearly marked whitelist data (`codex-test`, `v2-test`, `sandbox`, `测试学生`, `测试老师`, `测试业务归属`).

## Verification Levels

- Light verification:
  Use for UI-only field hiding/reordering when DB/API/RPC parameters are unchanged. Run static checks, page/API boundary scans, relevant browser/dialog checks, failure-state checks, and mobile overflow checks.
- Medium verification:
  Use when SQL/RPC/API parameters or master-data write behavior changes. Include light verification plus SQL/RPC static review, function existence checks, transaction rollback tests, and whitelist commit tests if the workflow requires persistent write verification.
- Heavy verification:
  Required when changes touch or can affect settlement, wage, payment, reimbursement, income/expense, account transaction, lesson, balance, or locking chains. Include dependency/side-effect analysis, rollback or whitelist tests across affected guards, and targeted regression of the touched main chain.

If a task starts as light/medium but discovers main-chain side effects, stop and reclassify before implementation.

## Documentation Rules

- Update `docs/current-status.md`, `docs/module-status.md`, and `docs/system-map.md` when module behavior or field scope changes.
- Keep `docs/current-status.md` as a lightweight entry with only the latest 5 key updates.
- Keep `docs/module-status.md` as current module state, not long history.
- Move older details to `docs/archive/` instead of deleting them when they are no longer daily context.
- Record hidden-but-retained fields and why they stay hidden.
- Record create-only exceptions and future backlog items.

## Repetition Rule

After the same operation pattern appears more than 3 times, abstract it into a workflow/rule and reference that workflow in later prompts. Do not keep repeating the long requirement block in every task prompt.

## Completed Samples

Recent modules that follow this pattern:

- Student management: create/edit narrowed to current student profile fields; settlement, tuition-rule, balance, parent/birthday/legacy fields remain closed.
- Wage rules: create/edit narrowed to matching keys, settlement type, rates, and note; transport fee, classroom fee, exchange rate, active-state select, and readonly summary remain hidden or handled elsewhere.
- Account management: create/edit narrowed to account profile fields; account code is generated, initial balance is create-only, current balance is card-only display, and balance correction remains a separate guarded backlog item.
