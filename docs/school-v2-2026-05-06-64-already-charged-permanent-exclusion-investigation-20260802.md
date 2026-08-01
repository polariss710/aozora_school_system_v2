# School V2 2026年5–6月64条已收费candidate永久排除只读调查

## 结论与停止点

业务负责人本轮最终确认已经解除上一版CSV完整性及6月业务事实HARD STOP。completed CSV本轮只作为`planned_id`与`manual_decision`来源；Excel改写的日期、月份、时间和错误`manual_note`全部不再具有业务权威。其余字段来自原始固定TSV和当前数据库。

固定64条当前仍全部被canonical candidate reader返回：2026-05为30条、2026-06为34条。64条全部为`ALREADY_CHARGED_EXCLUDE`，不存在`VALID_NO_FURTHER_CHARGE_EXCLUDE`，也不存在“未收费但放弃追收”。

现有数据库已经有正确的“历史已收费planned永久排除”概念和reader路径，但现有表只允许固定42清单及School settlement/income/account transaction证据包；本次64条均不能合法写入。不得伪造bill、income、settlement、account transaction或relation，因此触发业务模型扩张门禁。本轮仅提交proposal，未编写或执行DDL/DML，停止在：

> 64条已收费candidate永久排除方案业务审查点

## 1. 固定集合、CSV与规范化结果

