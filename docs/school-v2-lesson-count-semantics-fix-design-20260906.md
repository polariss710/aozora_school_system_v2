# 学费候选与总课次数的 lesson_count 语义修复 —— 设计（2026-09-06）

## 1. 问题

`lesson_count`（回数）是**排序用的组内序号**，却在三处被当作数量使用，
导致两类缺陷：

| # | 位置 | 现状 | 后果 |
|---|---|---|---|
| 1 | 候选判定 `school_list_student_tuition_candidates` L172-173 | 要求 `IS NOT NULL AND > 0` | 缺该字段的课时**被排除出账单**，无任何报错 |
| 2 | builder `school_build_student_tuition_generation_snapshot` L150 | `coalesce(sum(detail.lesson_count),0)` → `total_lesson_count` | 把序号求和当次数 |
| 3 | validator `school_validate_tuition_bill_lessons_for_bill` L30/L119 | `sum(rel.lesson_count_snapshot)` 且与快照 total **强制相等** | 使 #2 无法单独修改 |

前端 `js/pages/income-page.js:1958` 并排显示
`${candidate_count} 条 / ${total_lesson_count} 次`——两个数本该相等。
目标学生 `be7effdf-…` 现在显示「3 条 / 4 次」，即缺陷的直接体现。

另见 `js/utils/tuition-validation-preview.js:87`、`js/pages/income-page.js:2027`。
三处**均为内部管理页面，不是对外账单**。

## 2. 回数的业务语义（业务负责人 2026-09-06 确认）

- **只用于排序**，不参与任何计算
- 作用域是**同一周内的同一门课**：一周两次的课才有第 1、2 回，
  下一周重新从第 1 回开始
- 一周只有一次的课，**每周都是第 1 回**
- 曾设想按月累计（第 1～8 回），因难以计算而放弃

因此 `sum(lesson_count)` 无论如何都不等于课次数：
一周两次的课贡献 1+2=3，而实际是 2 次。

## 3. 成因

`lesson_count` 在若干历史创建路径下未被填写。已确认的路径至少三种：
批量排课生成器、Excel 导入、单条创建。

批量生成器 `school_generate_planned_lessons_batch_r1d_f1_legacy_core` L425-432
仍存在 NULL 分支（`occurrence_count = 1` 且 pattern 未填回数时写 NULL），
但当前 UI 的「每周次数 / 起始回数」均有默认值，该分支在现行入口下走不到。
**历史数据缺该字段属于功能逐步演进的正常结果，不作为本次必修项。**

## 4. 影响面（2026-09-06 生产实测）

放宽判定后会新进候选的课时共 **5 条**，均满足其余全部必填条件、
且**从未被任何账单关联**：

| billing_month | 条数 | 合计 JPY |
|---|---:|---:|
| 2026-04 | 2 | 36,000 |
| 2026-06 | 2 | 47,375 |
| 2026-08 | 1 | 18,000 |
| 合计 | 5 | 101,375 |

历史账单中「序号和 ≠ 条数」的共 **8 张**，其中 active **5 张**
——这 5 张是将来真会走 Reissue / next revision 的部分，
也是版本兼容机制要覆盖的范围。

## 5. 设计

### 5.1 候选判定：去掉必填

```sql
-- school_list_student_tuition_candidates，删除这两行
AND evidence.lesson_count IS NOT NULL
AND evidence.lesson_count > 0
```

**不要改写成 `coalesce(lesson_count, 1)`** ——那会让 `sum` 多算 1，
在 5.2 落地前反而把 `total_lesson_count` 弄错。

其余必填条件全部保留。金额相关的三项
（`duration_hours > 0`、`unit_price` 非空且 > 0、`lesson_fee` 非空且 > 0）
仍在，因此**不会放过任何算不出钱的课时**。

### 5.2 builder：改为条数，并标记语义版本

```sql
-- L150
coalesce(sum(detail.lesson_count),0)::integer  →  count(*)::integer
```

同时在写入 `source_snapshot` 时加入：

```json
"lesson_count_semantics": "v2"
```

第八轮已确认：`school_student_tuition_bills.source_snapshot` 顶层
**无键集合 CHECK**，且普通 atomic 的 hash 只取指定字段与候选行、
**不整体纳入 source_snapshot**，故新增该键不影响任何既有 hash 计算方式。

