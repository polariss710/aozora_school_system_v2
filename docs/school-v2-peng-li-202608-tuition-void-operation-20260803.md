# 彭宇晗、李天伦 2026-08 学费真实 Void 操作报告

日期：2026-08-03。结论：业务负责人授权的两次专用 Void 均已成功提交。彭宇晗、李天伦各自 revision 1、旧 bill、旧 income 已成为 `voided / cancelled / cancelled`，active lesson claim 分别从 15 / 16 降为 0；两人的 lesson、settlement、Cash、School 下游与 Gate 均未修改。

## 授权与 Git 基线

- 更正后的指定基线为 `100fc0c2f49b56e52d16156419974e8ae92f297c`；操作前 HEAD 与 `origin/main` 均精确匹配。
- `b9b4332316750703b912f5d7d086ccdc699f003d` 是该基线 ancestor；中间只有合法张倬闻交付 `2d0ffe5f91e68e7f5492326453f92e83e4de980a` 与收尾 `100fc0c2f49b56e52d16156419974e8ae92f297c`，未 reset/revert/checkout/amend/rebase/覆盖。
- 张倬闻 revision 2 仍为唯一 active；新 income `d980cedd-ebba-4be1-afcb-b25dfa26798a` 仍为 `pending / CNY 27,950.00`；其 School/Cash downstream 均为 0。
- Business-model expansion：`none`。只调用 P0-C/P0-D 已批准、已部署的专用 Void 合同。
- 凭证只在受控进程内由官方 Supabase CLI 读取 canonical service-role key；未打印、落盘或提交 secret。

六份受保护 untracked 文件始终未修改：

| 文件 | SHA-256 |
|---|---|
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 操作前 exact facts

| 事实 | 彭宇晗 | 李天伦 |
|---|---|---|
| student | `eb705aad-de4d-45e6-a391-42dcdd89aeda` | `a7b163a0-201e-4867-9b94-372343356a80` |
| generation | `96000000-0000-4000-8000-202608030013` | `96000000-0000-4000-8000-202608030011` |
| revision 1 | `96000000-0000-4000-8000-202608031013` | `96000000-0000-4000-8000-202608031011` |
| manifest | `1e75fd1456114d53b5c575d27d103ec4c038675b35586576d4ec40a28c91d801` | `bf7d219c70cf8904824a5a318a46ef90ed0b02a198921624b6682ec61eed702e` |
| bill | `1e02dc09-8f42-4a93-85c6-e27809d68a83` | `5e032651-f3b0-40f9-b1ad-6bcce4e6fb93` |
| income | `ae4d8b66-491b-4db2-ac91-86765f56155c` | `1de45ea6-6cf7-45d9-9df5-1275bf5051d4` |
| status | `active / income_created / pending` | `active / income_created / pending` |
| frozen amount | JPY 255,000；rate 0.0415；carry CNY 0；CNY 10,582.50 | JPY 352,000；rate 0.0427；carry CNY 0；CNY 15,030.40 |
| relation | 15 行 / 15 课次 / JPY 255,000 | 16 行 / 21 课次 / JPY 352,000 |
| relation 全行 hash | `f85889931c02d6be0707882f3d021288` | `d1bf2ac0f33aa7ab9d87724e4df93009` |
| active claim | 15 | 16 |
| validators | identity、bill-income、bill-lessons、generation-revision：4/4 PASS | 同左：4/4 PASS |
| School downstream | linkage/account tx/actual/wage 均 0 | 同左 |
| Cash | request/CNY/JPY 均 0 | 同左 |
| preflight | `ok=true / eligible=true / blocker=NULL` | `ok=true / eligible=true / blocker=NULL` |

操作前整表 count/hash：

