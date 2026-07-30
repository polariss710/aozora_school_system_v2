# R1D-E-B2 actual writer 权威学生结算月切换报告

日期：2026-07-30（Asia/Tokyo）
阶段：R1D-E-B2
停止点：完成后停在数据库审查点；本阶段禁止 Git 提交、推送及进入 settlement reader / actual overage S1-B。

## 1. 结论

R1D-E-B2 已完成正式 School DB 部署、postdeploy、独立 rollback tests 与最终新连接复验，现停在数据库审查点。

- 切换瞬间全部 `234` 条 existing actual 已在同一原子事务写入 immutable evidence；lesson 业务行未修改，`student_settlement_month` 继续全 NULL。
- 切换后 actual 的学生月份由 DB 根据 canonical / fixed legacy planned 分类决定，兼容期 `year_month` 同步学生月份，老师月份只按 actual 日期决定。
- ordinary、cancelled、partial、canonical makeup、两个 makeup compatibility wrapper、guarded update 与 venue wrapper 共 8 个入口均覆盖。
- direct table INSERT / UPDATE 由 `BEFORE` trigger 封闭月份伪造、非法 source、partial source bundle 与 canonical/legacy 归属改写。
- ordinary `actual duration <> planned duration` 原校验仍存在且小于/大于拒绝、相等通过；未实现 overage，19 条历史 overage 的 S1-A 字段仍全 NULL。
- 未修改 settlement reader、15 个 locked snapshot、planned writer、页面、JS、candidate、R0、Cash 或空调范围。

## 2. Git 与保护边界

- branch：`main`
- 初始 HEAD / `origin/main`：`a3274b8cd4177f8aecdb3e1bfa560db5791e1f24`
- 初始暂存区：空
- 初始唯一未跟踪文件：`docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`
- 保护文件 SHA-256：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- 未读取、修改、移动、暂存或提交保护文件正文。

## 3. Preflight

- F1 当前权威 postdeploy：通过；version 为 `r1d_f1_planned_attribution_v1`。
- 切换前 actual：`234` 条，全部 `app_type=school`，全部有关联 source planned，`student_settlement_month` 全 NULL。
- 切换前 actual UUID MD5：`891eeabf9a48d1c7b00a695b21cf8e95`。
- 切换前 actual writer 8 入口组合 MD5：`4986090e0ba4e4706ea9ca4abd9580c5`。
- E-B1 旧 postdeploy 文件执行 1 次，在其已被 F1 合法替换的 planned writer 旧 hash 断言处停止；事务为 `READ ONLY` 且连接关闭回滚。该断言不是当前阶段权威边界，随后 F1 当前 postdeploy 完整通过。
- 两次补充只读查询分别发生 SQL 引号与歧义列名工具性错误；修正后均通过，未发生数据库写入。

## 4. 设计与部署范围

### 4.1 原子 evidence

新增 `public.school_legacy_actual_settlement_evidence`，同一 cutover 事务在锁住 lesson writer 后冻结全部 existing actual。每行保存 actual/source UUID、student/entity/teacher/subject、legacy `year_month`、teacher month、actual date、identity/full-row MD5，并重复保存固定 cutover count、UUID MD5、identity/full-row SHA-256。

固定 manifest：

- actual count：`234`
- actual UUID MD5：`891eeabf9a48d1c7b00a695b21cf8e95`
- identity SHA-256：`83f9df656fc8e089ce769cac84d61338c0889ac853b2e2b544f8b2bf3678650c`
- full-row SHA-256：`dd25082aac3216cf3ba6160e3ee81f56845359aa1a603e975b864bb630d933f8`

evidence 在 seed 后安装 INSERT/UPDATE/DELETE 与 TRUNCATE 拒绝 trigger；启用并强制 RLS；PUBLIC/anon/authenticated 无读写权，service_role 仅 SELECT。后续 actual 不会自动进入 evidence，不使用 `created_at` 判定 legacy。

### 4.2 source 分类与 table invariant

`school_resolve_r1d_e_b2_actual_student_month(uuid)` 只接受：

