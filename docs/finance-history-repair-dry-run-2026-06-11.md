# Finance History Repair Dry-Run 2026-06-11

Scope: dry-run candidate list and guarded repair design only. This pass did not execute any real-data write, did not run repair SQL/RPC, and did not change amount, closing, or account-balance policy.

Source documents:

- `docs/finance-consistency-investigation-2026-06-11.md`
- Current DB dry-run `select` checks run on 2026-06-11 after the future `teacher_wage` payment reversal fix.

## Executive Summary

| Issue Type | Records | Amount Impact | Accounts | Months | Risk | Auto-Fix? | Manual Confirmation |
|---|---:|---:|---|---|---|---|---|
| Orphan account transactions -> missing expenses | 75 tx / 48 missing-source groups | JPY `-469918` net | `包垫付金额`, `吴垫付金额`, `GMOあおぞらネット銀行`, `吴个人结算账户日元` | 2026-04..2026-06 | High | No | Required |
| Duplicate/split non-wage `expense_adjust` | 2 expenses | One over-post candidate JPY `29000`; one split source net-ok | `吴垫付金额` | 2026-05..2026-06 | High | No | Required |
| Missing CNY income transactions | 10 income rows | CNY `128929` missing tx candidate amount | `吴个人结算账户日元` recorded, but account is JPY | 2026-02..2026-06 | High | No | Required |
| Historical reversed teacher_wage payment with expense still paid | 5 payment/expense pairs | JPY `301500` still counted as paid expense unless excluded by policy | `吴个人结算账户日元` | Expense months 2026-02..2026-03; reversal tx month 2026-05 | Medium/High | No for history | Required |
| Account balance mismatch by `opening + all tx` | 6 accounts | JPY `361168` aggregate mismatch | 4 real accounts + 2 codex-test accounts | Latest tx through 2026-06 / 2028-12 test data | High | No | Required |

Current code risk check:

- Future `teacher_wage` payment reversal is fixed: `school_reverse_paid_payment_request` now marks the generated `teacher_wage` expense `reversed` together with the payment request and cash reversal.
- Page modules still have no direct `.rpc()` or direct insert/update/delete/upsert.
- No additional current-code fix is recommended in this dry-run pass.

## 1. Orphan Account Transactions

Definition: `school_account_transactions.related_table = 'school_expense_records'` where `related_id` no longer exists in `school_expense_records`.

Dry-run counts:

| Month | Type | Currency | Tx Count | Net Amount | Date Range |
|---|---|---:|---:|---:|---|
| 2026-04 | `expense_adjust` | JPY | 6 | -161200 | 2026-04-16..2026-04-20 |
| 2026-05 | `expense_adjust` | JPY | 63 | -308718 | 2026-04-20..2026-05-20 |
| 2026-06 | `expense_adjust` | JPY | 6 | 0 | 2026-06-15..2026-06-15 |
| Total | `expense_adjust` | JPY | 75 | -469918 | 2026-04-16..2026-06-15 |

Account impact:

| Month | Account | Business | Currency | Tx Count | Net Amount |
|---|---|---|---:|---:|---:|
| 2026-04 | `包垫付金额` | `青空进学塾` | JPY | 6 | -161200 |
| 2026-05 | `包垫付金额` | `青空进学塾` | JPY | 14 | -178319 |
| 2026-05 | `吴垫付金额` | `青空进学塾` | JPY | 45 | -130399 |
| 2026-05 | `GMOあおぞらネット銀行` | `青空进学塾` | JPY | 2 | 0 |
| 2026-05 | `吴个人结算账户日元` | `个人名义` | JPY | 2 | 0 |
| 2026-06 | `包垫付金额` | `青空进学塾` | JPY | 4 | 0 |
| 2026-06 | `GMOあおぞらネット銀行` | `青空进学塾` | JPY | 2 | 0 |

Missing-source group summary:

| Month | Groups | Net-Zero Groups | Non-Zero Groups | Net Amount |
|---|---:|---:|---:|---:|
| 2026-04 | 5 | 1 | 4 | -161200 |
| 2026-05 | 41 | 22 | 19 | -308718 |
| 2026-06 | 2 | 2 | 0 | 0 |

Largest non-zero groups:

| Month | Missing Source | Account | Currency | Tx Count | Net Amount | Date |
|---|---|---|---:|---:|---:|---|
| 2026-04 | `85faae2c` | `包垫付金额` | JPY | 1 | -40300 | 2026-04-20 |
| 2026-04 | `8f7092d5` | `包垫付金额` | JPY | 1 | -40300 | 2026-04-20 |
| 2026-04 | `991eb35a` | `包垫付金额` | JPY | 1 | -40300 | 2026-04-20 |
| 2026-04 | `b8e2778b` | `包垫付金额` | JPY | 1 | -40300 | 2026-04-16 |
| 2026-05 | `9affbc82` | `包垫付金额` | JPY | 1 | -150000 | 2026-04-20 |
| 2026-05 | `2f3d3b86` | `吴垫付金额` | JPY | 1 | -100000 | 2026-05-18 |
| 2026-05 | `9869b006` | `包垫付金额` | JPY | 1 | -23409 | 2026-05-07 |

Recommendation:

- Risk: High.
- Suggested automatic fix: No.
- Manual confirmation: Required.
- Do not hard delete account transactions.
- Net-zero groups can be left as audit-only or marked ignored/void if a future transaction status exists.
- Non-zero groups need business confirmation because they may represent real expenses whose source records were deleted.
- Preferred repair path is an audited maintenance RPC that writes logical void/reversal markers or compensating audit transactions only for exact approved ids and expected amounts.

Dry-run candidate query:

```sql
select t.*
from public.school_account_transactions t
left join public.school_expense_records e on e.id = t.related_id
where t.app_type = 'school'
  and t.related_table = 'school_expense_records'
  and t.transaction_type in ('expense_adjust', 'expense_reversal')
  and e.id is null;
```

Guarded repair RPC sketch:

```sql
-- Draft only. Do not execute as-is.
-- public.school_void_orphan_account_transactions(p_transaction_ids uuid[], p_expected_net numeric, p_reason text)
-- Validates:
--   1. all ids still point to missing source rows;
--   2. related_table/type match the approved class;
--   3. sum(amount) equals p_expected_net;
--   4. reason is nonblank;
--   5. every id is explicitly listed, no month-wide update.
-- Writes:
--   either a future audit/void table or compensating reversal rows,
--   depending on the approved account-balance baseline policy.
```

## 2. Duplicate / Split Non-Wage `expense_adjust`

Definition: live non-`teacher_wage` expense rows whose original `expense_adjust` count is not one, or whose `expense_adjust` sum does not equal `-expense.amount`.

Dry-run details:

| Expense | Month | Status | Category | Amount | Tx Count | Tx Sum | Account | Business | Recommendation |
|---|---|---|---|---:|---:|---:|---|---|---|
| `a2b16d72` | 2026-05 | paid | other | 130000 | 5 | -159000 | `吴垫付金额` | `青空进学塾` | Manual decision; likely over-posted by 29000 if expense amount is authoritative |
| `3ecbbe02` | 2026-06 | paid | other | 536430 | 2 | -536430 | `吴垫付金额` | `青空进学塾` | Keep amount; decide whether to support split originals or canonicalize audit chain |

Recommendation:

- Risk: High.
- Suggested automatic fix: No.
- Manual confirmation: Required.
- `a2b16d72`: confirm the authoritative amount. If the expense record amount `130000` is authoritative, void/reverse the extra net `29000` through an audited maintenance flow. If the posted total `159000` is authoritative, the source expense amount itself needs separate business correction.
- `3ecbbe02`: amount is net-consistent but split across two original transactions. Prefer extending reversal guard in a future phase to accept multiple same-account/same-currency originals when `sum(amount) = -expense.amount`, rather than rewriting historical rows.

Dry-run candidate query:

```sql
select e.id, e.year_month, e.status, e.expense_category, e.currency, e.amount,
       count(t.id) filter (where t.transaction_type = 'expense_adjust') as adjust_count,
       sum(t.amount) filter (where t.transaction_type = 'expense_adjust') as adjust_sum
from public.school_expense_records e
left join public.school_account_transactions t
  on t.related_table = 'school_expense_records'
 and t.related_id = e.id
 and coalesce(t.app_type, '') = 'school'
where e.app_type = 'school'
  and e.expense_category <> 'teacher_wage'
group by e.id, e.year_month, e.status, e.expense_category, e.currency, e.amount
having (e.status = 'paid' and not (
         count(t.id) filter (where t.transaction_type = 'expense_adjust') = 1
         and sum(t.amount) filter (where t.transaction_type = 'expense_adjust') = -e.amount
       ))
    or (e.status = 'reversed' and not (
         count(t.id) filter (where t.transaction_type = 'expense_adjust') = 1
         and sum(t.amount) filter (where t.transaction_type = 'expense_adjust') = -e.amount
         and count(t.id) filter (where t.transaction_type = 'expense_reversal') = 1
         and sum(t.amount) filter (where t.transaction_type = 'expense_reversal') = e.amount
       ));
```

