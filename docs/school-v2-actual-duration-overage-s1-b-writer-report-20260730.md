# Aozora V2 actual duration overage S1-B writer实施与验收报告

日期：2026-07-30（Asia/Tokyo）
阶段：S1-B canonical ordinary actual overage writer
停止点：`S1-B_DATABASE_REVIEW_POINT`
最终状态（2026-07-31）：`ACTUAL_DURATION_OVERAGE_COMPLETE`

> 2026-07-31补充：本报告记录原S1-B canonical-only部署。后续`S1-B_LEGACY_SOURCE_COMPAT_DATABASE_REVIEW_POINT`兼容补丁已将overage source资格扩展为“完整canonical R1D bundle”或“全NULL bundle + 唯一R1D-E-B1 approved legacy evidence + E-B2 resolver权威月”；其他规则不变。详见本文第10节。

## 1. 结论

S1-B已完成School DB正式部署、只读postdeploy及整体ROLLBACK测试，正常页面→API→RPC链现已支持canonical青空进学塾ordinary actual的三分支：

- actual < planned：继续拒绝，必须使用partial入口；
- actual = planned：维持原生成行为，5个overage字段全部NULL；
- actual > planned：在同一actual INSERT内冻结完整S1-A overage事实。

本阶段只激活writer事实生成，不让settlement、candidate、bill或Cash消费overage；未进入S1-C，R0保持不变。

## 2. 实施对象

正式部署只替换两个既有函数：

| 对象 | before MD5 | after MD5 |
| --- | --- | --- |
| `school_create_actual_lesson_from_planned(...)` | `da156f6c951b233a2878ecb100b2748b` | `e3d9dd24f3fd7c533301bb5c1a27fa4f` |
| `school_update_lesson_record_guarded(...)` | `bf856292c268aefa7c1aa036da480ae7` | `ca52667c94a86608b4ab712f543b04b1` |

部署后actual writer八入口组合MD5为`e1b303843c3717edd264a78d0f185c5e`。

未新增或修改table、column、constraint、index、trigger、RLS或ACL。partial、makeup、planned→cancelled、venue wrapper、E-B2、F1、E-C、resolver、set helper、settlement、candidate、bill及Cash对象均未修改。

## 3. ordinary writer规则

ordinary RPC签名及页面/API调用方式保持不变。writer继续先对source planned执行`FOR UPDATE`并沿用既有重复actual检查。

actual > planned仅在以下条件成立时生成overage：

- planned五字段R1D归属bundle完整；
- 现有E-B2 resolver确认source planned权威学生月；
- planned业务归属ID等于数据库权威`school_primary_business_entity_id()`，即青空进学塾；
- planned可计费且source planned unit price为正数。

字段映射：

| S1-A字段 | DB权威来源 |
| --- | --- |
| `student_duration_overage_minutes` | `round((actual.duration_hours - planned.duration_hours) * 60)::integer` |
| `student_duration_overage_fee_jpy` | `round((actual.duration_hours - planned.duration_hours) * planned.unit_price)` |
| `student_duration_overage_policy_version` | `student_duration_overage_v1` |
| `student_duration_overage_source` | `ordinary_actual_rpc` |
| `student_duration_overage_decided_at` | 同一事务的`statement_timestamp()` |

actual的`student_settlement_month`继续由E-B2在同一INSERT中写成source planned权威月。S1-A没有独立target-month字段；未来consumer只能从source月确定性派生下一个自然月。本次测试证明source `2034-01`派生target `2034-02`，actual发生月`2034-03`不会改变该结果。

金额不读取planned/actual lesson_fee差、不读取actual传入unit price、不读取aircon、venue费率或其他附加费。测试特意传入actual unit price `9999`，overage仍按planned unit price `1100`计算0.5小时为JPY 550。

## 4. guarded编辑边界

现有E-B2及guarded RPC已经冻结或拒绝student settlement month、source planned、student、business entity及status变化，但原guarded core仍允许修改actual duration和unit price。

S1-B仅增加局部判断：当actual带有`student_duration_overage_v1 / ordinary_actual_rpc` bundle时，normal guarded RPC拒绝duration或unit price变化，错误为`S1_B_OVERAGE_CHARGE_FIELDS_IMMUTABLE`。日期、老师、备注、内容和venue等不影响overage收费事实的既有编辑逻辑未扩大；测试证明备注编辑成功且bundle保持不变。

