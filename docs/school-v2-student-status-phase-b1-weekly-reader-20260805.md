# School V2 学生月份状态 Phase B1：周看板历史课时 reader 修复报告

日期：2026-08-05
结论：**Phase B1 已完成，可以进入 B2 的独立授权；本轮未开始 B2。**

## 1. 范围与模型声明

本轮只修复 `public.school_get_weekly_lesson_operations(date)` 对 `school_students.status` 的错误当前态过滤。周看板继续按既有课时事实、周边界、business entity 和补课余额合同聚合，不接入月份状态 resolver，不改变候选筛选、writer、页面或 API ABI。

业务模型扩展声明为 `none`：新表、业务列、状态、日期/月、身份、来源、快照、版本、可写事实、字段语义、mutability、writer authority、locking、reader precedence、fallback、dual write、历史解释和破坏性 schema 变更均为 `none`。本次只移除错误的当前状态行裁剪，不新增权威事实。

## 2. 实时基线

- Git：`main`，修改前 `HEAD = origin/main = 7d473d0c721609b557d0b247053b9b21cbbdccd3`，ahead/behind `0/0`。
- 页面版本：`v10.5.6`。
- 修改前 Pages：run `30976920833`，`success`，head `7d473d0c…`。
- Gate：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=enabled`。
- 唯一生产状态事件：`4190bddf-d995-4e6a-af6b-85997e6f999b`，student `cff85c52-6acc-4b0f-8c92-3db280a5dd77`，`2026-07-01 / paused`，row version `70deb…`；事件整行 MD5 `eeeb492ac7577ff85eb0926aa0b57301`。
- resolver：该学生 2026-06 为无事件前固定 `active` fallback；2026-07、2026-08 均由事件解析为 `paused`。
- 实时 `school_lesson_records` 为 736 行，而任务参考值为 733。差额是调查开始前已存在的三条正常 production actual：`68439257-…`、`6d723e3b-…`、`5eacba3e-…`，创建时间均早于本轮部署。本轮以实时 736 行及 MD5 `7755ad0edf8eea674003a59b60c1d66c` 为保护基线，没有回退或修改它们。

修改前函数：

- signature：`school_get_weekly_lesson_operations(date)`；
- return：固定 12 列 `student_id uuid, business_entity_id uuid, weekly_planned_count bigint, weekly_planned_hours numeric, weekly_registered_count bigint, weekly_completed_hours numeric, weekly_cancelled_count bigint, overdue_unregistered_count bigint, upcoming_unregistered_count bigint, open_credit_source_count bigint, open_credit_hours numeric, oldest_credit_date date`；
- owner `postgres`，`SECURITY INVOKER`，`STABLE`，parallel unsafe，leakproof false；
- `search_path=public`；
- EXECUTE：`postgres / anon / authenticated / service_role`；
- definition MD5：`b1ba774be1d11bfb8c576d512bebe0ad`；
- 错误点：`active_students` CTE 中存在 `coalesce(s.status,'active')='active'`，导致真实 paused 学生 10 个历史周的 RPC 行数全为 0。

## 3. 精确修改

函数体只有以下语义差异：

1. `active_students` CTE 重命名为 `school_students`；
2. 保留 `s.app_type='school'`；
3. 删除且仅删除 `coalesce(s.status,'active')='active'`；
4. 最终查询改为读取重命名后的 CTE；
5. 函数 comment 明确 student status 不过滤历史业务事实。

其余 weekly source、linked actual、completed/cancelled、overdue/upcoming、credit、business entity、排序、签名、12 列类型与顺序、owner、security、volatility、parallel、leakproof、search path、ACL 均未改变。没有修改页面、API wrapper、学生状态事件、legacy status、任何 writer、Gate 或权限边界。

部署后 definition MD5 为 `e7eac5f3bb07c31ad15e750e8721c01f`，与事务 rehearsal 内定义完全一致。

## 4. SQL、静态与 rollback 证据

静态检查：

- `git diff --check`：通过；
- `node scripts/student-status-phase-b1-weekly-reader-static-test.mjs`：`STUDENT_STATUS_PHASE_B1_WEEKLY_READER_STATIC_TEST_PASS`；
- `node --check js/weekly-lesson-dashboard-app.js`：通过；
- `node --check js/pages/weekly-lesson-dashboard-page.js`：通过；
- page-layer 全量扫描：直接 `.rpc()` 为 0，直接 insert/update/delete/upsert 为 0；
- 浏览器代码 service-role marker 为 0；
- source 与独立 deploy 文件中的目标函数定义规范化后逐字相同；deploy 文件不含 ACL、业务 DML 或非目标对象。

Rollback rehearsal：

- 文件：`sql/tests/student_status_phase_b1_weekly_reader_rollback_test_20260805.sql`；
- 固定 `b101/b102/b103/b104` UUID 与 `codex-test phase-b1 rollback` marker；
- 覆盖 active、paused、left、无事件 legacy、跨月周、completed、cancelled、makeup、状态事件前后同一历史事实不变、business entity、无重复、空周、registration 分类；
- 前三次因测试夹具字段名、planned duration 约束和未来 actual guard 依次被数据库安全拒绝，每次事务均自动回滚；修正测试数据后最终完整通过；
- rehearsal definition MD5：`e7eac5f3bb07c31ad15e750e8721c01f`；
- 结尾显式 `ROLLBACK`；
- 回滚后生产函数 MD5 恢复 `b1ba774be1d11bfb8c576d512bebe0ad`；
- student/lesson/event fixture residue 均为 0。

生产执行：

1. 代码检查点 `bfec0dfccff3eacbda2f0af7184bd6e688c61a21` 先提交并推送；
2. 执行 `sql/current/school_student_status_phase_b1_weekly_reader_deploy_20260805.sql`，输出仅 `CREATE FUNCTION / COMMENT`；
3. 执行 `sql/current/school_student_status_phase_b1_weekly_reader_postdeploy_20260805.sql`，返回 `STUDENT_STATUS_PHASE_B1_WEEKLY_READER_POSTDEPLOY_PASS`；
4. ABI、owner、SECURITY、search path、ACL、comment、Gate 与 residue 全部通过；
5. 代码检查点 Pages run `31015287798`，`success`，head `bfec0dfc…`。

本轮没有调用任何写 RPC。Rollback 测试只在回滚事务内调用测试所需 reader/既有函数；生产验收只读调用 `school_get_weekly_lesson_operations(date)`、月份状态 resolver 及只读查询。

## 5. 真实 paused 学生 10 周矩阵

目标学生：厦门吕同学，`cff85c52-6acc-4b0f-8c92-3db280a5dd77`；business entity 始终为 `2cf7b72f-6e3c-4d09-80f7-7c58593cd466`。

所有周修改前 RPC row count 均为 0；修改后均严格为 1 行，且统一聚合为 `planned 2节/4小时、registered 2节、completed 4小时、cancelled 0、overdue 0、upcoming 0、open credit 0/0小时`。

| 周一 | 直接课时数 | planned 数 | 修改后 RPC 行 | 遗漏 | 重复 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2026-04-27 | 4 | 2 | 1 | 0 | 0 |
| 2026-05-04 | 4 | 2 | 1 | 0 | 0 |
| 2026-05-11 | 4 | 2 | 1 | 0 | 0 |
| 2026-05-18 | 4 | 2 | 1 | 0 | 0 |
| 2026-05-25 | 4 | 2 | 1 | 0 | 0 |
| 2026-06-01 | 5 | 2 | 1 | 0 | 0 |
| 2026-06-08 | 5 | 2 | 1 | 0 | 0 |
| 2026-06-15 | 5 | 2 | 1 | 0 | 0 |
| 2026-06-22 | 2 | 2 | 1 | 0 | 0 |
| 2026-06-29 | 3 | 2 | 1 | 0 | 0 |

直接课时 ID 集合：

- `2026-04-27`：`030b2e64-e396-46cf-b233-5172ab8d7440`、`1554ca25-505c-43f4-8bc3-baf2639c571f`、`a8801d0e-bf4c-48a0-b9ed-e52d2dc51000`、`f65563ec-9bb3-46c2-905b-4552ab8d025f`；planned 为 `1554ca25-… / a8801d0e-…`。
- `2026-05-04`：`01997034-0ea8-432f-a0f5-33cf76446a7d`、`8148df49-f83d-4f6e-ab0b-c1a325f978f1`、`aae0f059-3703-4dca-8cf5-64eae68f3a2a`、`d36c5a5c-e333-4db3-a3f0-25e629a6cbdd`；planned 为 `01997034-… / d36c5a5c-…`。
- `2026-05-11`：`0c560840-c46b-44d4-aabb-e3293af89cd4`、`60c011b3-315d-4c05-9a79-aae8b34569bd`、`a452787b-5cd8-4ccd-ac35-d5960db786a5`、`d204b5aa-702e-437c-ae14-ecc7bc32f712`；planned 为 `60c011b3-… / a452787b-…`。
- `2026-05-18`：`765d4581-a58a-4955-b665-4afb2c05c3ae`、`8deb0b45-091a-46ae-8c2d-8cdea0da116e`、`923e3dca-dc19-42a4-aa0c-2c27b16ce83c`、`c199e93f-ff21-4dca-bf2a-2353bf3ea335`；planned 为 `8deb0b45-… / 923e3dca-…`。
- `2026-05-25`：`0b890d9c-f1d5-4ce1-b394-0bd77d5ee92a`、`1dd10499-8f14-4557-829b-eaf7371191a4`、`2ac7b22a-2058-476c-9adf-4c189c7c5585`、`d1ca3e0a-8edb-4121-9e45-2de503501ba9`；planned 为 `2ac7b22a-… / d1ca3e0a-…`。
- `2026-06-01`：`13b08cc6-720b-4002-9207-1f5b8bd64ae5`、`26f63029-bbaf-45d3-9faf-4a1807b0116f`、`4cd402d2-520c-4f65-b1eb-cc72a5c07dad`、`550553ae-be7c-4577-9f04-43b1feaae48d`、`cc274b39-83c5-4681-af55-229c7d6c2f45`；planned 为 `13b08cc6-… / 550553ae-…`。
- `2026-06-08`：`3be702b3-abf6-4282-ac2a-753b56afcda2`、`5c4b3739-7da2-4b89-94ac-a061ca3966ad`、`727304b4-19d4-478d-ac5f-700262e09e1d`、`9cea7b9b-7f7a-4c18-be2e-74c8ee68ef6c`、`a4a9690e-0b80-47d2-a6bd-d766bf0bb705`；planned 为 `727304b4-… / 9cea7b9b-…`。
- `2026-06-15`：`02c5eb3b-5510-4a20-881f-f299f3612329`、`44cd5bd0-8c49-448e-9c7c-75fb206bced3`、`616b14ab-9680-424e-8d53-1b3f2fc969f3`、`88995922-a375-427d-a56f-6cd838312c96`、`bfc41de1-f186-4676-9955-e93fc100c6bc`；planned 为 `88995922-… / bfc41de1-…`。
- `2026-06-22`：`bf10cbe0-8fd5-4d0a-b2e4-64a2bb65de8e`、`f8c94de2-92be-4b93-baba-3f70d89e00c4`；两条均为 planned。
- `2026-06-29`：`7de38e7a-233a-47e2-b2b8-726ed5a0d37d`、`8247acd1-474f-4bce-afdc-a912e4ac557d`、`f495da4a-71c0-49a3-81ed-5834b3b983bb`；planned 为 `7de38e7a-… / f495da4a-…`。

跨月周 `2026-06-29..2026-07-05` 保持 3 条直接课时、2 条 planned，RPC 为唯一一行 `2/4/2/4`。2026-07 生效的 paused 事件没有删除 6 月历史事实，也没有生成任何不存在的 7 月课时；`2026-07-27` 和 `2026-08-03` 该学生继续各有唯一零值行。

## 6. 其他学生逐字段回归

采用 `md5(string_agg(to_jsonb(row)::text,'|' order by student_id))` 对除目标学生外的完整 12 列 RPC 行逐周比较。每周均为 7 行，修改前后哈希完全相同：

| 周一 | pre = post MD5 |
| --- | --- |
| 2026-04-27 | `6268ac67f675cfef69326361d644de32` |
| 2026-05-04 | `f519a5d4437272f24100cb67ff392272` |
| 2026-05-11 | `615032965b7000d203f9d80832beb300` |
| 2026-05-18 | `7eca386887355c7eda5d6e02905f4949` |
| 2026-05-25 | `7983d7eff583d2c2f537f0c61ceb496f` |
| 2026-06-01 | `5d305b4cc9f86394cc0000e54671a4f3` |
| 2026-06-08 | `85d7f05526755c2da85dd1cda7c0e9f2` |
| 2026-06-15 | `ba44477a51590063e72bb65f8b7f22f1` |
| 2026-06-22 | `1e83612a6856058212f02e3996ad680c` |
| 2026-06-29 | `fcf8767c107d262ae773c80bff97c1d4` |
| 2026-07-27 | `758af7ff8ece8defc07a8f8e52569ff3` |
| 2026-08-03 | `c4ec1df465ab0fe05e4ae745e903fb90` |

12 周合计 84 行完整结果总哈希修改前后均为 `ecf295190531418d46c1cd10b245a1b7`。因此 active 学生当前周结果、business entity、各聚合字段均无漂移。

## 7. 真实业务数据、Cash、Storage 与 Gate

School 修改前后数量/全行 MD5：

| 对象 | 数量 | MD5 |
| --- | ---: | --- |
| students | 8 | `431ae7f350902dde0642ddc4982054ed` |
| lessons | 736 | `7755ad0edf8eea674003a59b60c1d66c` |
| settlements | 18 | `7986db5dd35c0ecfa180a04aef7f4051` |
| student income | 30 | `0380f2e4ab967d37ad898a4e534195a4` |
| tuition bills | 22 | `d079f068c0fa19fc07d4dcd94094fae2` |
| wage details | 556 | `0b2976f8005835d66b2db25b0b3c1939` |
| wage rules | 20 | `2dc430ca4a58416235f2ba771b91b9f1` |
| all income | 55 | `bd2d538d1de901621ff0e6757984a41e` |
| expenses | 47 | `141c76e4cf6148007e182704941a0c4a` |
| accounts | 3 | `443b3170f50bc23a56834d398069c565` |
| account transactions | 187 | `21694ff060e23289566f0a6e9fe3e449` |
| status events | 1 | `eeeb492ac7577ff85eb0926aa0b57301` |

Cash 修改前后：42 external requests / `dfb00aaa210894f78c47285e21d2f222`；73 CNY transactions / `937cbd8d10480c5c5dabaab658eb2558`；31 JPY transactions / `3f3f257b14b43c12925a8eecb7a8ca02`。

Storage 修改前后：57 objects、30 个既有 orphan；按 object id 排序的全行 MD5 均为 `c2852a4dbcd13b9cddb1da0b1115b18f`。未调用 Storage 写 API，未清理 orphan。

Gate 修改前后保持 `enabled / blocked / enabled`。真实学生、课时、状态事件、财务、Cash、Storage 业务行持久写入均为 0；唯一生产持久 DB 写入是目标函数定义与 comment。

## 8. Chrome 无写验收

使用现有 active-admin Chrome 登录态：

- 周看板正常加载，版本 `v10.5.6`；
- 周一日期输入与“查询本周”按钮各唯一 1 个，切换到 `2026-06-29` 成功；
- 表格 8 行；“厦门吕同学”显示 `2节/4小时、已登记2节、完成4小时、待登记0、取消0、待补0/0小时`；
- 课时链接为 `lesson.html?year=2026&month=06&week_start=2026-06-29&student_id=cff85c52-6acc-4b0f-8c92-3db280a5dd77`，课时管理页正常加载并保留学生筛选；
- 学生月度结算、收入记录、老师工资结算页面均正常加载、登录态正常、错误横幅 0；
- 所有验收页面 Console error/warning 为 0；
- 未点击任何保存、生成、提交、锁定或业务写按钮；
- page-layer 直接 RPC/DML 为 0，浏览器 service-role marker 为 0。

Chrome 最终保留在 `weekly-lesson-dashboard.html?week_start=2026-06-29`。

## 9. 修改文件与保护文件

实现文件：

- `sql/current/school_weekly_lesson_operations_read_rpcs.sql`
- `sql/current/school_student_status_phase_b1_weekly_reader_deploy_20260805.sql`
- `sql/current/school_student_status_phase_b1_weekly_reader_postdeploy_20260805.sql`
- `sql/tests/student_status_phase_b1_weekly_reader_rollback_test_20260805.sql`
- `scripts/student-status-phase-b1-weekly-reader-static-test.mjs`
- 本报告与 `docs/current-status.md`

六份受保护 untracked 文件没有读取后写回、修改、暂存或提交，最终 SHA-256：

- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`：`272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`：`b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`：`5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`：`b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`：`7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

## 10. 最终判断

没有发现聚合倍增、遗漏、business entity 越界、ABI/ACL 漂移、新权限旁路或真实业务数据异常变化。Phase B1 的 reader No-Go 已解除。

**Phase B1 已完成，可以进入 B2 的独立授权；本轮未自动开始 B2。**
