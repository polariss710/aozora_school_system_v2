# School V2 2026年5–6月固定64条已收费planned永久排除实施报告

## 1. 最终结论

业务负责人批准的固定64条历史已收费planned永久排除已经完成正式迁移、两阶段postdeploy验收及一次性writer退役。

- 2026-05：30条全部记录为`ALREADY_CHARGED_EXCLUDE`。
- 2026-06：34条全部记录为`ALREADY_CHARGED_EXCLUDE`。
- 固定ID集合SHA-256：`7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85`。
- `school_student_tuition_historical_lesson_exclusions`由42行变为106行；新增且仅新增固定64行。
- 六个目标学生/月scope的当前candidate由64条降为0，reader理由均为`historical_paid_exclusion`。
- 一次性fixed64 manifest函数已删除，insert guard已永久恢复为拒绝所有新写入。
- 没有修改planned、actual、bill、income、relation、identity、settlement、工资、账户流水、School Cash linkage或Cash DB业务数据。
- Gate保持`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=blocked`。

本轮按要求停止在commit前审查点；没有git add、commit或push。

## 2. 获批业务模型及最终对象

本轮扩展既有唯一权威表`public.school_student_tuition_historical_lesson_exclusions`，没有新建第二张排除表，也没有修改candidate reader的权威路径。

新增列：

| 列 | 最终定义 | 语义 |
|---|---|---|
| `evidence_profile_code` | `text not null` | 受CHECK约束的证据合同；旧42使用`SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1` |
| `lesson_complete_row_hash` | `text null` | 固定planned完整行证据hash |
| `external_evidence_snapshot` | `jsonb not null` | 不可变School/Cash外部审计证据快照，不是Cash operational authority |
| `external_evidence_sha256` | `text null` | 快照规范化SHA-256 |

既有`locked_settlement_id`、`received_tuition_income_id`、`school_account_transaction_id`改为nullable，但是否允许NULL完全由`evidence_profile_code`的CHECK组合决定。旧42 profile继续要求三个School FK全部非空，其历史语义和业务字段没有改变。

获批并实际使用的profile分布：

| profile | 行数 | 合同 |
|---|---:|---|
| `SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1` | 42 | 旧42兼容；三个School FK必填 |
| `CASH_MANUAL_INCOME_MATCHED_V1` | 22 | 5月已定位Cash手工收入；三个School FK为空 |
| `CASH_MANUAL_INCOME_OWNER_CONFIRMED_UNLOCATED_V1` | 8 | 厦门吕同学5月由业务负责人确认已收费、Cash行未定位；不伪造UUID |
| `SCHOOL_INCOME_CASH_SYNC_V1` | 34 | 6月School income、School linkage、Cash request和Cash transaction完整学生/月证据 |

新64行使用：

- `approval_source_code=approved_20260802_64_already_charged_manifest`
- `approval_report_version=school-v2-2026-05-06-64-already-charged-final-review-20260802-v1`
- `manifest_version=school-v2-2026-05-06-fixed-64-already-charged-20260802-v1`
- `evidence_class_code=business_owner_final_confirmed`
- `exclusion_reason=historical_monthly_tuition_paid`

reader仍只依据这张immutable表中的planned ID判断`historical_paid_exclusion`；没有新增fallback、dual-read、第二权威来源或前端业务判断。

## 3. 固定清单与证据冻结

固定证据时间：

- School检查时间：`2026-08-01 15:53:05.021302+00`
- Cash检查时间：`2026-08-01 15:53:05.230504+00`
- 新64行唯一`evidence_recorded_at`：`2026-08-01 15:53:05.021302+00`

固定产物hash：

| 项目 | SHA-256/MD5 |
|---|---|
| fixed64 ID集合 | `7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85` |
| manifest SQL文件 | `94fe290aa6e1e215c2e9e6790b7b0ef5d3aa6420ce03947fb75075fcb2719e77` |
| core SQL文件 | `d737f32e7c03eab16f62741dacbe3f1ef668c22d7484d47eac54b5f5ebb4f7be` |
| 最终fixed64完整行集合 | MD5 `d09fcf2193218fb02c9d3b2b7e7cbb20` |
| 64个evidence hash集合 | `ba0f3114a20fca390c521f2c19bf5a46fedea737028196eb54e46da8ab23e636` |
| 64个snapshot hash集合 | `edcac989e77f748a0972ffea8556d8ffe6c3372e20bebfd164ee443953fcaf13` |

六个学生/月scope的snapshot SHA-256：

