# 老师工资支付完成后的业务动作与状态显示调查

Date: 2026-06-12

Scope: read-only investigation only. No feature code was changed, no SQL file was executed, no write RPC was called, and no database writes were performed.

## Summary

Current v2 facts:

- Teacher wage payment confirmation creates one `teacher_wage` expense and one account transaction.
- Profit/monthly operating summary uses the paid `teacher_wage` expense as the actual operating expense.
- Payment requests are audit/status references and are not counted again as expense.
- Reimbursement records are audit/fund-flow references and are not operating expense.
- v2 ordinary reimbursement explicitly excludes `teacher_wage` expenses:
  - `js/api/reimbursement-api.js` filters `expense_category <> 'teacher_wage'`.
  - `reimbursement.html` says only non-teacher-wage ordinary pending expenses are shown.
  - `school_create_reimbursement_record` rejects `teacher_wage`.
- Therefore a paid teacher wage expense should not enter the current ordinary reimbursement workflow.

The confusing part is display/state wording:

- `school_confirm_payment_request` writes `reimbursement_status = 'pending'` when teacher wage is paid from a non-company account.
- Expense list/detail, payment detail, account transaction detail, and profit detail render `pending` as `待报销`.
- For `teacher_wage`, that label is misleading because the ordinary reimbursement module will not process the row.

Recommended next minimal fix is display-only: keep DB/payment/profit/account behavior unchanged, but render teacher-wage reimbursement status with teacher-wage-specific wording such as `垫付清算待处理` or `工资垫付待清算`, and render company-account teacher wage as `不适用（公司账户支付）` rather than generic `无需报销`.

## Current Data Chain

Sample provided by user:

| Item | Value |
| --- | --- |
| Payment request | `53813782-28ea-4328-917f-57792b3e2a71` |
| Wage lock | `d47953da-6283-4341-94ee-39124386fe63` |
| Expense | `300ce0be-5f0a-423b-acde-7ac7b2b40a15` |
| Account transaction | `16ece0a2-24d1-4066-82e4-2a77f49ade35` |
| Amount | `JPY 8500` |
| Payment account | `4f9c5090-b2e1-400c-8b0e-ff1a4cce6138` / `工资结算测试账户` |
| Account type | `bank` |
| Company account | `false` |

Chain:

1. `school_teacher_wage_locks`
   - id `d47953da-6283-4341-94ee-39124386fe63`
   - teacher `工资结算测试老师`
   - settlement month `2026-06`
   - business entity `工资结算测试业务归属`
   - status `locked`
   - total JPY `8500`
   - one wage detail; adjustment changed total from `6000` to `8500` by adding transport JPY `500` and classroom JPY `2000`

2. `school_payment_requests`
   - id `53813782-28ea-4328-917f-57792b3e2a71`
   - `source_type = teacher_wage`
   - `source_id = d47953da-6283-4341-94ee-39124386fe63`
   - status `paid`
   - amount `JPY 8500`
   - `account_id = 4f9c5090-b2e1-400c-8b0e-ff1a4cce6138`
   - `paid_expense_id = 300ce0be-5f0a-423b-acde-7ac7b2b40a15`
   - `paid_account_transaction_id = 16ece0a2-24d1-4066-82e4-2a77f49ade35`

3. `school_expense_records`
   - id `300ce0be-5f0a-423b-acde-7ac7b2b40a15`
   - `app_type = school`
   - `expense_category = teacher_wage`
   - status `paid`
   - `reimbursement_status = pending`
   - account `工资结算测试账户`
   - account `is_company_account = false`
   - business entity matches the payment request
   - amount `JPY 8500`

4. `school_account_transactions`
   - id `16ece0a2-24d1-4066-82e4-2a77f49ade35`
   - related table `school_expense_records`
   - related id `300ce0be-5f0a-423b-acde-7ac7b2b40a15`
   - transaction type `expense_adjust`
   - amount `JPY -8500`
   - balance after `JPY -8500`
   - account/business/currency match the expense

5. `school_reimbursement_items`
   - no item references the expense

Integrity check:

