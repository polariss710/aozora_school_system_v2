# P0-D 三名真实学生操作状态

日期：2026-08-03。本文最初记录三名学生的生产只读操作前事实；业务负责人随后分别授权并完成张倬闻真实 Void + P0-E Reissue，以及彭宇晗、李天伦真实专用 Void。三人当前状态均已在本文件更新。

## 分流结论

| 学生 | Void 技术条件 | July settlement | 仍缺输入 | Reissue / 当前 Go-No-Go |
|---|---|---|---|---|
| 彭宇晗 | 已完成；rev1/bill/income=`voided/cancelled/cancelled`；void event `48dbdd0d-0934-4270-a6cb-230537bee86f`；active claim 0 | 不存在；最新 DB preview system/carry `+92.44`；未保存/锁定 | 15 条课时页面会显示删除，但 DB 因历史 bill snapshot 全部拒绝；July 业务目标与 DB 合同还存在差异 | 删除、July lock、Reissue 均 **No-Go** |
| 李天伦 | 已完成；rev1/bill/income=`voided/cancelled/cancelled`；void event `9af7d2b3-7905-4dd6-a325-515ca22a304e`；active claim 0 | 不存在；DB preview carry `0`，不创建零金额 settlement | 16 条课时页面会显示删除，但 DB 因历史 bill snapshot 全部拒绝 | 删除与 Reissue 均 **No-Go** |
| 张倬闻 | 已按单独业务授权完成真实 Void | July 物理状态仍为 `unlocked`；有效状态 `historically_consumed_immutable`；未 relock/覆盖 | 无 | P0-E revision 2 已唯一 active；pending CNY `27950.00`；**Completed** |

## 彭宇晗

### Void 前冻结事实（历史基线）

| 字段 | 只读事实 |
|---|---|
| student | `eb705aad-de4d-45e6-a391-42dcdd89aeda` |
| generation / revision | `96000000-0000-4000-8000-202608030013` / `96000000-0000-4000-8000-202608031013` |
| revision | `1 / atomic_generation_v1 / active` |
| manifest | `1e75fd1456114d53b5c575d27d103ec4c038675b35586576d4ec40a28c91d801` |
| bill | `1e02dc09-8f42-4a93-85c6-e27809d68a83 / income_created` |
| income | `ae4d8b66-491b-4db2-ac91-86765f56155c / pending` |
| frozen money | currency `JPY`；JPY `255000`；rate `0.0415`；carry `0`；CNY `10582.50` |
| previous settlement | UUID `NULL`；status `ABSENT`；previous month `2026-07` |
| relation | 15 rows；lesson_count 合计 15；JPY `255000`；relation hash `bf24a5da40ad4b936f44d9e40cbccd14` |
| Cash / downstream | request `0`；CNY transaction `0`；JPY transaction `0`；School linkage/account transaction/actual/wage facts均 `0` |
| validators | identity、bill-income、bill-lessons、generation-revision：`4/4 PASS` |
| Void preflight | Edge `preflight_only ok=true`；School eligible；blocker `NULL`；active lesson claims 15 |
| 永久冻结 | revision 1、旧 bill/income、relation、snapshot、manifest 保留；当前不存在被该 bill 历史消费的 July settlement |

July DB-authoritative preview（只读、以当前事实为准）：rate `0.0435`；planned `12h / JPY102000 / CNY4437.00`；actual `10.25h / JPY87125 / CNY3789.94`；received `JPY102000 / equivalent CNY4437.00`；final due / locked carry `92.44`；draft/posted adjustment/carryover均 0。active August revision 存在时，Rule A 阻止 July settlement create/save/lock/unlock/relock 与 child mutations；Void 后因没有历史 `previous_settlement_id` 消费，该 scope 可释放并走正式 lock/relock RPC。

当前 15 条 frozen relation 均为 `planned / planned / billable=true`，当前行与 frozen line 一致：

