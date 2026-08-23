# 学生月度结算 自然周封口 P0 修复 —— 交接给 Codex 审计

- 日期：2026-08-23
- 开发：Claude Code（无 DB 写权限，本轮未执行任何 SQL）
- 审计与执行：Codex
- 部署状态：**已部署**（2026-08-24 更新）。Codex 于 2026-08-24 在 School 生产
  执行完毕，preflight 通过，5 条 writer 均保留 month-write assert。生产复验：
  `2026-09-01 → v2 / lesson_week_open / write_allowed=false`，
  `2026-09-07 → v2 / closed / write_allowed=true`。
  部署提交 `317ee0b`，归档去重提交 `0d6222b`。
  - 本文件撰写时（08-23）状态为「未部署」，部署后已就地更新。部署状态以本文件
    为准，不写在 SQL 文件头注释里 —— 参见文末「已知的同类失效模式」。

## 1. 问题

课时归属月按所在自然周的周一推导：

```sql
to_char(date_trunc('week', p_lesson_date::timestamp), 'YYYY-MM')
-- sql/current/school_tuition_p0b1_lesson_authority_rpc_only_20260803.sql:92
```

而月度结算的封口判定用的是日历月：

```sql
v_current_business_month := date_trunc('month', v_business_today)::date;
-- sql/current/school_student_settlement_tokyo_month_close_guard_20260810.sql:113
```

2026-08-31 是周一，因此 2026-08-31～09-06 这一周的课时归属 2026-08。旧规则在
2026-09-01 就把 2026-08 判为 `closed` 并放行 save/lock，此时 9/1～9/6 六天的
8 月课时尚未发生。**在 9/1 锁定会冻结一个不完整的 8 月。**

Codex 已于本日只读确认该行为：`business_today=2026-09-01` 时
`classification=closed`、`write_allowed=true`、两个 blocker_code 均为 NULL。

## 2. 修改范围

规则只存在于 `school_get_student_settlement_month_write_eligibility_at_core`
一个函数中。`..._eligibility_core` 是薄委托，`school_assert_student_settlement_month_write_allowed`
调用它，而 2026-08-10 的 guard 已把该 assert 注入进 5 个写入路径：

| 注入目标 | action |
|---|---|
| `school_set_student_settlement_source_treatment_draft` | save_draft |
| `school_set_student_monthly_settlement_draft_adjustment` | save_draft |
| `school_lock_student_monthly_settlement`（owner core） | lock |
| `school_save_student_settlement_draft_local` | save_draft |
| `school_lock_student_monthly_settlement_local`（本机受信工具） | lock |

**因此改 `_at_core` 一处，5 条路径全部继承，无需重新打任何补丁。**

## 3. 新判定

```sql
v_current_lesson_month := date_trunc(
  'month', date_trunc('week', v_business_today::timestamp)
)::date;
```

| 条件 | classification | blocker |
|---|---|---|
| `target > current_business_month` | future | `SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED`（不变） |
| `target = current_business_month` | current | `SETTLEMENT_MONTH_NOT_CLOSED`（不变） |
| `target < current_business_month` 且 `target >= current_lesson_month` | **lesson_week_open**（新） | **`SETTLEMENT_LESSON_WEEK_NOT_CLOSED`**（新） |
| 其余 | closed | 放行 |

`contract_version` 由 `student_settlement_tokyo_month_close_v1` 升为
`student_settlement_lesson_week_close_v2`。输出新增 `current_lesson_month` 便于观测。

因 `current_lesson_month <= current_business_month` 恒成立，新分支只可能在每月
头几天触发，**不会重判任何更早的月份**。

## 4. 文件清单

**SQL**（撰写时位于仓库根目录且未执行；部署后由 `0d6222b` 归档并按
`sql/current/` 惯例重命名，根目录副本已删除）

- `sql/current/school_student_settlement_lesson_week_close_guard_20260823.sql`
  —— 主体。含 preflight：5 个写入路径必须仍带 assert，否则 fail closed。
- `sql/current/school_student_settlement_lesson_week_close_guard_rollback_tests_20260823.sql`
  —— 回滚测试，9 组。**不读写任何业务表、不调用任何 writer RPC**，事务末尾
  `rollback`。准确说不是「全程只读」：它会在 `pg_temp` 中创建一个辅助函数
  （临时 schema 的 catalog 写入），T8/T9 会读 `pg_proc` / `pg_namespace`
  系统目录。业务数据零影响。

**前端（已改）**