- Payment request amount: `JPY 8500`
- Expense amount: `JPY 8500`
- Account transaction amount: `JPY -8500`
- The sample account balance replays correctly: opening `0`, transaction sum `-8500`, current `-8500`
- No amount/account/business mismatch was found for this sample.

## Company Account vs Non-Company Account

Current RPC behavior in `school_confirm_payment_request`:

```sql
v_reimbursement_status := case
  when coalesce(v_account.is_company_account, false) then 'not_required'
  else 'pending'
end;
```

### Company Account Payment

Current behavior:

- Creates `teacher_wage` expense.
- Creates account transaction.
- Marks payment request paid.
- Writes `reimbursement_status = not_required`.
- Does not create reimbursement records/items.

Observed current sample:

- Company-account paid teacher wage exists: expense `9939dfc0-9f00-4e91-8c39-f18e70b95b2a`, JPY `1400`, `reimbursement_status = not_required`.

Business implication:

- Company-account teacher wage should not enter reimbursement or clearing; it is already paid directly from company funds.

### Non-Company / Advance Account Payment

Current behavior:

- Creates `teacher_wage` expense.
- Creates account transaction from the selected non-company account.
- Marks payment request paid.
- Writes `reimbursement_status = pending`.
- Does not create reimbursement records/items.
- Ordinary reimbursement module rejects it.

Observed current pending teacher wage rows:

- `300ce0be-5f0a-423b-acde-7ac7b2b40a15`, 2026-06, JPY `8500`
- `5e17242b-34bb-44d0-ab7f-71c98a31a422`, 2029-02 codex-test, JPY `14450`

Business implication:

- The non-company payment has created the real wage expense and account outflow.
- The remaining issue is fund clearing between company and advance/personal account.
- Current v2 ordinary reimbursement does not implement that clearing for teacher_wage.
- Existing account transfer can move funds between accounts and creates transfer audit transactions, but it does not link to the wage expense and does not update `reimbursement_status`.
- There is no dedicated `teacher_wage` advance-clearing workflow in v2 yet.

## Should teacher_wage Enter Ordinary Reimbursement?

Current v2 design says no:

- `docs/system-map.md` says reimbursement candidates exclude `teacher_wage`, and reimbursement must not recreate teacher wage expense.
- `docs/module-status.md` says reimbursement candidates exclude `teacher_wage`, and `school_create_reimbursement_record` rejects teacher_wage expenses even if `reimbursement_status = pending`.
- `school_create_reimbursement_record` enforces the exclusion at DB/RPC level.

v1 was broader:

- v1 pending reimbursement list filters `state.expenseRecords` by `reimbursement_status === 'pending'` plus month/entity/account.
- v1 does not exclude teacher wage in that display.
- That explains why v1 can show the teacher wage pending row.

Conclusion:

- v1 visibility alone is not enough to conclude that teacher wage should use ordinary reimbursement in v2.
- v2 intentionally narrowed ordinary reimbursement to non-teacher-wage expenses.
- If the business wants teacher-wage advance clearing, it should be designed explicitly rather than silently adding teacher_wage to ordinary reimbursement.

## Does reimbursement_status Have Business Meaning On teacher_wage?

Currently it has partial meaning:

- `not_required`: direct company-account wage payment needs no clearing.
- `pending`: non-company account paid the wage; some fund-clearing action may still be needed.

But the labels are wrong for teacher_wage:

- `pending` currently renders as `待报销`, which implies the ordinary reimbursement page should process it.
- Because ordinary reimbursement excludes teacher_wage, the better user-facing meaning is closer to `垫付清算待处理` or `工资垫付待清算`.
- `not_required` for teacher_wage should probably display as `不适用（公司账户支付）` or `无需清算（公司账户支付）`, not generic `无需报销`.

Current DB has mixed historical status values:

- paid teacher_wage from company account: 1 row `not_required`
- paid teacher_wage from non-company account: 2 rows `pending`, 10 rows `not_required`
- reversed teacher_wage also contains historical `pending` / `not_required` values

