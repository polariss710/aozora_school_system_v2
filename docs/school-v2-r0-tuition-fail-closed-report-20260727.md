# School V2 R0学费链紧急阻断与8月全量基线实施报告

报告日期：2026-07-27（Asia/Tokyo）

## 1. 当前分支、HEAD、工作区

- 分支：`main`
- HEAD：`c180690 feat: calculate part-time lesson progress in db`
- 开始时工作区：clean
- 完成时工作区：仅包含本阶段 10 个目标文件的未提交修改；没有暂存、commit 或 push。
- School/Cash 数据库连接与 `psql` 可用；未输出、保存或提交任何数据库 URL、密钥或令牌。

## 2. 读取的规则

已完整或按任务相关范围读取并执行：

- `AGENTS.md`
- `docs/current-status.md`
- `docs/system-map.md`
- `docs/business-flow-canonical.md`
- `docs/canonical-flow-checklist.md`
- `docs/workflows/write-rpc-flow.md`
- 本阶段附件中的 R0 实施授权、边界、测试和交付要求
- 当前仓库的学费账单、收入、Cash、页面 API 与 Edge Function 调用链
- School DB 的实际函数、重载、ACL、触发器和相关表结构

附件引用了《School V2学费链P0最终整改设计书 Final Design v1.1》，但附件和仓库中未发现可单独读取的该设计书正文。本次以附件中已明确列出的 R0 设计规则为实施基线；这是未确认事项，不扩大实现范围。

## 3. 修改前基线

### 3.1 Git和数据库

- School DB、Cash DB 均可连接；数据库版本 PostgreSQL 17.6。
- 正式学费账单 9 张：`income_created` 8、`cancelled` 1。
- `source_type = student_tuition_bill` 的收入 9 条：`received` 7、`pending` 1、`cancelled` 1。
- School→Cash linkage 35 条，其中已同步正式学费 7 条。
- Cash external request 34 条：`approved` 32、`rejected` 2；无 active pending。
- School账户流水 185 条。
- planned lesson 397 条，actual lesson 228 条。
- 工资锁 95 条，工资锁明细 556 条。

### 3.2 张倬闻P0事故记录

两张账单和两条收入在实施前均存在，实施后保持原样：

| 对象 | ID | 状态/说明 | 基线哈希 |
|---|---|---|---|
| 旧账单 | `fdf3cdfe-f715-4814-b500-9ff2bfe77a63` | 2026-07，个人业务归属 | `6df85731a47800b3f272a6bdd5fee74c` |
| 新重复账单 | `047dac2b-9484-4637-8e5e-9887857d121b` | 2026-07，青空业务归属 | `a4d22ad3df6762024ed47e21290c6171` |
| 旧收入 | `f86ac9db-effd-402e-a320-1e4b6846a9c7` | `received` | `9843310d2634a639d93ceb18da04d0cb` |
| 新重复收入 | `bbd7e7fd-fa04-404b-91fc-ab894cca28c8` | `pending` | `0d5a2e8f5ec59bec1fb4c17d55e81901` |

### 3.3 孙陈锋两条跨月课

| ID | 日期 | 科目 | 时长 | 单价 | 业务归属 | 基线哈希 |
|---|---|---|---:|---:|---|---|
| `8b737b58-cd14-42c5-afd2-34730dcef963` | 2026-08-01 | 物理 | 2h | JPY 17,000/h | 青空 | `d11d94ddb8e6ea0592bff9de99a4a7e1` |
| `685ad45e-b5da-42ca-8f43-7732e8d6e40d` | 2026-08-02 | 化学 | 2h | JPY 17,000/h | 青空 | `c3e5c64d61dfd0c8d80ad45e3c1c61e2` |

两条课已进入孙陈锋 2026-07 正式账单 `2a9f1c25-a060-461e-ae10-b02295dec381`，该链路已 received/Cash synced。本阶段没有修改它们。

## 4. 所有学费生成入口清单

### 4.1 实际部署的数据库入口

