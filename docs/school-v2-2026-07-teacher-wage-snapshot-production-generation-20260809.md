# School V2 2026-07 老师工资快照生产生成报告

日期：2026-08-09（Asia/Tokyo）

范围：仅生成青空进学塾2026-07老师工资快照及工资明细；不生成工资支付请求、支出、账户流水或Cash请求，不修改工资规则、学生月结、历史完成证据、课时、待补余额、账单、收入、Storage或Gate。

## 1. 结论

1. 8位老师工资快照全部通过正式受控writer一次原子生成成功，状态均为`locked`；创建时间、锁定时间和更新时间均为`2026-08-09 09:17:25.033463+00`。
2. 最终为8条active工资快照、56条active工资明细、6660实际分钟、90.5计薪小时、JPY 410,750；遗漏actual、重复actual、额外actual均为0。
3. 11条/1230分钟`no_wage`均保留工资明细和actual minutes，`pay_hours=0`、`lesson_wage_jpy=0`、`total_jpy=0`，没有重新触发工资writer的学生月结阻断。
4. 正式writer调用1次：`school_generate_teacher_monthly_wage('2026-07',NULL,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466')`。没有直接表级DML，没有网络结果不明确或重试。
5. 工资支付请求、School支出、School账户流水、Cash request、Cash transaction均未生成；8条详情页全部显示“尚未生成支出记录”。
6. 数据库已具备另行授权生成工资支付请求的前提；吴峰快照总额JPY 0，页面正确显示“无需支付”，不会生成支付请求。其他7条正金额快照仍需业务负责人下一轮明确授权。
7. Chrome快照列表、8个详情、56条明细、金额及Console 0通过；但候选课时区仍按物理settlement读取，错误显示“学生结算完成/未完成 0/56”和行内“未生成”。该只读展示与正式preflight/resolver的blocker 0不一致，不影响已生成快照，但“页面不再显示月结未完成信号”这一验收项没有完全通过。本轮未擅自扩展为前端修复。

## 2. 实时基线与最终preflight

| 项目 | 生成前 |
|---|---|
| 分支 | `main` |
| HEAD / origin/main | `cb57fa6018fc3086b4c5e7156aaac6bee9ea6f2a` / 同值 |
| ahead/behind | `0/0` |
| 页面版本 | `v10.5.27` |
| 最新成功Pages | run `31304605843`，commit `cb57fa6` |
| Gate | `student_tuition_cash_submit=enabled`、`student_tuition_generate=blocked`、`student_tuition_preview=enabled` |
| 目标scope active工资锁/明细 | `0/0` |

正式authenticated active-admin只读preflight：candidate actual 56、老师8、总分钟6660、missing rule 0、duplicate rule 0、incomplete lesson 0、student settlement blocker/group 0/0、active lock 0、existing detail 0、no_wage 11条/1230分钟、条件计薪90.5小时、JPY 410,750。

兼容事实：

- 陈红卓、陈加恩、李天伦、袁振轩4条证据均解析为`historical_zero_carry_complete`，carry CNY 0。
- 张倬闻解析为`historically_consumed_immutable`，source settlement `b699209d-2f61-4cfa-959b-45686e2fe19b`，冻结carry CNY 107.50。
- 彭宇晗课时`145a8219-0fcf-4e0b-8230-c6a092668836`仍为`no_wage_not_required`，30分钟、pay hours 0、工资JPY 0。

## 3. 正式writer结果

| 老师 | teacher UUID | wage snapshot UUID | 课时/分钟 | 计薪小时 | JPY | 明细 |
|---|---|---|---:|---:|---:|---:|
| 丛琪润 | `ba4210e8-95ef-4f8c-9974-8825923912b7` | `8852b5c7-fbc7-4760-b09f-fccf4b2926ac` | 3 / 360 | 6 | 30,000 | 3 |
| 吴峰 | `bbc3d827-ba8b-4ded-a5ac-cafca88f26bd` | `7f586edc-ba41-4252-b93c-51785ae2c474` | 14 / 1590 | 6 | 0 | 14 |
| 李雯coco | `1ed3ef4e-4168-425d-a264-0fa3747e7448` | `08de9aed-361f-4e27-80f7-10433f27116d` | 3 / 420 | 7 | 38,500 | 3 |
| 王亚楠 | `f3b8735b-1966-4dae-ac4e-846cbedc54e6` | `1f6b8ce0-f021-417c-9fb0-e8c1f0635af9` | 7 / 840 | 14 | 77,000 | 7 |
| 王黎曦 | `c92ffb8f-c2af-48cd-99b1-2a2a75d70384` | `0bf085d6-8192-498d-856e-e1130d763e84` | 4 / 480 | 8 | 32,000 | 4 |
| 田宇辰 | `edaf30da-1315-4455-99d1-ead1b7147662` | `4964456c-bc8a-475a-ba6d-e34d8bed0f40` | 5 / 600 | 10 | 40,000 | 5 |
| 赵天歌 | `ea58874b-3656-4b14-8977-dc8bf9423997` | `41bd92b8-54c2-409b-8aca-c4082836474d` | 12 / 1410 | 23.5 | 129,250 | 12 |
| 高若天 | `78119d7d-624b-45ec-9f22-d24eef22553f` | `1b7b0881-14e3-4f45-83ac-97ed485293f5` | 8 / 960 | 16 | 64,000 | 8 |
| 合计 | 8名 | 8条 | 56 / 6660 | 90.5 | 410,750 | 56 |

