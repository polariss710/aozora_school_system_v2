# School V2 R2-F-F 学费Preview、Atomic Generate与空调费受控恢复报告

日期：2026-08-01
停止点：commit前审查点

## 结论

R2-F-F数据库与前端验收完成。正式gate现为：

- `student_tuition_preview = enabled`
- `student_tuition_generate = enabled`
- `student_tuition_cash_submit = blocked`

本阶段没有生成真实bill或income，没有连接Cash DB。唯一持久配置DML是两条venue master记录和三条gate状态更新；lesson、settlement、资金、工资及Cash linkage业务表全行指纹不变。

## 固定办公室与整小时政策

既有`public.school_lesson_venues`已经包含结构化`aircon_eligible`，无需新增表或模糊匹配场地名称。R2-F-F写入两个确定性配置：

| venue | ID | delivery | aircon eligible | effective from |
|---|---|---|---:|---|
| Regus办公室 | `f2ff0000-0000-4000-8000-202608010001` | onsite | true | 2026-08-01 |
| Regus公共区 | `f2ff0000-0000-4000-8000-202608010002` | onsite | false | 2026-08-01 |

calculator优先按venue ID解析；历史/当前lesson尚无ID时仅允许精确`venue.code = lesson_venue`回退，同时核对active、delivery mode和生效日期。不使用`ILIKE`、模糊字符串或“所有onsite均收费”的规则。

v2算法：

```text
aircon_billable_hours = floor(planned_duration_hours)
aircon_fee_jpy = saved_aircon_rate_jpy_per_hour × aircon_billable_hours
```

只有student settlement month不早于2026-08、周六/日、onsite、有效收费venue及正费率同时成立才收费。actual日期、actual时长和overage不参与。

旧五参数calculator因没有delivery/venue上下文，现永久返回`R2_F_F_AIRCON_VENUE_CONTEXT_REQUIRED`。新八参数overload MD5为`533ead6b181d64aee88ec5674ae4e8b0`。

## 现有数据审计

修改前只读结果：

- planned：414条；组件化快照：1条；正费率/正空调费：1/1。
- planned小数时长：7条；其中组件化小数时长：0。
- 周末onsite planned：5条；组件化且收费场地仅孙陈锋目标课时1条。
- 历史121条bill relation的正空调费：0条，合计JPY0。
- 没有已经进入正式资金快照的场地或整小时错误。
- 唯一未收费但正空调费课时：`6c70c4c1-1895-453d-b9b0-591e9f004f86`。

该真实课时保持原v1快照且未被cutover更新：2026-08-08周六、onsite、Regus办公室、2小时、JPY330/h、aircon 2小时/JPY660、base JPY17,000、total JPY17,660。未来对未收费组件化planned的日期、venue、delivery mode、duration或费率进行合法修改时，统一trigger按v2重算；已收费事实继续冻结。

## Writer与Reader统一

- 单条新增、批量生成、guarded update、历史兼容import和直接DML最终都经过`trg_school_lesson_r2_e_planned_aircon`。
- trigger调用带delivery/venue上下文的v2 calculator；场地、日期、mode、duration或rate变化会重算hours、aircon fee及course total。
- billed planned新增冻结delivery mode、venue code及venue ID，不能绕过正式收费快照。
- canonical candidate reader只接受legacy base-only、v1或v2完整bundle；complete-row证据加入billable hours、delivery mode、venue ID/code及policy。
- generation snapshot对v1/v2都验证`fee = rate × billable hours`，candidate line及generation manifest覆盖相同venue/aircon事实。
- normalized relation约束和validator接受并验证v2，继续要求JSON line、relation source snapshot、candidate line hash及generation manifest一致。

部署后关键MD5：

| 对象 | MD5 |
|---|---|
| planned aircon trigger | `e7820acbf80b3e5b1c02bc3ad9664762` |
| v2 calculator | `533ead6b181d64aee88ec5674ae4e8b0` |
| canonical charge reader | `65e718ba8d2e4cb46ebb0dc84b11bc2e` |
| generation snapshot | `bd1e8aebbe3038ff7423a1f8868b9220` |
| bill relation validator | `a19303aa66034a8900fe1077f1a1adc9` |
| enabled preview RPC | `11ef7b45932e6cd418c03c91da104fd0` |
| public atomic wrapper | `36bdadc9af59637c9d336ce68d9afb4c` |
| owner-only atomic core | `c6bd995a4703306d049ea30a9fb2ae17` |

## SQL执行证据

### Policy

- 同字节rehearsal：`r2_f_f_policy_commit=0`，全部DDL/配置/preview验证通过，明确`R2_F_F_POLICY_ROLLBACK`。
- 正式：相同文件以`r2_f_f_policy_commit=1`执行，明确`R2_F_F_POLICY_COMMIT`。
- 持久DML仅两条`school_lesson_venues`配置；没有lesson或资金业务DML。

### Gate

