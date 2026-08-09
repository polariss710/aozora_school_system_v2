# School V1 下线 P1-B1C：Storage 旧上传路径版本化迁移与封闭

- 日期：2026-08-10（Asia/Tokyo）
- 结论：**B1C-A 只读 Preflight 完成；命中硬停条件，B1C-B～E 未实施**
- 当前安全状态：生产业务数据、Storage 对象、数据库对象/policy、部署、DNS、任务、密钥均为零变化
- V1 基线：`main/e316598dafbe4d7f50a88c70e8bc488d792a2d49`
- V2 基线：`main/6170f0ceda11d40b796e17fa7830fa39755fbc3f`
- 生产页面版本：`v10.5.31`

## 1. 执行摘要

本轮完成了工作区、线上静态 bundle、V1/V2 调用、生产 bucket、57 个对象、30 个 orphan、附件引用、ACL/RLS/policy、数据库函数、Edge/CI/cron 线索和关键业务指纹的只读 Preflight。生产查询均在 `REPEATABLE READ READ ONLY` 事务中运行并以 `ROLLBACK` 结束；未调用业务 RPC，未调用 Storage upload/update/remove/move/copy/download API。

Preflight 发现本轮授权前提与当前 V2 实现不一致：V2 **没有真实二进制附件上传、读取、预览或下载链**。V2 当前只有 `school_create_expense_attachment_metadata(...)` metadata-only RPC；该 RPC 不接受 `storage_bucket`、`storage_path` 或 `public_url`，而是强制生成 `metadata-only/...` 占位路径。V2 页面查询也刻意不读取这些 Storage 字段，并明确显示“不提供下载、预览、上传、删除”。附件表直接 DML 已封闭。

因此，在不修改业务 RPC/附件引用契约、不新增真实上传与读取能力的前提下，无法把 V2 “切换”到新 Storage 路径。单独新增新前缀 INSERT policy 会产生一个没有正式调用方、没有可靠附件引用落库链、且旧 session 可主动发现的额外写面；若直接关闭旧 policy，则会关闭当前唯一真实上传能力并违反“V2 线上切换先于旧路径封闭”。这命中任务第十一节硬停条件中的：

- V2 附件读取无法同时兼容旧对象与新对象；
- 需要超出 Storage policy 与既有上传代码切换范围，修改业务 writer/引用契约；
- 不能在当前合同下证明新上传正向成功且不制造 orphan/dangling metadata。

故本轮没有部署加法 policy、没有选择最终生产新前缀、没有修改 V2、没有关闭旧路径、没有 commit/push/Pages run。Freeze entry gate 继续 `FAIL`。

## 2. 授权边界与零变化声明

### 2.1 已执行

- 读取 V1/V2 最新代码、SQL、历史报告、Git 状态和线上静态 bundle。
- 对 School 生产库执行显式只读事务中的 catalog、aggregate、hash 查询。
- 只读核对 `storage.buckets`、`storage.objects`、RLS/policy、ACL、角色继承、业务引用和业务表指纹。
- 新增本只读硬停报告，并在 `docs/current-status.md` 追加事实。

### 2.2 未执行

- Storage 对象 upload/update/delete/move/copy/rename/download：0。
- bucket、对象 metadata、附件引用变化：0。
- SQL DDL/DCL、policy/comment、schema、RPC、Gate 变化：0。
- 支出、收入、payment、Cash、账户、工资、月结、账单、课时业务写入：0。
- Auth/session/key、Edge、cron、Webhook、Realtime、Vault 变化：0。
- V1/V2 页面、版本、service worker、DNS、部署变化：0。
- synthetic 写测试：未开始。硬停发生在生产变更设计准入之前；没有必要为不可实施的合同创建迁移测试。
- commit、push、Pages run、恢复：0。

### 2.3 Business-model expansion declaration

| 项目 | 本轮事实 |
|---|---|
| 新表、列、enum/status、日期/月、归属、身份、来源、快照/version 业务概念 | none |
| 新可写事实 | none |
| 现有字段语义、可变性、锁定规则 | unchanged |
| writer/reader authority | unchanged；旧 Storage INSERT 仍存在 |
| 新权威来源、fallback、dual-read、dual-write | none |
| 历史解释、`personal/个人名义` | unchanged |
| destructive schema change | none |
| 批准依据 | 当前 P1-B1C 只允许 Storage 路径/policy 切换；所需业务 RPC/引用合同修改未获批准 |

