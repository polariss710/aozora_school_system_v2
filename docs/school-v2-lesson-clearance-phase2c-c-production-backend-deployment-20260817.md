# School V2 Phase 2C-C：课时差额清偿生产后端部署报告

日期：2026-08-17

生产页面版本：`v10.5.47`（本阶段未修改）

范围：仅部署课时差额清偿后端对象，不挂载页面，不处理真实余额。

## 1. 实时 preflight

- 开始时 HEAD 与 `origin/main` 均为 `f5dc53693b4594242fee329b7637de705637a45e`，ahead/behind 为 `0/0`。
- 生产此前不存在 clearance 表、函数或 guard；相关开放事务为 0。
- P002 package lot 为 `2a000000-0000-4000-8000-202608170002`，来源 `8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9`，总额/已用/可用为 `1200/0/1200` 分钟，行 MD5 为 `21e6453eddc240c626c0ba50eafbe72f`。
- 部署前普通待补为 21 个 source、2400 分钟；可用超额为 4 个 source、135 分钟；active variance claim 为 2 行。
- Phase 2C-B 本地 UI 原型及原 11 份受保护 untracked 文件均未纳入本阶段。

## 2. Business-model expansion declaration

本阶段采用业务负责人在当前任务第 II 至 XII 节及已批准 Phase 2C-A/2I-A 合同中逐项批准的模型：

- 新增 `public.school_lesson_clearances`：append-only 清偿主事实，权威保存业务类型、actor、幂等键、输入 manifest、操作日/月、财务 forward 方向与目标月、reversal 引用和审计证据。
- 新增 `public.school_lesson_clearance_details`：append-only 来源分配事实，权威保存 pending/overage UUID、分配分钟、两端 DB 权威单价/金额及 source manifest。
- 正式类型仅为 `overtime_offset`、`administrative_writeoff`、`legacy_consolidated_fulfillment`、`reversal`；行政处理仅为 `no_refund_no_credit`、`financial_adjustment_required`。
- forward destination 唯一取 DB 验证过的操作月；locked 历史只产生 append-only forward，不回写 settlement、bill、revision、income 或 Cash。
- 既有 planned/actual/package/claim 的业务含义和权威不变；P002 继续只由 Phase 2I-A package lot 表达，不新增第二套 package 表。
- 不存在 legacy fallback、双写、历史迁移、字段重解释或前端金额权威。

## 3. 部署对象

### 表与约束

- `school_lesson_clearances`
- `school_lesson_clearance_details`
- 唯一幂等、单次 reversal、正分钟、类型/方向、来源关系等约束；两表 RLS 开启且应用角色无表级 DML。
- append-only UPDATE/DELETE/TRUNCATE guard；detail 写入校验 trigger；variance claim/clearance 双向互斥 trigger。

### Reader / Preview

- `school_list_lesson_clearance_pending_balances`
- `school_list_lesson_clearance_available_overages`
- `school_suggest_lesson_clearance_targets`
- `school_preview_lesson_clearance`
- `school_list_lesson_clearance_history`
- `school_list_lesson_clearance_forward_manifest`
- `school_list_cross_month_makeup_projection`
- `school_get_lesson_clearance_source_manifest`

既有待补余额、registered variance/net settlement source 通过权威 helper 接入 clearance；普通 makeup actual 仍按原事实消费，不复制到 clearance detail。

### Writer / guard

- `school_create_lesson_clearance` 与 owner-only core
- `school_reverse_lesson_clearance` 与 owner-only core
- `school_guard_variance_claim_clearance_mutex`
- 余额、actor、reader、detail 与 append-only owner-only helpers

共检查 25 个相关函数：owner 均为 `postgres`、`SECURITY DEFINER`、固定 `search_path=pg_catalog, public`。

## 4. 权威余额与金额合同

- pending remaining minutes = DB 权威 planned 待补整数分钟 − active、non-void makeup actual 消费 − active clearance allocation + active reversal restoration；active claim 作为可用性占用；package source 强制排除。
- overage remaining minutes = frozen active overage minutes − active clearance allocation + active reversal restoration；active claim 作为可用性占用；voided actual 排除。
- clearance detail 只保存 clearance 自身分配，不复制 ordinary makeup，避免双扣。
- Preview 和 writer 均由 DB 读取两端 UUID、学生、业务归属、分钟和 JPY 单价；调用方不提交权威余额或金额。
- V2 只允许同价；异价稳定拒绝 `LESSON_CLEARANCE_PRICE_POLICY_REQUIRED`。
- 同价 `overtime_offset` 的运营余额两端都保存 source 证据；财务净额为 0 时仍不丢失 pending 负向和 overage 正向证据。

