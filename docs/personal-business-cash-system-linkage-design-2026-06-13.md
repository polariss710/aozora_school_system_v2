# Personal Business / Cash System Linkage Design

Status date: 2026-06-15

Task type: cross-project design plus guarded Phase 1 implementation checkpoints. Initial investigation was read-only; later phases executed guarded Cash-side and school-side schema/RPC work as recorded below. On 2026-06-14 this document was corrected to fix the Cash linkage v1 business policy. Historical Phase 1/2 implementation notes remain for audit, but the business policy below supersedes older personal-only / JPY-only scope statements.

## Investigation Scope

School project: `/Users/polariss710/Documents/aozora_school_system_v2`

Cash System project: `/Users/polariss710/Documents/home_account_book`

School DB read-only verification completed through `load_school_db`.

Cash DB read-only verification completed through `load_cash_db` after switching to the Cash System Supabase Direct connection. The loaded Cash DB URL was verified as different from the school DB URL without printing or storing either URL.

Cash System facts below are based on live DB `information_schema` / `pg_indexes` read-only verification plus repository SQL/API code.

## Cash Linkage v1 Business Policy, Effective 2026-06-14

Core split:

- School system = business ledger.
- Cash System = the user's household/private account ledger and actual
  user-controlled account ledger.
- School records business facts: tuition income, teacher wages,
  student/teacher/month, business ownership, cost attribution,
  corporate-account clearing records, and company expense records.
- Cash records actual account movement: Alipay, JPY cash, Mitsubishi/Rakuten
  and other JPY accounts, RMB accounts, actual money received, actual money
  paid, CNY/JPY allocation, transfers to corporate accounts, and corporate
  reimbursements back to user-controlled accounts.
- Business ownership no longer decides whether a financial event enters Cash.
- If money actually passes through a user-controlled account, it should enter
  Cash System.
- Cash System does not judge business ownership. School remains the source of
  business ownership.

External request policy:

- School initiates external Cash requests from School business flows.
- Cash System stores and displays pending external requests.
- Cash user approve creates the Cash transaction and changes Cash balance.
- Cash user reject creates no transaction and changes no balance.
- Cash System does not proactively create School business records.
- Cash System does not proactively initiate School business requests.
- The Cash zsh/manual sync path is historical verification/operations only;
  the target daily path is external request plus Cash approve/reject.

Deprecated old policies:

- `only personal business enters Cash`
- `青空塾 does not enter Cash`
- `personal + teacher_wage + JPY only`
- `personal tuition JPY only`

These old rules may still appear in current code guards and historical Phase
1/2 implementation notes. Treat them as historical implementation limitations,
not current business policy. The code should be aligned gradually before the
real 2026-05 wage trial resumes.

Tuition income policy:

- All tuition income is recorded in School with business ownership:
  - personal business tuition
  - 青空塾 tuition
  - JPY income
  - CNY / RMB income
  - cash receipts
  - bank receipts
  - Alipay receipts
- The School income record is the business fact. The Cash request is the
  account-movement confirmation.
- Actual received money enters Cash according to the receiving account:
  - Alipay receives RMB -> Cash records Alipay income.
  - JPY cash receives tuition -> Cash records JPY cash income.
  - JPY bank receives tuition -> Cash records the corresponding bank income.
- 青空塾 tuition is not excluded from Cash. When it enters Cash, categorize,
  tag, or note it as `青空塾代收学费`.
- Later transfer of 青空塾 tuition to the corporate account should be recorded
  in Cash as `转给法人账户 / 学费提交 / 代收款清算`.
- That transfer is not ordinary household expense; it is entrusted-funds
  clearing.

Teacher wage payment policy:

- All teacher wage payments go through Cash when paid from a user-controlled
  account:
  - personal-business wages
  - 青空塾-attributed wages
  - mixed-attribution wages
  - JPY cash payments
  - JPY bank transfers
  - RMB / Alipay payments
- School records wage cost attribution:
  - teacher wage settlement
  - payment request
  - personal-business portion
  - 青空塾 portion
  - adjustments / transport fees / classroom fees
- Cash records the actual payment account:
  - Alipay
  - JPY cash
  - Mitsubishi
  - Rakuten
  - other user-controlled accounts
- 青空塾-attributed teacher wages are first advanced through Cash and should be
  identifiable as `青空塾工资垫付`.
- Later corporate reimbursement should be recorded in Cash as
  `法人账户报销 / 青空塾工资垫付报销`.
- Cash approve creates the wage expense transaction. Cash reject creates no
  transaction.

Cash/corporate-account clearing policy:

- Cash -> corporate account movement is internal clearing / balancing, not new
  business revenue.
- For 青空塾 tuition submission or corporate funds aggregation:
  - Cash records `支出 / 转给法人账户 / 学费提交 / 代收款清算`.
  - School records `法人账户入金 / 学费清算 / 资金归集`.
  - Do not record a second tuition income; tuition income was already recorded
    when the student paid.
- For corporate reimbursement of Cash-advanced teacher wages:
  - Cash records `收入 / 法人账户报销 / 青空塾工资垫付报销`.
  - School records `青空塾工资垫付款已报销 / 法人账户清算`.
  - Do not record new tuition income or new profit income. This is advance
    recovery / internal balancing.

Profit policy:

- Count real operating revenue and real operating expenses:
  - tuition income
  - teacher wages
  - real business expenses
- Do not count internal clearing or account allocation:
  - Cash transfer to corporate account
  - corporate reimbursement to Cash
  - CNY/JPY exchange
  - user-account transfer
  - entrusted-funds clearing
  - wage-advance recovery

CNY / JPY allocation policy:

- School does not automatically handle CNY/JPY exchange, account transfers, or
  allocation between Alipay and JPY cash/bank accounts for now.
- School records the business income and wage-settlement view only.
- Cash manually records exchange and account transfers.
- This is usually a monthly operation and does not need automation now.

Cash account eligibility policy:

- Cash System owns the School-usable Cash account whitelist through
  `home_accounts.allow_school_requests`.
- School must not maintain Cash account balances. School should only read the
  active Cash accounts where `allow_school_requests = true` when offering Cash
  收款账户 / 支付账户 choices for future income and teacher-wage request flows.
- Current eligible Cash accounts:
  - `余额宝` (`CNY`, wallet)
  - `日元现金` (`JPY`, cash)
  - `日元三菱卡` (`JPY`, bank)
  - `日元乐天卡` (`JPY`, cash)
- Current excluded Cash accounts:
  - `余利宝` (`CNY`, wallet)
  - `医生处兑换日元先行支付` (`JPY`, cash)
- Future “all income / all teacher wage” Cash request implementation should
  use this whitelist before submitting any external Cash request.

Current implementation note:

- Teacher-wage Cash confirmation has been aligned to this policy for all
  pending `teacher_wage` payment requests with eligible JPY/CNY Cash accounts,
  including personal business, 青空塾, and mixed-attribution wage requests.
- Income Cash confirmation SQL/RPC has been installed. The
  `request-cash-income-confirmation` and `sync-cash-request-result` Edge
  Functions have been deployed.
- Frontend account routing is implemented. Normal income still uses the School
  account path; Cash System income saves through
  `request-cash-income-confirmation` and stops at Cash pending until Cash
  approve.
- Real whitelist CNY income tests passed for 李天伦 `21,450 CNY`, 彭宇晗
  `6,491 CNY`, and 厦门吕同学 `7,740 CNY`.
- Real 2026-05 teacher-wage first small-batch JPY trial passed for 吴峰
  `36,000 JPY` through `日元乐天卡`.
- Cash request display text is localized for future requests: income
  `description` includes student/payee plus content, teacher-wage
  `description` includes teacher plus wage month, and teacher-wage `note`
  includes student details when available.

## Income Request And Cash Receipt Confirmation

Income request and Cash receipt confirmation request are separate business
objects.

Income request:

- Business-side confirmation that income should be received.
- May originate from tuition, personal business income, personal external
  teaching income, or other income.
- Does not mean money has arrived in a real account.
- Does not directly change Cash balance.
- Belongs to School business state and settlement state.

Cash receipt confirmation request:

- Submits an income request to Cash System for approve/reject.
- Waits as a Cash external pending request.
- Cash approve creates the real Cash transaction.
- Cash approve increases the selected Cash account balance.
- Cash reject creates no transaction and changes no balance.
- Cash reject leaves the School income request pending and retryable.

Therefore the required flow is:

```text
monthly settlement / income record
-> income request
-> Cash receipt confirmation request
-> Cash approve
-> Cash transaction
-> School income received / settled
```

Do not treat income request creation as proof of receipt. Do not mark School
income received or settled until Cash approve confirms the real account
movement.

## Income Cash Confirmation Current Implementation

Commit `2fe6ae8` added the file-level implementation for generic income Cash
confirmation. The SQL/RPC workflow has since been installed and the Edge
Functions have been deployed.

- `school_income_cash_confirmation_workflow.sql`
- `supabase/functions/request-cash-income-confirmation/index.ts`
- `supabase/functions/sync-cash-request-result/index.ts` income dispatch
- `js/api/income-api.js` Cash System save path
- `js/pages/income-page.js` pending confirmation messaging

Prepared School RPCs:

- `school_create_cash_income_confirmation`
- `school_request_cash_income_confirmation`
- `school_mark_cash_income_request_submitted`
- `school_mark_cash_income_confirmed`
- `school_mark_cash_income_rejected`

Cash-side reuse:

- `home_create_external_transaction_request` creates the pending Cash request.
- `home_approve_external_transaction_request` creates the JPY/CNY Cash
  transaction after approve.

Installed / deployed state:

- `school_income_cash_confirmation_workflow.sql` has been executed against the
  School DB.
- `request-cash-income-confirmation` has been deployed.
- `sync-cash-request-result` has been deployed with income approve/reject
  dispatch.
- The frontend account selector has been split between School account and Cash
  System account.
- The Cash System income path calls `request-cash-income-confirmation`.
- Cash System income creates School pending income first, then a Cash pending
  external request.
- Cash approve creates `home_jpy_transactions` / `home_cny_transactions`,
  changes Cash balance, and calls back to mark School received / synced.
- Cash reject creates no transaction, changes no balance, and leaves School
  income pending / retryable.

Verified real CNY cases:

- 李天伦 / `21,450 CNY` / `余额宝` / `6月课时费`: Cash pending request was
  created, user approved in Cash UI, `home_cny_transactions` was generated,
  Cash balance increased by `21,450`, School income became `received` /
  `Cash已确认`, and active attempt count returned to 0.
- 彭宇晗 / `6,491 CNY` / `余额宝` / `6月课时费`: recreated after historical
  reversed income cleanup, approved, wrote `home_cny_transactions`, and
  reconciled with School.
- 厦门吕同学 / `7,740 CNY` / `余额宝` / `6月课时费`: recreated after historical
  reversed income cleanup, approved, wrote `home_cny_transactions`, and
  reconciled with School.

Related cleanup and UI state:

- codex test accounts / business entities / students / ledgers were cleaned.
- `吴个人结算账户人民币` and its historical/test account transactions were
  deleted; account orphan reference checks passed.
- `吴个人结算账户日元` remains because it has formal historical received income,
  teacher-wage expenses, reversed expenses, payment requests, reimbursements,
  and account transactions. It requires a separate migration/archive plan.
- Account management filters no longer include transaction type.
- Income and expense filters now keep only month, student, business entity,
  account, and currency.

## Personal External Teaching Income Module

Personal external teaching income is documented separately in
`docs/personal-teaching-income-module-design.md`.

Positioning:

- The user teaches or works at an external cram school.
- The external cram school is the payer.
- The income belongs to personal business.
- The module does not enter Aozora teacher wage settlement.
- The module does not create `teacher_wage` payment requests.
- The module should use income / receipt requests and Cash receipt
  confirmation.

Lesson model:

- Use planned + actual.
- Planned rows can be freely added, edited, and deleted.
- The only action is generating actual from planned.
- No cancel, makeup, makeup completed, or `is_billable` state is needed.
- If the lesson did not happen, delete the planned row.
- If planned has generated actual, deletion requires a second confirmation as
  business protection, not as makeup logic.

Settlement and Cash flow:

```text
daily planned entry
-> generate actual after teaching
-> month-end actual review
-> lock monthly settlement
-> create personal_teaching_income_request
-> submit Cash receipt confirmation
-> Cash approve
-> Cash transaction
-> income request / settlement received and settled
```

This income path can reuse attempt numbers, active-attempt uniqueness,
rejected retry, idempotency keys, Cash external requests, approve/reject
callbacks, and JPY/CNY transaction dispatch. It must not reuse payment naming,
expense direction, `paid` semantics, teacher wage settlement tables, or
teacher-wage-specific fields.

## Confirmed School Facts

Business ownership is stored in `school_business_entities`:

- `青空进学塾`: `code = aosora`, `entity_type = company`, active.
- `个人名义`: `code = personal`, `entity_type = personal`, active.
- A remaining `codex-test` business entity also exists and is test/sandbox data.

Main financial chains carry `business_entity_id`:

- `school_income_records`
- `school_teacher_wage_locks`
- `school_teacher_wage_lock_details`
- `school_teacher_wage_rules`
- `school_payment_requests`
- `school_expense_records`
- `school_accounts`
- `school_account_transactions`

Teacher wage flow:

- Actual lessons enter generated wage snapshots grouped by `teacher_id + business_entity_id + settlement_month`.
- `school_create_teacher_wage_payment_request` creates one pending `school_payment_requests` row from a locked wage snapshot.
- `school_confirm_payment_request` currently supports only `source_type = teacher_wage`.
- Current confirmation requires a school account with matching `business_entity_id`, matching currency, active state, and `app_type = school`.
- Confirmation creates one `teacher_wage` expense, one school account transaction, updates the selected school account balance, and links generated ids back to the payment request.
- Reversal uses `school_reverse_paid_payment_request`, appends a `payment_reversal` school account transaction, marks the request `reversed`, and marks the generated teacher-wage expense `reversed`.

Income flow:

- `school_create_income_record` creates a received income record, updates a school account balance, and inserts one school account transaction.
- Tuition income is the category that participates in student settlement guards.
- Income update/reversal are dedicated RPC paths.

Part-time / temporary wage:

- `docs/part-time-wage-record-module-design-2026-06-12.md` defines the design entry.
- Live school DB verification found no `school_part_time_wage_records` table yet.
- The design recommends future `source_type = part_time_wage` payment requests, separate from lesson-based teacher wage snapshots.

## Confirmed Cash System Facts

Live DB verification confirmed these public tables exist:

- `home_accounts`
- `home_payment_channels`
- `home_jpy_transactions`
- `home_cny_transactions`
- `home_fixed_templates`
- `home_fixed_month_items`

Cash System account master data is `home_accounts`:

- `currency`: `JPY` or `CNY`
- `name`: user-facing account name, such as 日元现金, 日元三菱卡, 支付宝/余额宝 style names
- `account_type`: `cash`, `bank`, `wallet`, `pass_through`, `investment`
- `opening_balance`
- `is_active`
- `sort_order`
- `user_id`

`home_payment_channels` is not the balance ledger target. It is used for fixed income/expense payment-channel grouping, with fields like `name`, `currency`, `default_due_day`, and `sort_order`.

Cash movement targets:

- JPY: `home_jpy_transactions`
- CNY: `home_cny_transactions`

Both transaction tables use positive `amount` only and classify direction through `transaction_type`:

- income-like: `income`, `fx_in`, and JPY-only `fixed_in`
- expense-like: `expense`, `fx_out`, and JPY-only `fixed_out`
- transfer: `transfer`, with `transfer_account_id`

Balance calculation:

- Cash System does not store `current_balance` on `home_accounts`.
- `home_get_jpy_account_page` / `home_get_cny_account_page` calculate current balance as opening balance plus all transactions before the next month.
- For transfers, the source account gets `-amount`; the transfer target gets `+amount`.

Existing linkage fields:

- `home_fixed_month_items.linked_jpy_transaction_id`
- `home_fixed_month_items.linked_cny_transaction_id`
- `home_jpy_transactions.linked_fixed_month_item_id`
- `home_cny_transactions.linked_fixed_month_item_id`
- `home_jpy_transactions.linked_cny_transaction_id`
- `home_cny_transactions.linked_jpy_transaction_id`

Live DB verification confirmed the JPY transaction fields needed for Phase 1 exist:

- `id`
- `user_id`
- `currency`
- `transaction_type`
- `account_id`
- `transfer_account_id`
- `transacted_at`
- `amount`
- `description`
- `note`
- `created_at`

Live DB verification also confirmed there is no generic `external_source`, `idempotency`, `external_reference`, `related`, or `school` field in `home_jpy_transactions` / `home_cny_transactions`. The only external-like fields are the existing fixed-month and FX linkage columns listed above.

## Linkage Boundary

Current business boundary:

- Link Cash when money actually moves through a user-controlled account.
- Do not link Cash merely because a School business event exists.
- School business ownership is retained in School and does not decide Cash
  eligibility.
- Cash eligibility is based on the actual receiving or paying account:
  Alipay, JPY cash, Mitsubishi, Rakuten, or any other user-controlled account.

Historical implementation boundary, deprecated as business policy:

- Phase 1 completed personal-business lesson-based teacher wage JPY payment
  linkage.
- Phase 2 completed personal-business tuition JPY income linkage.
- These phases used personal-only / JPY-only / selected-event guards to keep
  early implementation safe.
- Those guards remain useful as implementation history and risk controls, but
  they no longer define the v1 business policy.

Correct v1 target:

- 青空塾 tuition received in a user-controlled account enters Cash as
  `青空塾代收学费`.
- 青空塾 teacher wage paid from a user-controlled account enters Cash as
  `青空塾工资垫付`.
- CNY / RMB receipts and payments enter Cash when they happen in a
  user-controlled CNY/RMB account such as Alipay.
- Later corporate clearing/reimbursement is recorded in Cash as clearing or
  reimbursement, not household expense.

Still out of automatic School handling for now:

- CNY/JPY exchange automation.
- Automatic account allocation between Alipay and JPY cash/bank accounts.
- Broad historical backfill or real-data repair.
- Cross-DB strong transactions.
- Sandbox/test data unless explicitly marked for an integration test phase.

## Recommended Mapping

School should have a Cash account mapping table or equivalent server-side
config. The current implemented table name
`school_personal_cash_account_mappings` reflects the earlier personal-only
phase. For the corrected v1 policy, the concept should become a general
School-to-Cash mapping / allowlist that can support personal business, 青空塾,
JPY, and CNY/RMB flows when implementation catches up.

Recommended school-side table design:

- `id`
- `business_entity_id`: School business ownership for attribution; not a Cash
  eligibility gate by itself
- `flow_type`: `tuition_income`, `teacher_wage_payment`,
  `aosora_tuition_collected`, `aosora_wage_advance`,
  `aosora_tuition_clearing`, `aosora_wage_reimbursement`, future
  `part_time_wage_payment`
- `school_currency`
- `cash_currency`
- `cash_account_id`: UUID from Cash System `home_accounts`
- `cash_account_name_snapshot`
- `cash_account_type_snapshot`
- `is_active`
- `created_at`, `updated_at`

Rules:

- No foreign key to Cash DB; this is cross-project.
- Cash account ids must never be treated as school account ids.
- Mapping must be maintained through backend/API code, not hardcoded in page modules.
- If live Cash account lookup is available, use the mapping only as an allowlist and keep name/type snapshots for audit display.
- Current code may still restrict mappings to personal + JPY. That is a
  historical implementation guard and should be broadened in later phases.

## Cash Transaction Creation

Cash System should receive one idempotent write request per school financial event.

Recommended target rows:

- Tuition income:
  - `home_jpy_transactions` or `home_cny_transactions`, depending on the
    actual receiving account
  - `transaction_type = income`
  - `account_id = selected/mapped Cash account`
  - `transacted_at = school income date`
  - `amount = school received amount`
  - `description = 学费收入 / student or settlement snapshot`
  - For 青空塾 tuition collected through a user-controlled account, add
    category/tag/note such as `青空塾代收学费`.

- Teacher wage payment:
  - `home_jpy_transactions` or `home_cny_transactions`, depending on the
    actual payment account
  - `transaction_type = expense`
  - `account_id = selected Cash account`
  - `transacted_at = pay date`
  - `amount = payment request amount`
  - `description = 老师工资 / teacher / request month`
  - For 青空塾-attributed wages paid from a user-controlled account, add
    category/tag/note such as `青空塾工资垫付`.

