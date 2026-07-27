# School V2 学费链 P0：R1C-C-B 固定66-ID业务归属迁移实施报告

状态：数据库实施完成，等待代码与业务审查

实施日期：2026-07-28（JST）

实施基线：`main` / `abe1100ab253a231bb9ce249c5c0b5d0be6777d0`

## 1. 结论

R1C-C-B已按业务负责人批准的固定66-ID完成。张倬闻2026-09至2026-11的66条planned lesson仅将`business_entity_id`从个人名义改为青空进学塾；66/66原`updated_at`不变，其他lesson字段逐行不变。迁移新增1条batch和66条immutable item审计，没有新增或修改bill、income、Cash、账户流水、actual、月结或工资数据。

| 月份 | 条数 | 小时 | JPY | 目标归属 | updated_at不变 |
|---|---:|---:|---:|---:|---:|
| 2026-09 | 24 | 52 | 520,000 | 24/24 | 24/24 |
| 2026-10 | 24 | 52 | 520,000 | 24/24 | 24/24 |
| 2026-11 | 18 | 41 | 410,000 | 18/18 | 18/18 |
| 合计 | 66 | 145 | 1,450,000 | 66/66 | 66/66 |

业务批准证据写入审计：课程已发给学生，计划已确认锁定且当前有效；批准仅限张倬闻固定66-ID；李天伦11-ID明确排除；历史68-ID manifest不可用且不作为授权依据。

## 2. 固定66-ID manifest与before hash

执行对象逐条硬编码于迁移SQL；学生、月份、批次、归属、状态及汇总仅作fail-closed完整性断言，不用于动态选择UPDATE对象。冻结集合完整行聚合MD5为`ee7c476c9c56c926eda083008197450a`。

