# School V2 老师工资结算筛选栏单行布局优化实施报告

日期：2026-08-08（Asia/Tokyo）

## 结论

老师工资结算页顶部“结算类型”筛选已完整退役，页面版本由 `v10.5.21` 前进至 `v10.5.22`。月份、老师、学生、包含暂停/离校学生、状态、关键词、查询和重置全部保留；删除后默认结果与原“结算类型=全部”一致。工资快照/明细中的 `settlement_type`、表格及详情展示、关键词匹配和稳定排序全部保留，工资生成、作废、支付请求、导出、Cash及状态机未改变。

实现提交为 `5afc58be14b9d99853716bec41cca2e1be70dc38`，Pages run `31198977078` 成功，部署 commit 与实现提交一致。生产 Chrome 已确认 `v10.5.22`。

## 实时基线与工作区保护

- 初始分支：`main`。
- 初始 `HEAD` / `origin/main`：`ab7ea5be747211e3ee04ea17441b18d7dee06871`，ahead/behind `0/0`。
- 开始时没有 tracked 修改；仅存在六份既有受保护 untracked 文件。
- 未执行 reset、rebase、checkout 或回退。
- 初始生产页面：`v10.5.21`；最近 Pages run `31196366455` success，部署 commit `ab7ea5be747211e3ee04ea17441b18d7dee06871`。
- 业务模型扩展声明：表、字段、结算类型事实、权威来源、reader/writer、ACL/RLS 均为 `none`。

六份受保护文件开始、实现部署后哈希一致，且从未暂存：

| 文件 | SHA-256 |
| --- | --- |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 结算类型筛选退役

代码与 Git 历史确认，工资主页面实际使用的类型 URL 参数只有 camelCase `settlementType`；底层字段继续为 `settlement_type`。本轮同时把 snake_case `settlement_type` 作为旧链接兼容参数清理，没有添加无证据的 `wageType/wage_type` 猜测别名。

已从工资主页面删除：

- “结算类型”标签和 `wageSettlementTypeSelect` DOM。
- `DEFAULT_FILTERS.settlementType`、DOM cache、读取、恢复与数据选项生成。
- `filterWageLocks` 的 `row.settlement_type` 本地过滤条件。
- URL 读取和写回的 `settlementType`。
- 已无用途的类型下拉 option renderer。

页面初始化时在读取筛选前检查 `settlementType` 与 `settlement_type`，存在时循环删除全部命中参数并只调用一次 `history.replaceState`。生产旧链接同时包含两种参数时，两者均被清除；`year/month/teacherId/student_id/include_inactive/status/keyword` 全部保留，没有刷新循环。

API/reader 原本没有结算类型筛选参数，因此无需改 API 签名或传隐藏空值。`settlement_type` 仍用于工资快照表格/详情展示、关键词检索和稳定排序，数据库事实没有删除或改名。

## 局部单行布局

`wage.html` 只为工资筛选 form 和字段增加局部 class；include inactive checkbox 从学生字段内部移为紧跟学生的独立 grid item。`css/app.css` 新规则全部限定于 `.wage-filter-panel .wage-filter-grid` 或工资专用 class。

2560px 列合同为：

`196px / 300px / 300px / 176px / 300px / 300px / 弹性间隔 / 按钮区 / 140px`

字段顺序为月份、老师、学生、checkbox、状态、关键词、弹性间隔、查询/重置、右侧留白。常规 gap 和按钮 gap 均为 12px；没有绝对定位，也没有修改课时管理、学生月结、工资规则或其他页面布局规则。

## 静态与语法回归

以下检查全部通过：

- `node --check`：`js/pages/wage-page.js`、`js/wage-app.js`、`js/api/wage-api.js`。
- 新增 `wage-filter-layout-static-test.mjs`。
- `student-status-phase-b4-wage-student-filter-static-test.mjs`。
- `student-status-phase-b4-remaining-static-test.mjs`。
- `student-status-phase-b2/b3/b4-finance/b4-lesson/b5` 相关测试。
- `business-entity-ui-closure`、`business-entity-p0-permission`、系统 blocker 展示测试。
- 已上线的 lesson/settlement filter layout 回归。

静态结果：筛选 form 无类型 DOM；无类型 page state、URL读写或隐藏本地过滤；四个目标框共享同一 `300px` 列合同；page-layer直接RPC/DML为0；浏览器service-role为0；`js/legacy-core.js`未修改。

## 生产 Chrome 无写验收

### 2560×1440

