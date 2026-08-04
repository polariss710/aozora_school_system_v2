# School V2 Cash 支出“保存/提交 Cash”拆分实施报告（2026-08-04）

## 结论

“保存待支付支出”和“提交 Cash”已拆为两个独立动作并上线，技术结论为 **Go**。新增弹窗只保存 School `pending/manual_cash`；Cash 确认弹窗只能由用户随后从列表单条、批量或详情入口主动打开。本轮生产业务写入、DB migration、Edge 修改和 Edge 部署均为 0。

## 1. 实时 Git 与部署基线

- 初始分支：`main`。
- 初始 HEAD / `origin/main`：`5f14b44dc019a620c27f5b76361668eacab6f7d1`，ahead/behind `0/0`。
- 初始工作区只有六份受保护 untracked 文件。
- 初始页面 `v10.5.4`，初始 Pages run `30886157283`。
- Edge：`request-cash-expense-confirmation v4`、`sync-cash-request-result v8`，本轮定义与版本未改变。
- Gate：`student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`。

## 2. 原自动串联位置

修改前 `js/pages/expense-page.js` 的 `submitCreateExpense()` 在 `createPendingCashExpenseRecord(payload)` 成功后，立即用返回的 `pendingExpense` 调用：

```js
openBatchCashExpenseDialog([pendingExpense], { origin: "new-cash-expense" });
```

该调用会自动打开既有 Cash 确认弹窗；用户仍需在弹窗中确认后才会调用 Edge，但这违反“保存”和“提交 Cash”必须分开的新交互合同。原 `batchCashExpenseOrigin`、取消提示和专用失败提示均只为这条自动串联服务，现已删除。

## 3. 修改后的两步调用链

### 保存 School pending

页面 Cash 模式 → `createPendingCashExpenseRecord(payload)` → DB `school_create_pending_cash_expense_record_v1(...)` → 关闭新增弹窗 → 刷新当前列表/筛选 → 显示“已保存、尚未提交 Cash”提示。

保存阶段不会调用 `openBatchCashExpenseDialog()`、`requestCashExpenseConfirmation()` 或 `request-cash-expense-confirmation`，不会生成 Cash attempt/event/request/transaction，也不会自动选中新记录。

### 用户主动提交 Cash

列表单条“提交Cash”、checkbox +“批量提交 Cash”或详情页提交 → 打开既有 Cash 确认流程 → 用户确认 → `requestCashExpenseConfirmation()` → 既有 Edge/prepare/submitted/confirmed/rejected/sync 状态机。

School 直接支付路径完全不变：`createExpenseRecord(payload)` → `school_create_expense_record(...)` → paid → 一次余额扣减 + 一条 School 流水。

## 4. 修改文件

UI 检查点修改 5 个文件：

- `expense.html`
- `js/config.js`
- `js/expense-app.js`
- `js/pages/expense-page.js`
- `scripts/cash-expense-create-static-test.mjs`

文档封口新增/修改：本报告、`docs/current-status.md`，并在前一轮实施报告中加入后续交互变更提示。SQL、API、详情页业务代码、Edge、Cash 应用、CSS 和 `js/legacy-core.js` 均未修改。

## 5. 最终按钮和提示

- School 选项及说明保持：`从 School 账户直接支出` / `保存后立即记为已支付，并扣减 School 账户余额。`
- School 按钮保持：`保存 School 支出`。
- Cash 选项说明：`保存为待支付支出，不会扣减 School 账户余额。保存后可从支出列表单独提交至 Cash。`
- Cash 按钮：`保存待支付支出`。
- Cash 保存成功：`支出已保存为待支付记录，尚未提交 Cash。请从支出列表单独提交至 Cash。`
- 若当前筛选未显示新记录，提示用户调整月份/筛选；若刷新失败，提示刷新页面。均提供详情链接，不自动改变筛选业务事实。
- 页面不再包含 `保存并提交至 Cash` 或创建成功后“已提交 Cash 待审批”的表达。

## 6. Client request identity 生命周期

- 每次打开新增弹窗仍执行一次 `crypto.randomUUID()`，作为本次创建的稳定 identity。
- `isCreateSubmitting` 在请求期间禁用重复提交；网络层重试继续复用 payload 中的同一 identity。
- 同 identity/同 payload 的 DB 幂等合同不变，异 payload 仍 fail-closed。
- 保存成功后先解除 submitting，再关闭弹窗并清空本次 identity；下次打开生成新 UUID。
- Cash event/request identity 仍由既有 Cash 提交流程独立生成，不复用 creation identity。

