# Phase D 学生月度结算 页面锁定入口 —— 设计稿

- 日期：2026-08-25
- 设计：Claude Code
- 状态：**设计稿，未实现。** Codex 于 2026-08-25 完成生产契约核查，推翻本稿
  初版 4 处判断；修订已并入正文，见第 0 节。
- 部署状态请查生产，不以本文件为准（`AGENTS.md` 默认守则）。

## 0. 修订记录（2026-08-25）

初版依据阅读仓库文件写成，Codex 的生产只读核查推翻其中 4 处。修订已并入正文，
此处保留被推翻的内容，以免后来者重蹈。

**已由生产证据确认成立**：第 3.3 节的成功判定（`ordinary_locked` + 两份草稿
`consumed`，生产存在实例 `6ec3b815-…`）、第 2.3 节的 P0 金额边界方向、
canonical confirmation 页面无需提供（生产 wrapper 内部生成，Edge sanitizer
还会从浏览器响应中剔除）。

**被推翻并已修订的 4 处**：

| # | 初版判断 | 生产事实 | 修订位置 |
|---|---|---|---|
| 1 | 2026-09-07 开闸后 6 个 scope 自动 `can_lock=true` | `can_lock = can_save AND NOT requires_repreview`。6 个 scope 当前两份草稿均为 `null`、`requires_repreview=true`，开闸后只会 `can_save=true`。**必须先 save 再 lock** | 第 3.1、8 节 |
| 2 | 三态恢复 `confirmed / unchanged / conflict` 足够 | `sameDraftVersions + incomplete` 不等于可重试；auth/body 错误下 status 完全未变，会被误判为 `unchanged` 并允许重试原请求 | 第 3.4 节重写 |
| 3 | 「表单任一项变化即作废 Preview 并清空确认输入」 | 若包含确认金额输入框本身，用户一输入 Preview 就失效、输入被清空，流程走不完 | 第 5 节 |
| 4 | 静态断言可以守住「确认金额不进 payload」 | 那是数据流属性而非文本属性，正则无法证明金额没有经重命名或中间对象传入 | 第 6 节重写 |

第 1 条其实是好消息：它把顺序说清楚了——**9/7 开闸 → 页面 save → 才可能
lock**，与 Phase C 要求的「首次页面真实 save 证据」天然衔接，不是两件事。

**相关但已独立完成**：`SETTLEMENT_REPREVIEW_REQUIRED` 经查只在 status JSON 中
赋值、从不被 raise，因此不属于 Edge 错误映射，其文案已放入前端 `blockerLabel`。
在线结算 Edge 的错误映射已于 `816b6b6` 收口，22 个生产调用图确认可传播的 code
均有明确 `status` / `action` / 中文文案，未映射的稳定 code 也不再丢失身份。
本设计第 3.4 节的失败分流直接依据该映射的 `action` 词汇表。

## 1. 目标与范围

把「正式锁定」恢复为页面操作。后端已全部就绪：

- DB wrapper `school_lock_student_monthly_settlement_online_admin` 已部署
- Edge Function `lock-student-settlement` 已部署
- 前端 API 层 `lockStudentSettlementOnline`
  （`js/api/student-settlement-online-api.js:38`）**已写好但全项目无人调用**

缺的只有页面层的 UI 与 handler。

**不在范围**：`unlock` / `relock`。二者无 online wrapper、无 Edge、本机工具亦无
对应命令，属独立的业务模型决策，需单独审批。

## 2. 二次确认：手打结转金额（业务负责人 2026-08-25 选定）

### 2.1 为什么不用另外两种

- **沿用本机工具的精确文本**
  （`LOCK STUDENT SETTLEMENT <student> <month> MANIFEST <hash> CARRY <carry>`）：
  要求用户手抄 manifest hash，体验不可接受，且 hash 由 DB 生成、浏览器不得提交。
- **纯勾选框**：锁定不可逆（`unlock` 当前无任何通路），勾选框容易被无脑点过。

### 2.2 选定形态

对话框显著展示 DB 权威的最终结转金额，要求用户**手工输入该金额**，输入与
DB 值一致才启用锁定按钮。

### 2.3 P0 边界：输入是闸门，不是数据

**用户手打的金额绝不进入提交 payload。**

- 它只用于与 `previewResult.preview_expected_facts.final_carryover_cny` 比对，
  决定按钮 `disabled` 状态
