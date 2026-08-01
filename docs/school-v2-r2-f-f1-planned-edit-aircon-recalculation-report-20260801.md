# School V2 R2-F-F1 Planned编辑空调费重算与v2显示报告

日期：2026-08-01

## 结论

R2-F-F1已完成数据库与前端验收，停在Git提交前审查点。当前gate为：

- `student_tuition_preview = enabled`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

本阶段未生成真实bill或income，未连接Cash DB，未修改真实lesson、settlement、工资、账户流水或Cash linkage。业务负责人确认新增的孙陈锋EJU日语课程被完整保留；generate必须等8月课程补录完成后另行授权恢复。

## 三条真实课程

| ID | 日期/时间 | 老师/科目 | 来源 | policy | base | rate/hours | aircon | total |
|---|---|---|---|---|---:|---:|---:|---:|
| `6c70c4c1-1895-453d-b9b0-591e9f004f86` | 2026-08-08 | 田宇辰 / EJU物理 | 批量生成 | `planned_weekend_aircon_v1` | 17,000 | 330 / 2 | 660 | 17,660 |
| `89da310d-4f17-4a40-8315-659838aec59c` | 2026-08-09 14:00–16:00 | 王黎曦 / EJU化学 | 批量生成 | `planned_weekend_venue_whole_hour_aircon_v2` | 17,000 | 330 / 2 | 660 | 17,660 |
| `397446aa-b195-43ff-9506-a560e7d12d93` | 2026-08-09 16:30–18:30 | 赵天歌 / EJU日语 | 单条新建 | `planned_weekend_venue_whole_hour_aircon_v2` | 17,000 | 330 / 2 | 660 | 17,660 |

三条均为`onsite / Regus办公室`，学生、业务归属、billing month `2026-08`和收费自然周`2026-08-03`一致；均无normalized bill relation、bill JSON relation或legacy收费证据。合计空调计费6小时、JPY1,980。

三条记录的`lesson_venue_id`仍为NULL，结构化venue master由calculator使用精确`lesson_venue='Regus办公室'`解析；没有模糊字符串匹配。三条真实记录在本阶段全程只读。

## 根因与调用链

编辑链为：

`lesson-edit-dialog.js` → `lesson-page.js`保存回调 → `lesson-api.js.updateLessonRecordGuarded` → `school_update_lesson_record_guarded_with_venue(..., integer)` → venue wrapper/core guarded update → `trg_school_lesson_r2_e_planned_aircon` → 8参数venue-aware calculator → 列表重新查询。

调查确认：

- 页面把330作为`p_aircon_rate_jpy_per_hour`提交；date、mode和venue字段名与RPC一致。
- rate overload在同一RPC事务内完成guarded update及rate snapshot更新，最终返回更新后的完整行。
- trigger使用8参数calculator；旧5参数calculator继续永久抛出`R2_F_F_AIRCON_VENUE_CONTEXT_REQUIRED`。
- 两条8月9日记录保存后的DB派生值本来已经正确。
- 显示缺口来自课时卡片和详情页只承认v1 policy，正确v2 bundle被降级成“仅基础费”。
- DB另有独立潜在缺口：旧planned的policy和rate同时为NULL时，trigger直接`RETURN NEW`，无rate编辑路径可能跳过v2重算。

## 实施

数据库：

- 原R2-F-F policy cutover源文件删除legacy NULL bundle早退分支，保证未来全新部署正确。
- 独立纠正SQL只`CREATE OR REPLACE school_enforce_r2_e_planned_aircon()`。
- trigger对所有未进入正式bill的planned update执行统一8参数calculator；NULL rate按已保存事实归一为0，不因旧bundle为NULL/0跳过。
- billed、locked及收费周guard保持不变。

前端：

- 新增纯展示工具`planned-aircon-display.js`。
- 不再以唯一policy字符串决定是否展示，而是检查DB返回的完整权威bundle。
- v1、v2、完整零费用bundle及未来未知policy的完整正费用bundle均展示；缺字段bundle仍降级显示基础费。
- 卡片与详情显示base、saved rate、DB billable hours、aircon fee、course total、policy和“周末固定办公室计费”。
- JS只格式化DB字段，不计算或推导费用。
- 更新lesson和lesson-detail模块cache key，避免旧浏览器模块继续隐藏v2。

