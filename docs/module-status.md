# Module Status

Status date: 2026-06-13

This is the lightweight module summary for daily sessions. It keeps only each module's current state, recent key update, current limits / hard stops, and next step. Older module history, long commit/test logs, and completed detail records are archived in `docs/archive/module-status-history.md`.

Visual dashboard: open `docs/module-status-dashboard.html` locally for a card-based static overview.

## Global Rules

- v2 opens create/edit where safe; delete, merge, destructive cleanup, historical repair, and broad backfill remain closed unless separately designed and authorized.
- Current/unclosed real business months must not be used for real wage generation, snapshot generation, student settlement closing, locking, or lock-style write validation.
- Validation priority is transaction rollback or clearly marked whitelist data (`codex-test`, `v2-test`, `sandbox`, `测试学生`, `测试老师`, `测试业务归属`).
- Student settlement, teacher wage, payment request, reimbursement, account transaction, income/expense, and lesson chains are protected. Master-data changes must not rewrite or recalculate these chains.
- Core business writes must go through API/RPC boundaries. Page modules must not call `.rpc()` directly and must not directly insert/update/delete/upsert DB rows.
- Field narrowing policy:新增/编辑只保留当前实际业务使用字段；历史/预留/低频/派生/系统/交易链路字段隐藏或只读，暂不物理删除。主数据 dialog 收窄任务参考 `docs/workflows/v2-master-dialog-simplification.md`。

## Snapshot

| Module | Current state | Next priority |
| --- | --- | --- |
| 课时管理 | 已收口 | Keep planned-only V1 stable; full actual/history import stays backlog |
| 学生月度结算 | 已收口 | No immediate V1 work; future reversal/history requires new design |
| 老师工资结算 | V1 可用 | Payment flow is separate; wage lifecycle expansion remains backlog |
| 老师工资支付 | V1 可用 + personal Cash Phase 1 verified; v2 pending-request confirmation planned | Page-driven Cash request/approve/reject flow is next separate guarded phase |
| 账户管理 | V1 可用 + first-stage family account isolation | Account scope/household owner expansion and family ledger records require separate guarded phases |
| 收入记录 | V1 可用 + Phase 2 personal tuition Cash linkage verified + sync status/retry UI | Future Cash request/approve/reject flow should share the v2 pending-request architecture |
| 支出记录 | V1 可用 | Keep edit guards narrow; exchange rate is optional; real attachment storage is separate |
| 报销管理 | V1 可用 | Partial/edit requires separate guarded design |
| 学生/老师/科目/业务归属管理 | V1 可用 | Keep master-data writes narrow; delete/merge deferred |
| 工资规则 | V1 可用 | Keep future-lock config; generic matching rules need explicit semantics |
| 导入导出 | 已收口 | Planned-only import stable; full actual/history import deferred |
| 利润分析 | 只读完成 | Keep read-only |
| Backlog / 暂不实现 | Backlog | Separate guarded phases only; account/family ledger and part-time wage designs exist |

## 课时管理

- 当前状态: V1 已收口。普通列表、左右对应视图、DB/RPC 顶部统计、详情页、父母向け学生课时 PDF、planned-only 手动新增、completed/cancelled/makeup_completed actual-from-planned、跨月补课完成、planned-only 批量导入、guarded edit、planned-only void 都已完成。
- 最近关键更新: 学生线 RC 自检确认启动、筛选保留、PDF 导出、settlement/wage evidence links、390px 无横向溢出和 page/API/RPC 边界。
- 当前限制 / hard stop: 不开放 free actual creation、full actual batch import、lesson delete、void restore、历史迁移/修复。planned-only import 只接受 planned/pending_makeup；actual rows 仍是 future design。
- 下一步: 保持 planned-only import 和跨月补课稳定；full actual/history import、linked-actual unique/index、删除/恢复另开 guarded phase。

## 学生月度结算

- 当前状态: V1 已收口。支持 realtime preview、pre-lock adjustment draft、lock/unlock/relock、locked readonly adjustment audit、previous locked carryover、list/detail status display。
- 最近关键更新: 下游 teacher wage blocker 已加入；同学生/月 actual lesson 进入非 void 工资快照、支付请求、paid expense、account transaction 后，unlock/relock/draft adjustment 会被 DB guard 拒绝。
- 当前限制 / hard stop: 不做 multi-version history、post-lock adjustment edit、adjustment reversal/void、carryover automatic rebuild、历史迁移/修复或 whitelist cleanup。
- 下一步: 无即时 V1 工作；任何 reversal/history/carryover rebuild 都必须单独设计。