## 3. Missing CNY Income Transactions

Definition: `school_income_records.status = 'received'` without a matching `income_adjust` account transaction.

All current missing rows are CNY income records pointing to a JPY account (`吴个人结算账户日元`), so automatic transaction generation is unsafe.

Dry-run counts:

| Month | Income Currency | Recorded Account Currency | Rows | Amount |
|---|---:|---:|---:|---:|
| 2026-02 | CNY | JPY | 1 | 20800 |
| 2026-03 | CNY | JPY | 1 | 26000 |
| 2026-04 | CNY | JPY | 3 | 31395 |
| 2026-05 | CNY | JPY | 3 | 36503 |
| 2026-06 | CNY | JPY | 2 | 14231 |
| Total | CNY | JPY | 10 | 128929 |

Dry-run details:

| Income | Month | Date | Student | Amount | Recorded Account | Account Currency |
|---|---|---|---|---:|---|---:|
| `31406e8a` | 2026-02 | 2026-02-02 | 李天伦 | 20800 CNY | `吴个人结算账户日元` | JPY |
| `da78aee9` | 2026-03 | 2026-03-11 | 李天伦 | 26000 CNY | `吴个人结算账户日元` | JPY |
| `cbce9d33` | 2026-04 | 2026-04-08 | 李天伦 | 21105 CNY | `吴个人结算账户日元` | JPY |
| `4db34a0f` | 2026-04 | 2026-04-01 | 彭宇晗 | 8750 CNY | `吴个人结算账户日元` | JPY |
| `8a660ff4` | 2026-04 | 2026-05-20 | 厦门吕同学 | 1540 CNY | `吴个人结算账户日元` | JPY |
| `dbbd096b` | 2026-05 | 2026-05-15 | 李天伦 | 21450 CNY | `吴个人结算账户日元` | JPY |
| `56ea38e9` | 2026-05 | 2026-05-20 | 彭宇晗 | 8853 CNY | `吴个人结算账户日元` | JPY |
| `da7a2140` | 2026-05 | 2026-05-20 | 厦门吕同学 | 6200 CNY | `吴个人结算账户日元` | JPY |
| `2fd2b2bd` | 2026-06 | 2026-05-29 | 厦门吕同学 | 7740 CNY | `吴个人结算账户日元` | JPY |
| `7483261a` | 2026-06 | 2026-05-29 | 彭宇晗 | 6491 CNY | `吴个人结算账户日元` | JPY |

Recommendation:

- Risk: High.
- Suggested automatic fix: No.
- Manual confirmation: Required.
- Do not create CNY account transactions against a JPY account.
- First decide whether these records were settlement-only, should point to a CNY account, or need a separate FX/cross-currency policy.
- If the business confirms a valid CNY receiving account, use a guarded RPC that requires exact income ids, exact expected amounts, same business ownership, target account currency matching `income.currency`, no existing income transaction, and a nonblank reason.

Draft guarded RPC sketch:

```sql
-- Draft only. Do not execute as-is.
-- public.school_backfill_missing_income_transactions(
--   p_income_ids uuid[],
--   p_target_account_id uuid,
--   p_expected_total numeric,
--   p_reason text
-- )
-- Reject if any income has an existing income_adjust, status <> received,
-- target account currency <> income.currency, business_entity mismatch,
-- locked-settlement policy conflict, or expected total mismatch.
```

## 4. Historical Reversed `teacher_wage` Payment With Expense Still Paid

Definition: `school_payment_requests.status = 'reversed'` for `source_type = 'teacher_wage'`, but the generated `school_expense_records` row is still `status = 'paid'`.

Future behavior has already been fixed by `school_reverse_paid_payment_request_rpc.sql`. This section is historical data only.

Dry-run details:

| Request | Request Month | Payee | Amount | Expense | Expense Month | Expense Status | Account | Reversal Tx |
|---|---|---|---:|---|---|---|---|---|
| `15373c20` | 2026-02 | 赵天歌 | 81250 JPY | `8d05119c` | 2026-02 | paid | `吴个人结算账户日元` | `f2e6c7de` |
| `8af4125f` | 2026-02 | 高若天 | 30000 JPY | `984f4636` | 2026-02 | paid | `吴个人结算账户日元` | `a470c61a` |
| `bb07d665` | 2026-02 | 高若天 | 30000 JPY | `636a43bb` | 2026-02 | paid | `吴个人结算账户日元` | `96f02d20` |
| `6eb0995e` | 2026-03 | 赵天歌 | 120250 JPY | `5602a74f` | 2026-03 | paid | `吴个人结算账户日元` | `ba783f87` |
| `df34abf1` | 2026-03 | 高若天 | 40000 JPY | `a0c7e93b` | 2026-03 | paid | `吴个人结算账户日元` | `d6842992` |

