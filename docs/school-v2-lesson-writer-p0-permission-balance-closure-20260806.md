# School V2 补课与课时 Writer P0 权限及余额约束封口报告

日期：2026-08-06

结论：P0 writer 权限、补课余额、DB 时间权威、通用更新旁路与 legacy ABI 已完成生产封口；生产真实业务数据零修改，synthetic fixture residue 为 0。页面文件未修改，版本保持 `v10.5.12`。

## 1. 恢复、实时基线与 BE-UI 接纳

恢复时重新完整读取 `AGENTS.md`、执行 `git fetch origin`，实时分支为 `main`，`HEAD` 与 `origin/main` 均为 `013304be2d6b1a28229d65a66d119dc34d08c380`，ahead/behind `0/0`。合法 BE-UI 实现 `8581c25ca6c5b3f63a8246b9021891d90ec0fd8c` 与文档 `013304be2d6b1a28229d65a66d119dc34d08c380` 被作为新基线完整接纳，没有 reset、回退或覆盖。

本任务以实时 HEAD 重新审查页面/API 合同：用户页面继续没有业务归属筛选、选择器、列、详情、旧 URL 或管理入口；新业务继续通过 fail-closed Aozora resolver 获取内部 ID，历史编辑继续保留原 `business_entity_id`；工资继续按 `teacher + business_entity + month` 分区。`js/api/lesson-api.js` 的 canonical lesson RPC ABI 与本任务目标一致，page module 无直接 `.rpc()` 或表 DML，`js/legacy-core.js` 不存在。本任务没有修改任何 HTML、CSS、页面/API JS，也没有恢复旧业务归属 UI。

开始 Pages run 为 `31088247599`，HEAD `013304be…`，success；页面 `v10.5.12`。Gate 为 `enabled / blocked / enabled`，Auth 为 `disable_signup=true`、`mailer_autoconfirm=false`。

## 2. 三份草案与六份保护文件

BE-UI 留存的三份本任务草案先按实时生产定义、BE-UI 新 API 合同、原任务授权和硬停条件重新审查，未直接执行原 deploy：

| 文件 | 恢复大小 / SHA-256 | 最终部署前大小 / SHA-256 | 处理 |
|---|---|---|---|
| `school_lesson_writer_p0_permission_balance_closure_core_20260806.sql` | 30866 / `3282804943061e3e3436a056ecf6c3a9e19eafdcb0d43b48fb7a22b050e3b6c8` | 31815 / `e89a36cf43773d19780181410014d39bd4666b87638f27abd54956e980244eea` | 补齐 `voided_at` proposed-state、非法/non-pending来源拒绝、真实换行注入、P0-C旧update owner-only、fee/billable余额重检 |
| `school_lesson_writer_p0_permission_balance_closure_deploy_20260806.sql` | 247 / `b6cf7f6bf98d025b133673571f31d8262b38dac46f12f8274bbf77350b2e341f` | 246 / `c0baeaa8e2f05bed7cd73f91c59153484c08c90271e76725303f440a3c11f7d1` | 业务内容未变；移除EOF空行，且仅在全部 rehearsal、rollback、exact rollback、postdeploy组合验证通过后执行 |
| `school_lesson_writer_p0_permission_balance_closure_postdeploy_20260806.sql` | 7973 / `63615240b37518b0618bd5e7bd9005cad20649c606ae7fb3610eed0b291c6e1c` | 9727 / `e7476721de0fb1f709405bf178e5757f1cfc4832c36bd1b4ccb236935bc5bf80` | 补齐 canonical 全签名、P0-C旧update、触发器状态/来源/voided校验 |

原六份受保护 untracked 文件从开始到结束均未修改、移动、删除、执行、暂存或提交：

| 路径 | 大小 | SHA-256 |
|---|---:|---|
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | 61681 | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | 4483 | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | 15861 | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | 10345 | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | 15089 | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | 27370 | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 3. Business-model expansion declaration

- 新业务表、列、状态、日期/月、归属、身份、snapshot、version、可写事实：`none`。
- destructive schema、历史解释、fallback、dual-write、backfill：`none`。
- 已批准的既有语义收紧：课时 writer active admin/operator 权限；actual 时间/分钟/时长 DB authority；补课 raw remaining、稳定锁顺序与 proposed-state 约束；legacy ABI owner-only。批准来源为原任务第 VI–XII、XV、XVI、XXI 节。
- 新对象仅为执行批准合同的技术 helper/trigger；不新增业务事实或 reader。