## 7. Pending 列表状态与可提交逻辑

- 保存成功后调用 `refreshCurrentExpenseList()`，重新加载当前月份、恢复筛选并重新渲染。
- DB canonical `status=pending/source_type=manual_cash` 且无 reverse/transaction、Cash request status 非 pending/approved/synced 时，`canRequestCashExpense()` 将其计入“可提交 Cash”。
- 同一判定驱动列表 checkbox、单条“提交Cash”和批量按钮；详情页沿用同一来源/状态边界。
- 列表展示无 Cash request/transaction 的记录为“待支付 / Cash未提交”；不会把它误标为待确认、paid、rejected 或 reversed。
- 保存代码没有 `selectedExpenseIds.add(...)`，不会自动勾选或提交。

## 8. School 路径回归

Cash 分支之外的 `createExpenseRecord(payload)`、成功刷新和 `showExpenseCreateSuccess()` 未改变。School 默认 radio、说明、账户/支付方式字段和 `保存 School 支出` 按钮均通过静态及 Chrome 验收。本轮未实际创建 School 支出，因此生产余额与流水变化为 0。

## 9. 单条、批量、详情 Cash 回归

- 列表单条仍通过 `data-expense-cash-request-id` 打开既有 `openBatchCashExpenseDialog([expense])`。
- 批量仍按 checkbox 选择并在用户确认后逐条调用 `requestCashExpenseConfirmation(item.payload)`。
- 详情页仍只对 `manual_cash/teacher_wage + pending + 无终态 Cash linkage` 开放入口，并调用既有 expense detail API/Edge。
- Cash reject/approve/retry/sync、老师工资链和 active-admin 权限代码均未修改。

## 10. 测试与 Chrome

- `node --check`：`expense-page.js`、`expense-app.js`、`config.js`、静态测试均通过。
- `cash-expense-create-static-test.mjs`：验证创建分支只调用 pending writer、刷新列表、显示未提交提示；显式拒绝自动打开/自动 request、自动选中及旧文案；验证单条/批量/详情提交入口仍存在。
- `p0-expense-permission-static-test.mjs`、phase2、G1-B1 admin Cash 静态回归全部通过。
- 生产 Chrome：active admin、`v10.5.5`；默认 School 文案/按钮正确；切换 Cash 后精确说明与 `保存待支付支出` 正确，School 字段 disabled/hidden、Cash 币种可用，批量 Cash 弹窗保持关闭。未点击保存，点击取消后弹窗关闭；Console error/warning 为 0。

## 11–14. DB、Edge 与生产写入

- DB migration：0；SQL/RPC 定义执行：0；write RPC 调用：0。
- Edge 修改：0；Edge 部署：0。
- School 生产业务写入：0。
- Cash 生产业务写入：0。

本轮仅执行 School/Cash `REPEATABLE READ READ ONLY` 基线与终态 SELECT。

## 15. 合法业务记录与待确认请求

前后 School 指纹完全一致：

- 支出 47，hash `34a7a32319d8e538ef7997e1ba59c9d4`。
- `manual_cash=1`，状态仍为 `pending/Cash pending`；现有已撤销记录保持不变。
- 账户 3，hash `ac9fa3e0b92dde16dddfffff2c70c222`。
- School 流水 187，hash `00516a76f236d51406c82f37b0e468ee`。

前后 Cash 指纹完全一致：

- expense request 18：pending 1、approved 15、rejected 2，hash `ed52e53e332eb82f775c5e4b44b6b605`。
- CNY expense transaction 12，hash `912c514fe973023f567036e1e8c36df2`。
- JPY expense transaction 3，hash `654485db35df0657c0bf7121d464baa3`。

业务负责人刚完成验收的记录和待确认 request 未被删除、撤销、重提、批准、拒绝或修改。

## 16–17. Gate 与 Storage

- Gate 前后均为 `enabled / blocked / enabled`，变化 0。
- 30 个历史 Storage orphan 保持不变；Storage API 调用和对象写入均为 0。

## 18. 六份受保护文件

| 文件 | SHA-256 |
| --- | --- |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 19–22. 发布终态

- UI commit：`b788b520808784c0f5213d97dc803db6ef8793b9`，已 push。
- UI Pages run：`30889444439`，success。
- 页面最终版本：`v10.5.5`。
- 文档封口 commit、最终 Pages run、最终 HEAD/origin/ahead-behind 在最终对话报告给出。
- 最终判定：**保存支出与提交 Cash 已成功拆分并上线，无后端状态机阻塞。**
