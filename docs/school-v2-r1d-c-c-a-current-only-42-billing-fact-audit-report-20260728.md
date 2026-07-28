# School V2 学费链P0：R1D-C-C-A 42条current-only候选收费事实只读审计报告

- 审计日期：2026-07-28
- Git基线：`eba88297a236cc87303839aa36c54a375c85a872`（HEAD与`origin/main`一致）
- School最终正式只读事务：`2026-07-28 07:45:34.785059+00`，`REPEATABLE READ READ ONLY`
- Cash最终只读事务：`2026-07-28 07:45:45.055222+00`，与School分别读取，不宣称跨库原子快照
- DDL/DML/write RPC/数据库写入：`0 / 0 / 0 / 0`
- R0：`validation_preview_only / blocked / blocked`
- 结论：固定42条全部归入`exclude_reviewable_medium`；业务负责人已按固定Manifest批准其为“历史已收费、未来candidate应排除”的固定业务集合。没有lesson级直接收费证据，后续仍须建立不可变排除证据；本次批准不授权candidate函数修改，candidate切换继续阻断。

## 1. 审计结论

最终集合仍精确为：

| 集合 | 行 |
|---|---:|
| 当前R1C-B旧字段candidate | 160 |
| 完整合法新归属字段candidate | 118 |
| intersection | 118 |
| current-only | 42 |
| new-field-only | 0 |

42条仍在当前candidate中不是因为数据漂移，而是当前`school_list_student_tuition_candidates`只把normalized relation、bill JSON兼容证据、作废/状态、billable及字段完整性作为权威排除条件；它不把linked actual、locked settlement、received income或账户流水自动解释为lesson已经收费。42条自身仍为`planned + active + billable + 字段完整 + 无bill evidence`，因此当前函数继续返回candidate。它们的R1D-B新归属字段均为NULL，所以不进入只采用合法新字段的118集合。

审计发现：

- 42/42精确关联1条actual；一planned多actual为0；
- 41条actual为`completed`，1条为`makeup_completed`；
- 42/42 actual与planned的学生、业务归属、科目、老师、时长、费用及旧月份一致；跨月actual为0；
- 42/42 actual在对应locked settlement之前创建；
- 42/42 actual均至少进入一个当前有效locked教师工资快照；
- 四个学生/月/业务归属组均有locked月结、一笔received JPY 204,000 tuition income及一条同额School账户流水；
- 四组月度planned汇总均为JPY204,000，与received JPY精确相等；
- 但月结只保存月度聚合字段，没有lesson UUID、lesson detail或immutable lesson snapshot；
- 四组tuition bill、normalized bill relation、student payment、School Cash linkage及Cash external request/transaction固定引用均为0。

因此当前事实高度支持“这些课程所在月份已经结算并收到全月学费”，但不足以由数据库自动证明“每个固定lesson UUID已经进入不可变收费明细”。42条统一归入Manifest B `exclude_reviewable_medium`；业务负责人已基于本报告的固定清单明确批准这42个UUID作为历史已收费、未来candidate应排除的固定业务集合。Manifest A/C/D当前均为空。

## 2. 固定42及既有汇总复核

| 学生/月 | 条数 | 小时 | 目标JPY | old31 aggregate hash |
|---|---:|---:|---:|---|
| 陈加恩 2026-05 | 10 | 20 | 170,000 | `e2677dccdc55a10ac004a68c13266f40` |
| 陈红卓 2026-05 | 10 | 20 | 170,000 | `e46ffe10a180495961d8ebf2535b7e8d` |
| 陈加恩 2026-06 | 12 | 24 | 204,000 | `6af41dcff271f6cc63b9f561b1460067` |
| 陈红卓 2026-06 | 10 | 20 | 170,000 | `a7d68461ee4eb61214bc122df3c8b214` |
| 合计 | 42 | 84 | 714,000 | `dc6cd4ad206cc09ed5c02dfe6da5462b` |

数量、学生、月份、课时与金额和R1D-C-A完全一致。完整UUID、逐行old31 hash、actual、settlement、income、account transaction和evidence hash冻结于`docs/school-v2-r1d-c-c-a-current-only-42-fixed-manifests-20260728.md`；aggregate evidence hash为`dc2546bff536942650db58e437d37f0e`。

正式SQL不按姓名/月动态固定对象：42行静态VALUES是审计真值，实时current-only差集只用于fail-closed核对。如果UUID、old31、actual、settlement、income、账户流水或集合任何一项漂移，DO断言拒绝继续输出。

## 3. Planned→actual与工资链

42条actual状态：

| 状态 | teacher settlement month | 行 | 小时 | JPY |
|---|---|---:|---:|---:|
| completed | 2026-05 | 20 | 40 | 340,000 |
| completed | 2026-06 | 21 | 42 | 357,000 |
| makeup_completed | 2026-06 | 1 | 2 | 17,000 |

唯一`makeup_completed`来源planned为`7e5730ec-ad51-4f8b-87a6-c4cc225b6ede`，actual为`05451028-ecdb-41d2-8077-baf8e1ad3e97`。它仍是billable JPY17,000，学生/业务归属/科目/老师/时长/费用一致，且在陈红卓2026-06月结锁定前生成。42条均无cancelled、partial或多actual冲突。

