# School V2 P0-F 课时页面读取失败紧急修复报告（2026-08-03）

## 1. 结论

故障已修复。根因是 P0-F 新增的纯只读辅助 RPC `school_get_planned_lesson_tuition_history_state(uuid[])` 只授予了 `authenticated,service_role`，而生产 `lesson.html` 使用 anon 只读身份。主 lesson reader 成功后，辅助 reader 返回 401/`42501`；`fetchLessonRecords` 抛出该普通 PostgREST error object，`loadInitialData` 外层 catch 清空了主列表、统计和筛选主数据。

修复包括两层：

1. 仅向 anon 授予该 `STABLE / SECURITY DEFINER / 固定 search_path` 纯只读 reader 的 EXECUTE；不授予表级写权限、writer 或 owner helper；
2. 辅助 reader 失败或返回集合不完整时保留主 reader 数据，但把全部记录标记为 `tuition_history_state_available=false`，显示“课时历史状态暂时无法读取，相关修改操作已隐藏。”，并隐藏 edit/delete/void。主 reader 错误仍原样进入错误路径，不吞错。

未回退 P0-F 合同，未修改任何真实业务行。

## 2. 故障现场证据

### Chrome

- URL：生产 GitHub Pages `lesson.html?year=2026&month=08&view=pair&student_id=eb705aad-de4d-45e6-a391-42dcdd89aeda`
- 页面：`v10.4.5`
- HTML：`lesson-app.js?v=p0f-20260803-2`
- app：`config.js?v=p0f-20260803-1`、`lesson-page.js?v=p0f-20260803-2`
- page API：`lesson-api.js?v=p0f-20260803-2`
- Console：
  - info：`[aozora-school-v2:supabase-config] Object`
  - info：`[aozora-school-v2] v10.4.5`
  - error：`Lesson management initial load failed Object`
  - error URL：`js/pages/lesson-page.js?v=p0f-20260803-2`
- 页面提示：`读取课时管理数据失败，请稍后重试。`
- 统计八项全部为 `-`，列表为空。

PostgREST error 是普通对象，不带 JavaScript `stack` 属性，因此 Console 的实际 stack 为 `undefined`；调用链由对应已加载源码确定为：

`attachTuitionHistoryStates → fetchLessonRecords → loadLessonMonth → loadInitialData`

### 精确请求与响应

成功主请求：

- RPC：`school_list_lesson_management_records_authoritative`
- 参数：`{"p_year_month":"2026-08","p_week_start":null}`
- HTTP：`200 OK`
- 返回：127 行，其中 planned 126 个唯一 UUID。

失败辅助请求：

- RPC：`school_get_planned_lesson_tuition_history_state`
- 参数：`{"p_lesson_ids":[主 reader 返回的126个唯一 planned UUID]}`
- 参数顺序 SHA-256：`9087c2f64c1a88f21d786fd9034c52a28daa6f34acaa96aa6fcf36e76d63a08b`
- 首三个 UUID：`23d4b46b-eb1c-48b7-8001-d208ce14f08d`、`637ba833-830f-42a6-81ed-47a6f9902523`、`7175780c-b179-4f96-a42e-99ba11bdaed8`
- 末三个 UUID：`44641bf9-c445-4bf8-b35d-d9f20c33e206`、`aa55dc2e-3b1b-4d2d-863f-9f64e84b8578`、`004441ea-1be1-4abb-98c0-23343c32a535`
- HTTP：`401 Unauthorized`
- response：`{"code":"42501","details":null,"hint":null,"message":"permission denied for function school_get_planned_lesson_tuition_history_state"}`

结论：根因是 ACL；RPC 签名、参数名、返回结构和 P0-F 字段映射正确。Promise/聚合错误边界扩大了故障影响。缓存不是根因，但旧入口曾混用 `p0f-20260803-1/-2`，本次已统一核心加载链版本。

## 3. 函数与权限审核

reader 合同：

- 签名：`school_get_planned_lesson_tuition_history_state(uuid[])`
- 返回：`lesson_id`、`tuition_revision_count`、`voided_tuition_revision_count`、`active_tuition_revision_count`
- `LANGUAGE sql / STABLE / SECURITY DEFINER`
- `search_path=pg_catalog, public`
- 函数体仅 SELECT/LEFT JOIN 既有 lesson、tuition relation、generation revision；只返回 caller-supplied UUID 中 `lesson_type='planned'` 的行。
- 数据内容仅为页面已可读取 lesson 的历史 revision 路由计数，不返回 bill、income、金额、snapshot 或 owner-only字段。

最终 EXECUTE：

| 对象 | anon | authenticated | service_role |
|---|---:|---:|---:|
| history state reader | 是 | 是 | 是 |
| `school_void_planned_lesson_after_tuition_void` owner helper | 否 | 是 | 是 |
| source treatment draft writer | 否 | 是 | 是 |

anon HTTP 负向验证：上述 owner helper 与 draft writer 均返回 `401 / 42501 permission denied`，使用不可能 UUID，函数未执行。P0-F draft/claim 表对 anon 的 INSERT/UPDATE/DELETE 继续为否；未新增任何表级 grant、writer grant 或 service-role 浏览器路径。

