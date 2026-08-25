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

### 第二轮修订（同日，Codex 复审）

第一轮修订本身又被查出 5 处，其中 3 处 P1。这几条戳中的都是「我以为如此、
未经查证」的判断：

| # | 第一轮的说法 | 实测事实 | 修订位置 |
|---|---|---|---|
| 5 | 超时后「严格未变」可判 `retriable` | `invokeSettlementEdge` 用 `Promise.race`，**全文件无 `AbortController`**。超时只停止等待，底层请求仍在继续，可能稍后落库。「此刻未变」证明不了「将来不变」 | 3.4 重写 |
| 6 | 纯函数签名让错误代码写不出来 | JS 参数表证明不了对象来源。调用方可先把 DOM 值写进可变的 `previewResult` 再传入 | 6.1 重写为冻结快照 |
| 7 | sentinel 用 `999999.123`，是非法金额形态 | `DECIMAL_RE` 允许任意位小数，它是**合法**的；且与 DB 值不匹配时按钮禁用、API 根本不被调用——**该测试空转,不接触被测代码就通过** | 6.1 拆为三个测试 |
| 8 | 靠 `blockerLabel` 表达 9/7 顺序引导 | `onlineStatusDisplay()` 只读 `save_blocker_code`，从不读 `lock_blocker_code`，该路径走不到 | 3.1 |
| 9 | sentinel 测试要等 9/7 | 它本就不该用生产数据，现在即可全部写完 | 第 8 节 |

另有两处遗漏已补：`action` 词汇表漏了 Edge 自身使用的 `reauthenticate`
（初版只从 `DB_ERROR_MAP` 推导）；「严格未变」的判据从 6 条扩到 9 条，
其中「不得写死 `"admin"` 而应使用当前真实角色」与「物理 settlement 行仍不存在」
是初版完全没想到的。

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
的东西。

**但初版说「靠 `blockerLabel` 表达即可」是错的，那条路径走不到。**
`onlineStatusDisplay()` 只读 `status.save_blocker_code`
（`js/pages/settlement-online-state.js:133-135`），从不读 `lock_blocker_code`。
9/7 开闸后 `save_blocker_code` 会变成 null，而 `lock_blocker_code` 才是
`SETTLEMENT_REPREVIEW_REQUIRED`——现有代码根本不会展示它。

而且**只靠禁用按钮的 tooltip 也不够**：触屏没有 hover，键盘用户也拿不到。

因此需要两处改动：

1. `onlineStatusDisplay()` 增加读取 `lock_blocker_code` 的分支，使锁定相关的
   blocker 能进入展示模型
2. 锁定按钮旁必须有**始终可见**的静态提示（不是 tooltip）：

   > 下一步：请先完成预览并保存草稿。保存成功并刷新状态后，才可正式锁定。

可以附带「前往保存草稿」的焦点/滚动引导，但**不得自动触发 save**——保存是
业务写操作，必须由用户显式发起。

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

改为**先按错误来源与 `error.action` 分流**。关键区分是「请求已明确终止」与
「请求结果未知」——初版把两者混在一起，这是最危险的错误。

`action` 取值：`DB_ERROR_MAP` 实测四类（`repreview` 20、`stop` 13、
`refresh_status` 9、`retry_later` 1），另有 Edge 自身使用的 `reauthenticate`。
初版只从 `DB_ERROR_MAP` 推导，漏掉了后者。

#### 前提：超时不取消请求

`invokeSettlementEdge` 用 `Promise.race([invocation, timeout])` 实现超时，
全文件无 `AbortController`、无 `signal`。**超时只是停止等待，底层 Edge 调用
仍在继续，可能稍后落库。**

因此**网络超时、连接断开、响应格式无效这三类，永远不得产生 `retriable`**。
此时读到「严格未变」只说明「此刻还没落库」，证明不了「将来不会落库」。
对一个不可逆且无 `unlock` 通路的操作，这个区别就是重复锁定与否的区别。

