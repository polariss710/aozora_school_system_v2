# 彭宇晗、李天伦 2026-08 学费汇率修正及真实 Reissue 操作报告

日期：2026-08-04

## 最终结论

业务负责人授权的两组独立 `Void → Reissue` 已完成。两人旧 revision 2、bill、income 均合法保留并转为 `voided / cancelled / cancelled`；各新增一条 void event；新 revision 3 均为唯一 active，新 income 均为 pending，未提交 Cash。

| 学生 | 新 revision 3 | 新 bill | 新 pending income | JPY | 汇率 | carry CNY | 最终 CNY |
|---|---|---|---|---:|---:|---:|---:|
| 彭宇晗 | `f7bbd000-9753-4f00-9d3a-d8705ee8d5e9` | `a5cac133-36ee-4324-9c67-f95eadf62200` | `648e264d-3435-43f1-a797-cf1394011f65` | 204,000 | 0.043 | -624.75 | 8,147.25 |
| 李天伦 | `f7150ce5-fb77-4b7f-99f8-207bfbbced91` | `66a1f276-2756-466f-b709-b8ca29063fd9` | `efd670bc-8dba-4926-82c4-2d194281a609` | 220,000 | 0.042 | 0.00 | 9,240.00 |

## Git、凭证与操作前基线

- 实时 `HEAD = origin/main = 017a584086fb8d4d1dd33df7bfdfa7f22fd21825`；合法历史未回退。
- worktree 开始时仅有原六份受保护 untracked 文件，SHA-256 与上一轮一致。
- 经业务负责人在本任务中追加明确授权，canonical project service-role key仅由官方 Supabase CLI 在单次受控进程内读取；未打印、落盘、写日志、进入文档或 Git，进程结束即丢弃。
- Gate：`student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=blocked`。

操作前目标链：

| 学生 | active revision 2 | bill | pending income | rate / CNY |
|---|---|---|---|---|
| 彭宇晗 | `49e530ee-d190-45e2-8f2f-24b16713b194` | `bcd482dd-f376-4791-9862-a0ecbc0ba956` | `363ac949-7315-4207-8d75-ebab1a0623f2` | `0.0415 / 7,841.25` |
| 李天伦 | `8002e02c-a556-4161-bf01-6532f0eae0dd` | `872cc6d3-c524-4566-ad3c-a02f7987a412` | `acdd46db-0d44-4860-8c6d-672ea0b546bc` | `0.0427 / 9,394.00` |

两人 School Void preflight均为 `eligible=true`，Edge Cash权威preflight均为 `cash_fact_count=0`；income均pending，School linkage/account transaction、actual、wage blocker均0。五项validator（identity、bill-income、bill-lessons、generation revision、adjustment）全部通过。

彭宇晗 July settlement `6ec3b815-5540-44bd-88ee-9e30a5284770` 操作前为 `locked / carry -624.75`，`updated_at=2026-08-03 14:40:17.227562+00`；两条immutable variance claim的组合hash为 `fbce39067e6d98167cdb474eb9635c92`。李天伦 July settlement数量为0。

## Void 操作

管理工具分别执行 `status`、`history`、`void-preflight`、`void` dry-run和带完整expected facts的 `void --execute`，未合并批处理。

### 彭宇晗

- old revision 2：`49e530ee-d190-45e2-8f2f-24b16713b194 / voided`
- old bill：`bcd482dd-f376-4791-9862-a0ecbc0ba956 / cancelled`
- old income：`363ac949-7315-4207-8d75-ebab1a0623f2 / cancelled`
- new void event：`a5548110-8020-48d8-8966-5e56aecfcdfd`
- 释放12条active lesson claim和原active carryover claim；历史relation/snapshot/manifest保留。

### 李天伦

- old revision 2：`8002e02c-a556-4161-bf01-6532f0eae0dd / voided`
- old bill：`872cc6d3-c524-4566-ad3c-a02f7987a412 / cancelled`
- old income：`acdd46db-0d44-4860-8c6d-672ea0b546bc / cancelled`
- new void event：`1a39e70d-1203-4cb7-ba44-e316345d91d9`
- 释放10条active relation claim；历史relation/snapshot/manifest保留。

对两个old revision重复调用正式Void均由Edge返回HTTP409，管理工具报告“Void preflight failed; zero writes performed”。每个generation当前共有两条void event，分别对应历史rev1和本轮rev2；本轮每人精确新增一条。

## 普通 Reissue guard 最小修复