| lesson UUID | 日期 | 科目 / 老师 | count / hours | unit / fee |
|---|---|---|---:|---:|
| `d147d783-8c20-4d9e-bb94-03ea03c19a21` | 2026-08-05 | EJU日语 / 赵天歌 | 1 / 2 | 8500 / 17000 |
| `79502518-0c0d-4025-87e8-58e2177ae3dd` | 2026-08-06 | EJU数学 / 吴峰 | 1 / 2 | 8500 / 17000 |
| `edcc994a-85f4-48f6-9266-fd414eceaba3` | 2026-08-07 | EJU物理 / 宋弘德 | 1 / 2 | 8500 / 17000 |
| `6f22f125-4bd3-4278-8265-b04f39b3e8c2` | 2026-08-12 | EJU日语 / 赵天歌 | 1 / 2 | 8500 / 17000 |
| `d4d261bb-5b6b-4ab5-8dc8-7a2c7d6ca5dc` | 2026-08-13 | EJU数学 / 吴峰 | 1 / 2 | 8500 / 17000 |
| `8edaeefc-9295-4da5-83a2-5f38e4beda8d` | 2026-08-14 | EJU物理 / 宋弘德 | 1 / 2 | 8500 / 17000 |
| `91020ea0-2111-4aad-98e5-1f5a720ec267` | 2026-08-19 | EJU日语 / 赵天歌 | 1 / 2 | 8500 / 17000 |
| `67477810-f00b-41bc-8205-98f60047520f` | 2026-08-20 | EJU数学 / 吴峰 | 1 / 2 | 8500 / 17000 |
| `8636f89e-e838-4d0e-89c1-4953b5596bda` | 2026-08-21 | EJU物理 / 宋弘德 | 1 / 2 | 8500 / 17000 |
| `99c11176-0e31-4a2f-95cd-2999e1877c28` | 2026-08-26 | EJU日语 / 赵天歌 | 1 / 2 | 8500 / 17000 |
| `6f9e97c2-12d3-4ec4-96e6-dedd2707c321` | 2026-08-27 | EJU数学 / 吴峰 | 1 / 2 | 8500 / 17000 |
| `0f6e6dba-1ba4-4117-8dee-7fe06842abcd` | 2026-08-28 | EJU物理 / 宋弘德 | 1 / 2 | 8500 / 17000 |
| `bcb98247-a630-458b-95bf-de91c249c1ef` | 2026-09-02 | EJU日语 / 赵天歌 | 1 / 2 | 8500 / 17000 |
| `e1b67843-469c-473a-82fa-23aa8c2df260` | 2026-09-03 | EJU数学 / 吴峰 | 1 / 2 | 8500 / 17000 |
| `44641bf9-c445-4bf8-b35d-d9f20c33e206` | 2026-09-04 | EJU物理 / 宋弘德 | 1 / 2 | 8500 / 17000 |

Void 后 15 条 active claim 已释放；历史 relation 保留。只读删除核对发现页面 guard 会显示删除，但正式 `school_delete_fresh_planned_lesson(...)` 因旧 bill snapshot 保留而逐行拒绝，稳定原因为“该预定课时已进入学生学费应收快照，不能删除”。不得删除历史 relation/旧 revision 来绕过。July 最新 reconciliation 同时确认 1.75h/JPY14,875 净履约差成立，但现有 planned-receivable 合同权威 carry 为 `+92.44`；在删除合同与结算差异获得新业务决定前，不执行 lesson writer、settlement lock 或 Reissue。

## 李天伦

### Void 前冻结事实（历史基线）

| 字段 | 只读事实 |
|---|---|
| student | `a7b163a0-201e-4867-9b94-372343356a80` |
| generation / revision | `96000000-0000-4000-8000-202608030011` / `96000000-0000-4000-8000-202608031011` |
| revision | `1 / atomic_generation_v1 / active` |
| manifest | `bf7d219c70cf8904824a5a318a46ef90ed0b02a198921624b6682ec61eed702e` |
| bill | `5e032651-f3b0-40f9-b1ad-6bcce4e6fb93 / income_created` |
| income | `1de45ea6-6cf7-45d9-9df5-1275bf5051d4 / pending` |
| frozen money | currency `JPY`；JPY `352000`；rate `0.0427`；carry `0`；CNY `15030.40` |
| previous settlement | UUID `NULL`；status `ABSENT`；previous month `2026-07` |
| relation | 16 rows；lesson_count 合计 21；JPY `352000`；relation hash `0f14f7182a2cf8adbe03b1042e7a7bd4` |
| Cash / downstream | request `0`；CNY transaction `0`；JPY transaction `0`；School linkage/account transaction/actual/wage facts均 `0` |
| validators | identity、bill-income、bill-lessons、generation-revision：`4/4 PASS` |
| Void preflight | Edge `preflight_only ok=true`；School eligible；blocker `NULL`；active source claims 16 |
| 永久冻结 | revision 1、旧 bill/income、relation、snapshot、manifest 保留；当前不存在被该 bill 历史消费的 July settlement |

