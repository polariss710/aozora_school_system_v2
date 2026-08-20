# School V2 × Cash P0：历史 fingerprint resolver 最终实施报告

日期：2026-08-21
范围：Phase A—F；本报告固化最终只读验收、部署事实和目标单笔 callback-only 恢复结果。

## 1. 闭环结论

本 P0 已闭环。目标 Home request `aec4eb6d-2794-4ea4-abef-2176d32c48c5` 在 Cash 端原本已经唯一批准并生成唯一 CNY transaction `ccf672a4-acbe-4ff7-abd6-5786088cbaad`；故障只发生在 School 回写。生产 v12 上线后，Phase E 仅对该 request 执行一次真实 sync POST，School expense `204278e1-5f89-4358-b4ea-1effa5be48af` 从 pending 进入 paid，attempt `0590a210-20af-4e4c-a5d6-98acfe1da5fc` 从 submitted/version 1 进入 approved_immediate/version 2。Home request、transaction和账户余额未被再次写入。

Phase F 未调用任何生产 writer、callback 或部署；生产检查全部为 SELECT。页面版本仍为 `v10.5.55`。

## 2. 原始故障与根因

原始错误为：`School Cash V2 evidence is missing request_payload_fingerprint`。Phase 3C2-R 将历史 immediate expense attempt 确定性回填为 V2 attempt 事实，School attempt 已保存 DB canonical fingerprint；但这批 request 的 Home `payload_snapshot` 创建更早，不含 `request_payload_fingerprint`。旧 sync/shared 流程在按历史生命周期分类前即把所有 immediate expense 送入 native V2 fingerprint 必填校验，因此 Cash 已终态后无法进入既有 School 专用 callback writer。

这是 Phase 3C2-R 切换后留下、在后续 sync 路径中暴露的历史兼容缺口，不是 Phase 3E statement migration 导致。目标业务是 `immediate_account / expense_paid`，不是 fixed；Phase 3D fixed 分支有独立 typed evidence、projection和callback RPC，Phase 3E statement/funding/correction对象也不参与本调用链。income继续走独立income mapper/RPC。

修复没有为 Home snapshot 伪造或补写 fingerprint，也没有降低 native V2 校验。v12 仅在字段“真正不存在”、且业务已先分类为 School immediate expense 时调用 School 只读 resolver；字段存在但空、格式错误、长度错误或内容冲突仍 fail closed。

## 3. Historical resolver 资格合同

resolver 只接受以下结构化证据同时成立的 Phase 3C2-R 历史记录：

- canonical source/reference/type 为 `aozora_school / school_expense_records / expense_paid / expense`；
- `payment_route=immediate_account`，original和settlement币种仅JPY/CNY；
- expense、attempt、request、event、idempotency、attempt no均唯一且互相对应；
- original amount/currency、payment amount/currency、Cash账户和charge date逐字段一致；
- School expense镜像与attempt一致，attempt具有submitted时间，prepared recovery三个字段均未使用；
- 历史生命周期只能是submitted/v1、backfilled terminal/v1或本兼容路径恢复后的terminal/v2；native submitted/v2、native terminal/v3及prepared recovery记录不得进入；
- approved必须提供唯一、完整且逐字段匹配的Home transaction；rejected必须不存在transaction；
- DB使用`school_expense_cash_attempt_payload_fingerprint_v2(...)`重算，结果必须等于School attempt冻结fingerprint。

resolver不依据老师姓名、备注、自由文本、运行时ID allowlist或固定hash判定。兼容路径的退休条件是24条Phase 3C2-R request不再需要callback replay，并经生产监控确认不存在missing-fingerprint历史request；退休需独立阶段，不得把本路径扩成一般NULL fallback。

## 4. Native、historical、fixed与income边界

- native immediate expense：Home snapshot fingerprint存在且合法时继续严格使用原值；不允许resolver覆盖。存在但畸形时直接拒绝。
- historical immediate expense：仅字段缺失时查询Home JPY/CNY两表的完整唯一交易证据，再调用只读resolver，随后仍进入原有strict mapper和V2 callback writer。
- fixed expense：在业务分类阶段进入fixed evidence reader及`school_mark_cash_fixed_expense_approved_v2`/rejected路径；不调用historical resolver。
- income：继续走`school_mark_cash_income_confirmed`/rejected路径；不调用historical resolver。

