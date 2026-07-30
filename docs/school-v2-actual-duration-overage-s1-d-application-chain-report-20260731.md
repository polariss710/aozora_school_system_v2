# Aozora V2 actual duration overage S1-D 应用链收尾审查报告

审查日期：2026-07-31
Git 基线：`fdc4a43808399994b659cdf7ceae1e3e76c85c99`
结论：`S1-D_APPLICATION_CHAIN_VALIDATED_NO_CODE_CHANGE`
最终状态：`ACTUAL_DURATION_OVERAGE_COMPLETE`

## 1. 审查范围与边界

本阶段仅静态审查现有 planned→actual 页面/API 链与学生月结页面/API 链，并执行本地 JavaScript 语法检查。没有连接 School DB 或 Cash DB，没有执行 SQL、调用 RPC、生成 actual、锁定或重新锁定月结，也没有产生任何业务写入。

本阶段没有修改 `js/pages/lesson-page.js`、`js/api/lesson-api.js`、`js/pages/settlement-page.js` 或 `js/api/settlement-api.js`。交付内容仅为本报告及 `docs/current-status.md` 状态更新。

## 2. Git 与 R0 前置状态

- branch：`main`
- HEAD：`fdc4a43808399994b659cdf7ceae1e3e76c85c99`
- origin/main：`fdc4a43808399994b659cdf7ceae1e3e76c85c99`
- 暂存区为空。
- 初始工作区仅有受保护未跟踪文件 `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`。
- 未读取受保护文件正文；SHA-256 为 `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。
- 本轮不连接数据库；R0 沿用 S1-C 已验收状态且本轮未修改：
  - `student_tuition_preview = validation_preview_only`
  - `student_tuition_generate = blocked`
  - `student_tuition_cash_submit = blocked`

## 3. planned→actual 页面/API 结论

### 3.1 页面分支

`lesson-page.js` 的实际课时表单默认不勾选 partial。提交时只有 `payload.partial` 为真才调用 `createPartialCompletedActualFromPlanned(...)`；未勾选时统一调用 `createActualLessonFromPlanned(...)`。页面没有比较 actual duration 与 planned duration，也没有 `actual != planned` 或 `actual > planned` 阻断。因此：

- actual = planned：走 ordinary API；
- actual > planned：无需 checkbox，走 ordinary API；
- actual < planned：页面仍走 ordinary API，由 S1-B DB writer 拒绝并提示使用 partial；
- 用户主动勾选 partial：才走 partial API。

页面捕获 API/RPC 返回的错误文本并显示在表单错误区；包含“时长”的错误会定位时长字段。S1-B writer 中 actual < planned 的权威错误仍为“实际完成时长小于预定时长；部分完成请使用‘部分完成，剩余转待补’流程”。

### 3.2 参数与小数时长

页面将时长输入解析为 JavaScript `Number`，只校验它与开始/结束时间对应且为正数，没有对 planned duration 作比较。输入控件 `step="0.25"`，所以 `2.25` 等小数可通过表单，并作为 `payload.durationHours` 原样交给 API。

`lesson-api.js` 调用 `school_create_actual_lesson_from_planned`，继续传递 S1-B 兼容的十个参数，其中 `p_duration_hours = payload.durationHours`，API 未对时长舍入或重算。

### 3.3 P0 资金计算边界

页面模块没有直接 `.rpc()`；RPC 仅由 `lesson-api.js` 调用。页面/API 都不计算或传入 overage minutes、overage JPY、overage CNY、source month 或 target month。S1-B ordinary writer 在同一 actual INSERT 内根据 source planned 权威字段生成冻结 overage bundle。

页面保留既有普通课时费显示预览，但 ordinary submit 在用户未手工编辑课时费时传 `lessonFee = null`；该显示预览不是 overage 事实，也不参与 overage 分钟、JPY、CNY或月份计算。

### 3.4 静态调用链

```text
lesson page
→ lesson API
→ school_create_actual_lesson_from_planned
→ S1-B overage bundle
```

结论：现有页面/API 没有再次阻断 `actual > planned`，无需 JS/API 修改。

## 4. 月结页面/API 结论

### 4.1 DB 权威余额映射

`settlement-api.js` 通过 `school_get_student_monthly_settlement_preview` 取得实时月结结果，并直接映射：

- `summary.final_due_cny` → `row.system_difference_cny`
- `summary.locked_carryover_cny` → `row.carryover_amount_cny`
- `summary.carryover_cny` → `row.previous_balance_cny`

未锁定 preview 与 unlocked 重算均使用同一 preview RPC。locked 记录读取既有 settlement snapshot 列，不由页面重建。

`settlement-page.js` 的列表、锁定摘要和 relock 摘要只调用格式化函数显示上述字段。页面没有以 actual total 覆盖 `system_difference_cny`，没有筛除 S1-C 已计入 final due 的 overage，也没有把下一月 carryover 再叠加一次。

### 4.2 lock/relock 边界

页面通过 API 层调用：

- `school_lock_student_monthly_settlement`
- `school_relock_student_monthly_settlement`
- 既有 unlock/adjustment RPC

页面模块没有直接 `.rpc()`，也没有写入 settlement 的六个 overage snapshot 字段。lock 只提交 student、year month 与用户 note；relock 只提交 settlement id 与用户 note，S1-C DB 函数负责重新汇总并固化 snapshot。

差额调整弹窗存在一个 `system_difference_cny + 用户显式 adjustment` 的即时显示值；该值不作为 final due、carryover 或 overage 参数提交。保存仅提交用户选择/输入的 adjustment，随后重新读取 DB preview，因此持久化结算结果仍由 DB/RPC 权威计算与校验。

### 4.3 S1-C 与下一月承接

已提交的 S1-C SQL 证明：聚合 helper 只读取 S1-B 冻结字段；summary 将 overage CNY 正向加入 planned-based `final_due_cny`，actual totals 仅供信息展示；locked 月读取 snapshot。API 将 DB 返回的 `locked_carryover_cny` 原样展示，下一学生月继续通过既有 DB carryover 读取上月 locked balance 一次。

```text
settlement page
→ settlement API
→ preview / lock / relock RPC
→ S1-C aggregate / snapshot
→ next-month carryover
```

结论：月结页面能够显示已包含 overage 的 DB 权威最终余额，无需新增独立 overage UI 卡片，也无需页面/API 修改。

## 5. S1 全链状态

- S1-A：建立 nullable schema、约束与索引，不回填历史。
- S1-B：ordinary actual writer 原子生成冻结 overage bundle。
- S1-C：来源月 settlement 聚合、换算、final due、lock/relock snapshot 与既有 next-month carryover。
- S1-D：确认现有应用链没有再次阻断 actual > planned，且月结页面读取 DB 权威余额；无需代码修改。

Candidate、bill、income 和 Cash 没有直接消费 overage。下一周期收费差额只通过既有月结 carryover 承接；原账单不在 S1-D 修改。R0 未解除。

## 6. 静态检查

以下本地语法检查全部通过：

- `node --check js/pages/lesson-page.js`
- `node --check js/api/lesson-api.js`
- `node --check js/pages/settlement-page.js`
- `node --check js/api/settlement-api.js`

另经全文搜索确认：

- 两个 page module 均无 `.rpc()` 调用；
- lesson page/API 无 overage minutes、JPY、CNY、target month 计算；
- settlement page/API 不读写六个 overage snapshot 字段；
- 没有 actual duration 与 planned duration 的页面比较阻断。

未建立浏览器测试数据；根据任务边界，静态调用链和模块语法证据已足够，避免对真实 planned 或 settlement 产生写入风险。

## 7. 非阻断观察

`lesson.html` 表单说明“完整完成会生成 completed actual；勾选部分完成后，剩余时长会进入待补课余额。不会新增学生学费。”功能上不阻断 overage；其中最后一句可被理解为只描述 partial 分支，也可能被误读为描述整个弹窗。该静态文案不影响 ordinary actual > planned 调用链，且 `lesson.html` 不在本阶段允许修改文件范围，记录为后续可选文案澄清，不改变本阶段通过结论。

## 8. 最终定性与停止点

结果：`S1-D_APPLICATION_CHAIN_VALIDATED_NO_CODE_CHANGE`

功能恢复链已闭合：S1-B 允许并记录符合条件的 ordinary actual > planned，S1-C 在来源月月结中消费冻结事实并通过既有 carryover 承接下一周期，S1-D 确认页面/API 不阻断、不重算、不重复叠加。

本阶段在报告与状态文档完成后停止。未执行 Git add、commit 或 push；未进入 candidate、bill、income、Cash 或 R0 解除。

## 9. 后续approved legacy source兼容说明

S1-D完成后，真实planned `20533154-0de9-49b7-bbbd-907aa2a254ee`暴露的阻断来自S1-B DB writer原canonical-only资格，不来自页面/API。2026-07-31兼容补丁已让ordinary writer同时接受完整canonical source，以及五字段全NULL但具有唯一R1D-E-B1 approved legacy evidence并通过E-B2 resolver的source；页面/API签名和分支均未修改。因此本报告的`S1-D_APPLICATION_CHAIN_VALIDATED_NO_CODE_CHANGE`结论保持成立；该补丁当时停止于`S1-B_LEGACY_SOURCE_COMPAT_DATABASE_REVIEW_POINT`，现已由最终真实业务验收后的`ACTUAL_DURATION_OVERAGE_COMPLETE`取代。

## 10. 真实业务应用链只读验收（补充）

真实页面调用随后生成actual `4a1b74c6-65f0-4513-9c1e-4a094b7bb393`，其`planned_lesson_id`精确指向planned `20533154-0de9-49b7-bbbd-907aa2a254ee`，且该planned关联actual精确为1条。只读数据库核验确认页面输入的`2.25h / 135分钟 / JPY 10,000 / JPY 22,500`已落为`completed` actual，student month为`2026-07`，业务归属为青空进学塾；S1-B在同一actual上冻结`15分钟 / JPY 2,500 / student_duration_overage_v1 / ordinary_actual_rpc`，decided_at非NULL。planned仍为`2h / JPY 10,000 / JPY 20,000`且没有pending_makeup。

张倬闻`2026-07`只有这一条正式合格overage。S1-C只读aggregate返回`15分钟 / JPY 2,500 / CNY 107.50 / 1条`；只读settlement preview的planned base保持`JPY 520,000 / CNY 22,360.00`，无overage公式final due为`CNY 0.00`，DB final due为`CNY 107.50`，正向增量恰为overage CNY。该月settlement snapshot仍为0，没有执行lock/relock。

原canonical relation仍为1条，原bill及其既有income、School侧Cash linkage的created_at/updated_at均早于actual，没有因actual创建而新增或修改；未连接Cash DB。R0实查仍为`validation_preview_only / blocked / blocked`。该真实记录证明静态结论对应的运行链已成立，`S1-D_APPLICATION_CHAIN_VALIDATED_NO_CODE_CHANGE`不变。

来源月`2026-07`尚未锁定；未来只在正常S1-C lock/relock生命周期中固化snapshot，再由既有carryover进入下一自然月。Candidate、bill、income和Cash不直接扫描overage，原canonical bill保持不变，历史旧actual不回填、不追收。`actual < planned`仍走partial；canonical source与approved E-B1 legacy source均支持新生成overage actual。

V2无登录和宽松ACL/RLS作为已接受的内部系统技术债务保留，V3已有正式安全登录。本轮未改变安全边界或R0。最终结论：`ACTUAL_DURATION_OVERAGE_COMPLETE`。
