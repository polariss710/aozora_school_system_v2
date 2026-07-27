# School V2 学费链 P0：R1D-B 最小加法型日期与收费归属 Schema 实施报告

- 实施日期：2026-07-28（JST）
- 实施基线：`main` / `d9c97270f0186f1409e26a6ba5dbba3150deb959`
- 阶段范围：加法型schema、约束、只读helper/view、空override审计
- School业务DML：0
- Cash DDL/DML：0
- R0 gate：`validation_preview_only / blocked / blocked`
- 状态：数据库实施和验收完成，停在Git审查点；未开始R1D-C

## 1. 结论

R1D-B已按R1D-A批准模型完成最小加法型部署：

- `school_lesson_records`新增6个nullable、无default字段；626条既有lesson的6字段全部保持NULL；
- 部署7个validated check，保证月份格式、billing pair完整、ISO周一、月份与周一致、planned专用字段和source元数据完整性；
- 新增`school_iso_week_start(date)`和`school_is_valid_tuition_billing_period(text,date)`两个无副作用helper；
- 新增4个lesson partial index和1个audit reader index；
- 新增service-role-only、不可写的`school_lesson_date_semantics`语义view；
- 新增0行的`school_tuition_billing_attribution_override_audit`及UPDATE/DELETE永久拒绝trigger；本阶段没有override写入口；
- 现有15个直接lesson writer、API/page、候选、月结、工资、课程表和筛选均未修改或切换；
- rollback测试、正式DDL、postdeploy、R1B/R1C-B回归和R0拒绝探针全部通过；
- 旧lesson业务列、9 bill、42 income、7 identity、121 relation、两批118条迁移审计、229 actual、月结、工资及School/Cash资金链前后count/hash一致。

本阶段没有回填、没有writer/candidate切换、没有API/page变更、没有账单/income/Cash生成，也没有解除R0 gate。

## 2. 实施前schema调查

### 2.1 `school_lesson_records`

部署前共31列、626行：397 planned / 229 actual。`lesson_type`实际只有`planned`和`actual`；status实际为planned 307、completed 274、pending_makeup 25、makeup_completed 18、cancelled 2。

关键旧字段：

| 字段 | 类型 | nullable/default | 事实 |
|---|---|---|---|
| `lesson_type` | text | NOT NULL / `actual` | 当前仅planned/actual，无DB枚举check |
| `lesson_date` | date | NOT NULL | planned与actual存在多义，R1D-B不改写 |
| `year_month` | text | NOT NULL | planned/actual/结算多义，R1D-B不改写 |
| `start_time` / `end_time` | text | NULL | planned和actual共享；各305行NULL |
| `teacher_settlement_month` | text | NULL | actual工资月；planned通常NULL |
| `planned_lesson_id` | uuid | NULL | self FK `ON DELETE SET NULL` |
| `status` | text | NOT NULL / `completed` | 实际5种值 |
| `created_at` / `updated_at` | timestamptz | NOT NULL / `now()` | UPDATE触发器维护updated_at |

现有索引12个；与新字段无重名。现有trigger均保持enabled：

1. `trg_school_lesson_actual_minutes_sync`；
2. `trg_school_lesson_inherit_schedule_venue`；
3. `trg_school_lesson_records_updated_at`。

`start_time/end_time`可继续作为预计时间的优先复用候选，但共享nullable文本、planned/actual写法和锁定影响仍须在R1D-D逐writer切换前复核；R1D-B没有新增重复时间字段。

### 2.2 writer清单

DB目录确认15个直接INSERT/UPDATE/DELETE writer，定义均未变化；直接INSERT使用显式column list，UPDATE只设置明确旧列，故6个nullable无default新字段兼容现行调用：

