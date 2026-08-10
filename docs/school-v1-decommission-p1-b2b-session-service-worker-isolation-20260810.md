# V1 下线 P1-B2-B：Auth Session 隔离与 Service Worker/Cache 清理

日期：2026-08-10（Asia/Tokyo）
状态：已完成；B2-B1～B2-B8 全部通过。V1 仍保持普通网络页面在线，Freeze、Soft shutdown 与 P1-C 均未开始。

## 1. 执行摘要

业务负责人确认本人能够使用当前管理员账号正常密码登录，恢复邮箱可用，并批准撤销执行时唯一 Auth 用户的全部旧 session，使所有设备重新登录；同时确认会在撤销前关闭 V1 标签页和已安装的 V1 PWA。凭据、验证码、恢复链接、access token 与 refresh token 不由 Codex 获取、读取、复制或记录。

本阶段分为 B2-B1～B2-B8，严格执行 `V2 storage key 上线 → 全局撤销 → 人工重登 → 新会话验收 → 70 分钟观察 → V1 精确 cleanup`。V2 新 key 已部署，旧 session 已全局撤销，业务负责人已正常重登；观察窗结束后旧 session 未重现。V1 的唯一旧 service worker registration 与精确 cache `school-v1-cache` 已通过最小 cleanup 发布并在生产完成清理，普通 V1 网络页面仍可访问。本阶段没有执行 Freeze、Soft shutdown、DNS、密钥、Supabase 项目或 P1-C 操作。

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

## 7. B2-B2 生产部署

- V2 commit：`db6d8618ede8f4626cdb346ee86f1cbf1198e4bc`。
- GitHub Pages run：`31343583980`，结论 `success`。
- 线上版本：`v10.5.38`；登录页与 `supabase-client.js` 均命中 `p1-b2b-auth-storage-20260810-1` artifact。
- 独立浏览器未登录验收：31/31 业务入口全部 fail-closed 到登录页，console error/warn 0；未读取、复制或迁移旧 token。

## 8. B2-B3 全局撤销

- 执行方法：保持原 V2 已登录页面不刷新，在该页面已经初始化的旧 canonical Supabase client 内调用官方 `supabase.auth.signOut({scope:'global'})`；不把 JWT/refresh token 暴露给命令行、报告或工具输出。
- 开始：2026-08-10 00:12:05.701 UTC；结束：2026-08-10 00:12:06.965 UTC（09:12:06 JST）。
- 单次调用结果：`ok=true`，error code/status 均为空；没有第二种方法或重复尝试。
- 执行前：12 sessions、12 non-revoked refresh tokens、唯一用户 1、active-admin membership 1。
- 执行后：sessions 0、refresh tokens 0；唯一用户与 active-admin membership 仍各 1。Supabase 本次 global sign-out 删除旧 session/refresh 行，而非保留 revoked-history 行。
- 旧 access JWT 最晚观察截止：2026-08-10 01:22:06 UTC / 10:22:06 JST（3600 秒 + 10 分钟余量）。截止前不得声称旧 JWT 全部失效，也不得发布 V1 cleanup。

## 9. B2-B4 人工重新登录

Codex 在撤销后暂停并发送规定提示；业务负责人本人使用正常密码登录并回复“V2重新登录成功”。未向 Codex 提供邮箱、密码、验证码、恢复链接或 token。新 session 创建时间为 2026-08-10 00:27:27 UTC（09:27:27 JST）。

## 10. B2-B5 新 Session 与 Guard 验收

| 验收 | 结果 |
|---|---|
| Auth users / active-admin membership | 1 / 1，不变 |
| sessions / non-revoked refresh tokens | 1 / 1，归属唯一用户 |
| 旧 12 条 session/refresh token 重现 | 0 |
| 线上 client storage key | `aozora-school-v2-auth-v1` |
| 页面刷新后 session 恢复 | PASS；仍为 `auth-authorized` |
| 默认 key 迁移/回退 | 0；cleanup 代码 + synthetic 测试 + 新 key client + 刷新恢复形成证据链 |
| 31/31 已登录 guard | PASS |
| payment、课时、月结、工资、收入、支出、账户核心只读页 | PASS；均 authorized/session bar，页面错误 0 |
| console error/warn | 0 |

