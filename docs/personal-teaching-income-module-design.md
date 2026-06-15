# Personal Teaching Income Module Design

Status date: 2026-06-15

Scope: design only. No SQL has been executed for this module, no Edge Function has been deployed for this module, and no real or test data has been written for this module.

## Purpose

This document defines the future personal external teaching income module and its Cash System confirmation workflow.

The module covers income earned by the user when teaching or working for an external cram school. It is personal business income. It is not the Aozora teacher-wage expense module, does not enter Aozora teacher wage settlement, and must not create `teacher_wage` payment requests.

## System Boundary

School System is the business ledger:

- Records income business facts.
- Records student or payee context when relevant.
- Records month, course/work content, business attribution, and settlement status.
- Does not maintain Cash account balances.
- Initiates Cash receipt confirmation requests from School business flows.

Cash System is the real account ledger:

- Only Cash approve creates a transaction.
- Only Cash approve changes a Cash account balance.
- Cash reject creates no transaction and changes no balance.
- Cash does not proactively create School income requests.
- Cash does not proactively generate School business records.

Normal School income:

- Enters School / corporate account directly.
- Uses the School account selector.
- Uses the existing School income creation path.
- Does not enter Cash confirmation.

Cash System income:

- Creates a School income record or income request first.
- Then submits a Cash receipt confirmation request.
- Cash approve creates `home_jpy_transactions` or `home_cny_transactions`.
- Cash approve marks School income received / settled.
- Cash reject creates no transaction, leaves the income request pending, and allows retry.

Status note:

- Legacy Cash linkage `pending` belongs to the old personal tuition manual sync
  compatibility path.
- New Cash receipt confirmation should use the request lifecycle states
  `pending_cash_request`, `awaiting_cash_confirmation`, `synced`,
  `cash_rejected`, and `failed` / `blocked`.
- UI copy should describe these as Cash request states, not as proof that
  income has been received.

## Income Request vs Cash Receipt Confirmation Request

Income request:

- Business-side claim that this income should be received.
- May come from tuition, personal business income, personal external teaching income, or other income.
- Does not mean money has actually arrived in a real account.
- Does not directly change Cash balance.
- Belongs to School business state and settlement state.

Cash receipt confirmation request:

- Submission of an income request to Cash System for user confirmation.
- Waits in Cash as a pending external request.
- Cash approve creates the real transaction.
- Cash approve increases the selected Cash account balance.
- Cash reject creates no transaction and leaves the income request retryable.

Required flow:

```text
monthly settlement / income record
-> income request
-> Cash receipt confirmation request
-> Cash approve
-> Cash transaction
-> School income received / settled
```

Do not collapse income request and Cash receipt confirmation request into one concept. The first is business entitlement; the second is real-account confirmation.

## Module Positioning

Personal external teaching income:

- The user is the teacher / worker.
- The external cram school is the payer.
- The row is personal business income.
- It may not use the existing School student master.
- It does not enter Aozora teacher wage expense.
- It does not enter `teacher_wage` payment requests.
- It focuses on personal income, hourly rate, transport, allowance, deductions, monthly settlement, and Cash receipt.

This is separate from current Aozora lesson management. It can reuse broad UI concepts such as planned and actual rows, but it must not reuse Aozora-specific cancellation, makeup, student billing, teacher wage, or cost attribution semantics.

## Lesson Record Model

Use planned + actual:

- Daily planned lessons can be freely added, edited, and deleted.
- The only workflow action is generating actual from planned.
- There is no cancel state.
- There is no pending makeup state.
- There is no makeup completed state.
- There is no `is_billable` complexity.
- If the lesson did not happen, delete the planned row.
- If planned has already generated actual, deletion requires a second confirmation.
- The second confirmation is a business protection guard, not makeup logic.

Suggested fields:

- `lesson_date`
- `external_school_name`
- `work_content` / `course_name`
- `planned_start_time`
- `planned_end_time`
- `actual_start_time`
- `actual_end_time`
- `actual_hours`
- `hourly_rate`
- `lesson_wage_amount`
- `transportation_fee`
- `allowance_amount`
- `deduction_amount`
- `total_expected_income`
- `currency`
- `target_cash_account`
- `settlement_month`
- `settlement_status`
- `cash_confirmation_status`
- `memo`

