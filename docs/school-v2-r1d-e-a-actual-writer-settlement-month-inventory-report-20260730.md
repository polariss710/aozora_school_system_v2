# R1D-E-A-E planned 来源兼容与 legacy 边界勘误补证

日期：2026-07-30（Asia/Tokyo）
阶段：R1D-E-A-E，只读调查与既有 E-A 工件勘误
结论：`E_B_BLOCKED_UNTIL_PLANNED_WRITER_CUTOVER`；业务语义本身无新增待确认项，但 actual writer 不能先于 planned writer 权威字段切换。停在 E-A-E 勘误审查点，未进入 R1D-E-B/C/D。

## A. 执行结论

当前 actual writer、planned writer 与 settlement reader 均尚未完整切换到权威月份字段：

- 233 条 actual 的 `student_settlement_month` 全部为 NULL；
- ordinary/cancelled/partial 把旧 `year_month` 写为来源 planned 的 `year_month`；makeup 把旧 `year_month` 写为 actual 发生日月份；
- guarded actual edit 又统一把旧 `year_month` 重算为编辑后 actual 发生日月份；
- settlement summary、preview、lock、relock、draft adjustment、wage blocker、列表候选与详情均仍直接或间接按 lesson `year_month`；
- 仓库权威语义无冲突：所有来源 actual/cancel/partial/makeup 的学生结算月继承来源 planned，teacher settlement month 才按 actual occurred date；
- 279 条 fixed legacy planned 中仍有 `47` 条会在页面显示 ordinary/cancel 按钮、`12` 条会显示 same-month makeup 按钮并进入 open-credit 候选；actual writer 对 source NULL 直接 fail-closed 会中断这些现存流程；
- 单条、批量生成、导入、guarded edit 及 venue wrapper 共 8 个当前 planned writer 定义对五字段引用均为 0；新 planned 仍可继续以五字段全 NULL 写入；
- `school_planned_writer_commands` 当前为 0 行且没有函数引用，不能充当 cutover ledger；73 条 legacy 的 `created_at` 晚于首条五字段完整 planned，故技术时间戳不能区分合法 legacy NULL 与 cutover 后异常 NULL；
- 15 个 settlement snapshot 全部 locked，但 unlock/relock 代码会按 live old `year_month` 重算；当前均因 wage/adjustment/carryover至少一项而不能 unlock，仍不能把“现在被阻断”等同于永久冻结 basis；
- 正确顺序是先固定 legacy/cutover 证据并完成 planned writer 切换，再切 actual writer，最后切 reader。233 条 legacy actual 和 279 条 legacy planned 均不得在本阶段物理回填。

本阶段仅新增本报告与只读 SQL，没有修改任何 writer、reader、API、page、schema、R0 或历史数据。

## B. Git 基线与保护文件

- branch：`main`
- HEAD / `origin/main`：`0975122f1234c46a3659118ba5b114a051283918`
- 初始 staging / tracked diff：空
- 初始唯一未跟踪文件：`docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`
- 保护文件 SHA-256：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- 未读取、修改、移动或暂存保护文件正文。

## C. 数据库执行与回滚证据

- 目标：School DB；Cash DB 未连接。
- 第一次启动在 School DB 连接前失败：非交互 shell 未加载 `load_both_db`，随后空连接参数仅尝试本机 `/tmp/.s.PGSQL.5432` 并失败；未连接 School、未读取 SQL 文件、未开始事务，不计实际 School SQL 执行。
- 实际 School DB 连接：1 次；更新后 SQL 文件实际执行：1 次，`psql -X -v ON_ERROR_STOP=1 -f ...`。
- 事务：`REPEATABLE READ`、`READ ONLY = on`。
- SQL 错误：0。
- 业务 RPC 调用：0。
- DDL / DML / 临时表 / advisory lock / COMMIT：0。
- 数据库写入：0；白名单写入与测试 ID：不适用。
- 末尾输出 `ready_for_explicit_rollback = true`，随后明确输出 `ROLLBACK`；实际执行 exit code `0`。

执行文件：`sql/current/school_tuition_r1d_e_a_actual_writer_settlement_month_inventory_readonly.sql`。

## D. R0、candidate 与资金链权威边界

所有硬边界断言通过：

| 边界 | 结果 |
|---|---:|
| R0 | `validation_preview_only / blocked / blocked` |
| candidate function MD5 | `8981a2ce07abf8c28231bfaf05451368` |
| 完整 planned / legacy planned / partial bundle | `118 / 279 / 0` |
| candidate | `118 / 254小时 / JPY 2,474,000` |
| candidate UUID MD5 | `77f697f82e547d84dcabf88a3c868aa1` |
| candidate Manifest SHA-256 | `f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1` |
| legacy 279 UUID MD5 | `0975fdc91b533680e5ccc909f076ac62` |
| tuition bills | `9 / 0f0323b79e7ff1c47ff6b90c75477a2d` |
| income records | `42 / 2a4897b752f272b1f192045418b4940c` |
| bill lessons（B1-B新增列剔除后的旧投影） | `121 / 09dfee7d8833e09384fb41a84f2959e0` |
| historical exclusions | `42 / 680b6e5aaa718569aee4c36fe1cdc058` |

## E. 当前运营快照

运营数量只披露，不作为事故判断：

- lesson `630`：planned `397`，actual `233`；voided actual `0`；
- settlement snapshot `15`，全部 `locked`，月份范围 `2026-02` 至 `2026-06`；
- actual status：completed/billable `215`，cancelled/non-billable `2`，makeup_completed `16`（其中 9 non-billable、7 billable）。

## F. actual `student_settlement_month` 字段与分布

字段位于 `public.school_lesson_records.student_settlement_month`：

- 类型 `text`；nullable `YES`；无 default；
- 格式 CHECK：NULL 或 `YYYY-MM`；
- 普通部分索引：`(student_id, business_entity_id, student_settlement_month)`，仅非 NULL；
- S1-A overage context CHECK 另要求未来 overage snapshot 行的该字段非 NULL；
- actual 总数 `233`：NULL `233`，非 NULL `0`，非法格式 `0`。

