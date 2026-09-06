# 学费候选与总课次数的 lesson_count 语义修复 —— 设计（2026-09-06，第二稿）

> 第一稿（commit `2191430`）经交叉审查**不通过**，基础路线可行、六处需修订。
> 本稿为修订版。审查报告：
> `~/aozora-security-20260827/lesson-count-design-review-20260906-12:05-report.md`
>
> **所有行号以单个 `pg_get_functiondef(oid)` 从 1 起算**（第一稿用错了另一份导出的偏移）。

## 1. 问题

`lesson_count`（回数）是**排序用的组内序号**，却在三处被当作数量：

| # | 位置 | 现状 | 后果 |
|---|---|---|---|
| 1 | `school_list_student_tuition_candidates` L172-173 | 要求 `IS NOT NULL AND > 0` | 缺该字段的课时**被排除出账单**，无报错 |
| 2 | builder `school_build_student_tuition_generation_snapshot` **L150** | `coalesce(sum(detail.lesson_count),0)` | 把序号求和当次数 |
| 3 | validator `school_validate_tuition_bill_lessons_for_bill` **L30 / L119** | `sum(rel.lesson_count_snapshot)` 且与快照 total 强制相等 | 使 #2 无法单独修改 |

前端 `js/pages/income-page.js:1958` 并排显示
`${candidate_count} 条 / ${total_lesson_count} 次`，两数本应相等。

**佐证**：`school_get_atomic_tuition_void_preflight` L1220 对同名展示值用的是
`count(*)::integer`——本次修复是**向系统内既有正确实现对齐**，不是引入新语义。

## 2. 回数的业务语义（业务负责人确认）

- **仅用于排序**，不参与任何计算
- 作用域：**同一学生、同一周、同一科目**。一周两次的课得第 1、2 回，
  下一周重新开始；一周一次的永远是第 1 回
- 曾设想按月累计（1～8 回），因难以计算而放弃

`subject_id` 是正确的分组维度，**不应额外按 `teacher_id` 分组**
（否则同科换老师会重新编号）。若业务另有「科目下独立课程/班次」的定义，
那是另一件事，不能凭当前样本推定。

## 3. 影响面（2026-09-06 生产实测）

放宽判定后新进候选 **5 条**，均满足其余全部必填条件、从未被任何账单关联：

| billing_month | 条数 | 合计 JPY |
|---|---:|---:|
| 2026-04 | 2 | 36,000 |
| 2026-06 | 2 | 47,375 |
| 2026-08 | 1 | 18,000 |

**这四个「学生 × 月份」组合均无账单**，其学费已由其他方式收讫，
不构成欠款（业务负责人确认；不可由「无账单」推断「未付款」）。

## 4. 改动范围

### 4.1 正常路径六个函数

| # | 函数 | 改动 | 位置 |
|---|---|---|---|
| 1 | `school_list_student_tuition_candidates` | 删两行必填判定 | L172-173 |
| 2 | `school_build_student_tuition_generation_snapshot` | 新增 `ranked_candidates` CTE；L126 换序号；L150 改 `count(*)` | 见 §5 |
| 3 | `school_validate_tuition_bill_lessons_for_bill` | 版本分支 + 版本契约校验 | L101 之后 |
| 4 | `..._atomic_base_core_v1` | bill/income 两处快照加 `lesson_count_semantics` | L258 / L347 |
| 5 | `..._next_revision_core` | 同上 | L73 / L128 |
| 6 | `..._next_revision_p0e_core` | 同上 | L89 / L144 |

**三个 writer 的明细 INSERT 不改**：均读 `v_snapshot.candidates` 的
`v_line->>'lesson_count'`（base_core_v1 L307、next_revision_core L99、
p0e_core L115），序号在 builder 补好即自动正确。

⚠️ **不要给 `relation.source_snapshot` 单独加版本键**——validator L90-93
要求它去掉两个 manifest 键后与 `candidate_line` **整体相等**，加键即破坏该检查。

### 4.2 baseline 函数：封存，不改

`school_p0c_baseline_generate_atomic_core`（L260/L349）、
`school_p0c_baseline_validate_tuition_bill_lessons_for_bill`（L24/L116）、
`school_p0c_baseline_list_student_tuition_candidates` 含同样的旧逻辑。

三者 ACL 均为 `postgres=X/postgres`，生产 public 正文与 `pg_depend`
均未发现调用者。**本次不改、不动其 ACL**，但设计上必须写明：

> **baseline 系列为封存基线，不用于真实生成，也不用于新版本验收。**
> 不可宣称「全库只有一个旧 sum validator」——外部 postgres 运维代码若调用它，
> 行为仍是 v1。

### 4.3 不属于本次范围

