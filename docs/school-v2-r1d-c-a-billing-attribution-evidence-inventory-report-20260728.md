# School V2 学费链 P0：R1D-C-A 日期与收费归属证据分级及固定Manifest只读审计报告

- 审计日期：2026-07-28（JST）
- Git基线：`main` / `504d6a91d297cc9aac3a13f5178946f57e18ff24`
- School主证据事务：`2026-07-27 18:09:23.748629+00`至`2026-07-27 18:09:26.260605+00`，`REPEATABLE READ READ ONLY`
- Cash前基线：`2026-07-27 18:03:43.770478+00`，独立`REPEATABLE READ READ ONLY`
- 最终School只读复核：`2026-07-27 18:16:03.589171+00`至`18:16:06.629422+00`；最终Cash只读复核：`2026-07-27 18:16:03.063272+00`
- DDL/DML：0 / 0；write RPC：0；数据库写入：0
- R0 gate：`validation_preview_only / blocked / blocked`
- 状态：只读证据分类与固定manifest完成，停在Git审查点；未开始R1D-C-B

## 1. 结论

R1D-C-A在不回填、不建对象、不切writer/reader/candidate的前提下完成626条lesson × 6个R1D-B字段的逐字段分类，并冻结五类manifest。核心结论：

1. R1C-A固定52和R1C-C-B固定66共118条，可以分别作为`billing_month + billing_week_start_date`及planned `student_settlement_month`的`reviewable_medium`审批组。118/118旧日期为批量周计划的ISO周一代理，month/week/helper及下游冲突模拟全部通过；它们不能据此回填`scheduled_lesson_date`。
2. 85个有历史canonical evidence的planned可高置信证明`billing_month`，但121条relation的week/scheduled snapshot仍全部NULL。当前日期推导周一恰好与canonical month一致不构成历史周证据，因此pair约束下0条可回填。
3. 113条来自明确命名、非测试planned导入的当前日期可作为`scheduled_lesson_date`的`reviewable_medium`文件级审批组；批量生成的202条周一代理、76条single/unknown及6条测试导入不自动回填。
4. 229 actual全部指向planned，但只有228个不同source；李天伦`f759...`关联两个actual，是明确`conflict`。由于本阶段没有已批准的source planned student settlement，actual建议清单为0，禁止以actual发生月代替学生结算月。
5. `billing_month_decided_at`对397 planned全部`unavailable`。migration `executed_at`、identity/relation `created_at`、lesson `updated_at`和本次审计时间都不能冒充业务决定时间。R1D-C-B若批准118条，必须由新受控批准事件产生精确`decided_at`，才能与source一起满足R1D-B成对约束。
6. 现行旧候选160条，模拟只采用新字段固定118条时为118条；42条差异全部已有actual且目标月学生月结已锁定，原因可解释，但在明确排除规则前不得切换candidate。

完整固定UUID、逐行old31 hash、建议值和字段禁止集合在`docs/school-v2-r1d-c-a-fixed-manifests-20260728.md`。本报告和manifest都不是可执行迁移SQL。

## 2. Schema、writer与reader现状

### 2.1 Schema

`school_lesson_records`共37列、626行：397 planned / 229 actual。R1D-B新增6列均nullable、无default，当前六列非NULL数均为0：

- `billing_month`
- `billing_week_start_date`
- `scheduled_lesson_date`
- `student_settlement_month`
- `billing_month_source`
- `billing_month_decided_at`

override audit为0行。7个R1D-B check、ISO周/helper、语义view和权限未改变。本轮没有用临时表或永久对象。

### 2.2 DB writer

现库静态枚举出15个直接写lesson的函数，定义MD5与R1D-B相同：planned单条/批量/导入/编辑及venue wrapper，ordinary/cancelled/partial/makeup actual，void/delete和actual minutes技术同步。所有writer仍只写旧字段，没有读取或写入6个新字段。

