# School V2 R1B历史结构化回填与事故隔离实施报告

报告日期：2026-07-27（Asia/Tokyo）

## 1. 结论

R1B已在固定ID、固定角色、固定R1A行哈希和固定manifest保护下正式完成。School DB最终状态为：

- 9张bill：7 `canonical_charge`、1 `incident_duplicate`、1 `legacy_cancelled`，NULL为0；
- 7条永久billing identity；
- 121条normalized bill lesson：85 canonical、24 incident、12 legacy；
- 9/9 bill-income精确双向关系；
- 张倬闻事故income `bbd7e7fd-fa04-404b-91fc-ab894cca28c8`已切换为`incident_quarantined`；
- 正常运营收入41条，事故审计视图1条；事故在authenticated基础表读取和运营视图中均为0；
- 事故Cash linkage和School账户流水均为0，永久守卫负向测试全部拒绝；
- R0三个gate和三个mutation guard继续有效；
- Cash DB三张基线表行数和哈希完全不变；
- 最终代码审查已通过，本报告及R1B目标文件获准进行Git交付；R1C仍需独立授权。

### 必须回答的10个问题

| 问题 | 结论 |
|---|---|
| 1. 9张bill是否准确分类？ | 是，精确7/1/1，NULL 0。正式UPDATE目标来自固定9-bill manifest，不按status或Cash状态动态选取。 |
| 2. 7条identity是否准确？ | 是，7条均指向canonical bill；student/month与冻结bill一致；incident/legacy均无identity。 |
| 3. 121条关系是否准确？ | 是，85/24/12；canonical planned重复0，incident/legacy无canonical均为0，孤儿0，日期snapshot非NULL为0，证据标记不一致0。 |
| 4. 9/9 bill-income是否建立？ | 是，9条均满足bill.income_record_id、income.source_id、income.source_type和income.tuition_bill_id精确互指。 |
| 5. 张倬闻事故income是否真正退出运营统计？ | 是。authenticated直接读基础表也不可见；运营视图不可见；事故审计视图可见；运营pending和incident均为0。 |
| 6. 事故income是否仍可进入Cash、收据或账户？ | 否。Cash linkage/account transaction数据库trigger均拒绝；Cash RPC因非pending拒绝；收据和普通详情读取均经运营视图/RLS排除。 |
| 7. 原canonical历史资金事实是否完全不变？ | 是。9条目标income在仅规范化授权状态后，原R1A行哈希9/9一致；账户流水、Cash linkage、结算、工资、课时哈希均不变。 |
| 8. 陈加恩legacy历史是否正确保留？ | 是。bill/income仍cancelled，12条legacy关系保留，无identity，不修改金额、月份、来源或课时。 |
| 9. R0是否仍完全有效？ | 是。gate仍为`validation_preview_only / blocked / blocked`；13个R0/R1B trigger均enabled；四个生成入口及Cash gate复验均拒绝。 |
| 10. 是否可以进入下一阶段？ | R1B技术验收已通过，可提交审查；只有审查批准并获得新的阶段授权后，才可分别进入原子生成RPC、日期模型和52条迁移准备。本阶段未开始这些工作。 |

## 2. Git与开始前前置条件

- 分支：`main`
- HEAD：`6c761f61d1c8b95ba08d2f7760a2e1e45a5c6415`
- `origin/main`：同一commit
- 开始工作区：clean
- 三个gate：
  - `student_tuition_preview = validation_preview_only`
  - `student_tuition_generate = blocked`
  - `student_tuition_cash_submit = blocked`
- identity 0、bill lesson 0；9张bill的`billing_role`全NULL；9条income的`tuition_bill_id`全NULL；incident 0。
- School/Cash基线行数和哈希与R1A报告完全一致。
- 固定9张bill、9条income、121个JSON关系、7/1/1、85/24/12和7个canonical Cash证据全部通过事务前断言。

