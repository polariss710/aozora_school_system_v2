# School / Cash 统一业务链路原则

Status date: 2026-06-16

本文档定义 School 与 Cash 的唯一正确业务链路。后续新增模块、修复旧链路、设计 RPC / Edge Function / UI 时，必须优先遵守本文档，避免业务模块绕过 School 收入记录 / 支出记录直接向 Cash 发请求。

## 1. Cash 不承担业务判断

Cash 只处理账户收支确认，不判断收入或支出的业务来源。

Cash 只关心：

- 收入还是支出
- 金额
- 币种
- 账户
- 说明
- 外部引用 `income_record_id` / `expense_record_id`
- 确认后生成 Cash transaction
- 驳回后回写 School 状态

Cash 不区分学费、外部塾打工、老师工资、交通费、教室费、报销等业务类型。这些业务分类只保留在 School 的收入记录或支出记录中。

## 2. 业务归属月与现金发生月必须分离

收入记录和支出记录必须同时区分：

- 业务归属月
- 现金发生日期 / 现金发生月

老师工资支付和外部塾打工收入通常会延后一个月发生。例如 5 月外部塾打工工资可能在 6 月收到款，5 月老师工资也可能在 6 月实际支付。不能用一个“月份”字段同时表达业务归属和现金流发生。

### 2.1 业务归属月

`business_month` / `year_month` 表示这笔收入或支出属于哪个业务月份。

用于：

- 月度利润
- 业务统计
- 课时 / 工资 / 收入归属
- 老师工资成本归属
- 外部塾打工收入归属

示例：`2026-05` 诺应教育打工收入，业务归属月是 `2026-05`。

### 2.2 现金发生日期 / 现金发生月

`cash_date` / `received_date` / `paid_date` 表示实际收到钱或实际支付钱的日期。`received_month` / `paid_month` / `cash_month` 可以由该日期计算。

用于：

- Cash 账户流水
- Cash 余额
- 实际收款 / 付款月
- 现金流统计

示例：`2026-05` 诺应教育工资在 `2026-06` 收到，则 Cash 入账日期和现金发生月属于 `2026-06`。

### 2.3 收入记录规则

收入记录应能同时表达：

- `business_month`：业务归属月
- `income_date` / `received_date`：实际收款日期
- `income_month` / `received_month`：实际收款月，可由日期计算
- `original_amount` / `original_currency`：School 侧原始业务金额
- `payment_amount` / `payment_currency`：Cash 实际到账金额

外部塾打工收入示例：

- `business_month = 2026-05`
- 原始业务金额：`86,760 JPY`
- 实际收款日期 / 月：`2026-06`
- Cash 实际到账：`3,670 CNY`

### 2.4 支出记录规则

支出记录应能同时表达：

- `business_month`：业务归属月
- `expense_date` / `paid_date`：实际支付日期
- `expense_month` / `paid_month`：实际支付月，可由日期计算
- `original_amount` / `original_currency`：School 侧原始应付金额
- `payment_amount` / `payment_currency`：Cash 实际支付金额

老师工资示例：

- 5 月老师工资：`business_month = 2026-05`
- 6 月实际支付：`paid_month = 2026-06`

### 2.5 统计规则

- 业务利润统计按 `business_month` 归属。
- Cash 流水、账户余额、现金流统计按实际 Cash transaction 日期归属。
- 收入 / 支出记录列表默认可按 `business_month` 查看经营归属，同时显示实际收款月 / 支付月。
- 后续可以增加按现金发生月筛选。

### 2.6 禁止规则

禁止：

- 用实际收款月覆盖业务归属月。
- 用实际付款月覆盖业务归属月。
- 用业务归属月伪造 Cash 入账 / 出账日期。
- 用一个 `month` 字段同时承担业务归属和现金发生。
- 让 Cash 判断业务归属月。

Cash 只记录实际收支日期和账户变动。业务归属由 School 收入 / 支出记录负责。

## 3. 所有收入必须先进入 School 收入记录

正确链路：

```text
业务来源模块 -> School 收入记录 -> 从收入记录向 Cash 发请求 -> Cash 确认 -> 回写收入记录
```

