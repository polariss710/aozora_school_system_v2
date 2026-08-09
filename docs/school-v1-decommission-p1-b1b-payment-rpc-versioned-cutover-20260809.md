# School V1 下线 P1-B1B：Payment RPC版本化迁移与旧入口封闭

- 日期：2026-08-09（Asia/Tokyo）
- 当前阶段：P1-B1B完整完成；B1B-A～E全部验收通过
- 当前安全状态：V2已切换新RPC；两个旧RPC为owner-only历史内部对象
- V1基线：`main/e316598dafbe4d7f50a88c70e8bc488d792a2d49`
- V2起始基线：`main/43764200e56e326e7c120c255b1426455ace8471`
- 并发流程吸收后的V2基线：`main/6951c2fe8429ed9312c1f4d1af3e24aade488c3f`
- B1B-D后并发流程最新本地基线：`main/008dfe2aa66121a10cab7c685a0e68077fc1477d`

## 1. 执行摘要

P1-B1B采用可观察的五段切换：只读Preflight、新RPC加法部署、V2 Pages切换、旧RPC精确权限封闭、最终验收。两个旧入口各只有一个签名；V1和V2都直接调用旧名称，数据库内部、Edge、cron和Webhook未发现其他合法调用方。

选择的版本化架构为：保留两个既有、已审计的`SECURITY DEFINER`函数作为唯一业务实现；新增同参数、同返回契约的`_v2` wrapper。新wrapper先再次调用当前active-admin断言，再单次委托旧函数，不复制payment状态机、金额、锁、幂等、审计或Cash逻辑。V2线上切换成功前，旧RPC的authenticated权限保持不变。

加法migration已于`2026-08-09T14:23:31Z..14:23:41Z`成功提交，只创建两个wrapper及其精确ACL/comment并刷新PostgREST schema cache。部署前后51条payment request、47条支出、187条账户流水和全部School/Cash/Storage/Auth/Gate指纹完全一致；没有调用任何业务RPC。

## 2. 授权边界

### 2.1 本阶段允许并已执行

- V1/V2代码、历史migration、报告和Git状态只读检查。
- School/Cash生产库显式只读事务catalog与脱敏aggregate查询。
- 本地空PostgreSQL 17.10 synthetic解析、ACL、角色、委托、回滚和并发测试。
- 新增两个版本化payment wrapper并部署纯加法migration。
- 准备V2 payment API切换、页面版本和cache token更新。

### 2.2 未执行

- payment、支出、收入、账户流水、Cash、工资、月结、账单、课时业务写入：0。
- 正式payment writer调用：0。
- 旧RPC权限撤销：尚未执行，必须等待V2线上切换Gate。
- Storage、Auth/session、Edge、cron、Webhook、Realtime、Vault、Gate变化：0。
- V1页面、service worker、Pages、DNS、Freeze、归档或恢复演练：0。

## 3. 工作区与生产版本基线

调查开始时V1为`e316598d…`且仅保留用户既有`M .gitignore`。V2最初为P1-B1A-R1提交`4376420…`，随后另一个已获授权流程推进settlement合同到`6951c2f…`。Commit 1推送后，该流程又提交`008dfe2…`（guarded settlement Edge entrypoints）；7个文件均为settlement API/test/config/Edge，与payment范围不重叠且没有四个payment RPC引用。本阶段没有回退、覆盖或提前推送对方提交，并在最新HEAD重新完成payment调用定位和静态回归。

V2既有2份untracked V1报告、1份CSV、1份TXT和4个SQL fragment继续保留，不纳入本阶段commit。生产页面起始版本为`v10.5.30`；本阶段选择`v10.5.31`。

## 4. Business-model expansion declaration

