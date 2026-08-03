# School V2 学费 P0-F 实施报告（2026-08-03）

## 1. 结论

P0-F 已按业务负责人精确批准的模型实施：

- `net_lesson_variance_to_financial_credit_v1` 对所有学生、业务归属和结算月显式可用；
- 无显式 draft 时仍为 `separate_makeup_and_overage_v1`，不会自动产生 unused credit；
- 彭宇晗 2026-07 的生产只读 DB preview 为 unused `-JPY 17,000`、overage `+JPY 2,125`、net `-JPY 14,875 / -CNY 624.75`；
- 彭宇晗与李天伦 2026-08 共 31 条 planned lesson 只读满足 Void 后受控作废资格，但本轮没有作废任何真实 lesson；
- 张倬闻收入列表/详情的四项金额由新增只读 DB reader 返回：历史结转 `107.50`、forward adjustment `-107.50`、净结转影响 `0`、最终通知金额 `27,950.00`；
- P0-F 对真实学生的业务写入为 0；验收期间另有操作员通过正式流程为不在本任务范围的孙陈锋新增一条 actual，已单列为外部并发变化，未删除或改写；Gate 保持 `enabled / blocked / blocked`。

## 2. Business-model expansion declaration

批准来源：业务负责人《P0-F 精确业务模型扩展批准》。

### 新表

- `public.school_student_settlement_source_treatment_drafts`
- `public.school_student_settlement_lesson_variance_claims`

### Settlement 新字段

- `source_treatment_mode`
- `settlement_exchange_rate`
- `settlement_exchange_rate_source`
- `settlement_exchange_rate_effective_date`
- `lesson_variance_calculation_version`
- `unused_planned_credit_jpy`
- `unused_planned_credit_cny`
- `pending_makeup_hours`
- `lesson_variance_display_hours`
- `net_lesson_variance_jpy`
- `net_lesson_variance_cny`
- `lesson_variance_source_count`
- `lesson_variance_manifest_sha256`

未新增 enum、通用账务表、历史回填、双写、fallback 或 legacy reader precedence。`preset_exchange_rate` 语义不变；新模式只接受显式 `settlement_exchange_rate`，缺失时 fail-closed。

只读收入展示 RPC `school_get_tuition_income_forward_adjustment_display(uuid[])` 不增加业务事实，只把既有 P0-E immutable adjustment 与冻结通知金额作为 DB reader 结果返回。

## 3. 权威合同

### Source eligibility

- unused credit 只来自正式 `pending_makeup` planned source 的 DB 权威 remaining hours/value；
- partial actual 不单独产生第二份 credit，只通过 remaining pending makeup 进入；
- makeup completed 消耗 remaining balance；
- cancelled/non-billable 自身贡献 0，但解除 unresolved blocker；
- overage 只读取既有 frozen `actual_duration_overage_charge_v1`，不含空调或附加费；
- 金额逐 source 计算后合计，小时只展示；
- unresolved planned、关系冲突、无显式 rate/source/effective date 均 fail-closed。

### Claim lifecycle

- preview：只读，不创建 claim；
- draft：同 scope 至多一个 active，新版本将旧版本置为 `superseded`；
- lock：同事务重读并锁定 source，校验 draft/manifest，创建 immutable active claim batch，冻结 settlement aggregate/manifest，draft 置 `consumed`；
- unlock：仅未被任何 generation revision 消费时释放 claim，保留 released evidence；
- relock：新 draft、新 manifest、新 batch/version，不复用 released claim；
- consumed settlement：Rule B 永久优先，revision Void 后也不得 unlock/release/relock/recompute。

### Void 后 planned lesson

`school_void_planned_lesson_after_tuition_void(...)` 适用于所有学生但只允许逐条选择。它要求 voided revision 历史、无 active claim/actual/partial/makeup/wage/locked settlement/active bill-income/Cash/account downstream、expected `updated_at`、原因和确认文本。结果为 canonical soft-void；lesson、旧 revision、relation 与 snapshot 均保留。旧 fresh physical delete 合同未放宽。

