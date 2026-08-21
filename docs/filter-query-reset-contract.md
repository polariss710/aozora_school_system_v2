# 顶部筛选栏 Query / Reset 合同

本合同适用于 School V2 页面顶部、以“查询”显式应用筛选的结果型筛选栏。`lesson.html`（课时管理）是未改动正向基准；页面按批次迁移，未列入已完成批次的页面不得据此宣称已修复。

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
- deprecated legacy exception：Legacy 工资支付（`index.html` / `js/pages/payment-page.js`），理由为 `V3 removal`。正式处置合同为：V2维持现状，不纳入顶部筛选合同迁移；V3删除；如果出现数据、权限或支付链问题，再单独处理。
- 其他适用页面仍为 `pending migration`；在各自批次完成并验收前，仍视为未统一。
- `not applicable` 仅用于确实没有本合同所定义顶部结果筛选栏的页面，不得与 `pending migration` 或 deprecated legacy exception 混用。

截至 Phase B2 的统计：

| 口径 | 适用总数 | compliant | deprecated legacy exception | pending migration | not applicable |
| --- | ---: | ---: | ---: | ---: | ---: |
| HTML 页面 | 18 | 8 | 1 | 9 | 0 |
| 路由视图（`part-time-work.html` 拆为两个视图） | 19 | 8 | 1 | 10 | 0 |
