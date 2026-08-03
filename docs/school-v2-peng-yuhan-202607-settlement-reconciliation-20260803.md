# 彭宇晗 2026-07 月度结算只读核对

日期：2026-08-03。结论：业务描述中的净履约差 `1.75 小时 × JPY 8,500 = JPY 14,875` 由 DB 课时事实支持；但它不是当前 settlement 的应收扣减项。正式 DB 合同以 planned tuition 为基础应收，并额外加入 actual duration overage，故权威 system difference / carry 是 **+CNY 92.44**，不是 `-CNY 624.75`。本轮没有保存或锁定结算。

## 课时权威事实

July scope 共 6 条 planned、5 条 actual。aircon fee 全部为 0；无 cancelled、non-billable actual 或独立其他费用。

| planned | 日期 | 科目 / 老师 | planned | actual 关联 | actual | 结果 |
|---|---|---|---:|---|---:|---|
| `1a370095-dd14-444f-8ffb-778e92e03c88` | 07-13 | EJU日语 / 赵天歌 | 2h / JPY17,000 | 无 | 0 | `pending_makeup`，未履约 2h |
| `1c1d3db0-4e6e-40b2-b8ef-a6a2c2d144cd` | 07-13 | EJU数学 / 吴峰 | 2h / JPY17,000 | `cbae98fd-e379-44c5-89df-25b82617cb93` | 2h / JPY17,000 | completed |
| `6a16b4ed-adc4-4b72-bb41-cde39bb55a40` | 07-20 | EJU数学 / 吴峰 | 2h / JPY17,000 | `1d5a056d-4379-48b5-81ac-07d5c993f54d` | 2h / JPY17,000 | completed |
| `ccc8bf28-1059-4d50-85f4-905552cd3a0a` | 07-20 | EJU日语 / 赵天歌 | 2h / JPY17,000 | `6e08af3d-3780-4896-b603-64565f2e0ce4` | 2h / JPY17,000 | completed |
| `8d5ec9a9-6b8a-4203-8ee4-7d3513d45978` | 07-27 | EJU日语 / 赵天歌 | 2h / JPY17,000 | `d7b53eb8-e7ba-49e3-9259-1a2cdf389822` | 2.25h / JPY19,125 | completed；15 分钟 overage / JPY2,125 |
| `a600f131-88e9-4a5e-bc87-c8ea05d564e7` | 07-27 | EJU数学 / 吴峰 | 2h / JPY17,000 | `e28dede3-68b3-46d9-9d53-24c3799693fd` | 2h / JPY17,000 | completed |

汇总：planned `12h / JPY102,000`；billable actual `10.25h / JPY87,125`；单独未履约 `2h / JPY17,000`；另一 actual overage `0.25h / JPY2,125`；净差 `12 - 10.25 = 1.75h`，`102,000 - 87,125 = JPY14,875`。因此业务负责人所述的小时、单价、JPY 金额均精确成立，但它是“planned 与 actual 净差”，不是当前 DB settlement 合同的 receivable credit。

## 收款与汇率口径

| 事实 | 权威值 |
|---|---|
| July bill | `2a0948e0-9015-4b18-848c-8c397e0bc2a0`；JPY102,000；rate 0.0418；通知 CNY4,263.60 |
| School income | `09fa4398-9d20-494b-8ab5-8f7c3cafa414`；`received`；School 金额 JPY102,000 |
| School linkage | `3146994b-615e-4e77-82d2-139797a6718f`；synced；payment CNY4,263.60；rate 0.0418 |
| Cash request | `5e3df741-d4bc-405d-bc83-d2d288c72841`；approved；CNY4,263.60 |
| Cash transaction | `576bbce0-58c8-4f88-bcc1-e762c5d7f113`；CNY income 4,263.60；JPY transaction 0 |
| 当前 settlement rate | 学生 DB `preset_exchange_rate = 0.0435` |
| settlement received equivalent | School income 仍按 `payment_currency=JPY` 汇总 JPY102,000，再按当前 preset 0.0435 折算为 CNY4,437.00；不会读取 Cash 实收 CNY4,263.60 |

