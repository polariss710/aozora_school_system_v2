# School V2 学费链 P0 R1C-A 实施报告：2026年8月52条未来 planned 课时业务归属定向迁移

实施日期：2026-07-27
实施前 Git HEAD：`c663f32168b8e579eb4472a5a5258dec5292fc69`
迁移批次 ID：`c1000000-0000-4000-8000-202607279999`
迁移 key：`r1c-a:2026-08:planned-business-entity:personal-to-aosora`

## 1. 结论与停止状态

R1C-A 固定 52-ID 迁移已在 School DB 单一事务中正式提交。事务内所有 fail-closed 前置条件、52 行逐条完整指纹、下游零关系、跨月排除、仅 `business_entity_id` 变化、原 `updated_at` 保持、11 组非授权业务表前后行数/哈希比较及 1+52 条审计证据均通过。

正式迁移结果：

- 张倬闻：30 条、65 小时、JPY 650,000；
- 孙陈锋：22 条、44 小时、JPY 374,000；
- 合计：52 条、109 小时、JPY 1,024,000；
- 52 条全部由“个人名义”迁移为“青空进学塾”；
- 52 条授权字段外汇总哈希迁移前后均为 `fb95feb23740dba808979a7c73e165d9`；
- 52/52 原 `updated_at` 保持不变；
- audit batch 1 条、audit item 52 条，均为 immutable executed evidence。

迁移审计执行时间后 1 分 50 秒出现一条独立 actual 业务记录，因此“当前最终快照”的 actual 总数为 229，而迁移事务内基线为 228。该记录不是 R1C-A 写入、其 planned 来源不在 52-ID manifest。依照 fail-closed 原则，本阶段没有修改、删除或回滚该外部业务记录，也没有继续任何 R1C-B 工作。本报告分别记录“迁移事务内基线验收通过”和“迁移审计执行时间后的外部业务漂移”，交由审查确认。

## 2. 实施文件

新增：

- `sql/current/school_tuition_r1c_a_business_entity_migration_audit_schema.sql`
  - SHA-256：`acc8f767302e0806aaebbebac106c6301cee2888e32bfaf2f4dbb260a9f4b93d`
  - 建立 `school_business_entity_migration_batches` 与 `school_business_entity_migration_items`；
  - 两表分别 18/21 列；
  - batch/item 保存固定清单、原始完整快照、before/after hash、原始 `updated_at`、证据、批准、执行状态与时间；
  - anon/authenticated 无权限，service_role 仅 `SELECT/INSERT`；
  - update/delete 由 immutable trigger 永久拒绝。
- `sql/current/school_tuition_r1c_a_fixed_52_business_entity_migration.sql`
  - SHA-256：`6d61c9a162985c9aae3f834a67e4959912f73aff8b4f1d3ccd4a43486accbaca`；
  - 文件内冻结 52 个 UUID 及完整业务指纹；
  - UPDATE 只通过固定 UUID manifest 连接，不以“学生＋月份＋当前业务归属”动态决定执行对象；
  - 对课时表取得 `ACCESS EXCLUSIVE` 锁后逐行复核完整行哈希及显式字段；
  - 在同一事务中精确停用并恢复通用 `updated_at` trigger，避免非授权时间戳变化；
  - 事务内比较 11 组非授权业务对象及授权字段外课时投影；
  - `r1c_commit=0` 与 `r1c_commit=1` 使用完全相同文件。
- `sql/current/school_tuition_r1c_a_postdeploy_readonly.sql`
  - SHA-256：`5418cb768f971fc9dc6996d25df7a4c3e5be2f050a8149d316a9168f415fb5e1`；
  - 只读核对 audit、52 行、跨月排除、下游零关系、历史与资金链、trigger 和 R0 gate。
- `docs/school-v2-r1c-a-business-entity-migration-report-20260727.md`（本报告）。
- `docs/current-status.md` 将记录本阶段结果及迁移审计执行时间后的 actual 例外。

保留且未修改：

- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`。该 R1B 临时审查文件未删除、未暂存、未提交。

## 3. 审计 DDL

执行顺序：

1. `r1c_schema_commit=0`：创建两表、约束、索引、注释、ACL 和 immutable trigger 后整体 `ROLLBACK`；
2. 只读确认两个 relation 均不存在，DDL 残留 0；
3. `r1c_schema_commit=1`：正式部署相同文件并 `COMMIT`；
4. 只读确认：
   - batch 表 18 列，12 check / 2 FK / 1 PK / 1 unique；
   - item 表 21 列，10 check / 5 FK / 1 PK / 2 unique；
   - 两个 immutable trigger 均 `tgenabled='O'`；
   - ACL 为 postgres 全权限、service_role `SELECT/INSERT`，anon/authenticated 无权限；
   - 正式迁移前 batch/item 行数均为 0。

## 4. 固定 manifest 与前置条件

Manifest before-hash 汇总：`698f2bcb8f1fbc947b1f9785b5041b9a`。

只读预检与锁内复检均确认：

- 精确 52 条、序号 1..52、UUID 无重复；
- 张倬闻 30/65/650000，原批次 `5254a3fb-dc38-40c2-9cf3-810a79835275`；
- 孙陈锋 22/44/374000，原批次 `2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c`；
- 均为 School、planned、active 状态语义（`lesson_type='planned'`、`status='planned'`、`is_billable=true`、`voided_at is null`）；
- 均为 2026-08、当前个人名义、无 linked actual；
- normalized bill lesson 0、bill JSON snapshot 0；
- 有效工资明细 0、2026-08 月结 0；
- income/Cash linkage/School账户流水中的 UUID 引用均为 0；
- from/to 业务归属及学生身份均匹配；
- 三个 R0 gate 在锁内仍为 `validation_preview_only / blocked / blocked`。

### 固定 52-ID 清单

| 序号 | 学生 | 日期 | planned lesson ID | before row hash |
|---:|---|---|---|---|
| 1 | 张倬闻 | 2026-08-03 | `23d4b46b-eb1c-48b7-8001-d208ce14f08d` | `993e3806558cc2d230dbfa84d7cc33d2` |
| 2 | 张倬闻 | 2026-08-03 | `637ba833-830f-42a6-81ed-47a6f9902523` | `e056bd171ba1f6f6c72c85296188b79a` |
| 3 | 张倬闻 | 2026-08-03 | `7175780c-b179-4f96-a42e-99ba11bdaed8` | `eb8addbd2c972d08f4c6135980df8152` |
| 4 | 张倬闻 | 2026-08-03 | `80384c28-5044-4c56-94cd-5099aa852032` | `b42a13fccc8a05054dcc00bb658eb55e` |
| 5 | 张倬闻 | 2026-08-03 | `920808f2-5629-4fcc-957c-6bdcee48808e` | `599bcf87c019542f2d56576817d1effe` |
| 6 | 张倬闻 | 2026-08-03 | `d06f136e-d4c5-44fb-ae5e-d87efa26bbfb` | `b34ee38a48cfcb6c63fba63538f9ecbf` |
| 7 | 张倬闻 | 2026-08-10 | `3db3ad8b-44b6-4be7-a3ea-611362b82488` | `948983a8ec5663b44ffe044fe76e0384` |
| 8 | 张倬闻 | 2026-08-10 | `6997acdc-fec4-4e14-a22b-d9f5291b1e0b` | `dad81e74f73063d9a299991e46673256` |
| 9 | 张倬闻 | 2026-08-10 | `69ecc019-9f8f-474e-8dc9-1dced16e41a6` | `5e70c72de955da2b6b27e17953a9f69e` |
| 10 | 张倬闻 | 2026-08-10 | `72ffebba-ecb3-4a96-9550-f02a5f64cf62` | `8c56632af91fde27fc8e95c93b1f5286` |
| 11 | 张倬闻 | 2026-08-10 | `c0e9fd95-7833-44ef-a282-61611976b089` | `559f7fd6a2f485ea8ccca1b3274b82d1` |
| 12 | 张倬闻 | 2026-08-10 | `e6aaf546-bb9c-4e71-980e-40f78f2e1e11` | `9242057cb858c5714a9d70fc4e8b6d18` |
| 13 | 张倬闻 | 2026-08-17 | `12d70ee9-8221-4b8e-a01c-61548340c42d` | `e4284f940fdca2a631c8196ff084efeb` |
| 14 | 张倬闻 | 2026-08-17 | `1927b6ba-6ca6-4ef9-b1c0-0246067c7d41` | `ec1b3e0f77b80fdbfd4d9b4f7a6d0a6c` |
| 15 | 张倬闻 | 2026-08-17 | `3920fdea-2f9d-4b17-abd0-f788b0d7d29e` | `10d7c9c2795c6d675784d817d7c238ea` |
| 16 | 张倬闻 | 2026-08-17 | `95dff1ab-544d-43be-bc0e-a95232f06935` | `fee1dc2f588daf41d2d8e28de57d3580` |
| 17 | 张倬闻 | 2026-08-17 | `a10744fc-173a-4b25-9bc3-99d6437797c5` | `2001ad1047d7472eac01b7d73604f499` |
| 18 | 张倬闻 | 2026-08-17 | `a601916b-6add-4be6-adcc-5c232425f686` | `9db9d6e9363a39204c8408ab3f383ab3` |
| 19 | 张倬闻 | 2026-08-24 | `286344d1-c603-4990-aba3-814996535319` | `40820046da11f4e07acce87ccb2eecaf` |
| 20 | 张倬闻 | 2026-08-24 | `9a76aed4-058f-4801-90b5-b2637387fb3e` | `fe36193df43f2e02bfc7c50ea0540879` |
| 21 | 张倬闻 | 2026-08-24 | `9f755093-8f4d-4337-80ed-23d0e555c835` | `0955171430d89a6ac42b64fbc37904c6` |
| 22 | 张倬闻 | 2026-08-24 | `e2540bb3-5c1f-45bc-b964-9727a6ed3e48` | `e85e6cda3434165afeaf8e5e54d36b0b` |
| 23 | 张倬闻 | 2026-08-24 | `ee6c1383-4259-44e0-923c-1ee6b8749820` | `2fcaa752eaa6b385fbd8bb261e024ebc` |
| 24 | 张倬闻 | 2026-08-24 | `ee86e691-2c96-48c2-ad57-512f9eef4b3c` | `c1fe954541c2e97d0296a3f21990262d` |
| 25 | 张倬闻 | 2026-08-31 | `01490eb7-1bd7-430a-ba26-3ccc81d45796` | `69dbe9547f3b31e364b0abb9133a3ffc` |
| 26 | 张倬闻 | 2026-08-31 | `80e03531-5eaa-40e1-a435-0132dd62d5c0` | `2d5bd00a308f24f21c9b27038713fa20` |
| 27 | 张倬闻 | 2026-08-31 | `8c6da1a7-69a9-45b6-9a77-daa2bfd7f9e9` | `52a501d8db610126eb739d589e3b13db` |
| 28 | 张倬闻 | 2026-08-31 | `9efe2def-ff59-467a-bb76-a49537ec8e0f` | `168bcf37eb802c26944803750dce1aff` |
| 29 | 张倬闻 | 2026-08-31 | `adc0b06c-eee3-40ca-8992-592f5d4b009b` | `dad17b279a05cc120d59553b35c6fbda` |
| 30 | 张倬闻 | 2026-08-31 | `dbe16731-803b-49db-8cc0-f826e911bb41` | `b7ce2baa5664d7052af448cc1a7ff680` |
| 31 | 孙陈锋 | 2026-08-03 | `222c4ad5-b6fe-4e4e-b192-8db8c65b61fa` | `ffc18c002597b77a3ed1f2037b08a844` |
| 32 | 孙陈锋 | 2026-08-03 | `6c70c4c1-1895-453d-b9b0-591e9f004f86` | `2e980717dfc30cc996101436d5e961d4` |
| 33 | 孙陈锋 | 2026-08-03 | `89da310d-4f17-4a40-8315-659838aec59c` | `f0aa0d0e5b14f4bf2183263e00f607c9` |
| 34 | 孙陈锋 | 2026-08-03 | `9efb8862-e8c5-4f3d-9d55-b0be4317ad19` | `aa0728c018de3513dae269cb27a59d49` |
| 35 | 孙陈锋 | 2026-08-10 | `37a2083e-bb28-45d1-802a-f98f4564887f` | `90a653a4d812c68afb54e4b1ad8d14ef` |
| 36 | 孙陈锋 | 2026-08-10 | `63ca3a2b-7c2f-4eed-a997-71840357f8f6` | `e4fa8f0dbd1118796a0666614ad48a0e` |
| 37 | 孙陈锋 | 2026-08-10 | `a3ee5595-6dd5-4737-8605-ff5a8d7d0333` | `0f2a5b895356f26573c033b343561a7d` |
| 38 | 孙陈锋 | 2026-08-10 | `ea766c1d-f152-4b3f-9400-0d5b5aa64614` | `a5ddee910333c337e4d157aff64d9eb4` |
| 39 | 孙陈锋 | 2026-08-10 | `fcbf1be4-567b-4876-9cc6-19cd0d395da0` | `763c934627f53dad6f92b55d8ba20975` |
| 40 | 孙陈锋 | 2026-08-17 | `1df61ad9-742f-4fd6-b883-b3a8bbb0c4e8` | `0b6966ead96429c691fcdea8bb445d8c` |
| 41 | 孙陈锋 | 2026-08-17 | `68bbce4e-f6bb-45c6-9798-ee72b6f75179` | `95f8bfe2b386158b0451e5db2171b7e7` |
| 42 | 孙陈锋 | 2026-08-17 | `9bdb88c1-9c08-4716-b146-e98cf149978b` | `d45ab80204a907a66fce42550f94c31a` |
| 43 | 孙陈锋 | 2026-08-17 | `fa7883c8-35e6-40bd-92d1-70adcdcce078` | `e67c1bac7414a05e07edd2f73777b50d` |
| 44 | 孙陈锋 | 2026-08-24 | `1f9c027a-6db2-4aa2-8bef-215f3ed2bbb9` | `38d6ca8cba05411142f19eb78dc8076f` |
| 45 | 孙陈锋 | 2026-08-24 | `475853f0-2004-4375-ae72-013c5a86987c` | `c0cc01721dc09c2e80a30fe71510d7bb` |
| 46 | 孙陈锋 | 2026-08-24 | `6e005bee-2d14-4722-8b76-9dbe7f836e12` | `2af021da7e2fd3b3c699d33d0cfc8ddb` |
| 47 | 孙陈锋 | 2026-08-24 | `cde683d3-06f2-46ec-8b8a-4f2ed4b4962e` | `2a6c1e964d62ba4d111162b88c9502cd` |
| 48 | 孙陈锋 | 2026-08-24 | `e65b7d1d-45b2-4485-ae6d-7000fe92ce78` | `ffd7b8d4927c5bd693f823391ffab117` |
| 49 | 孙陈锋 | 2026-08-31 | `02b9e85e-2e03-404d-93a6-9bfef3bf186d` | `9b7d5836597c9394c1716bbf97c3e03f` |
| 50 | 孙陈锋 | 2026-08-31 | `0d048cbf-a5f5-458c-88aa-ce0c3a1c667c` | `50ba8a5847efff298560079e94c14ddd` |
| 51 | 孙陈锋 | 2026-08-31 | `196c9d86-500b-4687-a051-88dcc12fa2a9` | `94ee81c0c92d6ec41b8f6d09c3a53663` |
| 52 | 孙陈锋 | 2026-08-31 | `aa55dc2e-3b1b-4d2d-863f-9f64e84b8578` | `80d49b953d7f75c847ec84437b9ab95f` |

## 5. 跨月两条永久排除

以下两条从未进入 manifest，完整行哈希迁移前后不变：

| 日期 | planned lesson ID | 完整行哈希 |
|---|---|---|
| 2026-08-01 物理 | `8b737b58-cd14-42c5-afd2-34730dcef963` | `21f83674162b1b1ca485912a048bac3c` |
| 2026-08-02 化学 | `685ad45e-b5da-42ca-8f43-7732e8d6e40d` | `2d52e778bfb59a27bb3b28506232217d` |

验收结果：

- 两条仍为青空进学塾、各 2 小时、单价 JPY 8,500、费用 JPY 17,000；
- 日期、ID、金额、业务归属均未变化；
- 两条仍以 `canonical_charge` 关联 2026-07 canonical bill `2a9f1c25-a060-461e-ae10-b02295dec381`；
- 未修改、删除、重建、移动，也未改日期。

## 6. ROLLBACK 演练与正式事务

### ROLLBACK 演练

相同迁移文件以 `r1c_commit=0` 执行：

- 锁内插入 manifest 52；
- 临时更新 52；
- 事务内 audit batch 1、items 52；
- 张倬闻 30/65/650000、孙陈锋 22/44/374000；
- `updated_at` unchanged 30/30 + 22/22；
- `SET CONSTRAINTS ALL IMMEDIATE` 成功；
- 11 组非授权对象前后行数/哈希一致；
- 整体 `ROLLBACK` 后：
  - batch residue = 0；
  - item residue = 0；
  - migrated target scope residue = 0；
  - 原个人名义范围恢复 52/109/1024000。

回滚后 R1B 全量只读检查继续为 7 identity、121 relation、9/9 pair、原 income 9/9、13 个 R0/R1B trigger enabled，R0 gate 不变。

### 正式执行

相同文件 SHA-256 未变，以 `r1c_commit=1` 执行并 `COMMIT`：

- 仅 52 个固定 planned lesson 的 `business_entity_id` 由个人名义改为青空进学塾；
- audit batch 写入 1 条，audit item 写入 52 条；
- 未修改 52 行的 ID、学生、批次、日期/月、老师、科目、课时数、时长、单价、费用、状态、actual 关系、备注、`created_at`、`updated_at` 或其他字段；
- 没有新增 bill、income、Cash linkage、Cash request、Cash transaction、School账户流水、actual、月结或工资记录。

## 7. School / Cash 前后基线

### 迁移事务内基线

以下对象在迁移事务的 before/after 表中逐项比较，行数与完整行哈希一致：

| 对象 | 行数 | 前后哈希 |
|---|---:|---|
| tuition bills | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| School income | 42 | `2a4897b752f272b1f192045418b4940c` |
| billing identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| bill lesson | 121 | `09dfee7d8833e09384fb41a84f2959e0` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| School account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| actual lesson | 228 | `b31f213da04f324e68339fb5f4c4678a` |
| student settlement | 15 | `7925cf3018bd0e669cd29710f6593238` |
| teacher wage lock | 95 | `7bbe108d3ac73d4f21530793bf141bc6` |
| teacher wage detail | 556 | `6204dc666b3b8e0f64fac901ecf0686a` |

课时整表在迁移前为 625 行、哈希 `313cff5314d78adf6c02497d0cc0097f`；正式事务内验收时仍为 625 行，因授权的 52 个业务归属变化，完整表哈希按预期变为 `a172aa04fa7fa1f3df6e6d25dad3517d`。52 行授权字段外哈希保持 `fb95feb23740dba808979a7c73e165d9`。

R1B 历史事实继续通过：

- 7 identity；
- 121 relation = 85 canonical / 24 incident / 12 legacy；
- bill-income exact pair = 9/9；
- 9 条原 income 业务哈希 = 9/9；
- 张倬闻 duplicate incident 隔离仍有效；
- 13 个 R0/R1B 保护 trigger 全 enabled。

### Cash DB

迁移前后完全一致，Cash DB 零写入：

| 对象 | 行数 | 前后哈希 |
|---|---:|---|
| external request | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| CNY transaction | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| JPY transaction | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

### 迁移审计执行时间后的 actual

- 迁移审计执行时间（R1C-A batch `executed_at`）：`2026-07-27 10:58:38.658016+00`；
- 独立 actual：`50ec3900-63ff-4138-85f1-53a999c23daa`；
- actual created_at：`2026-07-27 11:00:29.030006+00`；
- 晚于迁移审计执行时间：`00:01:50.371990`；
- planned 来源：`7b26139d-4295-4ec6-93bf-c8ea8b0b1285`；
- 来源在 R1C-A manifest：false；
- 当前 actual 因此外部业务活动变为 229，当前 actual 哈希 `fe752c448bb4d38af498136d3149f14a`；
- 当前课时整表变为 626，哈希 `ca32bb31f5b9c3d98ece7762562ee71c`。

该记录的 `created_at` 晚于 R1C-A 迁移审计执行时间；该时间字段不是数据库 commit timestamp。正式事务内 actual 前后均为 228 且哈希一致。本阶段未对该记录做任何写入。若审查要求“最终查询时刻也必须仍为 228”，则该项不能宣称通过，需要业务负责人确认采用迁移事务内基线作为 R1C-A 验收点。

## 8. R0 gate 与入口探针

Gate 保持：

- `student_tuition_preview = validation_preview_only`；
- `student_tuition_generate = blocked`；
- `student_tuition_cash_submit = blocked`。

执行 `school_tuition_r1b_r0_entry_probes.sql`：

- 两个 `school_generate_student_tuition_bill(...)` overload 均返回 `TUITION_GENERATION_BLOCKED`；
- `school_create_student_tuition_bill_income_record(...)` 返回 `TUITION_GENERATION_BLOCKED`；
- `school_create_personal_cash_tuition_income_record(...)` 返回 `TUITION_GENERATION_BLOCKED`；
- Cash gate 返回 `TUITION_CASH_SUBMISSION_BLOCKED`；
- 隔离事故 income 的 Cash RPC 继续拒绝；
- 探针没有成功写入。

旧 8 月预览审计在迁移后按预期仍显示孙陈锋 24 条、48 小时、JPY 408,000，并标出其中 2 条已收费跨月冲突。本阶段没有修改预览 RPC、日期模型或候选规则；该已知状态留给 R1C-B。

## 9. SQL / RPC 与数据库写入清单

执行 SQL 文件：

- School：
  - `school_tuition_r1b_postdeploy_readonly.sql`（迁移前/回滚后/正式后只读核对）；
  - `school_tuition_r0_august_2026_baseline_readonly.sql`（迁移前及正式后只读核对）；
  - `school_tuition_r1c_a_business_entity_migration_audit_schema.sql`（rollback + commit）；
  - `school_tuition_r1c_a_fixed_52_business_entity_migration.sql`（rollback + commit）；
  - `school_tuition_r1c_a_postdeploy_readonly.sql`（正式后只读核对）；
  - `school_tuition_r1b_r0_entry_probes.sql`（预期拒绝探针）。
- Cash：
  - `cash_tuition_r1a_business_baseline_readonly.sql`（迁移前/后只读核对）。

调用 RPC/函数仅来自 R0 拒绝探针，详见第 8 节；没有成功写 RPC。

正式数据库写入：

- School DDL：新增 2 张审计表、2 个索引、2 个 immutable trigger、约束/注释/ACL；
- School DML：授权的 52 条真实 planned lesson 仅改 `business_entity_id`，新增 audit batch 1 + audit items 52；
- Cash DDL/DML：0；
- 回滚演练业务残留：0；
- 测试白名单写入：无。本阶段正式 DML 是业务负责人明确授权的固定 52 条真实业务数据，不是测试数据。

未执行：历史学费回填、时间戳恢复、账单/收入/Cash 生成、日期模型、原子生成、R0 gate 解除、9 月以后 68 条候选、R1C-B 或任何后续阶段。

## 10. Git 状态与建议交付

本阶段未执行 `git add`、commit、push，HEAD 仍为 `c663f32168b8e579eb4472a5a5258dec5292fc69`。

建议审查通过后精确暂存：

- `docs/current-status.md`
- `docs/school-v2-r1c-a-business-entity-migration-report-20260727.md`
- `sql/current/school_tuition_r1c_a_business_entity_migration_audit_schema.sql`
- `sql/current/school_tuition_r1c_a_fixed_52_business_entity_migration.sql`
- `sql/current/school_tuition_r1c_a_postdeploy_readonly.sql`

不得暂存：

- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`

建议 commit message：

`feat: migrate approved August tuition lessons to Aozora entity`

当前停止点：等待 ChatGPT 与业务负责人审查；未开始 R1C-B。
