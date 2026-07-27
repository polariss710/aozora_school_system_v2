# School V2 学费链 P0：R1D-A 日期语义与收费归属模型只读调查及设计

- 调查日期：2026-07-28
- 调查基线：`main` / `210bd372ee00bbc80165fbeebf49b5ddead1104c`
- 阶段性质：严格只读调查与设计
- 数据库变更：永久 DDL 0；School 业务 DML 0；Cash DDL/DML 0
- R0 gate：`validation_preview_only / blocked / blocked`
- 实施状态：R1D-A业务规则已确认；未开始R1D-B；停在Git审查点

## 1. 结论

当前不能把 `school_lesson_records.year_month`解释成单一月份，也不能把 `lesson_date`统一解释成“实际上课日”：

1. planned 单条新增和导入通常把 `lesson_date`当排课日，`year_month = month(lesson_date)`；
2. 自 commit `18e181479e8b51bb73c2cca0d0cf8a8aa9ff7870` 起，现行批量 planned 生成器把命中的课程日期归一化为该周周一，再把该周一写入 `lesson_date`并据此写 `year_month`；
3. 普通 actual、取消 actual、部分完成 actual 通常把 `year_month`继承为来源 planned 的学生归属月，而 `lesson_date`为实际发生日、`teacher_settlement_month`为发生日自然月；
4. 现行课时余额补课入口则把新 actual 的 `year_month`和 `teacher_settlement_month`都写为完成日期月；
5. 历史导入 actual 还存在 `teacher_settlement_month IS NULL`并由工资流程回退到 `year_month`的兼容语义。

因此，`year_month`目前至少混合表达 planned 计划月/周归属月、actual 学生结算归属月、历史导入日期月和补课完成月。它不能继续作为学费收费月、学生月结月和老师工资月的共同权威字段。

业务负责人已确认采用“方案 B + 方案 C”的组合模型，并确认以下最终规则：

- 学费严格按完整自然周归属，自然周为周一至周日；
- `billing_week_start_date`是独立、明确且冻结的收费周周一，不由预计上课日期推导；
- `billing_month = month(billing_week_start_date)`，数据库/API必须生成或校验这一唯一合法组合；
- 2026-07-27至2026-08-02只属于2026-07学费；2026-08-31至2026-09-06只属于2026-08学费；
- 同一跨月自然周不得在相邻收费月重复成为候选、bill lesson或月度统计记录；
- 每条planned的`billing_month`与`billing_week_start_date`必须显式、可审计地冻结；特殊业务只允许走受控DB override；
- canonical identity / normalized bill lesson / bill JSON已存在时，历史收费事实永远优先，不按当前lesson字段重算或改写；
- planned的`student_settlement_month`默认跟随冻结的`billing_month`；actual、取消、部分完成及补课完成继承来源planned的`student_settlement_month`；
- actual的实际完成日期只用于履约和课程表，`teacher_settlement_month`继续按actual实际发生月份；
- planned预计上课日期和时间只用于排课及课程表，可以编辑，但不得隐式修改`billing_month`、`billing_week_start_date`或`student_settlement_month`，也不改变课时管理月份归属或状态标识；
- 前端不得决定或校验持久化收费月份/收费周/学生结算月，必须由DB/API权威返回或fail-closed拒绝。

R1D-A的业务决策已闭合。本轮只更新设计文档，不实施字段、约束、writer或筛选切换；R1D-B仍需单独授权。

## 2. 调查范围与方法

已读取并交叉核对：

- `AGENTS.md`、`docs/current-status.md`；
- R0、R1A、R1B、R1C-A、R1C-B、R1C-C-A、R1C-C-B报告；
- 学费、课时、跨月补课、lesson credit、学生月结、老师工资、周课表、报价计划相关设计；
- lesson / tuition / settlement / wage 的 SQL、RPC、API wrapper 和 page 调用链；
- Git 历史，尤其是 `18e1814`“use week monday dates for planned lesson batch”、`1356dc4`报价计划周一规则、`648ef40`周运营/credit流程、`662896b`R1C-B候选规则；
- School/Cash 当前 schema、column、constraint、trigger、index、function signature/hash；
- School/Cash 当前业务表 count/hash；
- 新增并执行的 SELECT/DO-only 审计：`sql/current/school_tuition_r1d_a_date_semantics_inventory_readonly.sql`。

未调用任何写 RPC，未执行 DDL/DML，未创建临时数据库对象，未运行账单生成、收入生成或 Cash 提交。

## 3. 数据库只读审计结果

### 3.1 课时全表

