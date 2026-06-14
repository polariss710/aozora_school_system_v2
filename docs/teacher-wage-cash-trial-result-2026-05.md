# 2026-05 Teacher Wage Cash 小批量真实试运行结果

## 1. 文档目的

本文档记录 2026-05 teacher_wage Cash 化后的第一条真实小批量试运行结果。

本次试运行用于确认：

- School teacher_wage payment request 可以提交 Cash confirmation。
- Cash approve 后可以生成真实 Cash transaction。
- Cash 账户余额正确变化。
- School payment request 可以正确回写为 paid。
- attempt / linkage / transaction 对账一致。
- 不生成 School 侧账户流水或重复支出记录。

## 2. 执行范围

本次只处理 1 条真实 payment request。

| 项目 | 内容 |
| --- | --- |
| 对象月份 | 2026-05 |
| request type | teacher_wage |
| 老师 | 吴峰 |
| 金额 | 36,000 |
| 币种 | JPY |
| 归属 | 青空进学塾 |
| Cash 账户 | 日元乐天卡 |
| Cash transaction 表 | home_jpy_transactions |

本次未处理其他老师工资，未执行全量处理。

## 3. 执行前状态

### 3.1 School 侧

| 项目 | 状态 |
| --- | --- |
| Payment request ID | 3ef23a8a-417c-4bf8-938f-55975e03fa86 |
| payment request status | pending |
| paid_at | null |
| paid | false |
| active attempt | 0 |
| Cash linkage | 不存在 |
| Cash transaction | 不存在 |

### 3.2 Cash 侧

| 项目 | 状态 |
| --- | --- |
| Cash account | 日元乐天卡 |
| currency | JPY |
| allow_school_requests | true |
| Cash balance before Step 1 | 539,084.00 |
| related transaction | 不存在 |

## 4. Step 1：提交 Cash confirmation request

### 4.1 执行内容

从 School 侧提交 1 条 teacher_wage Cash confirmation request。

调用 RPC：

- School：school_request_cash_payment_confirmation
- Cash：home_create_external_transaction_request
- School：school_mark_personal_cash_payment_request_submitted

### 4.2 生成结果

| 项目 | 内容 |
| --- | --- |
| Cash external request ID | d7fa880c-ce9c-4c2c-94fd-b99099a12f9c |
| linkage event ID | 15180c80-0c71-4fa0-9bc4-805f9e6f92ad |
| attempt_no | 1 |
| attempt status | awaiting_cash_confirmation |
| Cash external request status | pending |

### 4.3 Step 1 后确认

| 检查项 | 结果 |
| --- | --- |
| School payment request status | pending |
| paid_at | null |
| active attempt | 1 |
| duplicate active attempt | false |
| old rejected attempt | 0 |
| Cash external request | pending |
| Cash request amount | 36,000 |
| Cash request currency | JPY |
| Cash request account | 日元乐天卡 |
| home_jpy_transactions | 未生成 |
| Cash 余额 | 未变化 |
| Cash balance before / after | 539,084.00 / 539,084.00 |

Step 1 按预期停在 Cash pending confirmation 状态，未 approve / reject / rollback。

## 5. Step 2：Cash approve

### 5.1 执行内容

Cash 侧 approve 指定 external request：

| 项目 | 内容 |
| --- | --- |
| Cash external request ID | d7fa880c-ce9c-4c2c-94fd-b99099a12f9c |
| School payment request ID | 3ef23a8a-417c-4bf8-938f-55975e03fa86 |

调用 RPC：

- Cash：home_approve_external_transaction_request
- School：school_mark_personal_cash_payment_request_confirmed

### 5.2 approve 后 Cash 侧结果

| 项目 | 内容 |
| --- | --- |
| Cash external request status | approved |
| transaction table | home_jpy_transactions |
| transaction ID | bf60dc09-37ee-4157-972f-d2e89f9b828a |
| transaction amount | 36,000 |
| transaction currency | JPY |
| transaction account | 日元乐天卡 |
| CNY transaction | 0 |

### 5.3 Cash 余额变化

| 项目 | 金额 |
| --- | --- |
| approve 前余额 | 539,084.00 |
| approve 后余额 | 503,084.00 |
| 变化额 | -36,000.00 |

## 6. approve 后 School 侧结果

| 项目 | 内容 |
| --- | --- |
| payment request status | paid |
| paid_at | 2026-06-14T08:52:55.994081+00:00 |
| paid amount | 36,000 |
| paid currency | JPY |
| attempt status | synced |
| Cash request status in linkage | approved |
| active attempt | 0 |
| duplicate active attempt | false |
| paid / approved / transaction 对账 | 一致 |

School 侧没有写入 School expense / account transaction。
School 侧 linkage 指向 Cash account 日元乐天卡 与 Cash transaction bf60dc09-37ee-4157-972f-d2e89f9b828a。

## 7. 对账结果

| 检查项 | 结果 |
| --- | --- |
| Cash request approved | OK |
| School payment request paid | OK |
| JPY transaction generated | OK |
| CNY transaction not generated | OK |
| Cash balance changed by -36,000 | OK |
| active attempt cleared | OK |
| attempt synced | OK |
| duplicate transaction | none |
| duplicate active attempt | none |
| paid / approved / transaction mismatch | none |

## 8. 本次未执行事项

本次未执行：

- reject
- rollback
- 其他老师工资处理
- 2026-05 全量工资处理
- 测试数据写入
- 代码修改
- SQL 修改
- SQL 文件执行
- commit / push 以外的 DB 结构变更

## 9. Git / 环境状态

| 项目 | 状态 |
| --- | --- |
| SUPABASE_DB_URL | 未使用 |
| School DB | 使用 SCHOOL_SUPABASE_DB_URL |
| Cash DB | 使用 CASH_SUPABASE_DB_URL |
| School repo 执行前 | clean |
| Cash repo 执行前 | clean |
| School repo 执行后 | clean |
| Cash repo 执行后 | clean |

## 10. 结论

2026-05 teacher_wage Cash 化第一条真实小批量试运行通过。

确认链路如下：

```text
School pending payment request
↓
School 提交 Cash confirmation
↓
Cash pending external request
↓
Cash approve
↓
home_jpy_transactions 生成
↓
Cash 余额减少 36,000
↓
School payment request 回写 paid
↓
attempt synced
↓
对账一致
```

本结果可作为后续处理剩余 2026-05 teacher_wage pending payment request 的基准案例。

后续建议：

1. 修正只读检查 SQL 中 historical void request 的 anomaly 分类。
2. 再处理剩余 7 条 2026-05 teacher_wage pending payment request。
3. 全量处理前继续保持小批量 / 分批执行策略。
