# R1D-E-C 学生结算 reader 权威月份切换报告

日期：2026-07-30（Asia/Tokyo）
阶段：R1D-E-C
停止点：数据库审查点（禁止 Git 提交）

## 1. 范围与结论

本阶段仅把学生月度结算的 lesson 读取边界从裸 `year_month` 切换为数据库权威学生结算月。覆盖：

1. `school_get_student_monthly_settlement_summary`
2. `school_get_student_monthly_settlement_preview`
3. `school_get_student_monthly_settlement_wage_blockers`
4. `school_assert_student_monthly_settlement_no_wage_blocker`
5. `school_lock_student_monthly_settlement`
6. `school_unlock_student_monthly_settlement`
7. `school_relock_student_monthly_settlement`
8. `school_set_student_monthly_settlement_draft_adjustment`

未修改 planned/actual writer、candidate、页面、JS、API、资金链、R0、E-B2 工件或 `docs/current-status.md`；未连接 Cash DB；未进入 R1D-E-D、S1-B 或 R0 解除。

## 2. Git 与数据库基线

- branch：`main`
- 开始时 `HEAD/origin/main`：`9f072844bd15d4ac515d0b1b594ee0d989e6f881`
- 暂存区：空
- 初始唯一未跟踪文件：受保护文件
- 保护文件 SHA-256：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- School DB：通过登录 shell 的 `load_both_db` 加载，仅使用 `SCHOOL_SUPABASE_DB_URL`
- Cash DB：未连接

E-B2 postdeploy preflight 通过：

- version：`r1d_e_b2_actual_writer_v1`
- fixed legacy actual：234
- UUID MD5：`891eeabf9a48d1c7b00a695b21cf8e95`
- identity manifest SHA-256：`83f9df656fc8e089ce769cac84d61338c0889ac853b2e2b544f8b2bf3678650c`
- full-row manifest SHA-256：`dd25082aac3216cf3ba6160e3ee81f56845359aa1a603e975b864bb630d933f8`
- actual writer组 MD5：`046cb8c0002528634b767a046e4626ab`
- trigger function MD5：`4a163f6691c779531a65a10be0f4422e`
- 原 settlement reader组 MD5：`b17b31a3dc1797159556032abdb04ac3`

运营期间 post-cutover canonical actual 从0增长为1，canonical planned 从118增长为135；重新执行 baseline 后全部合法，属于允许的运营增长。

## 3. Catalog、调用链与兼容性审计

8个外部函数均各有一个生效签名，owner 均为 `postgres`。原安全属性：summary 为 invoker，其余7个为 definer；8个函数 ACL 相同，PUBLIC、anon、authenticated、service_role 均保持原 EXECUTE 权限。

调用关系：

- summary 直接读取 lesson；preview 调 summary；
- wage blockers 直接读取 actual lesson；assert 调 wage blockers；
- lock/relock/draft 直接做 lesson existence 检查并调用 preview；
- unlock 不重算金额，但调用 assert；
- preview、assert、unlock 是既有 wrapper/guard 链，外部签名与返回结构保持不变。

内部 resolver 不向 service_role/PUBLIC/anon/authenticated开放，因此 summary 必须从 invoker 改为固定 `search_path` 的 definer；这是唯一安全属性变更，外部 ACL、参数和返回契约不变。

## 4. 权威 resolver

新增内部对象：

- `school_r1d_e_c_settlement_reader_cutover_version()`
- `school_resolve_r1d_e_c_lesson_student_month(uuid)`
- `school_list_r1d_e_c_student_month_lessons(uuid,text)`

三者均撤销 PUBLIC、anon、authenticated、service_role 的直接执行权。

分类规则：

- canonical planned：验证五字段完整、学生月=计费月、ISO Monday、month/week一致、批准 source；新 writer source 还复用 DB duration resolver；
- legacy planned：五字段全NULL且 immutable 279 evidence 的身份、机构、旧月、source/version/manifest全部匹配；
- canonical actual：不得命中234 evidence；验证 source planned、student/entity、student month、teacher month、actual禁用计费字段及 source权威月；
- legacy actual：只接受234 evidence，逐项验证 source、student/entity/teacher/subject、旧月、teacher month、lesson date、identity MD5、full-row MD5、source/version，且 `student_settlement_month`继续为NULL；
- partial、无evidence NULL、identity/full-row/source/month漂移、非法 app/type：全部抛错，禁止任何日期或 `coalesce(student_settlement_month,year_month)`兜底。

