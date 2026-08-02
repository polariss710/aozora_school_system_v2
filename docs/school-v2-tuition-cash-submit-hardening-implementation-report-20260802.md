# School V2 学费 Cash 提交技术硬化实施报告

日期：2026-08-02（JST）
阶段结论：技术硬化完成；停在 Cash Gate 开放前审查点

## 1. 结果

School/Cash RPC、ACL、Edge、API和页面硬化已完成并通过双库rollback、只读
postdeploy和静态测试。学费Cash请求金额唯一读取冻结
`school_student_tuition_bills.billing_amount_cny`，币种固定CNY，汇率读取冻结
`billing_exchange_rate`；客户端金额、币种、汇率及rounding输入全部fail-closed。

本阶段没有提交真实学费income，没有新增或修改真实School/Cash业务行。最终Gate仍为：

```text
student_tuition_preview     = enabled
student_tuition_generate    = enabled
student_tuition_cash_submit = blocked
```

Business-model expansion declaration：新表、字段、状态、日期、identity、source、snapshot、
可写业务事实、fallback、dual write、历史解释均为`none`。本轮只实现已批准的冻结CNY金额权威、
幂等、最小ACL和既有状态生命周期。

## 2. 权威fixture与direct DML保护

School fixture调用链：

```text
codex-test student
  -> school_create_planned_lesson_record（既有planned RPC）
  -> school_get_student_tuition_validation_preview_details
  -> school_generate_student_tuition_bill_atomic_core（owner-only）
  -> billing identity + bill + normalized relations + pending canonical income
```

测试没有直接写identity、bill、relation或tuition income，也没有禁用trigger、修改
`session_replication_role`或伪造writer context，因此Atomic Core建立writer context后，既有
`school_guard_r0_tuition_business_mutation`识别正式writer并允许原子生成；函数返回前context
清空。Cash callback曾暴露普通`UPDATE tuition income`会正确触发
`TUITION_DIRECT_DML_FORBIDDEN`，随后按批准合同做最小纠正：confirmed先把canonical linkage
写成`synced/approved`，guard只允许同一income从`pending`到`received`及
`Cash待确认`到`Cash已确认`的精确投影，其他字段逐字段不变；request/reject只写linkage，
不再改tuition income。冻结金额和其他业务字段仍只有Atomic Writer可写。

最终一次School rollback fixture对象：

| 流程 | student | planned | identity | bill | income | linkage |
|---|---|---|---|---|---|---|
| approve | `f2fc0000-0000-4000-8000-00000000a001` | `00bc2d08-079e-4c25-b580-0120bc157aef` | `e9166854-ca54-4287-a56b-f303a2b04e69` | `387e754a-407e-43e3-b0e2-1033d616c717` | `f7b83cf3-47c6-4083-86ad-a763399e9f73` | `bb0efab3-cad8-4297-ab69-589d9536a986` |
| reject/retry | `f2fc0000-0000-4000-8000-00000000a002` | `7fd20c22-e891-4aff-b5a5-d24ba2004aea` | `5f369333-6e7f-448e-ad68-4d7988ffc64e` | `3eb2ec4a-7ed3-4188-ab0b-6180ad2883c3` | `fa9171bd-47fd-4bd9-8890-8a1762cfa385` | `431c8cd6-ba6f-4d8c-84f2-e37f88833a7d` |

占位callback ID为request `f2fc0000-0000-4000-8000-00000000d001`、transaction
`f2fc0000-0000-4000-8000-00000000e001`。Cash独立rollback最终一次创建request
`1a47ed5d-044c-4deb-ad05-5684530f34bd`、transaction
`261ff1ff-50d4-4478-b881-38ffeb400f6f`；reject request为
`1e90e4cd-b313-4c9a-adb1-24d52664b2fd`。Cash测试账户为固定
`f2fc...c001`至`f2fc...c004`，全部回滚。

## 3. 双库事务编排