shared mapper不计算fingerprint、不读取数据库、不判断历史资格。sync中未增加Home approve/reject/create request/create transaction writer，现有School状态变更仍由原子transition/callback RPC执行。

## 5. DB函数与安全属性

新增函数：

- owner-only core：`public.school_resolve_historical_expense_cash_attempt_fp_v1_core(...)`
- service-role wrapper：`public.school_resolve_historical_expense_cash_attempt_fingerprint_v1(...)`

共同输入类型签名：

```text
(uuid,uuid,uuid,text,timestamptz,timestamptz,text,uuid,text,text,uuid,
 text,text,text,integer,numeric,text,numeric,text,uuid,date,uuid,uuid,uuid,
 text,numeric,text,uuid,date,text,text,uuid,text,text,uuid,text,boolean)
```

共同返回expense/attempt identity、attempt status/version、historical shape和DB重算fingerprint。两者均为postgres owner、`STABLE`、`SECURITY DEFINER`、固定`search_path=pg_catalog, public`。core仅postgres可执行；wrapper仅service_role和postgres可执行；PUBLIC、anon、authenticated均无EXECUTE。函数只读，不含业务DML，不增加service_role对expense/attempt表的DML权限。

最终生产定义MD5：core `f3fe6ef9128f20109876d0ede22536ef`，wrapper `f4134cce6da41f02ec2bdff0e5113b2c`。

## 6. Phase B本地验证

Phase B完成shared/sync语法、native JPY/CNY、missing/malformed fingerprint、approved/rejected首次恢复、terminal exact replay、transaction 0/1/many、fixed/income隔离、ACL/search_path及逐字段负向矩阵。隔离PostgreSQL加载真实helper与migration验证成功；未连接生产执行写入型测试。详见保留的Phase B报告。

## 7. Phase C生产ROLLBACK与并发

Phase C在生产顶层事务内完成resolver全合同演练并显式ROLLBACK：24/24 Phase 3C2-R记录符合只读资格，分布为approved/v1 16、rejected/v1 2、submitted/v1 6。覆盖CNY/JPY、approved/rejected、字段冲突、exact replay、native/fixed/income隔离、Home PostgREST真实只读证据及双独立连接并发。事务后以新连接确认fixture、2099数据和业务表残留均为0，目标及非目标manifest无漂移。

## 8. Phase D部署

2026-08-20 17:20:30—17:20:31 UTC完成resolver函数migration部署；17:22:12—17:22:15 UTC部署`sync-cash-request-result` v12。最终Edge事实：

- function ID：`16898c4b-ca5d-437b-97be-59b99149077e`
- status/version：唯一`ACTIVE / 12`
- bundle SHA-256：`5cd1173ca422476fb5357307711c61b85221bda74b975c6d70f28d62889fed45`
- migration SHA-256：`99435bb82f3f731a5cd167f2232356c2f1e33e1f3acacb02a4c14f41666239ca`
- sync源码SHA-256：`e70b738204f60526ca016f957e6ed13c2060e56002d3d2c7d54bf084ad556723`
- shared mapper SHA-256：`9320b516e0052d09681025008634bee3a11f13e1d1f9b6dc57d0e6e483b91b99`
- source-set manifest：`e3433e66790a2fb31c317a60c639a118a2857f0daa677b8a8c8d973062c58635`

Phase F重新下载ACTIVE v12源码，逐文件及source-set均与本地完全一致。request Edge未重新部署，Home源码及Pages未修改。

## 9. Phase E唯一真实callback

Phase E只对目标request发出一次真实POST，窗口为2026-08-20 18:18:28.290—18:18:36.153 UTC，HTTP 200；另有浏览器自动OPTIONS 204，不是业务重试。

- invocation ID：`98aeffad-82e5-42bd-8733-79cd195c4f06`
- execution ID：`4442f35a-6dc1-4ae2-8480-a1b92c3e3410`
- deployment ID：`xlcdqvlfzspcxdoidsrr_16898c4b-ca5d-437b-97be-59b99149077e_12`
- execution time：2896 ms

访问token仅留在浏览器会话内部，未写入仓库、报告或命令输出。没有第二次POST、幂等重放或Home approve调用。

## 10. Home零重复证明

