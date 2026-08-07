# School V2 课时管理筛选栏单页布局优化实施报告

日期：2026-08-07（Asia/Tokyo）

## Business-model expansion declaration

- New tables / columns / enum or status values: none
- New date, month, attribution, identity, source, snapshot or version concepts: none
- New writable facts or authorities: none
- Changed field semantics, mutability, writer, reader authority or locking: none
- Legacy fallback, dual read/write or historical reinterpretation: none
- ACL / RLS / Gate / schema / RPC changes: none

本轮只删除课时管理页面顶部 `lesson_type` 筛选链并调整该筛选卡布局；数据库中的 planned/actual 类型、课时业务规则、reader/writer 及历史事实完全不变。

## 实时基线

- 分支：`main`。
- 初始 HEAD / origin/main：`199335896977e24a685d38d580eb22be1394a878`。
- 初始 ahead/behind：`0/0`。
- 初始生产版本：`v10.5.18`。
- 初始最近 Pages：run `31165134972`，commit `199335896977e24a685d38d580eb22be1394a878`，success。
- Gate：`student_tuition_cash_submit=enabled / student_tuition_generate=blocked / student_tuition_preview=enabled`。
- 工作区只有六份既有受保护 untracked 文件，无本任务外 tracked 修改。

## 实现

### `lesson_type` 顶部筛选移除

- 从筛选表单删除“课时类型”标签、select 和 `lessonTypeSelect` DOM cache/event。
- 从 `DEFAULT_FILTERS`、initial query、`readFilters`、restore、query/reset/月切换、URL builder 和 `filterLessonRecords` 删除 `lessonType` 状态。
- 课时统计 RPC 保留既有固定签名，但 API 始终传 `p_lesson_type:null`，保证统计同时覆盖 planned/actual；未修改或部署 SQL/RPC。
- 底层 `lesson_type` 字段、导入预览、PDF、planned/actual writer、左右配对与详情展示均保留。

### 旧 URL 兼容

- initial query 识别 `lesson_type` 与旧 camelCase `lessonType` 后，以 `history.replaceState` 原地清除。
- 清理不刷新页面、不形成循环；year、month、student_id、include_inactive、view、week/status/billable/keyword 及 hash 均保留。
- 查询 URL builder 不再写入 `lesson_type`，reader 与统计不再获得隐藏类型过滤条件。

### 本页局部布局

- 筛选表单拆为本页专用 primary/secondary 两行容器，不改变共享页面样式。
- 宽屏第一行生产实测：月份 `196px`；自然周、学生、老师、科目各 `445px`；独立 include-inactive 区域 `176px`。
- 宽屏第二行生产实测：状态、计费、关键词各 `450px`；中间弹性空白 `612px`；查询/重置区 `200px` 且同一行靠右。
- checkbox 从学生字段内部移出为独立区域；390px 时仍按 DOM 顺序紧跟学生字段。
- 局部间距为 10/12px，移除类型筛选后卡片保持两行且更紧凑。

## 验证

### 静态与语法

- 新增 `scripts/lesson-filter-layout-static-test.mjs`，覆盖 DOM、页面状态、旧 URL、API null 合同、桌面/移动布局、页面 RPC/DML 和 service-role 防回退。
- `node --check`：lesson page/API/app 全部通过。
- 课时生成刷新、operations、authoritative month、settlement week、cancellation、B4-Lesson、B4-Remaining、B5、P0 permission/balance、P0F history reader、BE-UI 等相关静态回归全部通过。
- page-layer 直接 `.rpc()` / table DML 为 0；浏览器 service-role marker 为 0。

### 生产 Chrome 无写验收

- 生产版本：`v10.5.19`，active admin 会话。
- 旧 `lesson_type=actual` 与 `lesson_type=planned` 链接均在初始化后清除；year/month/student_id/include_inactive/view 保留，查询、重置、月切换和刷新恢复正常。
- 2026-06 paused selected student：10 组 pair rows 均同时含 planned 与 actual，空列 0；planned/actual 统计均为 20 小时。
- 保留筛选回归：老师王亚楠、科目 JLPT、状态 completed、计费 true、关键词 N2 联合查询成功并写入合法 URL；reset 恢复 2026-08、全部学生、空状态/计费/老师/科目/关键词及 pair view。
- 2026-07 默认学生 option 为 7 名 + “全部”，paused 学生隐藏；include inactive 后为 8 名 + “全部”，显示“本月暂停”；不勾 include 时 selected override 仍保留 paused 学生并正常刷新恢复。
- 2560×1440：body/document/client width 均 2560，无横向溢出；两行列宽及按钮位置符合目标。
- 390×844：全部筛选项为 346px 单列，checkbox 紧跟学生，body/document/client width 均 390，无横向溢出。
- Console error 0 / warning 0；未点击新增、编辑、取消、补课、批量生成、导入或其他写入按钮。

## 提交与部署

- `e5933975543be5d2bc3befdd4cac6ec4d56488c2`：移除类型筛选、初版布局、版本及测试；Pages `31178928161` success。
- `753e0a6cdbebea6531a9a6cde692e02f6fd45348`：按生产实测分离两行宽度；Pages `31179138566` success。
- `33db1d46ca2eb13dbb734e2b6bdd7d732104d894`：刷新缓存链；Pages `31179242238` success。
- `19ad901e5ffe801e45bb299be2b1f856b015fc80`：按钮保持第二行及 `-3` 缓存链；Pages `31179414958` success。
- 最终实现版本：`v10.5.19`。

## 数据库、业务数据与 Gate

- 执行 SQL 文件：0。
- 调用写 RPC：0；浏览器仅调用既有只读 lesson/student candidate/stats readers。
- School、Cash、Storage 与真实业务数据写入：0。
- 测试 fixture、测试记录、数据库残留：0。
- Gate 前后均为 `enabled / blocked / enabled`，未修改。

## 受保护文件

前后 SHA-256 完全一致；均未修改、移动、删除、暂存或提交：

- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`: `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`: `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`: `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`: `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`: `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`: `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

## 结论

课时管理筛选栏单页优化已完成；左右对应视图不再因顶部课时类型过滤产生单侧空白。其他页面、业务模型、状态模型、课时 writer、Gate、Cash 与生产数据均未改变。