## 3. Git、部署和并发基线

| 项目 | V1 | V2 |
|---|---|---|
| 本机路径 | `/Users/polariss710/Documents/aozora_school_system_v1_batch` | `/Users/polariss710/Documents/aozora_school_system_v2` |
| branch/HEAD | `main/e316598dafbe4d7f50a88c70e8bc488d792a2d49` | `main/6170f0ceda11d40b796e17fa7830fa39755fbc3f` |
| remote main | 同 HEAD | 同 HEAD |
| ahead/behind | `0/0` | `0/0` |
| P1-B1B commits | 不适用 | `f22a327…`、`a78c25d…` 均在当前历史中 |
| P1-B1B 后推进 | 无 | `008dfe2…`、`6170f0c…`，为 settlement Edge/文档流程 |
| 既有工作树 | `M .gitignore` | 8 个既有 untracked 报告/CSV/TXT/SQL |

本轮开始和报告落盘前分别确认本地 `origin/main` 与远端 `refs/heads/main`。V2 线上 `config.js` 与本地 SHA-256 一致，版本为 `v10.5.31`。线上 V1 `legacy-core.js` 与本地 SHA-256 均为 `718d438dbfb9242dffc3be9db9fd090f3fd007581a47640d5e77725dce0bd888`；线上 V2 `expense-detail-api.js`、`expense-detail-page.js` 与本地也分别完全一致。

报告落盘期间，另一个 settlement 流程在 V2 工作树新增了 4 个 modified 页面/API文件和 1 个 untracked JS。本轮没有修改、暂存、清理或纳入这些并发文件；它们与本报告/current-status 两项变化分开列示。HEAD 未因这些未提交文件变化。

## 4. Bucket 与对象只读基线

| 项目 | 结果 |
|---|---|
| bucket id/name | `school-expense-files` |
| public | `false`（private） |
| file size limit | 未设置 bucket 级限制 |
| MIME allowlist | 未设置 bucket 级 allowlist |
| bucket created/updated | `2026-05-18T03:54:32.838321Z` / 同值 |
| bucket row MD5 | `de2441274ca7ee9620abce7e945b2ce0` |
| object count / distinct path | `57 / 57`，无同名路径 |
| total bytes | `6,936,405` |
| owner/owner_id | 57/57 均为空 |
| created/updated/last-access range | `2026-05-18T04:49:17.761780Z` ～ `2026-06-01T01:11:21.719690Z` |
| object fingerprint | `ec6522f59532814af6bbfbb1a90e1822` |
| path fingerprint | `554366526bc0a983efa58d8001b7f536` |
| MIME | PDF 48 个 / 6,742,608 bytes；JPEG 9 个 / 193,797 bytes |

全部 57 个对象第一层均为 `expenses`；月份分布为 2026-04：5、2026-05：48、2026-06：4。57/57 均匹配脱敏结构：

```text
expenses/YYYY-MM/<expense_uuid>/<timestamp>_<sanitized-basename>.<extension>
```

没有 `metadata-only/` 物理对象，没有双斜线、`..`、`.` 段或其他非规范路径；对象名均唯一，因此没有可由 catalog 证明的同名覆盖。`created_at = updated_at = last_accessed_at` 的逐对象事实与 `upsert:false` 源码一致，但仅凭时间相等不能反向证明所有历史请求从未尝试 upsert。

## 5. 30 个 orphan 保留证明与引用关系

| 分类 | 数量 | 本轮动作 |
|---|---:|---|
| 与 `school_expense_attachments.storage_bucket/storage_path` 精确匹配 | 23 | 保留 |
| 无附件行，但路径 UUID 对应现存支出 | 4 | 保留 |
| 无附件行且当前支出不存在（既有 orphan 分类） | 30 | 保留 |

- orphan 指纹：`3b17d8c87494da6404c213009132437e`
- 附件行总数/目标 bucket 引用：`23/23`
- 附件行指纹：`a1b50c81c634121e83b65d31309eb062`
- 本轮未输出真实对象名、原始文件名、签名 URL 或附件内容。
- 本轮未下载、删除、移动、复制、重命名、覆盖或修改任何 orphan/object。

