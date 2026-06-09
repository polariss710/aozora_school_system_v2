# Module Status

Status date: 2026-06-10

Visual dashboard: open `docs/module-status-dashboard.html` locally for a card-based static overview.

Scope:

- This document summarizes feature completion from current repo docs and code structure. It does not replace the technical ownership map in `docs/system-map.md`.
- Historical maintenance remains in v1. v2 is scoped to current and future operations unless a future phase explicitly opens a guarded migration/repair workflow.
- Items marked `需要进一步验证` are intentionally not inferred beyond the current docs/code evidence.
- 完成度按当前 V1 目标清单粗粒度计算，不代表最终系统全部功能；历史迁移、删除/合并、广义编辑、清理和最终自动化能力不自动计入已完成。

Status labels:

- 已收口: 当前 V1 目标已经完成并有文档记录，后续只做独立新阶段或缺陷修正。
- V1 可用: 核心读写链路已经可用，但仍有明确的后续增强或补充页面。
- 只读/预览: 当前模块主要提供列表、详情、预览或审计查看，本模块自身不发起写入。
- 需要验证: repo/docs/code 里能看到入口或边界，但还需要单独复核后才能标为已完成。
- Backlog: 已明确暂不实现，或必须另开 guarded workflow 的事项。

Completion snapshot:

| Module | Status | Completion |
| --- | --- | --- |
| 课时管理 | 已收口 | 13/13 |
| 学生月度结算 | 已收口 | 8/8 |
| 老师工资结算 | 只读/预览 | 4/4 |
| 账户管理 | V1 可用 | 8/9 |
| 收入记录 | V1 可用 | 3/6 |
| 支出记录 | V1 可用 | 5/9 |
| 报销管理 | V1 可用 | 3/7 |
| 学生/老师/科目/业务归属管理 | V1 可用 | 12/16 |
| 工资规则 | V1 可用 | 5/8 |
| 导入导出 | 已收口 | 8/8 |
| Backlog / 暂不实现 | Backlog | 0/10 |

## 课时管理

- 状态标签: 已收口
- 完成度: 13/13
- V1 边界: 课时管理 V1 基本收口。当前运营主线以 planned-only 课时导入作为核心稳定源头；actual 生成、取消、补课完成和 linked actual 编辑都依托 planned 源头及其 guard 语义。当前运营中生成实际课时后，如发现日期、时间、金额、内容、备注等问题，优先通过 guarded edit 修正，而不是删除重建。
- 已完成: ordinary list, planned/actual paired view, detail page, planned lesson creation V1, completed/cancelled/makeup_completed actual-from-planned V1, guarded edit V1, planned-only void V1, voided planned readonly filter/detail, lesson import preview, planned-only batch import, planned-only Excel template export, detail return-query navigation, and settlement/wage evidence links.
- 可写入功能: create planned lesson, create completed actual from planned, create cancelled actual from planned, create makeup_completed actual from planned, planned-only batch import, guarded lesson edit, planned-only void. All exposed writes go through `js/api/lesson-api.js` and verified RPCs.
- 只读/预览功能: list, paired view, detail, import preview, planned-ID/lock precheck for import, voided planned review, source-chain and settlement/wage reference display.
- guard/锁定保护: planned/actual write RPCs guard locked student settlement months and locked teacher wage months where applicable; guarded edit blocks voided rows, linked actual/source master-data changes, stale `updated_at`, settlement locks, wage locks, and wage detail snapshots; planned void blocks linked actuals, locked settlement months, stale rows, already-voided rows, invalid lesson type/status, and blank reasons.
- 当前不处理历史数据: 历史维护继续由 v1 或单独 migration/backlog 处理；full actual import 保持 future/history migration backlog，不进入当前实现。
- 跨月待补课限制: 数据模型和统计口径可以表达 `lesson_type = actual` + `status = makeup_completed` + `is_billable = false`，但当前 UI 没有完整流程去选择上月 `pending_makeup` 并生成本月 `makeup_completed` actual。跨月待补课完成登记 / 待补课池标记为 future backlog，本轮不实现。
- 未完成: free actual creation outside planned flow, full actual batch import, lesson delete, void restore, `voided_by`, wage lock generation from lessons, settlement adjustment/generation beyond completed settlement V1, auto-matching by student/teacher/subject/date/time, same-file planned/actual linking, cross-month pending-makeup completion workflow / pending-makeup pool.
- 已知限制: planned-only import accepts only planned rows with `planned` / `pending_makeup`; actual rows may still be previewed/prechecked for future design but planned-only submit blocks them. Batch import does not use teacher wage lock protection because planned rows do not set actual teacher settlement month. Lesson delete remains backlog but is not a current operational must-have because guarded edit covers ordinary post-generation corrections.
- 后续优先级: keep planned-only import as stable V1; keep full actual/history migration import out of current implementation; design cross-month pending-makeup pool, void restore, and wage-lock generation only as separate guarded phases.

