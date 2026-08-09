# School V2 2026-07 历史零结转完成证据与工资 effective resolver 实施报告

日期：2026-08-09（Asia/Tokyo）

范围：获批 schema、不可变证据 writer/wrapper、effective resolver、工资只读 preflight、两个工资生成 overload 的共享合同，以及4条获批真实历史完成证据。即使最终 preflight 通过，本阶段也没有生成老师工资、支付请求、支出或 Cash 请求。

## 1. 结论

1. 4条 `2026-07 / 青空进学塾 / final carry CNY 0` 历史完成证据均已通过正式本机 `service_role` wrapper逐条创建，并冻结唯一的课时、待补课、2026-08 active revision、bill、received income、approved Cash request和Cash transaction事实。没有补建、保存或锁定普通学生月结。
2. 单一 effective resolver 已上线：普通 locked、历史账单已消费、获批历史零结转证据分别解析为 `ordinary_locked`、`historically_consumed_immutable`、`historical_zero_carry_complete`；否则为 `incomplete`。禁止跨 business entity fallback。
3. 张倬闻现在由既有历史消费事实解析为 effective 完成；其物理 settlement `b699209d-2f61-4cfa-959b-45686e2fe19b` 仍为 `unlocked`，普通月结和下游财务事实均未修改。
4. 彭宇晗课时 `145a8219-0fcf-4e0b-8230-c6a092668836` 由唯一 active `no_wage` 规则解析：保留候选课时与30分钟，`pay_hours=0`、`lesson_wage_jpy=0`，跳过学生月结前置检查；没有创建跨归属证据或通用 fallback。
5. 正式只读工资 preflight 达到预期：56条 actual、8名老师、6660分钟；missing rule、duplicate rule、incomplete lesson、学生月结 blocker、active工资锁及既有工资明细全部为0；11条/1230分钟 `no_wage`；条件计薪90.5小时、JPY 410,750。
6. 数据库已经具备在“新的单独业务授权”下生成2026-07老师工资的技术前提。本轮没有调用工资 writer，仍需等待负责人明确授权。
7. School既有业务表、Cash、Storage及Gate均未漂移；唯一生产业务行新增为本阶段获批的4条历史完成证据。

## 2. 实时基线

| 项目 | 实施基线 |
|---|---|
| 分支 | `main` |
| 初始 HEAD | `4e500c149ae5691b58cbd30044e2e7aec538ed67` |
| fetch后 `origin/main` | `4e500c149ae5691b58cbd30044e2e7aec538ed67` |
| ahead/behind | `0/0` |
| 页面版本 | `v10.5.27`；本阶段没有浏览器运行时代码变化，未升级页面版本 |
| 开始时最新成功 Pages | run `31299192988`，commit `4e500c1` |
| Gate | `student_tuition_cash_submit=enabled`、`student_tuition_generate=blocked`、`student_tuition_preview=enabled` |

没有 reset、rebase、checkout 或回退合法提交。

## 3. 最终对象与签名

### 3.1 Schema

批准的SQL名称：

`public.school_student_monthly_settlement_historical_completion_evidence`

PostgreSQL标识符最多63字节，因此 catalog 物理名为：

`public.school_student_monthly_settlement_historical_completion_evidenc`

两种拼写在本阶段SQL中解析为同一个对象。表共28列，唯一业务identity为 `(student_id, settlement_month, business_entity_id)`；`final_carry_cny=0`、`evidence_version='historical_zero_carry_completion_v1'`；UPDATE/DELETE由immutable trigger拒绝，普通settlement同scope INSERT/identity UPDATE由guard拒绝；RLS启用，PUBLIC/anon/authenticated/service_role表级DML均为0。

### 3.2 函数

