# School V2 R2-F-D Atomic Tuition Generate UI Report

Date: 2026-08-01

## Outcome

R2-F-D前端/API接入完成最终验收。收入页只读取数据库权威validation preview，并为未来开放的正式生成入口保留单一atomic API调用；当前R0下正式按钮持续禁用。本轮没有调用generate、没有创建bill/income、没有连接Cash，也没有改变任何gate。

## July settlement read-only verification

全部查询在School DB的`READ ONLY`事务中执行并显式`ROLLBACK`。

- 孙陈锋（`b17abc58-2f64-4bad-bf20-c9643ead60bc`）2026-07 settlement `5e0a23ff-0e1e-48c6-9866-5fc335b3e42d`：`locked`，汇率`0.042`，planned `36h / JPY306,000 / CNY12,852`，actual `25h / JPY212,500 / CNY8,925`，overage与adjustment均为0，carryover `CNY0`。
- 孙陈锋两条跨月收费事实仍归属学生结算月2026-07：planned `685ad45e-b5da-42ca-8f43-7732e8d6e40d`对应actual `8235d498-d621-4fab-8898-e856378b0a71`，planned `8b737b58-cd14-42c5-afd2-34730dcef963`对应actual `c8e6cf21-850c-4700-af9e-7ebf3c2a577d`；两条actual当前日期均为2026-08-01、各`2h / JPY17,000`，权威`student_settlement_month`及resolver结果均为2026-07。
- 张倬闻（`7aef8061-7037-4881-a847-a2cdb031c0f4`）2026-07 settlement `b699209d-2f61-4cfa-959b-45686e2fe19b`：继续为`locked`，汇率`0.043`，overage `15min / JPY2,500 / CNY107.50`，carryover `CNY107.50`。
- 两张月结各自锁定时点后，目标学生的bill、income新增或更新为0；与settlement关联的School账户流水、Cash income/payment linkage及目标学生工资锁定明细新增均为0。

历史资金指纹在最终只读快照中为：9 bill `0f0323b79e7ff1c47ff6b90c75477a2d`、42 income `2a4897b752f272b1f192045418b4940c`、121 relation `285172fedeb923c67ea9a179480d8692`、7 identity `4d91a5a1074f90389822fc367a7e5467`、17 settlement `7f78087e7b648992b95d66327a6a0a73`。

## August validation preview

只读调用`school_get_student_tuition_validation_preview_details(student_id, '2026-08', exchange_rate)`：

- 孙陈锋，显式汇率`0.042`：22 candidates、24课次、44小时、基础费JPY374,000、空调费JPY0、previous carryover CNY0、最终通知金额CNY15,708。上述两条2026-07跨月planned在2026-08 candidate命中数均为0。
- 张倬闻，显式汇率`0.043`：30 candidates、35课次、65小时、基础费JPY650,000、空调费JPY0、previous carryover CNY107.50、最终通知金额CNY28,057.50。
- 两次调用均返回`validation_preview_only`，均未出现`R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH`或`R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED`。

R0实查仍为：`student_tuition_preview = validation_preview_only`、`student_tuition_generate = blocked`、`student_tuition_cash_submit = blocked`；writer context残留为0。

## Frontend and API contract

- 页面通过`fetchStudentTuitionValidationPreviewDetails(...)`读取金额、candidate、carryover及generation manifest，不计算任何将被保存的业务金额。
- 正式生成载荷仅含`studentId`、`billingMonth`、用户显式输入的`billingExchangeRate`、数据库返回的`expectedGenerationManifestSha256`及备注。
- 页面模块没有直接`.rpc()`或表写；唯一正式入口由`js/api/income-api.js`包装公开RPC `school_generate_student_tuition_bill_atomic(...)`。
- 旧`school_generate_student_tuition_bill(...)`加独立`school_create_student_tuition_bill_income_record(...)`两步链已从收入页/API删除；页面不引用owner-only core。
- student、month或rate变化会清除旧preview；note变化不改变manifest；确认、并发点击、幂等成功、stale/source-busy失败及当前R0禁用均有fixture覆盖。
- 当前preview响应不提供`generate_feature_state = enabled`，所以正式按钮保持“生成应收（维护中）”且不可调用atomic writer。

## Verification

- `node --check`：`js/api/income-api.js`、`js/income-app.js`、`js/pages/income-page.js`、`js/utils/tuition-validation-preview.js`及两份UI test全部通过。
- `node scripts/tuition-validation-preview-ui-test.mjs`：PASS。
- `node scripts/tuition-atomic-generate-ui-test.mjs`：14/14 PASS。
- 页面/API边界扫描：page direct RPC/table write为0；owner-only core及旧两步generate调用为0；公开atomic RPC只出现在API wrapper。
- `git diff --check`：PASS。

## Deferred issues

以下问题只登记，不属于R2-F-D实现范围：

1. 已收费planned从`planned`改为`pending_makeup`时被`R2_E_LEGACY_PLANNED_CHARGE_FACT_IMMUTABLE`错误阻断，需独立调查。
2. 数据库尚无“未来actual日期不得提前标记`completed`/`makeup_completed`”guard，需独立设计和验收。

## Stop point

R2-F-D仅准备好atomic tuition generation UI并保持R0 fail-closed。不得真实生成2026-08账单，不得提交Cash，不得开始解除gate。
