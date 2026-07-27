# School V2 R1A收费身份结构与历史回填模拟实施报告

报告日期：2026-07-27（Asia/Tokyo）

## 1. 结论

| 验收问题 | 结论 |
|---|---|
| 1. incident隔离结构是否已安全准备？ | 是。加法型字段、FK、status扩展、严格双向一致check、partial index及仅对`OLD.status = incident_quarantined`生效的不可变trigger已部署。 |
| 2. 当前42条income是否保持原样？ | 是。原业务列、状态、行数及业务哈希前后相同；新增incident字段/`tuition_bill_id`均为NULL，两个新增boolean均为false。 |
| 3. 9张bill是否保持原样？ | 是。原业务列、状态、行数及业务哈希前后相同。 |
| 4. identity表是否为空？ | 是，0行。 |
| 5. bill lessons表是否为空？ | 是，0行。 |
| 6. billing_role是否仍全部为NULL？ | 是，9/9为NULL。 |
| 7. 是否得到准确7/1/1分类？ | 是：7 canonical、1 incident、1 legacy，未分类0。 |
| 8. 是否得到准确85/24/12关系？ | 是：85 canonical、24 incident、12 legacy，总计121。 |
| 9. 张倬闻24条incident是否全部有canonical？ | 是，缺失0。 |
| 10. 陈加恩12条legacy是否全部有canonical？ | 是，缺失0。 |
| 11. 9/9 bill-income是否可以安全建立1:1？ | 是，9条均精确互指；一bill多income和一income多bill均为0。 |
| 12. R0是否仍然完全有效？ | 是。三个gate不变；四个生成入口与学费Cash提交入口动态复验均返回BLOCKED。 |
| 13. 是否可以进入下一阶段正式事故隔离和历史回填？ | 可以提交审查并进入下一阶段；下一阶段仍须保持R0 gate关闭，并以本报告第13节的固定输入和顺序执行。 |

本阶段只部署School DB加法型结构，没有执行正式历史回填，没有修改任何既有业务记录，没有连接前端正式生成逻辑，没有commit或push。

## 2. Git、环境与R0基线

- 分支：`main`
- 开始HEAD：`4464e9ef237e17109cad2ed28b34d3d1078b9162`
- `origin/main`：`4464e9ef237e17109cad2ed28b34d3d1078b9162`
- 开始工作区：clean
- School/Cash连接变量通过`load_both_db`加载；未输出、保存或提交任何连接串或密钥。
- `psql`：可用。
- 三个gate部署后仍为：
  - `student_tuition_preview = validation_preview_only`
  - `student_tuition_generate = blocked`
  - `student_tuition_cash_submit = blocked`
- release version均为`r0-20260727`。

## 3. 本阶段工作区文件

新增：

- `sql/current/school_tuition_r1a_incident_income_schema.sql`
- `sql/current/school_tuition_r1a_bill_role_schema.sql`
- `sql/current/school_tuition_r1a_billing_identity_schema.sql`
- `sql/current/school_tuition_r1a_bill_lessons_schema.sql`
- `sql/current/school_tuition_r1a_bill_income_1to1_schema.sql`
- `sql/current/school_tuition_r1a_immutable_guards.sql`
- `sql/current/school_tuition_r1a_business_baseline_readonly.sql`
- `sql/current/cash_tuition_r1a_business_baseline_readonly.sql`
- `sql/current/school_tuition_r1a_historical_backfill_readonly.sql`
- `sql/current/school_tuition_r1a_postdeploy_readonly.sql`
- 本报告

修改：

- `docs/current-status.md`

未修改学费页面、正式生成RPC、Cash Edge Function、lesson页面、durationHours、week/date字段、52条迁移或R0 gate状态。

## 4. 实际部署对象

### 4.1 `school_income_records`

新增列：