## 6. V1/V2 Storage 调用矩阵

| 仓库/运行时 | 位置 | 操作与路径 | 身份/页面 | 当前状态 |
|---|---|---|---|---|
| V1 | `js/legacy-core.js:1835-1859,1916-1958` | `upload()` 到旧路径；`upsert:false`；随后直接 INSERT 附件 metadata | 同源共享 session 下可为 authenticated active admin；支出保存/附件选择 | 线上 bundle 与 HEAD 一致，仍可触发 object INSERT；metadata INSERT 受表权限拒绝，可制造 orphan |
| V1 | `js/legacy-core.js:39-51,213-225` | 从附件行读取 `public_url` 并渲染 `<a>`；同时 relation SELECT 全附件字段 | 同页面 | bucket private，`getPublicUrl()` 不产生 signed URL；能否实际打开取决于 Storage 访问语义，不能视为可靠私有对象下载链 |
| V2 | `js/api/expense-detail-api.js:106-116,237-256,439-451` | 只读摘要列；调用 metadata-only RPC | authenticated active admin | 没有 `storage_bucket/storage_path/public_url` 读取，也没有 Storage client 操作 |
| V2 | `js/pages/expense-detail-page.js:699-721,968-1071` | 文件名/类型/大小/来源/备注表单；无 `<input type=file>` | 支出详情 | 明确“不提供下载、预览、上传、删除或 OCR” |
| V2 DB writer | `sql/current/school_create_expense_attachment_metadata_rpc.sql` | 插入附件行，生成 `metadata-only/<expense_uuid>/<attachment_uuid>/<safe-name>` 占位路径 | authenticated active admin SECURITY DEFINER | 不上传对象；不接受真实 object path/public URL |
| V2 Edge | `supabase/functions/**` | 精确搜索无 bucket/Storage 调用 | n/a | 无调用方证据 |
| CI | `.github/workflows/pages.yml` | push/workflow_dispatch 静态 Pages；无 schedule/Storage | GitHub Actions | 无后台 Storage writer |

数据库函数反向搜索只命中 Supabase Storage 自身的 3 个 list/search helper，未发现 School 业务函数引用该 bucket 或 `storage.objects`。数据库无可见 `cron.job` relation；仓库无 schedule。未发现 Webhook/外部系统写入证据，但平台控制面未在本轮新增写入验证，因此继续按已有调查结论处理，不推断不存在所有外部调用。

## 7. 在线 Storage policy 与 ACL 矩阵

`storage.objects`/`storage.buckets` 均启用 RLS，owner 为 `supabase_storage_admin`，FORCE RLS 为 false。PUBLIC 没有 ACL 条目；anon/authenticated/service_role 有 Supabase 管理的表 ACL，实际客户端能力还必须通过 RLS。`storage.buckets` 没有 policy，因此普通客户端无可通过的 bucket 行操作路径。

| policy | cmd/role | 条件 | 实际目标 bucket 能力 |
|---|---|---|---|
| `school_allow_all_storage_expense_files_select` | SELECT / authenticated | bucket + 当前 membership 为 active admin | active admin 可 SELECT 历史对象；anon、无 membership、inactive、operator、read_only 不通过 |
| `school_allow_all_storage_expense_files_insert` | INSERT / authenticated | bucket + 精确旧路径 regex + active admin + 路径 expense UUID 存在、`app_type=school`、月份一致、非 `teacher_wage` | active admin 可向旧 V1 空间 INSERT；anon 等不通过 |
| `school_allow_all_storage_expense_files_update` | UPDATE / authenticated | `USING false WITH CHECK false` | 无客户端 UPDATE |
| `school_allow_all_storage_expense_files_delete` | DELETE / authenticated | `USING false` | 无客户端 DELETE |

没有 ALL policy、PUBLIC policy、anon policy、任意 authenticated 宽泛 policy、新 V2 前缀 policy或第二个目标 bucket policy。`upload(..., upsert:false)` 走 INSERT；现有 UPDATE 恒假也阻止客户端覆盖既有路径。service_role 的 Storage ACL/RLS bypass 能力属于共享平台后端能力，但仓库 Edge/DB/CI 未发现对该 bucket 的使用；本轮未收紧 service_role。

