# Module Status

Status date: 2026-06-15

This is the lightweight module summary for daily sessions. It keeps only each module's current state, recent key update, current limits / hard stops, and next step. Older module history, long commit/test logs, and completed detail records are archived in `docs/archive/module-status-history.md`.

Visual dashboard: open `docs/module-status-dashboard.html` locally for a card-based static overview.

## Global Rules

- v2 opens create/edit where safe; delete, merge, destructive cleanup, historical repair, and broad backfill remain closed unless separately designed and authorized.
- Current/unclosed real business months must not be used for real wage generation, snapshot generation, student settlement closing, locking, or lock-style write validation.
- Validation priority is transaction rollback or clearly marked whitelist data (`codex-test`, `v2-test`, `sandbox`, `测试学生`, `测试老师`, `测试业务归属`).
- Student settlement, teacher wage, payment request, reimbursement, account transaction, income/expense, and lesson chains are protected. Master-data changes must not rewrite or recalculate these chains.
- Core business writes must go through API/RPC boundaries. Page modules must not call `.rpc()` directly and must not directly insert/update/delete/upsert DB rows.
- Cash linkage boundary: School records business facts and initiates external Cash requests; Cash System only accepts external requests and user approve/reject changes Cash transactions/balances. Cash must not proactively create School business records or initiate School business requests.
- Field narrowing policy:新增/编辑只保留当前实际业务使用字段；历史/预留/低频/派生/系统/交易链路字段隐藏或只读，暂不物理删除。主数据 dialog 收窄任务参考 `docs/workflows/v2-master-dialog-simplification.md`。

## Snapshot

| Module | Current state | Next priority |
| --- | --- | --- |
| 课时管理 | 已收口 | Keep planned-only V1 stable; full actual/history import stays backlog |
| 学生月度结算 | 已收口 | No immediate V1 work; future reversal/history requires new design |
| 老师工资结算 | V1 可用 | Payment flow is separate; wage lifecycle expansion remains backlog |
| 老师工资支付 | V1 可用 + all pending `teacher_wage` Cash confirmation path implemented and whitelist-tested for Cash-eligible JPY/CNY accounts; direct confirm remains historical/special exception | Real 2026-05 wage trial remains not executed |
| 账户管理 | V1 可用 + first-stage family account isolation | Account scope/household owner expansion and family ledger records require separate guarded phases |
| 收入记录 | V1 可用 + income Cash confirmation file-level implementation prepared but not DB-executed/deployed; historical personal tuition JPY Cash linkage verified; Cash linkage policy now requires all actual receipts through user-controlled accounts to enter Cash | Execute guarded income Cash SQL/deploy only after resolving documented risks and running preflight checks |
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

- 当前状态: V1 可用。支付列表可确认支付、反转已支付请求、取消 pending、恢复 cancelled、reissue reversed；详情页只读。老师工资 Cash confirmation 已从历史 personal + `teacher_wage` + JPY 扩展为所有 pending `teacher_wage` payment request。School 发起工资付款 Cash request；Cash approve 后才生成工资支出 transaction 并回写 School `paid`，Cash reject 后不生成 transaction 且 School payment request 保持 `pending`。JPY 支付支持 `日元现金`、`日元三菱卡`、`日元乐天卡`；CNY 支付支持 `余额宝`，需要输入汇率，School 保留 JPY 工资成本，Cash 扣 CNY 实付金额。青空塾归属工资也先由 Cash 账户垫付，并应能识别为 `青空塾工资垫付`；法人账户报销时在 Cash 记录 `法人账户报销 / 青空塾工资垫付报销`，School 记录 `青空塾工资垫付款已报销 / 法人账户清算`。
- 最近关键更新: 2026-06-14 增加 `school_teacher_wage_cash_confirmation_all_scope_rpc.sql` 和 `school_request_cash_payment_confirmation(...)`；放宽 linkage event JPY-only / mapping-only 约束，新增 JPY cost、payment currency、exchange rate、payment amount 快照。`request-cash-confirmation` 通过 Edge Function 读取 Cash active + `allow_school_requests = true` 账户并校验币种，不靠账户名硬编码；支付页对所有 pending `teacher_wage` 显示 `提交到 Cash 确认`，选择 CNY 账户时要求汇率并预览人民币实付金额。Cash rejected 为终态且不可重新 approve；School payment request 保持 pending，显示拒绝理由，并可重新提交生成新的 attempt / Cash request；同一 payment request 同时只能有一个 active attempt。School rollback、Cash JPY/CNY request rollback、rejected -> retry -> approved 后端 E2E 已通过，测试仅使用 2026-06 codex-test teacher-wage 数据，cleanup 后 School/Cash 残留 0。`直接确认支付` 保留为历史/特殊例外，文案明确不会进入 Cash。真实 2026-05 工资试运行尚未执行。
- 当前限制 / hard stop: 支付链路仍不得删除 payment request、wage lock、expense、account transaction。Cash confirmation 提交不改 `paid`、不写 `paid_at`、不创建 School expense、不中转 Cash transaction；Cash transaction 只能由 Cash approve 产生。跨 DB 强事务、历史 backfill、撤销同步、自动后台任务、法人账户清算 UI、利润统计口径改造仍需单独 guarded phase。
- 下一步: 真实 2026-05 工资试运行另行执行；浏览器自动化仍不稳定时，页面路径可人工操作并配合 DB 验证。未来改 payment status actions 时，显式重测 cancel/restore/reissue 和 confirm/reverse 链路；如需真正开放支付记录编辑，必须先设计独立 edit RPC/API guard。