## 4. Writer 清单与最终分类

### 4.1 canonical authenticated writer

以下十个生产函数均为 `owner=postgres`、`SECURITY DEFINER`、`search_path=pg_catalog, public`，ACL 仅 `{postgres=X/postgres,authenticated=X/postgres}`。每个函数在任何业务读取/写入前调用统一 `school_assert_active_lesson_writer()`：

| 签名简写 | 最终 MD5 |
|---|---|
| `school_create_planned_lesson_record_with_venue(...17 args)` | `aa125b26f2dcb343d4234a2dd61a448a` |
| `school_generate_planned_lessons_batch_with_venue(...8 args)` | `e76bdfe1bb8b914b4ec1777bb38aa60e` |
| `school_update_lesson_record_guarded_with_venue(...19 args)` | `f02b4bd86d0e9c4e65cc94264785e53f` |
| `school_update_lesson_record_guarded_with_venue(...20 args)` | `ebc17dcd785e724509fa43147ff8a718` |
| `school_create_actual_lesson_from_planned(...10 args)` | `316c3b49bc1ab3950e9e61468c66d845` |
| `school_create_cancelled_actual_lesson_from_planned(...9 args)` | `73ac1abeebb6ce82870f9e0f8240629b` |
| `school_create_lesson_credit_makeup_actual(...12 args)` | `e6de3be6719e88c7da9b451e40f3b7c7` |
| `school_create_partial_completed_actual_from_planned(...7 args)` | `1475b36ade440630f7d1064cc24ff367` |
| `school_void_planned_lesson(...3 args)` | `4989ed14d7507ef346b9c1791cbc3a6b` |
| `school_delete_fresh_planned_lesson(...3 args)` | `5e5f720bbc2bfcea67d0ff98699a79fb` |

### 4.2 owner-only internal、兼容、legacy 与运维入口

下列函数均保留定义以保证依赖安全，但 PUBLIC、anon、authenticated、service_role 均无 EXECUTE：

- planned：两个 base overload、旧 venue overload、`school_create_planned_lesson_record_r1d_f1_legacy_core`。
- batch：base 与 `r1d_f1_legacy_core`。
- update：两个 base overload、`school_p0c_baseline_update_lesson_record_guarded`。
- makeup legacy wrapper：`school_create_makeup_completed_actual_lesson_from_planned`、`school_create_cross_month_makeup_completed_actual_from_planned`，comment 标记 deprecated。
- import：base、with-venue、legacy core。
- exact correction / tuition / claim legacy：`school_replace_unconsumed_makeup_actual_v1`、`school_void_planned_lesson_after_tuition_void`、`school_void_planned_lesson_p0f_legacy`。
- 运维：`school_backfill_actual_minutes_from_duration`。
- 本阶段 helper/trigger：`school_assert_active_lesson_writer`、`school_get_lesson_credit_raw_remaining_hours`、`school_lesson_writer_p0_validate_row`。

`school_create_part_time_work_planned_lesson` 写入独立的兼职课时表，不是 `school_lesson_records` writer，维持原合同，未纳入本阶段修改。

## 5. 权限、余额、时间与更新规则

统一断言以 `auth.uid()` + `school_app_memberships` 为唯一业务身份权威，稳定区分 `LESSON_WRITER_AUTH_REQUIRED`、`MEMBERSHIP_REQUIRED`、`ACTIVE_MEMBERSHIP_REQUIRED`、`ROLE_REQUIRED`。active admin/operator 允许；read_only、inactive、无membership拒绝。PostgREST 的 anon/service_role/PUBLIC 在 ACL 层拒绝；仅无 request JWT 的直接 postgres 运维会话具有 owner 例外。

canonical makeup writer先取得现有 P0 scope lock，再 `FOR UPDATE` 锁来源 planned；只接受未 void 的 `pending_makeup`。raw remaining 为 `planned.duration_hours - SUM(completed/makeup_completed non-void actual.duration_hours)`，不截断负数；cancelled 不消费。稳定错误分别为 `LESSON_MAKEUP_CREDIT_DATA_INCONSISTENT`、`...EXHAUSTED`、`...EXCEEDED`。