Git证据：commit `18e181479e8b51bb73c2cca0d0cf8a8aa9ff7870`（2026-06-29 03:03:13 +09:00）把批量生成器的匹配日期规范为ISO周一，并将该周一写入`lesson_date/year_month`。当前单条create和import保留输入日期，guarded edit会显式重写旧`lesson_date/year_month`。因此旧planned日期不能用统一规则解释。

### 2.3 Reader

现行reader全部保持旧口径：

| reader | 当前字段 |
|---|---|
| 课时管理月份 | `year_month` |
| 周课表/自然周 | `lesson_date`范围 |
| tuition candidate/preview | `year_month`scope + normalized/JSON billing evidence |
| 学生月结 | lesson `year_month` |
| 教师工资 | `teacher_settlement_month`，兼容回退`year_month` |
| API/page/PDF/导出 | 旧日期和旧31列 |

本轮没有修改任何SQL writer、API、page、课程表、月结、工资或候选函数。

## 3. 四个固定顶层cohort

四组互斥且覆盖626行：

| cohort | 行 | 学生 | planned/actual | 小时 | JPY | old31 hash aggregate |
|---|---:|---:|---:|---:|---:|---|
| R1C fixed | 118 | 2 | 118/0 | 254 | 2,474,000 | `2be63b86fd838be4d9075fb9b7e11525` |
| historical bill evidence | 85 | 6 | 85/0 | 192 | 1,824,000 | `af639bff90d07e70d9327c0d02154295` |
| other planned | 194 | 5 | 194/0 | 388.75 | 4,156,875 | `e6336c9b187cbebd17e3fdd105ed679f` |
| actual | 229 | 7 | 0/229 | 461.29 | 4,645,520 | `fe752c448bb4d38af498136d3149f14a` |

## 4. 六字段证据分类

| 字段 | approved_high | reviewable_medium | conflict | unavailable | not_applicable |
|---|---:|---:|---:|---:|---:|
| `billing_month` | 85 historical | 118 R1C | 0 | 194 other planned | 229 actual |
| `billing_week_start_date` | 0 | 118 R1C | 0 | 279 planned | 229 actual |
| `scheduled_lesson_date` | 0 | 113 named imports | 6 test imports | 278 planned | 229 actual |
| `student_settlement_month` | 0 | 118 R1C planned | 3 Li multi-chain rows | 505 | 0 |
| `billing_month_source` | 85 canonical source | 118 R1C | 0 | 194 other planned | 229 actual |
| `billing_month_decided_at` | 0 | 0 | 0 | 397 planned | 229 actual |

`approved_high`只描述单字段证据；历史85的billing month/source仍不能绕过billing pair和source/decided_at成对约束。逐行3756条分类由正式只读SQL输出。

建议稳定source code限定为：

- `canonical_billing_evidence`
- `approved_r1c_a_manifest`
- `approved_r1c_c_b_manifest`
- 后续新业务批准使用`manual_business_approval`
- 真正受控override保留`controlled_override`

本阶段不写枚举、不写source。

## 5. Billing month/week证据

### 5.1 历史121 relation / 85 planned

- relation角色：85 canonical、24 incident、12 legacy；85个不同planned均有canonical，incident/legacy只与canonical重叠，不产生第二收费月；多billing month冲突0。
- 121/121 normalized行与bill JSON顺序ID、学生、业务归属、billing month和role一致；9/9 bill-income互指正常。
- scheduled snapshot非NULL 0，week snapshot非NULL 0；R1B当前旧31列snapshot匹配85/85。
- 当前`lesson_date -> ISO Monday -> month`恰好与历史billing month匹配85/85，但不是账单时点周证据。

孙陈锋跨月两条：

| lesson | 日期 | canonical month / bill | 结论 |
|---|---|---|---|
| `8b737b58-cd14-42c5-afd2-34730dcef963` | 2026-08-01 | 2026-07 / `2a9f1c25-a060-461e-ae10-b02295dec381` | billing month高置信；week仍不以当前日期倒灌 |
| `685ad45e-b5da-42ca-8f43-7732e8d6e40d` | 2026-08-02 | 2026-07 / same | 同上 |

两条ID、日期、业务归属、2h、JPY17,000和old31 hash不变。

