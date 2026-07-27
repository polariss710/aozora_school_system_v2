# School V2 学费链 P0 R1C-B 实施报告：新候选规则与只读预览权威化

实施日期：2026-07-27
实施范围：仅学费候选课时规则与 `validation_preview_only` 预览权威化
实施前 Git HEAD：`814b9bbd2d563ad260ef087d1baedee05535c0c8`
建议 commit message（仅供审查后授权）：`fix: make tuition candidates exclude prior billing evidence`

## 1. 结论

R1C-B 已完成数据库实施和只读验收，未开始 R1C-C，也未解除任何 R0 gate。

- 新增 DB 内部确定性分类函数 `school_classify_student_tuition_candidate(...)`；
- 新增 service-role-only 结构化候选审计函数 `school_list_student_tuition_candidates(...)`；
- 保持现有公开 preview RPC 签名不变，并改为只聚合候选函数返回的 `candidate` 行；
- normalized bill lesson 与账单 JSON 兼容证据优先于 lesson 当前可变运营字段；
- 任一 normalized/JSON 不一致均返回 `bill_snapshot_conflict` 或在格式无法安全解析时整次请求 fail-closed；
- 普通页面继续调用同名 `school_preview_student_tuition_bill(uuid,text,numeric)`，无 API/page 改动；
- 孙陈锋 2026-08 从旧规则 24 条/48 小时/JPY 408,000 修正为 22 条/44 小时/JPY 374,000；
- 张倬闻保持 30 条/65 小时/JPY 650,000；
- 两组合计 52 条/109 小时/JPY 1,024,000，UUID 集合与 R1C-A audit item 52/52 完全一致；
- 85 canonical / 24 incident / 12 legacy 关系对应课时全部不能重新成为候选；
- 9 bill、42 income、7 identity、121 relation 以及 School/Cash 业务表前后数量和哈希不变；
- 本阶段没有业务表 DML，没有修改任何 lesson、bill、income、Cash、actual、工资或月结记录。

## 2. 调查结论

### 2.1 现行入口与调用链

唯一在用的 preview DB 签名为：

- `school_preview_student_tuition_bill(uuid,text,numeric)`；
- `SECURITY DEFINER`；
- `authenticated` 与 `service_role` 可执行；
- R0 gate 必须为 `student_tuition_preview = validation_preview_only`。

调用链保持：

`income.html` → `js/pages/income-page.js` → `js/api/income-api.js::previewStudentTuitionBill(...)` → `school_preview_student_tuition_bill(...)`。

页面只格式化并展示 RPC 返回的 `planned_lesson_count`、`planned_lesson_hours`、`planned_lesson_fee_jpy` / `bill_amount_jpy`，不补充、过滤、合并或重新计算候选。页面模块没有直接 `.rpc()`；`.rpc()` 位于 API wrapper。

正式生成入口仍为：

1. `school_generate_student_tuition_bill(uuid,text,text)`；
2. `school_generate_student_tuition_bill(uuid,text,numeric,text)`；
3. `school_create_student_tuition_bill_income_record(uuid,date,text)`；
4. `school_create_personal_cash_tuition_income_record(...)`。

四个入口继续在函数起始处由 R0 gate fail-closed 阻断。

### 2.2 旧规则原因

旧 preview 直接从 `school_lesson_records` 按以下条件汇总：

- School；
- 请求学生；
- 学生当前默认业务归属；
- `year_month = 请求月份`；
- `lesson_type = planned`；
- 未作废；
- status 不在 cancelled/voided/void。

它没有检查 `is_billable`、normalized bill lesson、billing identity 或账单 JSON。孙陈锋两条课当前仍是 active/billable planned，日期和 `year_month` 都在 2026-08，业务归属在 R1C-A 后也是青空进学塾，因此旧规则错误地再次纳入。

### 2.3 月份与日期字段

- 当前候选月份字段仍为 `school_lesson_records.year_month`；
- `lesson_date` 是当前课时日期，不等于永久收费身份；
- `school_student_tuition_bills.billing_month` 是账单收费月份；
- `school_student_tuition_bill_lessons` 把 planned lesson 固定关联到历史 bill；
- `school_student_tuition_billing_identities` 固定 canonical student/entity/billing-month identity；
- `week_start_date` 与 `scheduled_lesson_date` 尚未加入 `school_lesson_records`；relation 表相应 snapshot 字段当前也均为空。

