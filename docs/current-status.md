# Current Status

Status date: 2026-06-13

This is the lightweight daily entry document. It intentionally keeps only the current system state, hard stops, safety rules, active backlog, and the latest 5 key updates. Older status history is archived in `docs/archive/current-status-history.md`.

## Current System State

- v2 is currently focused on current/future operations. Historical maintenance remains in v1 or in separately authorized guarded migration/repair phases.
- v2 master-data policy: open create/edit where safe, keep delete/merge closed unless a future audit-safe workflow explicitly opens it.
- Core business writes are DB/RPC-backed. Page modules must not call Supabase `.rpc()` directly and must not directly insert/update/delete/upsert rows; page writes go through `js/api/*-api.js` wrappers and verified RPCs.
- Student settlement, teacher wage generation/snapshots, payment requests, reimbursements, account transactions, income/expense, and locking flows are protected main chains. Master-data dialog work must not mutate these chains.
- Current or unclosed real business months must not be used for real wage generation, snapshot generation, student settlement closing, locking, or lock-style write validation. Validation should use transaction rollback or clearly marked whitelist data such as `codex-test`, `v2-test`, `sandbox`, `测试学生`, `测试老师`, or `测试业务归属`.
- Field narrowing policy: create/edit dialogs should expose only fields actually used in current operations. Historical, reserved, low-frequency, generated, derived, financial-chain, and audit fields stay hidden/readonly but are not physically removed from DB unless a separate cleanup phase is designed. Repeated master-data dialog narrowing tasks should follow `docs/workflows/v2-master-dialog-simplification.md`.

## Hard Stops

Stop and report immediately for:

- missing `SUPABASE_DB_URL`, unavailable `psql`, static check failure, rollback/commit test failure, abnormal git status, or unclear ownership of test data that cannot be solved by creating safe test data;
- need for non-whitelisted real business data, current/unclosed real-month write validation, broad historical-data modification, historical repair, broad backfill, destructive cleanup, `delete`, `truncate`, `drop`, broad permission changes, or irreversible production operation;
- secrets exposure risk, page-level direct DB writes, page-level direct `.rpc()`, non-target module changes, broad refactor, or documentation/request conflict that cannot be safely interpreted.

## Latest 5 Key Updates

1. Personal business Cash System linkage Phase 1 planning, 2026-06-13:
   Completed read-only pre-implementation planning for `个人名义` teacher-wage JPY payment confirmation -> Cash System JPY transaction linkage. Live read-only DB verification confirmed school has no existing cash/linkage/outbox tables, and Cash has no external-source/idempotency/school-reference fields or external JPY transaction RPC. Updated `docs/personal-business-cash-system-linkage-design-2026-06-13.md` with the minimal Cash-side plan (`home_jpy_transactions` external metadata, idempotency/source uniqueness, `home_create_external_jpy_transaction`), school-side mapping/outbox plan (`school_personal_cash_account_mappings`, `school_personal_cash_linkage_events`), account-selection behavior, reversal posture, implementation order, and explicit out-of-scope boundaries. No SQL files were generated or executed, and no DB writes were performed.

2. Family account whitelist cleanup checkpoint, 2026-06-13:
   Cleaned the account/family first-stage whitelist commit-test account after dry-run, rollback validation, commit delete, and residue check. Deleted only `school_accounts.id = d3734cd7-fa94-4be3-b8dc-3cdc3690f667` / `account_code = codex-test-family-app-type-commit-20260613`; pre-delete checks confirmed `app_type = family`, inactive, no business entity, non-company, clearly `codex-test`, and 0 references from account transactions, adjustments, transfers, income, expense, payment requests, reimbursements, salary/student payments, and v51 backup account columns. Residue check confirmed target ID/code/text and all checked references are 0.