| # | planned lesson ID | 月份 / 日期 | before row MD5 |
|---:|---|---|---|
| 1 | 15f8147e-5bb0-4cf9-9ba7-3e12f115774e | 2026-09 / 2026-09-07 | 12d56243c2e3d2f086a61b8304cc1cbc |
| 2 | 224015ce-b435-4233-8113-0e6c712b1a18 | 2026-09 / 2026-09-07 | 2aacfa73b5c5a25cc37bbfd4bf8fe0a5 |
| 3 | 2bd402cb-fc4d-48cc-b166-400ee4945703 | 2026-09 / 2026-09-07 | 8932c8024e3c49fd8ab06cb3b7858a52 |
| 4 | c1f5c7e9-70e4-4c2d-99c8-aadd986cda15 | 2026-09 / 2026-09-07 | 10fee537e26570a52cf1044bd4b9c9b8 |
| 5 | dadcf864-5343-403d-a111-e68b8617f413 | 2026-09 / 2026-09-07 | 8d3cea4cb6c5b4cb5151364ff6bd32d2 |
| 6 | f91ecdd8-7442-4879-97b6-67ad8ea99f23 | 2026-09 / 2026-09-07 | 0f7cce6422795daf71d2830add38f174 |
| 7 | 10b62cc8-dd74-4665-a6cd-02cc02924a65 | 2026-09 / 2026-09-14 | 7e033b5989da8caa26a3b6f086a303cf |
| 8 | 57948b80-89d9-45f2-a99f-3b92aed9f4e8 | 2026-09 / 2026-09-14 | 599cec021da9e901d19db3f4f7b932f4 |
| 9 | 68da4912-72a8-418c-b30b-335bb9896c63 | 2026-09 / 2026-09-14 | 48350b8a77c2297e9c4acaeeb7d6ad91 |
| 10 | a9de94c0-954b-452d-95b0-6a8b7d1a5a9e | 2026-09 / 2026-09-14 | 5747f991ad01590c0ffcd704f3146939 |
| 11 | c79e2ade-4026-4ab3-a316-ba26354abfe2 | 2026-09 / 2026-09-14 | d4cbb87a047e2e6c3bb7d94a68c1d9ba |
| 12 | f693a3d9-fada-48f2-8203-bc33d46ee4dd | 2026-09 / 2026-09-14 | cf007f7c0625bbfc7a1139ce3f43b659 |
| 13 | 5591fb92-2333-460c-95f3-85c6511d6fd4 | 2026-09 / 2026-09-21 | 0894065af86da5bec68678c74f5d4cff |
| 14 | 645cccaf-ae0f-41b3-84d1-e40882a8c85f | 2026-09 / 2026-09-21 | 451e0fb9f6b74a5f685fccd3754138e9 |
| 15 | 82e81ecc-dd23-471e-8402-a45bd8b20eb1 | 2026-09 / 2026-09-21 | fc2d60a9be10b69e1d25249b16b07404 |
| 16 | bf38024e-2a5f-422c-ad41-01ec9922e701 | 2026-09 / 2026-09-21 | 902b580a174a5664d8823d27514f1e09 |
| 17 | dbd6f35a-b0ee-4af8-bcda-e065330f0413 | 2026-09 / 2026-09-21 | 8659c0ed70029c760346bbc7344bc307 |
| 18 | fb066255-82b5-4eb1-9f76-a776c04becc2 | 2026-09 / 2026-09-21 | 94d1df8602d5593bee66b6b37e1b7363 |
| 19 | 1eeb937e-a7ad-4e7c-955d-797b9d979882 | 2026-09 / 2026-09-28 | 4ea590fe3dac3991c493c6916c789494 |
| 20 | 21e97cbd-3e18-4c9e-9790-981f885af03a | 2026-09 / 2026-09-28 | ad86fd528a4991e917231679b663846c |
| 21 | 371e41c5-a659-44a6-87e0-c3a85c9c1b75 | 2026-09 / 2026-09-28 | 90211e1db2b192c40d2260dfd38e701f |
| 22 | 966119c6-09c8-4ac5-9c16-6cda13137d87 | 2026-09 / 2026-09-28 | 61b63b68c6d0998f0da5359b6eaef9d8 |
| 23 | a9e861d3-6bd6-4b76-ba78-4cc1f3265b43 | 2026-09 / 2026-09-28 | e0aae4aaaeea5b0e69a28fc1ef76a1f2 |
| 24 | fd803263-07b6-4b1f-b668-43a482f21c89 | 2026-09 / 2026-09-28 | 34c41fd38bca354f180e0f0ee207bb02 |
| 25 | 0386bf22-8619-41f2-be6c-5106b8c17cd0 | 2026-10 / 2026-10-05 | 8ab86cc4ab0063f9a5a005dd862b5713 |
| 26 | 4254095b-9ec1-4651-a9ff-0dffb3a4520f | 2026-10 / 2026-10-05 | d6cb7d5196a6d4aba0151ceb286803eb |
| 27 | 7e833e2c-3bc0-4c6d-a1ab-204229f43a77 | 2026-10 / 2026-10-05 | 93db4186a63a86332c069db26b2d7585 |
| 28 | aea933f5-5e3b-4476-b1f0-d781d41312a3 | 2026-10 / 2026-10-05 | de7821d7572d507fe39904e8bec6dbae |
| 29 | b33f023c-4b0c-495e-8f0b-934ead526421 | 2026-10 / 2026-10-05 | 9247dff70d9393390f8b0967276c2866 |
| 30 | ff368fb5-94a8-4ea4-b3fc-d62ce499732b | 2026-10 / 2026-10-05 | 64dbe380f64c2aab2e5a32e3fcd1a5ef |
| 31 | 17e58b7d-3fb8-4874-8071-0b1f808e8430 | 2026-10 / 2026-10-12 | d82ba0a4a270059cbbb1b42e2fdb3a8e |
| 32 | 30271ef0-51ee-43ca-9103-1b5ec34255e1 | 2026-10 / 2026-10-12 | 8b7053df33b58e2115861b8acfef9725 |
| 33 | a3a7dd70-1a1e-4078-bce8-d54f10fc57af | 2026-10 / 2026-10-12 | c94841a426d3533769296bb36b59d27c |
| 34 | cfb5e237-51a3-48b2-a12e-e8f0628e2c51 | 2026-10 / 2026-10-12 | 7a10d184831c000dd0b118b952adc4d3 |
| 35 | d9d11e4b-a01c-4535-93cf-bc51cf08b900 | 2026-10 / 2026-10-12 | b69a7d189dbc6ed9ff042cf44115c7c4 |
| 36 | eec50614-788d-429b-99a4-fc8938a86dda | 2026-10 / 2026-10-12 | bd72d1e53f349a42c0e7559165ddad53 |
| 37 | 0ea530e7-12ac-41fa-9f6e-972b24662a72 | 2026-10 / 2026-10-19 | d06b0ea5ac3615e1d65288889c482cd7 |
| 38 | 297c7ed8-4aca-40d5-b4de-5fcb3e2ddb83 | 2026-10 / 2026-10-19 | 37ca5cf9752262c7decc6c407f84379f |
| 39 | 3048b190-31e0-49b1-a255-ce73e6e15fc0 | 2026-10 / 2026-10-19 | ed179234d3e62ac4e6d126e53d8c27a6 |
| 40 | 70c31ae5-6083-46cb-90ad-fdc24726b6b6 | 2026-10 / 2026-10-19 | 4302180a1a22a2acf07fb4d59c622505 |
| 41 | 812979d0-43ac-4075-b38f-4c9aa455cd4b | 2026-10 / 2026-10-19 | da74fc4325fa48b71bdb343da2831e8d |
| 42 | d1961919-8c05-42e8-8a06-4ed1fabb13c0 | 2026-10 / 2026-10-19 | 0df9d034ec2481a7ede96d1be7235ad6 |
| 43 | 0a3a8c13-12cb-4430-a933-2941221c0c77 | 2026-10 / 2026-10-26 | 3a22cba84e5d83a88385f7ef77bd8351 |
| 44 | 4505777b-13e3-4187-9839-618ebe186f22 | 2026-10 / 2026-10-26 | 746814ad793791e7db81f3bbe7c10167 |
| 45 | 895ebf6e-6bf0-419d-bf9a-418d048a42a7 | 2026-10 / 2026-10-26 | 5f4b890353690103d5098ce3b7ab8401 |
| 46 | 92a0f909-6458-4d34-9144-9d60eeede33f | 2026-10 / 2026-10-26 | bc536f2a8a45ef3aa28d25be5afc2326 |
| 47 | c48478ef-8b3d-4c7f-bd48-cc99659e99f7 | 2026-10 / 2026-10-26 | 5b54dd3614dd950ed4f8380819507212 |
| 48 | d8ed3671-6865-42b6-a4a2-06b31c9051e6 | 2026-10 / 2026-10-26 | 5ea1c950e30ba5dc6d620481985d3429 |
| 49 | 0624fabe-a3c8-4930-aa41-8ed800a28eea | 2026-11 / 2026-11-02 | cbcefbb0cc47f8047a2ae90d548476a3 |
| 50 | 3f5884ea-ca12-41dc-89ce-ebc67db27fe8 | 2026-11 / 2026-11-02 | 0e1ea770f87e86d096f0eaf2d9db17ee |
| 51 | 89797ce3-58e0-4c9d-b107-79eca71e4161 | 2026-11 / 2026-11-02 | f47da6a3b28c1341a43e9219fe94678e |
| 52 | a42b1b2e-4f55-4915-a20b-bd411b4d81a0 | 2026-11 / 2026-11-02 | 11d4891fb37f950cf87870fcdfbf07c7 |
| 53 | d2307a35-1f41-4402-ab4d-c03ed4305f50 | 2026-11 / 2026-11-02 | 0541832b36c9a3549e2f2a626e64f166 |
| 54 | fd34b0d7-86c2-4d0e-a519-de2317e0ab26 | 2026-11 / 2026-11-02 | d1d4c58bf0d7464f6e9b15a5a70045c9 |
| 55 | 207430a6-c9cd-4acb-9a7d-962c078b0623 | 2026-11 / 2026-11-09 | a26f9291604e01fd05be81bdf631324d |
| 56 | 5666a624-05b5-4408-bc11-5d208851b216 | 2026-11 / 2026-11-09 | 722d1f66f1c56d6bd4f6fa10a3a89639 |
| 57 | a57bf7af-43e1-46ba-9bb6-9ee511b81e05 | 2026-11 / 2026-11-09 | ea7de78a84743f3237721844f561067c |
| 58 | 73dd0453-aec2-4612-b710-071a372f88ad | 2026-11 / 2026-11-16 | a42c9901944444fda961027d8522659a |
| 59 | bc718d5f-dc21-4e7d-914a-dd3a6debaeb6 | 2026-11 / 2026-11-16 | df597794e4861f4b4f54031ec238d1a0 |
| 60 | f1a321d8-5528-4afe-8fb7-79204f49f3dc | 2026-11 / 2026-11-16 | 26b108cf2118b114e96ce604ad4cd87b |
| 61 | 584ef4d6-fa9d-4dd8-803c-cab68ac67a67 | 2026-11 / 2026-11-23 | 19d23787c86a9266631a777c45dc4f6f |
| 62 | a4cd05e7-47e7-4e0d-8af8-dad6c7505744 | 2026-11 / 2026-11-23 | ec215c024147f0c57930e7db9b4cd0a6 |
| 63 | fc138193-f76a-476c-a394-b49d2e68dde2 | 2026-11 / 2026-11-23 | c632647833f336de856cd06345695c20 |
| 64 | 0f168663-afb1-49a7-90a8-39197ad7729e | 2026-11 / 2026-11-30 | 9718ffd90f1709b57483f8fb8ebdb708 |
| 65 | 594a4559-c1b1-4ad1-88e6-4c7834052831 | 2026-11 / 2026-11-30 | bcee1559efcdb98b26265d9cebecb7c2 |
| 66 | def65ad3-6f87-4889-802f-202550a9af49 | 2026-11 / 2026-11-30 | 603d28c1b5776e086c453623e10ff665 |