## 学生月度结算

- 状态标签: 已收口
- 完成度: 8/8
- 已完成: V1 is closed for current/future operations: realtime preview, preview -> locked snapshot, soft unlock, same-row relock, list/detail status display, guard documentation, and closure self-check.
- 可写入功能: lock from preview, unlock locked settlement, relock unlocked settlement. Writes are centralized in `js/api/settlement-api.js` through `school_lock_student_monthly_settlement`, `school_unlock_student_monthly_settlement`, and `school_relock_student_monthly_settlement`.
- 只读/预览功能: settlement list, detail page, realtime preview rows, read-only summary RPC `school_get_student_monthly_settlement_summary`, saved snapshot detail plus matching lesson/income references.
- guard/锁定保护: locked settlements block lesson edit, planned void, actual generation, tuition income create, and tuition income reverse through existing RPC guards; unlocked settlements release those guards until relock. Active carryovers using the settlement as source block unlock/relock.
- 未完成: multi-version snapshot/history, adjustment editing, carryover automatic revoke/rebuild, historical migration/repair, whitelist test data cleanup.
- 已知限制: current unique key remains `student_id + year_month`; lock remains insert-only; unlock/relock reuse the same snapshot row and do not mutate lesson/income/account/wage/payment/expense rows. Historical maintenance remains in v1.
- 后续优先级: no immediate V1 work; future adjustment or carryover automation must be separately designed.

## 老师工资结算

- 状态标签: 只读/预览
- 完成度: 4/4
- 已完成: wage lock list and wage lock detail are read-only and complete; detail shows saved wage lock snapshot, wage lock details, and related payment requests.
- 可写入功能: none from `wage.html` / `wage-detail.html`. Teacher wage payment actions are handled by the payment module, not wage detail.
- 只读/预览功能: monthly wage lock list, teacher/business filters, wage detail snapshot, payment request references.
- guard/锁定保护: wage detail must not recalculate locks from current rules/lessons or mutate payment status. Lesson actual-from-planned and guarded edit flows guard locked teacher wage months and wage detail snapshots.
- 未完成: wage lock generation, wage lock void/relock, wage recalculation, wage detail edit.
- 已知限制: saved wage locks are treated as audit snapshots. Future wage-generation work needs a separate full write-RPC workflow.
- 后续优先级: only after lesson/settlement inputs are stable, design wage lock generation as a guarded write phase.

## 账户管理

