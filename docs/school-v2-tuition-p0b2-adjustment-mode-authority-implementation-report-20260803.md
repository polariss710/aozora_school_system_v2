# School V2 学费财务 P0-B2 实施报告：Settlement Adjustment Mode 数据库权威合同

日期：2026-08-03
结论：完成生产部署、精确回滚/重部署、白名单 commit、8 组双会话并发、RPC/ACL/RLS、School/Cash postdeploy 与真实浏览器验收。Gate 保持 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=blocked`，本阶段不构成学费运营恢复授权。

## 1. Business-model expansion declaration

本阶段在任何业务 SQL 草案或执行前按 `docs/workflows/write-rpc-flow.md` 完成声明：

| 类别 | 精确对象/变更 | 当前任务批准依据 |
|---|---|---|
| 新业务表 | `none` | 不适用 |
| 新业务列 | `none` | 不适用 |
| 新 enum/status value | `none`；沿用页面既有且业务负责人本任务明确确认的 `carry_final_balance`、`clear_balance`、`manual_adjustment` | 本任务 II、VI |
| 新日期/月/归属/identity/source/snapshot/version/writable fact | `none` | 不适用 |
| 既有字段业务语义 | `school_student_settlement_adjustment_drafts.adjustment_source/adjustment_amount_cny`、`school_student_settlement_adjustments.adjustment_source/adjustment_amount_cny`、`school_student_monthly_settlements.system_difference_cny/adjustment_amount_cny/carryover_amount_cny`按本任务公式改为 DB 唯一权威 | 本任务 II、IV、VI |
| mutability/locking | carry/clear 禁止客户端金额；posted adjustment 永久只读；preview/save/lock/relock 复用 P0-A `student_tuition_operation_v1` 锁 | 本任务 IV、VII |
| writer/reader precedence | DB resolver、preview、draft writer、lock/relock 与表级 trigger 为唯一决定者；页面不得重算 | 本任务 II、IV、VIII |
| fallback/dual-write/history reinterpretation | `none` | 不适用 |

结论：既有四表和既有 mode 值足以表达获批合同；新增对象仅为约束、索引、trigger/function/RPC 与测试/验收资产，不新增业务事实。Schema And Business Model Expansion Gate 通过。

## 2. 最终权威合同

| mode | 客户端金额 | DB adjustment | DB carryover |
|---|---:|---:|---:|
| `carry_final_balance` | 必须 `NULL` | `0.00` | `round(system_difference, 2)` |
| `clear_balance` | 必须 `NULL` | `-round(system_difference, 2)` | `0.00` |
| `manual_adjustment` | 必须为用户显式输入 | `round(explicit_user_amount, 2)` | `round(system_difference + adjustment, 2)` |

- 非法 mode、carry/clear 非 NULL 金额、manual NULL/非有限金额全部 fail-closed。
- preview 每次在 P0-A 共享 operation lock 下读取当前 summary 并重新解析 active draft；没有 draft 时只返回隐式 carry 预览，不落库。
- lock/relock 在同一事务、同一 operation lock 下重新读取课时/收入/overage 权威事实，刷新 active draft 的 DB-resolved amount，冻结 settlement，写唯一 posted audit，再消费 draft。
- `school_tuition_p0b2_settlement_resolution` 为 deferred constraint trigger；lock/relock 写入前显式切回 deferred，审计行完成后切到 immediate 做原子一致性检查。
- draft/posted 两表有三值 CHECK；posted settlement 有唯一索引；active/consumed draft、posted audit、locked settlement 均有表级防绕过验证。
- 旧 `school_apply_student_monthly_settlement_adjustment` 保持 fail-closed，且 anon/authenticated/service_role 的 EXECUTE 已撤销。

## 3. RPC-only 与前端收口

- 四张 settlement 表继续 RLS enabled，anon/authenticated/service_role 均为 SELECT-only，INSERT/UPDATE/DELETE 均为 false。
- 正式 preview/draft/lock/relock 为 `SECURITY DEFINER + search_path=pg_catalog,public`，P0-B2 resolver/guard 仅 postgres 可执行。
- 页面模块没有 `.rpc()` 或表写；`js/api/settlement-api.js` 是唯一 RPC wrapper。
- API 不再暴露旧 apply wrapper，不再把 `manual` 作为默认值；只允许三种精确 mode。
- 页面仅在 manual 模式提交用户显式输入；carry/clear 一律传 `NULL`。
- 删除页面对 `system_difference + adjustment` 的结转计算与 CNY `Math.round`；未保存模式统一显示“保存后由数据库计算”。
- 页面版本为 `v10.4.3`，缓存链升级为 `v10.4.3-p0b2-adjustment-authority-2`。

## 4. SQL 部署与精确回滚

主要文件：

- `sql/current/school_tuition_p0b2_adjustment_mode_authority_20260803.sql`
- `sql/current/school_tuition_p0b2_adjustment_mode_authority_rollback_20260803.sql`
- `sql/current/school_tuition_p0b2_adjustment_mode_rollback_tests_20260803.sql`
- `sql/current/school_tuition_p0b2_inventory_readonly_20260803.sql`
- `sql/current/school_tuition_p0b2_acl_runtime_tests_20260803.sql`
- `sql/current/school_tuition_p0b2_whitelist_commit_test_20260803.sql`
- `sql/current/school_tuition_p0b2_concurrency_session_{a,b}_20260803.sql`
- `sql/current/school_tuition_p0b2_fixture_lifecycle_20260803.sql`
- `sql/current/school_tuition_p0b2_postdeploy_20260803.sql`
- `sql/current/cash_tuition_p0b2_readonly_postdeploy_20260803.sql`

执行事实：

1. 初次 rehearsal 因 preview 基线 MD5 写错在任何 DDL 前 fail-closed；DB 写入 0。
2. 修正后 migration `commit=0` 完整编译并 ROLLBACK；10 张业务表事务内 count/hash 零漂移。
3. migration 正式 COMMIT。
4. rollback 先完成强制 ROLLBACK 演练，再正式 COMMIT；随后同一 migration 正式重部署。
5. rollback test 暴露 constraint mode 被上游事务切成 immediate 时的时序问题；失败事务整体回滚。修复 lock/relock 显式 deferred 后再次正式 rollback/redeploy。
6. 最终 migration/rollback 均有固定函数指纹与对象/ACL断言；最终生产只保留 P0-B2 状态。

最终函数 MD5：

| function | MD5 |
|---|---|
| preview | `646e278c3144cab782141d3d01f69db5` |
| draft writer | `9b68480b55736c0602b28f637dcdc7a1` |
| lock | `19033b559cacb99677fc1d3583f78ad3` |
| relock | `6357848be1eb6c1cf11016d01cad14cb` |
| resolver | `9e056a42b0de50476233ed78de58b528` |
| draft/posted/settlement guards | `6249f945e0d359a8f5aa7820bd21f5da` / `aef4c30b2c3953b975b72d4e27feafc1` / `c67bc3735b253eb2bb57c843fafdfa4a` |

## 5. 测试证据

### 5.1 rollback matrix

通过项目包括：

- carry/clear/manual 的正、负、零差额组合；
- PostgreSQL CNY 舍入（如 `12.345 -> 12.35`）；
- 三类非法参数组合与第四 mode 拒绝；
- 正式 draft RPC、preview、lock 的权威结果；
- `lock -> unlock -> clear draft -> relock` 成功路径及 relock 固化结果；
- save clear 后用正式 Lesson RPC 修改来源事实，再 preview/lock，最终 `3200 / -3200 / 0`；
- posted audit、settlement snapshot 防篡改；
- Atomic Generate 消费 previous settlement 后 draft 写入拒绝；
- 旧 apply 入口 fail-closed。

### 5.2 角色与直写

- anon clear、authenticated manual `1.235 -> 1.24`、service_role carry 均通过正式 draft RPC 并 ROLLBACK。
- 三类角色直接 INSERT/UPDATE/DELETE draft 全部 permission denied。
- 三类角色不能执行 resolver 或旧 apply。

### 5.3 白名单 commit 与 fixture

- 复用已审查的固定 School-only fixture：entity/subject/teacher/student/lessons/previous settlement 均为 `b1b10000-*`，marker 为 `codex-test tuition-p0b1-lesson-authority-20260803`。
- committed draft：`40761f46-f285-4d12-a3f4-673b741f1ef7`，student `b1b10000-0000-4000-8000-00000000a100`，mode clear，amount `-3000.00`，carry `0.00`。
- commit test draft 随后按 fixed student + exact marker + exact row identity 清理；fixture 全部精确清理，最终 residue 0。
- fixture source change 仅修改 lesson `b1b10000-0000-4000-8000-000000001101`，通过正式 guarded Lesson RPC 提交并通过同一 RPC 恢复后再清理。

### 5.4 八组双会话并发

`draft_edit`、`draft_actual`、`draft_lock`、`lock_generate`、`draft_pair`、`unlock_draft`、`preview_edit`、`source_change_lock` 全部通过。B 会话实际阻塞约 4.1–4.7 秒后完成，无 partial write；最后一组在 A 提交白名单 Lesson 来源变更后，B 读取 `3200 / -3200 / 0` 并完成锁定事务的回滚验证。

### 5.5 浏览器

本地真实页面加载 v10.4.3 和生产只读数据。三种 option 精确；carry/clear amount 为空且 readOnly，manual 为空且可输入。输入 `12.345` 后 adjustment/carry 仍显示“保存后由数据库计算”。未点击保存，浏览器业务写入 0。

## 6. 最终零漂移与写入账

School postdeploy 10 张表与初始全行 MD5 完全一致：settlement 17、draft 6、adjustment 5、carryover 8、lesson 729、bill 17、identity 15、bill_lesson 256、income 50、School cash linkage 40。Cash request/CNY/JPY 为 39/68/31，MD5 分别为 `303e10bc1a28a0abd8b27afd3929cfd8`、`cba640a696f4c7da59d8df2be7fe79e5`、`95ab7cf8a8d167e9b052d3fc6b64614b`。

- 生产持久化：P0-B2 DDL、constraint、index、function/RPC、trigger、ACL/comment。
- 真实业务行写入：0。
- 白名单测试业务写入：仅上述 fixed fixture、一个 active draft、一次 fixture Lesson source change/restore；均已清理，residue 0。
- Cash DB DDL/DML/RPC：0；仅执行只读 postdeploy。
- 既有张倬闻异常、历史 settlement/draft/adjustment/carryover、bill/income/Cash 事实均未修改。

## 7. Gate 与下一步

最终 Gate 为 `enabled / blocked / blocked`。P0-B2 只完成 Settlement Adjustment Mode 的数据库权威与 RPC-only 收口；不得自动恢复真实 settlement lock/unlock/relock、差额调整运营、tuition generate、Atomic Void/Reissue、Cash submit 或真实数据修复。后续阶段须使用新的明确任务授权，并重新通过 Schema And Business Model Expansion Gate。