- `status_before_quarantine text NULL`
- `incident_type text NULL`
- `incident_canonical_income_id uuid NULL`
- `incident_canonical_bill_id uuid NULL`
- `incident_duplicate_bill_id uuid NULL`
- `incident_quarantined_at timestamptz NULL`
- `incident_quarantined_by text NULL`
- `incident_reason text NULL`
- `cash_submission_blocked boolean NOT NULL DEFAULT false`
- `operational_excluded boolean NOT NULL DEFAULT false`
- `tuition_bill_id uuid NULL`

部署的保护：

- status check保留全部既有合法值并增加`incident_quarantined`。
- 三个incident引用FK分别指向canonical income、canonical bill和duplicate bill，均`ON DELETE RESTRICT`。
- `tuition_bill_id`单向FK到bill，`ON DELETE RESTRICT`。
- `tuition_bill_id IS NOT NULL`的partial unique index已部署；当前42行均为NULL，不要求历史立即满足。
- incident字段非空白check和严格双向一致check已部署：`incident_quarantined`必须同时具有原状态、事故类型、canonical income/bill、duplicate bill、时间/操作人/原因及两个true阻断标志；任何其他status必须使上述字段全部NULL且两个标志均为false。
- `school_incident_quarantined_income_immutable` trigger已启用；函数仅在`OLD.status = 'incident_quarantined'`时拒绝UPDATE/DELETE，当前pending/received/cancelled/reversed不受该trigger影响。
- 没有创建通用事故隔离RPC。

### 4.2 `school_student_tuition_bills`

新增列：

- `billing_role text NULL`
- `incident_locked_at timestamptz NULL`
- `incident_reason text NULL`
- `cash_submission_blocked boolean NOT NULL DEFAULT false`

部署的check只允许非NULL角色为：

- `canonical_charge`
- `incident_duplicate`
- `legacy_cancelled`

没有要求9张历史bill立即非NULL，没有自动分类trigger，没有按status自动决定角色。部署后9张bill的`billing_role`仍全部为NULL。

### 4.3 永久billing identity空表

已创建`public.school_student_tuition_billing_identities`：

- PK及UUID默认值；
- `student_id` FK，`ON DELETE RESTRICT`；
- `canonical_bill_id`单向FK，`ON DELETE RESTRICT`；
- `UNIQUE(student_id, billing_month)`；
- `UNIQUE(canonical_bill_id)`；
- `UNIQUE(creation_idempotency_key)`；
- 月份格式、idempotency key/created_by非空白check；
- `source`只允许`historical_backfill`或`atomic_charge`；
- 不可UPDATE/DELETE trigger；
- `public`无SELECT/INSERT/UPDATE/DELETE；
- `anon`无SELECT/INSERT/UPDATE/DELETE；
- `authenticated`无SELECT/INSERT/UPDATE/DELETE；
- `service_role`仅SELECT/INSERT，明确撤销UPDATE/DELETE；
- 以后页面读取必须通过受控只读RPC，不直接读取基础表；
- 当前0行。

### 4.4 规范化账单课时空表

已创建`public.school_student_tuition_bill_lessons`，包含任务要求的全部字段。

关键结构：

- bill FK和planned lesson FK均`ON DELETE RESTRICT`；
- `UNIQUE(tuition_bill_id, planned_lesson_id)`；
- `UNIQUE(tuition_bill_id, line_no)`；
- relation role固定为三种bill角色；
- canonical partial unique `planned_lesson_id`；
- incident/legacy可与canonical使用相同planned lesson；
- `week_start_date_snapshot`和`scheduled_lesson_date_snapshot`允许NULL；
- 不可UPDATE/DELETE trigger；
- `public`无SELECT/INSERT/UPDATE/DELETE；
- `anon`无SELECT/INSERT/UPDATE/DELETE；
- `authenticated`无SELECT/INSERT/UPDATE/DELETE；
- `service_role`仅SELECT/INSERT；
- 以后页面读取必须通过受控只读RPC，不直接读取基础表；
- 当前0行。

### 4.5 触发器和函数

已部署并启用：

- `school_guard_tuition_identity_or_lesson_immutable()`
- `school_guard_incident_quarantined_income_immutable()`
- `school_tuition_billing_identities_immutable`
- `school_tuition_bill_lessons_immutable`
- `school_incident_quarantined_income_immutable`

