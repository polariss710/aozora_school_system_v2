# School V2 R2-F-F2 收费自然周不变量与空调策略中文化实施报告

日期：2026-08-01
状态：R2-F-F2与R2-F-F2-B数据库DDL、postdeploy、rollback及前端回归全部通过；`year_month`非法生产依赖为0，停在commit前审查点。

## 1. 结论

补充证据中“`student_settlement_month`被改为2026-09”的判断经数据库只读查询证伪。真实记录的三项权威收费归属一直正确：

- `billing_week_start_date = 2026-08-31`
- `billing_month = 2026-08`
- `student_settlement_month = 2026-08`

漂移的是兼容字段`year_month`：通用guarded core在编辑日期时执行`year_month = to_char(p_lesson_date,'YYYY-MM')`，因此变为`2026-09`。旧课时列表、统计和前端月份语义仍按`year_month`及`lesson_date`筛选/展示，才让正确的planned收费事实从8月结果消失并显示为9月。

本轮没有修正真实课时数据；目标课的权威收费归属、空调费和`updated_at`均保持原值。修复采用：

1. 表级trigger与validated constraints保护planned收费归属和周内日期；
2. 课时管理新增DB权威reader，planned按billing month/week，actual按R1D-E-C权威学生月；
3. 两个统计RPC复用同一reader；
4. 主课时列表、过滤统计、PDF和周课表读取不再按`year_month + lesson_date`筛选canonical planned；
5. 页面月份语义和空调策略改为中文权威展示。

commit前补充审计进一步发现主列表之外仍有8类planned生产路径及2处actual学生月结检查读取raw `year_month`。R2-F-F2-B已在既有billing attribution与R1D-E-C resolver模型内全部收口；未新增表、字段、状态、月份概念或fallback，详见第11节。

## 2. 真实异常记录与固定证据

目标UUID：`aa55dc2e-3b1b-4d2d-863f-9f64e84b8578`

- 类型/状态：`planned / planned`
- 学生/老师/科目：孙陈锋 / 王黎曦 / EJU化学
- 业务归属：青空进学塾
- 日期时间：`2026-09-06 14:00–16:00`
- `year_month`：`2026-09`（兼容日期月，不再作为planned收费筛选权威）
- 收费周/收费月/student month：`2026-08-31 / 2026-08 / 2026-08`
- attribution：`approved_r1c_a_manifest`，决定时间`2026-07-28 00:27:52.779654+00`
- 来源批次：`2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c`，batch pattern 4 occurrence 1
- migration evidence item：`f53b41d1-485e-de77-337d-4cbe4c8b39b9`
- evidence原始日期/月：`2026-08-31 / 2026-08`
- venue文本：`Regus办公室`；旧记录`lesson_venue_id/venue code`为NULL
- 空调bundle：rate 330，billable hours 2，fee 660，course total 17,660，policy v2
- candidate：2026-08 `candidate`；bill relation 0；关联locked settlement 0
- `updated_at`：`2026-08-01 00:45:21.664017+00`
- 最终整行MD5：`bcd7c6f132434929c68982d30cfae663`

保存前固定证据证明原预计日期为`2026-08-31`、收费月为`2026-08`。保存后只有预计日期及兼容`year_month`随日期变化；权威收费bundle未改变。

## 3. 写入链根因

页面编辑payload提交日期、学生、老师、科目、业务归属、时间、时长、基础金额、状态、mode、venue及显式rate；不提交billing month、billing week或student settlement month。

调用链为：

`lesson-edit-dialog` → `lesson-page/detail-page` → `lesson-api.updateLessonRecordGuarded` → 20参数`school_update_lesson_record_guarded_with_venue` → 19参数venue wrapper → `school_update_lesson_record_guarded` core。

19参数wrapper只预写标准化mode/venue。core对planned执行：

`lesson_date = p_lesson_date, year_month = to_char(p_lesson_date,'YYYY-MM')`

