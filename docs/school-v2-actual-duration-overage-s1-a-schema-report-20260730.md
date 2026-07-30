# Aozora V2 Actual Duration Overage S1-A Schema实施与验收报告

日期：2026-07-30
阶段状态：`S1-A_SCHEMA_VALIDATED`

## 1. 业务目标与阶段边界

actual时长超过planned时，未来由数据库权威写入记录每节课的纯课时超额事实，在来源月份月结时由业务确认超额差额，并将确认后的费用转入下一个账单周期。

本阶段只建立并验收nullable schema基础，不激活actual overage业务流程。ordinary、partial、makeup actual writer、settlement reader、lock/relock、tuition candidate、API和页面均未修改；当前系统仍不会生成、汇总或收费actual overage。

业务负责人确认的后续业务口径：

- actual超额无需checkbox；
- 超额部分直接计费；
- 原账单不可修改；
- 超额费用在来源月份月结时确认；
- 确认后转入下一个账单周期；
- 业务归属统一为青空进学塾；
- 允许canonical账单之外存在补充收费身份。

## 2. Schema资产

`school_lesson_records`新增5个字段：

- `student_duration_overage_minutes integer`
- `student_duration_overage_fee_jpy numeric`
- `student_duration_overage_policy_version text`
- `student_duration_overage_source text`
- `student_duration_overage_decided_at timestamptz`

`school_student_monthly_settlements`新增6个字段：

- `duration_overage_minutes integer`
- `duration_overage_fee_jpy numeric`
- `duration_overage_fee_cny numeric`
- `duration_overage_actual_count integer`
- `duration_overage_policy_version text`
- `duration_overage_source text`

11个字段均为nullable且无default。本阶段没有历史backfill。

新增6个validated CHECK约束：

- lesson snapshot全NULL或5字段完整；
- lesson snapshot仅允许未来ordinary actual、completed、billable及批准的policy/source上下文；
- lesson分钟和JPY金额必须非负，JPY为整数，零值/正值关系一致；
- settlement snapshot全NULL或6字段完整；
- settlement只允许批准的policy/source；
- settlement分钟、actual数量及JPY/CNY金额必须非负，JPY为整数、CNY最多2位小数，零值/正值关系一致。

新增2个partial index：

- `school_lesson_records_duration_overage_month_idx`：未来按学生、业务归属和学生月结月份读取已激活的正数overage；
- `school_lesson_records_duration_overage_planned_uidx`：仅约束未来新政策ordinary actual对planned来源的幂等性，不覆盖legacy、partial、makeup、cancelled或全NULL记录。

Schema SQL SHA-256：

`ca9964e50150060105100a1526c2afa2eba0db74953583a7dbfe19ec3c427871`

Git交付规范化审计：

- 数据库实际部署使用的原始schema SHA-256：`ca9964e50150060105100a1526c2afa2eba0db74953583a7dbfe19ec3c427871`；
- Git交付文件规范化后的SHA-256：`f9bb43a8e057a04e4c2a48d126ce68f82887ed619c10e8c7a8065da857fdaade`；
- 两个文件的唯一差异是Git交付文件删除了EOF多余空行；SQL token、注释文本和对象定义均未变化；
- 该whitespace修正不改变SQL语义，schema没有重新部署；
- 数据库目录已经通过S1-A postdeploy验收，状态仍为`S1-A_SCHEMA_VALIDATED`。

## 3. 历史策略

部署没有扫描或回填历史`actual > planned`记录。已确认的19条历史记录新增字段全部保持NULL，不具备新政策收费身份，不进入未来收费链，固定策略为：

`no backfill / no collection / legacy facts remain unchanged`

19条固定投影哈希验收前后保持：

`352e72ac33d648a23be84bb27b3580d1`

## 4. 部署与验收恢复

`school_actual_duration_overage_s1_a_schema.sql`已成功执行并COMMIT，只新增上述nullable字段、CHECK约束、partial index和注释；没有正式业务DML、历史修复、backfill、function、trigger或权限修改。