R1C-B 不需要新增日期字段：本阶段只用现有 `year_month` 定义请求范围，再以永久 bill lesson / JSON 证据排除已经收费的 planned lesson。更广的日期模型仍留给后续独立阶段。

### 2.4 normalized relation 与 JSON 审计

部署前只读审计结果：

| 项目 | 结果 |
|---|---:|
| 历史 bill | 9 |
| 含 `planned_lesson_ids` JSON array | 9/9 |
| JSON lesson 行 | 121 |
| 非法 UUID | 0 |
| 同一 bill 内重复 UUID | 0 |
| normalized relation | 121 |
| JSON 无 relation | 0 |
| relation 无 JSON | 0 |
| bill/lesson/line_no 不一致 | 0 |
| relation distinct planned lesson | 85 |

因此现有历史证据可以在不修改历史账单、课时或日期的前提下安全完成 R1C-B。

## 3. 新候选规则

### 3.1 结构化审计结果

`school_list_student_tuition_candidates(uuid,uuid,text,boolean)` 返回：

- planned lesson / student / business entity / candidate billing month；
- lesson date 与当前 `year_month`；
- teacher / subject / lesson count / duration / unit price / fee；
- candidate/excluded 与稳定 reason code；
- normalized relation 是否存在、全部 relation roles、关联 bill IDs；
- 可关联的 billing identity IDs；
- JSON snapshot 是否存在、snapshot bill IDs；
- normalized/JSON conflict 标志；
- planned lesson 完整行哈希。

普通 preview 只使用 `p_include_excluded=false` 的候选行。包含事故/legacy 细节的审计模式仅授予 `service_role`；`anon`、`authenticated` 均无执行权限。

### 3.2 稳定原因码与优先级

1. `scope_mismatch`；
2. `bill_snapshot_conflict`；
3. `already_canonical_charged`；
4. `incident_history`；
5. `legacy_history`；
6. `existing_bill_lesson_history`（覆盖以后新增的正式 relation role）；
7. `voided_or_inactive`；
8. `non_billable`；
9. `invalid_or_incomplete_data`；
10. `candidate`。

历史收费证据在 scope 核对之后、status/void/is_billable/字段完整性之前判断。因此 lesson 当前状态变化、income 被取消/拒绝/事故隔离，都不能让已有 bill lesson 重新成为候选。当前 incident-quarantined bill 与 legacy-cancelled bill 均通过实际数据回归验证。

JSON 安全规则：

- 任一 bill 缺少 `planned_lesson_ids`、值不是 array、含不可解析 UUID 或同 bill 重复 UUID，整次候选请求拒绝；
- JSON-only、relation-only、bill ID 集合不一致或 line number 不一致，课时以 `bill_snapshot_conflict` 排除；
- 不使用模糊文本查找，也不依赖 income active 状态。

## 4. 2026-08 修改前后结果

### 4.1 七名学生摘要

下表“旧规则”按部署前函数的原筛选条件从未变化的 lesson 业务数据重放；“新规则”来自正式部署后的 DB 候选函数。

| 学生 | 旧规则 count/hours/JPY | 新规则 count/hours/JPY | 变化 |
|---|---:|---:|---|
| 厦门吕同学 | 0 / 0 / 0 | 0 / 0 / 0 | 无 |
| 孙陈锋 | 24 / 48 / 408,000 | 22 / 44 / 374,000 | 排除2条July canonical |
| 张倬闻 | 30 / 65 / 650,000 | 30 / 65 / 650,000 | 无 |
| 彭宇晗 | 0 / 0 / 0 | 0 / 0 / 0 | 无 |
| 李天伦 | 0 / 0 / 0 | 0 / 0 / 0 | 无 |
| 陈加恩 | 12 / 24 / 216,000 | 0 / 0 / 0 | 12条已有canonical bill |
| 陈红卓 | 0 / 0 / 0 | 0 / 0 / 0 | 无 |

新规则下 2026-08 共披露 14 条 excluded：孙陈锋2条和陈加恩12条，全部为 `already_canonical_charged`。普通 validation 页面只收到 candidate 汇总，不显示历史事故字段。

### 4.2 固定52-ID候选

孙陈锋 22 IDs：

