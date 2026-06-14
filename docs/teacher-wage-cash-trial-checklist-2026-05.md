# 2026-05 Teacher Wage Cash 试运行前 Checklist

Status date: 2026-06-14

## 0. 文档目的

本 checklist 用于在执行真实 2026-05 老师工资 Cash 确认试运行前，确认 School System 与 Cash System 的数据、口径、账户白名单、回写流程、rollback 方案均处于安全状态。

本 checklist 只用于试运行前确认，不直接执行 approve / reject / rollback 操作。

## 1. 当前阶段确认

- 老师工资全量 Cash 化功能已完成。
- 所有 `teacher_wage` 类型 payment request 均可走 Cash 确认。
- 不再限制为 personal + JPY。
- 支持 JPY / CNY。
- 支持个人归属、青空塾归属、混合归属。
- Cash 账户可用范围由 `allow_school_requests = true` 白名单控制。
- Cash approve 后才写入 Cash transaction。
- Cash approve 后才改变 Cash 账户余额。
- Cash approve 后才回写 School payment request 为 `paid`。
- Cash reject 后不写 transaction。
- Cash reject 后不改变 Cash 账户余额。
- Cash reject 后 School payment request 保持 `pending`。
- rejected attempt 可重新提交新 attempt。
- 旧 rejected attempt 保留为历史。
- 同一 payment request 同一时间只允许一个 active attempt。
- rejected -> retry -> approved E2E 已完成。
- rollback E2E 已完成。
- JPY request rollback E2E 已完成。
- CNY request rollback E2E 已完成。
- cleanup 后残留数据为 0。
- 目前未使用真实 2026-05 工资数据做测试。

## 2. 本次试运行范围

### 2.1 试运行对象

- 对象月份：2026-05
- 对象类型：老师工资
- School request 类型：`teacher_wage`
- Cash 处理方式：由 Cash 用户 approve / reject
- Cash transaction 写入目标：
  - JPY：`home_jpy_transactions`
  - CNY：`home_cny_transactions`

### 2.2 本次不包含

- 不处理学费收入 Cash 化。
- 不处理内部平账。
- 不处理法人账户清算统计排除。
- 不处理 CNY/JPY 换汇统计排除。
- 不处理账户调拨统计排除。
- 不处理代收款清算统计排除。
- 不处理垫付款回收统计排除。
- 不修改利润统计口径。
- 不修改工资计算逻辑。
- 不修改工资锁定逻辑。

## 3. 业务口径确认

### 3.1 School System 口径

- School System 是业务账。
- School 记录老师工资业务事实。
- School 记录学生、老师、月份、业务归属、成本归属。
- School 记录法人账户相关清算信息。
- School 不维护 Cash 账户余额。
- School payment request 只是业务侧支付请求，不等于真实账户流水。
- School payment request 只有在 Cash approve 后才可视为真实支付完成。

### 3.2 Cash System 口径

- Cash System 是家庭 / 私人真实账户流水账。
- Cash 记录支付宝系账户、日元现金、日元银行等真实账户变化。
- Cash 只接受 School 等外部系统发来的 request。
- Cash 用户 approve 后才生成 transaction。
- Cash 用户 approve 后才改变账户余额。
- Cash 用户 reject 后不生成 transaction。
- Cash 用户 reject 后不改变账户余额。
- Cash 不主动生成 School 业务 request。

## 4. Cash 可用账户白名单确认

### 4.1 School 可使用账户

以下账户应满足 `allow_school_requests = true`：

- 余额宝，币种 CNY
- 日元现金，币种 JPY
- 日元三菱卡，币种 JPY
- 日元乐天卡，币种 JPY

### 4.2 School 不可使用账户

以下账户不应出现在 School 可选账户中：

- 余利宝
- 医生处兑换日元先行支付

### 4.3 白名单检查项

- School 前端账户下拉只显示 `allow_school_requests = true` 的账户。
- School 后端 / RPC / Edge Function 不接受非白名单账户。
- 非白名单账户即使前端绕过，也不能提交成功。
- 账户币种与 payment request 币种必须一致。
- JPY payment request 不能提交到 CNY 账户。
- CNY payment request 不能提交到 JPY 账户。

## 5. 真实 2026-05 工资数据确认

### 5.1 工资锁定状态

- 2026-05 老师工资已计算完成。
- 2026-05 老师工资已人工核对。
- 2026-05 老师工资已锁定。
- 锁定后工资金额不再自动变动。
- 锁定后课时修正不会影响本次试运行数据。
- 锁定金额与工资结算画面显示一致。
- 锁定金额与 payment request 金额一致。

### 5.2 老师维度确认

逐个老师确认：

