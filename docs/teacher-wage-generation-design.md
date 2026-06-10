# 老师工资生成只读设计

Status: design-only / not implemented
Date: 2026-06-10

## 目标

本设计用于启动“老师工资生成”模块的后续 guarded workflow。当前阶段只调查现状、整理边界和建议 MVP，不实现代码、不写 SQL draft、不执行 SQL/RPC、不写 DB。

## 已确认现状

### 页面与 API

- `wage.html` / `js/pages/wage-page.js` / `js/api/wage-api.js` 目前是只读工资锁列表。
- `wage-detail.html` / `js/pages/wage-detail-page.js` / `js/api/wage-detail-api.js` 目前是只读工资锁详情。
- 工资详情读取 `school_teacher_wage_locks`、`school_teacher_wage_lock_details` 和 `source_type = teacher_wage` 的 `school_payment_requests`。
- `wage-rule.html` / `wage-rule-detail.html` 支持工资规则配置的读取、新增、编辑、停用/恢复；写入只影响 `school_teacher_wage_rules`，不重算历史工资。
- `payment` 页面处理老师工资支付请求确认、撤销、取消、恢复、重发；支付确认后才进入支出与账户流水链路。

### 现有表形状

从前端 select 字段和现有 RPC archive 可确认：

- `school_teacher_wage_locks` 是工资锁主表快照，包含 `teacher_id`, `teacher_name`, `settlement_month`, `business_entity_id`, `business_name`, `settlement_type`, `exchange_rate`, `lesson_count`, `total_minutes`, `pay_hours`, `fee_jpy`, `lesson_wage_jpy`, `lesson_wage_cny`, `total_jpy`, `total_cny`, `status`, `locked_at`, `voided_at`, `created_at`, `updated_at`。
- `school_teacher_wage_lock_details` 是工资明细快照，包含 `lock_id`, `lesson_record_id`, `lesson_date`, `start_time`, `end_time`, `student_id`, `student_name`, `subject_id`, `subject_name`, `business_entity_id`, `business_name`, `pay_hours`, `lesson_wage_jpy`, `lesson_wage_cny`, `transport_fee_jpy`, `classroom_fee_jpy`, `total_jpy`, `total_cny`, `settlement_type`, `exchange_rate`, `is_no_wage`, `status`, `lesson_content`, `created_at`。
- `school_teacher_wage_rules` 是未来锁定配置源，当前支持匹配键 `teacher_id + student_id + subject_id + business_entity_id`，配置字段包括 `settlement_type`, `hourly_rate_jpy`, `hourly_rate_cny`, `exchange_rate`, `transport_fee_jpy`, `classroom_fee_jpy`, `is_active`, `note`。
- 当前已验证的 `settlement_type` 只有 `jpy_hourly` 和 `no_wage`。

### 现有锁定逻辑

- 课时 actual 生成 RPC 会检查目标老师工资月份是否已有 `school_teacher_wage_locks.status = locked`，匹配 `teacher_id + business_entity_id + teacher_settlement_month`。
- guarded lesson edit 对 actual 会：
  - 拒绝已经被 `school_teacher_wage_lock_details.lesson_record_id` 引用的 actual。
  - 检查原老师工资月份和目标老师工资月份是否 locked。
  - 更新 actual 时重新派生 `teacher_settlement_month = lesson_date YYYY-MM`。
- `wage.html` 与 `wage-detail.html` 不提供任何重新计算、编辑工资明细或支付操作。
- `wage-detail.html` 明确把工资锁作为已保存快照，不用当前工资规则重算历史锁定工资。

## 课时进入工资口径的当前事实

- `planned` 不写 `actual_minutes` 和 `teacher_settlement_month`，不应进入工资生成。
- `actual` 会写 `actual_minutes` 和 `teacher_settlement_month`。
- `completed actual`：
  - `teacher_settlement_month = actual lesson_date YYYY-MM`
  - `actual_minutes = round(duration_hours * 60)`
  - `is_billable` 继承 planned，但这目前只被学生结算/课时统计用于学费口径。
- `makeup_completed actual`：
  - `teacher_settlement_month = makeup actual lesson_date YYYY-MM`
  - `actual_minutes = round(duration_hours * 60)`
  - 可计费或不计费；非计费时 `lesson_fee = 0`。
- 跨月 `makeup_completed actual`：
  - `year_month = 补课月份`
  - `teacher_settlement_month = 补课月份`
  - `planned_lesson_id` 指向原月份 `pending_makeup planned`
  - 默认 `is_billable = false` 且 `lesson_fee = 0`
  - 已验证不进入学生结算 actual fee/hours，但仍是补课月份 actual lesson。
- `cancelled actual`：
  - `teacher_settlement_month = cancelled actual lesson_date YYYY-MM`
  - `actual_minutes = 0`
  - `is_billable = false`
  - `lesson_fee = 0`
  - 是否进入老师工资不能从现有生成逻辑确认。

