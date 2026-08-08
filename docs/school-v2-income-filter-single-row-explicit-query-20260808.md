# School V2 收入记录筛选栏单行布局与显式查询边界实施报告

日期：2026-08-08（Asia/Tokyo）

## 结论

收入记录页已完成单页优化并部署生产：页面版本由 `v10.5.24` 前进至 `v10.5.25`，实现提交为 `22726296d01ada155bdce552f83e668e37904689`，Pages run `31249004631` 成功且部署 commit 一致。

2560px 下筛选栏为严格单行，学生、账户、分类、币种均精确 300px；1440px 自动两行；390px 单列且查询/重置并排。筛选状态现分为 draft/applied：普通筛选变化不查询、不改 URL，include inactive 只刷新学生候选且有请求序号保护，显式查询才调用一次收入 reader 并原子应用 URL/列表，重置各调用一次候选和收入 reader。

本轮未修改任何 reader/writer、数据库对象、ACL/RLS、Gate、Cash、Storage 或真实业务数据。

## 实时基线

- 分支：`main`。
- 初始 HEAD：`dc347d2f140e5e736ab2f52e381de263a7a7ee86`。
- 初始 `origin/main`：`dc347d2f140e5e736ab2f52e381de263a7a7ee86`。
- 初始 ahead/behind：`0/0`。
- 初始 tracked 工作区：clean。
- 初始生产版本：`v10.5.24`。
- 最近成功 Pages：run `31231593853`，commit `dc347d2f140e5e736ab2f52e381de263a7a7ee86`。
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

生产 `v10.5.24` 实测：

- 2560px 表单高 168px，筛选卡高 247.5px；学生、账户、分类、币种宽约 `498.84 / 498.84 / 453.50 / 362.81px`，控件分为两行。
- checkbox 仍附属在学生字段下方。
- 年/月 change 直接调用 `applyQuery()`，立即改 URL，并调用收入 reader 与候选 resolver。
- include inactive change 同样直接调用 `applyQuery()`：立即写 `include_inactive=1`，并调用收入 reader，不符合“只更新候选”的合同。
- loading 文案位于列表区，存在推动下方内容的结构风险。

## 实现

### 布局

- `income.html` 将 checkbox 拆为紧随学生字段的独立区域，并增加页面专属 flex/right spacer。
- `css/app.css` 新增只作用于 `.income-filter-panel` 的网格：`196 / 300 / 176 / 300 / 300 / 300 / flex / actions / 140px`，gap 12px。
- 查询/重置固定 `96×42px`，间距 12px；宽屏重置右侧至 form 边界为 152px。
- 1799px 以下取消宽屏右留白并改为两行；1279px 以下可继续合理换行；767px 以下单列，按钮使用两等列。
- 加载状态移到筛选标题的固定 20px `aria-live` 状态槽，filter panel 使用 `aria-busy`。

### 显式查询边界

- 新增 `draftFilters` 与 `appliedFilters`。
- 年、月、学生、账户、分类、币种 change 只更新 draft。
- include inactive 只调用 `fetchStudentMonthCandidates()`；不调用 `fetchIncomeRecords()`，不重渲染列表，不同步 URL。
- 候选请求使用 `topStudentCandidateRequestSequence`，旧响应不能覆盖最新勾选状态。
- 点击查询时防重复提交，`fetchIncomeRecords()` 精确调用一次；候选 scope 有变化时最多补一次 resolver，成功后再同步 applied URL、导航和列表。
- 查询失败保留此前 applied URL/列表。
- 重置恢复东京当前月默认值，并各调用一次候选 resolver 和收入 reader。
- 列表刷新后的业务行仍只由既有 `filterIncomeRecords()` 过滤；reader/API、金额、状态和 Cash 合同未改。

## 修改文件

- `income.html`
- `css/app.css`
- `js/pages/income-page.js`
- `js/income-app.js`
- `js/config.js`
- `scripts/income-filter-layout-static-test.mjs`
- 5份既有布局/B5测试只更新全局版本断言至 `v10.5.25`：lesson、settlement、wage、wage-rule、B5。
- 本报告和 `docs/current-status.md`。

## 测试

通过：

- `node --check`：income page/app/config。
- `scripts/income-filter-layout-static-test.mjs`。
- B4-Finance、B5、settlement/wage/wage-rule/lesson layout。
- P0 admin/Cash、tuition Cash hardening、Cash expense、B3 writer authority、B4-Wage/B4-Lesson/B4-Remaining。
- BE-UI、BE blocker、BE P0 permission。
- `git diff --check`。
- 全部 page module 直接 `.rpc()` / direct DML 扫描为 0。
- 浏览器代码 service-role marker 扫描为 0。

未执行 SQL 部署、DDL/DML 或写 RPC。

## 生产 Chrome 无写验收