彭宇晗DB普通preview首次即精确返回目标金额，但正式ordinary Reissue在写入前返回 `TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED`，事务零写入。根因是P0-E旧guard把所有“曾被上一revision消费的非零carry”一律判为历史异常，没有区分当前仍locked且carry完全一致的正常来源。

Business-model expansion declaration：新表、列、状态、日期/月、身份、来源、快照/版本、可写事实、字段语义/可变性/权威、双写、fallback、历史重解释及破坏性变更均为`none`。唯一修正是既有ordinary Reissue eligibility：

- source settlement当前为`locked`；
- student/entity/month与上一bill snapshot一致；
- 当前DB权威carry与上一bill冻结carry按CNY两位精确一致；
- 同时满足时允许ordinary Reissue重新认领；
- 非locked、carry变化或历史异常继续稳定返回`TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED`并必须走P0-E。

批准映射为本任务第五、六、十节要求沿用现有locked July settlement、不得新增P0-E adjustment/重复claim并得到CNY8,147.25的明确合同。writer仍为原service-role-only local trusted RPC，anon/authenticated无EXECUTE；未改变表、字段或历史记录。

修复部署后：locked-carry rollback PASS、固定whitelist commit PASS、duplicate幂等、五项validator、原P0-E unlocked异常回归 `P0E_ROLLBACK_TEST_PASSED`、本轮postdeploy PASS。固定fixture student `d0d00000-0000-4000-8000-00000000a001`及关联对象最终residue 0。

历史`school_tuition_p0d_postdeploy_20260803.sql`因硬编码旧generation数量返回`P0D_GENERATION_BASELINE_DRIFT`；这是本轮已授权新增rev3后的预期旧基线失效，检查本身只读且零写入。未改写历史测试，本轮使用新postdeploy验证当前合同。

## DB权威 Preview 与 Reissue

### 彭宇晗

- candidate：12行 / lesson count 12 / 24h / JPY204,000
- candidate manifest：`51fd7e9750cac88b917d6c94a7fa5f7fce1956efff5c89814941bb704c30bfa3`
- generation manifest：`335467e94f70cbcbf23070afc9ad80c59aad501266ce3598fd03394b5795dcee`
- exchange：`204000 × 0.043 = 8772.00`
- locked carry：`-624.75`
- final：`8147.25`
- 新relation：12；P0-E adjustment：0。
- 当前唯一active carry claim为rev3/bill `f7bbd000-… / a5cac133-…`；旧rev2历史消费证据保留但不是active claim。

### 李天伦

- candidate：10行 / lesson count合计15 / 20h / JPY220,000
- candidate manifest：`56348ea803f4f992be3586bb5ff8aeabee3a2463f86d548477da425a148b23be`
- generation manifest：`ba617d2da313363464eae16614c174faf27f4fc9b72ee69a4079b2e4280d4803`
- exchange/final：`220000 × 0.042 = 9240.00`
- previous settlement：NULL；carry：0；新relation：10；P0-E adjustment：0。
- 未创建July settlement或零金额carryover对象。

两次duplicate Reissue均返回 `idempotent=true` 和原revision/bill/income，行数零新增。两人新bill的五项validator全部通过。

已作废课时继续被排除，active relation均为0：

- 彭宇晗：`6f22f125-4bd3-4278-8265-b04f39b3e8c2`、`d4d261bb-5b6b-4ab5-8dc8-7a2c7d6ca5dc`、`8edaeefc-9295-4da5-83a2-5f38e4beda8d`。
- 李天伦：`40b45df8-6ed3-4ccd-9ffd-25fb06de18fe`、`f71185d0-92d0-4d73-8b0e-ea5c56ea7c49`、`0667c085-73ae-495e-ad05-e29ae98ca5cb`、`538ee794-8185-4d42-ac48-a44a7ce8cca6`、`61e9b683-9bff-4c30-9174-a4ad3463f430`、`6ce1da2f-0621-4ceb-ace4-b9994ef21fb1`。

## 数据保护与前后指纹

