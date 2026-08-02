# School V2 学费财务 P0-B1 Lesson Writer Inventory

审计日期：2026-08-03。来源：生产 `pg_proc/pg_get_functiondef`、trigger/ACL/RLS catalog、仓库 SQL、`js/api/lesson-api.js`、lesson page/edit dialog 与运维脚本。生产基线 lesson 729 行。

## 结论

- catalog 共命中 27 个名称/定义相关函数；其中 3 个只写 `school_part_time_work_lessons`，排除后是 24 个 `school_lesson_records` 入口/核心，21 个函数直接 DML、3 个 compatibility facade 间接调用核心。
- 日常正式闭包为 18 个签名；10 个最内层或先行取行锁的入口注入 P0-B1 lock，其他 facade 在任何 DML 前进入这些已锁入口。
- 历史导入 3 个签名和 actual-minutes backfill 已从 app roles 撤销；R1D legacy core 原本且继续 owner-only。
- 未发现 actual delete/reverse/void 正式入口。actual 编辑只允许 guarded update；planned 删除、作废、pending_makeup 转换分别由 delete、void、guarded/cancelled/partial 路径完成。
- 页面模块没有 `.rpc()` 或 lesson 表 DML；所有正式调用均先进入 `js/api/lesson-api.js`。

## 写入口闭包

| 类别 | 生产签名/组 | 调用者与字段/金额/月权威 | 部署前 | P0-B1 终态 |
|---|---|---|---|---|
| planned 单条 | `school_create_planned_lesson_record` 14/15参；`...with_venue` 16/17参；owner legacy core 14参 | lesson API；写 planned master、duration/unit、status/count、R1D-F1 billing bundle、R2-E aircon bundle。旧 `p_lesson_fee` 可决定金额；月份由 R1D-F1 trigger | SECDEF，`search_path=public`；部分 PUBLIC execute；无 P0 lock | facade/核心前先锁 new planned natural-week scope；DB trigger 保存 `round(duration*unit)`；正式签名 SECDEF、固定 path、显式 app grants；legacy core owner-only |
| planned 编辑 | `school_update_lesson_record_guarded` 17/18参；`...with_venue` 19/20参 | lesson API/edit dialog；planned 与 eligible actual 受控更新。旧 `p_lesson_fee` 可覆盖；old/new month 由 R1D resolver/自然周 trigger | SECDEF，`search_path=public`；17参有 PUBLIC；with-venue 在调用 core 前先 `FOR UPDATE` | 17参 core 与 19参外层均在任何 row lock 前取得 old/new scope；金额参数忽略，DB按输入变化计算；全部固定 path/ACL |
| planned 批量 | `school_generate_planned_lessons_batch`、`...with_venue`、owner R1D-F1 legacy core | lesson page/API；日期范围+patterns，core 批量 insert，trigger决定周/月/aircon | authenticated/service，`search_path=public`；无 P0 lock | 范围内自然周月份去重排序后共享 P0 namespace；outer facade app-only，core owner-only |
| 历史文件导入 | `school_import_lesson_records_batch`、`...with_venue`、owner legacy core | lesson import UI/API 曾提交 planned rows，包含 client `lesson_fee` | base 有 PUBLIC execute、venue facade app execute | 永久 disabled/owner-only；PUBLIC/anon/authenticated/service execute 全撤销；页面构造 `lesson_fee:null` |
| planned 删除/作废 | `school_delete_fresh_planned_lesson(uuid,timestamptz,boolean)`；`school_void_planned_lesson(uuid,timestamptz,text)` | lesson API dialogs；delete 或写 void/status audit；月由 R1D resolver | SECDEF，path public；void 有 PUBLIC；先 row lock，无 P0 scope | 入口最先取得 existing lesson scope；持锁后原 guard 重读；固定 path/ACL |
| ordinary actual | `school_create_actual_lesson_from_planned(...,p_lesson_fee,...)` | lesson API；source planned、actual duration/unit、R1D-E-B2 student month、teacher month、S1-B overage | client fee 可覆盖；先 planned `FOR UPDATE`，无 P0 scope；PUBLIC execute | 在 source row lock 前锁 source scope；DB billable fee=`round(actual duration*unit)`；overage bundle仍由既有 writer冻结 |
| cancelled actual | `school_create_cancelled_actual_lesson_from_planned(...)` | lesson API；actual cancelled + source planned pending_makeup | fee 0 已由 writer固定；先 row lock，无 P0 scope；PUBLIC execute | source scope 先锁；trigger再次固定 non-billable fee 0；既有 source状态合同不变 |
| partial actual | `school_create_partial_completed_actual_from_planned(...)` | lesson API；actual duration<planned，source改 pending_makeup | DB已 `round(actual duration*source unit)`；无 P0 scope；PUBLIC execute | source scope先锁；表级 DB authority复核/保存同公式 |
| makeup actual | `school_create_lesson_credit_makeup_actual(...)`；current/cross-month 两个 compatibility facade | lesson API；credit remaining、actual fulfillment；source可换 teacher/subject | DB已固定 non-billable fee 0；core先 row lock；PUBLIC execute | source scope先锁；两个 facade经同一 locked core；DB trigger固定0 |
| actual 编辑 | guarded update 同组 | edit dialog/API；status不可改、linked master受限、settlement/wage/overage guards | client fee在eligible actual可覆盖；先 row lock | old/source month scope先锁；billable按duration/unit计算，nonbillable 0；已消费关系表级冻结 |
| 运维/迁移 | `school_backfill_actual_minutes_from_duration(text)` | service/owner运维，直接 update actual minutes | service execute | app/service execute撤销，owner-only；不作为正式 writer |
| 直接表 DML | anon/authenticated/service_role | 任意字段可伪造；public `ALL true` policy | 三角色 INSERT/UPDATE/DELETE/TRUNCATE，另有 REFERENCES/TRIGGER | 三角色仅 SELECT；SELECT-only policy；privileged owner仍受 fee/aircon/week/consumed trigger |

## 统一合同

- 正式函数全部 `SECURITY DEFINER`，`search_path=pg_catalog,public`，撤销 `PUBLIC EXECUTE`，再按既有实际调用角色精确授予。
- 锁 namespace 只使用 `student_tuition_operation_v1`。scope 按 `student UUID → entity UUID → month` 排序；随后固定 `lesson(SHARE ROW EXCLUSIVE) → settlement(SHARE) → carryover(SHARE) → draft(SHARE) → adjustment(SHARE)`。
- DB 基础费用唯一公式：planned 与 billable actual 为 `round(duration_hours * unit_price)`；cancelled、non-billable makeup/non-billable actual 为 0。partial 使用实际时长；ordinary overage 保持既有五字段冻结 bundle，不二算；aircon/total 继续调用 `school_r2_e_calculate_planned_aircon_fee`。
- INSERT 或权威 fee input 变化时重新计算；不含 fee input 的历史/no-op edit 保留 OLD 金额，避免重算历史异常。仅 client `lesson_fee` 变化时忽略该值。actual/bill/consumed settlement/wage relation 已冻结时，收费事实变化稳定拒绝 `LESSON_FINANCIAL_FACT_IMMUTABLE`。

可重跑 catalog 清单：`sql/current/school_tuition_p0b1_lesson_writer_inventory_readonly_20260803.sql`。
