# 老师工资生成设计与 DB/RPC checkpoint

Status: MVP implemented; payment request generation implemented; guarded unpaid snapshot void implemented; payment confirmation account-type boundary verified; snapshot wording aligned; current-month generation safety documented
Date: 2026-06-11

## 目标

本设计用于启动“老师工资生成”模块的 guarded workflow。最初阶段只调查现状、整理边界和建议 MVP；2026-06-10 后续 DB/RPC phase 已实现工资生成 MVP 的 guarded RPC，同日 API/UI phase 已把生成入口接入 `wage.html`，并在后续阶段把工资快照生成待支付请求接入 `wage-detail.html`。v2 不再提供单独的用户侧二次固化步骤：生成工资本身就是生成并固化工资结算快照。2026-06-11 已补齐未支付/未请求工资快照的 guarded void 入口；业务归属单独生成、restore/reissue beyond void、金额实时预览仍是后续单独设计。

## Snapshot wording and flow checkpoint

2026-06-10 UI/docs 文案已统一到工资快照流程：

- `actual` 课时进入工资口径。
- `wage.html` 生成老师工资快照，生成动作本身即固化工资结算快照。
- `wage-detail.html` 从工资快照生成一条待支付请求。
- `index.html` 老师工资支付页面确认支付并选择账户。
- 支付确认生成 teacher_wage 支出和账户流水。
- 公司账户支付工资：支出 `reimbursement_status = not_required`。
- 垫付/个人账户支付工资：支出 `reimbursement_status = pending`。
- 报销流程只处理公司账户归还垫付账户，不再次生成 teacher_wage 工资支出。
- 底层表名、字段名和状态值仍保留 `school_teacher_wage_locks`、`locked_at`、`status = locked`，这是当前 schema 实现细节，不代表 UI 还有一个单独锁定操作。

## Current-month generation safety checkpoint

2026-06-11 对测试提前生成的真实 2026-06 老师工资快照完成一次性 guarded rollback：

- 目标为 9 个 2026-06 `locked` 工资快照、21 条工资明细、JPY `193975`，来源 actual 课时 21 条、actual minutes `2475`。
- 执行前确认目标快照没有 teacher_wage payment request、paid expense、linked account transaction、detail adjustment。
- 先在事务内运行 `school_rollback_test_generated_202606_teacher_wages.sql` 并 rollback，确认可删除 21 条明细和 9 个快照、课时编辑 blocker 清零，rollback 后原状态恢复。
- 持久执行同一 SQL 后，只删除目标 `school_teacher_wage_lock_details` 与 `school_teacher_wage_locks`；没有修改 `school_lesson_records`、`actual_minutes`、支付请求、支出、账户流水、账户、收入或学生结算。
- 回退后 2026-06 工资快照为 0，21 条 June actual 课时仍保留且 `actual_minutes` 缺失为 0，工资明细引用 blocker 与同月 locked blocker 均为 0。
- `wage.html` 生成确认文案已明确提示：生成工资快照后会锁定该月实际课时，未完成录入或修正前不要生成。

固定安全规则：

- 当前月份或未结月份的真实业务数据不得用于真实工资生成、快照生成、结账或锁定类写入验证。
- 工资生成验证必须优先使用 codex-test 白名单数据或 transaction rollback。
- 除非用户明确授权作为正式业务操作，否则不得对真实未结月份执行会导致锁定的生成类 RPC。
- 2026-06 本次回退是用户授权的定点修复；后续通用处理应使用已验证的 `school_void_teacher_wage_lock` guarded void 语义，而不是手工删除真实工资快照/明细。

## Guarded unpaid snapshot void checkpoint

2026-06-11 已新增并执行 `school_teacher_wage_locks_void_audit_schema.sql`：

- `school_teacher_wage_locks.void_reason`
- `school_teacher_wage_locks.voided_by`
- `school_teacher_wage_locks.void_source`

这些字段只用于新的撤销审计；执行后确认历史记录没有被回填。

同日新增并执行 `school_void_teacher_wage_lock_rpc.sql`，创建 verified RPC：

`public.school_void_teacher_wage_lock(p_wage_lock_id uuid, p_reason text, p_operator text default null, p_source text default 'v2_wage_detail')`

实现范围：

- 只接受存在的 `school_teacher_wage_locks`。
- 必须填写撤销原因。
- 只允许 `status = locked` 且 `voided_at is null` 的快照。
- 拒绝重复撤销。
- 拒绝任何 `source_type = teacher_wage` 且 `source_id = wage_lock.id` 的 payment request；即使 pending/cancelled/reversed 也不在本阶段自动撤销工资快照。
- 拒绝已存在 paid/generated expense、salary-payment expense 或 direct account transaction dependency。
- 校验快照 teacher/month/business 字段完整。
- 校验明细存在且 detail 聚合金额、课时、分钟、业务归属与主表一致。
- 只更新工资快照主表：`status = void`、`voided_at`、`void_reason`、`voided_by`、`void_source`、`updated_at`。

