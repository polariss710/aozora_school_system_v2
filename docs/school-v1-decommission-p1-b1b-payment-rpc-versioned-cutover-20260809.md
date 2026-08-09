# School V1 下线 P1-B1B：Payment RPC版本化迁移与旧入口封闭

- 日期：2026-08-09（Asia/Tokyo）
- 当前阶段：B1B-B新RPC加法部署已完成；B1B-C前端切换待Pages验证
- 当前安全状态：旧RPC仍服务authenticated，新RPC已安全可用；尚未撤销旧入口
- V1基线：`main/e316598dafbe4d7f50a88c70e8bc488d792a2d49`
- V2起始基线：`main/43764200e56e326e7c120c255b1426455ace8471`
- 并发流程吸收后的V2基线：`main/6951c2fe8429ed9312c1f4d1af3e24aade488c3f`

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

调查开始时V1为`e316598d…`且仅保留用户既有`M .gitignore`。V2最初为P1-B1A-R1提交`4376420…`，随后另一个已获授权流程在本地推进settlement SQL并最终推送到`6951c2f…`；其文件与payment范围不重叠。本阶段没有回退、覆盖或提前推送对方提交，并在最新HEAD重新完成payment调用定位。

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
| 执行文件SHA-256 | `84b04fded4f0b7bf6b4d5f60499b7838b66934ad89ff6202aab7e2dab9a6d696` |
| 开始/结束UTC | `2026-08-09T14:23:31Z` / `2026-08-09T14:23:41Z` |
| 执行身份 | postgres/session_user postgres |
| 返回 | `BEGIN; DO; CREATE FUNCTION x2; ALTER x2; REVOKE/GRANT x2; COMMENT x2; DO; NOTIFY; COMMIT` |
| 事务 | 成功提交 |
| 业务RPC调用 | 0 |
| 业务数据变化 | 0 |
| 旧RPC权限 | 保持authenticated，未提前封闭 |

加法部署后新函数definition MD5为confirm `af6f0a1abd5a3090351c6eed785ef2f5`、reverse `002a27499d63e31f82b104065944ba5e`。参数、返回、安全属性、ACL和委托关系全部通过online catalog验收。

## 11. B1B-C V2前端切换（待完成）

计划diff仅包含：payment API两处RPC名称切换；`APP_VERSION`到`v10.5.31`；index/app/payment模块cache token更新。页面字段、参数、流程、金额、状态和错误处理不变；无旧RPC fallback。

只有Commit 1推送、Pages成功、生产线上bundle只包含新运行时名称且payment相关页面无错误后，才进入旧RPC封闭。

## 12. 业务零变化基线与加法部署后对照

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

## 13. 后续阶段Gate

- B1B-C：待Commit 1、Pages和线上bundle/UI验证。
- B1B-D：仅在B1B-C全部PASS后执行精确旧签名REVOKE。
- B1B-E：待最终权限、零业务变化、Git和风险验收。

当前不得撤销旧RPC，不得开始P1-B1C、P1-B2、P1-C或Freeze。