- 提交时 `expected_final_carryover_cny` 一律取 DB 返回值
- 比对使用既有的 `canonicalDecimal()`，避免 `40000` 与 `40000.00` 判为不等

若把用户输入当作提交值，就是前端在决定持久化的业务事实，直接违反
`AGENTS.md` 的 P0 铁律。本节须有静态断言守护，见第 6 节。

`buildLockPayload`（`js/api/student-settlement-online-api.js:156`）的既有实现
已经不接受任何自由金额字段，也不接受 `canonical_confirmation`，这一层
天然拦住了误用；本设计不修改它。

## 3. 新增 state helper（与 save 侧严格对称）

`js/pages/settlement-online-state.js` 现有结构可直接对称扩展：

| 现有（save 侧） | 新增（lock 侧） |
|---|---|
| `canUseOnlineDraftSave` | `canUseOnlineDraftLock` |
| `buildOnlineDraftSaveInput` | `buildOnlineDraftLockInput` |
| `statusConfirmsDraftSave` | `statusConfirmsDraftLock` |
| `classifySaveRecovery` | `classifyLockFailure`（签名不同，见 3.4） |

`canonicalDecimal`、`sameDraftVersions`、`createSingleFlight`、`decimalString`
直接复用，不复制。

### 3.1 `canUseOnlineDraftLock(membershipRole, status)`

```
membershipRole === "admin"
  && status.can_lock === true
  && status.effective_state.effective_status === "incomplete"
  && !status.lock_blocker_code
  && !status.immutable_blocker
  && status.requires_repreview === false
```

`can_lock` 由 DB 派生（`can_save and not requires_repreview`），前端不重算。
自然周封口已在生产生效，因此 2026-08 在 2026-09-07 之前 `can_lock` 必为 false，
按钮自然禁用——**不需要前端做任何日期判断**。

**关键顺序约束**：`can_lock` 为真需要两个条件同时成立，而 2026-08 的 6 个 scope
当前两份草稿均为 `null`、`requires_repreview=true`。所以 2026-09-07 开闸**只会**
让 `can_save` 变真，`can_lock` 仍为假，blocker 是
`SETTLEMENT_REPREVIEW_REQUIRED`。用户必须先在页面完成一次 save、重读 status，
锁定按钮才可能启用。

这不是缺陷，是设计——锁定要冻结的正是那两份草稿的精确版本，没有草稿就没有可冻结
的东西。UI 上应把这一步表达清楚：`can_lock=false` 且 blocker 为
`SETTLEMENT_REPREVIEW_REQUIRED` 时，tooltip 要说「需先保存草稿」而不是笼统的
「当前不可锁定」。前端 `blockerLabel` 已有该文案。

### 3.2 `buildOnlineDraftLockInput({ row, status, previewResult, note, clientCorrelationId })`

产出 `lockStudentSettlementOnline` 所需输入。全部字段取自 `status` 与
`previewResult`，无一项由前端计算：

- 两份草稿的 `draft_id` 与 `updated_at` 取自 `status`
- 两个 manifest sha256、`expected_source_count`、6 个 expected 金额取自
  `previewResult`
- `confirmLock: true`
- `note` 取自用户输入（业务备注，非金额）
- `clientCorrelationId` 每次打开对话框时生成一次，重试沿用同一个

### 3.3 `statusConfirmsDraftLock(status, previewResult)`

判定「锁定确实落库」。与 save 侧的差异在于 lock 会产生终态，因此更好判定：

- `status.effective_state.effective_status === "ordinary_locked"`
- 且该 settlement 的 manifest 与 `previewResult` 一致
- 且两份草稿状态已由 `active` 变为 `consumed`

### 3.4 `classifyLockFailure(error, beforeStatus, afterStatus, previewResult)`

初版设计的三态（`confirmed / unchanged / conflict`）不足，已废弃。问题是
`sameDraftVersions + incomplete` **不等于可重试**：权限错误、body 校验错误发生时
status 完全没变，会被判成 `unchanged` 从而允许重试同一个必然再次失败的请求。

改为**先按 `error.action` 分流，只有真正结果不明确时才做状态比对**。
`action` 取值来自 Edge 的 `DB_ERROR_MAP`，生产实测四类：
`repreview`（20 个 code）、`stop`（13）、`refresh_status`（9）、`retry_later`（1）。