- 状态标签: V1 可用
- 完成度: 8/9
- 已完成: account list, account transaction detail, future-use account creation, account profile update, account adjustment create/reverse, account transfer create/reverse.
- 可写入功能: create/update account profile, create/reverse account adjustment, create/reverse account transfer through `js/api/account-api.js` and `js/api/account-transaction-detail-api.js`.
- 只读/预览功能: account list, account transaction list/filter, transaction detail with linked source summaries for income, expense, payment, reimbursement, adjustment, transfer, and account origin.
- guard/锁定保护: account create fixes opening/current balance at 0 and creates no transaction; profile edit cannot alter code, business ownership, currency, opening/current balances, or historical chains. Adjustment/transfer reversal preserves audit history through reversal records/transactions.
- 编辑范围: 账户新增可填写 `account_code`, `name`, `account_type`, `currency`, `business_entity_id`, `is_company_account`, `is_active`, `note`; `opening_balance` 和 `current_balance` 固定为 `0`，不生成 `school_account_transactions`。账户资料编辑仅允许 `name`, `account_type`, `is_company_account`, `is_active`, `note`。不可编辑/受保护字段包括 `account_code`, `currency`, `business_entity_id`, `opening_balance`, `current_balance`, `app_type`, `created_at`，以及 `school_account_transactions` 和历史收入、支出、报销、支付、转账、调整、结算、工资链路；余额修正只能走已验证的 account adjustment flow。
- 未完成: standalone account transfer detail page.
- 已知限制: balance changes are intentionally limited to verified income, expense, reimbursement, payment, adjustment, and transfer flows. Account transaction detail is the current audit surface for transfers.
- 后续优先级: add standalone transfer detail only if transaction detail becomes insufficient.

## 收入记录

- 状态标签: V1 可用
- 完成度: 3/6
- 已完成: income list/detail, paid tuition income creation, received tuition income reversal from detail when guards pass.
- 可写入功能: create income record and reverse income record through API-layer RPC wrappers.
- 只读/预览功能: income list, income detail, lookup loading, settlement/account transaction references.
- guard/锁定保护: create/reverse guard against locked student settlement months and student-payment-chain-linked income; reversal preserves original income and original transaction.
- 未完成: broader income categories, edit flow, partial/payment-plan handling.
- 已知限制: first version is limited to paid tuition income. Income is not inferred from account transactions.
- 后续优先级: expand income categories only after settlement guard semantics are explicitly designed.

## 支出记录

- 状态标签: V1 可用
- 完成度: 5/9
- 已完成: expense list/detail, ordinary paid expense creation, ordinary paid expense reversal from detail, ordinary non-teacher-wage expense attachment metadata creation.
- 可写入功能: create/reverse ordinary expense and create attachment metadata through API-layer RPC wrappers.
- 只读/预览功能: expense list/detail, payment request references, reimbursement references, attachment counts/metadata display.
- guard/锁定保护: ordinary reversal cannot be used for teacher wage expenses; attachment metadata cannot be added to teacher wage expenses; reimbursed expenses must not be reversed before reimbursement reversal; original expense/transaction records are preserved.
- 未完成: storage-backed file upload/download/preview/replace/delete, OCR/extracted text, attachments during expense create, partial reimbursement support.
- 已知限制: attachment V1 is metadata-only and audit-only; it does not affect expense amount/status/account/reimbursement state or account transactions.
- 后续优先级: add real attachment storage only as a separate storage/security phase.

## 报销管理

- 状态标签: V1 可用
- 完成度: 3/7
- 已完成: reimbursement list/detail, reimbursement confirmation from candidate paid non-teacher-wage expenses, reimbursement reversal from detail.
- 可写入功能: create reimbursement record and reverse reimbursement record through API-layer RPC wrappers.
- 只读/预览功能: list/detail, candidate expense loading, reimbursement item counts, transaction counts, linked expense/account references.
- guard/锁定保护: reimbursement is not operating expense; reversal creates opposite account transactions, restores balances, and returns linked expenses to pending reimbursement without deleting records/items/original transactions.
- 未完成: edit flow, partial reimbursement, attachments, reimbursement-page statistics.
- 已知限制: current flow expects candidate paid non-teacher-wage expenses and full reversal semantics.
- 后续优先级: partial reimbursement/edit requires separate guarded design because it touches expenses, accounts, and transactions.

## 学生/老师/科目/业务归属管理

