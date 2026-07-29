# School V2 学费链 P0：R1D-D-B1-A Planned Writer与空调费数据库权威模型只读调查及实施设计

日期：2026-07-30
阶段：R1D-D-B1-A
状态：仓库与School数据库只读调查完成；仅形成设计，不实施

## A. 执行结论

本阶段只读调查和设计完成，未触发停止条件。与交付SQL字节一致的临时预检及仓库内最终工件分别在School数据库的单一`REPEATABLE READ READ ONLY`事务中执行一次，两次SQL错误均为0并显式`ROLLBACK`；DDL、DML、业务RPC、测试记录和数据库写入均为0。

权威边界保持：628条lesson（397 planned / 231 actual），planned收费归属五字段完整118、全NULL 279、部分填写0，`scheduled_lesson_date`非NULL 0。固定118的UUID集合MD5、业务Manifest SHA-256、数量、小时、金额和下游零关系全部匹配B0-B；279集合MD5也匹配。candidate表级等价集合仍为118条/254小时/JPY2,474,000。

设计结论：不能在现有writer上继续叠加前端派生值。后续应建立数据库权威的归属、时间/时长、venue、空调费率和费用组件计算内核，并以不同事务入口承接单条create、批量create、同周schedule/venue更新和其他planned业务字段更新。正式切换时必须同时封闭旧核心RPC和直接表写绕过；R0学费生成/Cash gate继续独立保持阻断。

本次业务勘误进一步冻结：未来canonical planned最短2小时且必须为整数小时；空调报备小时精确等于已校验并冻结的planned权威时长，不使用`round`、`floor`或`ceil`，也不接受独立手填。固定118条已用B0-B内嵌UUID逐条只读核验，全部符合该规则，分布为100条×2小时、18条×3小时。

## B. Git与保护文件

