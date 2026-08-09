# School V2 学生月度结算线上开放 Phase B Edge 与隐藏 API 实施报告

日期：2026-08-09（Asia/Tokyo）
仓库：`/Users/polariss710/Documents/aozora_school_system_v2`

## 1. 结论

Phase B 已完成：生产新增两个互相独立的 Edge Function：`save-student-settlement-draft`与`lock-student-settlement`，均为ACTIVE/version 1；隐藏API已提供status/save/lock三个方法，但没有任何page/HTML入口、按钮或import。Edge先验证精确Origin、用户JWT和active-admin，再延迟读取server-only service-role并调用Phase A对应wrapper；浏览器不能提交actor、role、业务归属、authority或DB确认文本，Edge不计算金额。

生产active-admin不可变范围验收通过：陈红卓2026-07的status为`historical_zero_carry_complete`、`can_save=false`、`can_lock=false`；save与lock各一次均在任何业务写入前返回HTTP 409 / `SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE`和独立request ID。真实draft、settlement及全部财务事实零变化。Phase C页面接入尚未开始。

业务模型扩展声明：新表、列、enum、状态、权威事实、reader precedence、持久幂等事实、长期兼容路径均为`none`。本轮只实现业务负责人明确批准的两个Edge控制面入口、共享校验模块及隐藏API，不改变Phase A业务语义。

## 2. Git与实时基线

- 初始分支/HEAD：`main` / `f22a3276be68f138af08a7961c678d458b6bee83`；fetch后与`origin/main`一致，ahead/behind `0/0`。
- Phase B部署前checkpoint：`008dfe2`（`feat: add guarded settlement edge entrypoints`）。
- 执行期间并行的V1下线任务合法推进并push了`a78c25daeb11afae0b9e3f64a30d548650b77761`；本任务未reset/rebase/checkout或覆盖该提交。
- 并行push将`008dfe2`一并推到origin，并触发Pages run `31319615881`成功；这不是本轮主动Pages部署。生产版本仍为`v10.5.31`，本轮没有版本或页面入口变化。
- 实现前生产Edge共6个；两个目标slug均不存在。
- 开始与结束均没有纳入任何受保护untracked文件。

## 3. Edge清单与部署顺序

| Edge | 生产UUID | version | verify_jwt | 部署结果 |
|---|---|---:|---|---|
| `save-student-settlement-draft` | `d643ab21-9306-4031-b5f4-2727e904a48a` | 1 | false | ACTIVE |
| `lock-student-settlement` | `8fab9f4d-96de-43c8-8a15-98cec8096f9b` | 1 | false | ACTIVE |

严格按save先行：先部署save，完成生产list、CORS/401/schema负向测试、School/Cash指纹和Phase A postdeploy后，才部署lock。`verify_jwt=false`仅关闭网关的提前JWT短路，使Edge可对每个JSON错误生成server request ID；每个POST仍在函数内通过`auth.getUser(jwt)`验证真实Auth用户，再由用户态`school_require_current_app_admin()`验证active-admin。缺失/无效JWT均401，service-role不会成为用户身份。

## 4. Save合同

- 只接受POST/OPTIONS和`application/json`，body上限64 KiB；未知或缺失字段fail-closed。
- 允许的业务输入只有学生、月份、source treatment、显式汇率事实、adjustment mode、manual amount、reason/note、两个manifest、source count、6个expected金额、既有draft UUID/`updated_at`及可选correlation UUID。
- 金额必须为十进制定点字符串，Edge只做格式验证并原样传递；非manual mode禁止客户端金额，manual mode必须是明确用户输入。
- 浏览器不能提交`actor_user_id`、role、`business_entity_id`、operator authority、service-role、confirmation text或任何额外字段。
- active-admin通过后只调用`school_save_student_monthly_settlement_draft_online_admin(...)`；actor UUID来自验证过的JWT，不接受body覆盖。
- DB继续权威验证effective state、manifest、lesson manifest、expected金额、expected version、active revision、工资/财务不可变链、幂等和scope事务锁。

## 5. Lock合同

