# School V2 学生月度结算线上开放 Phase A DB安全合同实施报告

日期：2026-08-09（Asia/Tokyo）

## 1. 结论

Phase A已成功完成并部署School生产库，不存在业务硬阻断，可以进入Phase B的Edge inventory、JWT绑定与错误映射设计。

- 已部署两个新的online admin wrapper：保存草稿与正式锁定分离。
- 两个wrapper仅`service_role`与postgres owner可执行；PUBLIC、anon、authenticated均拒绝。
- DB在同一事务内以`auth.users + school_app_memberships`复核传入actor是active admin，并对membership行持有`FOR SHARE`锁。
- 五个核心writer仍为owner-only；service_role不能直接执行。
- 两个既有local wrapper签名、定义和ACL不变，原rollback回归通过。
- unlock/relock仍为owner-only，没有wrapper、Edge、API或页面入口。
- 新status reader统一返回ordinary locked、historically consumed immutable、historical zero-carry complete、incomplete四类状态。
- 页面、`js/api`、Edge、Auth、Storage、membership业务数据、页面版本和三个Gate均未修改；当前页面仍只读。
- 正式持久化仅有函数定义、owner、ACL和comment；生产业务行变化为0。

DB只能确认“未来Edge传入的UUID当前对应active admin”，不能证明该UUID来自当前JWT。JWT subject与actor绑定必须由Phase B Edge完成。

## 2. 实时基线与Git

本轮开始时先观察到HEAD/origin为`083e91957dc18392a30b7b7533c4516ce7adab4d`；并行合法任务随后将main前向推进到`43764200e56e326e7c120c255b1426455ace8471`。本任务没有reset、rebase、checkout或回退，而是在重新fetch确认`HEAD=origin/main=4376420`、ahead/behind `0/0`后，以该实时状态实施。

生产页面版本始终为`v10.5.30`。开始时最新成功Pages run为`31316777159`，部署commit为`43764200e56e326e7c120c255b1426455ace8471`。本轮未修改或部署页面，也未升级页面版本。

实现提交：

- `937b70ead388b1201f0fdc1be4a8b7b5fb7955c6` — DB合同、rollback测试、postdeploy初版。
- `1f5168f` — 补全canonical fixture、manifest/金额/version负向矩阵及postdeploy技术修正。
- `109d189` — 补全local wrapper与helper ACL postdeploy断言。
- 最终文档提交见Git历史。

本任务没有触碰并行任务产生的tracked文件。现场最终8份受保护untracked文件及SHA-256见第11节。

## 3. Business-model expansion declaration

| 项目 | 声明 |
|---|---|
| 新业务表／列／enum | none |
| 新日期、月份、归属、identity、source、snapshot、version事实 | none |
| 新持久actor审计或idempotency模型 | none |
| `created_by`／`updated_by`语义变化 | none |
| 新历史解释、fallback、dual read/write | none |
| 表级DML／RLS／Gate变化 | none |
| writer authority变化 | 仅新增本任务明确批准的service-role-only online wrapper |
| reader authority变化 | 新增authenticated active-membership status reader |
| locking变化 | 新wrapper复用既有scope锁，并增加membership `FOR SHARE`及draft exact-version校验 |
| 权威来源 | 仍为DB preview、effective resolver、现有draft UUID/`updated_at`及核心writer |

没有未授权业务模型扩展。

## 4. DB改动清单

迁移：

- `sql/current/school_student_settlement_online_admin_contract_20260809.sql`
- `sql/current/school_student_settlement_online_admin_contract_rollback_tests_20260809.sql`
- `sql/current/school_student_settlement_online_admin_contract_postdeploy_20260809.sql`

新增函数（均为postgres owner、`SECURITY DEFINER`、`search_path=pg_catalog, public`）：

1. `school_assert_student_settlement_online_admin(uuid)`：owner-only actor assertion。
2. `school_assert_student_monthly_settlement_online_writable(uuid,text,uuid,text)`：owner-only effective/mutability/wage guard。
3. `school_assert_student_settlement_online_expected_facts(jsonb,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric)`：owner-only manifest/金额断言。
4. `school_get_student_monthly_settlement_online_status_core(uuid,text)`：owner-only status core。
5. `school_get_student_monthly_settlement_online_status(uuid,text)`：authenticated active-membership reader。
6. `school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)`：service-role-only online save。
7. `school_lock_student_monthly_settlement_online_admin(uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,uuid)`：service-role-only online lock。

最小加固的既有helper：