- 同字节rehearsal：`r2_f_f_gate_commit=0`，事务内临时切换`enabled/enabled/blocked`，两名preview及四个旧入口验证通过，明确ROLLBACK。
- 正式：相同文件以`r2_f_f_gate_commit=1`执行，更新三条gate并明确COMMIT。
- disable文件以`r2_f_f_disable_commit=0`完成回滚演练；未正式disable。
- gate切换没有调用atomic wrapper/core，没有创建业务记录。

旧generate两个overload、旧bill→income及Personal Cash入口在generate enabled时仍分别抛出永久R0 stub错误。公开唯一生成入口为`school_generate_student_tuition_bill_atomic(...)`；atomic core ACL仍只有postgres。

## Rollback测试

最终矩阵5/5通过并明确ROLLBACK：

1. `policy_matrix`：办公室/公共区/online/工作日/2.5h/0.5h及旧calculator绕过。
2. `actual_overage_isolation`：planned 2h保持aircon JPY660；actual 2.25h只冻结15分钟/JPY2,500 overage。
3. `venue_manifest`：收费venue改为非收费venue后fee和manifest变化，旧manifest被拒；恢复原事实后manifest稳定恢复。
4. `atomic_consistency`：bill、relation、identity、income的JPY660、course total及manifest一致，validator通过，完全相同参数幂等返回原ID。
5. `atomic_failure`：`after_relations`故障注入后四对象均无残留。

最终成功运行测试ID：

- student A/B：`f2ff0000-0000-4000-8000-00000000a001` / `...a002`
- planned A：`156a4979-4d25-4448-bb77-352ccf1cbd7e`
- actual A：`240fb847-82e1-48bc-aabb-1620805dcd1e`
- planned B：`d4df735f-62d8-4563-8eff-1b7e9a5faeff`
- rollback bill/identity/income：`0ce8df6a-d8ed-44f6-8f5f-dc13b473d893` / `185347b9-fb8c-41ba-9194-df8eec7a79f1` / `2d8e9e43-cac5-48c2-9402-7a2636198b51`

残留检查为0。前两次测试运行分别因测试字段名和“恢复相同事实时manifest应不同”的错误预期中止，连接事务均自动回滚；修正测试脚本后通过，没有业务逻辑失败。

## 正式Preview与全学生分类

孙陈锋2026-08：

- 22 candidates / 24课次 / 44小时
- base JPY374,000 / aircon JPY660 / total JPY374,660
- exchange rate 0.042 / carryover CNY0 / notification CNY15,735.72
- 8月1/2日四条跨月planned/actual全部保持2026-07归属，8月candidate=false

张倬闻2026-08：

- 30 candidates / 35课次 / 65小时
- base及total JPY650,000 / aircon JPY0
- exchange rate 0.043 / carryover CNY107.50 / notification CNY28,057.50

两者均返回`feature_state=enabled`及`generate_feature_state=enabled`，没有既存本月canonical bill/identity。

8名活跃学生分类：孙陈锋、张倬闻有候选且可生成；厦门吕同学为`R2_F_B_CANDIDATES_EMPTY`；彭宇晗、李天伦、袁振轩、陈加恩、陈红卓均为`R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED`。没有执行空账单生成。

## 前端/API

- preview utility接受DB返回的`validation_preview_only|enabled`，但正式按钮只有`feature_state=enabled`且`generate_feature_state=enabled`时可用。
- 没有preview/manifest时按钮禁用；学生、月份或汇率变化继续清除旧preview，备注不清除。
- 页面只通过`js/api/income-api.js`调用公开preview和atomic wrapper；没有页面`.rpc()`或表写。
- 写payload仍只有student ID、billing month、exchange rate、generation manifest及用户备注，不含金额、空调费或candidate明细。
- 二次确认继续显示candidate数、课次数、小时、基础费、空调费、课程总额、carryover、汇率及CNY通知金额。
- Cash提交路径未开放，DB gate继续blocked。

`node --check`覆盖utility、income page、income API及app；validation preview、atomic generate和planned aircon三组UI测试全部通过。

## 零漂移证明

| 对象 | 行数 | 全行MD5 |
|---|---:|---|
| lesson | 659 | `9ce7c36283cfa51f8b2a334801f646dd` |
| settlement | 17 | `1d7328654f6488952dba20640072c3e2` |
| bill | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| relation | 121 | `285172fedeb923c67ea9a179480d8692` |
| wage detail / lock | 556 / 95 | `6204dc666b3b8e0f64fac901ecf0686a` / `7bbe108d3ac73d4f21530793bf141bc6` |
| School account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |

`school_tuition_atomic_writer_context`残留0。Cash DB未连接。

## 修改范围与停止点

修改前端消费文件、三组UI测试、current-status、实施报告及五份R2-F-F SQL工件；既有API wrapper无需修改。未修改`js/legacy-core.js`，未执行真实generate，未执行Git add/commit/push。

建议commit message：

```text
feat: enable atomic tuition generation
```

当前停止在R2-F-F commit前审查点。