## 4. 已部署 SQL / RPC

按顺序执行并成功：

1. `school_tuition_p0f_lesson_variance_schema_20260803.sql`（rollback rehearsal + commit）
2. `school_tuition_p0f_lesson_variance_rpcs_20260803.sql`（rollback rehearsal + commit）
3. `school_tuition_p0f_trigger_diagnostic_20260803.sql`
4. `school_tuition_p0f_rate_hash_correction_20260803.sql`
5. `school_tuition_p0f_reader_void_router_20260803.sql`
6. `school_tuition_p0f_writer_lock_correction_20260803.sql`
7. `school_tuition_p0f_separate_draft_consume_correction_20260803.sql`
8. `school_tuition_p0f_income_forward_adjustment_reader_20260803.sql`（rollback rehearsal + commit）

正式 callable RPC：

- `school_preview_student_settlement_source_treatment(...)`
- `school_set_student_settlement_source_treatment_draft(...)`
- `school_void_planned_lesson_after_tuition_void(...)`
- `school_get_tuition_income_forward_adjustment_display(uuid[])`

settlement summary/lock/unlock/relock、open makeup reader、canonical lesson void router 与 lesson source writer 已收口到同一 DB authority 和 `student_tuition_operation_v1` 锁域。页面只通过 API 模块调用 RPC；页面没有直接 `.rpc()` 或 DML。

## 5. 测试与 fixture

### Fixed rollback fixture

- 主 student：`f0f00000-0000-4000-8000-00000000a001`
- planned unused：`f0f00000-0000-4000-8000-000000001001`
- planned fulfilled：`f0f00000-0000-4000-8000-000000001002`
- controlled void lesson：`f0f00000-0000-4000-8000-000000001004`
- generation/revision：`f0f00000-0000-4000-8000-000000003001` / `f0f00000-0000-4000-8000-000000004001`

`school_tuition_p0f_rollback_tests_20260803.sql` 通过：彭宇晗镜像、draft manifest、lock 两条 claim、claimed makeup拒绝、direct DML拒绝、unlock release、relock batch v2、旧分离模式、canonical controlled void、consumed Rule B 与 claim 永久保留。

### 全员 mode matrix

固定 student `f0f20000-0000-4000-8000-00000000a001`；覆盖：unused only、overage only、net negative、net positive、net zero、不同科目/单价、partial actual、pending makeup、cancelled/non-billable、unresolved fail-closed、默认旧模式。结果 `P0F_ALL_STUDENT_MODE_MATRIX_PASSED`，整事务 rollback。

### Whitelist commit lifecycle

- student：`f0f10000-0000-4000-8000-00000000a001`
- lesson：`f0f10000-0000-4000-8000-000000001001`
- marker：`codex-test tuition-p0f-commit-20260803`

执行 `preflight → insert → verify → cleanup → residue`，最终 residue 0。commit test 写入仅限固定 synthetic fixture，随后精确清理。

### 并发与前序回归

- P0-F 双会话实际阻塞：settlement lock 持有 scope lock，makeup actual writer 阻塞 `4.887749s` 后完成；双方均 rollback，无 deadlock、timeout、半写或重复 claim；
- writer/void/reissue 全部复用 `student_tuition_operation_v1`，没有第二锁域；
- P0-B1 18/18 回归通过；P0-C 单会话矩阵通过；P0-E rollback 及最终 Rule A/B 8/8 通过；
- P0-D 旧普通 Reissue 用例现被后续 P0-E 合同正确拒绝为 `TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED`，由 P0-E 专用套件覆盖；
- 所有临时阶段 fixture 均完成 cleanup/residue 0。

## 6. 生产只读结果

### 彭宇晗 2026-07

| 项目 | DB 结果 |
|---|---:|
| pending makeup | 2.00h |
| unused planned credit | -JPY 17,000 |
| actual overage | +0.25h |
| overage charge | +JPY 2,125 |
| display hours | -1.75h |
| net lesson variance | -JPY 14,875 |
| explicit rate | 0.042 |
| net CNY | -CNY 624.75 |
| system difference | -CNY 624.75 |
| source count | 2 |