```
第一层 —— 按错误来源分流

  【Edge 明确响应，请求已终止】

  stop / reauthenticate  → "blocked"
                    权限或业务条件不满足。禁止重试。
                    reauthenticate 额外提示重新登录。

  repreview       → "stale"
                    payload 已不代表当前事实。禁止重放旧 payload。
                    作废 Preview，要求重新预览并重建 input。

  retry_later     → "busy"
                    本次事务已失败，但并发持有者可能正在写。
                    等待后重新读取 status 与 Preview，**构建新 input**，
                    不得直接重放旧 payload。

  refresh_status  → 进入第二层。注意不能默认「未变即可重试」——
                    服务器配置错误、结构性 blocker 会永久失败，
                    需按具体 code 判断。

  【请求是否落库未知】

  网络超时 / 连接断开 / 响应格式无效 / 未提取到 code
                  → 进入第二层，但**结果只能是 confirmed / unknown /
                    conflict，永远不产生 retriable**

第二层 —— 重读 status 后判定

  status 读取失败                         → "unknown"
  statusConfirmsDraftLock(after, preview) → "confirmed"
  严格未变（见下）且来源为 Edge 明确响应   → "retriable"
  严格未变但来源为超时/断线/响应无效       → "unknown"
  其余                                     → "conflict"
```

#### 「严格未变」的判据

初版只列了 6 条，不够。必须同时满足：

- `sameDraftVersions(before, after)`
- `after.effective_state.effective_status === "incomplete"`
- **物理 settlement 行仍不存在**（lock 的直接后果就是创建它）
- `canUseOnlineDraftLock(当前真实 membershipRole, after)` 仍为真
  —— **不得写死 `"admin"`**，必须用当前会话的实际角色，否则角色在此期间
  变化时会误判
- `after` 的 `status.contract_version` 与 `before` 一致
  —— 契约版本变化意味着语义可能已变，不能跨版本比较
- `student_id` / `settlement_month` / `business_entity_id` 三者与本次请求一致
- `after` 无任何 blocker，`requires_repreview === false`
- 两份草稿仍为 `active`，且 `draft_id`、`updated_at`、`status` 三项均一致
- 本次 payload 中**全部**字段仍与 `after` 一致：两个 manifest sha256、
  `expected_source_count`、6 个 expected 金额，逐项比对

任一条不成立即归为 `conflict`。

各态的处理：

| 态 | 是否允许重试 | 动作 |
|---|---|---|
| `confirmed` | — | 按成功处理：提示已锁定、关闭对话框、刷新列表 |
| `blocked` | ❌ | 展示原因，禁用提交，不刷新 Preview |
| `stale` | ❌ | 作废 Preview，要求重新预览 |
| `busy` | ⚠️ 需重建 input | 等待后重读 status 与 Preview，**用新 input 提交**，不重放旧 payload |
| `retriable` | ✅ | 允许再次提交同一 payload。**仅当来源是 Edge 明确响应时才可能到达此态** |
| `unknown` | ❌ | 既不能确认成功也不能确认失败。锁定入口保持禁用，只提供只读的「再次检查状态」按钮，提示「结果未确认，请勿重复锁定」 |

`unknown` 必须存在，而且它的入口比初版宽——所有超时与断线都落在这里，
不再有机会被判成 `retriable`。锁定不可逆且 `unlock` 无任何通路，在结果未知时
重试可能造成无法撤销的重复尝试；宁可让用户手动刷新确认，也不能自动重试。

`unknown` 态下**不得关闭对话框**，也不得清空已展示的事实——用户需要这些信息
来判断刚才那次到底成没成。

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
  → structuredClone + 递归冻结，得到模块私有权威 snapshot（见 6.1）
  → 展示只读事实 + 确认输入框
  → 用户输入结转金额 + 可选备注
  → 校验：canonicalDecimal 判等 && can_lock && 有匹配 Preview
  → single-flight 提交（复用 createSingleFlight，防双击）
  → 成功        → 提示 + 关闭 + 刷新列表
  → 失败/超时   → 一律经 classifyLockFailure 分流，见 3.4
                  该函数返回六态之一，不得在此处自行判断