不做的事：

- 不删除 `school_teacher_wage_lock_details`。
- 不修改 `school_lesson_records`、`actual_minutes` 或 lesson status。
- 不写 payment request、expense、account transaction、account balance、income、student settlement、wage rule。
- 不改变工资金额公式。

兼容修正：

- `school_generate_teacher_monthly_wage` 的重复生成 blocker 已改为只阻塞 active `status = locked and voided_at is null` 的工资快照。
- `school_generate_teacher_monthly_wage` 的 already-detailed blocker 已改为只阻塞 parent wage lock active 的明细；void 快照下保留的明细不再阻止重新生成。
- `school_update_lesson_record_guarded` 对 actual 的 wage-detail 引用 blocker 已改为只阻塞 parent wage lock active 的明细；void 快照下保留的明细不再阻止来源 actual 后续编辑。
- 生成粒度仍为 `teacher + business_entity + month`；本轮未新增 business-entity 参数，也未改金额口径。

页面接入：

- `wage-detail.html` 增加 `撤销快照` 按钮，只在未生成 payment request 的 `locked` 快照显示。
- 撤销确认弹窗必须填写原因并勾选确认。
- 确认文案说明：撤销后快照作废、课时不会删除、`actual_minutes` 不会修改、对应课时可重新进入候选范围、已生成支付请求/已支付不可撤销。
- 页面通过 `js/api/wage-detail-api.js` 的 `voidTeacherWageLock` 调用 RPC；页面模块不直接 `.rpc()`，也不直接 update/delete/upsert。
- 成功后刷新详情，按钮隐藏并显示只读原因。

验证记录：

- Rollback test 使用临时 codex-test 2029-03 actual lesson，在事务内生成工资快照、调用 `school_void_teacher_wage_lock` 撤销、验证重复撤销拒绝、有 pending payment request 的快照拒绝、有 paid payment request 的快照拒绝、void 明细不再阻塞 generation/edit、source actual 可在 void 后由 `school_update_lesson_record_guarded` 编辑且 `actual_minutes = 120` 保持正确、同一 source lesson 可再次生成工资快照；随后 rollback，lesson/lock/rule residue 均为 `0`。
- Whitelist commit test 使用 codex-test lesson `93000000-0000-4000-8000-000000092201`、persistent void wage lock `da98714f-9b2e-4587-bddc-92a61986ba7c`。撤销后 active lock blockers `0`、active detail blockers `0`、source lesson `actual_minutes = 120`，并在事务内验证重新生成可通过后 rollback。
- Browser UI test 使用 codex-test lesson `93000000-0000-4000-8000-000000092301`、persistent void wage lock `80210313-481c-4b7b-a5f8-6df8fe2ac358`。390px 页面确认撤销按钮、必填原因校验、确认复选框、成功刷新、只读原因和无横向溢出均通过。
- Protected counts after commit/browser tests stayed unchanged: payment requests `76`, expenses `47`, account transactions `240`。
- Real 2026-06 stayed read-only: wage locks `0`, wage details `0`, candidate actual lessons `24`, candidate minutes `2775`, missing `actual_minutes` `0`, active detail blockers `0`; no real June wage generation was executed.

## No-snapshot candidate preview checkpoint

2026-06-11 对回退后 `wage.html` 无法看到 2026-06 课时的问题完成修复：

- 根因是页面只读取并展示已生成工资快照 `school_teacher_wage_locks`，没有快照时不会读取待生成 actual 候选课时。
- DB 只读确认真实 2026-06 工资快照和工资明细均为 0；actual completed/makeup_completed 候选课时为 22 条，actual minutes `2595`，缺失 actual_minutes 为 0，工资明细引用 blocker 和同月 locked blocker 均为 0。
- `js/api/wage-api.js` 新增只读候选读取：按 `teacher_settlement_month` 读取 actual completed/makeup_completed，并用 `year_month` 兜底读取 teacher_settlement_month 为空的历史/兼容记录；同时只读检查候选课时是否已有工资明细引用或同月 locked 工资快照 blocker。
- `wage.html` 在当前月份没有工资快照时显示 `待生成候选课时` 区域，包含候选数量、实际分钟/小时、老师/业务归属数量，以及课时明细链接、日期、时间、老师、学生、科目、业务归属、状态、时长、实际分钟、计费状态和工资锁定状态。
- 候选预览不计算最终工资金额，不调用生成 RPC，不写工资快照，不锁定 actual 课时；用户仍必须通过原 `生成老师工资` 确认入口正式生成。

## 2026-05 historical reconciliation checkpoint

2026-06-10 对 2026-05 丛琪润 / 青空进学塾工资重复锁定做了用户授权的定点历史修正：

