# School V1 下线 P1-B1A：表级 writer 旁路封闭实施报告

- 日期：2026-08-09（Asia/Tokyo）
- 结论：**首次执行安全失败并整体回滚；P1-B1A-R1 修正版在唯一一次正式重试中成功提交，表级 writer 旁路已封闭**
- 停止状态：**P1-B1A-R1 COMPLETE；Freeze entry gate 仍为 FAIL，等待后续逐阶段独立授权**
- V1基线：`main` / `e316598dafbe4d7f50a88c70e8bc488d792a2d49`
- V2基线：`main` / `083e91957dc18392a30b7b7533c4516ce7adab4d`

## 1. 执行摘要

1. 首次执行的PL/pgSQL解析错误发生在事务内第一段`DO`块；任何权限DDL前即失败，事务整体回滚，生产数据和对象均零变化。
2. 经P1-B1A-R1独立授权，修正了`CASE ... END THEN`解析歧义，并把ACL比较改为排序后的`aclexplode`规范指纹；没有删除、降级或绕过fail-closed断言。
3. 修正版先在全新本地PostgreSQL 17.10最小环境中完成成功路径、policy漂移、NULL ACL、ACL顺序和中途异常回滚测试，未复制生产数据。
4. 正式重试前重新确认线上ACL/RLS/policy、trigger、依赖、V1/V2调用路径及业务基线均与migration预期一致，全部准入Gate通过。
5. 修正版migration SHA-256为`ceb94b1ca6e49510ba5d8773a4ff5f7d94d7dc00921bafb3d308346dc123243f`；于`2026-08-09T13:38:06Z`至`13:38:22Z`由`postgres`执行一次，返回`COMMIT`。
6. 四表对PUBLIC/anon/authenticated的直接`INSERT/UPDATE/DELETE/TRUNCATE`均已封闭；SELECT保持，service_role保持原权限，最终仅有四条SELECT policy。
7. 四表及School/Cash/Storage/Auth/Gate的前后行数、金额、时间和稳定指纹一致；V2生产页面只读加载及控制台回归通过。没有紧急恢复。

## 2. 授权边界与实际动作

### 2.1 已执行

- V1/V2 Git与源代码只读检查。
- School/Cash生产库显式只读事务中的catalog与脱敏aggregate查询。
- 新增P1-B1A migration草案和本报告。
- 正式执行migration文件一次；文件在原子事务preflight解析阶段失败并回滚。
- 回滚后的ACL/RLS、业务零变化和角色读取复核。

### 2.2 未执行

- 业务表DML、业务RPC调用和测试数据生成：0。
- payment RPC、Storage、Auth/session、Edge、cron、Webhook、Realtime、Vault、Gate变化：0。
- V1/V2页面、service worker、Pages、DNS变化：0。
- 紧急恢复：0；没有持久权限变化需要恢复。
- stage、commit、push、deploy：0。

## 3. 工作区与版本基线

| 项目 | branch / HEAD | remote同步 | 调查开始工作树 |
|---|---|---|---|
| V1 | `main` / `e316598d…` | `HEAD...origin/main = 0/0` | 既有` M .gitignore`，本轮未触碰 |
| V2 | `main` / `083e9195…` | `HEAD...origin/main = 0/0` | 上一轮两份报告、CSV/TXT和4个SQL fragment均为既有untracked |

本轮新增：

- `sql/current/school_v1_decommission_p1_b1a_table_writer_closure_20260809.sql`
- `docs/school-v1-decommission-p1-b1a-table-writer-closure-20260809.md`

未修改`docs/current-status.md`：本阶段没有成功的生产状态可写入权威状态页。

## 4. Business-model expansion declaration

| 项目 | 声明 |
|---|---|
| 新表、列、状态、日期/月、身份、来源、快照、可写事实 | none |
| 字段语义、字段可变性、锁定规则 | unchanged |
| 新权威来源、fallback、dual-read/dual-write | none |
| 历史重解释、破坏性结构变化 | none |
| writer authority | 计划仅撤销四表PUBLIC/anon/authenticated直接DML；RPC/Edge/service_role/owner不变 |
| 批准依据 | 本轮P1-B1A第一、六、九节的逐表逐角色授权 |

