# School V2 学费链P0：R1D-C-C-C Candidate新收费归属口径切换实施报告

- 实施日期：2026-07-28
- Git基线：`943d86689b26dde7a8895d1141f3b5c60332868c`（实施前HEAD与`origin/main`一致）
- School最终部署前只读事务：`2026-07-28 12:54:00.303866+00`
- School正式postdeploy只读事务：`2026-07-28 13:02:03.099378+00`
- Cash部署前/后只读事务：`2026-07-28 12:54:05.649642+00` / `2026-07-28 13:01:22.019272+00`；双库不是原子快照
- candidate定义hash：`1d9149f6e3ff02305d0963f81af9f0b9` → `8981a2ce07abf8c28231bfaf05451368`
- 正式永久DDL：替换1个既有只读candidate函数定义，更新comment与ACL；未增加表、列、index、trigger或helper
- 正式业务DML：0；Cash DDL/DML：0
- R0：`validation_preview_only / blocked / blocked`
- 结论：candidate权威scope已从旧`year_month`切换到显式billing归属字段，并显式读取固定42不可变历史排除证据；集合由160精确切换为批准的118。

## 1. 调查、调用链与兼容契约

实施前数据库目录确认：

| 函数 | owner | security | 权限 | 定义hash |
|---|---|---|---|---|
| `school_list_student_tuition_candidates(uuid,uuid,text,boolean)` | postgres | DEFINER | service_role EXECUTE | `1d9149f6e3ff02305d0963f81af9f0b9` |
| `school_preview_student_tuition_bill(uuid,text,numeric)` | postgres | DEFINER | authenticated/service_role EXECUTE | `ea71010c17f880ee61092bb8e01ea920` |
| `school_classify_student_tuition_candidate(...)` | postgres | INVOKER/IMMUTABLE | service_role EXECUTE | `759738bc62c558b5d29e2078b06ea297` |

数据库函数定义中只有preview直接调用candidate，没有view引用candidate。仓库实际页面调用链仍为：

`income.html` → `js/pages/income-page.js` → `js/api/income-api.js::previewStudentTuitionBill(...)` → `school_preview_student_tuition_bill(...)` → candidate。

其他仓库引用均为只读审计、迁移回归或postdeploy SQL。正式generate函数没有调用candidate，并继续由R0在函数开头阻断。本阶段未修改preview、classifier、generate、Cash、API或page。

candidate参数、22列返回结构、owner、SECURITY DEFINER和service-role-only权限全部保持不变；`year_month`及`lesson_date`仍作为兼容输出列返回，但不再决定candidate scope。preview定义hash保持`ea71010c17f880ee61092bb8e01ea920`，因此公开API契约无需变化。

## 2. 新权威candidate规则

新函数只扫描满足`lesson.student_id = p_student_id AND lesson.billing_month = p_billing_month`的行。每条candidate还必须满足：

- School `planned / status=planned / 未void / is_billable=true`；
- `business_entity_id`精确等于显式请求实体；当前schema没有单独的`billing_business_entity_id`，这里使用的是经R1C-A/R1C-C-B固定ID迁移并与新billing字段共同审批的现有`business_entity_id`，不从学生、旧月份或日期动态推断；
- `billing_week_start_date`非NULL且通过`school_is_valid_tuition_billing_period(billing_month, week)`；
- `student_settlement_month = billing_month`；
- `billing_month_source`只允许`approved_r1c_a_manifest`或`approved_r1c_c_b_manifest`；
- `billing_month_decided_at`非NULL；
- 原有teacher/subject/count/duration/unit price/fee及技术完整性条件继续成立；
- normalized bill relation、bill JSON snapshot及冲突仍按R1C-B规则优先fail-closed排除；
- `school_student_tuition_historical_lesson_exclusions`命中时返回`historical_paid_exclusion`并排除。

函数不读取`scheduled_lesson_date`决定收费归属，不读取`created_at/updated_at`推导月份，不使用旧`year_month/lesson_date`或缺失snapshot fallback。即使固定42将来被误填为完整新归属，历史排除证据仍独立阻止其重新成为candidate。

R1D-B已有planned `(student_id,business_entity_id,billing_month)` partial index和合法period helper，现有结构足够，不新增重复索引或辅助函数。

## 3. 160→118集合证明

部署前只读事务重建：

| 集合 | 行 |
|---|---:|
| 旧candidate | 160 |
| 目标candidate | 118 |
| 旧有、目标无 | 42 |
| 目标有、旧无 | 0 |
| 差集命中固定历史排除证据 | 42/42 |
| 固定证据不在差集 | 0 |