## 3. 固定manifest与哈希

### 3.1 9组bill-income-role

| Bill ID | Income ID | Role |
|---|---|---|
| `2a9f1c25-a060-461e-ae10-b02295dec381` | `468ab75b-312e-4ba0-8d8d-8ae2f6ace00e` | canonical_charge |
| `fdf3cdfe-f715-4814-b500-9ff2bfe77a63` | `f86ac9db-effd-402e-a320-1e4b6846a9c7` | canonical_charge |
| `047dac2b-9484-4637-8e5e-9887857d121b` | `bbd7e7fd-fa04-404b-91fc-ab894cca28c8` | incident_duplicate |
| `2a0948e0-9015-4b18-848c-8c397e0bc2a0` | `09fa4398-9d20-494b-8ab5-8f7c3cafa414` | canonical_charge |
| `07a02092-9503-47d1-9000-106f7e3de7e5` | `91756564-c48d-4a1d-b6bc-88a041660e46` | canonical_charge |
| `4109a4ec-1169-4d0b-965b-3e806b7e4c55` | `474f0fd2-71ca-4cce-9ba5-e615bd390151` | legacy_cancelled |
| `2608806a-283a-4919-a851-b25962f2c0b2` | `4a63f0ca-450f-4306-9e39-6d43172b3cf8` | canonical_charge |
| `1b546782-1b39-4c73-a85d-27ab1e5086ad` | `cdf3da68-e578-4f1b-b759-2fff394e1906` | canonical_charge |
| `7472f73f-fa19-4565-9180-a517c7151835` | `3a5542c5-5397-4688-999e-a08bb678f40d` | canonical_charge |

### 3.2 Manifest哈希

- 121条lesson manifest：`9b05ec18c7d6e4b2574591edae6b5709`
- 7条identity manifest：`a5a4d8665f7c0d2d794756f37934175e`
- 两个哈希均已写入正式SQL作为强制断言；rollback和formal commit两次输出完全相同。
- backfill batch ID：`b1000000-0000-4000-8000-202607279999`
- identity固定ID：`b1000000-0000-4000-8000-202607270001`至`...0007`
- lesson relationship ID由固定`bill_id + planned_lesson_id + r1b`在DB内确定性生成；业务关系目标不动态分类。

## 4. 正式结构、读取收敛与永久守卫

部署：

- `school_operational_income_records`：排除`incident_quarantined`或`operational_excluded=true`；
- `school_incident_income_records`：只包含事故，仅service_role可SELECT；
- income RLS policy：anon/authenticated即使仍直读旧基础表，也只能看到41条运营记录，事故为0；
- incident income不可UPDATE/DELETE；
- incident bill不可UPDATE/DELETE；
- incident income不可INSERT/UPDATE到Cash linkage；
- incident income不可INSERT/UPDATE到School account transactions；
- deferred identity/bill、bill/income、bill/lesson一致性trigger；
- canonical planned lesson partial unique继续有效；
- identity和bill lesson原有append-only保护继续有效。

### 4.1 Commit前OLD/NEW双端一致性加固

最终代码审查前确认原deferred consistency trigger仅以`coalesce`选取一侧对象，存在UPDATE、DELETE或解绑后遗漏旧对象的风险。已在不重新执行历史回填、不修改7/121/9正式业务数据的前提下完成以下加固：

- 新增三个按显式bill ID校验的内部helper：
  - `school_validate_tuition_identity_for_bill(uuid)`；
  - `school_validate_tuition_bill_income_for_bill(uuid)`；
  - `school_validate_tuition_bill_lessons_for_bill(uuid)`；
- 三个trigger函数分别收集INSERT/UPDATE/DELETE涉及的全部OLD和NEW bill ID，去重后逐一调用helper，不再使用`coalesce`单选一端；
- identity变更或删除会验证旧、新canonical bill；bill lesson移动或删除会验证旧、新bill；income的`tuition_bill_id`、`source_id/source_type`解绑或改指向以及bill的`income_record_id`改指向会验证全部相关bill和当前反向引用；
- 六个constraint trigger保持enabled、`DEFERRABLE INITIALLY DEFERRED`，原append-only和R0 guard保持不变。

