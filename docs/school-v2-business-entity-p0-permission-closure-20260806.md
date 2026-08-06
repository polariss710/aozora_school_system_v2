# School V2 Phase BE-P0：业务归属主表与 Profile RPC 权限封口报告

日期：2026-08-06

## 1. 实时开始与实施检查点

| 项目 | 开始 | 实施检查点 |
|---|---|---|
| 分支 | `main` | `main` |
| HEAD / origin/main | `beb04dd6d684fbcc985b381d343e3391c6e18fc9` | `d16e72a529fd9244f029576cf5248b1cd563266a` |
| ahead / behind | `0 / 0` | `0 / 0` |
| Pages | run `31070395698`，success | run `31080264684`，success |
| 页面版本 | `v10.5.11` | `v10.5.11` |
| Tuition Gate | preview=`enabled` / generate=`blocked` / cash_submit=`enabled` | 完全相同 |

开始工作区除第2节六份受保护 untracked 外干净；实时 fetch 后 HEAD 与 origin/main 一致。没有修改页面版本，因为本阶段只有 SQL 权限定义、测试和文档，没有页面发布规则要求版本递增。

## 2. 六份受保护文件开始指纹

| 文件 | 大小 | SHA-256 |
|---|---:|---|
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | 61,681 | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | 4,483 | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | 15,861 | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | 10,345 | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | 15,089 | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | 27,370 | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 3. 修复前风险

- `school_business_entities` owner=`postgres`、RLS enabled，但 ACL 为 postgres/anon/authenticated/service_role 全部 `arwdDxtm`。
- 唯一 policy `school_allow_all_business_entities` 为 `FOR ALL TO public USING(true) WITH CHECK(true)`。
- create/update 各有2个 overload，共4个 `SECURITY DEFINER` 函数；全部 owner=`postgres`、`search_path=public`，PUBLIC/anon/authenticated/service_role 均可 EXECUTE，函数体没有 DB active-admin 断言。
- 浏览器正常路径虽走 API/RPC，但攻击者可绕过页面直接表 DML 或直接调用任意 overload。
- 静态与生产函数盘点未发现其他 delete/merge/archive writer；Edge/service-role 也没有主表或 Profile RPC 真实运行时依赖。

## 4. 实际修改文件

- `sql/current/school_create_business_entity_profile_rpc.sql`
- `sql/current/school_update_business_entity_profile_rpc.sql`
- `sql/current/school_business_entity_p0_permission_closure_core_20260806.sql`
- `sql/current/school_business_entity_p0_permission_closure_deploy_20260806.sql`
- `sql/current/school_business_entity_p0_permission_closure_postdeploy_20260806.sql`
- `sql/tests/school_business_entity_p0_permission_closure_rollback_test_20260806.sql`
- `scripts/business-entity-p0-permission-static-test.mjs`
- 本报告与 `docs/current-status.md`

页面、API、`js/config.js`、`js/legacy-core.js`、Edge、Gate、signup、Cash 和 Storage 文件均未修改。

## 5. Migration 与函数改动

业务模型扩展声明：新表、列、状态、月份、身份、来源、快照、可写业务事实、历史解释、fallback/dual-write、破坏性 schema 均为 `none`。唯一 authority 变更由本任务明确批准：主表直接写关闭；SELECT 限 active membership；Profile writer 限 active admin。

核心 SQL 可重复执行并带 fail-closed preflight：

- 重定义4个既有 overload，不增删签名或返回列；
- 每个函数在任何业务读取/写入前执行 `public.school_require_current_app_admin()`；
- 保留 `SECURITY DEFINER` 与 postgres owner，固定 `search_path=pg_catalog, public`；
- 表/helper 均显式 schema 限定，随机 UUID 固定为 `pg_catalog.gen_random_uuid()`；
- JSONB canonical overload 仅授予 authenticated EXECUTE；两个旧文本 overload owner-only；
- 删除 allow-all policy，建立唯一 authenticated SELECT-only policy；
- 撤销 PUBLIC/anon/authenticated/service_role 全部表权限，仅恢复 authenticated SELECT；service_role 无已证明依赖，因此不保留主表权限。

没有 trigger、约束、列或主数据变更。

## 6. 最终表级权限矩阵

| 调用者 | SELECT | INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER |
|---|---|---|
| PUBLIC | 拒绝 | 全部拒绝 |
| anon | 拒绝 | 全部拒绝 |
| authenticated | 仅经RLS的active admin/operator/read_only | 全部拒绝 |
| service_role | 拒绝 | 全部拒绝 |
| postgres owner | owner能力 | owner能力 |

生产 `relacl` 精确为 `{postgres=arwdDxtm/postgres,authenticated=r/postgres}`。浏览器不能直接修改主表；RLS中也没有任何 INSERT/UPDATE/DELETE policy。

## 7. 最终 RPC EXECUTE 与 membership 矩阵