正式事务先在替换函数前冻结旧160 UUID，替换后冻结新118 UUID，再以SQL `EXCEPT/FULL JOIN`逐UUID验证：旧减新精确等于固定42，新增UUID为0；新118与migration batch `c100...279999`的52 item及`c100...289999`的66 item完全一致。

正式结果：

| 学生/月 | source | 行 | 小时 | JPY |
|---|---|---:|---:|---:|
| 孙陈锋 2026-08 | `approved_r1c_a_manifest` | 22 | 44 | 374,000 |
| 张倬闻 2026-08 | `approved_r1c_a_manifest` | 30 | 65 | 650,000 |
| 张倬闻 2026-09 | `approved_r1c_c_b_manifest` | 24 | 52 | 520,000 |
| 张倬闻 2026-10 | `approved_r1c_c_b_manifest` | 24 | 52 | 520,000 |
| 张倬闻 2026-11 | `approved_r1c_c_b_manifest` | 18 | 41 | 410,000 |
| 合计 |  | 118 | 254 | 2,474,000 |

118/118 period合法、student settlement month匹配、source已批准、decided_at非NULL；与固定42证据交集0。五个student/month组合经公开validation preview逐组验证，数量、小时、JPY均与上表一致。

## 4. 固定42与6条pending_makeup

固定历史排除证据保持：

- 行数42；candidate命中0；
- full hash `680b6e5aaa718569aee4c36fe1cdc058`；
- old31 aggregate hash `dc6cd4ad206cc09ed5c02dfe6da5462b`；
- evidence aggregate hash `dc2546bff536942650db58e437d37f0e`。

6条`pending_makeup`仍没有billing attribution，也没有历史排除证据，本阶段未修改或纳入；完整JSON聚合hash保持`0a30ece80c040491747f320d63c98e3d`。它们的固定UUID仍为：

- `9085ab09-a719-42b7-a517-2700b8d9ddb0`
- `e5eb7a47-13ea-4858-b73a-ddf5cc38c0f7`
- `2b49f20c-4c94-4129-abca-bd12a75c5026`
- `44ddcda2-dbdd-48c2-8d0a-ba59a5e65a90`
- `4da7e3e9-d36c-4102-b582-c67b281b5b69`
- `98a0f192-6e6f-4f6a-9cfc-bd2570d308fd`

## 5. ROLLBACK演练与负向测试

`school_tuition_r1d_c_c_c_candidate_cutover_rollback_tests.sql`以`r1d_c_c_c_commit=0`执行与正式部署相同的cutover文件。最终版本完整通过：临时安装后candidate hash为`8981a2ce07abf8c28231bfaf05451368`，旧160→新118集合断言通过。

回滚事务只使用两个精确既有UUID：

- 固定历史证据lesson：`495c035a-68f7-42a1-b2a9-28b89ee01d6b`；
- 合法118目标lesson：`23d4b46b-eb1c-48b7-8001-d208ce14f08d`。

验证结果：

1. 为固定历史lesson临时补齐完整新归属后，仍返回`historical_paid_exclusion`；
2. 尝试删除正式历史证据被immutable trigger拒绝，证据从未实际缺失；
3. 目标lesson临时缺少`student_settlement_month`时返回`invalid_or_incomplete_data`；
4. 非周一/非法month-week UPDATE被R1D-B check拒绝；
5. source存在但decided_at为空被R1D-B check拒绝；
6. 临时写入非批准source后返回`invalid_or_incomplete_data`；
7. 临时修改`scheduled_lesson_date`不改变candidate资格；
8. 固定历史lesson清空新归属并修改旧`year_month/lesson_date`后仍不能进入candidate；
9. 6条pending_makeup数量和状态不变；
10. preview gate仍为validation-only；
11. 两个generate、bill→income、legacy personal tuition四入口、Cash gate和事故Cash入口全部按预期拒绝。

回滚分支共执行8条成功的临时UPDATE语句，范围仅上述2个固定UUID；另有非法period、缺decided_at和证据DELETE三项被拒绝尝试。所有变更处于同一事务并最终ROLLBACK，`updated_at`、业务字段、证据、权限及函数定义全部恢复；没有INSERT测试lesson、没有持久测试ID。三张temp表和pg_temp fingerprint函数残留0。最终旧candidate hash恢复`1d9149...`，R1D-C-C-B postdeploy再次通过。

第一次ROLLBACK在固化新函数预期hash前已完整通过；取得新hash后只增加精确hash断言，并重新执行最终文件，第二次同样完整通过。正式执行使用第二次验证的最终文件。