- 新增并执行一次性 guarded RPC `public.school_fix_202605_teacher_wage_duplicate_cong_qirun()`，SQL archive 为 `school_fix_202605_teacher_wage_duplicate_cong_qirun_rpc.sql`。
- 函数只授予 `service_role` 和 owner 执行权限，不暴露给 `anon` / `authenticated`，也没有页面/API 接入。
- guard 精确验证 older wage lock `dacc2887-f039-4dcb-861b-6ec36e51bace`、duplicate wage lock `4af1b55e-ece1-47a1-a350-5bb0f2e111ca`、older payment request `a2794694-9bb0-411f-9f66-ae1fc174a646`、duplicate payment request `c8280c86-15f9-410b-b9ac-3588b780b3b0`、2026-05 执行前计数 `locked:10 / void:12`，以及两条 wage lock 完全相同的 3 条 detail lesson ids。
- Rollback test 验证事务内可把 duplicate payment request `pending -> cancelled`、duplicate wage lock `locked -> void` 并设置 `voided_at`，2026-05 计数变为 `locked:9 / void:13`，随后 rollback 恢复原状态。
- Commit test 持久完成同一修正。修正后 effective 2026-05 wage locks 为 `locked:9 / void:13`；older wage lock 与 older payment request 保持有效；两条 wage lock 的 detail rows 仍保留；重复调用被 guard 拒绝。
- 本次没有重算 2026-05 工资，没有修改 lesson records 或 wage details，没有写支出、账户、账户流水、收入、学生月度结算，也没有进入 broad history repair / backfill / cleanup。

## Closure fix checkpoint

2026-06-10 收口修正已完成并验证：

- `school_generate_teacher_monthly_wage` 的 guard 顺序已调整为先检查目标候选老师同月是否已有工资快照，再检查候选 actual 缺字段。
- 这样 `2026-05` 这类已有工资快照的月份会优先提示不能重复生成，不再被缺少老师/学生/科目/业务归属/实际分钟的 historical actual 校验掩盖。
- 缺字段 actual guard 保留；rollback-only codex-test lesson `83000000-0000-4000-8000-000000012001` 验证仍会拒绝缺少 `actual_minutes` 的候选课时，并在 rollback 后零残留。
- `wage.html` 默认不显示 `status = void` 的工资快照，只有显式选择 `已作废` 状态筛选才查看作废记录。
- `wage-detail.html` 返回 `wage.html` 时保留原列表筛选参数：年份、月份、老师、业务归属、结算类型、状态和关键字。
- 用户可见文案统一为“工资快照 / 已生成快照”，避免把当前 MVP 误表达成完整的工资快照 void/reissue 生命周期。
- 本修正不实现支付确认，不写支出、账户流水、收入、学生结算，不修改课时核心口径。

## Payment request generation checkpoint

2026-06-10 已新增并执行 `school_create_teacher_wage_payment_request_rpc.sql`，创建 verified RPC:

`public.school_create_teacher_wage_payment_request(p_wage_lock_id uuid, p_due_date date default null, p_note text default null)`

实现范围：

- 来源为一条 `school_teacher_wage_locks` 工资结算快照。
- 只接受底层 `status = locked` 且 `voided_at is null` 的已生成快照。
- 只写一条 `school_payment_requests`。
- `source_type = teacher_wage`。
- `source_id = wage_lock.id`。
- `request_month = wage_lock.settlement_month`。
- `payee_type = teacher`。
- `payee_id = wage_lock.teacher_id`。
- `payee_name = wage_lock.teacher_name`。
- `business_entity_id` / `business_name` 来自工资快照。
- `currency = JPY`，`amount = amount_jpy = wage_lock.total_jpy`，`amount_cny = wage_lock.total_cny`。
- `status = pending`。
- 拒绝已有任意 `source_type = teacher_wage` 且 `source_id = wage_lock.id` 的支付请求。
- 拒绝 `total_jpy <= 0` 的工资快照，避免生成无法确认支付的 0 金额请求。

边界：

- 不确认支付。
- 不生成支出。
- 不写账户流水。
- 不扣账户余额。
- 不写收入。
- 不写学生结算。
- 不修改课时、工资快照或工资明细。
- 不新增 DB-level source unique 约束，因为现有 reissue 链路允许同源历史请求链。

页面接入：

- `wage-detail.html` 在无关联支付请求、工资快照已生成且金额大于 0 时显示 `生成支付请求`。
- 页面通过 `js/api/wage-detail-api.js` 的 `createTeacherWagePaymentRequest` 调用 RPC。
- 页面模块不直接 `.rpc()`，也不直接 insert/update/delete/upsert。
- 成功后刷新工资详情，关联支付请求区域显示待支付请求，并提供 `payment-detail.html` 链接。
- 生成后隐藏入口，避免同一工资快照重复生成初始支付请求。

验证记录：

