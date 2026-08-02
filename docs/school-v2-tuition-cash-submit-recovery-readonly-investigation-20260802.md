# School V2 学费 Cash 提交恢复前只读调查报告

日期：2026-08-02（JST）
阶段：只读调查审查点；HARD STOP，未开放 Cash Gate

> 2026-08-02实施阶段补充：原16条调查基线仍原字节保留；之后权威Atomic
> Generate新增孙陈锋2026-09 canonical bill/income，因此实施基线为17条、eligible为8条。
> 17条TSV为`docs/school-v2-tuition-cash-submit-hardening-baseline-17rows-20260802.tsv`，
> SHA-256为`b91cb9dacef0c0c68013c5a2435a32a27cbef5089a159f30c49247a1145ccf46`；
> 8条eligible TSV字段集合SHA-256为
> `e1ad372ffea00b113088d7a39d7ab3ee2841f9b18ae3e18fd22952711b3cfd09`。

## 1. 结论

### 1.1 历史补充是否是前置条件

**2026年2月至7月历史数据补充不是学费 Cash 提交恢复的前置条件。**

现有提交链只需读取已经冻结的 canonical `school_income_records`、对应
`school_student_tuition_bills`、billing identity、Cash linkage 和目标 Cash
账户；不读取 historical actual、动态 student settlement、unlocked preview、
candidate reader、当前 lesson、历史排除表或历史收费重建结果。

这个结论有一个强制保护条件：后续历史补充只能为缺失月份创建独立的
canonical 对象，不得修改已生成的 billing identity、bill、income、bill-income
relation、normalized lesson relation、source snapshot、billing amount 或 Cash
linkage。若历史补充方案需要修改这些对象，应立即 HARD STOP；这不反过来构成
当前 Cash 恢复的依赖。

### 1.2 当前能否直接恢复

**不能。当前必须继续 HARD STOP，不能只把 Gate 改成 enabled。**

恢复前至少要关闭以下四类缺口：

1. 列表和详情 UI 都永久隐藏 `student_tuition_bill` 的 Cash 提交入口；
   Edge Function 在 Gate 为 enabled 时仍明确返回 `R0 不提供学费 Cash enabled 路径`。
2. 学费金额权威尚未收敛。页面仍可把 source snapshot 金额作为普通客户端参数
   提交，或提交汇率/取整意图；School RPC 仍可用 `income.amount × 请求汇率 +
   bill.previous_carryover_cny` 重算，而不是无条件读取冻结
   `bill.billing_amount_cny`。
3. 权限边界过宽。School 的三个 Cash 回写 `SECURITY DEFINER` RPC 对 PUBLIC/anon
   可执行；School linkage 表无 RLS 且 anon/authenticated 有表 DML 权限；Cash 的
   create/approve/reject `SECURITY DEFINER` RPC 也对 anon 可执行。当前 Gate 和触发器
   暂时保护了学费首次 linkage insert，但 Gate 开放后不能依赖这个偶然边界。
4. Cash `home_approve_external_transaction_request` 对重复 approve 返回“仅 pending
   可批准”，不会幂等返回既有 transaction；虽然唯一约束可防止第二条 transaction，
   但不满足下一阶段要求的重复 approve 幂等合同。

本轮没有改变上述任何实现。

## 2. 完整调用链与 Gate 阻断层

```text
income.html / income-detail.html
  -> js/pages/income-page.js / income-detail-page.js
  -> js/api/income-api.js / income-detail-api.js
  -> Edge: request-cash-income-confirmation
  -> School RPC: school_request_cash_income_confirmation_for_record
  -> School: school_personal_cash_income_linkage_events
  -> Cash RPC: home_create_external_transaction_request
  -> Cash: home_external_transaction_requests (pending)
  -> Cash UI approve/reject
       approve -> home_approve_external_transaction_request
               -> home_create_external_cny_transaction / jpy
               -> home_*_transactions
       reject  -> home_reject_external_transaction_request
               -> no transaction / no balance change
  -> Edge: sync-cash-request-result
  -> School RPC: school_mark_cash_income_confirmed / rejected
  -> School income + linkage terminal state
```

当前 `student_tuition_cash_submit = blocked` 在三层生效：

| 层 | 当前行为 |
|---|---|
| 列表/详情页面 | `source_type = student_tuition_bill` 时 `canRequestCashIncome` 直接返回 false，按钮不显示 |
| Edge Function | 读取 Gate；blocked 返回 423；即使 enabled 仍返回 R0 423，无 enabled 路径 |
| School DB | `school_r0_tuition_cash_linkage_mutation_guard` 在 tuition linkage INSERT/UPDATE/DELETE 前要求 Gate enabled，读取失败也 fail-closed |

