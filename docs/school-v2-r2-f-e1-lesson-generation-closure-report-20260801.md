# School V2 R2-F-E1 Lesson Generation Closure Report

Date: 2026-08-01

## Outcome

R2-F-E1完成三项课时运营补充闭环，并按业务前提修正恢复legacy actual合法编辑后的结算读取：

- charged `pending_makeup`可以生成一次DB权威、学生不计费的`makeup_completed actual`；原收费planned永久保持`pending_makeup`，余额由关联actual消费，不修改原账单或收费关系。
- ordinary、partial、同月makeup和跨月makeup actual写入成功后，统一按提交前筛选快照重新读取列表与统计，不因新actual日期跳月。
- 所有课时弹窗通过统一映射只显示中文业务信息；原始RPC/trigger错误只写入console诊断，不向用户透传技术标识。
- 筛选变化后立即清空旧列表与旧统计是明确的统一状态逻辑，不自动查询；点击“查询”后才使用最新筛选读取。
- legacy actual evidence resolver改为明确的身份/月归属契约。合法备注、`updated_at`、老师、科目、实际日期/时间等运营字段变化不再误报月份证据失配；没有新增或扩大locked actual编辑guard。

R0继续为`student_tuition_preview = validation_preview_only`、`student_tuition_generate = blocked`、`student_tuition_cash_submit = blocked`。未调用真实学费generate，未连接Cash DB。

## Root causes

### 1. Pending makeup could not complete

精确writer为：

`school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)`

旧函数先创建非计费`makeup_completed actual`，余额归零时又执行：

```sql
UPDATE public.school_lesson_records
SET status='makeup_completed'
WHERE id=p_source_planned_lesson_id;
```

charged planned履约guard正确拒绝了这次`pending_makeup -> makeup_completed`状态改写，因而返回`R2_E_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN`。这也与弹窗“不修改原planned”的说明冲突。

修复删除了原planned状态更新。原planned UUID继续作为待补余额身份；`school_get_lesson_credit_remaining_hours`按来源planned时长减去关联ordinary/partial/makeup actual的已履约时长。余额为0后开放来源reader不再返回该课，第二次生成由writer以“该待补课来源已无剩余课时”拒绝。因此无需新余额表，也不会重复消费。

真实彭宇晗来源`1a370095-dd14-444f-8ffb-778e92e03c88`未用于测试、未生成actual，仍保持`pending_makeup / remaining 2h`。

### 2. Actual generation appeared not to refresh

四类生成handler原本都调用刷新函数，但共享刷新没有调用`beginLessonRecordsRequest()`取得新request token；`loadLessonMonth`收到空token后，结果会被latest-request gate当作过期响应丢弃。同时旧代码使用新actual的`year_month`选择刷新月份，会改变用户原筛选。

现在所有生成handler在写请求前快照年月、自然周、学生、老师、科目、业务归属、类型、状态、计费、关键词和当前视图。写入成功后关闭弹窗，再用该快照、新request token读取原月份列表和统计；不读取新actual日期决定页面月份。写入失败时不关闭、不刷新、不显示成功；刷新失败固定显示“实际课时已生成，但列表刷新失败，请重新查询。”。

### 3. Technical error leakage

API层原来把future guard转换为中文加括号错误码，其余错误可能直接传到弹窗。新增`lessonUserErrorMessage`作为唯一UI边界映射：

- `FUTURE_ACTUAL_COMPLETION_FORBIDDEN` → `实际完成日期不能晚于东京当前业务日期。`
- `R2_E_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN`及当前同义码 → `已收费课时不允许执行该状态变更。`
- 网络错误 → 明确中文网络提示。
- 未识别SQL/RPC/system identifier → 安全中文兜底。

API仍抛出原始错误，页面和组件写入console供诊断；页面文本不显示错误码。

### 4. Legacy actual evidence false mismatch

业务负责人先撤销张倬闻2026-07月结锁定，再合法编辑actual备注。白名单actual：

- actual `a1977f69-69d7-45d5-a958-50138d3f80d4`
- planned source `421484ba-a1f8-4210-a9bc-ab40da0c1ece`
- student `7aef8061-7037-4881-a847-a2cdb031c0f4`
- legacy student settlement month `2026-07`

备注和`updated_at`改变后，旧resolver仍以`md5(to_jsonb(actual)::text)`的等价v1整行hash作为运行期编辑锁，导致`R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH`。这不是locked settlement绕过，也不是actual编辑缺陷。

现有v1 evidence字段分为：

- 稳定归属：actual UUID、planned source UUID、student snapshot、business entity snapshot、legacy `year_month`、evidence source/version和cutover cohort manifests。
- 合法可编辑运营字段的历史快照：teacher、subject、lesson date、teacher settlement month、identity/full-row hash。它们继续保留为不可变历史审计，但不再作为preview硬阻断。
- 时长、金额、状态、学生月结锁和工资锁等结算事实继续由既有actual writer、R1D-E-B2 attribution trigger、月结锁与工资锁规则保护；本轮没有改变这些writer规则。

新resolver运行时明确核对actual/source/student/entity/legacy month，并要求来源planned存在、未作废且student/entity一致。canonical actual继续使用自身`student_settlement_month`。它不依赖`to_jsonb(%ROWTYPE)`，新增数据库列不会再次使全库失配。

首次rehearsal曾额外要求legacy actual月份等于来源planned月份，因此在只读验证中发现8条合法历史跨月补课关系并明确ROLLBACK；删除该错误假设后，同字节rehearsal通过。没有修改这8条记录。

## Database implementation and execution

### Code-only DDL