禁止链路：

```text
业务来源模块 -> 直接 Cash 请求
```

收入来源可以包括：

- 学费收入
- 外部塾打工收入
- 其他收入
- 法人账户通常收入
- 法人账户调拨

Cash 侧不区分这些业务来源。业务分类、业务归属月、学生/付款方、外部机构、结算依据、利润口径等信息属于 School 收入记录。

## 4. 所有支出必须先进入 School 支出记录

正确链路：

```text
业务来源模块 -> School 支出记录 -> 从支出记录向 Cash 发请求 -> Cash 确认 -> 回写支出记录
```

禁止链路：

```text
业务来源模块 -> 直接 Cash 请求
```

支出来源可以包括：

- 老师工资
- 交通费
- 教室费
- 报销
- 其他支出

Cash 侧不区分这些业务来源。业务分类、业务归属月、老师/学生、工资明细、报销明细、成本归属、利润口径等信息属于 School 支出记录。

## 5. 收入记录的三种固定创建方式

### A. Cash 收入

流程：

```text
收入记录新增或由业务模块生成 -> 从收入记录向 Cash 发收款请求 -> Cash 确认 -> Cash 账户余额增加 -> 收入记录状态完成
```

适用：

- 人民币收入到余额宝
- 日元收入到日元现金 / 日元银行卡
- 学费收入
- 外部塾打工收入

### B. 法人账户调拨

流程：

```text
Cash 侧手动支出 -> School 侧新增“法人账户调拨”收入记录 -> 法人账户余额增加
```

规则：

- 不计入营业收入 / 利润
- 用于资金归集、内部调拨、代收款清算等非经营收入场景

### C. 法人账户通常收入

流程：

```text
收入直接进入法人账户 -> School 收入记录新增 -> 法人账户余额增加
```

规则：

- 计入 School income
- 低频保留
- 不需要 Cash 账户确认，除非实际资金经过用户控制的 Cash 账户

## 6. 外部塾打工收入正确链路

正确链路：

```text
打工模块课时 -> 月度工资结算 -> 锁定 -> 生成 School 收入记录 -> 收入记录页面发 Cash 请求 -> Cash 确认 -> 回写收入记录
```

规则：

- 打工模块不得直接向 Cash 发请求。
- 打工模块只负责生成收入记录。
- School 侧可以记录 JPY 锁定工资。
- 向 Cash 发请求时，可以填写实际到账金额和币种。
- Cash 入账以实际到账金额为准。
- 汇率、凑整、扣税、手续费、公司侧实际支付差异等，只在收入记录发 Cash 请求时处理。
- 打工收入的业务归属月来自打工结算月份；Cash 入账日期来自实际收款日期，不得互相覆盖。

示例：2026-05 诺应教育

- School 锁定工资：`86,760 JPY`
- 业务归属月：`2026-05`
- 实际收款月：`2026-06`
- 实际到账：`3,670 CNY`
- Cash 请求金额：`3,670 CNY`
- 反推汇率仅作为备注，不作为固定汇率

## 7. 老师工资正确链路

正确链路：

```text
老师工资结算 -> 生成 School 支出记录 -> 支出记录页面发 Cash 支付请求 -> Cash 确认 -> 回写支出记录
```

规则：

- 老师工资模块不得直接向 Cash 发请求。
- 老师工资模块只负责生成支出记录。
- Cash 只确认支出记录，不理解 `teacher_wage` 业务。
- 老师工资明细、学生归属、工资快照、交通费/教室费/调整项等业务信息属于 School。
- 老师工资的业务归属月来自工资结算月份；Cash 出账日期来自实际支付日期，不得互相覆盖。

2026-06-16 第四阶段状态：

