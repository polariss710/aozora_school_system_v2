# 彭宇晗 2026-07 月度结算真实操作报告

日期：2026-08-03  
授权范围：仅 `save-draft` 后 `lock`；禁止 Reissue、lesson 修改、Cash、Gate、unlock/relock及其他学生操作。

## 操作前检查

对象：

- student：`eb705aad-de4d-45e6-a391-42dcdd89aeda`
- business entity：`2cf7b72f-6e3c-4d09-80f7-7c58593cd466`
- settlement month：`2026-07`
- August active tuition revision：0
- source/adjustment draft、settlement、claim、carryover：均为 0
- Cash/downstream：0；Gate：`enabled / blocked / blocked`

最新 DB Preview：

- source treatment：`net_lesson_variance_to_financial_credit_v1`
- rate/source/date：`0.042` / `business_owner_confirmed_monthly_settlement_rate_v1` / `2026-07-01`
- adjustment mode：`carry_final_balance`
- unused planned：`-2.00h / -JPY17,000 / -CNY714.00`
- actual overage：`+0.25h / +JPY2,125 / +CNY89.25`
- net：`-1.75h / -JPY14,875 / -CNY624.75`
- system difference：`-CNY624.75`
- adjustment：`CNY0.00`
- final carryover：`-CNY624.75`
- preview manifest：`c7a8041210061a56d4b100430c10655931cb0f732e19d73f471a4af7be7a6c83`
- lesson source manifest：`864818e4d7c688e5dc4904a626ca8b426a94385f80b4a8e820b50ddffe64f38d`

reason：`7月2小时待补与0.25小时超额转为财务净额，净剩余1.75小时进入8月账单抵扣。`

## 保存草稿

正式工具先执行 dry-run，再用实时 DB 返回的完整 expected facts 和精确确认文本执行 `save-draft --execute`。结果：

- source-treatment draft：`8c619504-4426-49e5-af53-e529ee1346d1`
- adjustment draft：`3b0e653e-a9e8-452f-b331-7d570d319f2f`
- 创建时间：`2026-08-03T14:39:36.671057+00:00`
- 保存后状态：active；DB复读金额、mode、rate/source/date、source count和两个manifest全部一致

## 正式锁定

锁定前重新 Preview 和复读两份 draft，确认 source仍为2、UUID/manifest未变、没有新增 actual/makeup/overage/收入、August active revision为0、Rule A/B允许、final carry仍为 `-624.75`。随后单独执行 `lock --execute`。

结果：

- settlement：`6ec3b815-5540-44bd-88ee-9e30a5284770`
- status：`locked`
- locked at：`2026-08-03T14:40:17.227562+00:00`
- claim batch：`794255bb-9983-4c6c-8103-8697d1660df3`
- source draft / adjustment draft：均为 `consumed`，settlement_id指向上述 settlement
- system difference：`-624.75`
- posted adjustment：`0.00`
- final carryover：`-624.75`
- active claims：恰好2条

source与claim：

| 类型 | planned UUID | actual UUID | JPY | CNY | claim UUID |
|---|---|---|---:|---:|---|
| unused planned credit | `1a370095-dd14-444f-8ffb-778e92e03c88` | — | -17,000 | -714.00 | `3ecb9873-7036-4c27-a113-7f8b4f2d7f5f` |
| actual duration overage | `8d5ec9a9-6b8a-4203-8ee4-7d3513d45978` | `d7b53eb8-e7ba-49e3-9259-1a2cdf389822` | +2,125 | +89.25 | `8fc8d34e-b35e-42f9-b1a3-df12d66b8516` |

相同 exact facts 的 duplicate lock 返回上述同一 settlement、`idempotent=true`、active claim仍为2，没有第二批 claim。source已由 immutable active claim消费，不能再产生重复免费补课权益或重复 overage收费权益。

注意：settlement 的遗留字段 `duration_overage_fee_cny=92.44` 是 preset rate `0.0435` 的旧冻结展示字段；P0-F 本轮唯一财务净额权威使用显式 settlement rate `0.042`，overage claim为 `89.25`，unused为 `-714.00`，net/system difference/final carry均为 `-624.75`。本轮未改写旧字段语义。

## 前后数据证明

School 全表探针：

| 对象 | before | after |
|---|---|---|
| lesson | `731 / f3cb7c99e78b9fb26b5d557c53dc4f20` | 相同 |
| bill | `18 / bc7fe1fc6d904c5f6a0380583e430c9e` | 相同 |
| income | `51 / 4468607bc30770376ce6aaca9016e598` | 相同 |
| carryover row | `8 / 54133d433579c772ba76017b757c49fd` | 相同 |
| settlement | `17 / b890bdc29a27d842d3e3c6a28b84d526` | `18 / 481ffa7ed5173da852f0f28ce66c2e9b` |
| source draft | `0 / d41d8cd98f00b204e9800998ecf8427e` | `1 / c2a01866c1bfe9edd5eb559d6faf4a67` |
| adjustment draft | `6 / 059c5187ad6513f9501076193aa55696` | `7 / 0b162413935ed3a35920d144faffbc52` |
| posted adjustment | `5 / 4bce2b158d4de769d592a2d367881868` | `6 / c1db6c7c8fe52014b9dc569ae2386fa7` |
| variance claim | `0 / d41d8cd98f00b204e9800998ecf8427e` | `2 / fbce39067e6d98167cdb474eb9635c92` |

posted adjustment新增1条是 `carry_final_balance` 的DB权威冻结行，金额为0；不是 manual adjustment。generation identity/revision/void event终态分别为 `15 / 60f11efc1aebad6b182f7d0da08d36d7`、`16 / 3fb1700c806e58cb0f8a75358a09dbd5`、`3 / 77cdf1ea30ebd54801c6ce2b392bf73a`，本轮未改动。

Cash before/after完全一致：request `39 / 303e10bc1a28a0abd8b27afd3929cfd8`、CNY transaction `71 / d7e72182970de4ea8849c994b67e8dcc`、JPY transaction `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`。真实 Cash 写入0，lesson写入0，Reissue写入0，Gate写入0，其他学生写入0。

旧 `school_tuition_p0f_school_postdeploy_20260803.sql` 的 controlled-void eligible固定期望为31，而合法课时作废后的现值为22，故该历史断言在进入hash输出前失败且无写入；本报告改用当前任务的只读通用全行hash探针。此差异不属于月结写入失败，也未回退既有课时作废。

## Git、受保护文件与终态

- 基线：`649c14eb08b726172dd95535286e07d3d2f59f97`
- 工具/页面/wrapper：`fb3812c`，parent `649c14e`
- 幂等/history/status收紧：`1d3e08c`，parent `fb3812c`
- 上述提交与最终报告已普通 push `origin/main`

六份受保护 untracked 文件：

- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`：`272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`：`b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`：`5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`：`b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`：`7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

Gate终态继续为 `enabled / blocked / blocked`。本轮到此停止；彭宇晗、李天伦最终 Reissue 必须等待下一次业务负责人明确授权。
