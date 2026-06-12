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

1. Payment cache-bust and page-path exchange-rate validation checkpoint, 2026-06-13:
   Follow-up investigation found payment management frontend/API had no `exchange_rate` required-field or `<= 0` guard in the confirm-payment path; payment method protection remains `p_payment_method = bank_transfer`. The stale surface was the payment entry cache-bust/version: `APP_VERSION`, `index.html`, and `js/app.js` were updated to `v2.107.0-payment-exchange-optional-cache-bust-20260613`. Browser validation through the actual payment page path, with Supabase endpoints mocked to avoid DB writes, confirmed the displayed version is v2.107.0, confirm dialog submits successfully with JPY amount and CNY amount = 0, no confirm error appears, and the `school_confirm_payment_request` request body contains no exchange-rate field.

2. Payment cleanup and optional exchange-rate checkpoint, 2026-06-12:
   Cleaned the previous expense-test whitelist data after dry-run, rollback validation, commit delete, and residue check: business entity `f500595d-5455-4460-b826-757c8f834d20`, account `7ea665f1-74b0-4177-90d8-6e79002e3082`, expense `e37287bc-81f2-4714-b79c-a31894b8144b`, and account transaction `f444efb6-7f32-4b39-93d7-69ed3ce9b235` were removed; no related attachments, reimbursements, payment requests, income, or Storage objects were candidates. Re-executed `school_confirm_payment_request` so generated teacher-wage expenses store `exchange_rate = NULL` when JPY/CNY amounts cannot derive a positive rate. Payment method behavior is unchanged: the API/RPC path still defaults/protects payment method as `bank_transfer`. Rollback and whitelist commit tests verified the optional exchange-rate behavior, then the self-created whitelist rows were cleaned to 0 residue.

3. Expense record field-scope/edit checkpoint, 2026-06-12:
   Expense create dialog was narrowed to current operational fields: expense date, business entity, payment account, expense category, amount, description, payment method (`cash`, `bank_transfer`, `card`, `alipay`), receipt status, reimbursement status, tax category, exchange rate, and note. Account currency, business-expense toggle, teacher, and student are hidden from ordinary expense create/edit; currency is derived from the selected account and hidden DB fields are preserved/defaulted rather than physically removed. New guarded RPC `school_update_expense_record` edits ordinary paid expenses only when they are not reversed, not teacher-wage/source-payment-request expenses, not reimbursed or reimbursement-linked, have exactly one matching original `expense_adjust` transaction, and that transaction is still the latest account transaction. Already ledgered expenses cannot change payment account; use reversal/recreate for account migration. Expense detail now hides source payment request and account transaction display blocks, while retaining reimbursement and attachment sections. Attachment upload/preview/replace was investigated and deferred: DB/storage bucket support exists, but current attachment RPC is metadata-only with placeholder paths and no upload/replace lifecycle RPC, so real file handling remains a separate storage/security phase.

4. Income record field-scope/edit checkpoint, 2026-06-12:
   Income create/edit now exposes the same operational fields and hides account-currency input; account currency is derived from the selected account and still guarded by RPC. Income category is now a dropdown: `tuition` 学费, `material_fee` 教材费, `registration_fee` 报名费, and `other_fee` 其他费用. Only tuition income participates in student monthly settlement guards/calculation; non-tuition categories are ordinary income with `include_in_student_settlement = false`. New guarded RPC `school_update_income_record` edits received income only when the income is not reversed, not linked to student-payment chain, not locked by student settlement, has exactly one matching original `income_adjust` transaction, and that transaction is still the latest account transaction. The income detail page removed the student monthly settlement reference section because it was read-only lookup context and not a real settlement result; account transaction reference remains. Detail action buttons now use a responsive side-by-side layout for edit/reverse/return.

5. Codex/v2-test/sandbox DB cleanup round 2 checkpoint, 2026-06-12:
   One-time cleanup `school_cleanup_codex_test_data_round2_20260612.sql` was executed with dry-run, rollback validation, commit, and post-cleanup residue check. It removed 3 confirmed whitelist test DB rows: account `3c50704b-4c59-4253-a094-9eac0fea6c73` and business entities `8cbb40db-b6e5-48e1-9fe4-caf536f5efc1` / `2efabba9-59e9-49f6-915d-578440123c8d`. No related lesson, settlement, wage, payment, reimbursement, income/expense, account-transaction, attachment, or Storage rows were candidates. Post-cleanup dry-run reports 0 DB candidates, 0 Storage candidates, 0 manual-review rows, and 0 risk rows.

## Current To-Do / Priority

1. Preserve completed V1 surfaces before adding new write scope.
2. Treat payment-management follow-up beyond the current optional exchange-rate confirmation behavior, weekly plan image export, full actual import/history migration, expanded wage-lock lifecycle, teacher wage adjustment items for transport/classroom fees, payment-request realtime exchange-rate CNY conversion, account/family ledger scope implementation, part-time wage records, account balance adjustment / opening-balance correction, real expense attachment storage upload/preview/replace, business-entity-scoped wage generation, and DB-level linked-actual unique/index review as separate guarded phases.
3. Keep master-data create/edit narrow. Do not reopen hidden historical/reserved fields unless a concrete current-operation need and DB/API/RPC support are verified first.
4. For future master-data dialog field narrowing, reference `docs/workflows/v2-master-dialog-simplification.md` first. If touching settlement, wage, payment, reimbursement, income/expense, lesson, or account flows, use the full write-RPC workflow in `docs/workflows/write-rpc-flow.md` and verify side effects through rollback or whitelist tests.

## Daily References

- Module summary: `docs/module-status.md`
- Technical ownership map: `docs/system-map.md`
- Write/RPC workflow: `docs/workflows/write-rpc-flow.md`
- Master dialog simplification workflow: `docs/workflows/v2-master-dialog-simplification.md`
- Account/family ledger design: `docs/account-family-account-integration-design-2026-06-12.md`
- Part-time wage design: `docs/part-time-wage-record-module-design-2026-06-12.md`
- Full historical current-status archive: `docs/archive/current-status-history.md`
