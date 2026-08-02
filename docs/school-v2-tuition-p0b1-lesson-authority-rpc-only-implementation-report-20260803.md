# School V2 学费财务 P0-B1 实施报告

实施日期：2026-08-03。基线 HEAD `fac5e433e1b85b18db28833447814cb5ec883d93`，parent `87ce609ce717426db4c6e5e7a969435b1a640838`。

## 完成结论

P0-B1 已完成生产部署与验收：lesson 持久化基础课时费由 DB 唯一决定；R2-E aircon/total 与 S1-B overage 继续使用原权威实现；app roles 对 `school_lesson_records` 只剩 SELECT；正式 writer 进入 P0-A 同一 operation namespace 和固定五表锁序；前端/API 不再提交决定性金额。没有重算/回填/修改 729 条真实 lesson，真实财务业务行净变更与过程变更均为 0，Cash 写入 0。

## Business-model expansion declaration

- 新 business table/column/status/date/month/identity/source/snapshot/version/writable fact：`none`。
- 改变既有字段语义：`school_lesson_records.lesson_fee` 及既有 aircon/total bundle 的持久结果改为 DB-only authority；approval：任务 IV、VII。
- 改变 mutability/permission：app roles 失去 lesson table DML/REFERENCES/TRIGGER，保留 SELECT；approval：任务 VI、VII。
- 改变 writer authority：正式 SECDEF RPC + owner-only calculator/guard/trigger helper；approval：任务 IV、VI、VII。
- 改变 locking：lesson writer 加入 `student_tuition_operation_v1`，固定 lesson→settlement→carryover→draft→adjustment；approval：任务 VIII。
- fallback/dual authority/backfill/historical reinterpretation/destructive schema：`none`。

逐项对象、语义、authority、mutability、locking 均被本任务明确列出，Schema And Business Model Expansion Gate 通过；没有将一般实施授权当作缺失的扩展批准。

## DB 权威实现

新增 5 个 owner-only helper/guard（未新增业务表或字段）：

1. `school_tuition_p0b1_lock_lesson_scopes(jsonb)`
2. `school_tuition_p0b1_lock_new_planned_scope(uuid,uuid,date)`
3. `school_tuition_p0b1_lock_new_planned_range(uuid,uuid,date,date)`
4. `school_tuition_p0b1_lock_existing_lesson_scope(uuid,uuid,uuid,date)`
5. `school_tuition_p0b1_lesson_financial_authority()` 与 trigger `trg_school_lesson_p0b1_financial_authority`

基础费用唯一规则来自生产函数/既有报告与实际 729 行核验：planned、ordinary billable actual、partial billable actual均保存 `round(duration_hours * unit_price)`；cancelled/non-billable/makeup履约保存0。舍入只在 PostgreSQL `round(numeric)` 实现。旧金额参数为签名兼容：正值/0/NULL/极值/小数均不决定保存结果；负数在旧 RPC 前置即 fail-closed。历史 no-op/non-fee edit不触发重算，3条既有 nonbillable legacy 非零事实未被改写。

现有 `school_enforce_r2_e_planned_aircon()` 仍唯一计算 base snapshot、aircon charge、whole hours、total 与 policy；actual overage仍由 ordinary writer冻结现有五字段。新 trigger不建立第二套 aircon/overage计算。

## ACL/RLS 与调用边界

部署前：anon/authenticated/service_role 均有 lesson INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER，policy `school_allow_all_lesson_records` 为 public ALL/true/true。

部署后：三角色只有 SELECT；policy 只有 `school_lesson_records_select FOR SELECT TO anon,authenticated,service_role USING(true)`。18个正式签名全部 SECDEF、`search_path=pg_catalog,public`、无意外 PUBLIC execute；历史 import/backfill 与所有 helper owner-only。页面继续通过 `js/api/lesson-api.js`，页面/组件无 `.rpc()` 或表写。

## 前端/API

- planned create、guarded edit、ordinary actual 的 API compatibility 参数固定 `p_lesson_fee:null`。
- planned import payload固定 `lesson_fee:null`，文件金额只保留预览意义。
- planned/actual/makeup/edit 四个金额框只读并标注“DB 保存后确认”；保存后仍显示 DB返回/重新读取的 base、aircon、total、overage 与 billing month/week。
- 删除 4 个决定性 `Math.round(durationHours * unitPrice)` 与所有 manual fee state/validation。
- cache key统一为 `tuition-p0b1-20260803`。本地浏览器 smoke 确认4/4金额框只读，金额/收费构成/冻结超额列仍存在。

## SQL 与测试记录

执行 School DB：

1. `school_tuition_p0b1_lesson_authority_rpc_only_20260803.sql`（正式部署）
2. `school_tuition_p0b1_lesson_authority_rollback_tests_20260803.sql`（18/18，ROLLBACK）
3. `school_tuition_p0b1_lesson_authority_rpc_only_rollback_20260803.sql`（精确 rollback rehearsal，COMMIT）
4. migration 同文件重新部署（COMMIT）
5. `school_tuition_p0b1_lesson_acl_finalizer_20260803.sql`（仅ACL，COMMIT）
6. fixture lifecycle preflight/insert/cleanup/residue
7. 六组 concurrency session A/B（所有会话 ROLLBACK）
8. ACL/RLS inventory、School postdeploy、既有 P0-A postdeploy（只读）

调用的业务 RPC 仅限 rollback/concurrency synthetic：planned create/update、ordinary/partial/cancelled/makeup actual、void、settlement lock、Atomic Generate core。没有对真实业务 ID 调用写 RPC。

18/18 rollback-only矩阵覆盖：金额篡改、负数、planned edit、owner fee/aircon forge、ordinary/overage、partial、makeup、cancelled、weekday/weekend/zero/noneligible aircon、actual-consumed freeze、legacy read、ACL/RLS/lock catalog、三条跨月/年自然周。

六组双会话：Generate×planned edit、Generate×void、Generate×actual、settlement lock×actual、actual×actual、planned edit×actual。B阻塞4.064–4.245秒后完成；无deadlock/timeout/partial write/重复actual/重复bill，A/B均ROLLBACK。

## Fixture、指纹与终态

marker：`codex-test tuition-p0b1-lesson-authority-20260803`。

固定 UUID：entity `b1b10000-0000-4000-8000-00000000e100`、subject `...d100`、teacher `...7100`、student `...a100`、settlement `...b100`、lessons `...1101/...1102/...1103`。提交前 collision/residue 0；fixture仅School DB，测试后逐ID验证归属并精确DELETE；独立 residue 检查为0。

部署前后业务指纹完全一致：lesson `729 / fdddb50d53ff8be527186aa01dc4f710`；settlement `17 / 85c829ebc3bb0a4100393d9c8d6421d7`；bill `17 / b18f15673637280bf1455667ccd3cc00`；bill lesson `256 / dfa2bdb71f812f4b2aa0a23613edf289`；wage detail `556 / 6204dc666b3b8e0f64fac901ecf0686a`；income `50 / dccaf8446c3907b48cec9bf028b4373c`。

Cash只读终态：request `39 / 303e10bc1a28a0abd8b27afd3929cfd8`，CNY `68 / cba640a696f4c7da59d8df2be7fe79e5`，JPY `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`；P0-B1 marker 0，Cash写入0。

P0-A 15/15 canonical validator继续通过；张倬闻 consuming bill仍为 `553a24ba-81cf-4af0-b723-169a09914c79`，异常原样保留。Gate终态 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=blocked`。未开始 P0-B2、Void/Reissue、差额模式或真实修复。
