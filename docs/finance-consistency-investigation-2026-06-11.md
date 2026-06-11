# Finance Consistency Investigation 2026-06-11

Scope: guarded investigation only. All database work in this pass was read-only `select` / metadata inspection. No real data repair, no SQL/RPC execution file, and no write RPC call was run.

Target months: `2026-05`, `2026-06`.

## Summary

The teacher wage payment-request checks remain clean for the target months: zero-yen wage snapshots, void wage snapshots, and pending/cancelled/void/reversed teacher wage payment requests did not create paid expense or account-transaction side effects.

The close blockers are finance/account-chain data issues created before the current guarded RPC patterns were in place. The strongest source marker is account transaction description `前端收支记录联动账户余额`, which does not appear in current page/API code or current verified RPC output.

Current page modules still have no direct `.rpc()` or direct insert/update/delete/upsert calls. Current income, expense, reimbursement, and teacher-wage payment RPCs write source rows, account balances, and account transactions in one database transaction and do not delete source rows. However, `school_account_transactions.related_table / related_id` is polymorphic and has no FK to the source table, so historical/manual/service-role operations can still leave orphan references unless a separate validation or guarded maintenance flow is added.

## 1. Orphan Account Transactions

Definition: `school_account_transactions` rows where `related_table = 'school_expense_records'` but `related_id` no longer exists in `school_expense_records`.

Counts and amount impact:

| Month | Type | Currency | Count | Net Amount | Date Range |
|---|---|---:|---:|---:|---|
| 2026-05 | `expense_adjust` | JPY | 63 | -308718 | 2026-04-20..2026-05-20 |
| 2026-06 | `expense_adjust` | JPY | 6 | 0 | 2026-06-15..2026-06-15 |

Account distribution:

| Month | Account | Currency | Count | Net Amount |
|---|---|---:|---:|---:|
| 2026-05 | `包垫付金额` | JPY | 14 | -178319 |
| 2026-05 | `吴垫付金额` | JPY | 45 | -130399 |
| 2026-05 | `吴个人结算账户日元` | JPY | 2 | 0 |
| 2026-05 | `GMOあおぞらネット銀行` | JPY | 2 | 0 |
| 2026-06 | `GMOあおぞらネット銀行` | JPY | 2 | 0 |
| 2026-06 | `包垫付金额` | JPY | 4 | 0 |

Representative samples:

| Month | Date | Amount | Account | Short Tx | Short Source | Description |
|---|---|---:|---|---|---|---|
| 2026-05 | 2026-04-20 | -150000 | `包垫付金额` | `d05544f9` | `9affbc82` | `前端收支记录联动账户余额` |
| 2026-05 | 2026-05-18 | -100000 | `吴垫付金额` | `0860f0db` | `2f3d3b86` | `前端收支记录联动账户余额` |
| 2026-05 | 2026-05-07 | -23409 | `包垫付金额` | `6c1ed64d` | `9869b006` | `前端收支记录联动账户余额` |
| 2026-05 | 2026-05-20 | -28600 / +28600 | `吴个人结算账户日元` | `abd41a17` / `105a4607` | `cef339e8` | `前端收支记录联动账户余额` |

Likely source classification:

- Real business accounts are involved; do not classify as codex-test.
- The missing source rows look like historical deleted expense records or historical frontend/direct-write cleanup residue.
- Many related ids have paired positive/negative rows netting to zero, but several singleton negative rows remain and affect flow totals.

Repair guidance:

- Do not hard delete these account transactions.
- Do not infer the missing expense records automatically.
- For net-zero paired orphans, keep for audit unless a future `voided`/ignored status exists for account transactions.
- For non-zero orphan groups, require business/source evidence before repair. Preferred guarded repair is logical void/reversal with audit, not deletion.
- If a future maintenance RPC is built, it should first dry-run candidate ids, reject any candidate with a live source row, require an operator reason, write an audit record, and either mark transactions inactive/void or insert compensating reversal transactions according to a documented account-balance baseline policy.

## 2. Duplicate `expense_adjust`

Definition: one existing `school_expense_records` source has more than one original `expense_adjust` transaction, or the transaction sum does not match `-expense.amount`.

Summary:

| Month | Status | Expense Count | OK | Mismatch | Paid Amount | Original Tx Outflow |
|---|---|---:|---:|---:|---:|---:|
| 2026-05 | paid | 22 | 21 | 1 | 399935 | 428935 |
| 2026-06 | paid | 5 | 4 | 1 | 563263 | 563263 |
| 2026-06 | reversed | 2 | 2 | 0 | 0 | 0 |

Mismatched sources:

| Month | Expense | Amount | Tx Count | Tx Sum | Account | Description | Impact |
|---|---|---:|---:|---:|---|---|---|
| 2026-05 | `a2b16d72` | 130000 | 5 | -159000 | `吴垫付金额` | `系统开发 数据库租赁 域名购买` | Over-posted by 29000 if expense amount is authoritative |
| 2026-06 | `3ecbbe02` | 536430 | 2 | -536430 | `吴垫付金额` | empty | Net amount matches, but reversal guard expects one original tx |