页面模块没有直接 `.rpc()`，没有直接 insert/update/delete/upsert。所有页面写调用都先进入
`js/api/*-api.js`；学费 Cash 提交当前实际上在页面层已不可达。

## 3. 旧入口与旁路

| 旧入口 | 当前状态 |
|---|---|
| `school_create_personal_cash_tuition_income_record(...)` | 函数签名保留，但函数体固定抛出 R0 legacy blocked；不创建 income/outbox |
| `school_create_student_tuition_bill_income_record(...)` | 旧 bill→income 两步路径固定抛出 R0 blocked |
| 两个旧 `school_generate_student_tuition_bill(...)` overload | 固定抛出 R0 blocked；唯一正式 writer 是 atomic generate |
| `request-cash-part-time-income-confirmation` | 无条件 HTTP 410 |
| `request-cash-confirmation` teacher-wage direct path | teacher wage 返回 HTTP 410；Cash canonical create RPC也拒绝 legacy reference/request type |
| Cash `school_payment_requests` / `school_part_time_work_income_requests` | `home_create_external_transaction_request` 拒绝创建；`sync-cash-request-result` 对 legacy 返回 410 |
| 旧 manual sync retry | 页面仍保留 failed 事件“重新同步”旧按钮，但线上 `school_retry_personal_cash_income_linkage_event(uuid)` 已不存在，调用 fail-closed；它不能创建 Cash request |

旧入口目前不会绕过 canonical `school_income_records` 创建新 Cash request。下一阶段不得
恢复这些入口；旧 retry UI 应移除或明确标记历史不可用。

## 4. 当前 canonical 学费 income 只读基线

全量 TSV：`docs/school-v2-tuition-cash-submit-recovery-baseline-20260802.tsv`
TSV SHA-256：`33d0cb9a8d0cb62c4de5f6ea26ed658b6898293def3cc2ee205d58721295ec35`
范围：当前全部 16 条 `school_student_tuition_bills` 及其 income，不只检查单个学生。

| 学生 | 月份 | bill | income | JPY | 冻结通知 CNY | 状态分类 |
|---|---|---|---|---:|---:|---|
| 孙陈锋 | 2026-07 | `2a9f1c25…` | `468ab75b…` | 306,000 | 12,852.00 | ALREADY_SYNCED |
| 张倬闻 | 2026-07 | `047dac2b…` | `bbd7e7fd…` | 520,000 | 21,840.00 | BLOCKED_CONFLICT（incident duplicate） |
| 张倬闻 | 2026-07 | `fdf3cdfe…` | `f86ac9db…` | 520,000 | 22,360.00 | ALREADY_SYNCED |
| 彭宇晗 | 2026-07 | `2a0948e0…` | `09fa4398…` | 102,000 | 4,263.60 | ALREADY_SYNCED |
| 李天伦 | 2026-07 | `07a02092…` | `91756564…` | 260,000 | 11,700.00 | ALREADY_SYNCED |
| 袁振轩 | 2026-07 | `00c956f1…` | `4a6efa01…` | 27,000 | 1,120.50 | ELIGIBLE_FOR_CASH_SUBMIT（Gate后） |
| 陈加恩 | 2026-07 | `2608806a…` | `4a63f0ca…` | 216,000 | 9,288.00 | ALREADY_SYNCED |
| 陈加恩 | 2026-07 | `4109a4ec…` | `474f0fd2…` | 216,000 | - | BLOCKED_CONFLICT（cancelled） |
| 陈红卓 | 2026-07 | `7472f73f…` | `3a5542c5…` | 204,000 | 9,180.00 | ALREADY_SYNCED |
| 孙陈锋 | 2026-08 | `7d764343…` | `ae9e2400…` | 434,240 | 18,238.08 | ELIGIBLE_FOR_CASH_SUBMIT（Gate后） |
| 张倬闻 | 2026-08 | `553a24ba…` | `be64a9e2…` | 650,000 | 27,407.50 | ELIGIBLE_FOR_CASH_SUBMIT（Gate后） |
| 彭宇晗 | 2026-08 | `1e02dc09…` | `ae4d8b66…` | 255,000 | 10,582.50 | ELIGIBLE_FOR_CASH_SUBMIT（Gate后） |
| 李天伦 | 2026-08 | `5e032651…` | `1de45ea6…` | 352,000 | 15,030.40 | ELIGIBLE_FOR_CASH_SUBMIT（Gate后） |
| 袁振轩 | 2026-08 | `13bc7bc1…` | `54b281ee…` | 333,000 | 13,819.50 | ELIGIBLE_FOR_CASH_SUBMIT（Gate后） |
| 陈加恩 | 2026-08 | `1b546782…` | `cdf3da68…` | 216,000 | 9,288.00 | ALREADY_SYNCED；不得重新提交 |
| 陈红卓 | 2026-08 | `51f746c5…` | `895a7be3…` | 204,000 | 9,180.00 | ELIGIBLE_FOR_CASH_SUBMIT（Gate后） |