| 类别 | 当前入口 |
|---|---|
| planned创建 | `school_create_planned_lesson_record` |
| planned批量 | `school_generate_planned_lessons_batch` |
| planned导入 | `school_import_lesson_records_batch`；明确planned-only，不存在正式actual import |
| planned编辑 | `school_update_lesson_record_guarded` |
| venue兼容wrapper | 上述create/generate/import/update的`*_with_venue`，调用基础writer后只更新venue字段 |
| ordinary actual | `school_create_actual_lesson_from_planned` |
| cancelled actual | `school_create_cancelled_actual_lesson_from_planned` |
| partial actual | `school_create_partial_completed_actual_from_planned` |
| makeup actual | `school_create_lesson_credit_makeup_actual` |
| makeup兼容wrapper | `school_create_makeup_completed_actual_lesson_from_planned`调用core，不直接写表 |
| void/delete | `school_void_planned_lesson`、`school_delete_fresh_planned_lesson` |
| technical sync | `school_backfill_actual_minutes_from_duration`及actual-minutes trigger |

仓库仍保留一份标记“EXECUTED”的独立`school_create_cross_month_makeup_completed_actual_from_planned` SQL，但现库无该函数；当前API的同名wrapper实际转调已部署的`school_create_lesson_credit_makeup_actual`，没有调用缺失DB签名。该预存文档状态漂移与R1D-B结构无关，本阶段不修正文件或部署额外writer。

### 2.3 reader清单

| reader | 当前口径；R1D-B后仍不变 |
|---|---|
| 课时管理月筛选 | `school_lesson_records.year_month` |
| 自然周筛选/周课表 | `lesson_date >= week_start AND < week_start + 7` |
| 详情/PDF/导出 | 展示`lesson_date/start_time/end_time`，集合仍按旧month/week规则 |
| 学费候选/preview | `year_month`定义scope；normalized/JSON billing evidence优先排除 |
| 学生月结 | lesson `year_month` |
| 教师工资 | `teacher_settlement_month`，兼容路径回退`year_month` |
| API/page | 仍选择旧31列，不读取6个新字段；页面不直接写表或`.rpc()` |

因此本阶段只增加新语义存储能力，未改变任何现行页面行为或业务集合。

## 3. 最终新增字段

| 字段 | 类型 | 约束/用途 |
|---|---|---|
| `billing_month` | text NULL | planned权威收费月，合法`YYYY-MM` |
| `billing_week_start_date` | date NULL | planned权威收费周ISO周一，与month成对 |
| `scheduled_lesson_date` | date NULL | planned预计上课日期；与billing完全独立 |
| `student_settlement_month` | text NULL | planned/actual均可用的学生结算归属月 |
| `billing_month_source` | text NULL | future DB writer写入的非空白证据标签，最长100 |
| `billing_month_decided_at` | timestamptz NULL | future冻结决定时间，不冒充commit timestamp |

未新增：

- `occurred_lesson_date`：actual继续兼容使用`lesson_date`；
- `schedule_month`：未来只读派生，不持久化；
- wage month：继续使用`teacher_settlement_month`；
- 预计时间副本：优先复用`start_time/end_time`，留待writer切换阶段确认。

source元数据放在lesson表，原因是它描述同一行billing pair的冻结来源且当前结构最小；详细override证据独立进入append-only audit。当前字段均为NULL，没有枚举source值或强制billing pair必须已有source；待新writer和证据分类完成后再收紧。

## 4. 数据库约束

部署并validated的7个check：

1. `billing_month`非NULL时必须合法`YYYY-MM`；
2. `student_settlement_month`非NULL时必须合法`YYYY-MM`；
3. `billing_month`与`billing_week_start_date`必须同时NULL或同时非NULL；
4. billing week非NULL时必须ISO Monday；
5. billing month必须等于billing week周一所属`YYYY-MM`；
6. billing month/week、scheduled date、billing source/decided_at只允许planned使用；未知或actual类型只能保持这些列NULL；
7. source与decided_at同时出现，source非空白且要求billing pair存在。

`student_settlement_month`允许planned和actual使用。本阶段不增加NOT NULL、自动default、scheduled→billing trigger或最终不可变trigger；旧行和旧writer因此继续兼容。

## 5. Helper、合法组合与语义view

### 5.1 Helper

`school_iso_week_start(date)`：

