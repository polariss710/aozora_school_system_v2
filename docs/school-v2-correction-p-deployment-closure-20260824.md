# Correction-P 部署与业务更正 归档报告

- 日期：2026-08-24（补记 2026-08-22 / 08-23 的部署，当时未留文档）
- 撰写：Claude Code
- 生产事实来源：Codex 于 2026-08-23 的只读查询；2026-08-24 收尾审计又从
  School/Cash 生产独立复核函数定义、指纹、Gate、专用 route policy 与 saga 状态。

## 1. 为什么补这份文档

2026-08-22 与 08-23 有代码提交（`86a94f3`、`0fdedbf`）与生产部署，但
`docs/` 下没有任何对应报告，`docs/current-status.md` 零提及 correction-P。
这造成两个后果：

- 2026-08-24 的调查中，当时仍位于根目录的
  `supabase-update-20260822-correction-p.sql` 文件头
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
immediate attempt."*（`sql/current/school_expense_cash_correction_p_20260822.sql`）。更正只以
证据形式存在，不改写原始事实。

由此产生一个待业务方决定的问题，见第 6 节第 2 项。

## 5. 本次（2026-08-24）对仓库做的修正

`sql/current/school_expense_cash_correction_p_20260822.sql` 曾有两处与生产不符，已修：

1. **文件头声称 `NOT DEPLOYED`** —— 实际已部署。改为记录真实部署状态，并
   注明部署状态一律不以 SQL 文件头为准。
2. **`school_correction_p_evidence_fingerprint_v1` 的 amount 未规范化** ——
   文件为 `p_amount::text`，生产已于 08-23 由
   `sql/current/school_expense_cash_correction_p_evidence_fingerprint_canonicalization_20260823.sql`
   改为 `trim_scale(p_amount)::text`。**按原样重跑该文件会把生产覆盖回旧定义**，
   使 `202991` 与 `202991.00` 产生不同的 evidence fingerprint。已同步为
   `trim_scale`，两份文件的函数体去除空白后现已完全一致，重跑幂等。

2026-08-24 收尾审计重新 dump 生产定义：23 个参数的类型、顺序、返回类型、
volatility、parallel、search path 和完整函数体均与修订文件语义一致；生产
definition MD5 为 `497ec0d1552b75df12c6c26d5df51990`。已存 evidence 以生产函数
重算后与 `ec1f7536...c231d8` 完全相同。

该文件中其余两处 `'amount'` 也已独立追踪：source contract 的 `amount` 只作为
School reader 返回值，Edge 的 `buildHomePrepareArgs` 不传 amount；Home prepare
从自己的 approved request/transaction 重新读取金额。结果构造器的 amount 只做
响应序列化。Home evidence fingerprint 自身使用 `trim_scale(p_amount)::text`。
因此两处都不是遗漏的哈希输入。

## 6. 待确认项

1. **correction-P 的 feature gate 结论：有意使用独立更正授权，不是漏检。**
   普通 fixed 路线的两个 Gate 当前仍关闭：Cash 西武卡
   `is_school_fixed_route_enabled=false`，School
   `cash_fixed_credit_card_route_enabled=blocked`。Correction-P 不调用普通 fixed
   writer，也不读取这两个 Gate；Home prepare 改为要求恰好一条 active 的
   `home_external_correction_route_policies`。生产唯一 policy
   `1237171e-ae3b-43a9-8cd1-979f30a1bf85` 精确限定 School/JPY、2026-08-13、
   西武卡与指定付款通道，`approval_reference` 绑定目标 School expense
   `ed23a346-2ba5-47fb-a496-4c4ba781ec86`。表注释明确该 policy 是 owner-configured
   Correction-P route authority，并要求 separately approved policy。因此普通新业务
   route 继续关闭，既成事实更正通过单独、窄范围审批完成，不新增待修 Gate 项。

2. **School 端 UI 是否需要反映该更正。**
   当前更正只存在于证据表，页面上看不出这笔已改走 fixed 路线。
   `school_expense_cash_attempts` 的状态字典中 `corrected` 早在 Phase 3C3-B
   就已定义但至今无 writer
   （`sql/current/school_expense_cash_fixed_entry_phase3c3b_20260819.sql:207,263`）。
   若业务上需要在页面体现，需要一个 `attempt_status → corrected` 的原子 writer，
   属于新的业务模型扩展，需单独审批。

3. **Correction-P SQL 已归档。** 四份文件已从根目录移动到 `sql/current/`，无副本：
   - `school_expense_cash_correction_p_20260822.sql`
   - `school_expense_cash_correction_p_evidence_fingerprint_canonicalization_20260823.sql`
   - `school_expense_cash_correction_p_rollback_tests_20260822.sql`
   - `school_expense_cash_correction_p_concurrency_setup_20260822.sql`

## 7. 与本轮其他工作的关系

`sql/current/school_expense_cash_correction_p_20260822.sql` 的这类问题——仓库文件与生产不一致、
靠人记住执行顺序——与 2026-08-10 月封口 guard 的字符串补丁属于同一类失效模式，
已在
`docs/school-v2-settlement-lesson-week-close-guard-handoff-20260823.md` 第 8 节
一并记录，建议单独立项治理。

收尾审计已将默认规则写入 `AGENTS.md`：生产部署和运行时状态只能以生产只读证据
为权威；SQL 文件头、handoff、current-status 与其他文档只记录历史动作和意图，
不得单独用于断言当前是否已部署、启用、阻断或与仓库一致。
