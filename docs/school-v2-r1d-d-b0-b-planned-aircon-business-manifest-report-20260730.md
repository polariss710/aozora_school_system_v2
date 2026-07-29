# School V2 学费链 P0：R1D-D-B0-B Planned/Aircon业务Manifest冻结与只读验证

日期：2026-07-30
阶段：R1D-D-B0-B
状态：只读预检与最终工件执行全部通过

## 1. 阶段目的与边界

本阶段冻结后续planned writer与空调费实施所需的业务输入：固定办公室映射、空调费生效规则、两名学生的有效期费率、118条future planned固定UUID集合、279条legacy planned阶段外边界、三组历史已收费排除，以及孙陈锋2026-09尚无planned的事实。

本阶段只执行School数据库只读查询，不实施DDL、DML、业务RPC、回填或candidate切换；不修改`docs/current-status.md`、API、页面或既有SQL；不进入R1D-D-B1-A。

## 2. Git与数据库基线

- 分支：`main`
- HEAD：`ddad5e3a95bc1234c7667b454a396491c5c885d0`
- `origin/main`：`ddad5e3a95bc1234c7667b454a396491c5c885d0`
- 受保护R1B临时文件保持未跟踪，SHA-256为`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。
- 前置只读快照时间：`2026-07-29 04:40:27.695875+00`
- 最终工件只读快照时间：`2026-07-29 04:42:35.247411+00`
- lesson：628；planned：397；actual：231。actual较旧基线的正常运营增长只作披露。
- planned收费归属五字段完整：118；五字段全NULL：279；部分填写：0；`scheduled_lesson_date`非NULL：0。
- planned相对权威397基线增量：0，因此新增五字段全NULL planned为0。

R0保持：

- `student_tuition_preview = validation_preview_only`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

candidate函数定义MD5保持`8981a2ce07abf8c28231bfaf05451368`。本阶段未调用candidate业务RPC；通过与当前权威函数条件等价的表级只读查询核验为118条、254小时、JPY2,474,000，UUID集合MD5为`77f697f82e547d84dcabf88a3c868aa1`。

## 3. 固定办公室与空调费业务规则

固定映射冻结为：

| 当前`lesson_venue`显示值 | 业务含义 | 后续稳定code |
|---|---|---|
| `Regus办公室` | 青空塾固定办公室 | `regus_office` |

本阶段不创建venue master、不修改lesson，也不把中文显示字符串直接固化为长期收费判断。`Regus公共区`不属于固定办公室；线上课程不适用本规则。

空调费输入规则：

- 生效日：2026-08-01；
- 场地实际费用上限：JPY660/报备小时；
- 学生承担单价必须是0至660的整数；0必须显式配置；缺失配置是`unconfigured`并fail-closed；
- 费率按有效期新增记录，后续变更不得覆盖历史；
- 仅当生效日已到、venue code为`regus_office`、`scheduled_lesson_date`为周六或周日、且学生有效费率大于0时适用；
- 批量planned尚无预计日期时，空调状态应为`pending_schedule`，不得默认收费或默认不收费。

## 4. 学生费率Manifest

姓名以`public.school_students.name`精确匹配。两名学生均唯一命中、UUID与仓库固定证据一致且状态为`active`。

| 学生 | 固定UUID | 生效日 | 截止日 | JPY/报备小时 |
|---|---|---|---|---:|
| 孙陈锋 | `b17abc58-2f64-4bad-bf20-c9643ead60bc` | 2026-08-01 | NULL | 330 |
| 张倬闻 | `7aef8061-7037-4881-a847-a2cdb031c0f4` | 2026-08-01 | NULL | 0 |

费率Manifest SHA-256：`ed82a6c501121a825d0d279a43201a58d6d02f000a0a7273570335fc4e7ffe63`。

序列化规则为按`student_id::text`排序，每行连接`student_id|name|unit_price|effective_from|effective_to`，NULL记为`NULL`，UTF-8编码，行末及文件末均含换行。本阶段不写费率表；B1-C必须使用上述固定UUID，不得重新按姓名模糊匹配。

## 5. 118条future planned固定Manifest

118个UUID已完整写入只读SQL的`VALUES`，并按`student_id / billing_month / billing_week_start_date / lesson_id`排序。报告不重复全文UUID。

| 学生/月 | 条数 | 小时 | 当前基础费 |
|---|---:|---:|---:|
| 孙陈锋2026-08 | 22 | 44 | JPY374,000 |
| 张倬闻2026-08 | 30 | 65 | JPY650,000 |
| 张倬闻2026-09 | 24 | 52 | JPY520,000 |
| 张倬闻2026-10 | 24 | 52 | JPY520,000 |
| 张倬闻2026-11 | 18 | 41 | JPY410,000 |
| 合计 | 118 | 254 | JPY2,474,000 |

冻结hash：

- UUID集合MD5：`77f697f82e547d84dcabf88a3c868aa1`
- 完整业务Manifest SHA-256：`f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1`

业务Manifest SHA-256覆盖`lesson_id`、`student_id`、`billing_month`、`billing_week_start_date`、`duration_hours`、`unit_price`、`lesson_fee`、`billing_month_source`、`billing_month_decided_at`；按固定四字段顺序排列，NULL显式记为`NULL`，UTC时间使用微秒精度，UTF-8编码，行末及文件末均含换行。

只读断言确认：118个值/118个不同UUID全部命中；完整五字段范围外记录0；业务行异常0；actual关联0；normalized bill relation 0；bill JSON snapshot命中0；历史排除命中0；排序错误0。118条全部仍为active planned、`lesson_date=billing_week_start_date`周一代理、`scheduled_lesson_date`/`lesson_delivery_mode`/`lesson_venue`均为NULL。

后续只能人工补充真实预计日期和venue；不得从周一代理推断；不得修改既有billing week/month/source/decided_at；真实预计日期必须落在冻结billing week内。

## 6. 279条Legacy边界

- 五字段全NULL：279；部分填写：0；
- UUID集合MD5：`0975fdc91b533680e5ccc909f076ac62`；
- 不做通用billing/scheduled/venue/fee回填，不开放普通业务事实编辑，不加入空调费Manifest；
- actual及其他下游事实、固定42历史排除、pending_makeup、两条李天伦测试导入均保持阶段外。

actual当前全库数量为231；本阶段只冻结279条planned边界，不修改或重新解释任何actual。

### 6.1 Pending makeup数量口径勘误

R1D-D-B0-B-E在`2026-07-29 06:36:20.695693+00`只读快照中确认，“6条”和“25条”都是`public.school_lesson_records`中的planned课时行，可以直接比较，但范围不同：

| 口径 | 精确筛选 | 行/不同UUID | UUID集合MD5 | 与279/118交集 |
|---|---|---:|---|---|
| 固定历史6 | `lesson_type='planned' AND status='pending_makeup'`，学生限定陈加恩/陈红卓，`year_month IN ('2026-05','2026-06')` | 6/6 | `5a7e6ffc6161cf40c9b267600c93aad8` | 6/0 |
| 全库动态快照25 | `lesson_type='planned' AND status='pending_makeup'`，不限制学生或月份 | 25/25 | `54bb70fe88e86e336617dce7f7b03059` | 25/0 |

固定历史6的完整JSON聚合MD5仍为`0a30ece80c040491747f320d63c98e3d`；6个planned各关联1条actual，重复actual来源0，bill relation、bill JSON snapshot及历史收费排除均为0。其固定UUID与R1D-C-C-B/C-C-C证据逐项一致。

全库25是同一状态的动态运营快照，不是固定历史收费业务Manifest：其中13个planned关联14条actual，1个planned存在多条actual关联；10个planned有normalized bill relation且同10个也有bill JSON snapshot；历史收费排除命中0。其完整JSON聚合MD5为`ee07095f95e7046fd82c8ebd56ee9e5c`。

集合关系为交集6、固定6独有0、全库快照独有19；即固定历史6是全库25的真子集。原文笼统写“25条pending_makeup保持阶段外”没有区分固定业务范围与全库状态快照，表述不精确。最终口径为：固定历史6继续保持阶段外；全库当前另有19个同状态planned，合计动态快照25，也全部保持阶段外。动态25及其hash只用于本次勘误快照披露，不作为未来部署硬阻断条件。

## 7. 已收费历史排除

只读证据全部匹配：

1. 孙陈锋`8b737b58-cd14-42c5-afd2-34730dcef963`：2026-08-01、`Regus办公室`、2小时、当前课时费JPY17,000，仍有2026-07 canonical relation；不得追加空调费或修改历史账单。
2. 孙陈锋`685ad45e-b5da-42ca-8f43-7732e8d6e40d`：2026-08-02、venue NULL、2小时、当前课时费JPY17,000，仍有2026-07 canonical relation；不得追加空调费或补推venue。
3. 陈加恩2026-08 canonical bill `1b546782-1b39-4c73-a85d-27ab1e5086ad`：12条、24小时、JPY216,000、`income_created`，12条canonical relation全部存在；不得追加空调费或重算历史账单。

## 8. 孙陈锋2026-09缺失事实

只读核验为planned 0、candidate等价范围0、active bill 0。不得从8月复制或推断；本阶段不创建。后续必须由canonical planned writer根据明确billing week、duration及课程信息新建，并在正式generate前完成venue、schedule及aircon状态。

## 9. SQL执行与零写入

执行文件：`sql/current/school_tuition_r1d_d_b0_b_planned_aircon_business_manifest_readonly.sql`。

- SQL结构为单一`REPEATABLE READ READ ONLY`事务，末尾显式`ROLLBACK`；
- 只使用`SELECT`、`WITH`、`VALUES`及只读内建函数；不调用业务RPC；
- UUID唯一性解析使用`min(matched_student_id::text)::uuid`且仅在命中数为1时返回，不再对UUID直接使用`min/max`；
- 静态检查确认无可执行DDL/DML、CTE作用域完整、118值数量/唯一性/固定排序正确；
- 前置完整只读执行成功，全部布尔断言为true；
- 最终工件再次完整执行成功，包含新增的费率Manifest与118业务Manifest SHA-256固定断言，全部布尔断言为true，并以`ROLLBACK`结束；
- B0-B-E新增两种pending_makeup口径的数量、UUID/full-row hash、actual关联、279/118交叉及账单证据查询；固定6集合与子集关系作为断言，全库动态计数/hash不作为未来硬阻断条件；
- 数据库DDL 0，数据库DML 0，数据库写入0，测试记录0，SQL/RPC业务调用0。

B0-B-E数据库执行分类：仅连接School数据库`postgres`；证据调查SQL执行1次，修改后的完整工件执行1次，合计2次；两次均为`repeatable read / transaction_read_only=on`并显式`ROLLBACK`，SQL错误0。修改后完整工件快照时间为`2026-07-29 06:39:04.058772+00`。

修改后完整工件的布尔输出逐项为：

- database：`lesson_table_exists=true`、`student_table_exists=true`；
- R0开始：三个`expected_state=true`；candidate：`expected_definition=true`；
- lesson基线：`expected_stable_scope=true`；两名学生：两个`expected_student=true`；
- 固定118：`all_expected=true`；candidate表级等价核验：`all_expected=true`；279边界：`all_expected=true`；
- 固定历史6：`same_object_type=true`、`directly_comparable=true`、`dynamic_snapshot_only=false`（预期分类）、`scope_definition_consistent=true`、`set_relationship_consistent=true`；
- 全库动态25：`same_object_type=true`、`directly_comparable=true`、`dynamic_snapshot_only=true`（预期分类）、`scope_definition_consistent=true`、`set_relationship_consistent=true`；
- 孙陈锋两条跨月历史排除：`all_expected=true`；陈加恩2026-08历史排除：`all_expected=true`；
- 孙陈锋2026-09缺失事实：`all_expected=true`；R0结束：`all_expected=true`；最终`transaction_read_only=on`。

非交互shell第一次未发现`load_both_db`，`psql`仅尝试本机socket后退出，未连接数据库、未发送SQL；随后仅通过交互shell加载环境，实际生产数据库只读执行次数按上述记录计算。

## 10. 后续B1-A输入契约

B1-A及后续必须以本阶段固定事实为输入：

- 稳定venue code使用`regus_office`，不得以中文显示值作为长期收费事实；
- 只允许固定118 UUID进入future planned排课/venue处理，不得动态扩展；
- 孙陈锋/张倬闻费率使用固定UUID与有效期记录，缺失配置fail-closed；
- `scheduled_lesson_date`必须由用户明确提供并限制在冻结billing week内，不能反推或改变billing归属；
- 279 legacy、三组历史已收费排除及孙陈锋2026-09缺失事实继续保持独立边界；
- 任何writer/candidate/fee schema与部署仍需独立阶段授权、ROLLBACK、postdeploy、R0及Git审查。

## 11. 阶段外确认与工作区

本阶段未创建venue/费率数据，未修改lesson、bill、income、Cash、actual、月结或工资，未改变candidate或R0 gate，未修改现有仓库文件，未暂存、commit或push，未进入R1D-D-B1-A。

完成时工作区应仅包含受保护R1B临时文件及本阶段两份新增工件；最终SHA-256和`git status --short`以完成验收输出为准。