## 老师工资结算

- 当前状态: V1 可用。工资快照列表/详情、工资明细调整、勤务申报表 Excel、工资生成 MVP、从工资快照生成支付请求已可用。
- 最近关键更新: UI/docs 口径已统一为“生成工资快照”，不是额外的用户锁定步骤；payment request generation 从快照创建 pending teacher_wage payment request。
- 当前限制 / hard stop: 不做实时工资预览、广义重算、CNY/FX、generation-time transport/classroom fees、历史 backfill。当前/未结真实月份不得用于真实工资生成或快照验证。
- 下一步: payment confirmation 属于支付模块；wage void/relock、business-entity-scoped generation、preview UI 和历史工作另开阶段。

## 老师工资支付

- 当前状态: V1 可用。支付列表可确认支付、反转已支付请求、取消 pending、恢复 cancelled、reissue reversed；详情页只读。个人业务 Cash System linkage Phase 1 已验证：Cash-side external JPY RPC、school-side mapping/outbox schema/RPC/API、payment confirm 到 school pending outbox、手动同步器写入 Cash JPY transaction 并回写 school synced。Cash linkage v2 的 School 侧 request lifecycle SQL/RPC 已 apply 并通过 ROLLBACK 验证；老师工资支付页已完成第一段 School-only 嵌入式请求入口：personal + `teacher_wage` + JPY 的 pending 请求选择 Cash 支付账户后调用 `school_request_personal_cash_payment_confirmation(...)`，只生成/复用 School `pending_cash_request` linkage event，不把 payment request 改为 `paid`。Edge Function 桥接代码已加入 `supabase/functions/request-cash-confirmation/`，但尚未部署、尚未接入页面，Cash pending request 创建和 approve/reject 后回写 School 仍未实现。该手动同步器是验证/运维工具，不是最终日常业务入口。
- 最近关键更新: 2026-06-13 修正 v2 UI 方向并完成第一步页面调整：不新增独立 School 同步入口。personal + `teacher_wage` + JPY 的支付动作在老师工资支付页面内选择 Cash 支付账户，按钮文案使用 `提交到 Cash 确认`，弹窗说明该操作不是支付完成；Cash System 确认后才会记账并完成支付，拒绝时不会改变 Cash 余额且 School 侧仍保持未支付。当前页面只进入 School `pending_cash_request`，还不会创建 Cash pending request；Edge Function `request-cash-confirmation` 后续作为该业务按钮背后的安全桥接，只创建 Cash pending request，不创建 Cash transaction，不把 payment request 改为 `paid`。
- 当前限制 / hard stop: 不删除 payment request、wage lock、expense、account transaction。青空塾确认支付路径必须保持现有 school account/expense/account transaction 行为。最终 Cash linkage v2 目标不是 School 直接创建 Cash transaction，也不是普通用户进入独立同步页，而是老师工资支付页内选择 Cash 支付账户并提交 Cash 确认；approve 后才生成 Cash transaction 并改变 Cash 余额，reject 后不生成 Cash transaction 且 School 显示 `Cash已拒绝` 或保持未支付。继续排除 Cash CNY、报销、法人账户、学费收入、兼职工资、撤销同步、自动后台任务、跨 DB 强事务或历史 backfill。已 synced 的个人业务支付若要撤销，应继续阻断，直到 reversal sync 独立实现。
- 下一步: 未来改 payment status actions 时，显式重测 cancel/restore/reissue 和 confirm/reverse 链路；如需真正开放支付记录编辑，必须先设计独立 edit RPC/API guard。personal Cash linkage v2 后续阶段是 Edge Function 部署/配置并替换当前 School-only 请求调用、Cash pending request 创建、Cash approve/reject 后的 School confirmed/rejected 回写 RPC、5 月两笔 JPY 老师工资 approve/reject 试运行；仍不做跨 DB 强事务。

## 账户管理

