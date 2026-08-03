# School V2 P0-G1-A Auth、Membership 与全局 Session Guard 验收报告

日期：2026-08-04

生产版本：`v10.5.0`

School Supabase 项目：`xlcdqvlfzspcxdoidsrr`

发布提交：`559216e`、`743b0d6`、`f658898`、`24232d7`

## 1. 结论

P0-G1-A 已完成并发布。School Supabase Auth 是 V2 唯一 canonical Auth；当前访问权只由 `auth.uid()` 对应的 `public.school_app_memberships` 行决定，email 不参与授权。业务负责人确认的唯一初始账号已精确 bootstrap 为 active admin，生产邮箱仅记录为 `po***@gmail.com`。

31 个 V2 业务 HTML 入口已全部 fail-closed 接入全局 session guard。生产 Chrome 已验证密码登录、服务端 user 校验、active admin membership、原页面返回、刷新恢复、页面导航、恶意外部 return URL 拒绝、单标签退出、多标签退出同步和重新登录。生产 Console error/warning 为 0。

本阶段没有恢复 P0-G1-B 财务 writer。Generate 与 Cash Gate 继续 blocked；三名指定学生和 Cash 均无新增业务写入。底层既有部分 anon reader 暂留到 P0-G2，因此本阶段是页面访问收口，不宣称已经完成全部数据可见性收口。

## 2. Business-model expansion declaration

```text
New tables: public.school_app_memberships，按本任务批准的 exact 8-column contract 保存当前应用 membership。
New columns: user_id uuid PK/FK auth.users ON DELETE RESTRICT；role text NOT NULL CHECK admin/operator/read_only；is_active boolean NOT NULL default false；created_at/updated_at timestamptz NOT NULL default now()；created_by_user_id/updated_by_user_id uuid NOT NULL FK auth.users ON DELETE RESTRICT；note text NULL。
New enum/status values: role 的 admin/operator/read_only 三个获批值；未新增 PostgreSQL enum。
New date/month/attribution concepts: created_at/updated_at 仅为 membership 维护审计时间；不改变业务日期、月份或归属。
New identity concepts: membership 唯一身份为 user_id=auth.uid()；email 永不参与授权。
New source concepts: none。
New snapshot/version concepts: none。
New writable facts: role、is_active、note 及 actor/timestamp 审计事实；仅 owner 或受控 admin wrapper 可维护。
Changed existing-field semantics: none。
Changed field mutability: updated_at 只由受控 DB 写路径更新，浏览器不能传入或决定。
Changed writer or reader authority: membership 表 DML 仅 owner；当前用户最小读取仅经 school_get_current_app_membership()；后续维护仅经 school_admin_set_app_membership() 并记录 auth.uid() actor。
Changed locking rules: none；admin wrapper 使用表锁并禁止停用最后一个 active admin。
New authoritative sources: public.school_app_memberships 中 user_id=auth.uid() 的唯一当前行是应用角色和 active 状态 sole authority。
Legacy fallbacks or dual-read rules: none；不按 email、第一个用户或历史状态 fallback。
Dual-write behavior: none。
Historical reinterpretation: none。
Destructive schema changes: none。

Approval reference: 业务负责人在本任务中逐字段批准 public.school_app_memberships 完整合同、sole authority、owner-only DML、三角色权限、精确 Auth UUID bootstrap、actor/note、无 fallback/双写、RLS/ACL 和 DB-authoritative updated_at；随后确认脱敏邮箱匹配并明确批准 bootstrap 与继续 P0-G1-A。
```

## 3. 数据库实施

已执行 School SQL：

- `sql/current/school_p0_g1_a_membership_schema_20260804.sql`
- `sql/current/school_p0_g1_a_membership_schema_postdeploy_20260804.sql`
- `sql/current/school_p0_g1_a_membership_rpcs_20260804.sql`
- `sql/current/school_p0_g1_a_membership_rpc_rollback_tests_20260804.sql`
- `sql/current/school_p0_g1_a_membership_rpc_postdeploy_20260804.sql`
- `sql/current/school_p0_g1_a_initial_admin_bootstrap_20260804.sql`
- `sql/current/school_p0_g1_a_initial_admin_postdeploy_20260804.sql`

新增函数：

- `school_get_current_app_membership()`：authenticated 可执行，只返回 `auth.uid()` 当前最小 membership；anon、service_role、PUBLIC 均无 EXECUTE。
- `school_require_current_app_admin()`：owner-only authority helper；要求 membership 存在、active 且 role=admin。
- `school_admin_set_app_membership(uuid,text,boolean,text)`：authenticated 入口，但函数内部重新验证当前 JWT admin；actor 固定为 `auth.uid()`，`updated_at=now()`，禁止停用最后一个 active admin。