The historical non-company `not_required` rows appear to come from older data/rules. No amount/account transaction mismatch was found in the current sample; this document does not propose historical repair.

## Display Points That Mislead Users

Current display points:

- `expense.html` table always renders `reimbursement_status` through generic labels:
  - `pending` -> `待报销`
  - `not_required` -> `无需报销`
  - `paid` -> `已报销`
- `expense-detail.html` displays `报销状态` with the same generic labels even for `teacher_wage`.
- `payment-detail.html` paid expense summary displays `报销状态` with generic labels.
- `profit-summary.html` expense detail displays raw `reimbursement_status`, so `pending` can appear without context.
- `account-transaction-detail.html` expense source summary displays raw `reimbursement_status`.

These displays make users expect the row to appear in `reimbursement.html`, but that module explicitly excludes it.

## Profit / Monthly Summary / Account Dependency

Read-only code review:

- Profit summary uses paid expense records as operating expense.
- Teacher wage expenses are included through `school_expense_records.expense_category = teacher_wage`.
- Payment requests are audit/status references and are not counted again.
- Reimbursements, account transfers, and account adjustments are audit/fund-flow references and do not affect operating profit.
- The sample paid teacher wage expense contributes `JPY 8500` to paid expense regardless of whether `reimbursement_status` displays as pending/not_required/paid.
- Account balance is driven by `school_account_transactions`, not by display labels.

Therefore display-only changes for teacher_wage reimbursement wording should not affect profit, account balances, payment request status, or wage amount口径.

Changing the stored `reimbursement_status` semantics, adding teacher_wage to ordinary reimbursement, or historical repair would require a separate guarded DB/RPC workflow.

## Recommended Minimal Fix

Safe next step without business口径 changes:

1. Display-only fix:
   - For `expense_category = teacher_wage`, do not render generic `待报销/已报销/无需报销`.
   - Render teacher-wage-specific labels:
     - `pending` -> `工资垫付待清算` or `垫付清算待处理`
     - `not_required` -> `无需清算（公司账户支付）` or `不适用（公司账户支付）`
     - `paid` if it appears historically -> `已清算` only after confirming meaning
   - Add note in expense/payment detail: teacher wage does not enter ordinary reimbursement; use account transfer/clearing workflow if funds need moving.

2. Page clarity:
   - In `reimbursement.html`, keep teacher_wage excluded unless business decides otherwise.
   - Make the candidate note explicit: teacher wage expenses are handled outside ordinary reimbursement.

3. Optional next design:
   - Add a dedicated teacher-wage advance-clearing workflow, or define account transfer as the formal clearing action.
   - If using account transfer, decide whether it should link back to the teacher_wage expense/payment request and whether it should update a clearing status.

## What Can Be Done Next Without Business Confirmation

Can be done as display-only next phase:

- Change teacher_wage reimbursement labels in:
  - `expense.html`
  - `expense-detail.html`
  - `payment-detail.html`
  - `profit-summary.html`
  - `account-transaction-detail.html`
- Clarify `reimbursement.html` text that teacher wage is intentionally excluded from ordinary reimbursement.
- Keep DB values unchanged.
- Keep reimbursement RPC unchanged.
- Keep profit/payment/account calculations unchanged.

## What Needs Business Confirmation / Hard Stop

Needs confirmation before implementation:

- Whether non-company teacher wage payment should be cleared by generic account transfer or a dedicated teacher-wage clearing workflow.
- Whether teacher_wage should ever be allowed in `school_create_reimbursement_record`.
- Whether `reimbursement_status` should be renamed/repurposed for teacher_wage or a new clearing-status field is needed.
- Whether historical non-company teacher_wage rows with `reimbursement_status = not_required` should be repaired or simply displayed as historical/legacy state.

Hard stop if a future change requires:

- Changing teacher wage amount, payment confirmation amount, or account-balance口径.
- Creating a second `teacher_wage` expense during clearing/reimbursement.
- Broad historical repair of teacher_wage reimbursement statuses.
- Cross-business or cross-currency clearing without a dedicated design.
- Updating real historical records outside a whitelisted test/rollback workflow.
