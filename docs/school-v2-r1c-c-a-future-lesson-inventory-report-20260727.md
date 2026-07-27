# School V2 学费链 P0 R1C-C-A 实施报告：2026-09 以后未来课时清单只读审计

实施日期：2026-07-27
实施范围：仅调查并冻结 2026-09 以后 School lesson 当前范围
实施前 Git HEAD：`662896b639cc020bb8e7f9d7f6b279801534fefe`
建议 commit message（仅供审查后授权）：`docs: audit future tuition lesson inventory`

## 1. 审计结论与停止原因

R1C-C-A 已完成严格只读审计，但不能形成 R1C-C-B 迁移授权清单，现按强制停止条件停止：

- 仓库、Git 历史、历史 SQL、报告和已保存任务原文中均没有固定的原始 68-ID manifest，也没有原 68 行哈希；结论必须标记为 `68-ID manifest unavailable`；
- 当前数据库 `app_type = school AND year_month >= 2026-09` 的 R1C-B 原始盘点是 77 行，但其中只有 73 行是 planned，另有 4 行 actual；
- 当前可复现的“active、billable、字段完整、且没有有效 linked actual”的 planned 子集恰好是 68 行，但它只是当前查询结果，不能冒充历史原 68；
- 当前还存在 70 条 `status=planned`、66 条非测试来源且干净未履约的张倬闻记录等其他合理口径；
- 李天伦范围存在测试文件来源、`pending_makeup`、linked actual、同业务指纹不同 ID，以及一条 planned 关联两条 actual 的异常；
- 因原 68 无法恢复且存在多个可能口径、状态异常影响范围，本阶段不得推断批准，不得开始 R1C-C-B。

本阶段数据库 DDL = 0，School 业务 DML = 0，Cash DDL/DML = 0；没有创建、修改或删除 lesson、actual、bill、income、Cash、工资、月结或迁移审计记录。

## 2. “68”口径来源调查

按任务要求依次调查后的证据分级如下。

### 2.1 直接证据

- 已提交仓库中最早且唯一能追溯的数字来源，是 R1C-A 报告中“未执行 9 月以后 68 条候选”的汇总表述；该表述由 commit `814b9bbd2d563ad260ef087d1baedee05535c0c8` 引入。
- R1C-B 任务原文继续把“9 月以后 68 条候选”作为禁止处理范围，但没有附 UUID。
- R1C-B 实施报告的当前盘点是 77 行。
- Git 全历史、SQL `VALUES`/UUID manifest、旧审计 txt/md 和当前任务附件中均未发现 68 个固定 UUID、逐行快照、哈希或可唯一复现的原始查询。

### 2.2 可复现查询结果

当前 DB 可以稳定复现：

| 口径 | 行数 | 小时 | JPY |
|---|---:|---:|---:|
| R1C-B 原始范围：School、`year_month >= 2026-09` | 77 | 167 | 1,736,000 |
| 其中 `lesson_type=planned` | 73 | 159 | 1,632,000 |
| 其中 planned 且 `status=planned` | 70 | 153 | 1,554,000 |
| 当前 active/billable/完整且无 linked actual 的 planned 重建集 | 68 | 149 | 1,502,000 |
| 非测试来源、干净未履约的张倬闻记录 | 66 | 145 | 1,450,000 |

### 2.3 合理推断与未知

- 推断：R1C-B 的 77 是底层审计函数在 `include_excluded=true` 时返回学生/月范围内全部 lesson row，未先限制 `lesson_type=planned`，因此包含 4 条 actual。
- 推断：若从当前 77 排除 4 条 actual、3 条有 linked actual 的 planned、2 条其他 `pending_makeup`，数学上得到当前 68。
- 未知：历史“68”是否使用了上述规则、是否排除了测试导入、是否包含后来已消失的 ID，均无固定证据。

因此不得把当前重建 68 写成“恢复了原 68”。

## 3. 当前 77 条摘要