分类合计：

- `ELIGIBLE_FOR_CASH_SUBMIT`：7条，JPY 2,255,240，冻结通知 CNY 95,378.48；当前
  effective eligibility 全为 false，因为 Gate/页面/Edge 仍 blocked。
- `ALREADY_SYNCED`：7条。
- `BLOCKED_CONFLICT`：2条。
- `ALREADY_SUBMITTED`、`REJECTED_RETRYABLE`、`NOT_TUITION_INCOME`：均0条。

7条 pending 技术候选均满足：唯一 identity、bill-income 双向关系、canonical source、
student/month/business entity、JPY、冻结汇率/通知金额/carryover、relation count 和
source snapshot 一致；没有 School linkage、Cash request 或 Cash transaction。

历史行有两个只读差异，不影响 pending 7条，但不得在本轮修复：

- 孙陈锋、张倬闻 2026-07 historical bill 的 business entity snapshot 为“个人名义”，
  已 received income 当前 business entity 为“青空进学塾”。
- 7条 historical-backfill income snapshot 没有后续补建的 billing identity id；当前
  identity 表仍对 active bill 保持唯一。

它们均已 received/synced，必须永久排除重新提交。陈加恩 2026-07 与 2026-08 两条
received income 都已有 approved Cash request 和唯一 transaction；另有一条 cancelled
旧 bill/income，不可提交。

## 5. 金额权威与数据流

### 5.1 当前实现

| 阶段 | 当前金额来源 |
|---|---|
| 列表页默认显示 | `income.source_snapshot.billing_amount_cny` |
| 列表页提交 | 默认值仍放入可编辑 input；跨币种时会作为 `actual_received_amount` 提交，或提交客户端汇率+rounding intent |
| 详情页默认/提交 | 从同一 source snapshot 填入可编辑 input，并始终作为客户端 `actual_received_amount` 提交 |
| API wrapper | 透传 amount/currency/date/exchange_rate/rounding_mode 到 Edge |
| Edge | 先阻断 tuition；普通路径把客户端参数传给 School RPC；Cash payload 使用 RPC 返回的 `payment_amount` |
| School RPC | 可接受显式客户端金额；也可按 `income.amount × p_exchange_rate + bill.previous_carryover_cny` 后 round/ceil/floor |
| Cash pending request | `amount = School RPC.payment_amount` |
| Cash approve transaction | transaction 金额直接取 immutable pending request 的 `amount` |
| School approve回写 | linkage 既有 `payment_amount` 作为实际到账展示；callback只写 request/transaction id和状态，不重算业务金额 |

页面里的理论换算和 `Math.round/ceil/floor` 目前因 tuition 按钮被隐藏而不可达；但若只删除
页面阻断并开放 Gate，它们会重新进入写链，因此仍是 P0 缺口。

### 5.2 正确恢复合同

学费提交必须固定为：

```text
payment_currency = CNY
payment_exchange_rate = frozen bill.billing_exchange_rate
payment_amount = frozen bill.billing_amount_cny
```

School RPC 应在锁定 income/bill/identity 后直接读取并交叉验证冻结字段；对 tuition
请求应拒绝或忽略客户端 amount、currency、exchange_rate、rounding_mode。页面只展示
服务端 preflight 返回的只读金额，不计算、不允许覆盖。普通非 tuition income 的显式用户
到账金额合同保持不变。

## 6. 状态、retry、幂等与并发

### 首次提交

当前 DB/RPC 已检查 pending income、无 School account、JPY/CNY、bill-income link、
bill `income_created`。恢复时还必须新增/前置验证：canonical tuition source、identity、
row-level block/exclusion、Gate、固定 CNY、冻结 amount/rate/snapshot、目标 Cash 账户
active + `allow_school_requests` + CNY。

### 已提交

School 的 partial unique index保证同一 `(source_table, source_id, source_event_type)` 只有
一个 active attempt；相同 snapshot 的顺序重复提交复用既有 event。Cash 的 active
reference unique index和 idempotency unique index防止第二个 pending/approved request。

