# v2 报销管理看不到老师工资待报销支出调查

Date: 2026-06-12

Scope: read-only investigation only. No feature code was changed, no SQL file was executed, no write RPC was called, and no database writes were performed.

## Summary

Root cause:

- v2 报销管理当前设计只支持普通非老师工资支出的报销。
- `js/api/reimbursement-api.js` 的待报销候选查询明确排除 `expense_category = 'teacher_wage'`。
- `reimbursement.html` 文案也写明候选区“仅显示当前月份中已支付、待报销、非老师工资的普通支出”。
- `school_create_reimbursement_record` RPC 进一步拒绝 `expense_category = 'teacher_wage'`，错误为“老师工资支出不能通过报销流程处理。”
- v1 报销管理的待报销列表只按 `reimbursement_status = 'pending'` 过滤，没有排除老师工资支出，所以 v1 可以看到该类记录。

This is not caused by the company-account no-reimbursement rule. The tested teacher wage was paid from a non-company account, and the generated expense correctly has `reimbursement_status = 'pending'`.

## Tested Teacher Wage Chain

The user-reported flow corresponds to the latest real 2026-06 pending teacher wage expense:

| Item | Value |
| --- | --- |
| Expense id | `300ce0be-5f0a-423b-acde-7ac7b2b40a15` |
| Expense category | `teacher_wage` |
| App type | `school` |
| Expense date / month | `2026-06-11` / `2026-06` |
| Description | `2026-06 工资结算测试老师 老师工资` |
| Status | `paid` |
| Reimbursement status | `pending` |
| Currency / amount | `JPY 8500` |
| Business entity | `7fdc0547-19e7-4199-9c66-3e8b832dd485` / `工资结算测试业务归属` |
| Account | `4f9c5090-b2e1-400c-8b0e-ff1a4cce6138` / `工资结算测试账户` |
| Account type | `bank` |
| Company account | `false` |
| Receipt status | `无需收据` |
| Payment request id | `53813782-28ea-4328-917f-57792b3e2a71` |
| Payment request status | `paid` |
| Payment source | `teacher_wage` / wage lock `d47953da-6283-4341-94ee-39124386fe63` |
| Account transaction id | `16ece0a2-24d1-4066-82e4-2a77f49ade35` |
| Account transaction | `expense_adjust`, related to the expense, amount `JPY -8500` |
| Reimbursement item count | `0` |

Wage snapshot side:

- Wage lock `d47953da-6283-4341-94ee-39124386fe63`
- Teacher `12f6d142-b90b-4da2-be88-310414000bd1` / `工资结算测试老师`
- Month `2026-06`
- Business entity `工资结算测试业务归属`
- Status `locked`
- Lesson count `1`
- Total minutes `120`
- Pay hours `2`
- Total JPY `8500`
- Wage detail total JPY `8500`
- Transport fee JPY `500`
- Classroom fee JPY `2000`
- One adjustment record exists: `ca263d36-93da-4f2b-afac-8d8b8dbbf46f`, reason `测试调整工资明细`, total changed from `6000` to `8500`.

No amount/account mismatch was found in this chain:

- Payment request amount: `JPY 8500`
- Expense amount: `JPY 8500`
- Account transaction amount: `JPY -8500`
- Payment request `paid_expense_id` points to the expense.
- Payment request `paid_account_transaction_id` points to the account transaction.
- Expense and account transaction business entity match.
- Paid account is not a company account, so `pending` reimbursement status is expected under the payment confirmation rule.

## v2 Behavior

### Main Reimbursement List

`reimbursement.html` main table reads `school_reimbursements`, not pending expenses. Therefore pending expenses are not shown in the main page list until a reimbursement record has already been created.

### Create Reimbursement Dialog

Pending expenses are loaded only inside the `确认报销` dialog via `fetchReimbursementCandidateExpenses`.

Current query in `js/api/reimbursement-api.js`:

- `app_type = 'school'`
- `status = 'paid'`
- `reimbursement_status = 'pending'`
- `expense_category <> 'teacher_wage'`
- optional month/business/currency filters

