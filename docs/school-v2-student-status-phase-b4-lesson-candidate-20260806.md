# School V2 学生月份状态 Phase B4-Lesson：课时管理学生候选报告

日期：2026-08-06（Asia/Tokyo）

## 1. 结论

Phase B4-Lesson 已完成调查、实现、静态与 DB 回滚测试、生产只读 helper 部署、提交推送、Pages 发布和生产 Chrome 无写验收。

- `school_student_status_events` 继续是月份状态唯一权威；`school_students.status` 没有重新进入任何候选资格判断。
- 状态 resolver 只决定“可以主动选择谁”，没有裁剪任何既有 planned、actual、cancelled、partial、makeup 或详情事实。
- 顶部、单条 planned、批量 planned、导入预览、planned 编辑和 PDF 均按各自正确的 DB 权威月份取候选；actual/取消/partial/makeup 继续保留既有记录学生。
- 页面与工资页共用 `js/api/student-status-api.js`，没有复制两套月份状态解析规则。
- 正式持久 DB 写入仅为三个只读 helper、ACL/comment，以及批量 writer 内部改为调用同一 occurrence helper；课时、学生、事件、财务、Cash、Storage 和 Gate 业务数据写入均为 0。
- 本轮没有启动其他 Phase B4、Phase B5 或业务归属个人明细删除调查。

## 2. 起点、扩展声明与发布边界

| 项目 | 结果 |
|---|---|
| 初始分支 / HEAD / `origin/main` | `main` / `8b48b0c1d56befab0f4648f689eccf93f49ce4df` / 同值 |
| 初始 ahead / behind | `0 / 0` |
| 初始 Pages | run `31034429974`，success |
| 初始页面版本 | `v10.5.10` |
| 实现提交 | `df958a36081f3894d5770bd7a0d20fc9376c340e` |
| 实现 Pages | run `31069659038`，success，head 精确为 `df958a3…` |
| 最终页面版本 | `v10.5.11` |
| Gate 前后 | preview=`enabled` / generate=`blocked` / cash_submit=`enabled`，未变化 |

Business-model expansion declaration 在修改业务代码或 SQL 前完成：新表、列、enum/status、月份/归属概念、identity、snapshot、version、writable fact、mutability、locking、新权威、dual read/write、历史重解释和 destructive schema 均为 `none`。唯一 reader authority 变化是本任务明确批准的课时学生候选改读既有 Phase A 月份 resolver。三个 helper 只执行既有模型；批量 writer 的 ABI、金额、锁、状态、原子写入和 B3 逐 occurrence 资格校验均未改变。

## 3. 修改前入口矩阵与修改后权威

| 入口 | 修改前来源 | 修改后权威月份 / 行为 |
|---|---|---|
| 顶部学生筛选 | 全部 School 学生；legacy 当前状态曾参与候选 | 页面所选学生结算业务月首日；月/周/pair 都不以周一月份替代页面月份 |
| 月、周、pair 与 URL | 页面筛选值，非在读 selected override 不完整 | `year/month/view/student_id/include_inactive=1` 稳定同步；切月重解析；“全部学生”清除 `student_id` |
| 全部课时 reader | 记录 reader | 继续读取所选范围全部真实记录；状态候选绝不参与记录裁剪 |
| 单条新增 planned | 全学生候选，页面可自行依赖日期 | DB `school_resolve_planned_billing_attribution` 计算 billing month，再取该月 active 候选 |
| 批量新增 planned | 页面独立展开 occurrence，学生候选非完整月份交集 | DB 与正式 writer 共用 occurrence helper；所有目标 billing month active 候选交集 |
| 导入预览 | 名称匹配全部学生；最终由 B3 writer 校验 | 每一行按日期调用 DB planned 候选 reader并回报行、学生、日期、权威月份；格式和金额合同不变 |
| planned 编辑 | 全部学生 | 原学生始终保留并标状态；同学生同权威月可修正；换学生或权威月变化只允许新月份 active |
| actual 编辑 | 既有记录学生 | 学生冻结为记录 `student_id`，不套用新建资格 |
| actual / 取消 / partial / makeup | 既有 planned 关系 | 保留既有学生和 B3 writer 合同；不因后来 paused/left 拒绝 |
| 跨月补课来源 | pending_makeup 事实 reader | 保持来源 planned 的学生结算月、actual 日期的工资月、唯一 source/claim 和不重复收费 |
| PDF 学生选择 | 全部学生 | 导出业务月候选；默认 active，支持 include inactive 与 selected override；记录来源不裁剪 |
| record-ID 详情 | 先取全学生列表再匹配 | 只按课时记录的 `student_id` 做最小 `.eq("id", ...)` lookup，不经过 active 候选 |
| B4-Wage | wage 专用月份候选实现 | 改为调用共享 `fetchStudentMonthCandidates`，工资生成/支付合同不变 |

