# School V2 课时15分钟刻度前端封口实施报告

日期：2026-08-10（Asia/Tokyo）
仓库：`/Users/polariss710/Documents/aozora_school_system_v2`

## 1. 实施结论

- 方案A已完整上线，生产版本为 `v10.5.39`。
- School 主课时前端与既有 DB 权威规则统一为绝对15分钟刻度：开始、结束分钟只允许 `00/15/30/45`；DB继续作为最终防线。
- `14:40–16:40` 会在 API/RPC 前被拒绝，提示为：`无法提交：开始和结束时间必须使用15分钟刻度（00、15、30、45）。当前输入14:40–16:40不符合规则。`
- `LESSON_TIME_GRID_INVALID` 已映射为稳定中文业务提示；不会再对该错误显示“请稍后重试”。其他未知错误的既有 fallback 保留。
- 前端没有自动舍入、截断或替换输入；`14:40` 不会变为 `14:45`。历史非标准时间只在用户保存时被明确阻断，页面打开不会改写原值。
- 孙陈锋 `2026-08-10` actual 新增为 `0`；本轮没有重试生成 actual。仍需业务负责人另行决定真实、且符合既定刻度的标准登记时间。

## 2. 实时基线

| 项目 | 初始值 |
|---|---|
| 分支 | `main` |
| HEAD / origin/main | `f8f2d99a12c2b96a36b6968d7553747699a0ad3b` / 同值 |
| ahead / behind | `0 / 0` |
| 生产版本 | `v10.5.38` |
| 最近成功 Pages | run `31347910069`，commit `f8f2d99a…` |
| tracked / staged | `0 / 0` |
| 既有 untracked | 10份受保护文件 |
| Gate | `enabled / blocked / enabled` |

Business-model expansion declaration 全部为 `none`：没有表、列、状态、日期/月、身份、来源、快照、可写事实、字段语义/可变性、writer/reader authority、锁、fallback、dual write、历史解释或破坏性schema变化。本轮只让前端服从既有 DB 刻度规则。

## 3. 文件变更

| 文件 | 修改 | API / DB / 业务计算影响 |
|---|---|---|
| `js/utils/lesson-time-grid.js` | 新增共享纯校验：格式、端点刻度、时间先后和既有差值规则 | 不调用API/DB；不舍入输入；不改变费用/工资 |
| `js/pages/lesson-page.js` | 所有主课时创建/生成/取消/补课/批量入口复用共享校验；批量非法时间不再静默清空 | API参数结构不变；非法输入在writer前返回 |
| `js/components/lesson-edit-dialog.js` | 列表与详情编辑弹窗复用共享校验 | writer/API合同不变 |
| `js/utils/lesson-error-message.js` | 按稳定业务标识从message/details/hint/code安全映射刻度错误 | 其他`22023`不误映射；不显示内部细节 |
| `lesson.html` | 12个主课时time input统一`step="900"`，6组常驻提示 | HTML输入辅助，不是权威计算 |
| `lesson-detail.html` | 2个编辑time input统一`step="900"`，1组常驻提示 | 同上 |
| `css/app.css` | 仅调整刻度提示字重和行高 | 无业务影响 |
| `js/config.js` | `v10.5.38 → v10.5.39` | 仅页面版本 |
| `js/lesson-app.js`、`js/lesson-detail-app.js`、`js/pages/lesson-detail-page.js` | 更新最小模块缓存链 | 无业务影响 |
| `scripts/lesson-time-grid-frontend-test.mjs` | 新增刻度、mock writer、错误映射、HTML覆盖测试 | 本地测试，无生产写入 |
| `scripts/lesson-cancellation-hardening-ui-test.mjs` | 仅把旧缓存断言更新为本轮cache key | 原业务断言未放宽 |
| `docs/current-status.md`、本报告 | 记录实施与验收 | 文档 |

`js/legacy-core.js`、`js/api/*`、SQL、Supabase、兼职课时模型均未修改。page-layer直接`.rpc()`/DML为0，浏览器service-role为0。

## 4. 校验覆盖

- planned 新建、planned 编辑（列表与详情）。
- ordinary actual 与 partial actual（共用实际课时payload校验）。
- 当月补课完成、跨月待补课完成。
- 取消并转待补课；原取消业务错误映射保持。
- 批量生成planned pattern：两端非法时直接报错，不再降级为“只按课时生成”。
- 所有School主课时HTML time input 14个及动态pattern 2个均为 `step="900"`。
- `school_part_time_work_lessons` 独立模型明确不适用，本轮未改。

共享校验分别验证：HH:MM格式、开始端点、结束端点、结束晚于开始、总差值刻度。各入口既有duration字段与起止时间一致性校验继续保留；费用、工资、状态和writer参数计算未改。

## 5. 测试结果

以下全部通过：

- `git diff --check`。
- 修改JavaScript及两个测试脚本的 `node --check`。
- `node scripts/lesson-time-grid-frontend-test.mjs`：
  - `14:40–16:40`、单端`:40`、双端非法但总时长为15分钟整数倍均拒绝；
  - `14:00/14:15/14:30/14:45`四组合法样本均通过；
  - `14:45–14:30`按结束早于开始拒绝；
  - mock writer非法输入调用数 `0`；原输入保持 `14:40/16:40`；
  - `LESSON_TIME_GRID_INVALID` message/details映射通过；其他`22023`和未知中文fallback通过；
  - 14+2个主课时time input的`step="900"`覆盖通过；兼职页面未受影响。