## 5. 四表Preflight证据

### 5.1 对象与ACL

四表均为`public`普通表、owner=`postgres`、`relkind=r`、RLS enabled、FORCE RLS=false。

四表部署前ACL完全相同：postgres、anon、authenticated、service_role均有完整表权限；ACL MD5均为`46875263bd6598c4534e2df7d1847a5e`。PUBLIC没有显式表ACL，但anon/authenticated各自的显式grant使直接DML有效。

| 表 | anon I/U/D/T | authenticated I/U/D/T | service_role I/U/D/T | SELECT |
|---|---:|---:|---:|---:|
| `school_income_records` | 全true | 全true | 全true | 三角色true |
| `school_subjects` | 全true | 全true | 全true | 三角色true |
| `school_teachers` | 全true | 全true | 全true | 三角色true |
| `school_settings` | 全true | 全true | 全true | 三角色true |

角色继承目录仅显示`authenticator`和`postgres`是上述API roles的member；未发现anon/authenticated通过其他业务角色继承额外DML。

### 5.2 RLS policy

| 表 | 部署前policy | cmd / role / 条件 | 指纹 |
|---|---|---|---|
| income | `school_select_operational_income_records` | SELECT / public / 排除隔离、operational excluded | `3c03f656…`（与其余3条合并指纹） |
| income | `school_insert_non_tuition_income_records` | INSERT / public / 非隔离、非tuition | 同上 |
| income | `school_update_non_tuition_income_records` | UPDATE / public / 非隔离、非tuition | 同上 |
| income | `school_delete_non_tuition_income_records` | DELETE / public / 非隔离、非tuition | 同上 |
| settings | `school_allow_all_settings` | ALL / public / true | `37017143…` |
| subjects | `school_allow_all_subjects` | ALL / public / true | `2d4df94b…` |
| teachers | `school_allow_all_teachers` | ALL / public / true | `9f288113…` |

所有policy均PERMISSIVE。没有restrictive policy抵消这些旁路。

### 5.3 Trigger

| 表 | trigger |
|---|---|
| income | historical-confirmed guard、incident immutable guard、tuition mutation guard、deferred bill consistency、updated_at |
| settings | updated_at |
| subjects | updated_at |
| teachers | updated_at |

5个相关trigger function均不含`INSERT INTO`、表级`UPDATE ... SET`、`DELETE FROM`或`TRUNCATE`语句；本阶段权限变化不会触发这些trigger。

Trigger定义指纹：income `4431041d…`、settings `669100c4…`、subjects `126b8c9c…`、teachers `26cc506f…`。

### 5.4 外键、view与函数依赖

- income关联account、business entity、student、student payment、tuition bill、reversal transaction及自身canonical income链。
- subjects/teachers被lesson、actual lesson、expense、wage rule/lock和其他历史业务对象引用；权限收口不修改外键或引用数据。
- 依赖income的两个可更新view：`school_incident_income_records`和`school_operational_income_records`均只有SELECT权限，没有anon/authenticated DML grant。
- `school_v_business_month_summary`与`school_v_teacher_salary_month_summary`虽然保留历史宽ACL，但catalog确认均不可更新，不能形成底表DML旁路。
- online catalog识别24个写目标表的函数：income 16、subjects 3、teachers 5、settings 0；24个全部为`SECURITY DEFINER`，没有invoker writer依赖调用者表DML。

## 6. V1/V2/Edge依赖分析

### 6.1 V1

- `js/legacy-core.js:98,101,103`映射subjects、teachers、income。
- `legacy-core.js:1624,1626,1685,1807`及`modules/table-selection.js:173`可发出四表中的9种表级DML请求。
- `legacy-core.js:134`对settings仅SELECT。
- V1没有调用V2的income/profile正式writer RPC。

