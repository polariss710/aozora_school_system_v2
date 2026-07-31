# School V2 R2-F-E Lesson Operations Closure Report

Date: 2026-08-01

## Outcome

R2-F-E完成三项课时运营闭环加固：已收费planned可在收费事实继续冻结的前提下转为`pending_makeup`；所有actual写入口由表级trigger统一禁止未来东京业务日期的`completed`/`makeup_completed`；课时编辑保存后按保存前筛选重新读取列表与统计，不再随修改后的日期切换月份或自然周。

正式数据库部署只包含函数与trigger DDL，没有正式业务DML。所有fixture写入均在回滚测试事务中，最终残留为0。未修改真实课时、月结、bill、income、Cash、账户流水或工资事实；未连接Cash DB，未调用学费generate，R0保持`validation_preview_only / blocked / blocked`。

## Root causes

### 1. Charged planned to pending makeup

- 真实复现课时为彭宇晗planned `1a370095-dd14-444f-8ffb-778e92e03c88`，收费关系`7d3a5842-2101-5fd1-dd6e-706267a3e31f`，正式bill `2a0948e0-9015-4b18-848c-8c397e0bc2a0`。该课冻结为2026-07、`2h / JPY8,500/h / JPY17,000`，无关联actual，剩余待履约2小时。
- `school_enforce_r2_e_planned_aircon()`原本把有legacy evidence或正式relation的planned日期、状态及收费字段一并硬冻结，因此合法的`planned -> pending_makeup`也被`R2_E_LEGACY_PLANNED_CHARGE_FACT_IMMUTABLE`拒绝。
- 编辑弹窗把历史NULL空调费率显示成0，并把0随全量RPC契约提交；venue wrapper因此可能把NULL改成0，额外触发收费事实冻结。前端现保留NULL并省略该参数，选择保留legacy证据的既有overload。
- 待补余额的权威身份仍是原planned UUID；余额由DB根据原planned时长扣除已完成ordinary/partial/makeup actual得出。本次不创建独立余额行。状态重复保存不会新增relation或重复余额；原bill和canonical relation继续保留，该课不再进入后续candidate。

### 2. Future actual completion

- ordinary actual、partial、makeup及guarded edit此前分别依赖writer校验，但没有覆盖直接DML和全部未来日期状态组合的统一表级约束，因此未来actual能够以`completed`或`makeup_completed`落库。
- 新增`BEFORE INSERT OR UPDATE OF app_record_type, lesson_type, status, lesson_date` trigger，以`timezone('Asia/Tokyo', statement_timestamp())::date`为唯一业务日期；actual处于完成状态且日期晚于该日期时稳定抛出`FUTURE_ACTUAL_COMPLETION_FORBIDDEN`。
- trigger不影响未来planned，也不改变学生结算月、老师工资月或收费月份的既有解析规则。

### 3. Edit save refresh

- 原`refreshAfterEditLesson(updatedLesson)`会先从保存结果的`year_month`或`lesson_date`改写年月筛选，再重建查询，因此编辑跨月日期时会自动跳月，并可能制造“8月＋07/27–08/02周”的非法组合。
- 保存失败和保存成功后的刷新失败原本共用同一catch，无法准确告诉用户数据库已保存。
- 现在在写请求前快照年、月、自然周、学生、老师、科目、业务归属、类型、状态、计费、关键词和当前视图；保存后只用该快照重新读取原月份、列表和统计卡片。修改后不再命中的记录可以消失，但筛选和URL不变。新请求gate阻止旧响应覆盖新查询；刷新失败显示“课时已保存，但列表刷新失败”，保存失败则不刷新也不显示成功。

## Database implementation

部署文件：`sql/current/school_lesson_r2_f_e_operations_closure_cutover.sql`。

- 替换`school_enforce_r2_e_planned_aircon()`：继续冻结学生、业务归属、科目、收费月份、收费自然周、课时数、时长、单价、基础费、空调费组件、billable及canonical归属；仅允许老师、冻结收费自然周内的日期/时间，以及一次`planned -> pending_makeup`履约状态变化。
- 最小替换既有base `school_update_lesson_record_guarded(...)`，使已收费planned调整日期时保留DB已解析的学生结算`year_month`，不会因跨月自然周重新归月。
- 新增owner-only trigger helper `school_enforce_r2_f_e_actual_completion_date()`及表trigger，覆盖RPC writer与直接DML。
- 没有改变业务表schema、历史行、ACL/RLS客户端入口或R0 gate。