工资证据只证明老师履约/工资结算，不证明学生收费；本报告仅把42/42当前有效locked wage snapshot作为履约链交叉证据，不把它提升为student tuition bill evidence。部分actual还有旧voided工资快照版本，最终检查按distinct actual确认42/42均有有效locked版本。

## 4. Locked settlement真实语义

仓库和Git历史核对：

- `bd29e974895e3706453f23525e05278133199a17`（2026-06-09）首次加入学生月结锁定RPC；
- `2dc1083f70346a0eeb126574a3bf156f9f3b3c6c`加入月结差额调整；
- `24cedeb89f8b73a845ba8e44a29bc03b81316d7c`把差额调整移到锁定前；
- 当前`school_get_student_monthly_settlement_summary`按学生和旧`year_month`聚合非作废planned、有效billable actual及received tuition income；
- `school_lock_student_monthly_settlement`把汇总值复制到一行`school_student_monthly_settlements`。

月结表只有24个汇总/状态/时间字段，没有planned UUID、actual UUID、lesson JSON或明细snapshot；数据库中也不存在约定名称的月结lesson detail表。详情页当前按`student + year_month + business_entity`动态重新查询lesson/income，这不是锁定时immutable明细。

四组月结：

| 学生/月 | settlement | locked_at | planned JPY | actual JPY | received JPY | adjustment | final carryover |
|---|---|---|---:|---:|---:|---:|---:|
| 陈加恩 2026-05 | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `2026-06-01 01:12:53.63+00` | 204,000 | 170,000 | 204,000 | +1,476，后续补课 | 0.40000000000009095 |
| 陈红卓 2026-05 | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `2026-06-01 01:13:03.95+00` | 204,000 | 187,000 | 204,000 | +731，后续补课 | 0 |
| 陈加恩 2026-06 | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `2026-06-28 14:28:26.384411+00` | 204,000 | 204,000 | 204,000 | -0.40，抹平 | 0 |
| 陈红卓 2026-06 | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `2026-07-01 01:04:25.804881+00` | 204,000 | 187,000 | 204,000 | +731，7月5日补课 | 0 |

May两组和陈红卓June各有2条、4小时、JPY34,000的非目标`pending_makeup` planned；月度planned 204,000覆盖目标与这些非目标行。只读数据库证据本身无法合法地把204,000自动拆分到固定42中的每一条。业务负责人现已明确确认，陈加恩、陈红卓2026年5月和6月的四笔JPY204,000收入就是对应月份全部planned课程的学费，包含这6条`pending_makeup`；该确认解释月度总额，但6条不属于固定Manifest B，本批准不处理或动态纳入它们。

## 5. 收费、收款与资金链

四笔School收入均为`income_category=tuition`、`status=received`、JPY204,000、`include_in_student_settlement=true`：

| 学生/月 | income | income date | School account transaction |
|---|---|---|---|
| 陈加恩 2026-05 | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | 2026-05-18 | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` |
| 陈红卓 2026-05 | `18a80ecd-4486-44d6-95ca-324d2030404f` | 2026-05-18 | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` |
| 陈加恩 2026-06 | `3176d629-f319-497a-95ae-2366a43cdf7a` | 2026-06-01 | `fd90b997-d31d-4553-bda3-a9cc2096c404` |
| 陈红卓 2026-06 | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | 2026-06-01 | `bb124b53-ab20-4c85-aad2-a83bc316132d` |

每笔账户流水均为JPY204,000的`income_adjust`，直接关联对应income。四笔income的`source_type/source_id/tuition_bill_id/student_payment_id`均NULL；没有tuition bill、bill JSON lesson ID、normalized relation、billing identity或student payment，因此不是R1A/R1B意义的canonical收费链。

School的两类Cash linkage对四笔income引用均为0；Cash DB以四个income UUID搜索external request、CNY transaction和JPY transaction均为0。这不否定School旧账户流水所记录的收款，只说明该2026-05/06旧流程没有当前Cash外部引用证据。仓库中未发现把固定42 UUID写入Excel、历史报告或其他immutable收费明细的证据。

## 6. 证据分类与业务批准

| Manifest | 行 | 结论 |
|---|---:|---|
| A `exclude_high` | 0 | 没有lesson级immutable收费证据 |
| B `exclude_reviewable_medium` | 42 | actual + locked settlement + received tuition income + School账户流水 + 月度全额对账，缺lesson级snapshot；固定42 UUID已获业务批准排除 |
| C `needs_billing` | 0 | 没有发现明确未收费证据；不能因C为空就未经批准宣称已收费 |
| D `conflict/unavailable` | 0 | 当前School/Cash证据内部没有矛盾或无法解释的金额 |

业务负责人已明确确认并批准：四笔JPY204,000收入是对应学生月份全部planned课程的学费，包含后来进入`pending_makeup`的6条课程；固定Manifest B的42 UUID已包含在四组历史月度全额收费/收款中，未来candidate应将其作为历史已收费集合排除。

