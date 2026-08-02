# School V2 学费财务 P0-A 实施与验证报告

日期：2026-08-03

审计基线：`87ce609ce717426db4c6e5e7a969435b1a640838`

基线 parent：`b6076ab08e0f52e513d6b6aaf48767da790b9fff`

## 结论

P0-A 已完成生产部署和验收：被 active canonical tuition bill 消费的 settlement 及其 draft、posted adjustment、carryover 现在由数据库永久拒绝修改；Atomic Generate 和相关 settlement writer 使用同一 operation-lock namespace 与固定表锁顺序；四张目标表已收口为 RPC-only 写入。真实财务业务行变更为 0，固定 synthetic fixture 已精确清理且 residue 为 0，Cash 数据库写入为 0。

生产 Gate 终态为：

- `student_tuition_preview = enabled`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

本阶段没有修复张倬闻的既存异常，没有实施 P0-B、P0-C、Void/Reissue、forward adjustment、settlement revision、`lesson_fee` 或 Cash 写入。

## Business-model expansion declaration

- 新表、业务列、状态、日期/月、identity、source、snapshot、writable fact：`none`。
- 变更的既有语义：`school_student_monthly_settlements`、`school_student_settlement_adjustment_drafts`、`school_student_settlement_adjustments`、`school_student_settlement_carryovers` 在 settlement 被 active canonical tuition bill 消费后永久不可变；四表 writer authority 改为 RPC/owner-only；Atomic Generate 与 settlement mutation 使用统一共享锁协议。
- 唯一权威：active `school_student_tuition_billing_identities.canonical_bill_id` → active canonical bill → `previous_settlement_id`。没有 fallback、`COALESCE` 权威切换、历史重解释或双写。
- 审批依据：本任务 prompt 第 I、IV、V、VI、VII 节逐项批准上述对象、不可变语义、唯一权威、锁与权限合同。Schema And Business Model Expansion Gate 已匹配并通过。

## 已消费 settlement 精确定义

`school_tuition_p0a_consumed_bill_id(settlement_id)` 只在以下全部条件成立时返回 consuming bill：

1. `school_student_tuition_billing_identities` 当前 immutable identity 的 `canonical_bill_id` 指向该 bill；
2. bill 为 canonical charge，`billing_role = canonical_charge`；
3. bill active 状态为 `draft` 或 `income_created`；
4. bill source 为现行合法 canonical source：`atomic_charge` 或 `historical_backfill`；
5. bill 的 student/month 与 identity 一致；
6. bill 的 `previous_settlement_id` 精确等于目标 settlement。

命中后，`school_assert_tuition_settlement_mutable(...)` 和 month guard 使用 SQLSTATE `P0001` 及稳定标识 `TUITION_CONSUMED_SETTLEMENT_IMMUTABLE` 拒绝操作；消息明确说明该 settlement 已被 active bill 消费、历史 settlement 不得重开、后续纠错应走 forward adjustment，且本阶段不提供对应 UI。

## 修改的数据库对象

新增 owner-only helper/guard：

- `school_tuition_p0a_consumed_bill_id(uuid)`
- `school_assert_tuition_settlement_mutable(uuid)`
- `school_assert_tuition_settlement_month_mutable(uuid,text)`
- `school_tuition_p0a_lock_generate_scope(uuid,uuid,text[])`
- `school_tuition_p0a_lock_settlement_mutation_scope(uuid,uuid,text)`
- `school_guard_tuition_consumed_settlement_row()`
- `school_guard_tuition_consumed_settlement_child()`

修改既有 writer：

- `school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)`
- `school_lock_student_monthly_settlement(uuid,text,text)`
- `school_unlock_student_monthly_settlement(uuid,text)`
- `school_relock_student_monthly_settlement(uuid,text)`
- `school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)`

`school_apply_student_monthly_settlement_adjustment(...)` 原本已永久 fail-closed，本轮只收紧 execute grant，没有重新开放 posted-adjustment writer。生产 catalog 未发现其他正式 carryover mutation RPC；owner 直接路径仍受触发器保护。

新增四个 `BEFORE` trigger：

- `school_tuition_consumed_settlement_immutable`
- `school_tuition_consumed_draft_immutable`
- `school_tuition_consumed_adjustment_immutable`
- `school_tuition_consumed_carryover_immutable`

四个 trigger 覆盖 consumed settlement 的 row UPDATE/DELETE，以及关联 child 的 INSERT/UPDATE/DELETE；不信任浏览器状态、metadata 或布尔声明。

## 共享锁协议

所有目标 writer 先使用同一 advisory namespace：

`student_tuition_operation_v1 | student_id | business_entity_id | YYYY-MM`

月份按字典序去重后取 advisory transaction lock，再固定按以下顺序取表锁：

1. `school_lesson_records`
2. `school_student_monthly_settlements`
3. `school_student_settlement_carryovers`
4. `school_student_settlement_adjustment_drafts`
5. `school_student_settlement_adjustments`

