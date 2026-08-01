# School V2 2026年8月全体学费预览与Atomic Generate恢复实施报告

日期：2026-08-02（JST）
阶段：正式DB函数/Gate已实施；前端与审计工件停在commit前审查点

## 1. 结论

- 已冻结7名active学生、114条2026-08 canonical tuition candidate；全体candidate集合SHA-256为`cb3451c2f9482c202ffd02f2364ac4c2f84a29c821c1a3e6a0a9c8f864e3f3e3`。
- 已修复基础学费被上一期未锁定月结阻断的问题。基础学费只来自canonical candidate；上一期结转只来自locked settlement，无locked事实时冻结CNY0。
- 已修复前端把32位DB权威`complete_row_hash`误要求为64位的问题；未修改或伪造任何lesson/evidence hash。
- 已修复批量生成planned成功后列表不刷新的问题，统一复用已有request-gated刷新机制并保留完整筛选。
- 28/28 atomic rollback矩阵通过，所有固定白名单fixture均ROLLBACK，残留0。
- 正式Gate终态：preview `enabled`、generate `enabled`、Cash submit `blocked`。
- Codex未为任何真实学生调用generate，真实bill/income新增0，Cash调用/写入0。

## 2. 冻结基线

初次冻结时间：`2026-08-01 17:04:30.730473+00`。固定TSV再次导出时间为`2026-08-01 17:15:15.893077+00`；期间无业务DB写入，candidate仍为114/114且集合hash相同。

| 学生 | candidate | 课次 | 小时 | base JPY | aircon JPY | total JPY | locked carryover CNY | 规则金额 CNY | 开始时preview |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 孙陈锋 | 25 | 30 | 50 | 425,000 | 9,240 | 434,240 | 0.00 | 18,238.08 | 成功，generate Gate blocked |
| 张倬闻 | 30 | 35 | 65 | 650,000 | 0 | 650,000 | 107.50 | 28,057.50 | 成功，generate Gate blocked |
| 彭宇晗 | 15 | 15 | 30 | 255,000 | 0 | 255,000 | 0 | 11,092.50 | `R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED` |
| 李天伦 | 16 | 21 | 32 | 352,000 | 0 | 352,000 | 0 | 17,600.00 | 同上 |
| 袁振轩 | 16 | 19 | 37 | 333,000 | 0 | 333,000 | 0 | 13,819.50 | 同上 |
| 陈加恩 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 已有identity/bill/income |
| 陈红卓 | 12 | 12 | 24 | 204,000 | 0 | 204,000 | 0 | 8,772.00 | `R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED` |

基线工件：

- `docs/school-v2-2026-08-tuition-active-student-baseline-20260802.tsv`
- `docs/school-v2-2026-08-tuition-candidate-fixed-114-baseline-20260802.tsv`（header + 114行；逐行`before_row_hash`）
- `sql/current/school_tuition_2026_08_all_students_readonly_baseline.sql`

基线不变量全部通过：candidate均为canonical planned；billing/student month均为2026-08；自然周完整；64条5/6月历史已收费记录、孙陈锋8月1/2日归属7月记录、void/cancelled/pending_makeup、已有canonical charge relation均未泄漏；planned UUID唯一；8/31周20条，其中5条lesson date在9月但收费仍归8月。

## 3. Previous settlement根因与修复

旧snapshot在找不到上一期locked settlement时，会读取上一期动态settlement preview、overage、bill、income、carryover及draft，并把任何非零值解释为必须先锁月结，抛出`R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED`。这把“基础学费收费”和“未冻结的月结动态计算”错误耦合。

新合同：

1. 当月base/aircon/total仍唯一来自canonical charge candidate。
2. 上一期存在唯一locked settlement：冻结其ID、月份、locked时间、金额及evidence SHA。
3. 不存在locked settlement：冻结`zero_carryover_verified_v1`，其明确authority为`locked_previous_settlement_only`、locked count为0、carryover为0。
4. snapshot和atomic core不再调用unlocked settlement preview或duration overage aggregate，也不再存在previous-settlement-required分支。
5. generation manifest继续覆盖settlement ID或zero、carryover金额、evidence SHA和最终CNY金额；真实locked事实变化仍使旧manifest失效。

部署后函数指纹：

- `school_build_student_tuition_generation_snapshot(uuid,text,numeric)`：`083bcb58c2b92f34ded07dceafbbbbfe`
- `school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)`：`b88f6d960d920c10b914fe8e58cf38cb`
- public atomic wrapper未改：`36bdadc9af59637c9d336ce68d9afb4c`
- validation preview未改：`11ef7b45932e6cd418c03c91da104fd0`

## 4. 袁振轩调查

指定planned：`303170f4-1c99-483b-a1ac-6ce23e27ad29`。