### Planned / Actual Data Model Draft

Planned lesson row:

- `id`
- `settlement_month`
- `lesson_date`
- `external_school_name`
- `payer_name` or `external_school_id`
- `work_content` / `course_name`
- `planned_start_time`
- `planned_end_time`
- `planned_hours`
- `currency`
- `hourly_rate`
- `target_cash_account_id`
- `memo`
- `status = planned`
- `generated_actual_id`
- `created_at`
- `updated_at`

Actual lesson row:

- `id`
- `planned_lesson_id`
- `settlement_month`
- `lesson_date`
- `external_school_name`
- `payer_name` or `external_school_id`
- `work_content` / `course_name`
- `actual_start_time`
- `actual_end_time`
- `actual_hours`
- `currency`
- `hourly_rate`
- `lesson_wage_amount`
- `transportation_fee`
- `allowance_amount`
- `deduction_amount`
- `total_expected_income`
- `memo`
- `status = actual_generated`
- `created_at`
- `updated_at`

Design notes:

- Planned and actual can be separate tables or one table with `record_kind`.
  Separate tables make deletion protection and monthly review clearer.
- `planned_lesson_id` should be unique on actual rows so one planned row can
  generate at most one active actual row.
- Actual monetary fields should be snapshotted at generation time and editable
  during settlement draft/reviewing, but not after settlement lock.
- `target_cash_account_id` is an intended receipt account snapshot for later
  Cash confirmation. Final validation still belongs to Cash-side whitelist and
  currency checks.
- If external cram school master data is not yet needed, start with text
  fields (`external_school_name`, `payer_name`) and avoid adding a master table
  too early.

## Monthly Settlement Flow

1. Enter planned lessons during the month.
2. After teaching, generate actual from planned.
3. At month end, review all actual rows.
4. Calculate approximate income:
   - `actual_hours * lesson_count * hourly_rate`
   - plus `transportation_fee`
   - plus allowance
   - minus deductions
   - equals `total_expected_income`
5. Lock monthly settlement after review.
6. Generate `personal_teaching_income_request`.
7. The generated request is an income request, not a payment request.
8. Submit the income request to Cash receipt confirmation.
9. Cash approve writes the Cash transaction and increases the Cash balance.
10. Cash approve marks the income request / settlement received / settled.
11. Cash reject creates no transaction and leaves the request pending / retryable.

## Monthly Settlement Model

Monthly settlement header:

- `id`
- `settlement_month`
- `external_school_name` / `payer_name`
- `business_entity_id` for personal business attribution
- `currency`
- `target_cash_account_id`
- `actual_lesson_count`
- `actual_hours_total` (`sum(actual_hours * lesson_count)`)
- `lesson_wage_total`
- `transportation_fee_total`
- `allowance_total`
- `deduction_total`
- `total_expected_income`
- `status`
- `locked_at`
- `income_request_id`
- `cash_confirmation_status`
- `memo`
- `created_at`
- `updated_at`

Settlement detail:

- Links the settlement header to included actual lesson rows.
- Stores actual row amount snapshots used for the locked settlement.
- Prevents silent drift if actual rows are later corrected through a guarded
  future adjustment workflow.

Calculation:

```text
lesson_wage_amount = actual_hours * lesson_count * hourly_rate
total_expected_income =
  lesson_wage_total
  + transportation_fee_total
  + allowance_total
  - deduction_total
```

Locking rules:

- `draft`: actual rows can be reviewed and edited.
- `reviewing`: user is checking monthly totals; edits are still allowed.
- `locked`: included actual rows are frozen for this settlement.
- After `locked`, generating the income request is allowed.
- Once an income request exists, settlement amount/currency/target account
  cannot be edited through ordinary UI.
- Corrections after lock require a separate adjustment/reversal design; do not
  silently mutate a locked request.

The locked settlement generates exactly one active
`personal_teaching_income_request` at a time. Rejected Cash attempts remain
history, but there must be at most one active Cash confirmation attempt for
the same income request.

## Income Request Model

`personal_teaching_income_request` is the business-side receivable request.
It is not a Cash transaction and does not prove receipt.