- 状态标签: V1 可用
- 完成度: 12/16
- 已完成: student, teacher, subject, and business entity readable lists; future-use profile creation; narrow profile update.
- 可写入功能: create/update student profile, teacher profile, subject profile, and business entity profile through API-layer RPC wrappers.
- 只读/预览功能: master-data list/filter surfaces and lookup sources for lesson, settlement, wage, income, expense, account, payment, and profit modules.
- guard/锁定保护: master-data writes are narrow future-use changes and must not rewrite historical lessons, settlements, wages, payments, income, expenses, accounts, balances, or account transactions. Subject `status` maps to `is_active`; subject display name maps to `name`.
- 未完成: delete/merge flows, broad contact/parent/tuition-rule editing, business entity account auto-create, business entity company-report inclusion edit.
- 已知限制: teacher edit scope is narrow; student create/update excludes balances and historical financial fields; business entity default currency changes must not imply historical rewrite.
- 后续优先级: keep master-data writes narrow; defer delete/merge to explicit audit-safe workflows.

## 工资规则

- 状态标签: V1 可用
- 完成度: 5/8
- 已完成: wage rule list, read-only detail, future-use rule config create, config edit, soft-disable/restore instead of delete.
- 可写入功能: create/update wage rule config and set active state through API-layer RPC wrappers.
- 只读/预览功能: wage rule list/detail, teacher/student/subject/business entity lookups, future-lock-only/no-history-recalculation notice.
- guard/锁定保护: create/edit/soft-disable/restore must not recalculate historical wages or mutate wage locks, wage lock details, payment requests, expenses, account balances, or account transactions; edit cannot change teacher/student/subject/business linkage; restore rejects conflicting active rules.
- 未完成: physical delete, generic student-empty rules, historical wage recalculation.
- 已知限制: first create version requires explicit teacher/student/subject/business entity. Active-state changes use the dedicated soft-disable/restore action instead of the generic edit dialog.
- 后续优先级: leave as future-lock configuration; add generic matching rules only with explicit conflict semantics.

## 导入导出

- 状态标签: 已收口
- 完成度: 8/8
- 已完成: lesson planned-only import preview, same-file duplicate detection, exact-only lookup matching, planned-only batch import submit, planned-only template export with `回数` and `课时费总额 JPY`, legacy `关联预定ID` ignored during planned import, dialog error/scroll/close behavior fixes.
- 可写入功能: planned-only lesson batch import through `school_import_lesson_records_batch`.
- 只读/预览功能: CSV/Excel parsing, preview errors/warnings, lock precheck, planned reference precheck for future actual design, template export and guide sheet.
- guard/锁定保护: any row error blocks whole-batch submit; actual/completed/cancelled/makeup_completed rows are blocked in planned-only submit; locked student settlement months are rejected; planned IDs are not written for planned-only import.
- 未完成: full actual import, history migration import, import undo, richer import result/detail navigation beyond current success links.
- 已知限制: actual examples may appear only as guide/future backlog context; current supported import is planned-only. Whitelist test data cleanup is intentionally deferred.
- 后续优先级: keep planned-only stable as the core lesson source; full actual/history migration import stays future/backlog and must be designed separately with settlement/wage guard coverage.

## Backlog / 暂不实现

- 状态标签: Backlog
- 完成度: 0/10
- 已完成: backlog boundaries are documented in `docs/system-map.md` and `docs/current-status.md`; student settlement V1 and planned-only lesson import are explicitly closed for current/future v2 operation.
- 可写入功能: none in this section.
- 只读/预览功能: docs-only tracking.
- guard/锁定保护: any future write item must use the full write-RPC workflow and API-layer boundary. Real historical-data repair, destructive cleanup, broad backfill, or non-whitelisted real-data writes remain hard stops unless separately authorized and designed.
- 未完成: historical data migration/repair, full actual import, cross-month pending-makeup completion workflow / pending-makeup pool, multi-version settlement history, settlement adjustment, carryover automatic revoke/rebuild, wage lock generation, lesson delete/restore, wage rule physical delete, payment cancel/restore/reissue retest depth, whitelist test data cleanup.
- 已知限制: v2 does not replace v1 historical maintenance. `current-status.md` notes payment cancel/restore/reissue UI/API/RPC exist, but future changes around those status actions should retest them explicitly.
- 后续优先级: first preserve completed V1 surfaces; then handle backlog as small guarded phases, with full actual import/history migration, cross-month pending-makeup pool, and wage lock generation as separate designs.
