# School V2 普通支出权限面 P0 第二阶段封口实施报告

日期：2026-08-04
结论：普通支出相关生产写面已完成本阶段闭包封口，满足进入“Cash 端新增支出”独立设计/实现阶段的安全前提；本轮未实现该功能。

## 1. 实时基线

- 分支：`main`
- 开始时 HEAD / `origin/main`：`b62e30821e1a142dfbcdafecaaf58f336d14feef`
- 开始时 ahead / behind：`0 / 0`
- 开始时生产页面：`v10.5.2`
- 开始时 Pages run：`30878098230`，成功
- 相关 Edge 基线：`request-cash-expense-confirmation` v4；`request-cash-confirmation` v8；`sync-cash-result` v8；`request-cash-income` v11；`request-cash-part-time-work-confirmation` v2；学费 void Edge v5
- 本轮没有修改或部署 Edge。

## 2. Business-model expansion declaration

- 新表、业务列、状态、金额/月份/锁定/工资/Cash 事实：`none`
- 唯一变更语义：`school_update_expense_record` 新增显式 `p_expected_updated_at timestamptz`，以数据库 `updated_at` 作为更新前期望版本；缺失或陈旧版本分别 fail-closed，防止 lost update。该项对应本任务对 expected version、并发安全和不得 lost update 的逐项批准。
- writer authority：按本任务明确批准，将交互式 writer 收口为 active admin、后台 Cash helper 收口为 service_role、历史无合法调用方入口改为 owner-only。
- attachment：沿用现有 metadata-only 合同；目标支出加行锁，完全相同 metadata 重复提交明确拒绝，不新增存储业务事实。
- 兼容 fallback、双写、历史回填、历史语义重解释：`none`。

## 3. 最终身份与 ACL

### 五个点名交互式 writer

以下当前签名均为 `SECURITY DEFINER`、`search_path=pg_catalog, public`、PUBLIC/anon/service_role 无 EXECUTE、authenticated 有 EXECUTE且函数首段调用 `school_require_current_app_admin()`：

- `school_update_expense_record(uuid,timestamptz,date,uuid,uuid,text,text,text,numeric,numeric,text,text,text,text,text)`
- `school_reverse_expense_record(uuid,date,text)`
- `school_create_reimbursement_record(date,uuid,uuid,uuid,uuid[],text)`
- `school_reverse_reimbursement_record(uuid,date,text)`
- `school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)`

旧 update overload 已设安全 search_path，PUBLIC/anon/authenticated/service_role 全部不可执行。更新 writer 对目标行 `FOR UPDATE` 并校验期望 `updated_at`；reverse、报销 create/reverse、附件重复均由数据库锁和既有状态守卫保证单次效果。

### 老师工资及支付 writer

- 19 个交互式签名统一为 authenticated 入口 + DB active-admin 断言，anon/service_role 拒绝；覆盖工资生成两个 overload、工资明细调整、工资支出创建/作废、工资锁作废、工资规则 create/update/active-state、支付确认/撤销/cancel/restore/reissue。
- `school_void_teacher_wage_lock_admin_impl_20260804` 为 owner-only 私有实现；公开 wrapper 记录 DB 当前 admin actor，不信任客户端操作人。
- 14 个旧 personal-Cash、旧工资支付、旧 overload 与一次性修复入口均 owner-only。
- 4 个普通支出 Cash 后台 helper 仅 service_role：prepare、submitted、confirmed、rejected；PUBLIC/anon/authenticated 均无 EXECUTE。
- 工资金额、月份、snapshot、锁定、作废、Cash identity 和既有 17 条链未改变。

### 角色矩阵

| 身份 | 交互式 writer | 4 个 Cash helper | 表级写入 |
|---|---:|---:|---:|
| PUBLIC / anon | 拒绝 | 拒绝 | 拒绝 |
| authenticated 无 membership | DB 首段拒绝 | ACL 拒绝 | 拒绝 |
| inactive admin | DB 首段拒绝 | ACL 拒绝 | 拒绝 |
| operator | DB 首段拒绝 | ACL 拒绝 | 拒绝 |
| read_only | DB 首段拒绝 | ACL 拒绝 | 拒绝 |
| active admin | 允许，继续受业务状态守卫 | ACL 拒绝 | 拒绝 |
| service_role | ACL 拒绝 | 允许，继续受 identity/状态/幂等守卫 | 拒绝 |

## 4. Storage 与附件

- bucket `school-expense-files` 已由 public 改为 private。
- anon 无 SELECT/INSERT/UPDATE/DELETE；authenticated 上传必须是 active admin、符合 `expenses/YYYY-MM/<expense UUID>/<filename>` 前缀、月份一致且目标为真实非工资支出。
- UPDATE/DELETE policy 固定拒绝，不能覆盖或删除既有对象。
- metadata writer 不接受 bucket、外部 URL 或客户端 storage path，仅生成受控 `metadata-only/...` 证据；目标支出锁定，完全重复 metadata 返回稳定拒绝。
- 页面/API 当前没有 Storage 上传链，生产已有 57 个对象，其中 30 个是部署前历史 orphan；本轮未删除、改写或新增 Storage 对象。由于任务禁止破坏性清理，这 30 个历史对象作为已封写的历史遗留单列，不计为本轮 fixture residue。

## 5. 写面闭包结果