Generate 对五表使用 `SHARE`；settlement mutation 对 lesson 使用 `SHARE`，对其余四张财务表使用 `SHARE ROW EXCLUSIVE`。锁在同一事务内持有，writer 在持锁后重新读取并执行 consumed guard。8 秒 lock timeout fail-closed 为 `TUITION_P0A_SOURCE_BUSY`，没有应用层“先查后写”作为最终判断。

## Grants、RLS 与 execute 收口

部署前：四张表对 `anon`、`authenticated`、`service_role` 均有直接表 DML；settlement/carryover 有宽泛 true DML policy，draft/adjustment 未启用 RLS；目标 write RPC 还存在非预期 `PUBLIC EXECUTE`。

部署后：

- 四张表全部启用 RLS；只保留 SELECT policy。
- `anon`、`authenticated`、`service_role` 只保留 SELECT，INSERT/UPDATE/DELETE/TRUNCATE 均无权限。
- 表 owner `postgres` 保持维护权限，但任何遗漏/privileged writer 仍受 consumed trigger guard。
- 五个正式 write RPC 均为 `SECURITY DEFINER`、`search_path = pg_catalog,public`，撤销 PUBLIC execute，只授予 `anon`、`authenticated`、`service_role` execute。
- 七个 helper/trigger function 只允许 owner execute。
- 页面模块不直接 `.rpc()`；现有 API wrapper 原样抛出 RPC error，settlement 列表和详情现有错误区域原样显示 `error.message`，因此不需要修改 UI/API。

最终仓库回归发现两个审计基线即已 stale 的静态断言：旧 Cash 整改硬编码文案和预览列表已不展示的空调费率字段。两处只删除过期 source-match 断言；现有 Gate 状态消费、提交按钮默认禁用、DB 权威空调费/课程总价展示及 API 边界断言继续保留，业务 JS/HTML 未修改。

## 执行的 SQL 与结果

School DB 使用 `SCHOOL_SUPABASE_DB_URL`；Cash DB 使用 `CASH_SUPABASE_DB_URL`，均未输出或保存连接信息。

1. `school_tuition_p0a_gate_block_20260803.sql`
   - `p0a_gate_commit=0`：两条 Gate UPDATE 后 ROLLBACK，通过。
   - `p0a_gate_commit=1`：两条 Gate UPDATE 后 COMMIT，通过。
2. `school_tuition_p0a_consumed_settlement_rpc_only_20260803.sql`
   - `p0a_migration_commit=0`：完整 DDL rehearsal 后 ROLLBACK，通过。
   - `p0a_migration_commit=1`：正式部署 COMMIT，通过；目标业务表行数/hash 零漂移。
3. `school_tuition_p0a_consumed_settlement_rpc_only_rollback_20260803.sql`
   - `p0a_rollback_commit=0`：在事务内精确恢复旧函数、trigger、policy 与 grant，校验旧 MD5 和业务 hash 后 ROLLBACK，通过；正式 P0-A 部署保持生效。
4. `school_tuition_p0a_rollback_tests_20260803.sql`
   - 11/11 PASS，整组 ROLLBACK，residue 0。首次运行因测试 bill fixture amount assertion 不匹配而整事务回滚，修正测试值后重跑通过；没有生产残留。
5. `school_tuition_p0a_acl_rls_inventory_20260803.sql`
   - 只读通过：四表 RLS、SELECT-only、无 app-role DML、四个 guard trigger、正式 RPC execute 与 owner-only helper 全部符合合同。
6. `school_tuition_p0a_concurrency_fixture_lifecycle_20260803.sql`
   - `preflight`：所有固定 UUID 不存在。
   - 首次 `insert` 因既有 `R2_E_DIRECT_AUTHORITY_FIELDS_FORBIDDEN` 拒绝并整事务回滚；去除 fixture 对权威费用字段的直接赋值后重新 preflight 为 0。
   - 第二次 `insert`：只提交 6 条固定 synthetic 行，并验证 atomic preview candidate 1、manifest 有效、previous settlement 精确匹配。
   - `cleanup`：先验证 marker/UUID/引用范围，再精确删除 6 条固定行并 COMMIT。
   - `residue`：所有 UUID、marker 和引用为 0。
7. `school_tuition_p0a_concurrency_session_a_20260803.sql` / `school_tuition_p0a_concurrency_session_b_20260803.sql`
   - 六组独立双会话测试全部通过，两个会话均 ROLLBACK。
8. `school_tuition_p0a_postdeploy_20260803.sql`
   - fixture 前后均只读通过；15/15 canonical validators、真实计数/hash、三条重点链、Gate 与 fixture residue 全部通过。
9. `cash_tuition_p0a_readonly_postdeploy_20260803.sql`
   - Cash 只读复审通过；request/CNY/JPY transaction 行数及 hash 固定，marker residue 0，Cash 写入 0。

