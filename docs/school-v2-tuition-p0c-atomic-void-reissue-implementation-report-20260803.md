# School V2 学费财务 P0-C Atomic Tuition Void/Reissue 实施报告

日期：2026-08-03
基线提交：`fe095c3991a7dfaf09095d8bdacdd5fef0f61739`

## 结论

P0-C 已完成生产数据库部署、固定15链 metadata registration、active authority cutover、专用 owner-only Void、revision 2 Reissue、共享锁/Cash reservation 收口、Edge Function 部署、回滚矩阵、10组双会话并发、School/Cash postdeploy、fixture 精确清理和前端/API 收口。没有对任何真实账单执行 Void/Reissue，没有提交真实 Cash request/transaction，没有修改 Cash DB。

生产 Gate 最终保持：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=blocked`。本阶段完成不等于恢复真实学费写运营。

## Business-model expansion declaration

本任务依据业务负责人在 P0-C 指令中的逐项明确批准实施：

- 新表：`school_student_tuition_generation_identities`、`school_student_tuition_generation_revisions`、`school_student_tuition_generation_void_events`。
- 新 authority：generation identity 是学生/业务归属/账单月的永久身份；revision 是 active/voided 历史权威；void event 是 append-only 审计事实。
- 固定15链 registration：只使用生产既有15条 canonical identity，不推断或扩展名单。
- manifest 映射：批准名称 `atomic_generation_manifest_v1` / `historical_registration_manifest_v1` 在 DB CHECK 中固定存为 `atomic_generation_v1` / `historical_registration_v1`；前者8条、后者7条。
- active lesson/carryover claim、P0-A consumed settlement 永久冻结、共享 `student_tuition_operation_v1` 锁、School reservation 先提交再允许 Edge 访问 Cash，均按本任务获批合同实现。
- 无新增金额、汇率、工资、课时费、carryover 或舍入算法；所有持久化业务金额继续由 DB 权威结果决定。

## 三张新表与权限

三表全部启用 RLS；`public`、`anon`、`authenticated`、`service_role` 的表级 ALL 被撤销，仅 `service_role` 保留 SELECT。应用角色不能直接 INSERT/UPDATE/DELETE/TRUNCATE；正式写入只允许 owner-only core 在 writer context 和表级 trigger 合同内完成。

- `school_student_tuition_generation_identities`：永久 generation scope，唯一 student/entity/billing month；保留 legacy identity 关联。
- `school_student_tuition_generation_revisions`：revision number、previous revision、bill、manifest、active/voided lifecycle；同一 generation 最多一个 active。
- `school_student_tuition_generation_void_events`：一 revision 一条 append-only Void 事件，记录理由、结果和审计时间。

DELETE 的 row-level 与 statement-level guard、UPDATE/DELETE/TRUNCATE guard、revision active claim trigger 均已验证；空表 DELETE 也会拒绝。

## 固定15链 registration 与 authority cutover

同一个受控 migration 事务写入15条 generation identity 与15条 revision 1：

- `atomic_generation_v1`：8，总计 active 8。
- `historical_registration_v1`：7，总计 active 7。
- generation identity：15；revision：15；active：15；manifest NULL：0；void event：0。
- 三个既有 validator 以及新增 generation revision validator 对15个 bill 全部通过。
- migration 同事务对11张既有业务表做全行 count/hash 前后对比，零漂移。

active revision 现为 candidate/duplicate preview、validation preview、Atomic Generate/Reissue、identity/bill-income/bill-lessons/revision validators、P0-A consumed bill resolver、generic tuition cancel guard、Cash preflight 与 Cash reservation 的唯一生产权威。没有 NULL fallback、双读 authority 或 legacy reader precedence。

旧 relation 永久保留。旧的“planned lesson 永久唯一”约束被精确替换为“只有 active revision 可持有 lesson claim”；voided revision 保留 relation 但释放 active claim。carryover claim 同样只由 active revision 占有。advisory lock 与触发器保证 active lesson/carryover claim 唯一，rollback SQL 可精确恢复旧 index/constraint。

P0-A consumed-settlement resolver 已升级为读取所有 revision 历史：即使 revision 已 voided，其旧 bill 对 previous settlement 的消费仍永久成立，`TUITION_CONSUMED_SETTLEMENT_IMMUTABLE` 保持稳定。

## 专用 Void 合同

只允许 active `atomic_generation_v1`、完整 validator/manifest、bill `income_created`、income `pending`、School account transaction=0、School Cash linkage/reservation=0、Cash 两库 request/transaction=0、actual/wage/locked settlement downstream=0、明确非空理由且 expected revision/bill/income/manifest 与持锁后事实一致。

稳定 blocker：

- `TUITION_VOID_NOT_ATOMIC`
- `TUITION_VOID_NOT_ACTIVE_REVISION`
- `TUITION_VOID_INCOME_NOT_PENDING`
- `TUITION_VOID_CASH_FACT_EXISTS`
- `TUITION_VOID_DOWNSTREAM_FACT_EXISTS`
- `TUITION_VOID_MANIFEST_MISMATCH`
- `TUITION_VOID_ALREADY_VOIDED`

owner-only core 在一个 School 事务内按固定顺序取得 operation scope、generation、revision、bill、income、relation、Cash linkage 锁；持锁后重验全部前置，revision 置 voided，旧 bill/income 进入既有合法 `cancelled` 终态，插入恰好一条 append-only event，释放 active lesson/carryover claim，保留所有历史 row/snapshot/manifest/relation，不创建新 bill/income，不修改 planned lesson，不自动 Reissue。

generic `school_cancel_pending_income_record` 对 Atomic Tuition 继续返回 `TUITION_ATOMIC_CANCEL_FORBIDDEN`。

## Reissue 结果

固定 synthetic 链在整文件 ROLLBACK 测试中完成：revision 1 Void 后恢复2个 candidate，手动 DB preview 返回下一 revision 提示，transaction-local 开启 Generate Gate 后生成 revision 2；previous revision 正确，只有 revision 2 active，四个 validator 全部通过。相同 manifest 重试严格幂等，不同 manifest 返回既有冲突码。所有成功 Void/Reissue 业务写均在测试事务回滚，生产 void event 最终为0。

页面不计算 revision number，直接显示 DB preview `message` 中的“将生成 revision N”。

## Cash 与并发

School Cash reservation 与 Void/Generate 共用 `student_tuition_operation_v1` scope。School reservation 必须先在 School 提交，Edge 才能读 Cash 并创建 request；Void 在持锁后重验 School linkage=0。`void-atomic-tuition-generation` Edge Function 已部署：校验 School bearer user、精确 UUID/manifest/reason，读取 School preflight，分别只读检查 Cash request、JPY transaction、CNY transaction 均为0，再以 service role 调用 owner-only School Void RPC。无凭证烟测返回 HTTP 401。

10组独立 psql 双会话均通过并全部回滚：

1. Void vs Void
2. Void vs Generate
3. Void vs Cash reservation
4. Void vs lesson edit
5. Reissue vs Cash reservation
6. Reissue vs settlement mutation
7. duplicate Reissue
8. active lesson claim race
9. active carryover claim race
10. historical reader consistency

前9组 session B 等待约2.77–2.86秒后按锁序完成或稳定拒绝，无 deadlock/timeout；historical reader 约0.16秒一致返回。Cash 与 Void 不会同时成功，Cash request 不会在无 School reservation 时创建，voided income 不能进入 Cash preflight。

## 测试与 fixture

固定 marker：`codex-test atomic-void-reissue-p0c-20260803`。

- business entity：`c0c00000-0000-4000-8000-00000000e001`
- subject：`c0c00000-0000-4000-8000-00000000d001`
- teacher：`c0c00000-0000-4000-8000-000000007001`
- student：`c0c00000-0000-4000-8000-00000000a001`
- previous settlement：`c0c00000-0000-4000-8000-00000000b001`
- planned lessons：`c0c00000-0000-4000-8000-000000001101`、`c0c00000-0000-4000-8000-000000001102`
- legacy identity：`c0c00000-0000-4000-8000-000000002001`
- generation identity：`c0c00000-0000-4000-8000-000000003001`
- revision 1：`c0c00000-0000-4000-8000-000000004001`
- relations：`c0c00000-0000-4000-8000-000000005001`、`c0c00000-0000-4000-8000-000000005002`
- bill：`c0c00000-0000-4000-8000-000000006001`
- income：`c0c00000-0000-4000-8000-000000007101`
- reserved cleanup void event：`c0c00000-0000-4000-8000-000000008001`

Blocker rollback matrix 分别验证 received、School linkage pending、awaiting、rejected、synced、School request ID、School transaction ID、locked settlement、manifest mismatch、non-active revision、historical revision 与 incomplete validator chain。actual/wage 的运行时互斥由 active lesson claim race 和 lesson writer 并发矩阵验证，Void preflight/core 对 legacy actual/wage 行仍有明确计数阻断。Cash DB request/transaction blocker 由 Edge 三表只读查询与 Cash postdeploy 零事实验证，未为测试向 Cash 写入假 request/transaction。

fixture 两次按固定 UUID committed INSERT 后均精确 cleanup；最终 residue：student 0、revision 0、linkage 0、Cash fixture request 0、Cash fixture transaction 0。测试写入只涉及该白名单 fixture；没有真实业务测试写入。

## SQL 执行顺序与结果

正式生产顺序：

1. `school_tuition_p0c_atomic_void_reissue_20260803.sql`，`p0c_migration_commit=1`：三表、15链 registration、authority cutover、writers 同事务 COMMIT。
2. `school_tuition_p0c_postdeploy_20260803.sql`：15链、validator、ACL、Gate PASS。
3. `school_tuition_p0c_cash_readonly_postdeploy_20260803.sql`：Cash request/transaction 0。
4. `school_tuition_p0c_append_only_delete_guard_correction_20260803.sql`：补齐 statement-level DELETE guard。
5. `school_tuition_p0c_candidate_snapshot_authority_correction_20260803.sql`：candidate snapshot 读取 active revision authority。
6. `school_tuition_p0c_fixture_cleanup_guard_correction_20260803.sql`：仅允许固定 postgres+GUC+UUID marker 的精确 fixture cleanup。
7. `school_tuition_p0c_settlement_preflight_guard_correction_20260803.sql`：使只读 preflight 与 owner-only core 的 locked-settlement blocker 一致。

纠正内容均已同步到主 migration 分片，fresh deploy 不依赖事后修正文件。

主 migration `p0c_migration_commit=0` 完整 rollback rehearsal 通过，三表/functions/15链均无 residue，11张既有业务表 hash 不变。精确 rollback 文件 `school_tuition_p0c_atomic_void_reissue_rollback_20260803.sql` 已准备并静态审核；未在最终生产状态上执行。五次早期替换/validator 自校验失败和 settlement correction 的三次文本自校验失败均由事务自动回滚，随后修正并通过；没有部分部署或业务数据残留。

## 前端/API 与验收限制

page module 没有直接 `.rpc()` 或 insert/update/delete/upsert；read RPC 位于 API layer，写入只调用已部署 Edge Function。学费记录隐藏 generic cancel，只有 DB preflight `eligible=true` 才显示“作废学费账单”。弹窗展示学生、月份、业务归属、revision、bill/income、JPY/CNY、汇率、课时、carryover、Cash 状态、历史永久保留警告和手动 Reissue 提示。JS 只格式化 DB 结果，不计算任何保存事实或写 RPC 金额参数。

本地内置浏览器与 Chrome 均没有有效 School 登录会话；详情页以 `anon` 调用既有 `school_get_cash_income_submission_preflight` 时按既定 ACL 返回 permission denied。数据库确认该函数和新 Void preflight 对 `authenticated` 有 EXECUTE、对 `anon` 无权限。为避免扩大权限边界，没有给 anon 增权，也没有伪造登录态，因此交互弹窗验收记录为“登录环境受限”；静态 DOM/API 契约、JS syntax、DB/RPC、Edge 401 和后端矩阵均已通过。

## 最终数据与安全状态

- 真实既有业务表行变更：0；migration 前后11表 count/hash 零漂移。
- 新 metadata 写入：30（15 generation identity + 15 revision）；Void event：0。
- School DB：写入三表 metadata、DDL/functions、固定测试 fixture（已清理）。
- Cash DB：写入0；只读 postdeploy。
- 真实 Void/Reissue/Cash：0。
- Gate：`enabled / blocked / blocked`。
- Edge：`void-atomic-tuition-generation` 已部署；无凭证烟测401。
- 精确 rollback：rehearsal PASS；最终部署未回滚。
