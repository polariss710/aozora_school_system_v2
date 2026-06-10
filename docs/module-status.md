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
| 课时管理 | 已收口 | 15/15 |
| 学生月度结算 | 已收口 | 10/10 |
| 老师工资结算 | V1 可用 | 7/7 |
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
- 完成度: 15/15
- V1 边界: 课时管理 V1 基本收口。当前运营主线以 planned-only 课时导入作为核心稳定源头；当前 v2 普通新增/导入仍保持 planned-only，不恢复 v1 那种普通新增时自由选择预定/实际的宽入口。actual 生成、取消、补课完成和 linked actual 编辑都依托 planned 源头及其 guard 语义。当前运营中生成实际课时后，如发现日期、时间、金额、内容、备注等问题，优先通过 guarded edit 修正，而不是删除重建。
- 已完成: ordinary list, planned/actual paired view, DB-sourced top stats, student lesson PDF print export, detail page, planned lesson creation V1, completed/cancelled/makeup_completed actual-from-planned V1, guarded edit V1, planned-only void V1, cross-month makeup_completed API/UI V1, voided planned readonly filter/detail, lesson import preview, planned-only batch import, planned-only Excel template export, detail return-query navigation, and settlement/wage evidence links.
- 可写入功能: create planned lesson, create completed actual from planned, create cancelled actual from planned, makeup_completed actual from planned, cross-month makeup_completed actual from earlier pending_makeup planned, planned-only batch import, guarded lesson edit, planned-only void. All exposed page writes go through `js/api/lesson-api.js` and verified RPCs.
- 只读/预览功能: list, paired view, DB-sourced lesson stats, student actual/planned lesson PDF print export, detail, cross-month makeup source candidate lookup, cross-month source/target reference display, import preview, planned-ID/lock precheck for import, voided planned review, source-chain and settlement/wage reference display.
- PDF 导出样式: 2026-06-10 student lesson PDF export was updated to a parent-facing A4 print layout. Current-month actual exports use DB/API-sourced same-month planned/actual rows and DB/RPC stats, render four summary cards and planned/actual side-by-side lesson cards, and no longer output the backend-style 11-column actual table. Next-month planned exports use a compact six-column table and explicit `没有下月预定课时` empty state. Browser validation covered makeup_completed, non-billable, long content/note, non-empty next planned lessons, empty next planned lessons, Chrome `printToPDF`, and 390px no-overflow.
- guard/锁定保护: planned/actual write RPCs guard locked student settlement months and locked teacher wage months where applicable; guarded edit blocks voided rows, linked actual/source master-data changes, stale `updated_at`, settlement locks, wage locks, and wage detail snapshots; planned void blocks linked actuals, locked settlement months, stale rows, already-voided rows, invalid lesson type/status, and blank reasons.
- 当前不处理历史数据: 历史维护继续由 v1 或单独 migration/backlog 处理；full actual import 保持 future/history migration backlog，不进入当前实现。
- 跨月待补课高优先级: 已完成 DB/RPC + API/UI V1。`school_create_cross_month_makeup_completed_actual_from_planned` 选择原月份 `pending_makeup` planned，并在补课月份生成 `makeup_completed` actual，`planned_lesson_id` 指向原 planned，不复制 planned/actual，不修改来源 planned，默认 `is_billable = false` 且页面固定金额 `0`，按目标 actual 月检查学生结算锁和老师工资锁。`lesson.html` 的独立入口从目标月份打开，来源范围只列出以前月份、未作废、无 linked actual 的 `pending_makeup` planned；原月份 paired view 显示 `已于 YYYY-MM 完成`，补课月份 paired view 显示 `来源：YYYY-MM 待补课`。
- 跨月补课收口回归: 2026-06-10 rollback tests verified source-month student settlement lock is allowed when target month is unlocked, target-month student settlement lock is rejected, and target-month teacher wage lock is rejected; browser read-only regression verified linked sources disappear from candidates, source month hides `补课完成`, target/source paired references render correctly, and non-billable cross-month actuals do not enter student settlement actual fee/hours.
- 启动与筛选修复: 2026-06-10 removed the obsolete `#lessonCount` startup dependency after the stats-bar migration and consolidated create/actual/cancelled/makeup/cross-month success refresh into one filter-preserving path. Browser validation covered teacher-filtered planned->actual and cross-month completion, desktop/390px pair/list views, source/target cross-month references, and confirmed no page-layer `.rpc()` or direct insert/update/delete/upsert calls.
- 完成态 checkpoint: 2026-06-10 docs-only consistency pass explicitly marks 课时管理 V1 = 完成 / 已验证, planned-only 导入 = 完成 / 当前稳定源头, 学生月度结算 V1 = 完成 / 已验证, and 跨月补课完成登记 = 完成 / 已验证. Full actual import remains future/history migration backlog; whitelist/codex-test cleanup remains deferred cleanup.
- 未完成: free actual creation outside planned flow, full actual batch import, lesson delete, void restore, `voided_by`, expanded wage-lock lifecycle beyond the completed generation MVP, auto-matching by student/teacher/subject/date/time, same-file planned/actual linking.
- 已知限制: planned-only import accepts only planned rows with `planned` / `pending_makeup`; actual rows may still be previewed/prechecked for future design but planned-only submit blocks them. Batch import does not use teacher wage lock protection because planned rows do not set actual teacher settlement month. Lesson delete remains backlog but is not a current operational must-have because guarded edit covers ordinary post-generation corrections.
- 后续优先级: keep planned-only import, cross-month makeup completion, and teacher wage generation MVP as stable V1 surfaces; next-stage candidates are payment management follow-up enhancements, weekly plan image export, full actual import / history migration, whitelist/codex-test deferred cleanup, and DB-level linked-actual unique/index only after read-only duplicate-risk verification. Each remains a separate guarded phase.