## 3. 前置条件与锁

66条逐行验证：固定ID、student、batch、from entity、日期/月、老师、科目、回数、时长、单价、费用、状态、created_at、updated_at及完整行MD5全部一致；均为active billable planned，无void、actual、bill relation、bill JSON、income、School Cash linkage、账户流水、有效工资明细或锁定月结；不属于R1C-A 52-ID。迁移前R1C-B候选函数返回66/66 `excluded / scope_mismatch`且没有其他账单风险。

事务取得：

- `school_lesson_records`：`ACCESS EXCLUSIVE`；
- feature gate、business entity、student、bill、bill lesson、billing identity、income、School Cash linkage、账户流水、月结、工资锁及工资明细：`SHARE`；
- migration batch/item：`SHARE ROW EXCLUSIVE`。

该锁序列覆盖目标lesson修改/新actual关联、账单证据、收入与School资金链、月结/工资、gate变化及审计重复写入。Cash为独立数据库，本阶段不写Cash；其三表在正式事务前后分别只读取count/hash，并以固定66 UUID扫描三表JSON文本，直接引用数为0。

## 4. updated_at与事务内字段守卫

沿用R1C-A已验收方案：持有`school_lesson_records ACCESS EXCLUSIVE`后，仅在事务内精确停用`trg_school_lesson_records_updated_at`，更新固定66 UUID，异常分支及正常分支均恢复trigger；随后验证trigger为`O`。事务内逐行比较`to_jsonb(lesson) - 'business_entity_id'`与before snapshot，并验证66/66原`updated_at`完全不变。

