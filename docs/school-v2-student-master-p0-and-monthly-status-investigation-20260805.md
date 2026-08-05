# School V2 学生主数据 P0 权限封口与月份状态模型调查报告

日期：2026-08-05

## 1. 结论

- 学生主数据已确认的生产权限旁路已经封口并上线：客户端不再拥有 `school_students` 表级写权限，PUBLIC/anon 无读取权限，authenticated 读取由 active membership + 角色白名单控制；交互式新增、编辑及当前 `status` 修改只允许 active admin。
- canonical create/update writer 已固定 `SECURITY DEFINER` 与 `search_path=pg_catalog, public`，首段执行 DB active-admin 断言；update 增加行锁和 `expected updated_at` 并发合同。旧 overload 全部 owner-only，service_role 不能调用交互式 writer。
- migration rehearsal、事务 rollback 角色矩阵、双会话锁、生产 postdeploy、真实身份负向和生产 Chrome 无写验收均通过。8 名学生与学生关联历史指纹严格不变，真实学生业务写入为 0，fixture residue 为 0。
- 月份状态调查已完成，但本轮没有建立状态事件表、没有修改筛选、没有修改任何真实学生资料或状态。
- 月份状态模型目前为 **No-Go for implementation**：需要业务负责人补充批准唯一 paused 学生的准确生效月份、旧 `school_students.status` 的退役语义、状态转换/更正合同，以及各业务 writer 对 paused/left 的资格规则。不得把 `2026-07` 或 `updated_at` 推断为暂停月份。

## 2. 实时起点与部署基线

| 项目 | 起点 |
|---|---|
| 分支 | `main` |
| HEAD | `5b276a826e1ea5f9deacc0e1264fb8eda073e695` |
| fetch 后 `origin/main` | `5b276a826e1ea5f9deacc0e1264fb8eda073e695` |
| ahead / behind | `0 / 0` |
| 页面版本 | `v10.5.5` |
| 起点页面代码 Pages run | `30889444439`，HEAD `b788b52...`，success |
| 起点最新 Pages run | `30889756079`，HEAD `5b276a8...`（仅文档后续提交），success |
| Gate | preview=`enabled` / generate=`blocked` / cash_submit=`enabled` |
| 学生 | 8：active 7，paused 1 |

起点工作区除六份受保护 untracked 文件外无其他改动；六份文件始终未移动、未修改、未暂存。

## 3. 业务模型扩展声明

本轮 P0 封口没有新增业务表、业务列、状态值、月份事实或历史解释。已获本任务明确批准的语义变化只有：

- `school_students` 直接客户端写入改为只允许受控 writer；
- 学生读取权威改为 active admin/operator/read_only；
- 学生新增、普通资料编辑和当前状态修改权威改为 active admin；
- service_role 只保留必要 SELECT，不允许调用交互式 writer；
- canonical update 增加行锁与 expected-version 并发保护。

月份状态事件表、月份权威、legacy status 退役和 paused 初始事件均未获逐对象实施批准，所以本轮只调查和设计。

## 4. 漏洞根因与写面盘点

### 4.1 根因

页面登录 guard 只保护正常 UI 路径，不能阻止直接 REST/RPC 请求。修复前同时存在三层旁路：

1. `school_allow_all_students` 是 PUBLIC `ALL / USING true / WITH CHECK true` policy；
2. anon、authenticated、service_role 持有学生表直接 SELECT 与 DML；
3. 3 个 create overload、5 个 update overload 均为 `SECURITY DEFINER`，旧 search path 为 `public`，anon/authenticated/service_role 可执行且函数体无 DB active-admin 断言。

只修 canonical 函数会遗留旧 overload 旁路；只修页面会遗留 REST/RPC 旁路；只修 RLS 会遗留 SECURITY DEFINER writer 旁路。因此必须同时收口表 ACL、RLS 和全部函数签名。

### 4.2 修改前完整写面

- `school_students` owner 为 postgres，RLS 已开启；唯一业务 trigger 为 `trg_school_students_updated_at -> school_set_updated_at()`，只更新 `updated_at`。
- 运行时学生主表 writer 共 8 个：3 个 `school_create_student_profile(...)`、5 个 `school_update_student_profile(...)`。
- 未发现其他运行时函数写学生主表，未发现动态 SQL、可写 view 或等价 trigger writer。
- 唯一读取该表的 view `school_v_student_month_summary` 不可更新。
- 浏览器页面对学生表只有 SELECT；页面写入只经 `js/api/student-api.js` 的 create/update RPC。
- Edge `request-cash-income-confirmation` 使用 service-role 读取学生姓名/显示名，不写学生，因此只保留 service-role 最小 SELECT。
- 未发现合法生产后台任务确实需要 service_role 创建或编辑学生；未发现浏览器 service-role secret。
- migration/import/test 中的一次性学生写入均不是运行时入口；部署后的表 ACL 与函数 EXECUTE 已阻断客户端复用这些路径。

