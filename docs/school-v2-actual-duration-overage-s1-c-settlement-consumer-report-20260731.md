# Aozora V2 actual duration overage S1-C settlement consumer实施与验收报告

日期：2026-07-31（Asia/Tokyo）
Git基线：`403b23231b42e73b28af933f416911f222da5d3b`
停止点：`S1-C_DATABASE_REVIEW_POINT`

## 1. 结论

S1-C已完成School DB部署和验收。来源月学生月结现在只消费S1-B ordinary actual在写入时冻结的overage事实：未锁定preview读取live aggregate，首次lock在同一事务重新汇总并写入6字段snapshot，locked读取使用snapshot，relock替换同一snapshot而不叠加；来源月锁定后的既有`carryover_amount_cny`继续由下一自然月preview读取一次。

本阶段没有修改candidate、bill、billing identity、income或Cash，也没有进入S1-D。原来源月账单、income及Cash不被修改；R0保持`validation_preview_only / blocked / blocked`。

## 2. 资格与冻结事实

新增内部helper：

- `school_get_student_duration_overage_aggregate(uuid,text)`

live aggregate只读取同时满足以下条件的lesson：

- `lesson_type = 'actual'`；
- `status = 'completed'`；
- `is_billable = true`；
- 业务归属为数据库权威青空进学塾；
- `student_settlement_month`等于来源学生月；
- `student_duration_overage_policy_version = 'student_duration_overage_v1'`；
- `student_duration_overage_source = 'ordinary_actual_rpc'`；
- 冻结分钟和冻结JPY均大于0。

聚合直接求和`student_duration_overage_minutes`和`student_duration_overage_fee_jpy`。helper不读取actual/planned时长差、`unit_price`、`lesson_fee`、actual日期、legacy月份、aircon或其他附加费。

helper仅向`service_role`开放；summary作为同owner的SECURITY DEFINER函数调用它，anon/authenticated不能直接执行该内部helper。

## 3. 来源月汇率与月结公式

live preview按来源月月结当前权威`preset_exchange_rate`进行一次DB舍入：

```text
duration_overage_fee_cny
= round(duration_overage_fee_jpy × source month exchange rate, 2)
```

当前系统的`final_due_cny / carryover_amount_cny`采用“应收为正”的既有符号约定，因此“overage只增加正向应收”落地为：

```text
final_due_cny
= planned_fee_cny
+ duration_overage_fee_cny
+ previous carryover_cny
- received_equivalent_cny
```

没有恢复`actual total - received`。`actual_fee_jpy/cny`继续只作为既有信息字段，partial、cancelled、makeup或NULL policy记录不会降低planned应收。manual adjustment仍在preview外层按既有方式加入`locked_carryover_cny`，未改变其审计和生命周期。

## 4. snapshot、locked读取与relock

首次lock和relock均写入：

- `duration_overage_minutes`；
- `duration_overage_fee_jpy`；
- `duration_overage_fee_cny`；
- `duration_overage_actual_count`；
- `duration_overage_policy_version = 'student_duration_overage_v1'`；
- `duration_overage_source = 'monthly_settlement_lock'`。

`monthly_settlement_lock`沿用S1-A已验证CHECK的canonical来源值，没有修改S1-A约束。新策略月份即使overage为0，也会写入`0 / 0 / 0 / 0`和policy/source，形成明确snapshot。

locked月份由helper读取snapshot；若历史locked settlement的6字段仍为NULL，则返回0并标记内部basis为`legacy_locked_null_snapshot`，不会从历史lesson动态推导收费。relock只允许现有R1D E-C生命周期允许的非legacy、无posted adjustment、无active carryover记录，重新汇总后覆盖同一6字段snapshot，不执行加法叠加。

## 5. carryover边界

未新增carryover表、消费身份或candidate逻辑。现有summary仍按以下优先级读取下一月carryover：

1. 显式active carryover记录；
2. 上一自然月locked settlement的`carryover_amount_cny`；
3. 学生fallback balance。

测试证明来源月overage增加来源月`final_due_cny`和锁定余额；下一自然月两次preview均读取相同上月锁定余额一次，没有重复增加。原来源月bill保持不变。

## 6. 历史宽松策略

部署SQL不包含历史lesson或历史settlement DML，不执行backfill，也不扫描`actual > planned`差额。overage字段为NULL的lesson不参与新机制；历史locked settlement的6字段继续允许为NULL。