| 学生 | 月份 | lesson type / status | 行数 | 小时 | JPY |
|---|---|---|---:|---:|---:|
| 张倬闻 | 2026-09 | planned / planned | 24 | 52 | 520,000 |
| 张倬闻 | 2026-10 | planned / planned | 24 | 52 | 520,000 |
| 李天伦 | 2026-10 | planned / planned | 2 | 4 | 52,000 |
| 李天伦 | 2026-10 | planned / pending_makeup | 1 | 2 | 26,000 |
| 张倬闻 | 2026-11 | planned / planned | 18 | 41 | 410,000 |
| 李天伦 | 2026-11 | planned / planned | 2 | 4 | 52,000 |
| 李天伦 | 2026-11 | planned / pending_makeup | 2 | 4 | 52,000 |
| 李天伦 | 2026-11 | actual / completed | 1 | 2 | 26,000 |
| 李天伦 | 2026-11 | actual / cancelled | 1 | 2 | 26,000 |
| 李天伦 | 2026-11 | actual / makeup_completed | 2 | 4 | 52,000 |
| **合计** |  |  | **77** | **167** | **1,736,000** |

当前 77 行完整行聚合 MD5：`cdb615883662acf76b0f07c6e2693d38`。

当前重建 68 行完整行聚合 MD5：`4a0e6c5b58f856d6ee1417315bbe433c`。

审计 SQL 对 77 行逐条输出任务要求的完整业务指纹、整行 JSON、整行 MD5、R1C-B 状态、账单/actual/工资/月结/School 资金链证据及建议分类；报告中的金额和小时均来自同一 DB 查询结果。

## 4. 业务归属与 R1C-B 状态

- 77/77 lesson 当前业务归属均为个人名义 `886a8f7c-0fea-45ac-97d2-15c976ede996`；没有已迁移为青空进学塾或其他实体的行，也没有同一学生/月混合 lesson 业务归属。
- 两名学生当前默认业务归属均为青空进学塾 `2cf7b72f-6e3c-4d09-80f7-7c58593cd466`。
- 因学生默认实体与 lesson 实体不一致，现行 R1C-B 审计函数对 77/77 返回 `candidate_status=excluded`、`exclusion_reason=scope_mismatch`。
- 此不一致只说明当前候选请求范围不匹配，不构成迁移批准。
- 77 行均未 void，必填业务指纹缺失 0，`duration_hours × unit_price != lesson_fee` 为 0，`updated_at != created_at` 为 0。

## 5. 按学生、月份和批次的时间线

| 学生 | 月份 | batch/source | rows（planned/actual） | 小时 | JPY | created/updated |
|---|---|---|---:|---:|---:|---|
| 张倬闻 | 2026-09 | `5254a3fb-dc38-40c2-9cf3-810a79835275` / generator | 24（24/0） | 52 | 520,000 | `2026-07-04 03:43:09.607005+00` |
| 张倬闻 | 2026-10 | 同上 | 24（24/0） | 52 | 520,000 | 同上 |
| 张倬闻 | 2026-11 | 同上 | 18（18/0） | 41 | 410,000 | 同上 |
| 李天伦 | 2026-10 | `lesson_import_20260526104852595_ztof7o` / `测试1_2026-10.xlsx` | 3（3/0） | 6 | 78,000 | `2026-05-26 10:49:07.930607+00` |
| 李天伦 | 2026-11 | `lesson_import_20260526010525470_q14wle` / `测试2_2026-11.xlsx` | 6（3/3） | 12 | 156,000 | `2026-05-26 01:05:26.618+00` |
| 李天伦 | 2026-11 | 无 batch/source | 2（1/1） | 4 | 52,000 | `2026-05-26 01:27:25.016231+00` 至 `01:27:30.636915+00` |

全部 77 行的创建时间均早于 2026-07-27 的“68”报告引用，且均无创建后编辑证据。净 9 条不是在该引用之后新增的课程；当前差异来自筛选口径。不过，由于原 manifest 不存在，不能排除未知的历史删除或不同原始集合。

## 6. 当前 77-ID 完整固定清单

以下分组的 UUID 合计 77 个；逐行完整 JSON 与 MD5 由本阶段只读 SQL 固定输出。

### 6.1 张倬闻 2026-09：24 IDs