R1D-B 报告明确该字段“允许planned和actual使用”，但阶段当时“不增加NOT NULL、自动default”；见 `docs/school-v2-r1d-b-date-and-billing-attribution-schema-report-20260728.md:121`。当前数据符合加法型兼容状态，不代表 writer 已切换。

## G. ordinary actual writer 完整调用链

### 总表

| 操作 | Page / API | 当前 DB canonical | 当前写入及月份来源 | 时长规则 | 锁/账单保护 | R1D-E-B归属 |
|---|---|---|---|---|---|---|
| ordinary actual | `lesson-page.js` → `createActualLessonFromPlanned` | `school_create_actual_lesson_from_planned` | INSERT actual；`year_month=planned.year_month`；teacher month=actual date；不写新字段 | `duration <> planned.duration` 拒绝 | source student old month、target teacher month lock；不检查 bill relation/JSON | 必须切换 |
| cancelled actual | page → `createCancelledActualLessonFromPlanned` | 独立 `school_create_cancelled_actual_lesson_from_planned` | `year_month=planned.year_month`；non-billable；不写新字段；source→pending_makeup | 正数；不要求等于 planned | source student old month、teacher month lock | 必须切换 |
| partial | ordinary dialog 的“部分完成”分支 → `createPartialCompletedActualFromPlanned` | 独立 `school_create_partial_completed_actual_from_planned` | `year_month=planned.year_month`；teacher month=actual date；source→pending_makeup；不写新字段 | `0 < duration < planned.duration` | source student old month、teacher month lock | 必须切换 |
| makeup | makeup/cross-month dialog → API canonical wrapper | `school_create_lesson_credit_makeup_actual` | `year_month=actual date month`；teacher month相同；non-billable；不写新字段 | 不超过 remaining credit | 当前错误地检查 actual-date student month；检查 teacher month | 必须切换 |
| legacy makeup RPC | 外部/旧调用者可直调 | 两个 compatibility RPC | 当前 catalog 是 wrapper，调用 lesson-credit canonical；忽略旧 fee/billable 参数 | canonical 规则 | canonical 规则 | 保持 wrapper，不得成为旁路 |

页面/API证据：

- `js/api/lesson-api.js:614-710` 映射 ordinary、cancelled、makeup、partial；cross-month API 在 `:693-695` 直接转发同一 makeup API；
- `js/pages/lesson-page.js:1885-1886` 在同一 ordinary dialog 内选择 partial/ordinary；cancelled、makeup、cross-month 分别位于 `:2181`、`:2439`、`:2833`；
- 页面未传 `student_settlement_month`，这是正确的边界方向：该值必须由 DB 从 locked source planned 继承。

数据库证据：

- ordinary 的不等时长拒绝在 `sql/current/school_create_actual_lesson_from_planned_rpc.sql:177-179`；INSERT 未列新字段且 `year_month=v_planned.year_month` 在 `:277-328`；

ordinary 与 cancelled 都是独立 SECURITY DEFINER 函数；cancelled 同样继承 source old month，并把 source 转为 `pending_makeup`。两者均未写新字段，也未检查 bill relation/JSON。

## H. partial completion writer 完整调用链

- partial 的小于规则、source/teacher lock 与写入在 `sql/current/school_lesson_credit_operations_rpcs.sql:274-358`；

partial 不是 ordinary 的参数模式，而是单独函数：首次完成必须短于 planned，INSERT completed actual 后把 source 置为 `pending_makeup`。它复制 source old `year_month`，但未复制新权威字段。

## I. makeup actual writer 完整调用链

- makeup 当前 `v_target_year_month=actual date month`，同时用于 student/teacher lock 与 INSERT，在同文件 `:166-199`；
- compatibility wrappers 在同文件 `:376-461`，current catalog MD5 为 `7f82002b...` / `e4ccad38...`，证明生效定义是 wrapper，而不是同名旧 SQL 文件中的历史直写正文；
- catalog MD5：ordinary `da156f6c...`、cancelled `12ed369b...`、partial `ec7bdebb...`、makeup canonical `eaad3fc1...`；四者 `student_settlement_month` 引用均为 0。

三类 writer 不共享一个底层 canonical：ordinary、cancelled、partial 是独立实现；makeup 的页面入口和两条 legacy 签名才统一到 lesson-credit canonical。

## J. actual 编辑、重算与其他旁路

| 入口 | 能否影响 actual | 当前行为/风险 | 结论 |
|---|---|---|---|
| shared edit dialog | 是 | `lesson-edit-dialog.js` → `updateLessonRecordGuarded` → `_with_venue` → core | 主要编辑旁路 |
| guarded core | 是 | 对 actual 日期编辑后把 `year_month=month(new lesson_date)`，不写/保持新字段；检查旧/新 old month settlement 和 teacher wage lock | 必须随 writer 一起切 |
| actual_minutes sync trigger | 是，但仅 minutes | INSERT/UPDATE 时同步 `actual_minutes`；不引用任何月份字段 | 不改 |
| schedule venue trigger | INSERT actual 时可能继承场地 | 不引用月份字段 | 不改 |
| updated_at trigger | 任意 UPDATE | 仅更新时间 | 不改 |
| actual_minutes backfill RPC | 是，仅 minutes | service_role-only；按 `coalesce(teacher_settlement_month,year_month)`选取并拒绝 student/wage lock | 不写学生月，但 student lock predicate应在后续一并审查 |
| planned import/batch | 否 | import 明确固定 INSERT `lesson_type='planned'`；不存在 actual import bypass | R1D-E-B不改 |
| planned delete/void | 否 | 仅 planned，并拒绝已有关联 actual | 非 actual writer |
| historical migration/test SQL | 可写但不是在线入口 | 固定、已执行的迁移/测试工件；不得作为新在线 writer | 不重跑、不纳入切换 |