## 学生月度结算

- 状态标签: 已收口
- 完成度: 10/10
- 已完成: V1 is closed for current/future operations: realtime preview, preview -> locked snapshot, soft unlock, same-row relock, guarded difference adjustment audit, previous locked snapshot carryover reading, list/detail status display, guard documentation, and closure self-check.
- 可写入功能: lock from preview, unlock locked settlement, relock unlocked settlement, and append posted difference adjustment records. Writes are centralized in `js/api/settlement-api.js` through `school_lock_student_monthly_settlement`, `school_unlock_student_monthly_settlement`, `school_relock_student_monthly_settlement`, and `school_apply_student_monthly_settlement_adjustment`.
- 只读/预览功能: settlement list, detail page, realtime preview rows, read-only summary RPC `school_get_student_monthly_settlement_summary`, saved snapshot detail plus matching lesson/income/adjustment references.
- guard/锁定保护: locked settlements block lesson edit, planned void, actual generation, tuition income create, and tuition income reverse through existing RPC guards; unlocked settlements release those guards until relock. Active carryovers using the settlement as source block unlock/relock and block new adjustments. Posted adjustment records block unlock/relock recalculation for that snapshot.
- 未完成: multi-version snapshot/history, adjustment reversal/void, carryover automatic revoke/rebuild, historical migration/repair, whitelist test data cleanup.
- 已知限制: current unique key remains `student_id + year_month`; lock remains insert-only; unlock/relock reuse the same snapshot row and do not mutate lesson/income/account/wage/payment/expense rows. Difference adjustment is append-only posted audit in `school_student_settlement_adjustments`; it updates only the settlement adjustment/carryover fields. Historical maintenance remains in v1.
- 后续优先级: no immediate V1 work; future adjustment reversal, carryover rebuild, or multi-version history must be separately designed.

## 老师工资结算