Representative details:

- `a2b16d72`: tx amounts `-100000`, `-29000`, `-29000`, `-603`, `-397`; all have description `前端收支记录联动账户余额`.
- `3ecbbe02`: tx amounts `-528200`, `-8230`; total matches source amount, but the source has split original transactions.

Likely source classification:

- Real business data, not codex-test.
- `a2b16d72` is likely duplicate/partial repost residue.
- `3ecbbe02` may be split-entry residue. It has no net amount mismatch, but it violates the current one-source/one-original-transaction guard.

Repair guidance:

- Do not delete duplicate rows.
- For `a2b16d72`, stop until business confirms whether the source expense amount `130000` is authoritative. If yes, void/reverse the extra net `29000` with audit; if no, the expense record itself needs a separate guarded business correction.
- For `3ecbbe02`, do not change amount. Either keep the split rows and update reversal logic in a future guarded phase to accept multiple same-account/same-currency original rows when `sum(amount) = -expense.amount`, or canonicalize by voiding old split transactions and inserting one replacement transaction through an audited maintenance RPC. The first option is lower data churn.
- Current `school_reverse_expense_record` correctly rejects these cases because it requires exactly one original `expense_adjust`; this prevents unsafe reversal but also means these records cannot be reversed until repaired or the guard is deliberately extended.

## 3. Missing Income Transactions

Definition: `school_income_records.status = 'received'` but no matching `income_adjust` account transaction exists.

Counts and amount impact:

| Month | Currency | Received Count | Missing Count | Missing Amount |
|---|---:|---:|---:|---:|
| 2026-05 | CNY | 3 | 3 | 36503 |
| 2026-06 | CNY | 3 | 2 | 14231 |

Samples:

| Month | Income | Date | Amount | Account On Income | Account Currency | Business | Note |
|---|---|---|---:|---|---:|---|---|
| 2026-05 | `dbbd096b` | 2026-05-15 | 21450 CNY | `吴个人结算账户日元` | JPY | `个人名义` | no income tx |
| 2026-05 | `56ea38e9` | 2026-05-20 | 8853 CNY | `吴个人结算账户日元` | JPY | `个人名义` | no income tx |
| 2026-05 | `da7a2140` | 2026-05-20 | 6200 CNY | `吴个人结算账户日元` | JPY | `个人名义` | no income tx |
| 2026-06 | `2fd2b2bd` | 2026-05-29 | 7740 CNY | `吴个人结算账户日元` | JPY | `个人名义` | no income tx |
| 2026-06 | `7483261a` | 2026-05-29 | 6491 CNY | `吴个人结算账户日元` | JPY | `个人名义` | no income tx |

Likely source classification:

- Real business/student tuition data, not codex-test.
- These records also point to a JPY account while the income currency is CNY. Current `school_create_income_record` would reject this with the account-currency guard, so these are historical/import/direct-write records rather than current RPC output.

Repair guidance:

- Do not blindly create account transactions against the recorded JPY account.
- Business must confirm the intended CNY receiving account, or confirm that these CNY tuition income records are settlement-only and should not affect account balances.
- If the income should affect account balance, build a guarded RPC that inserts missing `income_adjust` rows only after confirming `income.currency = target_account.currency`, same business ownership, no existing income transaction, and a required reason. It must not modify locked student settlement amounts.
- If the recorded `account_id` is wrong, fix should be treated as a source correction with audit, not as silent transaction generation.

## 4. Account Balance Mismatch

Two balance checks give different signals:

- `current_balance = latest account transaction.balance_after`: passed for the six accounts that failed full recomputation.
- `current_balance = opening_balance + sum(all account transactions)`: failed for 6 / 14 school accounts.

Mismatch accounts:

| Account | Business | Currency | Current | Opening + All Tx | Difference | Classification |
|---|---|---:|---:|---:|---:|---|
| `GMOあおぞらネット銀行` | `青空进学塾` | JPY | 853102 | 1701896 | -848794 | real |
| `吴垫付金额` | `青空进学塾` | JPY | 0 | -600193 | 600193 | real |
| `包垫付金额` | `青空进学塾` | JPY | 0 | -339519 | 339519 | real |
| `吴个人结算账户日元` | `个人名义` | JPY | 1234 | -119016 | 120250 | real |
| `codex-test v2.84 commit 公司支付账户` | codex-test | JPY | 98600 | -1400 | 100000 | test |
| `codex-test v2.84 commit 垫付支付账户` | codex-test | JPY | 48500 | -1500 | 50000 | test |

Interpretation:

- The displayed/current account balances match the latest recorded `balance_after`, so the account table is internally aligned with the last incremental write.
- The full recomputation from opening balance is not reliable until the baseline policy is defined and historical orphan/duplicate/missing transactions are resolved.
- The codex-test mismatches are whitelist test residue and can be handled separately from real finance data.