1. 五字段完整且内部一致的 canonical planned；
2. 五字段全 NULL、命中 E-B1 固定 279 evidence 且 student/entity/year_month/identity 全匹配的 legacy planned。

其他 NULL、partial、漂移、voided 或非法 source 一律 fail-closed；不使用 `coalesce`、时间戳、actual date 或客户端月份兜底。

`trg_school_lesson_r1d_e_b2_actual_attribution` 对新 actual 覆盖客户端月份，写入 `student_settlement_month=source authority`、`year_month=student month`、`teacher_settlement_month=actual date month`；同时检查 student settlement / teacher wage lock。canonical update 冻结 source/student/entity/student month，actual date 只更新 teacher month。legacy actual 保持 student month NULL，并只在 settlement/wage 均未锁且 identity 不变时允许 note/content/venue 非归属修改。

### 4.3 writer 入口

- ordinary/cancelled/partial 的现有函数签名、返回结构及业务校验保持；最终权威月份与权威 student lock 由同一 table invariant按 classified source执行，旧 `year_month` precheck仅保留 writer-first 兼容期的保守保护，不能成为写入权威。
- `school_create_lesson_credit_makeup_actual` 改为 source authority 学生月与 actual-date teacher month分离；remaining credit、non-billable、venue 与 teacher/student/entity校验保持。
- 两个旧 makeup 签名继续只调用 canonical makeup。
- guarded core 的 student lock 与 `year_month` 对 actual 改用 canonical student month或 actual legacy evidence month；venue wrapper 继续调用 core。
- actual writer 8 入口正式组合 MD5：`046cb8c0002528634b767a046e4626ab`。

## 5. Rehearsal、正式部署与验收

### 5.1 Rehearsal 与测试脚本修正

原 cutover 文件成功 rehearsal 与首次正式部署使用同一 SHA-256：`4f250a85c680be7e7961e2ba363c4c8c854244b7d6e53ba8db5461dbb40bf42b`。部署后 corrective 审查将该文件更新为最终可重放定义，最终 SHA 见第 8 节。

完整 cutover + rollback matrix 共执行 3 次：

1. rollback tests `932a763325adfafa89466e522366bb211bb773150a595c59e3e0a0b47465ace9` 在 rowtype 与 scalar 同列 `INTO` 的 PL/pgSQL fixture 语法处停止；改为分两次赋值，SHA 变为 `1ad6a755ae71a150052e7473b20d80fd4a5d2b6b7940e35acf6670ef74b0ce60`。
2. 第二次在构造 partial source fixture 时被既有 billing CHECK 先行拒绝；为实际执行 resolver 的 fail-closed 断言，改为在锁表、必回滚子事务内临时移除两个相关 CHECK，SHA 变为 `c8622d40877075dddfbf30e1060ec98303443e0583272b7800501e40145e60c2`。
3. 第三次 cutover 与 8 组测试全部通过，外层事务显式 `ROLLBACK`；新连接确认目标对象不存在、测试 marker/固定 UUID 0、actual 仍为 234/全 NULL，UUID MD5 与两个真实 fixture full-row MD5 全部恢复。

以上修正均未删除或放宽业务断言；production cutover 定义未因测试失败修改。

postdeploy 同事务验证首次因脚本自己的 `BEGIN READ ONLY` 不能嵌套在已写事务而停止，SHA `852e32304ef4bd8523210462f2b654424edc6199ba8639da0f7a79ca0ae4bfad`；加入 caller-owned transaction 开关后 SHA 为 `b7c406fcbe1177bba9b4970061917d6279e27f6ca550d5ca45d6c342d3f9e80a`，同字节 cutover + postdeploy 通过并回滚。另有两次 DNS 解析失败，均发生在建立数据库连接前，不计 SQL 执行或数据库写入。

### 5.2 正式部署

正式执行：