- 状态标签: V1 可用
- 完成度: 7/7
- 已完成: wage snapshot list and wage snapshot detail are complete; detail shows saved wage snapshot, wage details, and related payment requests. Teacher wage generation MVP is available from `wage.html` through API-layer wrapper `generateTeacherMonthlyWage` and verified RPC `school_generate_teacher_monthly_wage`. Teacher wage payment request generation from a wage snapshot is available from `wage-detail.html` through API-layer wrapper `createTeacherWagePaymentRequest` and verified RPC `school_create_teacher_wage_payment_request`.
- 可写入功能: `wage.html` can generate a teacher wage snapshot for the selected month and optional selected teacher. `wage-detail.html` can generate one pending teacher wage payment request from a non-voided generated wage snapshot that has no existing teacher_wage payment request. Page writes go through `js/api/wage-api.js` / `js/api/wage-detail-api.js`; page modules do not call `.rpc()` directly and do not directly insert/update/delete/upsert rows. Payment confirmation and payment status actions are handled by the payment module.
- 只读/预览功能: monthly wage snapshot list, default non-void list filtering with explicit `已作废` review option, teacher/business/status filters, filter-preserving detail return links, wage detail snapshot, payment request references.
- guard/锁定保护: wage detail must not recalculate snapshots from current rules/lessons or mutate payment status. Lesson actual-from-planned and guarded edit flows guard generated teacher wage months and wage detail snapshots. The generation RPC rejects existing same-teacher same-month wage records before missing-field actual validation, rejects already-wage-detailed actual lessons, missing/duplicate active wage-rule matches, planned/cancelled/voided lessons, and same-teacher same-month candidates spanning multiple business entities.
- 流程边界: v2 不提供单独的工资二次固化用户操作。生成老师工资本身就是生成并固化工资结算快照；确认金额后从工资快照生成支付请求；老师工资支付页面确认支付并选择账户；支付确认生成 teacher_wage 支出和账户流水。公司账户支付工资时支出 `reimbursement_status = not_required`；垫付/个人账户支付工资时支出 `reimbursement_status = pending`；报销流程只归还垫付账户，不再次生成 teacher_wage 工资支出。底层表名、字段名和 `status = locked` 仍是当前 schema 实现细节，不作为额外锁定步骤展示给用户。
- 历史定点修正: 2026-06-10 completed a one-time guarded reconciliation for the confirmed duplicated 2026-05 Cong Qirun / Aozora wage snapshot. Duplicate wage lock `4af1b55e-ece1-47a1-a350-5bb0f2e111ca` is now `void` with `voided_at`; duplicate payment request `c8280c86-15f9-410b-b9ac-3588b780b3b0` is `cancelled`; the older wage lock `dacc2887-f039-4dcb-861b-6ec36e51bace` and older request `a2794694-9bb0-411f-9f66-ae1fc174a646` remain effective. Effective 2026-05 wage lock count is now `locked:9 / void:13`. This was not a general wage void/relock implementation and did not change lessons, wage details, expenses, accounts, account transactions, income, or student settlements.
- 未完成: wage lock void/relock, wage recalculation/preview UI beyond the guarded generator, wage detail edit.
- 已知限制: saved wage snapshots are treated as audit snapshots. Generation MVP has no preview UI, no expense/account/income/student-settlement writes, no CNY/FX, no transport fee, and no classroom fee. Payment request generation only creates a pending request; it does not confirm payment, generate expenses, write account transactions, change account balances, write income, or write student settlements. Generated `lesson_count` equals detail row count; `is_billable=false` does not exclude teacher wage candidates.
- 后续优先级: payment confirmation remains in the existing payment module. Wage void/relock, preview UI, multi-business same-teacher-month handling, CNY/FX, transport/classroom fee handling, and historical/backfill workflows remain backlog.

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
- guard/锁定保护: reimbursement is not operating expense and must not recreate teacher wage expense. Reimbursement candidates exclude `expense_category = teacher_wage`, and `school_create_reimbursement_record` rejects teacher_wage expenses even if their `reimbursement_status = pending`. Reversal creates opposite account transactions, restores balances, and returns linked non-teacher-wage expenses to pending reimbursement without deleting records/items/original transactions.
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
- 未完成: historical data migration/repair, full actual import, multi-version settlement history, settlement adjustment, carryover automatic revoke/rebuild, expanded teacher wage-lock lifecycle beyond the completed generation MVP, lesson delete/restore, wage rule physical delete, payment management follow-up enhancements, payment cancel/restore/reissue retest depth, weekly plan image export, whitelist/codex-test deferred cleanup, and DB-level linked-actual unique/index consideration only after read-only duplicate-risk verification.
- 已知限制: v2 does not replace v1 historical maintenance. `current-status.md` notes payment cancel/restore/reissue UI/API/RPC exist, but future changes around those status actions should retest them explicitly.
- 后续优先级: first preserve completed V1 surfaces; then handle payment management follow-up enhancements, weekly plan image export, full actual import/history migration, whitelist/codex-test cleanup, DB-level linked-actual unique/index review, expanded wage-lock lifecycle, and other backlog as separate guarded phases.