```text
222c4ad5-b6fe-4e4e-b192-8db8c65b61fa
6c70c4c1-1895-453d-b9b0-591e9f004f86
89da310d-4f17-4a40-8315-659838aec59c
9efb8862-e8c5-4f3d-9d55-b0be4317ad19
37a2083e-bb28-45d1-802a-f98f4564887f
63ca3a2b-7c2f-4eed-a997-71840357f8f6
a3ee5595-6dd5-4737-8605-ff5a8d7d0333
ea766c1d-f152-4b3f-9400-0d5b5aa64614
fcbf1be4-567b-4876-9cc6-19cd0d395da0
1df61ad9-742f-4fd6-b883-b3a8bbb0c4e8
68bbce4e-f6bb-45c6-9798-ee72b6f75179
9bdb88c1-9c08-4716-b146-e98cf149978b
fa7883c8-35e6-40bd-92d1-70adcdcce078
1f9c027a-6db2-4aa2-8bef-215f3ed2bbb9
475853f0-2004-4375-ae72-013c5a86987c
6e005bee-2d14-4722-8b76-9dbe7f836e12
cde683d3-06f2-46ec-8b8a-4f2ed4b4962e
e65b7d1d-45b2-4485-ae6d-7000fe92ce78
02b9e85e-2e03-404d-93a6-9bfef3bf186d
0d048cbf-a5f5-458c-88aa-ce0c3a1c667c
196c9d86-500b-4687-a051-88dcc12fa2a9
aa55dc2e-3b1b-4d2d-863f-9f64e84b8578
```

张倬闻 30 IDs：

```text
23d4b46b-eb1c-48b7-8001-d208ce14f08d
637ba833-830f-42a6-81ed-47a6f9902523
7175780c-b179-4f96-a42e-99ba11bdaed8
80384c28-5044-4c56-94cd-5099aa852032
920808f2-5629-4fcc-957c-6bdcee48808e
d06f136e-d4c5-44fb-ae5e-d87efa26bbfb
3db3ad8b-44b6-4be7-a3ea-611362b82488
6997acdc-fec4-4e14-a22b-d9f5291b1e0b
69ecc019-9f8f-474e-8dc9-1dced16e41a6
72ffebba-ecb3-4a96-9550-f02a5f64cf62
c0e9fd95-7833-44ef-a282-61611976b089
e6aaf546-bb9c-4e71-980e-40f78f2e1e11
12d70ee9-8221-4b8e-a01c-61548340c42d
1927b6ba-6ca6-4ef9-b1c0-0246067c7d41
3920fdea-2f9d-4b17-abd0-f788b0d7d29e
95dff1ab-544d-43be-bc0e-a95232f06935
a10744fc-173a-4b25-9bc3-99d6437797c5
a601916b-6add-4be6-adcc-5c232425f686
286344d1-c603-4990-aba3-814996535319
9a76aed4-058f-4801-90b5-b2637387fb3e
9f755093-8f4d-4337-80ed-23d0e555c835
e2540bb3-5c1f-45bc-b964-9727a6ed3e48
ee6c1383-4259-44e0-923c-1ee6b8749820
ee86e691-2c96-48c2-ad57-512f9eef4b3c
01490eb7-1bd7-430a-ba26-3ccc81d45796
80e03531-5eaa-40e1-a435-0132dd62d5c0
8c6da1a7-69a9-45b6-9a77-daa2bfd7f9e9
9efe2def-ff59-467a-bb76-a49537ec8e0f
adc0b06c-eee3-40ca-8992-592f5d4b009b
dbe16731-803b-49db-8cc0-f826e911bb41
```

数据库按 UUID 排序后的 candidate array 与 batch `c1000000-0000-4000-8000-202607279999` 的 52 个 audit item array 使用 `IS DISTINCT FROM` 比较，结果完全相同。

## 5. 跨月课强制验收

| planned lesson | date | exclusion | July bill | relation | 完整行hash |
|---|---|---|---|---|---|
| `8b737b58-cd14-42c5-afd2-34730dcef963` | 2026-08-01 | `already_canonical_charged` | `2a9f1c25-a060-461e-ae10-b02295dec381` | canonical_charge | `21f83674162b1b1ca485912a048bac3c` |
| `685ad45e-b5da-42ca-8f43-7732e8d6e40d` | 2026-08-02 | `already_canonical_charged` | `2a9f1c25-a060-461e-ae10-b02295dec381` | canonical_charge | `2d52e778bfb59a27bb3b28506232217d` |

两条同时存在 normalized 与 JSON 证据，关联 canonical identity `b1000000-0000-4000-8000-202607270001`，两侧证据无冲突。lesson 本身、July bill、income、identity 和 relation 均未修改。

