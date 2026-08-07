# School V2 课时管理筛选栏单行布局二次优化实施报告

日期：2026-08-07（Asia/Tokyo）

## 结论

课时管理顶部筛选已按本轮合同完成并生产上线，页面版本由 `v10.5.19` 前进至 `v10.5.20`。宽屏筛选卡只保留收费／学生结算月、自然周、学生、包含暂停/离校学生、老师、科目、关键词、查询和重置；课时类型、状态、计费三个顶部筛选均不再存在。底层 `planned/actual`、课时状态、计费状态、金额、卡片展示、统计业务口径和全部 writer 未改变。

实现提交为 `29726091a23091eb295298a086e627f02cbb3ce6`，Pages run `31182779102` 成功，部署 commit 与实现提交一致。生产 Chrome 确认 `v10.5.20`。

## 实时基线与工作区保护

- 初始分支：`main`。
- 初始 `HEAD` / `origin/main`：`76787a168e7e7efe4ab01212dd2c94a73d970a42`，ahead/behind `0/0`。
- 开始时没有 tracked 修改，因此没有业务负责人未提交的 JS/CSS 试改需要合并；仅存在六份既有受保护 untracked 文件。
- 未执行 reset、rebase、checkout 或回退。
- 业务模型扩展声明：表、字段、状态、权威来源、writer、reader precedence、ACL/RLS 均为 `none`。

六份受保护文件开始、实现部署后哈希一致，且从未暂存：

| 文件 | SHA-256 |
| --- | --- |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 实现内容

### 顶部筛选与隐藏状态

- 删除状态、计费的标签、select、DOM cache、事件、默认 page state、URL 读取/写入、恢复/重置、本地记录过滤和 reload mode 分支。
- 课时 reader 继续使用既有默认口径：读取未作废记录，不再接收不可见的 `status` 页面参数。
- 统计 RPC 保留固定历史签名，但 `p_lesson_type`、`p_status`、`p_is_billable` 均由 API 层显式传 `null`，等价于删除前“全部类型、全部状态、全部计费”。
- 历史检索确认实际使用过的退役参数为 `lesson_type`、`lessonType`、`status`、`is_billable`、`isBillable`；页面启动时统一以一次 `history.replaceState` 原地删除，不刷新、不循环，并保留合法参数。
- 页面模块没有新增直接 `.rpc()` 或表 DML；`js/legacy-core.js` 未修改；浏览器代码没有 service-role。

实现修改文件为：`lesson.html`、`css/app.css`、`js/pages/lesson-page.js`、`js/api/lesson-api.js`、`js/lesson-app.js`、`js/config.js`，以及五份相关静态回归测试；文档封口只新增本报告并更新 `docs/current-status.md`。

### 单行布局

宽屏 grid 顺序固定为：

`196px / 300px / 250px / 176px / 250px / 250px / 250px / 弹性空白 / 按钮区`

checkbox 作为独立 grid item，宽屏使用与其他标签等高的占位行，使控件底边对齐；移动端隐藏该占位，使 checkbox 紧跟学生字段。所有规则限定在课时管理局部 class 内，没有修改其他页面筛选栏。

## 测试

以下静态/语法回归全部通过：

- `node --check`：`js/pages/lesson-page.js`、`js/api/lesson-api.js`、`js/lesson-app.js`。
- `lesson-filter-layout-static-test.mjs`。
- `lesson-generation-closure-ui-test.mjs`。
- `lesson-cancellation-hardening-ui-test.mjs`。
- `lesson-operations-closure-ui-test.mjs`。
- `lesson-billing-week-invariant-ui-test.mjs`。
- `lesson-authoritative-month-refresh-regression-test.mjs`。
- `lesson-batch-generate-refresh-ui-test.mjs`。
- `lesson-p0b1-authority-static-test.mjs`、`tuition-p0f-lesson-read-failure-static-test.mjs`。
- `student-status-phase-b4-lesson-candidate-static-test.mjs`、`student-status-phase-b5-static-test.mjs`。

静态扫描结果：顶部 form 不含课时类型/状态/计费控件；页面不含对应隐藏 state 或 URL 写入；全部 page-layer 直接 RPC/DML 为 0；浏览器 service-role 标记为 0。

## 生产 Chrome 无写验收

### URL 与功能

- 同时带 `lesson_type=actual`、`lessonType=planned`、`status=completed`、`is_billable=false`、`isBillable=true` 的旧链接打开后，五项退役参数一次清除。
- `year=2026`、`month=07`、`student_id`、`include_inactive=1`、`view=pair` 全部保留，数据正常加载，没有刷新循环。
- 月份、自然周、学生、老师、科目、关键词联合查询通过；测试组合收敛为 1 行，URL 完整恢复各合法筛选。
- 重置后恢复东京当前月 2026-08 的全量结果；查询、切月、刷新均正常。
- 2026-06 删除前 `v10.5.19` 的“全部状态/全部计费”与部署后 `v10.5.20` 均为 list 124 行、pair 62 行，统计均为 planned 122.75h / actual 118.5h / planned JPY1,210,875 / actual JPY1,165,750 / 跨月补课4次7h / 待补来源17 / 待补余额51h。
- `v10.5.20` 继续渲染 62 个顶层 pair row；抽查配对行同时包含左侧预定课时和右侧实际课时，页面已不存在能隐藏任一类型的顶部/隐藏条件。卡片中的状态、计费、金额、月份继续显示。

### 学生月份候选

- 2026-06 默认 8 名。
- 2026-07 默认 7 名；include inactive 后 8 名，`厦门吕同学｜本月暂停` 标签正确；关闭 include inactive 后，已选 paused 学生继续作为 selected override 保留，URL 只保留 `student_id`。
- 2026-08 默认 7 名；include inactive 后 8 名，同一 paused 标签正确。

### 尺寸与控制台

- 2560×1440：筛选 row 高 66px、卡片高 140px，仅一行；实测宽度依次为 `196 / 300 / 250 / 176 / 250 / 250 / 250px`，按钮区 200px，全部控件底边为 y=306，查询/重置位于最右侧；页面横向溢出 0。
- 1440×900：自动为 4 列，每列 264px，字段分三行合理换行；页面横向溢出 0。
- 390×844：字段内容宽 346px 单列，checkbox 距学生字段 12px，按钮各 346px 可操作；document/body 横向溢出均为 0。
- 新标签页最终验收 Console 仅有版本 info；error `0`、warning `0`。
- 全程未点击新增、编辑、取消、补课、批量生成、导入或任何写入口。

## 数据库、Gate 与发布边界

- SQL 文件执行：0。
- 写 RPC 调用：0；生产业务 RPC 写入：0。
- 只执行一次 School DB Gate 的只读 `SELECT`；页面验收只调用既有 reader。
- School、Cash、Storage 及真实业务数据写入：0；测试 fixture：0；测试 record ID：无。
- Gate 前后均为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`。
- 未修改数据库 schema、RPC、ACL、RLS、Gate、Cash 或 Storage。

本轮到此停止，没有调整其他页面。
