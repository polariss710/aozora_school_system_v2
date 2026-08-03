# 张倬闻 2026-08 学费真实 Void + P0-E Reissue 操作报告

日期：2026-08-03。结论：业务负责人明确授权的真实生产操作已完成。张倬闻 2026-08 revision 1 已作废，P0-E revision 2 已成为唯一 active revision；新收入为 `pending / CNY 27,950.00`。本轮没有修改 lesson、2026-07 settlement、其他学生、Cash 或 Gate。

## 操作授权与 Git 基线

- 授权附件指定基线：`b9b4332316750703b912f5d7d086ccdc699f003d`。
- 操作前 HEAD 与 `origin/main` 均精确等于该基线。
- worktree 只有既有六份受保护 untracked 文件，逐项 SHA-256 与授权清单一致；本轮未修改或纳入提交。
- Business-model expansion：`none`。本轮只调用 P0-C/P0-D/P0-E 已批准、已部署的正式合同。
- 凭证仅在受控进程内由官方 Supabase CLI 读取 canonical service-role key；secret 未打印、未落盘、未进入 Git。

## 操作前 exact facts

| 事实 | 生产核验值 |
|---|---|
| student / entity | `7aef8061-7037-4881-a847-a2cdb031c0f4` / `2cf7b72f-6e3c-4d09-80f7-7c58593cd466` |
| generation / revision 1 | `96000000-0000-4000-8000-202608030009` / `96000000-0000-4000-8000-202608031009` |
| old bill / income | `553a24ba-81cf-4af0-b723-169a09914c79` / `be64a9e2-f15e-44b0-a9de-2ee91bdf9567` |
| old manifest | `3aaa288b6b4edfcd3c897f36c7f6ffb638553ed9e566a68041457036a9773f38` |
| old state / amount | active；income pending；JPY 650,000；rate 0.042；carry CNY 107.50；frozen CNY 27,407.50 |
| frozen relation | 30 行；35 课次；JPY 650,000 |
| July settlement | `b699209d-2f61-4cfa-959b-45686e2fe19b`；physical `unlocked`；effective `historically_consumed_immutable`；frozen CNY 107.50；editable/unlockable/relockable=false |
| validators | identity、bill-income、bill-lessons、generation-revision、adjustment validator 全部通过 |
| downstream | School linkage/account transaction/actual/wage 均 0；Cash request/CNY/JPY 均 0 |
| Gate | `enabled / blocked / blocked` |

操作前稳定指纹：lesson `730 / 034d3ee24d639e587447a9458244797c`；settlement `17 / 85c829ebc3bb0a4100393d9c8d6421d7`；Cash request `39 / 303e10bc1a28a0abd8b27afd3929cfd8`；CNY `71 / d7e72182970de4ea8849c994b67e8dcc`；JPY `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`。

## Void preflight 与真实 Void

正式管理工具依次执行 `status`、`history`、`void-preflight`、`void` dry-run。Edge 返回 `ok=true / eligible=true / cash_fact_count=0 / blocker=NULL`，并精确匹配 revision、bill、income、manifest、pending 与 30 条 lesson relation。

脱敏命令合同：

```text
manage-atomic-tuition.zsh void
  --student 7aef...c0f4 --entity 2cf7...d466 --month 2026-08
  --revision 9600...1009 --expected-revision 1
  --bill 553a...9c79 --income be64...9567
  --manifest 3aaa...f38 --reason <授权原文>
  --execute --confirm "VOID ATOMIC TUITION 7aef...c0f4 2026-08 REVISION 1"
```

结果：

- void event：`03ec26aa-fedb-4f18-861a-956acb771f83`；
- revision 1：`voided`；old bill / income：`cancelled / cancelled`；
- old revision、bill、income、30 条 relation、snapshot 与 manifest 全部保留；
- active old lesson claim 从 30 降为 0；lesson 行、July settlement、Cash/downstream 与 Gate 均未变化。

## P0-E preview 与真实 Reissue

正式 `reissue-preview` 的 DB 权威结果：

| 事实 | 值 |
|---|---:|
| original | JPY 650,000 |
| rate / exchange amount | 0.043 / CNY 27,950.00 |
| historical carry | CNY 107.50 |
| adjustment type / amount | `neutralize_historical_carryover_v1` / -CNY 107.50 |
| final billing amount | CNY 27,950.00 |
| source settlement / revision | `b699209d-2f61-4cfa-959b-45686e2fe19b` / `96000000-0000-4000-8000-202608031009` |
| candidate | 30 行 / 35 课次 / JPY 650,000 |
| candidate manifest | `515766018b4857ab4d1dd6f5bfd5cf64a8991dc44c42e708c1a940d57d116eb6` |
| generation manifest | `a35fa72406378c94c1d92574aaa054f46628057175e47155beafd5d704e3a677` |
| adjustment line manifest | `deb981857020f7deeb34ce9a224719e63bef07b6d1f6eeb2c777363b0aae25d7` |