表级 BEFORE trigger 对 INSERT 或相关 UPDATE 执行：旧/新来源 UUID 排序锁定；排除当前 actual 后计算其他消费 + proposed 消费；覆盖 lesson type、status、source、duration、actual minutes、billable、fee、voided 状态。来源时长缩小、actual 放大、cancelled 转消费状态、换来源、unvoid 或普通 actual 改为 makeup 的旁路不能制造负余额。content/note-only 更新不会触发余额重检，历史 raw-negative 行不会因无关编辑被全局阻断。

DB 验证日期、HH:MM、15 分钟网格与 `end > start`，以起止差计算 authoritative minutes/hours；传入 duration 仅做一致性校验。completed/makeup_completed 的 `actual_minutes` 等于 DB 分钟；cancelled 固定 minutes 0、nonbillable、fee 0；makeup 固定 nonbillable、fee 0；ordinary actual 原有 fee 与 overage calculator 保持不变。

`school_lesson_records` 仍为 RLS enabled/not forced，表 ACL 仍仅对 anon/authenticated/service_role 开放 SELECT，唯一 policy 仍为 SELECT-only；没有直接 DML 权限变化。已有 claim、financial authority、attribution、aircon、completion-date 与 updated-at trigger 定义 MD5 均未改变。

## 6. 验证证据

通过的本任务验证：

1. 静态边界、API ABI、BE-UI 无归属、page 无直接 RPC/DML、`node --check`、`git diff --check`。
2. catalog rollback rehearsal；完整 synthetic rollback matrix；部署+postdeploy 外层事务 rehearsal；exact rollback rehearsal。
3. 完整余额矩阵：2h全额、1h+1h拆分、cancelled不消费、超额、零余额、raw-negative、更新放大/status/source/source-shrink/unvoid/non-pending来源。
4. 时间/计费矩阵：15分钟成功与非网格/相等/倒序/mismatch拒绝，DB minutes/hours，makeup/cancelled零费，ordinary/partial/overage回归，legacy note-only更新。
5. postdeploy 角色矩阵：active admin/operator进入业务校验；read_only、inactive admin/operator、无membership、authless稳定拒绝；legacy wrapper/helper由 authenticated ACL 拒绝。
6. 页面 publishable key 的真实 PostgREST anon 请求返回 HTTP 401 / SQLSTATE 42501 `permission denied for function`；没有 service-role 进入浏览器。
7. 既有 cancellation rollback 回归继续通过 settlement locked、bill-consumed immutable、active claim 与 locked wage 阻断。

并发测试使用两个独立连接同时对固定 2h source 请求 1.5h：恰好一个成功，另一个稳定 `LESSON_MAKEUP_CREDIT_EXCEEDED`；成功 actual 为 1.5h / 90 分钟 / `makeup_completed` / nonbillable / fee 0，raw remaining 为 0.5h。

## 7. Synthetic fixture 与清理

- `be100000-*`：完整权限/余额/时间/更新矩阵，仅在事务内存在，ROLLBACK；课时事务内计数 23。
- `be110000-*`：postdeploy 6个 auth users、5个 memberships，仅在事务内存在，ROLLBACK。
- `be120000-*` 持久并发 fixture：actor `be120000-0000-4000-8000-000000000001`、subject `...d001`、teacher `...7001`、student `...a001`、planned `...1101`；最终记录的 winner actual 为 `d839696c-f78c-432c-82b9-c3add9267c47`。
- 并发测试后依次精确删除 winner actual、planned、student、teacher、subject、membership、auth user；每项 `DELETE 1`，commit 后全表 residue scan PASS。没有宽范围 DELETE。

真实学生、课时、工资、账单、月结、Cash、claim 均未用于成功写测试。李天伦、彭宇晗、陈红卓对象只进入只读指纹，不发生写入。

## 8. SQL 执行、部署与回滚

执行的 School SQL：

- `school_lesson_writer_p0_permission_balance_closure_baseline_readonly_20260806.sql`（部署前/后）
- `school_lesson_writer_p0_permission_balance_closure_rollback_rehearsal_20260806.sql`
- `school_lesson_writer_p0_permission_balance_closure_rollback_tests_20260806.sql`
- `school_lesson_writer_p0_permission_balance_closure_exact_rollback_test_20260806.sql`
- `school_lesson_writer_p0_permission_balance_closure_postdeploy_rollback_test_20260806.sql`
- `school_lesson_writer_p0_permission_balance_closure_deploy_20260806.sql`（唯一生产持久部署）
- `school_lesson_writer_p0_permission_balance_closure_postdeploy_20260806.sql`
- `school_lesson_writer_p0_permission_balance_closure_postdeploy_role_rollback_tests_20260806.sql`
- `school_cancelled_actual_writer_hardening_rollback_tests_20260806.sql`（既有回归）