| 项目 | 结果 |
|---|---|
| 原始TSV | 64行、43列，SHA-256 `5f2c7320568630b2e04af8bd8b7d593f7dd80a6cee1df7fa57c541775bd53ddc` |
| completed CSV | 64行、43列，SHA-256 `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| planned ID集合 | 两文件精确一致，无重复、无新增、无缺失 |
| 固定ID集合SHA-256 | `7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85` |
| completed中读取字段 | 仅`planned_id`、`manual_decision` |
| manual decision | 64条全部`ALREADY_CHARGED_EXCLUDE` |
| 其他字段来源 | 原始TSV；数据库事实另行只读复核 |
| normalized TSV | 64行、43列；与原TSV相同顺序；除`manual_decision/manual_note`外0个差异；64个`before_row_hash`全部保留 |
| normalized TSV SHA-256 | `53fb0d4e46dc8f0dc8b9879f19c0967712ade192b20b22bcb5e77ac017926a6c` |

规范化备注严格使用最终业务决定：

- 2026-05共30行：`已通过Cash端手工收入记录收取；当时School正式学费收入链尚未启用，禁止重复收费。`
- 2026-06共34行：`已通过School学费收入及Cash同步链收取，禁止重复收费。`

上一版完整性报告记录的Excel改写仍是文件事实，但在本轮“completed只读取两列”的新合同下不再阻塞；没有修改原completed CSV。

## 2. 当前candidate与课程事实

School DB最终复核时间为`2026-08-01 15:35:30.222226+00`（JST 2026-08-02）。当前candidate共64条，ID集合SHA-256仍为`7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85`；六个学生/月scope与固定基线一致：

| 学生 | 月份 | planned | 小时 | 总额JPY | linked actual | completed actual | active wage detail |
|---|---|---:|---:|---:|---:|---:|---:|
| 厦门吕同学 | 2026-05 | 8 | 16 | 144,000 | 8 | 8 | 8 |
| 彭宇晗 | 2026-05 | 8 | 16 | 136,000 | 8 | 8 | 8 |
| 李天伦 | 2026-05 | 14 | 28.5 | 370,500 | 14 | 14 | 14 |
| 厦门吕同学 | 2026-06 | 10 | 20 | 180,000 | 10 | 10 | 10 |
| 彭宇晗 | 2026-06 | 9 | 18 | 153,000 | 9 | 9 | 9 |
| 李天伦 | 2026-06 | 15 | 30.5 | 396,500 | 15 | 15 | 15 |
| **合计** | — | **64** | **129** | **1,380,000** | **64** | **64** | **64** |

64条canonical字段完整，固定集合没有动态扩大。所有64条均无planned级bill relation、billing identity、School tuition bill或既有historical exclusion；无对应student monthly settlement。6月四笔School income也没有`tuition_bill_id`、`source_type/source_id`或School account transaction。因此履约和工资事实完整，不等于收费关系已在School中逐课建立。

## 3. 2026年5月Cash手工收入证据

Cash侧交易表没有`approved/received/reversed`状态列。下表“存在”仅表示正式Cash交易行存在，且`transaction_type=income`、`created_by_external=false`、无School external reference；不能把它改称School同步收入。

| 学生 | 固定planned | Cash transaction ID | 日期 | 金额/币种 | 匹配依据 | 证据等级 |
|---|---:|---|---|---:|---|---|
| 厦门吕同学 | 8 | 未定位 | — | — | 业务负责人最终确认；全库姓名/“5月课时费”及2026-04至06全部手工income窗口均未命中对应收入行 | `BUSINESS_CONFIRMED_DB_ROW_NOT_LOCATED` |
| 彭宇晗 | 8 | `4b3f1168-af58-4c1a-a28e-6277e8fe2222` | 2026-05-08 | CNY 8,853 | 描述`彭宇晗5月课时费`；手工income；姓名和月份一致 | `HIGH_STUDENT_MONTH_LEVEL` |
| 李天伦 | 14 | `c3ee3c59-fb68-46af-8c44-8fe08cb81c1f` | 2026-05-08 | CNY 21,450 | 描述`李天伦5月课时费`；手工income；姓名和月份一致 | `HIGH_STUDENT_MONTH_LEVEL` |

没有把JPY candidate金额与CNY实收金额自行换算或强行逐课分摊。两条命中记录证明的是学生/月级历史收款，不是planned级Cash relation。检索未发现同名重复手工学费income或显式反向行；但由于Cash表没有状态/撤销字段，本报告不把“未检出”扩大解释为数据库级不可撤销证明。

厦门吕同学8条仍按业务负责人最终确认归类为已收费，不因School/Cash行未定位而改为未收费；其证据包必须明确保存“业务批准、Cash行未定位”，不得伪造Cash UUID。

## 4. 2026年6月School income → Cash同步证据

6月存在4笔School received income。每笔在School侧各有1条`synced` linkage；Cash侧各有且仅有1个`approved` external request和1条`created_by_external=true` income交易，external reference精确回指School income。

| 学生 | School income | School linkage | Cash request | Cash transaction | 金额/币种 |
|---|---|---|---|---|---:|
| 厦门吕同学 | `ac685f46-e924-435f-99e9-6797cca7e922` | `18480a0c-6b5b-4f39-9c3c-d148833f4d41` | `93c36048-754a-491b-8a52-8e987b4efc07` | `1d89c880-afd3-484a-ba73-3f158fef44de` | CNY 7,740 |
| 彭宇晗 | `4906423c-ea9f-454b-96be-898f4173f5b3` | `99f8fe36-834b-4fb7-8320-168d0dfcd397` | `0cacdde8-4283-4bfc-ad1b-4c0bf99294be` | `bf23f6f2-4591-4b5d-9923-2fbf7d34e556` | CNY 6,491 |
| 彭宇晗（补交） | `dbfe482b-a792-4368-87fa-4058f6b14436` | `0f49d850-7c76-4d31-841e-5d692f6cc332` | `1bee7599-42e0-4fc1-8a3d-47e0f64f70bc` | `d479512b-9ae5-430e-b371-e530cbc281d8` | CNY 715 |
| 李天伦 | `53fb579d-c924-4c81-a994-2dc6c42ab5fc` | `712fbc0a-c2af-45e1-9adb-b4d3db78638f` | `a7acec4c-235c-4f41-9a9b-3957fb63a999` | `fe6ef851-a33f-4ba9-aac9-b40fcbf9b54d` | CNY 21,450 |

Cash四条交易均为`external_source=aozora_school`、`external_reference_type=school_income_records`、`external_event_type=tuition_income_received`。这证明6月不是未收费或放弃追收。

限制：四笔收入都是学生/月级事实，不含planned ID清单；School也没有6月tuition bill、bill relation或billing identity。因此不能仅靠现有income行唯一推导34条planned映射。固定64人工决定与原始TSV集合是planned级排除范围，School/Cash链是学生/月级收费佐证。

## 5. 现有永久排除机制

当前candidate reader在[`school_tuition_r2_b_candidate_f1_source_compatibility.sql`](../sql/current/school_tuition_r2_b_candidate_f1_source_compatibility.sql)的`evidence_rows`中读取bill relation、bill snapshot、billing identity和`school_student_tuition_historical_lesson_exclusions`；存在后者时直接分类为`historical_paid_exclusion`。部署函数签名为`school_list_student_tuition_candidates(uuid,uuid,text,boolean)`，本轮读取到的定义MD5为`788ffc50c559116653e4fdb07d6db851`。

现有历史排除表定义和guard位于[`school_tuition_r1d_c_c_b_historical_42_exclusion_schema_backfill.sql`](../sql/current/school_tuition_r1d_c_c_b_historical_42_exclusion_schema_backfill.sql)：

- 当前只有42行；本次固定64重叠0行。
- `planned_lesson_id`和`linked_actual_lesson_id`唯一，UPDATE/DELETE/TRUNCATE全部拒绝。
- `locked_settlement_id`、`received_tuition_income_id`、`school_account_transaction_id`均为非空School FK。
- source/report/manifest/evidence class均被CHECK固定为旧42值。
- insert guard只接受`school_r1d_c_c_b_fixed_42_manifest()`中的精确行。
- service_role只有SELECT，无INSERT/UPDATE/DELETE；anon/authenticated无表权限。

结论：现有概念和reader authority正确，但证据合同只覆盖旧42。5月Cash-only证据无法满足三个School非空FK；6月虽有School income和Cash linkage，仍无settlement、School account transaction、bill及planned级映射，也不在固定42 manifest。两个月都不能通过伪造或复用不匹配role/source处理。

| 范围 | 当前candidate | 现有模型可安全直接处理 | 需要扩张批准 | 矛盾 | 未确认业务决定 |
|---|---:|---:|---:|---:|---:|
| 2026-05 | 30 | 0 | 30 | 0 | 0 |
| 2026-06 | 34 | 0 | 34 | 0 | 0 |
| **合计** | **64** | **0** | **64** | **0** | **0** |

## 6. 精确业务模型扩张proposal contract

### 6.1 推荐方向

扩展现有`public.school_student_tuition_historical_lesson_exclusions`，不新建第二张排除表。candidate reader继续只认这一张表中的planned级不可变排除事实，因此不会形成第二套收费口径，也无需在reader中写死64 UUID、备注判断或COALESCE fallback。

### 6.2 Business-model expansion declaration（待批准）

```text
New tables: none
New columns:
  public.school_student_tuition_historical_lesson_exclusions.evidence_profile_code text not null
  public.school_student_tuition_historical_lesson_exclusions.lesson_complete_row_hash text null
  public.school_student_tuition_historical_lesson_exclusions.external_evidence_snapshot jsonb not null
  public.school_student_tuition_historical_lesson_exclusions.external_evidence_sha256 text null