| 入口 | 作用 | R0结果 |
|---|---|---|
| `school_preview_student_tuition_bill(uuid,text,numeric)` | 学费验证预览 | 保留只读，要求 gate 精确为 `validation_preview_only` |
| `school_generate_student_tuition_bill(uuid,text,numeric,text)` | 正式账单生成 | DB 首阶段拒绝 `TUITION_GENERATION_BLOCKED` |
| `school_generate_student_tuition_bill(uuid,text,text)` | 兼容重载 | DB 首阶段拒绝 `TUITION_GENERATION_BLOCKED` |
| `school_create_student_tuition_bill_income_record(uuid,date,text)` | bill→income | DB 首阶段拒绝 `TUITION_GENERATION_BLOCKED` |
| `school_create_personal_cash_tuition_income_record(date,text,uuid,uuid,uuid,numeric,text,text,text,text,text,boolean,text,text,text)` | 遗留个人Cash学费received收入＋pending outbox | 已补充纳入 `student_tuition_generate` gate，DB首阶段拒绝 `TUITION_GENERATION_BLOCKED` |
| `school_cancel_pending_income_record(uuid,text,text)` | pending income 取消 | 不生成账单；对 tuition 行的直接更新还会被表级 guard 拒绝 |
| `school_delete_fresh_planned_lesson(...)` | 删除新 planned 的旧 guard | 仅检查账单引用，不生成账单或收入 |

### 4.2 遗留personal Cash tuition RPC补充审查

完整定义确认该 RPC 原本在同一 School DB 事务内：

1. 创建一条 personal business、`income_category = tuition`、JPY、`status = received` 的 `school_income_records`；
2. 创建一条 `source_event_type = tuition_income_received`、`sync_status = pending` 的 `school_personal_cash_income_linkage_events` outbox；
3. 不写 School account balance/transaction，也不直接写 Cash DB。

因此它虽然不使用 `source_type = student_tuition_bill`，仍会创建与学生学费收款等价或可能重复的资金事实，属于 R0 generate 风险，不能继续放行。

数据库补充调查结果：

- 仅 1 个重载；完整 identity signature 与上表一致。
- owner：`postgres`；语言：PL/pgSQL；`SECURITY DEFINER`；`search_path = public`。
- 部署前 EXECUTE：`anon/authenticated/service_role/postgres = true/true/true/true`。
- 补充阻断后 EXECUTE：`false/true/true/true`，收回 anon 和 public 默认执行权。
- 其他数据库函数调用方：0。
- 当前页面、API、Edge Function和非文档脚本直接调用方：0。
- `scripts/sync-personal-cash-linkage.zsh` 只消费历史 pending outbox，不调用创建 RPC；阻断新建不影响已有历史同步/审计。

Git历史确认：该路径在 2026-06-13 的 Phase 2 中建立；2026-06-15 commit `ae2849a` 删除 `createPersonalCashTuitionIncome(...)` API wrapper和页面入口。`docs/current-status.md` 明确标记它已被 `createCashSystemIncome(...)` → `request-cash-income-confirmation` 的现行 pending income/Cash approve-reject流程取代。现库共有4条非 `student_tuition_bill` 的遗留关联记录，最后一条创建于2026-06-27；函数调用统计未开启，但当前代码/数据库依赖均为0。综合定义、现行文档、代码和历史，判定该创建 RPC 已废弃，不是当前正常业务必需入口，故已纳入 R0 fail-closed；历史数据和outbox消费者均未修改。

### 4.3 仓库/API入口

- `js/api/income-api.js`：`previewStudentTuitionBill`、`generateStudentTuitionBill`、`createStudentTuitionBillIncomeRecord`。
- `js/pages/income-page.js`：预览入口；旧正式生成序列已从页面模块移除，正式按钮固定禁用。
- 页面模块未发现 Supabase `.rpc()` 或直接 insert/update/delete/upsert。
- 为防止旧 API、直接 RPC 或直接表写绕过，最终权威阻断位于 DB 函数和表级 trigger，而不是页面。

## 5. 所有学费Cash入口清单

- 收入列表单条提交：`js/pages/income-page.js` → API → `request-cash-income-confirmation`。
- 收入列表批量提交：同一 Edge Function；R0 页面禁选 `student_tuition_bill`。
- 收入详情单条提交：`js/pages/income-detail-page.js` → API → 同一 Edge Function。
- Edge existing-income 分支：查询 School income 后，原调用 `school_request_cash_income_confirmation_for_record(...)`，再调用 Cash `home_create_external_transaction_request(...)`。
- School linkage RPC：`school_request_cash_income_confirmation_for_record(...)`。
- `sync-cash-request-result` 是 Cash 回调，不是提交入口。
- 遗留同步脚本只读取已 received 的个人 tuition linkage，不提交 pending `student_tuition_bill`。
- `request-cash-part-time-income-confirmation` 是外部授课收入链路，与本阶段目标无关。