guarded edit 证据：`sql/current/school_update_lesson_record_guarded_rpc.sql:198-200` 从新 date 算 `v_year_month`，actual update 在 `:422-444` 重写 `year_month` 和 teacher month，但没有新字段；linked actual 禁改 student/teacher/subject/entity 与 wage lock 保护在 `:352-399`。

直接表写旁路是实质风险：catalog 显示 `school_lesson_records` 对 anon/authenticated/service_role 均有 CRUD，RLS policy `school_allow_all_lesson_records` 为 public `ALL / true / true`；ordinary/cancelled/update core 的 function ACL 还包含 PUBLIC execute。现有页面遵循 API/RPC，但数据库没有阻止外部调用者直接伪造 INSERT/UPDATE。R1D-E-B 必须以 table invariant trigger/权限收紧至少封闭月份伪造；权限变更需单独静态兼容审查，不能在本阶段顺手实施。

未发现 online actual delete、actual void、actual status-conversion 或 actual rebuild RPC。shared edit 明确禁止 actual status 变化。旧 direct makeup SQL 文件是历史源码工件，current catalog 已由 compatibility wrapper 覆盖，不是当前旁路。

## K. settlement summary 完整调用链

### Reader 映射

| 功能 | Page / API | 当前 DB / table path | 当前月份过滤 | 新字段引用 | R1D-E-C要求 |
|---|---|---|---|---|---|
| settlement list snapshots | settlement page → `fetchStudentSettlements` | direct `school_student_monthly_settlements` | snapshot `year_month` | 不适用 | snapshot key保持 |
| preview candidates | settlement API | direct lesson table | `.eq('year_month', selected)` | 0 | 改成权威+legacy兼容 predicate；选出新字段 |
| summary | preview/lock/relock共同调用 | `school_get_student_monthly_settlement_summary` | lessons `l.year_month=p_year_month`；income coalesce settlement/year | 0 | lesson分支切新字段；income不变 |
| preview | settlement API RPC | `school_get_student_monthly_settlement_preview` → summary + draft | 由 summary 决定 | 0 | 跟随 summary；draft month不变 |
| lock | settlement page/API RPC | existence old `year_month` → preview → INSERT snapshot | lesson old month | 0 | existence和preview同一 predicate，原子一致 |
| unlock | detail page/API RPC | 只变 snapshot 状态，并做 wage/downstream guard | settlement row month | 0 | legacy snapshot不得因 unlock 后失去原集合 |
| relock | detail page/API RPC | existence old `year_month` → preview → overwrite same snapshot | lesson old month | 0 | 与原 snapshot basis 相容或阻止 legacy relock |
| draft adjustment | settlement page/API RPC | existence old `year_month` → preview | lesson old month | 0 | 与 preview predicate一致 |
| wage blocker | list/detail/API RPC | actual + wage detail | `l.year_month=p_year_month` | 0 | 学生月份改权威/legacy；teacher wage本身仍按 teacher month |
| detail lessons | settlement detail API | direct lesson table | student + entity + `.eq('year_month', snapshot.year_month)` | 0，select列表也缺失 | locked legacy详情保持旧集合；新快照按新字段 |
| tuition candidate/preview/generate | income/tuition API → DB RPC | canonical candidate已切 `billing_month` 且只接受 planned | actual 不参与 canonical tuition fee candidate | candidate只读 planned新字段 | 不把 actual 学生月混入 billing candidate |
| bill relation/JSON | bill preview/classifier/audit | normalized relation + `source_snapshot.planned_lesson_ids` | planned billing evidence | actual无直接ID | 永不改写；仅作为 source planned 已收费证据 |
| semantic view | direct view | `school_lesson_date_semantics` | 同时暴露 legacy/new/date语义 | 有 | 展示用途，不应替代 reader predicate |

summary 是金额与履约显示的底层聚合：lesson CTE以 old `year_month` 同时选 planned/actual；planned fee形成 due，actual fee只作fulfilment display；income使用独立 `settlement_month`兼容口径。

## L. settlement preview 完整调用链

preview RPC本身不重新选lesson，而是调用summary，再合并active draft；列表页在调用preview前又直接以lesson old `year_month`生成候选学生。因此只改summary会遗漏列表候选，二者必须同阶段切换。

## M. settlement lock / relock / unlock 完整调用链

lock与relock先用old `year_month`做lesson existence检查，再调用preview并持久化/覆盖snapshot；unlock不重算，但使后续relock可能重算。wage blocker同样用actual old `year_month`。这四条路径必须使用同一权威/legacy predicate，不能分别切换。

代码证据：

- settlement list candidate direct old month：`js/api/settlement-api.js:92-105`；preview RPC：`:177-188`；lock/unlock/relock：`:341-379`；
- detail lesson direct old month：`js/api/settlement-detail-api.js:140-150`，且 `LESSON_COLUMNS` 未包含新字段（`:30-55`）；
- current summary definition MD5 `87aab230...`，lesson CTE 在 `sql/current/school_student_settlement_cny_rounding_rpcs.sql:81-116` 按 `l.year_month`，actual只是履约显示，planned费用才形成 due；preview MD5 `7bc39abe...` 在 `:249-291` 调 summary；
- lock MD5 `6a172d58...`、relock MD5 `6db55eec...`、wage blocker MD5 `50302789...`，catalog 对新字段引用均为 0；wage blocker old predicate见 `sql/current/school_student_settlement_teacher_wage_blocker_rpcs.sql:45-86`；
- lock/relock/draft 的 old existence predicate 分别见同文件 `:248-270`、`:619-644`、`:859-928`；
- canonical tuition candidate function仍为冻结 MD5 `8981a2ce...`，本阶段未发现 canonical bill generation 对 actual fee 做收费聚合；旧历史 SQL 中按 `year_month` 的实现不能替代 current catalog 事实。

## N. 所有旧月份推断与 `year_month` 依赖清单

所有 lesson 旧月份推断可归为四类：