| 学生/月 | SHA-256 |
|---|---|
| 厦门吕同学 / 2026-05 | `f9618df6a3969a8c2fde0e3133622ce2d67f84e308f3a40cd2d6a6c82fbc19d2` |
| 彭宇晗 / 2026-05 | `8d11af33cb5b6d57b0997028497a2754c9d69594db5bffbd8adf2f8d8c6bcab8` |
| 李天伦 / 2026-05 | `9d62fb66a1b8bc140e86193a48a5649d431be709cebe790d5fccd481eaf0bf7e` |
| 厦门吕同学 / 2026-06 | `b5369e725bc5fdece06252d2d8acdfab0c2ca5a7751006555b281be7ec2c3d47` |
| 彭宇晗 / 2026-06 | `36c36388754428a8fbae5e19b02c947af818f0b78b08bd09f04caada410d054f` |
| 李天伦 / 2026-06 | `aedda13c2b1a4f6b73fa8baa85b5557a1a89ff966f4d69c5f3dd56c1bb794e3e` |

Cash只读preflight在rehearsal前、正式迁移前和正式迁移后各执行一次，三次结果一致：2条已定位手工收入、4条approved request、4条同步Cash transaction；厦门吕同学5月无伪造或占位Cash行。Cash全表指纹保持：

- `home_cny_transactions`：63行，MD5 `3759e3d726400d5dd2225d79c78b9ac2`
- `home_external_transaction_requests`：34行，MD5 `ba0571247a869843c3ddda9075ea78dd`
- `home_jpy_transactions`：31行，MD5 `95ab7cf8a8d167e9b052d3fc6b64614b`

## 4. 执行流程

### 4.1 同字节rehearsal

`school_tuition_2026_05_06_fixed_64_already_charged_rehearsal.sql`在单事务内执行与正式迁移相同的manifest/core字节，插入64行、完成全部pre/post检查后明确`ROLLBACK`。

回滚后验证：排除表仍为42行；旧42业务字段MD5仍为`680b6e5aaa718569aee4c36fe1cdc058`；新增列不存在；fixed64函数不存在；candidate仍精确64条且ID hash不变；rehearsal残留0。

### 4.2 正式迁移

`school_tuition_2026_05_06_fixed_64_already_charged_migration.sql`在单事务内完成获批DDL、约束、固定manifest writer、64行insert及全部保护对象检查后`COMMIT`。

正式提交后的profile完整行MD5：

- 5月Cash已定位22条：`dabba9038609b5c0c78b56fa2ad01f62`
- 5月业务确认未定位8条：`1165f4a014b69aee190c539ab48b8248`
- 6月School→Cash同步34条：`9a114efbe660e2afaa1f865397537a4a`
- 旧42（含兼容新增列）：`4300a980ce68b8ac37a1e20e5f8e55f7`

### 4.3 两阶段postdeploy与writer退役

第一阶段postdeploy确认106行、42/22/8/34 profile分布、目标candidate泄漏0、reader定义不变及业务表零漂移。

随后执行`school_tuition_2026_05_06_fixed_64_already_charged_retire_writer.sql`：

- 将insert guard替换为永久拒绝`TUITION_HISTORICAL_LESSON_EXCLUSION_INSERT_RETIRED`；
- 删除一次性`public.school_20260802_fixed_64_already_charged_manifest()`；
- 不删除或修改任何历史排除事实。

第二阶段postdeploy再次确认106行全部可读、一次性函数不存在、普通insert被永久guard拒绝且残留0。最终insert guard定义MD5为`942fc49a3e2136cd7b65923abaadadc4`；candidate reader定义MD5始终为`788ffc50c559116653e4fdb07d6db851`。

最终纯SELECT终态采样时间为`2026-08-01 16:09:37.256851+00`：profile仍为42/22/8/34，manifest已退役，两个函数MD5及三项Gate均与第二阶段postdeploy一致。第一次内联终态采样因shell引号导致Gate SELECT解析错误，在任何写入前停止；随后使用`/private/tmp/school_v2_fixed64_final_readonly.sql`完整重跑并通过，两次均无数据库写入。

## 5. Candidate验收

| 学生 | 月份 | 已永久排除planned | 小时 | 总额JPY | 当前candidate泄漏 |
|---|---|---:|---:|---:|---:|
| 厦门吕同学 | 2026-05 | 8 | 16 | 144,000 | 0 |
| 彭宇晗 | 2026-05 | 8 | 16 | 136,000 | 0 |
| 李天伦 | 2026-05 | 14 | 28.5 | 370,500 | 0 |
| 厦门吕同学 | 2026-06 | 10 | 20 | 180,000 | 0 |
| 彭宇晗 | 2026-06 | 9 | 18 | 153,000 | 0 |
| 李天伦 | 2026-06 | 15 | 30.5 | 396,500 | 0 |
| **合计** | — | **64** | **129** | **1,380,000** | **0** |

`include_excluded=true`时64条仍完整返回并全部带`historical_paid_exclusion`，证明不是删除课时或隐藏数据；正常candidate集合中5月0、6月0，因而未来即使另行启用generate也不会重复收费。

## 6. 非目标对象零漂移

正式迁移前、COMMIT内检查、两阶段postdeploy及最终只读检查中的行数/整表MD5均一致：