浏览器安全边界禁止直接枚举 localStorage，因此没有读取任何 storage value。新 key 存在性以生产 client 的 `auth.storageKey`、正常登录后刷新仍恢复，以及唯一新 session 三项证据确认；旧默认 key 不再使用以精确 cleanup 实现、synthetic allowlist 测试、无 fallback/`setSession` 和 V1 默认-key client 代码差异确认。

同一套只读业务快照前后完全一致：lesson/settlement/bill `744/18/22`，wage lock/detail `103/612`，payment/expense/income `51/47/55`，School account/transaction `3/187`，attachment metadata 23，Storage `57 / 6,936,405 bytes`，Cash `7/43/74/31`，Gate 3，RLS policy/public function/user trigger `52/346/98`，DB cron/Webhook catalog 仍 absent。对应指纹全部与 B2-B1 相同。唯一允许变化为 Auth last-sign-in、新 session 1 与 refresh token 1。

## 11. B2-B6 旧 JWT 失效窗口复核

- 复核时间：2026-08-10 01:28:54 UTC / 10:28:54 JST，晚于最早截止 10:22:06 JST。
- Auth users / active-admin membership 仍为 `1 / 1`；sessions 为 1，non-revoked refresh tokens 为 1，均属于业务负责人重新登录产生的唯一新 session。
- 被撤销的旧 12 条 session/refresh token 没有重现。
- 业务、Cash、Storage、Gate、RLS policy、public function 与 user trigger 的 count 及指纹全部与 B2-B1 基线一致；DB cron 与 Database Webhook catalog 仍 absent。
- 结论：B2-B6 gate `PASS`，允许进入 B2-B7；没有提前发布 V1 cleanup。

## 12. B2-B7 V1 Service Worker/Cache 精确清理

### 12.1 实现边界

- `service-worker.js` 不再预缓存、拦截 fetch 或 claim client；install 仅 `skipWaiting()`，activate 仅删除精确 cache `school-v1-cache` 并注销自身。
- 新增 `js/v1-browser-lifecycle-cleanup.js`：只接受精确 scope `/aozora-school-system-v1/`，先尝试更新该 registration，再注销；只删除精确 cache `school-v1-cache`。不枚举 cache 名称，不清理 V2，不读取/删除 localStorage、sessionStorage、cookie 或 IndexedDB，不重定向页面。
- `js/legacy-core.js` 删除旧 service-worker register 路径；`index.html` 删除动态 manifest link，引入版本化 cleanup。`manifest.json` 文件保留，但普通页面已不再引用。
- 没有新增停用页、下线提示或 V2 跳转；没有改动任何 V1 writer 路径。

### 12.2 非生产验收

在临时同路径 HTTP fixture 中先建立精确 V1 registration、`school-v1-cache` 与无关 `unrelated-cache`：

| 检查 | 首次 cleanup | 第二次 cleanup |
|---|---|---|
| V1 registration | 已注销 | 缺失时安全通过 |
| `school-v1-cache` | 已删除 | 缺失时安全通过 |
| `unrelated-cache` | 保留 | 保留 |
| V2 probe/controller | 未受影响 | 未受影响 |
| console error/warn | 0 | 0 |

静态与 VM worker 测试 `node scripts/p1-b2b-v1-cleanup-static-test.mjs` 返回 `PASS`。临时服务停止，fixture 未进入仓库，也未连接 Auth、Storage 或业务数据库。

### 12.3 生产发布与验收