## 8. 路径设计结论与不相交证明

V1 已部署代码固定生成顶层 `expenses/`。若后续获得业务 writer/引用合同授权，候选空间应使用完全不同的固定顶层，例如：

```text
v2-expense-attachments/v1/YYYY-MM/<expense_uuid>/<server-or-contract-issued-object_uuid>
```

这只是后续设计候选，**不是本轮选定或部署的生产合同**。固定第一层 `v2-expense-attachments` 与旧第一层 `expenses` 可构成结构上的严格不相交；对象尾段不直接采用原始文件名，且须拒绝 `..`、`.`、空段、双斜线与非 UUID 段，默认 `upsert=false`。

当前不能最终定稿的原因不是前缀字符串，而是缺少原子业务合同：谁签发 attachment/object UUID、何时创建附件行、上传失败/响应丢失如何恢复、metadata 失败如何避免 orphan、历史 private object 如何安全读取。仅靠浏览器随机路径和 INSERT policy 不能解决这些问题。

## 9. 硬停证据

1. V2 线上与本地均不存在 `.storage/.upload/getPublicUrl/createSignedUrl/download/remove/move/copy` 的附件运行时调用。
2. V2 附件 RPC 参数只有 expense id、文件名、类型、大小、来源、备注；没有真实 Storage 引用参数。
3. RPC 强制生成 `metadata-only/...` 占位路径；它本身不上传、下载、预览、删除。
4. V2 reader 刻意遗漏 `storage_bucket/storage_path/public_url`；页面不能读取新旧物理对象。
5. `school_expense_attachments` 对客户端直接写已封闭；不能用直接表 DML 补写新对象引用。
6. 修改 RPC/附件引用合同被本轮第四节“不得修改 Storage 以外业务表、业务 RPC”明确禁止。
7. 新增 policy 但无正式调用方会扩大共享 session 的可发现写面；上传后仍无法可靠落引用，可能产生第 31 个 orphan。
8. 关闭旧 policy 会先关闭当前唯一真实上传链，违反分段顺序和“不得形成已知中断窗口”。

结论：必须在任何生产 policy 变化之前停止；不允许用“先加 policy、以后再补 writer”的部分实施方式绕过硬停。

## 10. 未实施阶段与恢复

| 阶段 | 状态 | 说明 |
|---|---|---|
| B1C-A 只读 Preflight | 完成 | 代码、线上 bundle、bucket、对象、引用、policy、ACL、业务指纹均已核对 |
| B1C-B 新 policy 加法 | 未开始 | 硬停；没有 migration，没有 comment/policy 变化 |
| B1C-C V2 上传切换 | 未开始 | 当前不存在可切换的真实上传实现；没有代码/版本/Pages 变化 |
| B1C-D 旧路径封闭 | 未开始 | 所有 entry gate 未满足；旧 INSERT policy 原样保留 |
| B1C-E 最终实施验收 | 未开始 | 仅完成硬停零变化验收 |
| 恢复 | 未执行 | 没有生产变化，无需恢复 |

## 11. Storage 与业务零变化证据

最终成功的生产查询事务从 `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY` 开始，以显式 `ROLLBACK` 结束。前面的 catalog 试探分别因 `PUBLIC` 角色参数、历史表名和缺失 cron relation 失败；每次都在只读事务内并随断连自动回滚，没有 DDL/DML/RPC。

| 对象 | count | MD5 |
|---|---:|---|
| Storage objects | 57 | `ec6522f59532814af6bbfbb1a90e1822` |
| orphan subset | 30 | `3b17d8c87494da6404c213009132437e` |
| expense attachments | 23 | `a1b50c81c634121e83b65d31309eb062` |
| expenses | 47 | `34a7a32319d8e538ef7997e1ba59c9d4` |
| income | 55 | `c55f82c7d62dbe92d0b49714a911a234` |
| accounts | 3 | `ac9fa3e0b92dde16dddfffff2c70c222` |
| account transactions | 187 | `00516a76f236d51406c82f37b0e468ee` |
| lessons | 744 | `3cd0c2ce1b7baa60c779c257c38e9f50` |
| monthly settlements | 18 | `481ffa7ed5173da852f0f28ce66c2e9b` |
| tuition bills | 22 | `e50673ac998ee2d84573a076a64d3d42` |
| wage locks | 103 | `ea395407134045e7623e171b02d3d910` |
| Auth users | 1 | `cf95e51bf943eaea9e1284aa3b494754` |
| Gate rows | 3 | `b04952a0603194dd5592124bdee2f7d7` |