| 类型 | 总数 | `year_month = date月` | 不等 | `year_month = 当前lesson_date推导周一月` | 不等 | edited | voided | non-billable | makeup状态 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| actual | 229 | 220 | 9 | 224 | 5 | 95 | 0 | 11 | 16 |
| planned | 397 | 397 | 0 | 393 | 4 | 166 | 0 | 0 | 27 |

其他结果：

- `lesson_date`为 NOT NULL；非法/空 `year_month`为0；
- 229条 actual 均有可解析的来源 planned；
- 1个 planned 关联2条 actual：`f759623b-ce28-4c5f-8556-95c4381b6b1b`；仅报告，不处理；
- 全表有14条课程日期与 ISO 周一跨自然月；无现存闰日记录，无现存跨年周记录；
- actual 有59条 `teacher_settlement_month IS NULL`，168条明确等于发生日期月，另2条明确值与发生日期月不同；
- 9条 actual 的 `year_month`与发生日期月不同；8条 actual 的 `year_month`与来源 planned 月不同；这些历史组合证明现字段不是统一公式。

本节的“周一月”仅是R1D-A对旧 `lesson_date`的只读模拟维度，不是新模型的收费周来源。最终业务规则使用独立冻结的`billing_week_start_date`；预计上课日期不得决定该字段。

### 3.2 planned 来源差异

当前397条 planned 按来源粗分：

| 来源 | 行数 | 批次数 | 说明 |
|---|---:|---:|---|
| `lesson_planned_batch_generator` | 202 | 8 | 多版本历史混合；现行版本保存周一，但较早批次仍含非周一日期 |
| 其他 import/batch | 119 | 10 | 主要保存文件/历史给出的日期 |
| manual/legacy | 76 | 0 | 保存用户或旧流程给出的日期 |

现行批量生成 SQL 明确执行：

```sql
week_monday = lesson_date - ((extract(dow from lesson_date) + 6) % 7)
year_month = to_char(week_monday, 'YYYY-MM')
```

页面预览也有 `mondayOfDateInputValue(...)`，但正式 RPC 会重新计算，因此页面只是非持久化预览，不是数据库权威。旧批次早于或跨越多版实现，不能仅凭 `import_source`假定其日期就是周一或实际排课日。

### 3.3 121条历史 bill lesson

| relation role | 行数 | 当前日期自然月匹配 bill | 当前lesson_date推导周一月匹配 bill | 跨月周收费 | 日期/周历史证据不足 | 当前行相对R1B证据漂移 | JSON冲突 | identity冲突 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| canonical_charge | 85 | 83 | 85 | 2 | 85 | 0 | 0 | 0 |
| incident_duplicate | 24 | 24 | 24 | 0 | 24 | 0 | 0 | 0 |
| legacy_cancelled | 12 | 12 | 12 | 0 | 12 | 0 | 0 | 0 |

结论分两层：

- 收费事实可高置信确认：121/121 normalized relation 与9张 bill JSON 的 ID、line_no、billing month稳定对应；7条 canonical identity 无冲突；85/24/12均被当前R1C-B规则排除，不会重新成为候选。
- 排课日期事实不能高置信回填：121/121 的 `scheduled_lesson_date_snapshot`和 `week_start_date_snapshot`均为 NULL；R1B `source_snapshot.current_planned_lesson`只是回填时当前行的中等置信证据，不是账单生成时冻结的排课日期。

因此，可以永久保留已有 `billing_month_snapshot`，但不能把当前lesson日期倒灌成121条关系的历史scheduled/week snapshot，也不能把当前lesson日期的周一推导结果冒充历史`billing_week_start_date`。

### 3.4 孙陈锋两条跨月课

| planned ID | lesson date | current year_month | 当前日期对应ISO周一证据 | canonical bill | bill/identity月 | role | 当前行MD5 |
|---|---|---|---|---|---|---|---|
| `8b737b58-cd14-42c5-afd2-34730dcef963` | 2026-08-01 | 2026-08 | 2026-07-27 | `2a9f1c25-a060-461e-ae10-b02295dec381` | 2026-07 | canonical_charge | `21f83674162b1b1ca485912a048bac3c` |
| `685ad45e-b5da-42ca-8f43-7732e8d6e40d` | 2026-08-02 | 2026-08 | 2026-07-27 | `2a9f1c25-a060-461e-ae10-b02295dec381` | 2026-07 | canonical_charge | `2d52e778bfb59a27bb3b28506232217d` |

两条的 normalized/JSON ID证据一致。新模型中的表达应为：

- scheduled date：2026-08-01 / 2026-08-02，仅作为预计上课日期；
- frozen billing week start：2026-07-27；
- schedule month：2026-08；
- frozen billing month：2026-07；
- canonical identity：2026-07，且永远优先；
- 不修改现有 planned ID、日期、`year_month`、业务归属或账单关系。