建议合同仍为 source treatment `net_lesson_variance_to_financial_credit_v1` + adjustment mode `carry_final_balance`；本轮未保存或锁定真实 settlement。

### 李天伦与 31 条 lesson

- 李天伦 2026-07 在默认旧分离模式下 DB system difference 为 0、lesson variance source count 为 0；不创建零金额 settlement；
- 彭宇晗 15 条、李天伦 16 条，共 31 条 2026-08 planned lesson 只读满足受控作废资格；
- 本轮未逐条执行作废。历史 relation 存在不等于 active revision claim；旧 relation/revision 不得删除。

### 张倬闻 P0-E 显示

只读 DB reader 返回：历史结转 `CNY 107.50`、forward adjustment `-CNY 107.50`、净结转影响 `CNY 0.00`、最终通知金额 `CNY 27,950.00`。未修改张倬闻任何记录。

## 7. School / Cash 前后基线

除一条可明确归因于外部操作员的正式 actual 外，School 前后一致（settlement 使用去除 13 个新 NULL 字段后的 legacy projection）：

| 对象 | 行数 | MD5 |
|---|---:|---|
| lesson（操作前） | 730 | `034d3ee24d639e587447a9458244797c` |
| lesson（最终） | 731 | `7030411f5104c7c5e8994d341bc99190` |
| settlement legacy projection | 17 | `85c829ebc3bb0a4100393d9c8d6421d7` |
| bill | 18 | `bc7fe1fc6d904c5f6a0380583e430c9e` |
| income | 51 | `4468607bc30770376ce6aaca9016e598` |
| adjustment draft | 6 | `059c5187ad6513f9501076193aa55696` |
| adjustment | 5 | `4bce2b158d4de769d592a2d367881868` |
| carryover | 8 | `54133d433579c772ba76017b757c49fd` |

Cash 前后完全一致：request `39 / 303e10bc1a28a0abd8b27afd3929cfd8`；CNY `71 / d7e72182970de4ea8849c994b67e8dcc`；JPY `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`。P0-F Cash fact count 0。

外部并发变化为 lesson `e72edbd9-cc86-4b75-9890-46613b3ed516`（学生孙陈锋、planned source `9efb8862-e8c5-4f3d-9d55-b0be4317ad19`、2026-08-03 actual、DB fee JPY17,000、创建时间 `2026-08-03 10:45:26.479179+00`）。它不是 P0-F fixture，也不属于彭宇晗、李天伦或张倬闻；本任务未修改或清理该记录。

历史 settlement 的 13 个 P0-F 字段全部保持 NULL；正式 treatment draft/claim 表均为 0；Gate 为 `student_tuition_preview=enabled`、`generate=blocked`、`cash_submit=blocked`。

## 8. 页面与 Chrome

页面版本：`v10.4.5`，静态资源 cache key `p0f-20260803-1`。

- settlement preview/save/lock/relock 展示并消费同一 DB resolver 结果；
- 新模式显式输入 rate/source/effective date，金额与换算不由前端计算；
- lesson 页面文案统一为“作废预定课时”；
- income list/detail 四项 P0-E 金额均读取 DB reader；
- Chrome 生产只读验收：待最终 GitHub Pages 发布后补录。

## 9. 写入边界、Git 与保护文件

真实学生 lesson/settlement/draft/adjustment/carryover/Reissue/Cash/Gate 写入均为 0。数据库永久变更仅为获批 schema、RPC、trigger、ACL/RLS、reader 定义；业务写测试仅限固定 whitelist fixture 并已清零。

Git 基线/首个 parent：`0412a94cb63e8cff2053b28e896ec88958989e7e`。最终 commit/push 在 Chrome 生产验收后补录。

六份受保护 untracked 文件 SHA-256 未变：

- `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`