1. writer 创建时显式复制 source planned `year_month`（ordinary/cancelled/partial）；
2. makeup writer 从 actual date 推导 `year_month`；
3. guarded edit 从 edited actual date 重算 `year_month`；
4. settlement summary/list/detail/lock/relock/draft/wage blocker按 `year_month`筛选；teacher wage另用 `coalesce(teacher_settlement_month,year_month)`，不应被学生月切换覆盖。

`created_at` 当前不用于月份归属；JSON snapshot 只冻结 planned lesson IDs，不直接保存 actual settlement month。

## O. 新旧口径差异分类

### 总体

| 指标 | 数量 |
|---|---:|
| actual总数 / 有来源planned | `233 / 233` |
| 新字段NULL / source planned新字段非NULL | `233 / 0` |
| old `year_month` = source planned `year_month` | `225` |
| old与source不一致 | `8` |
| old `year_month` = actual date month | `224` |
| old与actual date不一致 | `9` |
| source planned month = actual date month | `216` |
| source与actual date不同 | `17` |
| old month已有locked settlement | `184` |
| source planned month已有locked settlement | `186` |
| source planned已进入bill relation / bill JSON | `43 / 43` |
| actual已进入active wage snapshot | `182` |

### 按 writer shape

| 分类 | actual | old=source | old=actual date | source≠actual date | old locked | source locked | bill relation/JSON | wage snapshot |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| cancelled | 2 | 2 | 2 | 0 | 1 | 1 | 0 | 0 |
| makeup | 16 | 8 | 14 | 10 | 12 | 14 | 0 | 12 |
| ordinary equal duration | 187 | 187 | 182 | 5 | 145 | 145 | 41 | 144 |
| ordinary legacy overage | 19 | 19 | 17 | 2 | 19 | 19 | 0 | 19 |
| partial-like | 9 | 9 | 9 | 0 | 7 | 7 | 2 | 7 |

“partial-like”是由数据关系（completed 且 duration 小于 source planned）形成的只读分类，不是持久化 provenance 字段；不能把该分类写回。

8 条 old/source 差异全部位于 makeup shape，正是历史 makeup 使用 actual-date month 的已知语义差异。由于 233 个 source planned 的新权威字段当前也全部 NULL，不能声称已有可直接 backfill 的新字段证据。

## P. 历史 actual 与 overage 19 边界

历史 actual 分类：

- **可由不可变证据唯一确定**：未来由已冻结、非 NULL 的 source planned `student_settlement_month` 创建的新 actual；当前历史集合为 0。
- **必须保持 legacy**：已锁定、已进 bill relation/JSON 或 active wage snapshot 的行；不得因 reader 切换改写其行或快照。
- **需要单独证据审查**：剩余 legacy actual；source planned `year_month`可作历史兼容证据，但不是已经冻结的新字段，不能在本阶段直接升级为新权威事实。
- **需要业务确认**：本阶段规则本身无需确认；若未来要求把未锁 legacy 行物理回填，则需独立 fixed manifest/逐行证据授权。
- **overage阶段外**：19 条保持 S1-A 五字段全 NULL，不补月份、不补金额、不收费。

固定 overage 19：新月份 NULL `19`；old=source `19`；old=actual date `17`；old-month locked `19`；active wage snapshot `19`；bill relation `0`；历史 duration 差 `9.20小时`、旧 fee 差 `JPY119,600`；S1 snapshot populated `0`。

结论：本阶段不需要、也不允许历史 backfill。reader 不能在 233 个 NULL legacy actual 存在时对全表直接纯 fail-closed，否则历史 preview/detail/lock guard 会丢行；必须有显式、可审计的 legacy compatibility branch。

### P1. 固定 279 legacy planned 分类与可操作性勘误

固定集合继续由 `279 / 0975fdc91b533680e5ccc909f076ac62` 封闭；SQL 首先断言该 count/hash，因此未来新增五字段 NULL 行不能被静默吸收为 legacy。集合的五字段非 NULL 例外为 0，`year_month` 覆盖 `2026-02` 至 `2026-11`；以执行日 `2026-07-30` 分桶为历史 `258`、当天 `0`、未来 `21`。

| status | 数量 |
|---|---:|
| planned | 189 |
| pending_makeup | 25 |
| completed | 63 |
| makeup_completed | 2 |

关联和下游证据：

| 分类 | 数量 |
|---|---:|
| 关联 actual 0 / 1 / 多条 | `59 / 207 / 13` |
| positive remaining credit | 59 |
| source master 当前无效 | 146 |
| bill relation / bill JSON | `121 / 121` |
| historical exclusion | 42 |
| source old month 已 locked | 187 |
| linked actual 已进入 active wage snapshot | 182 |

“可能来源”是把当前 RPC 的 source 条件、actual 关系、credit 余额、master 状态和 source lock 一并应用后的上限；actual 日期、目标 teacher/student month lock 等用户输入相关条件仍需在真正 writer 内再次判断：

| 路径 | 当前 DB source 可能 | 页面/API 当前暴露 | 关键解释 |
|---|---:|---:|---|
| ordinary | 47 | 47 | DB 接受 planned/pending，但 12 个 pending 来源月已 locked；页面仅 planned 显示 ordinary |
| partial | 47 | 由 ordinary dialog 分支进入 | 必须 planned、无 actual、source month 未 locked |
| cancelled | 47 | 47 个按钮 | DB 接受 planned/pending；页面按钮只在 planned 显示，但 dialog 又错误要求 pending，因此这 47 个按钮当前会被 dialog 拒绝 |
| makeup credit | 12 | same-month 12；cross-month candidate 12 | 必须 pending_makeup 且 authoritative remaining hours > 0；source 可来自 locked old month，目标 student/teacher lock 仍在提交时判断 |

这证明“legacy 279 已全部不可操作”不成立。E-B 若要求 source planned `student_settlement_month` 非 NULL，而 planned writer 与 legacy compatibility 尚未切换，上述现存 source 与后续新建五字段 NULL planned 都会 fail-closed。页面证据来自 `renderMissingActualCard`、cancel/makeup dialog guard 与 `school_list_open_lesson_credit_sources`；不能只看 status 得出结论。

