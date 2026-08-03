# P0-D 三名真实学生最终只读操作前检查

日期：2026-08-03。本文只记录生产只读事实，不授权或执行真实 Void、Reissue、课时编辑、settlement 或 Cash 提交。三人目标账期均为 `2026-08`；真实业务写入均为 0。

## 分流结论

| 学生 | Void 技术条件 | July settlement | 仍缺输入 | Reissue / 当前 Go-No-Go |
|---|---|---|---|---|
| 彭宇晗 | School eligible、Cash/downstream 0；技术可行，但尚无真实执行授权 | 当前不存在；active August zero-carry claim 期间被 Rule A 冻结；Void 后可创建/锁定，DB 当前 preview carry `92.44` | 业务负责人必须给出精确 lesson UUID、目标字段和值 | lesson 修改与 July lock 后必须重新取 DB preview/manifests；当前 **No-Go** |
| 李天伦 | School eligible、Cash/downstream 0；技术可行，但尚无真实执行授权 | 当前不存在；DB preview 明确 carry `0`，无业务必要时不创建零金额 settlement | 业务负责人必须给出精确 lesson UUID、目标字段和值 | Void/修改后重新取 DB preview/manifests；当前 **No-Go** |
| 张倬闻 | School eligible、Cash/downstream 0，仅说明 Void 技术前置满足 | July settlement 已被历史 revision 消费却为 `unlocked`；Rule B 永久禁止 relock/覆盖 | 不是 lesson 输入问题；缺 DB 权威 forward adjustment 合同 | 路径 1 金额虽为 `27950`，状态仍错误；必须先独立 P0-E；当前 **No-Go** |

## 彭宇晗

### 核心事实

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

Void 后这 15 条 active claims 会释放并重新进入 DB candidate 判定，但系统不能推断应改哪条。用户必须逐条提供 lesson UUID、目标字段与目标值。若课时事实不改且 July 最终锁定仍为 `92.44`，仅可做非最终投影 `255000 × 0.0415 + 92.44 = 10674.94`；实际 Reissue 金额、candidate manifest 与 generation manifest 必须在 lesson RPC 和 July lock 完成后由 DB 重新返回，当前不可作为 execute 输入。

## 李天伦

### 核心事实

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

Void 后 16 条 claim 会释放；系统仍不能推断要修改哪些 lesson。若不改任何课时，当前事实的 Reissue carry 仍为 `0`、JPY `352000`；但 execute 所需金额与 manifests 必须在用户给出精确修改并完成 RPC 后由 DB 重新生成，当前不可执行。

## 张倬闻

### 核心事实

| 字段 | 只读事实 |
|---|---|
| student | `7aef8061-7037-4881-a847-a2cdb031c0f4` |
| generation / revision | `96000000-0000-4000-8000-202608030009` / `96000000-0000-4000-8000-202608031009` |
| revision | `1 / atomic_generation_v1 / active` |
| manifest | `3aaa288b6b4edfcd3c897f36c7f6ffb638553ed9e566a68041457036a9773f38` |
| bill | `553a24ba-81cf-4af0-b723-169a09914c79 / income_created` |
| income | `be64a9e2-f15e-44b0-a9de-2ee91bdf9567 / pending` |
| frozen money | currency `JPY`；JPY `650000`；rate `0.042`；carry `107.50`；CNY `27407.50` |
| previous settlement | `b699209d-2f61-4cfa-959b-45686e2fe19b / unlocked`；system difference `107.50`；carry `107.50`；后于 2026-08-02 异常 unlock |
| relation | 30 rows；lesson_count 合计 35；JPY `650000`；relation hash `775919f454621c7c6e51736a2232b2cc` |
| Cash / downstream | request `0`；CNY transaction `0`；JPY transaction `0`；School linkage/account transaction/actual/wage facts均 `0` |
| validators | identity、bill-income、bill-lessons、generation-revision：`4/4 PASS` |
| Void preflight | Edge `preflight_only ok=true`；School eligible；blocker `NULL`；active lesson claims 30 |
| 永久冻结 | resolver 返回 bill `553a…9c79`；July settlement 曾被历史 revision 消费，故 revision Void 后仍受 Rule B 永久冻结 |

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

### 三条路径必须分开判断

1. **Void → 不恢复 July → rate 0.043 Reissue**：synthetic formal preview 已证明 carry `0`、`650000 × 0.043 = 27950.00`。但真实 July row 仍为 `unlocked`，Rule B 使其永远不能 relock。结算页面状态映射显示“锁定已撤销”，locked-only reader/report 不会把它当作已锁定结算。因此这是“金额正确、July 结算状态错误”，不可运营。
2. **Void → 恢复原 July locked snapshot 107.50 → rate 0.043 Reissue**：金额推演为 `650000 × 0.043 + 107.50 = 28057.50`；但恢复/覆盖 July 被 Rule B 明确禁止，只能作为 counterfactual，不可执行。
3. **保持历史 July locked snapshot 107.50 + August forward adjustment -107.50 + rate 0.043**：净额 `28057.50 - 107.50 = 27950.00`。这是同时满足 July 已结算、历史消费关系保留、August 等于实付、不篡改旧 revision、调整有独立审计留痕的唯一账务完整方向。

当前系统没有获批且 DB-authoritative 的 generation forward adjustment 事实，因此张倬闻必须 **No-Go**。路径 1 金额碰巧正确不能替代结算状态正确。

### P0-E 最小范围（本轮不实施）

P0-E 需由业务负责人另行逐项批准精确业务模型扩展后才能写 SQL/code：一个 DB 权威、不可变且可审计的 forward adjustment 对象/语义；明确绑定 generation/billing month/source settlement；金额 `-107.50` 必须来自业务负责人显式输入或 DB 权威计算；具备 idempotency、manifest 纳入、validator/reader 唯一 authority、共享锁、rollback/concurrency；不得改写 July settlement 或旧 revision；页面仅经 API/RPC，前端不得计算保存金额。P0-D 不自动启动 P0-E。

## 最终操作纪律

- 彭宇晗与李天伦的特殊问题互不阻断；但二人都缺精确 lesson 修改指令，因此当前均不可执行真实 Void/Reissue。
- 张倬闻的技术 preflight 通过不构成业务 Go；必须先有获批并完成的 P0-E。
- 任一未来真实操作前都要重新执行 Edge Cash preflight、School preflight、四 validator 与 DB preview，并以当时 exact manifests/amounts 为准。
- 不得自动调用任何真实 Void、lesson writer、settlement writer、Reissue、Cash writer 或 Gate writer。
