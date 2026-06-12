# Personal Business / Cash System Linkage Design

Status date: 2026-06-13

Task type: cross-project design-only + read-only investigation. No DB writes, SQL execution, RPC execution, or feature implementation were performed.

## Investigation Scope

School project: `/Users/polariss710/Documents/aozora_school_system_v2`

Cash System project: `/Users/polariss710/Documents/home_account_book`

School DB read-only verification completed through `load_school_db`.

Cash DB read-only verification did not complete because `load_cash_db` loaded a connection string but PostgreSQL authentication was rejected. Cash System facts below are therefore based on repository SQL/API code, not live DB data.

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

## Confirmed Cash System Facts From Code

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

There is no confirmed generic external-source field, source app field, or school correlation id field in the Cash System transaction tables.

## Linkage Boundary

Only personal-business money movement may link to Cash System.

Must link:

- Personal-business tuition income.
- Personal-business lesson-based teacher wage payments.
- Future personal-business part-time / temporary wage payments after that source type is implemented.

Must not link:

- Any `青空进学塾` / `entity_type = company` school record.
- 青空塾 reimbursements.
- 青空塾 teacher wages.
- 法人账户支出.
- School account transfer, reimbursement, account adjustment, or profit-summary internals.
- Sandbox/test business data unless a future test phase explicitly marks it as integration test data.

The first gate should be `school_business_entities.entity_type = 'personal'` plus the known personal business entity. Do not infer from display text alone.

## Recommended Mapping

School should have a Cash account mapping table or equivalent server-side config.

Recommended school-side table design:

- `id`
- `business_entity_id`: only personal-business entities are allowed
- `flow_type`: `tuition_income`, `teacher_wage_payment`, future `part_time_wage_payment`
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

## Cash Transaction Creation

Cash System should receive one idempotent write request per school financial event.

Recommended target rows:

- Personal tuition income:
  - `home_jpy_transactions` or `home_cny_transactions`
  - `transaction_type = income`
  - `account_id = selected/mapped Cash account`
  - `transacted_at = school income date`
  - `amount = school received amount`
  - `description = 学费收入 / student or settlement snapshot`

- Personal teacher wage payment:
  - `home_jpy_transactions` first, matching current school wage payment currency
  - `transaction_type = expense`
  - `account_id = selected Cash account`
  - `transacted_at = pay date`
  - `amount = payment request amount`
  - `description = 老师工资 / teacher / request month`

- Future part-time wage payment:
  - Same pattern as teacher wage payment after `part_time_wage` has a verified payment source and confirmation flow.

Do not write `home_payment_channels` for this linkage.

## Account Selection UX

For supported personal-business flows:

- The confirmation dialog should show a Cash System account selector, filtered by currency and active mapping.
- Options should display Cash account name, currency, account type, and current Cash balance if the integration API can read it.
- The page module must call a school API wrapper; it must not call Cash DB directly or embed Cash DB credentials.
- If no active mapping exists, the confirmation action should be blocked with a clear setup-required message.

For 青空进学塾 / company flows:

- Keep the current school account selector and current school-only payment behavior.
- Do not show Cash System accounts.

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

## Not Recommended

Do not implement in the first phase:

- 青空塾 reimbursement linkage.
- 青空塾 teacher wage linkage.
- 法人账户 / company account linkage to Cash System.
- Cross-DB strong transactions.
- Direct page-module calls to Cash System writes.
- Writing Cash System rows without idempotency metadata.
- Reusing `home_payment_channels` as balance accounts.
- Treating Cash account ids as school account ids.
- Broad historical backfill or real-data repair.
- Deleting Cash transactions as a normal reversal mechanism.

## Open Verification Items

Before implementation, complete read-only Cash DB verification after credentials are fixed:

- Confirm live `home_accounts` columns and active account names/types for 支付宝, 日元现金, 日元三菱卡, etc.
- Confirm whether live `home_jpy_transactions` / `home_cny_transactions` already have any external-source metadata not present in local SQL files.
- Confirm current RLS and write RPC expectations for service/server-side integration.
- Confirm whether Cash System should add columns to transaction tables or use a separate external-link table.
