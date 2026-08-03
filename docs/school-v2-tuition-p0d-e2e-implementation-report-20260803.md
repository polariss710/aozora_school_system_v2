# School V2 学费财务 P0-D 最终闭环实施报告

日期：2026-08-03。最终结论：**P0-D 已真正关闭**。固定 whitelist fixture 已通过正式本机管理工具、正式 Edge/service-role、School RPC 与 Cash 只读 preflight 的 committed Void/Reissue 全链验收；Rule A / Rule B、回滚、并发、fail-closed、幂等、validator、cleanup 与双库 postdeploy 均通过。三名真实学生仅执行只读 preflight，真实写入均为 0；他们仍不得据此自动执行真实操作。

## Business-model expansion declaration

- New business tables/columns/status/date/month/identity/source/snapshot/version/writable facts：none。
- Changed amount formula、historical interpretation、dual authority、fallback、destructive schema：none。
- Changed writer/reader authority：none；继续使用 P0-C 已批准的 generation identity/revision、专用 Void/Reissue 与 DB snapshot authority。
- Changed locking semantics：`public.school_assert_active_tuition_previous_period_claim(uuid,uuid,text)` 及四表 trigger 将 active revision 已冻结的上一期 settlement scope（包括 `previous_settlement_id IS NULL + previous_carryover_cny = 0`）视为 active claim；专用 Void 后仅在 settlement 从未被任意 historical revision 消费时释放。批准来源：本次指令第五节 Rule A。
- Historical consumed authority：不变；`public.school_tuition_p0a_consumed_bill_id(uuid)` 跨 active/voided revision 解析历史消费，Rule B 始终优先。批准来源：既有 P0-A 合同及本次指令第五节 Rule B。
- Permission boundary：Edge 未给 `anon`、`authenticated`、`service_role` 增加业务表写权限；本机 owner 请求先以 service-role-only 表 SELECT 权限做 DB 权威探针，再调用既有 service-role-only wrapper。批准来源：本次指令第三、四节。

## 凭证与 Edge 收口

本机没有仓库内 secret。通过官方 Supabase CLI 交互登录后，只在受控进程内读取 project API key；key 未打印、未落盘、未进入 shell history、文档或 Git。Edge 原有自定义 `SCHOOL_SERVICE_ROLE_KEY` 与当前 project key 不一致，首次正式请求因此 401 且零写入。修复后的 `void-atomic-tuition-generation` 同时识别 canonical project service-role，并以 `school_student_tuition_generation_revisions` 的 service-role-only SELECT 权限作为权威探针；普通登录用户仍走原 auth 分支。Edge 已部署，静态检查 13/13。

## 正式 synthetic execute

固定对象：

- entity `d0d00000-0000-4000-8000-00000000e001`
- subject `d0d00000-0000-4000-8000-00000000d001`
- teacher `d0d00000-0000-4000-8000-000000007001`
- student `d0d00000-0000-4000-8000-00000000a001`
- settlement `d0d00000-0000-4000-8000-00000000b001`
- lessons `d0d00000-0000-4000-8000-000000001101`、`d0d00000-0000-4000-8000-000000001102`
- generation `d0d00000-0000-4000-8000-000000003001`
- revision 1 `d0d00000-0000-4000-8000-000000004001`
- bill `d0d00000-0000-4000-8000-000000006001`
- income `d0d00000-0000-4000-8000-000000007101`

管理工具 `status`、`void-preflight`、Void dry-run、缺 expected facts 拒绝、错误确认文本拒绝均通过。正式 `void --execute` 经 Edge 完成 committed write：void event `56b7af3d-8aa1-4103-98cd-19abe7f3a8b9` 恰好一条；revision 1 保留并变为 `voided`；bill/income 保留并变为 `cancelled`；历史 relation/snapshot/manifest 未删除；未被其他历史账单占用的 lesson claim 释放；operator authority 为 `local_trusted_business_owner_v1`。Cash preflight 全程只读且三类事实均为 0。

`history`、`reissue-preview`、Reissue dry-run 通过。DB authoritative preview 在 rate `0.043` 下返回 JPY `650000`、carry `0`、CNY `27950.00`。正式 `reissue --execute` 创建：

- revision 2 `e5298347-46d1-4964-9176-d6c16359fbaf`，active，previous revision 正确指向 revision 1；
- bill `da86c987-17bf-42ee-b9c4-1ab71060be10`；
- income `f209a466-c437-42f7-8886-e8e8ea18154b`；
- generation manifest `7728e114…188b8`，candidate manifest `f9982e…818fa`（完整值由工具/DB exact expected facts 传递，文档不作为可执行输入）。

identity、bill-income、bill-lessons、generation-revision 四个 validator 全部通过；重复 Reissue 返回 idempotent；不同 manifest 被 `TUITION_REISSUE_EXPECTED_FACT_MISMATCH` fail-closed。最终 fixture cleanup 按固定 student/generation 范围精确清理 revision 2 的随机 UUID 链，School residue 0、Cash residue 0。

## Rule A 与 Rule B

Rule A 已部署：

- 权威函数：`school_assert_active_tuition_previous_period_claim(uuid,uuid,text)`；
- settlement scope：create/save/lock/unlock/relock 全部受保护；
- child scope：adjustment draft、posted adjustment、carryover insert/update 受保护；
- 稳定错误码：`TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE`；
- active bill 即使明确冻结 carry `0` 且 `previous_settlement_id IS NULL`，上一期仍冻结；
- Void 后 active claim 释放，但只允许从未被历史 revision 消费的 settlement 继续结算。