### 6.2 V2 current HEAD

- income正式读取使用`school_operational_income_records`；创建、编辑、取消、反转通过API层RPC。
- subject/teacher API直接表调用均为SELECT；创建和编辑通过API层RPC。
- JS/TS扫描未发现对四个literal目标表的`.insert/.update/.delete/.upsert`链。
- 目标表writer函数全部`SECURITY DEFINER`，撤销caller表DML不会影响函数内部owner写入。

### 6.3 Edge与service_role

- `request-cash-income-confirmation`使用School service-role读取income，并通过正式RPC推进School/Cash链；没有直接target-table DML。
- 其他相关Edge调用正式RPC或只读引用。
- 本阶段按最小风险原则计划保留service_role全部现状，不修改Edge和任何函数ACL/定义。

## 7. 硬停条件检查

部署前业务硬停条件均未触发：

- V2不依赖authenticated直接表DML。
- Edge/RPC不依赖调用者表权限。
- 不需要新建/重写业务writer。
- 不需要修改payment RPC、Storage、Auth、Edge或客户端key。
- 线上ACL/RLS可确认。
- 本轮migration可与既有untracked文件区分。
- 没有需要扩大的目标外旁路修复。

正式执行阶段触发新的失败硬停：migration SQL语法解析失败。按第十一节要求停止，不允许本轮第二次执行。

## 8. Migration内容与静态审查

文件：`sql/current/school_v1_decommission_p1_b1a_table_writer_closure_20260809.sql`

计划动作：

1. 校验四表对象、owner、RLS、ACL、policy指纹、updatable view和invoker writer。
2. 对四表向PUBLIC、anon、authenticated撤销`INSERT/UPDATE/DELETE/TRUNCATE`。
3. 删除income三条DML policy。
4. 将settings/subjects/teachers的ALL policy替换为PUBLIC SELECT-only policy。
5. 保留income operational SELECT policy、原SELECT grants、service_role与所有RPC/trigger/function定义。
6. 在同一事务中断言anon/authenticated DML全false、PUBLIC无显式DML、四表仅剩四条SELECT policy。

静态结果：

- `git diff --no-index --check`：PASS。
- 业务DML语句扫描：PASS；无`INSERT INTO/UPDATE ... SET/DELETE FROM/TRUNCATE TABLE`。
- payment/Storage/Auth/Edge/Gate范围扫描：PASS。
- 疑似secret扫描：PASS。
- 目标DDL列表：4表DML REVOKE、6个旧policy DROP、3个SELECT policy CREATE、3个policy COMMENT。

静态审查未捕获PL/pgSQL `IF`中的`CASE`解析歧义，这是本次失败原因候选；必须在另行授权的重试前修正并增加可解析性检查。

## 9. 首次尝试部署记录

| 字段 | 结果 |
|---|---|
| 开始UTC | `2026-08-09T13:03:12Z` |
| 结束UTC | `2026-08-09T13:03:40Z` |
| 执行身份 | `postgres` / session_user `postgres` |
| 执行文件 | 本报告§8所列migration |
| 调用次数 | 1 |
| 返回 | `BEGIN`后在文件第133行preflight `DO`块报syntax error |
| 失败位置 | `v_actual_policy_count <> case when ... end then` |
| 权限DDL到达情况 | 未到达任何REVOKE/DROP/CREATE POLICY |
| 事务结果 | 连接结束，整体回滚 |

没有第二次migration执行。

## 10. 首次尝试回滚后ACL/RLS验收

回滚后四表ACL MD5仍全部为`46875263bd6598c4534e2df7d1847a5e`；policy数量和指纹与部署前完全一致：

| 表 | policy数 | 部署前 | 回滚后 |
|---|---:|---|---|
| income | 4 | `3c03f656…` | `3c03f656…` |
| settings | 1 | `37017143…` | `37017143…` |
| subjects | 1 | `2d4df94b…` | `2d4df94b…` |
| teachers | 1 | `9f288113…` | `9f288113…` |