- 既有回归：`lesson-cancellation-hardening-ui-test`、`actual-overage-ui-test`、`lesson-generation-closure-ui-test`、`lesson-operations-closure-ui-test`、`lesson-batch-generate-refresh-ui-test`、`lesson-billing-week-invariant-ui-test`、`lesson-writer-p0-permission-balance-static-test`、`student-status-phase-b4-lesson-candidate-static-test`、`p0-g1-a-auth-guard-static-test`、`p1-b2b-auth-storage-static-test` 全部通过。

## 6. 生产 Pages 与 Chrome 无写验收

- 功能commit：`b713defdc5172f0ac95ea063c19b2b6d3e9c68b3`。
- Pages run：`31373623148`，`success`，head SHA精确匹配功能commit。
- 生产 `config.js` 与页面均显示 `v10.5.39`。
- 新增planned弹窗：常驻提示完整显示，开始/结束`step=900`。
- 输入 `14:40–16:40`：两字段均为error状态，动态提示包含当前输入；点击“新增”后仍停留前端。
- 从Network cursor起观测5个请求，匹配School lesson writer RPC/Edge的请求为 `0`。
- 重新打开干净弹窗输入 `14:45–16:45`：两字段错误状态清除、错误区隐藏；没有点击合法提交。
- 390px：`innerWidth/body.scrollWidth/document.scrollWidth = 390/390/390`，提示可见。
- Console error/warning：`0 / 0`。

## 7. 孙陈锋记录状态

生产只读事务确认学生UUID为 `b17abc58-2f64-4bad-bf20-c9643ead60bc`。`2026-08-10` 四条planned仍原样存在：

| planned UUID | 状态 | 已存时间 |
|---|---|---|
| `37a2083e-bb28-45d1-802a-f98f4564887f` | planned | 空 / 空 |
| `63ca3a2b-7c2f-4eed-a997-71840357f8f6` | planned | 14:00 / 16:00 |
| `ea766c1d-f152-4b3f-9400-0d5b5aa64614` | planned | 13:00 / 15:00 |
| `fcbf1be4-567b-4876-9cc6-19cd0d395da0` | planned | 空 / 空 |

部署后planned数量 `4`、关联actual数量 `0`、planned hash `a139f32fc2832c0df58b3100ff892ba1`；全体lesson count/hash部署前后均为 `744 / 3cd0c2ce1b7baa60c779c257c38e9f50`。工资、结算、账单或Cash没有变化。

## 8. 数据不变量与Gate

| 范围 | 部署前 = 部署后 |
|---|---|
| lessons | `744 / 3cd0c2ce1b7baa60c779c257c38e9f50` |
| settlements | `18 / 481ffa7ed5173da852f0f28ce66c2e9b` |
| bills | `22 / e50673ac998ee2d84573a076a64d3d42` |
| income | `55 / c55f82c7d62dbe92d0b49714a911a234` |
| wage locks / details | `103 / ea395407134045e7623e171b02d3d910`；`612 / 1d45d0ce37696051c233465efaf3de5e` |
| Cash requests / CNY / JPY | `43 / f4b1876e981ef75828600e0c7f0dc371`；`74 / 070c262ec01008d404b424233d2a6e47`；`31 / 95ab7cf8a8d167e9b052d3fc6b64614b` |
| Storage buckets / objects | `1 / 9b1be72d5b5fb2ac22b7f7b49d9f8f90`；`57 / 62fac5521274c58c6f6982a0c690c134` |
| Gate | preview `enabled` / generate `blocked` / cash-submit `enabled`，三行hash不变 |

所有生产查询均在显式 `READ ONLY` 事务内并 `ROLLBACK`。首次一条shell引号错误的只读命令仅在SQL解析阶段报错，未进入事务且未执行查询或写入。SQL文件执行 `0`，DDL/DML `0`，业务/写RPC `0`，actual真实提交 `0`，School/Cash/Storage/Auth/Edge/Gate/cron变化 `0`。

## 9. 受保护untracked文件

10份既有文件最终路径与SHA-256均保持：

- `docs/school-v1-decommission-p1-b2a-session-service-worker-readonly-design-20260810.md` — `75474786ac2de0d9881be17b298acf51b1ad68099b6c1f88c7b0d7aac1736a47`
- `docs/school-v1-decommission-p1-ca-archive-restore-observation-readonly-design-20260810.md` — `fd703860ef2bb5ca5e159f14b0ef138ddad765c9025960aab40c245e901aec0e`
- `docs/school-v1-decommission-preflight-p1a-online-evidence-20260809.md` — `1047c2d686a43499e21a43055973475aeb0d52a9fd36c0604aa98ce8ebf0c519`
- `docs/school-v1-decommission-readonly-investigation-20260809.md` — `3e65e0091e68cd419ac13f0e692fcce99f07041abfcdab3b8786e526a800fcaa`
- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` — `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` — `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` — `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` — `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` — `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` — `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

这些文件未修改、移动、执行、暂存或提交。