- 当前状态: V1 可用，已完成 account/family first-stage `app_type` 隔离。账户列表、账户交易详情、账户新增、账户资料编辑、账户调整/反转、账户转账/反转已可用；账户管理默认 `school` 视图，可筛选/标识 `school` / `store` / `family`。
- 最近关键更新: 2026-06-13 增加 `school_create_account_profile(..., p_app_type)` 和 `school_update_account_profile(..., p_app_type)` 重载，保留旧重载。账户页新增“账户用途”筛选和 create/edit 用途字段；`school` / `family` 可新增/编辑，`store` 本阶段只展示/筛选不编辑。Family 账户强制 `business_entity_id = NULL`、`is_company_account = false`，资料编辑不能改 `app_type`，新增/编辑不创建账户流水。页面版本为 `v2.109.0-account-app-type-isolation-20260613`。同日已清理 first-stage whitelist commit-test family 账户 `d3734cd7-fa94-4be3-b8dc-3cdc3690f667` / `codex-test-family-app-type-commit-20260613`，residue 为 0。2026-06-12 账户新增/编辑 dialog 已按实际业务收窄；`account_code` 由 RPC 生成并隐藏；初始余额只在新增填写；当前余额只在账户卡片展示且不在资料 dialog 编辑。
- 当前限制 / hard stop: 不开放 account code、系统字段、created/updated timestamps、current balance 编辑、交易流水、历史收入/支出/报销/支付/转账/调整/结算/工资链路派生字段。Family 账户本阶段只是后续家庭账本可用的账户主数据，不进入 school 收入、支出、支付、报销、工资、学生结算、利润分析、账户调整或账户转账候选。新增初始余额只初始化 `opening_balance/current_balance`，不创建账户流水；已有账户流水后 RPC 拒绝改币种，避免历史流水币种不一致。余额变化只能走 verified income/expense/reimbursement/payment/adjustment/transfer flows；family ledger 收支/转账尚未实现。
- 下一步: `account_scope`、household/member owner、family income/expense/transfer records、family summary、余额调整 / 期初修正需另开 guarded implementation phase；只有当 account transaction detail 不够用时再补 standalone transfer detail。

## 收入记录

- 当前状态: V1 可用。收入列表/详情、received income create/edit/reversal 已可用。
- 最近关键更新: 2026-06-13 完成 Phase 2 personal-business tuition income -> Cash System JPY income E2E linkage，并新增 Cash sync 状态/重试 UI 和手动同步运维说明。已执行 Cash guard SQL、school DB foundation SQL、create RPC、sync executor、income entry UI/API、income detail guard 和普通 edit/reverse RPC guard。已验证路径为 personal business `tuition` JPY income -> `school_personal_cash_income_linkage_events` pending -> `scripts/sync-personal-cash-linkage.zsh` -> Cash `home_jpy_transactions.transaction_type = income` -> school event `synced`。v2 修正方向是收入记录页面自身完成 Cash 联动：personal + `tuition` + JPY 时直接选择 Cash 收款账户（例如支付宝账户 / 日元账户），提交收入记录即创建 school income record 并提交 Cash 确认请求；不新增独立同步按钮，不向普通用户暴露 sync executor / pending event 术语。业务状态显示应使用 `Cash待确认` / `Cash已确认` / `Cash已拒绝`。当前 zsh 同步是验证/运维脚本，不是最终业务入口。ROLLBACK 白名单测试验证 create/reject/edit-reverse guard；COMMIT E2E 验证 Cash transaction 数量保持 1、sync 幂等、school event synced 回写、无 `school_account_transactions`、不更新 `school_accounts.current_balance`；随后清理 Phase 2 E2E `codex-test-personal-cash-tuition-e2e-20260613` 残留，Cash target account/transaction、School target business/student/mapping/income/event、`home_cny_transactions` marker 均为 0。2026-06-12 收入新增/编辑字段统一；账户币种不再作为 dialog 输入，改由入账账户决定并由 RPC 校验。
- 当前限制 / hard stop: 普通收入路径仍按 V1：非 Cash path 会写入收入记录、账户余额和账户流水；Phase 2 personal Cash path 仅支持 personal + tuition + JPY + active `flow_type = tuition_income` Cash mapping，且不处理 青空塾、CNY、报销、法人账户、非学费收入或兼职工资。不从 account transaction 反推收入；不删除收入；不重算 locked student settlement。普通 edit/reverse 仅允许没有 Cash income linkage event 的普通收入；已进入 Cash linkage 的 tuition income 在 Phase 2 v1 中禁止普通 edit/reverse。普通收入编辑仍要求未撤销、非学生收款链路、未被锁定学生月结阻挡、原始 `income_adjust` 流水唯一且一致、且该流水仍是账户最新流水；不允许直接更换入账账户，旧流水或复杂账户链路应撤销后重新新增。Reversal 必须保留原收入和原交易。
- 下一步: Tuition income reverse sync、自动调度 sync executor、部分收款、付款计划、旧流水修正、跨账户收入迁移、结算外费用是否进入学生账单，均需另开 guarded design。自动调度需单独比较 cron / GitHub Actions / Supabase Edge Function / 本地 launchd，并设计密钥管理、日志告警、重试策略和防重复执行。

