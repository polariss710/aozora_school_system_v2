# 致远教育 2026-05 实际到账人民币修正

## 授权范围

- 用户明确确认：致远教育 2026-05 实际到账人民币应为 `7,372 CNY`，现存 `7,327 CNY` 为录入错误。
- 这是一次独立、精确 ID、精确旧值守卫的 School + Cash 历史数据修正，不开放通用历史编辑入口。
- 只修正实际到账金额数值以及同一链路说明文字中的 `7,327.00 -> 7,372.00`。

## 固定目标

- School settlement: `e4b8bbdb-3f5c-4e6f-b73c-dce0a4378941`
- School income: `7786630e-4173-4a93-8da3-023749822ea7`
- School linkage event: `c3139df9-b4af-4c78-83fd-a4034485d06f`
- Cash request: `a4d8404e-7c11-4a72-b9d6-c98274f77c48`
- Cash CNY transaction: `2c2145e1-8bf4-4295-b520-a99dfb9cf5f0`
- Cash user: `8596a708-d99f-4264-8f8c-5b89af9254b6`
- Cash account: `c61781cf-dd07-40d1-ab00-7f76eb581034`（余额宝）

## 不变事实

- School 业务月仍为 `2026-05`，日元结算及收入金额仍为 `172,860 JPY`。
- Cash 交易日期、School 收入日期、工作单位、账户、用户、币种、状态、请求和交易关联全部不变。
- `0.04189` 是原链路保存的参考汇率，不随本次实际到账数值修正而改写；说明中的理论金额也不改写。
- Cash 交易的 `external_payload_hash` 必须在请求 `payload_snapshot` 修正后按既有规则 `md5(payload_snapshot::text)` 同步刷新。
- Cash 账户没有单独保存的当前余额字段；账户余额由流水聚合，因此目标收入流水增加 `45 CNY` 后余额自然同步增加 `45 CNY`，不另写其他流水。

## 执行规则

1. 两个脚本默认 rollback；只有显式传入 `-v repair_commit=1` 才提交。
2. School 脚本必须核对结算、收入、联动事件、Cash request/transaction/user/account ID 及旧值。
3. Cash 脚本必须核对 request/transaction 全链路、旧值、参考汇率、各说明字段旧文本出现次数和修正前载荷哈希。
4. 先分别执行 rollback 测试，再执行仅使用 `pg_temp` 的白名单 commit transformation test。
5. 正式执行 Cash 后执行 School；任一步异常立即停止，不扩大写入范围。
6. 最终双库只读验收必须确认金额均为 `7,372`、旧文本全部消失、载荷哈希一致、固定关联和受保护事实未变化。

## SQL 文件

- School: `sql/current/school_repair_zhiyuan_202605_cny_amount.sql`
- Cash: `sql/current/cash_repair_zhiyuan_202605_cny_amount.sql`