## 5. P0 实施内容

### 5.1 SQL 与脚本

- `sql/current/school_student_master_p0_permission_closure_core_20260805.sql`
- `sql/current/school_student_master_p0_permission_closure_deploy_20260805.sql`
- `sql/current/school_student_master_p0_permission_closure_rollback_tests_20260805.sql`
- `sql/current/school_student_master_p0_permission_closure_postdeploy_20260805.sql`
- `scripts/student-p0-permission-static-test.mjs`

### 5.2 前端兼容

- `js/api/student-api.js` 在 canonical update 调用中传入 `p_expected_updated_at`。
- `js/pages/student-page.js` 使用编辑时已读取的 `editingStudent.updated_at`，不计算业务事实。
- `js/config.js` 更新为 `v10.5.6`。
- page-layer 仍不直接 `.rpc()`，不直接执行 INSERT/UPDATE/DELETE/UPSERT。

### 5.3 表 ACL 与 RLS 终态

| 身份 | SELECT | INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER |
|---|---:|---:|
| PUBLIC / anon | 拒绝 | 拒绝 |
| authenticated + 无 membership | RLS 拒绝 | 表 ACL 拒绝 |
| authenticated + inactive membership | RLS 拒绝 | 表 ACL 拒绝 |
| active admin | 允许 | 表 ACL 拒绝；只能走 writer |
| active operator | 允许 | 表 ACL 拒绝 |
| active read_only | 允许 | 表 ACL 拒绝 |
| service_role | 最小 SELECT | 拒绝 |

唯一 policy 为 `school_students_active_membership_select`，角色仅 authenticated；条件由 `school_get_current_app_membership()` 判定当前 membership 为 active 且角色属于 admin/operator/read_only。最终 information-schema ACL 指纹为 `481ca23a14d9e44375314c5e41e084d0`。

学生表无 sequence。postgres 的 public-schema default privileges 已撤销 PUBLIC/anon/authenticated 的未来表、sequence、function 自动权限；未扩大 service-role 或普通客户端权限。

### 5.4 create/update writer 终态

| 签名类别 | authenticated | anon | service_role | 说明 |
|---|---:|---:|---:|---|
| canonical create 10 参数 | 可 EXECUTE | 拒绝 | 拒绝 | 首段 active-admin 断言；固定 search path |
| canonical update 12 参数，含 expected timestamp | 可 EXECUTE | 拒绝 | 拒绝 | 首段 active-admin 断言；`FOR UPDATE`；精确版本比较 |
| 其余 2 个 create overload | 拒绝 | 拒绝 | 拒绝 | owner-only |
| 其余 5 个 update overload | 拒绝 | 拒绝 | 拒绝 | owner-only |

canonical update 在持有学生行锁后比较 `updated_at`；陈旧版本返回 SQLSTATE `40001`，不会 lost update。旧 overload 虽保留历史函数体和旧 search path，但只有 owner 可执行，不能形成客户端旁路。

## 6. 测试、部署与生产验收

### 6.1 静态与 rehearsal

- `git diff --check`：通过。
- JS 语法/边界检查：通过。
- `node scripts/student-p0-permission-static-test.mjs`：PASS。
- deploy wrapper 以 `commit=0` 执行：变更完整应用、验证后显式 ROLLBACK。
- rollback matrix：输出 `STUDENT_P0_PERMISSION_CLOSURE_ROLLBACK_TEST_PASS` 后显式 ROLLBACK。
- rollback 后旧 policy/旧权限仍在且 synthetic residue 为 0，证明 rehearsal 确实回滚。

### 6.2 角色与 payload 矩阵

- anon、无 membership、inactive admin、operator、read_only、service_role：交互式 create/update 均拒绝。
- active admin：rollback fixture 中 create/update 成功；非法 UUID、非法状态、陈旧 `updated_at` 和错误 payload 拒绝；失败无半写入。
- 所有旧 overload：普通角色无 EXECUTE。
- 表级 anon/无 membership/inactive/operator/read_only/admin/service_role DML：全部拒绝。
- writable view、旧 policy、动态 SQL、trigger 等价旁路：0。