现有工资表没有generation manifest或idempotency identity列。正式writer以active lock存在检查阻断重复生成；本次8条lock UUID是权威快照identity。只读诊断指纹：目标locks `18d7eb7a8b906a48d0d31bad23f9b18c`，目标details `021e3381a946630825c570f17833e0eb`。

## 4. 工资明细UUID

- 丛琪润 / `8852b5c7-fbc7-4760-b09f-fccf4b2926ac`：
  `4b38bc34-3eab-4de6-9032-9d2a25e342c6`, `968ddd24-fa2b-475f-bf86-1715fcf51f8a`, `26f64665-9ff7-4a7e-8360-18b3731111ac`
- 吴峰 / `7f586edc-ba41-4252-b93c-51785ae2c474`：
  `a7cecb76-cb9c-4030-86f7-75d88c29bc55`, `dc8eea70-f318-41a8-a009-12a823ff3546`, `2efab30e-439e-45e0-8f70-ba598a767d0d`, `20de25de-98a0-484b-85c9-d70e6df09e64`, `93e12cbf-53dd-417b-8de2-6d50aca67601`, `1485e319-69ca-416a-a9b9-dbf7d8d6f153`, `6758e7de-f0ca-45a3-b995-ff25e3f76603`, `9d65b2c9-8465-4531-8e64-d6ad7f281142`, `51aeefb2-11e4-42a8-aa7c-b4b574c4caea`, `b566b7fc-ee19-4993-96ad-6670811a593b`, `c37e28bb-fdce-4505-bf8d-7732327cc85f`, `d32ae5d7-b89e-4a86-a965-d41239a431bc`, `8b2e4673-2009-4b8b-a17d-ce245ff4c69c`, `77583ac4-8313-4710-b2e7-fe51025559b0`
- 李雯coco / `08de9aed-361f-4e27-80f7-10433f27116d`：
  `781c28b1-561a-4cf0-8898-4e0461822ca8`, `4a1b5f09-bc82-449a-b801-5d3ff9ab02dc`, `e560cb99-f204-4186-991e-2b1c157660df`
- 王亚楠 / `1f6b8ce0-f021-417c-9fb0-e8c1f0635af9`：
  `bb40a50f-6a1b-48b1-836a-67fedf10d256`, `8978ee2f-e89d-4fe9-92d9-2447a3216cb2`, `31b5b1c2-055a-4f41-92d4-4712c195110f`, `a751bbf8-8537-4338-b904-7874be280e23`, `8a621f04-1acb-4833-b72c-1c1b0f59b411`, `784d6bc5-efc2-45fb-8902-382db5a2fb07`, `79c5e009-ab64-47ff-939b-43485b15ee40`
- 王黎曦 / `0bf085d6-8192-498d-856e-e1130d763e84`：
  `eca9128e-a5a8-41c8-95d0-047a700bd625`, `df9257bb-e12c-405e-9cf9-fb7cb6a0bc39`, `2b0f0e59-0fe7-4bf8-807b-722cf061c9fe`, `d1769163-f82b-4e74-9d2e-d7880fc8d6c1`
- 田宇辰 / `4964456c-bc8a-475a-ba6d-e34d8bed0f40`：
  `7239e84c-0c0b-4710-943b-ef15f3926099`, `22733d92-5eff-4e86-ad45-af0ddb0f678f`, `7d105661-27e7-4c8c-88ef-c7c08bc1bf99`, `00c24fd1-7b18-4c6d-b333-6057343ba262`, `14a98b96-7101-4c74-a6e1-132ba0e34296`
- 赵天歌 / `41bd92b8-54c2-409b-8aca-c4082836474d`：
  `ac4c62a3-7293-469c-9031-7af15ffc0fcf`, `1d0af6ea-ff68-479d-b5f5-e5d18c74bd89`, `89063b1f-01f1-4fa1-8ea3-8f16d222cba6`, `ce03405b-d1b8-41db-8825-b7c953ab94a4`, `e98f3638-e5bd-4ae1-a855-bf10c03de2da`, `7960fe2e-4db2-4aa5-a19f-cd1cc62783f9`, `26924db1-5298-4979-879c-f4c00edc0742`, `fd895204-fcdf-4b57-abef-55ce38ea4c49`, `83e5687e-88f0-4f86-9474-5fb64c792175`, `e6c1cab9-bcf4-40bd-a9ed-43614857d674`, `31091b8f-d7c2-40a1-9bb4-01807d39cc83`, `0c712b59-d6ef-4807-afba-32662c96e5e4`
