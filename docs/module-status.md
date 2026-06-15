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
| 老师工资支付 | Legacy V1 可用；canonical 支出记录链路准备中，旧 `school_payment_requests` 直连 Cash 暂保留 | 后续将 teacher_wage 改为 `school_expense_records` -> Cash request，pending 迁移另开阶段 |
| 账户管理 | V1 可用 + first-stage family account isolation + account filter simplified; `吴个人结算账户人民币` cleaned, `吴个人结算账户日元` deferred | Account scope/household owner expansion and family ledger records require separate guarded phases |
| 收入记录 | V1 可用 + income Cash confirmation SQL/RPC installed, Edge Functions deployed, first real CNY whitelist tests passed; filters simplified | Future work: reversal sync, scheduling, broader income module integrations, and personal external teaching income implementation |
| 支出记录 | V1 可用 + teacher_wage canonical route 模型准备中 | 下一步实现 expense -> Cash request，再迁移/禁用旧 teacher_wage payment request 入口 |
| 报销管理 | V1 可用 | Partial/edit requires separate guarded design |
| 学生/老师/科目/业务归属管理 | V1 可用 | Keep master-data writes narrow; delete/merge deferred |
| 工资规则 | V1 可用 | Keep future-lock config; generic matching rules need explicit semantics |
| 导入导出 | 已收口 | Planned-only import stable; full actual/history import deferred |
| 利润分析 | 只读完成 | Keep read-only |
| 私塾打工 | Workflow V1 已安装 / 预计工资、锁定后 Excel 导出、专用 Cash pending request 链路已接入 | Cash UI 确认 2026-05 诺应教育 pending request 后验证回写 |
| Backlog / 暂不实现 | Backlog | Separate guarded phases only; account/family ledger and broader personal teaching income designs remain |

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

- 当前状态: Legacy V1 可用。支付列表仍可确认支付、反转已支付请求、取消 pending、恢复 cancelled、reissue reversed；详情页只读。按 `docs/business-flow-canonical.md`，该链路已被标记为待收敛 legacy：老师工资后续应先生成 `school_expense_records`，再由支出记录发 Cash request。旧 `school_payment_requests` -> Cash 直连暂不删除、不禁用、不迁移。
- 最近关键更新: 2026-06-14 增加 `school_teacher_wage_cash_confirmation_all_scope_rpc.sql` 和 `school_request_cash_payment_confirmation(...)`；放宽 linkage event JPY-only / mapping-only 约束，新增 JPY cost、payment currency、exchange rate、payment amount 快照。`request-cash-confirmation` 通过 Edge Function 读取 Cash active + `allow_school_requests = true` 账户并校验币种，不靠账户名硬编码；支付页对所有 pending `teacher_wage` 显示 `提交到 Cash 确认`，选择 CNY 账户时要求汇率并预览人民币实付金额。Cash rejected 为终态且不可重新 approve；School payment request 保持 pending，显示拒绝理由，并可重新提交生成新的 attempt / Cash request；同一 payment request 同时只能有一个 active attempt。School rollback、Cash JPY/CNY request rollback、rejected -> retry -> approved 后端 E2E 已通过，测试仅使用 2026-06 codex-test teacher-wage 数据，cleanup 后 School/Cash 残留 0。`直接确认支付` 保留为历史/特殊例外，文案明确不会进入 Cash。真实 2026-05 first small-batch JPY trial passed for 吴峰 `36,000 JPY` through `日元乐天卡`: Step 1 created a pending Cash external request, Step 2 approved it, wrote `home_jpy_transactions`, reduced Cash balance by `36,000`, marked School payment request paid, synced attempt/linkage, and reconciled paid / approved / transaction. Cash request display text was later improved so teacher-wage description shows teacher + month and note can show student details.
- 当前限制 / hard stop: 支付链路仍不得删除 payment request、wage lock、expense、account transaction。Cash confirmation 提交不改 `paid`、不写 `paid_at`、不创建 School expense、不中转 Cash transaction；Cash transaction 只能由 Cash approve 产生。跨 DB 强事务、历史 backfill、撤销同步、自动后台任务、法人账户清算 UI、利润统计口径改造仍需单独 guarded phase。
- 下一步: 先完成 canonical 支出记录链路：locked teacher wage -> `school_expense_records` -> expense Cash request -> Cash approve/reject -> expense writeback。7 条 pending `teacher_wage` payment request 和 1 条旧直连造成的 paid expense 缺口不在本阶段处理，后续单独迁移/清理策略。

## 账户管理