## 5. 切换前 baseline 与差异分析

第一次 baseline 覆盖631条 School lesson；运营增长后重新覆盖649条：

| 分类 | 数量 | 权威月与旧月不同 |
|---|---:|---:|
| canonical planned | 135 | 0 |
| legacy planned | 279 | 0 |
| canonical actual | 1 | 0 |
| legacy actual | 234 | 0 |

- 无法分类：0
- settlement + candidate scope：20
- scope baseline SHA-256：`e7280307cafec31ce1f50c1c9ced7b4cc562e7f387fd6951ec2ad05c73d81d71`
- old/new lesson集合、count、duration、amount、UUID hash 差异：0
- locked snapshot：15
- locked evidence mismatch：0
- locked summary/preview reader SHA-256：`b3a27028c10c11baefebeb4669c6b91758266353cb357dcc77344431c6b2d20f`

因此本次切换的预期现存业务结果变化严格为0；变化仅在未来 canonical 跨月 lesson 的选择规则和非法数据 fail-closed。

## 6. 锁、重锁及历史snapshot保护

- lock/relock 在同一事务中以 lesson table `SHARE` lock 和 wage detail table `SHARE` lock 覆盖权威解析、blocker、preview及snapshot写入，防止 lesson/wage fixture 在 precheck 与写入之间漂移；
- lock、relock、draft 的 existence 检查改用同一 resolver；
- blocker仅改变 actual lesson 的学生月份选择，teacher wage月份及资金事实不变；
- 15个 legacy snapshot 增加显式 unlock/relock拒绝 `R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE`，不会被动态重算；
- bill、carryover、posted adjustment、draft、active wage、payment/expense/account保护保持。

## 7. 工件与执行记录

工件：

- `sql/current/school_tuition_r1d_e_c_settlement_reader_authoritative_month_cutover.sql`
- `sql/current/school_tuition_r1d_e_c_settlement_reader_authoritative_month_cutover_postdeploy.sql`
- `sql/current/school_tuition_r1d_e_c_settlement_reader_authoritative_month_cutover_rollback_tests.sql`
- `docs/school-v2-r1d-e-c-settlement-reader-authoritative-month-cutover-report-20260730.md`

调试/失败记录：

1. catalog preflight 第1次：`has_function_privilege('PUBLIC',...)`错误；SHA `f7767784…` → `35c05d5d…`，改为 `aclexplode`；无数据库写入。
2. catalog preflight 第2次：连接前DNS失败；同字节重试成功；无数据库执行。
3. reader baseline 第1次：误用 actual evidence 不存在的 `approved_manifest`；SHA `5f11db10…` → `0def69d5…`；无数据库写入。
4. reader baseline 第2次：该版本不支持带 null-safe 条件的 FULL JOIN；SHA `0def69d5…` → `3962faab…`，因键已证明非NULL改为等值连接；第3次通过。
5. cutover-only rehearsal 初稿 SHA：`29790d78…`；对象及语法通过，连接关闭回滚；发现允许运营增长后重跑 baseline，结果仍无差异。

最终SQL三工件 SHA-256（与完整 rehearsal、正式部署同字节）：

- cutover：`29790d78b4bdd438d199b852e58dfce95e2a5df0768ac54cc4b8a45b074bd7a4`
- postdeploy：`d96d6f29a5144e50759e880bbc4604ebccbd059dc7053d5d7ea5680b7c2e0acd`
- rollback tests：`fe4dedd292c7ee7dc1f5be2184887cd3288b8718f725236b8e667e20736e82e0`

完整 rehearsal：