按月授权字段外哈希前后相同：

| 月份 | before immutable hash | after immutable hash |
|---|---|---|
| 2026-09 | `c974fb3133a066dd3e9c3fa0a2cf9435` | `c974fb3133a066dd3e9c3fa0a2cf9435` |
| 2026-10 | `37ac7a2029048912895df80545024985` | `37ac7a2029048912895df80545024985` |
| 2026-11 | `a0b844c97028142c6117672df666895a` | `a0b844c97028142c6117672df666895a` |

## 5. ROLLBACK演练与正式执行

迁移SQL SHA-256在演练与正式执行前均为：

`231cfe21932538948aea06af796ecb85095abe5c9c7ec05b8e14169bb11ae4f3`

同一SQL先以`r1c_c_b_commit=0`执行。事务内66条更新、1+66审计、deferred constraints、候选及全部基线断言均通过；ROLLBACK后：

- batch residue = 0；
- item residue = 0；
- 青空目标归属 residue = 0；
- 个人名义恢复 = 66；
- 66条完整行聚合MD5 = `ee7c476c9c56c926eda083008197450a`；
- 李天伦11条聚合MD5 = `da6361fd7e73fb2526e1fbb786bd4eb8`；
- updated_at trigger = enabled；
- School目标与Cash基线零变化。

随后以SHA不变的同一文件、`r1c_c_b_commit=1`正式执行并成功`COMMIT`。没有跳过、扩大或动态补入记录。

## 6. 审计结果