它不写三项权威billing字段。R1D-F1 trigger原本冻结billing bundle，但没有对所有未收费canonical planned校验新日期仍在原收费周内；R2-F-E的周界限只覆盖已收费planned。R2-E aircon trigger按新日期重算空调费，但未改收费归属。

## 4. 全库只读扫描

扫描416条planned：

- billing month与week start月份不一致：0
- lesson date在权威billing week之外：0
- week NULL但month存在：0
- month NULL但week存在：0
- student settlement month与billing month不一致：0
- partial attribution bundle：0
- 完整canonical attribution：137
- 五字段全NULL legacy：279
- 已进入bill relation：85
- 命中locked settlement范围：229
- `year_month != billing_month`：1，仅目标跨月周记录，属于兼容日期月差异，不是收费事实异常

没有“未收费且需要数据修正”的权威归属异常，也没有需要修改的bill/locked记录。目标没有override audit，attribution source/version保持不变。

## 5. 数据库不变量与reader

正式新增两个validated check：

- `school_lesson_records_planned_student_month_match_chk`
- `school_lesson_records_planned_date_within_billing_week_chk`

替换`school_enforce_r1d_f1_planned_attribution()`：

- canonical billing week/month/student month普通编辑不可变；
- canonical planned日期只能位于week start至+6天；
- 周外日期返回`PLANNED_DATE_OUTSIDE_BILLING_WEEK`；
- 试图改变收费归属返回`PLANNED_BILLING_ATTRIBUTION_IMMUTABLE`；
- 缺少结构化归属的legacy planned不得通过日期编辑静默推导，返回`PLANNED_BILLING_ATTRIBUTION_REQUIRED`；
- teacher、venue、mode、rate等既有合法操作继续由原writer/guard处理。

所有单条创建、批量生成、导入、guarded overload及直接DML最终都经过该表级BEFORE trigger。aircon trigger可以读取新lesson date并重算费用，但不能改写收费归属。

新增只读RPC：

`school_list_lesson_management_records_authoritative(text,date)`

- 月份：通过R1D-E-C权威学生月resolver选集；canonical planned显式使用billing month；
- 周：canonical planned使用billing week；actual优先使用source planned billing week；
- 缺少billing week的legacy planned不会在周查询中由lesson date伪造收费周；
- 9/10参数stats overload均复用该reader。

前端API和PDF planned读取改走该RPC。页面只验证DB返回的权威字段，不计算或写入任何收费事实。

## 6. 空调策略中文化

新增统一`plannedAirconPolicyLabel`：

- v1/v2：`周末固定办公室计费`
- 未知policy但DB有完整正费用：`按课时冻结规则计费`
- 其他：`不满足空调费条件`

课时卡片、左右配对卡片、详情页及打印复用路径均不再输出raw policy code。JS只映射文案，不计算rate、hours、fee或course total。

## 7. DDL、RPC与测试

执行SQL：

1. `school_lesson_r2_f_f2_billing_week_invariant_cutover.sql`
   - `r2_f_f2_cutover_commit=0`：同字节rehearsal，明确ROLLBACK；对象/约束残留0，旧trigger MD5恢复。
   - `r2_f_f2_cutover_commit=1`：正式代码DDL一次COMMIT；无业务DML。
2. `school_lesson_r2_f_f2_billing_week_invariant_postdeploy.sql`
   - 两次READ ONLY验收均通过。
3. `school_lesson_r2_f_f2_billing_week_invariant_rollback_tests.sql`
   - 7/7通过，固定fixture全部ROLLBACK，残留0。
4. R2-F-F1 rollback：10/10通过。
5. R2-F-F aircon/atomic rollback：5/5通过；lesson指纹预期按业务负责人合法新增后的662行更新并重跑通过。
6. R2-F-E与R2-F-E1 rollback：通过；R2-F-E旧周外错误码断言兼容新稳定错误码。