`school_import_historical_part_time_work_batch` L93 的
`sum(expected_lesson_count)` 是外部导入的预期记录数，与本序号无关，**不改**。

### 4.4 builder 的全部直接调用方：9 个（2026-09-06 13:46 复核修正）

第二稿只列了两个 preview 连带点，**那是错的**。生产 public 正文扫描得到的
builder 直接调用方共 9 个，全部会拿到新的 `total_lesson_count` 与重编序号：

| 类别 | 函数 | 处置 |
|---|---|---|
| preview | `school_get_student_tuition_validation_preview_details` | 行为自动变化，不改代码 |
| preview | `school_get_atomic_tuition_reissue_preview_p0e` | 同上 |
| preview（封存） | `school_p0c_baseline_tuition_preview_details` | L234 调 builder、L246 透传总值，**本次不改** |
| writer | `..._atomic_base_core_v1` / `..._next_revision_core` / `..._next_revision_p0e_core` | 本次修改对象 |
| reissue 中间层 | `school_reissue_atomic_student_tuition_generation_local` | 先构造 snapshot 比对预期再委托 atomic core，**不是漏标 writer** |
| reissue 中间层 | `school_p0e_base_reissue_local` | 同上 |
| 封存 writer | `school_p0c_baseline_generate_atomic_core` | L260/L349 仍写无版本键快照，本次不改 |

⚠️ 「封存」不等于「完全无依赖」。若绕过封存约定去调
`school_p0c_baseline_generate_atomic_core`，它会用**新 builder 的输出**配**旧标记方式**，
产出一张 `total = count` 却不带版本键的账单——兼容 validator 会按 v1 用序号和去校验它。
本次依既定范围不改它，但这是必须记下的剩余风险。

⚠️ public 正文扫描**不覆盖**外部运维脚本与动态拼接的调用字符串。

## 5. builder 改法

`candidate_rows` 当前只投影 `teacher_id` / `subject_id` / `updated_at` /
空调与场地字段，**没有 `start_time`**（第一稿凭空使用了它）。

```sql
-- ① candidate_rows 增加投影
lesson.start_time AS source_start_time

-- ② candidate_rows 之后、canonical_lines 之前，新增
ranked_candidates AS (
  SELECT detail.*,
    row_number() OVER (
      PARTITION BY detail.student_id, detail.subject_id,
                   detail.billing_week_start_date
      ORDER BY detail.lesson_date,
               nullif(btrim(detail.source_start_time), '')::time NULLS LAST,
               detail.planned_lesson_id
    )::integer AS bill_lesson_ordinal
  FROM candidate_rows detail
)

-- ③ canonical_lines 改为 FROM ranked_candidates detail
--    L126 的 JSON 值换成：
'lesson_count', detail.bill_lesson_ordinal

-- ④ aggregated L150
coalesce(sum(detail.lesson_count),0)::integer  →  count(*)::integer
```

**保留原始 `detail.lesson_count`，另起 `bill_lesson_ordinal`**，
避免 `SELECT *` 产生同名列。`row_number()` 返回 bigint，转 integer 与明细列契约一致。

### 5.1 start_time 的空值处理（必须写死）

生产 515 条 planned 中 **373 条 `start_time` 为 NULL、2 条为空串**，
其余符合 `HH:MM` 或 `HH:MM:SS`；该列为 `text` 且**无 CHECK**。
直接 `::time` 会在空串处报错。

规则：**空白（NULL 或空串）视为缺失并排在最后**（`NULLS LAST`），不改源事实。
UUID 仅作为同刻或缺刻时的稳定次序，**不代表真实时间先后**。

未来若出现非法的非空文本，**不得静默过滤丢课**——应显式失败或另行定义，
本设计不引入新的隐式排除条件。

### 5.2 返回数组顺序不改（前端契约）

builder L157-163 的 `string_agg` / `jsonb_agg` 均按
**周 → 日期 → UUID** 排序，而前端
`js/utils/tuition-validation-preview.js:71-77` 强制校验同一次序，违反即拒绝显示。

**本次只计算编号，不动数组排序。** 窗口 `ORDER BY` 不会替代聚合 `ORDER BY`。

副作用：同日不同时刻且 UUID 反序时，数组里可能出现「回数 2 排在回数 1 之前」。
若业务要求展示也按时刻排列，需另行纳入数组排序与前端校验契约，
届时六函数范围不再够用。

新增 CTE 与调整 SELECT 列的物理顺序**不改变 hash**：hash 输入是显式构造的
`canonical_line::text`，不是 `to_jsonb(detail)`；`source_start_time` 等辅助列不会进入 JSON。

## 6. validator 改法

