# School V2 学费 P0-E Forward Adjustment 实施报告

完成日期：2026-08-03
基线：`42804a4b2835208ba3aded36395960f5d4e45893`

## 结论

P0-E 已完成生产数据库合同、受信管理工具、月度结算只读展示、synthetic rollback/commit/并发、精确 rollback/redeploy、双库 postdeploy 和 Chrome 真实页面验收。

- 新增唯一 append-only 对象 `public.school_student_tuition_generation_revision_adjustments`。
- 唯一 adjustment type 为 `neutralize_historical_carryover_v1`。
- PostgreSQL 唯一计算 `forward_adjustment_cny = -historical_previous_carryover_cny`。
- 专用 Reissue 在同一事务写 revision、bill、income、lesson relations、adjustment、manifest 和 snapshots。
- 普通 Reissue 对符合 P0-E 的历史非零 carry 链返回 `TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED`。
- 张倬闻 2026-07 settlement 没有被修改，物理状态仍为 `unlocked`；DB reader 与页面显示 `historically_consumed_immutable`。
- 未执行任何真实学生 Void、Reissue、settlement、lesson 或 Cash 写入。

## Business-model expansion declaration

| 类别 | 精确对象 / 语义 | 权威与可变性 | 批准映射 |
|---|---|---|---|
| 新业务表 | `public.school_student_tuition_generation_revision_adjustments` | 仅保存 generation revision 的不可变 forward adjustment 证据；专用 owner core 原子 INSERT；正式记录禁止 UPDATE/DELETE；不是 settlement authority | 本轮任务“一、业务负责人精确批准”第 5–9、14–16 项和“五、Adjustment 不可变事实” |
| 新业务值 | `adjustment_type = neutralize_historical_carryover_v1` | 第一版唯一值；金额由 DB 唯一计算；不开放任意金额调账 | 第 5–7、14–15 项 |
| 新只读状态 | `historically_consumed_immutable` | 由历史 revision consumption 推导；不回写 settlement | 第 11–13 项及“八、Settlement 有效状态 Reader” |
| 历史来源语义 | 新 revision 继承上一 voided revision 冻结的 `previous_settlement_id`、`previous_carryover_cny` 与快照 | 上一 revision/bill snapshot 为唯一历史权威；当前 settlement status 不参与决策 | 第 2–4、10–13 项 |
| 兼容/双写/回填 | `none` | 无 fallback、无 dual write、无 NULL 兼容分支、无历史修复或 backfill | 第 4、10、16 项 |

索引、FK、CHECK、trigger、validator、RLS/ACL、fixture guard 和并发锁只执行上述已批准模型，没有引入其他业务事实。

## DB 权威合同

专用 preview 与 execute 均使用同一 DB 公式：

```text
exchange_amount_cny = round(original_amount_jpy * billing_exchange_rate, 2)
historical_previous_carryover_cny = previous revision frozen bill snapshot
forward_adjustment_cny = -historical_previous_carryover_cny
billing_amount_cny = exchange_amount_cny
                   + historical_previous_carryover_cny
                   + forward_adjustment_cny
```

synthetic 镜像权威结果：

| 事实 | 结果 |
|---|---:|
| original amount | JPY 650,000 |
| rate | 0.043 |
| exchange amount | CNY 27,950.00 |
| historical carry | CNY 107.50 |
| forward adjustment | -CNY 107.50 |
| final billing / Cash frozen amount | CNY 27,950.00 |
| 不带 adjustment 的继承预览 | CNY 28,057.50 |

adjustment type、source settlement/revision、historical carry、金额、reason、operator authority 和 line manifest 均进入 generation manifest、bill/income snapshots 和 validator。

## 月度结算事故回归

### 抹平差额

- `school_tuition_p0b2_resolve_adjustment('clear_balance', NULL, 107.50)` 返回 adjustment `-107.50`、carry `0.00`。
- `carry_final_balance` 只接受 `NULL`，返回 adjustment `0.00`、carry `107.50`。
- `manual_adjustment` 必须显式传金额；NULL 被拒绝。
- API 对非 manual mode 保持 `p_adjustment_amount_cny = NULL`，不会传空字符串、0 或页面计算值。
- preview/save/lock/relock 继续复用既有 P0-B2 resolver，没有第二套 adjustment 逻辑。
- Chrome 页面 `p0e-20260803-1`：从 manual 切换 clear 后，`123.45` 输入与旧错误同时清除；金额框为空且 readonly；再次触发校验显示“填写理由并勾选确认，金额由数据库计算”。
- **“抹平差额仍要求输入金额”已在真实页面确认消失。**

### 已消费 settlement

- mutation guard 修正为 active claim 时 Rule A 优先：`TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE`。
- revision Void 后，曾消费 settlement 仍由 Rule B 返回 `TUITION_CONSUMED_SETTLEMENT_IMMUTABLE`；从未消费的 zero-carry scope 可以释放。
- create/save/lock、draft、posted adjustment、carryover、row mutation、unlock/relock、直接表写和 owner RPC 均纳入 rollback 矩阵。
- **已消费 settlement 的撤销、重新保存差额、重新锁定和 carryover 修改入口均已隐藏，DB guard 同时拒绝绕过。**