- 与save为独立部署单元，互不调用。
- 除共同expected事实外，必须提供非空的两组draft UUID/`updated_at`以及严格布尔`confirm_lock=true`；不接受reason、source mode、adjustment mode、manual amount或任意save字段。
- Edge不生成DB canonical confirmation，不计算settlement、adjustment、carryover或任何金额；active-admin通过后仅调用`school_lock_student_monthly_settlement_online_admin(...)`。
- DB继续生成canonical确认并复核active draft版本、两类manifest、6个expected金额、active successor revision、工资/财务不可变关系、幂等及scope锁。

## 6. Service-role隔离与错误合同

- `SCHOOL_SERVICE_ROLE_KEY`只出现于Edge runtime共享模块，浏览器HTML/JS和响应均不存在；secret在JWT和active-admin验证完成后才延迟读取。
- Edge runtime使用`SCHOOL_SUPABASE_URL`、`SUPABASE_ANON_KEY`和`SCHOOL_SERVICE_ROLE_KEY`；没有使用V2禁用的`SUPABASE_DB_URL`。
- 允许Origin仅为`https://polariss710.github.io`及localhost/127.0.0.1的8000、8001开发端口；无`*`，非法Origin不反射ACAO。缺失Origin仅作为受信CLI策略接受且不返回ACAO。
- 所有JSON成功/失败均带server `request_id`及`x-request-id`；响应通过字段allowlist删除`actor_user_id`、`operator_authority`与`canonical_confirmation`。
- DB稳定码映射为明确HTTP/action；`55P03`为423/`retry_later`，并发、manifest、expected facts、draft stale和不可变关系均fail-closed。未知内部错误不回传原始DB信息。
- 日志只记录request ID、Edge名、操作、月份、HTTP状态、稳定码和耗时，不记录JWT、service-role、student UUID、reason/note、payload、金额或DB原始错误。

## 7. 隐藏API

新增`js/api/student-settlement-online-api.js`：

1. `getStudentSettlementOnlineStatus`只调用Phase A authenticated status reader。
2. `saveStudentSettlementDraftOnline`只调用save Edge。
3. `lockStudentSettlementOnline`只调用lock Edge。

API显式构造字段白名单，不传actor/role/业务归属/authority/确认文本，不计算金额，不自动重试。网络超时或返回不明确时抛出`SETTLEMENT_EDGE_RESULT_UNCERTAIN`并标记`requiresStatusRecovery=true`，要求status-first恢复。全仓page/HTML import为0，页面直接Edge调用为0，浏览器service-role为0，`js/legacy-core.js`修改0。

## 8. 测试与验收

- 新专项Node测试：8/8通过，覆盖严格schema、交叉payload拒绝、金额字符串、时间/UUID/manifest、confirm、Origin、auth/admin/RPC顺序、request ID、错误映射、响应脱敏、独立部署单元、隐藏API/page/service-role闭包。
- `node --check js/api/student-settlement-online-api.js`和`git diff --check`通过。
- 既有`settlement-trusted-tool`、`settlement-p0f-dialog-preview`、lesson writer P0测试通过。
- 两个当前HEAD既有脚本为陈旧基线而失败，本轮未修改其目标文件：`settlement-p0b2-adjustment-authority-static-test.mjs`仍要求已退役的旧直写参数；`p0-g1-a-auth-guard-static-test.mjs`仍硬编码旧cache版本。没有为通过旧断言恢复writer或回退合法版本。
- save生产负向：OPTIONS 204、缺失JWT 401、无效JWT 401、未知`actor_user_id` 400、非法Origin 403；一次本机service-role变量未加载的请求实际等价缺失JWT 401。
- lock生产负向：OPTIONS 204、缺失JWT 401、无效JWT 401、未知`confirmation_text` 400、非法Origin 403、GET 405。
- Chrome active-admin：status reader成功；save/lock不可变范围各返回409稳定码，request ID分别为`d48cfd66-d725-4a3f-9c57-477e56263fcd`与`8daa63e8-d889-4661-9d70-2526dee49bf9`。
- Chrome日志有1条本轮前已存在的lesson edit错误，以及5条因验收动态创建额外Supabase客户端产生的“Multiple GoTrueClient”测试工具警告；没有Edge业务错误。没有修改页面代码或生产页面状态。

## 9. 请求与写入计数