Suggested fields:

- `id`
- `settlement_id`
- `settlement_month`
- `payer_name`
- `business_entity_id`
- `income_category = personal_teaching_income`
- `description`
- `amount`
- `currency`
- `target_cash_account_id`
- `status`
- `receipt_status`
- `cash_confirmation_status`
- `cash_request_id`
- `cash_transaction_id`
- `idempotency_key`
- `created_at`
- `updated_at`

Suggested request statuses:

- `pending`: income should be received but is not confirmed in Cash.
- `cash_pending`: Cash receipt confirmation request has been submitted.
- `received`: Cash approve completed and Cash transaction exists.
- `settled`: School monthly settlement is fully closed.
- `cash_rejected`: latest Cash request was rejected; retry is allowed.
- `blocked`: operator intervention needed.

The request should eventually map into the generic income Cash confirmation
path, either by creating a School `school_income_records` row or by adding a
parallel income request table with callback support. The first implementation
should prefer reusing the existing income Cash workflow unless the UI/settlement
needs clearly require a separate table.

## Suggested Statuses

Lesson:

- `planned`
- `actual_generated`

Settlement:

- `draft`
- `reviewing`
- `locked`
- `income_request_created`

Cash confirmation:

- `cash_pending`
- `cash_approved`
- `received`
- `settled`
- `cash_rejected`
- `retryable`

Detailed state flow:

```text
planned
-> actual_generated
-> settlement draft
-> settlement reviewing
-> settlement locked
-> income_request_created / pending
-> cash_pending
-> cash_approved / received
-> settled
```

Reject branch:

```text
cash_pending
-> cash_rejected / retryable
-> cash_pending on retry
```

Cash reject must not unlock the settlement automatically. It only means the
real-account receipt was not approved. The income request remains pending /
retryable until the operator submits a corrected Cash request or separately
voids/reverses the business request through a future guarded workflow.

## Deletion Protection Rules

Planned rows:

- Planned without actual can be deleted directly.
- Planned with generated actual requires a second confirmation.
- The confirmation text should make clear that an actual business row exists.

Actual rows:

- Actual rows included in an unlocked `draft` / `reviewing` settlement can be
  removed only through an explicit action that updates settlement totals.
- Actual rows included in a `locked` settlement cannot be deleted through the
  ordinary UI.
- Actual rows with an income request or Cash request cannot be deleted through
  ordinary UI.

Settlement rows:

- Draft settlements can be discarded if no income request exists.
- Locked settlements with an income request cannot be deleted; use a future
  void/reversal workflow if business correction is required.

Income requests:

- Pending requests may be retryable, but not physically deleted in ordinary UI.
- Cash-approved / received requests cannot be deleted.
- Rejected Cash attempts are historical evidence and must remain traceable.

## Difference From Aozora Lesson Management

Current Aozora lesson management:

- Uses student, teacher, subject, and business attribution.
- Uses planned and actual lessons.
- Supports cancel and makeup workflows.
- Drives student billing.
- Drives teacher wage expense.
- Tracks business ownership and cost attribution.
- Exists for Aozora school operations.

Personal external teaching income:

- The user is the teacher / worker.
- The external cram school is the payer.
- May not use the School student master.
- Does not enter Aozora teacher wage expense.
- Does not need cancel or makeup states.
- Focuses on personal income, hourly pay, transport fee, monthly settlement, and Cash receipt.
- Cash approve increases balance.

## Relation To Teacher Wage Cash Confirmation

Teacher wage:

- Expense.
- Uses payment requests.
- Cash approve decreases balance.
- School payment request becomes paid.

Personal teaching income:

- Income.
- Uses income / receipt requests.
- Cash approve increases balance.
- School income request becomes received / settled.

Can reuse:

- Attempt mechanism.
- Unique active attempt guard.
- Rejected retry.
- `idempotency_key`.
- Cash external request table and approve/reject flow.
- JPY/CNY transaction dispatch.
- Cash approve/reject callback pattern.

Must not directly reuse:

- Payment naming.
- Expense direction.
- `paid` semantics.
- Teacher wage settlement tables.
- `teacher_wage` fields.

