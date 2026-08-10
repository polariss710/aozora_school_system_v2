# V1 下线 P1-B2-B：Auth Session 隔离与 Service Worker/Cache 清理

日期：2026-08-10（Asia/Tokyo）
状态：实施中；本文只记录已完成事实，未完成阶段不得视为已执行。

## 1. 执行摘要

业务负责人确认本人能够使用当前管理员账号正常密码登录，恢复邮箱可用，并批准撤销执行时唯一 Auth 用户的全部旧 session，使所有设备重新登录；同时确认会在撤销前关闭 V1 标签页和已安装的 V1 PWA。凭据、验证码、恢复链接、access token 与 refresh token 不由 Codex 获取、读取、复制或记录。

本阶段分为 B2-B1～B2-B8，严格执行 `V2 storage key 上线 → 全局撤销 → 人工重登 → 新会话验收 → 70 分钟观察 → V1 精确 cleanup`。截至本节记录时，仅 B2-B1 与 B2-B2 的本地实现/静态验证已完成；服务端 session 撤销、人工重登、70 分钟观察和 V1 cleanup 尚未执行。

## 2. 授权边界

- 允许：V2 独立 Auth storage key、精确旧 key 清理、官方全局 session 撤销、用户正常重登、只读验收、V1 精确 SW/cache/PWA cleanup、分仓库 commit/push/Pages。
- 禁止且未执行：token 迁移或输出、用户/邮箱/密码/membership 修改、Auth 内部表直接 DML、业务数据/RPC/RLS/Gate/Storage/Edge/cron/Webhook 修改、V1 停用页、重定向、DNS、Freeze、Soft shutdown、P1-C。
- 业务模型扩展：`none`；新增实体 `none`，正式 writer `none`，字段/状态机/归属扩展 `none`。

## 3. B2-B1 最新基线

### 3.1 Git 与部署

| 仓库 | branch | HEAD = origin/main | ahead/behind | 已有工作树 |
|---|---|---|---|---|
| V1 | `main` | `e316598dafbe4d7f50a88c70e8bc488d792a2d49` | `0/0` | 既有 `M .gitignore`，必须保留且排除提交 |
| V2 | `main` | `3d77b0170168c9dbfb2828cc90b58aad2730c98b` | `0/0` | 既有 9 个未跟踪证据/SQL 文件，必须保留且排除提交 |

- V1 Pages 当前部署 commit：`e316598d…`。
- V2 Pages 当前成功 run：`31328917170`，commit `3d77b017…`，线上版本 `v10.5.37`。
- P1-B1A `437642…`、B1B `a78c…`、B1C-R `1fa67…` 均仍为当前 V2 HEAD 的祖先。
- P1-B2-A 报告继续作为未跟踪证据保留，本阶段不把它并入提交。
- 本阶段开始时没有未合并的 ahead/behind；其他 settlement 流程已把 V2 推进到上述最新 HEAD，Auth 文件自 P1-B2-A 基线以来未发生并行逻辑变化。

### 3.2 登录与 Auth 设置

- V2 正式登录页可打开；生产已登录页面显示 `v10.5.37`，active-admin guard 正常。
- Email/password provider enabled；公开 signup off；anonymous signup off；confirm email on。
- 标准 email recovery 能力由已启用 Email provider 提供；V2 当前没有自建 recovery 页面。业务负责人已确认正常密码与恢复邮箱可用，因此本阶段不触发 recovery，也不发送恢复邮件。
- Auth 用户 1、active 1、anonymous 0、deleted 0；membership 1，且为 active admin。
- `scripts/p0-g1-a-auth-guard-static-test.mjs`：31/31 业务 HTML entry 均接入统一 fail-closed guard，结果 `PASS`。

### 3.3 Session 只读快照

快照事务：`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY`，结束 `ROLLBACK`。

| 项目 | 结果 |
|---|---|
| potentially-active sessions | 12 |
| 对应用户 | 唯一用户 1；脱敏用户标识另存为哈希证据，不记录完整 ID |
| non-revoked refresh tokens | 12 |
| revoked refresh-token history | 402 |
| 最近 session refresh | 2026-08-10 03:09:01 JST |
| access-token expiry | 3600 秒 |
| rotation / reuse interval | enabled / 10 秒 |

全局撤销只允许使用 Supabase 官方 Auth client `signOut({scope:'global'})`；它撤销目标用户的 refresh session，不删除用户、不修改密码/邮箱/membership。不得直接 DML `auth.sessions` 或 `auth.refresh_tokens`。

## 4. B2-B2 V2 独立 storage key 设计