## SQL执行

1. `school_tuition_r2_f_f1_generate_gate_block.sql`
   - 同字节rehearsal：ROLLBACK。
   - 正式执行：COMMIT；仅将generate gate改为blocked，preview保持enabled、Cash保持blocked。
2. `school_tuition_r2_f_f1_planned_edit_aircon_recalculation_cutover.sql`
   - 同字节rehearsal：ROLLBACK。
   - 正式执行：COMMIT；只替换一个trigger函数，无业务DML。
3. trigger MD5：
   - 前：`e7820acbf80b3e5b1c02bc3ad9664762`
   - 后：`33d0a36904ef02f595c69caafefe4f92`

正式业务DML仅为generate gate配置更新；未对真实lesson执行writer RPC。只读调用了validation preview、candidate reader和对象定义查询。rollback fixture中调用guarded update、calculator及owner-only atomic core，全部位于测试事务并ROLLBACK。

## Fixture修正

首次失败fixture把`fee_calculation_version=NULL`与部分0字段混合，违反完整bundle check。现改为：

- legacy案例：8个权威空调bundle字段全部NULL；
- zero案例：完整有效v2 bundle，rate=0、billable hours=2、fee=0、total=base、reason=`AIRCON_RATE_ZERO`。

第二项脚本口径修正：正式planned writer按既有规则只接受至少2小时的整数时长，因此writer用2→3小时验证duration重算；2.5小时的`floor()`通过纯权威calculator验证，没有放宽业务规则。

第三项脚本口径修正：fixture的工作日/周末切换改在同一自然周内，避免人为制造已收费跨周错误。E1 legacy actual回归遇到已锁定月结时只验证resolver/evidence结构契约，不尝试绕过locked guard。

## 测试结果

- R2-F-F1 rollback：10/10 PASS，覆盖NULL bundle、完整v1/v2 zero bundle、date、mode、venue、rate、duration、manifest、atomic四对象和billed immutable；固定fixture残留0。
- R2-F-F aircon/atomic rollback：5/5 PASS；actual overage隔离、故障注入、幂等及四对象一致；ROLLBACK，残留0。
- R2-F-E rollback：PASS，ROLLBACK，残留0。
- R2-F-E1 rollback：makeup credit及结构化evidence矩阵PASS，ROLLBACK，残留0。
- `planned-aircon-ui-test.mjs`：PASS，含v1 zero、v2 zero、v2 positive、unknown positive及incomplete bundle。
- lesson operations、lesson generation closure、validation preview及atomic generate UI测试全部PASS；atomic UI为14/14。
- 全部相关JS `node --check`通过；页面模块无直接`.rpc()`或表写，未在JS计算费用。
- F1 postdeploy：PASS并ROLLBACK。

## 当前阶段性Preview

孙陈锋2026-08当前已录入数据：

- 23 candidates / 26课次 / 46小时
- base JPY391,000
- aircon JPY1,980
- course total JPY392,980
- previous carryover CNY0
- 0.042下CNY16,505.16

张倬闻保持30 candidates / 35课次 / 65小时 / JPY650,000 / aircon JPY0 / carryover CNY107.50 / CNY28,057.50。

孙陈锋结果是当前阶段性preview，不是最终8月账单断言。业务负责人补录完成后必须重新preview、人工复核并另行授权generate。

## 数据指纹与并行运营

最终指纹：bill 9、income 42、identity 7、relation 121、settlement 17、wage detail 556、wage lock 95、account transaction 185、Cash linkage 35，hash均与既有资金基线一致。

lesson最终为660条、hash `23c996ac9ce14153c590ce2a57f09be9`。测试期间业务负责人并行把李天伦课时`8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9`更新为`pending_makeup`，造成lesson全表hash从阶段开始时变化；该行不是Codex fixture、不是本阶段目标，也未由本阶段SQL/RPC修改。重新取该合法运营状态为阶段性基线后，全套rollback和postdeploy通过。

## 停止点

停止在R2-F-F1 Git commit前审查点。未执行`git add`、commit或push；generate继续blocked。