School与Cash分别使用显式事务，未假装存在跨库原子事务。School事务生成canonical
fixture并验证request/submitted/confirmed/rejected；Cash事务只消费此前School fixture输出的
canonical external reference和冻结payload，验证create/approve/reject/retry。两边均显式
`ROLLBACK`；事务结束后另启只读事务确认School fixture、writer context、Cash账户/request/
transaction残留全部为0。异常路径由`ON_ERROR_STOP`和未提交事务保证连接退出自动回滚。

## 4. 26项验收矩阵

| # | 结果 | 证据 |
|---:|---|---|
| 1 | PASS | eligible canonical fixture创建唯一pending School event及Cash request。 |
| 2 | PASS | 顺序重复School submit返回同一event；Cash duplicate create返回同一request且`inserted=false`。 |
| 3 | PASS（安全边界） | 两库active unique index、row/advisory lock及`unique_violation`重读共同保证并发收敛；rollback-only未用第二连接读取未提交fixture，未做伪并发或永久fixture。首次Gate开放后的单条真实提交验收保留运行时双调用观察。 |
| 4 | PASS | School event生成后未有Cash request时重复request复用同一active event。 |
| 5 | PASS | Cash request存在后submitted callback重复执行幂等。 |
| 6 | PASS | 首次approve只创建1条CNY transaction。 |
| 7 | PASS | 重复approve返回同一transaction，`transaction_inserted=false`，count保持1、sum保持CNY1000。 |
| 8 | PASS | reject后transaction为0，测试账户流水金额不变。 |
| 9 | PASS | reject后School attempt 2和`:attempt:2`新key正确；Cash下一attempt创建新pending request。 |
| 10 | PASS | rejected request保留terminal历史，不被新attempt复用。 |
| 11 | PASS | received/synced/已有transaction动态拒绝再次提交。 |
| 12 | PASS | cancelled/voided/reversed/incident/excluded/row-blocked由preflight状态条件和17行只读基线验证为非eligible。 |
| 13 | PASS | request、payload和transaction均为Atomic bill冻结`billing_amount_cny`。 |
| 14 | PASS | DB四类非空货币输入逐一拒绝；Edge拒绝amount/currency/rate/rounding；API tuition body不含这些字段。 |
| 15 | PASS | wrong、inactive、`allow_school_requests=false`、JPY账户及请求币种不符均拒绝。 |
| 16 | PASS | 普通非tuition explicit amount测试仍返回原CNY123.45。 |
| 17 | PASS | Personal Cash、旧bill→income、manual retry及Cash legacy request type保持fail-closed。 |
| 18 | PASS | Gate blocked时School RPC/trigger拒绝；部署Edge probe返回HTTP 423；页面只按server preflight显示入口。 |
| 19 | PASS | anon/PUBLIC/普通authenticated不能调用School bridge/callback或Cash create/internal writer。 |
| 20 | PASS | callback submitted/confirmed重复执行均幂等；rejected terminal合同不变。 |
| 21 | PASS | School与Cash测试事务均输出`ROLLBACK`。 |
| 22 | PASS | School/Cash fixture残留均0。 |
| 23 | PASS | writer context在Atomic Core返回后、rollback前及rollback后均0。 |
| 24 | PASS | 原16条TSV SHA保持`33d0cb9a...ec35`。 |
| 25 | PASS | 17条基线SHA为`b91cb9da...cf46`；8条eligible集合SHA为`e1ad372f...d09`。 |
| 26 | PASS | School bill/income/linkage及Cash request/CNY/JPY真实业务指纹前后不变；Gate rehearsal后仍`enabled / enabled / blocked`。 |

并发项没有牺牲rollback-only约束：真正两连接都读取同一未提交School fixture不可能；本轮以
唯一约束、锁、异常重读分支和顺序重复调用完成数据库合同验收，没有提交永久fixture。

## 5. 金额、ACL与Edge

School RPC在锁定income/bill/identity并交叉检查snapshot后固定返回：

```text
payment_currency      = CNY
payment_exchange_rate = bill.billing_exchange_rate
payment_amount        = bill.billing_amount_cny
```