### 已批准

Cash request 的 approved 状态必须有 transaction；11条现有 tuition request 均通过
request→transaction金额/币种/账户/reference/idempotency一致性检查。School callback
对相同 request/transaction id 已幂等；但 Cash approve RPC 本身的重复调用仍返回错误，
需要在开放前改成返回既有 transaction 的幂等成功。

### 已拒绝与重试

现有合同明确且无需新增业务决策：

- rejected request 保留为历史 attempt；不创建 transaction、不改变余额；
- School income 保持 pending，linkage 为 `cash_rejected`；
- 下一次提交创建 `attempt_no + 1` 的新 linkage event；
- idempotency key 为
  `aozora_school:school_income_records:<income_id>:tuition_income_received:attempt:<N>`；
- School active-attempt unique index保证同时只有一个 active attempt；Cash active-reference
  unique index排除第二个 pending/approved request；rejected request不会被复用。

并发情况下唯一约束能保证只生成一个 active attempt/request，但第二个并发调用可能收到
unique violation而不是幂等返回既有 request。下一阶段 rollback 测试必须固定该行为；若要求
两端调用都成功返回同一 request，应在 RPC 内捕获唯一冲突并重读，不改变 retry 业务规则。

## 7. 权限与安全边界

### 正常边界

- 页面只持有 School 会话；不持有 Cash service role，不直接写 Cash DB。
- `request-cash-income-confirmation` 验证 School bearer token，内部使用 School/Cash
  service role bridge。
- Cash approve/reject 依据 Cash authenticated user 与 request owner匹配。
- Cash approve 是唯一创建 `home_cny_transactions` / `home_jpy_transactions` 并改变余额的
  动作；reject不创建交易。
- `sync-cash-request-result` 虽配置 `verify_jwt=false`，函数体仍强制验证 Cash bearer token、
  request owner、terminal status和 canonical reference；它本身不 approve/reject、不创建
  transaction。
- School confirmed writeback不写 School account transaction、不维护 Cash balance；Cash
  不主动创建 School业务记录。

### 必须修复的权限缺口

- School `school_mark_cash_income_request_submitted/confirmed/rejected` 为 postgres owner、
  `SECURITY DEFINER`，PUBLIC/anon/authenticated/service_role 均可执行。
- School `school_request_cash_income_confirmation_for_record` 对 authenticated/service_role
  可执行；页面正常链只需要 service_role Edge bridge。
- `school_personal_cash_income_linkage_events` 无 RLS，anon/authenticated拥有表级
  INSERT/UPDATE/DELETE/TRUNCATE等权限；页面仅需要 SELECT。
- Cash `home_create_external_transaction_request`、approve、reject 为 postgres owner、
  `SECURITY DEFINER`，anon也可执行；函数内的 `auth.uid()` 检查在 anon uid 为 NULL 时不会
  绑定 owner。Cash内部 transaction writer的 ACL 也不一致。

最小修复是权限收缩，不扩大权限：School桥接写 RPC只给 service_role；Cash create只给
service_role；Cash approve/reject/list只给 authenticated（必要运营service_role另行保留）；
内部 transaction writer不给 anon/普通页面；School linkage 表的 anon/authenticated只保留
页面所需 SELECT。所有 revoke/grant 需带 postdeploy privilege assertions。

## 8. Business-model expansion declaration

本轮只读调查：

```text
New tables/columns/status/date/identity/source/writable facts: none
Changed semantics/authority/mutability/locking: none
Schema/RPC/code/Gate/permissions changed: none
Historical reinterpretation/backfill/destructive changes: none
```

下一阶段建议的金额 authority 变更已经由本任务第2节和第5节明确批准为：学费 Cash
请求只消费冻结 canonical bill/income，`billing_amount_cny` 是唯一请求金额；不得重新计算。
不需要新表、新字段、新状态或双写。若实施时发现必须新增业务事实或改变 retry 业务规则，
仍需按 Schema And Business Model Expansion Gate 重新取得逐项明确批准。

## 9. 最小恢复实施方案

1. 保持 Gate blocked，先做 School/Cash ACL 收缩并补齐 privilege postdeploy。
2. 把 School tuition request 分支改成只读冻结 bill/income/identity；固定 CNY、冻结 rate和
   `billing_amount_cny`，拒绝客户端金额/汇率/取整参数。
3. Edge 删除“enabled仍R0 blocked”死分支，但只有在 Gate enabled且 School RPC preflight
   成功时继续；Cash payload只使用 RPC返回的冻结值。