rollback fixture UUID 范围为 `a0500000-0000-4000-8000-000000000001` 至 `a0500000-0000-4000-8000-000000000005`，学生 UUID 为 `a0500000-0000-4000-8000-000000000100`；最终 auth user、membership、student residue 全部为 0。

### 6.3 双会话

- Session A 对一条真实学生行执行 `SELECT ... FOR UPDATE`，没有修改字段。
- Session B 使用真实 active-admin JWT 上下文调用 canonical update，payload 与原行相同，`lock_timeout=700ms`；结果为 `lock_not_available` 并显式 ROLLBACK。
- Session A 随后显式 ROLLBACK。
- 该测试只证明真实行锁和无 lost-update 窗口，没有提交真实学生写入。

### 6.4 提交、DB 与 Pages

- P0 commit：`daa76188ad02d53194d3a0e5086c2d18ad871b7d`，已 push 到 `origin/main`。
- 生产 School DB：执行 `school_student_master_p0_permission_closure_deploy_20260805.sql`，`commit=1`，COMMIT；只写 schema/function/ACL/policy 定义，学生业务行写入 0。
- postdeploy：`STUDENT_P0_PERMISSION_CLOSURE_POSTDEPLOY_PASS`。
- Pages：run `30966070323`，HEAD `daa7618...`，success；生产页面 `v10.5.6`。
- Edge：无修改、无部署。

### 6.5 Chrome 无写验收

使用 active admin 的既有 Chrome session，只读打开生产：

- `student.html`：8 张卡、共 8 名、创建入口正常显示；
- `lesson.html`：118 行，学生选项 9 项（含“全部”）；
- `settlement.html`、`income.html`、`expense.html`、`wage-rule.html`：学生选项均 9 项；
- 各页版本/资源正常，未发生 auth redirect；
- 全部目标页 Console error/warning 为 0；
- 未打开写弹窗、未点击写按钮、未创建或编辑学生。

## 7. 数据不变量

| 范围 | 数量 | 全行 MD5 | 结果 |
|---|---:|---|---|
| `school_students` | 8 | `431ae7f350902dde0642ddc4982054ed` | 不变 |
| 学生关联支出 | 0 | `d41d8cd98f00b204e9800998ecf8427e` | 不变 |
| 学生关联收入 | 30 | `0380f2e4ab967d37ad898a4e534195a4` | 不变 |
| 学生课时 | 733 | `4d0c327cc0d7b2c6cbdae10ede6a3fd4` | 不变 |
| 学生月结 | 18 | `7986db5dd35c0ecfa180a04aef7f4051` | 不变 |
| 学费账单 | 22 | `d079f068c0fa19fc07d4dcd94094fae2` | 不变 |
| 工资锁详情 | 556 | `0b2976f8005835d66b2db25b0b3c1939` | 不变 |
| 工资规则 | 20 | `2dc430ca4a58416235f2ba771b91b9f1` | 不变 |

Gate 仍为 preview=`enabled` / generate=`blocked` / cash_submit=`enabled`，updated_at 均未变化。Cash 本轮只执行 SELECT，expense 链仍为 18 request / 12 CNY transaction / 3 JPY transaction，Cash 写入 0。

Storage 仍为 57 个 `school-expense-files` 对象，其中与现存 expense 关联 27 个、orphan 30 个；对象 ID+路径指纹为 `f74e601948d8cc5e9d06dc19db2bf296`。没有调用 Storage 写 API，没有删除、改写或补绑 orphan。

## 8. 学生 selector / lookup 全矩阵

说明：“当前包含inactive”表示当前代码按 `school_students.status` 快照是否仍能取到非 active 学生；不表示已经具备月份状态能力。