- 高若天 / `1b7b0881-14e3-4f45-83ac-97ed485293f5`：
  `0c24228b-b349-439c-b24e-fdc07b27ae2c`, `b907e60e-7853-49b4-8958-bee1611d0754`, `741672eb-2231-48ec-b5a3-42e20b622d53`, `e4b5a49b-d0c8-4c1b-b4e4-bc54b961a30e`, `b17a5d4d-9cbb-4034-9751-8a40fc80f233`, `6357cf66-322d-44af-a034-878d7dd3bfa4`, `e2920f85-99fb-48f9-b6a7-ac83b1fd8903`, `f5a03b8b-87fe-4365-a1ec-b57112976f4a`

## 5. 生成后闭包与无副作用证明

| 对象 | 生成前 count/hash | 生成后 count/hash | 结果 |
|---|---|---|---|
| wage locks | `95 / 7bbe108d3ac73d4f21530793bf141bc6` | `103 / ea395407134045e7623e171b02d3d910` | 仅新增8条目标快照 |
| wage details | `556 / 6204dc666b3b8e0f64fac901ecf0686a` | `612 / 1d45d0ce37696051c233465efaf3de5e` | 仅新增56条目标明细 |
| lessons | `744 / 02b9109c53d1a3d320d4c9f8899fdb40` | 同值 | 不变 |
| ordinary settlements | `18 / 481ffa7ed5173da852f0f28ce66c2e9b` | 同值 | 不变 |
| historical evidence | `4 / 9cb22ef4ddd83f7a77c8fcd2e3ab3966` | 同值 | 不变 |
| bills / revisions / income | `22 / e50673ac…`; `20 / ffdc498a…`; `55 / c55f82c7…` | 同值 | 不变 |
| wage rules | `30 / 97a601d0ea3f8c610f4b50c8acb93b77` | 同值 | 不变 |
| expenses | `47 / 34a7a32319d8e538ef7997e1ba59c9d4` | 同值 | 不变 |
| payment requests | `51 / 6ce63e69edfa19a020013634b686f5ce` | 同值 | 不变 |
| account transactions | `187 / 00516a76f236d51406c82f37b0e468ee` | 同值 | 不变 |

新8个wage lock UUID在expense、payment request、account transaction中的引用均为0。

Cash全库及School子集前后完全一致：requests `43 / f4b1876e981ef75828600e0c7f0dc371`；CNY全库`74 / 070c262ec01008d404b424233d2a6e47`、School子集`37 / a9ac168e157a00789bd5bff1de469f50`；JPY全库`31 / 95ab7cf8a8d167e9b052d3fc6b64614b`、School子集`3 / 654485db35df0657c0bf7121d464baa3`。

Storage前后完全一致：buckets `1 / 9b1be72d5b5fb2ac22b7f7b49d9f8f90`；objects `57 / 62fac5521274c58c6f6982a0c690c134`。Gate仍为`enabled / blocked / enabled`，变化0。

## 6. Chrome只读验收

- 生产`v10.5.27`，2026-07筛选正确；快照列表8条、8个详情链接。
- 列表逐老师课时、分钟、计薪小时、金额全部正确；吴峰显示14条/1590分钟/6小时/JPY 0和“无需支付”。
- 逐一直接打开8个详情页，明细数为`3+8+3+5+4+7+14+12=56`；所有详情显示“尚未生成支出记录”。
- 两个Chrome页面会话的Console error/warning均为0；没有点击生成支付请求、生成支出、调整、撤销、作废或任何其他写入口。
- 展示异常：候选区显示“未生成/已生成 0/56”正确，但同时显示“学生结算完成/未完成 0/56”及行内物理settlement“未生成”。代码只读定位到`js/api/wage-api.js`仍按普通`school_student_monthly_settlements`物理状态补充候选，而正式生成使用新的工资preflight/effective resolver。该问题只影响展示，不改变DB权威工资结果；需要独立前端修复授权。

## 7. 文件、Git与现场保护

本轮生产DB写入仅为正式writer创建的8条工资快照和56条工资明细；正式写RPC调用1次。SQL文件执行0、DDL 0、直接DML 0、synthetic fixture 0。文件变更仅为本报告和`docs/current-status.md`。

六份既有受保护untracked文件保持原状、未暂存、未提交，SHA-256仍为：

- `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`
- `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`
- `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`
- `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`
- `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`
- `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`

## 8. 下一步边界

不得在本阶段继续生成工资支付请求、支出或Cash请求。下一步如获独立授权，可对7条正金额快照进入正式“生成工资支付请求/支出”流程；吴峰JPY 0无需支付。候选区effective settlement只读展示异常建议在支付运营前另行修复或由负责人明确接受，但不是工资快照或支付资格的DB blocker。