```
第一层 —— 按 error.action 分流

  stop            → "blocked"
                    权限或业务条件不满足。禁止重试。
                    展示 message，关闭提交入口，要求用户先解决前置条件。

  repreview       → "stale"
                    payload 已不代表当前事实。禁止重试旧 payload。
                    作废当前 Preview，要求重新预览并重建 input。

  retry_later     → "busy"
                    同一 scope 正被占用。等待后重读 status；
                    仅当 status 证明未发生写入时才允许重试。

  refresh_status  → 进入第二层
  无 action / 网络超时 / 响应格式无效 / 未提取到 code → 进入第二层

第二层 —— 仅对结果不明确的情况，重读 status 后判定

  status 读取失败                              → "unknown"
  statusConfirmsDraftLock(after, preview)      → "confirmed"
  严格未变（见下）                              → "retriable"
  其余                                          → "conflict"
```

「严格未变」不能只看草稿版本，必须同时满足：

- `sameDraftVersions(before, after)`
- `after.effective_state.effective_status === "incomplete"`
- `canUseOnlineDraftLock("admin", after)` 仍为真
- `after` 无任何 blocker，`requires_repreview === false`
- 两份草稿仍为 `active`
- manifest 与 expected facts 仍与本次 `previewResult` 一致

任一条不成立即归为 `conflict`。

各态的处理：

| 态 | 是否允许重试 | 动作 |
|---|---|---|
| `confirmed` | — | 按成功处理：提示已锁定、关闭对话框、刷新列表 |
| `blocked` | ❌ | 展示原因，禁用提交，不刷新 Preview |
| `stale` | ❌ | 作废 Preview，要求重新预览 |
| `busy` | ⚠️ 仅在 status 证明未写入后 | 提示稍后重试 |
| `retriable` | ✅ | 允许用户再次提交同一 payload |
| `unknown` | ❌ | **最危险的一态**：既不能确认成功也不能确认失败。禁止重试，强制刷新状态，提示「结果未确认，请勿重复锁定」 |

`unknown` 必须存在。锁定不可逆且 `unlock` 无任何通路，在结果未知时重试可能造成
无法撤销的重复尝试；宁可让用户手动刷新确认，也不能自动重试。

与 save 侧 `SETTLEMENT_EDGE_RESULT_UNCERTAIN` 的处理保持一致
（`js/pages/settlement-page.js:1247`）。

## 4. 对话框：必须独立于保存草稿对话框

`docs/school-v2-...phase-b-edge-20260809.md:121` 要求「锁定必须独立二次确认」。
现有静态断言亦禁止出现「保存并锁定」这类合并操作
（`scripts/student-settlement-online-phase-c-static-test.mjs:19`）。

新增 `#settlementLockDialog`，与 `#settlementAdjustmentDialog` 完全分离：

```
标题        正式锁定月结（不可撤销）
只读展示    学生 / 月份 / 系统差额 / 最终结转（DB 权威，显著）
警示        锁定后不可撤销。当前系统未开放解锁与重新锁定。
确认输入    请输入上方最终结转金额以确认    [____________]
备注        业务备注（可选）
底部        [取消]  [确认锁定]（默认 disabled）
```

「确认锁定」的启用条件：

```
canUseOnlineDraftLock(...)
  && 已有与当前输入匹配的最新 Preview
  && canonicalDecimal(用户输入) === canonicalDecimal(DB 最终结转)
  && !isLockSubmitting
```

`disabled` 时的 tooltip 需区分原因：非 admin / DB 不允许 / 需重新预览 /
确认金额不匹配。

## 5. Handler 流程

```
打开对话框
  → 读 status（DB 权威）
  → 读 Preview（DB 权威）
  → 展示只读事实 + 确认输入框
  → 用户输入结转金额 + 可选备注
  → 校验：金额匹配 && can_lock && 有匹配 Preview
  → single-flight 提交（复用 createSingleFlight，防双击）
  → 成功        → 提示 + 关闭 + 刷新列表
  → 失败/超时   → 一律经 classifyLockFailure 分流，见 3.4
                  unchanged → 允许重试
                  confirmed → 按成功处理（提示已锁定）
                  conflict  → 禁止重试，强制重新预览
```

**任何情况下都不得在结果不明确时直接重试提交。**

### 5.1 什么会作废 Preview，什么不会

初版写的「表单任一项变化即作废 Preview 并清空确认输入」是自相矛盾的：确认金额
输入框本身也是表单项，用户一开始输入 Preview 就失效、输入被清空，流程永远走不完。

正确划分依据是**该输入是否参与 DB Preview 的计算**：