存在至少三个口径：历史 bill/Cash 冻结 0.0418；当前 DB settlement preset 0.0435；业务指令中的假设 0.042。生产 DB 没有把 0.042 保存为彭宇晗 July settlement 或收款权威汇率；本轮 0.042 只来自业务负责人给出的假设场景。August 已作废 bill 的 rate 0.0415 也不是 July settlement rate。

## 完整桥接表

| 项目 | DB 权威 0.0435 | 业务假设 0.042 | 说明 |
|---|---:|---:|---|
| planned JPY | 102,000 | 102,000 | DB July scope |
| actual JPY | 87,125 | 87,125 | informational |
| unused/net JPY | 14,875 | 14,875 | planned - actual |
| unused equivalent CNY | 647.06 | 624.75 | 不进入正式 final_due 公式 |
| duration overage | JPY2,125 / CNY92.44 | JPY2,125 / CNY89.25 | 正式合同正向加入 |
| received JPY | 102,000 | 102,000 | School income |
| received equivalent | CNY4,437.00 | CNY4,284.00 | 按场景 rate 换算；Cash 实收另为 CNY4,263.60 |
| previous carry | 0.00 | 0.00 | 无 carryover/previous locked settlement |
| draft adjustment | 0.00 | 0.00 | 无 draft |
| posted adjustment | 0.00 | 0.00 | 无 posted adjustment |
| system difference（正式 planned 合同） | **+92.44** | +89.25 | planned × rate + overage × rate - received JPY × rate |
| actual-consumption 假设结果 | -554.63 | -535.50 | actual × rate + overage - received；不是已批准合同 |
| `-624.75` | 不成立 | 仅 unused JPY × 0.042 | 还忽略了 JPY2,125 overage；不是 DB final carry |
| `carry_final_balance` final carry | **+92.44** | 非权威 | DB resolver：adjustment 0，carry=system difference |
| `clear_balance` final carry | 0.00 | 非权威 | DB resolver：adjustment -92.44；会抹掉差额 |

P0-D 的 `+92.44` 来源可逐项展开：

```text
planned tuition       JPY102,000 × 0.0435 = CNY4,437.00
duration overage       JPY2,125 × 0.0435 = CNY   92.44（round 2）
previous carry                                 = CNY    0.00
received equivalent   JPY102,000 × 0.0435 = CNY4,437.00
system difference = 4,437.00 + 92.44 + 0.00 - 4,437.00 = +92.44
```

`-624.75` 则只等于 `JPY14,875 × 0.042` 的负数。当前合同明确声明 actual totals 仅展示，不能冲减 planned tuition；同时实际存在 overage JPY2,125。因此 DB 不支持将 `-624.75` 作为 July final carry。

## 唯一操作建议

- mode：`carry_final_balance`。
- 权威汇率：当前 DB preset `0.0435`。
- system difference / final carry：`+CNY92.44 / +CNY92.44`。
- 符号与 August 影响：正数，若后续锁定并 Reissue，会在新 August 应收上增加 CNY92.44，而不是减少 CNY624.75。
- `clear_balance` 会把 carry 抹为 0，不符合“结转余额”；`manual_adjustment` 不得被用来强行制造 `-624.75`。

但该唯一合同建议与业务目标“把学生剩余余额作为负结转”冲突，所以当前操作状态为 **No-Go：新的结算差异调查**。业务负责人若坚持 actual-consumption credit，需要另行明确批准结算权威/公式的业务模型变化；本轮不修改合同，也不保存、lock、unlock 或 relock。

## 李天伦 July 对照

李天伦 July settlement、draft、adjustment均 0 行；DB preview 为 rate `0.05`、planned JPY260,000、received JPY260,000、actual 0、duration overage 0、previous carry 0、system difference/final carry 0。没有 adjustment、overage 或其他差额，不创建零金额 settlement不影响后续重新 preview/Reissue。

## 写入边界

本报告所有 reconciliation 查询均在 `BEGIN READ ONLY` 中完成。彭宇晗/李天伦真实 settlement、draft、adjustment、carryover 写入均为 0；lesson 写入 0；Cash 写入 0；未调用任何 settlement writer RPC。