- `js/pages/settlement-online-state.js` —— `PREVIEW_ONLY_MONTH_BLOCKERS` 加入新
  code；`blockerLabel` 加入新标签。
- `js/pages/settlement-page.js` —— 错误文案表加入新 code；保存按钮 tooltip 文案。

**版本**：`v10.5.61 → v10.5.62`，缓存键
`filter-contract-b3-20260822-1 → lesson-week-close-20260823-1`（10 个源文件 +
13 个静态测试）。缓存键在 5 个页面间被
`scripts/filter-query-reset-contract-static-test.mjs:7` 断言必须一致，故只能全局升。

## 5. 我验证了什么，怎么验证的

- **日期逻辑**：用独立实现（Node）交叉验算 2025-2028 共 48 个月、3570 次比对，
  0 处不一致。期望值不是抄实现，而是只从归属规则推导：月 M 的最后一节课是
  「M 中最后一个周一 + 6 天」，故 M 在 +7 完成。
  - 2026-08：9/1～9/6 拦截，9/7 放行 ✓
  - 48 个月中 8 个月末日恰为周日（无跨月周），开放日 = 次月 1 日，与旧规则一致。
    新规则是旧规则的严格收紧，不存在任何比旧规则更早放行的情况。
- **静态测试**：分两个阶段，读本文件时请注意当前处于哪个阶段。
  - 阶段一（本次 P0 改动本身）：全量 93 个，改动前后**均为 70 通过 / 23 失败**，
    用 `git stash` 在干净树上确认过基线，未引入新失败。
  - 阶段二（随后进行的静态测试红项清理，属于另一批改动）：新增
    `scripts/run-static-tests.mjs` 与 `scripts/static-test-helpers.mjs`，
    并把 7 个钉死具体 `APP_VERSION` 的断言改为单调断言。
    完成后为 **74 通过 / 19 失败**（逐文件直跑），等价于统一 runner 的
    **74 通过 / 11 环境跳过 / 8 失败**。11 + 8 = 19，两组数字描述同一状态。
  - 因此若你在阶段二之后读到本文件，`70/23` 已不可复现，这是预期的。
- **历史月份不受影响**：回滚测试 T5 覆盖 2026-01-01～2027-12-31 每一天。

## 6. 我没能验证的 —— 请 Codex 重点攻击

1. **回滚测试从未在真实 PostgreSQL 上跑过。** 我无 DB 权限，SQL 语法与函数行为
   均未实际执行验证。`pg_temp` 临时函数、`generate_series` 与 `date_trunc` 的
   具体返回类型可能与我的预期不符。
2. **`date_trunc('week', ...)` 是否真的返回周一，取决于服务器行为。** 我按 ISO
   语义假设为周一。请实测确认，并确认 2026-08-31 在生产上确实被算作 2026-08 的
   最后一个课时周起点。
3. **`school_get_student_monthly_settlement_online_status_core` 是否会正确透传
   新的 blocker code 与 message。** 该函数被 2026-08-10 的 guard 字符串补丁改过，
   我只能看到补丁脚本，看不到生产函数体。若它对 blocker code 做了白名单过滤，
   新 code 会被吞掉。
4. **前端 `immutable_blocker.code === save_blocker_code` 的相等性**
   （`js/pages/settlement-online-state.js:88`）在新 code 下是否仍成立。我从
   `:132-137` 推断 `immutable_blocker` 由 `save_blocker_code` 派生因而自洽，
   但未在真实响应上验证。
5. **是否存在别的 blocker 会先于月份检查命中，使新分支永远不可达。** Codex 给出
   的 16 条 `can_save` 判定链中，月份检查排第 15。请确认 2026-08 在 9/1 时不会
   先撞上第 16 条 `SETTLEMENT_SOURCE_FACTS_EMPTY` 之外的其他 blocker。
6. **本机受信工具 `scripts/manage-student-settlement.zsh` 的确认文本**是否包含
   月份可写性描述，需要同步更新。我未检查该脚本的文案。

## 7. 建议的执行顺序

1. Codex 独立复核本文件第 3 节的判定逻辑与第 6 节的攻击点
2. 在隔离环境跑 `supabase-test-...-rollback.sql`，确认 9 组测试全绿
3. 生产执行 `supabase-update-...-guard.sql`（含 preflight，失败即中止）
4. 生产只读复验：`_at_core` 在 `2026-09-01` 与 `2026-09-07` 两个参考时点的返回
5. 前端静态测试回归，确认仍为 70/23
6. 归档 SQL 至 `sql/current/`，更新 `docs/current-status.md`