- 19 个交互式 writer：PUBLIC/anon/service_role 旁路为 0；authenticated 无 active-admin guard 为 0。
- 4 个后台 helper：authenticated 旁路为 0；service_role 只经受控 RPC。
- 14 个旧 overload/legacy writer：非 owner EXECUTE 为 0。
- 15 张范围内表：anon/authenticated/service_role INSERT/UPDATE/DELETE 均为 0。
- writable view、旧 overload、动态 SQL、隐式不安全解析、触发器等价写旁路：0。
- page-layer 直接 `.rpc()` / DML：0；浏览器 service-role marker：0。
- Storage anon/非 admin 写旁路：0。
- `public` schema 的 postgres default ACL 不再把未来函数/表自动授予 PUBLIC/anon/authenticated。
- `school_set_updated_at()` 仍可被解析为 trigger function，但目标表 DML 已封闭，不能形成客户端写入口。

## 6. 实现文件

- 页面/API：`js/api/expense-detail-api.js`、`js/pages/expense-detail-page.js` 传递 DB `updated_at` 期望版本；`js/config.js` 升至 `v10.5.3`。
- SQL：五个点名 writer、工资生成/支出/工资锁/工资规则/支付状态等现行定义同步安全合同。
- 部署集：
  - `school_p0_expense_permission_phase2_deploy_20260804.sql`
  - `school_p0_expense_permission_phase2_closure_20260804.sql`
  - `school_p0_expense_permission_phase2_amendment_20260804.sql`
- 验收集：
  - `school_p0_expense_permission_phase2_rollback_tests_20260804.sql`
  - `school_p0_expense_permission_phase2_postdeploy_20260804.sql`
  - `cash_p0_expense_permission_phase2_postdeploy_20260804.sql`
  - `scripts/p0-expense-permission-phase2-static-test.mjs`
  - 更新上一阶段 rollback test，使 service_role 不再直接 UPDATE 表，只经 helper 完成回调测试。

## 7. 执行、测试与数据不变量

### 已执行 School SQL

- `school_p0_expense_permission_phase2_deploy_20260804.sql`：已提交函数定义、ACL、RLS 与 Storage policy/config。
- `school_p0_expense_permission_phase2_amendment_20260804.sql`：已提交旧 overload search_path 与剩余 service_role 表 DML 封口。
- `school_p0_expense_permission_phase2_rollback_tests_20260804.sql`：通过并 ROLLBACK。
- `school_p0_expense_permission_closure_rollback_tests_20260804.sql`：修正旧 fixture 后通过并 ROLLBACK。
- `school_p0_expense_permission_phase2_postdeploy_20260804.sql`：只读通过。

### 已执行 Cash SQL

- `cash_p0_expense_permission_phase2_postdeploy_20260804.sql`：只读通过；Cash DDL/DML 均为 0。

### 验收结果

- 19 个交互式签名：anon、service_role、无 membership、inactive admin、operator、read_only 全部拒绝；active admin 可进入业务校验。
- 回滚成功路径覆盖：expense update + stale token、expense reverse + duplicate、reimbursement create/reverse + duplicate、attachment create + duplicate、wage expense create/void、wage lock void；所有业务、余额、流水变化随事务回滚。
- 后台 helper 覆盖 prepare 幂等、submitted、confirmed 幂等、rejected，以及非法状态、错误 request/transaction identity 拒绝。
- 双会话：会话 A 对生产支出 `35c5cf65-cd94-4462-82de-f0342e4f1784` 只持有 `FOR UPDATE` 行锁；会话 B 的 `NOWAIT` 按预期得到 55P03；A 随后 ROLLBACK。未调用 writer，记录未改变。
- 页面只读：生产 Chrome 认证后 `2026-08` 显示 1 条，与 DB 月份计数一致；未点击任何写按钮。
- 静态检查、JS syntax、`git diff --check` 均通过。

### 指纹与 Gate

- School 46 条支出：`1a55bca9448e7549399f0a4abca99ac8`
- School 17 条工资 Cash 支出链：`8547abed7ae4565ca4d40c4df2c82e5c`
- School 3 个账户：`b75d680c238566896e28874f73f25582`
- School 186 条账户流水：`63963e4e15acfda30a036698f09dc795`
- Cash 17 个工资支出请求：`9fa87228ee67676af1a13cdb7acdcf7f`
- Cash CNY/JPY expense transaction 指纹：`912c514fe973023f567036e1e8c36df2` / `654485db35df0657c0bf7121d464baa3`
- Gate 保持：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=enabled`。
- 本轮真实支出、报销、工资、附件、Cash request/transaction 写入：0。
- School 持久写入仅限函数定义、ACL、RLS 与 Storage bucket/policy 配置；Cash 持久写入：0。
- rollback fixture 与 Storage 新对象 residue：0。

## 8. 流程偏差与处置

原计划先用同一部署文件进行 ROLLBACK rehearsal，但替换末尾 `commit;` 的命令未命中，第二次执行实际提交了已批准范围内的权限 SQL，因此部署发生在 Git commit/push 之前。首次失败事务由 PostgreSQL 自动回滚，第二次提交未写业务行；发现后未 reset/回退合法封口，而是立即披露、完成只读 inventory、补充 amendment、两套 rollback、双库 postdeploy 与闭包复扫。该偏差不改变数据库业务事实，但应在后续流程中避免依赖文本替换控制 commit/rollback。

## 9. 最终判断

本任务范围内已无 PUBLIC、anon、普通 authenticated、service_role 借用交互式 writer、表级 DML、旧 overload、Storage 或页面层等价写旁路。历史支出、工资 Cash 链、账户、流水和 Gate 均保持不变。

**Go：普通支出权限面已经完整封口，可以进入“Cash 端新增支出”下一轮独立业务模型声明、设计与实现；本轮未创建 pending-expense writer，也未恢复 Cash UI。**