### 3.5 R1C-A 52与R1C-C-B 66

| manifest | 行数 | 自然月=当前月 | 周一月=当前月 | 自然月/周一月分歧 | week rule候选集合变化 |
|---|---:|---:|---:|---:|---:|
| R1C-A | 52 | 52 | 52 | 0 | 0 |
| R1C-C-B | 66 | 66 | 66 | 0 | 0 |

当前DB权威候选仍为：张倬闻2026-08 30、孙陈锋2026-08 22、张倬闻2026-09/10/11分别24/24/18，与两批immutable manifest精确一致。R1D-A以旧`lesson_date`模拟周一归属时不会改变这118条集合；这只是兼容性证据，R1D-B不得据此直接把旧`lesson_date`批量转换为新`billing_week_start_date`。

不在已批准manifest中的两条李天伦planned位于2026-10-01和2026-11-01，其自然月与当前日期推导周一月不同。它们属于已知异常/待审范围，本阶段不迁移、不重分类，也不因规则确认而自动获得新收费周或收费月。

### 3.6 settlement与wage

- 15条学生月结；按当前 `lesson.year_month`有187条 planned、184条 actual命中 locked settlement。
- 学生月结summary按 `lesson.year_month`同时汇总 planned收费与actual履约；这正是未来必须拆开 attribution 的耦合点。
- 普通 actual/部分完成路径通常保留来源 planned `year_month`；现行credit makeup路径使用完成日期月。学生结算月写法不一致。
- 工资候选优先 `teacher_settlement_month`，NULL时回退 `year_month`；工资锁自身使用 `school_teacher_wage_locks.settlement_month`。
- 182条active工资明细的冻结 `lesson_date`相对当前 lesson日期漂移0，业务归属漂移0；但5条active明细的工资锁月与当前 `coalesce(teacher_settlement_month, year_month)`不同。五条都是历史 actual 的 `teacher_settlement_month IS NULL`，工资锁实际按发生日期月冻结，说明锁定快照必须优先，不能按当前回退公式重写。
- void工资明细存在缺失当前lesson或冻结字段漂移，只是历史审计事实，本阶段不清理。

已确认的新模型将拆开上述耦合：planned的`student_settlement_month = billing_month`；所有来源planned生成的actual及补课actual继承该`student_settlement_month`；actual发生日期不改变学生结算月；`teacher_settlement_month = month(actual occurred date)`。三种月份不得以fallback或字段更新互相覆盖。

## 4. 当前字段真实语义

### 4.1 `year_month`的实际语义

| 行/流程 | 当前实际语义 | 当前公式或来源 |
|---|---|---|
| planned 单条新增 | 排课日期自然月 | `to_char(p_lesson_date,'YYYY-MM')` |
| planned 导入 | 导入日期自然月 | DB重新按导入 `lesson_date`计算 |
| planned 现行批量生成 | 计划周周一所属月 | 先归一化周一，再 `to_char` |
| 普通/取消/部分完成 actual | 学生侧来源 planned归属月 | `actual.year_month = planned.year_month` |
| 现行credit makeup actual | 补课完成日期月 | `to_char(p_lesson_date,'YYYY-MM')` |
| 历史导入 actual | 多数为发生日期月 | import RPC按日期计算；旧数据另有例外 |
| 学生月结 | 请求/锁定的学生结算月 | settlement表自身 `year_month` |
| income | 业务归属月 | `income.year_month`，发生日另存 `income_date` |
| 账户流水 | 业务月份 | `school_account_transactions.year_month`，发生日另存 `transaction_date` |

`year_month`这个名称不能再承担“学费收费月”的新模型权威，也不能直接改名后沿用。

### 4.2 `lesson_date`的实际语义

- planned：逻辑上应表示 scheduled date，但现行批量生成器把它写成 week Monday；历史行因此既有具体排课日，也有周起点。
- actual：表示 occurred date，且工资锁详情会冻结这一日期。
- 周课表/周统计：按 `[p_week_start, p_week_start + 7)`直接筛 `lesson_date`；自然周明确以周一开始。
- PDF/Excel和详情页：展示 `lesson_date`，月筛选通常仍按 `year_month`；这会把“显示日期”和“归属月份”分开。

最终设计要求planned新增专用nullable `scheduled_lesson_date`，用于预计上课日期和课程表；预计上课时间优先复用现有`start_time/end_time`，但R1D-B实施前必须核实现有schema与全部writer。actual的`lesson_date`继续承担occurred date。旧`lesson_date/year_month`保留兼容，不能批量改写或立即改名。

