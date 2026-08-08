# School V2 支出记录筛选栏单行布局与显式查询边界实施报告

日期：2026-08-08（Asia/Tokyo）

## 结论

支出记录页已完成单页优化并部署生产：页面版本由 `v10.5.25` 前进至 `v10.5.26`，实现提交为 `ef22d36591bcf5c518b8ac508716d318217f8169`，Pages run `31255250710` 成功且部署 commit 一致。

2560px 下筛选栏为严格单行，学生、老师、账户、币种均精确 300px；1440px 自动两行；390px 单列且查询/重置并排。筛选状态现分为 draft/applied：普通筛选变化不查询、不改 URL，include inactive 只刷新学生候选且有请求序号保护，显式查询才调用一次支出 reader 并原子应用 URL/列表，重置各调用一次候选和支出 reader。

本轮没有修改支出/Cash reader、writer、金额或状态合同，没有修改数据库对象、ACL/RLS、Gate、Cash、Storage 或真实业务数据。完成本页后，本轮筛选栏 UI 调整阶段暂告一段落，不继续其他页面或新任务。

## 实时基线

- 分支：`main`。
- 初始 HEAD：`0ec07fc2e436e69b5cf8ce5562e2c412456501c8`。
- 初始 `origin/main`：`0ec07fc2e436e69b5cf8ce5562e2c412456501c8`。
- 初始 ahead/behind：`0/0`。
- 初始 tracked 工作区：clean。
- 初始生产版本：`v10.5.25`。
- 最近成功 Pages：run `31249269930`，commit `0ec07fc2e436e69b5cf8ce5562e2c412456501c8`。
- Gate：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=enabled`。

## Business-model expansion declaration

- 新业务表：`none`。
- 新业务列：`none`。
- enum/status：`none`。
- 日期、月份、归属：`none`。
- identity/source/snapshot/version/writable fact：`none`。
- 既有字段语义、可变性、reader/writer authority、锁：`none`。
- 权威来源切换、legacy fallback、双读、双写：`none`。
- 历史重解释或 destructive schema：`none`。
- 本轮为前端布局和查询触发边界修复，无需业务模型扩展审批。

## 修改前问题

生产 `v10.5.25` 实测：

- 2560px 表单高 168px、筛选卡高 247.5px；学生、老师、账户、币种均约 390.80px，筛选控件分为两行。
- checkbox 仍附属在学生字段下方；查询/重置间距仅 8px，按钮紧贴右边。
- 年/月 change 直接执行查询；include inactive change 也直接调用既有 `applyQuery()`，提前写 `include_inactive=1` 并产生 1 次支出 reader GET 和 1 次候选 resolver POST。
- checkbox 前后虽保持 15 行，但列表被重新渲染，DOM 长度从 23387 变为 23732，不符合草稿边界及批量选择保持合同。
- loading 文案位于列表区，存在推动下方内容的结构风险。

## 实现

### 布局

- `expense.html` 将 checkbox 拆为紧随学生字段的独立区域，并增加页面专属 flex/right spacer。
- `css/app.css` 新增只作用于 `.expense-filter-panel` 的网格：`196 / 300 / 176 / 300 / 300 / 300 / flex / actions / 140px`，gap 12px。
- 查询/重置固定 `96×42px`，间距 12px；宽屏重置右侧至 form 边界为 152px。
- 1799px 以下取消宽屏右留白并改为两行；1279px 以下可继续合理换行；767px 以下单列，按钮使用两等列。
- 加载状态移到筛选标题的固定 20px `aria-live` 状态槽，filter panel 使用 `aria-busy`。

### 显式查询边界

- 新增 `draftFilters` 与 `appliedFilters`。
- 年、月、学生、老师、账户、币种 change 只更新 draft。
- include inactive 只调用 `fetchStudentMonthCandidates()`；不调用支出 reader，不重渲染列表、不清理批量选择、不重算 Cash 数量、不同步 URL。
- 候选请求使用 `topStudentCandidateRequestSequence`，旧响应不能覆盖最新勾选状态。
- 点击查询时防重复提交，`fetchExpenseRecords()` 精确调用一次；候选 scope 有变化时最多补一次 resolver，成功后再同步 applied URL、导航和列表。
- 查询失败保留此前 applied URL/列表；业务写操作后的列表刷新也固定使用 applied 条件，不会把未查询 draft 间接应用。
- 重置恢复东京当前月默认值，并各调用一次候选 resolver 和支出 reader。
- 支出快照继续读取既有 payment request/attachment 辅助事实；支出/Cash API、状态、金额、writer 和两动作合同均未改变。

## 修改文件

- `expense.html`
- `css/app.css`
- `js/pages/expense-page.js`
- `js/expense-app.js`
- `js/config.js`
- `scripts/expense-filter-layout-static-test.mjs`
- 6 份既有布局/B5 测试只更新全局版本断言至 `v10.5.26`：income、lesson、settlement、wage、wage-rule、B5。
- 本报告和 `docs/current-status.md`。

## 测试

通过：

- `node --check`：expense page/app。
- `scripts/expense-filter-layout-static-test.mjs`。
- Cash expense create/save-submit split、B4-Finance、B5、income/settlement/wage/wage-rule/lesson layout。
- P0 admin/Cash、tuition Cash hardening、B3 writer authority、B4-Wage/B4-Lesson/B4-Remaining。
- BE-UI、BE blocker、BE P0 permission、expense P0 permission Phase 1/2。
- `git diff --check`。
- 全部 page module 直接 `.rpc()` / direct DML 扫描为 0。
- 浏览器代码 service-role marker 扫描为 0。

未执行数据库部署 SQL、DDL/DML 或写 RPC。

## 生产 Chrome 无写验收

### 2560×1440

- filter form：`2210×66px`；filter panel：`2248×142px`。
- 年月组合列：196px。
- 学生/老师/账户/币种 `getBoundingClientRect().width`：`300 / 300 / 300 / 300px`。
- checkbox：`16×16px`；独立区域 176px，紧随学生。
- 查询/重置：均 `96×42px`；间距 12px；重置右侧至 form 边界 152px。
- 全部控件底边一致，严格单行。
- document scrollWidth = viewport width = 2560。

### 1440×900

- form 高 144px、筛选卡高 220px，自动两行。
- 第一行为月份 196px、学生 341px、checkbox 176px、老师 341px；第二行为账户 196px、币种 341px及按钮组。
- 宽屏 right spacer 为 `display:none`，没有固定右留白或整体横向溢出。
- 查询/重置仍 `96×42px`、间距 12px。

### 390×844

- 月份、学生、老师、账户、币种均为 346px 单列。
- checkbox 区域 346×42px 并紧随学生，checkbox 16×16px。
- 查询/重置各 `167×42px`，同一行，间距 12px。
- document/body scrollWidth 均为 390，无整体横向溢出。

### 查询与候选调用矩阵

| 操作 | 候选 resolver | 支出 reader | URL/列表/Cash |
|---|---:|---:|---|
| 连续修改月、学生、老师、账户、币种 | 0 | 0 | URL、15行DOM、Cash数量不变 |
| include inactive 单次变化 | 1 POST | 0 | URL、列表DOM、Cash数量不变 |
| include inactive 快速勾选/取消 | 每次变化各1 POST | 0 | 最终状态为最新操作，旧响应未覆盖 |
| 显式查询，候选 scope 已新鲜 | 0 | 1 GET | 成功后一次应用 URL 和列表 |
| 重置 | 1 POST | 1 GET | 清理可选 URL 并回到 2026-08 默认 |

CDP 中每个跨域 reader/resolver 另有 1 个 `OPTIONS` 预检；上表统计实际 resolver POST / reader GET 调用。

普通筛选前后 15 行的 HTML 长度均为 23387、文本 hash 均为 3444133818；checkbox 候选请求前/中/后列表 panel、thead、首行 Y 均固定为 `306 / 415 / 458.5px`，中间态为 `aria-busy=true`，完成后恢复 false。生产当前全部月份可提交 Cash 行均为 0，无法在不制造测试财务数据的前提下形成批量勾选样本；代码路径不调用列表渲染/选择清理，且 DOM 与按钮数量实测保持不变。Console error=0，warning=0。

### 学生月份候选、支出与 Cash 事实

- 2026-06：默认 8 名学生（含“全部学生”共 9 option），页面全部支出 15 条，其中老师工资 10 条。
- 2026-07：默认 7 名（共 8 option）；include inactive 后 8 名（共 9 option），厦门吕同学标记“本月暂停”；页面全部支出 1 条，checkbox 前后 DOM 签名不变。
- 2026-08：默认 7 名（共 8 option）；include inactive 后 8 名（共 9 option），paused 标签正确；页面全部支出 2 条，checkbox 前后 DOM 签名不变。
- 2026-07 在 `include_inactive=false` 下可由 URL 恢复厦门吕同学 selected override，选中值及“本月暂停”标签正确。
- 当前 47 条生产支出均无 `student_id`；6/7/8 月无学生关联数量分别为 15/1/2，因此没有真实 paused/left 关联支出的正样本。本轮没有修改 reader、record-ID lookup 或历史行，全部学生状态不会裁剪上述无学生关联、老师工资、教室和普通支出。
- 6月 UI 显示既有已支付、已取消、Cash已确认、Cash已拒绝、Cash未提交等状态；School 直接支付与 Cash 待审批文案及“保存后单独提交 Cash”合同均存在。
- 页面未出现“业务归属”“个人名义”或 `business_entity_id` 用户 UI。
- 未点击新增保存、School支付、保存待支付、Cash提交、reverse、附件或报销入口。

## 只读数据指纹（前后完全一致）

| 对象 | 数量 | hash/金额 |
|---|---:|---|
| expense | 47 | id `4d6db9c04885842fb70f48901719d6b8`；row `141c76e4cf6148007e182704941a0c4a`；JPY 2,890,406 / CNY 0 |
| 2026-06 expense | 15 | `85064122165fea6a650f93e6c9808b6e`；JPY 1,349,476 |
| 2026-07 expense | 1 | `4faf3130adb694cc9a4c7aa212653f1d`；JPY 243,000 |
| 2026-08 expense | 2 | `55fa6a3df85820f4d929a50c25d9893d`；JPY 405,983 |
| accounts / transactions | 3 / 187 | `443b3170f50bc23a56834d398069c565 / 21694ff060e23289566f0a6e9fe3e449` |
| School payment requests | 51 | `75f06bc98ad541c77f2ce9c6d7a7978d` |
| School Cash linkage events | 0 | empty hash |
| Cash requests | 43 | `38af234da847c517d548c7b6337a40a1` |
| Cash CNY / JPY transactions | 74 / 31 | `97d2cb2955477319b27664daa9af0b42 / 3f3f257b14b43c12925a8eecb7a8ca02` |
| Storage objects / orphan | 57 / 30 | `c2852a4dbcd13b9cddb1da0b1115b18f` |

Gate 前后均为 `student_tuition_cash_submit=enabled / student_tuition_generate=blocked / student_tuition_preview=enabled`，无变化。

## 安全与写入

- 数据库部署 SQL：0。
- DDL/DML：0。
- 写 RPC：0。
- School/Cash/Storage 真实业务写入：0。
- fixture及持久残留：0。
- Gate变化：0。
- 浏览器写入口点击：0。

## 受保护 untracked 文件

六份文件始终未修改、移动、删除、暂存或提交：

- `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` — tuition candidate CSV。
- `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` — R1B git diff txt。
- `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` — reader fragment。
- `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` — registration fragment。
- `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` — schema fragment。
- `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` — writer fragment。

现场无第七份非本任务 untracked 文件。
