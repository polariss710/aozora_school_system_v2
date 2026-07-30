# Aozora V2 actual duration overage S1-B approved legacy source兼容补丁报告

日期：2026-07-31（Asia/Tokyo）
Git基线：`fdc4a43808399994b659cdf7ceae1e3e76c85c99`
停止点：`S1-B_LEGACY_SOURCE_COMPAT_DATABASE_REVIEW_POINT`
最终状态：`ACTUAL_DURATION_OVERAGE_COMPLETE`

## 1. 最终结论

兼容补丁已完成School DB一次正式部署、只读postdeploy及整体ROLLBACK测试。ordinary actual writer现在接受两类overage source：

1. R1D五字段完整且通过E-B2 resolver的canonical planned；
2. R1D五字段全NULL、唯一命中R1D-E-B1 approved legacy evidence且通过E-B2 resolver的legacy planned。

部分填写、无approved evidence、resolver失败/不一致、非青空、non-billable、duplicate、voided/cancelled及来源月locked继续fail closed。没有UPDATE或回填planned，没有扫描历史actual，没有修改S1-C、guarded updater、trigger、resolver、candidate、bill、income、Cash、页面/API或R0。

## 2. 真实planned定向只读确认

目标planned：`20533154-0de9-49b7-bbbd-907aa2a254ee`。

| 项目 | 只读结果 |
| --- | --- |
| 关联actual / overage actual | `0 / 0` |
| lesson type / status / billable / voided | `planned / planned / true / NULL` |
| 业务归属 | `aosora / 青空进学塾`，ID `2cf7b72f-6e3c-4d09-80f7-7c58593cd466` |
| duration / unit price | `2 / JPY 10,000` |
| legacy year_month | `2026-07` |
| R1D五字段 | 全NULL，`num_nonnulls = 0` |
| E-B1 evidence | 唯一，approved=true，`r1d_e_b1_fixed_legacy_279 / legacy_settlement_evidence_v1` |
| evidence identity | frozen/current均为`641030239cdd6dfed9f07e4b670416f4`，匹配 |
| E-B2 resolver | 唯一标量结果`2026-07` |
| canonical_charge关系 | 1条，bill `fdf3cdfe-f715-4814-b500-9ff2bfe77a63` |
| 学生2026-07月结 | 无snapshot，因此locked=0 |
| 页面失败残留 | actual=0，overage actual=0 |

第一次只读目录输出使用`LEFT JOIN count(*)`将“无月结行”显示为1；修正为`count(s.id)`后确认真实settlement count为0。其余重复只读运行用于筛选安全测试夹具与核对trigger目录，不产生写入。

## 3. 根因与修复

原S1-B writer在`actual > planned`时强制R1D bundle的`num_nonnulls = 5`，因此在调用已经支持approved legacy evidence的E-B2 resolver之前，就对合法全NULL legacy source抛出`S1_B_OVERAGE_CANONICAL_SOURCE_REQUIRED`。

补丁只替换ordinary writer中的资格分支和overage来源月lock条件：

- bundle=5：继续由resolver验证canonical attribution，结果必须等于planned的`student_settlement_month`；
- bundle=0：必须唯一命中approved E-B1 evidence，再由resolver复核identity、student/entity、legacy month和证据版本；
- bundle=1–4：`S1_B_OVERAGE_PARTIAL_SOURCE_ATTRIBUTION_REJECTED`；
- overage来源月lock检查使用resolver结果；非overage ordinary行为继续沿用既有月份检查。

overage计算没有变化：

```text
minutes = round((actual duration - planned duration) × 60)
JPY = round((actual duration - planned duration) × planned unit price)
```

actual日期、actual传入unit price、lesson fee、legacy月份fallback、aircon及附加费都不参与overage事实计算。

## 4. 正式部署

执行一次且仅一次：

- `sql/current/school_actual_duration_overage_s1_b_legacy_source_compat.sql`

执行结果：COMMIT成功。

最终SQL SHA-256：