F2测试覆盖：跨月周内日期成功、week/month/student month不变、周外日期拒绝、直接归属修改拒绝、legacy日期编辑fail-closed、8月整月/08-31周包含、9月排除、aircon 660与统计一致。

前端测试全部通过：billing-week、settlement filter、planned aircon、R2-F-E、R2-F-E1、validation preview、atomic generate；相关JS `node --check`及`git diff --check`通过。页面层无直接RPC/表写，未发现raw policy泄漏。

## 8. 最终状态与零漂移

正式函数MD5：

- planned attribution trigger：`cc3fc1846815f1f2848186ca14319df5`
- authoritative reader：`bdf5995829a532bf5d8803ed1b1f582f`
- 10参数stats：`9456529c3cfb0d597f106d5ea6806832`
- 9参数stats：`59d88ab0852348b8f9f224d082292f43`

R2-F-F2首次验收时的阶段性preview：

- 孙陈锋：24 candidates / 28课次 / 48h / base JPY408,000 / aircon JPY8,580 / total JPY416,580 / carryover CNY0 / 0.042 → CNY17,496.36；目标课命中一次。
- 张倬闻：30 / 35课次 / 65h / base/total JPY650,000 / aircon 0 / carryover CNY107.50 / 0.043 → CNY28,057.50。

上述孙陈锋`24 / 28课次 / 48h / JPY416,580`是R2-F-F2首次验收时业务负责人继续补录后的阶段性数据库事实，不是R2-F-F2代码或fixture创建的课程，也不冻结为最终8月账单基线。

commit前补充只读复核时，业务负责人又新增candidate `004441ea-1be1-4abb-98c0-23343c32a535`（2026-09-06、billing month 2026-08、2课次、2h、base JPY17,000、aircon JPY660），最新preview已变为`25 candidates / 30课次 / 50h / base JPY425,000 / aircon JPY9,240 / total JPY434,240 / CNY18,238.08`。这同样是持续录入中的阶段性业务数据，不是本轮代码、DDL或fixture写入，最终账单金额必须在业务负责人完成全部录入后重新确认。

前后业务指纹一致：9 bill、42 income、7 identity、121 relation、17 settlement、95 wage locks、556 wage details、185 account transactions、662 lessons。测试student/lesson和atomic writer context残留均为0。

School Cash linkage的权威基线表为`public.school_personal_cash_income_linkage_events`，不是`public.school_personal_cash_linkage_events`。commit前只读复核确认：总行数35，其中`income_category='tuition'`学费相关11（7条atomic tuition bill来源、4条legacy tuition）；全行指纹`6e76a4dc2fc2954b28b7ad0a8d203ba0`，与R2-F-F和R2-F-F1基线完全一致；东京时间2026-08-01 00:00起本轮实施窗口内新增0、更新0。原“0 School Cash linkage”把“本轮变化0”误写成“记录0”，现已纠正为：`School Cash linkage：35条，指纹不变，本轮新增/更新0条`。

Gate保持：

- preview = `enabled`
- generate = `blocked`
- Cash submit = `blocked`

未生成真实bill/income，未连接Cash DB，未修改settlement、工资或资金事实，未处理历史全量归属或李天伦未来actual。

## 9. commit前`year_month`生产依赖补充审计

### 9.1 已正确收口或合法兼容

