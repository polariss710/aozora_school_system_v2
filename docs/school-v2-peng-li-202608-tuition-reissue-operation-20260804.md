# 彭宇晗、李天伦 2026-08 Atomic Tuition 最终真实 Reissue 操作报告

日期：2026-08-04

## 结论

经业务负责人明确授权，彭宇晗与李天伦的 2026-08 Atomic Tuition 已分别通过本机受信管理工具完成普通 Reissue。两人均生成唯一 active revision 2、唯一新 bill 与 pending income；旧 revision 1、旧 bill/income、void event、历史 relation、snapshot 与 manifest 全部保留。

| 学生 | revision 2 | bill | pending income | JPY | carry CNY | final CNY |
|---|---|---|---|---:|---:|---:|
| 彭宇晗 | `49e530ee-d190-45e2-8f2f-24b16713b194` | `bcd482dd-f376-4791-9862-a0ecbc0ba956` | `363ac949-7315-4207-8d75-ebab1a0623f2` | 204,000 | -624.75 | 7,841.25 |
| 李天伦 | `8002e02c-a556-4161-bf01-6532f0eae0dd` | `872cc6d3-c524-4566-ad3c-a02f7987a412` | `acdd46db-0d44-4860-8c6d-672ea0b546bc` | 220,000 | 0.00 | 9,394.00 |

彭宇晗的新 revision 精确引用已锁定的 July settlement `6ec3b815-5540-44bd-88ee-9e30a5284770`，消费其 DB 权威 carry `-624.75`；未创建 P0-E generation adjustment。李天伦的 previous settlement 为 `NULL`，carry 为 0，未创建无意义的 July settlement。两次重复执行均返回同一组对象并标记幂等，没有新增第二组业务记录。

## 授权与边界

- 生产基线：`993909e9b11b3dcd804489839ef56c42aecb567b`。
- 本轮只允许彭宇晗、李天伦的普通 Atomic Reissue。
- 未修改 lesson、settlement、draft、claim、P0-E adjustment、Cash、Gate 或张倬闻链。
- 未执行 generic generation、generic cancellation、直接 DML 或 SQL 数据修复。
- 本轮没有测试数据写入，也没有 whitelist fixture；真实业务写入仅为两人的 Reissue 输出。

## 工具路由修复

正式 dry-run 前发现 `scripts/manage-atomic-tuition.zsh reissue-preview` 无条件调用 P0-E preview，导致彭宇晗普通 Reissue 的只读 preview 被错误路由并返回 `TUITION_P0E_HISTORICAL_CARRY_REQUIRED`。该调用在函数写入前失败，数据库写入为 0。

修复后：

- 普通 Reissue preview 调用既有 DB 权威 `school_build_student_tuition_generation_snapshot`；
- 只有显式 P0-E mode 才调用 P0-E preview；
- 页面或脚本不计算金额、carry 或 manifest；
- `zsh -n scripts/manage-atomic-tuition.zsh`、P0-E static test、P0-D local management static test 均通过。

工具修复提交：`09d414a`，parent 为生产基线 `993909e9b11b3dcd804489839ef56c42aecb567b`。该修复没有 schema、RPC 或业务模型扩展；Business-model expansion declaration 全部为 `none`。

## 操作前权威事实

### 彭宇晗

- student：`eb705aad-de4d-45e6-a391-42dcdd89aeda`
- generation：`96000000-0000-4000-8000-202608030013`
- revision 1：`96000000-0000-4000-8000-202608031013 / voided`
- old bill/income：`1e02dc09-8f42-4a93-85c6-e27809d68a83 / cancelled`、`ae4d8b66-491b-4db2-ac91-86765f56155c / cancelled`
- void event：`48dbdd0d-0934-4270-a6cb-230537bee86f`，恰好 1 条
- active revision / active candidate claim：0 / 0
- locked July settlement：`6ec3b815-5540-44bd-88ee-9e30a5284770`
- July 权威事实：rate `0.042`；net unused `-JPY14,875`；carry `-CNY624.75`；两条 immutable source claim；既有 consumer 0
- current generation Cash request/CNY/JPY transaction、School linkage/account transaction：全部 0
- 四个 validator：全部通过