| 项目 | 声明 |
|---|---|
| 新表、列、enum/status、日期/月、归属、身份、来源、快照/version业务概念、可写事实 | none |
| 字段语义、字段可变性、历史解释 | unchanged |
| 新权威来源、fallback、dual-read、dual-write | none |
| payment状态机、金额、币种、来源、审计、幂等 | unchanged |
| 锁定和并发顺序 | unchanged；新wrapper无锁且单次委托旧实现 |
| writer reachability | 新`_v2`仅authenticated入口且DB active-admin；V2切换后旧签名owner-only |
| destructive schema change | none；旧函数不删除、不改体 |
| 批准依据 | 当前P1-B1B任务第一、七、十三节对exact版本化与旧EXECUTE收口的明确批准 |

## 5. 两个旧RPC精确身份与全部overload

| RPC | 参数/default | 返回 | 线上definition MD5 |
|---|---|---|---|
| `public.school_confirm_payment_request(uuid,uuid,date,numeric,text,text)` | request id、account id、pay date；amount/note可NULL；method默认`bank_transfer` | 7列payment/expense/transaction/status/paid/account/balance结果 | `c15d26dfd81f36446b2f3e74b5ab74ed` |
| `public.school_reverse_paid_payment_request(uuid,text,date)` | request id；reason可NULL；reverse date默认`current_date` | 10列old/new status、expense、原/反向流水、account、amount、balance、time结果 | `e5513e22edbfaa9948848b55857c6655` |

online catalog确认每个名称都恰有1个overload，没有遗漏签名。owner均为`postgres`，`SECURITY DEFINER=true`、volatile、parallel unsafe、`search_path=pg_catalog, public`。

## 6. 调用矩阵

| 调用方 | confirm | reverse | 证据/结论 |
|---|---|---|---|
| V1部署代码 | 旧名称 | 旧名称 | `js/modules/payment-management.js:361,427` |
| V2当前运行代码 | 旧名称 | 旧名称 | 切换前`js/api/payment-api.js:98,164` |
| DB内部函数 | 无 | 无 | online `pg_proc.prosrc`反向搜索0行 |
| Edge Functions | 无 | 无 | V2 Edge/source exact-name扫描0行 |
| cron/Webhook | 无证据 | 无证据 | DB无cron catalog；仓库workflow/Edge exact-name扫描0行 |
| 历史SQL/测试 | 有 | 有 | 仅部署/rollback/postdeploy证据，不是运行时调用方 |

旧RPC同时承担公开入口和唯一权威业务实现；没有独立core。直接修改旧函数体或复制其业务逻辑都不是最小方案。

## 7. 旧RPC权限与业务安全属性

部署前两个旧RPC ACL相同：postgres与authenticated有EXECUTE；PUBLIC、anon、service_role没有EXECUTE。函数首段均执行`public.school_require_current_app_admin()`，该owner-only helper使用`auth.uid()`和canonical membership，只有active admin通过。

confirm锁payment request，再锁school account；创建1条teacher-wage支出、1条账户流水并更新payment/account。reverse锁payment request、支出、原流水和account，并保留原对象、创建1条反向流水。新wrapper不引入任何锁、查询、金额计算或状态分支，因而锁顺序、幂等范围、expected-state错误和返回结构全部由旧函数继续唯一决定。

## 8. 版本化方案与新旧契约对照

新入口：

- `public.school_confirm_payment_request_v2(uuid,uuid,date,numeric,text,text)`
- `public.school_reverse_paid_payment_request_v2(uuid,text,date)`

两者均owner=`postgres`、`SECURITY DEFINER`、volatile、parallel unsafe、固定`search_path`；PUBLIC/anon/service_role无EXECUTE，仅authenticated有EXECUTE。函数体只有active-admin断言和一次schema-qualified旧函数调用。

| 合同 | 旧RPC | 新RPC |
|---|---|---|
| 参数名称、顺序、类型、default | 线上权威值 | 完全相同 |
| 返回列、类型、顺序 | 线上权威值 | 完全相同 |
| active admin | 函数首段要求 | wrapper先要求，旧函数再次要求 |
| 金额/币种/来源/状态机 | 旧函数决定 | 单次委托，不重算 |
| 锁、幂等、expected-state | 旧函数决定 | 无新增锁/分支 |
| 审计/actor/time/Cash边界 | 旧函数决定 | 不修改 |
| 错误码/消息 | 旧函数抛出 | 原样传播 |