Summary:

| Expense Month | Rows | Amount |
|---|---:|---:|
| 2026-02 | 3 | 141250 JPY |
| 2026-03 | 2 | 160250 JPY |
| Total | 5 | 301500 JPY |

Recommendation:

- Risk: Medium/High.
- Suggested automatic fix: No for historical rows.
- Manual confirmation: Required.
- If business confirms reversed payment should also remove expense from paid operating expense, update only the exact five expense ids to `status = 'reversed'`, `reversed_at`, `reversal_reason`, and `reversal_account_transaction_id = payment_request.reversal_transaction_id`.
- Do not add new cash transactions for these five rows because payment reversal transactions already exist.
- Do not change wage locks/details in this historical repair.

Draft SQL sketch:

```sql
-- Draft only. Do not execute as-is.
-- update public.school_expense_records e
-- set status = 'reversed',
--     reversed_at = p.reversed_at,
--     reversal_reason = 'historical teacher_wage payment reversal sync: <approved reason>',
--     reversal_account_transaction_id = p.reversal_transaction_id,
--     updated_at = now()
-- from public.school_payment_requests p
-- where p.paid_expense_id = e.id
--   and p.source_type = 'teacher_wage'
--   and p.status = 'reversed'
--   and e.status = 'paid'
--   and e.id = any (:approved_expense_ids)
--   and p.reversal_transaction_id is not null;
```

## 5. Account Balance Mismatch

Definition: `school_accounts.current_balance` differs from `opening_balance + sum(all account transactions)`.

Important dry-run result:

- Every mismatched account still matches its latest transaction `balance_after`.
- Therefore the account table is consistent with incremental balance progression.
- The mismatch comes from the full-replay baseline, historical orphan/duplicate/missing transaction set, codex-test residue, or opening-balance policy, so direct overwrite is unsafe.

Dry-run details:

| Account | Business | Currency | Opening | Current | Tx Sum | Opening + Tx | Difference | Latest Balance After | Latest Check | Classification |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| `GMOあおぞらネット銀行` | `青空进学塾` | JPY | 1000000 | 853102 | 701896 | 1701896 | -848794 | 853102 | OK | real |
| `吴垫付金额` | `青空进学塾` | JPY | 0 | 0 | -600193 | -600193 | 600193 | 0 | OK | real |
| `包垫付金额` | `青空进学塾` | JPY | 0 | 0 | -339519 | -339519 | 339519 | 0 | OK | real |
| `吴个人结算账户日元` | `个人名义` | JPY | 0 | 1234 | -119016 | -119016 | 120250 | 1234 | OK | real |
| `codex-test v2.84 commit 公司支付账户` | codex-test | JPY | 0 | 98600 | -1400 | -1400 | 100000 | 98600 | OK | test |
| `codex-test v2.84 commit 垫付支付账户` | codex-test | JPY | 0 | 50000 | 0 | 0 | 50000 | 50000 | OK | test |

Recommendation:

- Risk: High.
- Suggested automatic fix: No.
- Manual confirmation: Required.
- Do not run `update school_accounts set current_balance = opening_balance + tx_sum`.
- First define account baseline policy: opening balance as ledger start, or snapshot-based replay start.
- Real accounts should be handled separately from codex-test accounts.
- If a future balance-rebuild RPC is introduced, it should be snapshot-based and dry-run by account id with expected pre/post balances.

Draft RPC sketch:

```sql
-- Draft only. Do not execute as-is.
-- public.school_recalculate_account_balance_from_snapshot(
--   p_account_id uuid,
--   p_snapshot_id uuid,
--   p_expected_current_balance numeric,
--   p_expected_new_balance numeric,
--   p_reason text
-- )
-- Requires:
--   approved snapshot baseline, exact account id, expected current balance,
--   no unresolved orphan/duplicate/missing transaction candidates unless
--   explicitly marked excluded by policy.
```

## Suggested Phase Order

1. Export full dry-run candidate ids to an operator-reviewed sheet.
2. Confirm policy for historical deleted expenses and missing CNY income account ownership.
3. Decide whether split original expense transactions can be accepted by reversal guards.
4. Decide whether the five historical reversed teacher_wage payment expenses should be marked reversed.
5. Define account balance baseline policy.
6. Only then design and execute guarded repair RPCs with rollback and codex-test validation first.

No historical real-data repair should be bundled with ordinary feature work.