批准严格限定为Manifest B明确列出的42个UUID，不动态扩展到同学生、同月份、同业务归属或其他lesson；不补造历史tuition bill、bill relation、identity或月结lesson snapshot；不回填这42条的新收费归属字段；不处理6条`pending_makeup`；不授权修改candidate函数或解除R0。后续实施必须另开独立阶段，建立不可变排除证据并经过rollback、postdeploy和Git审查。

## 7. Candidate四方案只读模拟

| 方案 | 显示candidate | 未决差异 | 结论 |
|---|---:|---:|---|
| 1：仅新字段118 | 118 | 42 | 42从集合消失不等于逐课证明收费，不能切换 |
| 2：118 + Manifest A | 118 | 42 | A为空，42全部继续阻断 |
| 3：118 + 经批准A/B | 118 | 0 | 固定B已获业务批准；须待独立阶段建立不可变证据并修改candidate后方可采用 |
| 4：实施前继续阻断 | 160 | 42 | 当前推荐状态，保持现行candidate和R0直至后续实施获批并验收 |

本阶段没有修改candidate函数，也没有把Manifest B写入数据库。业务批准只解决固定42 UUID的收费事实归属；后续仍需独立设计固定排除证据、不可变审计、OLD/NEW一致性、rollback、postdeploy及候选切换方案。

## 8. School/Cash基线

School审计前后count/hash一致：

| 对象 | count | hash |
|---|---:|---|
| lesson raw37 | 626 | `c4f892d857fe674e4060f80d6af56b42` |
| lesson old31 | 626 | `4fb1901c888d56cb29c05e387490ca75` |
| bill | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| relation | 121 | `09dfee7d8833e09384fb41a84f2959e0` |
| migration batch/item | 2 / 118 | `18e74c21ebf95fdf80bed6767a4e28be` / `23a2f93d0db01d84ba6195573ec58790` |
| settlement | 15 | `7925cf3018bd0e669cd29710f6593238` |
| settlement adjustment | 5 | `4bce2b158d4de769d592a2d367881868` |
| student payment | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| School account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| teacher wage lock/detail | 95 / 556 | `7bbe108d3ac73d4f21530793bf141bc6` / `6204dc666b3b8e0f64fac901ecf0686a` |
| feature gate | 3 | `da00c76d8f8c72dd2decdac8ab6125b8` |
| override audit | 0 | `d41d8cd98f00b204e9800998ecf8427e` |

A1 52及A2 66归属字段、118条old31和两个既有decided_at未变化；scheduled仍全库NULL；candidate仍160/118/42/0。

Cash前后分别为：

| 对象 | count | hash |
|---|---:|---|
| external request | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| CNY transaction | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| JPY transaction | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

Cash数据库零写入。

## 9. R0、SQL/RPC及异常披露

R0保持：

- `student_tuition_preview = validation_preview_only`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

本阶段没有主动调用写入口或R0写RPC探针。只在SELECT/readonly DO中直接读取`school_list_student_tuition_candidates`及`school_is_valid_tuition_billing_period`；没有通过Supabase RPC接口调用函数。

正式仓库SQL：

- `sql/current/school_tuition_r1d_c_c_a_current_only_42_billing_fact_readonly.sql`

外部`/private/tmp`只读调查SQL：

- `r1d-c-c-a-schema-inventory-readonly.sql`
- `r1d-c-c-a-evidence-exploration-readonly.sql`
- `r1d-c-c-a-evidence-details-readonly.sql`
- `r1d-c-c-a-freeze-lines-readonly.sql`
- `r1d-c-c-a-final-preflight-readonly.sql`
- `r1d-c-c-a-cash-evidence-readonly.sql`

异常/修正记录：

1. 首次非interactive shell没有加载`load_both_db`，只输出两个环境变量missing；未连接数据库、未执行SQL。改用interactive shell后确认双库变量存在。
2. 一次探索性工资汇总直接连接工资明细版本，返回84个joined rows；这不是42条actual数量漂移。最终以distinct actual核对，确认42/42均有有效locked工资快照，历史detail版本每条1至3个。
3. 正式只读SQL首次运行在42行明细之后因Manifest汇总的`planned_lesson_id`列歧义报错，事务abort；限定`manifest.planned_lesson_id`后修正。
4. 第二次运行通过Manifest、月结/收款和School基线，在最后R0展示查询因使用不存在的`gate_state`列报错，事务abort；修正为实际`state`并补充三项R0 fail-closed断言。
5. 第三次正式只读事务完整通过并COMMIT。上述失败均在`READ ONLY`事务内，无DDL/DML、临时对象或数据库写入。

## 10. Git停止点

本阶段新增正式只读SQL、实施报告和固定Manifest，并更新`docs/current-status.md`。业务批准后仅同步更新本报告、固定Manifest和current-status中的审批状态；未修改只读SQL，未重新连接数据库或执行SQL/RPC。未执行`git add`、commit或push；不启动candidate切换、writer改造、actual继承、scheduled date处理或数据库回填。