| 页面/用途 | 页面 JS → API | 学生 reader | 业务数据 reader | 月份、URL 与刷新 | 当前行为与风险 |
|---|---|---|---|---|---|
| 学生管理 `student.html` | `student-page.js` → `student-api.js` | `school_students` 两次直接 SELECT | 无独立业务数据 | 无月份；无 selected URL；每次查询及写后重载 | 默认列出全部快照状态，可按状态搜索；status 仍在资料弹窗中编辑 |
| 课时管理 `lesson.html` 顶部 | `lesson-page.js` → `lesson-api.js` | `fetchLessonStudents()` 直接 SELECT | `school_list_lesson_management_records_authoritative` + stats RPC | `year/month`，可带 `week_start`、`student_id`；学生 lookup 仅初载，业务月变更重读 | 顶部含所有快照状态；“全部”课时不依赖学生候选，URL paused 可保留 |
| 课时新增/批量 | 同上 | 同一内存 lookup | write RPC 独立校验 | 使用所选月份/日期；打开弹窗不重读 lookup | 只显示当前快照 active 且新业务归属学生，历史月份也会永久隐藏当前 paused |
| 课时 PDF 导出 | 同上 | 同一内存 lookup | 权威课时 reader + stats | 当前月或下一月；无独立 URL | 只显示当前快照 active，paused 学生历史 PDF 无法从弹窗选择 |
| 周课表图片 `weekly-schedule-image.html` | `weekly-schedule-image-page.js` → `lesson-api.js` | `fetchLessonStudents()` 直接 SELECT | 对周覆盖的每个月调用课时权威 reader | `week_start` + `student_id` URL；学生 lookup 仅初载 | 顶部含所有快照状态，业务行按课时独立加载，selected paused 保留 |
| 本周课时看板 `weekly-lesson-dashboard.html` | `weekly-lesson-dashboard-page.js` → `lesson-api.js` | `fetchLessonStudents()` 直接 SELECT | `school_get_weekly_lesson_operations(date)` | `week_start` URL；周切换只重读业务 RPC | **业务 RPC 直接要求当前 `s.status=active`**，paused 学生即使目标周有事实也会被静默排除 |
| 教室排班 `classroom-schedule.html` | `classroom-schedule-page.js` → `lesson-api.js` | `fetchLessonStudents()` 直接 SELECT，仅显示姓名 | 周覆盖月份的课时权威 reader | 日期周，无 selected URL；lookup 仅初载 | 无学生候选；业务课时不由 status 过滤，paused 姓名可显示 |
| 课时详情 `lesson-detail.html` | `lesson-detail-page.js` → `lesson-detail-api.js` + `lesson-edit-dialog.js` | 全量 `school_students` 直接 SELECT | record-ID 课时/结算/工资读 | `id`；月份来自记录；详情/保存后重载 | 详情姓名保留；编辑下拉只留当前 active，当前 inactive/paused 的原学生可能变成空值 |
| 学生月结 `settlement.html` | `settlement-page.js` → `settlement-api.js` | `fetchSettlementStudents()` 直接 SELECT | 月结 snapshot + lesson/income candidates + preview/blocker RPC | 单 `year_month`；无 URL selected；lookup 仅初载，月份变化只重读结算 | 顶部含所有快照状态；“全部”由 snapshot/lesson/income 事实产生，不依赖候选列表 |
| 月结详情 `settlement-detail.html` | `settlement-detail-page.js` → `settlement-detail-api.js` | 全量 `school_students` 直接 SELECT | record-ID 月结、课时、收入、调整、工资 blocker | `id`；月份来自 settlement；操作后重载 | 历史详情不按当前 status 隐藏；当前实现读取了超出单记录所需的全学生列表 |
| 收入 `income.html` 顶部 | `income-page.js` → `income-api.js` | `fetchIncomeLookups()` 直接 SELECT | `school_operational_income_records` 按 `year_month` | URL 只同步 `year/month`，不保留 student；lookup 仅初载 | 顶部含所有快照状态；“全部”收入独立加载后客户端筛选 |
| 收入新增/学费账单 | 同上 | 同一 lookup | 既有收入/学费 preview 与 writer | 新增使用日期/settlement month；学费使用 billing month | 两处只显示当前快照 active；paused 在历史月份也不可选；DB tuition reader 当前并不一致地拒绝 paused |
| 收入详情 `income-detail.html` | `income-detail-page.js` → `income-detail-api.js` | 全量 `school_students` 直接 SELECT | record-ID 收入、结算、流水 | `id`；月份来自记录；操作后重载 | 详情姓名保留；编辑学生只显示当前 active，原 paused 选择可能丢失 |
| 学费收据 `tuition-receipt.html` | `tuition-receipt-page.js` → `tuition-receipt-api.js` | 只按 income.student_id 直接 SELECT 单学生 | record-ID income + linkage event | `income_id`；月份来自 income | record-ID lookup 不应经过候选筛选；手工收据姓名只是文档覆盖，不是学生 selector |
| 支出 `expense.html` | `expense-page.js` → `expense-api.js` | `fetchExpenseLookups()` 直接 SELECT | `school_expense_records` 按 `year_month` + payment/attachment reads | URL 只同步 `year/month`；lookup 仅初载 | 顶部含所有快照状态；“全部”支出独立加载。当前新增支出不提供学生选择，payload student 为 NULL |
| 支出详情 `expense-detail.html` | `expense-detail-page.js` → `expense-detail-api.js` | 全量 `school_students` 直接 SELECT | record-ID expense/payment/reimbursement/transaction | `id`；月份来自记录 | 只作历史显示 lookup；不应由月份候选隐藏 |
| 老师工资 `wage.html` | `wage-page.js` → `wage-api.js` | `fetchWageStudents()` 直接 SELECT，用于姓名 | wage locks、payments、expenses、candidate lessons 按月 | URL 有月份/老师/业务归属，无学生 selector；lookup 仅初载 | 工资业务集合不由学生候选驱动；历史学生名必须始终可见 |
| 工资规则 `wage-rule.html` | `wage-rule-page.js` → `wage-rule-api.js` | lookup 直接 SELECT | wage rule 表独立加载 | 无月份、无 selected URL；页面加载/写后重载 | 顶部含所有快照状态；新增/编辑只显示当前 active，paused 的既有规则编辑可能丢选择 |
| 工资规则详情 | `wage-rule-detail-page.js` → `wage-rule-api.js` | 按 rule.student_id 单学生直接 SELECT | record-ID wage rule | `id`；无月份 | record-ID 姓名保留，不应使用候选列表过滤 |
| 报销列表/详情/导出 | reimbursement page/API | **不直接读取 `school_students`** | expense/reimbursement/payment snapshot | 列表按月份、详情按 id | expense 的 `student_id` 是历史事实，但显示主要使用收款对象/快照；不得新增候选门控 |
| 合同、方案、收据手工姓名 | contract/quote/receipt page | 无学生 master selector | 文档输入/record lookup | 无统一月份 | 手工姓名不是状态 resolver 的接入对象 |