### P2. planned writer 与 cutover marker 调查

current catalog 的 8 个在线入口如下，所有 definition 对 `billing_month`、`billing_week_start_date`、`student_settlement_month`、`billing_month_source`、`billing_month_decided_at` 的引用数均为 0：

| 类型 | current function | definition MD5 | lesson INSERT / UPDATE |
|---|---|---|---:|
| 单条 | `school_create_planned_lesson_record` | `9f43c43cf0c98c2c1225e74fa8d8d49f` | `1 / 0` |
| 单条 venue wrapper | `school_create_planned_lesson_record_with_venue` | `73da60c85e9f74d20b601a0d1339badf` | `0 / 1` |
| 批量生成 | `school_generate_planned_lessons_batch` | `693b1ef8c5adeff45bc94f03c5d9766e` | `1 / 0` |
| 批量 venue wrapper | `school_generate_planned_lessons_batch_with_venue` | `5ae14921f400bf404eebfabcefdb631b` | `0 / 1` |
| 导入 | `school_import_lesson_records_batch` | `ce8f7d92b1558cc09d1027914c2983ef` | `1 / 0` |
| 导入 venue wrapper | `school_import_lesson_records_batch_with_venue` | `448346b2f3949aa9e217fc5d9b512410` | `0 / 1` |
| guarded edit | `school_update_lesson_record_guarded` | `4721315f96a96c47b2751c5cc75b5843` | `0 / 2` |
| guarded edit venue wrapper | `school_update_lesson_record_guarded_with_venue` | `dca22a58c3efad550d87597385a143df` | `0 / 1` |

- 未发现命名为 copy/duplicate 的 planned function；页面/API 同样没有独立 copy/duplicate writer。
- catalog 宽匹配有 7 个“insert planned-like”及 8 个“update planned-like”定义，包含 actual/guard/helper 的文本交叉；逐一定义和页面调用后，在线 planned 入口仍是上表 8 个，不能把宽文本计数当入口数。
- `school_planned_writer_commands` 是 B1-B 为未来 writer 预建的空表：当前行数 0、引用它的 current function 0；它不是已生效 command ledger/version。
- legacy planned `created_at` 为 `2026-05-19 05:55:35.365627+00` 至 `2026-07-08 06:53:08.639382+00`；五字段完整 planned 为 `2026-07-04 03:43:09.607005+00` 至 `2026-07-08 06:50:55.529737+00`；有 73 条 legacy 的 `created_at >=` 首条完整 planned。两类时间区间重叠，不能用数据库 cutover 时间或 `created_at` 作为业务真相。
- lesson table 的直接 CRUD ACL 与 permissive RLS 仍构成 direct-write 旁路；planned writer cutover 不能只改 page/API，必须有 DB invariant 或最小权限封闭异常 NULL。

### P3. legacy 身份方案 A-G

| 方案 | 不可伪造 | 会吸收 cutover 后异常 NULL | 修改历史行 | 279 / 15 snapshot 影响 | rollback / 运营 |
|---|---|---|---|---|---|
| A. fixed legacy planned/actual manifest 或不可变 evidence 表 | 是，固定 UUID、来源 hash、版本与 append-only 权限 | 否 | 否；只新增证据 | 精确冻结 279/233，并可为15个snapshot冻结 basis | 可按新对象依赖回滚；运营连续性最好 |
| B. writer cutover ledger/version | 仅在所有 writer/direct path 强制登记且不可绕过时是 | 否 | 否 | 新行可证明版本；仍需 A/G 识别既有279 | 可停新writer版本；需原子部署 |
| C. 数据库 cutover 时间 | 否；技术时间不等于业务事实，且当前区间已重叠 | 是 | 否 | 73 条现有重叠直接证明不安全 | 回滚简单但会误分类，拒绝 |
| D. 单纯 `student_settlement_month IS NULL` | 否 | 是，全部吞掉 | 否 | 会把任意未来 writer 回归当合法 legacy | 表面连续、实际 fail-open，拒绝 |
| E. `coalesce(student_settlement_month, year_month)` | 否 | 是，且静默改变判错方式 | 否 | 会在15个snapshot之外继续扩张旧口径 | 易回滚但无法发现回归，拒绝 |
| F. 先 planned writer，再 actual writer | 需要与 A/B/G 组合才完整 | 本身不会，但单独不能识别旧NULL | 否 | 保护新运营；279仍需固定兼容 | 必须作为部署顺序，运营风险最低 |
| G. 对仍可操作 legacy planned 使用独立 fixed manifest compatibility | 是，若固定 UUID/hash、只读调用且有退出条件 | 否 | 否 | 只覆盖47/12等可操作子集，不扩大279；snapshot另冻结 | 可撤 compatibility 分支；保障遗留运营 |

推荐 `A + B + F + G`：E-B1 固定 279/233、可操作 legacy source 和15个snapshot basis，并定义不可绕过的 writer version；随后完成 planned writer cutover；E-B2 才允许 actual writer fail-closed。D/E/C 均不批准。

### P4. 15 个 locked snapshot 的 live basis 与永久保持策略

集合稳定指纹：snapshot `15`，UUID MD5 `c87016564bb4ab954993ddf9f37ff955`，完整结构集合 MD5 `51fd3d3759b432c4b214e0eb5038e616`。当前 summary basis 与 detail basis 对每行数量/hash相同；这只证明本次快照一致，不代表 snapshot 已保存 lesson relation。