```

六态的具体处理见 3.4 的表格。此处只强调两条：

- **`retriable` 只可能来自 Edge 的明确响应。** 超时与断线一律落在 `unknown`，
  因为超时不取消底层请求。
- **`unknown` 时不关闭对话框、不清空已展示事实**，用户需要它们判断刚才那次
  到底成没成。

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

**「纯函数签名让错误写不出来」也是错的**（初版第一层，已废弃）。
`buildOnlineDraftLockInput` 的参数表里没有确认金额，但调用方完全可以先把 DOM
值写进可变的 `previewResult` 再传进来。**JS 的参数表证明不了对象来源。**

改为三层，第一层从「签名约束」换成「不可变权威快照」：

**第一层 —— 权威事实一经取得即冻结。**

- API 返回 `status` 与 `previewResult` 后，立即 `structuredClone` 并**递归
  冻结**（`Object.freeze` 深度遍历），得到权威 snapshot
- snapshot 存在模块私有作用域，不暴露给渲染层
- 渲染用的展示模型、确认输入的值、权威 snapshot **三者分开保存**，渲染层
  拿到的是展示模型的副本，改它不影响 snapshot
- `buildOnlineDraftLockInput` 只接受该私有冻结 snapshot
- 提交前再复核一次 snapshot 的 signature 与 status 契约版本

冻结之后，「render 之后篡改 previewResult」在严格模式下会抛错，在非严格模式下
静默失败——两种情况 payload 都拿不到被篡改的值。这才是结构约束。

**第二层 —— 三个真实的集成测试。**

初版的单个 sentinel 测试是**空转的**：`999999.123` 与 DB 的 `40000.00` 不匹配，
按钮理应禁用，API 根本不会被调用，测试不接触被测代码就通过。而且
`DECIMAL_RE = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/` 允许任意位小数，
`999999.123` 是**合法**金额字符串，初版称其为「非法形态」也是错的。

拆成三个各自能失败的测试：

| # | 场景 | 断言 |
|---|---|---|
| 1 | 不匹配 sentinel：DOM 输入 `999999.123`，DB `40000.00` | 按钮 `disabled`，且 `lockStudentSettlementOnline` 调用次数为 **0** |
| 2 | 等值但字符串不同：DOM 输入 `40000.000`，DB `40000.00` | 闸门放行（`canonicalDecimal` 判等），但 payload 的 `expected_final_carryover_cny` 必须是 **DB 原值 `40000.00`**，且递归遍历 payload 各层级不得出现字符串 `40000.000` |
| 3 | render 后篡改冻结 snapshot | 提交必须被拒绝，或强制作废 Preview；payload 不得包含被篡改的值 |

**第 2 个是关键**——那是闸门放行、但值仍可能泄漏的唯一窗口。初版完全没有覆盖到
这个场景，因为它的 sentinel 永远过不了闸门。

**第三层 —— API 层 exact-key 断言。**
对 `buildLockPayload` 的返回值做精确键集比对：键集必须与契约完全一致，不多不少。
额外断言不含 `canonical_confirmation`、不含任何确认输入相关字段。

三层都是必要项。第一层防住绝大多数写法，第二层的三个测试是唯一能真正证明数据流
的手段，第三层守住契约边界。**不能因为「静态测试已绿」而跳过第二层。**

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

**现在就能全部做完的**（初版把这部分切错了，sentinel 测试并不需要等 9/7，
它本就不该使用生产数据）：

- UI、handler、state helper
- 静态测试与断言改写
- 第 6.1 节的三层全部：冻结快照、三个集成测试、API 层 exact-key 断言
- `classifyLockFailure` 的六态矩阵测试——用 mock 的 status / Preview /
  各类 `action` 构造，不需要真实错误

**必须等到 2026-09-07 之后的，只有四项**：

1. 指定白名单 scope 的首次真实页面 save（Phase C 前置证据）
2. save 后复核生产 status 的 `can_lock` 是否确实变为 true
3. 首次真实页面 lock，及写后验收
4. 仅限**安全可构造**的生产错误路径复验

第 4 项要划清界限：**不得为了覆盖某个错误码而人为制造业务不变量异常**。
错误码矩阵靠 mock 覆盖，生产只验证那些不需要破坏数据就能触发的路径。

## 9. 待业务方决定（不阻塞实现）

1. **Phase C 首次真实 save 的白名单 scope**：9/7 之后 2026-08 会有 6 个活跃
   scope 同时开闸，需指定其中一个（学生 UUID + `2026-08`）。可在 9 月初再定。
2. **已锁定后需要补录或修改课时时怎么办**：走 `unlock`/`relock` 还是次月调整？
   `unlock`/`relock` 目前无任何可用通路。Phase D 上线后锁定频率会上升，
   这个问题的压力会变大。不阻塞 Phase D，但建议在上线前有答案。
