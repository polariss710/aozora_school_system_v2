# School V2 R2-E planned lesson 独立空调费实施报告

日期：2026-07-31
阶段：R2-E
目标停止点：R2-E Git交付完成（不得自动进入下一阶段）

## 1. 基线与边界

- branch：`main`
- HEAD / origin/main：`b1f117bd95623feb7096674263f4862376e726c1`
- 初始暂存区为空。
- 唯一初始未跟踪保护文件：`docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`
- 保护文件 SHA-256：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- 全程不读取保护文件正文，不修改、移动、暂存或提交。
- School DB 通过 `load_both_db` 加载；未使用 `SUPABASE_DB_URL`，未连接 Cash。

## 2. Inventory 结论

- 现有 `school_lesson_records` 已有 nullable 的 base/aircon/policy/frozen 组件骨架，但全部 lesson 组件为空。
- 旧 `school_student_aircon_rates` 与 `school_lesson_venues` 均为 0 行；旧 calculator 会按学生有效期费率和 venue 决定空调费，与本阶段规则冲突。
- 本阶段复用 lesson 上的 `aircon_unit_price_jpy_snapshot` 作为每条 planned 独立保存的 JPY/hour 费率，不创建学生级动态费率。
- `lesson_fee` 当前是基础课时费权威值，本阶段保持该语义；新增 `lesson_total_fee_jpy` 保存 base + aircon 的 DB 权威总价。
- 8 个 F1 planned 入口为 single/batch/import 的 core 与 venue wrapper，以及 guarded update core 与 venue wrapper。
- 批量生成旧链把 `lesson_date` 保存为收费周周一。R2-E 只对切换后新批量记录保留原 canonical billing week，同时把 `lesson_date` 改为规则实际星期，确保周六/周日可由 DB 判定；不修改历史记录。
- R0 初始状态保持 `validation_preview_only / blocked / blocked`。

## 3. 数据库设计

- policy：`planned_weekend_aircon_v1`
- DB 输入：planned date、student settlement month、planned integer duration、既有 base `lesson_fee`、每条 planned 独立 rate。
- DB 输出：base snapshot、saved rate、planned hours snapshot、aircon fee、total、status、reason、policy、decided time。
- 生效：`student_settlement_month >= 2026-08` 且 `lesson_date` 为周六/周日且 rate > 0。
- 工作日、NULL date、2026-07 及以前、rate=0 均保存 rate 但 aircon fee 为 0。
- actual 行所有 planned aircon 字段必须为空；actual date/duration、partial/cancelled/makeup/overage 不参与 planned fee calculation。
- 旧学生级 calculator 改为 fail-closed；旧学生费率表与 venue 表保持空。
- 新 planned INSERT 取得完整 zero bundle；历史 NULL bundle不批量回填，显式编辑 rate 后才组件化。
- direct table 只允许 rate/date/duration/base 的合法业务输入；伪造 fee/total/policy/time 或 partial bundle 被拒绝。
- normalized bill relation、bill JSON、locked settlement 或 frozen component 存在时，影响 charge 的字段不可修改。
- bill relation新增完整组件与 `lesson_fee_jpy_snapshot = base + aircon` 约束；历史 121 行组件 NULL，保持不变。

## 4. 学费链与前端

- 新 canonical charge candidate reader复用既有 fail-closed candidate classifier，显式返回 base/rate/aircon/total。
- validation preview summary与明细使用同一次 DB snapshot；UUID 唯一性、month/week、manifest SHA-256和 summary/detail 一致性继续 fail-closed。
- 旧历史 NULL bundle静默按 base-only 返回，避免补收费。
- formal generate仍被 R0 阻断；未来解除 gate 时必须从 canonical charge candidate reader取得 total，并按 relation/JSON contract冻结组件。
- 单条 planned 新增、编辑与批量默认费率均只提交 rate；页面不提交 aircon fee 或 total。
- planned 列表与详情展示 base/rate/condition/aircon/total；actual 详情只展示 source planned 收费事实。
- 保存成功后沿既有 refresh 链重新读取 DB 行；preview保留最新请求 gate，旧响应不能覆盖当前选择。
- 页面模块没有新增直接 `.rpc()`、`.from()` 或 table write；RPC保持在 `js/api`。
- `js/legacy-core.js` 未修改。

## 5. 工件