| 用途 | SQL调用名称与identity参数 | ACL |
|---|---|---|
| 证据mutation拒绝trigger | `school_reject_historical_zero_carry_evidence_mutation()` | owner-only |
| 普通月结同scope guard | `school_guard_ordinary_settlement_against_historical_zero_carry_evidence()` | owner-only |
| DB权威候选reader | `school_get_student_monthly_settlement_historical_completion_candidate(uuid,text,uuid)` | service_role-only |
| append-only core | `school_create_student_monthly_settlement_historical_completion_evidence_core(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)` | owner-only |
| 本机受信wrapper | `school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)` | service_role-only |
| scope resolver | `school_resolve_student_monthly_settlement_effective_state(uuid,text,uuid)` | authenticated、service_role只读 |
| 既有batch reader | `school_get_student_monthly_settlement_effective_states(uuid[])` | authenticated、service_role只读 |
| 工资共享候选helper | `school_get_teacher_monthly_wage_generation_candidate_facts(text,uuid,uuid)` | owner-only内部helper |
| 正式只读preflight | `school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)` | authenticated active-admin只读 |
| 工资writer | `school_generate_teacher_monthly_wage(text,uuid,uuid)` | authenticated active-admin；本轮未调用 |
| 兼容工资writer | `school_generate_teacher_monthly_wage(text,uuid)` | authenticated active-admin；本轮未调用 |

3个超长函数的 catalog 物理名分别为 `school_get_student_monthly_settlement_historical_completion_can`、`school_create_student_monthly_settlement_historical_completion_`、`school_local_create_student_monthly_settlement_historical_compl`；identity参数与上表完全一致。所有 SECURITY DEFINER 对象均为 `search_path=pg_catalog, public`，没有调用者可控动态SQL；未新增客户端表级DML或浏览器service-role。

## 4. 四条真实不可变证据

共同scope：月份 `2026-07`，business entity `2cf7b72f-6e3c-4d09-80f7-7c58593cd466`（青空进学塾），final carry `CNY 0`；actor `25331ae9-3412-48b9-bdc3-e516caeaeba4`；reason为负责人批准的历史零结转兼容原因。每条先由本机工具执行dry-run及School/Cash双库验证，再通过正式wrapper提交。

| 学生 | evidence UUID / created_at UTC | frozen revision / bill / income | School linkage / Cash request / transaction | 课时与待补冻结 |
|---|---|---|---|---|
| 陈红卓 `eceb2c59-9689-4ec8-9d3f-799b90bfdb27` | `be81b72d-62c7-41f5-9c91-174922fa5318` / `2026-08-09 08:39:32.130993+00` | `96000000-0000-4000-8000-202608031014` / `51f746c5-cede-4609-b845-06ba10d17de5` / `895a7be3-7a38-4744-94f7-e2ac7fdb7cef` | `8409b03b-da12-4462-b856-0e82bf065909` / `dfe3daa5-b81f-4d8d-8e49-564b8fccf5db` / `41369ca2-8f87-4967-822d-1f1dfe5c322b` | lessons 25，lesson hash `ed7a68…`；makeup 1 / 2h，hash `5f316…` |
| 陈加恩 `881dd60c-b92b-44ae-98e1-98448567a8d2` | `15991217-1599-4e48-870e-01b96c8545d4` / `2026-08-09 08:40:06.085457+00` | `96000000-0000-4000-8000-202608031010` / `1b546782-1b39-4c73-a85d-27ab1e5086ad` / `cdf3da68-e578-4f1b-b759-2fff394e1906` | `a3dbdf6f-eacf-469e-b2d6-d13312f4f2ad` / `2d414d6d-96de-40f7-b5fb-8b5c6c870b7c` / `62719969-85d9-45d7-927f-a06fc1208660` | lessons 24，hash `c02c3…`；makeup 2 / 4h，hash `06006…` |
| 李天伦 `a7b163a0-201e-4867-9b94-372343356a80` | `17529eee-d4cc-4590-a73d-28bf661e49b5` / `2026-08-09 08:40:16.742413+00` | `f7150ce5-fb77-4b7f-99f8-207bfbbced91` / `66a1f276-2756-466f-b709-b8ca29063fd9` / `efd670bc-8dba-4926-82c4-2d194281a609` | `81582ebf-dca0-4541-bdca-25a3caef7aaa` / `cd3c277a-801e-4743-9345-1e07b2b31ccf` / `46f135d2-36c5-43eb-b324-bbed9562d54f` | lessons 1，hash `3c94e…`；makeup 2 / 22h，hash `a1c1d…` |
| 袁振轩 `4c6f1473-7d44-467d-a70b-30f02e7cf8cd` | `591f58dd-259e-482e-af49-b6f50a94652f` / `2026-08-09 08:40:27.561114+00` | `96000000-0000-4000-8000-202608031008` / `13bc7bc1-4f93-4b7c-b447-a8ec595953d1` / `54b281ee-78ce-47ab-8fd2-f17791230698` | `a843f76e-07af-4d8f-92d8-d6b5082f2059` / `cfa29d05-cd16-493e-ad39-9b86acf63735` / `d394dd20-d726-4c34-8df0-28342c457d8b` | lessons 2，hash `616d6…`；makeup 0 / 0h，hash `4f53c…` |