本阶段调用的业务 RPC 仅发生在 rollback-only 或固定 synthetic fixture 并发事务内：validation preview、Atomic Generate owner core、settlement lock/unlock/relock、draft adjustment writer，以及 owner carryover测试路径。没有对真实学生调用 write RPC。

## 测试矩阵

Rollback-only 11/11 覆盖：consumed resolver、RPC guard、settlement direct UPDATE、draft/adjustment/carryover 三类 INSERT/UPDATE/DELETE 拒绝、unconsumed draft+lock、unlock+relock、owner carryover create/read、catalog permission、anon runtime SELECT 与 DML insufficient privilege。

多会话结果如下；A 先取得 operation/table locks 并保持约 5 秒，B 随后启动并实际阻塞，A ROLLBACK 后 B 完成目标路径再 ROLLBACK：

| 场景 | B 实测阻塞 | 结果 |
| --- | ---: | --- |
| Generate / unlock | 4.762 s | 串行完成，双方回滚 |
| Generate / relock | 4.733 s | 串行后按原状态 guard 拒绝 relock，双方回滚 |
| Generate / draft adjustment | 4.793 s | 串行完成，双方回滚 |
| Generate / carryover | 4.758 s | 串行完成，双方回滚 |
| 两个 settlement mutation | 4.746 s | 串行完成，双方回滚 |
| 重复 Generate | 4.747 s | 串行完成，双方回滚 |

六组均无 deadlock、timeout、partial write、重复 active bill、重复 income 或持久化随机 UUID。与 consumed 11/11 guard 组合证明：同一依赖不会并发成功；若 Generate 已经提交消费，后续 mutation 会由稳定 consumed guard 拒绝。

## Fixed synthetic fixture

Marker：`codex-test tuition-p0a-concurrency-20260803`

- business entity：`a0a00000-0000-4000-8000-00000000e100`
- subject：`a0a00000-0000-4000-8000-00000000e101`
- teacher：`a0a00000-0000-4000-8000-00000000e102`
- student：`a0a00000-0000-4000-8000-00000000a100`
- planned lesson：`a0a00000-0000-4000-8000-00000000a101`
- settlement：`a0a00000-0000-4000-8000-00000000b100`
- transient carryover（只在并发 B 的 rolled-back transaction）：`a0a00000-0000-4000-8000-00000000c100`

Committed INSERT 为上述前 6 行；cleanup 只按同一 6 个固定 UUID 删除。随机 bill/identity/income 只在并发 Generate 的 rollback transaction 内存在，从未提交。最终各固定 UUID、随机业务对象、marker 文本及引用 residue 均为 0。

## 生产复审与真实数据保护

School 真实行数/hash 保持：

- settlement `17 / 85c829ebc3bb0a4100393d9c8d6421d7`
- draft `6 / 059c5187ad6513f9501076193aa55696`
- adjustment `5 / 4bce2b158d4de769d592a2d367881868`
- carryover `8 / 54133d433579c772ba76017b757c49fd`
- bill `17 / b18f15673637280bf1455667ccd3cc00`
- identity `15 / d8d72d5f886e363b80bca4aecfe22522`
- bill lesson `256 / dfa2bdb71f812f4b2aa0a23613edf289`
- income `50 / dccaf8446c3907b48cec9bf028b4373c`
- School Cash linkage `40 / 8e467489878b5bbe15f9eadbcbaabb10`

15/15 canonical identity/bill-income/bill-lessons validators 全部通过。张倬闻 consuming bill `553a24ba-81cf-4af0-b723-169a09914c79` 仍精确解析到 unlocked settlement `b699209d-2f61-4cfa-959b-45686e2fe19b`；income 仍为 pending、无 Cash linkage，数据没有被修复或改写，但新 guard 已拒绝继续 mutation。彭宇晗、李天伦 2026-08 canonical pending 链保持原状。

Cash 只读基线保持：request `39 / 303e10bc1a28a0abd8b27afd3929cfd8`，CNY transaction `68 / cba640a696f4c7da59d8df2be7fe79e5`，JPY transaction `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`。

正式数据库变更只有：两个 Gate 状态、函数/trigger/RLS/policy/grant/comment 等 P0-A 元数据。真实财务业务行变更数量为 0；synthetic committed 行净变化为 0；Cash 写入为 0。

## Rollback 与后续边界

精确 rollback 文件可以恢复本阶段修改的函数、trigger、policy 与 grant，不含 CASCADE，不触碰业务行；本轮只做 `commit=0` rehearsal，没有执行正式 rollback。

P0-A 完成不等于恢复学费运营。Generate 和 Cash Submit 继续 blocked；settlement 实际运营也继续冻结，等待 P0-B（DB-authoritative `lesson_fee`/adjustment mode）、P0-C 与全量 E2E 复审。不得自动开始 Void/Reissue、forward adjustment 或张倬闻修复。
