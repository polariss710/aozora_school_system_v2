# School V2 Phase 2C-C-R2：Clearance候选与跨月投影只读Reader合同闭合

状态：已完成生产部署、只读验收及零业务变化复核；前端未修改；真实clearance writer调用0。

## Business-model expansion declaration

- New tables: none
- New columns: none
- New enum/status values: none
- New date/month/attribution concepts: none；仅返回既有来源月、履约月、学生结算月和老师工资月。
- New identity concepts: none；仅返回既有lesson、package、student及business entity UUID。
- New source concepts: none；普通待补、ordinary actual overage、package credit及cross-month makeup来源语义均已部署。
- New snapshot/version concepts: none；V2是技术返回合同版本，fingerprint和evidence status均为只读当前证据，不持久化新快照。
- New writable facts: none
- Changed existing-field semantics: none
- Changed field mutability: none
- Changed writer or reader authority: 新增四个versioned candidate/projection reader和一个dashboard summary，作为后续Phase 2C-D首次加载的唯一DB读取合同；旧reader保留兼容但后续页面不得fallback或双读。底层权威表、helper、R1 Preview/history及writer不变。
- Changed locking rules: none；reader仅报告create writer当前使用的physical settlement lock及active claim阻断，forward目标仍只由Preview V2决定。
- New authoritative sources: none；余额继续以既有lesson、claim、clearance detail、package lot及writer helper为权威。
- Legacy fallbacks or dual-read rules: none；旧reader不作为新页面fallback。
- Dual-write behavior: none
- Historical reinterpretation: none
- Destructive schema changes: none

Approval reference：当前任务第Ⅱ、Ⅳ至ⅩⅢ、ⅩⅥ节明确批准新增versioned只读reader、display name、余额分解、证据状态、确定性排序及summary，并要求后续页面只使用新reader。其余项目无业务模型扩张，无需额外批准。

## 实时基线

- Git：`c7ee66a4634791e6613b5b10fee7bea2e93ab6f5`，与`origin/main`一致。
- 生产版本：`v10.5.47`，本阶段不修改前端版本或缓存链。
- lesson：772行，MD5 `9b393f82ac424ac9df30234fbf44617d`。
- clearance主表／明细表：0／0。
- 普通待补：21源／2400分钟，manifest `e84826a9fce083075f52ef564983e104`。
- overage：4源／135分钟，manifest `a4d05da6063f4ff55587b8c3ad06498a`。
- P002：1200／0／1200分钟，lot MD5 `21e6453eddc240c626c0ba50eafbe72f`。
- R1 history：空。

## 权威与分解原则

- Pending `remaining_minutes`必须等于`school_get_lesson_clearance_pending_remaining_minutes`；分项在同一DB查询中按相同来源计算。
- Overage `available_minutes`必须等于`school_get_lesson_clearance_overtime_remaining_minutes`。
- clearance分解：非reversal行计入gross allocated，reversal行计入gross reversed；writer helper的net allocated为二者之差。
- active claim分钟来自immutable claim的`abs(source_hours) * 60`；active claim存在时当前可分配固定为0，不能按部分差额继续分配。
- display name使用已部署R1同一当前master规则；证据标记为`current_reference`，master缺失时保留UUID、name为NULL并标记`unavailable`。
- `is_locked`仅表示create writer当前使用的对应学生／业务归属／来源月physical locked settlement。active claim另列blocker；不把revision等writer未使用的事实伪装成lock。
- forward destination、same/cross teacher/subject及最终可执行性仍由选择后的Preview V2返回。

机器可检查的首次加载字段总清单见`docs/school-v2-phase2c-c-r2-clearance-reader-field-closure-20260817.json`。

## 旧合同缺口与最终对象

旧candidate/package/cross-month reader只满足后端初版选择，缺少完整display identity、余额gross分解、claim/lock/candidate blocker、evidence、稳定排序、source fingerprint和一次性页面汇总；页面若直接接入将需要master/lesson补查或自行反算余额。R2保留旧reader、R1 Preview/history及writer原定义/ACL，新增以下只读合同：

| RPC | 定义MD5 |
|---|---|
| `school_list_lesson_clearance_pending_balances_v2(uuid,boolean)` | `94dcc95f7c64325e77ea5fa326dc5d05` |
| `school_list_lesson_clearance_available_overages_v2(uuid,boolean)` | `ec54e9c7922c39089028b9ebcf0c340a` |
| `school_list_student_package_credit_lots_v2(uuid)` | `08f691e9ef9db06da0d8921ce7d8fb9a` |
| `school_list_cross_month_makeup_projection_v2(uuid,text)` | `ea91f56375992bb3c788975ee9787297` |
| `school_get_lesson_clearance_dashboard_summary_v1(uuid)` | `83c07aea007dea0f7eb0792fd36334dd` |