R0原有三个mutation guard trigger仍全部为enabled：

- `school_r0_tuition_bill_mutation_guard`
- `school_r0_tuition_income_mutation_guard`
- `school_r0_tuition_cash_linkage_mutation_guard`

## 5. 本阶段明确未部署的对象

以下仅保留为下一阶段启用顺序，不在R1A部署：

- identity与`billing_role = canonical_charge`的双向一致性constraint trigger；
- 要求每张canonical bill必须有identity的强制约束；
- 要求所有历史bill必须有normalized lesson关系的强制约束；
- bill/income立即双向非NULL的强约束；
- 正式历史回填SQL/RPC；
- 事故隔离RPC；
- 原子生成RPC；
- operational/incident读取切换；
- 任何feature gate解除。

## 6. 业务数据零变化

哈希算法逐行转换为JSONB、按ID稳定排序后聚合MD5。income/bill哈希明确排除本阶段新增列，因此比较的是原业务列。

### 6.1 School DB

| 表 | 行数 | 部署前哈希 | 部署后哈希 | 结果 |
|---|---:|---|---|---|
| `school_income_records` | 42 | `b00238c330e8ab5ef7a51eb2fd281d4f` | `b00238c330e8ab5ef7a51eb2fd281d4f` | 相同 |
| `school_student_tuition_bills` | 9 | `9ee93472fdac490897b8b837b174bbaa` | `9ee93472fdac490897b8b837b174bbaa` | 相同 |
| `school_account_transactions` | 185 | `8f4f6c4365035f6c36bac59ba986b28b` | `8f4f6c4365035f6c36bac59ba986b28b` | 相同 |
| `school_lesson_records` | 625 | `313cff5314d78adf6c02497d0cc0097f` | `313cff5314d78adf6c02497d0cc0097f` | 相同 |
| `school_personal_cash_income_linkage_events` | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` | `6e76a4dc2fc2954b28b7ad0a8d203ba0` | 相同 |
| `school_student_monthly_settlements` | 15 | `7925cf3018bd0e669cd29710f6593238` | `7925cf3018bd0e669cd29710f6593238` | 相同 |
| `school_teacher_wage_locks` | 95 | `7bbe108d3ac73d4f21530793bf141bc6` | `7bbe108d3ac73d4f21530793bf141bc6` | 相同 |
| `school_teacher_wage_lock_details` | 556 | `6204dc666b3b8e0f64fac901ecf0686a` | `6204dc666b3b8e0f64fac901ecf0686a` | 相同 |

部署后income状态仍为：

- received 39
- pending 1
- cancelled 2
- incident_quarantined 0

新增income incident字段和`tuition_bill_id`非NULL数均为0；新增boolean为true的行数均为0。
42条非quarantine income中，任一incident字段非NULL或任一阻断标志为true的行数为0；全部通过双向一致check，且原业务值未改变。

### 6.2 Cash DB

Cash DB只读前后：

| 表 | 行数 | 部署前哈希 | 部署后哈希 | 结果 |
|---|---:|---|---|---|
| `home_external_transaction_requests` | 34 | `ba0571247a869843c3ddda9075ea78dd` | `ba0571247a869843c3ddda9075ea78dd` | 相同 |
| `home_cny_transactions` | 59 | `27dfd0cb3bf85c5cc34677372b29502a` | `27dfd0cb3bf85c5cc34677372b29502a` | 相同 |
| `home_jpy_transactions` | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` | `95ab7cf8a8d167e9b052d3fc6b64614b` | 相同 |

Cash DB没有执行DDL、RPC或DML。

## 7. 9张bill角色只读模拟

角色规则不是只看bill status：

- canonical必须同时具有received income、synced School linkage、approved Cash request及Cash transaction；
- incident必须是pending income，且其同一学生planned lesson集合与canonical完全相同；
- legacy必须是cancelled bill/income，且其同一学生planned lesson集合与canonical完全相同。

