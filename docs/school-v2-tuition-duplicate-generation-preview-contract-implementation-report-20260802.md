# School V2 学费账单重复生成提示最小合同修正实施报告

日期：2026-08-02

## 结论

既有validation preview先构建candidate snapshot；snapshot在candidate为0时立即抛出`R2_F_B_CANDIDATES_EMPTY`，因此后续既有bill查询永远无法区分“已生成”与“真正无candidate”。本次仅替换既有`school_get_student_tuition_validation_preview_details(uuid,text,numeric)`函数体，在snapshot之前读取唯一billing identity及canonical bill/income链：完整有效链返回`R2_F_B_ALREADY_BILLED`，残缺或冲突链返回既有`R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE`，没有既有链才继续原snapshot流程。

前端两个统一错误helper现在分别显示：

- 已生成：`该学生本月学费账单已生成，不能重复生成。`
- 无candidate：`该学生本月没有可生成学费账单的课程。`

RPC签名、返回列、candidate reader、generation snapshot、generation manifest算法、atomic core、public wrapper、generate参数、按钮状态和二次确认流程均未修改。

## Reader precedence与有效链合同

当前顺序为：

1. 读取并验证preview/generate Gate。
2. 校验学生、月份、通知汇率、学生状态及学生业务归属。
3. 按`student_id + billing_month`读取唯一billing identity，并按学生权威业务归属及月份统计atomic canonical bill/income。
4. identity存在时，验证其唯一canonical bill和唯一关联income；完整链直接返回`R2_F_B_ALREADY_BILLED`，不构建candidate snapshot。
5. identity不存在但存在atomic canonical孤儿bill/income时fail-closed。
6. 不存在既有链时，调用原`school_build_student_tuition_generation_snapshot`；candidate为0仍返回`R2_F_B_CANDIDATES_EMPTY`，candidate存在时原金额、carryover及manifest流程不变。

完整有效链要求：

- identity为唯一`atomic_charge`，学生/月与输入一致，冻结source为`student_tuition_atomic_generate_v1`；
- canonical bill唯一，学生、业务归属、月份、identity反向关系一致，角色为`canonical_charge`，状态为`income_created`，且未cancelled或incident locked；
- income唯一并与bill精确双向关联，状态为`pending`或`received`，且未cancelled、reversed、incident或operational excluded；
- identity、bill、income的generation/candidate/carryover hash、业务归属、冻结汇率、金额、结转与结算证据一致；
- 三个既有validator继续验证identity、bill/income 1:1和bill lesson/candidate manifest关系。

本次重新输入的正数汇率只做输入合法性校验；已生成链以其冻结汇率和内部一致性为准，不会因操作员之后输入不同汇率而被误判为可重新生成。

## Fail-closed矩阵

同一cutover文件先以`tuition_duplicate_preview_commit=0`完成同字节rehearsal，再以`=1`正式执行。cutover在函数替换后建立保存点，执行17项固定白名单矩阵并回滚到保存点，正式事务只提交函数定义、ACL和comment。

17项结果全部通过：正常candidate金额/manifest稳定、无identity且candidate 0、完整pending链、完整received链、identity缺bill、bill缺income、重复bill/income、学生不一致、业务归属不一致、月份不一致、income反向关系不一致、cancelled bill、cancelled income、incident链、重复identity唯一约束、输入校验顺序及writer context清洁。

数据库已有两层更早保护：identity指向不存在bill由非延迟FK拒绝；同学生/业务归属/月的第二张active bill以及同学生/月第二个identity由唯一约束拒绝。reader仍显式检查数量、孤儿income及所有可读取的残缺/冲突状态。

固定白名单学生为：

- `f2fd0000-0000-4000-8000-00000000a001`
- `f2fd0000-0000-4000-8000-00000000a002`
- `f2fd0000-0000-4000-8000-00000000a003`

正式执行中临时生成的课时为`5fddec87-a189-464b-a20f-608307ac03f9`、`9729ea60-3b55-44d5-9a80-ed7ba91ba0`，临时bill为`920b0faa-2f85-4350-9d69-f1899d2f9f22`，identity为`e68be310-6e29-4d9a-a73c-e11646627122`，income为`87a2cfa6-7a2d-4d1f-83d2-9bdabec1f710`；全部在保存点回滚，残留0。