- `income.html`
- `lesson.html`
- `js/api/lesson-api.js`
- `js/api/lesson-detail-api.js`
- `js/components/lesson-edit-dialog.js`
- `js/pages/income-page.js`
- `js/pages/lesson-detail-page.js`
- `js/pages/lesson-page.js`
- `js/utils/tuition-validation-preview.js`
- `scripts/planned-aircon-ui-test.mjs`
- `scripts/tuition-validation-preview-ui-test.mjs`
- `sql/current/school_tuition_r2_e_planned_aircon_fee_cutover.sql`
- `sql/current/school_tuition_r2_e_planned_aircon_fee_postdeploy.sql`
- `sql/current/school_tuition_r2_e_planned_aircon_fee_rollback_tests.sql`
- `sql/current/school_tuition_r2_e_validation_preview_rpc_correction.sql`
- `sql/current/school_tuition_r2_e_guarded_update_overload_correction.sql`
- `docs/school-v2-r2-e-planned-aircon-fee-report-20260731.md`
- `docs/current-status.md`（最小阶段状态更新）

## 6. 执行与修正记录

- 原 R2-E cutover 先完成同字节 rehearsal并明确回滚，随后只正式执行一次并 COMMIT。之后绝对没有重新执行原 cutover。
- 原 cutover COMMIT只持久化 schema、RPC、trigger和约束，没有业务数据 DML。
- 首次 postdeploy调用
  `school_get_student_tuition_validation_preview_details(uuid,text,numeric)`
  时发现最终 CTE读取的未限定`candidate_count`与`RETURNS TABLE`输出变量重名；同一 SELECT中的`candidates`也是同类潜在冲突。
- 原 cutover源文件将该 SELECT的11个聚合列统一改为`aggregated.<column>`，不改变候选、月份、金额或返回结构。
- 独立 preview纠正 SQL：
  `school_tuition_r2_e_validation_preview_rpc_correction.sql`，
  SHA-256
  `af33c79dc6b5637d4f31f8981f713ef04f144e065bf2b82cafc28d075830b31d`。
  合格 rehearsal实际调用目标 preview后明确 ROLLBACK；同字节正式执行一次并 COMMIT。
  定义 MD5由`a9f7bf4ab6b4aa323af699dd61e94ba7`变为
  `b2b111670954f06a40f16d20163ab3d7`，签名、ACL、owner、STABLE、
  SECURITY DEFINER、search path和注释不变。
- rollback测试随后发现 R2-E新增
  `school_update_lesson_record_guarded(...,integer)` overload中的未限定
  `lesson_type`与输出变量重名。原 cutover源文件改为
  `lesson.lesson_type`，两个相关`id`条件也用`lesson.id`限定。
- 独立 guarded-update纠正 SQL：
  `school_tuition_r2_e_guarded_update_overload_correction.sql`，
  SHA-256
  `a91c19583ab3e70f697dec170a4f01cf1568aaeb8579664d93c9a68b7387f423`。
  合格 rehearsal fixture
  `cca5b56c-b319-484d-a373-6b8ba7537754`
  实际调用写入 overload并得到
  base/rate/aircon/total=`17000/330/660/17660`，fixture子事务回滚，
  外层明确 ROLLBACK。正式同字节执行 fixture
  `820bd910-1a84-48ce-b39b-0a00a05f96ef`，相同结果且子事务回滚，
  只 COMMIT函数定义。定义 MD5由
  `11e1758978fc3288a2d9a2b1079a0cf9`变为
  `ff54806fc8ee98e415c122e78e1984be`。
- rollback fixture曾把`2032-08-09`（周一）误当作周末，已按真实星期改为
  `2032-08-08`（周日）。这只修正测试数据，不改变业务规则。
- 最终完整 postdeploy通过并明确 ROLLBACK。
- 最终完整 rollback tests六组全部通过，动态 fixture UUID已输出；
  外层明确 ROLLBACK，后续只读残留检查为0。
- 正式数据库持久化写入只有原 cutover对象和两次独立函数定义纠正；
  没有 lesson、bill、income、settlement、wage、overage、Cash或其他业务数据写入。

## 7. 最终验收

### 7.1 Candidate / preview

- `candidate_count=30`表示30个唯一 planned收费行。
- `lesson_count=35`是各收费行业务回数之和，与 candidate行数属于不同口径。
- planned UUID唯一数、billing identity唯一数均为30，没有候选重复。
- 直接 candidate与validation preview一致：
  duration=`65`、base=`650000`、aircon=`0`、total=`650000` JPY。
- 每条事实满足`lesson_total_fee_jpy = base_lesson_fee_jpy + aircon_fee_jpy`；
  明细 JSON为30行，没有重复累计。