### 张倬闻 2026-07

最终只读 DB/Chrome 状态：

| 字段 | 值 |
|---|---|
| settlement UUID | `b699209d-2f61-4cfa-959b-45686e2fe19b` |
| physical status | `unlocked` |
| effective status | `historically_consumed_immutable` |
| 中文状态 | `已被历史学费账单消费（不可重开）` |
| frozen carryover | CNY 107.50 |
| editable / unlockable / relockable | `false / false / false` |
| immutable code | `TUITION_CONSUMED_SETTLEMENT_IMMUTABLE` |
| 页面版本 | `v10.4.4 · p0e-20260803-1` |
| 页面修改按钮 | unlock `0`、relock `0`、adjustment `0` |

页面不再将其显示成普通“未完成月度结算”，也不会诱导操作员重新做 7 月结算。

## Synthetic 验收

固定源 fixture：

- marker：`codex-test tuition-p0e-forward-adjustment-20260803`
- student `d0d00000-0000-4000-8000-00000000a001`
- settlement `d0d00000-0000-4000-8000-00000000b001`
- generation `d0d00000-0000-4000-8000-000000003001`
- revision 1 `d0d00000-0000-4000-8000-000000004001`
- old bill `d0d00000-0000-4000-8000-000000006001`
- old income `d0d00000-0000-4000-8000-000000007101`

whitelist commit test 临时创建并最终清理：revision 2 `bdf88e69-22f2-4c72-8a7b-1a5a2b2d63a3`、bill `34260cde-3d44-4858-ab8c-96249da425c0`、income `a7157b9a-f79c-4582-97f6-f1939bcfcc83`。commit test、幂等、不同 reason/manifest 冲突、append-only、防直接写、四 validator 和 adjustment validator 全通过；最终 fixture residue 为 0。

8 组双会话均实际阻塞 4–5 秒：

1. Reissue vs settlement mutation；
2. Reissue vs Void；
3. duplicate Reissue；
4. Reissue vs lesson edit；
5. Reissue vs Cash reservation；
6. ordinary Reissue vs P0-E Reissue；
7. adjustment duplicate race；
8. manifest mismatch race。

结果：无 deadlock、lock timeout、statement timeout 或半写入；active revision 始终最多 1，adjustment 始终最多 1。

## SQL、RPC 与工具

执行的生产 SQL：

- `school_tuition_p0e_forward_adjustment_schema_20260803.sql`
- `school_tuition_p0e_forward_adjustment_20260803.sql`
- `school_tuition_p0e_settlement_rule_priority_correction_20260803.sql`
- `school_tuition_p0e_shared_lock_correction_20260803.sql`
- `school_tuition_p0e_acl_correction_20260803.sql`
- `school_tuition_p0e_rollback_20260803.sql`（精确 rollback rehearsal，之后完整重部署）

测试/只读 SQL：rollback tests、whitelist commit test、settlement Rule A/B 8/8、双会话 8/8、School/Cash postdeploy、fixture lifecycle。

主要调用 RPC：

- `school_get_atomic_tuition_reissue_preview_p0e`
- `school_reissue_atomic_student_tuition_generation_p0e_local`
- `school_void_atomic_student_tuition_generation_local`
- `school_get_student_monthly_settlement_effective_states`
- `school_validate_tuition_generation_revision_adjustment_for_bill`
- 四个既有 tuition validators
- P0-B2 resolver 与 settlement lock/unlock/relock/draft RPC
- Cash submission preflight（只读 frozen amount）

`scripts/manage-atomic-tuition.zsh` 的 preview/reissue/status/history 已支持 forward adjustment exact facts；默认 dry-run、确认文本包含学生/月/汇率/carry/forward/final；脚本不计算金额、不直接 DML、不连接 Cash DB。

## 最终指纹与写入边界

School 核心业务表数量和全行 MD5 与 P0-D 基线完全一致，包括 lesson `730 / 034d3ee24d639e587447a9458244797c`、settlement `17 / 85c829ebc3bb0a4100393d9c8d6421d7`、bill `17 / b18f15673637280bf1455667ccd3cc00`、income `50 / dccaf8446c3907b48cec9bf028b4373c`、generation `15 / 15`。正式 adjustment 行为 `0`。

Cash 保持：request `39 / 303e10bc1a28a0abd8b27afd3929cfd8`、CNY `71 / d7e72182970de4ea8849c994b67e8dcc`、JPY `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`。

- Schema/RPC 元数据写入：有，限上述 P0-E 对象与函数。
- School synthetic whitelist 写入：有，已精确清理，residue 0。
- **本节真实业务写入：0。**
- **Cash DB 写入：0。**
- Gate：`student_tuition_preview=enabled`、`generate=blocked`、`cash_submit=blocked`。

P0-E 实施完成不等于授权真实操作。张倬闻真实 Void/Reissue 仍需后续单独、明确的操作指令。