- 当前状态: V1 可用，已完成 account/family first-stage `app_type` 隔离。账户列表、账户交易详情、账户新增、账户资料编辑、账户调整/反转、账户转账/反转已可用；账户管理默认 `school` 视图，可筛选/标识 `school` / `store` / `family`。
- 最近关键更新: 2026-06-15 账户管理筛选已精简，移除“流水类型”筛选但保留账户列表和流水展示。数据清理已删除 `吴个人结算账户人民币` 及其 1 条 adjustment、8 条历史/测试账户流水，删除后账户 orphan reference 为 0，且 `GMOあおぞらネット銀行`、`包垫付金额`、`吴垫付金额` 均保留。`吴个人结算账户日元` 只读调查显示仍有 2026-02～2026-06 正式 received income、teacher_wage expense、reversed expense、payment request、reimbursement/account transaction 历史，暂缓删除并需要单独迁移/归档方案。此前 2026-06-13 增加 `school_create_account_profile(..., p_app_type)` 和 `school_update_account_profile(..., p_app_type)` 重载，保留旧重载。账户页新增“账户用途”筛选和 create/edit 用途字段；`school` / `family` 可新增/编辑，`store` 本阶段只展示/筛选不编辑。Family 账户强制 `business_entity_id = NULL`、`is_company_account = false`，资料编辑不能改 `app_type`，新增/编辑不创建账户流水。
- 当前限制 / hard stop: 不开放 account code、系统字段、created/updated timestamps、current balance 编辑、交易流水、历史收入/支出/报销/支付/转账/调整/结算/工资链路派生字段。Family 账户本阶段只是后续家庭账本可用的账户主数据，不进入 school 收入、支出、支付、报销、工资、学生结算、利润分析、账户调整或账户转账候选。新增初始余额只初始化 `opening_balance/current_balance`，不创建账户流水；已有账户流水后 RPC 拒绝改币种，避免历史流水币种不一致。余额变化只能走 verified income/expense/reimbursement/payment/adjustment/transfer flows；family ledger 收支/转账尚未实现。
- 下一步: `account_scope`、household/member owner、family income/expense/transfer records、family summary、余额调整 / 期初修正需另开 guarded implementation phase；只有当 account transaction detail 不够用时再补 standalone transfer detail。

## 收入记录

- 当前状态: V1 可用。收入列表/详情、received income create/edit/reversal 已可用。Income Cash confirmation SQL/RPC 已安装，`request-cash-income-confirmation` / `sync-cash-request-result` 已部署，真实 CNY whitelist tests 已通过。普通收入继续走 School / 法人账户路径；Cash System 收入账户由 Cash `allow_school_requests = true` + 币种过滤提供，先创建 School pending income，再创建 Cash pending external request，Cash approve 后才写 Cash transaction、增加余额并回写 School received / settled。2026-06-15 起，收入详情页也可从既有 pending `school_income_records` 提交 Cash 确认，并支持 School 原始 JPY 金额与 Cash 实际到账 CNY/JPY 金额分离。
- 最近关键更新: 2026-06-15 income Cash workflow 完成安装和真实 CNY 验证。李天伦 `21,450 CNY` 通过 Cash System income path 创建 pending request 并由用户在 UI approve，School income 成为 `received` / `Cash已确认`，Cash 写入 `home_cny_transactions`，余额增加并对账一致。随后删除 3 条 reversed historical income，并按金额重建彭宇晗 `6,491 CNY`、厦门吕同学 `7,740 CNY` 两条真实 Cash System 收入，均 pending -> approve 成功、写 `home_cny_transactions`、School/Cash 对账一致。Cash request / transaction 用户可见文案已修复：income description 包含学生/付款人名 + 内容，note 保留原始备注。收入筛选已精简为月份、学生、业务归属、账户、币种。
- 当前限制 / hard stop: 普通收入路径仍按 V1。Cash approve 前不得把 School income 标记为 received / settled，也不得从 School 直接写 Cash transaction 或改变 Cash balance。Cash reject 后不生成 transaction、不改变余额，School income 保持 pending / retryable。旧 personal tuition linkage 的 `pending` 只是历史 manual-sync 兼容状态；新 income Cash workflow 使用 `pending_cash_request`、`awaiting_cash_confirmation`、`synced`、`cash_rejected`、`failed` / `blocked`。CNY/JPY 换汇、账户调拨、支付宝与日元现金/银行之间的资金调配暂时不由 School 自动处理；School 只记录业务收入/工资结算口径，Cash 手动记录换汇/账户调拨。不从 account transaction 反推收入；不删除正式 received income；不重算 locked student settlement。
- 下一步: Tuition income reverse sync、自动调度、青空塾代收清算、部分收款、付款计划、旧流水修正、跨账户收入迁移、结算外费用是否进入学生账单、personal external teaching income request 接入，均需另开 guarded design/implementation。

## 个人外部私塾打工收入

