# School V2 学费链P0：R1D-C-B-A2 R1C-C-B固定66条收费归属受控回填实施报告

- 实施日期：2026-07-28
- Git基线：`44209d133d04af3e101374ccacc6e11e41b1e03c`（实施前HEAD与`origin/main`一致）
- School正式决定/执行时间：`2026-07-28 04:33:07.050555+00`
- 结论：完成；精确66条planned lesson仅回填5个授权字段。
- Git状态：停在审查点；未执行`git add`、commit或push。

## 1. 范围与正式结果

本阶段只处理R1D-C-A固定manifest中migration batch `c1000000-0000-4000-8000-202607289999`对应的66个静态UUID。migration audit只作交叉证据，正式UPDATE对象只来自SQL内显式66行VALUES，没有按batch、学生、月份或当前状态动态扩张。

回填字段：

- `billing_month`
- `billing_week_start_date`
- `student_settlement_month`
- `billing_month_source = approved_r1c_c_b_manifest`
- `billing_month_decided_at = 2026-07-28 04:33:07.050555+00`

`scheduled_lesson_date`未回填，66/66仍为NULL。A2的66条共用一个全新决定/执行时间，没有复用A1的`2026-07-28 00:27:52.779654+00`，也没有使用migration `executed_at`、旧`updated_at`、审计时间或Git时间。

正式结果：

| 月份 | 条数 | 小时 | JPY | 合法month/week |
|---|---:|---:|---:|---:|
| 2026-09 | 24 | 52 | 520,000 | 24/24 |
| 2026-10 | 24 | 52 | 520,000 | 24/24 |
| 2026-11 | 18 | 41 | 410,000 | 18/18 |
| 合计 | 66 | 145 | 1,450,000 | 66/66 |

正式业务DML仅为一次精确66行`school_lesson_records`五字段UPDATE。没有新增或修改bill、income、identity、relation、migration audit、override audit、School资金链、账户流水、月结、工资、actual或Cash记录。

## 2. 固定66 UUID与before fingerprint

来源：`docs/school-v2-r1d-c-a-fixed-manifests-20260728.md`第2.1节中migration batch为`c1000000-0000-4000-8000-202607289999`的66行。每行静态冻结UUID、student、原生成batch、`updated_at`、old31 hash、billing month/week、student settlement month和source。

正式执行前逐行验证：

- lesson存在且为School planned；
- UUID、student、原生成batch、`updated_at`与静态manifest一致；
- 剔除6个R1D-B字段后的old31 MD5一致；
- old31 JSON与R1C-C-B migration item的`after_row_snapshot`一致；
- 六个R1D-B字段全部NULL；
- migration audit交叉匹配66/66；
- 7个R1D-B check均为validated；
- month/week为ISO周一合法组合，student settlement等于billing month；
- 66条仍是candidate，且无linked actual、无normalized bill relation；
- 当前汇总精确为66条/145小时/JPY1,450,000。

固定UUID：