代码层共有 12 个 API 模块直接读取 `school_students`：student、lesson、lesson-detail、settlement、settlement-detail、income、income-detail、expense、expense-detail、wage、wage-rule、tuition-receipt。没有显式 client cache；“缓存”只是页面模块内数组，通常只在首次加载或写后整页数据刷新，月份/周变化时大多只刷新业务记录而不刷新学生 lookup。

## 9. 候选名单与业务数据耦合

### 9.1 必须保持的边界

- 候选名单只决定用户能在筛选器或新增表单里主动选择谁。
- “全部”必须直接查询目标月/周的业务事实，不能先取 active student IDs 再 `IN (...)`。
- 财务待处理、异常、未锁定月结、pending income/expense/Cash 请求不能因学生状态被隐藏。
- record-ID 详情必须按记录引用的 student ID 读取最小展示资料，即使该学生在目标月 paused/left。
- URL 或当前已选的 inactive 学生必须作为显式 override 返回，并带 `selected_out_of_scope=true`，不能静默清空。

### 9.2 当前耦合结论

- lesson、settlement、income、expense、wage、classroom schedule、weekly schedule image 的业务集合目前基本独立于学生 lookup；把顶部候选改成月份 resolver 不应改变“全部”结果。
- settlement preview candidates 来自目标月课时和已收学费收入；学生表只用于补充默认业务归属，不决定 candidate 是否存在。
- wage 与报销没有学生候选门控，历史事实保持可见。
- 唯一已确认的直接静默耦合是 `school_get_weekly_lesson_operations(date)` 的 current-status active 条件，必须在接入月份模型时改为“业务行不因候选隐藏”，另行展示月份状态。

### 9.3 服务端现有状态规则不一致

生产函数定义显示：

- weekly operations reader 只接受当前 `active`；
- planned/actual/cancelled/makeup/partial lesson、batch/import、lesson edit 等 writer 排除 `inactive/graduated`，因此当前 `paused/withdrawn` 仍可能被 DB 接受；
- wage-rule writer 排除 `inactive/graduated/withdrawn`，仍允许 `paused`；
- tuition snapshot/preview 只排除 `inactive/disabled/archived`，会允许 `paused/graduated/withdrawn`；
- 前端新增、编辑和导出多处却严格只显示 current `active`。

因此不能把“接入统一 resolver”简化为前端过滤改造。各 writer 的月份资格必须由业务负责人逐域批准，否则会改变课时、学费、月结或工资业务语义。

## 10. 当前 paused 学生的可证明事实

唯一 paused 学生为 `cff85c52-6acc-4b0f-8c92-3db280a5dd77`（厦门吕同学）：

- `entrance_date` 为 NULL；created_at 为 2026-05-18；updated_at 为 2026-07-24。
- 课时事实共 40 条：2026-04 为 4、2026-05 为 16、2026-06 为 20；实际日期范围 2026-04-28 至 2026-06-29。
- 月结 3 条：2026-04、05、06 各 1 条，均有锁定事实。
- 收入 1 条：settlement month 2026-06。
- 工资锁详情 52 条：2026-04 为 6、05 为 16、06 为 30。
- 学生关联支出 0，学费 bill 0；未发现 2026-07 以后该学生的上述业务事实。