### 5.3 validator：按版本分支（比原设想简单得多）

读生产定义后发现：validator **已经同时算了条数和序号和**，只是分别赋给两个变量。

```sql
SELECT count(*)::integer, coalesce(sum(rel.lesson_count_snapshot),0)::integer, ...
  INTO v_count, v_lesson_count, ...

-- 判定段
OR (source_snapshot->>'candidate_count')::integer   IS DISTINCT FROM v_count
OR (source_snapshot->>'total_lesson_count')::integer IS DISTINCT FROM v_lesson_count
```

因此**不需要改聚合语句，也不需要改判定语句**，只在两者之间插入三行：

```sql
IF coalesce(v_bill.source_snapshot->>'lesson_count_semantics','v1') = 'v2' THEN
  v_lesson_count := v_count;
END IF;
```

`v_lesson_count` 在该函数内仅有「聚合赋值」与「判定比较」两处使用，
插入点安全。**这比改写聚合表达式风险低一个量级。**

#### 佐证：系统内已有正确实现

`school_get_atomic_tuition_void_preflight` L1220 计算同名展示值时用的是：

```sql
select count(*)::integer into v_lesson_count
```

即 **Void 预检页面显示的「课次数」一直是条数**，只有 builder 与 validator
在用序号和。本次修复不是引入新语义，而是把这两处对齐到系统内已存在的正确做法。

### 5.4 writer：三个，不是一个

生产中有**三个** writer 各自构造 `source_snapshot` 并插入 `bill_lessons`：

| 函数 | 角色 |
|---|---|
| `school_generate_student_tuition_bill_atomic_base_core_v1` | 首次生成 |
| `school_generate_student_tuition_next_revision_core` | 下一版 revision |
| `school_generate_student_tuition_next_revision_p0e_core` | P0-E forward adjustment 版 |

**三个都要改，各两处**：`source_snapshot` 加 `lesson_count_semantics`、
`bill_lessons` 补 `lesson_count_snapshot`。漏掉任何一个，
该路径生成的账单就会带着 v1 语义却是 v2 的数据，validator 当场失配。

### 5.5 改动点总表（6 个函数 / 8 处）

| # | 函数 | 改动 |
|---|---|---|
| 1 | `school_list_student_tuition_candidates` | 删两行必填判定 |
| 2 | `school_build_student_tuition_generation_snapshot` | `sum` → `count(*)` |
| 3 | `school_validate_tuition_bill_lessons_for_bill` | 插三行版本分支 |
| 4 | `..._atomic_base_core_v1` | snapshot 加键 + 明细补序号 |
| 5 | `..._next_revision_core` | 同上 |
| 6 | `..._next_revision_p0e_core` | 同上 |

### 5.6 lesson_count_snapshot 的补值规则（B 方案，已确认）

```sql
row_number() over (
  partition by student_id, subject_id, billing_week_start_date
  order by lesson_date, start_time, planned_lesson_id
)
```

**周内按科目重置**，与 §2 的业务规则一致：一周两次的课得第 1、2 回，
下一周重新开始，一周一次的永远是第 1 回。

采用 **B（全部重算）** 而非仅补 NULL：v2 语义下该字段不参与计算，
唯一用途是账单明细内的排序；仅补 NULL 会在同周同科目内产生重复序号
（例：某学生物理 09-03 补 1、09-04 源值也是 1），排序依然是乱的。

**历史账单一行都不用改**：快照里没有该键即走旧算法，与其冻结的
`total_lesson_count` 依然相等，那 8 张失配账单将来走 Reissue 也不会失败。

这条是本设计能够避免触碰冻结快照的关键——参照 P0-E 的先例
（宁可 forward adjustment 也不回写历史事实）。

### 5.4 writer：补 `lesson_count_snapshot`

`school_student_tuition_bill_lessons.lesson_count_snapshot` 为
**NOT NULL 且要求 > 0**，源课时为 NULL 时直接插入会失败，
故 5.1 无法单独实施。

按 §2 的业务规则生成：