五个函数均为`postgres` owner、`SECURITY DEFINER`、`STABLE`、固定`search_path=pg_catalog, public`；ACL仅`postgres`和`authenticated`有EXECUTE，PUBLIC/anon/service_role无EXECUTE。函数内继续复用`school_assert_lesson_clearance_reader`，仅active admin/operator/read_only可读。生产当前仅存在1名active admin，因此真实生产payload由该admin只读验收；operator/read_only、inactive、无membership、anon和service_role矩阵由生产事务内synthetic membership rehearsal及本地隔离角色矩阵证明，未放宽表ACL/RLS。

## 生产JSON样例

以下为postdeploy只读调用的代表项摘要；完整字段集合由字段闭合JSON和postdeploy逐字段断言固化。

```json
{
  "pending_source_planned_id": "8870f57f-bca5-4114-90db-ee592cca2f45",
  "student_display_name": "袁振轩",
  "teacher_display_name": "李雯coco",
  "subject_display_name": "TOEFL",
  "initial_credit_minutes": 120,
  "makeup_consumed_minutes": 60,
  "clearance_allocated_minutes": 0,
  "clearance_reversed_minutes": 0,
  "active_claimed_minutes": 0,
  "remaining_minutes": 60,
  "currently_allocatable_minutes": 60,
  "is_locked": false,
  "fifo_rank": 1,
  "evidence_status": "current_derived",
  "balance_matches_writer_helper": true
}
```

```json
{
  "overtime_source_actual_id": "4a1b74c6-65f0-4513-9c1e-4a094b7bb393",
  "student_display_name": "张倬闻",
  "teacher_display_name": "赵天歌",
  "subject_display_name": "EJU日语",
  "frozen_overtime_minutes": 15,
  "active_claimed_minutes": 0,
  "clearance_allocated_minutes": 0,
  "clearance_reversed_minutes": 0,
  "available_minutes": 15,
  "currently_allocatable_minutes": 15,
  "frozen_amount_jpy": 2500,
  "available_amount_jpy": 2500.00,
  "is_locked": false,
  "balance_matches_writer_helper": true
}
```

```json
{
  "package_lot_id": "2a000000-0000-4000-8000-202608170002",
  "origin_planned_lesson_id": "8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9",
  "student_display_name": "李天伦",
  "package_business_type": "package_credit",
  "package_display_label": "套餐余额",
  "initial_minutes": 1200,
  "consumed_minutes": 0,
  "remaining_minutes": 1200,
  "can_consume": false,
  "can_reserve": false,
  "read_only": true,
  "evidence_status": "immutable_reference"
}
```

```json
{
  "actual_lesson_id": "bd07e78c-eeaf-4881-9bd7-6b80bde0f11b",
  "source_planned_lesson_id": "387ce189-f465-4c33-8a38-b3a830f0552a",
  "student_display_name": "李天伦",
  "source_month": "2026-02",
  "actual_month": "2026-05",
  "actual_minutes": 120,
  "source_teacher_display_name": "吴峰",
  "actual_teacher_display_name": "吴峰",
  "source_subject_display_name": "EJU数学",
  "actual_subject_display_name": "EJU数学",
  "source_view_lesson_id": "387ce189-f465-4c33-8a38-b3a830f0552a",
  "actual_view_lesson_id": "bd07e78c-eeaf-4881-9bd7-6b80bde0f11b",
  "view_mode": "pair",
  "evidence_status": "current_derived"
}
```

跨月本地/生产rehearsal另验证source与actual老师不同、科目不同仍分别返回两个DB identity；同一actual仅一项，clearance和P002均不进入该reader。

## 余额、锁、名称与排序合同

- Pending：`initial - makeup consumed - gross clearance allocated + gross reversal`与既有pending remaining helper逐行相等；active claim独立返回并使`currently_allocatable_minutes=0`，页面不得自行套公式。
- Overage：frozen、gross allocated、gross reversal及active claim分别返回，`available_minutes`逐行与既有overtime remaining helper相等；JPY由DB按权威单价/冻结金额返回。
- 名称：student/entity/teacher/subject均在同一set-based DB查询中读取当前master，标记`current_reference`；缺master仍保留UUID和整行，名称NULL且证据`unavailable`。package origin为`immutable_reference`。
- Locked：与create writer相同的student/entity/source month physical locked settlement判定；active successor claim作为独立blocker，不伪装成physical lock；forward目的仍由Preview V2唯一决定。
- Pending FIFO：按student/entity分区，`credit_origin_sort_at`优先causal actual created_at，稳定fallback为planned updated/created，再以UUID打破平局；active claimed和非正余额不进入rank。
- Overage排序：student/entity、student settlement month、actual date、actual created/frozen time、UUID；`display_rank`由DB返回。

## Summary与字段闭合

生产dashboard summary为：pending 21源、initial 2640分钟、makeup consumed 240分钟、clearance allocated/reversed 0/0、remaining/allocatable 2400/2400；overage 4源、frozen/available 135/135分钟、allocated/reversed 0/0；package 1批/remaining 1200分钟；history 0。