| School对象 | before | after | 说明 |
|---|---|---|---|
| lesson | `731 / f3cb7c99e78b9fb26b5d557c53dc4f20` | 同前 | 不变 |
| settlement | `18 / 481ffa7ed5173da852f0f28ce66c2e9b` | 同前 | 不变 |
| variance claim | `2 / fbce39067e6d98167cdb474eb9635c92` | 同前 | 不变 |
| generation identity | `15 / 60f11efc1aebad6b182f7d0da08d36d7` | 同前 | 不变 |
| generation adjustment | `1 / 30304a8ab7a3edbe796b5528512ac242` | 同前 | 彭/李均0 |
| School linkage | `40 / 8e467489878b5bbe15f9eadbcbaabb10` | 同前 | 不变 |
| account transaction | `186 / 63963e4e15acfda30a036698f09dc795` | 同前 | 不变 |
| revision | `18 / 6756c752736bce391c661b3ba15e564b` | `20 / ffdc498a6e256aa29064f021f22e4b00` | 仅新增两条rev3并void两条rev2 |
| bill | `20 / 73d412333a7885fac4673a8fff8a78a4` | `22 / e50673ac998ee2d84573a076a64d3d42` | 仅新增两张bill并cancel两张old bill |
| income | `53 / 85b19ec34c40a59a52c852a5e9f959a4` | `55 / fa99ab1662937885450e517eaf3fcf36` | 仅新增两条pending并cancel两条old income |
| relation | `308 / 4603f7c51250f39f7e2d366a5e76cedb` | `330 / e3e2e0044c17864bc66c7e2861176c8b` | 仅新增12+10条rev3 relation |
| void event | `3 / 77cdf1ea30ebd54801c6ce2b392bf73a` | `5 / de7c29ebdbb72a2a0feff48ec4608f69` | 每人新增1条 |

Cash request/CNY/JPY transaction前后分别保持：

- `39 / 303e10bc1a28a0abd8b27afd3929cfd8`
- `71 / d7e72182970de4ea8849c994b67e8dcc`
- `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`

两条old income和两条new income的Cash request/CNY/JPY事实均为0。Cash只读preflight返回新income classification `ELIGIBLE_FOR_CASH_SUBMIT`，冻结金额分别为CNY8,147.25和CNY9,240.00，但 `gate_state=blocked / eligible=false`，没有提交Cash。

张倬闻仍为rev2 `7d319b0d-8f62-41e9-95bf-c1a0c6ed7090`唯一active，income `d980cedd-ebba-4be1-afcb-b25dfa26798a`仍pending CNY27,950，未修改。Gate终态仍为`enabled / blocked / blocked`。

## 执行的SQL、工具与RPC

生产RPC定义执行：

- `sql/current/school_tuition_locked_carry_ordinary_reissue_correction_20260804.sql`

测试及只读验收：

- `school_tuition_p0e_fixture_lifecycle_20260803.sql`：`preflight / insert_locked / cleanup / residue / insert / cleanup / residue`
- `school_tuition_locked_carry_ordinary_reissue_rollback_tests_20260804.sql`
- `school_tuition_locked_carry_ordinary_reissue_whitelist_commit_test_20260804.sql`
- `school_tuition_p0e_rollback_tests_20260803.sql`
- `school_tuition_locked_carry_ordinary_reissue_postdeploy_20260804.sql`
- `school_tuition_p0d_postdeploy_20260803.sql`：只读旧基线断言如上预期失败，零写入

正式工具：`scripts/manage-atomic-tuition.zsh status/history/void-preflight/void/reissue-preview/reissue`。主要RPC/Edge：

- Edge `void-atomic-tuition-generation`
- `school_get_atomic_tuition_void_preflight`
- `school_void_atomic_student_tuition_generation_local`
- `school_build_student_tuition_generation_snapshot`
- `school_reissue_atomic_student_tuition_generation_local`
- 五项tuition validators
- `school_get_cash_income_submission_preflight`（只读）

未执行generic cancellation、直接业务表DML、Cash writer、lesson writer、settlement writer或Gate writer。

## 精确真实写入与测试数据

真实业务写入仅为：两条rev2状态变更、两张old bill和两条old income取消、两条void event、两条rev3、两张new bill、两条new pending income、22条new relation及对应snapshot/manifest。另有既有RPC函数定义和comment更新。

真实业务写入为0：lesson、settlement、variance claim、settlement adjustment/carryover、P0-E generation adjustment、Cash request/transaction、School linkage/account transaction、Gate、张倬闻及其他学生。

测试写入仅限固定`codex-test tuition-p0e-forward-adjustment-20260803` whitelist UUID集合；rollback无持久化，commit test后精确cleanup，最终residue 0。

## Git交付

- parent：`017a584086fb8d4d1dd33df7bfdfa7f22fd21825`
- verified SQL commit：`baed587`
- docs commit：`PENDING_DOC_COMMIT`
- closeout/push/final status：见最终交付答复

六份受保护untracked文件未修改、未stage、未提交；最终SHA-256在Git收尾前再次核验。

## 终态

两人的目标金额已经由DB权威冻结并进入pending income。Cash submit Gate仍blocked，本任务不构成Cash提交授权。