普通 Reissue 仅在事务回滚探针内调用，精确返回 `TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED`；事务后 revision/active/adjustment 仍为 `1/0/0`，净写入 0。随后 P0-E 管理工具 dry-run 通过。

脱敏命令合同：

```text
manage-atomic-tuition.zsh reissue
  --student 7aef...c0f4 --entity 2cf7...d466 --month 2026-08
  --generation 9600...0009 --previous-revision 9600...1009
  --rate 0.043 --expected-jpy 650000
  --expected-exchange-cny 27950.00 --expected-cny 27950.00
  --forward-adjustment-mode neutralize-historical-carryover
  --expected-historical-carryover-cny 107.50
  --expected-forward-adjustment-cny -107.50
  --candidate/generation/line-manifest <上述 DB exact 值>
  --execute --confirm "REISSUE ATOMIC TUITION 7aef...c0f4 2026-08 RATE 0.043 CARRY 107.50 FORWARD -107.50 FINAL 27950.00"
```

正式结果：

- revision 2：`7d319b0d-8f62-41e9-95bf-c1a0c6ed7090`，唯一 active，previous 指向 revision 1；
- bill：`013a7766-101b-4b5b-bcae-c008825b14fa`；
- income：`d980cedd-ebba-4be1-afcb-b25dfa26798a`，`pending / Cash待提交`；
- adjustment：`df043dee-0013-4fb6-b31f-0ea5f446bbc1`；
- 新 30 条 relation、bill/income/revision/adjustment snapshots 与三个 manifest 一致；10 项 snapshot 交叉断言全为 true；
- 四个 tuition validators 与 adjustment validator 全部通过。

完全相同参数再次调用返回 `idempotent=true` 和原四个 UUID；revision/bill/income/adjustment 没有新增。

## 最终全链验收

- Cash preflight 只读返回 `payment_currency=CNY / payment_amount=27950.00 / gate_state=blocked / eligible=false`；未提交 Cash。
- Cash request/CNY/JPY 仍为 `39/71/31` 且全行哈希与操作前一致，目标链三类 count 均为 0。
- School account transaction/linkage 均为 0。
- July settlement 物理状态仍为 `unlocked`；有效状态仍为 `historically_consumed_immutable`，CNY 107.50，editable/unlockable/relockable=false；没有 save/lock/unlock/relock。
- lesson 与 settlement 全行 count/hash 和操作前完全一致；彭宇晗、李天伦及其余 generation 链哈希不变。
- Gate 最终仍为 preview `enabled`、generate `blocked`、cash submit `blocked`。

## 写入、SQL/RPC 与 Git 交付

- School 真实写入精确限定为：revision 1 / old bill / old income 状态变更；新增 1 void event；新增 revision 2、1 bill、1 pending income、30 relations、1 adjustment 及其不可变 snapshot/manifest metadata。
- Cash DB 写入：0。lesson、settlement、其他学生、School account transaction/linkage、Gate 写入：0。
- 测试白名单写入：0；普通 Reissue 探针在事务内失败并回滚，净写入 0。测试记录 ID：不适用。
- 执行的临时 SQL：`/private/tmp/zhang_p0e_school_baseline.sql`、`/private/tmp/zhang_p0e_cash_baseline.sql`、`/private/tmp/zhang_p0e_ordinary_reissue_rollback_probe.sql`、`/private/tmp/zhang_p0e_post_acceptance.sql`；除回滚探针外均为 read-only。
- 正式调用：管理工具 `status/history/void-preflight/void/reissue-preview/reissue`；School RPC 包括 Void preflight/专用 Void、P0-E preview/专用 Reissue、五个 validators、settlement effective-state reader、Cash submission preflight。P0-E duplicate 为幂等调用。
- Git parent：`b9b4332316750703b912f5d7d086ccdc699f003d`。操作文档 commit 与 push 在本报告完成后执行；最终 hash 以紧随本报告的 Git 交付记录及任务最终回执为准，避免文档自嵌 commit hash 的递归变化。

最终结论：**张倬闻 2026-08 已达到 CNY 27,950.00 pending income；本轮未提交 Cash，工作流完成。**