R0 后，已知 `student_tuition_bill` pending 收入的页面、Edge 和 School linkage 三层入口均在任何 Cash DB 写请求之前拒绝。

## 6. R0实现

1. 新增 DB 权威表 `public.school_feature_gates`，固定三个 key：
   - `student_tuition_preview = validation_preview_only`
   - `student_tuition_generate = blocked`
   - `student_tuition_cash_submit = blocked`
2. 新增 `school_require_feature_gate_state(...)`；gate 缺失、读取异常、状态不符均 fail-closed。
3. 将两个正式生成重载、bill→income和遗留 personal Cash tuition received/outbox RPC替换为先 gate 拒绝的 R0 stub，保持全部现有签名和返回结构。
4. 在账单、`student_tuition_bill` income、对应 linkage 三类表上增加 mutation guard，阻断直接表写绕过。
5. 预览 RPC 首行检查 `validation_preview_only`，其余旧候选逻辑不修复、不改变。
6. Edge Function 在 existing-income 查询得到 `source_type` 后，对 `student_tuition_bill` 读取 Cash gate，并在 Cash账户查询、School linkage RPC、Cash request RPC之前返回 423。
7. 页面固定禁用正式生成、学费 Cash 单条提交和批量选择，保留带明确提示的验证预览。
8. 新增 2026-08 七名学生全量只读审计 SQL；未增加日期字段、未回填数据。
9. 补充审查确认遗留 personal Cash tuition RPC 已废弃后，将其纳入同一 `student_tuition_generate` gate；收回 anon执行权，不删除函数、不改历史记录或outbox消费者。

## 7. 数据库部署结果

实际按顺序在 School DB 执行：

1. `sql/current/school_tuition_r0_feature_gate_schema.sql`
2. `sql/current/school_tuition_r0_feature_gate_state.sql`
3. `sql/current/school_tuition_r0_fail_closed_rpcs.sql`
4. `sql/current/school_student_tuition_bill_preview_rpc.sql`
5. `sql/current/school_tuition_r0_august_2026_baseline_readonly.sql`（SELECT-only审计）

部署/修改对象：

- 表：`public.school_feature_gates`
- 函数：`school_require_feature_gate_state(...)`
- 函数：两个 `school_generate_student_tuition_bill` 重载
- 函数：`school_create_student_tuition_bill_income_record(...)`
- 函数：`school_create_personal_cash_tuition_income_record(...)`（补充审查后同一 SQL 文件再次部署）
- 函数：`school_preview_student_tuition_bill(...)`
- 函数：`school_guard_r0_tuition_business_mutation()`
- trigger：账单、学费income、学费linkage mutation guard，共 3 个，均 enabled。

仅 School DB 的 schema/function/trigger 定义和 3 条 gate 配置行发生写入；School/Cash 业务记录没有写入。Cash DB 没有执行 DDL、RPC 或写操作。

## 8. Edge Function部署结果

- Function：`request-cash-income-confirmation`
- 状态：`ACTIVE`
- 版本：9（不是页面资源版本号；附件禁止的是前端版本号使用 v9.x）
- `verify_jwt = true`
- SHA-256：`cc0a0c2aea7a649618f55ce5778a456bc044a014efd271a800d524b86c6b2305`
- 部署后的 `supabase functions list` 再次确认上述状态。

Edge 只对 existing income 且 `source_type = student_tuition_bill` 增加 gate；普通收入的原路径未改写。没有用普通收入执行成功写入测试，因为附件禁止创建真实 Cash request/transaction。

## 9. 页面辅助阻断

- “生成应收”改为“学费整改验证预览”。
- 弹窗标题和说明明确：`validation_preview_only`、不可生成正式账单或收入。
- 正式提交按钮 HTML 和 JS 双重固定 disabled；点击只显示维护提示。
- 学费 pending income 的单条 Cash 提交不可用。
- 学费 pending income 的批量 checkbox 不可选，并显示整改原因。
- 非学费 Cash 判断和按钮未被统一禁用。
- 前端资源版本使用 `v10.4.0-tuition-r0-fail-closed`，未使用 v9.x。
- `js/legacy-core.js`、`docs/ui/`、durationHours、保存后月份逻辑均未修改。