## 4. 修改与执行

主要文件：

- `sql/current/school_tuition_p0f_lesson_history_reader_anon_acl_fix_20260803.sql`
- `sql/current/school_tuition_p0f_lesson_history_reader_anon_acl_fix_rollback_test_20260803.sql`
- `sql/current/school_tuition_p0f_income_forward_adjustment_reader_20260803.sql`
- `sql/current/school_tuition_p0f_school_postdeploy_20260803.sql`
- `js/api/lesson-api.js`
- `js/api/lesson-detail-api.js`
- `js/utils/lesson-tuition-history-state.js`
- `js/pages/lesson-page.js`
- `js/pages/lesson-detail-page.js`
- lesson app/component cache references、`lesson.html`、`lesson-detail.html`
- `scripts/tuition-p0f-lesson-read-failure-static-test.mjs`

已执行 SQL：

1. ACL rollback test：事务内 anon reader 返回1行，writer/helper权限保持拒绝，ROLLBACK 后 anon reader grant residue 0；
2. ACL fix：正式 `REVOKE` 后仅 `GRANT EXECUTE ... TO anon,authenticated,service_role`，并更新函数 comment；
3. `school_tuition_p0f_school_postdeploy_20260803.sql`：通过；
4. `school_tuition_p0f_cash_readonly_postdeploy_20260803.sql`：只读事务并 rollback，通过。

实际调用：主 lesson reader、history state reader、课时统计/credit reader（Chrome页面）；postdeploy 的 P0-F preview 与 P0-E income reader均为只读。两个 writer 仅做权限前拒绝的 anon 负向 HTTP 测试，没有函数执行或业务写入。

## 5. 测试

- `tuition-p0f-lesson-read-failure-static-test.mjs`：通过；实际执行纯函数用例覆盖辅助 reader error、返回不完整、正常映射、主行保留、所有动作 fail-closed；
- JS syntax：全部通过；
- 页面层 `.rpc()` 与直接 insert/update/delete/upsert：0；
- P0-B1 authority、lesson settlement filter、authoritative-month refresh、lesson operations、lesson generation closure：全部通过；
- anon reader：修复前 `401/42501`，修复后 `200 OK`，`1/1/0`；
- anon writer/helper：`401/42501`；
- 未使用 synthetic 业务 fixture；rollback test 无业务 DML，test record id 不适用，residue 0。

## 6. Chrome 生产验收

最终页面 `v10.4.6`，HTML/app/config/page/API/component 核心资源统一 `p0f-readfix-20260803-1`。

- 强制新导航后加载成功，Console 仅两条 info，error 0；
- 2026-08 彭宇晗：planned 30课次、JPY255,000，15个唯一“作废预定课时”，delete 0、edit 0；
- 2026-08 李天伦：planned 32课次、JPY352,000，16个唯一“作废预定课时”，delete 0、edit 0；
- 张倬闻查询成功，planned 65，未受影响；
- 2026-07 左右对照显示 completed、pending makeup、makeup completed；普通列表135行并正常显示 actual；partial 履约继续表现为 actual completed + source pending makeup；
- 2026-07 自然周筛选返回28行；老师筛选29行；科目筛选35行；青空业务归属筛选135行；月份、学生筛选均正常；
- 所有统计卡片为实际数值，不再为 `-`；
- 页面未出现 permission denied，相关 REST 请求成功，无失败请求；
- 未点击作废、新增、实际课时生成、保存、结算或任何写按钮。

## 7. 数据保护与哈希

修复前后完全一致：

| 对象 | 行数 | 全行哈希 |
|---|---:|---|
| lesson | 731 | `7030411f5104c7c5e8994d341bc99190` |
| settlement | 17 | `b890bdc29a27d842d3e3c6a28b84d526` |
| generation identity | 15 | `60f11efc1aebad6b182f7d0da08d36d7` |
| revision | 16 | `3fb1700c806e58cb0f8a75358a09dbd5` |
| bill | 18 | `bc7fe1fc6d904c5f6a0380583e430c9e` |
| income | 51 | `4468607bc30770376ce6aaca9016e598` |
| generation adjustment | 1 | `30304a8ab7a3edbe796b5528512ac242` |
| Cash request | 39 | `303e10bc1a28a0abd8b27afd3929cfd8` |
| Cash CNY | 71 | `d7e72182970de4ea8849c994b67e8dcc` |
| Cash JPY | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

唯一生产 DB 变更是只读函数 ACL 与 comment 元数据。真实 lesson、settlement、generation、revision、bill、income、adjustment、Cash 和 Gate 写入均为 0。

Gate 终态：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=blocked`。

## 8. Git 与保护文件

- 基线/parent：`c202eb9a7d982a030a3a5b74c59ad2967075bfe8`
- 修复提交：`44101a0`（已普通推送 `origin/main`）
- 最终文档提交与 HEAD/origin 状态见任务最终交付。

六份受保护 untracked 文件 SHA-256：

- `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

修复完成前后均未继续执行彭宇晗、李天伦真实课时作废或月度结算。