```text
15f8147e-5bb0-4cf9-9ba7-3e12f115774e
224015ce-b435-4233-8113-0e6c712b1a18
2bd402cb-fc4d-48cc-b166-400ee4945703
c1f5c7e9-70e4-4c2d-99c8-aadd986cda15
dadcf864-5343-403d-a111-e68b8617f413
f91ecdd8-7442-4879-97b6-67ad8ea99f23
10b62cc8-dd74-4665-a6cd-02cc02924a65
57948b80-89d9-45f2-a99f-3b92aed9f4e8
68da4912-72a8-418c-b30b-335bb9896c63
a9de94c0-954b-452d-95b0-6a8b7d1a5a9e
c79e2ade-4026-4ab3-a316-ba26354abfe2
f693a3d9-fada-48f2-8203-bc33d46ee4dd
5591fb92-2333-460c-95f3-85c6511d6fd4
645cccaf-ae0f-41b3-84d1-e40882a8c85f
82e81ecc-dd23-471e-8402-a45bd8b20eb1
bf38024e-2a5f-422c-ad41-01ec9922e701
dbd6f35a-b0ee-4af8-bcda-e065330f0413
fb066255-82b5-4eb1-9f76-a776c04becc2
1eeb937e-a7ad-4e7c-955d-797b9d979882
21e97cbd-3e18-4c9e-9790-981f885af03a
371e41c5-a659-44a6-87e0-c3a85c9c1b75
966119c6-09c8-4ac5-9c16-6cda13137d87
a9e861d3-6bd6-4b76-ba78-4cc1f3265b43
fd803263-07b6-4b1f-b668-43a482f21c89
```

### 6.2 张倬闻 2026-10：24 IDs

```text
0386bf22-8619-41f2-be6c-5106b8c17cd0
4254095b-9ec1-4651-a9ff-0dffb3a4520f
7e833e2c-3bc0-4c6d-a1ab-204229f43a77
aea933f5-5e3b-4476-b1f0-d781d41312a3
b33f023c-4b0c-495e-8f0b-934ead526421
ff368fb5-94a8-4ea4-b3fc-d62ce499732b
17e58b7d-3fb8-4874-8071-0b1f808e8430
30271ef0-51ee-43ca-9103-1b5ec34255e1
a3a7dd70-1a1e-4078-bce8-d54f10fc57af
cfb5e237-51a3-48b2-a12e-e8f0628e2c51
d9d11e4b-a01c-4535-93cf-bc51cf08b900
eec50614-788d-429b-99a4-fc8938a86dda
0ea530e7-12ac-41fa-9f6e-972b24662a72
297c7ed8-4aca-40d5-b4de-5fcb3e2ddb83
3048b190-31e0-49b1-a255-ce73e6e15fc0
70c31ae5-6083-46cb-90ad-fdc24726b6b6
812979d0-43ac-4075-b38f-4c9aa455cd4b
d1961919-8c05-42e8-8a06-4ed1fabb13c0
0a3a8c13-12cb-4430-a933-2941221c0c77
4505777b-13e3-4187-9839-618ebe186f22
895ebf6e-6bf0-419d-bf9a-418d048a42a7
92a0f909-6458-4d34-9144-9d60eeede33f
c48478ef-8b3d-4c7f-bd48-cc99659e99f7
d8ed3671-6865-42b6-a4a2-06b31c9051e6
```

### 6.3 张倬闻 2026-11：18 IDs

```text
0624fabe-a3c8-4930-aa41-8ed800a28eea
3f5884ea-ca12-41dc-89ce-ebc67db27fe8
89797ce3-58e0-4c9d-b107-79eca71e4161
a42b1b2e-4f55-4915-a20b-bd411b4d81a0
d2307a35-1f41-4402-ab4d-c03ed4305f50
fd34b0d7-86c2-4d0e-a519-de2317e0ab26
207430a6-c9cd-4acb-9a7d-962c078b0623
5666a624-05b5-4408-bc11-5d208851b216
a57bf7af-43e1-46ba-9bb6-9ee511b81e05
73dd0453-aec2-4612-b710-071a372f88ad
bc718d5f-dc21-4e7d-914a-dd3a6debaeb6
f1a321d8-5528-4afe-8fb7-79204f49f3dc
584ef4d6-fa9d-4dd8-803c-cab68ac67a67
a4cd05e7-47e7-4e0d-8af8-dad6c7505744
fc138193-f76a-476c-a394-b49d2e68dde2
0f168663-afb1-49a7-90a8-39197ad7729e
594a4559-c1b1-4ad1-88e6-4c7834052831
def65ad3-6f87-4889-802f-202550a9af49
```

### 6.4 李天伦：11 IDs

