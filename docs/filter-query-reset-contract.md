# 顶部筛选栏 Query / Reset 合同

本合同适用于 School V2 页面顶部、以“查询”显式应用筛选的结果型筛选栏。`lesson.html`（课时管理）是未改动正向基准；Phase B1–B5 已完成全部计划迁移，后续新增适用页面必须进入统一参数化合同测试矩阵。

## 状态所有权

- `draft filters`：控件当前值；change 可以更新 draft。
- `applied filters`：最近一次显式查询实际使用的值；只有查询可以更新。
- 主结果：列表、表格、卡片、统计、汇总和主预览；其所有权属于 applied filters。
- display state：列表/左右对应、展开/折叠、卡片/表格等纯展示状态；reset 原则上保留。

## 事件合同

- 初始加载：可以读取默认或 URL 筛选，初始化辅助候选，读取并渲染默认主结果。
- change：不得调用主结果 reader，也不得用缓存显示新筛选对应的主结果。可以只更新 draft、清空失效主结果、显示等待查询提示、读取辅助候选，并通过 `history.replaceState()` 无导航同步 draft URL。
- reset：恢复页面默认 draft；清空主结果、统计、汇总、计数、选择/勾选和依赖结果的操作状态；保留纯 display state；显示精确文案 `已重置筛选条件；点击“查询”后刷新结果。`。不得调用主结果 reader、不得用缓存恢复默认结果、不得调用 writer、不得发生 Document navigation。
- query：读取 draft，按页面合同使用主结果 reader 或现有缓存，设置 applied filters，渲染结果和统计，恢复合法的结果依赖操作状态，同步查询 URL，并清除等待查询提示。

## Reader、缓存与 URL

- `auxiliaryReader` 只更新学生、老师、科目、业务归属或依赖下拉等筛选候选；必要时可在 change/reset 使用。
- `mainResultReader` 更新主列表、统计、汇总、业务卡片、流水或主预览；只允许在初始加载、显式查询或其他明确业务刷新中使用。
- HTTP `POST` 形式不能单独决定 reader/writer 分类，应按业务用途和副作用分类。
- change/reset 即使网络请求为 0，也不得从缓存重绘新条件或默认条件的主结果。
- URL 可以在 change/reset 无导航同步 draft；URL 变化本身不是查询。URL、draft、applied 与可见主结果必须保持可解释的一致关系。
- 顶部筛选事件不得调用 writer；页面既有 writer 成功后的显式刷新不属于 reset/change，不能因本合同被移除。

## 迁移状态

- 正向基准：课时管理（生产行为保持不变）。
- Phase B1 已统一：科目管理、老师工资结算、报销管理、利润分析。
- Phase B2 已统一：学生管理、老师管理、账户管理。
- Phase B3 已统一：学生月度结算、工资规则、收入记录、支出记录、外部授课年度汇总。
- Phase B4 已统一：PTW 授课记录（`part-time-work.html?view=lessons`）与授课结算（`part-time-work.html?view=settlement`）共享视图。两者共用 `lessons`、`wageLessons`、`settlements` 和一次三-reader 请求生命周期；reset 同时失效请求、清空两侧缓存/DOM/结果上下文，保留 `view` 与两套独立折叠 Set。显式 Query 重新使用保存的 display state，writer 成功后的保留折叠刷新仍是独立业务动作。
- Phase B5 已统一：周课表图片、教室排班、本周课时待处理。三页 reset 均恢复默认 draft、清空 applied filters、主结果/预览/排班/周统计/计数/结果依赖操作和 loading，并通过页面局部 request sequence 阻止旧主响应回填；教室 change 的缓存排班重绘以及教室/周切换按钮的隐式主查询均已移除。周课表图片的学生候选 reader 仍是唯一允许在 change/reset 使用的 B5 auxiliary reader。
- deprecated legacy exception：Legacy 工资支付（`index.html` / `js/pages/payment-page.js`），理由为 `V3 removal`。正式处置合同为：V2维持现状，不纳入顶部筛选合同迁移；V3删除；如果出现数据、权限或支付链问题，再单独处理。
- `pending migration`：0。所有适用且计划保留的 V2 顶部筛选页面均已迁移。
- `not applicable` 仅用于确实没有本合同所定义顶部结果筛选栏的页面，不得与 `pending migration` 或 deprecated legacy exception 混用。
- Quote Generator、Contract Generator 等没有本合同所定义结果筛选栏的页面不计入适用清单，也不以 `not applicable` 增加本表总数。

