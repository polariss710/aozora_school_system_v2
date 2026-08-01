# School V2 2026年5–6月64条历史tuition candidate人工核对清单

## 结论与冻结信息

本轮只读调查在开始时得到精确`2026-05=30 / 2026-06=34 / 合计64`，因此继续生成固定清单；范围没有动态扩大。

| 冻结项 | 值 |
|---|---|
| 查询时间（UTC） | `2026-08-01 14:22:08.134118+00` |
| candidate ID集合SHA-256 | `7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85` |
| ID + before row hash + reader row hash清单SHA-256 | `1c612c3ce0d396b504ea0dcd83599661fe9e2f7161bbede56967a884084079fd` |
| TSV SHA-256 | `5f2c7320568630b2e04af8bd8b7d593f7dd80a6cee1df7fa57c541775bd53ddc` |
| TSV结构 | 43列、64数据行、逐行MD5 `before_row_hash`、0个错列行 |

固定审核文件：

- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-20260801.tsv`
- 只读复核SQL：`sql/current/school_tuition_2026_05_06_candidate_manual_review_readonly.sql`

`manual_decision`和`manual_note`全部为空。Codex建议不是业务决定，也未用于任何数据库写入。

## 口径说明

- ID集合来自当前`school_list_student_tuition_candidates(..., false)`；费用字段来自同一固定ID在`school_list_student_tuition_charge_candidates(..., false)`中的DB权威结果。
- `base_fee_jpy / aircon_fee_jpy / course_total_jpy`不是本地计算；本批权威结果均为空调费0，基础费等于课程总额。
- 直接bill relation按planned ID取证；同月正式bill按同学生、同月份的active `draft/income_created`账单取证。
- 历史tuition income按同学生、`coalesce(settlement_month, year_month)`和`income_category=tuition`取证，不用planned迁移后的业务实体硬过滤；income原业务实体保留在`legacy_income_or_cash_evidence`。这是只读审核口径，不改变任何生产reader authority。
- School Cash仅读取`school_personal_cash_income_linkage_events`；未连接Cash DB。账户流水仅读取School的`school_account_transactions`。
- `lesson_count`原值在多组历史导入中呈`1,2,3...`序号形态。本报告原样汇总为219，但不能把它直接解释为64个课时条目；固定记录数为64、小时为129。该字段的数据语义需人工核对，本轮不重解释或修改。

## 总体汇总

| 指标 | 2026-05 | 2026-06 | 合计 |
|---|---:|---:|---:|
| planned记录 | 30 | 34 | 64 |
| `lesson_count`原值合计 | 103 | 116 | 219 |
| 小时 | 60.5 | 68.5 | 129.0 |
| 基础费JPY | 650,500 | 729,500 | 1,380,000 |
| 空调费JPY | 0 | 0 | 0 |
| 总额JPY | 650,500 | 729,500 | 1,380,000 |

证据覆盖：

| 指标 | planned数量 | 唯一底层证据数量 |
|---|---:|---:|
| 有linked actual | 64 | 64个actual，状态均为`completed` |
| 有直接bill relation | 0 | 0 |
| 有同月active tuition bill | 0 | 0 |
| 有同月tuition income | 34 | 4个received income |
| 有School Cash linkage或账户流水 | 34 | 4个School Cash linkage；0个account transaction |

4个唯一历史收入及School侧Cash证据：

| 学生 | 月份 | income | 状态/金额 | School Cash linkage |
|---|---|---|---|---|
| 厦门吕同学 | 2026-06 | `ac685f46-e924-435f-99e9-6797cca7e922` | received / 个人名义 / CNY 7,740 / 6月课时费 | `18480a0c-6b5b-4f39-9c3c-d148833f4d41` |
| 彭宇晗 | 2026-06 | `4906423c-ea9f-454b-96be-898f4173f5b3` | received / 个人名义 / CNY 6,491 / 6月课时费 | `0f49d850-7c76-4d31-841e-5d692f6cc332` |
| 彭宇晗 | 2026-06 | `dbfe482b-a792-4368-87fa-4058f6b14436` | received / 个人名义 / CNY 715 / 补交6月学费 | `99f8fe36-834b-4fb7-8320-168d0dfcd397` |
| 李天伦 | 2026-06 | `53fb579d-c924-4c81-a994-2dc6c42ab5fc` | received / 个人名义 / CNY 21,450 / 6月课时费 | `712fbc0a-c2af-45e1-9adb-b4d3db78638f` |

## 按学生和月份汇总

| 学生 | 月份 | 记录 | lesson_count原值 | 小时 | 基础费JPY | 空调费JPY | 总额JPY |
|---|---|---:|---:|---:|---:|---:|---:|
| 厦门吕同学 | 2026-05 | 8 | 36 | 16.0 | 144,000 | 0 | 144,000 |
| 彭宇晗 | 2026-05 | 8 | 20 | 16.0 | 136,000 | 0 | 136,000 |
| 李天伦 | 2026-05 | 14 | 47 | 28.5 | 370,500 | 0 | 370,500 |
| 厦门吕同学 | 2026-06 | 10 | 55 | 20.0 | 180,000 | 0 | 180,000 |
| 彭宇晗 | 2026-06 | 9 | 9 | 18.0 | 153,000 | 0 | 153,000 |
| 李天伦 | 2026-06 | 15 | 52 | 30.5 | 396,500 | 0 | 396,500 |

## 按学生、月份和自然周汇总

| 学生 | 月份 | 周一 | 记录 | lesson_count原值 | 小时 | 基础费JPY | 空调费JPY | 总额JPY |
|---|---|---|---:|---:|---:|---:|---:|---:|
| 厦门吕同学 | 2026-05 | 2026-05-04 | 2 | 3 | 4.0 | 36,000 | 0 | 36,000 |
| 厦门吕同学 | 2026-05 | 2026-05-11 | 2 | 7 | 4.0 | 36,000 | 0 | 36,000 |
| 厦门吕同学 | 2026-05 | 2026-05-18 | 2 | 11 | 4.0 | 36,000 | 0 | 36,000 |
| 厦门吕同学 | 2026-05 | 2026-05-25 | 2 | 15 | 4.0 | 36,000 | 0 | 36,000 |
| 彭宇晗 | 2026-05 | 2026-05-04 | 2 | 2 | 4.0 | 34,000 | 0 | 34,000 |
| 彭宇晗 | 2026-05 | 2026-05-11 | 2 | 4 | 4.0 | 34,000 | 0 | 34,000 |
| 彭宇晗 | 2026-05 | 2026-05-18 | 2 | 6 | 4.0 | 34,000 | 0 | 34,000 |
| 彭宇晗 | 2026-05 | 2026-05-25 | 2 | 8 | 4.0 | 34,000 | 0 | 34,000 |
| 李天伦 | 2026-05 | 2026-05-04 | 1 | 1 | 2.0 | 26,000 | 0 | 26,000 |
| 李天伦 | 2026-05 | 2026-05-11 | 5 | 10 | 8.0 | 104,000 | 0 | 104,000 |
| 李天伦 | 2026-05 | 2026-05-18 | 4 | 15 | 9.0 | 117,000 | 0 | 117,000 |
| 李天伦 | 2026-05 | 2026-05-25 | 4 | 21 | 9.5 | 123,500 | 0 | 123,500 |
| 厦门吕同学 | 2026-06 | 2026-06-01 | 2 | 3 | 4.0 | 36,000 | 0 | 36,000 |
| 厦门吕同学 | 2026-06 | 2026-06-08 | 2 | 7 | 4.0 | 36,000 | 0 | 36,000 |
| 厦门吕同学 | 2026-06 | 2026-06-15 | 2 | 11 | 4.0 | 36,000 | 0 | 36,000 |
| 厦门吕同学 | 2026-06 | 2026-06-22 | 2 | 15 | 4.0 | 36,000 | 0 | 36,000 |
| 厦门吕同学 | 2026-06 | 2026-06-29 | 2 | 19 | 4.0 | 36,000 | 0 | 36,000 |
| 彭宇晗 | 2026-06 | 2026-06-01 | 3 | 3 | 6.0 | 51,000 | 0 | 51,000 |
| 彭宇晗 | 2026-06 | 2026-06-08 | 3 | 3 | 6.0 | 51,000 | 0 | 51,000 |
| 彭宇晗 | 2026-06 | 2026-06-15 | 3 | 3 | 6.0 | 51,000 | 0 | 51,000 |
| 李天伦 | 2026-06 | 2026-06-01 | 4 | 5 | 8.0 | 104,000 | 0 | 104,000 |
| 李天伦 | 2026-06 | 2026-06-08 | 5 | 14 | 9.5 | 123,500 | 0 | 123,500 |
| 李天伦 | 2026-06 | 2026-06-15 | 4 | 18 | 8.0 | 104,000 | 0 | 104,000 |
| 李天伦 | 2026-06 | 2026-06-22 | 2 | 15 | 5.0 | 65,000 | 0 | 65,000 |

## Codex建议分类

| 建议 | 数量 | 依据 |
|---|---:|---|
| `LIKELY_ALREADY_CHARGED` | 34 | 全部为2026-06；虽无直接bill relation或formal bill，但同学生同月有received tuition income、School Cash linkage及completed actual。income原实体为个人名义，与planned当前青空进学塾实体不同，故仍需人工逐条归属。 |
| `LIKELY_UNCHARGED` | 30 | 全部为2026-05；均有completed actual且无测试/作废信号，但School侧未见直接relation、同月bill/income、Cash linkage或账户流水。仍需排除系统外或未录入的历史收款。 |
| `LIKELY_TEST_OR_VOID` | 0 | 无匹配状态或测试标记。 |
| `NEEDS_MANUAL_REVIEW` | 0 | 建议规则可以给出倾向，但所有64条仍必须由业务负责人填写最终决定。 |

## 相互矛盾证据

以下34条同时满足“当前canonical reader判为candidate”与“同学生2026-06已有received tuition income + School Cash linkage”，且没有planned直接bill relation；收入原业务实体均为`个人名义`，planned当前业务实体为`青空进学塾`。这是本批最关键的收费证据冲突：

- 厦门吕同学：`13b08cc6-720b-4002-9207-1f5b8bd64ae5`, `550553ae-be7c-4577-9f04-43b1feaae48d`, `727304b4-19d4-478d-ac5f-700262e09e1d`, `9cea7b9b-7f7a-4c18-be2e-74c8ee68ef6c`, `88995922-a375-427d-a56f-6cd838312c96`, `bfc41de1-f186-4676-9955-e93fc100c6bc`, `bf10cbe0-8fd5-4d0a-b2e4-64a2bb65de8e`, `f8c94de2-92be-4b93-baba-3f70d89e00c4`, `7de38e7a-233a-47e2-b2b8-726ed5a0d37d`, `f495da4a-71c0-49a3-81ed-5834b3b983bb`。
- 彭宇晗：`8a6fad1b-7d34-463b-b2ec-e4c95e68cd24`, `4aa7c6ef-ef3f-4c4f-9a52-58948d07aacc`, `5f1babca-be7b-43c8-a7de-2379a6c573aa`, `0afbc656-29e8-4583-8ff0-67450623a859`, `ec0610ed-ddf4-4942-bdab-65f69c77274f`, `43a8e403-88cc-4c50-bce5-b6a96df763ae`, `f4b7c125-8cba-4654-9657-1ebdfc3520b7`, `fffb0867-77c3-4643-8969-1d8e2d063ac1`, `fff47dbd-f4ca-4c3e-b4a9-aa0515655a12`。
- 李天伦：`ce991343-9a45-4a77-bd09-bb37a8b7692e`, `644d3126-d563-48de-97da-b8665d511bd2`, `316fdd57-277c-425a-80ec-39cea197f00a`, `4e2c7294-6cec-42a4-a91a-5d8c8339e677`, `09a4f5cf-65ae-400f-b7c6-4dd59d27bf3d`, `4015d1e6-c3bd-4dca-8e0f-4eba15f5252a`, `06e49b97-234d-4233-8548-b2636bdf851d`, `e96e59f5-6ec5-49cc-a0b3-33021a0b68fc`, `0a6a9f56-d2b8-40fd-b0e4-502773f648b6`, `47d73896-4b17-431e-83ba-38ee36a3fa5b`, `2073ff43-e70e-4e1f-8097-61ab9e151e11`, `5dbf82b5-4c85-40f6-80e2-976f6936c64c`, `6c44b0c6-bc45-4262-baa5-fe95c31e3852`, `14e5ac8c-d4f6-4bce-b0d4-28399d5f57cb`, `8ca07718-b50d-44a6-be39-2b838c13b69b`。

另有24条6月导入行的文件名明确为6月课时表，但`source_note`含“完整课时导入：李4月课时”：厦门吕同学上述10条，以及李天伦上述15条中除`0a6a9f56-d2b8-40fd-b0e4-502773f648b6`外的14条。该备注冲突已原样保留，不能据此自动改变月份或收费判断。

## 人工填写方法

1. 用Excel、Numbers或其他支持UTF-8 TSV的工具打开TSV；不要另存为会丢失UUID精度或改变编码的格式。
2. 只填写`manual_decision`和`manual_note`两列，不改`planned_id`、`before_row_hash`及其他证据列。
3. `manual_decision`仅填写：`ALREADY_CHARGED_EXCLUDE`、`UNCHARGED_KEEP_CANDIDATE`、`TEST_OR_VOID_EXCLUDE`或`UNDECIDED`。
4. 建议先审核34条`LIKELY_ALREADY_CHARGED`，按历史收入覆盖的具体课时确认；再审核30条`LIKELY_UNCHARGED`是否存在系统外或未录入收款。
5. 填写完成后保留原TSV并另存一个带决定的副本，供后续独立proposal与实施审查使用。本轮不会读取人工决定写库。

## 执行边界与状态

- 仅连接School DB执行`SELECT`及两个只读reader函数；未调用任何写RPC。
- 未连接Cash DB；未执行DDL/DML；未修改lesson、candidate、bill、income、Cash、账户流水或Gate。
- Gate应保持`student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=blocked`；最终值另行只读复核。
- 本轮新增本地TSV、Markdown及只读SQL；未git add、commit或push，停在人工审核点。
