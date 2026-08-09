# V1 下线 P1-B1C-R：支出附件写入功能正式退役实施报告

日期：2026-08-10（JST）

阶段：`P1-B1C-R / Expense Attachment Write Retirement`

结论：生产数据库权限收口已单事务提交；V2 runtime 创建入口已移除；历史对象与 metadata 完整保留。P1-B2、P1-C、Freeze 均未开始。

## 1. 业务决定与方案替代

业务负责人确认长期规则：V2 不再提供支出附件上传，未来 V3 也计划取消该功能。B1C-A 因 V2 没有真实二进制 Storage 合同而硬停的历史结论继续有效；原拟“新 policy 加法 → V2 切换 → 旧 INSERT 封闭”不再适用。本阶段改为直接退役 V1/V2 全部附件新增写入能力，同时把现有对象与 metadata 留给 P1-C 归档和恢复准备。

## 2. 授权边界与业务模型声明

本轮只修改目标 Storage 写权限面、附件 metadata RPC/表权限面及 V2 创建入口；未修改 V1、Auth/session/JWT/client key、Edge、Gate、cron、Webhook、Realtime、Vault、Cash、DNS、service worker 或业务 writer。

业务模型扩展声明：

- 新表、列、状态、日期/月语义、业务归属、身份、source、snapshot、金额、可写业务事实：**无**。
- 历史对象、23 条 metadata 字段、reader 权威、业务金额/状态/归属/审计链：**不变**。
- 唯一变化：依据本阶段授权，缩小 `school-expense-files` 对象写 authority，并退役 metadata 创建 RPC/UI；不形成新业务模型。
- `personal/个人名义` 及全部历史 `business_entity_id`：未删除、合并、改名或重写。

对象操作计数：upload 0、update 0、move 0、copy 0、rename 0、delete 0、download 0。metadata 业务写入 0，其他业务写入 0。

## 3. Git 与生产基线

| 仓库 | 分支/HEAD | origin/main | ahead/behind | 工作树保护 |
|---|---|---|---:|---|
| V1 `/Users/polariss710/Documents/aozora_school_system_v1_batch` | `main` / `e316598dafbe4d7f50a88c70e8bc488d792a2d49` | 同 HEAD | `0/0` | 既有 `M .gitignore` 保留，未修改 |
| V2 `/Users/polariss710/Documents/aozora_school_system_v2` | `main` / `a029b27d76177783c8c81007c56bc611e69dc7f1` | 同 HEAD | `0/0` | 既有未跟踪报告、CSV/TXT、4 个 tuition SQL 全部排除 |

本轮中其他流程把 V2 从 `562c3c7` 推进到 `a029b27`；重新 fetch、依赖搜索和语法回归后继续，未覆盖或回退他人变更。P1-B1A-R1 与 P1-B1B 提交仍为当前历史祖先。开始时线上版本为 `v10.5.32`；本轮 runtime 目标版本为 `v10.5.33`。

## 4. Preflight：Storage

| 项目 | 生产事实 |
|---|---|
| bucket | 唯一 bucket `school-expense-files`，private |
| 对象 | 57 个唯一路径，6,936,405 bytes |
| 对象/路径指纹 | `ec6522f59532814af6bbfbb1a90e1822` / `554366526bc0a983efa58d8001b7f536` |
| 分类 | 23 metadata-linked、4 expense-only、30 orphan |
| orphan 指纹 | `3b17d8c87494da6404c213009132437e` |
| V1 旧路径 | 57/57 符合 `expenses/YYYY-MM/<expense_uuid>/<file>`；旧 INSERT policy 可接受合规 active-admin 请求 |
| policy | authenticated SELECT、INSERT、恒 false UPDATE、恒 false DELETE；无 ALL/跨 bucket policy |
| service_role | DB role `BYPASSRLS=true`，对 `storage.objects` 有受管表 ACL；无合法附件写调用方 |
| 间接调用方 | V2/Edge/CI/DB function/cron/Webhook 未发现合法目标 bucket writer；V1 旧页面是唯一 runtime 上传路径 |