截至 Phase B5 的最终统计：

| 口径 | 适用总数 | compliant | deprecated legacy exception | pending migration | not applicable |
| --- | ---: | ---: | ---: | ---: | ---: |
| HTML 页面 | 18 | 17 | 1 | 0 | 0 |
| 路由视图（`part-time-work.html` 拆为两个视图） | 19 | 18 | 1 | 0 | 0 |

## B5 Reader、URL 与异步合同

- 周课表图片：`fetchStudentRangeCandidates` 只更新学生候选，是 auxiliary reader；初始化使用的 `fetchLessonTeachers` / `fetchLessonSubjects` 以及 Query 使用的 `fetchLessonRecords` / `fetchLessonStudentsByIds` 共同决定图片内容，均归入主结果 reader。URL 可表示当前 draft 等待态或最近 Query 的 applied 筛选；change/reset/Query 均只用 `history.replaceState()`，reset 写入默认下周一、全体学生且不含非在籍，并清空预览和下载上下文。图片布局、画布模板与即时 data URL 下载保持不变，不持有 blob/object URL。
- 教室排班：初始化使用的 `fetchLessonTeachers` / `fetchLessonSubjects` 与 Query 使用的 `fetchLessonRecords` / `fetchLessonStudentsByIds` 共同决定排班卡片内容，均归入主结果 reader；该页无 auxiliary reader。该页不新增筛选 URL；教室、日期、上一周、本周、下一周只更新 draft 并清空失效结果，显式“刷新排班”才读取并执行既有教室筛选、冲突判断和排班渲染。
- 本周课时待处理：`fetchWeeklyLessonOperations` 与 `fetchLessonStudentsByIds` 均是主 reader，无 auxiliary reader。`week_start` 在 change/reset 的空结果状态表示 draft，在 Query 成功后表示 applied；全部同步使用 `history.replaceState()`。上一周/下一周不再隐式查询。
- 三页主 Query 均采用 latest-request-wins sequence；reset 和任一 draft 变更会递增 generation、立即结束 loading 并清空结果。旧请求成功、失败或 finally 均不能覆盖 reset 文案、空结果或新 Query。

## PTW Phase B4 URL 与历史合同

- 旧 PTW 专项合同刻意规定 reset 的 reader/render/URL effect 都为 0，并保留旧主 DOM、旧 applied URL 与短提示；这些保护已由 Phase B4 撤销，历史提交仍保留审计证据。
- PTW 正常查询 URL 表示 applied filters；reset 是例外的明确等待态：以 `history.replaceState()` 写入默认 draft 年月、删除旧 `workplace_name` / `class_description`，保留当前 `view`，同时将 `appliedFilters` 设为 `null` 并清空双视图结果。URL 改变不触发 reader，也不产生 document navigation。
- 显式 Query 会把当前 draft 设为 applied、以 `pushState()` 同步 URL 并读取两次授课记录和一次月结结果；同页 `popstate` 按 URL 恢复并查询，整页手动刷新按首次加载合同查询。因此 reset 后页面本身保持空结果，浏览器历史恢复或手动刷新则是可解释的新读取，不会复用旧缓存。
- `fetchPartTimeWorkLessons`（筛选记录及整月工资记录）和 `fetchPartTimeWorkMonthlySettlements` 是主 reader；顶部筛选无 auxiliary reader。`fetchPartTimeWorkSettlementExport` 是用户显式导出的结果依赖 reader，不属于顶部 auxiliary reader。创建/修改/生成/删除授课记录、锁定/解锁结算和生成收入记录均为 writer，reset 不调用它们。