3. Account/family account isolation first-stage checkpoint, 2026-06-13:
   Implemented first-stage account `app_type` isolation for account management. New RPC overloads `school_create_account_profile(..., p_app_type)` and `school_update_account_profile(..., p_app_type)` support `school` and `family` account profile create/update while preserving old overloads; family accounts are master data only, force `business_entity_id = NULL` and `is_company_account = false`, cannot change `app_type` through profile edit, and do not create account transactions. Account page version/cache-bust is `v2.109.0-account-app-type-isolation-20260613`; account management now filters and labels `school` / `store` / `family`, defaults to `school`, creates/edits `school` and `family` profiles, disables store editing for this phase, and keeps adjustment/transfer school-only. School main-chain APIs/pages still filter account candidates with `app_type = school`; browser validation confirmed default school-only cards, family create/edit payloads, school create payload, transfer dropdown school-only, and mobile no-overflow.

4. Expense exchange-rate optional checkpoint, 2026-06-13:
   Fixed expense create/edit page validation so exchange rate is optional: blank input and `0` submit as `NULL`, positive values submit normally, and only negative or non-numeric input is blocked. Expense edit still backfills DB `NULL` as a blank field, not `0`. Updated expense page cache-bust/version to `v2.108.0-expense-exchange-rate-optional-20260613`. Browser validation through actual `expense.html` and `expense-detail.html` paths with mocked Supabase endpoints confirmed create/edit blank, `0`, positive, and negative cases; no real DB writes were performed.

5. Payment cache-bust and page-path exchange-rate validation checkpoint, 2026-06-13:
   Follow-up investigation found payment management frontend/API had no `exchange_rate` required-field or `<= 0` guard in the confirm-payment path; payment method protection remains `p_payment_method = bank_transfer`. The stale surface was the payment entry cache-bust/version: `APP_VERSION`, `index.html`, and `js/app.js` were updated to `v2.107.0-payment-exchange-optional-cache-bust-20260613`. Browser validation through the actual payment page path, with Supabase endpoints mocked to avoid DB writes, confirmed the displayed version is v2.107.0, confirm dialog submits successfully with JPY amount and CNY amount = 0, no confirm error appears, and the `school_confirm_payment_request` request body contains no exchange-rate field.

## Current To-Do / Priority

1. Preserve completed V1 surfaces before adding new write scope.
2. Treat personal-business Cash System linkage implementation, payment-management follow-up beyond the current optional exchange-rate confirmation behavior, weekly plan image export, full actual import/history migration, expanded wage-lock lifecycle, teacher wage adjustment items for transport/classroom fees, payment-request realtime exchange-rate CNY conversion, account scope/household owner expansion beyond first-stage `app_type`, part-time wage records, account balance adjustment / opening-balance correction, real expense attachment storage upload/preview/replace, business-entity-scoped wage generation, and DB-level linked-actual unique/index review as separate guarded phases.
3. Keep master-data create/edit narrow. Do not reopen hidden historical/reserved fields unless a concrete current-operation need and DB/API/RPC support are verified first.
4. For future master-data dialog field narrowing, reference `docs/workflows/v2-master-dialog-simplification.md` first. If touching settlement, wage, payment, reimbursement, income/expense, lesson, or account flows, use the full write-RPC workflow in `docs/workflows/write-rpc-flow.md` and verify side effects through rollback or whitelist tests.

## Daily References

- Module summary: `docs/module-status.md`
- Technical ownership map: `docs/system-map.md`
- Write/RPC workflow: `docs/workflows/write-rpc-flow.md`
- Master dialog simplification workflow: `docs/workflows/v2-master-dialog-simplification.md`
- Account/family ledger design: `docs/account-family-account-integration-design-2026-06-12.md`
- Personal business Cash System linkage design: `docs/personal-business-cash-system-linkage-design-2026-06-13.md`
- Part-time wage design: `docs/part-time-wage-record-module-design-2026-06-12.md`
- Full historical current-status archive: `docs/archive/current-status-history.md`