部署前同一结构SQL完成rollback验证，正式部署仅更新view/function/policy/trigger对象定义，没有提交业务DML。

前端/API只读路径已切换到运营视图：

- 收入列表、数量、合计和待Cash候选；
- 收入详情；
- 利润统计；
- 学生结算候选与结算明细；
- 收据来源；
- 账户流水反向来源；
- 打工年度收入读取。

页面模块没有新增直接`.rpc()`或表写。即使这些未commit代码尚未部署，RLS也已令旧authenticated基础表读取看不到事故。

## 5. Rollback演练与正式执行

### 5.1 结构演练

`school_tuition_r1b_operational_isolation_and_consistency.sql`使用同一文件完成rollback解析验证和正式部署。后续一致性错误优先级、RLS收敛均再次经过rollback后部署。

### 5.2 固定回填演练

最终版本`school_tuition_r1b_fixed_historical_backfill.sql`：

1. `r1b_commit=0`完整构造9/7/9/121/1五组manifest；
2. 固定哈希通过；
3. 事务内达到7 identity、121 relations、9 reverse pairs、1 incident；
4. deferred constraint全部转为immediate并通过；
5. 指定R0 trigger重新enabled；
6. ROLLBACK；
7. 回滚后identity、relations、classified bill、reverse pair、incident五项均为0；
8. School/Cash基线哈希完全恢复。

### 5.3 正式commit

同一SQL仅将`r1b_commit`从0切换为1。正式输出：

- `UPDATE school_student_tuition_bills`: 9
- `INSERT billing identities`: 7
- `INSERT bill lessons`: 121
- `UPDATE school_income_records`: 9
- transaction acceptance：7 / 121 / 9 / 1
- COMMIT成功。

### 5.4 `updated_at`自动trigger偏差与恢复

正式验收发现通用`trg_school_income_records_updated_at`自动改写了9条income的技术时间戳，不在授权字段白名单内。处理过程：

- 立即停止完成宣告并只读定位；
- 用R1A固定行哈希从既有Cash linkage、cancelled evidence、created evidence及两条账户流水时间附近恢复9个原始微秒值；
- 修正主回填脚本，在授权UPDATE期间临时关闭并恢复该通用trigger；
- 新增固定9-ID、固定原时间、固定原哈希补偿SQL；
- 补偿rollback演练得到9/9并回滚；
- 同一补偿SQL正式commit后得到9/9原行哈希；
- R0、incident immutable和updated_at三个指定trigger最终均enabled。

最终没有遗留非白名单字段变化。

## 6. 修改前后行数与哈希

### 6.1 School DB