- deployment：`db3a03eb90eed1dafb26df628d27c0719ee4c4f69caf51f9cd64176f4bd3b286`
- postdeploy：`ef422fc5e9e5ca8981136310a626beaf5d399da04759fef2a3f7e9218d9d82fa`
- rollback tests：`bffc6f5ae79547ea4e94700de799934f8bc47d233e33e608124e3b1275b27001`

| 对象 | before MD5 | after MD5 |
| --- | --- | --- |
| ordinary writer | `e3d9dd24f3fd7c533301bb5c1a27fa4f` | `149634304f5407de81f23717b913be7e` |

正式数据库变化仅为ordinary writer definition/comment的系统目录变化。部署事务对lesson、E-B1 evidence、settlement、bill、income、bill-lessons及R0做前后完整指纹比较，业务DML为0。真实planned没有生成actual。

保持不变：

- guarded updater：`ca52667c94a86608b4ab712f543b04b1`
- E-B2 resolver：`b83f0a270a79c4ed07663ab2c296360e`
- E-B2 trigger function：`4a163f6691c779531a65a10be0f4422e`
- F1 trigger function：`08f3c60890d4afab8d9c730eec286c8d`
- S1-C aggregate：`d24b82f51053b3960ce0e4839613ddc7`
- S1-C summary：`f9f5e0fffc2d0fcb5f917cc374c9e9ac`
- S1-C lock：`523058b631837025101d558668ce10c8`
- S1-C relock：`5b313cc696057a4a1f960ed8f1b50124`

## 5. Postdeploy

只读脚本：

- `sql/current/school_actual_duration_overage_s1_b_legacy_source_compat_postdeploy.sql`

所有运行均使用`BEGIN TRANSACTION READ ONLY`并明确`ROLLBACK`。最终结果：

- writer MD5及新旧marker正确；
- protected function MD5不变；
- F1和E-B1 immutable row trigger均保持enabled；
- 真实planned证据/resolver仍匹配且关联actual为0；
- 正式overage bundle count为0；
- lesson / settlement / bill / income为`649 / 15 / 9 / 42`；
- R0为`validation_preview_only / blocked / blocked`。

## 6. Rollback测试

测试脚本：

- `sql/current/school_actual_duration_overage_s1_b_legacy_source_compat_rollback_tests.sql`

测试共运行3次：

1. 首次因无证据legacy负向夹具先于locked settlement fixture存在，E-C reader按设计报`R1D_E_C_LEGACY_PLANNED_EVIDENCE_MISMATCH`；连接退出后事务回滚。将locked fixture创建提前。
2. 第二次因`created_at`使用transaction timestamp，而断言标记使用`clock_timestamp()`，把本事务新actual误归入历史；事务回滚。改为按两个测试actual UUID显式排除。
3. 第三次6/6通过，整体ROLLBACK，随后READ ONLY验证persisted rows=0。

通过项目：

- canonical planned 2h→2.25h仍生成15分钟/JPY2,500；
- synthetic approved legacy planned通过resolver继承`2036-07`并生成15分钟/JPY2,500；
- 无证据legacy、partial bundle、非青空拒绝；
- duplicate actual与locked权威来源月拒绝；
- source planned不变且不创建pending_makeup；
- existing actual没有被扫描；
- S1-C、bill、income与R0不变。

事务内source IDs：

- `684b0239-109c-4f02-bbce-f99f108704a9`
- `d4100000-0000-4000-8000-000000000001`
- `d4100000-0000-4000-8000-000000000002`
- `d4100000-0000-4000-8000-000000000003`
- `c2fc1b47-0e72-4499-95ab-b4248657203c`
- `3e931b35-4cdc-43e3-81f1-bed22d6df3aa`

事务内actual IDs：

- `68a9f865-34c1-42d8-93a9-ef2556588c56`
- `80f7464f-1629-4d4a-9776-07c3fd3b6b12`

为构造全NULL legacy planned及approved evidence，测试事务内短暂禁用F1 planned row trigger与E-B1 evidence immutable row trigger，写入明确`codex-test`夹具后立即恢复；partial负向测试沿用既有E-B2测试模式，在子事务内短暂移除两条bundle CHECK并由sentinel整体回滚。最终trigger/constraint状态恢复且所有marker残留0。没有使用真实planned进行写入测试。

## 7. 最终边界