| 调用者 | JSONB create/update | 两个旧文本 overload | 结果 |
|---|---|---|---|
| PUBLIC | 无 EXECUTE | 无 EXECUTE | 拒绝 |
| anon | 无 EXECUTE | 无 EXECUTE | 拒绝 |
| authenticated 无membership | 可进入JSONB签名 | 无 EXECUTE | helper首段拒绝 |
| inactive admin | 可进入JSONB签名 | 无 EXECUTE | helper首段拒绝 |
| active operator | 可进入JSONB签名 | 无 EXECUTE | helper首段拒绝 |
| active read_only | 可进入JSONB签名 | 无 EXECUTE | helper首段拒绝 |
| active admin | 可进入且允许 | 无 EXECUTE | 正常合法路径保留 |
| service_role | 无 EXECUTE | 无 EXECUTE | 拒绝 |

旧 overload 虽为 owner-only，函数体仍包含相同 active-admin guard，不存在遗漏签名。

## 8. 最终 RLS policy

唯一 policy：

- name=`school_business_entities_active_membership_select`
- `PERMISSIVE FOR SELECT TO authenticated`
- `USING EXISTS (school_get_current_app_membership())`
- membership 必须 `is_active=true` 且 role 属于 `admin/operator/read_only`
- `WITH CHECK=NULL`

旧 `school_allow_all_business_entities` 已不存在；无普通角色写 policy。

## 9. SECURITY DEFINER、owner、search_path 证明

| 签名 | owner | SECURITY DEFINER | search_path | DB定义MD5 |
|---|---|---:|---|---|
| create `(jsonb)` | postgres | true | `pg_catalog, public` | `d7000540d0a6ff9d679953b8223bf812` |
| create `(text,text,text,text,boolean,text)` | postgres | true | `pg_catalog, public` | `c3bceecbec0b8e239187ac3651152613` |
| update `(uuid,jsonb)` | postgres | true | `pg_catalog, public` | `1c8d61c700c7502f381a5add5ebc14d7` |
| update `(uuid,text,text,text,boolean,text)` | postgres | true | `pg_catalog, public` | `7536062577b4c1715ec86b6cae8c60ca` |

四个定义中 admin guard 位置分别为845/966/850/845，首次 business-entity 表读取位置分别为1272/1655/1356/1547，证明权限断言先于业务读取；本地非法空 payload 负向测试也稳定先返回 `P0G1_ACTIVE_ADMIN_REQUIRED`。

## 10. 本地/隔离测试

- 安装并启动仅监听临时 Unix socket 的 PostgreSQL 17 fixture，测试结束后停止并删除临时集群。
- `school_business_entity_p0_permission_closure_rollback_test_20260806.sql`：PASS，最终整体 ROLLBACK。
- 覆盖 PUBLIC、anon、无membership、inactive admin、operator、read_only、active admin、service_role。
- active-admin create/update 正向仅发生在本地 rollback fixture；生产未调用 writer。
- 直接 INSERT/UPDATE/DELETE/TRUNCATE ACL拒绝；临时恢复DML grant后，RLS无写policy仍拒绝INSERT，证明双层阻断。
- 所有 overload、PUBLIC默认EXECUTE、fixed search_path、guard顺序、拒绝无部分写入均通过。
- 本地固定测试 actor：`be000000-0000-4000-8000-000000000001`至`...0005`；全部随事务回滚，无持久测试记录。
- `business-entity-p0-permission-static-test.mjs`：PASS；`node --check`、`git diff --check`、page-layer边界、browser service-role、`js/legacy-core.js`和受保护文件范围均通过。

## 11. 生产部署步骤与结果

执行顺序：

1. `git fetch --prune origin`，确认 `beb04dd...` 与 origin/main、ahead/behind 0/0；
2. 生产 `REPEATABLE READ READ ONLY` before snapshot；
3. 同一 deploy wrapper 以 `p0_be_permission_commit=0` 演练，成功 ROLLBACK；
4. 只读确认演练后旧ACL/policy和主数据指纹完全恢复；
5. core SHA-256 `cc13db34b7c945fea91ba0e02d1ea5c92ea58946fe87dd561a8000f11efa32ec`、deploy SHA-256 `fb5f3fb491a757de1686bd443a2512d2a97bdffeb096b85312f869f90cc353cb`；
6. 同一 wrapper 以 `p0_be_permission_commit=1` 正式 COMMIT；
7. 运行只读 postdeploy、权限矩阵、完整 after snapshot。

正式持久变更只包括4个函数定义/comment、表ACL和RLS policy。生产业务DML=0。

## 12. 生产 catalog postdeploy

`BE_P0_PERMISSION_CLOSURE_POSTDEPLOY_PASS`：