- `school_expense_records` 是老师工资新链路的承接表。
- `school_expense_records.source_type = teacher_wage`，`source_id` 指向老师工资快照来源。
- 老师工资支出记录通过专用 RPC 从 locked wage snapshot 生成；普通支出新增仍不得手动创建 `teacher_wage`。
- 新老师工资支付入口已改为生成 `school_expense_records`，再由支出记录详情页提交 Cash 支付确认。
- 7 条旧 pending `teacher_wage` payment request 已迁移为 7 条 pending `school_expense_records`，旧请求保留为 `cancelled` legacy audit。
- `school_payment_requests` 中的 `teacher_wage` 请求只保留历史只读，不再作为新 Cash 请求入口。
- Legacy RPC `school_request_cash_payment_confirmation(...)` 和 Edge Function `request-cash-confirmation` 对 `teacher_wage` 旧 payment request 提交返回拒绝：`teacher_wage payments must be handled through school_expense_records`。

## 8. 当前已知违规链路

以下内容仅记录为待修复项，本轮不修复、不清理、不确认、不驳回。

### A. 老师工资（已收敛为 legacy 只读）

当前可能存在：

```text
teacher_wage -> 直接 Cash request
```

应改为：

```text
teacher_wage -> School 支出记录 -> Cash request
```

2026-06-16 状态：

- 新老师工资支付入口已改为 `teacher_wage -> school_expense_records`。
- 旧 `school_payment_requests` 老师工资页面只作为 legacy / historical view。
- 旧 pending 老师工资 payment request 已迁移为支出记录，旧请求不再保留 active pending。
- 旧 direct Cash request 入口已禁用，不得再产生 `teacher_wage_payment_confirm` 新请求。

### B. 外部塾打工收入

当前已生成过：

```text
part_time_work_income_request -> 直接 Cash request
```

应改为：

```text
part_time_work -> School 收入记录 -> Cash request
```

现有旁路 request：

- Cash request: `19ba6cbd-9588-486b-8b2a-b4b7c573f252`（已在 Cash UI 拒绝）
- School income request: `123180f8-012a-4334-95dd-3adc3e7f5b11`
- 业务：`2026-05 诺应教育`
- 金额：`86,760 JPY / 3,670 CNY`

该请求不得确认或复用。2026-06-15 已定向回写 School 为 `cash_rejected`，并已按正确链路生成 School 收入记录 `fc676042-663b-45c2-9e1f-51e7306d9d63`。后续 Cash 请求应从该收入记录发起。

## 9. 后续修复顺序建议

第一阶段：审计 School -> Cash 入口

- 列出哪些入口由收入记录 / 支出记录发起。
- 列出哪些入口由业务模块直连 Cash。
- 标记每条入口对应的 DB 表、RPC、Edge Function、前端按钮和状态字段。

第二阶段：收入侧统一化

- 外部塾打工收入改为生成 School 收入记录。（2026-06-15 已开始实装）
- 收入记录页面统一负责向 Cash 发收款请求。（2026-06-15 已开始支持 existing income record）
- 清理或保留归档错误旁路 Cash rejected request，不再生成新的旁路 request。

第三阶段：支出侧统一化

- 老师工资改为生成 School 支出记录。（2026-06-16 已完成新入口改造）
- 支出记录页面统一负责向 Cash 发付款请求。（2026-06-15 已完成最小链路）
- 禁用 `teacher_wage` 直连 Cash。（2026-06-16 已完成）
- 旧 `school_payment_requests` pending 老师工资请求已迁移为支出记录；已 paid / reversed / void 历史记录作为 legacy 保留只读。

第四阶段：Cash 侧收敛

- Cash 只接受 `income_record` / `expense_record` 类型外部请求。
- 移除业务模块专用 `external_reference_type` 分支。
- Cash UI 保留业务摘要展示，但业务分类来自 School 收入/支出记录 payload，不作为 Cash 自身判断条件。

## 10. 实装约束

- 新业务模块不得新增直连 Cash request。
- 新 Cash request 必须以 School 收入记录或支出记录为唯一外部引用。
- Cash approve 是唯一生成 Cash transaction 并改变 Cash 余额的动作。
- Cash reject 不生成 Cash transaction，不改变 Cash 余额，只回写 School 状态。
- School locked settlement、工资快照、课时明细、利润口径不得由 Cash 回写重算。
- 汇率只作为单次实际收付款记录或备注，不得作为固定自动换算规则。
- `business_month` / `year_month` 不得被 Cash 发生日期覆盖，Cash transaction 日期也不得被业务归属月伪造。