## 账户管理

- 当前状态: V1 可用，已完成 account/family first-stage `app_type` 隔离。账户列表、账户交易详情、账户新增、账户资料编辑、账户调整/反转、账户转账/反转已可用；账户管理默认 `school` 视图，可筛选/标识 `school` / `store` / `family`。
- 最近关键更新: 2026-06-13 增加 `school_create_account_profile(..., p_app_type)` 和 `school_update_account_profile(..., p_app_type)` 重载，保留旧重载。账户页新增“账户用途”筛选和 create/edit 用途字段；`school` / `family` 可新增/编辑，`store` 本阶段只展示/筛选不编辑。Family 账户强制 `business_entity_id = NULL`、`is_company_account = false`，资料编辑不能改 `app_type`，新增/编辑不创建账户流水。页面版本为 `v2.109.0-account-app-type-isolation-20260613`。同日已清理 first-stage whitelist commit-test family 账户 `d3734cd7-fa94-4be3-b8dc-3cdc3690f667` / `codex-test-family-app-type-commit-20260613`，residue 为 0。2026-06-12 账户新增/编辑 dialog 已按实际业务收窄；`account_code` 由 RPC 生成并隐藏；初始余额只在新增填写；当前余额只在账户卡片展示且不在资料 dialog 编辑。
- 当前限制 / hard stop: 不开放 account code、系统字段、created/updated timestamps、current balance 编辑、交易流水、历史收入/支出/报销/支付/转账/调整/结算/工资链路派生字段。Family 账户本阶段只是后续家庭账本可用的账户主数据，不进入 school 收入、支出、支付、报销、工资、学生结算、利润分析、账户调整或账户转账候选。新增初始余额只初始化 `opening_balance/current_balance`，不创建账户流水；已有账户流水后 RPC 拒绝改币种，避免历史流水币种不一致。余额变化只能走 verified income/expense/reimbursement/payment/adjustment/transfer flows；family ledger 收支/转账尚未实现。
- 下一步: `account_scope`、household/member owner、family income/expense/transfer records、family summary、余额调整 / 期初修正需另开 guarded implementation phase；只有当 account transaction detail 不够用时再补 standalone transfer detail。

## 收入记录

- 当前状态: V1 可用。收入列表/详情、received income create/edit/reversal 已可用。Income Cash confirmation 已完成代码/SQL 文件级准备，但 SQL 尚未执行、Edge Function 尚未部署、真实收入测试尚未做。
- 最近关键更新: 2026-06-15 补全文档口径：收入请求 / income request 是 School 业务侧“这笔收入应该收”的事实，不代表真实到账，也不改变 Cash 余额；Cash 入账确认请求 / cash receipt confirmation request 是把 income request 提交给 Cash System 等待用户 approve/reject。Cash approve 后才生成 `home_jpy_transactions` / `home_cny_transactions`、Cash 余额增加、School income received / settled；Cash reject 后不生成 transaction、不改变余额、School income 保持 pending 且可 retry。当前 commit `2fe6ae8` 已准备 `school_income_cash_confirmation_workflow.sql`、`request-cash-income-confirmation`、`sync-cash-request-result` income 分派和相关 School RPC，但执行前必须处理已记录的兼容风险。
- 当前限制 / hard stop: 普通收入路径仍按 V1。不得在 SQL 未执行 / Edge Function 未部署前做真实 Cash System 收入测试。执行 `school_income_cash_confirmation_workflow.sql` 前必须做 preflight：现有 income linkage `sync_status` 分布、income `status` 分布、旧 `pending` linkage 兼容、旧 personal tuition Cash RPC 是否保留、detail/update/reverse 是否扩展到 `income_received`。CNY/JPY 换汇、账户调拨、支付宝与日元现金/银行之间的资金调配暂时不由 School 自动处理；School 只记录业务收入/工资结算口径，Cash 手动记录换汇/账户调拨。不从 account transaction 反推收入；不删除收入；不重算 locked student settlement。
- 下一步: 在 guarded workflow 下修正并执行 income Cash SQL、部署 Edge Functions、做 rollback/whitelist verification，然后再处理真实收入。Tuition income reverse sync、CNY/RMB request integration、青空塾代收清算、自动调度、部分收款、付款计划、旧流水修正、跨账户收入迁移、结算外费用是否进入学生账单，均需另开 guarded design。