## 5. FIFO、锁、互斥、并发与幂等

- FIFO 仅是只读建议：按待补形成时间 `coalesce(min(因果 cancelled/completed actual.created_at), planned.updated_at, planned.created_at)` 升序，再按 planned UUID 稳定排序；writer 只接受调用方明确 UUID，不自动 FIFO。
- 数据库锁顺序与推荐顺序分离：先按 settlement month 排序加锁，再按 source UUID 排序加锁。
- 已有 active claim 的 source 拒绝 clearance；已有 active clearance allocation 的 source 拒绝新 claim。默认 reader 只返回实际可用余额，`include_active_claimed=true` 兼容保留。
- 幂等键唯一；相同请求重试返回同一事实或稳定拒绝；同一 clearance 只能有一个 reversal。
- 本地双会话同时竞争同一 pending、同一 overage 时均仅一个成功；不同 source 无死锁、无负余额。

## 6. Locked forward 与 reversal

- unlocked source 按既有 source 财务月参与当前合同。
- 任一 locked 来源均不更新历史事实；forward destination 为 DB 权威操作月，该规则来自 Phase 2C-A 已批准并通过的合同，不由页面选择或推导。
- 多来源证据分别保留在 detail/source manifest，未来 settlement source reader按目标月读取，避免重复 carryover。
- 后续 reversal 是新的 append-only `reversal` 事实；locked/不可变效果只产生方向相反、归属 reversal 操作月的 forward，不修改原 clearance 或历史 settlement。

## 7. 跨月补课投影

`school_list_cross_month_makeup_projection` 在来源月和实际补课月返回同一 actual UUID及同一来源 planned UUID，并返回学生收费月、老师工资月、实际日期、老师、科目和分钟。reader 去重，不复制 lesson，不改变工资/结算归属，clearance 事实不会伪装为 makeup actual。

## 8. 本地隔离测试

在一次性 PostgreSQL 17 隔离实例完成：

- 主合同 30/30、扩展合同 14/14、角色矩阵 7/7、P002 回归 12/12；全部业务测试最终 ROLLBACK。
- 同/异价、部分/多次分配、跨老师/科目、跨学生/归属拒绝、claim 双向互斥、package 排除、locked forward、三种运营类型、reversal、跨月投影、manifest、表 DML 拒绝均通过。
- 双会话 pending/overage 竞争各仅一个提交，未死锁；提交仅发生在一次性本地数据库。
- static test、SQL 对象覆盖、exact rollback 和 `git diff --check` 通过。
- exact rollback 恢复 5 个被接入的既有函数定义 MD5、owner 与 ACL，并移除全部新增对象。

## 9. Production ROLLBACK rehearsal

所有 attempt 均在显式事务内，使用固定 `2cc0...` synthetic fixture，未引用真实学生余额：

1. Attempt 1：合成 planned 误带 partial billing bundle，触发 `R1D_E_C_PARTIAL_PLANNED_ATTRIBUTION_REJECTED`；完整 ROLLBACK，独立连接确认对象、函数 MD5、P002 与全业务指纹均恢复。
2. Attempt 2：FIFO-first synthetic source 错传 deviation reason，触发 `LESSON_CLEARANCE_FIFO_DEVIATION_REASON_FORBIDDEN`；仅修正 fixture，完整 ROLLBACK并独立复核零变化。
3. Attempt 3：完整通过。事务内验证 claim 先占用阻断 clearance、operator unlocked 成功、clearance 先占用阻断 claim、admin locked forward 成功、角色/ACL/RLS/search_path 正确；保存点清除 fixture 后执行 exact rollback，5 个旧函数 MD5恢复、新对象归零，最后显式外层 ROLLBACK。

Attempt 3 后独立连接确认 clearance 表/函数不存在、fixture 0、P002不变、School/Cash 全指纹不变、开放事务0。

## 10. 正式部署与 postdeploy

正式执行：

- `sql/current/school_phase2c_c_lesson_clearance_deploy_20260817.sql`

该原子部署以 advisory lock 包装 schema 与 backend migration，验证 P002 和空账本后 COMMIT。持久变化仅为获批表、函数、trigger、约束、ACL/RLS/comment；未写任何业务行，未调用真实 reader/writer RPC。