## Relation To Income Cash Confirmation

The personal external teaching income request should enter the generic income Cash confirmation model:

```text
personal teaching monthly settlement
-> personal_teaching_income_request
-> request Cash receipt confirmation
-> Cash pending external request
-> Cash approve/reject
-> School received/settled or retryable pending
```

The module should use the Cash System account whitelist. If target income currency is JPY, only JPY Cash accounts are selectable. If target income currency is CNY, only CNY Cash accounts are selectable.

Reuse from existing income Cash workflow:

- Cash account whitelist and currency validation.
- Cash external request creation.
- Active attempt unique guard.
- Rejected retry pattern.
- Idempotency key design.
- Cash approve/reject callback routing.
- JPY/CNY transaction dispatch.
- School received / settled callback semantics.

Do not reuse directly:

- `teacher_wage` payment request naming or statuses.
- Expense/payment direction.
- Teacher wage settlement tables.
- Aozora lesson cancel/makeup semantics.
- Ordinary School account received-income path before Cash approve.

## Current Implementation Snapshot

Generic income Cash confirmation code and SQL were introduced in commit
`2fe6ae8` and are now installed/deployed:

- `supabase/functions/request-cash-income-confirmation/index.ts`
- `supabase/functions/sync-cash-request-result/index.ts` income dispatch
- `school_income_cash_confirmation_workflow.sql`
- `school_create_cash_income_confirmation`
- `school_request_cash_income_confirmation`
- `school_mark_cash_income_request_submitted`
- `school_mark_cash_income_confirmed`
- `school_mark_cash_income_rejected`
- Cash-side reuse of `home_create_external_transaction_request`
- Cash approve reuse of `home_approve_external_transaction_request`

Current implementation state:

- SQL/RPC has been executed against School DB.
- `request-cash-income-confirmation` has been deployed.
- `sync-cash-request-result` has been deployed.
- Real CNY income tests passed for 李天伦 `21,450 CNY`, 彭宇晗
  `6,491 CNY`, and 厦门吕同学 `7,740 CNY`.
- Frontend account routing has been implemented.
- Cash System income save path calls `request-cash-income-confirmation`.
- Cash request display text now includes student/payee plus content for income
  confirmations.
- This module itself is not implemented yet; it should reuse the stabilized
  income Cash workflow in a later phase.

## Implementation Phase Split

Phase 1: design and schema draft

- Define planned / actual tables or one `record_kind` table.
- Define monthly settlement header/detail.
- Decide whether `personal_teaching_income_request` maps to
  `school_income_records` or needs a dedicated request table.
- Define constraints for one actual per planned row and one active Cash attempt
  per income request.
- Draft read-only preflight SQL for existing income/Cash compatibility.

Phase 2: School backend

- Add RPC/API wrappers for planned creation/edit/delete.
- Add RPC/API wrappers for generate actual from planned.
- Add settlement draft/review/lock RPCs.
- Add income request creation RPC.
- Ensure page modules do not call `.rpc()` directly for writes.

Phase 3: Cash confirmation integration

- Reuse `request-cash-income-confirmation` where possible.
- If a dedicated request table is used, add an Edge Function branch and School
  callback RPCs.
- Validate Cash whitelist and currency at request time.
- Ensure Cash approve is the only point that writes
  `home_jpy_transactions` / `home_cny_transactions`.

Phase 4: frontend

- Add module pages for planned/actual entry.
- Add settlement review and lock UI.
- Add income request and Cash pending status UI.
- Add retry path after Cash reject.
- Keep the UI simple: no cancel/makeup states.

Phase 5: verification

- Static checks.
- SQL/RPC rollback tests with whitelist data.
- Cash pending request rollback/commit tests with whitelist data.
- First real test only after user explicitly authorizes a target record.
- No historical backfill in the first implementation phase.

## Implementation Guardrails

- Do not use `teacher_wage` payment tables for personal external teaching income.
- Do not mark School income received before Cash approve.
- Do not write Cash transactions from School.
- Do not change Cash balances from School.
- Do not create Cash request from Cash proactively.
- Do not add cancel/makeup semantics unless a separate future design proves they are needed.
- Do not backfill old personal teaching income automatically.