- Edge HTTP请求：save 7次、lock 7次，合计14次；其中2次OPTIONS，10次在Origin/method/schema/auth阶段拒绝，2次active-admin到达Phase A wrapper并因不可变状态409拒绝。
- active-admin status reader：Chrome只读调用3次。
- Phase A online wrapper：save 1次、lock 1次；均在任何draft/settlement写入前拒绝，COMMIT业务行0。
- SQL文件执行：`school_student_settlement_online_admin_contract_postdeploy_20260809.sql`只读/ROLLBACK验收3次；另执行School/Cash指纹SELECT。DDL/DML 0。
- Edge控制面持久写入：部署2个函数。数据库业务写入、School/Cash/Storage业务写入、fixture、结算、工资、账单、income和Cash写入均为0。

## 10. 零变化核验

部署前、save后、lock及active-admin验收后，以下数量/MD5完全一致：

- settlement 18、adjustment drafts 7、source drafts 1、historical evidence 4；
- lessons 744、tuition bills 22、revisions 20、income 55、expense 47；
- wage locks 103、wage details 612、payment requests 51、account transactions 187；
- Storage objects 57；Cash CNY 74、JPY 31、external requests 43；membership 1。

Gate始终为`student_tuition_cash_submit=enabled / student_tuition_generate=blocked / student_tuition_preview=enabled`。

`auth.users`数量仍为1、membership不变；其整行指纹在14:52:01发生一次`updated_at`变化。时间早于本轮第一个动态测试客户端，且与已打开课时页当时的lesson edit事件同秒，属于现有浏览器Auth会话元数据活动；无membership、role或业务授权变化，不是本轮业务写入。

## 11. 回滚合同

本轮未执行回滚。若Edge自身需要紧急撤除，应先禁用/删除单个独立Edge deployment（save和lock可分别处理），再用前向Git revert撤销`008dfe2`；不得reset/rebase，不需要也不得回滚Phase A DB合同或修改任何业务行。网络结果不明确时先读取online status，不盲目重试。

## 12. 剩余项与受保护现场

- Phase C页面入口、按钮、对话框、文案、页面import、页面版本和Pages专项部署均未实施。
- 因本机没有可用的service-role secret值，真实service-role Bearer负向HTTP未完成；静态合同、用户JWT验证顺序和浏览器零secret已验证。不可将secret取回浏览器测试。
- 没有可用的真实non-admin JWT，因此operator/read_only/inactive的Edge层HTTP 403保留给Phase C；Phase A DB角色矩阵和本轮mock顺序测试已通过。
- 8份既有受保护untracked文件均未修改、移动、删除、执行、暂存或提交；SHA-256：
  - `1047c2d686a43499e21a43055973475aeb0d52a9fd36c0604aa98ce8ebf0c519` `docs/school-v1-decommission-preflight-p1a-online-evidence-20260809.md`
  - `3e65e0091e68cd419ac13f0e692fcce99f07041abfcdab3b8786e526a800fcaa` `docs/school-v1-decommission-readonly-investigation-20260809.md`
  - `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`
  - `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`
  - `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`
  - `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`
  - `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`
  - `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`
- 执行期间另出现外来untracked `sql/current/school_v1_decommission_p1_b1b_payment_rpc_legacy_closure_20260809.sql`（当时SHA-256 `2a9f0cbb069ec4ddbdaecaee63cfdd41e3e24c65ebccd3b21402df56f0814f4d`）；本任务未读取正文、修改、执行或暂存。它随后由其所属并行任务合法纳入`a78c25d`，因此终态不再是untracked。

## 13. Phase C建议

Phase C应保持最小接入：仅active-admin页面导入隐藏API；先status/preview，再以DB返回的manifest、expected金额和draft UUID/`updated_at`组装save/lock请求；所有模式选择与manual amount必须由负责人明确输入，UI不计算权威金额。锁定必须独立二次确认，结果不明确必须status-first。上线前补齐真实operator/read_only/inactive 403矩阵，并使用专用安全测试scope完成一次ROLLBACK或明确的不可写范围验收；不得用真实未结算学生做自动commit测试，不恢复core/unlock/relock入口，不把service-role带入浏览器。