- 主列表与月份/周筛选：`school_list_lesson_management_records_authoritative(text,date)`通过`school_list_r1d_e_c_student_month_lessons`选月；canonical planned解析为`billing_month`，周筛选只比较`billing_week_start_date`。目标课8月整月命中1、`2026-08-31`周命中1、9月整月命中0。
- 过滤统计：9/10参数`school_get_lesson_management_stats_filtered(...)`复用上述reader；跨月actual/source比较的两侧均调用R1D-E-C resolver。
- PDF、教室课表和学生周课表：均通过`js/api/lesson-api.js::fetchLessonRecords`或同一权威reader取月，再按预计日期作课表展示；目标课只从8月reader集合进入，9月reader不重复返回。
- 学费candidate与atomic snapshot：`school_list_student_tuition_candidates(...)`明确使用`lesson.billing_month=p_billing_month`并校验billing week/student month bundle；snapshot只聚合candidate detail。目标课8月candidate命中1、9月命中0，`year_month`变化不改变收费月。
- 月结reader：`school_list_r1d_e_c_student_month_lessons(...)`对五字段完整的canonical planned调用resolver并返回`billing_month`；`year_month`只保留给有固定legacy evidence的旧记录。目标课resolver返回`2026-08`。
- 工资reader：`school_generate_teacher_monthly_wage(...)`只选择actual，并优先使用`teacher_settlement_month`；其`year_month` fallback属于actual历史兼容，不决定planned收费归属。
- 单条、批量、导入planned创建与guarded update：正式wrapper最终经过`school_enforce_r1d_f1_planned_attribution()`；canonical billing month/week/student month由结构化bundle生成或保持不可变。guarded update继续按预计日期更新兼容`year_month`，但trigger不允许它改写canonical收费归属。
- `school_lesson_date_semantics`视图只把该列命名为`legacy_year_month`用于诊断，不参与筛选。

### 9.2 补充审计时发现的非法或误导性planned依赖（已由R2-F-F2-B收口）

1. 已部署`school_get_lesson_management_stats(text,uuid,uuid,uuid,text,text,uuid)`仍直接执行`year_month=p_year_month`，且anon/authenticated均有EXECUTE；虽然当前课时页改用filtered overload，它仍是可调用旧生产入口。
2. 已部署且页面实际调用的`school_list_open_lesson_credit_sources(text,text,text)`以`p.year_month >= from_month / <= to_month / <= target_month`筛选pending makeup planned；anon/authenticated均有EXECUTE。
3. `js/api/lesson-api.js::fetchCrossMonthMakeupReferences`以planned `row.year_month !== normalizedMonth`分类跨月来源；`js/pages/lesson-page.js`还以`source.year_month`校验补课来源月份。
4. `js/pages/lesson-page.js`的历史文件导入锁前检以`plannedLesson.year_month`查学生locked settlement并生成错误文案，没有使用`student_settlement_month/billing_month`。
5. `js/api/lesson-detail-api.js::fetchSettlementReferences`以`lesson.year_month`查询`school_student_monthly_settlements.year_month`；canonical跨月planned会错误查询2026-09而不是2026-08。
6. 普通课时表、编辑摘要及普通/取消/补课actual弹窗仍把planned `year_month`显示为“学生结算月（DB权威）”；void/delete刷新目标月份、pair view来源月份/详情返回参数也仍使用planned `year_month`。
7. 已部署`school_create_actual_lesson_from_planned`、`school_create_partial_completed_actual_from_planned`及`school_create_cancelled_actual_lesson_from_planned`在插入前的学生locked settlement检查仍使用`v_planned.year_month`；canonical actual attribution trigger虽会写入正确结构化月份，但前置锁检查口径仍可能检查错月。
8. 已部署`school_delete_fresh_planned_lesson`和`school_void_planned_lesson`仍以`coalesce(v_lesson.year_month,to_char(v_lesson.lesson_date,'YYYY-MM'))`检查学生月结；canonical跨月planned可能绕开正确billing month的月结检查。

以上内容是R2-F-F2提交前的阻塞清单，不是当前残留。R2-F-F2-B已替换已部署函数并修正源码；旧stats与补课来源RPC继续保留anon/authenticated/service_role既有EXECUTE，不扩大权限，其实现已改为权威reader/resolver。

### 9.3 补充审计时的目标页面语义（已修复）