- Rollback test 使用 wage lock `7c367bf0-a2c8-467f-91c8-fb1e237fac51`，临时 payment request `969968cd-6f06-4bae-adde-3d3567b97fb1`，验证字段、重复 guard 和保护表计数，然后 rollback 后 source payment residue 为 `0`。
- Whitelist SQL commit test 使用 wage lock `f5fe1fe3-f9e1-45d4-ac50-270c9b609d58`，创建 payment request `753d043d-9b3e-47c0-8e0c-e8d5a582aa42`。
- Browser UI commit test 使用 wage lock `7c367bf0-a2c8-467f-91c8-fb1e237fac51`，创建 payment request `8421a278-2e84-4f8b-ba01-6e9869f0bd3c`。
- 两条持久请求均为 `pending`，金额 `JPY 15400`，无 `paid_expense_id`、`paid_account_transaction_id`、`account_id`。
- Protected counts after SQL + UI commits: payment requests `68`, expenses `44`, accounts `12`, account transactions `235`, income `17`, student monthly settlements `14`.

## Payment confirmation account-type checkpoint

2026-06-10 复核老师工资支付确认后的账户类型边界，并重建 verified RPC `public.school_confirm_payment_request(...)`，SQL archive 为 `school_confirm_payment_request_rpc.sql`。

现状与修正：

- 支付页面确认支付时已要求选择账户，并通过 `js/api/payment-api.js` 的 `confirmPaymentRequest` 调用 RPC；页面模块不直接 `.rpc()`，也不直接写表。
- 修正前 DB RPC 创建 `teacher_wage` 支出时未显式写 `reimbursement_status`，会落到 `school_expense_records` 默认值 `pending`。
- 修正后 RPC 只接受 `pending` 的 `teacher_wage` payment request，要求请求无既有支付 side effects，账户为 active school account，业务归属和币种与请求一致，支付金额等于请求金额。
- 公司账户支付：生成一条 `teacher_wage` 支出、一条账户流水、更新支付请求为 `paid`，并设置支出 `reimbursement_status = not_required`。
- 垫付/个人账户支付：生成一条 `teacher_wage` 支出、一条垫付账户流水、更新支付请求为 `paid`，并设置支出 `reimbursement_status = pending`。
- 报销流程边界不变：报销候选 API 排除 `teacher_wage`，`school_create_reimbursement_record` 也拒绝 `teacher_wage`，所以报销只处理公司账户归还垫付账户，不会再次生成工资支出。

验证记录：

- Rollback test 使用临时 accounts `91000000-0000-4000-8000-000000013001` / `91000000-0000-4000-8000-000000013002` 和 payment requests `91000000-0000-4000-8000-000000013101` / `91000000-0000-4000-8000-000000013102`，验证公司账户 `not_required`、垫付账户 `pending`、报销候选为 `0`、报销 RPC 拒绝 `teacher_wage`，rollback 后 residue `0`。
- Whitelist commit test 使用 active codex-test business `2fa5bd72-7ba5-48f3-91dd-b56f978c56e6`，创建 accounts `91000000-0000-4000-8000-000000014001` company and `91000000-0000-4000-8000-000000014002` advance，确认 payment requests `91000000-0000-4000-8000-000000014101` and `91000000-0000-4000-8000-000000014102`。
- Commit test 生成 expenses `9939dfc0-9f00-4e91-8c39-f18e70b95b2a` (`not_required`) and `72633214-2424-4b18-9dd8-7994c3e1e34b` (`pending`)，account transactions `37c74735-fbe8-4c91-b288-d5fca751d6bd` and `31c6e09e-22bc-4cac-9225-63c4608afd71`。
- Duplicate confirm was rejected because the request is no longer pending; reimbursement RPC rejected the pending advance teacher_wage expense and created no reimbursement records/items/transactions.

## API/UI MVP checkpoint

2026-06-10 已在 `js/api/wage-api.js` 新增 API wrapper:

`generateTeacherMonthlyWage({ yearMonth, teacherId })`

页面接入：

- `wage.html` 新增 `生成老师工资` 主操作。
- 弹窗使用当前筛选月份；如果筛选了老师，则按该老师生成，否则按该月份全部候选老师生成。
- 页面通过 API wrapper 调用 `school_generate_teacher_monthly_wage`，页面模块不直接 `.rpc()`，也不直接 insert/update/delete/upsert。
- 成功后刷新工资快照列表，生成的工资快照可进入 `wage-detail.html` 查看只读明细。
- 重复生成或已生成快照月份由 RPC 拒绝，页面在弹窗内显示错误，不静默吞错。

弹窗文案明确：

- 只基于 actual completed / makeup_completed 课时。
- cancelled 不计入。
- planned 不计入。
- `is_billable=false` 仍可能计入老师工资。
- 生成后写入工资快照主表和工资明细。
- 不生成支付请求。
- 不生成支出。
- 不写账户流水。
- 不写收入。
- 不写学生结算。

UI 验证记录：