## 6. 测试

### 6.1 DDL rollback

执行 `school_tuition_r1c_b_candidate_preview_rollback_tests.sql`：

1. `BEGIN`；
2. `\ir school_student_tuition_bill_preview_rpc.sql` 安装与正式部署完全相同的三个函数定义/权限；
3. 完成 preview、固定52-ID、跨月、85/24/12、synthetic conflict、void/nonbillable/nonplanned/incomplete、scope 和非active income状态断言；
4. `ROLLBACK`。

结果：

- `R1C_B_ROLLBACK_TESTS_OK`；
- rollback 后两个新函数均不存在；
- 原 preview 定义 MD5 恢复为 `e14f379230eaa7664371bbc73fcaeb9c`；
- 9/42/7/121 数量及哈希恢复一致；
- 业务 DML 0，测试业务记录 0，残留 0。

synthetic conflict 使用纯确定性分类函数输入，不插入或修改任何真实/临时业务行。

### 6.2 正向与负向

- 张倬闻：30/65/650000；
- 孙陈锋：22/44/374000；
- 合计：52/109/1024000；
- candidate UUID = R1C-A 52 audit UUID；
- 两条 July canonical 排除；
- 85 canonical、24 incident、12 legacy 逐 relation role 验证为 excluded；
- normalized-only/JSON-only/line或bill集合 conflict → `bill_snapshot_conflict`；
- voided、inactive、nonplanned、nonbillable、字段不完整均不能成为 candidate；
- wrong student/month 无行，wrong entity 为 `scope_mismatch`，candidate-only 返回0；
- incident-quarantined 与 cancelled income 对应 bill lesson 不会因 income 状态重开；分类函数完全不接受 income status 作为候选输入；
- `authenticated` 角色调用现有 preview RPC 成功返回孙陈锋22/44/374000；
- `anon/authenticated` 无权直接调用包含排除详情的审计函数。

### 6.3 只读脚本中的别名修正

首次 postdeploy 的核心 DO 断言和 52-ID/跨月输出已通过，随后 future inventory SELECT 因 `year_month` 别名歧义停止。该脚本没有 DDL/DML。仅把只读 CTE 别名改为 `audit_month` 后从头重跑，完整通过；正式函数 SQL 未重跑、数据库业务数据未变化。

## 7. 2026-09及以后只读盘点

当前 student 默认业务归属均与这些 future lesson 的个人名义归属不一致，因此新候选函数按请求学生的当前默认业务归属返回 candidate 0，全部以 `scope_mismatch` 排除：

| 月份 | 学生 | candidate | excluded |
|---|---|---:|---:|
| 2026-09 | 张倬闻 | 0 | 24 |
| 2026-10 | 张倬闻 | 0 | 24 |
| 2026-10 | 李天伦 | 0 | 3 |
| 2026-11 | 张倬闻 | 0 | 18 |
| 2026-11 | 李天伦 | 0 | 8 |

这里只是现状盘点；未迁移业务归属、未生成账单、未修改课时，也未处理提示中保留给后续阶段的68条业务清单。

## 8. School/Cash 前后基线

### 8.1 School

| 对象 | 前 count/hash | 后 count/hash |
|---|---|---|
| tuition bill | 9 / `0f0323b79e7ff1c47ff6b90c75477a2d` | 相同 |
| income | 42 / `2a4897b752f272b1f192045418b4940c` | 相同 |
| billing identity | 7 / `4d91a5a1074f90389822fc367a7e5467` | 相同 |
| bill lesson | 121 / `09dfee7d8833e09384fb41a84f2959e0` | 相同 |
| Cash linkage | 35 / `6e76a4dc2fc2954b28b7ad0a8d203ba0` | 相同 |
| account transaction | 185 / `8f4f6c4365035f6c36bac59ba986b28b` | 相同 |
| actual lesson | 229 / `fe752c448bb4d38af498136d3149f14a` | 相同 |
| settlement | 15 / `7925cf3018bd0e669cd29710f6593238` | 相同 |
| wage lock | 95 / `7bbe108d3ac73d4f21530793bf141bc6` | 相同 |
| wage detail | 556 / `6204dc666b3b8e0f64fac901ecf0686a` | 相同 |
| R1C-A audit batch | 1 / `e8c2013a460374be5b2a3b82564876c4` | 相同 |
| R1C-A audit item | 52 / `6399cd2b368e30e5ca43e113957bfa5f` | 相同 |
| R1C-A 52 lessons current full-row aggregate | `13c3217f56b10166770bd0ee15b28e15` | 相同 |