## 支出记录

- 当前状态: V1 可用。支出列表/详情、ordinary paid expense create/edit/reverse、ordinary non-teacher-wage expense attachment metadata 已可用。
- 最近关键更新: 2026-06-13 支出新增/编辑的 `exchange_rate` 改为可选：空白和 `0` 提交为 `NULL`，正数正常提交，负数或非数字才阻断；编辑回填 DB `NULL` 时保持空白。页面版本/cache-bust 更新到 `v2.108.0-expense-exchange-rate-optional-20260613`，并已用 mock Supabase 的实际新增/编辑页面路径验证四种输入。2026-06-12 支出新增/编辑 dialog 已收窄并统一。开放字段为 `expense_date`, `business_entity_id`, `account_id`, `expense_category`, `amount`, `description`, `payment_method`（`cash`, `bank_transfer`, `card`, `alipay`）, `receipt_status`, `reimbursement_status`, `tax_category`, `exchange_rate`, `note`。隐藏 `account currency`, `is_business_expense`, `teacher_id`, `student_id`；币种由付款账户派生，普通新增默认 `is_business_expense = true`，隐藏 legacy/低频字段暂不物理删除。详情页隐藏来源支付请求和账户流水展示块，保留报销信息和附件信息。
- 当前限制 / hard stop: ordinary reversal/edit 不得用于 teacher_wage expenses、来源支付请求生成的支出、已撤销支出、已报销支出或已进入报销链路的支出。编辑必须有且只有一条匹配原始 `expense_adjust` 账户流水，且该流水仍是账户最新流水；已出账支出暂不允许更换付款账户，需撤销后重新新增。Teacher_wage expense 不得加 ordinary attachment metadata；已报销 expense 必须先反转报销才能反转支出。不得删除 expense records、attachments、payment requests 或 original transactions。
- 下一步: Supabase Storage 文件上传/下载/预览/替换/删除和 OCR 另开 storage/security phase。调查结论：`school-expense-files` bucket 和附件表 storage 字段存在，但当前 `school_create_expense_attachment_metadata` 只创建 metadata-only 占位路径，没有上传/替换生命周期 RPC；本轮不开放真实上传/预览/替换。

## 报销管理

- 当前状态: V1 可用。报销列表/详情、从候选 paid non-teacher-wage expenses 生成报销、报销反转已可用。
- 最近关键更新: 报销仅归还垫付账户，不是 operating expense，也不能再次生成 teacher_wage expense。
- 当前限制 / hard stop: 不支持 edit、partial reimbursement、attachments、reimbursement-page statistics。不得删除报销记录/items/original transactions。
- 下一步: partial/edit 需要单独 guarded design，因为会触及 expenses、accounts、transactions。

## 学生/老师/科目/业务归属管理

- 当前状态: V1 可用。学生、老师、科目、业务归属列表可读；future-use profile create/update 已通过 API/RPC 边界开放。
- 最近关键更新: 2026-06-12 已完成学生、老师、业务归属、科目 dialog 收缩；科目卡片不再显示颜色 swatch、颜色代码或三级分类。业务归属默认币种经只读验证不影响主业务链路，现隐藏保留。
- 当前开放字段:
  - 学生: `name`, `business_entity_id`, `course_track`, `preset_exchange_rate`, `wechat`, `phone`, `entrance_date`, `target_schools` 最多 3 个, `note`。
  - 老师: `name`, `department`, `default_subject_id`, `default_business_entity_id`, `status`, `note`, `alipay_account`, `wechat_account`, `bank_name`, `bank_branch_code`, `bank_branch_name`, `bank_account_number`。
  - 科目: `name`, `is_active`, `primary_category`（`班课` / `VIP`）, `category`（`学部进学` / `大学院进学` / `资格考对策` / `特殊课程`）, `sort_order`, `note`。隐藏保留 `tertiary_category` 和 `color`；新增传空，编辑保留原值。
  - 业务归属: `name`, `entity_type`, `is_active`, `note`；create RPC 生成系统 code，隐藏 `default_currency = JPY`。