Supabase 官方说明 service-role key 会绕过 RLS，Storage 普通上传则由 `storage.objects` policy 控制。因此仅删除 INSERT policy 不能证明 service_role 对目标 bucket 失去写能力；现有表 grant 又来自受管 Storage owner，事务内 `REVOKE` 探针证明不会消除其有效权限。参考：<https://supabase.com/docs/guides/storage/security/access-control>、<https://supabase.com/docs/guides/troubleshooting/why-is-my-service-role-key-client-getting-rls-errors-or-not-returning-data-7_1K9z>。

## 5. Preflight：metadata 与 V2

- 表：`public.school_expense_attachments`，owner `postgres`，RLS enabled/FORCE off；23 行，指纹 `a1b50c81c634121e83b65d31309eb062`。
- 直接表 DML：PUBLIC/anon/authenticated/service_role 的 I/U/D/T 已为 false；三类客户端原有 SELECT 与 MAINTAIN，历史 authenticated SELECT policy 独立存在。
- 创建 RPC：唯一 overload `school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)`；owner `postgres`、SECURITY DEFINER、`search_path=pg_catalog, public`；仅 authenticated 可执行；定义指纹 `a7459d0479d9208b5ea01804cf5ad086`。
- V2 最新 HEAD：无真实 upload/update/remove/move/copy/download/signed URL；但详情页仍有 metadata-only 按钮、表单、API export 和 RPC 调用。列表/详情历史 reader 只查询 metadata 摘要字段。
- 移除 writer 不影响详情加载：writer export/表单与 `fetchExpenseAttachments`/`renderAttachments` 是独立代码路径。

硬停条件逐项检查均未命中：没有合法上传调用方、没有跨 bucket policy、没有复合业务 RPC、无需修改历史行/对象，也无需 Auth/Edge/Storage 新合同。

## 6. Migration 与恢复定义

生产文件：`sql/current/school_p1_b1c_r_attachment_write_retirement_20260810.sql`

SHA-256：`6779f5068459baa19813ab49374fb2c9bf90a60436dfa881e8bac59a832bad18`

单事务先 fail-closed 核对 bucket、57 对象、30 orphan、4 policy、metadata 23 行、RPC 唯一 overload/定义/ACL、角色属性与历史指纹，再执行：

1. 新建 `SECURITY INVOKER`、固定 `search_path=pg_catalog` 的目标 bucket 写入 guard 与 `BEFORE INSERT OR UPDATE OR DELETE` trigger。
2. guard 同时检查数据库 `current_user` 和请求 JWT role；目标 bucket 的 anon/authenticated/service_role 一律 `42501` 拒绝，Storage owner 的 P1-C 受控维护能力不向客户端公开。
3. 删除旧 INSERT、UPDATE、DELETE policy；原 authenticated active-admin SELECT policy原样保留。
4. 删除 metadata 表恒 false 的旧 ALL policy；历史 SELECT policy保留。
5. 撤销 metadata RPC 对 PUBLIC/anon/authenticated/service_role 的 EXECUTE；函数定义与 owner 保留并标记 retired。
6. 撤销 metadata 表客户端 DML、TRUNCATE、REFERENCES、TRIGGER、MAINTAIN；SELECT 保留。
7. postcondition 再核对权限和历史指纹后 COMMIT。

精确恢复定义：`sql/current/school_p1_b1c_r_attachment_write_retirement_restore_definition_20260810.sql`，SHA-256 `d1602b14d69adcd3301b6881fcf53512fd9e9a5cbb95760872ce3d0791ad498c`。它只恢复本轮前精确 policy/EXECUTE/MAINTAIN/comment 并移除 guard，不含对象/metadata DML；**未执行**，未来也必须另行授权。

## 7. 非生产角色矩阵