`scheduled_lesson_date`与`billing_week_start_date`是两个独立事实：前者可编辑且只影响排课展示，后者是冻结的收费周归属。不得要求scheduled date位于billing week内，不得根据scheduled date编辑结果重算收费周、收费月、学生结算月、课时管理月份归属或状态标识。

## 5. 业务流调用链

| 流程 | DB function/RPC | API wrapper | page | 当前日期/月公式 | 写入/读取与风险 |
|---|---|---|---|---|---|
| 单条planned | `school_create_planned_lesson_record[_with_venue]` | `createPlannedLessonRecord` | `lesson-page.js` | DB：date月 | 写 `lesson_date/year_month`；前端只传日期 |
| 批量planned | `school_generate_planned_lessons_batch[_with_venue]` | `generatePlannedLessonRecordsBatch` | `lesson-page.js` | DB：匹配日→周一→周一月 | 页面也算周一预览；DB重算才是权威 |
| lesson导入 | `school_import_lesson_records_batch[_with_venue]` | `importPlannedLessonRecordsBatch` | `lesson-page.js` | DB：date月 | 页面预检也算月，但RPC重算并检查锁 |
| planned编辑 | `school_update_lesson_record_guarded[_with_venue]` | `updateLessonRecordGuarded` | `lesson-page.js` | planned改日期后 `year_month=date月` | 与批量生成周一语义不完全相同 |
| 普通actual | `school_create_actual_lesson_from_planned` | `createActualLessonFromPlanned` | `lesson-page.js` | student月=planned月；wage月=date月 | `lesson_date`为发生日 |
| 取消actual | `school_create_cancelled_actual_lesson_from_planned` | `createCancelledActualLessonFromPlanned` | `lesson-page.js` | student月=planned月；wage月=date月 | actual non-billable，来源变pending_makeup |
| 部分完成 | `school_create_partial_completed_actual_from_planned` | `createPartialCompletedActualFromPlanned` | `lesson-page.js` | student月=planned月；wage月=date月 | 来源形成credit |
| 补课完成 | `school_create_lesson_credit_makeup_actual`及兼容wrapper | `createMakeupCompletedActualLessonFromPlanned` | `lesson-page.js` | student/wage月均=date月 | 与普通actual学生月公式不同；不新增学费 |
| 月筛选/详情/PDF | table select + stats RPC | `fetchLessonRecords`等 | lesson/detail | 无week时按`year_month`；week时按日期范围 | PDF展示date但集合按month |
| 周运营/课表 | `school_get_weekly_lesson_operations`、week stats | lesson API | weekly/lesson pages | `[week_start, week_start+7)` | 周一由调用范围表达，未存专列 |
| 学费preview | `school_list_student_tuition_candidates`、`school_preview_student_tuition_bill` | `previewStudentTuitionBill` | `income-page.js` | scope仍用lesson `year_month`；bill证据优先排除 | DB权威，只读；R0 validation-only |
| 学费generate | `school_generate_student_tuition_bill` | wrapper保留 | 当前页面无正式可用入口 | 旧实现按`year_month` | R0 blocked，不得启用 |
| income生成 | `school_create_student_tuition_bill_income_record` | API wrapper | 当前受R0阻断 | bill月写income业务/settlement月，`income_date`独立 | 9/9历史互指；发生日不等于收费月也合法 |
| 学生月结 | summary/preview/lock RPC | `settlement-api.js` | settlement pages | lesson按`year_month`，income按`coalesce(settlement_month,year_month)` | planned费用与actual履约共用一个筛选月 |
| 老师工资 | `school_generate_teacher_monthly_wage` | `generateTeacherMonthlyWage` | wage page | `coalesce(teacher_settlement_month,year_month)` | lock/detail冻结结果；与billing独立 |
| Cash | Cash request/approve链 | income/expense API/Edge | income/Cash pages | request/transaction使用`transacted_at` | Cash发生日独立于School billing/business month |

### 5.1 已确认的目标筛选契约

- 学费月份筛选不得再与任意自然周筛选自由组合；DB/API只返回合法的`billing_month + billing_week_start_date`组合。
- `billing_week_start_date`必须为周一，且`billing_month = to_char(billing_week_start_date, 'YYYY-MM')`。
- 选择2026-08收费月时，2026-07-27周不得出现；该周只属于2026-07。选择2026-08时可出现的跨月周示例是2026-08-31至2026-09-06。
- 候选、bill lesson和收费月统计必须使用同一DB权威组合；不合法、缺失或冲突组合一律fail-closed。
- 前端只能提交DB/API返回的组合标识，不能自行拼接月份和周，也不能依据`scheduled_lesson_date`修正组合。
- 课时管理页面自身的月份归属和状态标识继续由兼容职责决定；编辑预计上课日期/时间不得隐式改变这些值。