- 筛选 form 宽 `2210px`、高 `66px`，卡片高 `139.5px`，严格单行。
- 月份 `196px`。
- 老师 `300px`、学生 `300px`、状态 `300px`、关键词 `300px`；四者 `getBoundingClientRect().width` 完全一致，无亚像素差异。
- checkbox 区 `176px`，紧跟学生；checkbox 本体位于输入控制行中部。
- 查询/重置均为 `96×42px`，间距 `12px`；按钮组 `204px`。
- 按钮组右侧为 `12px + 140px = 152px` 留白。
- 全部 select/input/button 控制行底边均为 `y=305.5`；document/body横向溢出均为0。

### 1440×900

- form 宽 `1090px`、高 `144px`，自动两行。
- 首行月份 `196px`、老师 `341px`、学生 `341px`、checkbox `176px`；第二行状态 `196px`、关键词 `341px`，按钮组在右侧。
- 固定右侧留白自动取消；document/body横向溢出均为0。

### 390×844

- 内容宽 `346px` 单列；月份、老师、学生、checkbox、状态、关键词、按钮顺序正确。
- checkbox 与学生字段间距 `12px`。
- 查询/重置各 `167×44px`，间距 `12px`。
- document/body横向溢出均为0；Console error `0`、warning `0`。

### 业务与URL回归

- 修改前 `v10.5.21` 与部署后 `v10.5.22` 的2026-06“全部类型/全部学生”均为9个有效工资快照、63课时、7530分钟、合计JPY563,845；候选均为63条/7530分钟/125.5小时/6名老师。
- 工资快照表格继续显示9个“日元时给”结算类型标签，类型字段没有从业务展示移除。
- 王亚楠 + 厦门吕同学 + locked + 关键词“厦门”联合查询得到唯一1个历史工资快照：10课时、1200分钟、JPY104,000；候选为10条/1200分钟。
- 厦门吕同学对应工资详情 `9918610d-a0f8-4c52-965c-8e60d214c4ca` 正常显示老师、学生、日元时给及10条冻结明细，paused历史事实和record-ID lookup未丢失。
- 2026-07默认7名active候选；include inactive后8名，`厦门吕同学｜本月暂停`正确；关闭include inactive后selected override仍保留paused学生。
- “全部学生”时不裁剪工资快照或候选课时；状态默认仍不显示void记录，locked显式筛选保持。
- 重置恢复东京当前月2026-08、全部老师/学生、默认状态、空关键词和未勾include inactive；查询、切月、刷新均正常。
- `generateTeacherMonthlyWage` 调用仍只传月份和老师，不传学生或退役类型；生成范围函数仍只按老师过滤，当前学生筛选只影响可见候选，不改变完整内部生成范围。
- 未恢复业务归属、个人名义或 `business_entity_id` UI。
- 全程未点击生成工资、作废、支付请求、导出或任何写入口。

## 生产只读指纹与边界

部署前后以下数量与完整行指纹完全一致：

| 对象 | 数量 | MD5 |
| --- | ---: | --- |
| wage locks | 95 | `8474b2adcc3ed39059efd7237da90168` |
| wage details | 556 | `0b2976f8005835d66b2db25b0b3c1939` |
| 2026-06 candidate lessons | 63 / 7530分钟 | `d8360df367faf81e9eaf02304b72e24b` |
| income | 55 | `eb40e1ea59767e4299cd23b332f57d2a` |
| expenses | 47 | `141c76e4cf6148007e182704941a0c4a` |
| accounts | 3 | `443b3170f50bc23a56834d398069c565` |
| account transactions | 187 | `21694ff060e23289566f0a6e9fe3e449` |
| School payment requests | 51 | `75f06bc98ad541c77f2ce9c6d7a7978d` |
| Storage objects / orphan | 57 / 30 | `c2852a4dbcd13b9cddb1da0b1115b18f` |
| Cash requests | 43 | `38af234da847c517d548c7b6337a40a1` |
| Cash CNY transactions | 74 | `97d2cb2955477319b27664daa9af0b42` |
| Cash JPY transactions | 31 | `3f3f257b14b43c12925a8eecb7a8ca02` |

Gate 前后均为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`。

- 数据库部署SQL：0；DDL/DML：0；写RPC：0。
- 为部署前后指纹复核，临时只读脚本 `/private/tmp/school_v2_wage_filter_layout_baseline_readonly_20260808.sql` 与 `/private/tmp/school_v2_wage_filter_layout_cash_baseline_readonly_20260808.sql` 各执行两次，均为 `BEGIN READ ONLY ... ROLLBACK`。
- School、Cash、Storage及真实业务写入：0；fixture：0；测试record ID：无。
- 未修改工资reader/writer、数据库函数/schema/ACL/RLS、学生状态resolver、Gate、Cash或Storage。

本轮到此停止，只完成老师工资结算页，不修改工资规则或其他页面。