因此P1-B1A的目标权限变化没有生效。anon/authenticated对四表的INSERT/UPDATE/DELETE/TRUNCATE仍为true。

## 11. 首次尝试业务零变化验收

### 11.1 四表

| 对象 | 行数 | max updated UTC | 业务合计/指纹 | 前后 |
|---|---:|---|---|---|
| income | 55 | `2026-08-07 00:14:12.853428` | amount `9704226.00`；JPY `9667830.00`；CNY `36396.00`；MD5 `c55f82c…` | 一致 |
| subjects | 12 | `2026-06-12 04:56:40.917518` | MD5 `b02dc737…` | 一致 |
| teachers | 9 | `2026-07-14 04:41:52.932165` | MD5 `74b7e046…` | 一致 |
| settings | 4 | `2026-05-17 06:48:19.596049` | MD5 `4948a5be…` | 一致 |

### 11.2 关联链

- School accounts：3行、余额合计JPY `1401412.00`、MD5 `ac9fa3e0…`，一致。
- School Cash linkage：43行、MD5 `cd0f5320…`，一致。
- lesson/settlement/tuition bill/wage lock/wage detail/payment request/account transaction：`744/18/22/103/612/51/187`，一致。
- Gate：`enabled / blocked / enabled`及三行MD5一致。
- Storage：57 objects、6,936,405 bytes、catalog MD5 `641ce912…`，一致。
- School Auth：1 user、deleted 0、anonymous 0、last sign-in不变。
- Cash：accounts 7、external requests 43、CNY transactions 74、JPY transactions 31；四个rowset MD5均一致。

没有业务数据写入、sequence测试、Webhook调用或外部副作用。

## 12. 首次尝试V2只读回归

由于没有持久部署，不声称完成“postdeploy UI回归”。回滚后以只读角色模拟确认：

| role | income可见 | subjects | teachers | settings |
|---|---:|---:|---:|---:|
| anon | 54 operational | 12 | 9 | 4 |
| authenticated | 54 operational | 12 | 9 | 4 |

V2源代码、Pages和session均未修改；没有新增页面权限错误的生产变更来源。

## 13. 首次尝试失败与恢复状态

- 失败类型：SQL syntax error，发生在事务内第一段preflight解析。
- 部分状态：无。权限DDL未开始，回滚后catalog指纹与部署前一致。
- 紧急恢复：未执行，也不需要。
- 未实施第二套临时修复。
- 下一次尝试必须作为新的单次生产deployment授权；不得把本次已消费的“一次”授权解释为可自动重试。

## 14. 首次尝试风险重算

由于权限收口没有生效，风险数量保持：

- `Blocker 4`
- `High 5`
- `Medium 4`
- `Low 2`
- `Unknown 2`

三张V1表的9种DML请求仍可能成功；settings anon DML残余仍存在。payment RPC和Storage上传路径按范围要求完全未处理。

## 15. 首次尝试Freeze entry gate

结论仍为`FAIL`：

- 四表直接DML旁路未关闭。
- 两个旧payment writer RPC仍待P1-B1B。
- Storage旧上传路径仍待P1-B1C。
- session/service-worker隔离、最后活动边界和可验证恢复路径仍未关闭。

不得进入Freeze或Soft shutdown。

## 16. 首次尝试下一阶段建议

只建议批准一个新的“P1-B1A migration修正与单次重试”阶段：

1. 修正preflight `CASE`表达式的PL/pgSQL语法歧义。
2. 在不连接生产写路径的条件下增加SQL parse/transaction rollback rehearsal；若该rehearsal也需生产执行，必须在新授权中明确。
3. 重新核对最新HEAD、工作树和在线ACL/RLS指纹。
4. 静态与回滚审查通过后，单次正式执行修正版migration。
5. 完整postdeploy ACL/RLS、业务零变化和V2只读回归后，才允许commit/push。

该建议不授权P1-B1B、P1-B1C、P1-B2、归档、恢复、Freeze或Soft shutdown。

## 17. 首次尝试Git与证据索引

