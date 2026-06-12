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

1. Personal business Cash System linkage Phase 1 end-to-end sync checkpoint, 2026-06-13:
   Completed a controlled manual sync executor for personal-business `teacher_wage` JPY school outbox events. Added `scripts/sync-personal-cash-linkage.zsh`; it reads eligible `school_personal_cash_linkage_events.sync_status = pending`, switches to Cash DB to call `home_create_external_jpy_transaction`, then switches back to school DB and marks the event `synced` with `cash_transaction_id` or `failed` with `last_error`. It processes only personal business, paid `teacher_wage`, JPY, `teacher_wage_payment_confirm`, and pending events; it skips company / 青空塾, CNY, non-teacher-wage, reversed, synced, and failed events. End-to-end whitelist test inserted one Cash JPY external transaction and synced the school event: Cash account `94000000-0000-4000-8000-000000150501`, school business entity `94000000-0000-4000-8000-000000150001`, payment request `94000000-0000-4000-8000-000000150101`, school event `2f20e264-1e20-493d-b92a-58c244abfa09`, Cash transaction `fbd3e5df-14be-4b3b-9a0b-319f4416968b`. Re-running the sync for the same event found no pending candidate and Cash transaction count stayed 1. Failure path was verified on codex-test event `11f8f9ee-cbf4-4a29-8d6a-dc56a7d2e7e4`, which moved to `failed` with the Cash RPC error. Old fake pending test event `9b95e09a-09c4-4203-bc02-07daaf1beb5b` was marked `blocked`.

2. Personal business Cash System linkage payment-confirm outbox checkpoint, 2026-06-13:
   Completed payment confirmation UI/API/RPC integration for Phase 1 school outbox only. Added and executed `school_confirm_personal_cash_payment_request_rpc.sql`, which confirms one personal-business `teacher_wage` JPY pending payment request and creates one pending `school_personal_cash_linkage_events` outbox row in the same school DB transaction, without writing Cash DB and without creating school expense/account-transaction/account-balance side effects. Payment page now loads active `school_personal_cash_account_mappings`, shows a Cash System account selector only for `entity_type = personal` + `teacher_wage` + `JPY`, keeps company / 青空塾 on the existing school account selector and `school_confirm_payment_request`, blocks personal requests without active mapping, and hides reversal action for paid requests that already have a Cash outbox event. Payment detail page now shows read-only Cash linkage status. Rollback test residue was 0. Whitelist commit test left clearly marked school test data only: business entity `93000000-0000-4000-8000-000000141001`, payment request `93000000-0000-4000-8000-000000141101`, mapping `eaf3b59d-f944-441f-911f-b639ba284c78`, linkage event `11f8f9ee-cbf4-4a29-8d6a-dc56a7d2e7e4` with `sync_status = pending`. No Cash DB writes were performed.

3. Personal business Cash System linkage school-side mapping/outbox checkpoint, 2026-06-13:
   Completed school-side Phase 1 minimum schema/RPC/API support for `个人名义` teacher-wage JPY payment -> Cash System linkage metadata. Added and executed `school_personal_cash_linkage_schema.sql` for `school_personal_cash_account_mappings` and `school_personal_cash_linkage_events`; added and executed `school_personal_cash_linkage_rpcs.sql` for guarded mapping create/update/list, linkage event create/query, and sync status update. Added API wrappers in `js/api/personal-cash-linkage-api.js`; no page module was changed, and payment confirmation/wage/reimbursement/student-settlement main chains were not modified. Rollback tests verified personal-only guards, duplicate event idempotency, status update behavior, and 0 residue. Whitelist commit test left clearly marked school test data only: business entity `92000000-0000-4000-8000-000000132001`, payment request `92000000-0000-4000-8000-000000132101`, mapping `f5c02610-1b11-4353-b5de-ae5b3b60f980`, linkage event `9b95e09a-09c4-4203-bc02-07daaf1beb5b` with `sync_status = pending`. No Cash DB writes were performed.

4. Personal business Cash System linkage Phase 1 planning, 2026-06-13:
   Completed the earlier read-only pre-implementation planning for `个人名义` teacher-wage JPY payment confirmation -> Cash System JPY transaction linkage. Later 2026-06-13 checkpoints implemented Cash-side external JPY RPC support, school-side mapping/outbox support, payment-confirm outbox creation, and controlled manual end-to-end sync.

5. Family account whitelist cleanup checkpoint, 2026-06-13:
   Cleaned the account/family first-stage whitelist commit-test account after dry-run, rollback validation, commit delete, and residue check. Deleted only `school_accounts.id = d3734cd7-fa94-4be3-b8dc-3cdc3690f667` / `account_code = codex-test-family-app-type-commit-20260613`; pre-delete checks confirmed `app_type = family`, inactive, no business entity, non-company, clearly `codex-test`, and 0 references from account transactions, adjustments, transfers, income, expense, payment requests, reimbursements, salary/student payments, and v51 backup account columns. Residue check confirmed target ID/code/text and all checked references are 0.

## Current To-Do / Priority

1. Preserve completed V1 surfaces before adding new write scope.
2. Treat personal-business Cash System reversal sync / retry UI / production cleanup, payment-management follow-up beyond the current optional exchange-rate confirmation behavior, weekly plan image export, full actual import/history migration, expanded wage-lock lifecycle, teacher wage adjustment items for transport/classroom fees, payment-request realtime exchange-rate CNY conversion, account scope/household owner expansion beyond first-stage `app_type`, part-time wage records, account balance adjustment / opening-balance correction, real expense attachment storage upload/preview/replace, business-entity-scoped wage generation, and DB-level linked-actual unique/index review as separate guarded phases.
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