最终独立连接SELECT确认request仍为approved，`approved_at=2026-08-19 15:43:33.650642+00`，历史snapshot仍不含fingerprint；目标transaction仍为`ccf672a4-acbe-4ff7-abd6-5786088cbaad`、expense CNY 1,330、school scope、原账户和日期不变。request与transaction按ID、event、idempotency、reference四种身份的计数均各为1；账户余额仍为CNY 203,662.50，只承受一次CNY 1,330扣减。request/transaction最终行MD5分别为`c7811ccfdf4e7273fe4d9b7caa03b8b2`和`d7586101c00104cae3fd71de9e3c83d6`。

## 11. School最终状态与时间合同

School expense为paid，Cash request镜像为approved，Cash transaction镜像为目标transaction；attempt为approved_immediate/version 2，transaction相同，latest error code/message均为NULL。original amount仍为JPY 31,500，settlement amount仍为CNY 1,330，fingerprint仍为`aa0f9e436356ba58c9b4734bd5f1ee1ab06eeeb09060028e7bcd4bbedc7428bf`。expense/attempt目标identity各只有1条，最终行MD5分别为`90c455f9d9b95a19de7f0ff1820e7b21`和`cb850be731dfcaa2ead374e35d4f7633`。

本P0正式接受并固化以下时间语义：

```text
cash_synced_at = Home Cash终态业务生效时间 = Home approved_at
               = 2026-08-19 15:43:33.650642 UTC

school_expense_records.updated_at = School实际callback写入墙钟时间
                                  = 2026-08-20 18:18:36.015733 UTC
```

callback延迟不改写Cash真正批准时间；两字段不要求相等。本P0不新增字段、不修改成功记录，也不重定义其他历史时间语义。

## 12. 非目标业务零变化

其余5条submitted/version 1历史attempt保持原状态和版本，manifest仍为`b0c4dec837bce16bed6477381607fb6f`。工资lock仍1条、manifest `f00238d47a54c17deb5e2b316c45918a`；3条工资detail manifest仍为`f0632ee68df24438510021c4726cd1fe`。fixed attempt为0；Home fixed projection/cycle/revision均为0，70条fixed month item manifest保持`5f5706f813b77e450c170368db47d738`。School income、非目标expense/attempt以及2099 fixture均无异常变化。

## 13. 其他5条历史request

本P0不授权批量恢复。它们对应的Home request尚未形成approved/rejected终态，不得提前sync、批量补Home snapshot或手工UPDATE School。只有每条Home request按正常流程被独立批准或拒绝后，才可由正常sync callback逐条处理。resolver只是严格兼容能力，不是批量业务处理授权。

## 14. 测试与源码一致性

Phase F提交前复跑并通过：

- shared JS语法检查；
- sync TypeScript strip-types语法检查；
- `P0_HISTORICAL_RESOLVER_EDGE_MOCK_TEST_PASS`；
- `P0_HISTORICAL_RESOLVER_LOCAL_POSTGRES_TEST_PASS`；
- ACL/SECURITY/search_path及native/fixed/income隔离；
- `git diff --check`；
- P0文件限定secret扫描；
- 临时PostgreSQL、2099 fixture和测试残留检查。

本地resolver测试第一次在受限沙箱内因SysV共享内存权限失败；获准在沙箱外用自动清理的临时PostgreSQL重跑后通过。这是测试环境限制，不是代码或合同失败。

## 15. Git交付

实现提交：`cc831fc`（`fix(school): recover historical cash expense callbacks`），仅包含resolver migration、shared mapper、sync Edge、Edge mock和resolver本地测试。Phase B报告、本最终报告及`docs/current-status.md`由独立文档提交交付；该提交的完整hash与push结果记录在Phase F最终对话回执和Git历史中，以避免文档自引用hash。

Home仓库没有文件修改或commit。既有无关untracked/ignored文件全部保留，PDF相关diff为0。

## 16. 尚存风险与后续顺序

- historical resolver是限时兼容面；待24条历史request全部不再需要callback replay后，应另阶段审计并退休，不能永久扩成一般fallback。
- 其余5条submitted历史attempt仍等待各自Home业务终态；本P0闭环不等于允许批量处理。
- 对未来每条恢复仍须证明Home终态、交易唯一、School当前状态及exact callback幂等边界。
- 已只读确认`#globalSessionBar`会进入契约书、报价单和学费收据打印；该问题与本P0无代码重叠。应在本P0闭环后作为独立Pages任务处理，不得混入Cash修复提交。

在遵守上述逐条业务授权和独立任务边界的前提下，可以恢复此前暂停的其他阶段；不得把本resolver视作fixed、income、statement、funding或correction路径的授权。