这些事实只能证明其曾在 4–6 月有业务活动，以及学生快照在 7 月 24 日被更新。`updated_at` 同时可由任何学生资料编辑触发，不是 status actor/time 字段；没有 status history、暂停原因、操作者或 effective month。**不得据此推断暂停从 2026-07 生效，也无法证明是否曾暂停后恢复。**

当前页面表现：顶部筛选会在所有月份显示该 paused 学生；新增课时、批量课时、课时 PDF、收入新增、学费账单、收入编辑、课时编辑、工资规则新增/编辑则在所有月份隐藏；weekly dashboard 会在所有周静默排除；历史列表和多数详情仍保留业务事实。

## 11. 推荐月份状态模型

### 11.1 唯一权威表

建议新增 `public.school_student_status_events`：

| 列 | 类型/约束 | 语义 |
|---|---|---|
| `id` | uuid PK，DB default | 稳定事件身份 |
| `student_id` | uuid NOT NULL，FK `school_students(id)` ON DELETE RESTRICT | 学生 |
| `effective_month` | date NOT NULL | 生效月第一天 |
| `status` | text NOT NULL CHECK in (`active`,`paused`,`left`) | 自该月起的月份状态 |
| `reason` | text | 业务原因；是否强制非空需批准 |
| `created_at` | timestamptz NOT NULL DB default | 实际创建审计时间，不回填伪时间 |
| `created_by_user_id` | uuid NOT NULL | DB 取 `auth.uid()`；客户端不得传 actor |
| `voided_at` | timestamptz NULL | 一次性作废时间 |
| `voided_by_user_id` | uuid NULL | DB 取 `auth.uid()` |
| `void_reason` | text NULL | 作废原因 |
| `corrects_event_id` | uuid NULL self FK | replacement 对应的被更正事件 |

约束：

- `effective_month = date_trunc('month', effective_month)::date`；API 只接受 `YYYY-MM-01`，页面的 `YYYY-MM` 在 API 层做格式转换，不参与业务推断。
- partial unique `(student_id, effective_month) WHERE voided_at IS NULL`，同一学生同月最多一个有效事件。
- void 三字段必须全 NULL 或全非 NULL；普通 UPDATE 禁止，只有受控 writer 可把有效事件单向作废。
- 不存 `valid_to`、`current_status` 或第二份可写快照；结束月由下一事件推导。
- 不允许物理 DELETE；历史更正为“旧事件作废 + 同事务 append replacement”。

### 11.2 解析规则

对目标月 `M`：

1. 只看未作废事件；
2. 选择 `effective_month <= M` 中月份最大的唯一事件；
3. 有事件则该事件 status 为权威；
4. 没有任何适用事件时严格 fallback 为 `active`；
5. 不读取 `school_students.status` 作为 fallback，不根据入口日、最后课时或 updated_at 推断。

暂停后恢复只需在恢复月 append `active`；此前 paused 月自然保留。`left` 是否允许以后再次 active、以及具体转换矩阵必须由业务负责人批准。

### 11.3 并发、append、void/correction

- writer 仅 authenticated 可 EXECUTE，函数首段 `school_require_current_app_admin()`；anon/service_role/operator/read_only/无 membership/inactive 均拒绝。
- 每次写入先对 `school_students` 目标行 `FOR UPDATE`，把同一学生的状态序列串行化。
- writer 接受 `p_expected_latest_event_id` 与 `p_expected_latest_event_created_at`；锁后精确比较，陈旧页面返回稳定并发错误。
- 同月已有有效事件时普通 append 拒绝；correction writer 在一个事务中锁定、校验、作废旧事件并 append replacement。
- void 表示“事件从解析历史中完全移除”，可能改变该月直到下一事件的解析结果；UI 提交前必须由 DB preview 返回受影响月份范围。前端不得自行推导范围。
- actor、created/voided 时间全部由 DB 记录，不接受客户端传入或伪造。

### 11.4 统一 DB resolver

建议分为一个内部权威 resolver 和两个最小公开 reader：

1. owner-only/internal：
   `school_resolve_student_status_at_month(p_student_id uuid, p_target_month date)`
   返回 `resolved_status, source_event_id, source_effective_month, is_legacy_fallback`。
2. 页面候选：
   `school_list_student_filter_candidates(p_start_month date, p_end_month date default null, p_include_inactive boolean default false, p_selected_student_id uuid default null, p_business_entity_id uuid default null)`