1. `sql/current/school_lesson_r2_f_e1_makeup_credit_closure_cutover.sql`
   - 同字节`r2_f_e1_commit=0` rehearsal：执行并明确`ROLLBACK`。
   - `r2_f_e1_commit=1`正式部署：只替换目标makeup writer，明确`COMMIT`。
   - writer MD5：`3b9378e01900b0e73b9d0b1c2d1e7209` → `4b3af5a89c0409d934513a259dc29d94`。

2. `sql/current/school_lesson_r2_f_e1_legacy_actual_evidence_contract_correction.sql`
   - 第一次rehearsal因错误的source-month等值假设失败并自动回滚，事务状态明确。
   - 修正后同字节`r2_f_e1_evidence_commit=0` rehearsal通过并明确`ROLLBACK`。
   - `r2_f_e1_evidence_commit=1`正式部署只替换resolver DDL并明确`COMMIT`。
   - resolver MD5：`88acc674f4884538863b9c2518908a4f` → `ea944ad620268ac4d86fc8e622ba8d02`。

### Authorized one-row cleanup

`sql/current/school_lesson_r2_f_e1_whitelist_test_note_cleanup.sql`仅对授权actual `a1977f69-69d7-45d5-a958-50138d3f80d4`删除note末尾精确`123`：

- rehearsal明确`ROLLBACK`；正式执行更新1行并明确`COMMIT`。
- note和由既有trigger生成的新`updated_at`之外，全行字段指纹不变。
- 没有伪造旧`updated_at`；正式新值为`2026-07-31 17:50:44.913719+00`。
- cleanup后resolver仍权威返回`2026-07`。

这是本轮唯一正式业务DML。其余正式部署均为代码型DDL。

## Rollback and postdeploy tests

`sql/current/school_lesson_r2_f_e1_makeup_credit_closure_rollback_tests.sql`完整通过并明确`ROLLBACK`。最终fixture：

- source `8772ae92-20d4-4e9a-8e6f-ed1b23602452`
- charged relation `6be0a9ac-b6c8-435a-991b-2d412fde633d`
- makeup actual `1c86d2d3-e3b3-4995-8072-0e67116eef3e`
- legacy legal-edit actual `a1977f69-69d7-45d5-a958-50138d3f80d4`（仅在回滚事务中再次追加测试备注）

矩阵确认：

- charged planned → pending_makeup → makeup actual成功；待补余额增加一次、消费一次。
- source永久保持pending_makeup；余额归零后不再出现在open-source reader。
- 第二次生成被拒绝且actual仍只有1条。
- makeup actual不计学生费，学生结算月由DB解析，教师工资月按actual日期。
- 原bill/income/identity/canonical relation全行hash不变。
- 修改charged unit price仍被拒绝；未来makeup继续由`FUTURE_ACTUAL_COMPLETION_FORBIDDEN`拒绝。
- 原收费课和makeup actual均不进入后续学费candidate。
- 合法legacy note编辑后仍解析2026-07，immutable v1 evidence行hash不变。
- lesson fixture残留0，relation fixture残留0。

最终`sql/current/school_lesson_r2_f_e1_makeup_credit_closure_postdeploy.sql`在`READ ONLY`事务中通过并明确`ROLLBACK`：函数MD5/ACL、234条legacy与10条canonical resolver、3条既有未来actual、真实彭宇晗来源、业务指纹、candidate及R0均符合预期。

当前业务状态发生了一个独立于本轮代码的人工变化：张倬闻2026-07 settlement已由业务负责人为合法actual登记撤销锁定，记录保持`unlocked / rate 0.043 / carryover CNY107.50`。因此张倬闻2026-08 validation preview现在正确fail-closed为`R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED`，不再出现legacy mismatch；需业务负责人页面复核并重新锁定后才能恢复完整preview。孙陈锋2026-08仍为`22 candidates / 24课次 / 44h / JPY374,000 / aircon JPY0 / carryover CNY0`；张倬闻独立canonical candidate仍为`30 / 35 / 65h / JPY650,000`。

## Frontend and API tests

- `node --check`覆盖本轮相关JS、utility和测试脚本。
- `scripts/lesson-generation-closure-ui-test.mjs`覆盖ordinary/partial/makeup/cross-month刷新、写失败不刷新、刷新失败提示、筛选快照、request gate、筛选变化清空、错误映射及page/API边界。
- `scripts/lesson-operations-closure-ui-test.mjs`、`scripts/planned-aircon-ui-test.mjs`、`scripts/actual-overage-ui-test.mjs`及`lesson-settlement-filter-test.mjs`继续作为回归矩阵。
- 页面及component无直接`.rpc()`或Supabase表写；写操作仍只经`js/api/lesson-api.js`。
- 未改变actual编辑、月结锁定/撤销锁定、工资锁或R0规则。

## Zero drift and safety state

在授权note cleanup之后的最终只读指纹：

- 658 lessons：`b54ba3d4c8608a597c8164673840266f`
- 17 settlements：`fe0b47c5534d0afd009ae7e70b370f70`
- 9 bills：`0f0323b79e7ff1c47ff6b90c75477a2d`
- 42 income：`2a4897b752f272b1f192045418b4940c`
- 121 bill relations：`285172fedeb923c67ea9a179480d8692`
- 7 billing identities：`4d91a5a1074f90389822fc367a7e5467`
- 556 wage details：`6204dc666b3b8e0f64fac901ecf0686a`
- 185 account transactions：`8f4f6c4365035f6c36bac59ba986b28b`
- 35 School Cash linkages：`6e76a4dc2fc2954b28b7ad0a8d203ba0`

没有执行真实学费generate，没有连接Cash，没有改变R0，没有处理李天伦3条既有未来actual，也没有修改真实彭宇晗待补课记录。

## Stop point

停在R2-F-E1 commit前审查点。不得自行`git add`、commit、push、重新锁定张倬闻月结、解除R0、真实生成学费或连接Cash。