本轮没有 Cash 连接写入；由于没有任何生产写语句、Storage API 写调用或部署，且 School 侧财务/业务指纹来自同一只读快照，不能把任何业务变化归因于本轮。Gate、Auth、Edge、cron、Webhook、payment RPC 均未修改。

报告编写完成后又执行一次独立最小只读验收并显式 `ROLLBACK`：对象数/字节/对象指纹/路径指纹、`23/4/30` 分类及 orphan 指纹、23 条附件指纹、支出/收入/账户/流水/Gate 指纹与 Preflight 完全一致；4 个目标 policy 的组合指纹为 `52aa55fc0e750ea51058187417a302e1`。没有观察到本轮外并发 Storage 上传。

## 12. 风险重算与 Freeze gate

没有完成任何风险消减动作，沿用已验收基线：

| 级别 | 数量 | 本轮变化 |
|---|---:|---:|
| Blocker | 4 | 0 |
| High | 5 | 0 |
| Medium | 4 | 0 |
| Low | 2 | 0 |
| Unknown | 2 | 0 |

Storage Blocker 仍在：V1 旧页面在共享 authenticated active-admin session 下仍可向旧路径 INSERT，虽不能 UPDATE/DELETE；metadata INSERT 会失败，因此仍可能创建 orphan。共享 Supabase/Auth/公开客户端 key、旧 session、service worker/cache、最后活动边界、归档与可验证恢复路径等风险均未处理。Freeze entry gate 继续 `FAIL`；不得进入 Freeze。

## 13. 下一阶段所需独立授权

需要先批准一个独立的“V2 真实附件 Storage 业务合同”阶段，精确包含：

1. 修改或版本化 `school_create_expense_attachment_metadata`，使 DB 权威地签发/校验真实 `storage_bucket/storage_path`，并定义 upload 与 metadata 的失败恢复、幂等和 orphan/dangling 行处理；不得复用旧宽泛表 DML。
2. 修改 V2 attachment reader/UI，安全读取 `storage_bucket/storage_path`，通过 private bucket 的受控 download/signed URL 方式兼容历史旧路径与未来新路径；禁止把长期 public URL 作为私有对象权威。
3. 明确浏览器直传还是新增 Edge/signed-upload 合同；如需 Edge，单独授权 Edge、service-role 和 secret 边界。
4. 在 synthetic/隔离环境验证 active-admin-only、路径规范、`upsert=false`、响应丢失、metadata/upload 次序、重复提交、历史读取和负向角色矩阵。
5. 该合同生产上线并在不创建测试附件的条件下完成静态验收后，再单独重新授权 B1C 的“新 policy 加法 → V2 上线 → 旧 INSERT closure”。

P1-B2（session/service worker/cache）、P1-C（归档、恢复、最后活动、观察窗口）、Freeze、Soft shutdown、V1 停服仍须各自独立授权。

## 14. 调查命令、SQL 与证据索引

### 14.1 代码证据

- V1：`js/legacy-core.js:39-51,213-225,1180-1225,1835-1859,1916-1958`
- V2 API：`js/api/expense-detail-api.js:106-116,237-256,439-451`
- V2 page：`js/pages/expense-detail-page.js:699-721,968-1071`
- V2 writer：`sql/current/school_create_expense_attachment_metadata_rpc.sql:1-201`
- V2 权限收口：`sql/current/school_p0_expense_permission_phase2_closure_20260804.sql:200-310`
- CI：`.github/workflows/pages.yml`
- 既有证据：`docs/school-v1-decommission-preflight-p1a-online-evidence-20260809.md`

### 14.2 只读命令/SQL 类别