```sql
row_number() over (
  partition by student_id, subject_id, billing_week_start_date
  order by lesson_date, start_time, planned_lesson_id
)
```

**待定选项**（需业务负责人确认其一）：

- **A. 仅对源值为 NULL 的补** —— 改动最小，但同周同科目内可能出现重复序号
  （例：骆同学物理 09/03 补 1、09/04 源值也是 1），账单明细排序仍然乱
- **B. 全部按规则重算** —— 明细内排序保证正确，但明细值可能与源课时不同

倾向 **B**：v2 语义下该字段不参与计算，其唯一用途就是账单明细内的排序；
源课时的 `lesson_count` 服务于课时列表排序，两者用途本就不同。

## 6. 已知缺口（必须记录）

**修复后，2026-08 之前那 4 条历史课时会成为合法候选。**

它们的费用**已通过其他方式收讫**（业务负责人确认：
`cff85c52-…` 的 2026-04 与 5 月合并收取；另两名学生所属月份早于学费账单功能上线）。
系统中不存在「此课时已用其他方式结清」的表达方式，
现在把它们挡在账单外的，恰恰是本次要修的这个缺陷。

`is_billable = false` 这条常规出路**不可行**：该字段同属 P0-B1 保护的财务字段，
而这 4 条均已有 actual 关联、永久冻结。

**因此只能依靠操作纪律：修复后不要为 2026-08 之前的月份生成学费账单。**
实际风险低（无人会回头为历史月份开账单），但这是本次修复引入的已知缺口，
不应被遗忘。

## 7. 验证清单

### 7.1 该成功的

1. 目标学生 `be7effdf-…` / 2026-08 / 汇率 0.042：
   `candidate_count` 3 → **4**，`total_fee_jpy` 54000 → **72000**，
   `billing_amount_cny` 2268.00 → **3024.00**
2. `total_lesson_count` = **4**（等于 `candidate_count`，不再是序号和）
3. 生成账单成功，`bill_lessons` 4 条，`lesson_count_snapshot` 均非空且 > 0
4. 新账单 `source_snapshot` 含 `"lesson_count_semantics": "v2"`
5. validator 对该新账单通过

### 7.2 该失败的（更重要，见 lessons E4）

1. **历史账单仍能通过 validator** —— 取 §4 那 8 张失配账单中的任意一张，
   验证其仍走 `v1` 分支且校验通过。**这是版本兼容机制的核心证据。**
2. 缺 `unit_price` / `lesson_fee` / `duration_hours` 的课时**仍被排除**
   —— 证明放宽只放过了序号缺失，没有放过算不出钱的数据
3. `voided_at` 非空、`status <> 'planned'`、`is_billable = false`
   的课时**仍被排除**
4. `lesson_count = 0` 或负数的课时（若存在）行为符合预期
5. 已被其他账单 claim 的课时**仍走 `existing_bill_lesson_history` 分支**

### 7.3 回归

- 未受影响的学生（`lesson_count` 全部正常）的 snapshot
  `candidate_count` / `total_fee_jpy` / `billing_amount_cny` **逐字未变**
- 但注意 `total_lesson_count` 会变（序号和 → 条数），
  这是预期内的修正，需逐个学生记录改动前后值

## 8. 本次不做

- 不修改任何历史账单或其冻结快照
- 不回填历史课时的 `lesson_count`（有 actual 关联者永久冻结，改不了）
- 不补建 2026-08 之前月份的账单
- 不修批量生成器的 NULL 分支（现行 UI 走不到，另行排期）
- 不动 `student_tuition_generate` gate（该 gate 的解冻是独立事项）

## 9. 回滚

四处改动均为函数体替换，回滚脚本按生产当前定义逐个还原，
执行前以 `md5(pg_get_functiondef(oid))`（单参数 canonical）做基线断言。

`source_snapshot` 中已写入 `lesson_count_semantics` 的账单在回滚后仍带该键，
但 v1 validator 会忽略它——**回滚不产生数据不一致**。
唯一残留是那些在 v2 期间生成的账单，其 `total_lesson_count` 为条数而非序号和；
若回滚后需要对它们做 Reissue，validator 会失配，需要人工处理。
**这是回滚的已知限制，回滚前应确认 v2 期间是否已生成账单。**