| 输入 | 变化时 | 理由 |
|---|---|---|
| 学生 / 月份 / 任何影响 DB Preview 的业务选择 | **作废 Preview，并清空确认输入** | 权威事实变了，之前确认的金额不再对应当前事实 |
| 确认金额输入框 | 不作废 | 它是闸门，不参与任何计算 |
| 业务备注 | 不作废 | 不进 Preview，只随 payload 提交 |

清空确认输入必须与作废 Preview 同时发生——否则用户会对着**旧金额**的确认状态
提交**新事实**，那正是这道闸门要防的。

锁定对话框的输入面本来就很窄（只有确认金额与备注），业务选择在保存草稿阶段
就已固定。因此实践中这一节主要是防止对话框在打开期间被外部状态刷新后，
确认状态却残留。

## 6. 静态断言改写（6 处）

| 位置 | 现状 | 改后 |
|---|---|---|
| `settlement-trusted-tool-static-test.mjs:19` | `doesNotMatch(page, /data-lock-settlement-id=/)` | 删除；改为断言锁定按钮存在且 `disabled` 由 `can_lock` 驱动 |
| `settlement-trusted-tool-static-test.mjs:31` | `doesNotMatch(page, /lockStudentSettlementOnline\|lock-student-settlement/)` | 反转为 `assert.match(page, /lockStudentSettlementOnline\(lockInput\)/)` |
| `student-settlement-online-phase-b-static-test.mjs:251` | 同上 | 同上 |
| `student-settlement-online-phase-b-static-test.mjs:252` | `doesNotMatch(pageSource, /lock-student-settlement/)` | 收窄为「除 `settlement-page.js` 外，其余页面模块不得出现」 |
| `student-settlement-online-phase-c-static-test.mjs:18` | 同 :31 | 同 :31 |
| `student-settlement-online-phase-c-static-test.mjs:19` | `doesNotMatch(html, /data-lock-settlement\|lockSettlementDialog\|保存并锁定/)` | 收窄为 `doesNotMatch(html, /保存并锁定/)`；允许 `lockSettlementDialog` |

**继续守着、一条不动**：

- 5 个 core writer 禁令与 `.rpc()` 禁令
  （`settlement-trusted-tool-static-test.mjs:20-29`）
- 详情页保持完全只读（`phase-c-static-test.mjs:20`）
- **`canonical_confirmation` 不得出现在页面**（`phase-c-static-test.mjs:24`）
- `state` 模块禁止 `Math.round / parseFloat / Number(`
  （`phase-c-static-test.mjs:26`）
- 全部 `service_role` 禁令

**新增约束**（本设计引入）：

1. 锁定对话框必须独立于草稿对话框（两个不同的 dialog id），且两者的提交
   handler 不得共用
2. 提交失败路径必须经 `classifyLockFailure` 分流，不得直接重试
3. 页面不得把确认输入框的值写入任何 `expected_*` 字段 —— 见下节，
   这一条**不能靠静态断言表达**

### 6.1 「确认金额不进 payload」为什么不能只靠断言

初版把它写成一条静态断言。那是错的：「这个值不来自 DOM」是**数据流属性**，
静态正则最多证明 builder 源码里没有出现某个 DOM 变量名，无法证明该金额没有经
重命名、中间对象或参数间接传入 `expected_final_carryover_cny`。

改为三层，靠结构而非检查：

**第一层 —— 让错误代码写不出来。**
`buildOnlineDraftLockInput` 定义为纯函数，签名只接受
`{ row, status, previewResult, note, clientCorrelationId }`。
**确认金额根本不在参数表里**，函数内部拿不到它。这一层不是断言，是不可能性。

**第二层 —— sentinel 集成测试。**
构造 DOM 确认输入为 `999999.123`、DB Preview 的 `final_carryover_cny` 为
`40000.00`，走完整提交流程，捕获传给 `lockStudentSettlementOnline` 的完整 input：

- 断言 `expected_final_carryover_cny === "40000.00"`
- 递归遍历整个 input，断言**任何层级**都不含 sentinel 值 `999999.123`

sentinel 选成非法金额形态（三位小数），确保它一旦泄漏必然可辨认。

**第三层 —— API 层 exact-key 断言。**
对 `buildLockPayload` 的返回值做精确键集比对：键集必须与契约完全一致，不多不少。
额外断言不含 `canonical_confirmation`、不含任何确认输入相关字段。

第一层是主要保障，二三层是回归网。**只有第二层能真正证明数据流**，因此它是
Phase D 验收的必要项，不能因为「静态测试已绿」而跳过。