说明：附件同时禁止 commit/push，因此页面变更仅在当前工作区；线上 GitHub Pages 仍是旧页面。权威 DB/Edge 阻断已实际部署，不依赖页面上线。

## 10. Gate权限验证

| 验收项 | 结果 |
|---|---|
| anon 修改 gate | `has_table_privilege(..., 'INSERT,UPDATE,DELETE') = false` |
| authenticated 修改 gate | `false` |
| gate 缺失 | helper 返回 `TUITION_GENERATION_BLOCKED` |
| gate 状态未知/不符合 | helper 返回 `TUITION_GENERATION_BLOCKED` |
| gate 读取失败 | 函数定义的 `EXCEPTION WHEN OTHERS` 明确转为指定 blocked code；未通过破坏 gate 表做故障注入 |
| 普通页面解除功能 | 不存在 |
| R0 enabled切换 | 不实现；state constraint 仅允许本阶段的 blocked/validation 状态 |
| 遗留personal Cash tuition RPC的anon EXECUTE | 补充部署前 `true`，补充部署后 `false`；authenticated/service_role保留调用权但调用后端立即被gate拒绝 |

## 11. 旧生成RPC直接调用验证

零写入参数验证结果：

| RPC | 结果 |
|---|---|
| `school_generate_student_tuition_bill(uuid,text,text)` | `TUITION_GENERATION_BLOCKED` |
| `school_generate_student_tuition_bill(uuid,text,numeric,text)` | `TUITION_GENERATION_BLOCKED` |
| `school_create_student_tuition_bill_income_record(uuid,date,text)` | `TUITION_GENERATION_BLOCKED` |
| `school_create_personal_cash_tuition_income_record(...)` | `TUITION_GENERATION_BLOCKED`；以6个必填参数全部为NULL直接调用，证明在日期/学生/金额校验和任何写入前拒绝 |

同时验证 gate 缺失和不匹配状态均 fail-closed。遗留 RPC 部署后 owner仍为 `postgres`、签名/默认值/返回结构不变，定义哈希为 `10c7d5d3c98081cb46eb52eac200679e`，新定义包含 gate 且不含 `INSERT`。调用前后 bill 9、School income 42、两类outbox/linkage、lesson 625、School账户流水及Cash request/transaction相关哈希不变；没有 draft、中间记录、状态改变或业务写入。

未对真实账单执行 no-op UPDATE 来动态触发直接表 guard，因为这仍属于对真实业务行的写操作，超出附件零业务写入边界；表级 trigger 的存在、enabled 状态和函数定义已做静态/目录验证。

## 12. 预览只读验证

- gate：`student_tuition_preview = validation_preview_only`。
- 孙陈锋 2026-08，旧 RPC 实际返回：2 条、4 小时、JPY 34,000、CNY 1,700；这与附件预估的 24 条不同，已按要求记录“旧RPC实际结果”。
- 张倬闻 2026-07：返回“该学生月份已生成收入记录，不能重复生成学费应收”；可作为事故验证证据，但不能得到金额预览，也未生成任何数据。
- 张倬闻 2026-08：保持“没有可生成学费应收的正式预定课时”的现状。
- 陈加恩 2026-08：候选聚合层仍错误汇总 12 条、24 小时、JPY 216,000，因为旧查询只按学生当前业务归属和 `year_month` 过滤，未排除已入账单的课时；RPC 随后因已有 `income_created` 账单/received income 对外报“已生成收入记录”，所以不会返回预览结果。候选逻辑错误基线仍为12，canonical未收费候选为0。
- 本阶段没有修复旧预览逻辑。
- 预览前后 School/Cash 业务表行数、状态和哈希完全不变。

## 13. Cash提交阻断验证

固定测试 income：`bbd7e7fd-fa04-404b-91fc-ab894cca28c8`。