- `school_get_student_monthly_settlement_wage_blockers(text,uuid)`固定安全search_path，去除PUBLIC默认权限，保留现有anon/authenticated/service_role只读依赖；同时排除`is_no_wage=true`或`settlement_type=no_wage`的明细。
- `school_assert_student_monthly_settlement_no_wage_blocker(uuid,text,text)`固定安全search_path并改为owner-only。

未修改的受保护定义：五个核心writer、两个local wrapper、effective resolver和dialog preview的定义MD5均与部署前相同。

## 5. Online save合同

### 输入

输入只包含actor UUID、student UUID、month、source treatment业务选择及净额汇率输入、adjustment mode/manual显式金额、reason/note、preview/lesson manifest、DB expected金额/source count、两个旧active draft UUID/`updated_at`和可选correlation UUID。

不接收actor role、membership、business entity authority、operator authority、service-role信息、canonical confirmation、resolved adjustment或用户决定的final carry。business entity始终由DB根据student解析；final carry和resolved adjustment始终来自DB preview。

### 事务顺序

1. `auth.role()`必须为service_role。
2. active-admin assertion查询真实Auth用户与membership，并锁定membership行。
3. DB解析student权威business entity。
4. 获取既有settlement mutation scope锁。
5. unified effective guard只允许`incomplete`，并阻断ordinary locked、historical consumed、historical zero-carry、successor revision、账单消费、非no_wage工资链及scope异常。
6. `FOR UPDATE`读取两个active draft。
7. DB重跑preview，验证preview manifest、lesson manifest、source count、JPY/CNY金额、system difference和final carry。
8. 以DB规范化后的source/adjustment业务内容判断语义幂等。
9. 非幂等请求必须精确匹配旧draft UUID和`updated_at`；source与adjustment在同一外层事务写入。
10. 写后再次preview并复核；只返回draft，不自动lock或生成settlement。

### 幂等与并发

- 当前两个active draft及DB权威事实与请求目标完全一致时，直接返回原UUID/`updated_at`，`idempotent=true`，不supersede、不update。
- 不同payload若携带旧版本，返回`SETTLEMENT_SOURCE_DRAFT_STALE`或`SETTLEMENT_ADJUSTMENT_DRAFT_STALE`；不会覆盖先到请求。
- manifest/expected facts变化在核心writer前拒绝，source和adjustment均零写入。
- correlation UUID只原样回传，不伪装成持久幂等记录。

返回包含operation、固定authority、actor、scope、两个draft UUID/`updated_at`、两个manifest、权威preview、effective status及幂等标志。

## 6. Online lock合同

lock是独立动作，不与save合并。它只接受已保存的两个draft UUID/`updated_at`、manifest、expected DB金额/source count/final carry、note与可选correlation UUID。

- 与save相同地复核service role、active-admin actor、DB权威scope与scope锁。
- `incomplete`时两个draft必须仍是active最新精确版本；随后DB重跑preview并复核所有facts。
- canonical confirmation在DB内部按scope/manifest/final carry构造，仅作为权威响应；客户端不能传入或覆盖。
- 首次调用只委托owner-only `school_lock_student_monthly_settlement`，不调用unlock/relock。
- 网络重试后若effective state已为`ordinary_locked`，只有原draft已被该settlement消费、请求版本落在其created/consumed时间窗、manifest与冻结金额均一致时才返回同一settlement，`idempotent=true`。
- historical consumed和historical zero-carry绝不按ordinary lock重试处理；不同事实返回manifest/expected facts或`SETTLEMENT_LOCK_CONFLICT`。
- 不生成学费账单、老师工资、支付请求、Cash或Storage事实。

## 7. Status reader合同

`school_get_student_monthly_settlement_online_status(uuid,text)`从`auth.uid()`验证active membership，admin/operator/read_only可读；PUBLIC、anon、service_role、inactive和无membership拒绝。reader不写入、不自动建draft或settlement。

返回：

- student、month、DB权威business entity；
- unified effective state及source/carry；
- physical settlement UUID/status/locked_at；
- active或与ordinary settlement关联的consumed source/adjustment draft UUID、status、`updated_at`与展示字段；
- 当前preview/lesson manifest；
- DB权威preview、system difference、resolved adjustment、final carry；
- 安全immutable blocker code/detail；
- `can_save`、`can_lock`、`requires_repreview`。

生产postdeploy以真实scope验证四类状态：ordinary locked、historically consumed immutable、historical zero-carry complete和incomplete。没有physical settlement的历史零结转仍由统一resolver正确返回完成。

## 8. 稳定错误合同

稳定机器码包括：