### 2560×1440

- filter form：`2210×66px`；filter panel：`2248×142px`。
- 年月组合列：196px。
- 学生/账户/分类/币种 `getBoundingClientRect().width`：`300 / 300 / 300 / 300px`。
- checkbox：`16×16px`；独立区域 176px，紧随学生。
- 查询/重置：均 `96×42px`；间距 12px；重置右侧至 form 边界 152px。
- 控件底边均为 271px；严格单行。
- document scrollWidth = viewport width = 2560。

### 1440×900

- form `1090×144px`，自动两行。
- 学生/账户/币种在可用列中为 341px，分类列为196px；没有强制 300px 导致溢出。
- 宽屏 right spacer 隐藏，按钮右侧固定留白为 0。
- 查询/重置仍 `96×42px`、间距12px。
- document scrollWidth = viewport width = 1440。

### 390×844

- 学生/账户/分类/币种均为346px单列。
- checkbox区域346×42px并紧随学生，checkbox 16×16px。
- 查询/重置各167×42px，同一行，间距12px。
- document/body scrollWidth均为390，无整体横向溢出。

### 查询与候选调用矩阵

| 操作 | 候选resolver | 收入reader | URL/列表 |
|---|---:|---:|---|
| 连续修改月、学生、账户、分类、币种 | 0 | 0 | URL和既有10行不变 |
| include inactive单次变化 | 1 POST | 0 | URL和列表不变 |
| include inactive快速取消/勾选 | 每次变化各1 POST | 0 | 最终状态为最新勾选，旧响应未覆盖 |
| 显式查询，候选scope已新鲜 | 0 | 1 GET | 成功后一次应用URL和列表 |
| 显式查询，候选scope已变化 | 1 POST | 1 GET | 成功后一次应用URL和列表 |
| 重置 | 1 POST | 1 GET | 清理可选URL并回到2026-08默认 |

CDP中同一跨域请求可能另有一个 `OPTIONS` 预检；上表统计实际 resolver POST / reader GET 调用。

checkbox候选请求前/中/后列表 panel、thead、首行 Y 均固定为 `306 / 415 / 458.5px`。Console error=0，warning=0。

### 学生月份候选与历史事实

- 2026-06：默认8名学生（含“全部学生”共9 option），页面全部收入10条。
- 2026-07：默认7名（共8 option）；include inactive 后8名（共9 option），厦门吕同学标记“本月暂停”；页面既有 operational reader 全部收入8条。
- 2026-08：默认7名（共8 option）；include inactive 后8名（共9 option），paused标签正确；页面全部收入12条。
- 2026-07 取消 include inactive 后，已选厦门吕同学仍以 selected override 保留，共9 option；URL恢复也能在 `include_inactive=false` 下保留选中值和paused标签。
- 2026-06 selected override 可查看厦门吕同学历史学费收入1条（CNY 7,740）；“全部学生”恢复10条，外部授课等无学生关联行未被候选裁剪。
- 新增收入、学费应收预览入口保持可用；无可提交行时批量提交Cash继续disabled。未点击保存、生成、到账、取消、reverse、收据或Cash提交。

## 只读数据指纹（前后完全一致）

| 对象 | 数量 | hash/金额 |
|---|---:|---|
| income | 55 | row `eb40e1ea59767e4299cd23b332f57d2a`；JPY 9,667,830 / CNY 36,396 |
| 2026-06 raw income | 10 | id `5e854f00811c409f14753696bbce7b42` |
| 2026-07 raw income | 9 | id `54e612f031d294bedf3541d7cffdbe65` |
| 2026-08 raw income | 12 | id `b2c2c26a7de8c9e53a0290ee0dd3696f` |
| tuition bills | 22 | `d079f068c0fa19fc07d4dcd94094fae2` |
| tuition identity/revision/void | 15 / 20 / 5 | `65c7ad… / 5076f7… / 87e8c1…` |
| accounts / transactions | 3 / 187 | `443b31… / 21694f…` |
| School payment requests | 51 | `75f06bc98ad541c77f2ce9c6d7a7978d` |
| School Cash linkage events | 0 | empty hash |
| Cash requests | 43 | `38af234da847c517d548c7b6337a40a1` |
| Cash CNY / JPY transactions | 74 / 31 | `97d2cb… / 3f3f25…` |
| Storage objects / orphan | 57 / 30 | `c2852a4dbcd13b9cddb1da0b1115b18f` |

2026-07 raw表9条而页面既有 operational reader 显示8条是部署前已存在的 reader合同差异；本轮前后两者各自保持不变，不是学生状态裁剪或数据漂移。

## 安全与写入

- 数据库部署SQL：0。
- DDL/DML：0。
- 写RPC：0。
- School/Cash/Storage真实业务写入：0。
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