July DB-authoritative preview：rate `0.05`；planned `20h / JPY260000 / CNY13000`；actual `0`；received `JPY260000 / equivalent CNY13000`；final due / locked carry `0`；draft/adjustment/carryover均 0。数据库已证明当前 July 无结算金额；不为了形式创建无业务意义的零金额 settlement。August bill 已明确冻结 zero carry，因此不创建 July settlement不影响按当前事实 Reissue。

当前 16 条 frozen relation 均为 `planned / planned / billable=true`，当前行与 frozen line 一致：

| lesson UUID | 日期 | 科目 / 老师 | count / hours | unit / fee |
|---|---|---|---:|---:|
| `42e48eb1-4ce7-420e-a17c-d42080d20101` | 2026-08-03 | EJU日语 / 赵天歌 | 2 / 2 | 11000 / 22000 |
| `61172854-98d8-4069-bcfb-c2904b4316b4` | 2026-08-03 | EJU日语 / 赵天歌 | 1 / 2 | 11000 / 22000 |
| `40b45df8-6ed3-4ccd-9ffd-25fb06de18fe` | 2026-08-10 | EJU数学 / 吴峰 | 1 / 2 | 11000 / 22000 |
| `514e1578-00fc-4291-b135-704f8193b5b4` | 2026-08-10 | EJU日语 / 赵天歌 | 2 / 2 | 11000 / 22000 |
| `6068a0c1-7d2a-49a3-b659-35cf998e0b15` | 2026-08-10 | EJU日语 / 赵天歌 | 1 / 2 | 11000 / 22000 |
| `f71185d0-92d0-4d73-8b0e-ea5c56ea7c49` | 2026-08-10 | EJU文综 / 高若天 | 1 / 2 | 11000 / 22000 |
| `155dc1c7-f9d1-4cef-bcc1-4894f4b6837a` | 2026-08-17 | EJU日语 / 赵天歌 | 2 / 2 | 11000 / 22000 |
| `886373fa-bfd3-4016-b4f7-f9d4f3f14f51` | 2026-08-17 | EJU日语 / 赵天歌 | 1 / 2 | 11000 / 22000 |
| `0667c085-73ae-495e-ad05-e29ae98ca5cb` | 2026-08-24 | EJU文综 / 高若天 | 1 / 2 | 11000 / 22000 |
| `1ff01de9-c67f-49ff-a3cd-6cadf0e108cf` | 2026-08-24 | EJU日语 / 赵天歌 | 1 / 2 | 11000 / 22000 |
| `538ee794-8185-4d42-ac48-a44a7ce8cca6` | 2026-08-24 | EJU数学 / 吴峰 | 1 / 2 | 11000 / 22000 |
| `7fe11097-509e-469e-9fbe-301412c9a0e9` | 2026-08-24 | EJU日语 / 赵天歌 | 2 / 2 | 11000 / 22000 |
| `50c6cedc-1433-4e3c-b4a0-7e54e11a44d8` | 2026-08-31 | EJU日语 / 赵天歌 | 2 / 2 | 11000 / 22000 |
| `61e9b683-9bff-4c30-9174-a4ad3463f430` | 2026-08-31 | EJU数学 / 吴峰 | 1 / 2 | 11000 / 22000 |
| `6ce1da2f-0621-4ceb-ace4-b9994ef21fb1` | 2026-08-31 | EJU文综 / 高若天 | 1 / 2 | 11000 / 22000 |
| `8eacbb08-ea3a-4b5d-9f62-fc772a36d31c` | 2026-08-31 | EJU日语 / 赵天歌 | 1 / 2 | 11000 / 22000 |

Void 后 16 条 active claim 已释放；历史 relation 保留。逐行核对同样确认页面 guard 会显示删除，但 DB 因旧 bill snapshot 永久证据全部拒绝。July settlement/draft/adjustment仍不存在，preview carry 仍为 0，不创建零金额 settlement。删除合同获得新业务决定并完成合法课时修改前，不执行 Reissue。

## 张倬闻

### 核心事实