## 工资生成字段建议

MVP 应只读取 `school_lesson_records` 中的 actual 行，候选条件建议：

- `lesson_type = 'actual'`
- `teacher_id` 非空
- `business_entity_id` 非空
- `teacher_settlement_month = p_settlement_month`
- `status in ('completed', 'makeup_completed')`
- `actual_minutes > 0`
- `voided_at` 不参与，因为当前 void 只适用于 planned；若未来 actual void/delete 出现，必须重新设计。

字段口径：

- `teacher_id`: 工资主表分组键之一。
- `business_entity_id`: 工资主表分组键之一，且匹配工资规则。
- `teacher_settlement_month`: 工资月口径，应优先于 lesson `year_month`。
- `lesson_type`: 只允许 actual。
- `status`: MVP 建议只纳入 `completed` 和 `makeup_completed`。
- `actual_minutes`: 优先作为 pay minutes 来源；若为空但 `duration_hours` 有值，是否 fallback 需要下一阶段确认并写入 guard。
- `duration_hours`: 可作为只读校验或 fallback 候选，不应替代已写好的 `actual_minutes` 口径。
- `is_billable`: 学生收费口径，不应默认排除老师工资；跨月补课的 non-billable actual 仍应作为老师已上课事实进入候选，除非业务另行确认排除。
- `lesson_fee`: 学生学费口径，不应用于老师工资计算。
- `lesson_count`: 当前工资锁主表有 `lesson_count`，但工资规则是 hourly 口径；MVP 应明确是否只是统计字段，不作为金额计算来源。

## 规则匹配与金额建议

当前可确认的工资规则匹配键为：

- `teacher_id`
- `student_id`
- `subject_id`
- `business_entity_id`
- `is_active = true`

MVP 建议：

- 每条 actual 必须匹配一条启用工资规则。
- 多条启用规则命中同一 actual 时应 hard stop，不自动选。
- 未命中规则的 actual 应阻止生成，并返回缺规则明细。
- `settlement_type = 'jpy_hourly'`：
  - `pay_hours = actual_minutes / 60`
  - `lesson_wage_jpy = round/pay according to chosen precision in RPC design`
  - `lesson_wage_cny = 0` unless a future CNY hourly rule is explicitly defined
  - `transport_fee_jpy`、`classroom_fee_jpy` 从规则复制到明细
  - `total_jpy = lesson_wage_jpy + transport_fee_jpy + classroom_fee_jpy`
  - `total_cny` 按现有字段设计确认，不能从现有代码推导最终公式
- `settlement_type = 'no_wage'`：
  - 明细可写入 `is_no_wage = true`
  - 金额字段为 0
  - 是否生成明细用于审计，建议生成 0 金额明细，避免“漏算还是无工资”无法区分。

## 锁定与重复生成建议

现有系统只有 saved wage lock 快照；未发现 draft 表或 draft 状态的已实现入口。

MVP 建议选择“直接生成 locked snapshot”，不引入 draft：

- 输入：指定 `settlement_month`，可选 `teacher_id` / `business_entity_id`。
- 输出：为每个 `teacher_id + business_entity_id + settlement_month` 生成一条 `school_teacher_wage_locks` 和对应明细。
- 已存在 `status = locked` 的同一老师/业务归属/月应拒绝重新生成。
- 已存在 payment request、paid expense、account transaction 的工资锁绝对不能被重算或覆盖。
- 不删除旧 detail，不覆盖旧 lock，不做历史重算。
- 如果未来需要 draft，必须新增单独设计：明确 draft 表/状态、覆盖规则、旧 draft 删除/替换规则，以及与 lesson edit guard 的关系。

不建议在 MVP 做“先删除旧 draft 明细再生成”，因为仓库没有现有 draft 概念，且 `delete` 是项目 hard stop 类操作。

## 与支付、支出、账户边界

工资生成阶段建议只写：

- `school_teacher_wage_locks`
- `school_teacher_wage_lock_details`

工资生成阶段不得直接写：

- `school_payment_requests`
- `school_expense_records`
- `school_accounts`
- `school_account_transactions`
- `school_income_records`
- `school_student_monthly_settlements`
- `school_student_settlement_carryovers`

支付请求应作为后续单独阶段处理。现有支付管理已经以 `source_type = 'teacher_wage'` 和 `source_id = wage_lock.id` 展示工资来源，并在支付确认时才生成 teacher_wage 支出和账户流水。普通支出 RPC 明确拒绝手工创建 `teacher_wage` 分类，普通支出撤销/附件也排除 teacher_wage。

## UI / API / RPC / DB 触点

### DB

优先复用现有 `school_teacher_wage_locks` 与 `school_teacher_wage_lock_details`。是否需要新增唯一约束或状态字段不能在本阶段决定，必须先做只读 DB 验证：

