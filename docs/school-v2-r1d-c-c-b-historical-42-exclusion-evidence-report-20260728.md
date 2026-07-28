# School V2 学费链P0：R1D-C-C-B 固定42-ID历史已收费不可变排除证据实施报告

- 实施日期：2026-07-28
- Git基线：`4f1838d62ed2d184363d587da9a9951691cdd234`（实施前HEAD与`origin/main`一致）
- School部署前只读事务：`2026-07-28 09:03:02.267659+00`
- School正式部署前只读事务：`2026-07-28 09:18:52.267464+00`
- 迁移审计执行时间：`2026-07-28 09:18:53.91212+00`
- School postdeploy只读事务：`2026-07-28 09:19:03.314931+00`
- Cash部署前/后只读事务：`2026-07-28 09:03:18.258432+00` / `2026-07-28 09:19:11.436318+00`；双库不是原子快照
- 正式永久DDL：1表、3函数、3 trigger、2 index、约束/注释/权限
- 正式业务证据DML：新证据表精确`INSERT 42`；既有业务表DML为0
- Cash DDL/DML：`0 / 0`
- RPC调用：0；SQL中仅以SELECT直接读取既有只读函数
- R0：`validation_preview_only / blocked / blocked`
- 结论：固定Manifest B的42个UUID已固化为独立、append-only、数据库不可更新/删除/截断的历史已收费排除证据；candidate函数和候选结果仍未切换。

## 1. 授权范围与设计选择

本阶段严格承接R1D-C-C-A的业务批准：陈加恩、陈红卓2026-05/06四笔JPY204,000收入分别是对应月份全部planned课程的学费，固定Manifest B的42个UUID属于该历史已收费范围，未来candidate应排除。批准只覆盖这42个UUID，不按学生、月份、业务归属或实时查询动态扩展。

没有使用`school_student_tuition_billing_identities`或`school_student_tuition_bill_lessons`，因为42条没有历史tuition bill、bill JSON或lesson级canonical快照；把月度收款补造成canonical账单关系会伪造历史。没有复用`school_tuition_billing_attribution_override_audit`，因为该表用于未来收费月/周override请求审计，不能表达“历史已收费、应排除候选”的独立永久事实。本阶段也没有补造bill、identity、relation、月结lesson snapshot或回填lesson新归属字段。

新增表为`public.school_student_tuition_historical_lesson_exclusions`。每行保存：

- planned lesson、student、business entity及settlement month快照；
- lesson old31 hash、唯一linked actual、locked settlement、received tuition income、School账户流水及evidence hash；
- 受控reason/class/source/report/manifest版本；
- 人类可读批准说明、证据登记人、证据登记时间及created_at。

机器判断使用固定code/version，不依赖人类自由文本。planned/actual/settlement/income/account引用均为非NULL、`ON DELETE RESTRICT`外键；planned和actual分别唯一。month及两个MD5字段有格式约束，受控code/version只能取本阶段固定值。

## 2. 固定Manifest与逐条证据

数据库函数`school_r1d_c_c_b_fixed_42_manifest()`内嵌R1D-C-C-A已提交Manifest B的显式42行VALUES。每行冻结planned UUID、old31 hash、student、business entity、year_month、actual、settlement、income、account transaction和evidence hash；动态查询只用于逐行fail-closed核验，不用于选择或扩大INSERT对象。

| 学生/月 | 行 | 小时 | JPY |
|---|---:|---:|---:|
| 陈加恩 2026-05 | 10 | 20 | 170,000 |
| 陈红卓 2026-05 | 10 | 20 | 170,000 |
| 陈加恩 2026-06 | 12 | 24 | 204,000 |
| 陈红卓 2026-06 | 10 | 20 | 170,000 |
| 合计 | 42 | 84 | 714,000 |

- old31 aggregate hash：`dc6cd4ad206cc09ed5c02dfe6da5462b`
- evidence aggregate hash：`dc2546bff536942650db58e437d37f0e`
- 42/42为School planned，仍无canonical/incident/legacy bill relation，R1D-B六个新日期/归属字段仍NULL；
- 42/42各有且只有一个审计匹配actual，41个`completed`、1个`makeup_completed`；
- settlement、received tuition income和School账户流水引用逐条匹配，四组月度planned及income均为JPY204,000；
- 写入前新证据表不存在，已有排除证据为0。