### 5.2 R1C固定118

| 批次 | 月份 | 行 | 小时 | JPY | 周一/helper合法 | 当前行/audit |
|---|---|---:|---:|---:|---:|---:|
| R1C-A | 2026-08 | 52 | 109 | 1,024,000 | 52/52 | 52/52 |
| R1C-C-B | 2026-09 | 24 | 52 | 520,000 | 24/24 | 24/24 |
| R1C-C-B | 2026-10 | 24 | 52 | 520,000 | 24/24 | 24/24 |
| R1C-C-B | 2026-11 | 18 | 41 | 410,000 | 18/18 | 18/18 |

118/118 migration after snapshot、original updated_at、生成批次和当前旧31列一致；bill/actual/锁定月结/工资明细冲突均0。建议R1D-C-B分成52和66两个批准单元，任一单元逐行old31 hash漂移都fail-closed。

### 5.3 其余planned 194

- named planned import：113；可进入scheduled date文件级审批，但无冻结billing pair证据。
- single/unknown：75；旧日期是预计日还是代理无法独立证明。
- test import：6；来源`测试1_2026-10.xlsx`/`测试2_2026-11.xlsx`，标为conflict。
- 上述194均不因“active/future/current state”动态进入billing pair建议。

## 6. Scheduled date证据

按来源的完整397 planned：

| source class | cohort | 行 | 周一行 | updated≠created | linked actual | 结论 |
|---|---|---:|---:|---:|---:|---|
| batch week proxy | R1C fixed | 118 | 118 | 0 | 0 | scheduled保持NULL |
| batch week proxy | historical | 84 | 66 | 50 | 39 | scheduled保持NULL |
| named import | other | 113 | 111 | 51 | 112 | medium；逐文件/编辑后状态确认 |
| single/unknown | historical | 1 | 1 | 1 | 0 | unavailable |
| single/unknown | other | 75 | 45 | 64 | 74 | unavailable |
| test import | other | 6 | 0 | 0 | 3 | conflict |

113条C manifest按10个命名文件批次冻结，before aggregate `7b07855e518030154ad81a87933e45bc`，proposed hash `430c1bd29737228f932f71314e585ebe`。51条曾更新，故不能只凭原文件名自动执行；业务批准必须确认当前日期仍是有效预计日期。scheduled date不参与billing pair推导，模拟中改变scheduled不会改变118条billing month/week。

## 7. Student settlement与actual继承

229 actual全部有source planned，228个不同source。证据分组：

| source billed | source R1C | 月结locked | active wage detail | sibling actual | actual行 |
|---:|---:|---:|---:|---:|---:|
| true | false | false | false | 1 | 39 |
| false | false | true | true | 1 | 182 |
| false | false | true | false | 1 | 4 |
| false | false | false | false | 1 | 2 |
| false | false | false | false | 2 | 2 |

没有actual来源于R1C 118。锁定月结是学生/月/业务归属级事实，不是每条actual的独立归属snapshot；在source planned billing/student settlement未获批准前不能据此自动填actual。

李天伦异常链固定为：

- planned `f759623b-ce28-4c5f-8556-95c4381b6b1b`；
- actual `c582a187-32f6-4a24-bb7b-d590b25c1854`；
- actual `dc06b98c-360f-4661-a294-52ecb82830a7`。

三行student settlement均为`conflict`，不得在R1D-C-B普通回填中处理。李天伦固定11行及独立第229条actual `50ec3900-63ff-4138-85f1-53a999c23daa`本轮只读核对，未修改。

## 8. 五类固定Manifest