`fetchLessonStudents()` 现只用于历史事实、名称匹配和既有关系的最小全学生 lookup，不再携带 legacy `status`。

## 4. DB helper、API 与权限

| 函数 | 定义 MD5 | ACL / 合同 |
|---|---|---|
| `school_expand_planned_lesson_batch_occurrences_v1(date,date,jsonb,jsonb)` | `865a7a3f1d4d83e754d079b64c7ace93` | owner `postgres`，SECURITY DEFINER，固定 `pg_catalog, public`，仅 `postgres` EXECUTE |
| `school_list_planned_lesson_student_candidates_v1(date,uuid,uuid)` | `812218b29ff4a9bf322145158a275f65` | `postgres, authenticated` EXECUTE；anon/service_role 无权限 |
| `school_preflight_planned_lesson_batch_student_candidates_v1(date,date,jsonb,jsonb,uuid,uuid)` | `ecc995b023ef1ee0ebaa24adf150df60` | `postgres, authenticated` EXECUTE；anon/service_role 无权限 |

正式批量 core `school_generate_planned_lessons_batch_r1d_f1_legacy_core(...)` 只把原内联 occurrence 展开替换为共享 helper，终态定义 MD5 为 `8f8343a3adef2278e0392f003cfb62fe`；所有 B3 resolver、writer ABI、事务原子性和落库计算保持不变。B1 weekly reader MD5 仍为 `e7eac5f3bb07c31ad15e750e8721c01f`，最新取消 writer MD5 仍为 `e1d7414424dada7e1a77c0130c67d159`。

前端共享 API 为 `fetchStudentMonthCandidates()`；课时 API 新增 `fetchPlannedLessonStudentCandidates()` 和 `preflightPlannedLessonBatchStudentCandidates()`。页面模块直接 `.rpc()` / insert / update / delete / upsert 为 0，浏览器 service-role 为 0。

## 5. 逐入口结果

### 顶部、URL 与历史事实

- 2026-06 默认 8 名；2026-07/08 默认各 7 名；包含非在读后均为 8 名。
- 唯一事件学生在 6 月显示普通 active 名称，在 7/8 月显示“厦门吕同学｜本月暂停”。
- 8 月 URL 带暂停学生时，即使关闭 include inactive，selected override 仍保留；异步刷新完成后 URL 正确移除 `include_inactive=1` 并保留 `student_id`。
- 切到 6 月后同一 selected 重新解析为 active；重置恢复 2026-08、全部学生、默认不包含非在读，URL 清除学生参数。
- 周筛选选项继续按页面学生结算月约束；候选权威不改用自然周跨月日期。
- “全部学生”前后课时总量、状态、配对、费用、排序和记录哈希不变；选择学生仅按课时记录 `student_id` 过滤。

### 单条、批量与导入

- 单条 planned 默认日期 `2026-08-01` 经 DB 归属到 2026-07，候选为 placeholder + 7 active，不含暂停学生；改为 `2026-07-01` 后 DB 归属到 2026-06，候选变为 placeholder + 8，包含该学生且不带暂停标签。
- 日期/业务归属变化会重新读取候选；无效选择被清除并提示；页面候选不是最终保护，B3 writer 仍会在提交事务内重验。
- 批量 `2026-06-29` 至 `2026-07-06`、周一 occurrence 的只读 preflight 返回两个目标 occurrence 月的 active 交集：placeholder + 7，暂停学生不可选；学生选择在 preflight 前禁用，提交继续禁用。本轮没有点击生成。
- 批量页面不再自行展开 occurrence；排除日期、范围、星期或规则变化会使 preflight 失效并重新计算。若 pending selected 不合格，错误包含日期、月份和状态。
- 导入功能仍保持原有禁用/预览边界；每行 planned 候选按该行日期走 DB reader，错误能定位行、学生、日期和权威月份；没有改变文件格式、金额或“不允许部分成功”合同，也没有提交导入。

