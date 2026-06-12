# Module Status

Status date: 2026-06-12

This is the lightweight module summary for daily sessions. It keeps only each module's current state, recent key update, current limits / hard stops, and next step. Older module history, long commit/test logs, and completed detail records are archived in `docs/archive/module-status-history.md`.

Visual dashboard: open `docs/module-status-dashboard.html` locally for a card-based static overview.

## Global Rules

- v2 opens create/edit where safe; delete, merge, destructive cleanup, historical repair, and broad backfill remain closed unless separately designed and authorized.
- Current/unclosed real business months must not be used for real wage generation, snapshot generation, student settlement closing, locking, or lock-style write validation.
- Validation priority is transaction rollback or clearly marked whitelist data (`codex-test`, `v2-test`, `sandbox`, `测试学生`, `测试老师`, `测试业务归属`).
- Student settlement, teacher wage, payment request, reimbursement, account transaction, income/expense, and lesson chains are protected. Master-data changes must not rewrite or recalculate these chains.
- Core business writes must go through API/RPC boundaries. Page modules must not call `.rpc()` directly and must not directly insert/update/delete/upsert DB rows.
- Field narrowing policy:新增/编辑只保留当前实际业务使用字段；历史/预留/低频/派生/系统/交易链路字段隐藏或只读，暂不物理删除。

## Snapshot

| Module | Current state | Next priority |
| --- | --- | --- |
| 课时管理 | 已收口 | Keep planned-only V1 stable; full actual/history import stays backlog |
| 学生月度结算 | 已收口 | No immediate V1 work; future reversal/history requires new design |
| 老师工资结算 | V1 可用 | Payment flow is separate; wage lifecycle expansion remains backlog |
| 老师工资支付 | V1 可用 | Retest status actions before future changes |
| 账户管理 | V1 可用 | Add transfer detail only if transaction detail becomes insufficient |
| 收入记录 | V1 可用 | Expand categories only after guard semantics are designed |
| 支出记录 | V1 可用 | Real attachment storage is a separate storage/security phase |
| 报销管理 | V1 可用 | Partial/edit requires separate guarded design |
| 学生/老师/科目/业务归属管理 | V1 可用 | Keep master-data writes narrow; delete/merge deferred |
| 工资规则 | V1 可用 | Keep future-lock config; generic matching rules need explicit semantics |
| 导入导出 | 已收口 | Planned-only import stable; full actual/history import deferred |
| 利润分析 | 只读完成 | Keep read-only |
| Backlog / 暂不实现 | Backlog | Separate guarded phases only |

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

- 当前状态: V1 可用。支付列表可确认支付、反转已支付请求、取消 pending、恢复 cancelled、reissue reversed；详情页只读。
- 最近关键更新: 支付确认按所选账户类型设置 teacher_wage expense reimbursement status：公司账户 `not_required`，垫付/个人账户 `pending`；报销 RPC 继续拒绝 teacher_wage expense。
- 当前限制 / hard stop: 不删除 payment request、wage lock、expense、account transaction。确认支付必须不创建 reimbursement/income/student settlement/wage/lesson 等非本链路数据。
- 下一步: 未来改 payment status actions 时，显式重测 cancel/restore/reissue 和 confirm/reverse 链路。

## 账户管理

- 当前状态: V1 可用。账户列表、账户交易详情、账户新增、账户资料编辑、账户调整/反转、账户转账/反转已可用。
- 最近关键更新: 账户编辑 summary 已隐藏；账户新增未收缩到 name/type/status/note，因为 schema/RPC 仍要求 `account_code`, `currency`, `business_entity_id`，隐藏这些字段会引入不安全默认值。
- 当前限制 / hard stop: 账户资料编辑不得改 account code、业务归属、币种、opening/current balance、交易流水、历史收入/支出/报销/支付/转账/调整/结算/工资链路。余额变化只能走 verified income/expense/reimbursement/payment/adjustment/transfer flows。
- 下一步: 只有当 account transaction detail 不够用时再补 standalone transfer detail。

## 收入记录