## 6. 正式DDL/DML分类

正式执行文件：

1. `sql/current/school_tuition_r1d_c_c_c_candidate_cutover.sql`；
2. `sql/current/school_tuition_r1d_c_c_c_candidate_cutover_rollback_tests.sql`；
3. `sql/current/school_tuition_r1d_c_c_c_candidate_cutover_postdeploy.sql`；
4. `sql/current/school_tuition_r1b_r0_entry_probes.sql`（既有拒绝探针）；
5. `sql/current/school_tuition_r1d_c_c_a_current_only_42_billing_fact_readonly.sql`与`school_tuition_r1d_c_c_b_historical_42_exclusion_postdeploy.sql`（部署前/回滚后只读基线）。

另执行`/private/tmp/r1d-c-c-c-predeploy-inventory-readonly.sql`及既有Cash临时只读基线。

准确分类：

- 永久DDL：`CREATE OR REPLACE FUNCTION school_list_student_tuition_candidates`、COMMENT、REVOKE/GRANT；没有新增永久对象；
- 正式业务DML：0；
- 正式事务临时DDL：1个pg_temp fingerprint函数、3张`ON COMMIT DROP`临时表；
- 正式事务临时DML：向旧/新candidate临时集合分别INSERT 160/118，仅用于UUID级比较；
- rollback测试业务DML：上述2个固定lesson的事务内UPDATE，最终全部回滚；
- Cash DDL/DML：0；
- Supabase RPC调用：0；psql中直接SELECT只读candidate/preview，R0探针直接调用写函数但全部在首阶段拒绝，成功写入0。

没有禁用trigger，没有修改writer、preview、generate或Cash业务逻辑。

## 7. School/Cash前后基线

正式cutover事务使用完整JSON fingerprint比较全部既有School业务表；postdeploy独立验证重点count/hash，均未变化：

| School对象 | count | 前后hash |
|---|---:|---|
| lesson（含229 actual） | 626 | `c4f892d857fe674e4060f80d6af56b42` |
| tuition bill | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| billing identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| bill lesson relation | 121 | `09dfee7d8833e09384fb41a84f2959e0` |
| migration batch/item | 2 / 118 | `18e74c21ebf95fdf80bed6767a4e28be` / `23a2f93d0db01d84ba6195573ec58790` |
| student settlement | 15 | `7925cf3018bd0e669cd29710f6593238` |
| settlement adjustment | 5 | `4bce2b158d4de769d592a2d367881868` |
| School account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| wage lock/detail | 95 / 556 | `7bbe108d3ac73d4f21530793bf141bc6` / `6204dc666b3b8e0f64fac901ecf0686a` |
| override audit | 0 | `d41d8cd98f00b204e9800998ecf8427e` |

五个R1D-B收费归属字段仍各118条非NULL，`scheduled_lesson_date`仍全库NULL；118条字段、两个decided_at和229 actual完整JSON未变化。

| Cash对象 | count | 前后hash |
|---|---:|---|
| external request | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| CNY transaction | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| JPY transaction | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

Cash只执行SELECT，数据库零写入。

## 8. R0与停止边界

最终gate：

- `student_tuition_preview = validation_preview_only`；
- `student_tuition_generate = blocked`；
- `student_tuition_cash_submit = blocked`。

四个学费生成/收入入口、Cash gate及事故Cash入口均继续拒绝，没有账单、income、relation或Cash request写入。preview仍只进行validation preview，没有解除R0。

本阶段没有处理229 actual继承、`scheduled_lesson_date`、6条pending_makeup、writer或其他数据阶段；没有修改API/page；没有启动下一阶段。

## 9. 错误与修正披露

第一次补充只读inventory事务已完成函数元数据和160/118/42/0核心查询，随后业务实体汇总误用不存在的`school_business_entities.display_name`列而报错并使只读事务abort。实际列为`name`；修正后从头重跑完整通过。该事务为`REPEATABLE READ READ ONLY`，没有DDL/DML或数据库写入。

除此之外，ROLLBACK、正式部署、postdeploy、R0探针和Cash检查均未失败。

## 10. Git停止点

新增3个SQL和本报告，更新`docs/current-status.md`。按授权不执行`git add`、commit或push。受保护R1B临时审查文件保持未跟踪、未修改、未暂存。

建议后续精确暂存上述5个R1D-C-C-C文件，commit message：

`feat: cut over tuition candidate attribution`

本阶段在Git审查点停止，不启动writer、actual继承、scheduled date或R0解除。