### 编辑、actual、取消、partial、makeup 与详情

- planned 编辑组件始终加入原学生并显示目标权威月状态；同学生同权威月可继续历史资料修正；换学生或日期导致权威月变化时重新加载 active 候选并清除不合格原选择。生产数据没有可安全打开且可编辑的 paused planned 样本，因此该组合由 rollback/static 矩阵验证，没有制造生产 fixture。
- 生产 Chrome 打开 paused 学生 2026-06 actual 编辑：学生 select 为 disabled，值和姓名均为记录原学生。
- actual、取消、partial、单条 makeup、跨月 makeup 不接入新建 planned 候选；最新取消 writer 的权限、15 分钟网格、费用/工资 0、`pending_makeup`、账单/工资/月结/claim 和并发保护 postdeploy 全部通过。
- 详情只按记录 `student_id` lookup；paused/left 历史姓名和关联课时不会因候选资格丢失。

### PDF 与工资回归

- 8 月 PDF 默认 placeholder + 7 active；打开 include inactive 后 placeholder + 8，暂停标签正确。没有执行导出下载或 Storage 上传。
- PDF 记录 reader 仍按明确学生和导出月读取真实课时；全部学生的内容、金额、配对和排序未变化。
- 工资页生产回归为 `v10.5.11`：8 月默认 7 名，包含非在读后 8 名并显示暂停标签；URL 正确加入 `include_inactive=1`，Console 0 error/warning，工资生成与支付未触发。

## 6. 测试与生产 Chrome

静态与语法全部通过：

- 全部修改 JS `node --check`。
- `STUDENT_STATUS_PHASE_B4_LESSON_CANDIDATE_STATIC_TEST_PASS`。
- `STUDENT_STATUS_PHASE_B4_WAGE_STUDENT_FILTER_STATIC_TEST_PASS`。
- B1、B2、B3、最新 cancellation、tuition P0F、权威月份刷新、batch 刷新、billing-week invariant、generation/operations closure、lesson P0B1、settlement filter 防回退测试。
- `git diff --check`；page-layer RPC/DML 扫描为 0；课时 legacy status 资格读取为 0。

SQL 验证：

- `sql/tests/student_status_phase_b4_lesson_candidate_rehearsal_20260806.sql`：完整通过并 `ROLLBACK`。
- `sql/tests/student_status_phase_b4_lesson_candidate_rollback_test_20260806.sql`：`BEGIN READ ONLY ... ROLLBACK` 通过。
- B1/B2/B3/Phase B4-Lesson/最新取消 writer postdeploy 全部 PASS。
- rehearsal/rollback fixture residue 为 0；没有白名单 commit test，也没有 test record ID。

生产 Chrome 无写验收：顶部候选、include inactive、selected override、切月、重置、单条 billing 边界、批量跨月交集、PDF、paused actual 冻结、工资共享回归均通过。390×844 下页面横向溢出为 0，学生 select 宽 346px，include 开关可见；恢复默认视口。Console error/warning 为 0。没有点击任何保存、生成、导入、actual、取消、partial、makeup 或支付提交。

## 7. 前后业务指纹