PostgreSQL 17.10 临时实例只使用合成 bucket、对象和 metadata。合成脚本 SHA-256 `6ca61bb5a1bbf374bdd4599afc4ec70632984cc0fc5dc4e7e4a135deb2800a2f`。

| 验收 | 结果 |
|---|---|
| anon / authenticated target INSERT | 拒绝 |
| service_role target INSERT/UPDATE/DELETE（含 BYPASSRLS） | guard 拒绝 |
| unrelated bucket authenticated INSERT | 成功并 ROLLBACK，证明范围隔离 |
| 历史对象 / metadata authenticated SELECT | 成功 |
| metadata RPC authenticated EXECUTE / 表 INSERT | 拒绝 |
| overload 数 | 精确 1，全部覆盖 |
| late exception atomicity | 前置 synthetic policy DDL 整体回滚，residue 0 |

结果：`P1-B1C-R SYNTHETIC MATRIX PASS`。临时实例验证结束后停止。

## 8. 正式部署记录

- 执行身份：`postgres`。
- 首个本地命令因受限环境 DNS 无法解析，在建立数据库连接前结束；服务端事务 0、生产变化 0。
- 随后以完全相同的固定哈希文件建立连接；未修改 SQL。
- 服务端结果：`BEGIN → preflight DO → CREATE FUNCTION/TRIGGER → 4 DROP POLICY → REVOKE/COMMENT → postdeploy DO → COMMIT`。
- SQL 异常：0；部分提交：0；恢复：未执行。

## 9. Postdeploy 权限

### 9.1 Storage

| before | after |
|---|---|
| authenticated active-admin旧路径 INSERT policy | 已删除 |
| authenticated UPDATE false policy | 已删除；目标 guard 仍拒绝 |
| authenticated DELETE false policy | 已删除；目标 guard 仍拒绝 |
| authenticated active-admin SELECT policy | 原定义/指纹 `b25eab5f94a7bc0841eabf79b44ee86b` 保留 |
| service_role RLS bypass | role属性未改；目标 bucket 写入由 request/db-role guard 拒绝 |

PUBLIC、anon、authenticated、service_role 对目标 bucket 的 INSERT/UPDATE/DELETE 最终均无可用路径。没有新增 bucket、路径或 policy；范围外 policy 指纹保持。

### 9.2 metadata

| 对象 | before | after |
|---|---|---|
| 创建 RPC | authenticated EXECUTE | owner-only；PUBLIC/anon/authenticated/service_role 均 false |
| metadata 表 | 客户端 SELECT+MAINTAIN，DML false | 客户端仅 SELECT；I/U/D/T/REFERENCES/TRIGGER/MAINTAIN false |
| RLS policy | SELECT + 恒 false ALL | 仅原 authenticated SELECT |
| 历史记录 | 23 | 23，同指纹 |

PUBLIC ACL residue 为 0；同名 RPC overload 仍精确 1，没有 wrapper/fallback/Edge 调用方。

## 10. V1/V2 最终行为

- V1 源码/Pages/SW 未修改；但其唯一旧 upload 请求不再满足 INSERT policy，且即使共享 active-admin session 有效也会在服务端失败。UPDATE/DELETE 同样失败。
- V2 删除详情页“新增附件摘要”按钮/对话框、页面 handler、API export 和 RPC 字符串；没有 fallback，也没有新增上传/下载/预览功能。
- `fetchExpenseAttachments`、详情 `renderAttachments` 和列表附件计数保留；UI 明确显示“附件新增功能已退役，仅保留历史摘要”。
- 本地 auth guard/login 页面显示 `v10.5.33`，console error/warn 0；生产已登录的列表/详情与历史 metadata 摘要在 Pages 上线后完成最终只读验收。

## 11. 历史与业务零变化证据