| 对象 | 行数 | MD5 |
|---|---:|---|
| planned | 417 | `ed7fe80429a9a3c8e745d7b760cab6bb` |
| actual | 245 | `accf575ee9927fc6960420867c4552f5` |
| tuition bills | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income records | 42 | `2a4897b752f272b1f192045418b4940c` |
| bill relations | 121 | `285172fedeb923c67ea9a179480d8692` |
| billing identities | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| settlements | 17 | `1d7328654f6488952dba20640072c3e2` |
| wage locks | 95 | `7bbe108d3ac73d4f21530793bf141bc6` |
| wage details | 556 | `6204dc666b3b8e0f64fac901ecf0686a` |
| School account transactions | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| School Cash linkages | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |

除固定64外的candidate集合为142条，MD5保持`85ef25590d0e17c5d30002a54443cbe5`。没有创建bill、income、Cash request、Cash transaction、settlement、工资明细或测试fixture。

## 7. SQL、函数及数据库执行记录

执行的仓库SQL：

1. `sql/current/school_tuition_2026_05_06_fixed_64_cash_readonly_preflight.sql`：执行3次，仅SELECT，Cash写入0。
2. `sql/current/school_tuition_2026_05_06_fixed_64_already_charged_rehearsal.sql`：School完整rehearsal，最终ROLLBACK。
3. `sql/current/school_tuition_2026_05_06_fixed_64_already_charged_migration.sql`：School正式DDL/64行insert并COMMIT。
4. `sql/current/school_tuition_2026_05_06_fixed_64_already_charged_postdeploy_phase1.sql`：只读第一阶段验收。
5. `sql/current/school_tuition_2026_05_06_fixed_64_already_charged_retire_writer.sql`：School正式退役一次性writer并COMMIT。
6. `sql/current/school_tuition_2026_05_06_fixed_64_already_charged_postdeploy_phase2.sql`：第二阶段验收；insert拒绝测试在内部exception block中执行且无残留。

`school_tuition_2026_05_06_fixed_64_already_charged_manifest.sql`和`..._core.sql`由rehearsal/正式wrapper以相同字节包含执行。

只读调用`public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)`；没有调用写RPC。一次性fixed64 manifest函数仅用于迁移事务，随后已删除。

最终额外执行`/private/tmp/school_v2_fixed64_final_readonly.sql`，仅包含SELECT，用于复核profile分布、Gate、manifest退役及函数MD5；该临时文件不属于仓库交付物。

`school_tuition_2026_05_06_fixed_64_already_charged_audit_rollback_not_executed.sql`仅作为未来需另行明确业务授权的精确审计回滚脚本保存，本轮没有执行。正式历史事实不可通过普通writer删除。

## 8. 最终业务模型声明

```text
New tables: none
New columns: 已按批准新增4列至既有historical exclusion表
New enum/status values: 已按批准新增4个evidence profile及business_owner_final_confirmed受控值
New date/month/attribution concepts: none
New identity concepts: none
New source concepts: approved_20260802_64_already_charged_manifest，仅固定64一次性迁移
New snapshot/version concepts: immutable external evidence snapshot、批准report/manifest版本，均按批准实施
New writable facts: 固定64条append-only historical_monthly_tuition_paid排除事实，已一次性写入；writer已退役
Changed existing-field semantics: 三个School FK改为profile决定必填组合；旧42语义不变
Changed field mutability: 三个School FK列允许NULL，但整行仍永久immutable且受profile CHECK约束
Changed writer authority: 固定manifest一次性owner writer已使用并退役；当前无可写入口
Changed reader authority: none；既有historical exclusion表仍为唯一planned级历史收费排除权威
Changed locking rules: none；UPDATE/DELETE/TRUNCATE继续拒绝
New authoritative sources: none；manifest只是一次性writer authority，提交后immutable行是既有表内权威事实
Legacy fallbacks or dual-read rules: none
Dual-write behavior: none
Historical reinterpretation: 仅固定64条按最终业务决定标记为历史已收费，不创建或改写收费链事实
Destructive schema changes: none

Approval reference:
业务负责人在“School V2 2026年5–6月64条已收费planned永久排除实施批准”中逐项批准上述对象、值、证据profile、一次性writer、迁移、验收与retirement合同。
```

## 9. Git、Gate与保护状态

- 文件：新增本报告和本轮9个SQL文件；更新`docs/current-status.md`。其他工作树变更属于此前同一系列任务并保持未暂存。
- 数据库写入：School仅获批schema/约束、固定64行排除事实及writer退役函数变更；Cash写入0；非目标业务表写入0。
- 测试白名单：未使用测试数据；正式写入对象是业务负责人明确批准的固定64个真实planned ID。rehearsal全部ROLLBACK，postdeploy拒绝测试残留0。
- Git：未add、未commit、未push。
- Gate：`enabled / blocked / blocked`。
- 保护文件`docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`正文未读取、未修改、未暂存；SHA-256保持`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。
- 工作流状态：实施、rehearsal、正式COMMIT、两阶段postdeploy及writer retirement均完成；按要求停在commit前业务审查点。