`v_lesson_count` 除声明外只在 L99（聚合 `INTO`）与 L119（比较）出现，
`v_count` 在同一 `INTO` 已赋值。

**插入点：L101 分号之后、L103 candidate_manifest SELECT 之前**
（不能插在 `INTO` 与 `FROM/WHERE` 之间）。且必须留在
`atomic_generation_v1` 分支内，不进入 historical_registration 的 ELSE。

### 6.1 版本识别必须严格（第一稿的三行不够）

`coalesce(key,'v1')='v2'` 不是严格识别：缺键与 JSON null 都回落到 v1，
拼写错误、数字、对象等未知值会**静默走旧算法**。

契约：

```
缺键                        → v1（历史账单）
显式值 'v1' / 'v2'          → 按值
其他任何情况
  （未知字符串 / JSON null /
    非字符串类型）          → 拒绝，抛错
```

### 6.2 bill/income 版本一致性必须校验

**第一稿「漏一处就会当场失败」是错的**：

- 拟议逻辑只读 bill 的版本；**income 漏标不会被发现**
  （bill-income validator 只检查 1:1 关联，不比较版本）
- **bill 漏标而该组恰好 `sum = count` 时，v1 算法也能通过**

因此必须显式校验 **bill 与 income 两份 `lesson_count_semantics` 相等**，
不一致即抛错。该检查可并入现有 validator，无需新函数。

> 「10 处」是概念计数，**不是禁止补充必要检查的上限**。

## 7. 历史账单为何不受影响（已验证）

validator 的重算全部基于**冻结数据**，无一处调用当前 builder / 候选 reader：

| 位置 | 数据来源 |
|---|---|
| L30-34 | `bill_lessons` 冻结明细的序号和 / 小时 / 费用 |
| L81-85 | 冻结 `candidate_line` 去掉行 hash 后的整体 SHA256 |
| L103-108 | bill 自己的冻结 `candidate_lines`，有序拼接行 hash |
| revision validator | atomic 比较存储的 manifest；historical_registration 重算整行；P0-E 依据冻结数据重算 |

`complete_row_hash` 同样不从当前源课时重算。

**前提**：旧快照与明细不动、v1 分支持续可用、版本判定正确。

⚠️ **不得给 historical_registration 的旧快照补 v1 键**——它的 manifest 是
整行 `to_jsonb` 的 hash，加键会改变结果。

另注：旧账单能过 validator **不等于**能 Void/Reissue，收款与下游事实仍有独立阻挡。

## 8. preview manifest 的失效范围（修正）

`candidate_line_hash` 的输入是 22 个显式键，**确实包含 `lesson_count`**
（builder L117-140），整体经 L144 SHA256；普通 generation hash 还直接含
`v_lesson_count`（L200）。

但**「所有旧 preview 必失效」不成立**：若某组只有一条、源序号已为 1、
其他输入未变，则行 hash、总次数、generation hash 可以全部不变。
顶层 `lesson_count_semantics` 不在任何 hash 输入中。

P0-E 的最终 manifest 由专用 helper 计算，取的是 candidate manifest、
来源 revision、结转与调整等，**不直接含 `total_lesson_count`**，
不能把普通 builder 的 hash 输入套用到它。

**结论**：部署后应作为**流程要求**重新预览（而非「DB 保证旧凭证必被拒」）。
若要后者，需把版本绑定进 manifest 协议并覆盖 P0-E，那超出「不改 hash 契约」
的前提，需另行设计。

## 9. 部署与回滚（第一稿此节整体作废）

### 9.1 部署：六个函数同一事务

分批会产生真实的错误中间态：

| 分批方式 | 后果 |
|---|---|
| 候选先放宽 | NULL 序号进入明细 `NOT NULL` 路径**失败** |
| builder 先改、writer 未标 | count 4 / sum 6 按 v1 校验**失败**；恰好相等时**静默存下漏标账单** |
| writer 先标 v2、builder 仍求和 | 旧 validator 可能**放行语义错误的账单** |

兼容 validator 可以在**专门设计的两阶段发布**中先上线，但这不等于任意拆批安全。

同事务只消除「已提交目录的中间态」，**不足以隔离在途调用**——
部署还需排空生成调用，或经核验的同锁协调 / 维护窗口。

### 9.2 回滚：有 v2 数据后不能简单还原

**第一稿称「回滚不产生数据不一致」是错的。**

v2 账单的明细序号被重编为周内 1/2，例如目标四行为 **1、2、1、2**：
**条数 4、序号和 6**。原样恢复旧 sum validator 后，它会要求 `4 = 6`。

失败**不限于 Reissue**——普通 generate 的幂等返回校验、Void preflight
等任何触发 validator 的路径都会失败。

回退矩阵：

