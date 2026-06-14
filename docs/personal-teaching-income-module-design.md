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

## Monthly Settlement Flow

1. Enter planned lessons during the month.
2. After teaching, generate actual from planned.
3. At month end, review all actual rows.
4. Calculate approximate income:
   - `actual_hours * hourly_rate`
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

## Current Implementation Snapshot

As of commit `2fe6ae8`, generic income Cash confirmation code and SQL drafts exist:

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

- SQL has not been executed.
- Edge Function has not been deployed.
- Real income test has not been run.
- Frontend account routing has been implemented.
- Cash System income save path calls `request-cash-income-confirmation`.
- Production use depends on executing the School SQL and deploying the Edge Functions.

## Implementation Guardrails

- Do not use `teacher_wage` payment tables for personal external teaching income.
- Do not mark School income received before Cash approve.
- Do not write Cash transactions from School.
- Do not change Cash balances from School.
- Do not create Cash request from Cash proactively.
- Do not add cancel/makeup semantics unless a separate future design proves they are needed.
- Do not backfill old personal teaching income automatically.