证据表最终为4行，aggregate fingerprint `9cb22ef4ddd83f7a77c8fcd2e3ab3966`。陈红卓、陈加恩、李天伦的待补余额及全部planned/cancelled actual/ordinary actual保持不变；袁振轩无待补来源。

## 5. Resolver与特殊兼容结果

- 张倬闻 `7aef8061-7037-4881-a847-a2cdb031c0f4`：`historically_consumed_immutable`，source settlement `b699209d-2f61-4cfa-959b-45686e2fe19b`，冻结carry `CNY 107.50`；物理 `unlocked` 未改。
- 陈红卓、陈加恩、李天伦、袁振轩：`historical_zero_carry_complete`，source为各自evidence UUID，carry `CNY 0`。
- 彭宇晗 `145a8219-0fcf-4e0b-8230-c6a092668836`：rule `0940a10f-a292-43f0-903c-92fa3e6a79c0` 为唯一active `no_wage`；effective状态为 `no_wage_not_required`，30分钟仍在候选范围，零值工资明细合同保留。没有建立跨BE evidence。
- 计薪规则仍必须通过scope resolver；若只在其他business entity存在完成事实，稳定阻断码为 `WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH`；完全无完成事实为 `WAGE_EFFECTIVE_SETTLEMENT_MISSING`。

## 6. 最终2026-07工资只读preflight

### 6.1 汇总

| 指标 | 最终值 |
|---|---:|
| candidate actual / teachers / minutes | 56 / 8 / 6660 |
| missing rule / duplicate rule / incomplete lesson | 0 / 0 / 0 |
| no_wage | 11条 / 1230分钟 |
| student settlement blockers / groups | 0 / 0 |
| total blocker | 0 |
| active wage locks / existing wage details | 0 / 0 |
| conditional pay hours | 90.5 |
| conditional amount | JPY 410,750 |

### 6.2 逐老师预览

| 老师 | 候选课时 | 分钟 | 计薪小时 | 预览金额 JPY |
|---|---:|---:|---:|---:|
| 丛琪润 | 3 | 360 | 6 | 30,000 |
| 吴峰 | 14 | 1590 | 6 | 0 |
| 李雯coco | 3 | 420 | 7 | 38,500 |
| 王亚楠 | 7 | 840 | 14 | 77,000 |
| 王黎曦 | 4 | 480 | 8 | 32,000 |
| 田宇辰 | 5 | 600 | 10 | 40,000 |
| 赵天歌 | 12 | 1410 | 23.5 | 129,250 |
| 高若天 | 8 | 960 | 16 | 64,000 |
| 合计 | 56 | 6660 | 90.5 | 410,750 |

吴峰14条中11条/1230分钟为 `no_wage`；这些课时保留在lesson count/minutes中，但pay hours与wage为0。preflight为正式authenticated active-admin只读reader结果；没有调用两个工资生成writer。

## 7. 测试、部署与写入边界

- 静态测试：`scripts/historical-zero-carry-wage-effective-static-test.mjs`通过；shell语法、`git diff --check`通过。
- migration rehearsal：schema＋RPC＋postdeploy在同一事务内执行并明确ROLLBACK；回滚后对象不存在。
- rollback矩阵：ACL/角色、4种resolver、跨BE拒绝、wrapper幂等与payload conflict、UPDATE/DELETE不可变、普通settlement guard、no_wage零值明细、计薪effective前置、工资writer synthetic路径全部通过；`HISTORICAL_ZERO_CARRY_ROLLBACK_MATRIX_PASS`，fixture residue 0。
- 正式部署SQL：
  - `sql/current/school_historical_zero_carry_completion_schema_20260809.sql`
  - `sql/current/school_historical_zero_carry_completion_rpcs_20260809.sql`
  - `sql/current/school_historical_zero_carry_completion_postdeploy_20260809.sql`
