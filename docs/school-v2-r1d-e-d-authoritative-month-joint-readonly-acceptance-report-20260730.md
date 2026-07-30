# R1D-E-D 权威学生月联合只读验收报告

## 1. 结论与范围

R1D-E-D 联合只读验收通过。当前 School planned writer、actual writer、settlement resolver、summary/preview/blocker 与 15 个 locked snapshot 形成同一权威学生月闭环：

`planned writer → planned student month → actual source inheritance → resolver/set helper → summary/preview/blocker/locked reader`

本阶段只新增联合只读验收 SQL 与本报告；未修改任何既有文件、页面、JS、API、writer、reader、candidate、`docs/current-status.md` 或数据库对象。未执行 rollback tests，未调用 lock/unlock/relock/draft adjustment/assert 或任何写 RPC，未连接 Cash DB，未进入 S1-B、R0 解除、空调费、venue 或页面阶段。

## 2. Git 权威基线

- branch：`main`
- 开始时 HEAD / origin/main：`c07311d83d14cb0d099e2b0d9610dcd1106f4d7a`
- 开始时暂存区：空
- 开始时唯一未跟踪文件：`docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`
- 保护文件未读取正文、未修改、未移动、未暂存；SHA-256：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- 本阶段 Git add / commit / push / amend / stash / clean / reset：均为 0

## 3. 只读事务与执行纪律

所有数据库验收均使用：

```text
psql -X "$SCHOOL_SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <file>
```

环境加载只用于取得 School DB 变量；未引用、打印或连接 Cash DB。联合 SQL 显式执行：

```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
...
ROLLBACK;
```

两次最终同字节执行均输出：

- `transaction_isolation = repeatable read`
- `transaction_read_only = on`
- `txid_current_if_assigned() IS NULL = true`
- 结尾 `ROLLBACK`

因此数据库业务写入 0、测试数据写入 0、数据库对象写入 0、测试记录 ID 不适用。

## 4. 执行命令、次数与结果

数据库 `psql -f` 共建立 10 次 School DB 连接：

1. F1 postdeploy，1 次：在跨阶段旧断言处停止，连接关闭回滚。
2. E-B2 postdeploy，1 次：在跨阶段旧断言处停止，连接关闭回滚。
3. E-C postdeploy，2 次：初始权威复核与最终新连接零变化复核均通过并显式 `ROLLBACK`。
4. R1D-E-D 联合 SQL，6 次：前 3 次因验收脚本自身问题停止并回滚；第 4 次通过；固化 planned writer/trigger hash 后，最终同字节 SQL 连续 2 次通过并显式 `ROLLBACK`。

三个既有 postdeploy 文件 SHA-256：

- F1：`c9ccd49ac17ae6b8b61d233916d6127b29de954e86c9dd0476234de0a419b984`
- E-B2：`cb1e6f47e7efa2ecefbecfe65fe6be97697e3aecc2c76167448e84516c407600`
- E-C：`d96d6f29a5144e50759e880bbc4604ebccbd059dc7053d5d7ea5680b7c2e0acd`

E-C 两次均确认：649 条 School lesson 可分类、234 条 actual evidence、279 条 planned evidence、scope baseline `e7280307cafec31ce1f50c1c9ced7b4cc562e7f387fd6951ec2ad05c73d81d71`、locked reader baseline `b3a27028c10c11baefebeb4669c6b91758266353cb357dcc77344431c6b2d20f`。

## 5. 失败与修正记录

### 5.1 建立数据库连接前

- 初次静态检索把 F1 postdeploy 简称写成不存在的 `school_tuition_r1d_f1_planned_attribution_postdeploy.sql`；仓库实际文件为 `school_tuition_r1d_f1_planned_attribution_writer_cutover_postdeploy.sql`。未建立连接、未开启事务、未改文件。
- 联合 SQL 初稿静态审查修正 candidate record 的列别名，并删除一个没有权威冻结值支持的 shared guarded-update 单函数猜测 hash；均发生在首次 SQL 执行前。首次执行版 SHA 为 `198c2dad54bbf3aa064d7b86db57bf823992689f1e152fcd328c1133a9828cdb`。