| 学生 | 月份 | Bill ID | Bill/Income状态 | Cash证据 | JSON课时 | 模拟角色 |
|---|---|---|---|---|---:|---|
| 孙陈锋 | 2026-07 | `2a9f1c25-a060-461e-ae10-b02295dec381` | income_created/received | synced、approved、transaction `c37665ea-e8bc-4b90-859c-292ef37c35eb` | 18 | canonical_charge |
| 张倬闻 | 2026-07 | `fdf3cdfe-f715-4814-b500-9ff2bfe77a63` | income_created/received | synced、approved、transaction `76267dae-5603-415d-b900-7b19502a813a` | 24 | canonical_charge |
| 张倬闻 | 2026-07 | `047dac2b-9484-4637-8e5e-9887857d121b` | income_created/pending | 无linkage/request/transaction；24个ID与canonical完全相同 | 24 | incident_duplicate |
| 彭宇晗 | 2026-07 | `2a0948e0-9015-4b18-848c-8c397e0bc2a0` | income_created/received | synced、approved、transaction `576bbce0-58c8-4f88-bcc1-e762c5d7f113` | 6 | canonical_charge |
| 李天伦 | 2026-07 | `07a02092-9503-47d1-9000-106f7e3de7e5` | income_created/received | synced、approved、transaction `f500dbe4-07a9-4a4d-ac99-e68592a8af6a` | 1 | canonical_charge |
| 陈加恩 | 2026-07 | `4109a4ec-1169-4d0b-965b-3e806b7e4c55` | cancelled/cancelled | 无linkage/request/transaction；12个ID与canonical完全相同 | 12 | legacy_cancelled |
| 陈加恩 | 2026-07 | `2608806a-283a-4919-a851-b25962f2c0b2` | income_created/received | synced、approved、transaction `0fdb968a-d37f-4430-9dc3-57c8ca020734` | 12 | canonical_charge |
| 陈加恩 | 2026-08 | `1b546782-1b39-4c73-a85d-27ab1e5086ad` | income_created/received | synced、approved、transaction `62719969-85d9-45d7-927f-a06fc1208660` | 12 | canonical_charge |
| 陈红卓 | 2026-07 | `7472f73f-fa19-4565-9180-a517c7151835` | income_created/received | synced、approved、transaction `b06cfd54-f374-4d3d-a0e5-2f93c92d0577` | 12 | canonical_charge |

汇总：canonical 7、incident 1、legacy 1、unclassified 0。

Cash DB只读复核确认7个approved request的`external_reference_id`均为对应School income，7个`created_transaction_id`均在Cash交易表存在。

## 8. Billing identity只读模拟

只为7张canonical bill生成模拟identity：

| 学生 | 月份 | Canonical Bill ID |
|---|---|---|
| 孙陈锋 | 2026-07 | `2a9f1c25-a060-461e-ae10-b02295dec381` |
| 张倬闻 | 2026-07 | `fdf3cdfe-f715-4814-b500-9ff2bfe77a63` |
| 彭宇晗 | 2026-07 | `2a0948e0-9015-4b18-848c-8c397e0bc2a0` |
| 李天伦 | 2026-07 | `07a02092-9503-47d1-9000-106f7e3de7e5` |
| 陈加恩 | 2026-07 | `2608806a-283a-4919-a851-b25962f2c0b2` |
| 陈加恩 | 2026-08 | `1b546782-1b39-4c73-a85d-27ab1e5086ad` |
| 陈红卓 | 2026-07 | `7472f73f-fa19-4565-9180-a517c7151835` |

固定输入：

- `source = historical_backfill`
- `creation_idempotency_key = historical_backfill:student_tuition:<student_id>:<billing_month>`
- evidence包含bill/income/linkage/request/transaction及角色判定依据。

验证：

- identity模拟数7；
- student+month重复0；
- canonical_bill_id重复0；
- incident/legacy identity数0。

## 9. 121条bill lesson关系只读模拟