- batch ID：`c1000000-0000-4000-8000-202607289999`；
- migration key：`r1c-c-b:2026-09-11:zhang-planned-business-entity:personal-to-aosora`；
- 既有batch schema的`target_year_month`为单月必填字段，本批记录授权范围首月`2026-09`；完整三个月范围同时保存在`source_generation_batches.months`、批准信息及66个item各自的`target_year_month`中；
- migration manifest hash：`ee7c476c9c56c926eda083008197450a`；
- 迁移审计执行时间（batch/item `executed_at`）：`2026-07-27 15:44:04.086187+00`；该值是审计执行证据，不冒充数据库commit timestamp；
- 新审计：1 batch + 66 item，全部`executed`；
- 每个item包含original/after完整快照、before/after hash、original updated_at、学生、月份、原批次、from/to、批准及证据；
- R1C-A原1+52审计count/hash保持`1 / e8c2013a460374be5b2a3b82564876c4`与`52 / 6399cd2b368e30e5ca43e113957bfa5f`，未修改。

## 7. 李天伦11-ID永久排除

以下11条均不在66-ID manifest，postdeploy逐行MD5与R1C-C-A冻结值一致；聚合MD5前后均为`da6361fd7e73fb2526e1fbb786bd4eb8`。完整行不变即status、is_billable、business_entity_id、planned/actual关联字段及其他字段均未变化；未删除、作废、清理或修复。

| ID | before MD5 = after MD5 |
|---|---|
| `f256bca9-fac5-4909-b113-8077efd27d65` | `39a3d5ccc1755499b54595b303c49cc5` |
| `a722a49e-dbe5-447d-8068-fd5fb743f6ab` | `f7b3636134ebd23191c5b6ea37c0d204` |
| `265f4d3d-2372-42e3-aec3-b963bbdddf95` | `6620ad1a8085077dbb8e4d4317f0af8f` |
| `e890424d-407d-4fc2-b8ad-84745b242cdd` | `b707e69e1ece74e9b6edf2e44483f512` |
| `552c54e3-2d0c-4607-962d-aad39dfff7f7` | `82a2d4d62f96c07a3bb65a2c2e8b92a1` |
| `b186fa1c-a56b-4ed7-b566-178a5708ae96` | `3ac247e72ba1e8e55484d5bb96052a9c` |
| `ac16b068-a58b-4ca5-be95-7c57c3f1b82b` | `0c32bffa1f171517a1c034b0cb6d1195` |
| `39aa30ab-d66c-43c0-bbde-3b3a35d71fb7` | `c46cc189dac5ac53ba455838af5859e0` |
| `f759623b-ce28-4c5f-8556-95c4381b6b1b` | `4fff65ea2500ba5613d3927f2cd8042c` |
| `c582a187-32f6-4a24-bb7b-d590b25c1854` | `91679ca8877c299bf02faaf56fdfee8c` |
| `dc06b98c-360f-4661-a294-52ecb82830a7` | `04099067c0430d749487c2170b1ec5d8` |

R1C-B青空范围审计中11条仍全部为`excluded / scope_mismatch`，没有成为新候选。

## 8. 候选与8月回归

迁移后DB权威候选函数返回：2026-09为24/52/JPY520,000，2026-10为24/52/JPY520,000，2026-11为18/41/JPY410,000；总计66/145/JPY1,450,000，UUID数组与固定66-ID审计manifest完全一致。

2026-08候选集合继续与R1C-A固定52-ID完全一致：张倬闻30/65/JPY650,000，孙陈锋22/44/JPY374,000，总计52/109/JPY1,024,000。候选与金额均由DB函数返回，没有前端过滤或计算，本阶段未修改候选RPC/API/page。

## 9. School/Cash与actual前后基线

除lesson表内固定66行的唯一授权字段和新增R1C-C-B审计外，下列count/hash前后完全一致：

| 对象 | 迁移前 | 迁移后 |
|---|---|---|
| tuition bill | `9 / 0f0323b79e7ff1c47ff6b90c75477a2d` | 相同 |
| income | `42 / 2a4897b752f272b1f192045418b4940c` | 相同 |
| billing identity | `7 / 4d91a5a1074f90389822fc367a7e5467` | 相同 |
| bill lesson | `121 / 09dfee7d8833e09384fb41a84f2959e0` | 相同 |
| R1C-A batch | `1 / e8c2013a460374be5b2a3b82564876c4` | 相同 |
| R1C-A item | `52 / 6399cd2b368e30e5ca43e113957bfa5f` | 相同 |
| School Cash linkage | `35 / 6e76a4dc2fc2954b28b7ad0a8d203ba0` | 相同 |
| School账户流水 | `185 / 8f4f6c4365035f6c36bac59ba986b28b` | 相同 |
| actual lesson | `229 / fe752c448bb4d38af498136d3149f14a` | 相同 |
| student settlement | `15 / 7925cf3018bd0e669cd29710f6593238` | 相同 |
| teacher wage lock | `95 / 7bbe108d3ac73d4f21530793bf141bc6` | 相同 |
| teacher wage detail | `556 / 6204dc666b3b8e0f64fac901ecf0686a` | 相同 |
| Cash request | `34 / ba0571247a869843c3ddda9075ea78dd` | 相同 |
| Cash CNY transaction | `59 / 27dfd0cb3bf85c5cc34677372b29502a` | 相同 |
| Cash JPY transaction | `31 / 95ab7cf8a8d167e9b052d3fc6b64614b` | 相同 |