### 5.2 既有 postdeploy 的跨阶段旧断言

- F1 postdeploy 第 1 次：`R1D_F1_POSTDEPLOY_UNCHANGED_WRAPPER_OR_UPDATE_CHANGED`。原因是 F1 文件仍冻结 E-B2 前的 shared guarded-update 定义；E-B2 已获授权替换该共享入口。未修改既有 F1 文件。事务已开启且为 `READ ONLY`，错误后连接关闭回滚。
- E-B2 postdeploy 第 1 次：`R1D_E_B2_POSTDEPLOY_SETTLEMENT_READER_CHANGED`。原因是 E-B2 文件仍冻结 E-C 前 reader 组 `b17b31a3dc1797159556032abdb04ac3`；当前 E-C 权威值为 `b3818fc1119b5b2c1069d78164760e95`。未修改既有 E-B2 文件。事务已开启且为 `READ ONLY`，错误后连接关闭回滚。

上述两项不是当前 catalog 漂移：E-C postdeploy 与联合 SQL 随后分别确认 E-B2 writer/trigger 和 E-C reader/helper 全部命中当前冻结值。

### 5.3 联合验收 SQL

1. 第 1 次，SHA `198c2dad54bbf3aa064d7b86db57bf823992689f1e152fcd328c1133a9828cdb`：partial actual 与 canonical makeup 的 `regprocedure` 签名写错，在 catalog 解析阶段停止。修正为当前精确签名，SHA 变为 `e6a561b830a6477c53e64812a7d65e934091639dea819678a4579aaae6a1aece`。已建立只读事务，未发生业务查询写入，连接关闭回滚。
2. 第 2 次，SHA `e6a561b830a6477c53e64812a7d65e934091639dea819678a4579aaae6a1aece`：trigger `TG_OP='INSERT'` 文本检查错误地要求空格格式；MD5 与 writer 组已匹配。改为去空格后的稳定结构标记，SHA 变为 `7a2a5e4ac3305a871f6b93a65730f45a761f2ac1c5babdc5eae2cad796592b03`。只读事务，连接关闭回滚。
3. 第 3 次，SHA `7a2a5e4ac3305a871f6b93a65730f45a761f2ac1c5babdc5eae2cad796592b03`：额外加入的 NULL 月份 blocker=0 假设不属于有效 student/month 合同；catalog、冻结边界、全量分类及双向集合比较此前已通过。删除越界假设，SHA 变为 `219853c0b70d7ebe01abc4f1f335cad1690bb809f465f752bd8e2b6721659dac`。只读事务，连接关闭回滚。
4. 第 4 次，SHA `219853c0b70d7ebe01abc4f1f335cad1690bb809f465f752bd8e2b6721659dac`：完整通过并 `ROLLBACK`。
5. 将已确认的 planned writer 组与 planned trigger MD5 固化为 fail-closed 断言，SHA 变为最终 `84b0b0d9d82e9a801527037c3c183a75643e643113e3e3bd18ef9bcac31226d1`。
6. 最终同字节 SQL 第 1、2 次：全部通过、全部 manifest 一致、均显式 `ROLLBACK`。

不存在写入尝试、SQL DML/DDL 错误、业务 RPC 错误或真实数据修正。

## 6. Writer、trigger、reader 与调用图

当前稳定 hash：

- planned writer 8 入口组 MD5：`edf092ebf96fdd608dbd87cd93c4d047`
- F1 planned trigger MD5：`08f3c60890d4afab8d9c730eec286c8d`
- actual writer 8 入口组 MD5：`046cb8c0002528634b767a046e4626ab`
- E-B2 actual trigger MD5：`4a163f6691c779531a65a10be0f4422e`
- E-C reader 8 函数组 MD5：`b3818fc1119b5b2c1069d78164760e95`
- resolver MD5：`8de65e9787d8d66f2cd7b65eb2479a8c`
- set helper MD5：`155e831118acbeadfd04b6640324c7cd`
- version helper MD5：`1307a4e86cccff841af55d3120a33b43`
- 22 函数联合调用图 manifest SHA-256：`b0161bf09032dffd6f1a9f2c874b97207362412ed96e73c419fce65394c700f1`

