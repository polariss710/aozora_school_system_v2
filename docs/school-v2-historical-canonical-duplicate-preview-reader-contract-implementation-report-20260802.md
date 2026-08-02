# School V2 历史canonical账单重复生成提示reader合同修正实施报告

日期：2026-08-02

## 结论

`school_get_student_tuition_validation_preview_details(uuid,text,numeric)`已按业务负责人批准的reader authority合同完成最小替换。validation preview仍以`school_student_tuition_billing_identities`作为唯一身份权威；identity存在时按`atomic_charge`与`historical_backfill`分支严格验证完整canonical bill/income/relation链。完整链统一返回`R2_F_B_ALREADY_BILLED`，任何残缺、重复、孤儿、状态无效、关系不一致或validator失败继续返回`R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE`。只有不存在identity且不存在canonical收费链时才进入原candidate snapshot流程。

陈加恩2026-08旧合同判定冲突的原因不是账单链残缺，而是其唯一identity来源为`historical_backfill`，旧reader硬性要求`identity.source = atomic_charge`及Atomic generation source/manifest。其现有identity、canonical bill、received income和12条normalized relation实际完整，三个既有validator全部通过。本次不修改、不补造、不迁移任何历史收费事实，仅修正validation preview的读取分类。

## Reader分支合同

### `atomic_charge`

原Atomic合同完整保留：唯一identity、唯一canonical bill、唯一有效income、学生/业务归属/月一致、bill/income双向关系一致、`income_created` bill、`pending`或`received` income、无cancel/reverse/incident/exclusion、冻结汇率/金额/carryover一致、generation/candidate/carryover manifest一致，且identity、bill-income、bill-lessons三个validator全部通过。

### `historical_backfill`

仅在以下条件全部成立时归类为已生成：

- `student_id + billing_month`只有一个billing identity，source精确为`historical_backfill`；
- identity指向唯一`canonical_charge` bill，bill学生、业务归属、月份与输入及学生主档一致；
- bill状态精确为`income_created`，未cancelled、incident locked或cash blocked；
- bill关联唯一tuition income，income与bill的`source_id`、`tuition_bill_id`、`income_record_id`双向一致；
- income学生、业务归属、`year_month`、`settlement_month`与目标账单月一致；
- income状态为`pending`或`received`，且未cancelled、reversed、incident、operational excluded或cash blocked；
- bill/income JPY金额一致，bill冻结汇率及CNY金额内部一致；
- identity、bill/income及normalized bill-lessons三个既有validator全部通过；
- 不要求历史identity、bill或income补造`student_tuition_atomic_generate_v1`、generation manifest或Atomic snapshot字段。

`historical_backfill`不是fallback或第二权威。不存在identity时不会扫描历史JSON推断“已生成”；identityless canonical bill/income只会触发fail-closed。

## Fail-closed条件

以下任一情况继续返回`R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE`：identity重复；identity缺bill；bill缺income；重复canonical bill或重复关联income；source不是`atomic_charge`/`historical_backfill`；student、business entity或month不一致；bill/income双向关系不一致；bill不是`income_created`；income不是`pending`/`received`；cancelled、reversed、incident、cash blocked或operational excluded；JPY金额或冻结CNY内部不一致；normalized relation不完整；任一既有validator失败；identityless历史bill/income；任何需要猜测、JSON fallback或基础表前端推断的链。既有check constraints继续使`voided` bill和`rejected` income状态不可写入。

## Rollback-only测试矩阵

cutover使用固定`f2fe...`白名单学生与`codex-test historical canonical preview reader`标记，在保存点内执行24项矩阵，然后`ROLLBACK TO SAVEPOINT`：

1. 正常candidate金额及manifest重复调用稳定；
2. 无identity且candidate为空继续`CANDIDATES_EMPTY`；
3. 完整`atomic_charge`链返回`ALREADY_BILLED`；
4. 完整`historical_backfill + pending`返回`ALREADY_BILLED`；
5. 完整`historical_backfill + received`返回`ALREADY_BILLED`；
6. 重复historical identity由唯一约束拒绝；
7. identity缺bill由FK拒绝；
8. bill缺income fail-closed；
9. 重复canonical bill由唯一约束拒绝；
10. 重复关联income由约束拒绝或reader fail-closed；
11. bill/income反向关系不一致fail-closed；
12. student不一致fail-closed；
13. business entity不一致fail-closed；
14. billing month不一致fail-closed；
15. normalized relation额外/不完整fail-closed；
16. lesson validator失败fail-closed；
17. cancelled bill无效；
18. cancelled income无效；
19. reversed income无效；
20. incident chain无效；
21. `voided`/`rejected`由既有status check拒绝；
22. identityless历史bill不得作为fallback；
23. candidate reader、snapshot、atomic core、public wrapper及Gate不变；
24. fixture writer capability严格限定当前测试事务，并由保存点rollback清除。