## 6. 日期语义矩阵

| 业务概念 | 当前来源 | 当前写入者 | 当前读取者 | 可变性 | 历史冻结 | 建议权威字段 |
|---|---|---|---|---|---|---|
| planned scheduled date | planned `lesson_date`，但batch可能是周一代理值 | planned RPC/import/generator/edit | lesson/weekly/PDF | 可编辑 | 新bill relation已有nullable证据槽位，历史121为空 | planned新增nullable `scheduled_lesson_date`；只用于课程表，不参与收费/学生结算/课时管理月份归属 |
| actual occurred date | actual `lesson_date` | actual/cancel/partial/makeup/import RPC | lesson/settlement/wage/PDF | 月结/工资锁后应不可变 | wage detail冻结 | 保留actual `lesson_date`作为occurred date |
| billing week Monday | 当前未独立存储；旧batch/报价使用周一概念 | 未来planned DB writer | tuition candidate/bill/month statistics | 收费归属决定后冻结 | 新bill relation应冻结 | planned新增nullable `billing_week_start_date`，必须为周一；不得从scheduled date编辑联动 |
| planned schedule month | `month(scheduled_lesson_date)`的展示值 | 不持久化 | lesson/课程表/PDF | 随预计日期变化 | 无 | 只读派生展示，不作为收费、结算或课时管理月份 |
| tuition billing month | bill/identity/relation已明确；未收费future依赖`year_month` scope | 历史bill、未来planned DB writer/原子生成 | tuition candidate/bill/income | 与收费周一起冻结 | bill/identity/relation高置信 | planned新增nullable显式`billing_month`及source/audit；必须等于billing week周一所属月 |
| student settlement month | lesson `year_month`、settlement `year_month` | lesson RPC与settlement lock RPC | settlement与wage前置检查 | planned收费归属后冻结；actual继承 | settlement row冻结金额 | lesson新增nullable `student_settlement_month`；planned默认等于billing month，actual/makeup继承来源planned |
| teacher wage month | `teacher_settlement_month`，NULL回退`year_month` | actual RPC/import兼容 | wage API/RPC | 工资锁后不可变 | wage lock/detail冻结 | 继续使用`teacher_settlement_month`；新actual必须DB写非NULL |
| makeup source month | source planned的冻结billing/student settlement字段 | 原planned DB writer | credit/makeup/UI | 来源收费/结算后不可变 | 通过planned ID关联 | 继承来源planned，不新增可自由输入的文本副本 |
| makeup completion month | `month(actual occurred date)` | makeup RPC | lesson/wage | 工资锁后不可变 | wage snapshot | 仅表示履约/工资日期月；不覆盖继承的student settlement month |
| bill snapshot date | relation nullable scheduled/week snapshot | R1B历史回填/未来原子生成 | audit/candidate | immutable | 历史121日期为空 | future分别冻结scheduled evidence与独立billing week；两者无包含/推导约束 |
| income record date | `school_income_records.income_date` | income RPC | income/account/Cash | 财务状态后不可变 | income row | 保留，不与billing month合并 |
| Cash transaction date | Cash request/transaction `transacted_at` | Cash批准链 | Cash账本 | 批准后不可变 | Cash transaction | 保留Cash权威，不由School月份推导 |

## 7. 三种候选模型比较

### 7.1 方案A：课程自然月

`billing_month = month(scheduled_lesson_date)`

优点：直观；手工课和导入课容易理解；无需周归属概念。

缺点：与现行报价计划、现行批量生成器的周一归属规则不一致；孙陈锋两条会被算为2026-08，与既有2026-07 canonical事实相反；月末同周可能被拆入两个收费月。

方案A已被业务规则排除，既不能用于推翻历史账单，也不能作为future planned的默认收费月。

### 7.2 方案B：周一归属月

```text
billing_week_start_date = frozen ISO Monday selected by the billing plan
billing_month = month(billing_week_start_date)
```

这里的ISO Monday定义收费自然周本身，不从`scheduled_lesson_date`推导。优点：与报价计划和当前批量生成业务一致；同一自然周不会跨收费月；85条canonical当前日期证据全部匹配该口径；孙陈锋两条明确表示为2026-07收费。

边界规则已确认：月初周末课程归周一所在的前月，年初课程可归上年。DB/API必须只提供合法月份/周组合。旧`lesson_date`有时已是周一代理值，但不能据此自动回填独立收费周。

### 7.3 方案C：显式收费月