| 字段 | 只读事实 |
|---|---|
| student | `7aef8061-7037-4881-a847-a2cdb031c0f4` |
| generation / revisions | `96000000-0000-4000-8000-202608030009` / rev1 `96000000-0000-4000-8000-202608031009` / rev2 `7d319b0d-8f62-41e9-95bf-c1a0c6ed7090` |
| revision state | rev1 `voided`；rev2 `atomic_generation_v1 / active / previous=rev1` |
| manifests | old `3aaa288b6b4edfcd3c897f36c7f6ffb638553ed9e566a68041457036a9773f38`；new `a35fa72406378c94c1d92574aaa054f46628057175e47155beafd5d704e3a677` |
| bills | old `553a24ba-81cf-4af0-b723-169a09914c79 / cancelled`；new `013a7766-101b-4b5b-bcae-c008825b14fa / income_created` |
| incomes | old `be64a9e2-f15e-44b0-a9de-2ee91bdf9567 / cancelled`；new `d980cedd-ebba-4be1-afcb-b25dfa26798a / pending` |
| active frozen money | JPY `650000`；rate `0.043`；historical carry `107.50`；forward adjustment `-107.50`；CNY `27950.00` |
| previous settlement | `b699209d-2f61-4cfa-959b-45686e2fe19b / unlocked`；system difference `107.50`；carry `107.50`；后于 2026-08-02 异常 unlock |
| relation | old 30 rows永久保留；new active 30 rows；lesson_count 合计35；JPY `650000`；lesson业务行未修改 |
| Cash / downstream | request `0`；CNY transaction `0`；JPY transaction `0`；School linkage/account transaction/actual/wage facts均 `0` |
| validators | rev2四个 tuition validators + adjustment validator：全部 PASS |
| Void / P0-E | void event `03ec26aa-fedb-4f18-861a-956acb771f83`；adjustment `df043dee-0013-4fb6-b31f-0ea5f446bbc1`；duplicate idempotent=true |
| 永久冻结 | July settlement继续受 Rule B 永久冻结；Cash未提交；Gate未开启 |

当前 30 条 relation 均为 `planned / planned / billable=true`，aircon 0；每行 unit `10000`，TOEFL 3h/JPY30000，其余 2h/JPY20000：

| lesson UUID | 日期 | 科目 / 老师 | count / hours / fee |
|---|---|---|---:|
| `23d4b46b-eb1c-48b7-8001-d208ce14f08d` | 2026-08-03 | EJU日语 / 赵天歌 | 1 / 2 / 20000 |
| `637ba833-830f-42a6-81ed-47a6f9902523` | 2026-08-03 | EJU数学 / 吴峰 | 1 / 2 / 20000 |
| `7175780c-b179-4f96-a42e-99ba11bdaed8` | 2026-08-03 | EJU物理 / 田宇辰 | 1 / 2 / 20000 |
| `80384c28-5044-4c56-94cd-5099aa852032` | 2026-08-03 | EJU日语 / 赵天歌 | 2 / 2 / 20000 |
| `920808f2-5629-4fcc-957c-6bdcee48808e` | 2026-08-03 | TOEFL / 李雯coco | 1 / 3 / 30000 |
| `d06f136e-d4c5-44fb-ae5e-d87efa26bbfb` | 2026-08-03 | EJU化学 / 王黎曦 | 1 / 2 / 20000 |
| `3db3ad8b-44b6-4be7-a3ea-611362b82488` | 2026-08-10 | EJU物理 / 田宇辰 | 1 / 2 / 20000 |
| `6997acdc-fec4-4e14-a22b-d9f5291b1e0b` | 2026-08-10 | EJU化学 / 王黎曦 | 1 / 2 / 20000 |
| `69ecc019-9f8f-474e-8dc9-1dced16e41a6` | 2026-08-10 | EJU日语 / 赵天歌 | 1 / 2 / 20000 |
| `72ffebba-ecb3-4a96-9550-f02a5f64cf62` | 2026-08-10 | TOEFL / 李雯coco | 1 / 3 / 30000 |
| `c0e9fd95-7833-44ef-a282-61611976b089` | 2026-08-10 | EJU数学 / 吴峰 | 1 / 2 / 20000 |
| `e6aaf546-bb9c-4e71-980e-40f78f2e1e11` | 2026-08-10 | EJU日语 / 赵天歌 | 2 / 2 / 20000 |
| `12d70ee9-8221-4b8e-a01c-61548340c42d` | 2026-08-17 | EJU数学 / 吴峰 | 1 / 2 / 20000 |
| `1927b6ba-6ca6-4ef9-b1c0-0246067c7d41` | 2026-08-17 | EJU日语 / 赵天歌 | 2 / 2 / 20000 |
| `3920fdea-2f9d-4b17-abd0-f788b0d7d29e` | 2026-08-17 | TOEFL / 李雯coco | 1 / 3 / 30000 |
| `95dff1ab-544d-43be-bc0e-a95232f06935` | 2026-08-17 | EJU日语 / 赵天歌 | 1 / 2 / 20000 |
| `a10744fc-173a-4b25-9bc3-99d6437797c5` | 2026-08-17 | EJU物理 / 田宇辰 | 1 / 2 / 20000 |
| `a601916b-6add-4be6-adcc-5c232425f686` | 2026-08-17 | EJU化学 / 王黎曦 | 1 / 2 / 20000 |
| `286344d1-c603-4990-aba3-814996535319` | 2026-08-24 | EJU数学 / 吴峰 | 1 / 2 / 20000 |
| `9a76aed4-058f-4801-90b5-b2637387fb3e` | 2026-08-24 | TOEFL / 李雯coco | 1 / 3 / 30000 |
| `9f755093-8f4d-4337-80ed-23d0e555c835` | 2026-08-24 | EJU日语 / 赵天歌 | 2 / 2 / 20000 |
| `e2540bb3-5c1f-45bc-b964-9727a6ed3e48` | 2026-08-24 | EJU化学 / 王黎曦 | 1 / 2 / 20000 |
| `ee6c1383-4259-44e0-923c-1ee6b8749820` | 2026-08-24 | EJU物理 / 田宇辰 | 1 / 2 / 20000 |
| `ee86e691-2c96-48c2-ad57-512f9eef4b3c` | 2026-08-24 | EJU日语 / 赵天歌 | 1 / 2 / 20000 |
| `01490eb7-1bd7-430a-ba26-3ccc81d45796` | 2026-08-31 | EJU日语 / 赵天歌 | 2 / 2 / 20000 |
| `80e03531-5eaa-40e1-a435-0132dd62d5c0` | 2026-08-31 | EJU物理 / 田宇辰 | 1 / 2 / 20000 |
| `8c6da1a7-69a9-45b6-9a77-daa2bfd7f9e9` | 2026-08-31 | TOEFL / 李雯coco | 1 / 3 / 30000 |
| `9efe2def-ff59-467a-bb76-a49537ec8e0f` | 2026-08-31 | EJU数学 / 吴峰 | 1 / 2 / 20000 |
| `adc0b06c-eee3-40ca-8992-592f5d4b009b` | 2026-08-31 | EJU化学 / 王黎曦 | 1 / 2 / 20000 |
| `dbe16731-803b-49db-8cc0-f826e911bb41` | 2026-08-31 | EJU日语 / 赵天歌 | 1 / 2 / 20000 |