- 实际执行SQL文件：`sql/current/school_v1_decommission_p1_b1a_table_writer_closure_20260809.sql`，1次，失败并整体回滚。
- 业务RPC调用：0。
- 数据库持久写入：0。
- 测试白名单写入/测试记录ID：不适用/无。
- commit/push/deploy：0。
- Preflight证据：`pg_class/pg_namespace/aclexplode/has_table_privilege/pg_auth_members/pg_policies/pg_trigger/pg_proc/pg_constraint/information_schema.views`。
- 零变化证据：四表、account、Cash linkage、核心业务计数、Gate、Storage、Auth及Cash四表的count/sum/MD5只读对比。

## 18. 停止点（首次尝试）

首次P1-B1A在失败回滚与报告后按原授权停止；没有现场修补或第二次执行。其后仅依据新的P1-B1A-R1授权完成下述修正与单次重试。

## 19. P1-B1A-R1：修正Migration并单次重试

### 19.1 上一次安全失败与根因

原语句位于preflight policy指纹断言：

```sql
or v_actual_policy_count <> case when v_table='school_income_records' then 4 else 1 end then
```

这里的`CASE`意图作为返回期望policy数量的SQL表达式，而不是PL/pgSQL控制语句。它直接嵌入外层`IF ... THEN`后形成连续的`END THEN`，PL/pgSQL解析器无法将该`END`可靠地归属于CASE表达式并闭合外层IF，最终在`$preflight$`块结束处报syntax error。修正前的真实安全不变量是：income必须恰有4条预期policy，其余三表必须各恰有1条，且policy定义指纹必须完全一致；任何偏差都必须抛异常并在权限DDL前回滚。

修正后先用普通PL/pgSQL `IF/ELSE/END IF`赋值`v_expected_policy_count`，再比较：

```sql
if v_table='school_income_records' then
  v_expected_policy_count:=4;
else
  v_expected_policy_count:=1;
end if;

if v_actual_policy_md5 is distinct from v_expected_policy_md5
   or v_actual_policy_count <> v_expected_policy_count then
  raise exception 'P1_B1A_POLICY_DRIFT: %',v_table;
end if;
```

判断语义未变，错误分支仍为exception。ACL断言同时由依赖`relacl::text`元素顺序的原始MD5，改为对`aclexplode`结果按grantee、privilege、grantable排序后计算规范MD5，并断言恰有32个ACL item。生产前规范指纹为`916c9ecaffa9dda176f71280173b43bd`。该修改消除ACL数组排列差异导致的误报，同时以item计数和NULL-safe `coalesce(...,acldefault(...))`保持fail-closed；不是弱化权限检查。

### 19.2 修正版范围与静态检查

- 保持`ON_ERROR_STOP`、单一`BEGIN`/`COMMIT`和两个完整DO块；异常不被捕获或降级。
- 目标仍仅为四张既有表的ACL，以及六条旧DML/ALL policy被删除、三条SELECT-only policy被建立；income既有operational SELECT policy保留。
- 没有业务DML、表结构、trigger、function、role、Gate、payment RPC、Storage、Auth或Edge变更。
- schema均显式为`public`；动态表权限检查使用`format('%I.%I',...)`限定identifier。
- `IF/THEN/END IF`、美元引用、括号、分号、引号、array、NULL路径和事务边界静态检查通过。
- `git diff --no-index --check`、业务DML扫描、范围外对象扫描、V2目标表直接DML扫描和疑似secret扫描均通过。

### 19.3 非生产PostgreSQL验证

使用全新本地PostgreSQL 17.10临时cluster和空模拟表/role/policy；没有复制生产业务数据。结果：

