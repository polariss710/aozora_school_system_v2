# School V2 Atomic Tuition Void/Reissue 扩模批准实施前硬停止报告

日期：2026-08-02（JST）
阶段：业务模型扩展批准映射与固定15链生产前检查；**HARD STOP**

## 1. 结论

本轮批准已经逐项覆盖 generation identity、revision、void event、active authority、
relation claim、统一 School operation lock、Cash reservation、固定15链初始化和
service-role-only 权限，原扩模门主体已通过。

但固定15链与已批准的 revision manifest 合同存在无法自主解释的冲突：

- 15条现有 canonical identity 中，8条 `atomic_charge` 具有合法64位小写
  `generation_manifest_sha256`；
- 7条 `historical_backfill` 在 legacy identity evidence、bill snapshot、income snapshot
  三处都没有 generation manifest；
- 已批准的 `school_student_tuition_generation_revisions.generation_manifest_sha256`
  明确为 `NOT NULL`；
- 同一批准同时禁止 NULL/legacy fallback，并要求固定15链全部注册为 revision 1 active。

因此不能在不新增业务语义的情况下为7条 historical chain 填入该字段。伪造零值、复用
无关 hash、把某个诊断 hash 当成 generation authority，或自主设计新的 historical
registration manifest 都会违反 Schema And Business Model Expansion Gate。

本轮在 schema/RPC 草案前停止。没有关闭 Gate，没有执行 migration/registration，
没有修改数据库、前端或真实目标记录。

## 2. 缺少 generation manifest 的固定7链

| legacy identity | 学生 | 月份 | bill | income |
|---|---|---|---|---|
| `b1000000-0000-4000-8000-202607270001` | 孙陈锋 | 2026-07 | `2a9f1c25-a060-461e-ae10-b02295dec381` | `468ab75b-312e-4ba0-8d8d-8ae2f6ace00e` |
| `b1000000-0000-4000-8000-202607270002` | 张倬闻 | 2026-07 | `fdf3cdfe-f715-4814-b500-9ff2bfe77a63` | `f86ac9db-effd-402e-a320-1e4b6846a9c7` |
| `b1000000-0000-4000-8000-202607270003` | 彭宇晗 | 2026-07 | `2a0948e0-9015-4b18-848c-8c397e0bc2a0` | `09fa4398-9d20-494b-8ab5-8f7c3cafa414` |
| `b1000000-0000-4000-8000-202607270004` | 李天伦 | 2026-07 | `07a02092-9503-47d1-9000-106f7e3de7e5` | `91756564-c48d-4a1d-b6bc-88a041660e46` |
| `b1000000-0000-4000-8000-202607270005` | 陈加恩 | 2026-07 | `2608806a-283a-4919-a851-b25962f2c0b2` | `4a63f0ca-450f-4306-9e39-6d43172b3cf8` |
| `b1000000-0000-4000-8000-202607270007` | 陈红卓 | 2026-07 | `7472f73f-fa19-4565-9180-a517c7151835` | `3a5542c5-5397-4688-999e-a08bb678f40d` |
| `b1000000-0000-4000-8000-202607270006` | 陈加恩 | 2026-08 | `1b546782-1b39-4c73-a85d-27ab1e5086ad` | `cdf3da68-e578-4f1b-b759-2fff394e1906` |

7/7 的三个 manifest 位置均为 NULL；7/7 的 identity source 均为
`historical_backfill`。其余8/8 `atomic_charge` chain 的现有 generation manifest
均通过 `^[0-9a-f]{64}$`。

## 3. 其他实施前检查结果

- 15/15 chain 的 identity、bill-income、bill-lessons 三个 authoritative validator
  全部通过。
- 当前 Gate 仍为 `enabled / enabled / enabled`，本轮没有进入短时维护 Gate 阶段。
- 当前 Cash bridge 已具备正确的结构顺序：School
  `school_request_cash_income_confirmation_for_record(...)` 先插入或确认
  `pending_cash_request` linkage/reservation 并独立提交；Edge 随后才调用 Cash
  `home_create_external_transaction_request(...)`。后续仍需把 active revision 与统一
  operation lock 校验加入 School RPC，并执行批准的并发矩阵。
- 彭宇晗、李天伦 2026-08 目标链未调用 void、lesson edit、generate 或 Cash submit。

## 4. 需要补充的精确业务负责人批准

推荐的最小补充是批准一个仅用于7条 historical revision 1 registration 的新 manifest
语义：

1. `generation_manifest_sha256` 对 `atomic_charge` revision 继续保存原 Atomic generation
   manifest，语义不变。
2. 对固定7条 `historical_backfill` revision 1，允许保存
   `historical_registration_manifest_v1`；它不是原 Atomic generation manifest，仅是这条
   已有 canonical chain 的不可变 registration manifest。
3. 该 hash 的 canonical JSON 必须固定包含：version、legacy identity ID、student ID、
   business entity ID、billing month、bill ID、income ID、legacy identity整行SHA-256、
   bill整行SHA-256、income整行SHA-256，以及按 `line_no,id` 排序后的全部 normalized
   relation整行SHA-256数组。
4. 最终值为上述 canonical `jsonb::text` 的 SHA-256 小写hex；registration SQL必须冻结
   7条预期值并在写前重新计算精确匹配。
5. 该语义只允许 fixed7 historical revision 1 registration；不得用于新 generate、
   不得使 historical chain 获得第一版 void/reissue 资格，也不得形成 NULL fallback。
6. 第一版专用 void 仍只接受 `atomic_charge` / `student_tuition_atomic_generate_v1` 的
   pending完整链；其 expected manifest 必须匹配 Atomic generation manifest。

这会新增 `historical_registration_manifest_v1` 这一明确 snapshot/version/authority
概念，必须由业务负责人显式批准后才能继续。若不批准，则必须修改“固定15链全部注册”
或 revision manifest 的 NOT NULL 合同；Codex不能自主选择。

## 5. 执行记录

- 文件变更：仅本报告与 `docs/current-status.md`。
- SQL 文件执行：0；schema/RPC草案：0；写RPC调用：0。
- 只读调用：15链 inventory、三个validator、Gate、Cash计数和现有代码路径审查。
- 数据库写入：0；test whitelist写入：0；测试记录ID：无。
- Gate写入：0；真实void/reissue/Cash submit：0。
- 两份既有未跟踪文件均未修改。