| 状态 | 可行动作 |
|---|---|
| **尚无 v2 持久化账单**，且已排空在途调用 | 可完整还原六个函数的旧定义 |
| **已有 v2 账单** | **保留 v1/v2 兼容 validator**，仅停用或回退有问题的新生成路径；writer 的标记必须与所用算法对应 |

个别 v2 账单恰好 `sum = count`，**不能**据此证明整体回退安全。
**不接受用「人工处理」替代兼容契约。**

## 10. 已收款课时的排除机制（修正）

**第一稿称「系统无此表达，只能靠操作纪律」不准确。** 机制存在：

- 表 `school_student_tuition_historical_lesson_exclusions`，当前 **106 行**
- 候选 reader L123-142 **优先返回** `historical_paid_exclusion`

但**不能直接追加那 4 条**：

- INSERT guard 无条件抛 `TUITION_HISTORICAL_LESSON_EXCLUSION_INSERT_RETIRED`
- UPDATE / DELETE / TRUNCATE 受 immutable guard 阻断
- CHECK 将 report / manifest / approval_source / profile 绑定旧批准清单
- `service_role` 对该表仅有 SELECT

两条可评估方向（**均为选项，未获授权**）：

1. 沿用既有排除语义，增加**经批准的**证据登记路径（范围窄，不动冻结 lesson）
2. 在 preview/generation 边界增加**经批准的**历史月份限制
   （影响所有历史月份的合法首开/重开，须明确例外规则）

**禁止**：冒用旧批准清单常量、解除 retired guard、
或把新排除规则夹带进本次六函数修复。

若业务选择仅靠操作纪律，应表述为**主动接受的剩余风险**，
而不是「系统没有相应概念」。

## 11. 验证清单

### 11.1 历史兼容性（成功用例，非「该失败的」）

样本必须是：**atomic + canonical_charge + 无版本键 + `total = sum ≠ count`**。
不能选 `total = count` 的样本（无法区分新旧算法），
也不能用无 revision / billing_role 的行。

已取得改前基线（bill `013a7766-…`）：active、`atomic_generation_v1`、
`canonical_charge`、缺版本键、frozen total = 35、冻结序号和 = 35、明细条数 = 30，
只读调用当前 validator **成功**。

⚠️ 这只证明**改前旧函数通过**。部署后须对同一对象重新核对：
条件不变、完整 validator 成功、冻结内容未变——届时 `35 ≠ 30` 才能区分分支。

建议只读覆盖全部 **8 张 atomic 差异账单**（active + voided）
与 **7 张 historical_registration**，**不改任何真实历史行来造证据**。

### 11.2 必须补充的场景

1. 三个 writer **分别**验证：bill/income 双份 v2、`total = count`、
   JSON 与 normalized 明细一致。不能只测首次生成
2. 新样本用 **1/2 + 1/2（count 4 / sum 6）**；全为 1 的样本无法区分新旧算法
3. 跨周、跨科目、同科换老师、同日不同时刻、同刻 UUID tie、
   NULL / 空串时刻、同周部分课时被 claim
4. total 错值、单行序号 / 行 hash / manifest 不一致**应失败**；
   未知版本、JSON null、非字符串、bill/income 版本不同**应按契约失败**
5. 金额必填缺失、voided / 非 planned / 非 billable **仍被排除**
6. 删除 `> 0` 条件后，源序号为 0 或负数**不应仅因该字段被排除**，
   账单内重编号为正数——**须明确写出预期值**，不写「符合预期」
7. active canonical claim 的实际原因是 `already_canonical_charged`；
   `incident_history` / `legacy_history` 另有分支，
   `existing_bill_lesson_history` 是兜底。voided 历史关联可释放，不等于 active claim
8. 旧 preview 输入**已变**时应拒绝；输入**完全未变**时按 §8 所选策略验收
9. 费用 / 汇率 / 结转与候选集合不变时，候选数与金额不变；
   `total_lesson_count` **仅在旧 sum ≠ count 时变**，不是人人必变
10. 若改数组顺序则补前端验证；不改则明确「编号 ≠ 全局 line_no」
11. **已持久化 v2 后的回退**与**整个测试事务 ROLLBACK** 是两个不同场景，分别覆盖

涉及写入的测试须在**独立获授权阶段**安排。

## 12. 本次不做

- 不改任何历史账单或其冻结快照
- 不回填历史课时的 `lesson_count`（有 actual 关联者永久冻结）
- 不补建 2026-08 之前月份的账单
- 不改 baseline 系列函数及其 ACL
- 不改 `student_tuition_generate` gate（独立事项）
- 不动数组排序与前端校验契约
- 不追加历史排除记录、不解除 retired guard