- 青空塾 tuition clearing to corporate account:
  - Cash records the actual transfer/expense-like movement from the
    user-controlled account
  - label as `转给法人账户 / 学费提交 / 代收款清算`
  - do not classify as ordinary household expense

- 青空塾 wage reimbursement from corporate account:
  - Cash records the actual reimbursement into the user-controlled account
  - label as `法人账户报销 / 青空塾工资垫付报销`

- Future part-time wage payment:
  - Same pattern as teacher wage payment after `part_time_wage` has a verified payment source and confirmation flow.

Do not write `home_payment_channels` for this linkage.

## Account Selection UX

For supported flows where money passes through a user-controlled account:

- The confirmation dialog should show a Cash System account selector, filtered by currency and active mapping.
- Options should display Cash account name, currency, account type, and current Cash balance if the integration API can read it.
- The page module must call a school API wrapper; it must not call Cash DB directly or embed Cash DB credentials.
- If no active mapping exists, the confirmation action should be blocked with a clear setup-required message.

For 青空进学塾 / company-owned business events:

- Do not exclude them from Cash solely because of business ownership.
- If the money is received into or paid from a user-controlled account, show or
  derive the appropriate Cash account selection.
- Preserve School-side business ownership as 青空塾/company.
- Use Cash labels/notes that distinguish entrusted tuition, wage advances,
  clearing, and reimbursement from ordinary household income/expense.
- If the money moves only inside corporate accounts outside user control, that
  corporate movement is outside Cash System unless a later company-account
  integration is explicitly designed.

## Correlation And Idempotency

Both sides need explicit correlation metadata before implementation.

Recommended Cash-side addition:

- Add generic external-source columns to `home_jpy_transactions` and `home_cny_transactions`, or add a `home_external_transaction_links` table.
- Required metadata:
  - `external_source_app = aozora_school`
  - `external_source_table`
  - `external_source_id`
  - `external_event_type`: `confirm`, `reverse`, future `reissue`
  - `external_idempotency_key`
  - optional `external_payload_hash`

Recommended uniqueness:

- Unique key on `external_source_app + external_source_table + external_source_id + external_event_type`.
- A reversal should be a separate event from the original confirmation.

Recommended school-side addition:

- `school_cash_linkage_events`
  - `source_table`
  - `source_id`
  - `source_event_type`
  - `business_entity_id`
  - `cash_account_id`
  - `currency`
  - `amount`
  - `idempotency_key`
  - `cash_transaction_table`
  - `cash_transaction_id`
  - `status`: `pending`, `synced`, `failed`, `reversed`
  - `attempt_count`
  - `last_error`
  - `created_at`, `updated_at`, `synced_at`

This prevents duplicate Cash writes and gives school a retry/audit surface without requiring cross-DB foreign keys.

## Failure, Retry, And Reversal

Do not attempt cross-DB strong transactions.

Recommended flow:

1. School confirmation/reversal RPC completes the school-side state change and records a linkage event in the same school DB transaction.
2. A backend integration worker or server action writes the Cash transaction using the idempotency key.
3. On success, school stores the Cash transaction id and marks the event `synced`.
4. On failure, school keeps the event `failed` or `pending_retry` and exposes retry from an admin surface.

Retry rules:

- Retrying must reuse the same idempotency key.
- If Cash already has the transaction for the idempotency key, treat it as success and backfill the Cash transaction id into the linkage event.
- Do not create a second Cash transaction for the same school event.

Reversal rules:

- Preserve the original Cash transaction.
- Create an opposite-direction Cash transaction with a new reversal idempotency key.
- Teacher wage payment reversal: original Cash `expense`; reversal Cash `income`.
- Tuition income reversal: original Cash `income`; reversal Cash `expense`.
- Link the reversal event to the original linkage event on school side.

Manual repair:

- Avoid deleting Cash transactions for synced school events.
- If a Cash transaction was manually edited/deleted, integration should stop and surface a reconciliation error instead of silently recreating broad history.

## First-Stage Minimum Implementation

Recommended MVP:

1. Personal-business teacher wage payment only.
2. JPY only, because current school teacher wage payment request generation uses `currency = JPY`.
3. One selected Cash account per confirmation, filtered from active mapped `home_accounts`.
4. School-side linkage event table and Cash-side external idempotency metadata.
5. Append-only Cash transaction creation for confirm and reverse.
6. Admin retry for failed Cash writes.
7. No change to 青空进学塾 flows.

After MVP:

- Add personal-business tuition income linkage.
- Add CNY support after currency and Cash account selection rules are confirmed.
- Add part-time wage linkage only after the part-time wage module and `part_time_wage` payment source are implemented.

## Phase 1 Implementation Status

Status: Phase 1 end-to-end manual sync completed and test residue cleaned on 2026-06-13. Cash System side schema/RPC, school-side mapping/outbox schema/RPC/API, payment confirmation to school pending outbox, and manual pending-outbox-to-Cash sync are implemented. Reversal sync, automatic background retry, CNY, tuition income, and part-time wage are not implemented.

Cash completed:

- Cash repository: `/Users/polariss710/Documents/home_account_book`
- SQL archive: `supabase-update-20260613-external-jpy-1.sql`
- Added external/idempotency metadata columns to `home_jpy_transactions`.
- Added partial unique indexes for external idempotency and external source event uniqueness.
- Added `home_jpy_transactions_external_required_check`.
- Added RPC `home_create_external_jpy_transaction(...)`.
- Rollback idempotency test verified: first call inserted a temporary external JPY expense, second call with the same idempotency key returned the same transaction id with `inserted=false`, count stayed 1 inside the transaction, and rollback residue was 0.
- End-to-end whitelist test data was later cleaned: target Cash transaction/account counts are 0.

Not completed:

- reversal sync
- automatic background retry worker
- retry UI / operator workflow
- CNY, tuition income, part-time wage linkage
- Phase 2 personal-business tuition income design

Target flow:

- `个人名义` / `entity_type = personal`
- `school_payment_requests.source_type = teacher_wage`
- `currency = JPY`
- payment confirmation selects a Cash System JPY account
- Cash System receives one JPY `expense` transaction for the paid wage

### Cash System Minimum Schema / RPC

Add external reference metadata to `home_jpy_transactions` only for Phase 1:

- `external_source_app text`
- `external_source_table text`
- `external_source_id uuid`
- `external_event_type text`
- `external_idempotency_key text`
- `external_reference text`
- optional `external_payload_hash text`
- optional `external_created_at timestamptz default now()`

Recommended constraints / indexes:

- Partial unique index on `external_idempotency_key` where not null.
- Partial unique index on `external_source_app, external_source_table, external_source_id, external_event_type` where all are not null.
- Check constraint for Cash-owned external rows:
  - `external_source_app = 'aozora_school'`
  - `external_source_table = 'school_payment_requests'`
  - `external_event_type in ('teacher_wage_payment_confirm', 'teacher_wage_payment_reverse')`

Recommended RPC:

- `home_create_external_jpy_transaction(...)`
- Security definer or server-only execution should be decided before SQL implementation. The RPC must not be callable by ordinary browser UI unless RLS/auth ownership is fully designed.
- Inputs:
  - target `home_accounts.id`
  - transaction date
  - transaction type: Phase 1 should allow only `expense`; if reversal is included in the same RPC, also allow `income`
  - positive amount
  - description and note
  - external source metadata
  - idempotency key
- Guards:
  - account exists, is active, belongs to the intended Cash user, and `currency = JPY`
  - amount > 0
  - `transfer_account_id` must be null
  - duplicate idempotency key returns the existing transaction id instead of inserting a second row
  - source triple duplicate returns the existing transaction id only if amount/account/date/type match; otherwise returns a conflict error

Reversal / reverse posting:

- Do not delete the original Cash transaction.
- Preferred Phase 1 support: create an opposite JPY `income` transaction with `external_event_type = teacher_wage_payment_reverse` and a new idempotency key.
- If the frontend integration does not wire reversal in the first UI pass, school should block reversing a synced personal-business Cash-linked payment until the reverse posting path is available. Silent divergence is worse than a blocked reversal.

### School Minimum Schema / RPC

Implemented on 2026-06-13 in the school project:

- SQL archive: `school_personal_cash_linkage_schema.sql`
- SQL archive: `school_personal_cash_linkage_rpcs.sql`
- API wrapper: `js/api/personal-cash-linkage-api.js`
- Added `school_personal_cash_account_mappings`.
- Added `school_personal_cash_linkage_events`.
- Added RPCs:
  - `school_create_personal_cash_account_mapping`
  - `school_update_personal_cash_account_mapping`
  - `school_list_personal_cash_account_mappings`
  - `school_create_personal_cash_linkage_event`
  - `school_get_personal_cash_linkage_events`
  - `school_update_personal_cash_linkage_event_status`
- Rollback tests verified:
  - personal-business mapping/event happy path
  - company / 青空塾-style business entity guard rejection
  - duplicate source event returns the existing event instead of creating a second event
  - sync status update can record failed error state and later synced Cash transaction id
  - rollback residue was 0
- Whitelist commit test initially left clearly marked school test data:
  - business entity: `92000000-0000-4000-8000-000000132001`
  - payment request: `92000000-0000-4000-8000-000000132101`
  - mapping: `f5c02610-1b11-4353-b5de-ae5b3b60f980`
  - linkage event: `9b95e09a-09c4-4203-bc02-07daaf1beb5b`
  - event status: `pending`
- This Phase 1 test data was later cleaned; target school mapping/outbox/payment/business entity counts are 0.
- No Cash DB writes were performed in the school-side phase.
- No existing payment confirmation, teacher wage generation, reimbursement, income, student settlement, or page module was changed.

Payment confirmation outbox integration implemented on 2026-06-13:

- SQL archive: `school_confirm_personal_cash_payment_request_rpc.sql`
- Frontend/API files:
  - `js/api/payment-api.js`
  - `js/api/payment-detail-api.js`
  - `js/pages/payment-page.js`
  - `js/pages/payment-detail-page.js`
  - `index.html`
  - `payment-detail.html`