4. 页面/API对 tuition 使用服务端 eligibility/preflight；金额只读，不传业务计算参数。
   普通非 tuition income行为不变。
5. Cash approve改为重复调用幂等返回既有 transaction；不改变首次approve和reject合同。
6. 准备并执行全 rollback fixture 矩阵、并发测试、只读 postdeploy和双库前后指纹。
7. 技术验收全通过后，另行由业务负责人批准 Gate enable；Codex不提交任何真实学生。
8. Gate开放后业务负责人按逐人清单提交；陈加恩和所有 ALREADY_SYNCED/BLOCKED记录永久
   不出现可提交按钮。

本轮不生成可执行 Gate enable SQL，因为现有缺口尚未关闭，提前准备可执行开放脚本会增加
误操作风险。下一阶段 enable SQL 必须把 Edge部署指纹、RPC指纹、ACL、20+ rollback测试、
7条固定基线SHA和双库零漂移作为 preflight，最后只更新
`student_tuition_cash_submit` 一行。

Emergency disable 应是独立、幂等、只更新该 Gate 为 `blocked` 的 SQL；不回滚已 approved
交易，不修改 pending/received income，不删除 request/linkage。Edge和School DB每次提交都
实时读 Gate，因此 disable 后新提交立即失败；已有 Cash pending request仍由人工明确处理。

## 10. 下一阶段 rollback 测试矩阵

至少覆盖：

1. eligible tuition income创建一个 Cash pending request。
2. 同一income重复提交返回同一request。
3. 并发提交只创建一个active request，并固定第二调用的幂等结果。
4. School event后/Cash request前失败可安全重试，无第二event。
5. Cash request后/School submitted回写前失败可安全重试并复用request。
6. approve创建唯一transaction并回写School received/synced。
7. 重复approve幂等返回同一transaction。
8. reject不创建transaction、不改变余额，School income保持pending。
9. reject后新attempt号和幂等键正确，旧request不复用。
10. 已有transaction、received/synced不可再提交。
11. cancelled/voided/reversed/incident/excluded/row-blocked不可提交。
12. request、payload、transaction金额精确等于冻结`billing_amount_cny`。
13. 前端/API不传 tuition amount/rate/rounding；篡改客户端参数被拒绝。
14. 错误Cash账户、inactive、`allow_school_requests=false`或非CNY拒绝。
15. 非tuition普通income行为零回归。
16. Personal Cash、旧bill→income、manual sync、legacy request type继续fail-closed。
17. Gate blocked时页面、Edge、School RPC/trigger都拒绝。
18. anon和普通authenticated不能直接调用桥接/回写/内部transaction写RPC。
19. emergency disable立即阻断新提交，不修改既有terminal记录。
20. fixture全ROLLBACK、残留0；不使用真实学生。
21. School/Cash全表前后指纹不变。
22. 7条真实候选基线TSV SHA保持不变；陈加恩等已同步记录不可见提交入口。

## 11. 本轮执行与零写入证明

执行的只读 SQL：

- `sql/current/school_tuition_cash_submit_recovery_readonly_investigation_20260802.sql`
- `sql/current/cash_tuition_cash_submit_recovery_readonly_investigation_20260802.sql`

没有调用任何业务 RPC；只通过 `SELECT` 读取表、catalog、函数定义、ACL/RLS/constraint/index。
School与Cash DB都建立了只读连接；没有 insert/update/delete/upsert/DDL，没有 Cash request、
Cash transaction、approve/reject、School income/linkage/bill/identity/relation/lesson/settlement/
wage/account transaction写入。

只读末端指纹：

| DB | 对象 | 行数 | MD5 |
|---|---|---:|---|
| School | tuition bills | 16 | `66efdf2de6cf5ec906eb6879ccb2ae52` |
| School | income | 49 | `76dfc996acdf1dca834d7b6cb75af8be` |
| School | billing identities | 14 | `dd6b170ed6eb60d72db72975dd197d4e` |
| School | bill lessons | 236 | `3d064537a43cc38392277f364c32f138` |
| School | Cash income linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| Cash | external requests | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| Cash | CNY transactions | 63 | `3759e3d726400d5dd2225d79c78b9ac2` |
| Cash | JPY transactions | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

本轮新增的本地文件只有本报告、两份只读调查 SQL 和一份 TSV。没有修改代码、既有 SQL、
Gate或数据库；没有 `git add`、commit、push。两份既有保护文件未读取正文、未修改、未删除、
未暂存。