3. record-ID lookup：
   `school_get_student_display_lookup(p_student_id uuid, p_target_month date)`

候选返回最小字段：`id, student_code, name, display_name, business_entity_id, status_at_start, status_at_end, is_active_in_scope, is_selected_override, source_effective_month, is_legacy_fallback`。reader 只允许 active admin/operator/read_only，固定 security-definer search path；不返回电话、微信、家长资料、备注等非必要敏感字段。

候选包含规则：

- 单月：目标月为 active；
- 范围：在闭区间任一月份 active；
- `include_inactive=true`：返回全部，并附 DB 解析状态；
- `p_selected_student_id`：即使不在 active 范围也额外返回，`is_selected_override=true`，UI 标注“该月暂停/离校”；
- record-ID reader 永远按引用 ID 返回最小展示资料，不受候选条件影响。

### 11.5 月份口径

- 单月页面（lesson、settlement、income、expense、wage）：使用页面明确选择的 `YYYY-MM`，传 DB 为该月第一天。
- 无月份页面（student、wage-rule）：默认使用东京当前月；页面必须用 `Asia/Tokyo` 显式计算，不能依赖浏览器/主机本地时区。
- record-ID 详情：使用记录自身权威月份；lesson 优先既有 authoritative student settlement/billing month，income 使用 settlement_month 或既有业务合同指定的 year_month，settlement/wage 使用其冻结月份。
- 日期范围/自然周：传起止日期覆盖的月份范围，candidate 采用“任一覆盖月 active”；业务数据仍按记录本身查询，不以 candidate IDs 缩小。
- 跨月课时：候选范围可覆盖两个自然月，真正写入资格仍由 DB 以该记录已有 authoritative month 复核，page 不计算。
- 当前 `currentYearMonth()` 使用浏览器本地 `Date#getFullYear/getMonth`，而 `currentJapanDate()` 才显式东京时区；下一轮应统一为 Tokyo helper。这是默认月份契约问题，不是本轮业务数据修改。

## 12. 页面交互与复用建议

- 新增 `js/api/student-status-api.js`，所有页面只调用 API wrapper；page-layer 不直接 `.rpc()`。
- 新增轻量共享 renderer/helper，只负责 option 标签、selected override 和刷新，不计算状态：例如 `renderStudentCandidateOptions()`；状态与 `is_active_in_scope` 全由 DB 返回。
- 单月顶部默认只显示 active，增加“包含暂停/离校”开关；切月、切周或开关变化时重新调用 resolver，不能沿用首次加载的学生数组。
- “全部”选项永远不把 candidate IDs 传给业务 reader；若选择具体学生，再用 student_id 对已加载业务结果筛选或作为显式业务查询参数。
- URL selected inactive 在 resolver 请求中作为 `p_selected_student_id`，返回后显示标记并保持选择；若 ID 不存在或无读取权限，才显示明确错误。
- 学生管理页增加目标月和 include toggle；卡片显示 DB resolved status、生效月及 legacy fallback 标记。
- 学生资料编辑弹窗移除 status；另设 active-admin-only 状态事件弹窗，要求生效月、状态、原因，并显示 DB preview/历史。更正/作废入口只在历史区出现。
- lesson/income/wage-rule 的编辑弹窗必须保留原记录学生，即使其当前不在候选范围；是否允许改成另一 inactive 学生由 writer 资格合同决定。
- 导出、dashboard、工资、报销和详情均不得因 selector 默认值隐藏历史或待处理业务行。

## 13. Legacy fallback 与最小 backfill

- 推荐不做全量 backfill。现有 7 名 active 学生不建立虚构历史事件，按“无事件=active”解析。
- 唯一 paused 学生不能直接走 fallback，否则切换后会在所有月份被解析为 active；也不能用 2026-07、updated_at 或最后课时推断。
- 安全切换条件是业务负责人明确提供该学生的 paused 生效月，并授权创建 **一条** 初始 paused event。created_at/actor 记录实际迁移操作，不伪造历史 actor；reason 明确写“业务负责人确认的初始状态事件”。
- 如果业务负责人无法确认月份，则只能暂缓月份权威切换；不能长期以 `COALESCE(event, school_students.status)` 维持双权威。
- 切换后 `school_students.status` 应冻结并声明为 legacy diagnostic，不再被 profile writer 修改、不被任何生产 reader/writer用来判断学生月份状态；达到“所有运行时消费者均改用 resolver、连续监控无旧读”后再单独审批是否物理删除。当前不建议立即 drop。

## 14. 分阶段实施计划

前提：下一轮先取得第 16 节逐项批准。