- owner/RLS/relacl正确；
- allow-all消失且唯一SELECT policy精确；
- PUBLIC/anon/authenticated/service_role写权限全false；
- service_role SELECT false；authenticated SELECT true；
- 4/4 overload owner、SECURITY DEFINER、search_path、guard、ACL正确；
- PUBLIC默认EXECUTE不存在；
- JSONB canonical仅authenticated，旧overload owner-only；
- 无其他 delete/merge/archive mutator；
- 两行主数据、10组引用、两条异常链、Gate均通过硬编码只读指纹守卫。

生产没有通过实际负向写请求测试权限，只使用 catalog 证明。

## 13. Chrome 只读验收

使用现有合法 active-admin Chrome 会话，未填写/保存任何表单：

- `business-entity.html`：加载成功，2条实体仍为启用，版本 `v10.5.11`；
- `account.html`：加载成功，筛选仍显示个人名义/青空进学塾；
- `lesson.html?year=2026&month=05&view=pair`：加载成功，业务归属名称正常；
- `wage.html?year=2026&month=05`：加载成功，个人名义41、青空进学塾25个可见归属单元；
- 网络只见 Auth user GET、`school_get_current_app_membership` reader RPC、`school_business_entities` GET；publishable key + user JWT，无service-role、无直接表DML、无Profile writer。

临时验收标签页已关闭，用户原有标签页未改动。

## 14. 两条主数据 before/after

聚合：count=`2`，完整行 MD5=`3bc3425c4bd152bafe7a528a2762d33e`，before/after一致。

- `2cf7b72f-6e3c-4d09-80f7-7c58593cd466`：`aosora / 青空进学塾 / company / JPY / company_report=true / active=true`，创建/更新时间均未变。
- `886a8f7c-0fea-45ac-97d2-15c976ede996`：`personal / 个人名义 / personal / CNY / company_report=false / active=true`，创建/更新时间均未变。

未新增第三条实体，trigger没有顺带更新 `updated_at`。

## 15. 关键历史引用 before/after

| 对象 | 青空 | 个人 | 结果 |
|---|---:|---:|---|
| lesson | 597 | 142 | 不变 |
| settlement | 7 | 11 | 不变 |
| tuition bill | 20 | 2 | 不变 |
| tuition bill lesson | 288 | 42 | 不变 |
| wage lock | 18 | 77 | 不变 |
| wage detail | 93 | 463 | 不变 |
| income | 26 | 29 | 不变 |
| expense | 38 | 9 | 不变 |
| payment request | 8 | 43 | 不变 |
| personal Cash income linkage event | 12 | 30 | 不变 |

## 16. 两条历史学费异常链

账单 `2a9f1c25-a060-461e-ae10-b02295dec381` 与 `fdf3cdfe-f715-4814-b500-9ff2bfe77a63` 的 bill/income/generation identity/active revision/linkage event 关键字段聚合 MD5 before/after 均为 `56745a8c13e441169d5c739dd250e18d`。

本阶段没有修复、重开、void/reissue、改identity/income/Cash或调用任何关联writer。

## 17. Signup 与 Gate

- Auth settings before/after：`disable_signup=true`；signup继续关闭。
- `student_tuition_preview=enabled`
- `student_tuition_generate=blocked`
- `student_tuition_cash_submit=enabled`

三个 Gate 的 `updated_at` 也完全不变。

## 18. Commit、push 与 Pages

- 实现提交：`d16e72a529fd9244f029576cf5248b1cd563266a`（`security: close business entity profile permissions`）。
- 已 push 到 `origin/main`。
- Pages run `31080264684`：success，head=`d16e72a...`。
- 页面代码未变，版本保持 `v10.5.11`。

## 19. 受保护文件最终证明

六份文件的最终路径、大小和 SHA-256 与第2节逐项相同；未修改、移动、删除、格式化、暂存或提交，未进入任何 Git diff。

## 20. 工作区与零写入结论

实现提交后 HEAD/origin/main=`d16e72a...`、ahead/behind=`0/0`；工作区只有六份既有受保护 untracked。正式报告提交后将只新增本报告和更新 `docs/current-status.md`。

- 生产DDL：仅本权限修复所需4函数定义/comment、表ACL、RLS policy。
- 生产业务DML：0。
- business entity行修改：0；Profile writer生产调用：0。
- 学生/老师/课时、工资、学费/月结/收入/支出、School账户/Cash/claim、Storage修改：全部0。
- Gate变化：0；signup变化：0；六份受保护文件变化：0。
- 白名单生产写测试：无；生产测试记录ID：不适用。

BE-P0 工作流完成，没有遗留权限旁路或测试残留。

## 21. 下一阶段“全页面移除业务归属 UI”边界

后续应作为独立授权阶段：逐页移除筛选、候选、表单字段、列表列和详情展示，同时保持底层历史技术实体及冻结事实不变。不得删除/停用/改名/合并 `personal`，不得改写工资、月结、账单、收入、支出、支付、Cash或两条异常学费链；不得用前端默认值重新表达业务事实。开始前应重新盘点所有 reader/API/PDF/export 路径，并明确历史技术字段在无UI情况下的诊断和审计读取方式。