New enum/status values (CHECK-controlled text):
  evidence_profile_code = SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1
  evidence_profile_code = CASH_MANUAL_INCOME_MATCHED_V1
  evidence_profile_code = CASH_MANUAL_INCOME_OWNER_CONFIRMED_UNLOCATED_V1
  evidence_profile_code = SCHOOL_INCOME_CASH_SYNC_V1
  evidence_class_code = business_owner_final_confirmed
New date/month/attribution concepts: none
New identity concepts: none
New source concepts:
  approval_source_code = approved_20260802_64_already_charged_manifest
New snapshot/version concepts:
  immutable external_evidence_snapshot（仅审计School/Cash证据，不是Cash operational authority）
  approval_report_version = school-v2-2026-05-06-64-already-charged-final-review-20260802-v1
  manifest_version = school-v2-2026-05-06-fixed-64-already-charged-20260802-v1
New writable facts: 64条planned的一次性、append-only historical_monthly_tuition_paid排除事实
Changed existing-field semantics:
  locked_settlement_id / received_tuition_income_id / school_account_transaction_id
  从所有profile一律必填改为由明确evidence_profile_code决定必填组合；旧42 profile语义不变
Changed field mutability:
  上述三个字段允许NULL，但整行仍永久immutable；profile CHECK禁止模糊组合