- 数据与主reader已经满足：收费月份`2026-08`、收费自然周`2026-08-31`至`2026-09-06`、预计上课日期`2026-09-06`；8月整月及8月末周各命中一次，9月整月不命中。
- 9月周选项由统一周函数从`2026-09-07`开始，不会生成“9月 + 08/31–09/06”。
- 当时独立详情页虽能解析到2026-08，但仍重复显示billing month且自然周只显示周一；现已统一为收费归属月、完整自然周及预计日期。
- 当时普通课时表和多个操作弹窗仍会把raw `year_month=2026-09`标成学生结算月；现已全部改为消费canonical字段。

该段结论是触发R2-F-F2-B的历史阻塞证据；当前结论以第11节为准。

## 10. 历史停止点

R2-F-F2曾停在commit前补充审查阻塞点；该阻塞已由下列R2-F-F2-B实施解除。

## 11. R2-F-F2-B生产依赖收口

### 11.1 根因与8类路径结果

根因是新权威reader只替换了主列表，却没有同步审计旧兼容RPC、writer锁前检查及页面辅助路径。raw `year_month`因此仍可能把跨月周planned当成预计日期所在月。R2-F-F2-B逐项结果：

1. 旧stats RPC改为调用`school_list_r1d_e_c_student_month_lessons`，合法结果与主reader一致；既有ACL不变。
2. 补课来源RPC用R1D-E-C resolver输出兼容`year_month`，不再按planned raw month筛选；待补余额算法不变。
3. 跨月补课API/页面只消费`authoritative_student_month`，不再前端判断raw month。
4. 文件导入锁前检查先调用只读resolver wrapper，再查询locked settlement；教师工资月仍按实际日期的既有规则。
5. 详情页及月结详情按权威reader/resolver关联月结；返回链接保留收费月、自然周和视图。
6. 主列表、详情、编辑、删除及作废摘要统一显示“收费归属月 / 收费自然周 / 预计上课日期”，普通业务页面不显示raw planned month或policy code。
7. ordinary、partial、cancelled实际课时写入口的来源月结锁检查改用R1D-E-C resolver；makeup/makeup_completed继续使用既有actual权威月份规则。
8. planned删除、作废及guarded update锁检查改用resolver；bill relation、locked settlement及linked actual保护均未放宽。

全库复核另发现并收口：10参数stats的actual跨月比较、教师工资生成中的学生月结检查，以及actual_minutes历史维护函数中的学生月结检查。教师工资候选仍只按`teacher_settlement_month`并保留其既有legacy actual fallback；该fallback不决定学生收费月。

### 11.2 全库引用分类

- 合法legacy诊断/审计：`school_lesson_date_semantics.legacy_year_month`、R1D evidence/hash校验、RPC兼容返回列、planned/actual legacy字段保存及历史inventory SQL。
- actual历史兼容：仅存在于R1D-E-C resolver内部，或教师工资`teacher_settlement_month`为空时的既有工资月兼容；学生月结关联全部经过R1D-E-C resolver。
- 非生产：旧cutover、readonly inventory、rollback fixture、UI fixture和文档中的历史字符串，均不会成为已部署生产判断。
- 非法生产依赖：`0`。生产planned月份筛选只使用`billing_month`，周筛选只使用`billing_week_start_date`；candidate/atomic使用canonical billing attribution；actual学生月结使用R1D-E-C resolver。

### 11.3 DDL与函数MD5

执行的代码型DDL均先同字节rehearsal ROLLBACK，再正式COMMIT：

- `school_lesson_r2_f_f2_b_year_month_production_closure.sql`，SHA-256 `e2b0d7605f2e9f542cb3652d4b5930567db1b445a5e6447ae24d2589af5173af`。
- `school_lesson_r2_f_f2_b_actual_stats_resolver_correction.sql`，SHA-256 `c5332f0c787131dcfb1f63a645ac6a014f1f3d7c2e24334dd01d75e92cc16cc1`；正式连接第一次在BEGIN前DNS失败，事务未开始，重试后明确COMMIT。
- `school_lesson_r2_f_f2_b_actual_writer_month_correction.sql`，SHA-256 `983c0febc02bd2db504e1762f45db2400a003e263428c78517e34365b825354c`。