lesson整表保持626行；完整行哈希按预期由`ca32bb31f5b9c3d98ece7762562ee71c`变为`4fb1901c888d56cb29c05e387490ca75`。事务内授权投影基线证明仅固定66行`business_entity_id`变化；正式postdeploy投影为`626 / 2b0551a3ba418843fac220a3792f64c0`。actual执行前后均为229行及同一哈希，没有并发新增actual。

## 10. R0 gate与拒绝探针

最终gate仍为：

- `student_tuition_preview = validation_preview_only`；
- `student_tuition_generate = blocked`；
- `student_tuition_cash_submit = blocked`。

`school_tuition_r1b_r0_entry_probes.sql`验证四个生成入口全部返回`TUITION_GENERATION_BLOCKED`，Cash gate返回`TUITION_CASH_SUBMISSION_BLOCKED`，事故income Cash RPC同样被拒绝；无入口写入成功。

## 11. 执行的SQL/RPC及数据库变更分类

执行文件：

1. `/private/tmp/r1c_c_b_preflight_readonly.sql`：School迁移前只读基线与逐行指纹；
2. `/private/tmp/r1c-c-b-cash-baseline.sql`：Cash迁移前、rollback后、正式迁移后三次只读基线；
3. `sql/current/school_tuition_r1c_c_b_fixed_66_business_entity_migration.sql`：先`r1c_c_b_commit=0`，后以同一SHA执行`r1c_c_b_commit=1`；
4. `sql/current/school_tuition_r1c_c_b_postdeploy_readonly.sql`：正式迁移后全量只读验收；
5. `sql/current/school_tuition_r1b_r0_entry_probes.sql`：R0阻断入口探针；
6. `/private/tmp/r1c-c-b-school-rollback-verify.sql`及`/private/tmp/r1c-c-b-school-final-readonly.sql`：零残留与补充只读哈希；
7. `/private/tmp/r1c-c-b-cash-fixed-66-reference-scan.sql`：固定66 UUID在Cash request/CNY/JPY三表的只读直接引用扫描，结果0。

只读验收调用`school_list_student_tuition_candidates(...)`。R0探针调用四个学费生成/收入入口、feature gate检查及事故Cash入口，均在写入前按预期拒绝。没有成功调用写RPC。

数据库分类：

- 永久DDL：0；没有修改审计schema；
- 事务临时DDL：临时manifest/snapshot/baseline表，以及持锁期间停用/恢复一个updated_at trigger；
- ROLLBACK演练DML：66 UPDATE + 1 batch INSERT + 66 item INSERT，全部回滚且残留0；
- 正式真实DML：精确66条lesson `business_entity_id` UPDATE + 1 batch INSERT + 66 item INSERT；
- Cash DB DDL/DML：0；
- bill/income/Cash/账户流水/actual/月结/工资DML：0。

首次沙箱内连接因DNS不可用未到达数据库；一次School preflight只读排序别名、一次Cash只读错误表名、一次补充School只读列别名查询失败，均未写入，修正临时只读查询后通过。正式迁移文件及postdeploy文件未因此临时修改数据库事实。

## 12. 文件、Git状态与停止点

本阶段新增：

- `sql/current/school_tuition_r1c_c_b_fixed_66_business_entity_migration.sql`；
- `sql/current/school_tuition_r1c_c_b_postdeploy_readonly.sql`；
- `docs/school-v2-r1c-c-b-business-entity-migration-report-20260728.md`。

本阶段更新：

- `docs/current-status.md`。

未执行`git add`、commit或push。R1B临时审查文件保持未跟踪且未修改，SHA-256仍为`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。未开始R1D或其他后续阶段。

建议审查通过后的精确暂存清单即上述4个R1C-C-B文件；建议commit message：

`feat: migrate approved future tuition lessons to Aozora entity`