## 3. 6条pending_makeup继续排除

R1D-C-C-A确认的6条`pending_makeup`不在固定Manifest中，postdeploy再次断言交集为0、当前范围计数仍为6：

- `9085ab09-a719-42b7-a517-2700b8d9ddb0`
- `e5eb7a47-13ea-4858-b73a-ddf5cc38c0f7`
- `2b49f20c-4c94-4129-abca-bd12a75c5026`
- `44ddcda2-dbdd-48c2-8d0a-ba59a5e65a90`
- `4da7e3e9-d36c-4102-b582-c67b281b5b69`
- `98a0f192-6e6f-4f6a-9cfc-bd2570d308fd`

回滚负向测试还以其中一条显式尝试插入并被固定Manifest guard拒绝。正式部署没有处理、修改或为这6条建立证据。

## 4. 时间语义

四笔历史学费的income date分别为2026-05-18及2026-06-01；这是历史月度收费/收款证据。业务批准事实来自R1D-C-C-A报告与固定Manifest的后续明确批准，但没有伪造逐课历史批准时间。

`evidence_recorded_at = 2026-07-28 09:18:53.91212+00`只表示业务批准之后，本次受控事务把42条证据登记进数据库的时间；它不是2026-05/06原始收费发生时间，也不是逐lesson收费决定时间。`created_at`同样是数据库证据行创建时间。

## 5. 权限与不可变保护

| 角色 | SELECT | INSERT | UPDATE | DELETE/TRUNCATE |
|---|---|---|---|---|
| anon | 否 | 否 | 否 | 否 |
| authenticated | 否 | 否 | 否 | 否 |
| service_role | 是 | 否 | 否 | 否 |

正式42行由受控部署事务写入；未建立页面、API、RPC或service-role通用写入口。函数权限全部先`REVOKE ALL FROM PUBLIC`。数据库保护包括：

- `BEFORE INSERT`逐行对固定42 manifest全部指纹字段做精确匹配；
- `BEFORE UPDATE OR DELETE` row trigger无条件拒绝，覆盖OLD/NEW目标转移；
- `BEFORE TRUNCATE` statement trigger无条件拒绝；
- planned lesson及linked actual唯一约束，防止重复或一证据多lesson；
- 外键`ON DELETE RESTRICT`，不允许lesson或证据引用被级联清除。

postdeploy确认3个自定义trigger均为enabled，角色权限只有`service_role SELECT`。

## 6. ROLLBACK演练

正式部署前执行`school_tuition_r1d_c_c_b_historical_42_exclusion_rollback_tests.sql`。它以`r1d_c_c_b_commit=0`调用与正式部署完全相同的schema/backfill SQL，在单一事务内创建对象并成功插入固定42，然后执行11项负向测试：

1. 非固定reason拒绝；
2. 非固定evidence class拒绝；
3. 非固定approval source拒绝；
4. 关键证据引用NULL拒绝；
5. 第43个未批准planned UUID拒绝；
6. pending_makeup UUID拒绝；
7. UPDATE拒绝；
8. 修改planned lesson ID拒绝；
9. DELETE拒绝；
10. TRUNCATE拒绝；
11. 重复lesson插入拒绝。

权限断言同时确认anon/authenticated/service_role均无写权限，candidate函数定义未变化。所有负向测试均按预期拒绝，42行内容及现有School业务fingerprint不变。最终ROLLBACK后，新表、3个public函数、trigger、权限和证据行残留均为0；随后重新运行R1D-C-C-A只读审计，业务基线恢复一致。测试DML全部位于回滚事务，没有持久测试记录或测试ID残留。

## 7. 正式执行分类

执行的正式仓库SQL：