关键最终MD5：主reader `bdf5995829a532bf5d8803ed1b1f582f`；10参数stats `9456529c3cfb0d597f106d5ea6806832`；旧stats `d3683834072338f07329f2c4832060a3`；补课来源 `79529f1032057f930823da8efbb8ccb2`；resolver wrapper `fdc96abda53507cb9fd979809ebc0b10`；教师工资三参数 `9d8594a51a26db4d7b211a3ab5d234cc`；actual_minutes维护 `8740bcfefc580e15acb5ebccf7fc0542`。

### 11.4 测试、目标记录与阶段性preview

- F2-B rollback矩阵11/11；F2 billing-week 7/7；F1 aircon 10/10；R2-F-F aircon/atomic 5/5；R2-F-B atomic 8组；R2-F-E/E1均通过。所有fixture事务明确ROLLBACK，student/lesson/settlement/writer context残留0。
- billing-week、settlement filter、lesson operations、actual generation、actual overage、planned aircon、validation preview及atomic generate UI测试全部通过；相关JS `node --check`、页面/API边界扫描和`git diff --check`通过。
- 目标UUID保持`lesson_date 2026-09-06 / legacy year_month 2026-09 / billing week 2026-08-31 / billing month 2026-08 / student month 2026-08`；8月整月1、8月末自然周1、9月整月0、8月candidate 1、9月candidate 0。
- 详情业务语义固定为：收费归属月`2026-08`、收费自然周`2026-08-31至2026-09-06`、预计上课日期`2026-09-06`。
- 最新孙陈锋阶段性preview为`25 candidates / 30课次 / 50h / base JPY425,000 / aircon JPY9,240 / total JPY434,240 / CNY18,238.08`；张倬闻保持`30 / 35 / 65h / JPY650,000 / carryover CNY107.50 / CNY28,057.50`。孙陈锋变化来自业务负责人持续补录的真实课程，不是本轮DDL/fixture，不作为最终账单固定基线。

### 11.5 零漂移、Gate与停止点

最终全行指纹：lesson `662 / afee1af53686091a9e2353734d2b7cd9`；bill `9 / 0f0323b79e7ff1c47ff6b90c75477a2d`；income `42 / 2a4897b752f272b1f192045418b4940c`；relation `121 / 285172fedeb923c67ea9a179480d8692`；identity `7 / 4d91a5a1074f90389822fc367a7e5467`；settlement `17 / 1d7328654f6488952dba20640072c3e2`；wage lock `95 / 7bbe108d3ac73d4f21530793bf141bc6`；account transaction `185 / 8f4f6c4365035f6c36bac59ba986b28b`；School Cash linkage `35 / 6e76a4dc2fc2954b28b7ad0a8d203ba0`。本轮正式数据库变更只有函数DDL，没有真实业务DML。

Gate保持`preview enabled / generate blocked / Cash submit blocked`。未调用真实atomic generate，未创建bill/income，未连接Cash DB，未修改lesson、settlement、工资或资金事实。未执行git add、commit或push；当前停止在R2-F-F2-B commit前审查点。

### 11.6 修改文件清单