| ID | 月/日期 | type / status | batch/source | 行 MD5 |
|---|---|---|---|---|
| `f256bca9-fac5-4909-b113-8077efd27d65` | 2026-10 / 10-01 | planned / planned | 测试1 | `39a3d5ccc1755499b54595b303c49cc5` |
| `a722a49e-dbe5-447d-8068-fd5fb743f6ab` | 2026-10 / 10-08 | planned / planned | 测试1 | `f7b3636134ebd23191c5b6ea37c0d204` |
| `265f4d3d-2372-42e3-aec3-b963bbdddf95` | 2026-10 / 10-15 | planned / pending_makeup | 测试1 | `6620ad1a8085077dbb8e4d4317f0af8f` |
| `e890424d-407d-4fc2-b8ad-84745b242cdd` | 2026-11 / 11-01 | actual / completed | 测试2 | `b707e69e1ece74e9b6edf2e44483f512` |
| `552c54e3-2d0c-4607-962d-aad39dfff7f7` | 2026-11 / 11-01 | planned / planned | 测试2 | `82a2d4d62f96c07a3bb65a2c2e8b92a1` |
| `b186fa1c-a56b-4ed7-b566-178a5708ae96` | 2026-11 / 11-08 | actual / cancelled | 测试2 | `3ac247e72ba1e8e55484d5bb96052a9c` |
| `ac16b068-a58b-4ca5-be95-7c57c3f1b82b` | 2026-11 / 11-08 | planned / planned | 测试2 | `0c32bffa1f171517a1c034b0cb6d1195` |
| `39aa30ab-d66c-43c0-bbde-3b3a35d71fb7` | 2026-11 / 11-15 | planned / pending_makeup | 无 | `c46cc189dac5ac53ba455838af5859e0` |
| `f759623b-ce28-4c5f-8556-95c4381b6b1b` | 2026-11 / 11-15 | planned / pending_makeup | 测试2 | `4fff65ea2500ba5613d3927f2cd8042c` |
| `c582a187-32f6-4a24-bb7b-d590b25c1854` | 2026-11 / 11-22 | actual / makeup_completed | 无 | `91679ca8877c299bf02faaf56fdfee8c` |
| `dc06b98c-360f-4661-a294-52ecb82830a7` | 2026-11 / 11-22 | actual / makeup_completed | 测试2 | `04099067c0430d749487c2170b1ec5d8` |

## 7. 原 68-ID 清单

`68-ID manifest unavailable`

原报告只有汇总数字，没有固定 UUID、逐行哈希或可唯一复现查询，因此以下字段均不可恢复：原 68 ID、原始逐行快照、原始行哈希、原集合中后来缺少的行、同 ID 业务指纹变化。

当前重建 68 的固定集合仅作诊断：上述张倬闻 66 IDs，加李天伦测试1来源的 `f256bca9-fac5-4909-b113-8077efd27d65`、`a722a49e-dbe5-447d-8068-fd5fb743f6ab`。不得将该集合用于迁移或称为原 68。

## 8. 原 68 / 当前 77 集合差异

| 要求分组 | 结果 | 原因 |
|---|---|---|
| `current_77_intersect_original_68` | unavailable | 原 68 固定 UUID 不存在 |
| `current_77_only` | unavailable | 不能与未知集合比较 |
| `original_68_only` | unavailable | 无法识别已经不在 DB 的原 UUID |
| `same_id_business_fingerprint_changed` | unavailable | 原逐行哈希未保存 |

可以精确报告的只是“当前 77 减当前重建 68”的 9 行：

| ID | 排除重建 68 的直接原因 |
|---|---|
| `265f4d3d-2372-42e3-aec3-b963bbdddf95` | planned / `pending_makeup` |
| `e890424d-407d-4fc2-b8ad-84745b242cdd` | actual row |
| `552c54e3-2d0c-4607-962d-aad39dfff7f7` | planned 已关联有效 actual |
| `b186fa1c-a56b-4ed7-b566-178a5708ae96` | actual row |
| `ac16b068-a58b-4ca5-be95-7c57c3f1b82b` | planned 已关联有效 actual |
| `39aa30ab-d66c-43c0-bbde-3b3a35d71fb7` | planned / `pending_makeup` |
| `f759623b-ce28-4c5f-8556-95c4381b6b1b` | planned / `pending_makeup` 且已关联 2 条 actual |
| `c582a187-32f6-4a24-bb7b-d590b25c1854` | actual row |
| `dc06b98c-360f-4661-a294-52ecb82830a7` | actual row |

这 9 行全部属于李天伦，全部创建于 2026-05-26；没有张倬闻后来追加行的证据。

## 9. 下游关系审计

当前 77 行：

| 风险链 | 命中行数 |
|---|---:|
| normalized bill lesson | 0 |
| bill JSON snapshot | 0 |
| billing identity | 0 |
| downstream income | 0 |
| School Cash linkage | 0 |
| School account transaction | 0 |
| R1C-A 52-ID migration item | 0 |
| planned with linked actual | 3 |
| effective wage detail | 0 |
| locked student settlement | 0 |

