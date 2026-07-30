# R2-B canonical candidate reader兼容F1新planned来源报告

日期：2026-07-31
Git基线：`aee5144169a4b4c7017fde1be43bdb3774822df8`

## 结论

本阶段只替换：

```sql
public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)
```

candidate定义MD5由`8981a2ce07abf8c28231bfaf05451368`变为`1770f3469dbc3bc030a977381b853deb`。内部reader继续只允许`service_role`，`PUBLIC`、`anon`、`authenticated`均无执行权。R2-A authenticated wrapper及既有preview函数定义、签名和ACL未改变。

唯一canonical candidate reader现在允许四类完整来源：

- `approved_r1c_a_manifest`
- `approved_r1c_c_b_manifest`
- `scheduled_date_at_create`
- `explicit_billing_week_at_create`

修改没有按`lesson_date`、`year_month`或客户端输入重新计算归属月。source放宽仍要求五字段完整、月份合法、student settlement month一致、week start为周一且与billing month一致、decided_at存在，以及既有学生/业务归属/老师/科目/课次数/时长/单价/费用、planned状态、billable和时间字段完整。normalized bill relation、账单JSON snapshot、历史排除、legacy evidence和冲突证据继续fail-closed。

当前catalog调用链只有：

- `school_preview_student_tuition_bill`调用canonical reader；
- `school_get_student_tuition_validation_preview_details`同时复用preview和canonical reader；
- canonical reader自身。

两个`school_generate_student_tuition_bill`重载仍是R0 fail-closed stub，不读取lesson，也没有另一套candidate规则。

## 执行与测试

执行文件：

- `sql/current/school_tuition_r2_b_candidate_f1_source_compatibility.sql`
- `sql/current/school_tuition_r2_b_candidate_f1_source_compatibility_postdeploy.sql`
- `sql/current/school_tuition_r2_b_candidate_f1_source_compatibility_rollback_tests.sql`

完整rehearsal先替换函数、运行rollback fixtures和current postdeploy，再整体`ROLLBACK`，旧函数hash恢复且fixture残留0。正式部署随后无SQL错误`COMMIT`，postdeploy与独立rollback tests均通过。

rollback fixtures使用同一学生/业务归属的2032-07空白scope：

- scheduled fixture：lesson date `2032-08-01`，权威week start `2032-07-26`，billing month `2032-07`，source=`scheduled_date_at_create`；
- explicit fixture：先由F1 batch writer确定week start `2032-07-26`，再把lesson date更新为`2032-08-01`；权威billing month仍为`2032-07`，source=`explicit_billing_week_at_create`。

两条均只进入2032-07 candidate，不进入2032-08；R2-A detail同一响应返回两条且两个source均存在，preview汇总与candidate count/hours/fee一致。独立测试ID为`fc73d6a1-704f-4ab6-b26e-8f906f07da25`与`3cc049ad-cbec-4ae2-9e30-eeacb57e3f1f`，均已ROLLBACK，残留0。

测试同时验证：legacy NULL bundle不进入、partial完整性判定fail-closed、existing relation/JSON snapshot/historical exclusion均不与candidate相交、UUID重复0、ACL未扩大、R0不变。没有创建测试bill或income。

## 正式生产验收

部署前生产planned来源为：279条legacy NULL bundle、52条R1C-A manifest、66条R1C-C-B manifest、17条`explicit_billing_week_at_create`；尚无`scheduled_date_at_create`生产行。部署前17条explicit行均仅因旧allowlist被标记`invalid_or_incomplete_data`；部署后17条全部正常分类。

当前candidate披露值：

| source | UUID | lesson count | hours | fee JPY |
|---|---:|---:|---:|---:|
| approved_r1c_a_manifest | 52 | 59 | 109 | 1,024,000 |
| approved_r1c_c_b_manifest | 66 | 79 | 145 | 1,450,000 |
| explicit_billing_week_at_create | 17 | 20 | 40 | 360,000 |
| 合计 | 135 | 158 | 294 | 2,834,000 |

135是当前运营结果，不是永久断言。candidate UUID全局唯一，完整性和证据排除验收通过。

当前张倬闻2026-08 R2-A真实preview仍为30 UUID、35课次、65小时、JPY 650,000；UUID MD5=`29389fd78b127bc9b42cf90559e2ac56`，manifest SHA-256=`79b9119d4f6ed50dd187c448b80c91160ee9f7e26cc2c411bec4ad767b707c74`。生产中`2026-07-27`起始周在7月为1条、在8月为0条；`2026-08-31`起始周在8月为12条。

最终R0仍为preview=`validation_preview_only`、generate=`blocked`、cash submit=`blocked`。lesson/bill/income行数保持652/9/42，业务表fingerprint未改变。永久数据库变化只有candidate函数定义/注释及原ACL重授予；业务DML为0，Cash未连接。

首次rehearsal按计划用postdeploy hash占位符取得规范化MD5，随后写入固定hash并完整重跑通过；另一次只读catalog查询误包含aggregate，添加`prokind='f'`后通过。正式部署和正式postdeploy无错误。

R2-B已关闭F1 source兼容缺口，未发现额外candidate/preview规则缺口。正式generate仍由R0与两个fail-closed stub阻断；恢复真实writer属于后续独立阶段，本阶段未实现或授权。