1. Schema：创建事件表、约束、索引、RLS/ACL、immutable/void guard；不切换 reader，不写真实事件。
2. Writer/reader：部署 active-admin append/correction/void、DB preview、内部 resolver、候选与 record-ID reader；完成角色/rollback/并发测试。
3. 最小初始化：只在业务负责人给出精确月份后，为唯一 paused 学生写一条白名单真实初始事件；7 名 legacy active 不回填。
4. API/共享组件：新增统一 API wrapper 和 option renderer；禁止 page direct RPC。
5. 页面接入：先只读顶部筛选，再接入 create/edit/export selected override；每一组都证明“全部”业务 hash 不变。
6. 服务端消费者：按逐域批准替换 weekly reader 和现有 writer 的 current-status 判断；不得自行把 paused/left 解释为业务写禁用。
7. Authority cutover：同一发布窗口移除 profile status 写入、将 event resolver 宣告为唯一权威、冻结 legacy status；兼容窗口、监控、截止时间和回退规则需在批准中明确。
8. Postdeploy/Chrome：角色、月份序列、URL inactive、跨月、detail、export、财务待处理及全量业务指纹回归；更新 current-status、commit、push。

## 15. 下一轮测试矩阵

### DB

- 无历史、首事件前、事件当月、事件后、paused→active、active→left、同月 correction、void 后回退。
- 月份第一天 CHECK、非法状态、重复同月、陈旧 expected event、双会话相同学生/不同学生。
- anon/无 membership/inactive/operator/read_only/service_role 写拒绝；active admin 写允许；active角色最小读允许。
- 表级直接 DML、legacy profile status 写、旧 overload、可写 view、动态 SQL 均无旁路。

### 页面

- 单月 active 默认、include inactive、URL selected inactive、选择标记、切月刷新。
- 周跨月 active-in-any；东京月末/年末默认月份。
- lesson/settlement/income/expense 顶部“全部”数量与业务行 hash 不变。
- weekly dashboard 不再因 current status 丢业务行。
- lesson/income/wage-rule 详情与编辑保留原 inactive 学生。
- PDF/图片/工资/报销/详情历史不隐藏；无 JS 业务状态推导、无 page direct RPC/DML。

### 零影响

- 学生主表除经批准的 legacy status 冻结合同外不改资料；仅获批的一条 paused initial event 可为真实业务写。
- lesson、settlement、bill、income、expense、wage、account/Cash 全行指纹前后相同。
- Gate、Edge、Cash、Storage 对象与 30 orphan 均不变。

## 16. 下一轮必须精确批准的业务事项

1. 新表 `school_student_status_events` 及第 11.1 节每个字段/语义；事件 status 仅 `active/paused/left`。
2. `effective_month` 为月首 date，最新未作废事件为唯一月份权威；无事件 fallback active。
3. `school_students.status` 在切换后冻结为非权威 legacy diagnostic，profile writer/UI 不再修改；不得 dual write/fallback。
4. 唯一 paused 学生的准确 paused 生效月，以及允许创建一条初始事件；当前证据不能代替该决定。
5. `reason` 是否必填、left 是否允许以后 active、完整转换矩阵。
6. correction/void 的影响语义、是否允许作废非最新历史事件，以及 DB preview 后的确认合同。
7. lesson、tuition、settlement、income、expense、wage-rule/Cash 各自对目标月 paused/left 的“只隐藏候选、允许历史修正、禁止新业务或仍允许财务收尾”规则。
8. 权威切换的兼容窗口、唯一 reader precedence、监控、完成标准、截止时间和 legacy 字段退休条件。

在上述事项明确批准前可以继续只读验证或把 SQL/测试范围进一步细化，但不能开始 schema、writer、真实 paused event 或页面实现。

## 17. 受保护 untracked 文件

| 文件 | SHA-256 |
|---|---|
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 18. 最终状态摘要

- 文件变更：P0 SQL/JS/测试及本报告/current-status；六份受保护文件未变。
- 已执行 SQL：P0 deploy wrapper rehearsal/正式部署、rollback tests、postdeploy；其余调查均为 SELECT。
- 已调用写 RPC：仅 rollback synthetic fixture 中的 create/update；生产真实学生 create/update 为 0。
- DB 写入：School 仅 schema/function/ACL/RLS 定义；真实学生及关联业务行 0。Cash 写入 0。Storage 写入 0。
- 白名单测试：只限 `a0500000-*` synthetic fixture，最终 residue 0。
- P0 已 commit/push并部署；月份状态模型未实施。
- 结论：学生主数据权限旁路已封口；月份状态实现仍需第 16 节精确批准后才能 Go。