新名称隔离只阻止未更新的V1静态代码自动调用；它不是抵御恶意active admin的独立安全边界。P1-B2仍必须处理旧session。

## 9. 非生产验证

全新本地PostgreSQL 17.10数据库仅包含synthetic角色、membership、空业务表及两份与线上MD5完全一致的旧函数定义，没有复制生产数据。

| 测试 | 结果 |
|---|---|
| migration完整解析、preflight、create、ACL、postdeploy、COMMIT | PASS |
| PUBLIC/anon/service_role拒绝，新authenticated允许 | PASS |
| 无membership、inactive、operator、read_only | 均`42501/P0G1_ACTIVE_ADMIN_REQUIRED` |
| active admin confirm | 单次进入旧函数，产生synthetic支出/流水/余额结果 |
| duplicate confirm | 原`status must be pending`语义 |
| active admin reverse | 单次进入旧函数，恢复synthetic余额并标记支出/payment |
| duplicate reverse | 原`already reversed`语义 |
| 外层ROLLBACK | payment/account/expense/transaction residue均0 |
| PUBLIC function default ACL漂移 | DDL前`P1_B1B_PUBLIC_FUNCTION_DEFAULT_ACL_FOUND` |
| 未预期旧overload | DDL前`P1_B1B_UNEXPECTED_LEGACY_OVERLOAD` |
| 中途强制异常 | probe不存在，旧authenticated EXECUTE恢复 |
| 并发 | B在A持有旧payment行锁时未返回；A COMMIT后B由旧状态机拒绝，最终唯一支出/流水 |

## 10. B1B-B新RPC加法部署

文件：`sql/current/school_v1_decommission_p1_b1b_payment_rpc_additive_20260809.sql`

| 字段 | 结果 |
|---|---|
| 执行文件SHA-256 | `84b04fded4f0b7bf6b4d5f60499b7838b66934ad89ff6202aab7e2dab9a6d696`；补充执行状态注释后的归档文件SHA为`4933307b5f46754147309c1cc22b199956bfd665d402e3406dd26c74bb12324a`，SQL逻辑未变 |
| 开始/结束UTC | `2026-08-09T14:23:31Z` / `2026-08-09T14:23:41Z` |
| 执行身份 | postgres/session_user postgres |
| 返回 | `BEGIN; DO; CREATE FUNCTION x2; ALTER x2; REVOKE/GRANT x2; COMMENT x2; DO; NOTIFY; COMMIT` |
| 事务 | 成功提交 |
| 业务RPC调用 | 0 |
| 业务数据变化 | 0 |
| 旧RPC权限 | 保持authenticated，未提前封闭 |

加法部署后新函数definition MD5为confirm `af6f0a1abd5a3090351c6eed785ef2f5`、reverse `002a27499d63e31f82b104065944ba5e`。参数、返回、安全属性、ACL和委托关系全部通过online catalog验收。

## 11. B1B-C V2前端切换与Pages部署

Commit 1为`f22a3276be68f138af08a7961c678d458b6bee83`（`security: add V2 payment RPC cutover`），仅包含加法migration、两处payment API名称切换、`v10.5.31`与cache token、报告前半部分。既有8个untracked文件和并发settlement流程文件均未纳入。

Pages run `31318507203`由该commit在`2026-08-09T14:27:54Z`触发，build与deploy均成功，最终完成于`14:29:08Z`。线上四级加载链逐项验证：