- 兼容补丁部署验收停止时，真实planned `20533154-0de9-49b7-bbbd-907aa2a254ee`仍是`planned`且无关联actual；之后的真实业务生成结果见第8节，本阶段没有回写该planned。
- 历史actual没有backfill；NULL字段不参与S1-C。
- 既有canonical bill/income未修改。
- 页面/API无需修改，S1-D no-code-change结论不变。
- 未连接Cash DB；没有生成正式账单或收入。
- R0未解除。
- Git未add、commit或push。

该兼容补丁的数据库审查停止点为`S1-B_LEGACY_SOURCE_COMPAT_DATABASE_REVIEW_POINT`；后续真实业务验收与最终Git交付结论见第8节及文首最终状态。

## 8. 真实业务记录定向只读验收（补充）

2026-07-31对planned `20533154-0de9-49b7-bbbd-907aa2a254ee`与actual `4a1b74c6-65f0-4513-9c1e-4a094b7bb393`执行定向只读验收。所有数据库检查均在School DB的`REPEATABLE READ READ ONLY`事务中执行并`ROLLBACK`；没有调用写入型RPC，没有连接Cash DB。

| 项目 | 只读结果 |
| --- | --- |
| planned→actual关系 | `actual.planned_lesson_id`精确指向目标planned；目标planned关联actual精确为1条 |
| actual核心字段 | `actual / completed / billable`，duration `2.25`，actual minutes `135`，unit price `JPY 10,000`，lesson fee `JPY 22,500` |
| actual权威归属 | student `张倬闻`，student month `2026-07`，business entity `青空进学塾` |
| overage bundle | `15`分钟，`JPY 2,500`，`student_duration_overage_v1 / ordinary_actual_rpc`，decided_at非NULL |
| planned保持 | status仍为`planned`，duration `2`，unit price `JPY 10,000`，lesson fee `JPY 20,000`；updated_at早于actual创建 |
| canonical关系 | 仍精确1条：relation `0b0ffddf-6a28-e93e-6104-f9c78b2b0084`，bill `fdf3cdfe-f715-4814-b500-9ff2bfe77a63` |
| pending_makeup | 0；remaining credit为0 |
| 原canonical bill | 仍为`canonical_charge / income_created`、JPY 520,000；created_at与updated_at均早于actual，未因本次actual新增或修改 |
| income / School侧Cash关联 | 仍是既有income `f86ac9db-effd-402e-a320-1e4b6846a9c7`及linkage `45a5ff39-c2b4-4a9c-96c7-d891ffd30ca4`；二者created_at/updated_at均早于actual，没有因本次actual新增或修改 |
| 2026-07 settlement snapshot | 0条；overage snapshot 0条，未自动锁定或固化 |

S1-C对张倬闻`2026-07`的合格overage明细只有上述actual一条；live aggregate为`15`分钟、`JPY 2,500`、`CNY 107.50`、actual count `1`，来源月汇率为`0.043`。只读preview保持planned base为`52h / JPY 520,000 / CNY 22,360.00`；既有received equivalent为`CNY 22,360.00`，无overage公式的final due为`CNY 0.00`，DB返回的final due为`CNY 107.50`，正向增量与overage换算额完全一致。未执行lock/relock。

R0实查仍为`validation_preview_only / blocked / blocked`。这次验收证明真实业务记录已正确进入S1-B冻结事实与S1-C只读聚合/preview；没有生成新bill、income或Cash记录，也没有改变历史19条策略。

完整canonical planned与全NULL bundle但唯一命中approved E-B1 evidence并通过E-B2 resolver的legacy planned，均已支持新生成overage actual；`actual < planned`继续走partial。来源月`2026-07`未来按正常流程锁定后，S1-C才固化snapshot并由既有carryover承接下一自然月；本次没有锁定真实月结。Candidate、bill、income和Cash不直接扫描overage，原canonical bill不修改，历史旧actual不回填、不追收。

V2无登录及`school_lesson_records`宽松ACL/RLS是业务负责人接受的内部系统技术债务，不属于本补丁；V3已有正式安全登录。最终结论：`ACTUAL_DURATION_OVERAGE_COMPLETE`。
