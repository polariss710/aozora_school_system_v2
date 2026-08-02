# School V2 Atomic Tuition Void/Reissue 并发验收环境硬停止报告

日期：2026-08-03（JST）
阶段：Historical Registration Manifest 补充批准后的实施前检查；**HARD STOP**

## 1. 结论

业务负责人已精确批准 `manifest_kind` 与
`historical_registration_manifest_v1`，上一轮7条 historical chain 缺少 Atomic
generation manifest 的业务模型阻塞已经解除。

继续检查实施与测试顺序时发现新的环境/授权冲突：原批准要求在生产 migration 提交前
完成真实多会话并发测试，但 PostgreSQL 未提交的三表、constraint trigger、active
revision helper 和新 RPC 对第二数据库会话不可见。当前又不存在独立 School 测试库、
staging 连接、可用本地 PostgreSQL server 或已提交的白名单 synthetic fixture。

因此无法在不扩大权限的情况下同时满足：

1. 测试实际新 DDL/RPC，而不是只测试等价伪代码；
2. 使用两个独立数据库会话；
3. 在生产 migration 提交前完成；
4. 不向生产库提交测试 fixture；
5. 测试 residue 为0；
6. 不执行未获批准的 fixture cleanup `DELETE`；
7. 不留下临时 schema/table/function 并执行禁止的 `DROP`。

本轮在 SQL 草案前停止；没有执行或创建 migration、RPC、fixture、Gate 变更或业务写入。

## 2. 技术原因

- 同一事务内的 rollback rehearsal 可以完整创建新表、函数、trigger并执行单会话
  synthetic matrix，但这些对象在事务提交前不对其他连接可见。
- 第二连接不能调用或锁定第一连接尚未提交的新对象，因此不能证明 active revision、
  active lesson claim 和 Void/Cash reservation 的真实并发合同。
- 若先把新对象或 fixture 提交到生产库，再做多会话测试，就已经越过原批准的阶段B→C→D
  顺序；若测试失败，生产 schema 已改变。
- 多会话对同一 synthetic chain 的竞争还要求两个连接看到同一批已提交 fixture。
  当前 School DB 没有 `codex-test` / `sandbox` / `v2-test` student fixture。
- 测试后 residue 0 需要删除固定 synthetic rows，当前批准没有明确授权该 committed
  fixture lifecycle，且项目默认 hard stop 包含 `delete`。

## 3. 已核对的可用环境

- `SCHOOL_TEST_SUPABASE_DB_URL`：不存在。
- `SCHOOL_STAGING_SUPABASE_DB_URL`：不存在。
- `TEST_SCHOOL_SUPABASE_DB_URL`：不存在。
- 本机只有 PostgreSQL client 工具；没有可启动的 `postgres` server binary。
- Supabase CLI 存在，但没有可用 Docker/Podman runtime。
- School生产库中没有符合 `codex-test|sandbox|v2-test` 的现成学生fixture。

## 4. 安全解锁方案

推荐方案A：提供一个隔离的 School 测试库连接，并明确其可写、可创建/删除 synthetic
fixture。Codex可在该库部署同字节 migration、执行真实多会话矩阵和 residue cleanup；
全部通过后再按原流程关闭生产 Gate、执行生产 migration，并在生产仅做无业务写的锁阻断
复核与postdeploy。

备选方案B：业务负责人精确授权生产库固定 synthetic fixture lifecycle：

- 仅使用一组预先冻结的 `codex-test atomic-void-concurrency-20260803` UUID；
- Gate关闭后提交这些测试学生、planned lesson、bill/income/relation及新revision metadata；
- 只对该固定UUID集合执行多会话测试；
- 测试完成后按固定FK逆序 `DELETE` 这些 synthetic rows；
- 删除前后逐表证明UUID、marker和引用范围，最终 residue 必须为0；
- 禁止触碰任何未在固定manifest中的记录。

方案B需要业务负责人另行明确批准 committed test INSERT 与固定范围 cleanup DELETE；当前
prompt的“明确白名单synthetic数据”不足以覆盖项目默认禁止的 `delete`，Codex不能自行
推定。

仅把多会话测试移动到 production migration 之后并不能独立解决问题，因为仍缺少两个
会话都可见、可安全清理的 committed synthetic fixture。

## 5. 当前状态

- Historical manifest补充批准：已匹配，未再阻塞业务模型。
- SQL/schema/RPC/前端草案：0。
- SQL文件执行、写RPC、Gate DML、数据库写入：0。
- 彭宇晗、李天伦及其他真实链：未void、未修改、未reissue、未提交Cash。
- Gate：`enabled / enabled / enabled`，未进入维护期。
- 两份既有未跟踪文件均未修改或暂存。