首次执行`school_actual_duration_overage_s1_a_postdeploy.sql`时，函数MD5断言使用了直接内联的`IF actual_md5 <> CASE ... END THEN`结构，PL/pgSQL未能正确闭合该条件并在DO块末尾报告`syntax error at end of input`。该只读事务未完成并自动回滚，没有数据库写入。

恢复阶段将CASE结果先赋给`v_expected_md5`，再用`IS DISTINCT FROM`比较；同时补齐对象目录、业务行数和验收输出。完成dollar-quote、括号、BEGIN/END、IF、LOOP、CASE及只读写语句的离线静态检查后，仅再次执行一次修复后的postdeploy。脚本以`REPEATABLE READ READ ONLY`运行，全部断言通过并明确ROLLBACK。

## 5. Postdeploy验收结果

- lesson新增5字段全部存在、nullable、无default；
- settlement新增6字段全部存在、nullable、无default；
- 6个CHECK约束全部存在、定义一致且validated；
- 2个partial index存在，列、唯一性及谓词一致；
- overage目录仅有11个字段和2个index，无overage function或trigger；
- 原两表trigger数量/哈希及ACL不变，无grant/revoke；
- 630条lesson新增字段全部NULL；
- 15条settlement新增字段全部NULL；
- 历史19条新增字段全部NULL；
- aircon/planned fee component非NULL行仍为0；
- R0保持不变。

业务数据边界：

| 对象 | 行数 | 稳定投影哈希 |
| --- | ---: | --- |
| lessons | 630（planned 397 / actual 233） | `fd8b5570f42d618f136b2f6408704ae8` |
| settlements | 15 | `7925cf3018bd0e669cd29710f6593238` |
| tuition bills | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income records | 42 | `2a4897b752f272b1f192045418b4940c` |
| bill-lessons | 121 | `285172fedeb923c67ea9a179480d8692` |

## 6. 受保护函数MD5

| 函数 | 部署前后MD5 |
| --- | --- |
| `school_create_actual_lesson_from_planned` | `da156f6c951b233a2878ecb100b2748b` |
| `school_create_partial_completed_actual_from_planned` | `ec7bdebb8b2eacf0527c603a32650af9` |
| `school_create_lesson_credit_makeup_actual` | `eaad3fc14366af9c11cc70ba34275091` |
| `school_get_student_monthly_settlement_summary` | `87aab230b7d9cb35124eeca7899317f5` |
| `school_get_student_monthly_settlement_preview` | `7bc39abec927bc4e3c72167b29c06e8e` |
| `school_lock_student_monthly_settlement` | `6a172d58ed07d983db80972e31bd34a1` |
| `school_relock_student_monthly_settlement` | `6db55eec5e3f6601b1d7aae0835d3b58` |
| `school_list_student_tuition_candidates` | `8981a2ce07abf8c28231bfaf05451368` |
| `school_resolve_planned_billing_attribution` | `529c7387e63dcdb2e6972398c2d74dae` |
| `school_resolve_planned_duration` | `4f5b754585c9e3752639e6b0f2fa7a34` |
| `school_calculate_planned_fee_components` | `2dfabf4a920f7138043079855347207b` |

ordinary/partial/makeup writer、settlement reader/lock/relock、candidate和helper均未变化。空调费逻辑未修改、未复用；planned整数时长规则未修改。

## 7. Rollback测试

`school_actual_duration_overage_s1_a_rollback_tests.sql`仅在`pg_temp`复制表中测试约束：

- 合法lesson组合5条、合法settlement组合3条被接受；
- 非法lesson组合11条被CHECK或UNIQUE拒绝；
- 非法settlement组合8条被CHECK拒绝；
- 测试事务完整ROLLBACK；
- 没有临时或正式业务数据残留；
- rollback后再次确认lesson/settlement行数、全NULL边界和稳定投影哈希不变。

## 8. R0与停止点

R0保持：

- `student_tuition_preview = validation_preview_only`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

当前停止点：`S1-A_SCHEMA_VALIDATED`。

Schema已经部署但尚未激活，actual overage业务仍不可用。下一实施阶段继续被R1D actual writer及settlement reader的权威月份切换阻断；必须先完成该切换，才能实施overage writer、来源月份月结确认和下一账单周期逻辑。