| 测试 | 结果 | 安全含义 |
|---|---|---|
| 满足preflight的完整migration | PASS，完整到达`COMMIT` | 解析、控制流与权限DDL路径正确 |
| subjects policy定义漂移 | `P1_B1A_POLICY_DRIFT`，事务失败 | policy漂移fail closed，原DML仍在 |
| settings `relacl IS NULL` | `P1_B1A_TABLE_STATE_OR_ACL_DRIFT` | NULL不会使断言意外通过 |
| 同语义ACL反向grant顺序 | PASS并`COMMIT` | 规范ACL比较不依赖数组顺序 |
| REVOKE后强制中途exception | 事务失败，权限恢复 | 任一中途异常整体回滚 |

临时实例随后正常停止。测试仅产生本机临时对象，无生产数据。

### 19.4 正式重试前线上Preflight与准入Gate

V1仍为`main/e316598dafbe4d7f50a88c70e8bc488d792a2d49`，V2仍为`main/083e91957dc18392a30b7b7533c4516ce7adab4d`，两者与各自`origin/main`均为0/0。V1既有`.gitignore`修改、V2既有untracked报告和6个CSV/TXT/SQL文件保持隔离。

四表均存在于`public`，owner=`postgres`、`relkind=r`、RLS enabled、FORCE RLS=false；规范ACL指纹均为`916c9eca…`/32 items，anon/authenticated/service_role在部署前均有SELECT和I/U/D/T。policy定义与首次失败前完全一致：income 4条、其余各1条；trigger数量/指纹为income `5/4431041d…`、settings `1/669100c4…`、subjects `1/126b8c9c…`、teachers `1/26cc506f…`。

V2当前HEAD仍未发现四目标表的`.insert/.update/.delete/.upsert`直接调用；24个相关数据库writer均为`SECURITY DEFINER`，Edge使用service_role读取并调用正式RPC。两个依赖income的可更新view对anon/authenticated无DML；两个历史宽ACL summary view均不可更新。service_role保留完整权限。因此不会撤销V2调用者所需的直接表权限。

非生产解析、静态/secret/业务DML/范围检查、线上catalog、V2依赖、service_role、回滚定义和工作树隔离全部PASS；没有新硬停条件，正式重试Gate为PASS。

### 19.5 唯一一次正式生产重试

| 字段 | 结果 |
|---|---|
| 文件 | `sql/current/school_v1_decommission_p1_b1a_table_writer_closure_20260809.sql` |
| SHA-256 | `ceb94b1ca6e49510ba5d8773a4ff5f7d94d7dc00921bafb3d308346dc123243f` |
| 开始/结束UTC | `2026-08-09T13:38:06Z` / `2026-08-09T13:38:22Z` |
| 执行身份 | `postgres` / session_user `postgres` |
| 本轮正式重试次数 | 1 |
| 数据库返回 | `BEGIN`、preflight `DO`、`REVOKE`、6次`DROP POLICY`、3次`CREATE POLICY`、3次`COMMENT`、postdeploy `DO`、`COMMIT` |
| 事务 | 成功提交 |
| 异常 | 无 |
| 紧急恢复 | 未执行；不需要 |

### 19.6 Postdeploy ACL/RLS验收

| 表 | anon I/U/D/T | authenticated I/U/D/T | anon/auth SELECT | service_role I/U/D/T/SELECT | 最终policy |
|---|---|---|---|---|---|
| income | 全false | 全false | true/true | 全true | existing operational SELECT |
| settings | 全false | 全false | true/true | 全true | `school_settings_public_select` |
| subjects | 全false | 全false | true/true | 全true | `school_subjects_public_select` |
| teachers | 全false | 全false | true/true | 全true | `school_teachers_public_select` |

PUBLIC没有I/U/D/T ACL item；anon/authenticated仅保留MAINTAIN、REFERENCES、SELECT、TRIGGER，不存在角色继承取得的等效DML。最终四表仅有4条SELECT policy，全部旧DML/ALL policy已消失。owner、relkind、RLS/FORCE、trigger数量与定义指纹不变；依赖income的可更新view对anon/authenticated的I/U/D仍全false，两个summary view仍不可更新。

因此V1对income、subjects、teachers各自insert/update/delete的9种请求均不再具有服务端表权限；settings的anon直接DML残余也已封闭。该结论来自catalog和有效权限计算，没有发送测试写请求。