## 5. cancelled、partial、makeup及历史边界

- 从planned直接生成的cancelled actual继续固定non-billable、fee 0、overage五字段NULL；
- partial actual继续走专用入口并留下pending_makeup credit，overage字段NULL；
- makeup actual继续non-billable且只消费remaining credit，overage字段NULL；
- completed actual不新增转cancelled流程，S1-A CHECK未修改；
- 固定历史19条不扫描、不回填、不收费，字段继续全部NULL，投影哈希仍为`352e72ac33d648a23be84bb27b3580d1`。

## 6. 验收与修正记录

writer部署SQL执行1次并成功COMMIT，没有重跑：

- `sql/current/school_actual_duration_overage_s1_b_writer.sql`

postdeploy共执行4次：

1. 首次在`S1_B_UNEXPECTED_TRIGGER_CHANGE`停止。根因是用`information_schema.triggers`按事件展开行数比较5个实际trigger对象；READ ONLY事务随连接退出回滚。
2. 改用`pg_trigger`后，逐项核对5个trigger名称、definition及函数MD5，全部通过并显式ROLLBACK。
3. rollback tests后最终复验再次全部通过并显式ROLLBACK。
4. 文档复核时补齐11个S1-A字段及2个partial index的显式目录断言，增强版最终复验全部通过并显式ROLLBACK。

修正只涉及postdeploy目录查询，不修改writer或数据库对象。

rollback tests执行1次即9/9通过并显式ROLLBACK：

- equal branch全NULL；
- canonical青空overage成功；
- source/target/actual日期月份分离；
- actual < planned拒绝；
- legacy与非青空overage拒绝；
- partial/makeup/cancelled不生成overage；
- duplicate ordinary拒绝；
- planned完整行不被反写；
- guarded safe edit与收费字段拒绝；
- aircon、历史19条、禁止对象MD5及R0不变。

事务内actual测试ID：

- `4eb771b4-3c50-4ade-a018-e816fc86c580`
- `bfe21b07-9fa0-4ec4-a568-4cc7ccb2a94c`
- `3b0e7222-2e35-41e8-a2fd-5f06d6665a52`
- `ae484336-2d40-42b5-bb1d-465c142f96a0`
- `c9acf2b3-a315-4b3b-86b2-3383125a38b4`

全部回滚；新连接验证测试marker及固定测试ID残留0。

最终SQL SHA-256：

- writer：`4f9609d8807f77eda30b8567a4bb8ee64243b045212716a843cb14179a33f69e`；
- postdeploy：`6b6b692cc2f6c780d744734ab7cdf7e578cc570d426468157699a7545e8e6ebe`；
- rollback tests：`d548877654d46300710fa38d20a2c00d91b3bebbf16728cca97151a8c292b91e`。

## 7. 最终数据库边界

- lesson：649（planned 414 / actual 235）；正式overage bundle非NULL 0；
- settlement：15；overage aggregate仍全部NULL；
- bill / income / bill-lessons：9 / 42 / 121；
- lesson稳定投影哈希：`fd8b5570f42d618f136b2f6408704ae8`；
- settlement稳定投影哈希：`7925cf3018bd0e669cd29710f6593238`；
- 6个S1-A CHECK定义及MD5不变；2个S1-A index不变；
- E-B2 trigger：`4a163f6691c779531a65a10be0f4422e`；
- F1 trigger：`08f3c60890d4afab8d9c730eec286c8d`；
- E-C reader组：`b3818fc1119b5b2c1069d78164760e95`；
- resolver：`8de65e9787d8d66f2cd7b65eb2479a8c`；
- set helper：`155e831118acbeadfd04b6640324c7cd`；
- planned duration helper：`4f5b754585c9e3752639e6b0f2fa7a34`；
- planned fee component helper：`2dfabf4a920f7138043079855347207b`；
- R0：`validation_preview_only / blocked / blocked`。

数据库正式写入仅为两个函数定义/comment的系统目录变化；lesson、settlement、bill、income、Cash及其他业务数据DML为0。Cash DB未连接。

## 8. 已知安全债务与未完成范围