| 对象 | before |
|---|---|
| generation identity | `15 / 60f11efc1aebad6b182f7d0da08d36d7` |
| generation revision | `16 / aced19d1d02d4c7842a0eb364a797a09` |
| void event | `1 / 438f3b1d8a403eda5853e01174177d17` |
| generation adjustment | `1 / 30304a8ab7a3edbe796b5528512ac242` |
| bill | `18 / d7c322ddf9a24cb30451bf7553590628` |
| income | `51 / 1f8f9b86d1eb2b006f1d43fe4dbecce6` |
| bill relation | `286 / b3911d2a45c6b1ac98ba24254c2b619d` |
| lesson | `730 / 034d3ee24d639e587447a9458244797c` |
| settlement | `17 / 85c829ebc3bb0a4100393d9c8d6421d7` |
| settlement draft / adjustment / carryover | `6 / 059c5187ad6513f9501076193aa55696`；`5 / 4bce2b158d4de769d592a2d367881868`；`8 / 54133d433579c772ba76017b757c49fd` |
| Cash request / CNY / JPY | `39 / 303e10bc1a28a0abd8b27afd3929cfd8`；`71 / d7e72182970de4ea8849c994b67e8dcc`；`31 / 95ab7cf8a8d167e9b052d3fc6b64614b` |

## 正式工具 dry-run 与执行

两人分别依次运行 `status`、`history`、`void-preflight`、`void` 默认 dry-run。所有 exact expected facts 均来自当次正式工具返回，而非复用旧报告。dry-run 确认不会删除历史记录、不会调用 Cash writer，释放 relation 数分别为 15 / 16。

脱敏命令合同：

```text
manage-atomic-tuition.zsh void
  --student <student UUID> --entity 2cf7...d466 --month 2026-08
  --revision <revision UUID> --expected-revision 1
  --bill <bill UUID> --income <income UUID>
  --manifest <64-char manifest> --reason <各自授权原文>
  --execute --confirm "VOID ATOMIC TUITION <student UUID> 2026-08 REVISION 1"
```

正式结果：

| 学生 | void event | revision / bill / income | released active claims |
|---|---|---|---:|
| 彭宇晗 | `48dbdd0d-0934-4270-a6cb-230537bee86f` | `voided / cancelled / cancelled` | 15 |
| 李天伦 | `9af7d2b3-7905-4dd6-a325-515ca22a304e` | `voided / cancelled / cancelled` | 16 |

两次 duplicate Void 均由正式入口稳定返回 HTTP 409：`Void preflight failed; zero writes performed`；对应 void event count 始终各为 1，没有第二条事件。

## Void 后课时删除条件

历史 relation 仍各为 15 / 16 且 hash 不变，active claim 已全部为 0。**历史 relation 保留不等于课时仍被 active revision claim。** 但是当前页面的前置 guard 只检查 fresh planned/no actual，因此以下 31 行都会展示删除入口；正式 `school_delete_fresh_planned_lesson(...)` 还检查任意历史 bill snapshot。每一行都已存在于已作废旧 bill 的 `planned_lesson_ids`，DB 最终都会拒绝：`该预定课时已进入学生学费应收快照，不能删除。`

### 彭宇晗：15 行

| 页面确认 | lesson UUID | 日期 / billing week / month | 科目 / 老师 | count / hours / unit / fee | actual / wage / settlement | active claim | 页面 / DB |
|---|---|---|---|---:|---:|---:|---|
| □ | `d147d783-8c20-4d9e-bb94-03ea03c19a21` | 08-05 / 08-03 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `79502518-0c0d-4025-87e8-58e2177ae3dd` | 08-06 / 08-03 / 2026-08 | EJU数学 / 吴峰 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `edcc994a-85f4-48f6-9266-fd414eceaba3` | 08-07 / 08-03 / 2026-08 | EJU物理 / 宋弘德 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `6f22f125-4bd3-4278-8265-b04f39b3e8c2` | 08-12 / 08-10 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `d4d261bb-5b6b-4ab5-8dc8-7a2c7d6ca5dc` | 08-13 / 08-10 / 2026-08 | EJU数学 / 吴峰 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `8edaeefc-9295-4da5-83a2-5f38e4beda8d` | 08-14 / 08-10 / 2026-08 | EJU物理 / 宋弘德 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `91020ea0-2111-4aad-98e5-1f5a720ec267` | 08-19 / 08-17 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `67477810-f00b-41bc-8205-98f60047520f` | 08-20 / 08-17 / 2026-08 | EJU数学 / 吴峰 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `8636f89e-e838-4d0e-89c1-4953b5596bda` | 08-21 / 08-17 / 2026-08 | EJU物理 / 宋弘德 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `99c11176-0e31-4a2f-95cd-2999e1877c28` | 08-26 / 08-24 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `6f9e97c2-12d3-4ec4-96e6-dedd2707c321` | 08-27 / 08-24 / 2026-08 | EJU数学 / 吴峰 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `0f6e6dba-1ba4-4117-8dee-7fe06842abcd` | 08-28 / 08-24 / 2026-08 | EJU物理 / 宋弘德 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `bcb98247-a630-458b-95bf-de91c249c1ef` | 09-02 / 08-31 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `e1b67843-469c-473a-82fa-23aa8c2df260` | 09-03 / 08-31 / 2026-08 | EJU数学 / 吴峰 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `44641bf9-c445-4bf8-b35d-d9f20c33e206` | 09-04 / 08-31 / 2026-08 | EJU物理 / 宋弘德 | 1 / 2 / 8500 / 17000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |

### 李天伦：16 行

| 页面确认 | lesson UUID | 日期 / billing week / month | 科目 / 老师 | count / hours / unit / fee | actual / wage / settlement | active claim | 页面 / DB |
|---|---|---|---|---:|---:|---:|---|
| □ | `42e48eb1-4ce7-420e-a17c-d42080d20101` | 08-03 / 08-03 / 2026-08 | EJU日语 / 赵天歌 | 2 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `61172854-98d8-4069-bcfb-c2904b4316b4` | 08-03 / 08-03 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `40b45df8-6ed3-4ccd-9ffd-25fb06de18fe` | 08-10 / 08-10 / 2026-08 | EJU数学 / 吴峰 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `514e1578-00fc-4291-b135-704f8193b5b4` | 08-10 / 08-10 / 2026-08 | EJU日语 / 赵天歌 | 2 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `6068a0c1-7d2a-49a3-b659-35cf998e0b15` | 08-10 / 08-10 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `f71185d0-92d0-4d73-8b0e-ea5c56ea7c49` | 08-10 / 08-10 / 2026-08 | EJU文综 / 高若天 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `155dc1c7-f9d1-4cef-bcc1-4894f4b6837a` | 08-17 / 08-17 / 2026-08 | EJU日语 / 赵天歌 | 2 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `886373fa-bfd3-4016-b4f7-f9d4f3f14f51` | 08-17 / 08-17 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `0667c085-73ae-495e-ad05-e29ae98ca5cb` | 08-24 / 08-24 / 2026-08 | EJU文综 / 高若天 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `1ff01de9-c67f-49ff-a3cd-6cadf0e108cf` | 08-24 / 08-24 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `538ee794-8185-4d42-ac48-a44a7ce8cca6` | 08-24 / 08-24 / 2026-08 | EJU数学 / 吴峰 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `7fe11097-509e-469e-9fbe-301412c9a0e9` | 08-24 / 08-24 / 2026-08 | EJU日语 / 赵天歌 | 2 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `50c6cedc-1433-4e3c-b4a0-7e54e11a44d8` | 08-31 / 08-31 / 2026-08 | EJU日语 / 赵天歌 | 2 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `61e9b683-9bff-4c30-9174-a4ad3463f430` | 08-31 / 08-31 / 2026-08 | EJU数学 / 吴峰 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `6ce1da2f-0621-4ceb-ace4-b9994ef21fb1` | 08-31 / 08-31 / 2026-08 | EJU文综 / 高若天 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |
| □ | `8eacbb08-ea3a-4b5d-9f62-fc772a36d31c` | 08-31 / 08-31 / 2026-08 | EJU日语 / 赵天歌 | 1 / 2 / 11000 / 22000 | 0 / 0 / 0 | 0 | 显示删除 / snapshot拒绝 |