`docs/school-v2-phase2c-c-r2-clearance-reader-field-closure-20260817.json`逐项映射Phase 2C-B首次加载、R1 Preview/history及reversal Preview的required/provided/source/evidence；Node Gate结果为`missing_fields=[]`。页面无需master或lesson补查、无需N+1、无需伪造Preview、不得反算余额；旧reader不作为fallback。

## 测试、Rehearsal与回滚

- 静态：R2字段闭合/SQL安全、既有Phase 2C-C、R1和P002回归全部通过；两个R2 Node文件语法及`git diff --check`通过。
- 本地：一次性PostgreSQL完成40项reader功能、缺master、P002、角色矩阵、旧合同回归和exact rollback，输出`SCHOOL_PHASE2C_C_R2_CLEARANCE_CANDIDATE_READERS_LOCAL_POSTGRES_PASS`；全部fixture随本地集群销毁。
- Production Attempt 1：跨月fixture把周五误作`billing_week_start_date`，触发既有周一CHECK；连接退出完整回滚，独立函数/fixture/全业务指纹复核无变化。
- Attempt 2：两个overage actual误共用一个planned，触发既有唯一约束；完整回滚和独立指纹通过；改为两个精确planned source。
- Attempt 3：跨月pending source使用1小时，触发既有canonical planned duration guard；完整回滚和独立指纹通过；source改为标准2小时、actual保留1小时。
- Attempt 4：五reader、余额分解、名称缺失、lock/claim、FIFO、P002、跨月、Preview/history回归、权限矩阵、exact rollback全部通过，末尾显式ROLLBACK；独立连接确认5个新函数不存在、fixture残留0、业务指纹不变。
- exact rollback文件精确删除五个新增versioned函数并断言旧reader、Preview/history和writer MD5恢复；生产Attempt 4已在同事务中验证。
- postdeploy首次因只读事务禁止`CREATE TEMP TABLE`在业务断言前停止；改为PL/pgSQL局部JSON变量和直接稳定reader调用后完整通过，未改变部署函数。

## 正式部署与性能

正式执行`school_phase2c_c_r2_clearance_candidate_readers_migration_20260817.sql`一次并COMMIT；对象变化仅5个只读RPC、ACL和comment，无新helper、表、列、索引或业务行。部署后只调用五个reader，真实create/reversal writer均0。

`EXPLAIN (ANALYZE,BUFFERS)`当前全量：pending约29.096ms、overage约6.343ms、cross-month约9.749ms；均为set-based查询，无页面逐行RPC或master N+1，当前数据量无明显笛卡尔积。无新增索引。

## 生产零业务变化

部署前后全部一致：lessons 772/`9b393f82ac424ac9df30234fbf44617d`；settlements 18/`481ffa7ed5173da852f0f28ce66c2e9b`；claims 2/`fbce39067e6d98167cdb474eb9635c92`；bills 22/`e50673ac998ee2d84573a076a64d3d42`；bill lessons 330/`e3e2e0044c17864bc66c7e2861176c8b`；revisions 20/`ffdc498a6e256aa29064f021f22e4b00`；income 56/`5410e66708a01d7017de7dc331d32674`；School Cash linkages 44/`f1c336c43533b9d9b81d88b6fa55feef`；wage locks 104/`bb9d5e027e482547ba4ca58b3731651a`；wage details 624/`b68ada9b934d4de511da93104228eb4b`；package lots 1/`8c2b70b087164e5d03defed8cd237f34`；School Storage 57/`62fac5521274c58c6f6982a0c690c134`；Gate 3/`b04952a0603194dd5592124bdee2f7d7`。clearance主/明细仍0/0；普通待补21/2400、overage 4/135、P002 1200/0/1200均不变。

Cash DB仍为CNY流水75/`b5d8b7d466532b90531814e5ccf61ad2`、external requests 44/`1fc51497aedfaecd72a2ee85714284f0`、Storage 0/空集MD5 `d41d8cd98f00b204e9800998ecf8427e`。生产页面、JS、版本和缓存链均未修改，仍为`v10.5.47`。

## 文件、保护边界与后续结论

本阶段提交migration、exact rollback、preflight、rehearsal、postrehearsal、postdeploy、两份本地SQL、角色矩阵、两个Node测试、字段闭合JSON及本报告；不提交Phase 2C-A/B草案、其他untracked文件或截图。原11份受保护untracked文件路径和SHA-256与Phase 2C-C基线逐项一致。

结论：R2字段闭合Gate通过，`missing_fields=[]`，允许在新的独立Phase 2C-D授权中恢复页面接入；页面必须只消费R2 versioned reader、R1 Preview/history及reversal Preview，不得fallback旧reader、补查master/lesson或前端反算余额。本阶段在后端部署和Git交付后停止，不进入页面接入或真实清偿。