- Browser validation used teacher `12f6d142-b90b-4da2-be88-310414000bd1`, month `2028-11`, setup lesson ids `82000000-0000-4000-8000-000000011001` completed, `82000000-0000-4000-8000-000000011002` non-billable `makeup_completed`, and `82000000-0000-4000-8000-000000011003` cancelled.
- UI generation created wage lock `7c367bf0-a2c8-467f-91c8-fb1e237fac51` and details `9e26d6ab-acd5-45e1-8972-8ec2d13505ab`, `dfb642ee-6b33-4621-8679-a31a629db6f1`.
- Verified totals: `lesson_count = 2`, `total_minutes = 210`, `pay_hours = 3.5`, `lesson_wage_jpy = total_jpy = 15400`, `fee_jpy = 0`, cancelled detail count `0`.
- Desktop browser verified list refresh, generated row visibility, duplicate generation error, and detail page completed / makeup_completed rows.
- 390px browser verified generation dialog visibility and `documentElement.scrollWidth = body.scrollWidth = 390`.
- Protected counts stayed unchanged after UI generation: payment requests `66`, expenses `44`, accounts `12`, account transactions `235`, income `17`, student monthly settlements `14`.

## DB/RPC MVP checkpoint

2026-06-10 已新增并执行 `school_generate_teacher_monthly_wage_rpc.sql`，创建 verified RPC。2026-06-11 后续更新支持同一老师同月按业务归属拆分生成多个工资快照，并补齐 actual_minutes 同步保护：

`public.school_generate_teacher_monthly_wage(p_year_month text, p_teacher_id uuid default null)`

实现范围：

- 只读取 `lesson_type = actual` 的课时。
- 只纳入 `status in ('completed', 'makeup_completed')`。
- 排除 `planned`、`cancelled`、`voided_at is not null`。
- 按 `coalesce(teacher_settlement_month, year_month) = p_year_month` 进入工资月份；跨月补课 actual 因已落在补课月份，所以进入补课月份工资。
- `is_billable` 不影响老师工资；非计费 `makeup_completed` actual 仍计入。
- 直接生成底层 `status = locked` 的工资快照，不做 draft。
- 按 `teacher_id + business_entity_id + settlement_month` 生成工资快照；同一老师同月跨多个业务归属时生成多个快照。
- 只写 `school_teacher_wage_locks` 和 `school_teacher_wage_lock_details`。
- 不修改 `school_lesson_records`。
- 不写 `school_payment_requests`、`school_expense_records`、`school_accounts`、`school_account_transactions`、`school_income_records`、`school_student_monthly_settlements`。

金额口径：

- 只处理 JPY hourly / no_wage。
- `pay_hours = actual_minutes / 60`。
- `lesson_wage_jpy = round(pay_hours * hourly_rate_jpy)`。
- 本阶段不处理 CNY/汇率、交通费、教室费；生成的 `lesson_wage_cny`、`total_cny`、`exchange_rate`、`transport_fee_jpy`、`classroom_fee_jpy`、`fee_jpy` 固定为 `0`。
- `total_jpy = lesson_wage_jpy`。
- `lesson_count = 生成的工资明细条数`。

Guard：

- `p_year_month` 必须是 `YYYY-MM`。
- 可选 `p_teacher_id` 必须存在。
- 候选 actual 必须有老师、学生、科目、业务归属和 `actual_minutes`。
- 同一 actual 已存在 `school_teacher_wage_lock_details.lesson_record_id` 时拒绝。
- 目标候选老师 + 业务归属在同一月份已存在 active `status = locked and voided_at is null` 的 `school_teacher_wage_locks` 时拒绝重复生成；void 快照不再阻塞。
- 每条 actual 必须命中且只命中一条启用工资规则。
- 同一 actual 已存在 active wage detail 引用时拒绝；void 快照下保留的明细作为审计保留，不再阻塞重新生成。

验证记录：

- 只读 DB verification 确认历史 388 条工资明细均符合 `lesson_wage_jpy = round(pay_hours * hourly_rate_jpy)`，70 个工资快照主表金额/课时字段均与明细聚合一致。
- Rollback test 使用 codex-test lesson ids `80000000-0000-4000-8000-000000008001`、`80000000-0000-4000-8000-000000008002`、`80000000-0000-4000-8000-000000008003`，生成临时 wage snapshot `3184381f-fafe-458a-ae93-30bceda3cc6c`，验证 completed / non-billable makeup_completed 计入、cancelled 排除、重复生成拒绝、已有 generated wage snapshot 拒绝、保护表计数不变，并 rollback 后 lessons/locks/details residue 为 `0`。
- Whitelist commit test 使用 teacher `12f6d142-b90b-4da2-be88-310414000bd1`、month `2028-10`、lesson ids `81000000-0000-4000-8000-000000010001` completed、`81000000-0000-4000-8000-000000010002` non-billable makeup_completed、`81000000-0000-4000-8000-000000010003` cancelled，创建 wage lock `f5fe1fe3-f9e1-45d4-ac50-270c9b609d58` 和 detail ids `aad48406-c0cc-499b-b2a5-0fd7e1709688`、`1ad4f156-e869-4a36-aa47-c12edaa18da6`。
- Commit test totals: `lesson_count = 2`、`total_minutes = 210`、`pay_hours = 3.5`、`lesson_wage_jpy = total_jpy = 15400`、`fee_jpy = total_cny = 0`，cancelled detail count `0`。
- Protected counts stayed unchanged: payment requests `66`、expenses `44`、accounts `12`、account transactions `235`、income `17`、student monthly settlements `14`。