- Added RPC `school_confirm_personal_cash_payment_request`.
- Personal-business `teacher_wage` JPY pending payment confirmation now:
  - requires an active `school_personal_cash_account_mappings` row for the payment business entity
  - marks the school payment request `paid`
  - creates one pending `school_personal_cash_linkage_events` outbox row in the same school DB transaction
  - leaves `paid_expense_id`, `paid_account_transaction_id`, and `account_id` null because no school account ledger is written for the personal Cash path
  - does not write Cash DB
- Company / 青空塾 payment confirmation remains on the existing `school_confirm_payment_request` path with school account selector, expense, account transaction, and school account balance update.
- Payment detail now shows Cash linkage status for existing outbox events.
- Paid payment requests with a Cash outbox event do not expose the reversal action in the payment list because reversal sync is out of this phase.
- Rollback test verified:
  - personal-business confirm creates exactly one pending outbox event
  - company / 青空塾-style payment cannot use the personal Cash confirm RPC
  - repeated confirm is blocked after payment status changes from `pending`
  - rollback residue was 0
- Whitelist commit test initially left clearly marked school test data:
  - business entity: `93000000-0000-4000-8000-000000141001`
  - payment request: `93000000-0000-4000-8000-000000141101`
  - mapping: `eaf3b59d-f944-441f-911f-b639ba284c78`
  - linkage event: `11f8f9ee-cbf4-4a29-8d6a-dc56a7d2e7e4`
  - event status: `pending`
- This Phase 1 test data was later cleaned; target school mapping/outbox/payment/business entity counts are 0.

End-to-end manual sync implemented on 2026-06-13:

- School script: `scripts/sync-personal-cash-linkage.zsh`
- The script:
  - loads school DB with `load_school_db` only for school reads/status writes
  - loads Cash DB with `load_cash_db` only for Cash RPC calls
  - does not print or store DB URLs
  - reads only pending school events that match all Phase 1 guards:
    - `school_personal_cash_linkage_events.sync_status = pending`
    - `source_table = school_payment_requests`
    - `source_event_type = teacher_wage_payment_confirm`
    - event currency `JPY`
    - linked payment request `status = paid`
    - linked payment request `source_type = teacher_wage`
    - linked payment request currency `JPY`
    - linked business entity `entity_type = personal`
    - not reversed
  - calls Cash RPC `home_create_external_jpy_transaction(...)`
  - marks school event `synced` with `cash_transaction_id` on success
  - marks school event `failed` with `last_error` on Cash RPC failure
  - ignores synced/failed/blocked rows on later runs
- Successful E2E whitelist test:
  - Cash test account: `94000000-0000-4000-8000-000000150501`
  - school business entity: `94000000-0000-4000-8000-000000150001`
  - school payment request: `94000000-0000-4000-8000-000000150101`
  - school linkage event: `2f20e264-1e20-493d-b92a-58c244abfa09`
  - Cash JPY transaction: `fbd3e5df-14be-4b3b-9a0b-319f4416968b`
  - school event final status: `synced`
- Duplicate run validation:
  - re-running the script for the synced event found no pending candidate
  - Cash transaction count for the school payment reference stayed 1
- Failure path validation:
  - previous codex-test fake Cash mapping event `11f8f9ee-cbf4-4a29-8d6a-dc56a7d2e7e4` moved to `failed`
  - `last_error` stores `Cash RPC returned ok=false: JPY account not found or inactive`
- Old fake pending test event `9b95e09a-09c4-4203-bc02-07daaf1beb5b` was marked `blocked` so default sync runs do not process stale fake test data.
- Rollback exclusion test verified company / 青空塾-style and non-`teacher_wage` pending events are not selected by the sync candidate query.
- Duplicate run validation verified the same school event does not create duplicate Cash transactions.
- Phase 1 cleanup later removed:
  - Cash account: `94000000-0000-4000-8000-000000150501`
  - Cash JPY transaction: `fbd3e5df-14be-4b3b-9a0b-319f4416968b`
  - school business entities: `92000000-0000-4000-8000-000000132001`, `93000000-0000-4000-8000-000000141001`, `94000000-0000-4000-8000-000000150001`
  - school payment requests: `92000000-0000-4000-8000-000000132101`, `93000000-0000-4000-8000-000000141101`, `94000000-0000-4000-8000-000000150101`
  - school mappings: `f5c02610-1b11-4353-b5de-ae5b3b60f980`, `eaf3b59d-f944-441f-911f-b639ba284c78`, `44d55329-4850-4116-8f9a-0c3ba2d211a1`
  - school events: `9b95e09a-09c4-4203-bc02-07daaf1beb5b`, `11f8f9ee-cbf4-4a29-8d6a-dc56a7d2e7e4`, `2f20e264-1e20-493d-b92a-58c244abfa09`
- Cleanup verification confirmed all target counts are 0 and older income-edit `codex-test` data was not deleted.

Add a personal Cash account mapping table:

- suggested name: `school_personal_cash_account_mappings`
- fields:
  - `id`
  - `business_entity_id`
  - `flow_type`: Phase 1 value `teacher_wage_payment`
  - `school_currency`: Phase 1 value `JPY`
  - `cash_currency`: Phase 1 value `JPY`
  - `cash_user_id`
  - `cash_account_id`
  - `cash_account_name_snapshot`
  - `cash_account_type_snapshot`
  - `is_active`
  - `note`
  - audit timestamps
- Guards:
  - referenced school business entity must be active and `entity_type = personal`
  - no mapping for `company` / 青空塾 business entities
  - no FK to Cash DB
  - uniqueness on active `business_entity_id + flow_type + school_currency + cash_account_id`

Add a school outbox / linkage event table:

- suggested name: `school_personal_cash_linkage_events`
- fields:
  - `id`
  - `source_table`: Phase 1 `school_payment_requests`
  - `source_id`
  - `source_event_type`: `teacher_wage_payment_confirm`, later `teacher_wage_payment_reverse`
  - `business_entity_id`
  - `payment_request_id`
  - `school_account_id` nullable, if the legacy school account flow is still used for school-side audit
  - `cash_user_id`
  - `cash_account_id`
  - `cash_account_name_snapshot`
  - `cash_transaction_table`: Phase 1 `home_jpy_transactions`
  - `cash_transaction_id`
  - `currency`: Phase 1 `JPY`
  - `amount`
  - `idempotency_key`
  - `sync_status`: `pending`, `synced`, `failed`, `blocked`
  - `attempt_count`
  - `last_error`
  - timestamps: `created_at`, `updated_at`, `synced_at`
- Constraints:
  - unique `idempotency_key`
  - unique source event: `source_table + source_id + source_event_type`
  - positive amount
  - Phase 1 check for `currency = 'JPY'`

Payment confirmation behavior:

- For `entity_type = company` / 青空塾: keep the current school account selector and current `school_confirm_payment_request` behavior.
- For `entity_type = personal` / personal business teacher wage JPY payment:
  - show a Cash account selector populated from active mappings
  - selected account is a Cash account, not a school account
  - page calls the school API layer, never Cash DB directly
  - school RPC records the paid school payment state and inserts a pending linkage event in the same school DB transaction
  - server/integration step calls Cash `home_create_external_jpy_transaction`
  - after Cash succeeds, update the school linkage event with `cash_transaction_id` and `sync_status = synced`

Cross-DB transaction rule:

- Do not attempt cross-DB strong transactions.
- If school confirmation succeeds and Cash write fails, keep the school event as `failed` or `pending` with `last_error`; expose manual retry later.
- Automatic background retry is explicitly out of Phase 1.
- The manual script intentionally performs Cash write and school status update as separate steps. If Cash succeeds but school status update fails, the event can be rerun while still pending; Cash RPC idempotency should return the existing transaction instead of inserting a duplicate.

### Phase 1 Implementation Order

1. Cash System schema/RPC draft:
   - add external metadata columns / indexes to `home_jpy_transactions`
   - add `home_create_external_jpy_transaction`
   - rollback test duplicate/idempotency behavior
   - whitelist commit test with clearly marked Cash test data only
2. School schema/RPC draft:
   - add mapping table
   - add linkage event / outbox table
   - add read APIs/RPCs for active personal Cash mappings
   - add school-side linkage event creation/update helpers
   - status: completed on 2026-06-13
3. Payment confirmation integration:
   - API wrapper chooses legacy school account path for company business entities
   - API wrapper chooses personal Cash mapping path for personal JPY teacher wage requests
   - payment page shows Cash account selector only for eligible personal JPY teacher wage requests
   - status: completed on 2026-06-13 for school outbox creation; Cash DB write is performed later by the manual sync executor
4. End-to-end verification:
   - rollback test for school confirm + event creation
   - rollback test for Cash external insert + duplicate idempotency
   - whitelist commit test with explicitly marked personal business test data
   - verify no 青空塾 / company records enter the Cash path
   - verify duplicate confirm/retry does not duplicate Cash transactions
   - status: completed on 2026-06-13 for manual sync executor; no automatic background retry or reversal sync

### Explicitly Out Of Historical Phase 1

The following list describes the deliberately narrow 2026-06-13 Phase 1
implementation boundary. It is not the current Cash linkage v1 business
policy.

- 青空塾 linkage in that historical implementation phase
- reimbursement linkage
- legal/company account linkage
- cross-DB strong transactions
- automatic retry background jobs
- Cash System full ledger refactor
- CNY linkage in that historical implementation phase
- tuition income linkage in that historical implementation phase
- part-time wage linkage
- historical backfill or real-data repair

## Phase 2 Design: Personal Tuition Income

Status: Phase 2 v1 completed and verified on 2026-06-13 for personal-business
`tuition` JPY income -> Cash System JPY `income` transaction linkage.

Completion scope:

- personal business `tuition` income only
- JPY only
- school income -> income linkage event -> manual sync executor -> Cash JPY
  income transaction -> school `synced` writeback
- read-only Cash sync status display in income list/detail
- manual failed retry from income detail; retry resets eligible failed events
  back to `pending` and waits for the manual sync executor
- no school account ledger write for the personal Cash path
- no `school_accounts.current_balance` update for the personal Cash path

Verified:

- ROLLBACK whitelist create test passed.
- Reject cases passed for 青空塾/company business, CNY, non-`tuition`,
  amount `<= 0`, wrong mapping flow, and student/business mismatch.
- Ordinary income edit/reverse guard passed for linked tuition income.
- COMMIT whitelist E2E passed: one Cash JPY `income` transaction was created.
- Re-running sync was idempotent; Cash transaction count stayed 1.
- School event was updated to `synced` with `cash_transaction_id` and
  `synced_at`.