### 19.7 业务零变化验收

部署前后精确一致：

| 对象 | 行数/合计 | 稳定指纹 |
|---|---|---|
| income | 55；amount `9704226.00`；JPY `9667830.00`；CNY `36396.00` | `c55f82c7d62dbe92d0b49714a911a234` |
| subjects / teachers / settings | 12 / 9 / 4 | `b02dc737…` / `74b7e046…` / `4948a5be…` |
| School accounts | 3；余额合计JPY `1401412.00` | `ac9fa3e0…` |
| School Cash linkage | 43 | `cd0f5320…` |
| lesson/settlement/bill/wage lock/wage detail/payment/account tx | `744/18/22/103/612/51/187` | 前后一致 |
| Storage | 57 objects；6,936,405 bytes | `641ce912…` |
| Auth | 1 user；deleted 0；anonymous 0 | last sign-in不变 |
| Cash accounts/request/CNY tx/JPY tx | `7/43/74/31` | `89b057e2…/f4b1876e…/070c262e…/95ab7cf8…` |

四表max created/updated、关键状态分布、Gate `enabled / blocked / enabled`及其指纹亦完全一致。没有并发业务变化需要归因；生产业务数据变化为0。

### 19.8 V2无写回归

复用现有active-admin生产session，仅加载页面、未点击writer：

- session guard正常；生产版本仍为`v10.5.30`。
- income 2026-08列表读取12条；subjects读取12条；teachers读取9名；account读取3条。
- payment detail无ID时按设计显示只读提示；没有调用payment writer。
- V2没有独立settings页面；anon/authenticated对settings的SELECT由生产有效权限和4行只读结果确认。
- 上述income、subject、teacher、account、payment页面的console error/warn均为0，未见新增权限错误。
- 当前正式writer仅验证其无副作用preflight/读取依赖；正向业务写入留给下一次真实业务操作观察，未制造测试记录。

### 19.9 风险重算、Freeze Gate与下一阶段

风险数量保持`Blocker 4 / High 5 / Medium 4 / Low 2 / Unknown 2`。原因是B2“仍存在旧writer”是组合阻断：本阶段已关闭四表直接DML部分，但两个旧payment writer RPC和Storage上传路径仍在；共享School资源、最后活动边界和可验证恢复准备度三个Blocker也均未关闭。P1-B1A成功不应虚假减少整体风险计数。

Freeze entry gate仍为`FAIL`。剩余事项必须分别授权：

1. `P1-B1B`：两个payment writer RPC的兼容迁移与封闭。
2. `P1-B1C`：Storage旧上传路径和policy的独立收口；30个orphan只调查/保留，不在该授权中顺带删除。
3. `P1-B2`：旧admin session与service-worker/cache隔离。
4. `P1-C`：正式归档、隔离恢复验证、最后活动/观察窗口和历史查询验收。

在这些证据和权限面完成前，不得Freeze、Soft shutdown或处理共享Supabase项目/密钥。

### 19.10 Git与证据索引

- 生产变更仅为本migration列明的四表ACL、6个旧policy删除、3个SELECT policy建立及3条policy comment。
- 生产migration：R1正式重试1次，成功；业务RPC 0；测试DML 0；测试记录 0；紧急恢复 0。
- catalog证据：`pg_class/pg_namespace/aclexplode/has_table_privilege/pg_auth_members/pg_policies/pg_trigger/pg_proc/information_schema.views`。
- 业务零变化证据：四表、账户、Cash linkage、课时/月结/账单/工资/支付/流水、Gate、Storage、Auth和Cash库的只读count/sum/max/MD5前后对比。
- 页面证据：生产`v10.5.30`的income/subject/teacher/account/payment只读加载及console error/warn 0。
- 本轮仅允许stage本migration、本报告和必要的`docs/current-status.md`；其余既有工作区文件继续排除。

P1-B1A-R1在完成报告、单一职责commit、push及其自动Pages run记录后立即停止。