- SQL、IMMUTABLE、STRICT、PARALLEL SAFE、SECURITY INVOKER；
- `search_path=pg_catalog`；
- NULL→NULL，不读业务表；
- anon/authenticated不可执行，service_role可执行。

`school_is_valid_tuition_billing_period(text,date)`：

- SQL、IMMUTABLE、PARALLEL SAFE、SECURITY INVOKER；
- NULL或格式/周一/month不合法均返回false；
- anon/authenticated不可执行，service_role可执行。

验证结果：

| pair | 结果 |
|---|---|
| `2026-07 / 2026-07-27` | true |
| `2026-08 / 2026-07-27` | false |
| `2026-08 / 2026-08-31` | true |
| `2026-09 / 2026-08-31` | false |
| `2026-12 / 2026-12-28` | true |
| `2027-01 / 2026-12-28` | false |
| 非周一 | false |

### 5.2 语义view

`school_lesson_date_semantics`明确分开：

- `legacy_lesson_date/year_month/start_time/end_time`；
- raw nullable `scheduled_lesson_date`；
- 显式命名`legacy_planned_scheduled_date_inferred`；
- actual-only `actual_occurred_date`；
- raw nullable billing week/month、student settlement、billing source/time；
- `teacher_settlement_month`。

view使用`DISTINCT`确保DB报告`is_updatable=NO`；不以`coalesce`伪造新事实。anon/authenticated无权限，service_role只有SELECT。626行新权威字段在view中仍全部NULL。

## 6. Override审计

新增空表`school_tuition_billing_attribution_override_audit`，保存：

- audit ID、planned lesson FK；
- before/requested billing month/week；
- reason、evidence、business approval；
- expected lesson updated_at、before hash；
- requested/executed actor/time；
- executed/rejected/failed状态及failure reason。

requested和before pair均使用DB合法组合校验。表由trigger拒绝UPDATE/DELETE；anon/authenticated无读写；service_role仅SELECT，INSERT也暂不开放。未来override必须由另行授权的SECURITY DEFINER受控入口以最终append-only evidence写入。本阶段表始终0行，没有真实或测试audit记录。

## 7. 索引

| 索引 | 未来明确reader |
|---|---|
| planned `(student_id,business_entity_id,billing_month)` partial | tuition candidate/month scope |
| planned `(billing_week_start_date,student_id,business_entity_id)` partial | legal billing week candidate/statistics |
| `(student_id,business_entity_id,student_settlement_month)` partial | student settlement/actual inheritance queries |
| planned `(scheduled_lesson_date,start_time,end_time)` partial | future schedule/calendar reader |
| audit `(planned_lesson_id,created_at desc)` | future override evidence lookup |

四个lesson index均只收新字段非NULL行，正式部署后为空，不把旧NULL行推断为新事实。

## 8. ROLLBACK演练

执行：`school_tuition_r1d_b_date_and_billing_attribution_rollback_tests.sql`。

流程：`BEGIN`→`\ir`正式schema文件→结构/ACL/helper/约束测试→`ROLLBACK`→对象/列/测试ID残留断言。

事务内固定测试lesson：

- `d1000000-0000-4000-8000-202607280001`：合法pair、scheduled与billing独立正向行；
- `d1000000-0000-4000-8000-202607280002`：旧writer显式列形状兼容行；
- `...0011`至`...0017`：非周一、month/week错配、pair两种单边NULL、actual填planned字段、非法month、source元数据不完整负向行。

结果：

- 正向2行在事务内通过；
- 7项负向均被check拒绝；
- helper普通周、跨月、跨年、闰年、NULL全部通过；
- view独立/NULL语义及不可写ACL通过；
- audit始终0行；
- 最终`R1D_B_ROLLBACK_TESTS_OK`；
- 回滚后3个函数、view、audit表、6列、权限与全部固定测试ID残留0；
- lesson恢复626 / `4fb1901c888d56cb29c05e387490ca75`；Cash 34/59/31哈希不变。

首次命令从仓库根路径拼接错误，psql在打开SQL文件前报`No such file or directory`；没有执行数据库语句。更正工作目录后完整演练一次通过。

## 9. 正式部署与验收