### 李天伦

- student：`a7b163a0-201e-4867-9b94-372343356a80`
- generation：`96000000-0000-4000-8000-202608030011`
- revision 1：`96000000-0000-4000-8000-202608031011 / voided`
- old bill/income：`5e032651-f3b0-40f9-b1ad-6bcce4e6fb93 / cancelled`、`1de45ea6-6cf7-45d9-9df5-1275bf5051d4 / cancelled`
- void event：`9af7d2b3-7905-4dd6-a325-515ca22a304e`，恰好 1 条
- active revision / active candidate claim：0 / 0
- July settlement：0；DB preview carry `0`
- current generation Cash request/CNY/JPY transaction、School linkage/account transaction：全部 0
- 四个 validator：全部通过

## DB 权威 Preview 与候选集合

### 彭宇晗

- candidate：12 行 / 12 lessons / 24h / JPY204,000
- rate：`0.0415`
- previous carry：`-624.75`
- final amount：`CNY7,841.25`
- candidate manifest：`51fd7e9750cac88b917d6c94a7fa5f7fce1956efff5c89814941bb704c30bfa3`
- generation manifest：`bf0edf6f19dc1af514530b719d9eb93da1c8b81b66dfe3ce1316baff23f3b18b`
- candidate UUID MD5：`77b09157fb956ce0f610fce17fb46b82`

| lesson UUID | 日期 | billing week | 科目 / 老师 | count | hours | unit / fee JPY |
|---|---|---|---|---:|---:|---:|
| `d147d783-8c20-4d9e-bb94-03ea03c19a21` | 2026-08-05 | 2026-08-03 | EJU日语 / 赵天歌 | 1 | 2 | 8,500 / 17,000 |
| `79502518-0c0d-4025-87e8-58e2177ae3dd` | 2026-08-06 | 2026-08-03 | EJU数学 / 吴峰 | 1 | 2 | 8,500 / 17,000 |
| `edcc994a-85f4-48f6-9266-fd414eceaba3` | 2026-08-07 | 2026-08-03 | EJU物理 / 宋弘德 | 1 | 2 | 8,500 / 17,000 |
| `91020ea0-2111-4aad-98e5-1f5a720ec267` | 2026-08-19 | 2026-08-17 | EJU日语 / 赵天歌 | 1 | 2 | 8,500 / 17,000 |
| `67477810-f00b-41bc-8205-98f60047520f` | 2026-08-20 | 2026-08-17 | EJU数学 / 吴峰 | 1 | 2 | 8,500 / 17,000 |
| `8636f89e-e838-4d0e-89c1-4953b5596bda` | 2026-08-21 | 2026-08-17 | EJU物理 / 宋弘德 | 1 | 2 | 8,500 / 17,000 |
| `99c11176-0e31-4a2f-95cd-2999e1877c28` | 2026-08-26 | 2026-08-24 | EJU日语 / 赵天歌 | 1 | 2 | 8,500 / 17,000 |
| `6f9e97c2-12d3-4ec4-96e6-dedd2707c321` | 2026-08-27 | 2026-08-24 | EJU数学 / 吴峰 | 1 | 2 | 8,500 / 17,000 |
| `0f6e6dba-1ba4-4117-8dee-7fe06842abcd` | 2026-08-28 | 2026-08-24 | EJU物理 / 宋弘德 | 1 | 2 | 8,500 / 17,000 |
| `bcb98247-a630-458b-95bf-de91c249c1ef` | 2026-09-02 | 2026-08-31 | EJU日语 / 赵天歌 | 1 | 2 | 8,500 / 17,000 |
| `e1b67843-469c-473a-82fa-23aa8c2df260` | 2026-09-03 | 2026-08-31 | EJU数学 / 吴峰 | 1 | 2 | 8,500 / 17,000 |
| `44641bf9-c445-4bf8-b35d-d9f20c33e206` | 2026-09-04 | 2026-08-31 | EJU物理 / 宋弘德 | 1 | 2 | 8,500 / 17,000 |

### 李天伦