1. `0386bf22-8619-41f2-be6c-5106b8c17cd0`
2. `0624fabe-a3c8-4930-aa41-8ed800a28eea`
3. `0a3a8c13-12cb-4430-a933-2941221c0c77`
4. `0ea530e7-12ac-41fa-9f6e-972b24662a72`
5. `0f168663-afb1-49a7-90a8-39197ad7729e`
6. `10b62cc8-dd74-4665-a6cd-02cc02924a65`
7. `15f8147e-5bb0-4cf9-9ba7-3e12f115774e`
8. `17e58b7d-3fb8-4874-8071-0b1f808e8430`
9. `1eeb937e-a7ad-4e7c-955d-797b9d979882`
10. `207430a6-c9cd-4acb-9a7d-962c078b0623`
11. `21e97cbd-3e18-4c9e-9790-981f885af03a`
12. `224015ce-b435-4233-8113-0e6c712b1a18`
13. `297c7ed8-4aca-40d5-b4de-5fcb3e2ddb83`
14. `2bd402cb-fc4d-48cc-b166-400ee4945703`
15. `30271ef0-51ee-43ca-9103-1b5ec34255e1`
16. `3048b190-31e0-49b1-a255-ce73e6e15fc0`
17. `371e41c5-a659-44a6-87e0-c3a85c9c1b75`
18. `3f5884ea-ca12-41dc-89ce-ebc67db27fe8`
19. `4254095b-9ec1-4651-a9ff-0dffb3a4520f`
20. `4505777b-13e3-4187-9839-618ebe186f22`
21. `5591fb92-2333-460c-95f3-85c6511d6fd4`
22. `5666a624-05b5-4408-bc11-5d208851b216`
23. `57948b80-89d9-45f2-a99f-3b92aed9f4e8`
24. `584ef4d6-fa9d-4dd8-803c-cab68ac67a67`
25. `594a4559-c1b1-4ad1-88e6-4c7834052831`
26. `645cccaf-ae0f-41b3-84d1-e40882a8c85f`
27. `68da4912-72a8-418c-b30b-335bb9896c63`
28. `70c31ae5-6083-46cb-90ad-fdc24726b6b6`
29. `73dd0453-aec2-4612-b710-071a372f88ad`
30. `7e833e2c-3bc0-4c6d-a1ab-204229f43a77`
31. `812979d0-43ac-4075-b38f-4c9aa455cd4b`
32. `82e81ecc-dd23-471e-8402-a45bd8b20eb1`
33. `895ebf6e-6bf0-419d-bf9a-418d048a42a7`
34. `89797ce3-58e0-4c9d-b107-79eca71e4161`
35. `92a0f909-6458-4d34-9144-9d60eeede33f`
36. `966119c6-09c8-4ac5-9c16-6cda13137d87`
37. `a3a7dd70-1a1e-4078-bce8-d54f10fc57af`
38. `a42b1b2e-4f55-4915-a20b-bd411b4d81a0`
39. `a4cd05e7-47e7-4e0d-8af8-dad6c7505744`
40. `a57bf7af-43e1-46ba-9bb6-9ee511b81e05`
41. `a9de94c0-954b-452d-95b0-6a8b7d1a5a9e`
42. `a9e861d3-6bd6-4b76-ba78-4cc1f3265b43`
43. `aea933f5-5e3b-4476-b1f0-d781d41312a3`
44. `b33f023c-4b0c-495e-8f0b-934ead526421`
45. `bc718d5f-dc21-4e7d-914a-dd3a6debaeb6`
46. `bf38024e-2a5f-422c-ad41-01ec9922e701`
47. `c1f5c7e9-70e4-4c2d-99c8-aadd986cda15`
48. `c48478ef-8b3d-4c7f-bd48-cc99659e99f7`
49. `c79e2ade-4026-4ab3-a316-ba26354abfe2`
50. `cfb5e237-51a3-48b2-a12e-e8f0628e2c51`
51. `d1961919-8c05-42e8-8a06-4ed1fabb13c0`
52. `d2307a35-1f41-4402-ab4d-c03ed4305f50`
53. `d8ed3671-6865-42b6-a4a2-06b31c9051e6`
54. `d9d11e4b-a01c-4535-93cf-bc51cf08b900`
55. `dadcf864-5343-403d-a111-e68b8617f413`
56. `dbd6f35a-b0ee-4af8-bcda-e065330f0413`
57. `def65ad3-6f87-4889-802f-202550a9af49`
58. `eec50614-788d-429b-99a4-fc8938a86dda`
59. `f1a321d8-5528-4afe-8fb7-79204f49f3dc`
60. `f693a3d9-fada-48f2-8203-bc33d46ee4dd`
61. `f91ecdd8-7442-4879-97b6-67ad8ea99f23`
62. `fb066255-82b5-4eb1-9f76-a776c04becc2`
63. `fc138193-f76a-476c-a394-b49d2e68dde2`
64. `fd34b0d7-86c2-4d0e-a519-de2317e0ab26`
65. `fd803263-07b6-4b1f-b668-43a482f21c89`
66. `ff368fb5-94a8-4ea4-b3fc-d62ce499732b`

66条old31聚合hash：`6d6e0a39969343b18dbfbae5be41ceb4`；执行前后不变。分月old31 hash：