Cash 仅执行 `cash_lesson_writer_p0_permission_balance_closure_baseline_readonly_20260806.sql` 的部署前/后 SELECT。生产持久 DB 定义变化仅为三个 owner-only技术函数、一个 BEFORE trigger、十个 canonical 函数定义、comments 与 ACL；无业务 schema/table/column 变化。

精确 rollback 已保存全部目标 canonical 原始 `pg_get_functiondef`、原始 makeup 定义、原 ACL/comments，并会删除本阶段 trigger/helper；外层部署→rollback rehearsal 验证原 MD5 与 ACL 逐字恢复后 ROLLBACK。未在生产执行正式 rollback。

## 9. 业务数据部署前后指纹

下列 School 指纹部署前后完全一致：

| 对象 | 数量 | MD5 |
|---|---:|---|
| lessons | 740 | `b32de0cf60c05baef21420618bd1635b` |
| settlements | 18 | `481ffa7ed5173da852f0f28ce66c2e9b` |
| tuition bills / bill lessons / revisions | 22 / 330 / 20 | `e50673ac…` / `e3e2e004…` / `ffdc498a…` |
| income | 55 | `ccfb156a42068df78e98f2ce6693aac6` |
| wage locks / details | 95 / 556 | `7bbe108d…` / `6204dc66…` |
| claims | 2 | `fbce39067e6d98167cdb474eb9635c92` |
| School Cash linkage | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| legacy fee anomalies | 10 | `9f9db28e1baa1a7ab37b6e067f6e2a7d` |
| raw-negative / zero-pending | 23 / 14 | `11b336c0…` / `46ac528a…` |

专项对象保持：李天伦4条 `ce7c8c297e92688fb044927d5a264559`；彭宇晗取消链1条 `5510fdb85832ce9f4a5ba4cba25882dc`；陈红卓跨月链3条 `d16b9ad0d55105effbbfd1d94bd251bc`。两条异常学费链和历史异常均未触碰。

Cash 部署前后完全一致：external requests 42 / `39bed891…`，CNY 36 / `38b0e164…`，JPY 3 / `654485db…`；上述课时 UUID 引用均为0。生产真实业务 DML 为0；唯一短暂持久业务行是明确白名单 `be120000-*` 并发 fixture，已精确清理至 residue 0。

## 10. 页面、发布与后续边界

本阶段没有页面文件或 API 文件变化，不增加缓存版本：页面仍为 `v10.5.12`，现有 BE-UI Pages run `31088247599` success。Gate 与 signup 保持 `enabled / blocked / enabled`、`disable_signup=true`。没有恢复业务归属 UI、旧选择器、旧 URL、管理入口或 Profile 权限。

P0完成后，active admin/operator 可以恢复生产“登记待补课完成”；DB 会强制权限、余额、并发、时间与零收费合同。现有页面若仍把已补课 actual 的时间字段设为 readonly，属于独立 UI 编辑合同，不在本 P0 中修改；本任务没有纠正张倬闻或任何真实记录。

后续必须独立授权：李天伦4个误建 exact-ID 纠正；历史 raw-negative/fee anomaly 修复；余额徽章/reader；跨月排序；移动端/UI；张倬闻实际时间编辑与生产 exact-record 纠正。不得因本 P0 完成而自动启动这些阶段。

实现提交为 `f3eb43c6949bc44edeffe0c41fc82d7717004e10`，已推送 `main`。首次 Pages run `31102416890` 的 build 成功，但同 SHA deployment 首次等待10分钟后由 GitHub Pages 服务端超时，随后两个 rerun 因相同 `pages_build_version` 已处于 cancelled 终态而立即返回 `Deployment cancelled`；仓库构建没有失败。为取得新的 Pages deployment ID，本段发布记录由后续纯文档提交发布；最终文档提交、Pages run、HEAD/origin/main 与工作区状态记录在任务交付中。