本阶段按新口径没有重复核验固定19条UUID、逐行哈希、全量lesson哈希或全资金表哈希。部署前后只验证：

- 正式lesson overage bundle非NULL：`0 → 0`；
- 正式settlement overage snapshot非NULL：`0 → 0`；
- bill行数：`9 → 9`；
- income行数：`42 → 42`；
- Cash DB未连接。

## 7. 数据库对象与MD5

| 对象 | before | after |
| --- | --- | --- |
| overage aggregate helper | 不存在 | `d24b82f51053b3960ce0e4839613ddc7` |
| settlement summary | `86b93835aaed296fb908d26ee2559eae` | `f9f5e0fffc2d0fcb5f917cc374c9e9ac` |
| settlement lock | `323216425f47e1cfa2960b4341ef452c` | `523058b631837025101d558668ce10c8` |
| settlement relock | `060c25ee1ab25d8d72ab5f43f32728b5` | `5b313cc696057a4a1f960ed8f1b50124` |

保持不变：

- settlement preview：`1ddcfdd0344ba0ea3cf06d12058796ba`；
- settlement unlock：`dfeaa0243b27999724cc06bd1f1efbb6`；
- S1-B ordinary writer：`e3d9dd24f3fd7c533301bb5c1a27fa4f`；
- S1-B guarded updater：`ca52667c94a86608b4ab712f543b04b1`；
- E-B2 trigger：`4a163f6691c779531a65a10be0f4422e`；
- F1 trigger：`08f3c60890d4afab8d9c730eec286c8d`；
- R1D E-C resolver/set helper：`8de65e9787d8d66f2cd7b65eb2479a8c` / `155e831118acbeadfd04b6640324c7cd`；
- 6个S1-A CHECK定义及MD5。

未新增overage trigger，未修改table、column、index、RLS、既有ACL、writer、candidate、bill或Cash对象。唯一ACL变化是新helper从默认权限收窄为service-role-only。

## 8. SQL执行与验收

正式部署执行一次并成功COMMIT：

- `sql/current/school_actual_duration_overage_s1_c_settlement_consumer.sql`

只读postdeploy执行两次，均在READ ONLY事务中全部通过并显式ROLLBACK：

- 部署后首次目录验收；
- rollback测试后最终复验。

整体rollback tests共执行两次：

1. 首次在创建第二条planned fixture时触发现有`planned duration must be an integer number of hours and at least 2`规则。该错误发生在目标断言前；连接退出后只读复核确认lesson/settlement marker均为0，正式overage非NULL仍为0。
2. 将该无关fixture从1小时修正为2小时，同时把actual从1.25小时修正为2.25小时，保持15分钟/JPY 300目标不变。第二次12/12通过并显式ROLLBACK。

通过项：

- zero和排除项聚合；
- 两条事实求和为45分钟/JPY 800；
- actual发生月不改变来源学生月；
- 来源月汇率换算；
- final due只正向增加overage；
- lock写入6字段；
- locked重复preview不叠加；
- relock替换snapshot；
- 下一月carryover只出现一次；
- bill/income不写；
- S1-B writer MD5和R0不变；
- marker残留0。

事务内actual测试ID：

- `7ccd7ef7-ec22-4dde-a759-bc308983201e`；
- `3460de4c-4b52-4f3d-a74a-37dae139d619`；
- `4d79a53f-9998-41e4-8da3-032243b37739`；
- `641c35dc-2dbd-4b3b-b66a-a74da8e8b4a7`；
- `0e85ca16-b429-439b-b7ed-f67ee2642788`；
- `9a18a26f-7ee1-48e9-9cf0-15d0eb592ccd`。

以上测试数据全部ROLLBACK，正式或测试marker残留为0。

## 9. 当前边界与停止点

S1-C只完成settlement consumer：S1-B事实现在能够进入来源月final balance并通过既有carryover影响下一月preview。candidate、补充收费身份、bill、income和Cash仍未消费overage；正式overage bundle与settlement snapshot当前仍为0。

R0最终保持：

- `student_tuition_preview = validation_preview_only`；
- `student_tuition_generate = blocked`；
- `student_tuition_cash_submit = blocked`。

当前停止在`S1-C_DATABASE_REVIEW_POINT`。没有git add、commit或push，不进入S1-D。