Edge只把这三个School返回值写入Cash payload/RPC；tuition调用School时四个货币参数为NULL。
页面展示preflight金额且只读，tuition API body只含income、Cash account、date和note；页面模块
无直接`.rpc()`或表DML。

ACL终态：School request/submitted/confirmed/rejected仅`service_role`；preflight为
`authenticated, service_role`；School linkage对anon/authenticated仅SELECT。Cash create和
CNY/JPY内部writer仅`service_role`；approve/reject为`authenticated, service_role`且函数内
核对owner；anon/PUBLIC均无执行权。

Edge `request-cash-income-confirmation`部署version为10，bundle SHA-256为
`bd5a0924ae6fb2ab9114f6103a90f825968520784069d9f704a4ac74374cb6a3`，本地源SHA-256为
`e3e42e2f7b03654c03612def0c1f9d9515dc702432bdf2ec44e55c7cddd4ad54`。已登录部署probe使用
ALREADY_SYNCED非eligible income及虚假Cash账户，返回HTTP 423；未使用8条eligible，也未写
School linkage或Cash request。enabled逻辑由静态fixture测试覆盖。完整真实E2E只能在Gate
开放后由业务负责人选择一条真实eligible提交，这是唯一延后事项。

## 6. Gate与基线

Gate enable脚本：
`sql/current/school_tuition_cash_submit_gate_enable_20260802.sql`。它要求Edge version/bundle/
source SHA、16/17 TSV SHA、eligible SHA、双库rollback结果、School函数MD5/ACL和真实业务
指纹全部匹配；本轮以`tuition_cash_gate_commit=0`执行，输出`UPDATE 1`后`ROLLBACK`，未正式
启用。

Emergency disable脚本：
`sql/current/school_tuition_cash_submit_emergency_disable_20260802.sql`。本轮以
`tuition_cash_disable_commit=0`演练；因Gate已经blocked而`UPDATE 0`，断言通过后ROLLBACK。
脚本只阻断新提交，不删除或修改既有业务记录。

基线：原16条SHA为`33d0cb9a8d0cb62c4de5f6ea26ed658b6898293def3cc2ee205d58721295ec35`；
新17条SHA为`b91cb9dacef0c0c68013c5a2435a32a27cbef5089a159f30c49247a1145ccf46`；
8条eligible字段集合SHA为`e1ad372ffea00b113088d7a39d7ab3ee2841f9b18ae3e18fd22952711b3cfd09`，
合计JPY2,605,800、冻结CNY109,926.72、carryover CNY107.50。

孙陈锋2026-09保持bill `3435cbac-adc5-4bec-a54c-cefaab593359`、income
`004c7eeb-94c8-4312-aa2c-1ab44baa70dd`、JPY350,560、rate 0.0415、CNY14,548.24、
carryover 0、income pending；postdeploy只读断言通过，没有改动。

## 7. 指纹、执行与数据库写入分类

| DB对象 | 前后行数 | 前后MD5 |
|---|---:|---|
| School bills | 17 | `b18f15673637280bf1455667ccd3cc00` |
| School income | 50 | `d393822a95c6121a2e754919b1464a5b` |
| School linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| Cash requests | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| Cash CNY transactions | 63 | `3759e3d726400d5dd2225d79c78b9ac2` |
| Cash JPY transactions | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

执行的持久SQL：

- `sql/current/school_tuition_cash_submit_hardening_rpc_acl_20260802.sql`
- `sql/current/school_tuition_cash_submit_hardening_lifecycle_guard_correction_20260802.sql`
- `sql/current/cash_tuition_cash_submit_hardening_rpc_acl_20260802.sql`

持久数据库写入仅为函数定义、comment、REVOKE/GRANT；真实业务DML为0。执行的write RPC仅发生
在School/Cash rollback事务中的白名单fixture；所有fixture记录ID见第2节，最终残留0。
Gate enable没有正式执行；emergency disable只做rollback rehearsal；Edge唯一操作为version 10
部署和blocked无写probe。

两份保护文件未读取正文、未修改、未暂存；第二份SHA保持
`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。