最终同字节rehearsal及正式部署矩阵均24/24通过，fixture残留0。前两次SQL rehearsal分别因测试硬编码金额期望错误、以及测试尝试在存在deferred trigger事件时切换trigger而安全失败；两次事务均完整回滚。最终测试采用DB权威金额`candidate 1 / 3课次 / 2小时 / JPY2,400 / CNY120.00`，并移除trigger切换，不更新或删除immutable relation。

正式部署fixture：

- 学生：`f2fe0000-0000-4000-8000-00000000a001`至`a004`；
- lessons：`56a18bd3-e269-422a-9b96-c64cf77372cd`、`cdfe314b-287b-41b1-8f46-7f9f33135dea`、`9cf356d6-e384-4aa2-87ed-600f0db34dd4`；
- atomic bill：`75f56d79-8714-4f5d-9c0b-cb35118e2629`；
- historical bill/identity/income/relation：`f2fe0000-0000-4000-8000-00000000b002`、`f2fe0000-0000-4000-8000-00000000d002`、`f2fe0000-0000-4000-8000-00000000c002`、`f2fe0000-0000-4000-8000-00000000e002`。

以上全部已回滚，数据库中均不存在。

## 真实只读验收

- 陈加恩2026-08：部署前`R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE`，部署后`R2_F_B_ALREADY_BILLED`；
- 陈加恩2026-09：部署前后均为`R2_F_B_CANDIDATES_EMPTY`；
- 孙陈锋、张倬闻、彭宇晗、李天伦、袁振轩、陈红卓2026-08：部署后全部继续`R2_F_B_ALREADY_BILLED`；
- 真实Chrome页面：陈加恩8月显示“该学生本月学费账单已生成，不能重复生成。”，9月显示“该学生本月没有可生成学费账单的课程。”；
- 真实页面仅调用preview，未点击或调用generate。

正常candidate fixture的两次连续preview完整JSON相同，正式矩阵值为1 candidate、3课次、2小时、JPY2,400、CNY120.00，generation manifest为稳定64位SHA-256。candidate reader与generation snapshot函数指纹未变，因此candidate选择、金额及manifest算法未变。

## 函数、Gate和业务数据指纹

| 函数 | 部署前MD5 | 部署后MD5 |
|---|---|---|
| validation preview | `c90ce637c055b7322f278d89ff9fbed6` | `6c5f083d2151f43d48bcb3b7d0cc9dfe` |
| generation snapshot | `083bcb58c2b92f34ded07dceafbbbbfe` | 同前 |
| atomic core | `b88f6d960d920c10b914fe8e58cf38cb` | 同前 |
| public atomic wrapper | `36bdadc9af59637c9d336ce68d9afb4c` | 同前 |
| candidate reader | `65e718ba8d2e4cb46ebb0dc84b11bc2e` | 同前 |

| 业务表 | 前后行数 | 前后整行MD5 |
|---|---:|---|
| `school_income_records` | 49 | `76dfc996acdf1dca834d7b6cb75af8be` |
| `school_lesson_records` | 706 | `9b1644dbb1605164c5c3672106d6ba9f` |
| `school_student_tuition_bill_lessons` | 236 | `3d064537a43cc38392277f364c32f138` |
| `school_student_tuition_billing_identities` | 14 | `dd6b170ed6eb60d72db72975dd197d4e` |
| `school_student_tuition_bills` | 16 | `66efdf2de6cf5ec906eb6879ccb2ae52` |

Gate前后均为`student_tuition_preview = enabled`、`student_tuition_generate = enabled`、`student_tuition_cash_submit = blocked`。真实bill、income、identity、relation、lesson新增或修改为0。

## 数据库执行情况

正式执行：

- `sql/current/school_tuition_historical_canonical_duplicate_preview_reader_cutover_20260802.sql`

由cutover执行并全部回滚：

- `sql/current/school_tuition_historical_canonical_duplicate_preview_reader_rollback_tests_20260802.sql`

SELECT-only执行：

- `sql/current/school_tuition_historical_canonical_duplicate_preview_reader_postdeploy_20260802.sql`

定向rollback工件：

- `sql/current/school_tuition_historical_canonical_duplicate_preview_reader_rollback_not_executed_20260802.sql`

定向rollback仅以`commit=0`完成事务演练并整体ROLLBACK；正式rollback未执行，未来`commit=1`必须重新获得业务负责人授权。Cash DB未连接，Cash RPC调用及写入为0。

## Business-model expansion declaration最终结果

New tables、columns、enum/status、date/month/attribution、identity、source、snapshot/version、writable facts、writer authority、mutability、locking、authoritative sources、fallback、dual read/write及destructive schema changes均为none。

唯一非none项目：validation preview reader authority允许既有`historical_backfill` billing identity在完整、唯一、状态有效且三个既有validator全部通过时，归类为历史canonical已生成账单。Historical reinterpretation仅确认该既有canonical链的preview阻断分类；不修改或补造历史事实。该对象和语义已由本任务业务负责人明确批准，Gate通过。

本阶段完成后停在commit前审查点，不执行`git add`、commit或push。