| Manifest | rows | proposed hash | 下一阶段边界 |
|---|---:|---|---|
| A billing pair | 118 | `303663d375fa0a4e5281aed4af6cf041` | 分52/66批准；写入时逐UUID+old31 hash |
| B planned student settlement | 118 | `0e7344a65afaeebabea65560a76b3fa6` | 仅随已批准A写入；actual为0 |
| C scheduled date | 113 | `430c1bd29737228f932f71314e585ebe` | 按文件及编辑后状态审批 |
| D manual review | 239 unique | `19c0e66e10d9c8cbab730006d4c37cac` | A∪C∪测试导入6∪多actual 2；before hash `ade8a5c66b4a031662a4d1c0199bc9e7` |
| E no-auto-fill | 字段级覆盖626 | 空值MD5 `d41d8cd98f00b204e9800998ecf8427e` | 当前保持NULL/N/A/conflict；按旧证据永久禁推断、当前证据不足暂缓、类型不适用分层 |

Manifest A/B lesson层面重叠118但字段不同；C与A不重叠；D是审查汇总集合；E在相同字段上与A/B/C不重叠。完整UUID与逐行hash见独立manifest文件。

Manifest E的“不自动回填”不是统一的“字段永久为NULL”：一类是禁止永久使用当前旧字段、旧快照或技术时间戳作自动推断，但未来如出现新的独立权威来源仍可重新审批；一类只是R1D-C-A当前证据不足而暂缓；另一类是字段对该lesson类型`not_applicable`。尤其229条actual当前不得填`student_settlement_month`，原因是source planned尚未受控批准，并非actual应永久保持NULL。未来只能在source planned的billing/student settlement已获批准后，通过独立设计和授权的继承阶段处理；李天伦一对多actual链继续为`conflict`，必须独立处置。

## 9. R1D-B约束模拟

118条建议pair只读模拟：

- pair helper合法118/118；
- ISO周一118/118；
- month等于week所属月118/118；
- planned student settlement等于billing month 118/118；
- `2026-08 + 2026-07-27`错误组合0；
- `2026-09 + 2026-08-31`错误组合0；
- 每个planned只有一个建议month/week；
- scheduled建议不参与pair表达式；
- actual和makeup未被赋予新收费归属。

source/decided_at不完整时R1D-B约束会拒绝单边source。故本报告提出source标签但不建议使用旧时间拼出decided_at。

## 10. Candidate集合模拟

| 集合 | 行 |
|---|---:|
| 当前R1C-B旧字段candidate | 160 |
| proposed新字段candidate（仅A 118） | 118 |
| current only | 42 |
| proposed only | 0 |

42条current-only全部已有1条linked actual且对应学生/月/业务归属的student settlement已locked：

- 陈加恩2026-05：10条/20h/JPY170,000；
- 陈红卓2026-05：10条/20h/JPY170,000；
- 陈加恩2026-06：12条/24h/JPY204,000；
- 陈红卓2026-06：10条/20h/JPY170,000；
- 合计42条/84h/JPY714,000。

当前R1C-B候选只按账单证据等规则排除，并不把linked actual/locked settlement当通用排除事实；因此差异可解释，不是数据漂移。R1D-C-B不得顺手修改候选函数，后续candidate切换前必须由业务负责人确认这42条的最终收费事实和排除规则。

R1C-A 52与R1C-C-B 66均在当前和proposed集合；历史85 canonical、24 incident、12 legacy仍为0 candidate / 121 excluded。

## 11. R0与回归

- feature gate仍为preview=`validation_preview_only`、generate=`blocked`、cash submit=`blocked`。
- 本轮严格只读，没有调用四个学费生成入口、Cash提交入口或事故Cash入口；复用R1D-B最近一次拒绝探针证据，不主动触发write RPC。
- 9/9 bill-income互指；121 normalized relation与bill JSON一致；week/scheduled snapshot非NULL均0。
- 两条孙陈锋跨月canonical事实不变。
- R1C-A 52、R1C-C-B 66、两批118审计不变。
- 李天伦11行、第229条actual及229 actual整组old31 hash不变。

## 12. 执行的SQL、函数与异常记录

### 12.1 正式仓库SQL

- `sql/current/school_tuition_r1d_c_a_billing_attribution_evidence_readonly.sql`：`BEGIN ... REPEATABLE READ READ ONLY`，只含SELECT/DO只读断言/COMMIT；无临时对象。
- Cash companion使用仓库既有三表baseline SELECT，由外部只读事务包装；未新增Cash仓库文件。