1. 直接调用 School `school_request_cash_income_confirmation_for_record(...)`，在写入 linkage 前返回 `TUITION_CASH_SUBMISSION_BLOCKED`。
2. 使用已登录 School 页面会话直接请求已部署 Edge Function，使用有效格式但不存在的 Cash account UUID，得到：
   - HTTP 423
   - `code = TUITION_CASH_SUBMISSION_BLOCKED`
   - `gate_state = blocked`
   - `release_version = r0-20260727`
3. 阻断发生在 Cash account 查询、School linkage 写 RPC 和 Cash request 写 RPC之前。
4. School linkage 仍为 35，Cash request 仍为 34，Cash交易仍为 CNY 59/JPY 31，income 仍为 pending，School账户流水仍为 185。

普通非学费分支的代码差异检查确认原执行路径未修改；因禁止真实成功写测试，未创建普通收入 Cash request 来做动态验证。

## 14. 业务数据零变化证明

基线算法：逐行 `md5(row_to_json(row)::text)`，按 `id` 排序拼接后再次 MD5。部署后结果与部署前逐项相同：

### 14.1 School DB

| 表 | 行数 | 部署前/后哈希 |
|---|---:|---|
| `school_account_transactions` | 185 | `f07bbb159bb5be3ad65e92ef9b2dcb78` |
| `school_income_records` | 42 | `28e03bcc9df232fb16308250d902951d` |
| `school_lesson_records` | 625 | `2c63eea124ba003d60c59fa364884ff8` |
| `school_personal_cash_income_linkage_events` | 35 | `d11738a87e8d8f7587dcca1ac383cec3` |
| `school_personal_cash_linkage_events` | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| `school_student_monthly_settlements` | 15 | `a1eced5c3a3606c421480abc95881062` |
| `school_student_tuition_bills` | 9 | `673a4c2f14987099d2fb483d48f62da3` |
| `school_teacher_wage_lock_details` | 556 | `1fdffb6ec83e114b7049deee8ea5cd7e` |
| `school_teacher_wage_locks` | 95 | `ff121f7230a26f90d49decf9953b0292` |

### 14.2 Cash DB

| 表 | 行数 | 部署前/后哈希 |
|---|---:|---|
| `home_cny_transactions` | 59 | `e09234624c09f620c95cd5a1328cf2c7` |
| `home_external_transaction_requests` | 34 | `6ccb044573be3c41b0192bc3336116de` |
| `home_jpy_transactions` | 31 | `ca7cf3d0697ce60cf203d16bddc1f5fd` |

补充部署前后重点结果同样完全一致：School income 42 / `28e03bcc9df232fb16308250d902951d`，personal Cash income outbox 35 / `d11738a87e8d8f7587dcca1ac383cec3`，旧payment outbox 0 / `d41d8cd98f00b204e9800998ecf8427e`，School账户流水185 / `f07bbb159bb5be3ad65e92ef9b2dcb78`，Cash request 34 / `6ccb044573be3c41b0192bc3336116de`，CNY/JPY transaction 59/31且哈希不变。动态调用没有创建income、outbox、中间记录、Cash request/transaction或账户流水。

张倬闻四条事故记录哈希与第 3 节完全一致；孙陈锋两条跨月课的关键字段和行哈希也保持基线。唯一数据写入是新增的 3 条 feature gate 系统配置以及函数/权限定义部署，不属于学生/课时/账单/收入/Cash/流水/actual/工资业务记录。

## 15. 8月全体学生收费候选基线

“8月记录”按当前 `year_month = 2026-08`；“旧RPC候选”保持现有错误逻辑；“审计后未正式计费”仅是只读分类，不是本阶段修复结果。

| 学生 | 状态 | 8月记录总量 | 时长 | JPY | 旧RPC当前候选 | 审计后未正式计费 | 主要异常 |
|---|---|---:|---:|---:|---|---|---|
| 厦门吕同学 | paused | 0 | 0h | 0 | 0 | 0 | 无8月记录 |
| 孙陈锋 | active | 24 | 48h | 408,000 | 2 / 4h / 34,000 | 22 / 44h / 374,000 | 22条业务归属不符；2条跨月课已在7月Cash synced；2条月份漂移 |
| 张倬闻 | active | 30 | 65h | 650,000 | 0（RPC报无候选） | 30 / 65h / 650,000 | 30条业务归属不符；另有7月重复账单事故 |
| 彭宇晗 | active | 0 | 0h | 0 | 0 | 0 | 无8月记录 |
| 李天伦 | active | 0 | 0h | 0 | 0 | 0 | 无8月记录 |
| 陈加恩 | active | 12 | 24h | 216,000 | 候选聚合错误纳入12；RPC随后因已有income报错 | 0 | 账单 `1b546782-1b39-4c73-a85d-27ab1e5086ad`、income `cdf3da68-e578-4f1b-b759-2fff394e1906` 已 received/Cash synced；canonical关系建立后正确未收费候选必须为0 |
| 陈红卓 | active | 0 | 0h | 0 | 0 | 0 | 无8月记录 |