因此本轮发现新的操作 blocker：当前“Void 后由业务负责人在页面删除错误课时”的计划无法按现有合同完成。不得为了允许删除而删除历史 relation、旧 revision、bill、income 或 snapshot，也未在本轮修改删除 RPC/UI。需要业务负责人另行决定是否批准精确的“已作废 Atomic 历史快照存在时 fresh planned lesson 的删除语义”扩展；在此之前不要点击这些删除入口。

## Void 后全链验收

| 对象 | after | 与预期 |
|---|---|---|
| generation identity | `15 / 60f11efc1aebad6b182f7d0da08d36d7` | 不变 |
| generation revision | `16 / 3fb1700c806e58cb0f8a75358a09dbd5` | 仅两行状态/void metadata |
| void event | `3 / 77cdf1ea30ebd54801c6ce2b392bf73a` | 精确新增 2 |
| generation adjustment | `1 / 30304a8ab7a3edbe796b5528512ac242` | 不变 |
| bill | `18 / bc7fe1fc6d904c5f6a0380583e430c9e` | 仅两张 old bill cancelled metadata |
| income | `51 / 4468607bc30770376ce6aaca9016e598` | 仅两条 old income cancelled metadata |
| bill relation | `286 / b3911d2a45c6b1ac98ba24254c2b619d` | 不变 |
| lesson | `730 / 034d3ee24d639e587447a9458244797c` | 不变；insert/update/delete=0 |
| settlement | `17 / 85c829ebc3bb0a4100393d9c8d6421d7` | 不变 |
| draft / adjustment / carryover | `6 / 059c5187ad6513f9501076193aa55696`；`5 / 4bce2b158d4de769d592a2d367881868`；`8 / 54133d433579c772ba76017b757c49fd` | 全部不变 |
| Cash request / CNY / JPY | `39 / 303e10bc1a28a0abd8b27afd3929cfd8`；`71 / d7e72182970de4ea8849c994b67e8dcc`；`31 / 95ab7cf8a8d167e9b052d3fc6b64614b` | 全部不变；目标 count 0/0/0 |

两人 active revision 均为 0；old revision/bill/income、31 条 relation、snapshot、manifest 全部保留；四个 validator 继续全部通过。School linkage/account transaction 均为 0。Gate 终态继续为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=blocked`。

## SQL/RPC、写入与 Git 交付

- 正式调用：管理工具 `status/history/void-preflight/void`；Edge `void-atomic-tuition-generation`；School `school_get_atomic_tuition_void_preflight(...)`、专用 `school_void_atomic_student_tuition_generation_local(...)` 与四个 validators。两次 duplicate 为稳定零写入拒绝。
- 临时 SQL：`/private/tmp/peng_li_void_pre_baseline.sql`、`peng_li_cash_pre_baseline.sql`、`peng_li_readonly_catalog.sql`、`peng_li_readonly_reconciliation.sql`、`peng_july_compact_readonly.sql`、`peng_july_cash_readonly.sql`、`peng_li_post_compact_readonly.sql`、`peng_li_cash_post_compact_readonly.sql`、`peng_li_reconstruct_pre_hash.sql`、`revision_columns_readonly.sql`；全部 `SELECT`/`BEGIN READ ONLY`，未执行 repo SQL 文件。
- School 真实写入精确为：两条 revision active→voided；两张 bill income_created→cancelled；两条 income pending→cancelled；新增上述两条 void event。测试/白名单写入 0，测试记录 ID 不适用。
- 本轮 lesson、settlement/draft/adjustment/carryover、Reissue、P0-E adjustment、Cash request/transaction、School account transaction、Gate、张倬闻写入均为 0。
- Git 操作文档 commit：`1bfb7e2976db3b463291ad12690693672d04f134`；parent：`100fc0c2f49b56e52d16156419974e8ae92f297c`。该 commit 后 status 仅为原六份受保护 untracked 文件。本条 Git 结果回填由紧随其后的收尾 commit 记录；两次提交均已普通推送 `origin/main`，最终 HEAD 以 Git history 与任务回执为准。六份受保护文件未纳入提交。

最终状态：两次 Void 已完成；后续 lesson 删除因历史 bill snapshot guard **No-Go**；本任务在只读核对、报告与 Git 交付后停止，不执行 Reissue 或 Cash。