部署后执行：

- `school_phase2c_c_lesson_clearance_postdeploy_readonly_20260817.sql`
- `school_phase2c_c_lesson_clearance_negative_readonly_20260817.sql`
- `school_phase2c_c_lesson_clearance_business_fingerprint_readonly_20260817.sql`
- `school_phase2c_c_lesson_clearance_cash_readonly_20260817.sql`

均为 SELECT/只读断言。reader wrapper 仅 `authenticated` 执行并由 DB active membership 限定 admin/operator/read_only；writer wrapper 仅 `authenticated` 执行并由 DB 限定运营角色，PUBLIC/anon/read_only/inactive/无membership/authless拒绝；owner-only core/helper 不授予 authenticated/service_role。表对应用角色无 DML，RLS 开启。

正式 postdeploy：clearance 主表 `0` 行、明细表 `0` 行；真实 clearance writer调用 `0`；页面/API引用 `0`；生产 JS、版本号和缓存链均未修改。

## 11. 零业务变化证明

部署前后数量/整行指纹一致：

| 对象 | 行数 | MD5 |
|---|---:|---|
| lessons | 771 | `fca4b09572caba906c3f473654f40170` |
| settlements | 18 | `481ffa7ed5173da852f0f28ce66c2e9b` |
| variance claims | 2 | `fbce39067e6d98167cdb474eb9635c92` |
| bills | 22 | `e50673ac998ee2d84573a076a64d3d42` |
| bill lessons | 330 | `e3e2e0044c17864bc66c7e2861176c8b` |
| revisions | 20 | `ffdc498a6e256aa29064f021f22e4b00` |
| income | 56 | `5410e66708a01d7017de7dc331d32674` |
| Cash linkages | 44 | `f1c336c43533b9d9b81d88b6fa55feef` |
| wage locks | 104 | `bb9d5e027e482547ba4ca58b3731651a` |
| wage details | 624 | `b68ada9b934d4de511da93104228eb4b` |
| package lots | 1 | `8c2b70b087164e5d03defed8cd237f34` |
| School Storage | 57 | `62fac5521274c58c6f6982a0c690c134` |
| feature gates | 3 | `b04952a0603194dd5592124bdee2f7d7` |

Cash DB `home_cny_transactions` 为 75 行/`b5d8b7d466532b90531814e5ccf61ad2`，external requests 为44行/`1fc51497aedfaecd72a2ee85714284f0`，Storage 为0行；全部与 preflight 相同。普通待补仍 21/2400 分钟，可用超额仍4/135分钟；P002仍1200/0/1200且整行 MD5不变。

## 12. 受保护文件

原 11 份受保护 untracked 文件的路径和 SHA-256 均与基线逐字一致：

- `docs/school-v1-decommission-p1-b2a-session-service-worker-readonly-design-20260810.md` — `75474786ac2de0d9881be17b298acf51b1ad68099b6c1f88c7b0d7aac1736a47`
- `docs/school-v1-decommission-p1-ca-archive-restore-observation-readonly-design-20260810.md` — `fd703860ef2bb5ca5e159f14b0ef138ddad765c9025960aab40c245e901aec0e`
- `docs/school-v1-decommission-preflight-p1a-online-evidence-20260809.md` — `1047c2d686a43499e21a43055973475aeb0d52a9fd36c0604aa98ce8ebf0c519`
- `docs/school-v1-decommission-readonly-investigation-20260809.md` — `3e65e0091e68cd419ac13f0e692fcce99f07041abfcdab3b8786e526a800fcaa`
- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` — `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` — `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `favicon.ico` — `1f6f2cc50cb07f55e12d27163f453342baa56fc5e49ef7a6a4df79a041028903`
- `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` — `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` — `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` — `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` — `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

## 13. 后续建议（未执行）

- 建议后端稳定待命后，以独立授权进入 Phase 2C-D 页面接入；页面只能提交 UUID、分钟、类型、原因、幂等键和 manifest，并原样展示 DB Preview，不得计算可保存余额或金额。
- 首次真实试点建议选择一个未锁月、同价、低分钟、没有 active claim 的 pending/overage 精确 UUID 对；先由 reader/Preview核对 actor、分钟、单价、manifest、幂等键和目标月，单次执行后立即审计余额、history、settlement source与业务指纹。该试点本阶段未执行。
- 不进入 M016、套餐消费、真实清偿、月结页面修改或 Phase 2C-B 上线。