- 分支：`main`
- 调查开始HEAD与`origin/main`：`3c50684c29a720a5cc1cf09ab156711cd5a4779b`
- 开始时暂存区为空，工作区仅有受保护未跟踪文件。
- B0-B报告SHA-256：`f1edfb9a48666c87de08a1bca9ca5bca33cd8fb5c41f54ffdf043e39a250c261`
- B0-B只读SQL SHA-256：`1aed1bc91a13d399b63b54faeb80c125edeae6658775ac1d788dba5e4f826c16`
- 受保护文件`docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`未读取正文、未修改、未暂存，SHA-256保持`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。

本阶段只新增本报告和一份只读SQL；未修改`docs/current-status.md`或任何既有文件，未执行`git add`、commit或push。

## C. R0、candidate及118/279边界

| 核验项 | 结果 |
|---|---|
| `student_tuition_preview` | `validation_preview_only` |
| `student_tuition_generate` | `blocked` |
| `student_tuition_cash_submit` | `blocked` |
| candidate函数定义MD5 | `8981a2ce07abf8c28231bfaf05451368` |
| candidate表级等价结果 | 118条 / 254小时 / JPY2,474,000 |
| candidate UUID集合MD5 | `77f697f82e547d84dcabf88a3c868aa1` |
| 固定118业务Manifest SHA-256 | `f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1` |
| 固定118异常/actual/bill relation/bill JSON/历史排除 | 0 / 0 / 0 / 0 / 0 |
| legacy 279 UUID集合MD5 | `0975fdc91b533680e5ccc909f076ac62` |
| planned部分填写 | 0 |

actual从B0-B快照231保持231；只作正常运营数量披露，不处理actual。School资金链只读快照继续为9 bill、42 income、121 relation、42历史排除；hash分别为`0f0323b79e7ff1c47ff6b90c75477a2d`、`2a4897b752f272b1f192045418b4940c`、`09dfee7d8833e09384fb41a84f2959e0`、`680b6e5aaa718569aee4c36fe1cdc058`。

## D. 仓库writer入口完整inventory

页面模块没有直接`.rpc()`，所有页面写操作经`js/api/lesson-api.js`。仓库扫描未发现页面/API对`school_lesson_records`的直接insert/update/delete/upsert；`.from("school_lesson_records")`均为读取。但数据库ACL/RLS允许客户端直接写，见N节。

| 入口 | 页面/调用方 | API与数据库链 | 当前输入与权威位置 | 绕过风险 | 后续入口/范围 |
|---|---|---|---|---|---|
| 单条planned create | `lesson.html` → `js/pages/lesson-page.js` | `createPlannedLessonRecord` → `school_create_planned_lesson_record_with_venue` → core `school_create_planned_lesson_record` | 页面提交旧`lesson_date`、对象ID、时间、duration、unit price、可手填fee、状态/回数/内容/备注、mode/venue；DB派生旧`year_month`，fee为NULL时才计算 | 页面计算时间差和fee预览；允许手填fee；core对PUBLIC/anon/authenticated可执行，可绕过venue wrapper；不写R1D-B字段 | `school_create_planned_lesson_canonical`；属于后续writer切换 |
| 规则批量create | `lesson.html`批量弹窗 → `lesson-page.js` | `generatePlannedLessonRecordsBatch` → `_with_venue` → core `school_generate_planned_lessons_batch` | 页面提交generation ID、学生/entity、日期范围、weekday规则、时间/duration/unit price/venue等；DB展开日期并把匹配日归一为周一，派生duration/fee | 页面同时计算/改写duration预览；core authenticated可直接调用绕过venue wrapper；没有显式新billing字段 | `school_create_planned_lessons_batch_canonical`；属于后续writer切换 |
| planned导入 | `lesson.html`导入弹窗 → `lesson-page.js` | `importPlannedLessonRecordsBatch` → `_with_venue` → core `school_import_lesson_records_batch` | 文件可带date/time/duration/unit price/fee/mode/venue；DB派生旧month，缺duration时按时间算，缺fee时计算 | core仍授予PUBLIC/anon/authenticated；文件可提供最终fee；导入没有明确scheduled与billing week二选一契约 | 导入只做解析；提交必须转换为canonical batch命令；属于后续writer切换 |
| planned/actual共享编辑 | `lesson.html`及`lesson-detail.html` → `js/components/lesson-edit-dialog.js` | `updateLessonRecordGuarded` → `_with_venue` → core `school_update_lesson_record_guarded` | 页面提交旧date、时间、duration、unit price、可手填fee等；DB锁行、检查`updated_at`、planned linked actual/月结等并更新 | 页面计算duration/fee；core授予PUBLIC/anon/authenticated；不检查bill relation；可改已有账单证据对应planned的收费字段 | planned拆为schedule/venue和其他业务字段两个canonical更新入口；actual编辑保持阶段外 |
| actual生成链 | planned → completed/cancelled/partial/makeup/cross-month actual | 多个现有SECURITY DEFINER RPC；insert trigger继承mode/venue | actual工资月、actual minutes等由现有RPC/trigger处理 | 多个旧RPC仍接受duration/fee；与planned费用组件继承语义尚未切换 | 本阶段不改；actual的student settlement继承和费用语义另开阶段 |
| void/delete | planned void、fresh test delete | 现有受控RPC | 只处理作废/测试删除边界 | 与费用冻结需在未来统一检查账单证据 | 不并入B1 planned create；单独保持/适配 |

页面当前还存在三类非权威计算：单条/编辑的时间差与fee预览、批量规则的duration与汇总、导入preview的duration估算。预览可以保留，但新API不得把这些预览结果作为权威duration或fee写参数；有完整时间时duration由DB重算，任何最终费用只能来自DB返回。

## E. 数据库schema、constraint、function、permission inventory

### E.1 lesson物理结构

`school_lesson_records`当前37列。关键事实：

- `start_time/end_time`是nullable `text`；`duration_hours`是NOT NULL `numeric default 0`；`unit_price/lesson_fee`是nullable `numeric default 0`。
- 旧`lesson_date/year_month`仍NOT NULL并被现有reader/writer广泛使用。
- `lesson_delivery_mode/lesson_venue`为nullable text；mode只允许`onsite/online`；onsite venue固定值约束仍是`NOT VALID`。
- R1D-B六字段均nullable、无default；7个validated check继续有效。
- 三个lesson trigger均enabled：`updated_at`、actual minutes sync、actual venue inheritance。
- R1D-B四个partial index及现有month/teacher/student/schedule索引均存在。

### E.2 函数与权限

核心planned create/import/update和venue-aware wrapper均由`postgres`拥有、`SECURITY DEFINER`、`search_path=public`。目前：

- `school_create_planned_lesson_record`、`school_import_lesson_records_batch`、`school_update_lesson_record_guarded`仍向PUBLIC、anon、authenticated、service_role开放EXECUTE；
- core batch及四个venue-aware wrapper向authenticated/service_role开放；
- 旧core均不引用`billing_week_start_date`或`scheduled_lesson_date`；
- `school_iso_week_start`与合法period helper只向service_role开放；
- formal generate有两个重载，均保持R0阻断。

直接调用旧core可绕过venue wrapper和未来空调计算，不能只新增一个canonical RPC而保留旧ACL。

### E.3 RLS与表权限

`school_lesson_records`启用RLS，但现有`school_allow_all_lesson_records`为`FOR ALL TO public USING(true) WITH CHECK(true)`；同时anon、authenticated、service_role都有整表CRUD/TRUNCATE等ACL。RLS在当前配置下不是防绕过边界。账单表也向客户端角色暴露广权限；relation表则仅service_role SELECT/INSERT且有immutable trigger。

后续收口必须以显式ACL撤销、替换permissive policy、仅开放受控SECURITY DEFINER函数三者共同完成，不能只依赖应用代码约定。

### E.4 可复用结构调查

目录中不存在名称指向venue master、学生有效期费率或pricing config的表/view。`school_lesson_schedules.location`、旧并行`school_planned_lessons/school_actual_lessons`、教师工资规则和学生preset exchange rate语义均不等价，禁止复用为学费空调费配置。应新增最小专用venue master和学生空调费率表。

## F. 现有数据与新约束冲突计数

| 核验 | 当前结果 | 设计含义 |
|---|---:|---|
| planned总数 | 397 | 118新归属完整、279 legacy |
| start/end均NULL | 304 | canonical writer必须支持无时间+显式duration |
| start/end完整 | 93 | 可由DB计算duration |
| 单边时间 | 0 | 新pair约束不会与现状冲突 |
| 跨午夜或非正时间差 | 0 | 新writer可fail-closed禁止 |
| duration NULL | 0 | 旧default为0，但现有无NULL |
| duration < 2小时 | 5 | 不得对历史加VALIDATED全表最小2小时约束；只约束新canonical写入或用NOT VALID策略 |
| 非整小时duration | 7 | 属于既有历史planned；不得直接增加立即验证全表的普通VALIDATED整数约束，也不得修改历史行 |
| 非15分钟粒度duration | 0 | 仅为历史分布证据；未来canonical planned的批准规则已收紧为整数小时 |
| sub-minute duration | 0 | 无现有冲突 |
| base fee公式不匹配 | 0 | 当前397均等于`round(duration × unit_price)` |
| scheduled超出冻结周 | 0 | 当前scheduled全NULL |
| billing week非周一/月周不一致/student month不一致 | 0/0/0 | R1D-B约束正常 |

全体397条planned的duration分布为1小时2条、1.5小时2条、1.75小时1条、2小时364条、2.5小时3条、3小时23条、3.5小时1条、20小时1条。固定118条单独核验为2小时100条、3小时18条，NULL/低于2小时/非整数均为0；历史5条低于2小时、7条非整数以及279 legacy均不在本阶段处理。

venue/mode分布：planned 387条NULL/NULL、online 2、Regus公共区4、Regus办公室4；actual 222条NULL/NULL、online 2、Regus公共区4、Regus办公室3。固定118的schedule/mode/venue仍全部NULL。

## G. 推荐的canonical writer函数划分

不建议由一个RPC承担所有操作。推荐最小分层：

1. 内部纯函数`school_resolve_planned_billing_attribution(...)`：只接受`scheduled date`或明确ISO周一二者之一，返回week/month/student month/source；调用方不得提交派生month。
2. 内部函数`school_resolve_planned_duration(...)`：执行time pair、跨午夜、最低2小时和整数小时规则，返回权威duration。
3. 内部函数`school_resolve_lesson_venue(...)`：按稳定venue code解析master，禁止中文文本成为收费判断。
4. 内部函数`school_calculate_planned_fee_components(...)`：锁定并解析学生有效费率，返回base/aircon/total、状态、快照和版本。
5. 公共单条入口`school_create_planned_lesson_canonical(...)`：有scheduled date路径；DB派生归属和所有费用。
6. 公共批量入口`school_create_planned_lessons_batch_canonical(...)`：每行必须给明确billing week；scheduled可NULL；全批fail-closed。
7. 公共同周排课入口`school_update_planned_schedule_venue_canonical(...)`：只改scheduled date/venue，锁行并限制同周，账单前重算空调组件。
8. 公共业务字段入口`school_update_planned_business_fields_canonical(...)`：老师、科目、可选时间或显式duration、unit price、回数、内容、备注；不允许改billing pair/entity，并重算基础费/空调费。

所有入口使用`p_request_id uuid`及payload hash做幂等；相同request+相同payload返回原结果，不同payload返回`PLANNED_IDEMPOTENCY_CONFLICT`。批量沿用generation/import batch ID但统一进入同一命令账本。更新使用`SELECT ... FOR UPDATE`和`expected_updated_at`；写入、账单生成和关系插入必须采用一致锁序（planned lesson → rate/config → bill identity/bill），避免更新与出账竞态。

建议稳定错误码：`PLANNED_WRITER_BLOCKED`、`INVALID_BILLING_WEEK`、`SCHEDULE_OUTSIDE_BILLING_WEEK`、`TIME_PAIR_REQUIRED`、`CROSS_MIDNIGHT_NOT_ALLOWED`、`PLANNED_DURATION_BELOW_MINIMUM`、`PLANNED_DURATION_NOT_INTEGER`、`AIRCON_RATE_UNCONFIGURED`、`PLANNED_FEE_INCOMPLETE`、`BILLED_FEE_COMPONENT_IMMUTABLE`、`STALE_LESSON_VERSION`、`PLANNED_IDEMPOTENCY_CONFLICT`、`DIRECT_LESSON_WRITE_FORBIDDEN`。

## H. billing attribution数据库权威设计

单条create：调用方只提交`scheduled_lesson_date`，DB用`school_iso_week_start(date)`生成周一，`billing_month=to_char(week,'YYYY-MM')`，`student_settlement_month=billing_month`，source固定为建议值`scheduled_date_at_create`，`billing_month_decided_at`由DB写`statement_timestamp()`。

批量create：调用方对每个待生成行明确提交`billing_week_start_date`，DB验证ISO周一，生成month/student month，scheduled保持NULL，source建议`explicit_billing_week_at_create`，decided_at由DB写入。页面不得以周一代理显示真实上课日期。

归属创建后普通writer不可改变。补充scheduled date必须在`billing_week_start_date`至`+6天`，且不得改week/month/student month。现有118保留`approved_r1c_a_manifest`/`approved_r1c_c_b_manifest`；未来新行使用新source。旧`year_month/lesson_date/created_at/updated_at`不能作为新归属的fallback，因为旧字段多义且技术时间戳不构成业务决定。

建议不立刻把全表source收紧为单一枚举check；应先在canonical函数中固定允许值，并在candidate适配阶段显式批准新source。未来若建source master也必须保留两种已批准历史source。

## I. 时间、时长及跨午夜约束设计

- `start_time/end_time`可继续复用现有nullable text以避免历史列改型；canonical helper先严格解析`HH24:MI`，内部转`time without time zone`计算。
- 两者均NULL时，必须提交显式`duration_hours`；显式值必须是大于等于2的整数小时。只填一个时间立即拒绝。
- 两者齐全时，调用方不得提交权威duration；DB以`end-start`计算，并再次验证计算结果是大于等于2的整数小时。前端可显示preview，但API应传NULL/省略派生duration。
- `end <= start`拒绝，不支持跨午夜。
- 新canonical planned最低2小时且必须为整数小时；现有5条低于2小时和7条非整数planned只能由新writer入口约束，或由安全的NOT VALID/trigger方案保护新写入，不能直接增加会立即验证全表的普通VALIDATED约束，也不能批量改写397条历史planned。
- `scheduled_lesson_date`和时间是东京本地排课事实；date/time本身不做UTC换算。数据库当前TimeZone为UTC，只影响`timestamptz`显示；decided/calculated时间保存`timestamptz`。
- actual允许小数时长；actual不得反向修改来源planned。actual超过planned的部分由独立事故修复线中的月度结算流程转入下期账单，不与B1-B、planned writer或空调费实现合并。

## J. venue稳定模型

比较：

| 方案 | 优点 | 风险/结论 |
|---|---|---|
| lesson直接新增code text | 最小 | code/display/有效状态分散，扩展与审计弱 |
| 新venue master + lesson FK | 稳定code、显示名、mode、有效状态、空调资格集中；可扩展 | 增加一表一FK；已批准采用 |
| 复用`lesson_venue`文本 | 无迁移 | 中文显示名成为收费事实；禁止 |
| 复用`schedules.location`或旧parallel表 | 表面已有字段 | 语义和生命周期不同；禁止 |

已批准新建专用venue master，建议物理结构为`school_lesson_venues(id uuid PK, code text UNIQUE, display_name text, delivery_mode text, aircon_eligible boolean, effective_from date, effective_to date NULL, is_active boolean, created_at/by...)`，lesson新增nullable `lesson_venue_id` FK。API未来提交稳定code，由DB解析venue ID；中文名称仅为display name。兼容期由DB从master写现有`lesson_delivery_mode/lesson_venue`显示字段，reader后续再切。B1-C独立写入`regus_office`及需要的非适用venue配置；不从历史中文文本自动映射。

`Regus办公室`对应`regus_office`；`Regus公共区`、online及其他venue必须通过master属性明确为非空调适用。118只允许后续人工选择，不做动态文本回填。

## K. 学生有效期空调费率模型

已批准采用学生级有效期费率表，建议名称`school_student_aircon_rates`：

| 字段 | 建议 |
|---|---|
| `id` | uuid PK |
| `student_id` | uuid NOT NULL FK restrict |
| `unit_price_jpy` | integer NOT NULL，check 0..660 |
| `effective_from` | date NOT NULL |
| `effective_to` | date NULL；半开区间的exclusive end，NULL表示开放结束 |
| `reason` | nonblank text |
| `created_at/created_by` | DB生成，不接受页面伪造 |
| `closed_at/closed_by` | 仅受控换价时记录 |
| `superseded_by_rate_id` | nullable自引用，形成换价链 |

0是明确配置；missing是`unconfigured`，不可coalesce为0。有效期采用`[effective_from,effective_to)`：起始日当天生效，结束日当天旧费率已失效，NULL表示开放结束。同一学生有效期不得重叠，优先采用`daterange(...,'[)')`排斥约束；B1-B实施前必须核验`btree_gist`已安装或可安全启用，若不能安全使用则停止返回审查，不得自行降级为弱约束。同一学生同一天只能有一个有效费率，新费率从`effective_from`当天整日生效，不支持日内按时间分段。普通UPDATE/DELETE全部禁止；唯一允许的换价是受控RPC在同一事务内把当前open row的`effective_to`从NULL关闭到新`effective_from`，同时INSERT新row并写审计，旧单价和旧`effective_from`永不可覆盖。

anon/authenticated无表读写；service_role最多SELECT；只有单独批准的管理RPC可结束旧记录/新增记录。孙陈锋JPY330和张倬闻JPY0两条固定配置只在后续独立B1-C写入，本阶段没有写入。

## L. lesson费用组件和状态模型

建议对`school_lesson_records`最小加法增加nullable字段；旧118/279和历史行保持NULL，直到各自独立阶段：

| 字段 | 类型/NULL | DB写入与语义 |
|---|---|---|
| `base_lesson_fee_jpy` | numeric NULL | canonical DB计算`unit_price × authoritative duration`；不接受调用方金额 |
| `lesson_venue_id` | uuid NULL FK | DB按稳定code解析；历史文本不自动映射 |
| `aircon_charge_status` | text NULL | `pending_schedule/pending_venue/unconfigured/not_applicable/configured_zero/calculated` |
| `aircon_rate_id` | uuid NULL FK restrict | 命中的不可变费率记录；missing/pending/not-applicable为空 |
| `aircon_unit_price_jpy_snapshot` | integer NULL | 命中rate时快照，包括0 |
| `aircon_billable_hours_snapshot` | numeric NULL | 精确等于通过整数/最低2小时校验的权威planned duration；独立冻结快照且不随actual变化，不接受调用方手填 |
| `aircon_fee_jpy` | numeric NULL | DB计算；configured_zero为0，pending/unconfigured为空 |
| `aircon_calculated_at` | timestamptz NULL | DB计算时间 |
| `fee_calculation_version` | text NULL | 例如版本常量；新writer complete行必填 |
| `fee_block_reason_code` | text NULL | pending/unconfigured的结构化原因；不得存自由金额 |
| `fee_components_frozen_at` | timestamptz NULL | formal relation成功时冻结，历史不倒灌 |

已批准继续把现有`lesson_fee`定义为最终总额：新canonical行必须`lesson_fee = base_lesson_fee_jpy + aircon_fee_jpy`，其中`base_lesson_fee_jpy`保存基础课时费，`aircon_fee_jpy`保存空调费。旧行在component字段NULL时保持原legacy金额，不用`coalesce(component, legacy)`伪装成已完成组件化。candidate、preview和generate分别在后续独立阶段切换；不能对旧NULL组件静默回退。

状态决策顺序：

1. scheduled NULL → `pending_schedule`；
2. 日期已知但venue未定 → `pending_venue`；
3. 生效日前、非周末、online或明确非适用venue → `not_applicable`，aircon fee=0；
4. 否则查学生当天有效费率；缺失 → `unconfigured`且fee保持NULL；
5. rate=0 → `configured_zero`，rate/price/hours快照完整，fee=0；
6. rate>0且planned权威时长已通过整数及最低2小时校验 → `calculated`，令`aircon_billable_hours_snapshot = authoritative duration_hours`并保存rate/price/hours/fee快照。

空调报备小时不需要也不允许用户单独输入。其独立snapshot用于账单冻结，防止以后planned变化覆盖历史证据，不表示它是独立业务输入。账单前修改同周schedule、venue、planned duration或unit price时DB重算；actual duration永不参与或触发空调重算。新canonical planned若低于2小时或不是整数，writer必须在写入前直接拒绝，不得创建“等待取整”收费状态；空调费不得使用`round`、`floor`或`ceil`。

## M. bill冻结与不可变设计

现有121 relation已冻结duration、unit price、lesson fee和source JSON，但week/scheduled snapshot均为NULL；9张bill均有planned IDs/fee，均无aircon或calculation version。121历史行不得回填新快照。

未来formal generate前只允许：

- `not_applicable`（aircon=0且理由完整）；
- `configured_zero`（rate/0价/hours快照完整）；
- `calculated`（rate/hours/fee完整）。

`pending_schedule`、`pending_venue`、`unconfigured`、缺version或组件不平衡必须阻断整张账单；低于2小时或非整数planned应更早在canonical writer层被拒绝，不能进入收费状态机。

已批准采用双层冻结：normalized relation是逐课金额约束和审计的主依据，bill header `source_snapshot`保存账单级汇总、版本和完整证据，JSON不得替代结构化列。relation至少保存base lesson fee、aircon rate ID、aircon unit price、aircon billable hours、aircon fee、lesson total、fee calculation version、venue、scheduled lesson date、billing week及其他必要来源证据；最终精确列名、类型和约束由B1-B migration设计确定，但不得减少上述业务证据。两层内容必须在B1-I formal generate的同一事务中生成并保持一致；B1-B只能加法型创建nullable relation列，不能提前写入或启用冻结逻辑，历史121条relation和既有账单不得回填。

当前85个不同planned存在121条关系；121条关系行状态仍看似可编辑，且59条关系没有linked actual，现有planned edit RPC没有bill relation blocker。因此后续必须同时：

- formal generate锁planned行并原子插入relation/冻结字段；
- lesson BEFORE UPDATE trigger对所有可能改变收费组件的字段收集OLD/NEW并检查normalized/JSON evidence；
- canonical update RPC重复同一检查并返回稳定错误；
- 直接表写权限撤销；
- bill后schedule/venue如因运营需要调整，只能走独立非收费排课入口，relation收费快照不变，差额进入未来adjustment，不能覆盖原组件。

账单后字段保护采用三层：canonical RPC在更新前同时检查normalized relation和bill JSON证据；数据库trigger覆盖直接写及遗漏路径；B1-E原子切换时撤销客户端直接表写并关闭permissive写policy。保护字段至少覆盖billing attribution、scheduled date中影响收费判断的部分、venue identity、planned duration、unit price、base fee、aircon状态/rate/快照/hours/fee、lesson total、calculation version及frozen timestamp。正式账单后的运营排课变化或金额调整必须进入未来独立流程，不得覆盖冻结事实。

本轮不开放通用金额override：不得直接覆盖base fee、aircon fee或total，不得绕过费率/报备小时规则，管理员页面也不得修改冻结金额。未来如有需求，必须新开独立adjustment/override审计阶段，不能复用普通lesson update。

## N. 权限、RLS与防绕过设计

1. 撤销anon/authenticated/service_role对`school_lesson_records`的INSERT/UPDATE/DELETE/TRUNCATE；保留确有需要的SELECT。
2. 删除/替换`school_allow_all_lesson_records` permissive ALL policy；建立最小SELECT policy，不给直接写policy。
3. 新canonical RPC采用`SECURITY DEFINER SET search_path=pg_catalog,public`或安全等价形式，owner为受控数据库角色，只授予需要的调用角色EXECUTE。
4. 旧core create/batch/import/update与venue wrapper在切换事务中撤销PUBLIC/anon/authenticated EXECUTE，或改为内部不可直调函数；不能保留旁路。
5. venue/rate/command audit表对anon/authenticated无表权限；service_role只获得明确需要的SELECT；管理写入仅经审计RPC。
6. 表级constraint/trigger仍是最后防线，不能只靠RPC。

为避免部署危险窗口，建议新增独立planned-writer gate：`blocked`、`validation_only`、`canonical_write_enabled`。B1-E数据库切换事务同时部署canonical函数、收口ACL/RLS、把旧入口改为明确blocked兼容stub，并保持gate blocked；B1-F/G完成API/page后先validation，最后另经授权启用canonical写入。该gate独立于R0，不得顺带解除学费generate/Cash gate。

上述ACL、RLS和旧RPC收口只能在B1-E writer原子切换事务中执行；B1-B不得提前撤销现有权限或关闭现行写入口，以免造成运营不可用窗口。B1-B只可准备加法型schema、helper和防线对象，不启用会改变现有writer行为的权限切换。

## O. 后续分阶段实施顺序

1. **B1-B**：加法型venue/rate/lesson component/relation snapshot schema、内部只读helper、nullable或NOT VALID check/index、空审计/命令账本；不写配置、不切writer，不提前收口旧RPC/ACL。
2. **B1-C**：独立写入venue master和两条固定学生有效费率；固定Manifest、rollback、postdeploy、Git审查。
3. **B1-D**：只处理固定118的人工schedule/venue方案；不得动态扩展，数据库写入需独立授权。
4. **B1-E**：canonical planned writer数据库实施；同一事务收口旧函数与直接写权限，planned-writer gate保持blocked；rollback/whitelist commit test。
5. **B1-F**：API wrapper切换，不改页面业务规则；API不传派生month/duration/fee。
6. **B1-G**：页面交互改造；单条scheduled date、批量明确billing week、可选时间/显式duration、venue code和DB结果展示。
7. **B1-H**：candidate/validation preview适配费用complete状态和新source；保持generate blocked。
8. **B1-I**：formal generate、relation/header同事务写入与双层冻结及不可变保护改造；仍不解除R0。
9. **独立R0解除审查**：完成全链rollback/postdeploy、并发、权限、事故入口和Cash复核后再授权。

schema、配置数据、118写入、writer DB、API、页面、candidate、generate、R0和Git均保持独立授权与停止点。

actual超额月结转入下期账单属于独立事故修复线：不得并入B1-B migration、planned writer切换或空调费计算；仅在未来formal generate最终验收时做兼容性联合验证。

## P. 已批准业务与schema冻结策略

### P.1 已批准业务决定

- 未来canonical planned必须为大于等于2的整数小时；时间完整时由DB计算后校验，无时间时由DB校验显式duration。
- actual可以为小数时长，但不得反写planned；actual超额由独立月结结转流程处理。
- `aircon_billable_hours_snapshot`精确等于已校验的planned整数时长，actual不改变该值，且不使用任何取整函数。
- 固定118已通过上述规则：NULL 0、低于2小时0、非整数0、合法整数118；279 legacy继续保持阶段外。

planned整数及最低2小时check可以进入B1-B设计，但因全体历史planned中存在5条低于2小时和7条非整数，B1-B不得直接添加会立即验证全表的普通VALIDATED约束；只能设计为保护新canonical写入，或采用安全的NOT VALID/trigger策略，且不得修改历史397条。

### P.2 已批准schema与冻结策略

1. **Venue稳定模型**：新建专用venue master，lesson保存nullable venue FK；API提交稳定code并由DB解析ID，中文名称仅为display。`Regus办公室 → regus_office`；公共区、online及其他场地显式配置为不适用。历史文本不自动推断，固定118由后续独立人工阶段填写。
2. **`lesson_fee`兼容语义**：`lesson_fee`继续表示最终总额；新canonical行满足`lesson_fee = base_lesson_fee_jpy + aircon_fee_jpy`。历史component为NULL时保留legacy金额，不用coalesce伪装组件化；candidate、preview、generate独立切换。
3. **账单双层冻结**：normalized relation保存逐课结构化快照并作为主依据，header JSON保存账单级汇总、版本和完整证据；两层由B1-I formal generate同事务生成并一致。B1-B可加法型创建relation列，但历史121条及既有账单不回填。
4. **费率有效期**：采用`[effective_from,effective_to)`；起始日生效、结束日旧费率失效、NULL为开放结束，同一学生区间不得重叠，优先使用`daterange`排斥约束。
5. **同日费率切换**：使用date粒度，同一学生同日只有一个有效费率，新费率从起始日整日生效，不支持日内分段；受控事务关闭旧记录并新增新记录，不覆盖旧单价或旧起始日。
6. **账单后字段保护**：采用canonical RPC预检、数据库trigger最后防线、B1-E撤销客户端直接写及关闭permissive写policy三层保护；正式账单后的排课变化和金额调整走未来独立流程。
7. **金额override**：本轮不开放base、aircon或total通用覆盖，不允许绕过费率/小时规则或由管理员页面改冻结金额；未来需求必须进入独立adjustment/override审计阶段。

上述7项业务和schema策略均已批准，足以让B1-B形成最终DDL设计，不再属于业务未决项。

### P.3 B1-B授权边界与实施前技术停止条件

B1-B仍仅为加法型schema/helper/constraint实施：不得写venue配置或学生费率，不得回填固定118，不得修改279，不得切writer、API/page、candidate或generate，不得提前收口旧RPC/ACL，不得解除R0。relation新增列可在B1-B加法型创建，但formal generate写入、header/relation一致生成和冻结逻辑留在B1-I；权限收口只能在B1-E writer原子切换阶段执行。

实施前仍须核验以下技术事实，它们不是业务未决项：

- `btree_gist`是否已安装或可安全启用；
- 最终真实列名和constraint名是否冲突；
- migration锁范围和运营影响；
- rollback是否可行且残留为0；
- nullable/NOT VALID策略是否保证现有历史行零改写。

任一技术检查失败，B1-B必须停止并返回审查，不得降级约束、扩大范围或修改历史数据。

## Q. 两份工件SHA-256

完成后以最终验收输出为准：

- `docs/school-v2-r1d-d-b1-a-planned-aircon-schema-design-report-20260730.md`
- `sql/current/school_tuition_r1d_d_b1_a_planned_aircon_schema_inventory_readonly.sql`

## R. 数据库只读执行与ROLLBACK证据

初始B1-A调查连接对象仅School数据库`postgres`；临时预检快照时间`2026-07-29 08:14:47.378719+00`，初始工件快照时间`2026-07-29 08:23:27.518092+00`。本次B1-A-E另执行一次固定118 UUID只读预检，以及一次与勘误后交付SQL字节一致的完整inventory；完整工件快照时间为`2026-07-29 08:48:15.504996+00`。全部事务均为`transaction_isolation=repeatable read`、`transaction_read_only=on`，数据库TimeZone为`UTC`，并显式`ROLLBACK`。

输出确认：required objects全存在；R0起止三项均expected；candidate definition起止hash一致；原118/279/candidate三组`all_expected=true`；新增固定118整数兼容断言`all_expected=true`，明细为VALUES 118、唯一UUID 118、命中118、缺失0、合法整数且大于等于2小时118、总时长254、基础费JPY2,474,000、UUID/业务Manifest hash匹配、下游关系全部0，时长分布100条×2小时及18条×3小时；scheduled/billing冲突0。B1-A-E两次只读SQL均无错误并以`ROLLBACK`结束。未调用candidate业务RPC或其他业务RPC，只调用只读catalog/system函数和读取业务表。

数据库DDL 0、DML 0、写入0、测试记录0、whitelist写入不适用、Cash数据库未连接。

## S. Git停止点

本阶段完成后应只出现：

```text
?? docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt
?? docs/school-v2-r1d-d-b1-a-planned-aircon-schema-design-report-20260730.md
?? sql/current/school_tuition_r1d_d_b1_a_planned_aircon_schema_inventory_readonly.sql
```

暂存区必须为空。本阶段不执行`git add`、commit或push，不修改current-status，不进入B1-B，等待ChatGPT与业务负责人审查。