每条planned同时保存最终`billing_month`和`billing_week_start_date`；预计上课date/time仅作为独立排课信息。

优点：业务事实明确、可冻结、可审计；能兼容历史canonical事实；不会因改排课日悄悄改已确定收费周、收费月或学生结算月。

缺点：必须定义权威写入者、override权限和不可变边界；若允许前端任意传值，会制造新的双重事实。

DB/RPC根据获批规则生成并验证合法`billing_month + billing_week_start_date`组合；前端不能独立提交两项业务事实。override只接受lesson ID、期望版本、目标组合、原因和批准信息，由service-role受控RPC验证无任何bill evidence、无locked settlement、周一/月份关系合法并写immutable audit。bill生成再次校验并冻结relation snapshot。

### 7.4 已确认组合

业务已正式批准B+C：DB权威生成/校验收费周周一，planned显式冻结`billing_week_start_date`与`billing_month`，特殊业务受控override。历史canonical永远覆盖默认公式。

预计上课日期和时间与收费周独立；编辑预计信息不得联动三个业务归属字段。R1D-B仍不得直接切候选或批量回填，必须先完成加法schema、旧字段兼容职责和全部writer审查。

## 8. 字段决策

| 候选字段 | 是否新增 | 类型/nullable | 生成/写入 | 更新与冻结 | index/constraint | 历史策略 |
|---|---|---|---|---|---|---|
| `scheduled_lesson_date` | 建议planned专用新增 | `date NULL`过渡 | planned create/import/generator/edit由DB writer写；前端只提交显式预计日期 | 可编辑；不得联动收费周/月、学生结算月、课时管理月份或状态 | planned-only check与课程表索引；不与billing week建立包含约束 | 旧`lesson_date`来源混合，不盲填；按证据分类 |
| `occurred_lesson_date` | 不新增重复列 | actual现有`lesson_date` | actual/cancel/partial/makeup/import RPC | settlement/wage lock后不可变 | 现有date索引/guard | wage detail是冻结证据 |
| `billing_week_start_date` | 建议planned专用新增 | `date NULL`过渡 | DB/API从合法收费计划组合生成；不得由scheduled date编辑推导 | 与billing month/student settlement month一起冻结；override审计 | 必须为周一；与billing month组合check/unique candidate invariant | canonical优先；旧lesson date不能直接回填；relation历史NULL保留 |
| `schedule_month` | 不新增 | 只读派生`text` | `to_char(scheduled_lesson_date,'YYYY-MM')` | 随预计日期变化 | 仅展示 | 不作为任何归属回填来源 |
| `billing_month` | 建议planned专用新增 | `text NULL`过渡 | DB/API随合法billing week组合写入；不接受前端独立派生值 | 与billing week一起冻结；有bill evidence后永久不可变 | 格式check；必须等于billing week周一所属月；partial index | canonical高置信；未收费按固定manifest/证据分类，不盲填 |
| `student_settlement_month` | 建议新增 | `text NULL`过渡 | planned由DB默认等于billing month；actual/makeup继承来源planned | 来源收费归属/settlement锁后不可变 | 格式check + student/entity/month查询索引；禁止actual按发生日覆盖 | 历史按来源分high/medium/conflict；不全量猜测 |
| `wage_month` | 不新增 | 已有 `teacher_settlement_month` | 新actual由DB按occurred date写 | active wage lock后不可变 | 现有index；后续新actual要求非NULL | 历史NULL保留，lock/detail优先 |

同时建议为planned billing增加`billing_month_source`、`billing_month_decided_at`和独立immutable override audit；是否同表保存source元数据可在R1D-B schema审查时最终决定。预计上课时间优先复用现有`start_time/end_time`，但必须先核实现有column类型、nullable策略、planned/actual共享方式及全部writer，不能只改一个入口。

## 9. 长期不变量

