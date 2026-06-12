# Part-Time / Temporary Wage Record Module Design

Status date: 2026-06-12

Task type: design-only. This document does not implement SQL, RPC, API, or UI changes.

## Goal

Design a module for non-lesson labor costs such as administrative work, short-term part-time work, temporary staff, and fixed ad-hoc labor payments, without confusing it with the existing teacher lesson-wage snapshot chain.

## Target Use Cases

Applicable workers:

- administrative / affairs teachers (`事务老师`);
- short-term part-time workers;
- temporary workers;
- teachers doing non-lesson labor;
- external helpers who do not need full lesson/wage-rule setup.

Applicable pay types:

- hourly wage;
- daily wage;
- fixed amount;
- transport fee;
- allowance/subsidy;
- manual adjustment item.

Not in scope:

- lesson-based teacher wages generated from actual lessons;
- student settlement;
- teacher wage rules for lesson pay;
- historical wage repair.

## Recommendation

Build this as an independent part-time wage record module, not as another path into existing teacher wage snapshots.

Recommended model:

- part-time wage records are source records for non-lesson labor;
- records can be grouped by month/business entity/worker for review;
- approved unpaid records can generate payment requests through a new source type such as `part_time_wage`;
- payment confirmation reuses the payment request -> expense -> account transaction chain after that chain explicitly supports the new source type;
- records do not enter `school_teacher_wage_locks` or `school_teacher_wage_lock_details`;
- records do not use lesson wage rules and do not require student monthly settlements.

This separation keeps the current teacher lesson-wage chain stable and makes non-lesson labor auditable as its own source.

## Core Data Model

Recommended future tables:

### `school_part_time_wage_records`

Suggested fields:

- `id`
- `app_type`
- `business_entity_id`
- `worker_type`: `teacher`, `staff`, `external`
- `teacher_id` nullable
- `worker_name_snapshot`
- `worker_category`: `事务老师`, `短期兼职`, `临时工`, `其他`
- `work_date`
- `year_month`
- `pay_method`: `hourly`, `daily`, `fixed`
- `currency`: likely `JPY` first, but do not hardcode forever
- `hours`
- `days`
- `unit_rate`
- `base_amount`
- `transport_amount`
- `allowance_amount`
- `adjustment_amount`
- `total_amount`
- `description`
- `note`
- `status`: `draft`, `approved`, `payment_requested`, `paid`, `void`
- `payment_request_id` nullable
- audit columns: `created_at`, `updated_at`, `approved_at`, `voided_at`, `void_reason`

### Optional `school_part_time_wage_batches`

Use only if the UI needs monthly review/approval before payment request generation.

Suggested grouping:

- `business_entity_id`
- `worker_type`
- `teacher_id` / worker snapshot
- `year_month`
- `currency`
- `status`
- totals

Avoid introducing batch locks until the record lifecycle is understood.

## Calculation Rules

- `hourly`: `base_amount = hours * unit_rate`
- `daily`: `base_amount = days * unit_rate`
- `fixed`: `base_amount = fixed input`
- `total_amount = base_amount + transport_amount + allowance_amount + adjustment_amount`
- Negative adjustment can be allowed only as an explicit adjustment amount with reason.
- Transport/allowance here belongs to non-lesson labor, not lesson wage-rule transport/classroom fields.

## Lifecycle

Recommended first lifecycle:

1. `draft`
   - editable;
   - no payment request;
   - no expense;
   - no account transaction.
2. `approved`
   - amount frozen for payment request generation;
   - only void/reopen rules can change it.
3. `payment_requested`
   - linked to one payment request;
   - no direct edit.
4. `paid`
   - payment request has been confirmed;
   - generated expense/account transaction become audit evidence;
   - no edit or ordinary void.
5. `void`
   - allowed only before payment;
   - preserves original record.

Cancellation after payment should follow payment reversal flow, not direct wage-record deletion.

## Payment Request Integration

Recommended future extension:

- Add or reuse a payment request source discriminator:
  - `request_type = part_time_wage` or `source_type = part_time_wage`.
- Payment request references:
  - one approved part-time wage record, or
  - one approved batch.
- Payment confirmation creates:
  - expense record with category such as `part_time_wage` / `labor_cost`;
  - account transaction;
  - paid status updates back to the part-time wage source.