- V1 commit：`d8dcd1d18658b41df8bfe39d0fcf5f55c8b7f56f`。
- GitHub Pages legacy build：`1142153720`，状态 `built`，commit 与上述一致。
- cleanup 前，同源浏览器确认精确 V1 registration scope 与 `school-v1-cache` 各 1。
- 首次加载新 V1 artifact 后：registration 0、cache 0、manifest link 0；当前旧 realm 在当次导航仍可能短暂显示原 controller，这是 Service Worker 生命周期预期。
- 再次普通网络 reload 后：registration 0、cache 0、controller `null`、manifest link 0，V1 页面仍正常加载。
- V2 复核：仍为 `auth-authorized`，版本 `v10.5.38`，controller `null`、registration 0、cache 0；V2 页面与 session 未被 V1 cleanup 清理。
- V2 console error/warn 0。V1 console 仅有 2 条既有“附件 relation 读取失败后降级”warning，与本阶段 cleanup 无关；没有 cleanup error。

精确 cleanup 只能在设备重新连接并加载新 artifact 后生效，不能远程卸载长期离线设备上已安装的 PWA；因此不声称所有离线设备已经物理清理。即使离线设备仍显示旧静态 UI，旧 refresh sessions 已全局撤销、旧 access JWT 已过期，且 P1-B1A/B1B/B1C-R 已关闭已知服务端写入口。

## 13. B2-B8 最终零变化验收

最终只读快照时间：2026-08-10 01:37:31 UTC。所有生产 SQL 均在只读事务内结束 `ROLLBACK`。

| 资源 | 最终结果 | 与基线比较 |
|---|---:|---|
| lesson / settlement / tuition bill | 744 / 18 / 22 | count 与指纹不变 |
| wage lock / detail | 103 / 612 | 不变 |
| payment / expense / income | 51 / 47 / 55 | 不变 |
| School account / transaction | 3 / 187 | 不变 |
| attachment metadata | 23 | 不变 |
| Storage object / bytes | 57 / 6,936,405 | 不变，对象操作 0 |
| Cash account / request / CNY / JPY | 7 / 43 / 74 / 31 | 不变 |
| Gate | 3 | 不变 |
| RLS policy / public function / user trigger | 52 / 346 / 98 | 不变 |
| DB cron / Database Webhook catalog | absent / absent | 不变 |
| Auth users / active-admin memberships | 1 / 1 | 身份与权限不变 |
| Auth sessions | 1 | 仅业务负责人新登录 session |
| refresh tokens | 2 total / 1 non-revoked | 同一新 session 的正常 rotation 产生 1 条 revoked history；旧 12 条未重现 |

本阶段没有业务 SQL/RPC 调用、业务 DML、Storage 对象操作、Auth 内部表直接 DML、用户/邮箱/密码/membership 修改，也没有 DB schema/RLS/Gate/Edge/cron/Webhook/DNS/密钥/Supabase 项目变更。持久变化仅为获批的 V2 Auth client/session 隔离代码、V1 SW/cache cleanup 代码、两仓库 Pages artifact，以及 Supabase Auth 官方流程产生的旧 session 撤销和正常新登录/refresh rotation。

## 14. 最终问题逐项结论

| 问题 | 结论 |
|---|---|
| V2 是否稳定使用独立 storage key | 是；生产 client 为 `aozora-school-v2-auth-v1`，刷新后仍恢复唯一新 session |
| 旧默认 key 是否被迁移到新 key | 否；代码无 token 读取、`setSession` 或 fallback，仅做精确删除 |
| 所有旧 session 是否撤销 | 是；12→0，观察窗后未重现；之后仅有用户新登录 session |
| 旧 access JWT 是否越过失效窗口 | 是；在 expiry + 10 分钟后复核通过 |
| V1 普通代码能否自动恢复 V2 新 session | 不能；V1 SDK 使用 project-derived 默认 key，V2 使用独立 key，且无迁移/回退代码 |
| V1 SW registration 与目标 cache 是否清除 | 已在执行验收设备清除；长期离线设备须重新联网加载新 artifact 后 cleanup，不能宣称远程物理卸载 |
| V1 是否仍能普通网络访问 | 是；本轮不是 Freeze 或 Soft shutdown |
| V1 能否新建 standards-based PWA 安装 | 普通入口已无 manifest link、无 register 路径，不能再通过该入口建立旧 PWA；既有离线安装不能被远程强制卸载 |
| V2 页面、cache、SW 与新 session 是否受影响 | 否；生产复核 authorized，V2 无被误删 registration/cache，session 正常 |
| 业务、财务、Cash、Storage、审计链是否变化 | 否；最终 count/指纹全部与基线一致 |
| 是否执行回滚 | 否；所有 gate 首次通过，无回滚 |