`school_tuition_r1a_historical_backfill_readonly.sql`从9张bill的`source_snapshot.planned_lesson_ids`按JSON ordinality展开全部121行，并输出每一行的完整模拟snapshot。

置信度表达已在commit前加固：

- bill JSON中bill→planned lesson ID关系身份为`high`，记录在`source_snapshot.relationship_identity_confidence`；
- teacher、subject、lesson_count、duration、unit price、lesson fee来自当前planned源行，只能作为`medium`历史字段证据；
- 行级`attribution_confidence = medium`；
- `source_snapshot.current_source_field_confidence = medium`；
- `source_snapshot.bill_aggregate_verified = true`；
- `snapshot_source = bill_json_exact_id_plus_current_source_fields_aggregate_verified`；
- `historical_schedule_dates_available = false`。

汇总：

- canonical_charge：85
- incident_duplicate：24
- legacy_cancelled：12
- 总计：121

验证：

- canonical planned lesson全局重复：0
- 张倬闻incident无canonical：0
- 陈加恩legacy无canonical：0
- planned lesson孤儿：0
- bill内line_no重复：0
- 9张bill的关系数量、duration hours、JPY lesson fee与冻结bill汇总不一致：0

历史日期政策：

- 账单JSON没有逐课时历史计划日期或week start证据；
- `week_start_date_snapshot`全部模拟为NULL；
- `scheduled_lesson_date_snapshot`全部模拟为NULL；
- 不使用actual日期，不用当前planned日期伪造历史日期；
- 当前planned的日期仅放入`source_snapshot`证据，不进入两个历史日期snapshot列。

当前源与冻结bill差异单独保留：

- 学生差异：0行；
- 当前planned business entity与bill冻结business entity差异：42行：
  - 孙陈锋canonical bill 18行：bill为个人名义，当前planned为青空进学塾；
  - 张倬闻canonical bill 24行：bill为个人名义，当前planned为青空进学塾；
- `year_month`与bill billing month差异：2行，即孙陈锋两条既有跨月课：
  - `685ad45e-b5da-42ca-8f43-7732e8d6e40d`
  - `8b737b58-cd14-42c5-afd2-34730dcef963`

正式回填时：

- student/business entity/billing month snapshot必须使用bill冻结值；
- teacher/subject/count/duration/unit price/fee可使用本次验证通过的当前planned源值；
- 所有当前planned数值聚合与冻结bill相同；
- 上述42+2项差异只进入evidence，不覆盖bill，也不修改planned lesson。

## 10. 9/9 bill-income 1:1模拟

| Bill ID | Income ID | Income状态 |
|---|---|---|
| `2a9f1c25-a060-461e-ae10-b02295dec381` | `468ab75b-312e-4ba0-8d8d-8ae2f6ace00e` | received |
| `fdf3cdfe-f715-4814-b500-9ff2bfe77a63` | `f86ac9db-effd-402e-a320-1e4b6846a9c7` | received |
| `047dac2b-9484-4637-8e5e-9887857d121b` | `bbd7e7fd-fa04-404b-91fc-ab894cca28c8` | pending |
| `2a0948e0-9015-4b18-848c-8c397e0bc2a0` | `09fa4398-9d20-494b-8ab5-8f7c3cafa414` | received |
| `07a02092-9503-47d1-9000-106f7e3de7e5` | `91756564-c48d-4a1d-b6bc-88a041660e46` | received |
| `4109a4ec-1169-4d0b-965b-3e806b7e4c55` | `474f0fd2-71ca-4cce-9ba5-e615bd390151` | cancelled |
| `2608806a-283a-4919-a851-b25962f2c0b2` | `4a63f0ca-450f-4306-9e39-6d43172b3cf8` | received |
| `1b546782-1b39-4c73-a85d-27ab1e5086ad` | `cdf3da68-e578-4f1b-b759-2fff394e1906` | received |
| `7472f73f-fa19-4565-9180-a517c7151835` | `3a5542c5-5397-4688-999e-a08bb678f40d` | received |