- 2026-09：`308c3cae122554bd10ae3dd308d438a8`
- 2026-10：`c32f0f89f0e536706dbfa3e7f0f88be5`
- 2026-11：`6cd9689a76f8380c109c731a24760a0b`

整表626条old31 hash继续为`4fb1901c888d56cb29c05e387490ca75`。

## 3. updated_at trigger与DDL/DML分类

A2 prompt明确授权复用A1方案。执行过程：

1. 单一事务内取得`school_lesson_records ACCESS EXCLUSIVE`锁；
2. 确认`trg_school_lesson_records_updated_at`初始enabled；
3. 仅固定66行UPDATE期间执行`ALTER TABLE ... DISABLE TRIGGER trg_school_lesson_records_updated_at`；
4. 异常和成功路径均执行`ALTER TABLE ... ENABLE TRIGGER trg_school_lesson_records_updated_at`；
5. commit前确认trigger恢复enabled；
6. postdeploy再次确认全部三条lesson trigger为`O`。

66/66原`updated_at`不变，old31不变。其他560条lesson在事务前保存完整JSON并在UPDATE后逐行比对，其中A1 52条与其余508条均无变化。

准确分类：

- School永久/净DDL变化：0；
- School事务内临时表DDL：创建ON COMMIT DROP的静态manifest、560条非目标before snapshot、业务基线、执行上下文和updated ID临时表；
- School现有trigger事务性DDL：一次`DISABLE TRIGGER`和一次`ENABLE TRIGGER`；
- School正式业务DML：66条lesson的5字段UPDATE；
- School测试持久写入：0；
- Cash DDL/DML：0。

## 4. ROLLBACK演练与负向测试

正式执行前使用完全相同的backfill SQL，以`r1d_c_b_a2_commit=0`演练：

- 静态manifest 66；
- before fingerprint 66/66；
- 模拟UPDATE 66；
- 5个授权字段66/66正确；
- A2测试decided_at统一且不同于A1；
- scheduled 66/66 NULL；
- 月份、小时、金额及7个check全部正确；
- A1 52条完整JSON不变；
- 其他508条完整JSON不变；
- actual 229条及School业务链不变；
- trigger恢复enabled；
- 最终ROLLBACK。

五项负向测试全部拒绝：

| 测试 | 结果 |
|---|---|
| manifest缺少一个UUID | rejected |
| before old31 hash不匹配 | rejected |
| source存在但decided_at为NULL | check constraint rejected |
| `2026-10 + 2026-09-28`非法month/week | check constraint rejected |
| 纳入第67个A1非目标UUID | rejected |

约束测试固定目标为`0386bf22-8619-41f2-be6c-5106b8c17cd0`；第67个临时manifest UUID为A1目标`01490eb7-1bd7-430a-ba26-3ccc81d45796`，只写事务内临时表，没有修改其业务行。ROLLBACK后A2字段残留0、override audit 0、测试记录0、trigger enabled；A1 52条继续保持正式值。

## 5. 正式执行与保护范围

正式模式`r1d_c_b_a2_commit=1`只执行一次，UPDATE返回66并commit。决定/执行时间为`2026-07-28 04:33:07.050555+00`。

事务内before/after保护证明：

- A2目标：66/66仅5字段变化；
- A1目标：52/52完整JSON不变，source仍`approved_r1c_a_manifest`，decided_at仍`2026-07-28 00:27:52.779654+00`；
- 其他lesson：508/508完整JSON不变；
- actual：229/229六字段仍全NULL；
- scheduled：全库非NULL仍为0；
- target和整表old31不变；
- updated_at trigger恢复enabled。

## 6. Postdeploy只读验收

最终结果：

- A2 manifest/matched/student/generation/`updated_at`/old31/授权值均66/66；
- A2 decided_at distinct = 1；
- A1 batch 52/52保持原source、原decided_at、原old31和原updated_at；
- lesson仍626 = 397 planned + 229 actual；
- billing month/week/student settlement/source/decided非NULL均为118；
- scheduled非NULL为0；
- 118条中decided_at精确为2个：A1时间与A2时间；
- 229/229 actual六字段NULL；
- 历史85 canonical / 24 incident / 12 legacy保持六字段NULL且candidate 0；
- 121/121 normalized relation继续匹配bill JSON，121/121历史scheduled/week snapshot仍NULL；
- candidate仍为160 / proposed 118 / current-only 42 / proposed-only 0；
- override audit仍0；
- lesson raw37 hash按授权字段变化为`c4f892d857fe674e4060f80d6af56b42`，old31保持`4fb1901c888d56cb29c05e387490ca75`；
- postdeploy SQL首次即成功，没有重跑正式迁移。