Cash DB 额外只读核对 current 77 UUID 在 request external event/reference/payload 以及 CNY/JPY transaction external source/reference 中的可识别直接引用，结果均为 0。School 侧 bill/income/linkage/account 链为 0，因此也不存在可沿正式 School 链追踪到 Cash 的关系。

没有发现已有账单、income 或 Cash 链，但 linked actual 异常已经足以阻止把 77 或重建 68 整体当作迁移范围。

## 10. 疑似重复与 actual 异常

1. 李天伦 2026-11-15 有两个业务指纹相同但 ID 不同的 pending_makeup planned：
   `39aa30ab-d66c-43c0-bbde-3b3a35d71fb7`、`f759623b-ce28-4c5f-8556-95c4381b6b1b`。
2. 李天伦 2026-11-22 有两个业务指纹相同但 ID 不同的 makeup_completed actual：
   `c582a187-32f6-4a24-bb7b-d590b25c1854`（non-billable）、`dc06b98c-360f-4661-a294-52ecb82830a7`（billable）。
3. planned `f759623b-ce28-4c5f-8556-95c4381b6b1b` 同时关联上述两条 actual。
4. `552c54e3-2d0c-4607-962d-aad39dfff7f7` 关联 completed actual `e890424d-407d-4fc2-b8ad-84745b242cdd`。
5. `ac16b068-a58b-4ca5-be95-7c57c3f1b82b` 关联 cancelled actual `b186fa1c-a56b-4ed7-b566-178a5708ae96`。

这些异常只报告，不修复，也不在 R1C-C-A 判定业务所有权。

## 11. 建议进入业务确认的清单

分类只是建议，不是迁移批准。

### 11.1 `recommended_for_business_confirmation`

- 张倬闻 66 条；145 小时；JPY 1,450,000；
- 即本报告 6.1、6.2、6.3 的全部 UUID；
- 当前均为 active、billable、字段完整、未 void、无 linked actual、无账单/资金/工资/月结关系；
- 全部来自原生成批次 `5254a3fb-dc38-40c2-9cf3-810a79835275`；
- 仍须业务负责人确认 2026-09 至 2026-11 计划真实有效并批准目标实体。

### 11.2 `requires_manual_review`

共 4 条、8 小时、JPY 104,000：

- `f256bca9-fac5-4909-b113-8077efd27d65`、`a722a49e-dbe5-447d-8068-fd5fb743f6ab`：active planned 且无下游，但来源文件明确为 `测试1_2026-10.xlsx`，业务所有权未知；
- `265f4d3d-2372-42e3-aec3-b963bbdddf95`：测试1来源且 `pending_makeup`；
- `39aa30ab-d66c-43c0-bbde-3b3a35d71fb7`：无 batch/source、`pending_makeup`，并与另一行同业务指纹。

### 11.3 `exclude_from_future_migration`

共 7 条、14 小时、JPY 182,000：

- 4 条 actual：`e890424d-407d-4fc2-b8ad-84745b242cdd`、`b186fa1c-a56b-4ed7-b566-178a5708ae96`、`c582a187-32f6-4a24-bb7b-d590b25c1854`、`dc06b98c-360f-4661-a294-52ecb82830a7`；
- 3 条已有 linked actual 的 planned：`552c54e3-2d0c-4607-962d-aad39dfff7f7`、`ac16b068-a58b-4ca5-be95-7c57c3f1b82b`、`f759623b-ce28-4c5f-8556-95c4381b6b1b`。

“排除”仅针对未来 business entity 迁移候选，不代表授权删除、作废或修复这些历史记录。

## 12. School 前后基线

审计前后完全一致，未观察到并发变化：

| 表/范围 | count | MD5 |
|---|---:|---|
| tuition bill | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| billing identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| bill lesson | 121 | `09dfee7d8833e09384fb41a84f2959e0` |
| lesson records | 626 | `ca32bb31f5b9c3d98ece7762562ee71c` |
| planned lesson | 397 | `58d1218cd3ce30074a2daf3447ee6855` |
| actual lesson | 229 | `fe752c448bb4d38af498136d3149f14a` |
| R1C-A migration batch | 1 | `e8c2013a460374be5b2a3b82564876c4` |
| R1C-A migration item | 52 | `6399cd2b368e30e5ca43e113957bfa5f` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| School account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| student settlement | 15 | `7925cf3018bd0e669cd29710f6593238` |
| teacher wage lock | 95 | `7bbe108d3ac73d4f21530793bf141bc6` |
| teacher wage detail | 556 | `6204dc666b3b8e0f64fac901ecf0686a` |