前三次rehearsal分别在测试尝试设置无权GUC、修改immutable identity、插入受唯一索引保护的重复bill时安全失败；事务均整体回滚。测试随后改为复用现有writer context和DB约束，没有扩大权限或绕过保护。最终同字节rehearsal与正式矩阵均17/17通过。

## 正常preview与保护指纹

正常candidate fixture在相同输入下前后完整返回相同，candidate 1、课次2、2小时、JPY2,400、CNY120，generation manifest为稳定64位SHA-256。前端fixture继续证明preview state保存DB返回的`generation_manifest_sha256`，正式payload原样提交`expectedGenerationManifestSha256`，学生、月份或汇率变化清除旧preview。

部署后函数指纹：

| 函数 | MD5 |
|---|---|
| validation preview | `c90ce637c055b7322f278d89ff9fbed6` |
| generation snapshot | `083bcb58c2b92f34ded07dceafbbbbfe` |
| atomic core | `b88f6d960d920c10b914fe8e58cf38cb` |
| public atomic wrapper | `36bdadc9af59637c9d336ce68d9afb4c` |
| candidate reader | `65e718ba8d2e4cb46ebb0dc84b11bc2e` |

postdeploy只读循环验证7组真实atomic identity，全部返回`R2_F_B_ALREADY_BILLED`。未调用真实generate。

Gate前后均为：

- `student_tuition_preview = enabled`
- `student_tuition_generate = enabled`
- `student_tuition_cash_submit = blocked`

## 数据库执行与业务数据

正式执行SQL：

- `sql/current/school_tuition_duplicate_generation_preview_contract_cutover_20260802.sql`

只读执行SQL：

- `sql/current/school_tuition_duplicate_generation_preview_contract_postdeploy_20260802.sql`

由cutover保存点包含并执行、全部回滚的测试SQL：

- `sql/current/school_tuition_duplicate_generation_preview_contract_rollback_tests_20260802.sql`

保留但未执行、需重新授权的定向rollback：

- `sql/current/school_tuition_duplicate_generation_preview_contract_rollback_not_executed_20260802.sql`

测试调用了固定白名单`school_create_planned_lesson_record`、validation preview和owner-only atomic core；所有测试业务DML均回滚。真实数据只调用validation preview作只读验收。public atomic generate wrapper、Cash RPC和Cash DB均未调用。

postdeploy业务表状态为706 lesson、16 tuition bill、49 income、14 billing identity、236 bill relation；与部署前冻结的整行JSON聚合MD5逐表完全相同，分别为`d1461edbc3b4e86a87dd59223e914ae3`、`c8b3f17f4381148e26433817fa214ab8`、`682bc8fd2b13fbf58878f349e7c91a41`、`de90fc39ad1e17758c6ca95f7c882a46`、`92e869986eef9124b7ac7603d6429c4b`。保存点输出和残留检查确认真实bill、income、identity、relation、lesson新增或修改均为0。正式持久化写入仅为获批函数的系统目录定义、ACL与comment。

## 前端验证

- `node --check`：utility、income page、income app及两个fixture测试全部通过。
- 权威preview UI fixture：PASS。
- Atomic Generate前端状态fixture：18/18 PASS。
- `git diff --check`：PASS。
- 普通页面只显示中文业务提示，不显示错误码、UUID、函数名、constraint或raw SQL。
- 页面/API边界不变：page无`.rpc()`，API仍只调用validation preview和atomic wrapper；前端没有新增基础表查询。

## Business-model expansion declaration最终结果

New tables/columns/enums/date/month/identity/source/writable facts：none。字段语义、mutability、writer authority、locking、historical interpretation、fallback及dual read/write：none。唯一变化是已明确批准的reader precedence：validation preview在candidate snapshot之前读取既有billing identity及canonical bill/income链。既有链仍是唯一权威，没有新增权威来源或持久化状态。

实施阶段完成时停在commit前审查点；后续Git交付须按业务负责人批准的精确文件清单另行执行。
