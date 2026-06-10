# 跨月补课完成登记设计

Status: implemented through DB/RPC + API/UI V1
Date: 2026-06-10

## 目标

为“跨月补课完成登记”建立设计边界，并记录 DB/RPC 与 API/UI 阶段落地结果。本文仍用于约束 UI / API / RPC / DB 触点；截至 2026-06-10，专用写 RPC、API wrapper、目标月份页面入口和跨月引用展示均已实现。

## 业务边界

- 临时加课：在本月新增 `planned`，再从该 `planned` 生成 `actual`。
- 当月补课：本月 `pending_makeup planned` -> 本月 `makeup_completed actual`，继续走现有补课完成流程。
- 跨月补课：原月份 `pending_makeup planned` -> 补课月份 `makeup_completed actual`。
- 跨月补课 `actual.planned_lesson_id` 必须指向原月份的 `pending_makeup planned lesson`。
- 跨月补课不复制 `planned`。
- 跨月补课不复制 `actual`。
- 原月份页面只引用显示“已于补课月份完成”。
- 补课月份页面只引用显示“来源：原月份待补课”。
- 该功能只处理 `pending_makeup planned.year_month` 早于 `makeup_completed actual.year_month` 的情况。

## 当前实现差异

现有 `school_create_makeup_completed_actual_lesson_from_planned` 适合当月或同源补课完成，但不适合作为跨月实现直接复用：

- 当前 RPC 允许来源 planned 状态为 `planned` 或 `pending_makeup`；跨月入口应只允许 `pending_makeup`。
- 当前 RPC 插入 actual 时 `year_month = v_planned.year_month`；跨月要求 actual 属于补课月份，即 `year_month = to_char(p_lesson_date, 'YYYY-MM')`。
- 当前学生结算锁检查只看来源 planned 月；跨月实现必须按补课月份 actual 月检查写入保护，同时不能因来源月已锁定而修改来源 planned。
- 当前页面只在当前加载记录里做 planned/actual 左右配对；跨月时原月份或补课月份可能只加载到链路的一侧，需要跨月引用展示。

因此实现时新增专用 RPC，而不是改变现有当月补课 RPC 的口径。

## 实现检查点

- 2026-06-10 已新增并执行 `public.school_create_cross_month_makeup_completed_actual_from_planned`，SQL archive 为 `school_create_cross_month_makeup_completed_actual_from_planned_rpc.sql`。
- RPC 阶段只新增写 RPC，不接 API/UI，不新增 DB-level unique/index 约束。
- 只读预检发现 existing linked-actual duplicate group 为 `1`，existing cross-month linked actual count 为 `0`。
- Rollback tests 覆盖成功默认不计费插入、重复 linked actual guard、同月 guard、目标学生结算锁 guard、目标老师工资锁 guard，并确认无 rollback residue。
- Whitelist commit test 创建 source planned `19b574d5-78e0-43fb-8248-e2cd9c2c68af` 和 actual `8baa4f13-f290-4332-819c-d8ba20906df4`；actual `year_month = 2027-10`、`planned_lesson_id` 指向 source、`is_billable = false`、`lesson_fee = 0`、`actual_minutes = 120`。
- 2026-06-10 API/UI 阶段已在 `js/api/lesson-api.js` 新增跨月补课来源候选读取、跨月引用读取、`createCrossMonthMakeupCompletedActualFromPlanned(payload)` wrapper；`lesson.html` 新增目标月份独立入口 `登记跨月补课完成`，页面仍无直接 `.rpc()`。
- UI 阶段 browser validation 使用 source planned `d97acf8d-47f1-4b06-9eef-459521aaecb1`，通过页面生成 actual `50ea35b7-c746-4ffb-88e7-f2c11758258c`；actual `year_month = 2027-12`、`is_billable = false`、`lesson_fee = 0`、`actual_minutes = 120`、`teacher_settlement_month = 2027-12`。
- UI 验证确认：linked source 不再出现在候选列表；目标月份显示 `来源：2027-11 待补课`；原月份显示 `已于 2027-12 完成`；原 planned 的同月 `补课完成` action count 为 `0`；390px mobile `scrollWidth = 390`。

## DB 设计触点

优先不新增表字段。现有 `school_lesson_records` 可表达跨月链路：

- 来源行：`lesson_type = 'planned'`, `status = 'pending_makeup'`, `year_month = 原月份`, `voided_at is null`。
- 结果行：`lesson_type = 'actual'`, `status = 'makeup_completed'`, `planned_lesson_id = 来源 planned id`, `lesson_date = 补课日期`, `year_month = 补课月份`, `teacher_settlement_month = 补课月份`。
- 不修改来源 planned，不新增复制 planned，不复制既有 actual。

需要只读查询增强：

- 原月份页面加载 `pending_makeup planned` 时，应能查到跨月 linked actual 的基本信息。
- 补课月份页面加载 `makeup_completed actual` 时，应能查到来源 planned 的原月份、原日期、学生、老师、科目、业务归属和状态。

后续若现有 Supabase select 不能稳定查询跨月引用，可设计一个 read-only RPC，例如 `school_get_lesson_cross_month_makeup_links(p_year_month text)`，只返回当前月份相关的跨月链路摘要，不写 DB。

## RPC 设计触点

已新增写 RPC，并通过 API/UI 接入：

`public.school_create_cross_month_makeup_completed_actual_from_planned(...)`

核心规则：