- 老师姓名正确。
- 老师归属正确：个人 / 青空塾 / 混合。
- 工资月份为 2026-05。
- 工资金额正确。
- 币种正确：JPY / CNY。
- 支付账户正确。
- 成本归属正确。
- payment request 未重复生成。
- payment request 当前状态正确。

### 5.3 金额合计确认

- School 工资结算画面合计金额正确。
- payment request 合计金额正确。
- JPY 合计金额正确。
- CNY 合计金额正确。
- 个人归属合计正确。
- 青空塾归属合计正确。
- 混合归属拆分合计正确。

## 6. 试运行前 DB 状态检查

### 6.1 School 侧检查

- 不存在 2026-05 `teacher_wage` 的重复 payment request。
- 不存在异常 `paid` 状态但 Cash 无 transaction 的记录。
- 不存在异常 `pending` 状态但 Cash 已 approve 的记录。
- 不存在 orphan payment request。
- 不存在金额为 0 但需要支付的 payment request。
- 不存在币种为空的 payment request。
- 不存在支付账户为空的 payment request。
- 不存在 payment request 与老师工资锁定记录金额不一致的记录。

### 6.2 Cash request / attempt 检查

- 不存在残留 active attempt。
- 不存在同一 payment request 多个 active attempt。
- 不存在 orphan cash external request。
- 不存在 Cash request 已 approve 但 School 未 paid 的记录。
- 不存在 Cash request 已 rejected 但 School 被 paid 的记录。
- 不存在 rejected attempt 被覆盖或删除。
- 不存在 `attempt_no` 异常跳号导致无法追踪的问题。

### 6.3 Cash transaction 检查

- 本次试运行前，不存在真实 2026-05 `teacher_wage` 试运行产生的 JPY transaction。
- 本次试运行前，不存在真实 2026-05 `teacher_wage` 试运行产生的 CNY transaction。
- 不存在重复 `external_reference_id`。
- 不存在重复 `idempotency_key`。
- 不存在 transaction 已写入但 balance 未变化的异常。
- 不存在 balance 已变化但 transaction 不存在的异常。

## 7. 备份确认

试运行前建议至少备份或导出以下数据。

### 7.1 School 侧

- 老师工资锁定相关表。
- payment request 相关表。
- payment request attempt / cash linkage 相关表。
- 老师 master。
- 账户映射 / 支付账户配置相关表。
- 工资统计或工资汇总相关数据。

### 7.2 Cash 侧

- Cash external request 相关表。
- Cash external request attempt 相关表。
- `home_jpy_transactions`
- `home_cny_transactions`
- Cash 账户 master。
- Cash 账户余额相关表。
- School 可用账户白名单字段相关数据。

### 7.3 备份记录

- 备份时间已记录。
- 备份文件名已记录。
- 备份范围已记录。
- 备份保存位置已记录。
- 备份后未立即执行不可逆操作。

## 8. 小批量试运行计划

### 8.1 小批量原则

首次真实试运行不直接全量执行。

建议先选择：

- 1 条 JPY 老师工资 payment request。
- 如 2026-05 存在 CNY 工资，再选择 1 条 CNY 老师工资 payment request。
- 优先选择金额较小、数据结构简单、归属清晰的记录。
- 不优先选择混合归属记录。
- 不优先选择金额复杂或存在历史修正的记录。

### 8.2 提交 Cash 前确认

每条试运行记录提交前确认：

- payment request ID 已记录。
- 老师姓名已记录。
- 月份为 2026-05。
- 金额已记录。
- 币种已记录。
- 支付账户已记录。
- 当前 School 状态为 `pending`。
- 当前不存在 active attempt。
- 当前 Cash 侧不存在对应 external request。
- 当前 Cash 侧不存在对应 transaction。

## 9. 小批量 approve 检查

Cash approve 后逐项确认：

### 9.1 Cash 侧

- Cash external request 状态变为 `approved`。
- Cash transaction 已生成。
- JPY request 写入 `home_jpy_transactions`。
- CNY request 写入 `home_cny_transactions`。
- transaction 金额正确。
- transaction 币种正确。
- transaction 账户正确。
- transaction 日期正确。
- transaction 备注 / external reference 可追踪。
- Cash 账户余额变化正确。
- 未生成重复 transaction。

### 9.2 School 侧

- School payment request 状态变为 `paid`。
- `paid_at` 已写入。
- `paid_currency` 正确。
- `paid_amount` 正确。
- `paid_account` 正确。
- Cash request ID / external reference 已回写。
- 老师工资支付状态正确。
- 工资统计画面显示正确。
- 利润统计没有因内部平账产生误计入。
- 无异常 pending 残留。

## 10. Reject / Retry 检查原则

真实 2026-05 工资试运行中，不主动做 reject 测试。

仅在实际误操作或 Cash 用户确实 reject 时检查以下内容。