| snapshot / student / entity / month | created / locked (UTC) | lesson P/A / UUID MD5 | amount / structure MD5 |
|---|---|---|---|
| `1fdfa789-572a-4e7d-9c4e-6e3ede2602de` / `a7b163a0-201e-4867-9b94-372343356a80` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-02 | `2026-05-21 10:28:43.363406` / `2026-05-24 23:39:45.573` | `30 16/14` / `ecbccbacca352f355fe009b396135f3c` | `7c15ece8b727b2a7ebc5a9735f3b4253` / `a27e8487806ab71e27159afc21d931fb` |
| `744c74ab-f743-44c4-97e7-c806551fb5f0` / `a7b163a0-201e-4867-9b94-372343356a80` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-03 | `2026-05-21 07:26:14.179281` / `2026-05-24 23:44:04.4` | `40 20/20` / `f6241408e500746c0ce3d197ecd74ef4` | `b7ea812fb59bf2deac3a4c5cb08c869f` / `eb7c3f0e9d230db2c130e6fc5a9b053a` |
| `467fa754-64b4-4ee9-a983-5a54aebd4001` / `a7b163a0-201e-4867-9b94-372343356a80` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-04 | `2026-05-21 10:15:22.76541` / `2026-05-24 23:48:41.46` | `32 16/16` / `709a5e42addff5826179f191fbd8fdd3` | `a2c220cf715489bee5e79c904680b4bf` / `fe43231f7d0a84cafdee770addc6b6bd` |
| `9d8e23f3-a102-4934-a34a-c568030bd73e` / `cff85c52-6acc-4b0f-8c92-3db280a5dd77` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-04 | `2026-05-22 06:03:04.431746` / `2026-05-22 16:05:05.689` | `4 2/2` / `38e0264283c5438a6b79a08d513a3973` | `543a0be1288b44dc82e9b8f8d48a8c98` / `198eab1efb92fea8db32f1f42329a5b9` |
| `047ff631-7bda-4fc4-bb5f-23c5420fb53b` / `eb705aad-de4d-45e6-a391-42dcdd89aeda` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-04 | `2026-05-21 10:29:07.367265` / `2026-05-22 16:04:57.563` | `24 12/12` / `6ef17caab9c4fdbf15c4414e1e730cb1` | `14cf22b815ad92886533c8333d190dff` / `982233587cdbb06694e705225debc49d` |
| `6db58942-7b98-4cb1-aa3d-c40b199e54c5` / `881dd60c-b92b-44ae-98e1-98448567a8d2` / `2cf7b72f-6e3c-4d09-80f7-7c58593cd466` / 2026-05 | `2026-06-01 01:12:55.289433` / `2026-06-01 01:12:53.63` | `22 12/10` / `a0d8a0bde97571b0f320b5ca9bf31cc5` | `b55c8a3431c540d3b6f8b7713db8afe7` / `9c8ea88fd73c38158f9e2740109ed761` |
| `33d4e693-575b-468c-a295-c884eacedea6` / `a7b163a0-201e-4867-9b94-372343356a80` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-05 | `2026-05-31 11:59:39.501591` / `2026-06-10 09:45:03.671301` | `33 16/17` / `887e4613cb3fd4fd49ff1a68954f323b` | `6da26bf64c45cdc80ac896bf55c00963` / `99aabb5c15e0682d6acf2d6ea394ee04` |
| `d70374bc-f8a5-43f3-a5a1-c45cfff78512` / `cff85c52-6acc-4b0f-8c92-3db280a5dd77` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-05 | `2026-05-26 13:25:54.455853` / `2026-05-28 16:16:03.923` | `16 8/8` / `0ccdef6efa91d8599fc6479a462cd0a8` | `67332833439c17ee366a83605218dcc3` / `55e4ed1459e06d125facc16a546e283c` |
| `41e018bd-bbf6-4673-83d9-56b8c71c49c4` / `eb705aad-de4d-45e6-a391-42dcdd89aeda` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-05 | `2026-06-01 01:13:49.560025` / `2026-06-01 01:13:48.348` | `23 12/11` / `eaa3dabffbad3630f81b76a22985080a` | `35f7eba42f6a7682481040847edfe4df` / `3899330074a50ee451c5fe967003983e` |
| `64ae8e85-0edb-468b-8310-1e1d396104e9` / `eceb2c59-9689-4ec8-9d3f-799b90bfdb27` / `2cf7b72f-6e3c-4d09-80f7-7c58593cd466` / 2026-05 | `2026-06-01 01:13:05.293548` / `2026-06-01 01:13:03.95` | `23 12/11` / `c2af15e749d1039886ab1f8e84bc62d5` | `6c63fcb8885ccf48565f74bac4073d56` / `b75712096b1b295684d9b80945643867` |
| `24c9f706-6eb8-4592-80d2-18446ca6ba42` / `881dd60c-b92b-44ae-98e1-98448567a8d2` / `2cf7b72f-6e3c-4d09-80f7-7c58593cd466` / 2026-06 | `2026-06-28 14:28:26.384411` / `2026-06-28 14:28:26.384411` | `25 12/13` / `ca0c4cebc1063764a58ab126a46faff7` | `b40a8c4353badaf9c689c8001b76c6b2` / `0be97f4ab40d9b96a0908ace384a5ef8` |
| `5527d3a1-4804-4007-8b36-d6efffb6b82f` / `a7b163a0-201e-4867-9b94-372343356a80` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-06 | `2026-06-11 17:34:37.762393` / `2026-07-01 01:06:36.783547` | `34 17/17` / `e61b6e9ea1ef70f40cb6fe0bc73742a4` | `64789f8d72c56eac1f437544e2c81e83` / `a2a9747ed4e2b0acb27f6646f42495bb` |
| `dd1a599e-a4f1-4656-ad3a-33dcdc0004f7` / `cff85c52-6acc-4b0f-8c92-3db280a5dd77` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-06 | `2026-06-24 08:39:57.319644` / `2026-06-24 08:39:57.319644` | `20 10/10` / `493972386ae2da590c016f08c567b100` | `a271b8e6e51b7a2c2b64ff4648cb85f1` / `2f9f8bc5d908395b87d59c292f62e028` |
| `b31986d0-4026-472a-b580-0864a295fbdb` / `eb705aad-de4d-45e6-a391-42dcdd89aeda` / `886a8f7c-0fea-45ac-97d2-15c976ede996` / 2026-06 | `2026-06-11 17:33:12.10962` / `2026-06-27 16:55:20.640198` | `21 10/11` / `abb71300e10ac521e8d6f7df016d705b` | `df4607b8d2e84ba7d9a6e278298d5c5b` / `5aced4d00a70ab265d5958de75ce20fb` |
| `bffa9c9f-27d7-4522-93ed-d64ff629513a` / `eceb2c59-9689-4ec8-9d3f-799b90bfdb27` / `2cf7b72f-6e3c-4d09-80f7-7c58593cd466` / 2026-06 | `2026-07-01 01:04:25.804881` / `2026-07-01 01:04:25.804881` | `24 12/12` / `220f0de01f4285d691d41cc51ced2787` | `5bc5e9653e8b1f0773bcba6a7fa852a1` / `e0efc88ebb09be62acd231e57e146ea6` |

