# School V2 普通支出 P0 权限封口与生产只读审计

日期：2026-08-04（Asia/Tokyo）

## 结论

- 本轮明确点名的旁路已在生产封口：`school_create_expense_record(...)` 仅 authenticated 可进入且函数内先执行 DB active-admin 权威断言；普通支出 Cash 四个准备/回写 writer 仅 service_role；`request-cash-expense-confirmation` Edge 使用真实 School JWT 和同 Bearer user-scoped admin 断言，并在 School/Cash 写边界前重验。
- 三张直接写入表已撤销 PUBLIC/anon/authenticated DML，authenticated 仅保留 SELECT；旧宽泛 RLS policy 已限定给 service_role，并新增 authenticated SELECT-only policy；postgres/public schema 默认 ACL 不再自动给 PUBLIC/anon/authenticated 表、sequence 或函数权限。
- 历史 School/Cash 数据未发现真实异常：17 条 Cash expense request 全部是老师工资链，15 approved、2 rejected；17/17 跨库 event/request/transaction/金额/币种/状态/来源与 Cash 账户资格完全一致，孤儿、重复、错配、长期 pending 均为 0。
- 没有历史“普通支出 Cash”成功样本；现有 17 条全部为 `teacher_wage`。因此不能用历史数据证明普通支出的报销状态、School/Cash 账户选择或 payment_method 语义。
- 整体普通支出权限面仍为 HARD STOP：另有五个 SECURITY DEFINER writer 允许 anon/authenticated 且无 active-admin guard，包含普通支出编辑、撤销及报销财务 writer。本轮授权逐对象清单没有批准这些 writer 的最终角色语义，不能擅自修改。已完成的 P0 封口不得回退，但在这些残余 writer 单独获批并封口前，不得进入“Cash 端新增支出”实现。

## 实时 Git 与部署基线

- 分支：`main`
- 开始时 HEAD / `origin/main`：`490674d62386b75c7f48102470f83ac2209e861c`
- 开始时 ahead/behind：`0/0`
- 开始时生产页面版本：`v10.5.2`（`js/config.js`）
- 开始时最新成功 Pages：run `30869451918`，HEAD `490674d62386b75c7f48102470f83ac2209e861c`
- P0 实现提交：`5a67e26055ce7b5f5be62c733c36022a0080fe1c`
- P0 推送后的 Pages：run `30875288279`，成功；页面代码和 `APP_VERSION` 未改变，仍为 `v10.5.2`
- Edge：`request-cash-expense-confirmation` version `4`，deployment id `df0124ab-e947-410e-90be-fd07dd1c6984`，`verify_jwt=true`，bundle SHA-256 `41d981f4f216d684c2a4aac443be1fa8b03c63faef2bde7905775b2d1b831c4b`

## Business-model expansion declaration

本轮生产实施声明如下；授权来源为当前任务“五、P0权限封口合同”与“D、表级ACL和RLS”。

- 新业务表：`none`
- 新业务列：`none`
- 新 status / enum：`none`
- 新 source / snapshot / version / date / month / attribution：`none`
- 历史数据解释或回填：`none`
- 权威与 writer 变更：
  - `public.school_create_expense_record(date,uuid,uuid,text,text,text,numeric,numeric,text,boolean,text,text,text,uuid,uuid,text)`：业务结果仍是 paid + School 余额扣减 + 一条 School 流水；唯一当前用户权限源为 `school_require_current_app_admin()`。
  - `school_request_cash_expense_payment_confirmation(...)`、`school_mark_cash_expense_request_submitted(...)`、`school_mark_cash_expense_confirmed(...)`、`school_mark_cash_expense_rejected(...)`：仅 service_role 可执行。
  - `school_expense_records`、`school_accounts`、`school_account_transactions`：浏览器角色只读，写入仅由受控 SECURITY DEFINER writer 完成。
  - postgres/public schema default privileges：不再为未来对象自动授予 PUBLIC/anon/authenticated。
- 锁定行为：`school_create_expense_record(...)` 使用以 DB 断言出的 active-admin UUID 为键的 transaction-scoped `pg_try_advisory_xact_lock`；同一管理员并发第二次调用立即以 `55P03 / SCHOOL_CREATE_EXPENSE_ALREADY_IN_PROGRESS` 拒绝，不新增持久化 identity。

## 根因与修复

根因是 SECURITY DEFINER writer 的 EXECUTE ACL 过宽、函数体没有 DB 身份/角色断言、search_path 未固定安全前缀；同时三张底表向 anon/authenticated 暴露 DML 且 RLS policy 为 public ALL。Edge 虽验证 JWT 用户存在，却没有 membership/active-admin 断言。