## 个人外部私塾打工收入

- 当前状态: 设计已补全，尚未实装。详见 `docs/personal-teaching-income-module-design.md`。
- 业务定位: 用户个人在外部私塾授课 / 打工产生的个人业务收入。外部私塾是付款方；用户是授课者 / 打工者。该模块不是青空塾老师工资支出模块，不进入青空塾老师工资结算，不创建 `teacher_wage` payment request。
- 课时模型: 使用 planned + actual，但不复用现行青空塾 lesson 的 cancel / makeup / makeup_completed / `is_billable` 复杂状态。Planned 可自由新增、编辑、删除；唯一动作是生成 actual。如果没上课，删除 planned；如果 planned 已生成 actual，删除需要二次确认作为业务保护。
- 月度流程: 日常录入 planned -> 上课后生成 actual -> 月末核对 actual -> 计算 `actual_hours * hourly_rate + transportation_fee + allowance - deduction` -> 锁定月度结算 -> 生成 `personal_teaching_income_request` -> 提交 Cash 入账确认 -> Cash approve 后余额增加并标记 income request / settlement received / settled；Cash reject 后 request pending / retryable。
- 与 teacher_wage Cash 化区别: teacher_wage 是支出、payment request、Cash approve 后余额减少、School payment request paid；personal teaching income 是收入、income / receipt request、Cash approve 后余额增加、School income request received / settled。可复用 attempt、active attempt unique guard、rejected retry、idempotency、Cash external request、approve/reject callback、JPY/CNY transaction 分流；不可复用 payment 命名、支出方向、paid 语义、老师工资结算表或 teacher_wage 专用字段。
- 下一步: 仅在 income Cash confirmation SQL/Edge Function 链路稳定后，再另开 guarded implementation phase 设计表结构、RPC、页面、结算锁定、Cash request 提交和回写。

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
- 当前限制 / hard stop: 不写 DB，不调整源记录，不重算 payment/settlement/wage。利润只看真实经营收入和真实经营支出：学费收入、老师工资、真实业务支出计入利润；Cash 转给法人账户、法人账户报销 Cash、CNY/JPY 换汇、用户账户之间调拨、代收款清算、垫付款回收不计入利润，也不要记为新的学费收入或新的利润收入。
- 下一步: 保持只读；未来改筛选/drilldown 时重测只读边界。

## Backlog / 暂不实现

- 当前状态: Backlog。历史维护继续由 v1 或单独 migration/repair workflow 处理。
- 最近关键更新: 2026-06-15 个人外部私塾打工收入模块设计已新增为 `docs/personal-teaching-income-module-design.md`，定位为个人业务收入和 Cash 入账确认链路，不是青空塾 teacher_wage 支出。2026-06-14 Cash linkage 业务口径已从 personal-only/JPY-only 修正为“实际经过用户控制账户的钱都进入 Cash；School 保存业务归属；Cash 保存资金账户变化”。旧 Phase 1/2 personal JPY 实现记录保留为历史验证结果，但不再作为业务边界。账户/家庭账本账户联动已完成第一阶段 `app_type` 隔离实装；后续 account_scope、household/member ownership、family income/expense/transfer、family reporting 仍是 backlog。first-stage whitelist commit-test family 账户 `d3734cd7-fa94-4be3-b8dc-3cdc3690f667` / `codex-test-family-app-type-commit-20260613` 已经 dry-run、rollback validation、commit delete、residue check 清理完成。打工/兼职工资记录模块设计 `docs/part-time-wage-record-module-design-2026-06-12.md` 已完成但未实装。
- 当前限制 / hard stop: destructive cleanup、真实历史修复、广义 backfill、非 whitelist real-data writes、delete/merge、物理删除、全量重算均不是默认工作。
- 下一步候选: unified Cash linkage implementation alignment、School 读取 Cash eligible account whitelist、青空塾代收学费 Cash 标记与法人清算、青空塾工资垫付与法人报销、CNY/RMB School request integration、manual FX/account-transfer runbook、Cash-linked reversal sync / retry UI、payment management follow-up、weekly plan image export、full actual import/history migration、expanded wage-lock lifecycle、teacher wage adjustment items for transport/classroom fees、payment-request realtime exchange-rate CNY conversion、account_scope/household owner expansion、family ledger records/reporting、part-time wage records、account balance adjustment / opening-balance correction、business-entity-scoped wage generation、DB-level linked-actual unique/index after read-only duplicate-risk verification。