- Git：`status --short`、`rev-parse`、`rev-list --left-right --count`、`ls-remote`、`log --all`。
- 源码：`rg` 精确搜索 bucket、`.storage`、upload/update/remove/move/copy、signed URL/download、upsert、附件字段/RPC/Edge/CI schedule。
- 线上静态：公开 Pages JS 下载到 `/tmp` 后仅比较 SHA-256 和定向字符串；未输出客户端配置。
- 数据库：`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY`；bucket/object aggregate、path shape、owner/metadata/timestamps、引用分类与脱敏 MD5；`pg_policies`、ACL、RLS、role membership、`pg_proc` 反向引用、业务/Auth/Gate 指纹；`ROLLBACK`。

## 15. 最终问题逐项回答

1. **P1-B1C 是否完整成功：否。** 只读 B1C-A 完成；命中硬停，B1C-B～E 未实施。
2. **目标 bucket/旧路径：** `school-expense-files`；`expenses/YYYY-MM/<expense_uuid>/<timestamp>_<safe-name>.<ext>`。
3. **V2 新路径：** 未选定/未部署；报告只给出不具生产效力的候选空间。
4. **新旧路径是否严格不相交：** 未形成生产合同；候选顶层与 `expenses/` 可结构不相交，但不能宣称已完成。
5. **新 policy 允许哪些 role/操作：** 没有新 policy。现有旧 policy 仍只允许 authenticated active admin 按旧路径 INSERT。
6. **V2 线上 bundle 是否只生成新路径：** 否；V2 线上根本不生成物理 Storage 路径，只调用 metadata-only RPC。
7. **是否存在旧路径 fallback：** V2 无真实上传/fallback；V1 仍直接使用旧路径。
8. **旧路径 INSERT/UPDATE/DELETE 是否全部封闭：** 否；UPDATE/DELETE 已为 false，INSERT 仍开放给 active admin。
9. **V1 旧页面能否继续上传：** 能，在继承共享 active-admin session 且 expense/月/类型符合 policy 时仍可 INSERT object；附件行写入会失败。
10. **57 个对象是否全部保留：** 是，57 个、6,936,405 bytes。
11. **30 个 orphan 是否全部保留：** 是，指纹已记录。
12. **是否上传/更新/移动/复制/删除对象：** 否，均为 0。
13. **业务数据是否零变化：** 是，本轮写语句/业务 writer 调用为 0，关键 School 指纹已记录。
14. **Gate/Auth/Edge/cron/Webhook/payment RPC 是否零变化：** 是。
15. **历史附件读取是否正常：** 没有执行真实文件读取；V2 仅正常读取 23 条 metadata 摘要，不能把它表述为物理文件预览/下载已验收。
16. **是否执行恢复：** 否；没有生产变更。
17. **风险数量变化：** `4/5/4/2/2`，各级均无变化。
18. **Freeze entry gate：** `FAIL`。
19. **P1-B2/P1-C：** session/SW/cache 与归档/恢复/最后活动/观察窗口全部未处理。
20. **migration/报告/commit/Pages：** migration 0；本报告 1；commit/push/Pages run 0。
21. **最终 Git：** 报告落盘前两仓库 HEAD 与远端 main 一致、ahead/behind `0/0`；最终工作树见本任务交付说明，既有用户文件全部保留。

本轮到此停止。不得继续执行 B1C-B、P1-B2、P1-C、Freeze、Soft shutdown、V1 停服、共享 Supabase 关闭或客户端 key 轮换。

## 16. 2026-08-10 后续业务决策（P1-B1C-R）

以上 B1C-A 硬停结论保持原样，未被改写。其后业务负责人明确决定：V2 不再提供支出附件上传，未来 V3 也计划取消该功能；因此不再实施本报告原拟的“新 Storage 合同加法 → V2 切换 → 旧路径封闭”。后续独立授权 `P1-B1C-R：Expense Attachment Write Retirement` 改为直接退役 V1/V2 全部附件新增写入能力，同时完整保留 57 个既有对象、30 个 orphan 候选和全部历史 metadata，交由 P1-C 归档与恢复准备。

P1-B1C-R 的实际实施、权限矩阵、零变化证据和恢复定义见：

- `docs/school-v1-decommission-p1-b1c-attachment-write-retirement-20260810.md`
- `sql/current/school_p1_b1c_r_attachment_write_retirement_20260810.sql`
- `sql/current/school_p1_b1c_r_attachment_write_retirement_restore_definition_20260810.sql`