Catalog 审查确认：

- F1 的 8 个 planned 入口继续由 table trigger/invariant 控制，三个 facade 调用内部 legacy core，venue wrapper 继续调用 canonical 入口。
- E-B2 的 ordinary、cancelled、partial、canonical makeup、两个 compatibility wrapper、guarded update、venue wrapper 共 8 个入口齐全；compatibility wrapper 只调用 canonical makeup；ordinary 保持严格 `<>` duration 拒绝；partial 保持 `0 < actual < planned`；makeup 保持 remaining-credit 上限。
- actual trigger 覆盖 direct INSERT/UPDATE、数据库覆盖新 actual student month、existing actual source/student/entity/month 不可变、lesson_type/app_type 不可变、planned→actual UPDATE fail-closed。
- E-C 的 8 个 reader/lock 函数统一通过 resolver/set helper；三个内部对象 ACL 精确为 `{postgres=X/postgres}`。
- 未发现裸 canonical `year_month` 筛选、`coalesce(student_settlement_month,year_month)`、actual date 作为学生月、created_at/updated_at 作为 legacy 识别。

## 7. 全量分类与运营增长

当前共有 649 条 School lesson，全部且仅归入一类：

| attribution class | count | UUID MD5 | manifest SHA-256 |
|---|---:|---|---|
| canonical planned | 135 | `3ce7dec0788c6bca4d293331e38462ce` | `0db418745cf5100567bed01fd005117635116674ebf5ea82a3599f4e2fdd5d58` |
| legacy planned | 279 | `0975fdc91b533680e5ccc909f076ac62` | `93a81c8ebb75528c46960f193f04bcde28767f7026adbd8465a658fd40a6670d` |
| canonical actual | 1 | `4650f06fe21670af0e5dc1e075deffa9` | `bd6c71aa25dcf1d6cd82f3149174c74bcbb3f1808bdda412a263f3f7aaa94f71` |
| legacy actual | 234 | `891eeabf9a48d1c7b00a695b21cf8e95` | `126eb83dff723b6330765aec94e235a0e0012087822d1d088a0518b9dc7fec99` |

- fixed approved canonical planned：118
- post-cutover planned：17
- post-cutover actual：1
- partial bundle：0
- 无法分类：0
- 多重分类：0
- E-C 部署后已披露总量也是 649，因此本次验收期间无额外运营增长；当前 17/1 post-cutover 行全部满足 writer invariant。
- student/entity/month 维度共 31 组；count、duration、planned fee、billable actual fee、UUID、class 构成和 teacher month 联合 manifest：`8248faece0b863c1ee2698ef60504ecb88ef73cd8e12af4d5e0188b99c90231d`。

## 8. Evidence、resolver 与集合一致性

- planned legacy evidence：279；manifest `34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627`
- actual legacy evidence：234；UUID MD5 `891eeabf9a48d1c7b00a695b21cf8e95`
- actual identity SHA-256：`83f9df656fc8e089ce769cac84d61338c0889ac853b2e2b544f8b2bf3678650c`
- actual full-row SHA-256：`dd25082aac3216cf3ba6160e3ee81f56845359aa1a603e975b864bb630d933f8`
- 234 条 legacy actual 完整业务行、source/student/entity/teacher/subject/date/year_month/teacher month/full-row hash 均与 evidence 一致；`student_settlement_month` 全部保持 NULL。

直接逐行调用 resolver 与 `school_list_r1d_e_c_student_month_lessons(NULL,NULL)` 的双向比较：

- direct count / helper count：649 / 649
- 缺失：0
- 多出：0
- month 不一致：0
- class 不一致：0
- student/entity 不一致：0

## 9. 真实跨月事实

| 事实类别 | count | UUID MD5 | 维度 manifest SHA-256 |
|---|---:|---|---|
| canonical planned：lesson date 月不同 | 0 | 不适用 | 不适用 |
| canonical planned：billing week 跨月 | 28 | `9dcaf2e399db297c4cac491e619c8960` | `2198df81c8160556f472d75c0c73681a5f475b725c9559e8a5aafec6db3ad431` |
| canonical actual：date/teacher 月不同 | 0 | 不适用 | 不适用 |
| legacy planned：冻结月与 date 月不同 | 0 | 不适用 | 不适用 |
| legacy actual：冻结月与 date 月不同 | 9 | `eb107fb6abf5e04681a52b25fb7a1f4b` | `c81ea28bc2c21497e5d29be5c0253fa799f44813246d4c117947e922c6ae2cb3` |