Rule B 保持永久优先：

- 权威 resolver：`school_tuition_p0a_consumed_bill_id(uuid)`；
- guard：`school_assert_tuition_settlement_mutable(uuid)`；
- 稳定错误码：`TUITION_CONSUMED_SETTLEMENT_IMMUTABLE`；
- revision 后来 Void 不改变“曾消费”事实，settlement 仍不能 unlock/relock/覆盖/重算。

最终回滚矩阵 8/8 覆盖 zero-carry active claim、create/save/lock/child mutation 拒绝、Void 释放、正式 relock、下一期 Reissue 精确消费 locked carry、Rule B 永久冻结。`generate/reissue vs settlement` 与 `void vs settlement mutation` 双会话均实际等待后拒绝，无 deadlock、timeout、半写入或重复 active revision。

## 前后指纹、residue 与 Gate

| 范围 | before | after | 结论 |
|---|---:|---:|---|
| School lesson | `730 / 034d3ee24d639e587447a9458244797c` | 同左 | 不变 |
| Cash request | `39 / 303e10bc1a28a0abd8b27afd3929cfd8` | 同左 | 不变 |
| Cash CNY transaction | `71 / d7e72182970de4ea8849c994b67e8dcc` | 同左 | 不变 |
| Cash JPY transaction | `31 / 95ab7cf8a8d167e9b052d3fc6b64614b` | 同左 | 不变 |
| School P0-D fixture | committed lifecycle | residue `0` | 已清场 |
| Cash P0-D fixture | `0` | `0` | 从未写入 |

生产 generation identity/revision/active 恢复 `15/15/15`，正式 fixture 清理后 void event residue 0。Rule A postdeploy 当前只读识别 14 条 active zero-carry previous-period claims。Gate 终态严格保持：

- `student_tuition_preview = enabled`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

## 实际执行清单

正式执行或复核过的 SQL 文件：

- `sql/current/school_tuition_p0d_fixture_lifecycle_20260803.sql`：`preflight / insert / cleanup / residue`；
- `sql/current/school_tuition_p0d_final_closure_20260803.sql`：Rule A 与 cleanup guard 主 migration，含 exact rollback 后 redeploy；
- `sql/current/school_tuition_p0d_final_closure_cleanup_guard_correction_20260803.sql`：多表 OLD row JSON 安全取值修正；
- `sql/current/school_tuition_p0d_final_closure_rollback_20260803.sql`：exact rollback rehearsal；
- `sql/current/school_tuition_p0d_final_closure_rollback_tests_20260803.sql`：最终 8/8、整体 ROLLBACK；
- `sql/current/school_tuition_p0d_final_closure_concurrency_session_a_20260803.sql`；
- `sql/current/school_tuition_p0d_final_closure_concurrency_session_b_20260803.sql`；
- `sql/current/school_tuition_p0d_final_closure_postdeploy_20260803.sql`；
- `sql/current/school_tuition_p0d_postdeploy_20260803.sql`；
- `sql/current/cash_tuition_p0d_readonly_postdeploy_20260803.sql`。

实际调用的 Edge/RPC：

- Edge `void-atomic-tuition-generation`：三名真实学生仅 `preflight_only`；synthetic 执行 preflight 与 committed Void；
- `school_get_atomic_tuition_void_preflight`；
- `school_void_atomic_student_tuition_generation_local`（synthetic，Edge 内）；
- `school_reissue_atomic_student_tuition_generation_local`（synthetic）；
- `school_get_student_tuition_validation_preview_details`、`school_get_student_monthly_settlement_preview`（只读）；
- `school_relock_student_monthly_settlement`（仅 rollback synthetic）；
- 四个 tuition validators；
- Rule A / Rule B resolver 与 guard。

未调用任何真实学生 write RPC、lesson writer、settlement writer、Cash writer 或 Gate writer。三名真实学生、真实 bill/income/lesson/settlement/carryover/adjustment/Cash 写入全部为 0。

## 测试中的受控失败

首次 Edge 请求因旧自定义 secret 不匹配返回 401；修复并部署后通过。一个 postdeploy 仅因函数文本空格匹配过严产生 false negative，修正断言后通过。双会话最初分开调度导致计时 false negative，改为同 shell 并行后实际等待验证通过。首次 cleanup 因通用 trigger 直接读取不存在的 `OLD.planned_lesson_id` 失败且事务完整回滚；JSON OLD row 修正部署后 cleanup/residue 通过。增强回滚矩阵前两次分别发现测试遗留 writer-context 与测试 bill 未模拟 cancelled 状态；均在事务回滚中暴露并修正，最终 8/8。以上失败均未触及真实学生，未产生 Cash 写入或残留。

## 运营边界

P0-D 的技术闭环完成不等于三名学生获得运营授权。彭宇晗、李天伦仍缺业务负责人给出的精确 lesson UUID 与目标字段；张倬闻因历史 settlement 状态与 forward adjustment 缺口必须先完成独立 P0-E。详见三人只读操作计划。不得自动开始任何真实 Void、lesson edit、settlement、Reissue 或 Cash 操作。