This must be implemented as an explicit extension to payment RPCs, not by pretending part-time wage records are teacher wage snapshots.

## Reimbursement Behavior

If paid from a company account:

- expense reimbursement status should be `not_required`.

If paid from an approved advance/personal-business account:

- expense reimbursement status can be `pending`;
- reimbursement candidate logic must include or exclude `part_time_wage` deliberately.

Do not inherit the current teacher-wage reimbursement special case blindly. Teacher wage expenses currently have special rejection rules in reimbursement flows; part-time wage should get its own business rule.

## Monthly Summary And Locking

Recommended first version:

- Provide monthly summary by `year_month`, business entity, worker, currency, and status.
- Do not add hard monthly locks in the first phase.
- Freeze records once approved or linked to payment request.
- Reject edits once `payment_requested` or `paid`.

Future version:

- Add monthly close/lock only if operations need batch approval.
- Locking must not share `school_teacher_wage_locks`.

## Avoiding Confusion With Existing Teacher Wages

Required UI and data wording:

- Existing teacher wage module remains "课时工资 / 老师工资快照".
- New module should be named "兼职工资" or "非课时工资".
- Records must show `source = part_time_wage`.
- Do not show part-time records in teacher lesson wage candidate previews.
- Do not match part-time records through wage rules.
- Do not require student settlement.
- Do not write `school_teacher_wage_lock_details`.

## Impact Scope

### Tables

Potential new tables:

- `school_part_time_wage_records`
- optional `school_part_time_wage_batches`

Potential existing table impacts:

- `school_payment_requests`: source/type support for `part_time_wage`
- `school_expense_records`: expense category/source support
- `school_account_transactions`: related table/source metadata

### RPC

Potential future RPCs:

- create/update part-time wage record
- approve/void record
- generate payment request from approved record or batch
- read monthly summary

Payment confirmation/reversal RPCs need explicit source-type support before part-time wage can enter payment flow.

### API

Potential future files:

- `js/api/part-time-wage-api.js`
- payment API extensions for source type display and actions
- expense/reimbursement API filters if part-time wage expenses should be reimbursable

### Pages

Potential future pages:

- `part-time-wage.html`: list/create/edit/approve/void/monthly summary
- `part-time-wage-detail.html`: audit detail, payment request link, expense/account evidence
- payment page source labels for `part_time_wage`
- expense/reimbursement pages source/category labels as needed

## Risks

- If part-time wages enter `school_teacher_wage_locks`, they will inherit lesson settlement assumptions and create false blockers.
- If payment requests do not distinguish source type, teacher wage payment logic may create wrong expense/reimbursement behavior.
- If external workers are stored only as free text, duplicate identity and reporting issues may appear.
- If records are editable after payment request/paid status, source totals and payment evidence can diverge.
- If transport/allowance are mixed back into wage rules, lesson wage generation becomes harder to reason about.

## Phased Implementation

1. Design audit phase:
   - inspect payment request schema, expense categories, reimbursement candidate guards, and teacher wage payment assumptions.
2. Part-time record MVP:
   - create/list/edit draft records;
   - approve/void unpaid records;
   - monthly summary read-only;
   - no payment request integration yet if payment RPC source typing is not ready.
3. Payment request integration:
   - add `part_time_wage` source support;
   - generate one payment request from approved records/batch;
   - verify no teacher wage snapshot tables are touched.
4. Payment confirmation and expense integration:
   - confirm payment into expense/account transaction with explicit `part_time_wage` category/source;
   - define reimbursement behavior for company vs advance accounts.
5. Reporting and detail:
   - add detail page links to payment, expense, and account evidence;
   - update monthly labor-cost summaries.
6. Advanced operations:
   - recurring templates;
   - CSV import;
   - batch approval/locking if operationally required;
   - worker master table if external worker duplication becomes a real issue.

## Open Questions

- Whether external workers should be a new master-data table or only snapshot text in v1.
- Whether part-time wage supports CNY in first implementation or starts JPY-only.
- Whether reimbursement candidates should include part-time wage paid from advance accounts.
- Whether tax/withholding/social insurance needs explicit fields or stays out of v1.