- 当前限制 / hard stop: 不开放 delete/merge；不改学生/老师编号、display-name variants、读音、目标类型、默认币种、工资币种、支付币种、默认时给、科目三级分类/颜色、余额、结算、学费规则、历史课时、工资、支付、收入/支出、账户流水、公司报表等系统/派生/历史/交易链路字段。
- 下一步: 保持 master-data writes narrow。学生 contact/guardian/birthday 或 tuition-rule、老师 legacy contact/payment defaults、业务归属 company-report/defaulting 如要重开，必须单独设计。

## 工资规则

- 当前状态: V1 可用。工资规则列表、只读详情、future-use rule create/edit、soft-disable/restore 已可用。
- 最近关键更新: 2026-06-12 工资规则新增/编辑 dialog 已收窄为 matching keys、结算类型、日元/人民币时薪和备注；汇率、交通费、教室费、启用状态 select、编辑摘要不再暴露在新增/编辑 dialog。隐藏 DB/RPC 字段暂保留：新增传 `0`，编辑保留原值，`no_wage` 时按 RPC 规则传 `0`。`is_active` 仍通过停用/恢复专用 action 修改。
- 当前限制 / hard stop: 不物理删除；不重算 historical wages；不改 wage locks/details、payment requests、expenses、account balances、account transactions。restore 必须拒绝冲突 active rules。工资规则暂不维护交通费、教室费或日常汇率。
- 下一步: 保持 future-lock config 口径；交通费/教室费后续进入老师工资结算调整项设计；支付请求生成时实时汇率换算人民币金额另开设计；generic student-empty rules 或更复杂匹配需独立冲突语义设计。

## 导入导出

- 当前状态: 已收口。planned-only lesson import preview/submit/template、same-file duplicate detection、exact lookup matching、teacher duty report Excel export 已可用。
- 最近关键更新: 学生课时 PDF 与老师勤务申报表均已做浏览器/文件验证，导出不写 DB。
- 当前限制 / hard stop: 当前导入仅支持 planned rows；actual rows、history migration import、import undo、复杂结果导航均不开放。
- 下一步: planned-only 保持稳定；full actual/history migration import 必须另开包含 settlement/wage guards 的设计。

## 利润分析

- 当前状态: 只读完成。支持月份、业务归属、币种筛选和收入/支出 drilldown。
- 最近关键更新: 读取 effective received income 和 paid expense；reversed income/expense 排除；teacher_wage expense 通过 paid expense 计入。
- 当前限制 / hard stop: 不写 DB，不调整源记录，不重算 payment/settlement/wage，不把 reimbursement/account adjustment/transfer 等 audit-only transaction 当经营利润。
- 下一步: 保持只读；未来改筛选/drilldown 时重测只读边界。

## Backlog / 暂不实现

- 当前状态: Backlog。历史维护继续由 v1 或单独 migration/repair workflow 处理。
- 最近关键更新: 2026-06-13 个人业务 Cash System linkage 已完成 Phase 1 E2E 同步器；reversal sync、retry UI/操作面、测试数据清理或正式配置迁移仍是 backlog。设计边界仍为 Phase 1 只做个人业务老师工资 JPY 支付联动，不做青空塾、报销、法人账户、CNY、学费收入、兼职工资、跨 DB 强事务、自动重试后台任务、撤销同步或历史 backfill。账户/家庭账本账户联动已完成第一阶段 `app_type` 隔离实装；后续 account_scope、household/member ownership、family income/expense/transfer、family reporting 仍是 backlog。first-stage whitelist commit-test family 账户 `d3734cd7-fa94-4be3-b8dc-3cdc3690f667` / `codex-test-family-app-type-commit-20260613` 已经 dry-run、rollback validation、commit delete、residue check 清理完成。打工/兼职工资记录模块设计 `docs/part-time-wage-record-module-design-2026-06-12.md` 已完成但未实装。
- 当前限制 / hard stop: destructive cleanup、真实历史修复、广义 backfill、非 whitelist real-data writes、delete/merge、物理删除、全量重算均不是默认工作。
- 下一步候选: personal-business Cash System reversal sync / retry UI / cleanup、payment management follow-up、weekly plan image export、full actual import/history migration、expanded wage-lock lifecycle、teacher wage adjustment items for transport/classroom fees、payment-request realtime exchange-rate CNY conversion、account_scope/household owner expansion、family ledger records/reporting、part-time wage records、account balance adjustment / opening-balance correction、business-entity-scoped wage generation、DB-level linked-actual unique/index after read-only duplicate-risk verification。