1. `billing_week_start_date`必须为周一；收费周固定覆盖该周一至周日。
2. `billing_month = to_char(billing_week_start_date, 'YYYY-MM')`；不合法、缺失或冲突组合必须fail-closed。
3. DB/API只能提供合法的billing month/week组合；月份筛选和自然周筛选不能自由拼接。
4. 同一跨月自然周不得同时进入相邻月份的candidate、bill lesson或收费月统计。
5. `scheduled_lesson_date`和预计上课时间是独立、可编辑的排课事实；无需位于billing week内，也不得改变billing/student settlement归属或课时管理月份/状态。
6. billing/student settlement/teacher wage month均满足`YYYY-MM`，但三者不能以fallback或字段编辑隐式覆盖。
7. planned `student_settlement_month = billing_month`；actual/cancel/partial/makeup继承来源planned；`teacher_settlement_month = month(actual occurred date)`。
8. canonical billing identity保持一学生一收费月唯一；一个planned最多一个canonical收费身份。
9. normalized relation与bill JSON同时存在时必须一致，冲突fail-closed。
10. 已有任何bill lesson/JSON证据后，lesson当前日期或月份不能改变历史billing归属。
11. candidate不得包含任何canonical、incident、legacy或兼容JSON bill evidence。
12. actual/cancel/makeup不会自动产生额外学费；学费只消费planned billing identity。
13. 新bill lesson必须一次冻结scheduled evidence、独立billing week、billing month、数量、时长、单价、金额和源版本。
14. 学生settlement lock和teacher wage lock各自冻结，不因新字段上线自动回写。
15. 前端不能计算并提交持久化billing week、billing/student settlement/teacher wage month；只能使用DB/API返回的合法组合。
16. override只能通过受控DB入口，验证无历史bill evidence/锁定链、组合合法并写immutable批准证据。
17. 一个planned在任何时点只能属于一个有效candidate billing month/week组合；冲突或NULL在正式生成时fail-closed。

## 10. 兼容与分阶段建议

### R1D-B：最小加法型schema

在R0继续blocked下：

- 增加planned专用nullable `billing_month`、`billing_week_start_date`、`student_settlement_month`、`scheduled_lesson_date`及必要source/decided_at/override audit；
- 增加月份格式、billing week必须为周一、`billing_month = month(billing_week_start_date)`等check，以及必要partial index和只读语义view；
- DB/API提供或验证合法的billing month/week组合，拒绝任意月份与自然周自由拼接；
- 核实旧`lesson_date`的兼容职责、`scheduled_lesson_date`的所有写入入口，以及`start_time/end_time`能否安全复用预计时间；
- 明确scheduled date/time编辑不得修改billing week/month、student settlement month、旧月份归属或状态；
- 不回填121条relation日期快照，不切候选，不修改现有writer行为；
- schema rollback只移除本阶段全新且仍为空/未引用的对象；任何历史表字段撤销必须先证明无写入。

R1D-B只做加法型兼容结构；即使业务规则已确认，也不能在同一阶段直接批量回填、切换候选或启用正式生成。

### R1D-C：只读模拟与安全回填

- high：canonical identity/relation的billing month；已锁定settlement/wage自身快照；
- medium：R1B当前lesson snapshot、旧planned date，以及有固定业务计划证据但尚未冻结新字段的future planned；
- conflict：多个字段给不同归属、现有active wage month drift、一个planned多actual等；
- unavailable：121条历史scheduled/week bill-time日期。

只回填获批准且逐行证据充分的字段；不得从预计上课日期推导收费周。relation历史日期NULL永久允许保留。rollback使用固定manifest和完整前后hash，不动态选对象。

### R1D-D：写入口切换

- planned单条、batch、import统一由DB分别返回scheduled date/time和独立冻结的billing week/month/student settlement权威值；
- scheduled date/time编辑入口只更新排课字段，不联动任何归属字段；
- actual/cancel/partial/makeup统一继承来源planned的student settlement month，teacher wage month按实际发生月；
- tuition preview按DB提供的合法billing month/week组合查询，同时继续永久排除bill evidence；
- settlement/wage分别只读自己的权威字段；
- API/page只展示，不派生持久化月份；
- 每个writer单独rollback测试与白名单测试，R0 generate/cash gate仍blocked。

### R1D-E：约束收紧

仅在新writer稳定、历史分类完成后：

- 对新planned要求billing week/month/student settlement month非NULL，并收紧合法组合与不可变约束；
- 对新actual要求teacher settlement month非NULL；
- 加不可变/OLD+NEW双端一致性constraint trigger；
- 原子账单生成必须在R1D-D/E的日期字段、冻结snapshot和fail-closed候选稳定后才能开始；解除R0 gate需另行授权。

不得自动回写：121条缺失的历史scheduled/week snapshot、void工资快照、李天伦异常、一个planned多actual、无法证明来源的旧 `lesson_date`。

## 11. 十五个问题的明确回答

