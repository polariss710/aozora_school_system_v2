# School V2 clearance后月结gross overage重复计入修复

日期：2026-08-18
生产前端版本：`v10.5.52`（未修改页面、缓存链或版本）

## 1. Business-model expansion declaration

```text
New tables: none
New columns: none
New enum/status values: none
New date/month/attribution concepts: none
New identity concepts: none
New source concepts: none
New snapshot/version concepts: none
New writable facts: none
Changed existing-field semantics: none；原lesson frozen overage及clearance事实含义均不变
Changed field mutability: none
Changed writer or reader authority: school_get_student_duration_overage_aggregate(uuid,text)的unlocked live分支由原始gross frozen overage改为读取现有clearance/reversal净分配后的DB权威remaining minutes，并按既有source-lines金额规则汇总；locked分支不变
Changed locking rules: none；locked snapshot继续优先且不回写历史
New authoritative sources: none；复用school_get_lesson_clearance_overtime_remaining_minutes(uuid)
Legacy fallbacks or dual-read rules: none
Dual-write behavior: none
Historical reinterpretation: none；历史locked snapshot字节语义不变
Destructive schema changes: none

Approval reference: 当前任务第三节明确批准唯一目标函数、remaining helper权威、partial/reversal语义、无clearance兼容、locked snapshot/forward不回写和原frozen事实不变。
```

## 2. 修改合同

修改前unlocked aggregate：

```text
minutes = sum(raw frozen overage minutes)
jpy = sum(raw frozen overage fee JPY)
system difference = planned CNY + gross overage CNY + carryover - received equivalent
```

修改后仅unlocked live分支：

```text
remaining = school_get_lesson_clearance_overtime_remaining_minutes(actual_id)
remaining <= 0：source不进入aggregate
无active allocation或完整reversal：直接保留raw frozen fee
partial：round(raw fee × remaining / raw minutes, 2)，与既有source-lines一致
CNY：仍在汇总JPY后按学生preset exchange rate一次round(..., 2)
```

返回签名、字段、类型、`STABLE / SECURITY DEFINER / search_path`、ACL及`aggregation_basis`字符串不变。原actual frozen字段、clearance ledger、claim、wrapper、source manifest、页面均未修改。

## 3. 测试与rehearsal

- 一次性PostgreSQL 17、Unix socket only：无clearance、完整clearance、partial、多次partial、reversal、多source混合、locked snapshot、locked forward、active claim、返回合同共10项通过；全部位于最终`ROLLBACK`事务，一次性cluster销毁。
- exact rollback将函数MD5精确恢复为`d24b82f51053b3960ce0e4839613ddc7`。
- 生产Attempt 1在单一事务内依次执行新定义、目标/no-clearance/locked验证、exact rollback、再次确定性部署验证，最后显式`ROLLBACK`；独立连接确认旧MD5及全部业务基线恢复。
- 正式部署后函数MD5为`6ca9679d62304830e0161ae6da22a69a`。

## 4. 生产验收

袁振轩2026-08：

- base receivable difference：`CNY0`
- registered pending：`6小时 / JPY54,000`
- registered overage：`0`
- registered net：`待补6小时 / JPY54,000`
- `system difference：CNY373.50 → CNY0`
- projected final carryover：`CNY0`
- unresolved planned：`6`
- `can_save=false / can_lock=false / SETTLEMENT_MONTH_NOT_CLOSED`

回归：

- 无clearance样本保持`15分钟 / JPY2,500 / CNY107.50 / count1`。
- 历史locked snapshot保持`15分钟 / JPY2,125 / CNY92.44 / count1 / locked_snapshot`。
- clearance header/detail仍`1/1`，reversal `0`，两端余额仍`0/0`，未创建第二笔clearance。
- P002仍`1200/0/1200`。
- clearance writer与claim mutex函数MD5不变。

## 5. 零业务变化

部署前、rehearsal后、正式部署后，School 13组整表count/hash及Cash 3组count/hash完全一致：lesson、settlement、claim、bill、bill lesson、revision、income、Cash linkage、wage lock/detail、package、Storage、Gate及Cash DB均无业务变化。唯一持久数据库变化为目标只读aggregate定义及comment；ACL被原样重申。

writer调用为0；未调用clearance/reversal、settlement save/lock/unlock/relock、lesson、wage、bill或income writer。前端文件、版本及缓存链均未修改。

## 6. 文件

- `sql/current/school_duration_overage_clearance_aware_aggregate_20260818.sql`
- `sql/current/school_duration_overage_clearance_aware_aggregate_exact_rollback_20260818.sql`
- `sql/current/school_duration_overage_clearance_aware_aggregate_production_rehearsal_20260818.sql`
- `sql/current/school_duration_overage_clearance_aware_aggregate_postrehearsal_readonly_20260818.sql`
- `sql/current/school_duration_overage_clearance_aware_aggregate_postdeploy_readonly_20260818.sql`
- `sql/tests/school_duration_overage_clearance_aware_aggregate_local_20260818.sql`
- `scripts/school-duration-overage-clearance-aware-local-postgres-test-20260818.mjs`

受保护untracked文件未修改、移动、执行或纳入提交。