`actual` 数量不是代码或 SQL 中的固定预期；本报告仅记录本阶段前后实际查询时均为229且哈希相同。并发 actual `50ec3900-63ff-4138-85f1-53a999c23daa` 未被修改。

R1B 只读回归同时确认：

- 9/9 bill-income exact pairs；
- 事故 income 仍从普通 operational view 排除、incident audit view 可见；
- 13个相关 guard/consistency trigger 均 enabled；
- 9/9 原 income 业务行哈希恢复验证继续通过。

### 8.2 Cash DB

| 对象 | 前 count/hash | 后 count/hash |
|---|---|---|
| request | 34 / `ba0571247a869843c3ddda9075ea78dd` | 相同 |
| CNY transaction | 59 / `27dfd0cb3bf85c5cc34677372b29502a` | 相同 |
| JPY transaction | 31 / `95ab7cf8a8d167e9b052d3fc6b64614b` | 相同 |

Cash DB 仅执行 SELECT，没有 DDL/DML/RPC。

## 9. R0 gate 与拒绝探针

最终 gate：

- `student_tuition_preview = validation_preview_only`；
- `student_tuition_generate = blocked`；
- `student_tuition_cash_submit = blocked`。

`school_tuition_r1b_r0_entry_probes.sql` 结果：

- 四个生成入口全部返回 `TUITION_GENERATION_BLOCKED`；
- Cash gate 返回 `TUITION_CASH_SUBMISSION_BLOCKED`；
- incident Cash RPC 继续拒绝；
- 拒绝探针无成功写入。

## 10. 文件、SQL/RPC与数据库写入

修改/新增：

- `sql/current/school_student_tuition_bill_preview_rpc.sql`；
- `sql/current/school_tuition_r1c_b_candidate_preview_rollback_tests.sql`；
- `sql/current/school_tuition_r1c_b_postdeploy_readonly.sql`；
- `docs/school-v2-r1c-b-tuition-candidate-rule-report-20260727.md`；
- `docs/current-status.md`。

未修改 API、page、HTML、`js/legacy-core.js` 或 R1C-A 文件。

执行的 SQL 文件：

1. `school_tuition_r1c_b_candidate_preview_rollback_tests.sql`（事务内DDL并ROLLBACK，无业务DML）；
2. `school_student_tuition_bill_preview_rpc.sql`（正式DDL：三个function定义/注释/函数级权限）；
3. `school_tuition_r1c_b_postdeploy_readonly.sql`（SELECT/DO-only；别名修正前后各一次）；
4. `school_tuition_r1b_r0_entry_probes.sql`（预期拒绝，无成功写入）；
5. `school_tuition_r1b_postdeploy_readonly.sql`（只读）；
6. `cash_tuition_r1a_business_baseline_readonly.sql`（Cash只读）。

另执行若干显式 SELECT 用于前后哈希、schema、函数定义/ACL、JSON覆盖、逐学生候选和future inventory。调用的只读函数包括 preview 与两个R1C-B helper；调用的写入口仅为R0拒绝探针，全部在gate/事故守卫处拒绝。

数据库写入分类：

- School：发生函数DDL系统目录写入；
- School业务表DML：0；
- 测试白名单业务数据：未创建，测试ID不适用；
- Cash：0写入；
- 无 bill/income/identity/relation/lesson/actual/Cash/账户/月结/工资数据变化。

## 11. Git停止点

- 未执行 `git add`；
- 未 commit；
- 未 push；
- R1B 临时审查文件 `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` 未修改、未删除、未暂存，仍为未跟踪；本阶段开始与结束核对 SHA-256 均为 `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。

建议审查通过后的精确暂存清单：

```bash
git add -- \
  docs/current-status.md \
  docs/school-v2-r1c-b-tuition-candidate-rule-report-20260727.md \
  sql/current/school_student_tuition_bill_preview_rpc.sql \
  sql/current/school_tuition_r1c_b_candidate_preview_rollback_tests.sql \
  sql/current/school_tuition_r1c_b_postdeploy_readonly.sql
```

建议 commit message：

```text
fix: make tuition candidates exclude prior billing evidence
```

本阶段在数据库实施、验证和文档完成后停止，等待审查；不启动 R1C-C 或其他后续阶段。
