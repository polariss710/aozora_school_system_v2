# School V2 学生月度结算筛选栏单行布局优化实施报告

日期：2026-08-08（Asia/Tokyo）

## 结论

学生月度结算页顶部筛选栏已完成局部单行布局优化并生产上线，页面版本由 `v10.5.20` 前进至 `v10.5.21`。月份、学生、包含暂停/离校学生、结算状态、关键词、查询和重置全部保留，筛选语义、URL 合同、学生月份候选、selected override、月结 reader、历史详情及全部财务 writer 均未改变。

实现提交为 `4448cf596c25d0f06994028b0495968b189b3f1b`，Pages run `31195489763` 成功，部署 commit 与实现提交一致。生产 Chrome 已确认 `v10.5.21`。

## 实时基线与工作区保护

- 初始分支：`main`。
- 初始 `HEAD` / `origin/main`：`e95ec48828ac6ec474973eeaa450d989b89c2fb4`，ahead/behind `0/0`。
- 开始时没有 tracked 修改；仅存在六份既有受保护 untracked 文件，没有覆盖、丢弃或擅自纳入其他任务修改。
- 未执行 reset、rebase、checkout 或回退。
- 初始生产页面：`v10.5.20`；最近 Pages run `31183560451` success，部署 commit `e95ec48828ac6ec474973eeaa450d989b89c2fb4`。
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

- `settlement.html`：只为目标筛选 form 和七个布局区域增加 settlement 局部 class；将 include inactive checkbox 从学生字段内部移为紧跟学生的独立 grid item；筛选 DOM 顺序保持为月份、学生、checkbox、结算状态、关键词、弹性间隔、查询/重置、右侧留白。
- `css/app.css`：新增严格限定在 `.settlement-filter-grid` 的布局规则。宽屏列为 `196px / 300px / 176px / 300px / 300px / 弹性间隔 / 按钮区 / 140px`，统一 gap 12px；1440px 档自动换行；390px 档单列，checkbox 紧跟学生，按钮两列。
- `js/config.js`：页面版本前进至 `v10.5.21`。
- `js/settlement-app.js` 与页面静态资源 query key：仅更新版本化缓存键。
- 新增 `scripts/settlement-filter-layout-static-test.mjs`，并同步更新受页面版本影响的既有精确断言。

未修改 `js/pages/settlement-page.js`、`js/api/settlement-api.js` 或任何业务 reader/writer；筛选状态、URL 参数、查询、切月、刷新和重置逻辑保持原样。页面模块没有新增直接 `.rpc()` 或表 DML；`js/legacy-core.js` 未修改；浏览器代码没有 service-role。

## 测试

以下静态、语法及回归全部通过：

- `node --check`：`js/settlement-app.js`、`js/pages/settlement-page.js`、`js/api/settlement-api.js`。
- `settlement-filter-layout-static-test.mjs`。
- `settlement-p0f-dialog-preview-static-test.mjs`。
- `settlement-business-error-static-test.mjs`。
- `settlement-p0b2-adjustment-static-test.mjs`。
- `settlement-trusted-tool-static-test.mjs`。
- `student-status-phase-b4-finance-static-test.mjs`。
- `student-status-phase-b5-static-test.mjs`。
- `tuition-p0e-static-test.mjs`。
- `lesson-filter-layout-static-test.mjs` 与 B4-Lesson candidate 回归。

静态扫描确认：月结筛选项完整；checkbox 已是独立布局区域；CSS 规则只作用于 settlement 局部 class；page-layer 直接 RPC/DML 为 0；浏览器 service-role 为 0。

## 生产 Chrome 无写验收

### 布局实测

- 2560×1440：form 宽 2210px、高 66px，全部筛选控件严格一行且底边均为 `y=371.5`。字段宽度依次为月份 `196px`、学生 `300px`、checkbox 区 `176px`、结算状态 `300px`、关键词 `300px`。查询/重置均为 `96×42px`，间距 `12px`；按钮组宽 `204px`，其右侧为 `12px + 140px = 152px` 留白。document 横向溢出 0。
- 1440×900：form 宽 1090px、高 144px，自动分成两行；首行月份 `196px`、学生 `341px`、checkbox `176px`、结算状态 `341px`，第二行关键词 `549px`，按钮组在右侧；大屏右侧留白自动取消。document 横向溢出 0。
- 390×844：内容宽 `346px` 单列；顺序为月份、学生、checkbox、结算状态、关键词、按钮，checkbox 与学生间距 `12px`；查询/重置各 `167×44px`，间距 `12px`。document/body 横向溢出均为 0。

筛选卡以外的提示栏、统计/记录区域、表格、列宽、金额、状态和操作按钮没有修改。

### 筛选、URL 与历史数据

- 2026-06 “全部学生”仍显示 5 条月结记录；学生候选 8 名。
- 结算状态 `locked` 查询返回 3 条且三条均为已锁定；再与关键词“李天伦”联合查询返回唯一 1 条，URL 正确保存 `status` 与 `keyword`。
- 2026-07 默认 7 名 active 候选；include inactive 后为 8 名，`厦门吕同学｜本月暂停` 标签正确；“全部学生”记录仍为 7 条，没有被候选状态裁剪。
- 2026-08 默认 7 名，include inactive 后 8 名且 paused 标签正确；“全部学生”仍为 7 条。
- `student_id=cff85c52-...` 在 2026-07 且不勾 include inactive 时通过 selected override 保留 paused 学生；`year/month/student_id/view` 均从 URL 正确恢复。
- 重置恢复东京当前月 2026-08、全部学生、全部状态、空关键词及未勾 include inactive；切月、刷新和查询均正常。
- 历史 paused 学生厦门吕同学的 2026-06 月结 `dd1a599e-a4f1-4656-ad3a-33dcdc0004f7` 详情页正常显示姓名、月份与只读状态，record-ID lookup 未经过当前 active 候选裁剪。
- Console error `0`、warning `0`；全程没有点击或调用预览、保存、锁定、解锁、调整、生成账单或其他写入口。

## 数据、Gate 与发布边界

- 部署前后 `school_student_monthly_settlements` 均为 18 行；标准完整行指纹 `md5(string_agg(md5(to_jsonb(row)::text),'|' order by id))` 均为 `549324c1ff7a45afe266b255f488b5bb`。
- 月份数量保持：2026-02 `1`、03 `1`、04 `3`、05 `5`、06 `5`、07 `3`。
- Gate 前后均为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`。
- SQL 文件执行：0；DDL/DML：0；写 RPC 调用：0；测试 fixture：0；测试 record ID：无。
- 只执行 School DB 只读 `SELECT` 和页面既有 reader；School、Cash、Storage 及真实业务数据写入均为 0。
- 未修改数据库 schema、RPC、ACL、RLS、Gate、Cash、Storage、业务归属或其他页面。

本轮到此停止，只完成月度结算页面筛选栏优化。