### 真实操作完成状态

P0-E 合同完成后，业务负责人另行明确授权了张倬闻真实操作。正式工具先作废错误 rate `0.042` 的 revision 1，再以 DB 权威 `neutralize_historical_carryover_v1`、rate `0.043`、historical carry `107.50`、forward adjustment `-107.50` 创建 revision 2，最终 pending income 为 CNY `27950.00`。July settlement 未修改，仍显示“已被历史学费账单消费（不可重开）”。普通 Reissue fail-closed、P0-E duplicate idempotency、五个 validators、School/Cash 哈希均已验收。完整证据见 `docs/school-v2-zhang-zhuowen-202608-tuition-void-p0e-reissue-operation-20260803.md`。

## 彭宇晗、李天伦真实 Void 完成状态

- 彭宇晗 void event：`48dbdd0d-0934-4270-a6cb-230537bee86f`；李天伦 void event：`9af7d2b3-7905-4dd6-a325-515ca22a304e`。两次 duplicate 均稳定零写入拒绝，没有第二条事件。
- 两人 old revision/bill/income/relation/snapshot/manifest 全部保留；active revision 与 active claim 均为 0；lesson 全表 `730 / 034d3ee24d639e587447a9458244797c`、settlement 全表 `17 / 85c829ebc3bb0a4100393d9c8d6421d7` 不变。
- 详细证据见 `docs/school-v2-peng-li-202608-tuition-void-operation-20260803.md` 与 `docs/school-v2-peng-yuhan-202607-settlement-reconciliation-20260803.md`。

## 最终操作纪律

- 彭宇晗与李天伦的专用 Void 已完成；二人的 lesson 删除均被历史 bill snapshot guard 阻止，不得直接尝试页面删除或清除历史证据。
- 彭宇晗 July 的 `-624.75` 不是现有 DB 合同结果；唯一合同 mode 为 `carry_final_balance`，当前结果 `+92.44`，但在业务差异调查完成前不得锁定。
- 张倬闻的单独授权操作已完成；不得据此继续提交 Cash，也不得外推为彭宇晗或李天伦的授权。
- 任一未来 lesson/settlement/Reissue 操作必须获得新的精确业务授权，重新执行 DB preview/preflight/validators，并以当时 exact facts/manifests 为准。
- 不得自动调用 lesson writer、settlement writer、Reissue、Cash writer 或 Gate writer。