- lesson date、billing week、billing month、student settlement month：`2026-07-27 / 2026-07-27 / 2026-07 / 2026-07`。
- source：2026-07-30批量生成的canonical planned；status `planned`；1课次、3小时、JPY9,000/小时，candidate base/total JPY27,000。
- linked actual：`57fc877b-c87f-464e-ad2e-c7caa5585d68`，2026-07-30，`completed`，3小时。
- bill relation 0、historical exclusion 0、legacy planned evidence 0。
- 当前完整lesson行MD5：`91a4ccb91fa9cb91e63a62621c74b00e`；charge candidate的32位完整证据hash为`6ab45a9cb655bd42a0dceae96c3e6902`。二者用途不同，不构成证据冲突。
- 7月reader返回该ID；8月reader不返回。8月返回另外16条planned，19课次、37小时、JPY333,000。7月/8月ID集合不重复。

页面报错根因是JS validator要求`complete_row_hash`为64位，但权威charge reader合同明确返回32位MD5；`candidate_line_hash`才是64位SHA-256。已修正validator，无需改月、无需新增排除、无需历史解释，袁振轩未触发HARD STOP。

## 5. 批量planned列表刷新

根因：成功后直接调用`loadLessonMonth(loadedMonth, filters)`，没有传`lessonRecordsRequestGate` token。`loadLessonMonth`因此判定响应不是当前请求，不更新`lessonRecords`；随后的统计刷新却可成功，形成“统计有值、列表为空”。

修复：提交前冻结完整`readFilters()`；成功后关闭弹窗；调用现有`refreshLessonMonthPreservingFilters(month, filters)`。该helper统一创建request token、重新读取列表、恢复年月/学生/周/老师/科目/状态/view等筛选、同步URL、渲染列表并刷新stats。保存失败不刷新；保存成功但刷新失败显示中文“已生成但列表刷新失败”，不会重复调用batch writer。

## 6. 最终全体preview

| 学生 | candidate | 课次 | 小时 | base JPY | aircon JPY | total JPY | 汇率 | carryover CNY | 通知CNY | 结果 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 孙陈锋 | 25 | 30 | 50 | 425,000 | 9,240 | 434,240 | 0.042 | 0.00 | 18,238.08 | 可生成 |
| 张倬闻 | 30 | 35 | 65 | 650,000 | 0 | 650,000 | 0.043 | 107.50 | 28,057.50 | 可生成 |
| 彭宇晗 | 15 | 15 | 30 | 255,000 | 0 | 255,000 | 0.0435 | 0 | 11,092.50 | 可生成 |
| 李天伦 | 16 | 21 | 32 | 352,000 | 0 | 352,000 | 0.05 | 0 | 17,600.00 | 可生成 |
| 袁振轩 | 16 | 19 | 37 | 333,000 | 0 | 333,000 | 0.0415 | 0 | 13,819.50 | 可生成 |
| 陈红卓 | 12 | 12 | 24 | 204,000 | 0 | 204,000 | 0.043 | 0 | 8,772.00 | 可生成 |
| 陈加恩 | 0 | 0 | 0 | 0 | 0 | 0 | 0.0434 | 0 | 0 | 已有identity/bill/received income，不重复生成 |

精确candidate/candidate-manifest/generation-manifest及existing bill/income见`docs/school-v2-2026-08-tuition-active-student-final-preview-20260802.tsv`。

## 7. Atomic rollback矩阵

`sql/current/school_tuition_r2_f_b_atomic_generate_rollback_tests.sql`输出28/28 PASS：

1. candidate数量/UUID唯一；2. actual/partial/makeup/cancelled排除；3. base+aircon=total；4. candidate JSON顺序；5. 汇率改变manifest；6–9. teacher/subject/venue/date变化使manifest过期；10. 未变manifest稳定；11. Gate开放前public wrapper拒绝；12. identity/bill/relation/pending income四对象原子生成；13. 三个validator；14. 幂等同对象；15. carryover证据篡改拒绝；16–18. 汇率/manifest冲突拒绝；19. atomic income取消拒绝；20. 三类唯一约束；21. locked carryover只带入一次；22. 无locked且有unlocked overage仍为0并允许；23. 注入异常四对象全回滚；24. 跨月自然周；25. legacy actual不参与；26. ordinary non-tuition income不受损；27. advisory locks；28. writer context无残留。

固定学生fixture：`f2fb...a001`至`f2fb...a005`。测试中生成的bill/identity/income UUID只存在于回滚事务；最终fixture残留0。第一轮在旧core validator处fail-closed，事务未提交且残留0；同步core合同后全量重跑通过。

旧入口继续永久fail-closed；页面无直接`.rpc()`或表DML，API只调用`school_generate_student_tuition_bill_atomic(...)`。Cash DB未连接，Cash API/RPC调用0。

## 8. Gate与紧急停止

| Gate | 前 | 后 |
|---|---|---|
| student_tuition_preview | enabled | enabled |
| student_tuition_generate | blocked | enabled |
| student_tuition_cash_submit | blocked | blocked |