正式执行与rollback完全相同、SHA-256固定的schema SQL：

- 新nullable columns：6；
- validated check：7；
- read-only helper：2；
- lesson partial index：4；
- non-updatable semantic view：1；
- empty audit table：1；
- audit index：1；
- audit immutable trigger/function：1/1；
- comments与最小ACL。

正式输出没有INSERT/UPDATE/DELETE。6个新字段非NULL计数均为0，audit 0，旧3个lesson trigger仍enabled，所有既有writer函数定义均未引用新字段。

### 历史与候选回归

- 9 bill / 42 income / 7 identity / 121 relation；角色7/1/1，relation 85/24/12；
- 9/9 bill-income精确互指；9条原income业务哈希9/9；
- 121条relation的scheduled/week snapshot仍0/0；剔除6个新增NULL键后，121/121当前lesson JSON仍匹配R1B evidence；
- 孙陈锋8月1/2日仍为2026-07 canonical，旧日期/月份/归属不变，新字段全部NULL；
- R1C-A 52和R1C-C-B 66当前旧列JSON、original updated_at及两批118条audit完全不变；候选集合仍52/66；
- 李天伦固定11行旧列哈希逐条不变，继续未进入66迁移；
- R1C-B preview：张倬闻30/65/JPY650,000，孙陈锋22/44/JPY374,000；85/24/12历史关系继续排除。

## 10. School/Cash前后基线

新增NULL列会改变`to_jsonb(lesson)`的物理全行JSON和依赖它的raw hash。以下lesson哈希显式剔除6个新增NULL键，与部署前旧31列完全同口径；该哈希包含`updated_at`，因此同时证明业务行和时间戳未被UPDATE。

| School对象 | count | 前/后hash |
|---|---:|---|
| tuition bill | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| billing identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| bill lesson | 121 | `09dfee7d8833e09384fb41a84f2959e0` |
| lesson旧31列 | 626 | `4fb1901c888d56cb29c05e387490ca75` |
| planned旧31列 | 397 | `b11602c7d2b1bf3c87d9d4c3763c0b3e` |
| actual旧31列 | 229 | `fe752c448bb4d38af498136d3149f14a` |
| migration batch/item | 2 / 118 | `18e74c21ebf95fdf80bed6767a4e28be` / `23a2f93d0db01d84ba6195573ec58790` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| settlement | 15 | `7925cf3018bd0e669cd29710f6593238` |
| wage lock/detail | 95 / 556 | `7bbe108d3ac73d4f21530793bf141bc6` / `6204dc666b3b8e0f64fac901ecf0686a` |
| feature gate | 3 | `da00c76d8f8c72dd2decdac8ab6125b8` |

R1B兼容business hash：bill `9ee93472fdac490897b8b837b174bbaa`；income `6c70d924bc4de7ce3817f0f125a6c302`。

| Cash对象 | count | 前/后hash |
|---|---:|---|
| request | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| CNY transaction | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| JPY transaction | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

Cash只执行SELECT；Cash DDL/DML/RPC均为0。

## 11. R0 gate与入口

最终gate：

- `student_tuition_preview = validation_preview_only`；
- `student_tuition_generate = blocked`；
- `student_tuition_cash_submit = blocked`。

`school_tuition_r1b_r0_entry_probes.sql`确认两个generate重载、bill→income和legacy personal tuition四个生成入口均返回`TUITION_GENERATION_BLOCKED`；Cash gate返回`TUITION_CASH_SUBMISSION_BLOCKED`；事故income Cash入口继续拒绝。没有成功写入。

## 12. 实际执行的SQL/RPC

School SQL文件：

1. `school_tuition_r1d_a_date_semantics_inventory_readonly.sql`：部署前只读基线；
2. `school_tuition_r1d_b_date_and_billing_attribution_rollback_tests.sql`：一次完整ROLLBACK；内部执行同一schema；
3. `school_tuition_r1d_b_date_and_billing_attribution_schema.sql`：一次正式DDL；
4. `school_tuition_r1d_b_postdeploy_readonly.sql`：初始验收、补充52/66与R1B legacy JSON断言后从头复跑；均只读通过；
5. `school_tuition_r1b_postdeploy_readonly.sql`：只读回归；
6. `school_tuition_r1c_b_postdeploy_readonly.sql`：只读候选/preview回归；
7. `school_tuition_r1b_r0_entry_probes.sql`：预期拒绝探针。