修复后角色矩阵：

| 入口 | PUBLIC/anon | authenticated 非 active admin | active admin | service_role |
|---|---:|---:|---:|---:|
| `school_create_expense_record` | 拒绝 | DB 拒绝 | 允许 | 拒绝 |
| 普通支出 Cash 四 writer 直调 | 拒绝 | 拒绝 | 直调仍拒绝 | 允许 |
| `request-cash-expense-confirmation` Edge | 401 | 403，任何 School/Cash 写入前 | 允许进入权限阶段 | 不进入浏览器 |
| 三张底表 SELECT | 拒绝 | 允许 | 允许 | 允许 |
| 三张底表 DML | 拒绝 | 拒绝 | 浏览器角色仍拒绝 | 仅受控服务/definer 路径 |

Edge 复用 P0-G1-B1 模式：先用 School service client `auth.getUser(bearerToken)` 验证真实 JWT，再用 `SUPABASE_ANON_KEY + 同一 Authorization Bearer` 创建 user-scoped School client，调用 `school_require_current_app_admin()`，并核对返回 actor UUID 等于已验证 user UUID。函数在初始阶段、School prepare writer 前、Cash request writer 前共检查三次；客户端 body 中没有 role/admin/user/membership 提权字段。

## 测试、部署与数据库写入

- 静态测试：`node scripts/p0-expense-permission-static-test.mjs` 通过；page-layer `.rpc()` 为 0，page-layer table DML 为 0，浏览器 service-role marker 为 0。
- 回滚矩阵：`school_p0_expense_permission_closure_rollback_tests_20260804.sql` 通过并整体 ROLLBACK。
  - fixture users：`e410...001` 至 `e410...005`
  - fixture account：`e410...0100`
  - fixture expenses：`e410...0201`、`e410...0202`，另有 DB 生成的 paid expense/transaction，仅存在于回滚事务
  - anon、无 membership、inactive admin、operator、read_only 全拒绝；active admin 成功产生一条 paid expense、余额 `100000 → 98766`、一条 `-1234` 流水；失败路径三对象不变。
  - Cash prepare 重试复用同 event / attempt 1 / idempotency；submitted 错误状态、不同 request、不同 transaction 均拒绝；confirmed 重放同 transaction 幂等。
  - 最终 School fixture expense/account/transaction residue 均为 0；Cash fixture residue 均为 0。