9条全部满足：

- `bill.income_record_id = income.id`
- `income.source_type = student_tuition_bill`
- `income.source_id = bill.id`
- 每bill对应income数=1
- 每income被bill引用数=1
- 可安全回填`income.tuition_bill_id = bill.id`

本阶段没有执行该回填。

## 11. 张倬闻事故与陈加恩legacy结论

### 11.1 张倬闻

- canonical bill：`fdf3cdfe-f715-4814-b500-9ff2bfe77a63`
- canonical income：`f86ac9db-effd-402e-a320-1e4b6846a9c7`，仍为received
- incident bill：`047dac2b-9484-4637-8e5e-9887857d121b`
- incident income：`bbd7e7fd-fa04-404b-91fc-ab894cca28c8`，本阶段仍为pending
- 下一阶段目标状态：`incident_quarantined`
- 24个incident planned lesson均由canonical关系占用，缺失0。

### 11.2 陈加恩

- legacy bill：`4109a4ec-1169-4d0b-965b-3e806b7e4c55`
- legacy income：`474f0fd2-71ca-4cce-9ba5-e615bd390151`，仍为cancelled
- 对应canonical bill：`2608806a-283a-4919-a851-b25962f2c0b2`
- 12个legacy planned lesson均由canonical关系占用，缺失0。
- legacy不取得identity。
- legacy relation不参与canonical partial unique，不冲突。
- 正确2026-08未收费候选：0。

## 12. DDL、权限、rollback和R0验证

### 12.1 DDL rollback

正式部署前，将6个DDL/trigger文件置于单事务执行：

- 所有列、表、check、FK、index、grant及trigger均成功创建；
- 两张新表事务内均为0行；
- 最终`ROLLBACK`。

### 12.2 约束rollback测试

固定`codex-test-r1a-rollback`测试ID：

- identity：`a1000000-0000-4000-8000-202607270001`
- 被source check拒绝的identity：`a1000000-0000-4000-8000-202607270002`
- canonical relation：`a1000000-0000-4000-8000-202607270101`
- 被partial unique拒绝的重复canonical：`a1000000-0000-4000-8000-202607270102`
- 允许与canonical共用planned lesson的incident relation：`a1000000-0000-4000-8000-202607270103`
- temp incident probe：`a1000000-0000-4000-8000-202607270201`

结果：

- 非法identity `source = invalid_source`被check拒绝；
- identity UPDATE被不可变trigger拒绝；
- bill lesson UPDATE被不可变trigger拒绝；
- 第二条canonical使用同一planned lesson被partial unique拒绝；
- incident relation使用同一planned lesson成功；
- `OLD.status = incident_quarantined`的probe UPDATE被拒绝；
- 事务内identity 1行、relationship 2行；
- 最终ROLLBACK后两张正式新表均为0行。

没有执行白名单commit test，因为本阶段禁止正式历史数据插入，且空结构DDL不需要留下任何测试行。

### 12.3 Commit前DDL与权限加固

主体审查后追加执行限定范围加固：

- 重新执行`school_tuition_r1a_incident_income_schema.sql`，将incident状态约束改为严格双向一致；ADD CHECK实际扫描并接受现有42条income。
- 重新执行`school_tuition_r1a_billing_identity_schema.sql`，将source固定为`historical_backfill / atomic_charge`并重置ACL。
- 重新执行`school_tuition_r1a_bill_lessons_schema.sql`，重置ACL。
- 三文件先在同一事务内完整执行并ROLLBACK，随后正式部署。

最终`has_table_privilege`结果，两张新表完全相同：

| Role | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| public | false | false | false | false |
| anon | false | false | false | false |
| authenticated | false | false | false | false |
| service_role | true | true | false | false |

页面以后只能通过受控只读RPC读取，不直接开放基础表。

### 12.4 普通非学费income兼容

数据库实际定义中4个当前income创建函数均使用明确column list插入`school_income_records`：

- `school_create_cash_income_confirmation(...)`
- `school_create_income_record(...)`
- `school_create_part_time_work_income_record(...)`
- `school_create_pending_cash_income_record(...)`