- `sql/current/school_tuition_r1d_e_b2_actual_writer_settlement_month_cutover.sql`
- 参数：`r1d_e_b2_commit=1`
- 结果：exit code 0，正式 `COMMIT`
- evidence DML：插入 234 条 immutable evidence
- lesson、settlement、bill、income、wage、overage、aircon、feature gate 业务 DML：0
- 业务 RPC：正式部署未调用
- Cash DB：未连接

### 5.3 Postdeploy 与最终复验

正式 postdeploy 及 rollback tests 后的最终 postdeploy 均通过，并各自在 READ ONLY 事务中 `ROLLBACK`：

- evidence 234，post-cutover actual 0；existing actual full-row 与 identity 未变，学生月仍 NULL；
- new actual invariant、8 writer call graph、ordinary `<>` 与 partial/makeup guard存在；
- planned `118 / 279 / partial 0`、F1 version/trigger 不变；
- E-B1 planned evidence 279 与 snapshot evidence 15 manifest 不变；
- candidate `118 / 254小时 / JPY2,474,000`、function/UUID/manifest hash 不变；
- R0 仍为 `validation_preview_only / blocked / blocked`；
- 资金链仍为 `9 / 42 / 121 / 42` 及冻结 hash；
- 历史 19 overage 全部 S1-A 字段 NULL；固定 8 makeup hash不变；空调四表及 lesson 组件仍为 0；
- settlement reader/writer 组合 MD5 仍为 `b17b31a3dc1797159556032abdb04ac3`。

## 6. 测试 fixture 与回滚证明

首次独立 rollback tests 8/8 通过；corrective 后原 8 组与新增 bypass 回归合计 9/9 通过并显式 `ROLLBACK`，随后新只读事务及最终新连接均确认测试残留 0。

- deterministic legacy planned fixture：`03755651-7e48-4bcb-8bdf-36581a1ef479`
- pre/post full-row MD5：`1e428d2dabd8293dc7ff4457e759696b`
- deterministic unlocked legacy actual fixture：`024be382-d7bd-4410-87a0-ab5b1ae71254`
- pre/post full-row MD5：`c73f02b7990f81710e9315ac09f64102`
- locked settlement / active wage fixture：`002875ac-4b12-4f83-b752-d5972d8bb7fa`
- 固定 direct-test UUID：`e2000000-0000-4000-8000-00000000a001`、`a002`、`a003`、`a010`、`a011`，最终残留 0。
- 独立测试自动生成 actual UUID：`030455bb-94e7-4c58-aa8b-3f940f52095e`、`0fb39f57-2922-4c01-9c91-dbcdc6626251`、`900684b3-4347-4ac8-bab1-72ea16dc50c1`、`9116aa27-8ccc-48e1-b982-b089a4b0ce71`、`ade1cf4e-edd1-4a01-9cc7-e22ef2bdc21c`、`d621221f-883c-4cb8-973e-4c01da95b883`、`f2e867f2-7cb8-4583-bc02-c92c968cc844`，最终均回滚。

测试覆盖 ordinary same/cross month、cancelled、partial、canonical makeup、两个 compatibility wrapper、legacy planned、identity drift、非法/partial source、direct forged/null month、canonical/legacy edit、student/wage lock、evidence immutable/ACL、planned isolation 与 overage NULL。

## 7. 数据库及 Git 交付状态

- 数据库已写入：是，仅正式 DDL/function/trigger/ACL 与 234 条 cutover evidence；existing lesson 业务行及其他业务表未修改。
- 白名单测试写入：仅 rollback 事务内；无测试数据 COMMIT，最终残留 0。
- 执行 SQL：cutover、corrective、postdeploy、rollback tests；未执行生产 rollback SQL。
- 测试调用 RPC：ordinary、cancelled、partial、canonical makeup、两个 makeup wrappers、guarded update；均只在 rollback 事务内。
- 文件变更：本阶段原 4 份工件加 1 份正式 corrective SQL；保护文件仍为唯一既有未跟踪文件。
- Git add / commit / push：均未执行；commit hash：不适用。
- `docs/current-status.md`、页面、JS 与其他既有文件：未修改。
- 当前停止点：`R1D-E-B2数据库审查点`；未进入 settlement reader 切换、R1D-E-C 或 actual overage S1-B，未解除 R0。