1. `sql/current/school_tuition_r1d_c_c_a_current_only_42_billing_fact_readonly.sql`：schema/backfill脚本内前置只读审计；
2. `sql/current/school_tuition_r1d_c_c_b_historical_42_exclusion_rollback_tests.sql`：同文件ROLLBACK演练；
3. `sql/current/school_tuition_r1d_c_c_b_historical_42_exclusion_schema_backfill.sql`：正式DDL与固定42证据INSERT；
4. `sql/current/school_tuition_r1d_c_c_b_historical_42_exclusion_postdeploy.sql`：正式只读验收。

另执行`/private/tmp/r1d-c-c-a-cash-evidence-readonly.sql`生成Cash前后只读基线。

永久DDL：

- 1张证据表；
- 3个函数：固定42 manifest、INSERT guard、immutable guard；
- 3个trigger：INSERT guard、UPDATE/DELETE不可变、TRUNCATE不可变；
- 2个索引、外键/唯一/check约束、comments、revoke/grant。

事务内临时DDL：School业务fingerprint临时函数和`ON COMMIT DROP`临时基线表；回滚后/提交后自动消失。

正式DML只有新表`INSERT 42`。没有UPDATE lesson/actual，没有禁用任何trigger，没有写bill、income、identity、relation、migration audit、settlement、wage、School账户流水、Cash linkage或override audit。Cash永久/临时DDL与DML均为0。没有调用Supabase RPC或任何写RPC。

## 8. School/Cash前后基线

正式事务内部对所有既有School业务表做前后完整JSON fingerprint比较；postdeploy再按权威数量及重点hash独立断言，均通过：

| School对象 | count | 前后hash |
|---|---:|---|
| lesson raw37 | 626 | `c4f892d857fe674e4060f80d6af56b42` |
| lesson old31 | 626 | `4fb1901c888d56cb29c05e387490ca75` |
| tuition bill | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| billing identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| bill lesson relation | 121 | `09dfee7d8833e09384fb41a84f2959e0` |
| migration batch/item | 2 / 118 | `18e74c21ebf95fdf80bed6767a4e28be` / `23a2f93d0db01d84ba6195573ec58790` |
| student settlement | 15 | `7925cf3018bd0e669cd29710f6593238` |
| settlement adjustment | 5 | `4bce2b158d4de769d592a2d367881868` |
| student payment | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| School account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| teacher wage lock/detail | 95 / 556 | `7bbe108d3ac73d4f21530793bf141bc6` / `6204dc666b3b8e0f64fac901ecf0686a` |
| feature gate | 3 | `da00c76d8f8c72dd2decdac8ab6125b8` |
| billing override audit | 0 | `d41d8cd98f00b204e9800998ecf8427e` |

626 lesson仍为397 planned + 229 actual；五个收费归属字段各118条非NULL，`scheduled_lesson_date`仍全库0。A1 52及A2 66的归属事实、全部lesson/actual完整JSON与updated_at未变化。

Cash前后：

| Cash对象 | count | 前后hash |
|---|---:|---|
| external request | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| CNY transaction | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| JPY transaction | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

四笔School income UUID在Cash request/CNY/JPY transaction的固定引用仍均为0；Cash数据库零写入。

## 9. Candidate与R0保持未切换

正式部署前后`school_list_student_tuition_candidates(uuid,uuid,text,boolean)`函数定义MD5均为`1d9149f6e3ff02305d0963f81af9f0b9`，函数定义不包含新证据表名。候选数量保持：

| 集合 | 行 |
|---|---:|
| 现行旧字段candidate | 160 |
| 完整合法新字段candidate | 118 |
| current-only | 42 |
| new-only | 0 |

新表存在不表示candidate已经使用它。本阶段没有修改preview RPC/API/page，也没有把42条从当前候选结果中删除。

R0保持：

- `student_tuition_preview = validation_preview_only`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

本阶段没有主动调用写入口探针；通过gate只读状态及既有函数定义不变确认没有解除R0。

## 10. Git停止点与后续边界

本阶段新增3个SQL和本报告，更新`docs/current-status.md`。未执行`git add`、commit或push。受保护的R1B临时审查文件未修改、未删除、未暂存。

后续candidate切换仍须独立授权，必须明确读取这张证据表的排除语义并另行完成rollback、postdeploy与Git审查。本阶段不启动candidate切换、writer改造、actual继承、scheduled date处理或R0解除。