净效果：放开的只有「lock 经 Edge 这一条受控路径」，其余边界一条未松，
另新增上述三条约束。

## 7. 生产验证状态

初版列出的 6 项假设已由 Codex 于 2026-08-25 完成生产只读核查。

**已确认成立（可直接依赖）**：

1. `school_lock_student_monthly_settlement_online_admin` 确为 18 参数，
   `security definer`、owner `postgres`，校验顺序共 15 步；owner writer 自身
   还有第二层校验。
2. `lock-student-settlement` 与 `save-student-settlement-draft` 已于 `816b6b6`
   重新部署为 ACTIVE v3 —— 这同时消除了「生产 Edge 是否与仓库一致」的不确定性，
   因为部署之后生产即为本仓库版本。错误码映射已收口，22 个生产调用图确认可传播
   的 code 均有明确 `status` / `action` / 中文文案。
3. `canonical_confirmation` 由生产 wrapper 在 expected facts 核验之后内部生成，
   不是参数、不与页面输入比较，Edge sanitizer 还会从浏览器响应中剔除。
   **页面完全不需要提供它**，`buildLockPayload` 中确无该字段。
4. `status` 确实返回两份草稿的 `draft_id`、`status` 与 `updated_at`。
5. 锁定成功后 `effective_status` 确为 `ordinary_locked`，adjustment draft 由
   writer 改为 `consumed`，source draft 由 `school_tuition_p0f_settlement_after`
   trigger 改为 `consumed`。生产存在实例 `6ec3b815-…`（彭宇晗 2026-07）。

**已被否定**：

6. 「2026-08 的 6 个 scope 在 2026-09-07 之后 `can_lock` 为 true」不成立。
   见第 0 节第 1 条与第 3.1 节。

**仍未验证、需在实现阶段处理**：

- 第 6.1 节第二层的 sentinel 集成测试尚未编写，那是唯一能真正证明确认金额不进
  payload 的手段。
- `classifyLockFailure` 的六态划分是否覆盖全部真实失败模式，须在实现后用
  Edge 的实际错误码逐条走查。设计依据是 `DB_ERROR_MAP` 的四类 `action`，
  但「某个具体 code 在什么条件下出现」仍需实测。

## 8. Phase C 前置与时间约束

`docs/school-v2-student-settlement-online-phase-c-ui-20260810.md:95` 要求开放
lock 前须有一次**从页面**完成的真实 save 成功证据。Codex 已核实：经
`online_admin` 路径的成功 save 至今为 **0**。

而该证据现在无法取得：

- 2026-07 及更早的 scope 全部因已锁定 / 历史消费 / 后继冻结而 `can_save=false`
- 2026-08 在自然周封口下要到 **2026-09-07** 才开闸

Codex 核查后这条链更清楚了，Phase C 与 Phase D 不是两件事而是同一条：

```
2026-09-07 00:00 JST   自然周封口开闸，6 个 scope 变为 can_save=true
                       此时 can_lock 仍为 false，blocker 是
                       SETTLEMENT_REPREVIEW_REQUIRED（两份草稿均为 null）
        ↓
页面完成一次真实 save   → 这就是 Phase C 要求的前置证据
                       → 两份草稿产生，requires_repreview 变为 false
        ↓
重读 status            can_lock 才可能为 true，锁定按钮启用
        ↓
页面 lock              Phase D 生产验收
```

因此：**代码可以现在写完，生产验收最早 2026-09-07，且当天必须先 save 再 lock。**
这不是排期选择，是规则决定的。

实现阶段可以做完的：UI、handler、state helper、静态测试、第 6.1 节第一与第三层。
必须等到 9/7 之后的：sentinel 集成测试的真实数据部分、`classifyLockFailure` 的
实际错误码走查、Phase C 首次 save、Phase D 首次 lock。

## 9. 待业务方决定（不阻塞实现）

1. **Phase C 首次真实 save 的白名单 scope**：9/7 之后 2026-08 会有 6 个活跃
   scope 同时开闸，需指定其中一个（学生 UUID + `2026-08`）。可在 9 月初再定。
2. **已锁定后需要补录或修改课时时怎么办**：走 `unlock`/`relock` 还是次月调整？
   `unlock`/`relock` 目前无任何可用通路。Phase D 上线后锁定频率会上升，
   这个问题的压力会变大。不阻塞 Phase D，但建议在上线前有答案。