## 8. 部署后审查 corrective

### 8.1 审查发现与最小修复

部署后 ChatGPT 审查发现旧 trigger 在读取 `OLD` 前先执行 `IF NEW.lesson_type<>'actual' THEN RETURN NEW`，因此 direct UPDATE 可把 existing actual 改为 planned 并绕过后续 legacy/canonical、settlement lock 与 wage lock。

本次只调整 `school_enforce_r1d_e_b2_actual_attribution()` 的入口顺序：

- INSERT planned 继续立即返回，不受 actual invariant 影响；
- UPDATE 先检查 `OLD.lesson_type='actual'` 或 OLD 是否命中 actual legacy evidence；
- existing actual 的 `NEW.lesson_type` 必须仍为 actual，`NEW.app_type` 必须仍为 school；
- non-actual→non-actual 普通更新保持隔离；planned→actual UPDATE 明确 fail-closed；
- 未修改 evidence、ACL、RLS、writer RPC、reader或其他业务逻辑。

正式部署前后 hash：

- trigger function MD5：`c2a735047dd399b97cdae5bc84a7e636` → `4a163f6691c779531a65a10be0f4422e`
- actual writer 8 入口组合 MD5：`046cb8c0002528634b767a046e4626ab` → `046cb8c0002528634b767a046e4626ab`

### 8.2 Corrective 执行与测试记录

- corrective rehearsal + 9 组 rollback tests：1 次，全部通过并回滚；无需修改测试脚本。
- corrective + 最终 postdeploy 同事务 rehearsal：1 次，全部通过并回滚。
- 正式 corrective：1 次，exit code 0，`COMMIT`；仅替换 trigger function，evidence 未重 seed，业务行 DML 为 0。
- 正式 postdeploy：2 次（提交后及独立测试后的最终复验），均完整通过并回滚 READ ONLY 事务。
- 正式后独立 rollback tests：1 次，9/9 通过，持久测试行 0。
- 正式前有 1 次 DNS 解析失败，发生在连接数据库前；未执行 SQL、未写数据库，授权网络重试后成功。
- 失败修正记录：SQL/rehearsal/test 失败 0，业务断言删减或放宽 0。

新增回归明确验证：legacy actual→planned、canonical actual→planned、legacy actual→non-school、canonical actual→non-school 均返回 `R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE`；planned 行合法 note 更新通过。原 8 组矩阵全部继续通过。

corrective 后独立测试 actual UUID：`180feaec-d0a8-4ce7-8113-588c3c464d39`、`19650bd0-e0db-4dd4-8e87-ec1223ac76d0`、`70dd7075-a3d3-4462-9f23-45e66078bb83`、`9b30dea5-f805-4fe8-a1ac-a5461e8e6d04`、`a365c11b-b8a7-401a-b21e-1229ffa44822`、`d6d351e9-d541-4ade-99aa-a3293beeb8f2`、`d8a7e605-c871-41ee-89a7-213149843bac`及固定 `e200...a001/a002/a003`；全部回滚。

最终工件 SHA-256（报告自身 SHA 在最终文件校验输出中记录）：

- cutover：`0641685612f5c9a2e1a057d2f2f5f88c16f497a4de322960733add354b38142b`
- corrective：`72f298b418f4f640c864bfdccc5931497572218bd60b18d274e306441077a1db`
- postdeploy：`cb1e6f47e7efa2ecefbecfe65fe6be97697e3aecc2c76167448e84516c407600`
- rollback tests：`53819591f0462c66b38d0b2a1540d2c2926d6d09ca1a4655acd8dd1752e0ce7b`

最终数据库复验：234 evidence、UUID/identity/full-row manifest、existing actual full-row、student month NULL、post-cutover actual 0、planned 118/279、candidate、资金链、19 overage、8 makeup、15 snapshot、settlement reader 与 R0 全部不变；测试 marker 0。停回 `R1D-E-B2数据库审查点`。