- Income detail displays Cash sync status, Cash transaction id, Cash account
  snapshot, `synced_at`, `last_error`, `retry_count`, and idempotency key.
- Income detail exposes `重新同步` only for failed linkage events. The action
  uses a dedicated school retry RPC, does not run the sync executor directly,
  and does not create Cash transactions.
- Income list displays a compact Cash sync badge for linked tuition income.
- Phase 2 E2E `codex-test-personal-cash-tuition-e2e-20260613` residue was
  cleaned: Cash target account/transaction = 0, School target
  business/student/mapping/income/event = 0, and `home_cny_transactions`
  marker = 0.

Still unsupported:

- linked edit / reverse for synced tuition income
- CNY
- 青空塾 / company income
- non-`tuition` income
- automatic scheduled sync; Phase 2 v1 still uses the manual sync script and
  documented operator runbook

### Cash Linkage v2 Direction: Page-Driven Cash Confirmation

The current zsh sync executor is a verification and operations tool. It is not
the final daily business entry point.

Current verified teacher-wage payment chain:

1. Pending teacher wage payment request exists in School.
2. School user clicks `确认支付`.
3. `school_payment_requests.status` becomes `paid`.
4. School creates `school_personal_cash_linkage_events.sync_status = pending`.
5. `scripts/sync-personal-cash-linkage.zsh` directly calls Cash
   `home_create_external_jpy_transaction(...)`.
6. Cash creates a JPY transaction and the Cash balance changes.
7. School event is updated to `synced`.

Target Cash linkage v2 chain:

The corrected product direction does not add an independent School sync page.
Cash linkage is embedded into the two real School business pages:

1. Income record page:
   - user records personal-business `tuition` JPY income
   - user selects a Cash 收款账户, such as Alipay or a JPY account
   - submitting the income record creates the school income record and submits
     the Cash confirmation request
   - Cash approval later creates the Cash JPY income transaction and School
     displays `Cash已确认`
   - Cash rejection creates no Cash transaction and School displays `Cash已拒绝`
2. Teacher wage payment page:
   - user confirms a personal-business `teacher_wage` JPY payment
   - user selects a Cash 支付账户, such as Alipay or a JPY account
   - button copy should be business-oriented, for example `提交到 Cash 确认`
     or `请求支付确认`
   - School creates/marks the payment Cash request, but this does not mean paid
   - Cash approval later creates the Cash JPY expense transaction and only then
     should the School payment request become `paid`
   - Cash rejection creates no Cash transaction; the payment request remains
     pending and School displays `Cash已拒绝` with the rejection reason
3. Cash System keeps the separate `外部待确认` page as the ledger-side
   confirmation entry. This is not a School sync page.

Key principles:

- Cash balance can change only after Cash-side approval.
- School business submission to Cash is not Cash payment/income confirmation.
- Ordinary School users should not see sync executor, pending event, outbox, or
  batch terminology.
- School UI wording should use business terms: 收款账户, 支付账户, 提交到 Cash
  确认, Cash待确认, Cash已确认, Cash已拒绝.
- Idempotency starts at pending request creation.
- Cash transaction creation still uses the existing external/idempotency guard.
- Do not exclude 青空塾 or CNY/RMB when money actually moves through a
  user-controlled account. Current code may still exclude them; that is a
  known implementation gap.
- Continue excluding arbitrary school events that do not represent real
  user-controlled-account movement.

Recommended architecture:

- Keep the zsh sync script as a verification/operations tool only.
- Add a Cash pending request table, for example
  `home_external_transaction_requests`.
- Add Cash approve/reject RPCs:
  - approve validates a pending request and calls
    `home_create_external_jpy_transaction(...)`
  - reject stores `rejected_at` / `rejected_reason` and creates no transaction
- Add Cash UI for pending request list, request detail, approve, reject, and
  approve confirmation.
- Add a Supabase Edge Function as the School-click backend bridge:
  - School income/payment page calls the function as part of the business
    submission
  - the function writes/returns the Cash pending request
  - service keys stay server-side
- Do not let a School browser directly write the Cash project with a Cash anon
  key.
- Do not make the Cash frontend directly read the School DB.

School-side objects likely needed:

- Extend `school_personal_cash_linkage_events` lifecycle with request states
  such as `pending_cash_request`, `awaiting_cash_confirmation`,
  `cash_confirmed/synced`, and `cash_rejected`.
- Add fields such as `cash_request_id`, `requested_at`, `confirmed_at`,
  `rejected_at`, and `rejected_reason`.
- Add/adjust RPCs so School can request Cash sync without marking the payment
  request paid and without creating Cash transactions.
- Embed the Cash account selector and confirmation action into the existing
  School business pages:
  - income page: historical implementation is personal `tuition` JPY only; the
    target policy is all tuition/income records whose money enters a
    user-controlled Cash account
  - teacher wage payment page: all pending `teacher_wage` payment requests whose
    actual payment account is Cash-eligible

Teacher wage all-scope Cash confirmation checkpoint, 2026-06-14:

- Added formal SQL file
  `school_teacher_wage_cash_confirmation_all_scope_rpc.sql`.
- The SQL relaxes the historical payment linkage event constraints:
  - `cash_account_mapping_id` is nullable for new all-scope request events
  - `currency` accepts `JPY` / `CNY`
  - `cash_transaction_table` accepts `home_jpy_transactions` /
    `home_cny_transactions`
  - request snapshots store `school_amount_jpy`, `payment_currency`,
    `payment_exchange_rate`, `payment_amount`, and
    `cash_account_type_snapshot`
- Added `school_request_cash_payment_confirmation(...)`.
- The new request RPC validates:
  - payment request exists and is still `pending`
  - `source_type = teacher_wage`
  - business entity exists and is active
  - no existing payment side effects (`paid_at`, school expense, account
    transaction, or school account)
  - selected Cash account snapshot is supplied by the Edge Function from the
    Cash-owned eligible account whitelist
  - payment currency is `JPY` or `CNY`
  - JPY payment uses exchange rate `1` and Cash amount equals the School JPY wage
    cost
  - CNY payment requires `exchange_rate` and Cash amount equals
    `school_amount_jpy * exchange_rate`
- The request RPC intentionally does not:
  - set `school_payment_requests.status = paid`
  - write `paid_at`
  - create school expense records
  - create `school_account_transactions`
  - create Cash transactions
- The payment page now makes `提交到 Cash 确认` the main action for every pending
  `teacher_wage` request. It reads Cash eligible accounts through the
  `request-cash-confirmation` Edge Function and shows:
  - `余额宝` for CNY payment with required exchange rate and CNY payment preview
  - `日元现金`, `日元三菱卡`, `日元乐天卡` for JPY payment
- `直接确认支付` remains available only as a historical/special exception and is
  described as not entering Cash.
- Cash approve remains the only point that creates Cash transactions and changes
  Cash balances. Cash reject creates no Cash transaction and leaves the School
  payment request pending.
- Rejected retry attempts are implemented:
  - rejected Cash requests are terminal and cannot be approved later
  - School payment request stays `pending`
  - School displays the rejected reason
  - resubmission creates a new attempt / Cash request
  - old rejected attempts remain as history
  - one payment request can have only one active attempt at a time
- Verified scope:
  - School rollback test passed
  - Cash JPY/CNY request rollback tests passed
  - rejected -> retry -> approved backend E2E passed
  - cleanup completed with School/Cash target residue 0
  - tests did not use real 2026-05 wage data
- The first real 2026-05 wage trial was later executed for 吴峰 `36,000 JPY`
  through `日元乐天卡`: pending request creation and Cash approve both
  reconciled. Remaining 2026-05 wages should still be processed only by
  explicitly targeted batches.

School-side v2 lifecycle checkpoint, 2026-06-13:

- Added formal SQL draft
  `school_personal_cash_payment_confirmation_lifecycle_schema.sql`.
- The draft extends `school_personal_cash_linkage_events` with:
  - `cash_request_id`
  - `cash_request_status`
  - `requested_at`
  - `confirmed_at`
  - `rejected_at`
  - `rejected_reason`
  - `cash_request_last_checked_at`
- The lifecycle keeps old operational states `pending`, `synced`, `failed`,
  and `blocked`, and adds v2 request states:
  - `pending_cash_request`
  - `awaiting_cash_confirmation`
  - `cash_rejected`
- Added formal RPC draft
  `school_request_personal_cash_payment_confirmation_rpc.sql`.
- Historical note: this RPC is the old compatibility path for personal + JPY
  only. It is no longer the target teacher-wage path; new implementation should
  use `school_request_cash_payment_confirmation(...)`.
- `school_request_personal_cash_payment_confirmation(...)` validates:
  - payment request exists and is still `pending`
  - `source_type = teacher_wage`
  - `currency = JPY`
  - amount is positive
  - business entity is active and `entity_type = personal`
  - mapping is active, `flow_type = teacher_wage_payment`, `JPY -> JPY`
  - mapping business entity matches the payment request
- The request RPC creates or reuses a `school_personal_cash_linkage_events`
  row with `sync_status = pending_cash_request`.
- The request RPC intentionally does not:
  - set `school_payment_requests.status = paid`
  - write `paid_at`
  - create school expense records
  - create `school_account_transactions`
  - create Cash transactions
- `school_mark_personal_cash_payment_request_submitted(...)` is the first
  bridge writeback RPC. After the future Edge Function creates a Cash pending
  request, it records `cash_request_id`, sets `cash_request_status = pending`,
  and moves the School event to `awaiting_cash_confirmation`, while the payment
  request remains `pending`.
- Cash approve/reject callback RPCs are intentionally deferred to the next
  guarded phase, because they are the phase that will first change School
  payment status to `paid` or `cash_rejected`.
- The existing zsh sync executor remains an operations/verification tool. It
  only processes old payment events with `sync_status = pending` and linked
  payment request `status = paid`, so it does not process v2
  `pending_cash_request` or `awaiting_cash_confirmation` events.

Edge Function bridge checkpoint, 2026-06-13:

- Added `supabase/functions/request-cash-confirmation/index.ts`.
- The function is the intended backend bridge behind an embedded School business
  action, not a standalone School sync entry.