因此新增nullable/default列不会改变参数位置或破坏INSERT。既有合法status全部继续允许；R1A没有切换普通收入读取或写入路径。

### 12.5 R0动态复验

以下调用均在写入前按预期失败：

- `school_generate_student_tuition_bill(uuid,text,text)` → `TUITION_GENERATION_BLOCKED`
- `school_generate_student_tuition_bill(uuid,text,numeric,text)` → `TUITION_GENERATION_BLOCKED`
- `school_create_student_tuition_bill_income_record(uuid,date,text)` → `TUITION_GENERATION_BLOCKED`
- `school_create_personal_cash_tuition_income_record(...)` → `TUITION_GENERATION_BLOCKED`
- `school_request_cash_income_confirmation_for_record(...)`，目标incident income `bbd7e7fd-fa04-404b-91fc-ab894cca28c8` → `TUITION_CASH_SUBMISSION_BLOCKED`

调用后School/Cash业务哈希仍完全相同。

### 12.6 静态检查

- 所有schema/trigger文件由PostgreSQL实际解析并执行成功；
- 所有只读文件仅包含SELECT；
- `git diff --check`通过；
- 未新增page模块`.rpc()`或直接表写；
- 未新增前端业务计算。

## 13. 下一阶段正式回填的精确输入与顺序

下一阶段必须继续保持三个R0 gate现状，并在单一受控事务内按以下顺序执行。

### 13.1 精确输入

1. Bill角色：第7节固定9个bill ID及角色。
2. Incident隔离：
   - income：`bbd7e7fd-fa04-404b-91fc-ab894cca28c8`
   - `status_before_quarantine = pending`
   - `status = incident_quarantined`
   - canonical income：`f86ac9db-effd-402e-a320-1e4b6846a9c7`
   - canonical bill：`fdf3cdfe-f715-4814-b500-9ff2bfe77a63`
   - duplicate bill：`047dac2b-9484-4637-8e5e-9887857d121b`
   - `cash_submission_blocked = true`
   - `operational_excluded = true`
   - incident type/reason/operator/time必须由下一阶段固定SQL/RPC写入并审计。
3. Identity：第8节7个student/month/canonical bill；固定source和idempotency key格式。
4. Bill lesson：`school_tuition_r1a_historical_backfill_readonly.sql`输出的121行：
   - 85 canonical、24 incident、12 legacy；
   - line_no使用bill JSON ordinality；
   - bill/student/business entity/billing month使用冻结bill；
   - 两个历史日期snapshot为NULL；
   - current source差异写入evidence，不覆盖历史。
5. Bill-income reverse FK：第10节9组固定映射。

### 13.2 精确启用顺序

1. 获取9张bill、9条income及121个JSON关系的行锁/一致性快照；复验R0 gate仍关闭。
2. 复验9/9互指、7/1/1、85/24/12、Cash证据和业务哈希；任一差异立即回滚。
3. 设置9张bill的`billing_role`；incident/legacy bill同时设置`cash_submission_blocked = true`及审计字段。
4. 将张倬闻duplicate income原子切换为`incident_quarantined`并一次性填写全部incident证据字段；canonical received income不变。
5. 插入7条identity。
6. 插入121条normalized bill lesson关系；不得伪造历史日期。
7. 回填9条income的`tuition_bill_id`，不修改`bill.income_record_id`、`source_type`或`source_id`。
8. 验证新表7/121、角色7/1/1、关系85/24/12、identity唯一、canonical lesson唯一及9/9双向关系。
9. 在上述回填通过后，另行部署并验证：
   - canonical bill ↔ identity一致性constraint trigger；
   - bill ↔ income双向一致性constraint trigger；
   - 只对已回填范围成立的NOT VALID/分阶段强约束，再执行VALIDATE。
10. 保持generate和cash_submit gate为blocked；不得在同一阶段解除。

## 14. 风险与审查点