Repair guidance:

- Do not overwrite `current_balance` with `opening_balance + sum(all transactions)` yet.
- Define an account-balance baseline first: either opening balance is the start of all recorded transactions, or a monthly/account snapshot becomes the replay starting point.
- Preferred future mechanism: `school_account_balance_snapshots` plus a guarded recalculation RPC that computes from an approved snapshot through active transactions only, with dry-run output before commit.
- Real accounts and codex-test accounts should be handled in separate phases.

## Current RPC / Code Risk Review

Reviewed current code and DB definitions:

- Page-layer scan found no direct `.rpc()` and no direct insert/update/delete/upsert in `js/pages`.
- No repository SQL/code path was found that deletes `school_expense_records`.
- `school_create_income_record` creates one income, updates one account, and inserts one `income_adjust` in one transaction; it rejects account/currency mismatch.
- `school_create_expense_record` creates one paid ordinary expense, updates one account, and inserts one negative `expense_adjust` in one transaction; it rejects teacher_wage manual creation.
- `school_reverse_income_record` and `school_reverse_expense_record` preserve source rows and require exactly one original transaction before inserting reversal transactions.
- `school_create_reimbursement_record` / `school_reverse_reimbursement_record` preserve source rows and write paired reimbursement account transactions. Target-month reimbursement chains passed current consistency checks.
- `school_confirm_payment_request` creates one teacher_wage expense and one account transaction in one transaction and links both back to the payment request.

Resolved future policy risk:

- Follow-up on 2026-06-11 replaced `school_reverse_paid_payment_request` for future reversals so it now reverses cash movement, marks the payment request `reversed`, and marks the generated teacher_wage expense `reversed` with the same `payment_reversal` transaction id. A separate guarded historical-data phase later on 2026-06-11 executed `school_fix_historical_reversed_teacher_wage_expenses_20260611.sql` for the exact five older rows (`2026-02`: 3 rows / JPY 141250; `2026-03`: 2 rows / JPY 160250), marking only the generated teacher_wage expenses `reversed` and linking them to existing payment reversal transactions. Post-repair historical reversed teacher_wage payment / paid expense mismatches are `0`.

## Guarded Repair Plan

Recommended future phases:

1. Dry-run candidate export.
   - Produce immutable candidate lists for orphan expense transactions, duplicate expense transactions, missing income transactions, and account-balance baseline mismatches.
   - Include full ids, accounts, business entity, source status, amounts, and proposed action.
   - No writes.

2. Policy confirmation.
   - Confirm whether historical deleted expenses should be reconstructed, voided, or left as audit-only.
   - Confirm whether split original expense transactions may be treated as one effective source by sum.
   - Confirm intended CNY receiving account for the five tuition income rows.
   - Confirm account-balance baseline policy.
   - Confirm payment reversal vs teacher_wage expense policy for older reversed payments.

3. Guarded maintenance schema/RPC design.
   - Add audit-first primitives rather than hard delete.
   - Candidate writes should require a reason, target ids, exact expected old values, and whitelist/business approval.
   - Maintenance RPCs should reject broad month-only updates unless the candidate set was precomputed and matches expected counts/sums.

4. Whitelist test first.
   - Validate maintenance RPCs only on codex-test account/source rows.
   - Verify rollback, commit test, duplicate-run rejection, and no unrelated table changes.

5. Real data repair only after explicit phase authorization.
   - Use exact id lists and expected sums.
   - Re-run the consistency report after each category.

Dry-run query pattern for future candidate export:

```sql
select t.*
from public.school_account_transactions t
left join public.school_expense_records e on e.id = t.related_id
where t.app_type = 'school'
  and t.related_table = 'school_expense_records'
  and t.transaction_type = 'expense_adjust'
  and e.id is null;
```

```sql
select e.id, e.year_month, e.amount, count(t.id) as tx_count, sum(t.amount) as tx_sum
from public.school_expense_records e
left join public.school_account_transactions t
  on t.related_table = 'school_expense_records'
 and t.related_id = e.id
 and t.transaction_type = 'expense_adjust'
where e.app_type = 'school'
group by e.id, e.year_month, e.amount
having count(t.id) <> 1 or sum(t.amount) is distinct from -e.amount;
```

```sql
select i.*
from public.school_income_records i
left join public.school_account_transactions t
  on t.related_table = 'school_income_records'
 and t.related_id = i.id
 and t.transaction_type = 'income_adjust'
where i.app_type = 'school'
  and i.status = 'received'
group by i.id
having count(t.id) = 0;
```

```sql
select a.id, a.name, a.currency, a.opening_balance, a.current_balance,
       a.opening_balance + coalesce(sum(t.amount), 0) as calculated_balance
from public.school_accounts a
left join public.school_account_transactions t
  on t.account_id = a.id
 and t.app_type = 'school'
where a.app_type = 'school'
group by a.id, a.name, a.currency, a.opening_balance, a.current_balance;
```