28 条跨月 billing week 与 9 条 legacy actual 均在权威月集合中，错误 comparison/date 月集合为 0，权威月缺失为 0。canonical actual 跨 student/teacher 月真实样本当前为 0；本阶段不造数，结构性证据沿用已通过且本轮未执行的 E-B2/E-C rollback tests。teacher settlement month 仍由 actual 发生日期决定。

## 10. Summary、preview 与 blocker

- 当前相关 student/month scope：31
- zero-lesson scope：0
- income-only scope：0
- summary/preview/blocker 联合 manifest：`896a0e136aa8c2d17013c8097a7317d5ffc7febce3a890fb899bb43a45c90892`

全部有效 scope 的 summary、preview、blocker 调用无异常；student/month 与 business entity 正确；preview 中所有 summary 合同字段与 summary 一致；planned/actual duration 与 fee 同 resolver 集合手工聚合一致；adjustment 只来自现有 active draft；blocker 调用链只使用权威月份 lesson 集合。当前没有空月份或 income-only 真实样本，因此明确报告 0，未写数据库制造样本；其结构性行为由既有已通过 rollback tests 支持。

## 11. 15 个 locked snapshot

- snapshot evidence count：15
- snapshot evidence manifest：`68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26`
- locked joint manifest（identity、status、student/entity/month、lesson/planned/actual count、lesson UUID、amount basis、structure、carryover、adjustment、summary、preview/total）：`0a50478a99787c4d003cce6d616bd5bf71dad1e1c7f971ecfc91f27347350f10`
- locked reader baseline：`b3a27028c10c11baefebeb4669c6b91758266353cb357dcc77344431c6b2d20f`

15 个 snapshot 逐条 mismatch 为 0；未发生动态重算覆盖历史。unlock 函数定义仍包含 `R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE`，本阶段未实际调用 unlock/relock。

## 12. R0、candidate、资金链及隔离边界

R0 保持：

- `student_tuition_preview = validation_preview_only`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

Candidate 保持：

- 118 条 / 254 小时 / JPY 2,474,000
- function MD5：`8981a2ce07abf8c28231bfaf05451368`
- UUID MD5：`77f697f82e547d84dcabf88a3c868aa1`
- manifest SHA-256：`f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1`

School 资金链保持：

- bills / income / bill lessons / historical exclusions：9 / 42 / 121 / 42
- hashes：`0f0323b79e7ff1c47ff6b90c75477a2d` / `2a4897b752f272b1f192045418b4940c` / `09dfee7d8833e09384fb41a84f2959e0` / `680b6e5aaa718569aee4c36fe1cdc058`

其他隔离边界：

- 历史 actual > planned：19；全部 S1-A overage 字段仍 NULL
- ordinary actual 严格 `<>` 时长拒绝仍存在；S1-B 未实现、未恢复
- 固定 8 条 makeup 差异事实保持；full-row 组合 MD5 `18a32469745dfcfe5535b5920df41cfd`
- lesson 空调字段写入数：0
- venue/rate/planned command/audit 四表合计：0
- 本阶段未生成 bill/income，未修改 snapshot/carryover/adjustment，未接入空调费计算

## 13. 最终工件与停止点

- 联合 SQL：`sql/current/school_tuition_r1d_e_d_authoritative_month_joint_readonly_acceptance.sql`
- 联合 SQL SHA-256：`84b0b0d9d82e9a801527037c3c183a75643e643113e3e3bd18ef9bcac31226d1`
- 本报告：`docs/school-v2-r1d-e-d-authoritative-month-joint-readonly-acceptance-report-20260730.md`
- 报告 SHA-256：以最终文件系统核验输出为准

完成后停止在：`R1D-E-D联合只读验收审查点`。

未提交 Git，未恢复 S1-B，未解除 R0，未进入后续阶段。