- 权限/输入：`SETTLEMENT_TRUSTED_EDGE_ROLE_REQUIRED`、`SETTLEMENT_ADMIN_REQUIRED`、`SETTLEMENT_ACTIVE_MEMBERSHIP_REQUIRED`、`SETTLEMENT_INPUT_INVALID`、`SETTLEMENT_SCOPE_NOT_UNIQUE`。
- effective/不可变：`SETTLEMENT_NOT_INCOMPLETE`、`SETTLEMENT_ORDINARY_ALREADY_LOCKED`、`SETTLEMENT_HISTORICALLY_CONSUMED`、`SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE`、`SETTLEMENT_SUCCESSOR_REVISION_BLOCKED`、`SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED`、`SETTLEMENT_WAGE_BLOCKED`。
- preview/facts：`SETTLEMENT_PREVIEW_MANIFEST_STALE`、`SETTLEMENT_LESSON_MANIFEST_STALE`、`SETTLEMENT_EXPECTED_FACTS_MISMATCH`。
- 并发/幂等：`SETTLEMENT_SOURCE_DRAFT_STALE`、`SETTLEMENT_ADJUSTMENT_DRAFT_STALE`、`SETTLEMENT_SCOPE_BUSY`、`SETTLEMENT_LOCK_CONFLICT`。

本实现不接受客户端confirmation，因此不存在可被伪造的confirmation输入；`SETTLEMENT_INVALID_CONFIRMATION`不进入online接口。无持久request identity时，通用`SETTLEMENT_IDEMPOTENCY_CONFLICT`被更精确的两个draft stale或lock conflict取代。Phase B应按上述固定code映射脱敏用户文案，并在服务端日志保留原错误。

## 9. 权限矩阵

| 对象 | PUBLIC | anon | authenticated | service_role | postgres owner |
|---|---:|---:|---:|---:|---:|
| 五个核心writer | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 允许 |
| online save | 拒绝 | 拒绝 | 拒绝 | 允许 | 允许 |
| online lock | 拒绝 | 拒绝 | 拒绝 | 允许 | 允许 |
| local save/lock | 拒绝 | 拒绝 | 拒绝 | 允许 | 允许 |
| unlock/relock | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 允许 |
| status reader | 拒绝 | 拒绝 | active membership只读 | 拒绝 | 允许 |
| settlement/draft表DML | 拒绝 | 拒绝 | 拒绝 | 拒绝 | owner内部 |

online wrapper与local wrapper权限边界相同但operator authority不同；local仍使用`local_trusted_business_owner_v1`，online固定响应`authenticated_active_admin_edge_v1`，二者不混用。

## 10. 测试与部署结果

### 迁移与静态

- `git diff --check`通过；migration在生产连接中先以`phase_a_rollback=true`完成显式ROLLBACK rehearsal。
- preflight固定核心writer、local wrapper、resolver、preview的生产定义MD5并检查核心ACL与表级DML；漂移时在DDL前fail closed。
- 无动态SQL、无新table/column/enum、无RLS/Gate/page/Edge变化。

### Rollback matrix

固定`a109...` synthetic IDs覆盖：

- PUBLIC/anon/authenticated/service_role的wrapper/core ACL；admin/operator/read_only/inactive/no-membership/NULL actor。
- same-payload save幂等、两个admin旧版本覆盖拒绝、source/adjustment单事务、save不自动lock。
- preview/lesson manifest、source count、金额/final carry伪造均零写。
- carry、clear、manual三种adjustment，以及separate/net两种source treatment。
- 首次ordinary lock、旧draft拒绝、stale preview拒绝、完全相同lock重试同UUID。
- no_wage不阻断，非no_wage active工资锁阻断。
- 真实ordinary locked、historically consumed、historical zero-carry、active successor scope均只走写前拒绝。
- status reader四状态及operator/read_only读取、inactive/no-membership拒绝。
- bill/payment/工资/Cash下游零生成。

测试技术修复过程：首轮fixture缺少canonical planned→actual归属、第二轮planned时长不满足既有最小2小时合同，均由事务中止自动回滚；随后补齐合法planned来源。另因同一测试事务内`now()`固定，版本断言改为显式旧时间戳而不是错误假定`updated_at`在同一事务变化。最终矩阵输出`SETTLEMENT_ONLINE_PHASE_A_ROLLBACK_TESTS_PASS`，residue为0。

现有`school_tuition_p0f_local_settlement_management_rollback_20260803.sql`也重新执行并ROLLBACK，证明本机save/lock正常、重复lock幂等及ACL合同未破坏。

### 正式部署与postdeploy