- `index.html`加载`js/app.js?v=p1-b1b-payment-rpc-v2-20260809-1`。
- `js/app.js`加载同token的config与payment page。
- `payment-page.js`加载同token的payment API。
- `config.js`显示`v10.5.31`。
- 线上`payment-api.js`只有`school_confirm_payment_request_v2`与`school_reverse_paid_payment_request_v2`两个payment writer字面量，不含旧名称运行时调用或fallback。

代码参数名、数量、类型和错误处理未变。V2历史migration/报告继续保留旧名称作为证据，不属于运行时回退。

### 11.1 V2切换后无副作用页面验收

复用既有active-admin生产session，仅加载和只读查询页面：

- session guard正常，Payment列表显示`v10.5.31`及“旧支付请求只读审计”边界。
- 选择2026-05 cancelled历史范围后读取7条详情入口；首条Payment详情成功加载，页面无可见写按钮。
- 工资、支出、收入、账户及Cash关联页面均成功加载表格和`v10.5.31`。
- 所有页面console error/warn均为0。
- 没有点击确认、撤销、保存、Cash提交或任何writer。

因此B1B-C Gate为`PASS`。新RPC正向生产业务效果没有人为制造测试记录，将由下一次获授权的真实业务操作观察；这不是本阶段的测试授权。

## 12. 业务零变化基线与加法、前端切换后对照

| 对象 | 行数 | MD5 | 前后 |
|---|---:|---|---|
| payment requests | 51 | `6ce63e69…` | 一致 |
| expense records | 47 | `34a7a323…` | 一致 |
| account transactions | 187 | `00516a76…` | 一致 |
| accounts | 3 | `ac9fa3e0…` | 一致；余额合计JPY 1,401,412 |
| income | 55 | `c55f82c7…` | 一致 |
| lessons/settlements/bills/wage locks/details | `744/18/22/103/612` | 五项MD5一致 | 一致 |
| School Cash linkage | 43 | `cd0f5320…` | 一致 |
| Storage | 57 objects / 6,936,405 bytes | `62fac552…` | 一致 |
| Auth | 1 user / deleted 0 / anonymous 0 | last sign-in一致 | 一致 |
| Cash accounts/request/CNY/JPY | `7/43/74/31` | `89b057e2…/f4b1876e…/070c262e…/95ab7cf8…` | 一致 |

payment状态仍为cancelled 7 / void 44；payment最近created/updated时间不变。Gate仍`enabled / blocked / enabled`且三行指纹不变。

## 13. B1B-D旧RPC权限封闭

在B1B-C全部PASS后，重新执行生产`REPEATABLE READ READ ONLY` Gate：

- 四个函数各恰有1个overload，定义MD5、owner、安全属性、参数/default和返回契约无漂移。
- 两个旧RPC仍为authenticated可执行；PUBLIC/anon/service_role不可执行；两个新RPC为authenticated-only。
- 唯一数据库内部调用方分别为对应的一个`_v2` wrapper；V2线上bundle只有新名称；Edge、cron、Webhook没有新增合法旧调用方证据。
- 337个范围外public函数定义+规范ACL聚合指纹为`1a87a3edccf141efe317addc6e54653f`。
- School/Cash/Storage/Auth/Gate关键指纹与加法部署前一致。

closure文件：`sql/current/school_v1_decommission_p1_b1b_payment_rpc_legacy_closure_20260809.sql`。

| 字段 | 结果 |
|---|---|
| SHA-256 | `2a9f0cbb069ec4ddbdaecaee63cfdd41e3e24c65ebccd3b21402df56f0814f4d` |
| 开始/结束UTC | `2026-08-09T14:45:18Z` / `2026-08-09T14:45:34Z` |
| 执行身份 | postgres/session_user postgres |
| 正式执行次数 | 1 |
| 返回 | `BEGIN; SET x2; DO; REVOKE x2; COMMENT x2; DO; NOTIFY; COMMIT` |
| 业务RPC调用 | 0 |
| 业务数据变化 | 0 |
| 事务 | 成功提交 |

