# Canonical Flow Checklist

Status date: 2026-06-16

每次新增收入、支出或 Cash 联动模块前，先按本清单检查。默认原则见 `docs/business-flow-canonical.md`。

## 1. Cash 入口

- 新模块是否直接调用 Cash？
- 如果是，停止设计。业务模块不得直接向 Cash 发请求。
- 收入必须先进入 `school_income_records`。
- 支出必须先进入 `school_expense_records`。

## 2. 收入 / 支出分类

- 这笔数据本质是收入还是支出？
- 收入进入 `school_income_records`，再由收入记录发 Cash 收款确认。
- 支出进入 `school_expense_records`，再由支出记录发 Cash 支付确认。
- Cash 不区分学费、外部塾打工、老师工资、报销等业务来源。

## 3. 月份口径

- 是否同时记录业务归属月和现金发生日期？
- `business_month` / `year_month` 用于利润、课时、工资、收入归属。
- `income_date` / `received_date` / `expense_date` / `paid_date` 用于 Cash 流水日期和现金发生月。
- 不得用实际收付款月覆盖业务归属月。
- 不得用业务归属月伪造 Cash transaction 日期。

## 4. 原始金额与实际 Cash 金额

- 原始业务金额和实际 Cash 金额是否可能不同？
- 如果可能，必须在收入/支出记录发 Cash 请求时填写实际金额和实际币种。
- 汇率、凑整、手续费、扣税、公司侧实际支付差异只能作为单次请求记录或备注。
- Cash 入账/出账以实际 Cash 金额为准。

## 5. Cash payload

- Cash 是否需要理解业务类型才能处理？
- 如果需要，设计错误。
- Cash 只看：
  - 收入或支出
  - 金额
  - 币种
  - 账户
  - 说明
  - `school_income_records` / `school_expense_records` 外部引用
  - payload 摘要

## 6. 锁定与快照

- 来源模块是否有 locked snapshot？
- 锁定后的金额必须以 snapshot 为准。
- Cash approve/reject 不得重算来源明细、课时、工资或结算总额。
- 后续明细编辑不得影响已锁定并已发起收入/支出记录的金额。

## 7. Legacy 数据

- 是否已有旧链路或历史数据？
- 先只读审计，再 dry-run。
- 迁移、作废、保留、删除必须单独列清单。
- 不直接删除历史 request / transaction。
- `school_payment_requests` / `teacher_wage_payment_confirm` 与 `school_part_time_work_income_requests` / `part_time_work_income_received` 均为 legacy 历史，不得新建。

## 8. Smoke 要求

- 是否需要 rollback smoke？
- 最低验证：
  - income approve sync
  - income reject sync
  - expense approve sync
  - expense reject sync
  - legacy direct request create rejection
  - residue = 0
- smoke 不使用真实业务数据；如需持久测试，必须使用明确 whitelist 测试标识并清理。