- 新 key：`aozora-school-v2-auth-v1`，稳定且版本化；不是默认 project-derived key，也不作为秘密。
- 旧默认 key 仅在代码中作为精确 cleanup 常量存在；报告只保留项目 ref 脱敏标识 `xlcdq…dsrr`。
- 线上 `@supabase/supabase-js@2` 在实施时解析为 `2.112.2`。该版本源代码确认支持 `auth.storageKey`，并使用主键、`-user`、`-code-verifier`、`-flows-code-verifier` 及 flow-index 精确列出的 verifier key。
- cleanup 先读取且只解析 SDK 的 flow-index（不读取旧 session 值），再精确删除上述 allowlist；不枚举 `sb-*`，不调用 `localStorage.clear()`/`sessionStorage.clear()`，不影响主题、语言或其他应用项。
- cleanup 任一步异常即使生产 client 保持 placeholder/fail-closed，`hasSupabaseConfig()` 返回 false；没有默认 key fallback。
- 没有读取旧 session 后 `setSession`，没有把默认 key 内容复制到新 key，没有 token 日志。
- V2 全部 53 个 Supabase import 统一到同一版本化 client URL；31 个业务 entry、登录页及 32 个 HTML module cache key 同步更新，防止同页产生多个 Auth client 或 CDN 继续命中旧模块。

## 5. B2-B2 非生产验证（部署前）

| 验收 | 结果 |
|---|---|
| `createClient` 唯一实例 | 1 |
| 31/31 guard | PASS |
| synthetic 旧主 key/`-user`/verifier/flow-index 精确删除 | PASS |
| synthetic 新 key 保留 | PASS |
| theme/language/其他 app 项保留 | PASS |
| 非法 flow-index fail closed | PASS |
| `setSession` / blanket clear / default fallback | 0 |
| session/token console 输出 | 0 |
| V2 目标版本 | `v10.5.38` |

验证命令：

```text
node scripts/p1-b2b-auth-storage-static-test.mjs
node scripts/p0-g1-a-auth-guard-static-test.mjs
```

两者均返回 `PASS`。测试只使用 synthetic 字符串，不包含生产 token。

## 6. 业务零变化基线

以下为部署前只读快照；最终报告必须用同一查询比较允许变化与异常变化。

| 资源 | count |
|---|---:|
| lesson / settlement / tuition bill | 744 / 18 / 22 |
| wage lock / detail | 103 / 612 |
| payment / expense / income | 51 / 47 / 55 |
| School account / transaction | 3 / 187 |
| attachment metadata | 23 |
| Storage object / bytes | 57 / 6,936,405 |
| Cash account / request / CNY / JPY | 7 / 43 / 74 / 31 |
| Gate | 3 |
| RLS policies / public functions / user triggers | 52 / 346 / 98 |
| DB cron / Database Webhook catalog | absent / absent |

每类另有全行或安全字段 MD5 指纹；不记录业务明文或秘密。允许的后续 Auth 变化只限旧 session/refresh token 撤销与业务负责人正常重登产生的新 session。

## 7. 后续阶段检查点（尚未执行）

- B2-B2：提交、push、Pages 成功及独立浏览器未登录验收。
- B2-B3：执行时再次快照后，官方 global sign-out 单次撤销；记录起止时间与最晚 JWT 截止时间。
- B2-B4：强制暂停，等待业务负责人本人正常登录并只回复确认语。
- B2-B5/B6：新 key/session、31/31 guard、核心只读页与至少 70 分钟观察。
- B2-B7：只有全部 gate 通过后，才允许 V1 精确 cleanup；V1 普通网络页面保持在线。
- B2-B8：最终业务不变量、风险、Freeze gate、Git/Pages 与 `docs/current-status.md`。

## 8. 回滚

截至当前未执行回滚。global revoke 前若 V2 部署异常，可恢复上一成功 V2 Auth artifact；global revoke 后不得恢复旧 token，只能 fix-forward 后由用户正常登录。V1 cleanup 失败时不恢复 writer，不扩大 cache 清理。

## 9. 证据索引

- 设计基线：`docs/school-v1-decommission-p1-b2a-session-service-worker-readonly-design-20260810.md`（既有未跟踪文件，未纳入本阶段 commit）。
- V2 实现：`js/auth-storage-isolation.js`、`js/supabase-client.js`、统一 import/cache-query 变更。
- 静态验收：`scripts/p1-b2b-auth-storage-static-test.mjs`、`scripts/p0-g1-a-auth-guard-static-test.mjs`。
- 生产 SQL：`/private/tmp/b2b_school_baseline.sql`、`/private/tmp/b2b_cash_baseline.sql`（临时只读证据，不提交；事务均 `ROLLBACK`）。
- 官方源代码/文档：Supabase JS/Auth JS `2.112.2` 的 `storageKey` 与 verifier 命名；Supabase Auth sessions/global sign-out 文档。