- 当前状态: V1 可用。收入列表/详情、paid tuition income create、received tuition income reversal 已可用。
- 最近关键更新: 当前收入仍限定学费收入链路，详情页显示结算与账户交易引用。
- 当前限制 / hard stop: 不从 account transaction 反推收入；不删除收入；不重算 locked student settlement；reversal 必须保留原收入和原交易。
- 下一步: 扩展收入类别前，先设计 settlement/account guard 语义。

## 支出记录

- 当前状态: V1 可用。支出列表/详情、ordinary paid expense create/reverse、ordinary non-teacher-wage expense attachment metadata 已可用。
- 最近关键更新: 附件 V1 仍是 metadata-only、audit-only，不影响 expense/account/reimbursement 状态。
- 当前限制 / hard stop: ordinary reversal 不得用于 teacher_wage expenses；teacher_wage expense 不得加 ordinary attachment metadata；已报销 expense 必须先反转报销才能反转支出。
- 下一步: Supabase Storage 文件上传/下载/预览/替换/删除和 OCR 另开 storage/security phase。

## 报销管理

- 当前状态: V1 可用。报销列表/详情、从候选 paid non-teacher-wage expenses 生成报销、报销反转已可用。
- 最近关键更新: 报销仅归还垫付账户，不是 operating expense，也不能再次生成 teacher_wage expense。
- 当前限制 / hard stop: 不支持 edit、partial reimbursement、attachments、reimbursement-page statistics。不得删除报销记录/items/original transactions。
- 下一步: partial/edit 需要单独 guarded design，因为会触及 expenses、accounts、transactions。

## 学生/老师/科目/业务归属管理

- 当前状态: V1 可用。学生、老师、科目、业务归属列表可读；future-use profile create/update 已通过 API/RPC 边界开放。
- 最近关键更新: 2026-06-12 已完成学生、老师、业务归属 dialog 收缩；科目保留安全分类/排序/颜色编辑。业务归属默认币种经只读验证不影响主业务链路，现隐藏保留。
- 当前开放字段:
  - 学生: `name`, `business_entity_id`, `course_track`, `preset_exchange_rate`, `wechat`, `phone`, `entrance_date`, `target_schools` 最多 3 个, `note`。
  - 老师: `name`, `department`, `default_subject_id`, `default_business_entity_id`, `status`, `note`, `alipay_account`, `wechat_account`, `bank_name`, `bank_branch_code`, `bank_branch_name`, `bank_account_number`。
  - 科目: `name`, `is_active`, `primary_category`, `category`, `tertiary_category`, `color`, `sort_order`, `note`。
  - 业务归属: `name`, `entity_type`, `is_active`, `note`；create RPC 生成系统 code，隐藏 `default_currency = JPY`。
- 当前限制 / hard stop: 不开放 delete/merge；不改学生/老师编号、display-name variants、读音、目标类型、默认币种、工资币种、支付币种、默认时给、余额、结算、学费规则、历史课时、工资、支付、收入/支出、账户流水、公司报表等系统/派生/历史/交易链路字段。
- 下一步: 保持 master-data writes narrow。学生 contact/guardian/birthday 或 tuition-rule、老师 legacy contact/payment defaults、业务归属 company-report/defaulting 如要重开，必须单独设计。

## 工资规则

- 当前状态: V1 可用。工资规则列表、只读详情、future-use rule create/edit、soft-disable/restore 已可用。
- 最近关键更新: 编辑已开放 matching keys 和配置字段；`is_active` 仍通过停用/恢复专用 action 修改，不在通用 edit 中直接改。
- 当前限制 / hard stop: 不物理删除；不重算 historical wages；不改 wage locks/details、payment requests、expenses、account balances、account transactions。restore 必须拒绝冲突 active rules。
- 下一步: 保持 future-lock config 口径；generic student-empty rules 或更复杂匹配需独立冲突语义设计。

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
- 最近关键更新: 当前优先级仍是保护已完成 V1 surfaces，再按独立阶段推进新需求。
- 当前限制 / hard stop: destructive cleanup、真实历史修复、广义 backfill、非 whitelist real-data writes、delete/merge、物理删除、全量重算均不是默认工作。
- 下一步候选: payment management follow-up、weekly plan image export、full actual import/history migration、whitelist/codex-test cleanup、expanded wage-lock lifecycle、business-entity-scoped wage generation、DB-level linked-actual unique/index after read-only duplicate-risk verification。
