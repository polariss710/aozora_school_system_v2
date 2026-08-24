# Phase D 学生月度结算 页面锁定入口 —— 设计稿

- 日期：2026-08-25
- 设计：Claude Code
- 状态：**设计稿，未实现。** 第 7 节列出的假设尚未经生产验证，
  须由 Codex 的生产契约核查确认后才能开始实现。
- 部署状态请查生产，不以本文件为准（`AGENTS.md` 默认守则）。

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
| `classifySaveRecovery` | `classifyLockRecovery` |

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

### 3.2 `buildOnlineDraftLockInput({ row, status, previewResult })`

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

### 3.4 `classifyLockRecovery(beforeStatus, afterStatus, previewResult)`

```
statusConfirmsDraftLock(afterStatus, previewResult)  → "confirmed"
sameDraftVersions(before, after) 且 after 仍为 incomplete → "unchanged"
其余                                                  → "conflict"
```

- `confirmed`：提示成功，关闭对话框，刷新列表
- `unchanged`：未发生任何写入，**允许**用户重试
- `conflict`：**禁止重试**，强制刷新状态后重新预览

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
  → 失败/超时   → 一律先重读 status，用 classifyLockRecovery 判定
                  unchanged → 允许重试
                  confirmed → 按成功处理（提示已锁定）
                  conflict  → 禁止重试，强制重新预览
```

**任何情况下都不得在结果不明确时直接重试提交。** 与 save 侧
`SETTLEMENT_EDGE_RESULT_UNCERTAIN` 的处理保持一致
（`js/pages/settlement-page.js:1247`）。

表单任一项变化即作废当前 Preview 并清空确认输入框——避免用户对着旧金额
确认后提交新事实。

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

**新增断言**（本设计引入的新约束）：

1. 页面不得把确认输入框的值写入任何 `expected_*` 字段——即
   `buildOnlineDraftLockInput` 的返回值中不得出现来自 DOM 输入的金额
2. 锁定对话框必须独立于草稿对话框（两个不同的 dialog id）
3. 提交失败路径必须调用 `classifyLockRecovery`，不得直接重试

净效果：**放开的只有「lock 经 Edge 这一条受控路径」，其余边界一条未松，
另新增三条。**

## 7. 尚未经生产验证的假设

以下全部来自阅读仓库文件，按 `AGENTS.md`「生产是当前状态唯一权威」，
须由 Codex 的生产契约核查确认后才能实现：

1. `school_lock_student_monthly_settlement_online_admin` 的确切签名与校验顺序
   （仓库记录 18 个参数）
2. 生产部署的 `lock-student-settlement` Edge 是否与仓库版本一致，
   其错误码全集，以及哪些属于「结果不明确」类
3. `canonical_confirmation` 在生产的实际生成与比对位置——本设计假定页面完全
   不需要提供它
4. `status` 是否确实返回两份草稿的 `draft_id` 与 `updated_at`
5. 锁定成功后 `effective_status` 是否确实翻为 `ordinary_locked`，
   两份草稿是否确实变为 `consumed`（第 3.3 节的判定依赖此）
6. 2026-08 的 6 个活跃 scope 在 2026-09-07 之后 `can_lock` 是否确实为 true

## 8. Phase C 前置与时间约束

`docs/school-v2-student-settlement-online-phase-c-ui-20260810.md:95` 要求开放
lock 前须有一次**从页面**完成的真实 save 成功证据。Codex 已核实：经
`online_admin` 路径的成功 save 至今为 **0**。

而该证据现在无法取得：

- 2026-07 及更早的 scope 全部因已锁定 / 历史消费 / 后继冻结而 `can_save=false`
- 2026-08 在自然周封口下要到 **2026-09-07** 才开闸

因此：**代码可以现在写完，生产验收最早 2026-09-07。**
这不是排期选择，是规则决定的。

## 9. 待业务方决定（不阻塞实现）

1. **Phase C 首次真实 save 的白名单 scope**：9/7 之后 2026-08 会有 6 个活跃
   scope 同时开闸，需指定其中一个（学生 UUID + `2026-08`）。可在 9 月初再定。
2. **已锁定后需要补录或修改课时时怎么办**：走 `unlock`/`relock` 还是次月调整？
   `unlock`/`relock` 目前无任何可用通路。Phase D 上线后锁定频率会上升，
   这个问题的压力会变大。不阻塞 Phase D，但建议在上线前有答案。