- Historical note: the initial implementation supported only personal-business
  `teacher_wage` JPY payment requests. The current teacher-wage implementation
  supports all pending `teacher_wage` payment requests with Cash-eligible JPY/CNY
  accounts. It still does not route the income page or tuition income requests
  yet.
- The current RPC order is:
  1. validate POST JSON body and School bearer token
  2. read and validate Cash active + `allow_school_requests = true` account
  3. call School `school_request_cash_payment_confirmation(...)`
  4. call Cash `home_create_external_transaction_request(...)`
  5. call School `school_mark_personal_cash_payment_request_submitted(...)`
  6. return `ok`, `payment_request_id`, `linkage_event_id`,
     `cash_request_id`, and School/Cash status
- Input body:
  - `payment_request_id`
  - `cash_account_id`
  - `payment_currency = JPY | CNY`
  - `exchange_rate` for CNY
  - optional `payment_amount`
  - optional `note`
- Required Edge Function secrets:
  - `SCHOOL_SUPABASE_URL`
  - `SCHOOL_SERVICE_ROLE_KEY`
  - `CASH_SUPABASE_URL`
  - `CASH_SERVICE_ROLE_KEY`
- The function must use service-role keys only inside Supabase Edge Function
  secrets. No real key, token, DB URL, or connection string is stored in the
  repository.
- The Cash RPC call creates only `home_external_transaction_requests.status =
  pending`. It does not create `home_jpy_transactions` /
  `home_cny_transactions`, does not call Cash approve, and does not change Cash
  balance.
- If the idempotent Cash request already exists but is no longer `pending`,
  the function returns a conflict instead of treating approved/rejected requests
  as a new submitted request.
- The School submitted RPC records the Cash request id and moves the School
  event to `awaiting_cash_confirmation`; it does not set
  `school_payment_requests.status = paid` and does not write `paid_at`.
- The bridge is designed to be idempotent through the School linkage event
  unique key plus the Cash request `idempotency_key`.
- The initial function uses the execution date as Cash request
  `transacted_at` because the School request RPC does not yet return a
  user-selected payment date. If business requires explicit pay date selection,
  add that to the School UI/RPC in a later guarded phase.
- The payment page invokes this function through API wrapper
  `requestCashConfirmationViaFunction(...)` for all pending `teacher_wage`
  payment requests. Cash approve/reject -> School confirmed/rejected writeback
  uses `sync-cash-request-result` and accepts JPY/CNY request rows.

Teacher wage payment page Edge Function request checkpoint, 2026-06-13:

- The payment page now embeds the first v2 business action for personal
  `teacher_wage` JPY payment requests.
- For pending payment requests that match personal business + `teacher_wage` +
  `JPY`, the list action is labelled `提交到 Cash 确认` instead of generic
  `确认支付`.
- The confirmation dialog uses business wording:
  - this is not payment completion
  - Cash System confirmation is required before accounting and payment
    completion
  - rejection does not change Cash balance and School remains unpaid
- The dialog asks for a Cash 支付账户 mapping backed by active
  `school_personal_cash_account_mappings.flow_type = teacher_wage_payment`
  and `JPY -> JPY`.
- The page calls API wrapper
  `requestCashConfirmationViaFunction(...)` in `js/api/payment-api.js`.
  Page code still does not call Supabase `.rpc()`, `fetch`, or DB writes
  directly.
- The wrapper invokes Supabase Edge Function `request-cash-confirmation` with
  `payment_request_id`, `cash_account_mapping_id`, and optional `note`.
- The function creates/reuses the School linkage event, creates the Cash
  pending request, and then marks the School event
  `awaiting_cash_confirmation`.
- On success, the page shows `已提交到 Cash System 待确认` and reloads the
  payment list. The payment request remains `pending`.
- This checkpoint intentionally does not:
  - create a Cash transaction
  - set `school_payment_requests.status = paid`
  - write `paid_at`
  - create school expense records
  - create `school_account_transactions`
  - deploy the Edge Function
  - run the Edge Function
  - test with DB writes
- Existing company / 青空塾 / CNY / non-personal-Cash payment flows may still
  keep the ordinary school-account `确认支付` behavior in current code. That is
  a current implementation limitation to be aligned with the unified policy.
- The next implementation steps are deployment/configuration and Cash
  approve/reject -> School confirmed/rejected writeback.

Minimal School Auth checkpoint, 2026-06-13:

- The School payment page now has a minimal Supabase Auth login block for the
  Edge Function JWT requirement.
- Supported UI:
  - email/password login
  - logout
  - display current logged-in email
- This uses the existing School Supabase anon/publishable client and browser
  session handling. It does not save passwords in localStorage and does not
  expose service-role keys.
- The personal `teacher_wage` JPY Cash confirmation action checks for an active
  School Supabase session before calling
  `requestCashConfirmationViaFunction(...)`.
- If no session exists, the page shows
  `请先登录后再提交到 Cash 确认。` and does not call the Edge Function.
- This checkpoint intentionally does not implement signup, magic links,
  operator/admin roles, student/teacher user accounts, whole-app access
  enforcement, Function deployment, Function execution, DB writes, or E2E
  tests.

Cash request result callback checkpoint, 2026-06-13:

- Added formal SQL file
  `school_personal_cash_payment_request_result_rpcs.sql`.
- Added `school_mark_personal_cash_payment_request_confirmed(...)`:
  - validates the linkage event and matching `cash_request_id`
  - requires the School payment request to still be `pending`
  - marks `school_payment_requests.status = paid`
  - writes `paid_at`
  - marks linkage `sync_status = synced`
  - writes `cash_transaction_id`, `cash_request_status = approved`,
    `confirmed_at`, and `synced_at`
  - does not create school expense records
  - does not create `school_account_transactions`
  - does not write Cash DB
- Added `school_mark_personal_cash_payment_request_rejected(...)`:
  - validates the linkage event and matching `cash_request_id`
  - keeps the School payment request `pending`
  - keeps `paid_at` empty
  - marks linkage `sync_status = cash_rejected`
  - writes `cash_request_status = rejected`, `rejected_at`, and
    `rejected_reason`
  - does not write school ledger rows or Cash DB
- Added `supabase/functions/sync-cash-request-result/index.ts`.
- Added `supabase/config.toml` entry for this function with
  `verify_jwt = false`, because the function receives a Cash-project bearer
  token and validates it inside the function with Cash service role.
- Function input:
  - `cash_request_id`
  - `action = approved | rejected`
- Function behavior:
  1. validate POST JSON body and Cash bearer token
  2. read Cash `home_external_transaction_requests` using Cash service role
  3. require `external_source = aozora_school`,
     `external_reference_type = school_payment_requests`,
     `request_type = teacher_wage_payment_confirm`, JPY expense
  4. require Cash request status to match the requested action
  5. for approved, require `created_transaction_id`
  6. for rejected, require no Cash transaction
  7. call the corresponding School confirmed/rejected RPC with School service
     role
- Required Edge Function secrets remain:
  - `SCHOOL_SUPABASE_URL`
  - `SCHOOL_SERVICE_ROLE_KEY`
  - `CASH_SUPABASE_URL`
  - `CASH_SERVICE_ROLE_KEY`
- Cash browser callers should send only the Cash user bearer token and the
  function URL. They should not receive School service role or School anon keys.
- This checkpoint only adds code and SQL files. It does not apply SQL, deploy
  functions, call RPCs, connect DB, or run E2E tests.

### Corrected School UI Direction

School should not add a separate `sync` or `Cash linkage` work page for ordinary
business users. The only user-facing entry points are:

- `income.html` / income record workflow for personal-business tuition JPY
  income
- teacher wage payment management workflow for personal-business teacher wage
  JPY payment

Income record page target behavior:

1. User selects a personal business entity.
2. User selects `tuition`.
3. Currency is JPY.
4. User selects a Cash 收款账户 from active personal Cash mappings, such as
   Alipay or a JPY account.
5. Submitting the form creates the school income record and submits a Cash
   pending confirmation request.
6. School status uses business labels:
   - `Cash待确认`
   - `Cash已确认`
   - `Cash已拒绝`
7. Cash approval creates the Cash JPY income transaction. Cash rejection creates
   no Cash transaction.

Teacher wage payment page target behavior:

1. User opens a pending personal-business `teacher_wage` JPY payment request.
2. User selects a Cash 支付账户 from active personal Cash mappings, such as
   Alipay or a JPY account.
3. The primary action should be labelled `提交到 Cash 确认` or `请求支付确认`,
   not a generic sync action.
4. School does not mark the payment request `paid` at this step.
5. School shows `Cash待确认` while Cash has a pending request.
6. Cash approval creates the Cash JPY expense transaction and only then should
   School mark the payment request `paid` / `Cash已确认`.
7. Cash rejection creates no Cash transaction; School keeps the payment request
   pending and shows `Cash已拒绝` plus rejection reason.

The zsh sync executor and raw linkage states remain verification/operations
tools. They should not be the ordinary business UI model.

Cash-side objects likely needed:

- `home_external_transaction_requests` or equivalent:
  - `id`
  - `external_source = aozora_school`
  - `external_event_id`
  - `external_reference_type`
  - `external_reference_id`
  - `request_type`
  - `transaction_type`
  - `amount`
  - `currency`
  - `account_id`
  - `status = pending / approved / rejected`
  - `requested_at`, `approved_at`, `rejected_at`, `rejected_reason`
  - `created_transaction_id`
  - `idempotency_key`
  - `payload_snapshot`

Real 2026-05 teacher wage trial plan, not yet executed:

1. Run read-only verification for 2026-05 pending `teacher_wage` candidates.
2. Choose a narrow real-data trial set only after explicit trial authorization.
3. School teacher wage payment page submits selected rows to Cash confirmation
   with an eligible Cash 支付账户.
4. Cash page approves or rejects from `外部待确认`.
5. Verify approved rows create exactly one JPY/CNY Cash transaction and change
   Cash balance.
6. Verify rejected rows create no Cash transaction and do not change Cash
   balance.
7. Verify School status: approved rows become paid/synced; rejected rows remain
   pending with `Cash已拒绝` and rejected reason.
8. Verify retry creates a new attempt after rejection and preserves old rejected
   history.
9. Real 2026-05 data must not be cleaned up. Cleanup applies only to clearly
   marked whitelist test data.

Implementation phases:

1. Cash DB: add external transaction request table and approve/reject RPCs.
2. Cash UI: add pending request list, detail, approve, and reject.
3. Edge Function: School request -> Cash pending request.
4. School DB: extend payment linkage lifecycle and request/confirmed/rejected
   writeback.
5. School UI: embed Cash account selection into income and teacher wage payment
   pages; replace personal JPY teacher_wage direct `确认支付` linkage with
   `提交到 Cash 确认` / `请求支付确认`, not a standalone sync page.
6. ROLLBACK whitelist tests. Completed for School and Cash JPY/CNY requests.
7. COMMIT whitelist E2E approve/reject tests. Completed for rejected -> retry ->
   approved teacher-wage flow with cleanup residue 0.
8. Real 2026-05 teacher wage trial remains not executed.

### Current-State Investigation Summary

School income flow today:

- `school_create_income_record` creates one received `school_income_records`
  row, updates `school_accounts.current_balance`, and inserts one
  `school_account_transactions` row with `transaction_type = income_adjust`.
- `school_update_income_record` edits one received income only when the
  original `income_adjust` account transaction is unique, consistent, and still
  the latest transaction for the account.
- `school_reverse_income_record` preserves the original income and inserts one
  negative `income_reversal` school account transaction, then marks the income
  `reversed`.
- `income.html` currently requires a school account for create; the API layer
  calls `school_create_income_record` through `js/api/income-api.js`.
- `tuition` is the only income category that participates in student monthly
  settlement guards and preview calculations.

Business ownership:

- School business ownership must be identified by
  `school_business_entities`, not display text alone.
- Personal-only guards were valid for the historical Phase 1/2 implementation,
  but are no longer the business policy.
- 青空塾/company ownership should be retained in School and should not by itself
  reject Cash linkage when the actual money movement happens through a
  user-controlled account.

Cash System:

- `home_jpy_transactions` already has external metadata and idempotency columns.
- `home_create_external_jpy_transaction(...)` already supports positive JPY
  `income` and `expense` rows, idempotency-key reuse, and source-event
  duplicate detection.
- Cash-side guards allow `school_payment_requests` teacher-wage events and
  `school_income_records` + `tuition_income_received` for Phase 2 JPY income
  sync.

Reusable Phase 1 pieces:

- `school_personal_cash_account_mappings` as the school-side Cash account
  allowlist.
- Deterministic idempotency keys.
- School-side outbox event lifecycle: `pending`, `synced`, `failed`, `blocked`.
- Manual sync executor pattern: read eligible school outbox, call Cash RPC,
  write school result status.
- Cash RPC duplicate-safe behavior.

### Phase 2 Target Scope

Phase 2 v1 handles only:

- `个人名义` / `entity_type = personal`
- income category `tuition`
- school currency `JPY`
- Cash currency `JPY`
- received tuition income created through a dedicated personal-Cash path
- Cash System JPY transaction with `transaction_type = income`

Phase 2 v1 intentionally uses a dedicated school RPC:

- `school_create_personal_cash_tuition_income_record`
- creates `school_income_records`
- does not update `school_accounts.current_balance`
- does not insert `school_account_transactions`
- creates a pending income linkage event in the same school DB transaction

### Historical Phase 2 v1 Out Of Scope

The following list describes the deliberately narrow 2026-06-13 Phase 2 v1
implementation boundary. It is not the current Cash linkage v1 business
policy.

Do not include in Phase 2 v1:

- 青空塾 / company business records
- CNY
- non-`tuition` income categories
- reimbursements
- company /法人 account spending
- non-personal-business income
- part-time wage income
- school account balance updates for the personal Cash path
- school account transactions for the personal Cash path
- reverse sync
- automatic background retry
- broad historical migration/backfill
- direct page-module `.rpc()` calls or direct table writes

### Recommended Data Flow

1. User opens income creation for a personal business tuition JPY income.
2. UI shows a Cash System JPY account selector backed by active
   `school_personal_cash_account_mappings.flow_type = tuition_income`.
3. Page calls an API wrapper, not Supabase `.rpc()` directly.
4. API wrapper calls `school_create_personal_cash_tuition_income_record`.
5. School RPC validates:
   - business entity exists, is active, and `entity_type = personal`
   - student belongs to the same business entity when set
   - `income_category = tuition`
   - `currency = payment_currency = JPY`
   - amount is positive
   - target student monthly settlement is not locked
   - Cash mapping is active, same business entity, `flow_type = tuition_income`,
     `school_currency = JPY`, and `cash_currency = JPY`
6. School RPC inserts one `school_income_records` row:
   - `status = received`
   - `income_category = tuition`
   - `include_in_student_settlement = true`
   - `account_id = null` or a clearly documented nullable/sentinel pattern,
     because no school account ledger is written in this path
7. In the same transaction, School RPC inserts one
   `school_personal_cash_income_linkage_events` row with `sync_status = pending`.
8. Manual sync executor reads only eligible pending personal tuition JPY events.
9. Executor calls `home_create_external_jpy_transaction(...)`:
   - `transaction_type = income`
   - `external_source = aozora_school`
   - `external_source_id = school income linkage event id`
   - `external_event_type = tuition_income_received`
   - `external_reference_type = school_income_records`
   - `external_reference_id = school_income_records.id`
10. Cash RPC inserts or returns the idempotent existing
    `home_jpy_transactions` row.
11. Executor marks school event `synced` with `cash_transaction_id`, or `failed`
    with `last_error`.

### Implemented DB Objects

School DB:

- Implemented by `school_personal_cash_income_linkage_schema.sql`:
  `school_personal_cash_account_mappings` flow extension and independent income
  outbox table.
- Extend `school_personal_cash_account_mappings`:
  - allow `flow_type = tuition_income`
  - keep `school_currency = JPY`
  - keep `cash_currency = JPY`
  - keep personal-business RPC guards
- Add new outbox table instead of extending Phase 1 payment outbox:
  - `school_personal_cash_income_linkage_events`
  - reason: avoid breaking the existing
    `school_personal_cash_linkage_events` constraints that are intentionally
    payment-request / teacher-wage specific.
- Columns for `school_personal_cash_income_linkage_events`:
  - `id`
  - `source_table = school_income_records`
  - `source_id`
  - `source_event_type = tuition_income_received`
  - `income_record_id`
  - `business_entity_id`
  - `student_id`
  - `cash_account_mapping_id`
  - `cash_user_id`
  - `cash_account_id`
  - `cash_account_name_snapshot`
  - `cash_transaction_table = home_jpy_transactions`
  - `cash_transaction_id`
  - `currency = JPY`
  - `amount`
  - `idempotency_key`
  - `sync_status`: `pending`, `synced`, `failed`
  - `retry_count`
  - `last_error`
  - `note`
  - `created_at`, `updated_at`, `synced_at`
- School RPCs:
  - `school_create_personal_cash_tuition_income_record`
    - implemented by `school_create_personal_cash_tuition_income_record_rpc.sql`
    - creates `school_income_records` plus pending
      `school_personal_cash_income_linkage_events`
    - does not update `school_accounts.current_balance`
    - does not insert `school_account_transactions`
  - `school_update_personal_cash_income_linkage_event_status`
    - implemented by `school_personal_cash_income_linkage_rpcs.sql`
  - `school_retry_personal_cash_income_linkage_event`
    - implemented by `school_personal_cash_income_linkage_rpcs.sql`
    - operator retry only; resets eligible failed tuition income events to
      `pending`

Cash DB:

- Extend `home_jpy_transactions_external_required_check`:
  - allow `external_reference_type = school_income_records`
  - allow `external_event_type = tuition_income_received`
  - require `tuition_income_received` -> `transaction_type = income`
- Extend `home_create_external_jpy_transaction(...)` guards:
  - `external_reference_type` may be `school_income_records`
  - `external_event_type` may be `tuition_income_received`
  - `tuition_income_received` must create `transaction_type = income`
  - amount must stay positive
- Keep CNY untouched.

### Implemented Files

School repo:

- SQL/RPC:
  - `school_personal_cash_income_linkage_schema.sql` executed and verified
  - `school_personal_cash_income_linkage_rpcs.sql` executed and verified
  - `school_create_personal_cash_tuition_income_record_rpc.sql` executed and verified
  - migration/update for `school_personal_cash_account_mappings.flow_type`
- API/frontend:
  - `js/api/income-api.js` adds `createPersonalCashTuitionIncome(...)`,
    implemented
  - `js/pages/income-page.js` adds a create-mode switch for normal School
    account income vs personal Cash tuition income and a read-only Cash sync
    badge for linked income rows
  - `income.html` adds the create-mode and Cash mapping controls
  - `js/api/income-detail-api.js` reads income linkage event display fields
    and exposes `retryPersonalCashIncomeLinkageEvent(...)`
  - `js/pages/income-detail-page.js` renders the Cash sync card and keeps
    edit/reverse guard behavior unchanged; failed events expose a guarded
    `重新同步` action
  - `js/api/personal-cash-linkage-api.js`
- Sync:
  - `scripts/sync-personal-cash-linkage.zsh` extended to process both
    payment linkage and income linkage branches; income E2E verified

Cash repo:

- SQL/RPC:
  - incremental SQL extending `home_create_external_jpy_transaction` executed
    and E2E verified
  - external check constraint / event-type guards updated for
    `school_income_records` + `tuition_income_received`
- Docs only during design; no Cash UI change required for Phase 2 v1.

### Idempotency Strategy

School event idempotency key:

- `aozora_school:school_income_records:{income_record_id}:tuition_income_received`

School uniqueness:

- unique `(source_table, source_id, source_event_type)`
- unique `idempotency_key`

Cash uniqueness already maps well:

- unique `external_idempotency_key`
- unique source event using
  `external_source + external_reference_type + external_reference_id + external_event_type`

Expected duplicate behavior:

- same event / same payload returns the existing Cash transaction and should be
  treated as success.
- same idempotency/source event with different amount/account/date/type returns
  `ok=false`; school event should become `failed`, not silently rewritten.

### Failed / Retry Strategy

Phase 2 v1 keeps retry manual and explicit:

- `pending`: eligible for executor.
- `synced`: terminal for Phase 2 v1; not retried.
- `failed`: may be retried from income detail after an operator fixes the
  mapping/account cause. The retry action calls
  `school_retry_personal_cash_income_linkage_event(...)`, which resets only
  failed `tuition_income_received` events without `cash_transaction_id` back to
  `pending`, clears `last_error`, preserves `retry_count`, and waits for the
  next sync executor run.