| 对象 | 修改前 | 修改后 |
|---|---|---|
| students | 8 / `b7560ef8e43dd1d5b3bcd3766757d737` | 相同 |
| lessons | 738 / `55432494be781edd82bcd3e2defbd710` | 相同 |
| lesson fee sum | JPY 15,142,770 | 相同 |
| lesson total fee sum | JPY 1,408,800 | 相同 |
| linked actual / paired planned | 258 / 255 | 相同 |
| active / voided planned | 471 / 9 | 相同 |
| Storage objects / orphan / MD5 | 57 / 30 / `c2852a4dbcd13b9cddb1da0b1115b18f` | 相同 |
| Cash requests / CNY / JPY | 42 / 73 / 31 | 相同 |
| Cash MD5 | `dfb00aaa210894f78c47285e21d2f222` / `937cbd8d10480c5c5dabaab658eb2558` / `3f3f257b14b43c12925a8eecb7a8ca02` | 相同 |

课时状态明细前后均为：actual cancelled `2 / JPY52,000`、completed `236 / JPY4,892,895`、makeup_completed `20 / JPY181,000`；planned completed `63 / JPY1,503,000`、makeup_completed `2 / JPY52,000`、pending_makeup `33 / JPY908,500`、planned `382 / JPY7,553,375 / total fee JPY1,408,800`。

唯一真实事件保持：event `4190bddf-d995-4e6a-af6b-85997e6f999b`、student `cff85c52-6acc-4b0f-8c92-3db280a5dd77`、effective month `2026-07-01`、status `paused`；6 月解析 active/fallback，7/8 月解析 paused/event。事件 writer 继续 owner-only。

## 8. SQL、RPC 与数据库写入

执行的目标 SQL：

- `sql/current/school_student_status_phase_b4_lesson_candidate_deploy_20260806.sql`：生产 COMMIT，写入只读函数定义、ACL/comment，并更新批量 core 内部 occurrence 调用。
- `sql/current/school_student_status_phase_b4_lesson_candidate_postdeploy_20260806.sql`：只读验证。
- `sql/tests/student_status_phase_b4_lesson_candidate_rehearsal_20260806.sql`：ROLLBACK。
- `sql/tests/student_status_phase_b4_lesson_candidate_rollback_test_20260806.sql`：READ ONLY / ROLLBACK。
- B1、B2、B3 与 cancellation postdeploy，以及 School/Cash/Storage/Gate 最终只读指纹脚本。

测试和浏览器仅调用月份候选、planned 候选、batch preflight、billing attribution、月份 resolver 等 reader RPC；没有调用任何业务 write RPC。DB 持久写入仅为已提交版本对应的函数定义、ACL/comment；School 业务行写入 0、白名单业务写入 0、真实业务写入 0、Cash 写入 0、Storage 写入 0。

## 9. 修改文件

实现提交共 23 个文件：

```text
css/app.css
js/api/lesson-api.js
js/api/lesson-detail-api.js
js/api/student-status-api.js
js/api/wage-api.js
js/components/lesson-edit-dialog.js
js/config.js
js/lesson-app.js
js/pages/lesson-page.js
js/pages/wage-page.js
js/wage-app.js
lesson.html
scripts/lesson-cancellation-hardening-ui-test.mjs
scripts/student-status-phase-b4-lesson-candidate-static-test.mjs
scripts/student-status-phase-b4-wage-student-filter-static-test.mjs
scripts/tuition-p0f-lesson-read-failure-static-test.mjs
sql/current/school_student_status_phase_b3_writer_authority_postdeploy_20260806.sql
sql/current/school_student_status_phase_b4_lesson_candidate_core_20260806.sql
sql/current/school_student_status_phase_b4_lesson_candidate_deploy_20260806.sql
sql/current/school_student_status_phase_b4_lesson_candidate_postdeploy_20260806.sql
sql/tests/student_status_phase_b4_lesson_candidate_rehearsal_20260806.sql
sql/tests/student_status_phase_b4_lesson_candidate_rollback_test_20260806.sql
wage.html
```

收尾文档为本报告与 `docs/current-status.md`。

## 10. 受保护文件与交付状态

六份 untracked 文件始终未修改、移动、删除、暂存或提交；初始与最终 SHA-256 相同：

```text
272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432  docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv
5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093  docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt
b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54  sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql
5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a  sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql
b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773  sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql
7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b  sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql
```

Phase B4-Lesson 已完成；其余 Phase B4、Phase B5、状态事件 writer 权限恢复及业务归属个人明细删除调查均未启动。等待业务负责人验收。