For `2026-06`, read-only DB checks showed:

| Scope | Visible to v2 candidate query |
| --- | --- |
| `other` pending expense `eb7f2165-6517-4fb1-b08e-1c820c1073cf`, JPY `2963` | yes |
| `teacher_wage` pending expense `300ce0be-5f0a-423b-acde-7ac7b2b40a15`, JPY `8500` | no |

Across all months currently:

- Pending ordinary expense: 1 row, JPY `2963`
- Pending teacher_wage expenses: 2 rows, JPY `22950`
- v2 candidate query returns only the ordinary pending expense.

### RPC Guard

`school_create_reimbursement_record` currently rejects selected expenses where `expense_category = 'teacher_wage'`.

This means the issue cannot be fixed safely by frontend/API filtering alone. Even if v2 shows teacher wage expenses in the candidate dialog, submit will still fail until the DB/RPC business guard is deliberately changed.

## v1 Behavior

v1 source inspected: `/Users/polariss710/Documents/aozora_school_system_v1_batch/js/legacy-core.js`.

v1 pending reimbursement list:

```js
return (state.expenseRecords || []).filter(x =>
  x.reimbursement_status === "pending" &&
  (!month || x.year_month === month) &&
  (!entity || x.business_entity_id === entity) &&
  (!account || x.account_id === account)
);
```

There is no teacher-wage exclusion in the v1 pending list. That explains why v1 can show the teacher wage pending reimbursement expense while v2 does not.

## Is This A Company Account Misjudgment?

No.

The tested expense account is `工资结算测试账户`:

- `account_type = bank`
- `is_company_account = false`
- account currency `JPY`
- account business entity matches the expense business entity

The payment confirmation RPC rule worked as intended:

- company account -> `reimbursement_status = 'not_required'`
- non-company account -> `reimbursement_status = 'pending'`

The bug/gap is downstream: reimbursement management excludes all `teacher_wage` candidates even when their `reimbursement_status = 'pending'`.

## Is This Individual Or General?

It is general for teacher wage expenses.

All pending teacher wage expenses are excluded by v2:

- `300ce0be-5f0a-423b-acde-7ac7b2b40a15`, 2026-06, JPY `8500`
- `5e17242b-34bb-44d0-ab7f-71c98a31a422`, 2029-02 codex-test, JPY `14450`

v2 can still show ordinary pending expenses in the create dialog. The current page does not provide a persistent pending-expense list outside the dialog, so users may also reasonably perceive “报销管理看不到待报销记录” even for ordinary pending items unless they open `确认报销`.

## Recommended Fix Scope

Minimum safe next-phase design:

1. Decide business rule: teacher wage expenses with `reimbursement_status = 'pending'` should be reimbursable when paid from non-company/advance/personal accounts.
2. Update `school_create_reimbursement_record` guarded RPC to allow `teacher_wage` only when all existing reimbursement guards pass and the expense is already `paid + pending`.
3. Keep the rule that reimbursement does not create another teacher_wage expense; it should only create reimbursement records/items/account transactions and mark the existing teacher_wage expense reimbursed.
4. Update `js/api/reimbursement-api.js` candidate query to include eligible `teacher_wage` pending expenses.
5. Update `reimbursement.html` and `js/pages/reimbursement-page.js` wording/category display so users can see pending teacher wage reimbursement candidates.
6. Consider adding a visible pending-expense section on the main reimbursement page, not only inside the create dialog.

Frontend/API-only fix is insufficient because the current RPC rejects teacher_wage expenses.

## Hard Stop Conditions For Next Phase

Hard stop before implementation if any of the following is found:

- Need to change account-balance, payment-confirmation, or wage-expense amount口径.
- Need to create a second teacher_wage expense during reimbursement.
- Existing pending teacher_wage expenses have mismatched payment request, expense, or account transaction amounts/accounts/business entities.
- Reimbursement account direction for teacher wage expenses is unclear.
- Cross-currency reimbursement is required; current v2 reimbursement RPC does not support cross-currency reimbursement.