- 正式执行`school_student_settlement_online_admin_contract_20260809.sql`一次，COMMIT成功；仅函数/ACL/comment持久化。
- 完整rollback test中的wrapper调用全部针对`a109...`白名单fixture并最终ROLLBACK；没有真实scope成功写调用。
- 已知真实immutable scope仅用于预期写前拒绝，未到达业务writer。
- 最终只读postdeploy输出`SETTLEMENT_ONLINE_PHASE_A_POSTDEPLOY_PASS`。

## 11. 生产零变化证明

部署前后下列数量/全行MD5完全一致：

| 表 | 数量 | MD5 |
|---|---:|---|
| settlements | 18 | `481ffa7ed5173da852f0f28ce66c2e9b` |
| adjustment drafts | 7 | `0b162413935ed3a35920d144faffbc52` |
| source drafts | 1 | `c2a01866c1bfe9edd5eb559d6faf4a67` |
| historical completion evidence | 4 | `9cb22ef4ddd83f7a77c8fcd2e3ab3966` |
| income | 55 | `c55f82c7d62dbe92d0b49714a911a234` |
| lessons | 744 | `02b9109c53d1a3d320d4c9f8899fdb40` |
| tuition bills | 22 | `e50673ac998ee2d84573a076a64d3d42` |
| tuition revisions | 20 | `ffdc498a6e256aa29064f021f22e4b00` |
| wage locks | 103 | `ea395407134045e7623e171b02d3d910` |
| wage details | 612 | `1d45d0ce37696051c233465efaf3de5e` |

- 真实持久online save/lock调用：0。
- 真实持久local save/lock调用：0。
- unlock/relock调用：0。
- rollback-only synthetic wrapper调用：有，均为固定`a109...`且residue 0。
- 学费、工资、支付请求、Cash、Storage、Auth和membership业务变化：0。
- Gate：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=enabled`。
- Edge部署0、Pages部署0、页面版本变化0。

最终只读控制面指纹为：Auth `1 / 7f1f47a6f4f6f626725fc510fd21abb9`、membership `1 / 332d6f2e305a24e390b058abde88ff68`、Storage objects `57 / 62fac5521274c58c6f6982a0c690c134`；Cash external requests `43 / f4b1876e981ef75828600e0c7f0dc371`、CNY transactions `74 / 070c262ec01008d404b424233d2a6e47`、JPY transactions `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`。本轮迁移与测试不含这些对象的持久写语句，也未调用Cash/Storage/Auth writer；这些值仅作为最终只读现场记录。

最终受保护untracked文件：

| 路径 | SHA-256 |
|---|---|
| `docs/school-v1-decommission-preflight-p1a-online-evidence-20260809.md` | `1047c2d686a43499e21a43055973475aeb0d52a9fd36c0604aa98ce8ebf0c519` |
| `docs/school-v1-decommission-readonly-investigation-20260809.md` | `3e65e0091e68cd419ac13f0e692fcce99f07041abfcdab3b8786e526a800fcaa` |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

以上文件未修改、移动、删除、执行、暂存或提交。

## 12. Phase B建议（本轮未实施）

仍建议两个独立Edge：

1. `save-student-settlement-draft-online-admin`
2. `lock-student-monthly-settlement-online-admin`

共同合同：

- 从Bearer JWT验证真实用户，强制`actor_user_id = JWT sub`，禁止request body覆盖。
- user-scoped客户端先检查active admin；server-side再以service role调用对应DB wrapper，DB完成第二次active-admin复核。
- request body只透传本报告第5/6节允许的业务输入和expected facts；不接受business entity/role/authority/confirmation/service key。
- response透传DB的scope、draft/settlement UUID、versions、manifest、authoritative preview、effective status、idempotent与correlation ID。
- 将第8节固定code映射为安全HTTP状态和用户文案；原错误只进脱敏服务端日志。
- 网络结果不明确时先调用status reader恢复，不盲目重试不同payload。

部署顺序建议：完成Edge inventory与密钥/日志审计 → 部署两个Edge但无页面调用 → Edge负向/重试测试 → `js/api`接入 → 页面只读状态恢复 → 最后单独授权开放save，再单独授权开放lock。回滚顺序反向：先移除页面/API可达调用，再停Edge；DB wrapper可保留为不可达安全能力。

Phase B尚需：部署Edge inventory、JWT/actor绑定、CORS与错误映射、日志中correlation/actor记录、service-role不出浏览器、页面P0边界测试。持久actor审计表和idempotency表均未新增；现合同进入Phase B不需要额外业务模型授权。若未来要求持久request/actor审计，则必须另行取得精确模型授权。