三个函数均为 `SECURITY DEFINER`，固定 `search_path=pg_catalog, public`。membership 表启用 RLS，实际 ACL 仅 owner；PUBLIC、anon、authenticated、service_role 对 SELECT/INSERT/UPDATE/DELETE 全部为 false。初始 bootstrap 后总行数为 1，actor 两列均等于同一获批 admin UUID，note 明确记录业务负责人授权的 initial bootstrap。

rollback 测试使用固定 `a010…0001` 至 `a010…0005` synthetic Auth UUID，覆盖无 membership、inactive、read_only、operator、active admin、受控维护和最后 admin 保护，事务最终 ROLLBACK；Auth fixture residue 为 0。生产 bootstrap 是本阶段唯一持久 membership 数据写入。

## 4. 前端与鉴权链

```text
浏览器 School session
  -> Supabase Auth 自动恢复/refresh
  -> auth.getUser() 服务端验证当前 token
  -> authenticated RPC school_get_current_app_membership()
  -> DB 仅按 auth.uid() 查询当前 membership
  -> active + 合法 role 才解除 auth-pending 并初始化页面
```

实现要点：

- `login.html` 仅提供 email/password 登录与退出，不提供 signup。
- return URL 必须同源且位于当前 V2 base path；外部 URL、登录页循环和越界路径回退到 `index.html`。
- 所有 31 个业务入口在 HTML 初始即带 `auth-pending`，guard 成功后才初始化页面，避免业务数据和按钮闪现。
- session refresh/失效和 SIGNED_OUT 均 fail-closed 返回登录页；退出使用当前应用 session，不清理无关站点 storage。
- 所有页面复用单一 canonical Supabase client；浏览器无 multiple-client warning。
- 旧页面内登录面板在 global guard 生效后隐藏，旧 helper 也改为消费统一模块化 auth API。
- 页面模块继续保持 `.rpc()` 0；membership RPC 只由 `js/api/auth-api.js` 调用。

## 5. 测试与生产验收

- 31/31 业务 HTML：guard class、CSS/entry cache-bust 和入口 await 全覆盖。
- 全部仓库 `scripts/*.mjs` 通过，共 20 份；新增 `p0-g1-a-auth-guard-static-test.mjs`。
- `node --check` 覆盖 auth、入口与关联模块；`git diff --check` 通过。
- page-layer `.rpc()` 扫描为 0；`js/legacy-core.js` 未修改；浏览器 bundle 未发现 service-role/JWT/secret marker。
- 本地匿名访问直接跳转登录页并保留内部 return；登录后返回原收入页。
- 本地刷新恢复 active admin；外部 return URL 被拒绝并回到站内首页；三个标签页退出同步。
- GitHub Pages run `30838090547` build/deploy 成功。
- 生产 Chrome：`v10.5.0`、active admin、旧登录面板隐藏、刷新恢复、收入页 12 行加载完成、Cash Gate 提示存在、Cash 批量按钮 disabled、页面导航成功、Console error/warning 0。
- 生产两个标签页退出同步后，业务负责人重新登录；原 `income.html?year=2026&month=08` return 精确恢复，active admin 与 Console 0 error/warning 再次通过。
- 生产 Auth settings 最终只读确认 `disable_signup=true`；页面无 signup 入口，验收未创建随机账号。

最终 Gate：

- `student_tuition_preview = enabled`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

P0-G1 实施和验收期间，学生、bill、income、lesson、settlement、adjustment、Cash 业务写入均为 0；未再次调用三名学生的 Reissue、Void、settlement 或 Cash writer。

## 6. 回滚方案

1. 前端紧急回滚使用新的 revert 提交撤销 `24232d7` 与 `f658898`，不 reset、不覆盖历史；推送 `main` 后由 Pages 重新部署。
2. 数据库对象保持 additive。常规回滚不 DROP membership 表，不删除 bootstrap 或审计事实。
3. 如需立即冻结 membership 维护入口，owner 执行 `REVOKE EXECUTE ON FUNCTION public.school_admin_set_app_membership(uuid,text,boolean,text) FROM authenticated`；owner helper 与表 ACL 不开放。
4. 如需冻结页面 membership reader，可另外 revoke `school_get_current_app_membership()` 的 authenticated EXECUTE，并同步先回滚前端，避免全站锁死。
5. Gate 始终保持 preview enabled、generate blocked、cash submit blocked；回滚不改学生、账单、settlement、Cash 或审计事实。
6. P0-G1-A 未部署 Cash DB/Edge 对象；Cash 侧无对象需要回滚，service-role 未进入 GitHub Pages。

## 7. 后续边界

P0-G1-B 才负责五类 admin 财务 writer wrapper、页面/API 接入以及 School/Cash 跨项目鉴权链。当前 operator/read_only 不构成关键财务 writer 授权，Generate/Cash 继续 blocked；不得仅凭前端 role 显示、service-role 浏览器调用或跨项目 user_id 参数恢复 writer。