- 同一 `teacher_id + business_entity_id + settlement_month` 是否已有多条 active/locked lock。
- 是否存在 `status` 非 `locked` / `void` 的历史值。
- 是否存在 detail 缺 `lesson_record_id` 或一条 actual 被多个 detail 引用。
- 是否存在 `cancelled` detail。

### RPC

建议后续新增专用 guarded RPC：

`school_generate_teacher_wage_locks_for_month`

候选参数：

- `p_settlement_month text`
- `p_teacher_id uuid default null`
- `p_business_entity_id uuid default null`
- `p_note text default null`
- `p_dry_run boolean default false` only if design chooses preview through same RPC; otherwise separate read RPC

RPC guard：

- 月份格式必须是 `YYYY-MM`。
- 候选 actual 只来自 `school_lesson_records.lesson_type = actual`。
- 候选 actual 的 `teacher_settlement_month = p_settlement_month`。
- 候选 status 默认只允许 `completed`, `makeup_completed`。
- 拒绝任何候选 actual 已存在于 `school_teacher_wage_lock_details.lesson_record_id`。
- 拒绝目标 `teacher_id + business_entity_id + settlement_month` 已有 `status = locked` 的 wage lock。
- 拒绝缺工资规则、重复工资规则、停用工资规则。
- 不修改 lesson records。
- 不写 payment、expense、account、account transaction。

### API

新增 API wrapper 必须在 `js/api/wage-api.js` 或独立 `teacher-wage-generation-api.js`，页面不得直接 `.rpc()`。

建议 API：

- `previewTeacherWageGeneration(filters)`：只读候选预览，最好先用 select/API 查询；若未来用 read RPC，必须只读。
- `generateTeacherWageLocks(payload)`：调用 guarded RPC。

### UI

入口建议放在 `wage.html`：

- 页面仍以工资锁列表为主。
- 新增主操作：`生成老师工资`
- 弹窗文案：
  - `只基于 actual 课时生成工资快照`
  - `不会修改课时`
  - `不会生成支付请求`
  - `不会写入支出或账户流水`
  - `已锁定月份不能重新生成`
- 弹窗先显示候选月份、老师、业务归属、actual 数、缺规则数、将生成的锁数。
- 若存在缺规则、重复规则、已锁定、已被 wage detail 使用的 actual，应阻止提交并显示明细。

## MVP 范围建议

第一版只做：

- 指定月份生成老师工资锁主表与明细快照。
- 只基于 actual lesson records。
- 只纳入 `completed` 和 `makeup_completed`。
- 跨月补课 actual 按 `teacher_settlement_month` 进入补课月份老师工资。
- `is_billable = false` 不默认排除老师工资。
- 生成后 locked，不提供 draft。
- 已锁定后禁止重新生成。
- 不碰支付、不碰支出、不碰账户、不碰收入、不碰学生结算。
- 不做历史 backfill，不处理真实历史修复。

## Hard Stop / 待确认点

以下点无法从当前仓库中已实现的工资生成逻辑确认，进入实现前必须确认：

- `cancelled actual` 是否应进入老师工资。当前明细 UI 只标注 `completed` / `makeup_completed`，且 cancelled actual `actual_minutes = 0`；建议 MVP 暂不纳入，但这是业务口径确认点。
- 是否需要 draft / preview / locked 三态。当前只看到 `locked` / `void` 展示，未看到 draft 实现。
- 是否生成工资时同时生成 `school_payment_requests`。建议不做；若要求直接生成支付请求，应停止并单独设计。
- `lesson_wage_cny`、`total_cny` 的公式与汇率使用方式需要按历史工资口径确认。
- 交通费、教室费是否每节 actual 都加一次，还是按老师/月聚合一次；当前规则字段在 detail 上存在，但业务频率需确认。
- `lesson_count` 在工资中只是统计还是参与工资公式，需要确认。
- 是否允许按老师单独生成，还是必须整月全量生成，需要确认。
- 是否允许 void/relock 已生成工资锁。当前不是 MVP。

Hard stop：

- 如果实现需要修改课时核心口径，停止。
- 如果实现需要 backfill 历史工资，停止。
- 如果实现需要清理真实历史数据，停止。
- 如果实现要把工资生成直接写入支出、账户流水或支付请求，停止并单独说明。
- 如果工资口径无法从文档/只读验证确认，停止并列出待用户确认点。

## 下一阶段建议

1. 只读 DB verification：确认 `school_teacher_wage_locks` / details / rules 的真实列、状态值、重复情况和历史 detail status 分布。
2. 只读候选统计：统计一个测试月份中 actual `completed` / `makeup_completed` / `cancelled` 的分布、`is_billable=false` 的分布、跨月补课 actual 分布、缺工资规则候选。
3. 业务确认：确认 hard stop / 待确认点，尤其是 cancelled、CNY 公式、交通费/教室费频率、是否生成 payment request。
4. 进入 RPC phase：只在确认后写 SQL draft，并按 full write-RPC workflow 执行 rollback test 和 whitelist commit test。