- 当前状态: 设计已补全并在 2026-06-15 刷新，尚未实装。详见 `docs/personal-teaching-income-module-design.md`。
- 业务定位: 用户个人在外部私塾授课 / 打工产生的个人业务收入。外部私塾是付款方；用户是授课者 / 打工者。该模块不是青空塾老师工资支出模块，不进入青空塾老师工资结算，不创建 `teacher_wage` payment request。
- 课时模型: 使用 planned + actual，但不复用现行青空塾 lesson 的 cancel / makeup / makeup_completed / `is_billable` 复杂状态。Planned 可自由新增、编辑、删除；唯一动作是生成 actual。如果没上课，删除 planned；如果 planned 已生成 actual，删除需要二次确认作为业务保护。
- 月度流程: 日常录入 planned -> 上课后生成 actual -> 月末核对 actual -> 计算 `actual_hours * hourly_rate + transportation_fee + allowance - deduction` -> 锁定月度结算 -> 生成 `personal_teaching_income_request` -> 提交 Cash 入账确认 -> Cash approve 后余额增加并标记 income request / settlement received / settled；Cash reject 后 request pending / retryable。
- 与 teacher_wage Cash 化区别: teacher_wage 是支出、payment request、Cash approve 后余额减少、School payment request paid；personal teaching income 是收入、income / receipt request、Cash approve 后余额增加、School income request received / settled。可复用 attempt、active attempt unique guard、rejected retry、idempotency、Cash external request、approve/reject callback、JPY/CNY transaction 分流；不可复用 payment 命名、支出方向、paid 语义、老师工资结算表或 teacher_wage 专用字段。
- 下一步: income Cash confirmation 链路已稳定通过首批真实 CNY 测试；下一步可另开 guarded implementation phase 设计/实装表结构、RPC、页面、结算锁定、Cash request 提交和回写。

## 私塾打工

- 当前状态: Workflow V1 已替换旧模型 / SQL 已安装 / 收入侧已改为统一收入记录链路。旧 `school_part_time_work_records` 一条记录同时保存课时和工资的错误模型已废弃并从 DB 删除。当前正式模型使用 `school_part_time_work_lessons`、`school_part_time_work_monthly_settlements`、`school_part_time_work_monthly_settlement_details`；锁定后通过 `school_create_part_time_work_income_record(...)` 生成 `school_income_records`，再从收入记录详情页提交 Cash 确认。课时/结算 SQL 来源为 `sql/current/school_part_time_work_workflow.sql`，收入记录路由来源为 `sql/current/school_part_time_work_income_record_route.sql`。旧 `school_part_time_work_income_requests` 和 `school_part_time_work_cash_request_workflow.sql` 仅保留为历史错误旁路痕迹，不再作为正常 UI 入口。
- 业务定位: 外部私塾 / 外部机构兼职授课流程，独立记录 planned 预定打工课时和 actual 实际打工课时；实际课时由预定课时生成；月底按 `year_month + 打工先` 结算工资；锁定后冻结明细快照；锁定后可生成 School 侧收入请求。
- 边界: 不混入现有学生记录，不复用 lesson management，不进入 teacher_wage 结算，不创建 teacher_wage payment request，不写 School expense/account transaction。打工模块不得直接向 Cash 发请求；Cash linkage 必须从 `school_income_records` 发起。Cash approve/reject 仍由 Cash UI 用户操作，approve 才生成 Cash transaction 并回写 School income record，reject 不生成 Cash transaction。
- 计算/权限: 课时工资和结算总额由 RPC 统一计算。开始时间、结束时间、回数、累计课时为必填；RPC 根据时间差计算单次 planned / actual 课时。旧课程组字段已从 lesson rows 和 locked detail snapshots 物理删除。回数和累计课时只用于明细展示，不进入预计工资、工资结算、monthly settlement 或锁定快照金额计算。预计工资只取 planned hours * 各 planned 行时给并加 planned 交通费。月度结算课时合计只取 actual 课时合计，实际课时工资汇总各 actual 行已保存课时工资。交通费保存在 planned / actual 课时上且允许为 0；月度结算行不再有单独保存动作，锁定时读取当前调整额和备注、保存总额并写入 settlement detail snapshots。locked 且未生成收入请求时可撤销锁定，撤销会删除 snapshot 并回到 draft；生成收入请求后不能撤销。锁定后 Excel 导出只读取 detail snapshot，不用当前可变课时重算。所有 page-facing list/create/update/delete/generate/lock/unlock/request/export RPC 只 grant execute to `authenticated`，不 grant anon。
- 当前限制 / hard stop: 不自动 approve/reject Cash request，不从 School 直接创建 Cash transaction，不改 locked settlement 金额，不做月度锁定以外的审批、复杂导出模板、历史导入、真实业务数据迁移或与 teacher_wage/payment request 的复用。旧 V1 active 行经用户确认是新建状态后已随表删除。
- 下一步: Cash UI 确认 2026-05 诺应教育 pending request `19ba6cbd-9588-486b-8b2a-b4b7c573f252` 后验证 `sync-cash-request-result` 回写 School；如需异常分支，使用 whitelist 测试数据单独验证 reject/retry。