另执行School/Cash显式SELECT，用于目录、writer/reader、ACL、前后count/hash和对象残留核查。未执行Cash SQL文件；Cash没有RPC调用。

调用函数：两个R1D-B只读helper、R1C-B候选/preview，以及R0 probe中的五个写入口。五个写入口全部被gate/事故guard拒绝，无成功业务写RPC。

数据库写入分类：

- rollback事务：固定2条正向test lesson和7条被拒绝的负向尝试，全部回滚；test residue 0；
- 正式School：仅系统目录/加法DDL；业务DML 0；
- override audit：真实/测试行均0；
- Cash：0写入；
- 真实lesson/bill/income/actual/settlement/wage/Cash行：0修改。

两次ad hoc SELECT在执行前/解析期分别因shell SQL引号和误写`gate_key`列名失败；均无写入，随后用正确只读查询完成核对。

## 13. 文件与SHA-256

新增：

- `sql/current/school_tuition_r1d_b_date_and_billing_attribution_schema.sql`
  - `cd94a9113fbb5bb1024771eff096ff267ee8403806dddc3fc238438e413b4d0c`
- `sql/current/school_tuition_r1d_b_date_and_billing_attribution_rollback_tests.sql`
  - `497fdead757462cbaebe6384aa7371b32a4872f91e79cd673cea595b70251eb1`
- `sql/current/school_tuition_r1d_b_postdeploy_readonly.sql`
  - `a3b66fac133feec9aed3024454bcb0ccd5c6567d8990bcd6bcd9330df4ccc190`
- 本报告。

修改：`docs/current-status.md`。

未修改API/page、现有RPC/SQL、R1A–R1D-A文件和R1B临时审查文件。

## 14. 已知兼容风险与R1D-C前置条件

1. 新增NULL列必然改变未排除新键的raw `to_jsonb(lesson)` hash；R1C-B返回的`complete_row_hash`物理值也随schema变化，但候选集合和业务列未变。后续审计必须使用明确业务列或剔除R1D-B新增键，不能把结构差异误报为业务DML。
2. 旧`lesson_date/year_month`仍多义；所有reader/writer仍读写旧字段，这是本阶段明确兼容状态。
3. planned/actual尚未写`student_settlement_month`；不能切月结或工资fallback。
4. billing pair尚未强制source元数据、不可变或非NULL；最终收紧须等安全回填和writer切换。
5. 基础lesson表现有历史ACL/RLS未在本阶段重构；DB check能拒绝非法pair，未来writer仍必须使用受控入口决定合法业务归属。
6. 121条relation历史scheduled/week snapshot必须永久保持NULL；不得由新列或当前lesson倒灌。
7. R1D-C开始前必须形成业务批准的固定ID manifest、逐行before hash、证据分级和完整rollback方案；canonical优先，冲突/未知行fail-closed；不得动态按日期批量回填。
8. 预计上课时间复用`start_time/end_time`须在R1D-D逐writer确认；不得在R1D-C顺带切入口。

## 15. Git停止点

本阶段按授权不执行`git add`、commit或push。建议审查通过后精确暂存：

```sh
git add -- \
  docs/current-status.md \
  docs/school-v2-r1d-b-date-and-billing-attribution-schema-report-20260728.md \
  sql/current/school_tuition_r1d_b_date_and_billing_attribution_schema.sql \
  sql/current/school_tuition_r1d_b_date_and_billing_attribution_rollback_tests.sql \
  sql/current/school_tuition_r1d_b_postdeploy_readonly.sql
```

不得暂存：

`docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`

建议commit message：

`feat: add explicit tuition billing attribution schema`

本报告完成后停止，等待ChatGPT与业务负责人审查；不启动R1D-C、writer切换、回填、candidate切换、原子生成或R0解除。
