# School / Cash 统一业务链路原则

Status date: 2026-06-15

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

## 2. 所有收入必须先进入 School 收入记录

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

Cash 侧不区分这些业务来源。业务分类、业务归属、学生/付款方、外部机构、结算依据、利润口径等信息属于 School 收入记录。

## 3. 所有支出必须先进入 School 支出记录

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

Cash 侧不区分这些业务来源。业务分类、老师/学生、工资明细、报销明细、成本归属、利润口径等信息属于 School 支出记录。

## 4. 收入记录的三种固定创建方式

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

## 5. 外部塾打工收入正确链路

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

示例：2026-05 诺应教育

- School 锁定工资：`86,760 JPY`
- 实际到账：`3,670 CNY`
- Cash 请求金额：`3,670 CNY`
- 反推汇率仅作为备注，不作为固定汇率

## 6. 老师工资正确链路

正确链路：

```text
老师工资结算 -> 生成 School 支出记录 -> 支出记录页面发 Cash 支付请求 -> Cash 确认 -> 回写支出记录
```

规则：

- 老师工资模块不得直接向 Cash 发请求。
- 老师工资模块只负责生成支出记录。
- Cash 只确认支出记录，不理解 `teacher_wage` 业务。
- 老师工资明细、学生归属、工资快照、交通费/教室费/调整项等业务信息属于 School。

## 7. 当前已知违规链路

以下内容仅记录为待修复项，本轮不修复、不清理、不确认、不驳回。

### A. 老师工资

当前可能存在：

```text
teacher_wage -> 直接 Cash request
```

应改为：

```text
teacher_wage -> School 支出记录 -> Cash request
```

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

## 8. 后续修复顺序建议

第一阶段：审计 School -> Cash 入口

- 列出哪些入口由收入记录 / 支出记录发起。
- 列出哪些入口由业务模块直连 Cash。
- 标记每条入口对应的 DB 表、RPC、Edge Function、前端按钮和状态字段。

第二阶段：收入侧统一化

- 外部塾打工收入改为生成 School 收入记录。（2026-06-15 已开始实装）
- 收入记录页面统一负责向 Cash 发收款请求。（2026-06-15 已开始支持 existing income record）
- 清理或保留归档错误旁路 Cash rejected request，不再生成新的旁路 request。

第三阶段：支出侧统一化

- 老师工资改为生成 School 支出记录。
- 支出记录页面统一负责向 Cash 发付款请求。
- 禁用 `teacher_wage` 直连 Cash。

第四阶段：Cash 侧收敛

- Cash 只接受 `income_record` / `expense_record` 类型外部请求。
- 移除业务模块专用 `external_reference_type` 分支。
- Cash UI 保留业务摘要展示，但业务分类来自 School 收入/支出记录 payload，不作为 Cash 自身判断条件。

## 9. 实装约束

- 新业务模块不得新增直连 Cash request。
- 新 Cash request 必须以 School 收入记录或支出记录为唯一外部引用。
- Cash approve 是唯一生成 Cash transaction 并改变 Cash 余额的动作。
- Cash reject 不生成 Cash transaction，不改变 Cash 余额，只回写 School 状态。
- School locked settlement、工资快照、课时明细、利润口径不得由 Cash 回写重算。
- 汇率只作为单次实际收付款记录或备注，不得作为固定自动换算规则。