1. 42条关系的当前planned业务归属与bill冻结归属不同，正式snapshot必须以bill为准。
2. 孙陈锋2条跨月lesson的`year_month`与bill月份不同；不得在回填中修改lesson或伪造schedule日期。
3. 历史JSON没有逐课时历史计划日期；两个日期snapshot必须为NULL。
4. 新表service_role只保留INSERT/SELECT，后续回填应使用受审查SQL/RPC；不可开放UPDATE/DELETE。
5. identity/bill及bill/income最终强一致性尚未启用，必须等正式回填成功后分阶段部署。
6. R0 gate必须持续关闭，直到后续原子生成和读取切换完成独立审查。

以上均不阻断提交R1A审查或进入下一阶段；它们是下一阶段必须保持的输入约束。

## 15. 实际执行的SQL与RPC

School DB正式执行：

1. `school_tuition_r1a_incident_income_schema.sql`
2. `school_tuition_r1a_bill_role_schema.sql`
3. `school_tuition_r1a_billing_identity_schema.sql`
4. `school_tuition_r1a_bill_lessons_schema.sql`
5. `school_tuition_r1a_bill_income_1to1_schema.sql`
6. `school_tuition_r1a_immutable_guards.sql`

主体审查后，incident income、identity和bill lessons三个schema再次经过单事务ROLLBACK验证并正式部署，用于双向一致约束、source枚举和ACL加固；表保持0行。

只读执行：

- `school_tuition_r1a_business_baseline_readonly.sql`（前/后）
- `cash_tuition_r1a_business_baseline_readonly.sql`（前/后）
- `school_tuition_r1a_historical_backfill_readonly.sql`（前/后）
- `school_tuition_r1a_postdeploy_readonly.sql`

测试执行：

- 6个DDL文件的合并事务rollback；
- `/private/tmp/school_tuition_r1a_constraint_rollback_test.sql`
- `/private/tmp/school_tuition_r1a_r0_gate_probe.sql`

调用RPC：第12.4节5个入口。所有调用均为阻断验证，没有成功业务写入。

## 16. Git交付

本阶段按要求没有执行`git add`、commit或push。

建议审查通过后的精确暂存命令：

```bash
git add \
  docs/current-status.md \
  docs/school-v2-r1a-tuition-identity-backfill-simulation-report-20260727.md \
  sql/current/cash_tuition_r1a_business_baseline_readonly.sql \
  sql/current/school_tuition_r1a_bill_income_1to1_schema.sql \
  sql/current/school_tuition_r1a_bill_lessons_schema.sql \
  sql/current/school_tuition_r1a_bill_role_schema.sql \
  sql/current/school_tuition_r1a_billing_identity_schema.sql \
  sql/current/school_tuition_r1a_business_baseline_readonly.sql \
  sql/current/school_tuition_r1a_historical_backfill_readonly.sql \
  sql/current/school_tuition_r1a_immutable_guards.sql \
  sql/current/school_tuition_r1a_incident_income_schema.sql \
  sql/current/school_tuition_r1a_postdeploy_readonly.sql
```

建议commit message：

```text
feat: prepare tuition billing identity schema for R1A
```

审查、暂存并commit后的push命令：

```bash
git push origin main
```

是否建议批准commit：**是**。前提是业务负责人和ChatGPT确认第7至14节的角色、历史证据政策与下一阶段输入。本报告完成后按R1A要求停止，不自行commit或push。

## 17. 本阶段最终状态

- 文件：新增11个目标文件，修改`docs/current-status.md`。
- 数据库结构写入：仅School DB的列、空表、约束、索引、权限、函数和trigger。
- Commit前加固写入：仅School DB的check约束和两张新空表ACL；无业务DML。
- 正式业务数据写入：无。
- rollback测试写入：仅固定`codex-test`行，全部回滚；最终测试残留0。
- 白名单commit写入：无。
- Cash DB写入：无。
- 正式历史回填：无。
- commit/push：均未执行。
- 工作流：R1A授权范围完成，停止等待业务负责人和ChatGPT审查。