- `p_planned_lesson_id` 必填，来源必须是 school `planned`。
- 来源 `status` 必须是 `pending_makeup`。
- 来源 `voided_at` 必须为空。
- `p_lesson_date` 必填，且 `to_char(p_lesson_date, 'YYYY-MM') > source.year_month`。
- 目标 actual 固定为 `lesson_type = actual`, `status = makeup_completed`。
- 目标 actual 的 `planned_lesson_id = source.id`。
- 目标 actual 的 `year_month = to_char(p_lesson_date, 'YYYY-MM')`。
- 目标 actual 的学生、老师、科目、业务归属从来源 planned 继承。
- 默认 `is_billable = false`；只有调用方显式传入 `p_is_billable = true` 时才登记为计费。
- 拒绝任何已存在 `lesson_type = actual and planned_lesson_id = source.id` 的重复生成。
- 不更新来源 planned，不更新结算、工资、收入、支出、账户或流水。

锁定保护：

- 学生结算锁：检查目标 actual 月份 `actual.year_month`。来源原月份已锁定不应阻止跨月登记，因为来源 planned 不被修改。
- 老师工资锁：检查目标 `teacher_settlement_month`。
- 若后续统计要求原月份也展示引用，该展示必须是只读引用，不得修改来源月历史数据。

已执行的回滚/commit 测试：

- rollback：从 whitelisted `codex-test / v2-test / sandbox` 临时 `pending_makeup planned` 生成目标月 actual，确认 `actual.year_month` 为目标月、`planned_lesson_id` 指向来源、来源 planned 未变化，然后 rollback；rollback residue 为 `0`。
- duplicate guard：同一来源已有 actual 时拒绝。
- same-month guard：`p_lesson_date` 落在来源 `year_month` 时拒绝，引导使用现有当月补课流程。
- locked target settlement guard：目标学生结算月锁定时拒绝。
- locked target wage guard：目标老师工资月锁定时拒绝。
- whitelist commit：仅使用 whitelisted 测试数据，提交 source planned `19b574d5-78e0-43fb-8248-e2cd9c2c68af` 与 actual `8baa4f13-f290-4332-819c-d8ba20906df4`。

## API 设计触点

已新增 API-layer wrapper，页面不得直接 `.rpc()`：

- `createCrossMonthMakeupCompletedActualFromPlanned(payload)`：调用新写 RPC。
- `fetchCrossMonthMakeupSourceLessons({ fromMonth, toMonth, targetMonth })`：读取以前月份、未作废、无 linked actual 的 `pending_makeup planned` 来源候选。
- `fetchCrossMonthMakeupReferences(yearMonth, records)`：读取当前月份相关跨月引用摘要。

API 返回建议：

- 写入成功返回新 actual 的完整 lesson 摘要。
- 只读引用返回两类关系：
  - `source_month_refs`: 当前月 planned 在其他月份已补课完成。
  - `target_month_refs`: 当前月 actual 来源于其他月份 pending_makeup planned。

## UI 设计触点

课时管理页面默认“左右对应”视图后，跨月展示应围绕该视图展开。

原月份视图：

- 对 `pending_makeup planned`，如果 linked actual 在其他 `year_month`，在 actual 侧显示只读引用卡。
- 文案：`已于 YYYY-MM 完成`，并显示补课日期、时间、计费状态、金额和详情链接。
- 不显示“补课完成”写入按钮，因为来源已有 linked actual。

补课月份视图：

- 对 `makeup_completed actual`，如果来源 planned 在其他 `year_month`，在 planned 侧显示只读来源卡。
- 文案：`来源：YYYY-MM 待补课`，并显示原计划日期、时间、学生/老师/科目/业务归属和详情链接。
- actual 仍作为目标月份记录参与筛选、详情和工资结算引用。

入口设计：

- 当前月份内已有 pending_makeup planned 的“补课完成”继续使用现有当月入口。
- 跨月入口独立命名为 `登记跨月补课完成`，从目标补课月份页面打开。
- 入口内先选择原月份范围和 `pending_makeup planned` 来源，再填写补课日期/时间/课时/内容/备注；默认不计费，金额固定 `0`。
- 来源选择结果显示“不会复制 planned，不会修改来源 planned，只生成目标月份 actual”。

详情页：

- 来源 planned 详情：显示跨月 actual 引用和“已于 YYYY-MM 完成”。
- 目标 actual 详情：显示来源 pending_makeup planned 引用和“来源：YYYY-MM 待补课”。
- 返回链接继续保留 `returnQuery`，跨月 detail link 应携带对应月份和 `view=pair`。

## 统计与结算口径

- 学生月度结算：目标 actual 计入补课月份 actual 口径；来源月份 planned 仍作为原月份 planned 引用存在，不通过写入修改。
- 补以前月份已收费课时的 UI 默认值为 `is_billable = false`，且当前 V1 页面固定不计费、金额 `0`；若后续 UI 允许计费，必须显式选择并传入 `p_is_billable = true`。
- 老师工资：目标 actual 的 `teacher_settlement_month` 为补课月份。
- 导入：不进入 planned-only 导入；full actual import 仍是 future/history migration backlog。

## 非目标

- 不做历史数据迁移、历史修复、批量 backfill 或 cleanup。
- 不复制 planned 或 actual。
- 不修改来源 planned 状态。
- 不实现 free actual creation。
- 不改 planned-only import。
- 不生成或重算学生结算、老师工资、收入、支出、账户或流水。
- 不清理 whitelist / codex-test 数据。

## 后续非 V1 切片

1. 详情：原 planned 与目标 actual 的跨月引用展示可在 detail page 单独增强；当前 V1 已在 lesson paired view 展示。
2. 计费扩展：若未来允许跨月补课计费，必须新增显式 UI 控制并保持 `p_is_billable = true` 的显式传参。
3. 导入：full actual import 仍是 future/history migration backlog，不复用本入口。