actual 前后均为 229，哈希一致；本阶段没有创建、修改或删除 actual，也没有观察到审计期间的正常并发 actual 变化。

## 13. Cash 前后基线

Cash 仅执行 SELECT，前后完全一致：

| 表 | count | MD5 |
|---|---:|---|
| `home_external_transaction_requests` | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| `home_cny_transactions` | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| `home_jpy_transactions` | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

## 14. R0 gate 与回归选择

最终只读核对：

- `student_tuition_preview = validation_preview_only`；
- `student_tuition_generate = blocked`；
- `student_tuition_cash_submit = blocked`。

本阶段没有调用五个写入口拒绝探针。原因是本阶段授权是严格只读审计，gate 与现有 R1C-B 候选函数存在性均已只读确认，School 核心函数/业务基线无变化；执行写函数探针不会增加本阶段范围证据。没有修改 probe SQL，没有解除 gate。

## 15. 执行过的 SQL 与 RPC

执行：

- `sql/current/school_tuition_r1c_c_a_future_lesson_inventory_readonly.sql`：三次，均为 SELECT/DO-only；初版形成结果，补充下游摘要后以相同范围复跑，最后再次取得终态基线；
- `sql/current/cash_tuition_r1a_business_baseline_readonly.sql`：Cash 前后只读基线；
- School/Cash ad hoc SELECT：前后 count/hash、Git/DB范围证据、batch 时间线、直接引用及异常核对；
- 既有只读函数 `school_list_student_tuition_candidates(uuid,uuid,text,boolean)`：仅由审计 SQL 以 `include_excluded=true` 调用，未创建或替换函数。

未调用任何写 RPC。两个命令级无写失败也记录如下：一次非交互 shell 未加载 `load_both_db`，在连接前退出；一次 Cash SELECT 使用了不存在的猜测表名并由 PostgreSQL 在解析阶段拒绝，随后改用仓库权威 Cash 基线 SQL。两者均无数据库写入。

## 16. 数据库零写入证明

- 审计文件静态限定为 `SELECT/DO`，不含 DDL/DML、临时表、权限语句、函数创建/替换或写 RPC；
- 所有成功 DB 命令均为 SELECT 或只含 SELECT 的 DO 断言；
- School 全业务基线前后 count/hash 一致；
- Cash 三表前后 count/hash 一致；
- lesson/actual、R1C-A audit、bill/income、工资、月结及资金链均无变化。

## 17. Git 状态与停止点

本阶段只新增/修改：

- `sql/current/school_tuition_r1c_c_a_future_lesson_inventory_readonly.sql`；
- `docs/school-v2-r1c-c-a-future-lesson-inventory-report-20260727.md`；
- `docs/current-status.md`。

没有执行 `git add`、commit 或 push。R1B 临时审查文件 `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` 保持未跟踪、未修改、未暂存，SHA-256 应继续为 `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`。

建议审查通过后精确暂存：

```sh
git add -- \
  docs/current-status.md \
  docs/school-v2-r1c-c-a-future-lesson-inventory-report-20260727.md \
  sql/current/school_tuition_r1c_c_a_future_lesson_inventory_readonly.sql
```

建议 commit message：`docs: audit future tuition lesson inventory`。

## 18. R1C-C-B 开始前业务负责人必须回答的问题

1. 是否确认张倬闻 2026-09 至 2026-11 的 66 条计划均已发给学生、仍有效，并批准从个人名义迁移到青空进学塾？
2. 李天伦 `测试1_2026-10.xlsx` 的两条 active planned 是否是真实业务课，还是测试残留？
3. 李天伦 3 条 pending_makeup、两个相同 planned 指纹、两个相同 actual 指纹及一 planned 对两 actual 应如何由独立人工/修复阶段处理？
4. 后续固定 manifest 是否明确只允许 active、billable、无 linked actual 的 planned，并永久排除 actual 和已有履约证据行？
5. 业务负责人批准的最终 UUID 集合、from/to entity、学生/月/批次范围分别是什么？
6. 是否同意历史“68”只能保留为 unavailable 汇总，不再作为后续迁移授权依据？

在这些问题得到明确批准并形成新的固定 UUID manifest 前，不得开始 R1C-C-B。