全体 7 人均无 2026-08 monthly settlement。当前 66 条 8月 planned 中，没有 actual 或工资锁关系。

## 16. 新日期字段回填分类

本阶段没有新增 `week_start_date` 或 `scheduled_lesson_date`，也没有回填。对 66 条8月 planned 的只读证据分类：

| 分类 | 数量 | 说明 |
|---|---:|---|
| 高置信度，可从 batch 原始周一证据推导 | 52 | 张倬闻 30 + 孙陈锋 22；业务归属迁移不等于日期字段回填 |
| 已正式计费，可由 bill/batch 组合取证 | 12 | 陈加恩 12；仍需 R1/R2 设计确定权威字段和来源 |
| 证据冲突/人工确认/不属于8月收费 | 2 | 孙陈锋 8月1日、2日跨月课，已进入7月正式链 |

未来新字段当前不存在，因此 66 条均没有新字段值。后续字段应先允许 NULL；新写 RPC 返回权威值；NULL 候选 fail-closed；在全库审计完成前不得对 planned 增加全局 NOT NULL；actual 不得用 scheduled_lesson_date 代替真实日期。

## 17. 修改文件

修改：

- `income.html`
- `js/pages/income-detail-page.js`
- `js/pages/income-page.js`
- `sql/current/school_student_tuition_bill_preview_rpc.sql`
- `supabase/functions/request-cash-income-confirmation/index.ts`

新增：

- `sql/current/school_tuition_r0_august_2026_baseline_readonly.sql`
- `sql/current/school_tuition_r0_fail_closed_rpcs.sql`
- `sql/current/school_tuition_r0_feature_gate_schema.sql`
- `sql/current/school_tuition_r0_feature_gate_state.sql`
- `docs/school-v2-r0-tuition-fail-closed-report-20260727.md`

## 18. Git diff和状态

最终 `git diff --stat`：

```text
 income.html                                        | 10 ++--
 js/pages/income-detail-page.js                     |  7 +++
 js/pages/income-page.js                            | 67 ++++------------------
 .../school_student_tuition_bill_preview_rpc.sql    | 11 +++-
 .../request-cash-income-confirmation/index.ts      | 37 +++++++++++-
 5 files changed, 68 insertions(+), 64 deletions(-)
```

新文件未暂存，因此标准 `git diff --stat` 不显示它们；新文件行数为：审计 SQL 192、fail-closed RPC SQL 355、gate schema SQL 38、gate state SQL 52、本报告 397。

最终 `git status --short`：

```text
 M income.html
 M js/pages/income-detail-page.js
 M js/pages/income-page.js
 M sql/current/school_student_tuition_bill_preview_rpc.sql
 M supabase/functions/request-cash-income-confirmation/index.ts
?? docs/school-v2-r0-tuition-fail-closed-report-20260727.md
?? sql/current/school_tuition_r0_august_2026_baseline_readonly.sql
?? sql/current/school_tuition_r0_fail_closed_rpcs.sql
?? sql/current/school_tuition_r0_feature_gate_schema.sql
?? sql/current/school_tuition_r0_feature_gate_state.sql
```

未执行 `git add`、commit 或 push。当前 HEAD 保持 `c180690`。

## 19. 未确认事项

1. Final Design v1.1 正文未在附件或仓库中找到，需要业务负责人/ChatGPT审查时补充比对。
2. gate“读取失败”通过函数异常分支静态验证，没有故意破坏生产 gate 表做 fault injection。
3. 普通非学费 Cash 路径通过代码差异确认未改，未用真实业务数据执行成功写入测试。
4. 页面变更尚未上线，这是“不 commit、不 push”的必然结果；DB 和 Edge 权威阻断已经上线。