migration只对两个精确旧签名从PUBLIC、anon、authenticated、service_role撤销全部函数权限，保留owner；函数对象和函数体不删除、不修改。旧函数comment标记为deprecated owner-only内部实现。新函数ACL、定义和comment不变。PostgREST以既有`NOTIFY pgrst,'reload schema'`刷新cache；没有为“测试schema”发送任何RPC HTTP请求，以免触发writer。

## 14. Postdeploy权限矩阵与负向证据

| RPC | PUBLIC | anon | authenticated | service_role | postgres owner | 生产用途 |
|---|---:|---:|---:|---:|---:|---|
| legacy confirm exact签名 | false | false | false | false | true | `_v2`的owner-only内部实现 |
| legacy reverse exact签名 | false | false | false | false | true | `_v2`的owner-only内部实现 |
| confirm `_v2` exact签名 | false | false | true | false | true | V2 active-admin公开入口 |
| reverse `_v2` exact签名 | false | false | true | false | true | V2 active-admin公开入口 |

`aclexplode`确认四函数均无PUBLIC EXECUTE；`has_function_privilege`确认旧签名对anon/authenticated/service_role均false。每个名称仍只有一个overload，函数definition MD5和返回契约全部保持；两个新wrapper仍先调用active-admin helper再单次委托旧owner实现。默认PUBLIC函数EXECUTE不存在，其他wrapper或overload旁路未发现。

V1静态源码仍调用两个旧名称，因此其原payment调用现在由服务端权限直接拒绝；即使是有效旧admin session，也不能通过V1旧代码直接执行旧签名。由于V1/V2仍共享Auth、公开客户端key和数据库，一个有效active-admin旧session若脱离V1静态代码并主动发现新名称，理论上仍可调用新入口；版本名不是独立安全边界，必须由P1-B2隔离旧session/service worker。

## 15. 非生产closure验证

在本机PostgreSQL 17.10 synthetic数据库验证，未复制生产数据：

| 测试 | 结果 |
|---|---|
| closure完整解析、preflight、REVOKE/comment/postdeploy/COMMIT | PASS |
| 旧RPC direct authenticated | 两个均`permission denied for function` |
| 新RPC ACL | authenticated true；PUBLIC/anon/service_role false |
| 无membership、inactive、operator、read_only | 均`42501` fail closed |
| active admin新confirm→旧core | PASS，仅synthetic支出/流水/余额变化 |
| active admin新reverse→旧core | PASS，synthetic余额恢复、状态一致 |
| 外层ROLLBACK | payment/account/expense/transaction residue均0 |
| REVOKE后强制exception | ACL整体回滚，旧authenticated权限恢复 |
| unexpected legacy overload | DDL前`P1_B1B_UNEXPECTED_PAYMENT_OVERLOAD`，旧ACL不变 |

完整migration本地执行时仅将生产固定的“337个范围外函数/MD5”替换为本地固定的“1个范围外函数/本地MD5”；其余字节路径相同。测试overload已删除，临时实例已正常停止。

## 16. 最终业务零变化证据

closure前后精确一致：

| 对象 | 行数/状态/合计 | 稳定MD5 |
|---|---|---|
| payment requests | 51；cancelled 7/492,012，void 44/2,758,696 | `6ce63e69edfa19a020013634b686f5ce` |
| expense records | 47；cancelled2、paid43、pending1、reversed1 | `34a7a32319d8e538ef7997e1ba59c9d4` |
| income / accounts / account tx | `55/3/187`；JPY余额合计1,401,412 | `c55f82c…/ac9fa3e…/00516a76…` |
| lessons/settlements/bills/wage locks/details | `744/18/22/103/612` | `02b9109c…/481ffa7e…/e50673ac…/ea395407…/1d45d0ce…` |
| School legacy Cash linkage | 0 | `d41d8cd9…` |
| Storage | 57 objects / 6,936,405 bytes | `62fac5521274c58c6f6982a0c690c134` |
| Auth | 1 user / deleted0 / anonymous0；last sign-in不变 | count/time一致 |
| Cash accounts/request/CNY/JPY | `7/43/74/31` | `89b057e2…/f4b1876e…/070c262e…/95ab7cf8…` |
| 337个范围外public函数 | 337 | 定义+ACL `1a87a3edccf141efe317addc6e54653f` |
| Gate | `enabled / blocked / enabled` | `b9ebbce8…/d6e583f3…/a08b9792…` |