## 支出记录

- 当前状态: V1 可用。支出列表/详情、ordinary paid expense create/edit/reverse、ordinary non-teacher-wage expense attachment metadata 已可用。Canonical 老师工资支出链路的模型准备中：`school_expense_records` 将承接 `source_type = teacher_wage`、工资来源 id、收款人快照和 future Cash linkage 状态字段。
- 最近关键更新: 2026-06-15 新增支出记录老师工资承接阶段：专用 RPC 从 locked teacher wage snapshot 生成一条 pending `teacher_wage` expense record，普通支出新增仍拒绝手动创建 `teacher_wage`。该阶段不迁移旧 `school_payment_requests`、不提交 Cash、不中断旧入口。2026-06-13 支出新增/编辑的 `exchange_rate` 改为可选：空白和 `0` 提交为 `NULL`，正数正常提交，负数或非数字才阻断；编辑回填 DB `NULL` 时保持空白。页面版本/cache-bust 更新到 `v2.108.0-expense-exchange-rate-optional-20260613`，并已用 mock Supabase 的实际新增/编辑页面路径验证四种输入。2026-06-12 支出新增/编辑 dialog 已收窄并统一。开放字段为 `expense_date`, `business_entity_id`, `account_id`, `expense_category`, `amount`, `description`, `payment_method`（`cash`, `bank_transfer`, `card`, `alipay`）, `receipt_status`, `reimbursement_status`, `tax_category`, `exchange_rate`, `note`。隐藏 `account currency`, `is_business_expense`, `teacher_id`, `student_id`；币种由付款账户派生，普通新增默认 `is_business_expense = true`，隐藏 legacy/低频字段暂不物理删除。详情页隐藏来源支付请求和账户流水展示块，保留报销信息和附件信息。
- 当前限制 / hard stop: ordinary reversal/edit 不得用于 teacher_wage expenses、来源支付请求生成的支出、已撤销支出、已报销支出或已进入报销链路的支出。编辑必须有且只有一条匹配原始 `expense_adjust` 账户流水，且该流水仍是账户最新流水；已出账支出暂不允许更换付款账户，需撤销后重新新增。Teacher_wage expense 不得加 ordinary attachment metadata；已报销 expense 必须先反转报销才能反转支出。不得删除 expense records、attachments、payment requests 或 original transactions。
- 下一步: 先实现 `school_expense_records` -> Cash payment request 统一链路，再单独处理旧 pending teacher_wage payment request 迁移/清理和旧入口禁用。Supabase Storage 文件上传/下载/预览/替换/删除和 OCR 另开 storage/security phase。

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
- 最近关键更新: 2026-06-15 私塾打工已从错误的一条工资记录 V1 改为 planned / actual 课时、月度工资结算、锁定、School 侧收入请求 workflow；仍独立于学生、lesson、teacher_wage、payment request 和 Cash。个人外部私塾打工收入模块设计已刷新为 `docs/personal-teaching-income-module-design.md`，定位为个人业务收入和 Cash 入账确认链路，不是青空塾 teacher_wage 支出。Income Cash confirmation workflow 已安装/部署并通过真实 CNY whitelist tests，可作为后续 personal teaching income request -> Cash receipt confirmation 的复用基础。账户/家庭账本账户联动已完成第一阶段 `app_type` 隔离实装；后续 account_scope、household/member ownership、family income/expense/transfer、family reporting 仍是 backlog。first-stage whitelist commit-test family 账户 `d3734cd7-fa94-4be3-b8dc-3cdc3690f667` / `codex-test-family-app-type-commit-20260613` 已经 dry-run、rollback validation、commit delete、residue check 清理完成。
- 当前限制 / hard stop: destructive cleanup、真实历史修复、广义 backfill、非 whitelist real-data writes、delete/merge、物理删除、全量重算均不是默认工作。
- 下一步候选: 青空塾代收学费 Cash 标记与法人清算、青空塾工资垫付与法人报销、manual FX/account-transfer runbook、Cash-linked reversal sync / retry UI、payment management follow-up、legacy SQL `grant execute ... to anon` 写 RPC 权限审计、weekly plan image export、full actual import/history migration、expanded wage-lock lifecycle、teacher wage adjustment items for transport/classroom fees、payment-request realtime exchange-rate CNY conversion、account_scope/household owner expansion、family ledger records/reporting、personal teaching income full workflow、account balance adjustment / opening-balance correction、business-entity-scoped wage generation、DB-level linked-actual unique/index after read-only duplicate-risk verification。