SELECT中调用的只读函数：

- `school_iso_week_start(date)`；
- `school_is_valid_tuition_billing_period(text,date)`；
- `school_list_student_tuition_candidates(uuid,uuid,text,boolean)`（只读集合模拟）。

没有通过Supabase RPC入口调用函数，没有write RPC。

### 12.2 外部临时调查SQL

`/private/tmp`内使用preflight、inventory、evidence summary、candidate difference、fixed118输出、scheduled source、manifest summary、export、D/E summary和Cash baseline等SELECT-only脚本。它们没有进入仓库，不创建DB对象。

三次前置命令/查询错误均在只读边界内且无写入：

1. 首次shell用非interactive环境未加载`load_both_db`，psql只尝试本地socket且未连接目标数据库；没有执行SQL。
2. 一次inline SQL引号被shell解析，服务端在事务开始前语法错误；没有执行语句。
3. inventory首次连接后引用不存在的`business_approval`列，事务在该SELECT报错并abort；没有DML/DDL，修正为`approval_information`后只读重跑通过。

## 13. School/Cash前后基线

### 13.1 School

| 对象 | count | 前/后hash |
|---|---:|---|
| lesson raw 37列 | 626 | `3f547b5b0d9a6569057584b1021cf04a` |
| lesson旧31列 | 626 | `4fb1901c888d56cb29c05e387490ca75` |
| planned旧31列 | 397 | `b11602c7d2b1bf3c87d9d4c3763c0b3e` |
| actual旧31列 | 229 | `fe752c448bb4d38af498136d3149f14a` |
| tuition bill | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| billing identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| bill lesson relation | 121 | `09dfee7d8833e09384fb41a84f2959e0` |
| migration batch/item | 2 / 118 | `18e74c21ebf95fdf80bed6767a4e28be` / `23a2f93d0db01d84ba6195573ec58790` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| student settlement | 15 | `7925cf3018bd0e669cd29710f6593238` |
| wage lock/detail | 95 / 556 | `7bbe108d3ac73d4f21530793bf141bc6` / `6204dc666b3b8e0f64fac901ecf0686a` |
| feature gate | 3 | `da00c76d8f8c72dd2decdac8ab6125b8` |

6个新字段非NULL均0，override audit 0。raw hash显式包含6个NULL键；旧31列hash证明业务行和`updated_at`没有被UPDATE。

### 13.2 Cash

School与Cash不是跨库原子快照，分别披露：

| 对象 | count | 前/后hash |
|---|---:|---|
| external request | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| CNY transaction | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| JPY transaction | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

最终Cash只读复核时间为`2026-07-27 18:16:03.063272+00`；最终School只读复核为`18:16:03.589171+00`至`18:16:06.629422+00`。所有count/hash与前基线一致，未观察到并发漂移。

## 14. R1D-C-B建议拆分和待批准问题

建议未来独立授权、独立fail-closed事务：

1. A1：R1C-A 52 billing pair + planned student settlement + 新批准source/decided_at；
2. A2：R1C-C-B 66同上；
3. C：113 scheduled date按10个源文件及51条编辑后记录逐批确认；
4. 历史85：确认当前旧日期和缺失snapshot永久不得作为billing week自动推断来源；在出现新的独立权威来源并重新审批前，新pair保持NULL；
5. actual：等source planned获批后再设计继承；李天伦异常链必须独立处理；
6. candidate：先决定42条fulfilled/locked无bill记录的排除事实，再另阶段切换reader。

业务负责人必须明确：

- 是否分别批准52和66的billing pair/student settlement；
- R1D-C-B批准事件使用哪个精确`decided_at`，并确认source标签；
- 哪些命名导入文件及编辑后日期可作为scheduled事实；
- 历史85是否明确保持week NULL；
- 42条current-only的最终收费/候选口径；
- 李天伦一对多actual链如何由独立修复阶段处理。

本阶段结束后停止，不回填、不切换writer/reader/candidate、不启动R1D-C-B、不解除R0 gate。