| 资源 | before = after |
|---|---|
| Storage | 57 paths / 6,936,405 bytes / object `ec6522...` / path `554366...` |
| orphan | 30 / `3b17d8...` |
| metadata | 23 / `a1b50c...` |
| expense / income / payment | `47/34a7...` / `55/c55f...` / `51/6ce6...` |
| School accounts / transactions | `3/ac9fa...` / `187/00516...` |
| lessons / settlements / bills | `744/3cd0...` / `18/481f...` / `22/e506...` |
| wage locks / details | `103/ea395...` / `612/1d45...` |
| Cash 4 tables | `7/89b057...`, `74/070c26...`, `43/f4b187...`, `31/95ab7c...` |
| Auth stable | `1/a48555...` |
| Gate | `3/b04952...`（enabled / blocked / enabled） |
| 范围外 policy / functions | `51/fbfb90...` / `626/9a240c...` |
| payment RPC | 4 个 definition/ACL 指纹全部不变 |

DB cron/Webhook catalog 继续为空。Gate、Auth、Edge、cron、Webhook、Realtime、Vault 与 payment RPC 均未修改。所有 postdeploy SQL 在 `REPEATABLE READ READ ONLY` 中运行并 `ROLLBACK`。

## 12. 恢复

没有执行恢复。V2 history reader未被权限收口阻断，故不存在恢复条件。若未来只读页面确因本轮误撤 SELECT 而阻断，只允许按恢复定义恢复精确只读权限；不得借此恢复附件新增功能或扩大权限。

## 13. 风险与 Freeze gate

| 级别 | 数量 | 本轮结论 |
|---|---:|---|
| Blocker | 4 | 综合 B2 仍需 P1-B2 关闭旧 session/SW/cache；共享资源、最后活动、恢复准备仍未闭环 |
| High | 5 | B6 的“可继续产生新 orphan”已关闭，但历史对象可验证归档/恢复仍属 P1-C，故综合风险尚未销项 |
| Medium | 4 | 不变 |
| Low | 2 | 不变 |
| Unknown | 2 | 不变 |

本轮实质消除了 V1 附件写入路径和 V2 metadata-only writer，但不把组合风险在尚未完成 P1-B2/P1-C 时提前销项。Freeze entry gate 仍为 `FAIL`，不得自动进入下一阶段。

## 14. P1-B2 / P1-C 剩余事项

- P1-B2：旧 active session、service worker/cache、跨客户端缓存收敛和旧客户端对共享新 RPC 的发现风险；需独立授权。
- P1-C：57 对象/30 orphan/23 metadata 的正式归档清单、备份覆盖、checksum、隔离恢复验证、最后活动边界和至少一个完整业务周期观察；不得删除对象。
- Freeze/Soft shutdown/V1 停服/共享 Supabase 关闭/client key 轮换：均未授权、未执行。

## 15. Git、Pages 与证据索引

- Git/Pages：runtime、migration、B1C-A报告与本报告由同一个单一职责 commit 推送；因 commit SHA 和该 push 产生的 Pages run 在本报告对象定稿后才存在，精确 SHA/run ID/最终结论记录于 GitHub 历史和本任务最终交付，不为回填自引用信息制造第二个 commit。
- Migration：`sql/current/school_p1_b1c_r_attachment_write_retirement_20260810.sql`
- Restore：`sql/current/school_p1_b1c_r_attachment_write_retirement_restore_definition_20260810.sql`
- Synthetic：`sql/current/school_p1_b1c_r_attachment_write_retirement_synthetic_20260810.sql`
- Static：`scripts/p1-b1c-r-attachment-retirement-static-test.mjs`
- Preflight/Postdeploy：`/tmp/p1_b1c_r_preflight_readonly.sql`、`/private/tmp/p1_b1c_r_postdeploy_readonly.sql`、`/tmp/p1_b1c_r_cash_readonly.sql`（本机临时证据，不入 Git）。
- B1C-A：`docs/school-v1-decommission-p1-b1c-storage-path-cutover-20260810.md`

本阶段完成后立即停止；不得继续 P1-B2、P1-C、Freeze、Soft shutdown、V1 停服、共享 Supabase 关闭或客户端 key 轮换。