当前 15 行的 `unlock_currently_allowed=false`、`relock_currently_allowed_while_locked=false`：前10行分别被 active carryover 或 active wage snapshot 阻断；后5行另有 posted adjustment；active wage lock 每行 `1..6`。即使未来 blocker 被外部合法流程消除，unlock 后 relock 仍会按 live `l.year_month` 调 preview 并覆盖金额；没有 snapshot lesson relation、reader version 或 immutable basis 时集合可能静默变化。

设计结论：E-B1 应为这15个 snapshot 固定 `legacy_reader_v1` basis 和 lesson UUID/hash evidence（优先 normalized immutable snapshot-lesson relation；若不建关系，至少固定 manifest + basis hash），并使 relock 只能复用同一 basis；basis 缺失或 hash 漂移时主动拒绝。不得借机更新这15行或历史 lesson。新 reader 上线后，对 legacy snapshot 直接 relock应默认拒绝，直到上述证据基础存在。

## Q. R1D-E-B 阶段拆分与 writer 切换设计（未实施）

`R1D-E-B` 不能按原设计直接部署，必须拆分：

1. **R1D-E-B1：legacy/cutover evidence foundation**。固定279 planned、233 actual、仍可操作47/12子集及15个locked snapshot basis；只设计不可变manifest/reader-version/basis-hash，不改历史lesson。
2. **planned writer cutover prerequisite**。单条、批量、导入、guarded edit、venue wrapper和direct invariant必须原子写/保持五字段，并让command ledger/version成为所有入口不可绕过的证据。postdeploy须证明cutover后新planned不可能五字段NULL。
3. **R1D-E-B2：actual writer cutover**。前两项通过后，才替换ordinary、cancelled、partial、makeup canonical与guarded edit；compatibility wrapper继续只调用canonical。

E-B2细则：

1. 新 actual 不接受客户端月份参数。DB锁定 source planned 后，新版本source必须有合法非NULL `student_settlement_month`；fixed legacy source必须命中E-B1 manifest/version，不能靠`IS NULL`自动放行；两者之外fail-closed。
2. fixed legacy compatibility只复现冻结的old basis，不把`year_month`升级成全局新权威，也不扩大固定UUID集合。
3. writer-first窗口内继续令actual `year_month = student_settlement_month`作为旧reader兼容值；尤其makeup不再把student `year_month`写成actual date month。
4. `teacher_settlement_month = to_char(actual lesson_date,'YYYY-MM')`保持不变；student与teacher month明确分离。
5. student settlement lock按source/actual权威月份检查；teacher wage lock按teacher month检查。
6. ordinary的`duration <> planned.duration`拒绝原样保留；partial、makeup credit规则原样保留；不允许overage。
7. guarded actual edit不得重算或接受新student month；日期变化只重算teacher month。legacy actual必须命中fixed manifest/version才可进入独立兼容路径。
8. 已locked settlement、active wage detail/payment、bill evidence的actual/source拒绝影响归属或金额的修改；source link、student、entity、student month不可变。
9. DB table invariant必须保证direct INSERT/UPDATE无法伪造、清空或改写月份；同时审查并收紧PUBLIC/anon/authenticated直接表写与旧RPC execute ACL。
10. rollback tests覆盖ordinary/cancelled/partial/makeup、same/cross-month、legacy wrappers、direct-table伪造、locked source/teacher、NULL source、edited date、old/new值与manifest miss。
11. postdeploy断言cutover-version source及部署后actual全部非NULL且一致，legacy source全部命中fixed manifest；不要求历史233条物理非NULL。

E-B2 rollback只能在R1D-E-C前执行；若已创建新语义actual，回滚旧writer也必须保留该字段，不能清空或把makeup改回date month。

## R. R1D-E-C reader 切换设计（未实施）

推荐统一 DB predicate/helper，禁止各页面自行组合：

- authoritative branch：`lesson.student_settlement_month = requested_month`；
- explicit legacy branch：必须命中E-B1 fixed manifest/reader version或snapshot lesson relation，再按其中冻结的old basis；`student_settlement_month IS NULL`本身不是legacy identity；
- cutover后出现 NULL 必须报错/告警，不能 `coalesce(student_settlement_month,year_month)` 静默吞掉 writer 回归。

切换范围必须同一阶段覆盖：summary、preview、lock、relock、draft adjustment existence、wage blocker、settlement list candidate、detail lesson query。API/page只传 requested month，不派生保存月份。

特殊兼容：

- 当前15个 snapshot均 locked，金额本身保持原快照；详情必须按固定UUID/hash relation展示，不能因切换重新归组。
- legacy snapshot unlock/relock必须复用同一reader version与lesson relation；证据不存在或basis hash漂移时直接拒绝，不能用新reader悄悄重算。
- 新 preview/lock只接受 writer-cutover后非NULL authoritative actual；legacy分支需返回明确计数/telemetry并设退出条件。
- planned与actual的读取条件应分支表达；income继续使用其 `settlement_month` 权威字段，不受 lesson切换影响。
- tuition billing仍读取 planned `billing_month`；不以 actual student month改变已冻结bill relation/JSON。