正式部署后函数MD5：

- charged planned guard：`9124204f047c87b231f78e20e1fd73b6`
- base guarded update：`6ae23d24b310a749082811fcdaf44131`
- future actual completion guard：`866f4330cdef60dc67bc4fea8c2058e9`

同字节cutover先以`r2_f_e_commit=0`执行rehearsal并明确`ROLLBACK`，通过后以`r2_f_e_commit=1`正式执行一次并明确`COMMIT`。正式执行只有代码型DDL，没有业务DML。

## Rollback and UI tests

`sql/current/school_lesson_r2_f_e_operations_closure_rollback_tests.sql`最终完整通过并明确`ROLLBACK`：

- charged planned fixture `ff9913c3-da8d-44a2-a77e-2ec490e8ed5e`、relation fixture `765654e4-6064-4fc8-998a-52210be88cd7`成功转pending、同周改日期/时间和老师，重复提交幂等；收费身份、月份、count、duration、unit、base/aircon/total及relation不变，后续candidate为0，剩余余额恰为2小时。
- 科目、时长、单价、费用、收费周外日期及pending回退planned均被拒绝。
- ordinary actual今天与过去日期成功；明天actual、明天partial、明天makeup及已完成actual改到明天均返回`FUTURE_ACTUAL_COMPLETION_FORBIDDEN`；未来planned仍可创建。
- 测试报告actual ID为`cff0c6f6-cda3-4708-a41d-4d93ea01f1d0`；lesson与relation fixture残留均为0。

前端/API验收：

- 相关JS及3份测试`node --check`全部通过。
- `node scripts/lesson-operations-closure-ui-test.mjs`：PASS。
- `node scripts/planned-aircon-ui-test.mjs`：PASS；原测试对收入页字段的过时断言由`lesson_total_fee_jpy`修正为当前DB preview契约`course_total_jpy`，未改收入页业务代码。
- `node scripts/actual-overage-ui-test.mjs`：PASS。
- 页面层直接`.rpc()`/Supabase表写扫描为0；所有写入仍经`js/api/lesson-api.js`。
- `git diff --check`：PASS。

## Existing real-data anomalies

只读扫描发现3条学生李天伦的未来actual，均未进入locked学生月结或locked工资明细，本轮未修改：

- `e890424d-407d-4fc2-b8ad-84745b242cdd`：2026-11-01，`completed`，planned source `552c54e3-2d0c-4607-962d-aad39dfff7f7`，2h / JPY26,000。
- `c582a187-32f6-4a24-bb7b-d590b25c1854`：2026-11-22，`makeup_completed`，planned source `f759623b-ce28-4c5f-8556-95c4381b6b1b`，2h / JPY26,000。
- `dc06b98c-360f-4661-a294-52ecb82830a7`：2026-11-22，`makeup_completed`，同一planned source，2h / JPY26,000。

这些记录需要业务负责人另行确认后授权数据修正；新guard只阻止未来新增或修改，不回写历史事实。

## Final regression and zero drift

最终postdeploy在School DB `READ ONLY`事务中执行并明确`ROLLBACK`：

- 孙陈锋2026-08仍为22 candidates、24课次、44小时、基础费JPY374,000、空调费JPY0、previous carryover CNY0。
- 张倬闻2026-08仍为30 candidates、35课次、65小时、基础费JPY650,000、空调费JPY0、previous carryover CNY107.50。
- 两人的2026-07 settlement继续locked；彭宇晗真实课时及收费关系未变。
- 指纹保持：656 lessons `21ccb5b1b93f6004d061c95ed98994a9`、17 settlements `7f78087e7b648992b95d66327a6a0a73`、9 bills `0f0323b79e7ff1c47ff6b90c75477a2d`、42 income `2a4897b752f272b1f192045418b4940c`、121 relations `285172fedeb923c67ea9a179480d8692`、7 identities `4d91a5a1074f90389822fc367a7e5467`、556 wage details `6204dc666b3b8e0f64fac901ecf0686a`、185 account transactions `8f4f6c4365035f6c36bac59ba986b28b`、35 School Cash income linkages `6e76a4dc2fc2954b28b7ad0a8d203ba0`。
- writer context残留0；R0仍为`student_tuition_preview = validation_preview_only`、`student_tuition_generate = blocked`、`student_tuition_cash_submit = blocked`。

## Stop point

停在R2-F-E commit前审查点。不得自行暂存、commit、push、解除R0、真实生成2026-08学费、提交Cash或修改上述3条真实异常记录。