### 10.1 Reject 后

- Cash external request 状态变为 `rejected`。
- rejected reason 已记录。
- `rejected_at` 已记录。
- 不生成 Cash transaction。
- 不改变 Cash 账户余额。
- School payment request 保持 `pending`。
- rejected attempt 保留为历史。
- 前端可看到 rejected 结果或可追踪记录。

### 10.2 Retry 后

- 重新提交会生成新的 attempt。
- 新 `attempt_no` 正确。
- 旧 rejected attempt 未被覆盖。
- 同一时间只有一个 active attempt。
- retry 后 Cash 可正常 approve。
- retry approve 后 Cash transaction 只生成一次。
- retry approve 后 School payment request 变为 `paid`。
- retry approve 后不存在重复支付。

## 11. Rollback 检查原则

真实数据 rollback 只在必要时执行，不作为常规试运行步骤。

执行 rollback 前必须确认：

- rollback 对象 payment request ID 已记录。
- rollback 对象 Cash request ID 已记录。
- rollback 对象 transaction ID 已记录。
- rollback 原因已记录。
- rollback 前 Cash 当前余额已记录。
- rollback 前 School 当前状态已记录。
- rollback 不会影响其他老师工资记录。
- rollback 不会删除历史审计记录。

Rollback 后必须确认：

- Cash transaction 已按设计撤销或冲正。
- Cash 账户余额已恢复或生成正确冲正结果。
- School payment request 状态已恢复为预期状态。
- attempt / request 历史仍可追踪。
- 不存在 orphan rollback record。
- 不存在重复 rollback。
- JPY rollback 正常。
- CNY rollback 正常。

## 12. 全量执行前最终确认

小批量试运行通过后，进入全量前必须确认：

- 小批量 JPY approve 正常。
- 如有 CNY，小批量 CNY approve 正常。
- School payment request 状态回写正常。
- Cash transaction 写入正常。
- Cash 余额变化正常。
- 没有重复 transaction。
- 没有 orphan request。
- 没有 active attempt 残留。
- 没有 pending 状态异常。
- 没有 paid 状态异常。
- 没有金额不一致。
- 没有币种不一致。
- 没有账户不一致。
- 操作记录已保存。
- 问题记录已保存。
- 可以进入全量 2026-05 `teacher_wage` Cash 确认。

## 13. 全量执行后确认

全量执行完成后确认：

### 13.1 School 侧

- 所有目标 2026-05 `teacher_wage` payment request 均为预期状态。
- 已 approve 的记录均为 `paid`。
- 未 approve 的记录仍保持 `pending`。
- rejected 的记录可 retry。
- 工资支付状态正确。
- 工资结算画面正确。
- 工资统计画面正确。
- 没有重复 payment request。
- 没有异常 attempt。

### 13.2 Cash 侧

- 所有 approved request 均生成 transaction。
- 所有 rejected request 均未生成 transaction。
- JPY transaction 全部写入 `home_jpy_transactions`。
- CNY transaction 全部写入 `home_cny_transactions`。
- Cash 账户余额正确。
- transaction 金额合计与 School paid 金额合计一致。
- transaction 币种合计与 School paid 币种合计一致。
- 没有重复 transaction。
- 没有孤立 transaction。
- 没有孤立 external request。

## 14. 试运行结果记录

### 14.1 基本信息

- 执行日期：
- 执行人：
- School commit：
- Cash commit：
- 对象月份：2026-05
- 对象类型：`teacher_wage`
- 是否连接 DB：
- 是否执行 SQL：
- 是否调用 RPC：
- 是否写入测试数据：
- 是否使用真实工资数据：

### 14.2 小批量记录

| No | payment_request_id | teacher | currency | amount | cash_account | action | result | memo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | approve / reject / rollback |  |  |
| 2 |  |  |  |  |  | approve / reject / rollback |  |  |

### 14.3 全量记录

| currency | request_count | total_amount | approved_count | rejected_count | pending_count | transaction_count | memo |
| --- | --- | --- | --- | --- | --- | --- | --- |
| JPY |  |  |  |  |  |  |  |
| CNY |  |  |  |  |  |  |  |

### 14.4 问题记录

| No | problem | impact | action | resolved | memo |
| --- | --- | --- | --- | --- | --- |
| 1 |  |  |  | yes / no |  |
| 2 |  |  |  | yes / no |  |

## 15. 本 checklist 完成条件

以下条件全部满足时，本 checklist 视为完成：

- 文档已提交到 School repo。
- 文档已 push。
- School repo `git status --short` 无输出。
- Cash repo 如无变更，保持 clean。
- 本 checklist 中未完成项已明确记录原因。
- 是否进入真实 2026-05 `teacher_wage` 小批量试运行已明确决定。
- 下一步执行内容已明确。