- candidate：10 行 / lesson count 合计 15 / 20h / JPY220,000
- rate：`0.0427`
- previous carry：`0`
- final amount：`CNY9,394.00`
- candidate manifest：`56348ea803f4f992be3586bb5ff8aeabee3a2463f86d548477da425a148b23be`
- generation manifest：`e9e5b315e49b67e6eaaa29631d98d7f497ec8a333cd162f2104a305bee6c4552`
- candidate UUID MD5：`568982e3beb9c14319d0505b8df1ae85`

| lesson UUID | 日期 | billing week | 科目 / 老师 | count | hours | unit / fee JPY |
|---|---|---|---|---:|---:|---:|
| `42e48eb1-4ce7-420e-a17c-d42080d20101` | 2026-08-03 | 2026-08-03 | EJU日语 / 赵天歌 | 2 | 2 | 11,000 / 22,000 |
| `61172854-98d8-4069-bcfb-c2904b4316b4` | 2026-08-03 | 2026-08-03 | EJU日语 / 赵天歌 | 1 | 2 | 11,000 / 22,000 |
| `514e1578-00fc-4291-b135-704f8193b5b4` | 2026-08-10 | 2026-08-10 | EJU日语 / 赵天歌 | 2 | 2 | 11,000 / 22,000 |
| `6068a0c1-7d2a-49a3-b659-35cf998e0b15` | 2026-08-10 | 2026-08-10 | EJU日语 / 赵天歌 | 1 | 2 | 11,000 / 22,000 |
| `155dc1c7-f9d1-4cef-bcc1-4894f4b6837a` | 2026-08-17 | 2026-08-17 | EJU日语 / 赵天歌 | 2 | 2 | 11,000 / 22,000 |
| `886373fa-bfd3-4016-b4f7-f9d4f3f14f51` | 2026-08-17 | 2026-08-17 | EJU日语 / 赵天歌 | 1 | 2 | 11,000 / 22,000 |
| `1ff01de9-c67f-49ff-a3cd-6cadf0e108cf` | 2026-08-24 | 2026-08-24 | EJU日语 / 赵天歌 | 1 | 2 | 11,000 / 22,000 |
| `7fe11097-509e-469e-9fbe-301412c9a0e9` | 2026-08-24 | 2026-08-24 | EJU日语 / 赵天歌 | 2 | 2 | 11,000 / 22,000 |
| `50c6cedc-1433-4e3c-b4a0-7e54e11a44d8` | 2026-08-31 | 2026-08-31 | EJU日语 / 赵天歌 | 2 | 2 | 11,000 / 22,000 |
| `8eacbb08-ea3a-4b5d-9f62-fc772a36d31c` | 2026-08-31 | 2026-08-31 | EJU日语 / 赵天歌 | 1 | 2 | 11,000 / 22,000 |

## 已作废课时排除证据

以下 9 条均为 `voided_planned_excluded`，未进入新 candidate、relation 或金额：

- 彭宇晗：`6f22f125-4bd3-4278-8265-b04f39b3e8c2`、`d4d261bb-5b6b-4ab5-8dc8-7a2c7d6ca5dc`、`8edaeefc-9295-4da5-83a2-5f38e4beda8d`。
- 李天伦：`40b45df8-6ed3-4ccd-9ffd-25fb06de18fe`、`f71185d0-92d0-4d73-8b0e-ea5c56ea7c49`、`0667c085-73ae-495e-ad05-e29ae98ca5cb`、`538ee794-8185-4d42-ac48-a44a7ce8cca6`、`61e9b683-9bff-4c30-9174-a4ad3463f430`、`6ce1da2f-0621-4ceb-ace4-b9994ef21fb1`。

旧 revision 的 15/16 条 relation 继续作为不可删除历史证据存在；它们不等于新 active revision claim。新 active relation 分别精确为 12/10 条，且与 candidate manifest 一致。

## 正式执行与幂等验收

两人均依次执行 `status`、`history`、`reissue-preview`、`reissue` 默认 dry-run，并使用工具刚返回的 exact expected facts、manifest 与确认文本调用 `reissue --execute`。命令中的 URL、JWT、service-role 与数据库连接信息均未打印、落盘或提交。

正式 writer RPC：`school_reissue_atomic_student_tuition_generation_local`。结果：

