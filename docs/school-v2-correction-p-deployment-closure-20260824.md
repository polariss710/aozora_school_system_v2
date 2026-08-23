# Correction-P 部署与业务更正 归档报告

- 日期：2026-08-24（补记 2026-08-22 / 08-23 的部署，当时未留文档）
- 撰写：Claude Code
- 生产事实来源：Codex 于 2026-08-23 的只读查询（本文件中所有生产 id、
  时间戳与状态均出自该次核查，Claude 无生产库写权限，未独立复核）

## 1. 为什么补这份文档

2026-08-22 与 08-23 有代码提交（`86a94f3`、`0fdedbf`）与生产部署，但
`docs/` 下没有任何对应报告，`docs/current-status.md` 零提及 correction-P。
这造成两个后果：

- 2026-08-24 的调查中，`supabase-update-20260822-correction-p.sql` 的文件头
  仍写着 `Phase B local draft only. NOT DEPLOYED.`，先后两次误导判断，一度
  得出「correction-P 尚未修复」以及「saga 前提已失效」的错误结论。
- 仓库中留下一份与生产不一致的 SQL（见第 5 节）。

## 2. 被更正的业务事实

2026-08-13 一笔 **202,991 JPY 教室租金**支出，在 Cash 端按
`immediate_account`（即时账户扣款）提交并已批准，真实生成了一笔 transaction
并扣减了银行账户余额。业务上它应走西武卡 `fixed_credit_card` 路线，由信用卡
账单周期后续统一结算，不应当场扣账户。

错误事实的固化记录见
`docs/school-v2-phase3c1-expense-cash-attempt-model-backfill-20260819.md:49-60`。
在 Phase 3C3-B 与 3D 中均被明确排除在部署范围之外
（`docs/school-v2-phase3c3b-fixed-attempt-cash-request-entry-20260819.md:35,39`）。

## 3. Saga 执行记录

跨库三阶段协调，Edge 为 `supabase/functions/correct-cash-expense-route/`。

| 阶段 | 时间（UTC） |
|---|---|
| Home prepare | 2026-08-22 18:49:26.926502 |
| School finalize | 2026-08-22 18:49:27.366050 |
| Home complete | 2026-08-23 02:26:12.268276 |

```
operation_id        5139b4ff-c218-4372-bb28-670fe0906056
home_correction_id  0695e249-b3eb-4daa-976b-2ebd0a863241
status              completed
```

Home 侧产生的结构化事实，各一条，通过同一 `correction_id` 关联：

```
原始 JPY expense transaction   01e910b8-bf54-486c-a13a-597ca9dbf684
credit_restore entry           5a061ade-9302-4a27-ad41-faeea06296e5
2026-09 fixed item             4e9977b9-9e0e-412f-99b5-d0a4a1b52e3c
replacement request            8f2a9aff-56b0-4733-ba27-ce270d37aa5e
projection                     f5e8c6b0-7dfb-4ba6-9a30-5be94fb72668
```

Home 侧函数均已部署，且 evidence fingerprint 使用
`trim_scale(p_amount)::text`，与 School 侧一致。

**幂等性**（Codex 核查结论）：以相同 operation 重跑，Edge 先读到 `completed`
直接返回 `CORRECTION_P_ALREADY_COMPLETED`，不进入 prepare；直接调 prepare 返回
既有 correction 的幂等结果，只更新 retry/version 元数据；换新 operation 但用
相同业务 identity，会在 `home_prepare` 返回
`HOME_CORRECTION_BUSINESS_OPERATION_CONFLICT`。因此不会二次冲正。

未能确认的一点：是否还发生过数据库无法识别的外部人工动作。

## 4. School 端的当前表现

该笔支出在 School 端**仍显示 `paid` + `immediate_account` + Cash 已确认**。

这是设计如此，不是缺陷：`school_expense_cash_corrections` 是 append-only 的
证据表，表注释明写 *"It never changes the canonical expense or original
immediate attempt."*（`supabase-update-20260822-correction-p.sql`）。更正只以
证据形式存在，不改写原始事实。

由此产生一个待业务方决定的问题，见第 6 节第 2 项。

## 5. 本次（2026-08-24）对仓库做的修正

`supabase-update-20260822-correction-p.sql` 有两处与生产不符，已修：

1. **文件头声称 `NOT DEPLOYED`** —— 实际已部署。改为记录真实部署状态，并
   注明部署状态一律不以 SQL 文件头为准。
2. **`school_correction_p_evidence_fingerprint_v1` 的 amount 未规范化** ——
   文件为 `p_amount::text`，生产已于 08-23 由
   `supabase-update-20260823-correction-p-evidence-fingerprint-canonicalization.sql`
   改为 `trim_scale(p_amount)::text`。**按原样重跑该文件会把生产覆盖回旧定义**，
   使 `202991` 与 `202991.00` 产生不同的 evidence fingerprint。已同步为
   `trim_scale`，两份文件的函数体去除空白后现已完全一致，重跑幂等。

已核对：该文件中其余两处 `'amount'`（source contract 预览返回、结果构造器）
均非哈希输入，不受规范化问题影响。全文件只有一个指纹函数。

## 6. 待确认项

1. **correction-P 是否应当检查 feature gate。**
   `supabase/functions/correct-cash-expense-route/index.ts` 中检索
   `gate` / `enabled` / `blocked` 零命中，即更正路径不做任何开关检查。
   而正常 fixed 路线存在两个开关：Cash 侧的 `is_school_fixed_route_enabled`
   （2026-08-19 时为 `false`，Codex 于 08-23 复查仍为 `false`），以及 School 侧
   `school_feature_gates` 的 `cash_fixed_credit_card_route_enabled`
   （见 `sql/current/school_expense_cash_attempt_v2_gate_enable_20260819.sql:10`）。
   问题：saga 在 Gate 关闭状态下生成 2026-09 fixed item 与 replacement request，
   是有意设计（更正属对既成事实的补记，不应受新业务开关约束），还是漏检？
   `is_school_fixed_route_enabled` 是 Cash 侧列，本仓库零引用，需 Codex 从
   Cash 库判断。

2. **School 端 UI 是否需要反映该更正。**
   当前更正只存在于证据表，页面上看不出这笔已改走 fixed 路线。
   `school_expense_cash_attempts` 的状态字典中 `corrected` 早在 Phase 3C3-B
   就已定义但至今无 writer
   （`sql/current/school_expense_cash_fixed_entry_phase3c3b_20260819.sql:207,263`）。
   若业务上需要在页面体现，需要一个 `attempt_status → corrected` 的原子 writer，
   属于新的业务模型扩展，需单独审批。

3. **两份 correction-P SQL 尚未归档至 `sql/current/`。**
   截至本文件撰写时仍只在仓库根目录。根目录的定位是「归档前暂存区」，
   长期滞留会与真正待执行的草稿混淆。

## 7. 与本轮其他工作的关系

`supabase-update-20260822-correction-p.sql` 的这类问题——仓库文件与生产不一致、
靠人记住执行顺序——与 2026-08-10 月封口 guard 的字符串补丁属于同一类失效模式，
已在
`docs/school-v2-settlement-lesson-week-close-guard-handoff-20260823.md` 第 8 节
一并记录，建议单独立项治理。