后续仍需：

- 只读候选/错误预览 UI。
- 支付确认、支出生成、账户流水生成已经由支付模块处理，后续变更仍需在支付模块内单独 guarded 设计。
- 多业务归属单独生成、CNY/FX、交通费、教室费、snapshot restore/reissue beyond void、历史 backfill/cleanup 的单独设计。

## 已确认现状

### 页面与 API

- `wage.html` / `js/pages/wage-page.js` / `js/api/wage-api.js` 是工资快照列表和生成入口。
- `wage-detail.html` / `js/pages/wage-detail-page.js` / `js/api/wage-detail-api.js` 是只读工资快照详情和支付请求生成入口。
- 工资详情读取 `school_teacher_wage_locks`、`school_teacher_wage_lock_details` 和 `source_type = teacher_wage` 的 `school_payment_requests`。
- `wage-rule.html` / `wage-rule-detail.html` 支持工资规则配置的读取、新增、编辑、停用/恢复；写入只影响 `school_teacher_wage_rules`，不重算历史工资。
- `payment` 页面处理老师工资支付请求确认、撤销、取消、恢复、重发；支付确认后才进入支出与账户流水链路。当前支付撤销会追加 `payment_reversal` 现金反转流水，并同步将对应 `teacher_wage` 支出标记为 `reversed`；历史反转支付不会自动回填，已批准的 2026-02/2026-03 五条历史同步通过独立 guarded SQL 完成。

### 现有表形状

从前端 select 字段和现有 RPC archive 可确认：

- `school_teacher_wage_locks` 是底层工资快照主表，包含 `teacher_id`, `teacher_name`, `settlement_month`, `business_entity_id`, `business_name`, `settlement_type`, `exchange_rate`, `lesson_count`, `total_minutes`, `pay_hours`, `fee_jpy`, `lesson_wage_jpy`, `lesson_wage_cny`, `total_jpy`, `total_cny`, `status`, `locked_at`, `voided_at`, `created_at`, `updated_at`。
- `school_teacher_wage_lock_details` 是工资明细快照，包含 `lock_id`, `lesson_record_id`, `lesson_date`, `start_time`, `end_time`, `student_id`, `student_name`, `subject_id`, `subject_name`, `business_entity_id`, `business_name`, `pay_hours`, `lesson_wage_jpy`, `lesson_wage_cny`, `transport_fee_jpy`, `classroom_fee_jpy`, `total_jpy`, `total_cny`, `settlement_type`, `exchange_rate`, `is_no_wage`, `status`, `lesson_content`, `created_at`。
- `school_teacher_wage_rules` 是未来工资快照生成配置源，当前支持匹配键 `teacher_id + student_id + subject_id + business_entity_id`，配置字段包括 `settlement_type`, `hourly_rate_jpy`, `hourly_rate_cny`, `exchange_rate`, `transport_fee_jpy`, `classroom_fee_jpy`, `is_active`, `note`。
- 当前已验证的 `settlement_type` 只有 `jpy_hourly` 和 `no_wage`。

### 现有快照保护逻辑

- 课时 actual 生成 RPC 会检查目标老师工资月份是否已有 `school_teacher_wage_locks.status = locked`，匹配 `teacher_id + business_entity_id + teacher_settlement_month`。
- guarded lesson edit 对 actual 会：
  - 拒绝已经被 `school_teacher_wage_lock_details.lesson_record_id` 引用的 actual。
  - 检查原老师工资月份和目标老师工资月份是否 locked。
  - 更新 actual 时重新派生 `teacher_settlement_month = lesson_date YYYY-MM`。
- `wage.html` 与 `wage-detail.html` 不提供任何重新计算、编辑工资明细或支付操作。
- `wage-detail.html` 明确把老师工资作为已保存快照，不用当前工资规则重算历史工资快照。

## 课时进入工资口径的当前事实

- `planned` 不写 `actual_minutes` 和 `teacher_settlement_month`，不应进入工资生成。
- `actual` 会写 `actual_minutes` 和 `teacher_settlement_month`。
- `completed actual`：
  - `teacher_settlement_month = actual lesson_date YYYY-MM`
  - `actual_minutes = round(duration_hours * 60)`
  - `is_billable` 继承 planned，但这目前只被学生结算/课时统计用于学费口径。
- `makeup_completed actual`：
  - `teacher_settlement_month = makeup actual lesson_date YYYY-MM`
  - `actual_minutes = round(duration_hours * 60)`
  - 可计费或不计费；非计费时 `lesson_fee = 0`。
- 跨月 `makeup_completed actual`：
  - `year_month = 补课月份`
  - `teacher_settlement_month = 补课月份`
  - `planned_lesson_id` 指向原月份 `pending_makeup planned`
  - 默认 `is_billable = false` 且 `lesson_fee = 0`
  - 已验证不进入学生结算 actual fee/hours，但仍是补课月份 actual lesson。