- 2026-08-01/02归属学生结算月2026-07，空调费为0；
  2026-09-05/06归属学生结算月2026-08，rate 330、2小时的空调费为660。

### 7.2 Rollback / postdeploy

- postdeploy函数 MD5：
  calculator=`842a2000b6a7aaa64750a0577877181b`，
  charge candidate=`e79f8b9d562837417d7daf588f2a340b`，
  preview=`8e9496463c1d54247f25042be3f6e5c5`，
  preview details=`b2b111670954f06a40f16d20163ab3d7`。
- rollback tests通过
  `writer_entries / date_month_amount / direct_invariant /
  actual_isolation / preview_contract / r0_and_history`六组矩阵。
- 所有测试写入仅在`codex-test`/`e200...`白名单事务中发生，
  全部回滚；最终持久化测试记录0。

### 7.3 前端

- 所有修改 JS和测试脚本`node --check`通过。
- `planned-aircon-ui-test.mjs`通过。
- `tuition-validation-preview-ui-test.mjs`通过。
- 本地页面级验收确认 lesson、income、lesson-detail模块正常加载且无目标模块控制台错误。
- planned编辑框中的空调费率可编辑，默认0，提示明确说明只提交rate，fee/total由DB决定。
- actual编辑框中的空调费率为空且只读，不会写入planned空调事实。
- income页面保持“生成应收（维护中）”禁用，validation preview说明明确不会创建
  bill、income或Cash请求。
- 本地浏览器没有 School登录态，UI实际 preview调用按ACL被拒绝；
  没有输入或使用凭据。目标 preview真实调用已由同字节纠正 SQL、
  完整postdeploy、rollback tests和最终只读验收独立通过。

### 7.4 业务零漂移与R0

- lesson：`654`，全行哈希
  `9a787d2819b24fe4dece792b55b35ba5`。
- bill：`9`，哈希`b91c381ea7c42d8dc60e8a6af189f86a`。
- income：`42`，哈希`3ee88b3e883359e819a93d80ea0204b2`。
- bill relation：`121`，哈希`ff626f1677571c76406b4bc7b5122391`。
- settlement：`15`，哈希`44446ca9a3aa8fa7672e31d9ec25352c`。
- wage detail：`556`，哈希`6d68749bc1f0fbb908d2dfdb43dcc774`。
- 历史 legacy overage仍为19条、时长差9.20小时、旧fee差JPY119,600，
  空调字段0，子集哈希`499723726f4b8ed8024b330925616e39`。
- 正式 R2-E历史组件行0、actual空调组件行0、student dynamic rate和venue均0。
- R0保持
  `student_tuition_preview=validation_preview_only`、
  `student_tuition_generate=blocked`、
  `student_tuition_cash_submit=blocked`。
- 未连接Cash、未执行真实generate、未进入历史canonical化。

### 7.5 Planned-only import定向验收

- `school_import_lesson_records_batch(uuid,text,text,jsonb,text)`沿用既有
  planned-only V1契约，只接受`lesson_type=planned`及
  `status=planned / pending_makeup`；actual、partial、makeup、cancelled均不在
  业务契约内。
- 最终rollback tests中的import core及venue fixture都是planned；
  `actual_isolation`通过ordinary actual writer验证，并未通过import RPC导入actual。
- 补充精确RPC事务测试：2.25小时actual先被planned duration resolver拒绝；
  使用符合planned时长规则的2小时后，actual、partial、makeup、cancelled均由
  legacy core返回`row_valid=false / batch_committed=false /
  created_lesson_id=NULL`及既有planned-only错误。
- 因`batch_committed=false`且无created lesson，wrapper的后置空调费率
  `UPDATE`不可达，不会触发actual空调字段约束；ROLLBACK前后测试残留均为0。
- 临时测试脚本仅位于
  `/private/tmp/r2e_import_nonplanned_compatibility_rollback.sql`，
  不属于仓库交付。该定向验收没有发现受支持业务回归，未修改或重新部署RPC。

### 7.6 Git交付前检查与停止点

- `git diff --check`和`git diff --cached --check`通过，暂存区为空。
- HEAD / origin/main仍为
  `b1f117bd95623feb7096674263f4862376e726c1`。
- Git交付只允许提交第5节工件，并使用普通push；提交及push结果在最终交付回报中记录。
- 保护文件仅复核SHA，正文未读取、未修改、未移动、未暂存：
  `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。
- Git交付完成后停止，不自动进入下一阶段。
