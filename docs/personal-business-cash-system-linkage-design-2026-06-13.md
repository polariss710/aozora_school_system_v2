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

Phase 1 completed:

- Personal-business lesson-based teacher wage payments.
- JPY only.
- School payment request -> school linkage event / outbox -> manual sync executor -> Cash System JPY transaction.
- Idempotent sync: repeated execution does not create duplicate Cash rows.
- Successful Cash write marks the school event `synced`; Cash RPC failure marks the school event `failed`.

Phase 2 completed:

- Personal-business tuition income -> Cash System JPY income transaction.
- Reuses external metadata, idempotency, school linkage event, and outbox patterns.
- Continue to exclude 青空塾 and CNY.

Future candidate after its source flow exists:

- Personal-business part-time / temporary wage payments.

Must not link:

- Any `青空进学塾` / `entity_type = company` school record.
- 青空塾 reimbursements.
- 青空塾 teacher wages.
- 法人账户支出.
- CNY.
- Non-`teacher_wage` payment requests in Phase 1.
- Personal-business tuition income in Phase 1.
- 私塾打工 / 兼职工资收入 in Phase 1.
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

## Phase 2 Design: Personal Tuition Income

Status: Phase 2 v1 completed and verified on 2026-06-13 for personal-business
`tuition` JPY income -> Cash System JPY `income` transaction linkage.

Completion scope:

- personal business `tuition` income only
- JPY only
- school income -> income linkage event -> manual sync executor -> Cash JPY
  income transaction -> school `synced` writeback
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
- Phase 2 E2E `codex-test-personal-cash-tuition-e2e-20260613` residue was
  cleaned: Cash target account/transaction = 0, School target
  business/student/mapping/income/event = 0, and `home_cny_transactions`
  marker = 0.

Still unsupported:

- linked edit / reverse for synced tuition income
- CNY
- 青空塾 / company income
- non-`tuition` income
- automatic scheduled sync; Phase 2 v1 still uses the manual sync script

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

- Personal business must be identified by
  `school_business_entities.entity_type = 'personal'`.
- 青空塾 / company data must be rejected by DB/RPC guard; display text is not
  enough for authorization.

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

### Out Of Scope

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
    account income vs personal Cash tuition income
  - `income.html` adds the create-mode and Cash mapping controls
  - `js/api/income-detail-api.js`
  - `js/pages/income-detail-page.js`
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
- `failed`: may be retried only after an operator fixes the mapping/account
  cause or explicitly resets/chooses retry behavior in a later guarded UI.
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
- Re-check student settlement and profit summary behavior before changing
  income aggregation rules.
- Keep rollback and whitelist commit tests explicitly marked with
  `codex-test` / `v2-test` / `sandbox` markers.
- Clean whitelist E2E residue immediately after verification; do not keep
  temporary cleanup SQL in the repository.
- Keep Phase 2 v1 limited to personal + tuition + JPY; do not open 青空塾, CNY,
  reimbursement, company account, or reversal sync in the same phase.

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

Phase 1 closeout verification:

- pending event -> Cash JPY transaction -> school `synced` succeeded.
- duplicate sync execution did not duplicate the Cash transaction.
- failed Cash RPC path correctly marked the school event `failed`.
- 青空塾 / company, CNY, reimbursement, corporate account, and non-`teacher_wage` candidates were not processed.
- Temporary cleanup / rollback / delete SQL files were removed from the repository and pushed.
- Phase 1 test DB residue was cleaned from both school and Cash DBs.