- `cancelled actual`：
  - `teacher_settlement_month = cancelled actual lesson_date YYYY-MM`
  - `actual_minutes = 0`
  - `is_billable = false`
  - `lesson_fee = 0`
  - 是否进入老师工资不能从现有生成逻辑确认。

## 工资生成字段建议

MVP 应只读取 `school_lesson_records` 中的 actual 行，候选条件建议：

- `lesson_type = 'actual'`
- `teacher_id` 非空
- `business_entity_id` 非空
- `teacher_settlement_month = p_settlement_month`
- `status in ('completed', 'makeup_completed')`
- `actual_minutes > 0`
- `voided_at` 不参与，因为当前 void 只适用于 planned；若未来 actual void/delete 出现，必须重新设计。

字段口径：

- `teacher_id`: 工资主表分组键之一。
- `business_entity_id`: 工资主表分组键之一，且匹配工资规则。
- `teacher_settlement_month`: 工资月口径，应优先于 lesson `year_month`。
- `lesson_type`: 只允许 actual。
- `status`: MVP 建议只纳入 `completed` 和 `makeup_completed`。
- `actual_minutes`: 作为 pay minutes 来源；`trg_school_lesson_actual_minutes_sync` 会在未来 actual completed / makeup_completed 写入或更新时从 `duration_hours` 派生，`school_backfill_actual_minutes_from_duration` 可在服务端 guarded workflow 中补齐或同步指定月份的缺失/不一致分钟。
- `duration_hours`: 页面显示时长来源，也是 actual_minutes 同步的派生来源；工资生成仍读取同步后的 `actual_minutes`，不在生成 RPC 内临时 fallback。
- `is_billable`: 学生收费口径，不应默认排除老师工资；跨月补课的 non-billable actual 仍应作为老师已上课事实进入候选，除非业务另行确认排除。
- `lesson_fee`: 学生学费口径，不应用于老师工资计算。
- `lesson_count`: 当前工资快照主表有 `lesson_count`，但工资规则是 hourly 口径；MVP 应明确是否只是统计字段，不作为金额计算来源。

## 规则匹配与金额建议

当前可确认的工资规则匹配键为：

- `teacher_id`
- `student_id`
- `subject_id`
- `business_entity_id`
- `is_active = true`

MVP 建议：

- 每条 actual 必须匹配一条启用工资规则。
- 多条启用规则命中同一 actual 时应 hard stop，不自动选。
- 未命中规则的 actual 应阻止生成，并返回缺规则明细。
- `settlement_type = 'jpy_hourly'`：
  - `pay_hours = actual_minutes / 60`
  - `lesson_wage_jpy = round/pay according to chosen precision in RPC design`
  - `lesson_wage_cny = 0` unless a future CNY hourly rule is explicitly defined
  - `transport_fee_jpy`、`classroom_fee_jpy` 从规则复制到明细
  - `total_jpy = lesson_wage_jpy + transport_fee_jpy + classroom_fee_jpy`
  - `total_cny` 按现有字段设计确认，不能从现有代码推导最终公式
- `settlement_type = 'no_wage'`：
  - 明细可写入 `is_no_wage = true`
  - 金额字段为 0
  - 是否生成明细用于审计，建议生成 0 金额明细，避免“漏算还是无工资”无法区分。

## 快照生成与重复生成建议

现有系统只有 saved wage snapshot；未发现 draft 表或 draft 状态的已实现入口。

MVP 选择“直接生成工资结算快照”，不引入 draft：

- 输入：指定 `settlement_month`，可选 `teacher_id` / `business_entity_id`。
- 输出：为每个 `teacher_id + business_entity_id + settlement_month` 生成一条 `school_teacher_wage_locks` 和对应明细。
- 已存在 `status = locked` 的同一老师/业务归属/月应拒绝重新生成。
- 已存在 payment request、paid expense、account transaction 的工资快照绝对不能被重算或覆盖。
- 不删除旧 detail，不覆盖旧 snapshot，不做历史重算。
- 如果未来需要 draft，必须新增单独设计：明确 draft 表/状态、覆盖规则、旧 draft 删除/替换规则，以及与 lesson edit guard 的关系。

不建议在 MVP 做“先删除旧 draft 明细再生成”，因为仓库没有现有 draft 概念，且 `delete` 是项目 hard stop 类操作。

## 与支付、支出、账户边界

工资生成阶段建议只写：

- `school_teacher_wage_locks`
- `school_teacher_wage_lock_details`

工资生成阶段不得直接写：

- `school_payment_requests`
- `school_expense_records`
- `school_accounts`
- `school_account_transactions`
- `school_income_records`
- `school_student_monthly_settlements`
- `school_student_settlement_carryovers`

支付请求应作为后续单独阶段处理。现有支付管理已经以 `source_type = 'teacher_wage'` 和 `source_id = wage_lock.id` 展示工资来源，并在支付确认时才生成 teacher_wage 支出和账户流水。普通支出 RPC 明确拒绝手工创建 `teacher_wage` 分类，普通支出撤销/附件也排除 teacher_wage。