## 15. 风险与 Freeze entry gate

在 P1-B2 完整闭环后，综合风险更新为：

| 等级 | 数量 | 变化依据 |
|---|---:|---|
| Blocker | 3 | session/SW/cache 组合 blocker 已关闭；仍有共享 Supabase/关键资源不可整体关闭、最后 V1 业务活动归属证据、可验证归档/恢复路径 |
| High | 4 | 已关闭“联网设备继续由旧 SW/cache 运行”的 High；长期离线设备残留转为观察期风险 |
| Medium | 4 | 包含离线设备重新联网后的 cleanup 覆盖观察 |
| Low | 2 | 不变 |
| Unknown | 1 | 仍缺完整 cookie/IndexedDB/其他浏览器存储面证据；代码未使用或清理这些范围 |

Freeze entry gate 仍为 `FAIL`。P1-B2 完成不授权也不满足 V1 Freeze；下一阶段只能在业务负责人独立批准后进入 P1-C，补齐可验证归档/恢复、最后活动归属和共享资源边界。本轮不得顺带执行 P1-C、Freeze、Soft shutdown、DNS、密钥或 Supabase 项目动作。

## 16. 回滚与恢复边界

- 本次回滚 0。
- global revoke 不可通过恢复旧 token 回滚；如 Auth client 出现问题，只能恢复上一成功 V2 artifact 后由用户重新登录，或 fix-forward。
- V1 cleanup artifact 可通过独立授权恢复前一代码 artifact，但不应重新开放已关闭 writer，也不应恢复旧 token。重新注册 SW/重建 cache 会重新引入本阶段已关闭风险，因此不是默认回滚。
- 本阶段没有删除业务数据、Auth 用户、Storage 对象或数据库对象；业务恢复路径未被改变。但“完整可验证历史归档/恢复”仍是 P1-C blocker。

## 17. Git、Pages 与证据索引

- V2 Auth 实现 commit：`db6d8618ede8f4626cdb346ee86f1cbf1198e4bc`；Pages run `31343583980` success；版本 `v10.5.38`。
- V1 cleanup commit：`d8dcd1d18658b41df8bfe39d0fcf5f55c8b7f56f`；Pages legacy build `1142153720` built。
- V1 既有 `.gitignore` 修改保持未提交；V2 既有 9 个未跟踪证据/SQL 文件保持未提交。本阶段最终文档 commit 只包含本报告与 `docs/current-status.md`。
- 设计基线：`docs/school-v1-decommission-p1-b2a-session-service-worker-readonly-design-20260810.md`（既有未跟踪文件，未纳入本阶段 commit）。
- V2 实现：`js/auth-storage-isolation.js`、`js/supabase-client.js`、统一 import/cache-query 变更。
- V2 静态验收：`scripts/p1-b2b-auth-storage-static-test.mjs`、`scripts/p0-g1-a-auth-guard-static-test.mjs`。
- V1 实现：`service-worker.js`、`js/v1-browser-lifecycle-cleanup.js`、`js/legacy-core.js`、`index.html`。
- V1 静态验收：`scripts/p1-b2b-v1-cleanup-static-test.mjs`。
- 生产 SQL：`/private/tmp/b2b_school_baseline.sql`、`/private/tmp/b2b_cash_baseline.sql`（临时只读证据，不提交；事务均 `ROLLBACK`）。
- 官方源代码/文档：Supabase JS/Auth JS `2.112.2` 的 `storageKey` 与 verifier 命名；Supabase Auth sessions/global sign-out 文档。
- 未输出任何密码、JWT、service-role key、refresh token、验证码、恢复链接或数据库连接秘密。