- driver SHA-256：`5940ef8834f33a4e23e3ee9ba37c430ad60455150939a6ad8d884269b44c8b8e`
- 执行次数：1；结果：cutover、postdeploy、23/23 rollback matrix全部通过；末尾显式 `ROLLBACK`
- 新连接：3个E-C对象不存在、reader组恢复 `b17b31a3dc1797159556032abdb04ac3`、测试残留0；随后E-B2完整postdeploy再次通过
- rehearsal planned UUID：`c6254a4f-6e81-40b7-a64c-499786d71a5f`、`0874a84f-7ef0-48e9-9811-6b0b6e845c2a`、`0353ea55-f447-441a-b42e-710ba3d8e163`、`5859d587-c0f4-4a41-b2ce-a48bae368946`、`c9c45c76-ab8d-4251-9bab-f43462f6628c`
- rehearsal actual UUID：`ace4bdbd-27fa-437c-98b1-284f397d0845`、`17f4d247-3470-4df8-99fc-40263170b2de`、`f051f027-65d1-451b-b287-bb11c750965c`、`840e6eb9-82ca-465f-ab98-640588d9f2b9`
- rehearsal settlement UUID：`abab2a75-3cd4-4c9c-a700-edec543f3fb4`

正式部署：

- 执行次数：1；`psql -X -v ON_ERROR_STOP=1 -v r1d_e_c_commit=1 -f ...cutover.sql`
- 结果：无SQL错误，649条现存School lesson全部分类，`COMMIT`成功
- version：`r1d_e_c_settlement_reader_v1`
- reader组 MD5：`b3818fc1119b5b2c1069d78164760e95`
- resolver MD5：`8de65e9787d8d66f2cd7b65eb2479a8c`
- set helper MD5：`155e831118acbeadfd04b6640324c7cd`
- version helper MD5：`1307a4e86cccff841af55d3120a33b43`
- 三个内部对象ACL：均仅 `{postgres=X/postgres}`
- actual writer组 MD5：`046cb8c0002528634b767a046e4626ab`
- E-B2 trigger function MD5：`4a163f6691c779531a65a10be0f4422e`
- 业务表写入：0；正式写入仅为3个内部函数和8个外部函数最终定义/COMMENT/ACL

正式验收：

- postdeploy：完整rehearsal内1次、正式COMMIT后1次、独立测试后最终1次，共3次，全部通过并回滚
- rollback tests：完整rehearsal内1次、正式部署后独立1次，共2次；每次23/23通过并回滚
- 独立 planned UUID：`7a9d6a03-bb58-4abe-b651-afe4c3d81405`、`8c7e507e-a778-4c9a-a2fa-e4a637baabf8`、`658b2533-2933-482b-98dd-2e4d48951161`、`4e95395c-2c1a-4531-8bfc-a50b39f8e4cc`、`ed38710d-212b-4589-bb0b-792410dda974`
- 独立 actual UUID：`73a50853-6f19-4bb1-b28b-4cfecada162f`、`9fa0ca33-8b96-46bd-93b0-7fbc57a1fcae`、`6f1bdeed-59d5-4b4c-a3d8-9910f4781ac3`、`63ef73cb-ccb5-4aa0-bb11-897f52bf3c42`
- 独立 settlement UUID：`b16df928-7ffa-4295-b09c-37dc2befe128`
- 独立测试后新连接残留：0
- 最终 scope baseline SHA-256：`e7280307cafec31ce1f50c1c9ced7b4cc562e7f387fd6951ec2ad05c73d81d71`
- 最终 locked reader SHA-256：`b3a27028c10c11baefebeb4669c6b91758266353cb357dcc77344431c6b2d20f`
- 正式部署及全部正式验收失败：0；没有发生COMMIT后失败或生产回滚

## 8. 最终保护边界

最终再次确认：

- R0：`validation_preview_only / blocked / blocked`
- candidate：118 / 254小时 / JPY2,474,000，函数与manifest hash不变
- planned：批准118、legacy279、partial0；运营新增canonical只允许合法增长
- actual evidence：234及全部manifest不变；existing actual业务行不变且学生月仍NULL
- writer组、trigger、ordinary `<>`规则不变
- overage 19全部S1-A字段NULL；makeup 8历史事实不变
- locked snapshot 15、结构、lesson/amount basis与reader结果不变
- School资金链9/42/121/42及hash不变；aircon为0
- 测试全部ROLLBACK且新连接残留0
- 暂存区为空；最终工作区仅保护文件和本阶段4份工件
- 不提交、不推送；停止在 R1D-E-C 数据库审查点

结论：R1D-E-C数据库部署与验收通过，停在数据库审查点，等待独立Git授权。