| 表/对象 | 修改前 | 修改后 | 哈希/结果 |
|---|---:|---:|---|
| `school_income_records` | 42 | 42 | R1A原哈希`b00238c330e8ab5ef7a51eb2fd281d4f`；授权事故status后哈希`6c70d924bc4de7ce3817f0f125a6c302`；9/9原行经授权状态规范化后与R1A逐行哈希一致 |
| `school_student_tuition_bills` | 9 | 9 | 排除R1B角色/锁字段后仍为`9ee93472fdac490897b8b837b174bbaa` |
| `school_account_transactions` | 185 | 185 | `8f4f6c4365035f6c36bac59ba986b28b`不变 |
| `school_lesson_records` | 625 | 625 | `313cff5314d78adf6c02497d0cc0097f`不变 |
| Cash linkage events | 35 | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0`不变 |
| student settlements | 15 | 15 | `7925cf3018bd0e669cd29710f6593238`不变 |
| wage locks | 95 | 95 | `7bbe108d3ac73d4f21530793bf141bc6`不变 |
| wage lock details | 556 | 556 | `6204dc666b3b8e0f64fac901ecf0686a`不变 |
| billing identities | 0 | 7 | 固定manifest |
| bill lessons | 0 | 121 | 85/24/12 |

### 6.2 Cash DB

| 表 | 修改前/后行数 | 修改前/后哈希 |
|---|---:|---|
| `home_external_transaction_requests` | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| `home_cny_transactions` | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| `home_jpy_transactions` | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

Cash DB没有执行DDL、DML或RPC。

## 7. 字段白名单diff

允许且实际发生：

- 9张bill：`billing_role`；incident/legacy的`incident_locked_at`、`incident_reason`、`cash_submission_blocked`；
- 9条income：`tuition_bill_id`；
- 事故income：`status_before_quarantine`、`status`、`incident_type`、三个canonical/duplicate引用、quarantine时间/操作人/原因、两个阻断boolean；
- 新增7条identity和121条bill lesson。

没有变化：

- 9张bill的金额、学生、月份、业务归属、JSON、原status和原source字段；
- 9条income的金额、币种、JPY/CNY、汇率、通知快照、学生、月份、业务归属、source_type/source_id、created_at及最终原updated_at；
- 7条received canonical income状态；
- 陈加恩legacy bill/income cancelled状态；
- Cash request/transaction/linkage、School账户流水、planned/actual、结算、工资、孙陈锋两条跨月课及52条候选。

## 8. 正式验收与负向测试

通过：

- identity错配拒绝；
- canonical planned重复拒绝；
- incident无canonical拒绝；
- legacy无canonical拒绝；
- bill-income错配拒绝；
- incident income update/delete拒绝；
- incident bill update/delete拒绝；
- incident Cash linkage拒绝；
- incident School account transaction拒绝；
- R0 Cash linkage trigger在临时移除incident前置guard时仍返回`TUITION_CASH_SUBMISSION_BLOCKED`；
- 全部负向探针位于rollback事务，测试ID `b1000000-0000-4000-8000-202607279901`至`...9907`，最终残留0；
- 13个R0/R1B trigger最终全部enabled；
- authenticated基础表：41条，事故0；运营视图41，事故审计1；
- 事故linkage 0、School账户流水0；
- 运营pending 0、received 39、cancelled 2、incident 0。

Commit前新增`school_tuition_r1b_old_new_consistency_rollback_tests.sql`，在`SET CONSTRAINTS ALL IMMEDIATE`下验证：

1. existing identity从canonical bill A改指向canonical bill B；
2. canonical bill lesson从bill A移动到bill B；
3. 清空tuition income的`tuition_bill_id`；
4. tuition income的`source_id`改指向另一张bill；
5. bill的`income_record_id`改指向另一条income；
6. 删除canonical identity；
7. 删除canonical bill lesson。

七项均由目标一致性异常拒绝，结果为`7/7`；测试结束前对identity、bill lesson、bill和income四组业务表执行整表计数与内容哈希对比，`business_residue_count = 0`，随后总事务ROLLBACK。既有R1B guard rollback套件也再次通过。最终仍为7 identity、121 bill lesson（85/24/12）、9/9 bill-income精确互指，9条原income业务哈希仍为9/9，School其他业务哈希和Cash DB三表哈希均不变。

R0调用复验：

- 两个`school_generate_student_tuition_bill`重载：`TUITION_GENERATION_BLOCKED`；
- `school_create_student_tuition_bill_income_record`：`TUITION_GENERATION_BLOCKED`；
- `school_create_personal_cash_tuition_income_record`：`TUITION_GENERATION_BLOCKED`；
- Cash gate直接断言：`TUITION_CASH_SUBMISSION_BLOCKED`；
- 事故`school_request_cash_income_confirmation_for_record`：因`incident_quarantined`非pending而拒绝，无写入。

## 9. 执行的SQL与RPC

School DB结构/正式写入：

1. `sql/current/school_tuition_r1b_operational_isolation_and_consistency.sql`：rollback验证和正式部署；
2. `sql/current/school_tuition_r1b_fixed_historical_backfill.sql`：最终rollback演练和正式commit；
3. `sql/current/school_tuition_r1b_restore_income_updated_at.sql`：固定补偿rollback演练和正式commit。

School DB只读/rollback验收：

1. R1A School baseline和postdeploy readonly；
2. `school_tuition_r1b_postdeploy_readonly.sql`；
3. `school_tuition_r1b_guard_rollback_tests.sql`；
4. `school_tuition_r1b_r0_entry_probes.sql`。
5. `school_tuition_r1b_old_new_consistency_rollback_tests.sql`：七项OLD/NEW双端负向测试，7/7拒绝、业务残留0。

Cash DB只读：R1A Cash baseline，正式执行前后均相同。

没有成功调用任何业务写RPC；R0探针调用全部按预期失败。

## 10. 文件与Git交付

修改API：

- `js/api/account-transaction-detail-api.js`
- `js/api/income-api.js`
- `js/api/income-detail-api.js`
- `js/api/part-time-work-api.js`
- `js/api/profit-summary-api.js`
- `js/api/settlement-api.js`
- `js/api/settlement-detail-api.js`
- `js/api/tuition-receipt-api.js`

新增SQL：

- `sql/current/school_tuition_r1b_operational_isolation_and_consistency.sql`
- `sql/current/school_tuition_r1b_fixed_historical_backfill.sql`
- `sql/current/school_tuition_r1b_restore_income_updated_at.sql`
- `sql/current/school_tuition_r1b_guard_rollback_tests.sql`
- `sql/current/school_tuition_r1b_postdeploy_readonly.sql`
- `sql/current/school_tuition_r1b_r0_entry_probes.sql`
- `sql/current/school_tuition_r1b_old_new_consistency_rollback_tests.sql`

文档：本报告及`docs/current-status.md`。

精确暂存命令：

```bash
git add \
  docs/current-status.md \
  docs/school-v2-r1b-tuition-historical-backfill-incident-isolation-report-20260727.md \
  js/api/account-transaction-detail-api.js \
  js/api/income-api.js \
  js/api/income-detail-api.js \
  js/api/part-time-work-api.js \
  js/api/profit-summary-api.js \
  js/api/settlement-api.js \
  js/api/settlement-detail-api.js \
  js/api/tuition-receipt-api.js \
  sql/current/school_tuition_r1b_fixed_historical_backfill.sql \
  sql/current/school_tuition_r1b_guard_rollback_tests.sql \
  sql/current/school_tuition_r1b_old_new_consistency_rollback_tests.sql \
  sql/current/school_tuition_r1b_operational_isolation_and_consistency.sql \
  sql/current/school_tuition_r1b_postdeploy_readonly.sql \
  sql/current/school_tuition_r1b_r0_entry_probes.sql \
  sql/current/school_tuition_r1b_restore_income_updated_at.sql
```

建议commit message：

```text
feat: backfill tuition billing history and quarantine duplicate incident
```

审查、暂存和commit后的push命令：

```bash
git push origin main
```

最终代码审查已经通过并批准R1B Git交付。`docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`仅为ChatGPT临时审查材料，不属于暂存或commit范围。

## 11. 下一阶段仍禁止事项

在新的阶段授权和审查前，继续禁止：解除R0 gate、原子生成RPC、正式预览候选、52条迁移、孙陈锋两条跨月课修改、week/date模型、JS durationHours、退款/冲销/普通取消、Cash历史修改、School账户流水修改、金额/汇率/通知金额修改、planned/actual修改、工资/结算修改、业务归属修改、删除历史记录。

R1B到此停止，等待业务负责人和ChatGPT审查。