正式Gate release：`tuition-2026-08-atomic-generate-restored-20260802`。紧急disable脚本`sql/current/school_tuition_2026_08_atomic_generate_emergency_disable.sql`已以commit=0 rehearsal，UPDATE 1后ROLLBACK；未正式disable。

## 9. 历史指纹

以下前后完全一致：

| 对象 | 行数 | MD5 |
|---|---:|---|
| lessons | 706 | `9b1644dbb1605164c5c3672106d6ba9f` |
| tuition bills | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| bill relations | 121 | `285172fedeb923c67ea9a179480d8692` |
| billing identities | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| student settlements | 17 | `1d7328654f6488952dba20640072c3e2` |
| account transactions | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| wage locks/details | 95 / 556 | `7bbe108d3ac73d4f21530793bf141bc6` / `6204dc666b3b8e0f64fac901ecf0686a` |
| planned/actual evidence | 279 / 234 | `380ee5e6cb419572379a0cfa4dfe6821` / `e685566ddeb27bc9deb8ceb20a272374` |
| historical exclusions | 106 | `e97642f2031aa4fa000d5cd8ac4196bf` |

Gate行是本轮唯一正式业务配置DML。函数DDL仅替换snapshot与atomic core。没有真实lesson、actual、bill、income、relation、identity、settlement、工资、账户或Cash写入。

## 10. 前端验收

- Node fixtures：tuition validation preview PASS；atomic frontend state 14/14；batch unified refresh PASS；lesson generation closure PASS。
- 本地页面验证：7名active学生均出现在预览选择器；未登录调用失败时页面只显示安全中文，不显示raw code、UUID、SQL或函数名。
- 正向金额/candidate/manifest由同一validation preview RPC对6人逐人返回并通过postdeploy。由于本轮禁止commit/push，GitHub线上前端不会包含本轮JS改动；完整浏览器正向验收应在下一次获批Git交付后登录进行。本轮未点击正式生成及二次确认。

## 11. SQL/RPC与数据库执行

正式执行：

- `school_tuition_2026_08_atomic_generate_settlement_authority_cutover.sql`（snapshot DDL COMMIT）
- `school_tuition_2026_08_atomic_core_carryover_validator_cutover.sql`（core DDL COMMIT）
- `school_tuition_2026_08_atomic_generate_gate_enable.sql`（Gate UPDATE 1 COMMIT）

rehearsal/rollback：上述三个SQL均先rehearsal；atomic 28项fixture测试全ROLLBACK；emergency disable仅rehearsal并ROLLBACK。只读执行：baseline、final export、history fingerprints、postdeploy及袁振轩专项SELECT。

调用的生产只读函数包括candidate reader、validation preview、snapshot。写函数只在固定rollback fixture事务中调用core/fixture lesson writers/cancel test；public atomic wrapper仅在Gate blocked测试中验证拒绝。Gate enabled后Codex未调用public atomic wrapper。

## 12. Business-model expansion declaration（最终）

```text
New tables/columns/enum/date/identity/source/writable facts: none
Changed existing-field semantics:
  基础学费不要求上一期月结存在或locked；carryover只读取locked冻结事实，无locked为0。
Changed reader authority:
  validation preview与atomic snapshot/core统一使用locked-only carryover合同。
Changed field mutability/writer authority/locking rules: none
New authoritative sources: none
Legacy fallback/dual read: none；unlocked preview从生产收费判断中移除
Historical reinterpretation/destructive changes: none
Approval: 本任务业务负责人明确批准的Business-model expansion declaration
```

## 13. Git与保护状态

- 文件已修改/新增，尚未暂存；未`git add`、未commit、未push。
- 错误Excel completed CSV继续未跟踪且未修改：`docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`。
- 保护文件未读取正文、未修改、未暂存；SHA-256为`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。

## 14. 业务负责人正式生成清单

1. 在已部署本轮前端后登录School，打开“收入记录 → 学费应收预览”，月份选2026-08。
2. 依次处理：孙陈锋、张倬闻、彭宇晗、李天伦、袁振轩、陈红卓；陈加恩跳过。
3. 每人输入/核对固定汇率，点击“生成预览”；对照本报告candidate、课次、小时、JPY总额、carryover及CNY通知金额。
4. 确认candidate周明细，特别核对孙陈锋空调费JPY9,240、张倬闻carryover CNY107.50、袁振轩8月不包含7月ID。
5. 仅金额与candidate完全一致时打开二次确认并点击一次“确认生成学费应收”；不得重复点击。
6. 每生成一人立即检查唯一billing identity、bill、normalized lesson relations和pending tuition income；如页面要求重新预览或显示中文冲突，停止该人操作。
7. 不提交Cash；`student_tuition_cash_submit`仍blocked。
8. 出现异常时使用经重新授权的emergency disable SQL，仅关闭generate，保留preview并继续禁止Cash。

完成于commit前审查点，等待业务负责人和ChatGPT审查。
