# Personal Business / Cash System Linkage Design

Status date: 2026-06-13

Task type: cross-project design plus guarded Phase 1 implementation checkpoints. Initial investigation was read-only; later phases executed guarded Cash-side and school-side schema/RPC work as recorded below.

## Investigation Scope

School project: `/Users/polariss710/Documents/aozora_school_system_v2`

Cash System project: `/Users/polariss710/Documents/home_account_book`

School DB read-only verification completed through `load_school_db`.

Cash DB read-only verification completed through `load_cash_db` after switching to the Cash System Supabase Direct connection. The loaded Cash DB URL was verified as different from the school DB URL without printing or storing either URL.

Cash System facts below are based on live DB `information_schema` / `pg_indexes` read-only verification plus repository SQL/API code.

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

## Phase 1 Implementation Status

Status: Cash System side Phase 1 schema/RPC completed on 2026-06-13. School-side mapping/outbox schema/RPC/API completed on 2026-06-13. Payment confirmation integration and cross-project write path are not implemented.

Cash completed:

- Cash repository: `/Users/polariss710/Documents/home_account_book`
- SQL archive: `supabase-update-20260613-external-jpy-1.sql`
- Added external/idempotency metadata columns to `home_jpy_transactions`.
- Added partial unique indexes for external idempotency and external source event uniqueness.
- Added `home_jpy_transactions_external_required_check`.
- Added RPC `home_create_external_jpy_transaction(...)`.
- Rollback idempotency test verified: first call inserted a temporary external JPY expense, second call with the same idempotency key returned the same transaction id with `inserted=false`, count stayed 1 inside the transaction, and rollback residue was 0.

Not completed:

- payment confirmation UI/API/RPC integration
- cross-project write path

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
- Whitelist commit test left clearly marked school test data only:
  - business entity: `92000000-0000-4000-8000-000000132001`
  - payment request: `92000000-0000-4000-8000-000000132101`
  - mapping: `f5c02610-1b11-4353-b5de-ae5b3b60f980`
  - linkage event: `9b95e09a-09c4-4203-bc02-07daaf1beb5b`
  - event status: `pending`
- No Cash DB writes were performed in the school-side phase.
- No existing payment confirmation, teacher wage generation, reimbursement, income, student settlement, or page module was changed.

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
4. End-to-end verification:
   - rollback test for school confirm + event creation
   - rollback test for Cash external insert + duplicate idempotency
   - whitelist commit test with explicitly marked personal business test data
   - verify no 青空塾 / company records enter the Cash path
   - verify duplicate confirm/retry does not duplicate Cash transactions

### Explicitly Out Of Phase 1

- 青空塾 linkage
- reimbursement linkage
- legal/company account linkage
- cross-DB strong transactions
- automatic retry background jobs
- Cash System full ledger refactor
- CNY linkage
- tuition income linkage
- part-time wage linkage
- historical backfill or real-data repair

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

## Verification Notes

Completed live DB read-only verification:

- Confirmed the target Cash ledger tables exist.
- Confirmed Phase 1 account and JPY transaction fields exist.
- Confirmed no reusable generic external-source / idempotency / school-reference fields exist in the live Cash transaction tables.

Still required before implementation design is converted to SQL:

- Decide whether Cash System should add external-source columns to transaction tables or use a separate external-link table.
- Confirm service/server-side write path and RLS behavior for the future integration implementation.
- Confirm final user-facing Cash account mapping choices for accounts such as 支付宝, 日元现金, 日元三菱卡.