Changed writer authority:
  insert guard新增且只新增固定64 manifest；仅部署owner一次性写入；无API/RPC/page writer
Changed reader authority: none；现有historical exclusion表仍是唯一planned级历史收费排除权威
Changed locking rules: none；UPDATE/DELETE/TRUNCATE继续拒绝
New authoritative sources:
  固定64 manifest仅作为一次性writer authority；提交后表中immutable行是生产reader authority
Legacy fallbacks or dual-read rules: none
Dual-write behavior: none
Historical reinterpretation:
  仅固定64 planned按业务负责人最终决定记录为historical_monthly_tuition_paid；不创建或修改bill/income/Cash/settlement/wage
Destructive schema changes: none
```

### 6.3 Evidence profile合同

1. `SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1`仅代表现有42行。三个School FK继续全部非空，旧source/report/manifest/hash语义保持原样；新增列用常量默认和profile CHECK兼容旧行，不更新旧42业务事实。
2. `CASH_MANUAL_INCOME_MATCHED_V1`仅用于5月已定位Cash行的22条planned。三个School FK必须为空；snapshot必须冻结Cash表名、transaction ID、日期、币种、金额、transaction type、description、`created_by_external=false`、本轮查询时间及学生/月匹配范围。
3. `CASH_MANUAL_INCOME_OWNER_CONFIRMED_UNLOCATED_V1`仅用于厦门吕同学5月8条。三个School FK和Cash transaction ID必须为空；snapshot必须明确记录“业务负责人最终确认已收费、只读检索范围、未定位Cash行”，不得生成占位UUID。
4. `SCHOOL_INCOME_CASH_SYNC_V1`仅用于6月34条。snapshot必须冻结每个学生/月对应的School income ID/status、School linkage ID/status、Cash request ID/status、Cash transaction ID/金额/币种/external metadata；School bill ID和planned级relation必须明确为空。
5. 所有新64行必须保存当前完整planned row hash、linked completed actual、固定人工决定、normalized备注、evidence snapshot SHA-256和整行evidence hash。备注只供人读，machine decision只使用profile/source/version/manifest及hash。

### 6.4 Writer、reader、ACL与防伪

- 新建固定函数`public.school_20260802_fixed_64_already_charged_manifest()`，内嵌精确64 planned ID、baseline hash、student/entity/month、linked actual、evidence profile和完整evidence hash；不得通过动态candidate查询扩大清单。
- 修改现有`school_guard_tuition_historical_lesson_exclusion_insert()`：旧42只匹配旧manifest；新64只匹配新manifest；任何交叉版本、缺行、额外行、hash或证据包差异均fail closed。
- 不新增普通writer、API或RPC。仅迁移SQL以数据库owner一次性INSERT。service_role维持SELECT-only；anon/authenticated无权限；不新增RLS写策略。
- candidate reader无需改业务分支：继续按现有表中`planned_lesson_id`存在性返回`historical_paid_exclusion`。bill/income生成仍只消费candidate reader结果。
- Cash UUID属于跨库冻结审计证据，School DB不能建立跨库FK；防伪依靠批准前双库SELECT、固定manifest、snapshot SHA-256、insert guard、不可变触发器及迁移报告hash，不把School snapshot提升为Cash余额或交易状态authority。

### 6.5 迁移、验收、rollback与retirement

- 固定迁移对象只能是ID集合SHA-256 `7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85`的64条。开始时重新冻结School `clock_timestamp()`为唯一`evidence_recorded_at`，并复核64个row hash及School/Cash证据hash；任一漂移即停止。
- rehearsal在单一事务中执行完整INSERT与post-check后`ROLLBACK`；正式执行也必须在单一事务内完成全部preflight、INSERT、候选归零和非目标hash检查后才COMMIT。
- 正式提交后行级UPDATE/DELETE/TRUNCATE仍被拒绝，因此不存在普通“提交后删除回滚”。如固定清单或业务事实错误，只能由业务负责人另行批准显式纠错模型；不得绕过immutable guard。
- postdeploy必须验证：表42→106行；固定64全部且仅有64条；5月/6月这六个scope candidate 64→0；排除理由均为`historical_paid_exclusion`；其他月份candidate集合hash不变；bill/income/linkage/Cash/settlement/wage行数和hash不变；Gate不变。
- monitoring固定检查106行总数、64 manifest hash、profile分布22/8/34及候选泄漏0。任何新行或hash漂移报警。
- retirement条件：正式迁移和两轮postdeploy通过后，撤销/删除一次性fixed64 manifest及可写入口，insert guard回到“拒绝所有新manifest”；排除表和64条immutable事实永久保留。后续正常收费只走atomic bill chain，不得复用这些历史profile。

### 6.6 影响范围

- 影响：固定64 planned从candidate reader中永久排除，tuition preview不再列出；以后generate即使解Gate也不能再次收费。
- 不影响：planned金额/月/状态、actual、待补、工资、settlement、School bill/income/account transaction、Cash请求/交易、其他月份candidate及atomic writer。
- 不伪造：不创建School bill/income/relation/identity/settlement/account transaction；不把5月Cash手工行伪装成School atomic income；不把6月学生/月income声称为既有planned级relation。

该proposal属于明确业务模型扩张，当前任务没有批准以上对象和值；必须逐项批准后才能起草或执行DDL/DML。

## 7. 输出文件

- 规范化人工审核结果：`docs/school-v2-2026-05-06-tuition-candidate-manual-review-normalized-20260802.tsv`
- 64条最终分类：`docs/school-v2-2026-05-06-tuition-candidate-permanent-exclusion-classification-20260802.tsv`
- 本调查报告：`docs/school-v2-2026-05-06-64-already-charged-permanent-exclusion-investigation-20260802.md`

分类TSV共64行、27列，SHA-256 `c90c7778eaf0040b937daaceb70124374bc7f536ff3f02e3f07527314418d73e`；证据类型分布为`CASH_MANUAL_INCOME=22`、`BUSINESS_OWNER_CONFIRMED=8`、`SCHOOL_INCOME_CASH_SYNC=34`；`current_candidate=true`为64，`existing_model_can_exclude=false`为64。

## 8. 执行与保护状态

- 数据库连接：School DB只读、Cash DB只读；未连接或写入其他数据库。
- SQL：仅执行`SELECT`、catalog查询和只读函数调用；没有执行仓库SQL迁移文件。临时只读查询位于`/private/tmp/school_v2_*`，不属于交付物。
- 只读RPC/函数：调用`school_list_student_tuition_candidates(uuid,uuid,text,boolean)`；未调用写RPC。
- 数据库写入：0；测试白名单写入0；测试记录ID不适用。
- 真实bill/income/Cash提交：0。
- Git：未add、未commit、未push。
- Gate最终值：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=blocked`。
- 保护文件：未读取正文、未修改、未暂存；最终SHA-256须保持`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。
