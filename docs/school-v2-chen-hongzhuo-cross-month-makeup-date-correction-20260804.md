# School V2 陈红卓跨月补课日期纠正报告

日期：2026-08-04

## 结果

- 已将错误补课 actual `d1c60932-0f8a-43e3-98b8-bb362921ccf8` 原子替换为 `9d26220e-813a-43da-b48d-1e34cfa9324e`。
- 实际日期由 `2026-07-31` 纠正为 `2026-08-02`，时间仍为 `13:00–14:00`，时长 1 小时，状态仍为 `makeup_completed`，不计费且课时费为 JPY 0。
- 来源 planned 保持 `d4e3e060-1951-4fdd-9340-e6feb6687b7f`；学生、老师、科目、业务归属、内容、备注和既有来源关系保持不变。
- DB 权威归属为：`year_month=2026-07`、`student_settlement_month=2026-07`、`teacher_settlement_month=2026-08`。补课剩余时长仍为 0。
- School 账单、收入及 Cash 请求/交易均未修改。

## 审批与业务模型声明

本任务的业务负责人明确批准：新增并部署 `public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamptz,uuid,date,text,text)`，仅供 `service_role` 调用；在严格并发断言和财务/结算/Cash 零引用闸门下，原子删除唯一错误且未被下游消费的补课 actual，并复用既有 `school_create_lesson_credit_makeup_actual` 创建正确记录。

Business-model expansion declaration：

- 新对象/权威：上述 service-role-only 受控纠正 writer，完全对应本任务当前审批。
- 新表、业务列、状态、日期/月份概念、fallback、dual write、历史解释、前端权威：`none`。
- 未新增审计表；本报告、writer 的 fail-closed 结果和 Git/SQL 证据构成本次纠正证据。

## 实现与权限

- SQL：`sql/current/school_replace_unconsumed_makeup_actual_v1_20260804.sql`
- postdeploy：`sql/current/school_replace_unconsumed_makeup_actual_v1_postdeploy_20260804.sql`
- rollback matrix：`sql/current/school_replace_unconsumed_makeup_actual_v1_rollback_tests_20260804.sql`
- whitelist commit test：`sql/current/school_replace_unconsumed_makeup_actual_v1_commit_test_20260804.sql`
- 受信管理工具：`scripts/manage-chen-hongzhuo-makeup-correction.zsh`

writer 使用 `SECURITY DEFINER`、固定安全 search path、`auth.role()=service_role`、目标 UUID/来源 UUID/正确日期/原因/确认文本/`updated_at` 并发断言，并在同一事务中检查工资锁、学生月结、variance claim、学费 relation、legacy evidence、historical exclusion、migration item、Cash UUID 引用等阻断条件。PUBLIC、anon、authenticated 均无 EXECUTE；仅 service_role 可执行。最终部署函数定义 MD5 为 `a78f179ec781467e030260a0ac62e35d`。

跨月月份规则完全复用当前 DB authority：actual 的 `year_month` 与 `student_settlement_month` 继承来源 planned 的 2026-07；`teacher_settlement_month` 按 actual 发生日期得到 2026-08。页面没有计算或提交这些持久化业务事实。

## SQL 与测试

按 School DB 流程执行：

1. writer SQL `makeup_replacement_commit=0` rehearsal：ROLLBACK。
2. writer SQL `makeup_replacement_commit=1`：正式 COMMIT。
3. postdeploy：最终通过，函数、owner、安全属性、search path、ACL 与定义哈希匹配。
4. rollback matrix：全部通过并 ROLLBACK。测试 source/original/wrong/new 分别为 `5ad59426-4319-4ff1-8549-e93b3cc4495f`、`10b251ab-b921-463b-a1d5-6ef65d36c89b`、`47dfe0a6-df34-4c38-9d9d-ece84fed2ade`、`a597ecd4-08f5-49db-9695-e080505452e8`。
5. whitelist commit test：通过并在同一事务内清理，最终 residue 0。测试 source/original/wrong/new 分别为 `12182097-c752-4ba8-856f-3d91a39aad85`、`04729308-65d1-41b1-937c-1dd96e1b7f14`、`39472ccd-b99f-47be-b0e2-7a1ef4a0c2c0`、`3b63531a-1fe7-4444-aa37-22d381863189`。

测试夹具构造与初始归属断言曾触发既有 claim/Cash fixture guard 和当前 DB 跨月归属规则；每次失败均在完整事务内回滚、残留 0。修正测试夹具与断言后重新 rehearsal、正式部署、postdeploy、rollback matrix 和 whitelist commit test 均通过。未修改业务模型。

## 前端指引与验收

- `lesson.html` 明确提示“请在补课实际发生月份登记；来源课程可以选择以前月份”。
- `js/pages/lesson-page.js` 在日期不属于当前页面月份时提示先切换到实际发生月份，再从“来源月份”选择原待补月份。
- 页面仍经 `js/api` 调用既有普通补课创建 API；page module 直接 RPC/DML 为 0，纠正 writer 不暴露给页面。
- 版本升级为 `v10.5.2`，Pages run `30868770343` 成功。
- 静态检查、Node syntax、`git diff --check` 和 `scripts/makeup-actual-correction-static-test.mjs` 全部通过。
- 生产 Chrome 验收：八月页面可选择七月来源；输入 `2026-07-31` 时显示完整切月提示并在本地校验处停止，未发出业务写入。纠正后七月学生结算视图显示新 actual 为 `2026/08/02 13:00–14:00`、已补课、不计费、学生结算月 2026-07、老师工资月 2026-08。

## 生产执行与不变量

正式调用：

`public.school_replace_unconsumed_makeup_actual_v1(d1c60932-0f8a-43e3-98b8-bb362921ccf8, 2026-08-04 00:19:03.535682+00, d4e3e060-1951-4fdd-9340-e6feb6687b7f, 2026-08-02, approved_reason, REPLACE_UNCONSUMED_MAKEUP_ACTUAL)`

返回 `MAKEUP_ACTUAL_REPLACEMENT_COMPLETED`，新 actual 为 `9d26220e-813a-43da-b48d-1e34cfa9324e`。

事后只读验证：

- 旧 UUID count 0；精确新记录 count 1；来源 linked actual count 2；remaining hours 0。
- 新记录 MD5 `37d9ac62137fe8c691ecc81ddb572405`。
- 来源 MD5 继续为 `349111f8a6818c44a0cf4e1886cda97d`；原 2026-07-20 actual MD5 继续为 `0813f33689c87d799fe967826e37a8a2`。
- wage detail、settlement、claim、actual bill relation、legacy evidence、historical exclusion、migration count 均为 0。
- 学费 bill `7472f73f-fa19-4565-9180-a517c7151835` MD5 继续为 `bfa62da082009fbcef7fa8612152fc0a`；income `3a5542c5-5397-4688-999e-a08bb678f40d` MD5 继续为 `9071f5eb1b0ad2c0108b6673e375f751`。
- Cash 对旧/新 actual UUID 的请求/CNY/JPY引用均为 0；approved request 与 confirmed transaction MD5 继续为 `79628a382d3caaec9f141def2cb00a0e`、`ef8f684fc432c1137ca2747df9d8834d`。
- Gate 继续为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`。

## Git

- `a153a9f` — `feat(school): add controlled makeup actual correction`
- `e931281` — `fix(school): clarify cross-month makeup entry`
- 功能分支 `codex/chen-hongzhuo-makeup-date-fix` 已推送，并以 fast-forward 合并/推送到 `main`。