- 文档：`docs/current-status.md`、本报告。
- 页面/入口：`lesson.html`、`lesson-detail.html`、`settlement-detail.html`、`wage.html`、`js/lesson-app.js`、`js/lesson-detail-app.js`、`js/settlement-detail-app.js`、`js/wage-app.js`。
- API：`js/api/lesson-api.js`、`js/api/lesson-detail-api.js`、`js/api/settlement-api.js`、`js/api/settlement-detail-api.js`、`js/api/wage-api.js`。
- 页面/组件/utility：`js/pages/lesson-page.js`、`js/pages/lesson-detail-page.js`、`js/pages/settlement-detail-page.js`、`js/pages/wage-page.js`、`js/components/lesson-edit-dialog.js`、`js/components/lesson-delete-dialog.js`、`js/components/lesson-void-dialog.js`、`js/utils/lesson-settlement-filter.js`、`js/utils/actual-overage.js`、`js/utils/lesson-error-message.js`、`js/utils/planned-aircon-display.js`。
- UI测试：`scripts/lesson-billing-week-invariant-ui-test.mjs`、`scripts/lesson-settlement-filter-test.mjs`、`scripts/actual-overage-ui-test.mjs`、`scripts/planned-aircon-ui-test.mjs`。
- 权威业务SQL源：`school_create_planned_lesson_record_rpc.sql`、`school_generate_planned_lessons_batch_rpc.sql`、`school_import_lesson_records_batch_rpc.sql`、`school_update_lesson_record_guarded_rpc.sql`、`school_create_actual_lesson_from_planned_rpc.sql`、`school_create_cancelled_actual_lesson_from_planned_rpc.sql`、`school_lesson_credit_operations_rpcs.sql`、`school_delete_fresh_planned_lesson_rpc.sql`、`school_void_planned_lesson_rpc.sql`、`school_lesson_void_dependent_read_rpcs.sql`、`school_open_lesson_credit_sources_read_rpc.sql`、`school_generate_teacher_monthly_wage_business_scope.sql`、`school_backfill_actual_minutes_from_duration_rpc.sql`（均位于`sql/current/`）。
- R2-F-F2/F2-B工件：`school_lesson_r2_f_f2_billing_week_invariant_{cutover,postdeploy,rollback_tests}.sql`、`school_lesson_r2_f_f2_b_year_month_production_closure.sql`、`school_lesson_r2_f_f2_b_actual_stats_resolver_correction.sql`、`school_lesson_r2_f_f2_b_actual_writer_month_correction.sql`、`school_lesson_r2_f_f2_b_year_month_production_closure_{postdeploy,rollback_tests}.sql`（均位于`sql/current/`）。
- 回归期望修正：`school_lesson_r2_f_e_operations_closure_rollback_tests.sql`、`school_tuition_r2_f_b_atomic_generate_rollback_tests.sql`、`school_tuition_r2_f_f_aircon_atomic_rollback_tests.sql`（均位于`sql/current/`）；只修正当前guard、日期和阶段性业务指纹下的fixture/预期，不改变生产业务逻辑。

## 12. R2-F-F2-C课时管理权威月份刷新回归

### 12.1 真实记录与根因

生产回归目标`300751ba-2ea5-41f0-97dd-45251af8e9d1`是陈加恩/青空进学塾、丛琪润、EJU数学的`planned / planned`课时：预计日期`2026-08-03`，起止时间NULL，2小时/1课次，legacy `year_month=2026-08`，`billing_month / billing_week_start_date / student_settlement_month / teacher_settlement_month`均为NULL，`billing_month_source`为NULL，无source planned及linked actual，`updated_at=2026-07-04 14:35:52.963134+00`。R1D-E-C list把它分类为`legacy_planned`，公开权威resolver稳定返回`2026-08`；权威课时reader因此应在2026-08整月返回1次，在2026-09返回0次。该记录没有数据异常，也未被本轮修改。

根因属于B（前端校验错误）和E（API映射错误）：reader按resolver正确返回legacy planned，但API把请求月份直接盖成每行`authoritative_student_month`，页面又对所有planned强制读取nullable canonical `billing_month`，于是合法legacy行被误判并使整个结果集抛错。浏览器角色还暴露同链第二处问题：10参数filtered stats为SECURITY INVOKER，却直接调用无authenticated EXECUTE权限的私有R1D-E-C resolver，REST返回42501；DB owner直调此前掩盖了该错误。

### 12.2 最小修复