## 20. 下一阶段建议

当前 R0 已使正式学费账单/收入生成链和 `student_tuition_bill` pending→Cash 链处于安全 fail-closed 状态，因此具备继续准备事故隔离和三层唯一约束的安全前置条件；但不能自动开始 R1。

开始前至少需要：

1. 业务负责人和 ChatGPT 审查本报告与工作区 diff，并补充/确认 Final Design v1.1 正文。
2. 明确张倬闻事故隔离目标状态和不可逆边界。
3. 明确三层唯一约束的 billing identity、bill↔lesson 规范关系、bill↔income 1:1 设计及历史 9 张账单迁移策略。
4. 明确孙陈锋两条跨月课和 52 条业务归属异常的证据归属；不得在 R1 中顺带修复。
5. 继续保持三个 gate 当前状态，直到下一阶段验收通过；不得先解除 gate。遗留 personal Cash tuition 创建 RPC 已归入 generate gate，不再作为待放行入口。

## 21. Git命令

审查通过后精确暂存命令：

```bash
git add income.html js/pages/income-detail-page.js js/pages/income-page.js sql/current/school_student_tuition_bill_preview_rpc.sql supabase/functions/request-cash-income-confirmation/index.ts sql/current/school_tuition_r0_august_2026_baseline_readonly.sql sql/current/school_tuition_r0_fail_closed_rpcs.sql sql/current/school_tuition_r0_feature_gate_schema.sql sql/current/school_tuition_r0_feature_gate_state.sql docs/school-v2-r0-tuition-fail-closed-report-20260727.md
```

建议 commit message：

```text
feat: fail closed tuition billing for R0
```

审查并 commit 后的 push 命令：

```bash
git push origin main
```

建议业务负责人批准 commit：**有条件建议**。条件是核对 Final Design v1.1 正文、审查遗留 personal Cash tuition RPC 的补充阻断证据，并接受页面须在 commit/push 后才上线。当前阶段严格未自行执行这些 Git 命令。

## 22. 最终结论

- 已知学费专用生成入口：**没有可绕过 R0 gate 的已知入口**；两个正式生成重载、bill→income、遗留 personal Cash tuition received/outbox RPC及正式链直接表写均被 DB fail-closed。普通非学费专用的收入功能未被本补充任务扩大修改。
- 已知 `student_tuition_bill` pending 提交 Cash 入口：**没有可绕过 R0 gate 的已知入口**；页面、Edge、School linkage/表写均阻断，Edge 实测 423。
- 学费预览：**仍为只读 `validation_preview_only`**，旧错误候选逻辑未修复。
- R0 是否修改业务记录：**否**。仅写入 3 条 gate 系统配置并部署 schema/function/trigger/Edge 定义。
- 张倬闻事故记录：**保持原样**，四条关键哈希完全一致。
- 孙陈锋两条跨月课：**保持原样**，关键字段和哈希完全一致。
- 8月全体学生当前候选：见第 15 节；候选聚合基线分别为 0、2、0、0、0、12、0，且必须结合全量审计异常理解，不能用于正式生成。陈加恩12条/24小时/JPY216,000已全部进入received/Cash synced正式链，canonical正确未收费候选必须为0。
- 下一阶段：**可以安全准备，但不能未经新授权直接实施**事故隔离和三层唯一约束。
- 文件：已修改/新增 10 个目标文件。
- SQL/RPC：已执行第 7 节 5 个 SQL 文件，其中补充审查后再次部署 `school_tuition_r0_fail_closed_rpcs.sql`；调用过生成两重载、bill→income、遗留personal Cash tuition RPC、preview、Cash linkage和gate helper验证。
- 数据库写入：仅 School schema/function/trigger 与 3 条 gate 配置；Cash DB 零写入；业务数据零写入。
- 测试白名单：没有业务成功写测试，因此无白名单业务写入和无新增测试记录；测试使用固定事故 income ID和无效业务对象/有效格式 dummy UUID，并在写入前阻断。
- commit/push：均未执行；无新 commit hash；HEAD 仍为 `c180690`。
- 工作流状态：R0 授权范围已完成，已按要求停止在审查点，等待业务负责人和 ChatGPT 审查。