R1D-E-C rollback恢复旧 reader仅在没有新 cross-month makeup 依赖新语义时安全；因此 rollback必须保留兼容 `year_month=student_settlement_month` 的 writer策略，并对新增actual集合做固定验证。

## S. 权限、RLS、旧 RPC 与直接写风险

- lesson table RLS enabled但 policy允许 public ALL；anon/authenticated/service_role表ACL均含 CRUD，不能把 RPC 当作唯一物理入口。
- settlement table同样给anon/authenticated CRUD，并有分别允许SELECT/INSERT/UPDATE/DELETE的policy；锁/重锁权威性主要依赖调用纪律和RPC，不是表级不可绕过。
- ordinary/cancelled/update core含PUBLIC execute；partial/makeup及legacy wrappers含anon/authenticated/service_role execute。
- 旧同名 makeup/cross-month SQL正文仍在仓库，但 catalog MD5证明在线定义已被 lesson-credit wrapper替换。未来迁移顺序必须保证最后生效定义仍是 wrapper。
- trigger仅3个：actual_minutes sync、schedule venue inheritance、updated_at；均不保护 `student_settlement_month`。
- page模块当前通过 API wrapper 调 RPC；settlement list/detail仍有直接表读取，但未发现页面直接写 lesson actual。

R1D-E-B/C实施前必须把 ACL/RLS/definition MD5 做成前置与postdeploy指纹，避免旧RPC或direct table路径绕过。

## T. 部署、安全顺序、rollback 与验收

顺序勘误为：

1. **R1D-E-B1 evidence foundation**：固定legacy/cutover与15个snapshot basis；不改历史lesson。
2. **planned writer cutover**：所有新planned路径写五字段、登记不可绕过version，并封闭direct NULL旁路。
3. **R1D-E-B2 actual writer**：所有新actual/cancelled/partial/makeup与edit写/保持权威学生月；legacy仅按fixed manifest兼容；旧`year_month`保留过渡兼容。
4. 观察并验证cutover后新增planned/actual 100%符合version与月份不变量，teacher month仍按occurred date；检查所有legacy wrapper/direct path。
5. **R1D-E-C reader**：统一切summary/preview/lock/relock/draft/wage blocker/list/detail，并使用显式manifest/version分支。
6. **R1D-E-D联合验收**：same/cross-month、锁定、bill/wage snapshot、NULL回归、权限旁路、rollback与R0/funds边界。

验收必须固定：R0、candidate/118/279、资金链hash、现有15 locked snapshot、233 legacy集合与8条old/source差异；运营新增数量只披露。任何已锁/已收费事实不得被更新。

## U. BUSINESS_DECISION_REQUIRED

`none`。业务语义仍明确；本阶段停止是技术前置依赖未完成，不是要求用户放宽fail-closed。

权威文件已明确且一致：

- `docs/school-v2-r1d-a-date-and-billing-semantics-design-20260728.md:213`："planned默认等于billing month，actual/makeup继承来源planned"；
- 同文件 `:215-216`："继承来源planned"，完成月"不覆盖继承的student settlement month"；
- 同文件 `:269`："禁止actual按发生日覆盖"；
- 同文件 `:282`："actual/cancel/partial/makeup继承来源planned"；
- 同文件 `:399-400`："所有来源actual/makeup继承"，teacher month按实际发生月。
- `docs/current-status.md:25` 明确 S1-A 未激活且“next implementation phase remains blocked until R1D actual writer and settlement reader complete their authoritative month cutover”；`:63` 再次记录 planned student month 跟随 billing、actual/makeup 继承 source planned。

R1D-B加法schema、B1-A planned writer设计与S1-A都把actual writer/settlement reader切换留给后续独立阶段，没有提出相反业务规则。历史物理backfill是否另行批准不是本阶段业务规则缺口。最终分类是`E_B_BLOCKED_UNTIL_PLANNED_WRITER_CUTOVER`，不得用`BUSINESS_DECISION_REQUIRED`绕过planned writer前置。

## V. actual overage S1-B 恢复条件

独立 S1-B 只有在以下主线条件全部完成后才能恢复：

1. E-B1 legacy/cutover evidence与15个snapshot basis已固定；
2. planned writer cutover完成，所有入口/direct invariant证明新planned五字段非NULL且version可审计；
3. E-B2已覆盖ordinary/partial/makeup/cancelled及guarded edit/legacy wrappers/direct-table invariant；
4. 新ordinary actual都由DB写入非NULL、合法、等于source planned的student month；
5. R1D-E-C summary/preview/lock/relock/detail/wage blocker已统一读权威字段并有受控fixed-legacy窗口；
6. R1D-E-D证明same/cross-month、locked settlement、active wage、bill relation/JSON无漂移，R0/candidate/funds边界不变；
7. 历史19条继续全NULL、未补月/补金额/收费；
8. ordinary现有`<>`拒绝仍保持，S1-B再在自己的独立授权阶段设计overage writer/reader，不能复用空调费逻辑或planned整数时长规则。

当前这些条件未完成，S1-B继续blocked。

## W. 文件 SHA-256

最终值：

- 只读 SQL：`4862fb3791fdd1bf7c54d3df028b1f20a16b9470ebd55dd1756f224671ae33a4`
- 本报告的最终 SHA-256 由阶段最终报告在文件封存后披露；将自身 hash 写入自身会再次改变该 hash。
- 保护文件：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`

## X. 最终状态与停止点

预期最终工作区仅包含：

```text
?? docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt
?? docs/school-v2-r1d-e-a-actual-writer-settlement-month-inventory-report-20260730.md
?? sql/current/school_tuition_r1d_e_a_actual_writer_settlement_month_inventory_readonly.sql
```

未执行 git add/commit/push；未修改`docs/current-status.md`；未进入R1D-E-B/C/D、planned writer切换、S1-B、B1-C或解除R0。阶段在`R1D-E-A-E勘误审查点`停止。