没有创建payment request、支出、收入、账户流水或Cash transaction；没有金额、状态、归属、工资、月结、账单、课时、Storage、Auth、Edge、cron、Webhook或Gate变化。唯一生产数据库变化是两个旧函数的ACL/comment及PostgREST cache通知。

## 17. 恢复状态与精确方案

没有执行恢复，也不需要。预案只在有证据证明V2关键阻断由本轮旧ACL封闭直接导致时使用：仅向authenticated恢复两个旧精确签名的EXECUTE并刷新schema cache；不向PUBLIC、anon或service_role授权，不撤销新RPC，不修改业务数据。由于postdeploy、页面和零变化验收均通过，该预案保持未执行。

## 18. 风险重算

总体计数保持：

- `Blocker 4`
- `High 5`
- `Medium 4`
- `Low 2`
- `Unknown 2`

Payment子风险已经关闭：V1静态代码不能再调用两个旧writer。但原“V1仍存在writer”是组合Blocker，Storage旧上传路径仍可写，所以该Blocker尚未消除；另外共享School资源、无法确认最后活动边界、未验证恢复路径三个Blocker不变。旧session仍可能主动调用新RPC，service worker/cache也未隔离。P1-B1B完成不等于V1下线。

## 19. Freeze entry gate与后续授权

Freeze entry gate仍为`FAIL`，本轮不进入Freeze。必须分别授权：

1. `P1-B1C`：只调查并收口V1旧Storage上传入口/policy；30个orphan对象不得顺带删除。
2. `P1-B2`：旧admin session、service worker、cache和残余入口隔离；必须考虑共享Auth/key且不能破坏V2。
3. `P1-C`：正式归档、历史查询验收、隔离恢复演练、最后活动和观察窗口证据。

之后仍需独立授权Preflight/Freeze；不得直接进入Soft shutdown、Supabase项目关闭、密钥撤销或资源删除。

## 20. Git、部署与证据索引

- Commit 1：`f22a3276be68f138af08a7961c678d458b6bee83`；加法migration、V2切换、版本/cache和报告前半。
- Pages：run `31318507203`，success，`2026-08-09T14:27:54Z..14:29:08Z`。
- Commit 2：本报告所在的“旧入口封闭和最终证据”提交；最终hash以Git终态为准。
- 生产migration：加法1次成功；closure 1次成功；业务RPC 0；恢复0。
- catalog证据：`pg_proc/pg_namespace/aclexplode/has_function_privilege/pg_default_acl/pg_get_functiondef/pg_get_function_arguments/pg_get_function_result`及反向调用文本扫描。
- 业务证据：School/Cash/Storage/Auth/Gate与范围外函数count/sum/MD5的前后只读事务对比。
- 页面证据：线上四级bundle、`v10.5.31`、Payment列表/详情、工资/支出/收入/账户/Cash关联、console 0。
- V1证据：`js/modules/payment-management.js:361,427`继续调用旧名称；因此服务端撤权使这两个静态调用失效。
- V2证据：`js/api/payment-api.js:98,164`只调用`_v2`，无旧fallback。
- 并发工作树：settlement Edge文件在B1B-D前由其他流程出现，随后形成独立提交`008dfe2…`；与Payment无引用/文件重叠。Commit 2基于该最新HEAD形成，但不包含其7个文件，也不回退或覆盖。

P1-B1B到此完整完成，立即停止；不得继续P1-B1C、P1-B2、P1-C、Freeze、Soft shutdown或V1停服。