- lesson API不再把查询月份写成行级证据；每行调用既有公开`school_resolve_lesson_student_month_authoritative(uuid)`取得权威学生月。没有使用raw `year_month`、日期月或COALESCE fallback。
- 页面以`authoritative_student_month`校验所有记录；仅对已有非NULL canonical bundle的planned追加`billing_month`一致性检查，指定周仍校验`billing_week_start_date`。孤立异常行被隔离并显示中文告警，其余合法列表和DB权威统计保留；重复ID、非法查询月份等整体契约错误仍整体fail-closed。
- 10参数filtered stats只把两处私有resolver调用替换为既有公开SECURITY DEFINER wrapper；函数签名、owner、返回结构、ACL及业务范围不变。MD5由`9456529c3cfb0d597f106d5ea6806832`变为`46dd237d8eb615c2002c413882f2edaf`。
- 未新增表、字段、状态、月份/归属概念、fallback、ACL或第二权威来源。

### 12.3 DDL与验收

独立纠正SQL`school_lesson_r2_f_f2_c_filtered_stats_resolver_correction.sql`的SHA-256为`6a31b3f2db771a62d45184d2d0ecb38de12539cd53607942854f4896ca2fb012`。同一字节先以`r2_f_f2_c_commit=0`执行BEGIN/替换/函数MD5核验/明确ROLLBACK，再以`r2_f_f2_c_commit=1`执行同一流程并明确COMMIT；正式变更只有`CREATE OR REPLACE FUNCTION`，业务DML为0。

F2-C postdeploy通过；rollback矩阵4/4通过并明确ROLLBACK，lesson/student残留0。F2原矩阵7/7、F2-B矩阵11/11再次通过并ROLLBACK。新增UI回归覆盖首次加载、浏览器刷新、查询按钮、全部/单学生整月、指定自然周、legacy planned、canonical跨月planned、actual学生月与日期/教师月分离、source配对、孤立异常行隔离、列表/统计范围一致及request gate；billing-week、settlement filter、lesson operations、actual overage、planned aircon、validation preview及atomic generate回归均通过。

真实浏览器验收：2026-08整月+全部学生加载成功，目标UUID显示一次业务行且不再清空整页；点击查询和浏览器刷新均成功。孙陈锋2026-08整月及`08/31–09/06`周正常，跨月planned `aa55dc2e-3b1b-4d2d-863f-9f64e84b8578`在8月整月/末周命中、9月整月排除；2026-09周选项从`09/07`开始。统计RPC在authenticated角色下与权威reader数量一致。

### 12.4 零漂移、Gate与停止点

F2-B全指纹postdeploy再次通过：lesson `662 / afee1af53686091a9e2353734d2b7cd9`；bill `9 / 0f0323b79e7ff1c47ff6b90c75477a2d`；income `42 / 2a4897b752f272b1f192045418b4940c`；relation `121 / 285172fedeb923c67ea9a179480d8692`；identity `7 / 4d91a5a1074f90389822fc367a7e5467`；settlement `17 / 1d7328654f6488952dba20640072c3e2`；wage lock `95 / 7bbe108d3ac73d4f21530793bf141bc6`；account transaction `185 / 8f4f6c4365035f6c36bac59ba986b28b`；School Cash linkage `35 / 6e76a4dc2fc2954b28b7ad0a8d203ba0`。

Gate保持`preview enabled / generate blocked / Cash submit blocked`。未调用真实generate，未创建bill/income，未连接Cash DB，未修改lesson、settlement、工资、资金或账户流水。本轮停在R2-F-F2-C commit前审查点；未执行git add、commit或push。R2-F-F2-C目标文件为`lesson.html`、`js/lesson-app.js`、`js/api/lesson-api.js`、`js/pages/lesson-page.js`、`js/utils/lesson-settlement-filter.js`、两个既有UI测试、一个新增UI测试、一处F2-B rollback期望修正、三份F2-C SQL工件、本报告及`docs/current-status.md`。