- 生产持久DDL/函数写入：新表、索引、constraint、trigger、函数、ACL和comment；没有浏览器运行时代码变化。
- 生产业务DML：仅4条获批evidence，由正式local wrapper逐条INSERT。普通settlement、lesson、makeup、bill、revision、income、Cash、Storage、工资规则、工资锁、工资明细、支出、支付请求和账户流水写入均为0。
- 写RPC调用：正式evidence local wrapper 4次；工资writer 0；普通月结writer 0；Cash writer 0。
- 只读命令中两次shell引号错误及一次旧表名错误均在解析/关系查找阶段失败，没有写入。

## 8. School、Cash、Storage与Gate

### 8.1 School业务指纹

| 对象 | count | 最终fingerprint | 与基线 |
|---|---:|---|---|
| lessons | 744 | `02b9109c53d1a3d320d4c9f8899fdb40` | 相同 |
| ordinary settlements | 18 | `481ffa7ed5173da852f0f28ce66c2e9b` | 相同 |
| bills | 22 | `e50673ac998ee2d84573a076a64d3d42` | 相同 |
| active/history revisions | 20 | `ffdc498a6e256aa29064f021f22e4b00` | 相同 |
| income | 55 | `c55f82c7d62dbe92d0b49714a911a234` | 相同 |
| wage rules | 30 | `97a601d0ea3f8c610f4b50c8acb93b77` | 相同 |
| wage locks / details | 95 / 556 | `7bbe108d3ac73d4f21530793bf141bc6` / `6204dc666b3b8e0f64fac901ecf0686a` | 相同 |
| expenses / payment requests / account transactions | 47 / 51 / 187 | `34a7a32319d8e538ef7997e1ba59c9d4` / `6ce63e69edfa19a020013634b686f5ce` / `00516a76f236d51406c82f37b0e468ee` | 相同 |
| historical evidence | 4 | `9cb22ef4ddd83f7a77c8fcd2e3ab3966` | 本阶段获批新增 |

### 8.2 Cash、Storage、Gate

- Cash全库：requests 43 / `f4b1876e981ef75828600e0c7f0dc371`；CNY 74 / `070c262ec01008d404b424233d2a6e47`；JPY 31 / `95ab7cf8a8d167e9b052d3fc6b64614b`。
- Cash `external_source='aozora_school'`：requests 43 / `f4b1876e981ef75828600e0c7f0dc371`；CNY 37 / `a9ac168e157a00789bd5bff1de469f50`；JPY 3 / `654485db35df0657c0bf7121d464baa3`。approved request orphan、transaction orphan、duplicate request key、duplicate transaction key、duplicate event transaction均为0。
- Storage：buckets 1 / `9b1be72d5b5fb2ac22b7f7b49d9f8f90`；objects 57 / `62fac5521274c58c6f6982a0c690c134`，均不变。
- Gate最终仍为 `student_tuition_cash_submit=enabled / student_tuition_generate=blocked / student_tuition_preview=enabled`，本阶段变化0。

## 9. Git与现场保护

- 实现提交 `1424a13e3e9d9d6aeeb58af3cf2f57345a77bcd7`（`feat: add historical zero carry wage compatibility`）已推送 `main`；对应 Pages run `31304531464` 成功。生产页面仍为 `v10.5.27`；没有前端、页面版本或cache chain变化。
- 实现提交只包含本阶段5个SQL、2个脚本、本报告和`docs/current-status.md`，没有受保护或非任务文件。
- 六份既有受保护untracked文件始终未修改、未移动、未删除、未执行、未暂存、未提交：
  - `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`
  - `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`
  - `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`
  - `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`
  - `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`
  - `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`

## 10. 下一步

当前只剩业务负责人另行授权“生成2026-07老师工资”。授权前应再次执行同一只读preflight并要求 blocker、active lock和existing detail继续为0；随后才可调用正式工资writer。工资生成、工资支付请求、支出及Cash确认应按各自既有受控流程和独立授权执行。2026-08月结继续保持未结算、未修改。