1. 当前 `year_month`有哪些语义？planned日期月/批量周一月、actual来源学生月、历史导入日期月、credit makeup完成月；另有settlement/income表各自业务月。
2. planned和actual是否需要不同日期字段？需要。planned新增专用nullable `scheduled_lesson_date`；actual继续以现有`lesson_date`表达occurred date；旧字段兼容职责在R1D-B进一步设计。
3. 自然周是否以周一开始？是。当前batch、weekly RPC、week filter、报价计划和Git历史均明确周一。
4. 默认billing month由什么决定？已确认由独立冻结的billing week周一所属月决定；DB/API生成或校验，前端不得自行组合。
5. 孙陈锋两条如何表示？scheduled=8/1、8/2；frozen billing week=7/27；frozen billing/student settlement month=7月；canonical事实不变，scheduled编辑不影响归属。
6. billing month是否必须显式冻结？是，且必须与`billing_week_start_date`作为唯一合法组合一起冻结并随bill lesson保存。
7. week_start存储还是计算？收费周使用planned专用nullable `billing_week_start_date`显式冻结；不得由scheduled date编辑推导。课程表周范围可继续按排课日期计算，但不是收费事实。
8. 121条relation能否安全回填？billing month已安全；scheduled/week snapshot不能安全回填，121条均缺bill-time日期证据。
9. 52+66是否变化？不变；旧字段只读模拟118/118一致，但新billing week仍须按固定业务证据冻结，不能由旧lesson date动态回填。
10. 三个月份如何分离？planned `billing_month`与`billing_week_start_date`冻结；planned student settlement默认跟随billing，actual/makeup继承；teacher settlement只按actual发生月，各自独立。
11. 哪些字段新增？建议nullable `billing_month`、`billing_week_start_date`、`student_settlement_month`、planned专用`scheduled_lesson_date`及billing source/decided_at/override audit。
12. 哪些不应新增？不新增重复的actual occurred date、持久化schedule month或重复wage month；预计时间优先复用现有字段，但实施前必须全链核实。
13. 哪些历史行不能安全回填？121条relation的scheduled/week快照、来源不明旧planned日期、历史NULL/漂移工资月、李天伦异常与多actual链。
14. 原子生成前必须完成什么？加法schema、合法month/week组合、证据分类/安全回填、新writer切换、scheduled与billing彻底解耦、bill snapshot冻结、OLD/NEW约束与全链rollback测试。
15. R1D-B最小范围？四个nullable字段、source/override审计、合法组合check/API、partial index、只读兼容view，以及旧date/time字段和全部writer核查；不回填、不切候选、不解除R0。

## 12. 基线与零写入证明

### School

| 表/范围 | count | hash |
|---|---:|---|
| tuition bills | 9 | `9ee93472fdac490897b8b837b174bbaa` |
| income | 42 | `6c70d924bc4de7ce3817f0f125a6c302` |
| billing identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| bill lesson | 121 | `09dfee7d8833e09384fb41a84f2959e0` |
| lesson全表 | 626 | `4fb1901c888d56cb29c05e387490ca75` |
| planned | 397 | `b11602c7d2b1bf3c87d9d4c3763c0b3e` |
| actual | 229 | `fe752c448bb4d38af498136d3149f14a` |
| migration batch/item | 2 / 118 | `18e74c21ebf95fdf80bed6767a4e28be` / `23a2f93d0db01d84ba6195573ec58790` |
| Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| settlement | 15 | `7925cf3018bd0e669cd29710f6593238` |
| wage lock/detail | 95 / 556 | `7bbe108d3ac73d4f21530793bf141bc6` / `6204dc666b3b8e0f64fac901ecf0686a` |
| feature gates | 3 | `da00c76d8f8c72dd2decdac8ab6125b8` |

9张bill与9条income仍为9/9 `bill.income_record_id ↔ income.tuition_bill_id/source_id`精确互指。2026-08 bill的 `income_date`可在2026-07，证明收入发生日期与billing month本来就是独立事实。

### Cash

| 表 | count | hash |
|---|---:|---|
| request | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| CNY transaction | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| JPY transaction | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

Cash request/transaction使用独立 `transacted_at`；本阶段只读取schema和基线。调查前后已用同一表达式复核，count/hash完全一致，无本阶段数据库写入。

## 13. 业务规则确认与Git停止点

本阶段没有发现 normalized/JSON冲突、R0 gate变化或候选重新收费风险；只读审计assertion全部通过。

业务负责人已经确认：

1. 收费自然周为周一至周日，跨月周统一归周一所在月；
2. `billing_month + billing_week_start_date`必须由DB/API生成或验证为唯一合法组合；
3. scheduled date/time与billing week/month完全独立；
4. planned student settlement month默认跟随billing month，所有来源actual/makeup继承；
5. teacher settlement month继续按actual实际发生月；
6. 历史canonical证据优先，121条缺失snapshot继续保持NULL。

R1D-B仍需进一步设计旧`lesson_date`兼容职责、`scheduled_lesson_date`写入入口和预计时间字段复用方案，但不得再让预计上课日期决定收费月。本轮停在Git审查点：不连接数据库、不修改审计SQL、不暂存、不提交、不push，也不启动R1D-B。