- 彭宇晗 revision 2 唯一 active；12 条新 relation；bill/income 状态 `income_created/pending`；previous revision 与 July settlement 引用精确；四个 validator 全通过。
- 李天伦 revision 2 唯一 active；10 条新 relation且 lesson count 合计15；previous settlement 为 NULL；四个 validator 全通过。
- 两人 duplicate execute 均返回 `idempotent=true` 和原 revision/bill/income UUID；行数不再增加。
- 彭宇晗 settlement consumer resolver 返回新 bill `bcd482dd-f376-4791-9862-a0ecbc0ba956`，证明 July carry 已被唯一消费并受永久冻结合同保护。
- 两人新链均无 voided lesson relation、P0-E adjustment、Cash linkage 或 School account transaction。

## 数据保护与前后指纹

| School 对象 | before | after | 结果 |
|---|---|---|---|
| lesson | `731 / f3cb7c99e78b9fb26b5d557c53dc4f20` | 同前 | 不变 |
| settlement | `18 / 481ffa7ed5173da852f0f28ce66c2e9b` | 同前 | 不变 |
| generation identity | `15 / 60f11efc1aebad6b182f7d0da08d36d7` | 同前 | 不变 |
| generation revision | `16 / 3fb1700c806e58cb0f8a75358a09dbd5` | `18 / 6756c752736bce391c661b3ba15e564b` | 仅新增两条 rev2 |
| bill | `18 / bc7fe1fc6d904c5f6a0380583e430c9e` | `20 / 73d412333a7885fac4673a8fff8a78a4` | 仅新增两张 bill |
| income | `51 / 4468607bc30770376ce6aaca9016e598` | `53 / 85b19ec34c40a59a52c852a5e9f959a4` | 仅新增两条 pending income |
| bill relation | `286 / b3911d2a45c6b1ac98ba24254c2b619d` | `308 / 4603f7c51250f39f7e2d366a5e76cedb` | 仅新增 22 条 active relation |
| generation adjustment | `1 / 30304a8ab7a3edbe796b5528512ac242` | 同前 | 不变 |
| void event | `3 / 77cdf1ea30ebd54801c6ce2b392bf73a` | 同前 | 不变 |
| settlement draft/adjustment/claim | `7/1/2`及各原 hash | 同前 | 不变 |
| School Cash linkage/account transaction | `40/186`及各原 hash | 同前 | 不变 |

Cash DB request/CNY/JPY transaction 前后分别保持：

- `39 / 303e10bc1a28a0abd8b27afd3929cfd8`
- `71 / d7e72182970de4ea8849c994b67e8dcc`
- `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`

Gate 前后均为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=blocked`。张倬闻 revision 2 仍是唯一 active，income 仍为 pending CNY27,950，Cash/downstream 仍为0。孙陈锋既有 actual `e72edbd9-...` 及 lesson 全表 hash 保持不变。

## 精确写入范围

真实生产写入仅包括：2 条 revision、2 张 bill、2 条 pending income、22 条 relation，以及对应 immutable snapshot/manifest 元数据。以下写入为 0：lesson、settlement/draft/claim、adjustment/carryover、Void、P0-E、Cash request/transaction、School linkage/account transaction、Gate、张倬闻及其他学生。

没有执行 SQL 文件，没有部署或修改数据库函数/ACL/RLS。只读调用包括普通 generation snapshot preview、status/history/preflight 与 validators；唯一真实 writer 是上述两次目标学生 Reissue，另有各一次幂等重复验收。

## Git 与受保护文件

- baseline：`993909e9b11b3dcd804489839ef56c42aecb567b`
- tool routing fix：`09d414a`
- 文档交付提交：`PENDING_DOC_COMMIT`
- 收尾提交：`PENDING_CLOSEOUT_COMMIT`
- push：`PENDING_PUSH`

六份受保护 untracked 文件未读取改写、未 stage、未提交，最终 SHA-256 仍为：

- `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

## 终态

两人的 Reissue 已完成，现均等待业务负责人审核 pending income 后另行决定是否提交 Cash。本任务不构成 Cash 提交授权；Gate 继续关闭 generate 与 cash submit。