## UI / API / RPC / DB 触点

### DB

优先复用现有 `school_teacher_wage_locks` 与 `school_teacher_wage_lock_details`。是否需要新增唯一约束或状态字段不能在本阶段决定，必须先做只读 DB 验证：

- 同一 `teacher_id + business_entity_id + settlement_month` 是否已有多条 active/locked lock。
- 是否存在 `status` 非 `locked` / `void` 的历史值。
- 是否存在 detail 缺 `lesson_record_id` 或一条 actual 被多个 detail 引用。
- 是否存在 `cancelled` detail。

### RPC

建议后续新增专用 guarded RPC：

`school_generate_teacher_wage_locks_for_month`

候选参数：

- `p_settlement_month text`
- `p_teacher_id uuid default null`
- `p_business_entity_id uuid default null`
- `p_note text default null`
- `p_dry_run boolean default false` only if design chooses preview through same RPC; otherwise separate read RPC

RPC guard：

- 月份格式必须是 `YYYY-MM`。
- 候选 actual 只来自 `school_lesson_records.lesson_type = actual`。
- 候选 actual 的 `teacher_settlement_month = p_settlement_month`。
- 候选 status 默认只允许 `completed`, `makeup_completed`。
- 拒绝任何候选 actual 已存在于 `school_teacher_wage_lock_details.lesson_record_id`。
- 拒绝目标 `teacher_id + business_entity_id + settlement_month` 已有 `status = locked` 的 wage lock。
- 拒绝缺工资规则、重复工资规则、停用工资规则。
- 不修改 lesson records。
- 不写 payment、expense、account、account transaction。

### API

新增 API wrapper 必须在 `js/api/wage-api.js` 或独立 `teacher-wage-generation-api.js`，页面不得直接 `.rpc()`。

建议 API：

- `previewTeacherWageGeneration(filters)`：只读候选预览，最好先用 select/API 查询；若未来用 read RPC，必须只读。
- `generateTeacherWageLocks(payload)`：调用 guarded RPC。

### UI

入口建议放在 `wage.html`：

- 页面仍以工资快照列表为主。
- 新增主操作：`生成老师工资`
- 弹窗文案：
  - `只基于 actual 课时生成工资快照`
  - `不会修改课时`
  - `不会生成支付请求`
  - `不会写入支出或账户流水`
  - `已生成快照的月份不能重新生成`
- 弹窗先显示候选月份、老师、业务归属、actual 数、缺规则数、将生成的锁数。
- 若存在缺规则、重复规则、已生成快照、已被 wage detail 使用的 actual，应阻止提交并显示明细。

## MVP 范围建议

第一版只做：

- 指定月份生成老师工资快照主表与明细快照。
- 只基于 actual lesson records。
- 只纳入 `completed` 和 `makeup_completed`。
- 跨月补课 actual 按 `teacher_settlement_month` 进入补课月份老师工资。
- `is_billable = false` 不默认排除老师工资。
- 生成后 locked，不提供 draft。
- 已生成快照后禁止重新生成。
- 不碰支付、不碰支出、不碰账户、不碰收入、不碰学生结算。
- 不做历史 backfill，不处理真实历史修复。

## Hard Stop / 待确认点

以下点在只读设计阶段无法从仓库实现确认；本轮 DB/RPC phase 已按用户确认的 MVP 口径处理：

- `cancelled actual`: MVP 不计入工资。
- draft / preview / locked: MVP 不做 draft，生成即 `locked` snapshot。
- payment requests: 工资生成阶段不生成，后续支付管理阶段另做。
- CNY/FX: MVP 不处理，CNY/汇率字段为 `0`。
- 交通费、教室费: MVP 不处理，相关字段为 `0`。
- `lesson_count`: MVP 定义为工资明细条数。
- 生成范围: RPC 支持指定 month，可选 teacher；同老师同月已有工资记录时拒绝。
- void/relock: 不属于 MVP。

Hard stop：

- 如果实现需要修改课时核心口径，停止。
- 如果实现需要 backfill 历史工资，停止。
- 如果实现需要清理真实历史数据，停止。
- 如果实现要把工资生成直接写入支出、账户流水或支付请求，停止并单独说明。
- 如果工资口径无法从文档/只读验证确认，停止并列出待用户确认点。

## 下一阶段建议

1. 只读 DB verification：确认 `school_teacher_wage_locks` / details / rules 的真实列、状态值、重复情况和历史 detail status 分布。
2. 只读候选统计：统计一个测试月份中 actual `completed` / `makeup_completed` / `cancelled` 的分布、`is_billable=false` 的分布、跨月补课 actual 分布、缺工资规则候选。
3. 业务确认：确认 hard stop / 待确认点，尤其是 cancelled、CNY 公式、交通费/教室费频率、是否生成 payment request。
4. 进入 RPC phase：只在确认后写 SQL draft，并按 full write-RPC workflow 执行 rollback test 和 whitelist commit test。