`school_lesson_records`当前仍向anon/authenticated授予直接写权限，RLS为`public ALL true`。本阶段按业务决定只保证正常页面→API→RPC链，不新增通用trigger、不修改ACL/RLS，也不测试直接表攻击；该历史权限问题须独立整改。

S1-C前仍未完成：

- 来源月份月结确认和aggregate snapshot；
- target下一周期candidate；
- 补充收费身份、bill、API和UI；
- completed overage撤销/冲销事实。

S1-C未来必须直接读取已冻结的`student_duration_overage_fee_jpy`，不得根据`actual.unit_price`、`actual.lesson_fee`、actual发生月、legacy `year_month`、aircon或其他附加费重新计算超额差额。

当前严格停止在`S1-B_DATABASE_REVIEW_POINT`，不得进入S1-C或解除R0。

## 9. Git状态

截至数据库验收停止点，本阶段文件保持未暂存，尚未执行Git add、commit或push；受保护未跟踪文件未读取、修改、移动或暂存。Git交付由后续独立授权完成。

## 10. 2026-07-31 approved legacy source兼容补丁

页面真实验证使用planned `20533154-0de9-49b7-bbbd-907aa2a254ee`时，原S1-B canonical-only gate返回`S1_B_OVERAGE_CANONICAL_SOURCE_REQUIRED`。只读确认该planned的R1D五字段全NULL，但存在唯一且identity匹配的R1D-E-B1 approved legacy evidence，E-B2 resolver权威返回`2026-07`；它同时满足青空进学塾、billable、2小时、JPY10,000、无关联actual、来源月未锁定。

兼容补丁只再次替换ordinary writer：MD5从`e3d9dd24f3fd7c533301bb5c1a27fa4f`变为`149634304f5407de81f23717b913be7e`。完整canonical branch保持；全NULL branch必须唯一命中`r1d_e_b1_fixed_legacy_279 / legacy_settlement_evidence_v1`并通过现有E-B2 resolver；1–4字段、无证据、resolver不一致、非青空、non-billable、duplicate、voided/cancelled及locked source month继续拒绝。补丁不UPDATE planned、不回填R1D字段、不修改guarded updater、E-B2/F1、S1-C、candidate、bill、income、Cash或R0。

Rollback测试使用全事务`codex-test`合成legacy evidence夹具证明2h→2.25h生成15分钟/JPY2,500并继承resolver月份，全部测试行与临时trigger状态变更均ROLLBACK；补丁部署验收停止时真实planned仍无actual，之后已由页面完成真实生成并通过第11节最终只读验收。

## 11. 最终真实业务验收与完成状态

业务负责人确认页面已从planned `20533154-0de9-49b7-bbbd-907aa2a254ee`生成actual `4a1b74c6-65f0-4513-9c1e-4a094b7bb393`。最终School DB `REPEATABLE READ READ ONLY`验收并明确`ROLLBACK`，确认：关联actual精确1条；actual为`completed / 2.25h / 135分钟 / JPY10,000 / JPY22,500 / 2026-07 / 青空进学塾`；冻结overage为`15分钟 / JPY2,500 / student_duration_overage_v1 / ordinary_actual_rpc`且decided_at非NULL。planned仍为`2h / JPY10,000 / JPY20,000`，canonical_charge仍1条，pending_makeup为0。

S1-C live aggregate为`15分钟 / JPY2,500 / CNY107.50 / 1条`；preview保持planned base `JPY520,000 / CNY22,360.00`，无overage final due为0，DB final due为`CNY107.50`。真实2026-07月结没有snapshot，未执行lock/relock；未来按正常月结锁定后，该正向余额才会通过既有carryover进入下一自然月。原canonical bill、income及School侧Cash关联均未因actual新增或修改；candidate、bill、income和Cash不直接扫描overage。历史旧actual继续不回填、不追收。

`actual < planned`仍必须走partial；canonical planned与唯一approved E-B1 legacy planned均可为新生成overage actual提供权威来源月。V2无登录且`school_lesson_records`宽松ACL/RLS是业务已接受的内部系统技术债务，本次未整改；V3已有正式安全登录。R0保持`validation_preview_only / blocked / blocked`。最终结论：`ACTUAL_DURATION_OVERAGE_COMPLETE`。