## 7.5 业务规则确认（2026-08-23，业务负责人经 ChatGPT 复核）

已确认，可作为本次修改的业务依据：

- 学生月结按自然周归属，老师工资按实际授课日期的自然月归属。**两套规则不要求
  月份一致**，这是有意设计。2026-09-03 的课计入学生 2026-08 月结、计入老师
  2026-09 工资。
- **锁定 8 月学生月结不需要等待 9 月老师工资结算**，两者是独立业务流程。
- 副作用（非缺陷）：直接用「8 月学生收入」对比「8 月老师工资」算利润会有月份
  错位，09-01～09-06 的学生收入在 8 月而老师成本在 9 月。这是规则的自然结果。
- 月末恰为周日时，次日（周一）即可保存和锁定。与本次实现一致。
- 自然周未结束时，**保存草稿与正式锁定均禁止**；只读预览应保留。本次前端修改
  正是为了保住只读预览（详见第 6 节第 4 点）。
- 不同月份包含 4 或 5 个收费周、课时数天然不等，业务接受。

与跨月补课的兼容性（我已从代码确认，非业务口述）：

- `school_create_cross_month_makeup_completed_actual_from_planned_rpc` 的注释
  （该文件 :397）明确：补课 actual 默认 **non-billable**、写入**补课月**、且
  **拒绝已锁定的目标学生结算月**。
- 因此「某月最后一个自然周结束 = 该月应收事实完整」成立，后续补课不会向来源月
  追加应收金额。本次 guard 的前提假设不受跨月补课影响。

仍需业务方确认、**不在本次范围**：

- 跨月周中途入学 / 暂停 / 退学的收费周起算
- 固定月费学生在 4 周月与 5 周月是否同价
- 收据日期、账单月、现金收款月三者的归属关系
- 长假、停课周是否仍计入收费周
- 已锁定后补录或修改课时，走 unlock/relock 还是次月调整
  （注：unlock/relock 目前无任何可用通路，见第 8 节）

## 8. 已知的同类失效模式（建议单独立项，不在本次范围）

1. **字符串补丁静默丢失**：2026-08-10 guard 用 `pg_get_functiondef` + `replace`
   把 assert 打进 5 个函数。任何人重跑一次基础文件（如
   `school_tuition_r1d_e_c_settlement_reader_authoritative_month_cutover.sql`），
   补丁即静默丢失，须重跑 guard 才能补回。本次 SQL 的 preflight 与回滚测试 T9
   都会检出这种情况，但那是事后发现，不是防止。
2. **`supabase-update-20260822-correction-p.sql` 的 `p_amount::text` 回退陷阱。**
   ~~生产当前是正确的 `trim_scale`，但重跑 0822 会退回旧定义。~~
   已于 2026-08-24 修复：该文件同步为 `trim_scale(p_amount)::text`，与生产一致，
   重跑幂等。详见 `docs/school-v2-correction-p-deployment-closure-20260824.md`。
3. **仓库源文件不等于生产函数体。** 凡涉及函数体的判断，须以
   `pg_get_functiondef` 的实际返回为准。
4. **23 个静态测试在主干上即为红。** `AGENTS.md:21` 把 static check failure 列为
   autopilot 硬停止条件，但该闸门当前实际为空。
   已于 2026-08-24 部分处理：新增 `scripts/run-static-tests.mjs` 区分环境缺失与
   断言失败，7 个钉死版本号的断言改为单调断言，现为 74 通过 / 11 跳过 / 8 失败。
   剩余 8 项需业务意图判断。
5. **任何人工维护的部署状态记录都会过期——包括本文件。**
   本文件曾主张「部署状态以本文件为准，不写在 SQL 文件头注释里」。
   **该主张已被推翻**：`supabase-update-20260822-correction-p.sql` 的
   `NOT DEPLOYED` 文件头在部署后未更新，先后两次误导判断；而本文件自身的
   「部署状态：未部署」同样在 24 小时内过期，直到 2026-08-24 才补正。
   换一种载体不解决问题，因为问题不在载体，在于「状态需要人记得去更新」。

   **可靠的部署状态只有一个来源：查生产。** 例如
   `select ... ->> 'contract_version'`、`pg_get_functiondef`、
   或函数定义的 md5。文档应记录「做过什么、为什么这么做」，
   不应被当作「现在是什么」的权威。
   凡是要回答「这个东西部署了吗」，一律查库，不读文件。