- 并发：生产两个只读会话；持锁会话不调用 writer，竞争会话以 NULL 业务参数调用时在参数校验/写入前得到 `SCHOOL_CREATE_EXPENSE_ALREADY_IN_PROGRESS`；两会话均回滚。
- 生产负向：anon 调普通创建、authenticated 调 Cash confirmed 均为数据库 `permission denied`；Edge 无 JWT 为 HTTP 401；active-admin DB 权限阶段在只读事务中通过。
- 正式执行的 School SQL：`school_p0_expense_permission_closure_deploy_20260804.sql`；其 include `school_p0_expense_permission_closure_core_20260804.sql` 与 `school_create_expense_record_rpc.sql`。生产持久写入仅为函数、ACL、RLS policy 与 default privileges 定义，无业务行写入。
- Edge 部署成功；没有调用 Cash create/approve/reject RPC，没有创建 Cash request/transaction。
- 未执行 whitelist commit expense test：当前任务明确禁止创建真实支出或 Cash request，使用全事务 rollback matrix 替代。
- 三项 Gate 始终为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`，变化为 0。

## 生产只读历史审计

执行文件：

- School：`school_p0_expense_historical_readonly_audit_20260804.sql`
- Cash：`cash_p0_expense_historical_readonly_audit_20260804.sql`

结果：

| 项目 | 结果 |
|---|---:|
| School 全部支出 | 46 |
| 普通支出 paid / 无 Cash link | 29 |
| 普通 pending / 可提交 Cash | 0 / 0 |
| 老师工资 Cash 链 | 17 |
| 老师工资 approved + School paid | 15 |
| 老师工资 rejected + School cancelled | 2 |
| Cash request pending / approved / rejected | 0 / 15 / 2 |
| School/Cash 逐条完整匹配 | 17/17 |
| School 账本孤儿 / Cash-linked 却有 School 流水 | 0 / 0 |
| Cash request 或 transaction 孤儿 | 0 |
| 重复 event / idempotency / request / transaction | 0 |
| 同一 School expense 多 Cash request | 0 |
| 同一 request 多 Cash transaction | 0 |
| approved 缺 transaction 或 School 未 paid | 0 |
| School paid 但 Cash 非 approved | 0 |
| rejected 却 paid/有 transaction/缺同步时间 | 0 |
| 金额、币种、账户、来源、状态跨库错配 | 0 |
| `pending_cash_request` >24h / >7d | 0 / 0 |
| teacher wage 缺 wage lock / snapshot mismatch | 0 / 0 |

业务主体跨库一致性只能部分证明：17 条 School expense 与各自 wage lock 的 `business_entity_id` 全一致，但 Cash request schema/payload 没有保存 School business entity，因此不能把“Cash business entity mismatch=0”作为已证明事实。

疑似匿名/非管理员历史创建的结论为“证据不足”，不是“没有发生”：46 条支出全部创建于本次封口前，`school_expense_records` 没有 `created_by`/JWT actor 字段，也没有对应通用 expense audit 表；数据库现有行无法还原调用角色。行结构、账本与 Cash 关联未发现异常，但不能据此证明历史调用身份正常。

## 新发现的残余 P0 writer

生产只读核验确认以下函数均由 postgres 持有、SECURITY DEFINER、`search_path=public`、无 `school_require_current_app_admin()`；前五个仍允许 anon/authenticated：

- `school_update_expense_record(...)`
- `school_reverse_expense_record(uuid,date,text)`
- `school_create_reimbursement_record(...)`
- `school_reverse_reimbursement_record(uuid,date,text)`
- `school_create_expense_attachment_metadata(...)`

另有老师工资专用 `school_create_teacher_wage_expense_record(...)` 与 `school_void_unsubmitted_teacher_wage_expense_record(...)` 已拒绝 anon、允许 authenticated，但没有按 membership 角色区分。老师工资历史链本轮验证完整；其 operator/admin 最终权限仍需业务负责人明确决定，不能因兼容而猜测。

这些对象的权限语义没有在本轮逐对象批准。下一步必须先由业务负责人分别确认：普通编辑、普通撤销、报销创建、报销撤销、附件写入、老师工资生成/作废分别允许 admin/operator/read_only 中哪些角色；然后独立完成 ACL、DB guard、安全 search_path、rollback matrix 和部署。完成前整体普通支出权限面不算完全封口。

## 下一轮“Cash 端新增支出”精确实施合同草案

以下仅为提案，不是本轮授权；Schema And Business Model Expansion Gate 要求业务负责人逐项确认后才可起草 SQL/代码。

### 建议新增对象与权威

1. 新列 `school_expense_records.cash_creation_event_id uuid`：历史行 nullable；新普通 Cash pending writer 必填；由客户端为一次“新增 Cash 支出”动作生成随机 UUID 并在重试中复用；插入后 immutable；partial UNIQUE `where cash_creation_event_id is not null`。它是 pending expense 创建幂等 identity，不替代后续 `cash_request_event_id`。
2. 新列 `school_expense_records.created_by_user_id uuid`：历史行保持 NULL，禁止回填；新普通 paid/Cash-pending writer 仅从 `school_require_current_app_admin()` 返回值写入，客户端不可提供；immutable。它是创建者审计事实，不参与金额、状态或读者优先级。
3. 新 writer：

```sql
public.school_create_pending_cash_expense_record(
  p_creation_event_id uuid,
  p_expense_date date,
  p_business_entity_id uuid,
  p_expense_category text,
  p_description text,
  p_currency text,
  p_amount numeric,
  p_exchange_rate numeric default null,
  p_is_business_expense boolean default true,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_reimbursement_status text,
  p_teacher_id uuid default null,
  p_student_id uuid default null,
  p_note text default null
)
```

客户端显式提供：creation event、日期、业务主体选择、ordinary 分类、描述、原始币种、原始金额、可选汇率、业务费用标记、税类、收据、报销状态、可选老师/学生、备注。`amount` 和显式报销状态属于用户输入，不由页面推算。

DB 权威生成/校验：active-admin actor、`created_by_user_id`、`app_type='school'`、`year_month`、normalized category/currency/text、`amount_jpy/amount_cny`、业务主体有效性、老师/学生有效性、`status='pending'`、`account_id=NULL`、`payment_method=NULL`、Cash link 全 NULL、attempt 0、timestamps。writer 拒绝 `teacher_wage`。创建事务必须断言：School account balance delta 0、School account transaction delta 0、Cash request delta 0。

同一 `p_creation_event_id` + 完全相同 normalized payload 重试返回原 expense，`idempotent=true`；同 identity 不同 payload 返回稳定冲突码。DB 以 creation event advisory lock 串行化，不允许页面在响应不确定时生成新 event 自动重试。

报销状态与 `payment_method=NULL` 是必须由业务负责人明确批准的语义：历史没有普通 Cash 样本，DB 也无法从 Cash 账户推导 School 报销状态，因此草案要求用户显式选择 `not_required|pending`，且 pending 阶段不伪造 School payment method。

### UI 与调用顺序

- 选择器：`支出方式`
  - 默认：`School账户直接支付（立即记为已支付并扣减School账户余额）`
  - 第二项：`Cash账户支付（先保存为待支付，再提交Cash审批；不会扣减School账户余额）`
- School 模式继续调用既有 `createExpenseRecord`，必须选择 School 账户；确认文案：`将立即创建已支付支出，并从“{账户}”扣减 {金额/币种}，同时写入School账户流水。`
- Cash 模式不选择 School 账户；必须选择现有 Cash 账户。Cash 账户仍由 Edge/Cash DB 验证 `is_active=true`、`allow_school_requests=true`、币种匹配。现有历史证明成功链的 School `account_id` 全为 NULL，实际支付账户只存在于 Cash request/transaction。
- Cash 模式先通过 API 调新 pending writer；拿到唯一 expense ID 后，再调用既有 `request-cash-expense-confirmation` Edge。实际支付日、Cash 账户、支付币种、可选显式支付金额/汇率/rounding mode 沿用现有 Edge 合同；未显式输入金额时仍由 School prepare RPC 计算并验证，页面只做非持久化预览。
- Edge 成功：`School待支付支出已保存，Cash request 已提交，等待审批。`
- Edge 失败：`School待支付支出已安全保存（ID：…）；Cash提交未完成：…。请从支出列表使用“提交 Cash 支付确认”重试，不要重复新增支出。`
- 页面不得把两阶段错误谎报为“全部失败”，不得自动再次创建 expense；列表重试复用同 expense 的现有 Cash attempt/event/idempotency。

### 幂等、恢复与对账

- School 增加 partial unique indexes：`cash_request_event_id`、`cash_request_id`、`cash_transaction_id` 各自非 NULL 唯一；当前审计重复均为 0，适合先 rollback rehearsal 再部署。
- Cash 现有 request idempotency unique、source-event unique、active-reference unique，以及 CNY/JPY transaction external unique 已足够；本轮审计 17 条无重复，不建议新增后台补偿任务。
- 跨库半写入恢复：School `pending_cash_request + event` 为重试入口；Edge 用同 event/idempotency 查询/创建 Cash request，再回写 School。先提供只读 reconciliation SQL/管理视图，不自动修复。只有连续出现不可由幂等重试恢复的记录，才另行设计 service-role reconciliation writer。
- 建议 Edge payload snapshot 新增 `school_business_entity_id`，值只能来自 School prepare RPC，不接受客户端；作为 immutable audit snapshot，School row 仍是当前业务主体权威。此项也是需业务负责人批准的新 snapshot 语义。
- 不新增 Gate，不复用学费 Gate。

### 精确文件范围

- Schema/RPC：
  - `sql/current/school_pending_cash_expense_identity_schema_YYYYMMDD.sql`
  - `sql/current/school_create_pending_cash_expense_record_rpc.sql`
  - `sql/current/school_create_pending_cash_expense_record_rollback_tests_YYYYMMDD.sql`
  - `sql/current/school_create_pending_cash_expense_record_postdeploy_YYYYMMDD.sql`
- API/Edge/UI：
  - `js/api/expense-api.js`
  - `js/pages/expense-page.js`
  - `expense.html`
  - `css/app.css`
  - `supabase/functions/request-cash-expense-confirmation/index.ts`
- 测试/文档：
  - `scripts/pending-cash-expense-static-test.mjs`
  - 新的 School/Cash reconciliation SELECT 文件
  - `docs/current-status.md` 与实施报告

### 下一轮测试与部署顺序

1. 先完成上述 schema/authority/报销/payment_method/snapshot 的逐项业务批准与 expansion declaration。
2. Schema rollback rehearsal；identity unique 和历史 0 冲突验证；schema 部署/postdeploy。
3. writer 静态审查、五角色 + anon 矩阵、幂等相同/冲突 payload、并发、失败原子性、三个 delta=0；全部 rollback。
4. Edge mock/隔离验证 School pending 成功 + Cash 失败、幂等重试、权限拒绝双库写入 0；禁止真实 Cash request。
5. 前端 page/API boundary、P0 金额权威、双模式文案、两阶段错误与刷新恢复测试。
6. 独立提交并推送；Schema/RPC、Edge、Pages 顺序部署；双库只读 postdeploy 与历史哈希/计数复核。

在残余 writer ACL 封口和本草案所列业务模型扩展获批之前，结论为 No-Go。