## 7. School/Cash前后基线

School：

| 对象 | 行数 | 前后hash |
|---|---:|---|
| tuition bill | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| billing identity | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| bill lesson relation | 121 | `09dfee7d8833e09384fb41a84f2959e0` |
| migration batch | 2 | `18e74c21ebf95fdf80bed6767a4e28be` |
| migration item | 118 | `23a2f93d0db01d84ba6195573ec58790` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| account transaction | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| student settlement | 15 | `7925cf3018bd0e669cd29710f6593238` |
| teacher wage lock | 95 | `7bbe108d3ac73d4f21530793bf141bc6` |
| teacher wage detail | 556 | `6204dc666b3b8e0f64fac901ecf0686a` |
| feature gate | 3 | `da00c76d8f8c72dd2decdac8ab6125b8` |

9张bill与9条tuition income继续9/9精确互指。

Cash前后分别读取，不宣称跨库原子快照：

| 对象 | 行数 | 前后hash |
|---|---:|---|
| external request | 34 | `ba0571247a869843c3ddda9075ea78dd` |
| CNY transaction | 59 | `27dfd0cb3bf85c5cc34677372b29502a` |
| JPY transaction | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

Cash数据库零写入。

## 8. R0入口

feature gate保持：

- `student_tuition_preview = validation_preview_only`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

在显式ROLLBACK事务内执行R1B入口探针：四个生成入口均返回`TUITION_GENERATION_BLOCKED`；Cash gate返回`TUITION_CASH_SUBMISSION_BLOCKED`；事故Cash入口继续因非pending income拒绝。成功写入0。

## 9. 执行清单与异常披露

执行的仓库SQL：

1. `sql/current/school_tuition_r1d_c_b_a1_r1c_a_52_postdeploy.sql`：School前基线，只读；
2. `sql/current/cash_tuition_r1a_business_baseline_readonly.sql`：Cash前后基线，各一次；
3. `sql/current/school_tuition_r1d_c_b_a2_r1c_c_b_66_rollback_tests.sql`：同一正式SQL commit=0演练及五项负向测试，全部ROLLBACK；
4. `sql/current/school_tuition_r1d_c_b_a2_r1c_c_b_66_backfill.sql`：commit=1正式执行一次；
5. `sql/current/school_tuition_r1d_c_b_a2_r1c_c_b_66_postdeploy.sql`：正式后只读验收；
6. `sql/current/school_tuition_r1b_r0_entry_probes.sql`：显式ROLLBACK事务内执行。

另执行`/private/tmp/r1d-c-b-a2-summary-readonly.sql`作为A2补充只读前基线。此前一次内联`psql -c`只读汇总因shell引号丢失而在SQL解析阶段报错，未进入事务、未写数据库；改用临时SELECT-only文件后成功。正式postdeploy没有错误。

R0探针调用：`school_generate_student_tuition_bill`两个签名、`school_create_student_tuition_bill_income_record`、`school_create_personal_cash_tuition_income_record`、`school_require_feature_gate_state`、`school_request_cash_income_confirmation_for_record`。全部走预期拒绝路径并由外层ROLLBACK保护。

测试没有创建白名单业务记录；事务内约束测试使用前述固定UUID，持久残留0。

## 10. 未处理范围与Git停止点

未处理A1 52、scheduled date、actual继承、历史85、named import 113、candidate差异42、李天伦异常、writer/reader/RPC/API/page、relation snapshot、override、账单/income/月结/工资/Cash或R0 gate。未启动任何后续阶段。

本阶段新增3个A2 SQL、1份实施报告并更新`docs/current-status.md`。未执行`git add`、commit或push，等待ChatGPT与业务负责人审查。