- Phase 2 DB foundation v1 does not add a `blocked` status for income events;
  operator blocked/recreate behavior would need a later guarded update.

Executor rules:

- Read only pending income events.
- Require personal business, tuition income, JPY, positive amount, received
  status, not reversed, and no existing `cash_transaction_id`.
- Cash RPC call for tuition income uses:
  - `transaction_type = income`
  - `external_source = aozora_school`
  - `external_source_id = school_personal_cash_income_linkage_events.id`
  - `external_event_type = tuition_income_received`
  - `external_reference_type = school_income_records`
  - `external_reference_id = school_income_records.id`
  - `external_idempotency_key = event.idempotency_key`
- If Cash RPC execution fails or returns `ok=false`, mark `failed` and store
  the message in `last_error`.
- If Cash returns an existing idempotent transaction, mark `synced`.
- The retry UI does not call Cash RPC and does not run the sync executor; it
  only changes the school event back to `pending`.

### Manual Sync Operations

There is no browser-based sync runner and no automatic background scheduler in
Phase 2 v1. The current operations entry is the checked-in manual executor:

```sh
scripts/sync-personal-cash-linkage.zsh
```

Supported objects:

- `teacher_wage` payment linkage:
  - reads pending `school_personal_cash_linkage_events`
  - source event type `teacher_wage_payment_confirm`
  - creates Cash JPY `expense` transactions
- personal-business `tuition` income linkage:
  - reads pending `school_personal_cash_income_linkage_events`
  - source event type `tuition_income_received`
  - creates Cash JPY `income` transactions

Common commands:

```sh
# Inspect eligible pending events without writing Cash or school status.
scripts/sync-personal-cash-linkage.zsh --dry-run --limit 20

# Process eligible pending events, up to the default or supplied limit.
scripts/sync-personal-cash-linkage.zsh --limit 20

# Inspect one specific linkage event.
scripts/sync-personal-cash-linkage.zsh --event-id <event_uuid> --dry-run

# Process one specific pending linkage event.
scripts/sync-personal-cash-linkage.zsh --event-id <event_uuid>
```

Recommended timing:

- after confirming a personal-business teacher wage payment that should sync
  to Cash System
- after creating a personal-business tuition JPY income through the Cash System
  mode
- after seeing `pending` or `failed` Cash sync status in the payment/income UI
- during incident follow-up, prefer `--event-id` to keep the run focused

Operational guardrails:

- Do not manually edit DB rows to force sync state.
- For failed tuition income linkage, first use the income detail `重新同步`
  action to reset the event back to `pending`, then run the script.
- Payment linkage failed retry does not yet have a dedicated UI; handle it as a
  separate guarded operator workflow rather than ad hoc DB edits.
- `synced` events do not need repeat processing.
- Cash RPC idempotency protects duplicate event replay, but operators should
  still use `--dry-run` and `--event-id` when investigating a specific event.
- The script loads DB connection helpers from the local shell environment; do
  not print, paste, save, or commit DB URLs or other secrets.

Future automatic scheduling requires a separate design. Compare at least:

- cron on a controlled machine
- GitHub Actions
- Supabase Edge Function / scheduled function
- local `launchd`

That design must cover secret management, logs and alerting, retry policy,
single-run/duplicate-run protection, and operator visibility before enabling
any unattended execution.

### Edit / Reverse Guard Strategy

Phase 2 v1 does not include reverse sync.

Executed guards:

- `school_update_income_record_rpc.sql` rejects ordinary edit when the income
  has a `school_personal_cash_income_linkage_events` row with
  `source_event_type = tuition_income_received`.
- `school_reverse_income_record_rpc.sql` rejects ordinary reverse when the
  income has a `school_personal_cash_income_linkage_events` row with
  `source_event_type = tuition_income_received`.
- Income detail API reads minimal linkage metadata for the current
  `school_income_records.id`.
- Income detail UI hides ordinary edit/reverse for any Cash-linked tuition row
  and shows:
  - synced: already synced to Cash System; linked edit/reverse is unsupported
    in the current version.
  - pending/failed: already entered the Cash System linkage flow; ordinary
    edit/reverse is blocked.
- Pending/failed rows:
  - retry may be allowed through executor.
  - editing amount/date/business/student/mapping before sync should be treated
    conservatively; default recommendation is to block edits and use an
    operator-only blocked/recreate workflow if needed.
- Reversal linkage belongs to a later Phase 2.x design and should create an
  opposite Cash JPY `expense` event rather than deleting the original Cash
  `income`.

Income create-entry UI:

- Normal School account income remains the default mode and keeps the existing
  `school_create_income_record` path.
- Personal Cash tuition income mode is limited in the page/API to personal
  business, `tuition`, JPY, required student, and active
  `school_personal_cash_account_mappings.flow_type = tuition_income`.
- Personal Cash tuition income mode hides the school account field and calls
  `school_create_personal_cash_tuition_income_record` through the income API
  wrapper, not directly from the page module.
- Income detail guard is implemented in `income-detail.html`,
  `js/api/income-detail-api.js`, and `js/pages/income-detail-page.js`; DB guard
  behavior was verified in rollback testing.

### Verification

Rollback tests:

- personal + tuition + JPY creates one income row and one pending income outbox.
- no `school_accounts.current_balance` change.
- no `school_account_transactions` row.
- company / 青空塾 business entity is rejected.
- CNY is rejected.
- non-`tuition` category is rejected.
- locked student monthly settlement is rejected.
- inactive / wrong-business / wrong-flow mapping is rejected.

Whitelist commit tests:

- create one clearly marked personal tuition JPY income and one pending outbox.
- sync pending event to Cash and verify:
  - one `home_jpy_transactions` row
  - `transaction_type = income`
  - positive amount
  - `external_reference_type = school_income_records`
  - `external_event_type = tuition_income_received`
  - school event becomes `synced`
- rerun sync and verify Cash transaction count stays 1.
- create an invalid Cash mapping/account case and verify event becomes `failed`.
- verify 青空塾 / CNY / non-tuition / reimbursement / company account records are
  not selected by the executor.
- cleanup whitelist DB residue after verification.

Completed whitelist test and cleanup:

- Rollback create/reject/guard testing passed with 0 residue.
- Commit E2E created one marked Cash JPY income transaction, synced the school
  event, and repeated sync did not create a duplicate transaction.
- Cleanup removed the Phase 2 E2E test account, transaction, school
  business/student/mapping/income/event rows; final target counts were 0.

Frontend/browser tests:

- personal tuition JPY create dialog shows Cash account selector.
- 青空塾 or non-personal income uses existing school account flow or is blocked
  from the personal Cash path according to final UX.
- synced Cash-linked income detail hides ordinary edit/reverse and shows the
  Cash System synced reason.
- pending/failed Cash-linked income detail hides ordinary edit/reverse and
  shows the in-linkage-flow reason.
- income detail shows the Cash sync card for pending/synced/failed linked
  tuition income.
- failed linked tuition income detail shows the `重新同步` action; pending and
  synced events do not.
- income list shows the compact Cash sync badge for linked tuition income.
- direct calls to `school_update_income_record` and
  `school_reverse_income_record` reject linked tuition income once the SQL is
  executed.
- page modules still do not call `.rpc()` directly.

### Risks

- Existing income list/detail surfaces should continue treating personal Cash
  tuition income as a valid income row with `account_id = null` and no school
  account transaction.
- Student settlement preview reads tuition income. It must include personal
  Cash-linked tuition income even though no school account transaction exists.
- Profit summary currently uses effective income records; it may include
  Cash-linked income if it reads `school_income_records`, which is likely
  correct for school-side operating profit but should be verified.
- Ordinary income edit/reverse paths can create school ledger inconsistency if
  not blocked for Cash-linked tuition rows; frontend and RPC guards now cover
  synced, pending, and failed linkage statuses.
- Cross-DB strong transaction is still impossible; idempotency and retry remain
  the safety mechanism.

### Post-Completion Checklist

- Keep `school_income_records.account_id = null` display handling stable for
  the personal Cash path.
- Keep Cash retry UI limited to failed -> pending. Do not add direct sync
  execution or Cash transaction creation to the page.
- Re-check student settlement and profit summary behavior before changing
  income aggregation rules.
- Keep rollback and whitelist commit tests explicitly marked with
  `codex-test` / `v2-test` / `sandbox` markers.
- Clean whitelist E2E residue immediately after verification; do not keep
  temporary cleanup SQL in the repository.
- Historical Phase 2 v1 remains documented as personal + tuition + JPY only.
  Future implementation should not treat that scope as the business rule; it
  should add 青空塾, CNY/RMB, entrusted-funds clearing, reimbursement, and
  reversal sync through separate guarded phases.

## Not Recommended

Still not recommended as technical shortcuts:

- Cross-DB strong transactions.
- Direct page-module calls to Cash System writes.
- Writing Cash System rows without idempotency metadata.
- Reusing `home_payment_channels` as balance accounts.
- Treating Cash account ids as school account ids.
- Broad historical backfill or real-data repair.
- Deleting Cash transactions as a normal reversal mechanism.

Previously not recommended for the first narrow implementation phase, but now
required by the corrected business policy in guarded future phases:

- 青空塾 tuition received through user-controlled accounts.
- 青空塾 teacher wage advances paid through user-controlled accounts.
- 青空塾 entrusted-funds clearing to corporate account.
- 青空塾 wage-advance reimbursement from corporate account.
- CNY/RMB account movements such as Alipay receipts/payments.

## Verification Notes

Completed live DB read-only verification:

- Confirmed the target Cash ledger tables exist.
- Confirmed Phase 1 account and JPY transaction fields exist.
- Confirmed no reusable generic external-source / idempotency / school-reference fields exist in the live Cash transaction tables.

Phase 1 closeout verification:

- pending event -> Cash JPY transaction -> school `synced` succeeded.
- duplicate sync execution did not duplicate the Cash transaction.
- failed Cash RPC path correctly marked the school event `failed`.
- 青空塾 / company, CNY, reimbursement, corporate account, and non-`teacher_wage` candidates were not processed.
- Temporary cleanup / rollback / delete SQL files were removed from the repository and pushed.
- Phase 1 test DB residue was cleaned from both school and Cash DBs.
