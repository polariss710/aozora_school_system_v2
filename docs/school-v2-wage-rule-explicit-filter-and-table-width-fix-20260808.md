# School V2 工资规则显式查询、稳定加载与表格宽度修复报告

日期：2026-08-08（Asia/Tokyo）

## 结论

工资规则页已完成本地最小修复，页面版本由 `v10.5.23` 前进至 `v10.5.24`。筛选控件现明确分为 draft 与 applied 两份状态；只有显式点击“查询”或 Enter 提交才更新规则结果和合法 URL 条件。include inactive 变化只重读学生候选，并以请求序号阻止旧响应覆盖新状态。

异步提示已从规则列表区域移至筛选卡标题的固定高度状态槽；规则表增加18列专属 `colgroup`，宽度由1880px扩展为卡片内部完整2210px；规则列表数量/新增按钮组在宽屏向左留出153px。

实现提交 `11b3118e9590bd457486cf56adbaf28d3f70e4fb` 已推送，Pages run `31231194573` 成功且部署commit一致。生产 `v10.5.24` 的筛选请求边界、7/8名候选、selected override、稳定Y坐标、18列、三档响应式、弹窗/详情、Console及部署后只读指纹全部通过。

## 实时基线与保护

- 初始分支：`main`。
- 初始 `HEAD` / `origin/main`：`a080a04adeaf269e8a3249ddc3de34ac03a382e9`，ahead/behind `0/0`。
- 初始生产版本：`v10.5.23`；最近 Pages run `31202766852` success，部署commit为 `a080a04adeaf269e8a3249ddc3de34ac03a382e9`。
- 开始时没有 tracked 修改，只有六份既有受保护 untracked 文件；没有 reset、rebase、checkout 或回退。

六份受保护文件开始哈希如下，均未修改或暂存：

| 文件 | SHA-256 |
| --- | --- |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## Business-model expansion declaration

```text
New tables: none
New columns: none
New enum/status values: none
New date/month/attribution concepts: none
New identity concepts: none
New source concepts: none
New snapshot/version concepts: none
New writable facts: none
Changed existing-field semantics: none
Changed field mutability: none
Changed writer or reader authority: none
Changed locking rules: none
New authoritative sources: none
Legacy fallbacks or dual-read rules: none
Dual-write behavior: none
Historical reinterpretation: none
Destructive schema changes: none

Approval reference: not required — no business-model expansion
```

本轮仅修改页面筛选交互、加载提示布局和表格列布局，不修改任何业务reader/writer、业务字段、数据权威或权限边界。

## 事件链根因

修改前实际链路为：

`include inactive change` → `refreshFilterCandidatesAndApply()` → `fetchWageRuleCurrentStudentCandidates()` → 重建学生option → `applyCurrentFilters()` → `readFilters()` → `syncCandidateUrl()` → `filterWageRules()` → `renderWageRules()`。

因此实际情况是：checkbox只调用1次学生候选resolver，并没有再次调用工资规则列表reader；但候选请求完成后错误地继续同步URL、按缓存规则重筛并重建tbody。查询submit也复用了同一函数，反而只刷新候选、不重新读取工资规则结果。表单不存在全局change自动提交，根因是checkbox和submit共用了范围过大的handler。

同时，`setLoading(true)`把 `#wageRuleLoadingState` 从 `display:none` 切换到规则列表标题与表格之间，生产2560px基线中造成表头及首行临时下移21px：

| 时点 | 规则卡顶部Y | 表头顶部Y | 首行顶部Y |
| --- | ---: | ---: | ---: |
| checkbox前 | 340.5 | 422.5 | 463 |
| 候选加载中 | 340.5 | 443.5 | 484 |
| 候选完成后 | 340.5 | 422.5 | 463 |

生产基线中卡片内部滚动区宽2210px，表格实际仅1880px；规则列表操作组右侧仅19px。

## draft / applied 与请求边界

- `draftFilters`保存老师、学生、include inactive、科目、启用状态及关键词的当前控件值。
- `appliedFilters`只在页面合法URL初始化、显式查询或显式重置并查询时更新。
- 老师/学生/科目/启用状态change及关键词input只调用 `updateDraftFiltersFromControls()`，不触发reader、URL或列表渲染。
- include inactive调用 `refreshDraftStudentCandidates()`；该函数只调用候选resolver、保留selected override并重建学生option，不包含 `fetchWageRules`、URL同步、规则过滤或tbody渲染。
- `candidateRequestSequence`使连续快速勾选/取消只有最新响应可以提交候选结果；旧响应直接丢弃。
- 显式查询先快照draft为applied并同步现有合法学生候选URL，再精确调用一次 `fetchWageRules()`；查询期间保留既有表格，成功后才一次渲染。查询失败时恢复上一份applied及URL。
- 重置沿用“重置并查询”合同，只由用户点击触发：恢复默认draft、刷新默认候选、再调用一次规则reader。
- 页面首次从现有合法 `student_id/include_inactive` URL初始化draft/applied，并查询一次；既有退役URL参数清理合同不变。

## 固定状态槽与表格布局

筛选标题行新增 `#wageRuleFilterStatus`：

- 固定高度20px，idle使用 `visibility:hidden` 保留空间。
- 候选加载显示“正在更新学生候选…”；规则查询显示“正在查询工资规则…”。
- 状态槽和筛选panel同步维护 `aria-live`、`aria-atomic` 与 `aria-busy`。
- 候选/查询错误也留在同一固定槽，不插入规则列表节点。
- 原规则列表加载节点已删除，查询期间不清空规则行。

表格改为 `width:100% / min-width:2210px / table-layout:fixed`，18列设计宽度总和精确2210px：

`76 / 76 / 104 / 145 / 105 / 88 / 175 / 165 / 96 / 120 / 120 / 90 / 105 / 105 / 90 / 260 / 145 / 145`

列顺序、字段内容、排序、金额格式及业务语义均未修改。规则列表标题在≥1800px时使用134px内容区右padding；加上卡片19px内边距，目标卡边右留白为153px，中等宽度自动归零。CSS均限定在 `.wage-rule-*` 及 `.app-shell--wage-rule`。

## 本地验证与已知基线测试

以下通过：

- JS syntax。
- wage-rule显式筛选/布局、B4-Remaining、B4-Wage学生候选、B3 writer authority、B5。
- 工资结算、月结、课时筛选布局及B4-Lesson候选。
- BE-UI、BE系统blocker和BE-P0权限防回退。
- page-layer直接RPC/DML为0；浏览器service-role为0；`js/legacy-core.js`未修改。

仓库既有 `p0-g1-a-auth-guard-static-test.mjs` 在本轮前后都会因它硬编码所有31个页面入口必须使用旧 `be-ui-20260806-1` cache key而失败；实时HEAD中的 `classroom-schedule.html` 已合法使用 `phase-b4-remaining-20260807-1`，故该失败与本轮无关。本轮没有扩大范围修改这一历史测试，工资规则入口仍保持 `auth-pending`、唯一 `requireGlobalSession()` 且在init前await。

## 部署前只读指纹

| 对象 | 数量/合计 | MD5 |
| --- | --- | --- |
| wage rules | 20条；启用18；JPY时薪78,400；CNY时薪0；汇率0.558028；交通/教室费0 | `2dc430ca4a58416235f2ba771b91b9f1` |
| wage rule ID集合 | 20 | `9097d343ec0eddbe9ea061679a3aff44` |
| wage locks | 95 | `8474b2adcc3ed39059efd7237da90168` |
| wage details | 556 | `0b2976f8005835d66b2db25b0b3c1939` |
| income / expenses | 55 / 47 | `eb40e1ea59767e4299cd23b332f57d2a` / `141c76e4cf6148007e182704941a0c4a` |
| accounts / account transactions | 3 / 187 | `443b3170f50bc23a56834d398069c565` / `21694ff060e23289566f0a6e9fe3e449` |
| School payment requests | 51 | `75f06bc98ad541c77f2ce9c6d7a7978d` |
| Storage objects / orphan | 57 / 30 | `c2852a4dbcd13b9cddb1da0b1115b18f` |
| Cash requests / CNY / JPY | 43 / 74 / 31 | `38af234da847c517d548c7b6337a40a1` / `97d2cb2955477319b27664daa9af0b42` / `3f3f257b14b43c12925a8eecb7a8ca02` |

Gate为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`。

- SQL、DDL/DML、业务RPC、写RPC：0。
- School、Cash、Storage及真实业务写入：0；fixture：0；测试record ID：无。
- 只执行School/Cash的 `BEGIN READ ONLY ... ROLLBACK` 指纹脚本。

## 生产 Chrome 无写验收

### 请求与显式查询矩阵

生产Chrome逐项修改控件，并以页面DOM/URL签名和一对一handler中的reader调用点共同核对：

| 操作 | 工资规则reader | 学生候选reader | 查询前行数/DOM | URL |
| --- | ---: | ---: | --- | --- |
| 老师 change | 0 | 0 | 20条，SHA-256 `af9c2333…1543`不变 | 不变 |
| 学生 change | 0 | 0 | 20条，同一签名 | 不变 |
| 科目 change | 0 | 0 | 20条，同一签名 | 不变 |
| 启用状态 change | 0 | 0 | 20条，同一签名 | 不变 |
| 关键词 input | 0 | 0 | 20条，同一签名 | 不变 |
| include inactive change | 0 | 1 | 20条、ID集合、内容和签名不变 | 不变 |
| 查询submit | 1 | 0 | 成功后按applied一次渲染 | 此时才写入 `student_id/include_inactive` |
| 重置 | 1 | 1 | 恢复20条 | 清回合法默认URL |

`fetchWageRules()`自身是对 `school_teacher_wage_rules` 的单次PostgREST SELECT；query handler中只有一个该调用点。普通change/input handler只有draft赋值，候选handler中只有一个resolver调用点且不存在规则reader、URL同步或tbody渲染。

Chrome先累积设置老师、学生、科目、inactive和关键词，查询前仍是20条及同一DOM签名；点击查询后URL才加入学生与include inactive，结果按组合条件变为0条。重置恢复默认控件、7名候选、20条规则与原URL。合法URL直接加载paused学生时，页面一次初始化为8名候选、选中“厦门吕同学｜本月暂停”并显示其2条历史规则。

### 候选、selected override与布局稳定性

- 默认候选7名；include inactive draft后8名，新增标签“厦门吕同学｜本月暂停”。
- 勾选时selected active学生保持；快速取消/再勾选最终严格服从最新checked=true、8名候选，旧响应没有覆盖。
- paused学生已applied且显示2条后，取消include inactive只刷新候选：URL仍保留旧applied的 `include_inactive=1`，2条行完全不变；候选仍以selected override保留paused学生。再次点击查询后仅移除URL的include参数，2条历史规则继续显示。
- 候选加载状态准确显示“正在更新学生候选…”，规则查询状态为“正在查询工资规则…”；idle时状态槽以visibility隐藏。

修复后checkbox前、加载中及加载后三项Y坐标完全一致：

| 时点 | 规则卡顶部Y | 表头顶部Y | 首行顶部Y |
| --- | ---: | ---: | ---: |
| checkbox前 | 274.5 | 356.5 | 397 |
| 候选加载中 | 274.5 | 356.5 | 397 |
| 候选完成后 | 274.5 | 356.5 | 397 |

加载提示不再出现在规则列表，候选/查询期间不先清空现有行。筛选标题状态槽实测高20px，panel/slot `aria-busy` 正常回到false/idle。

### 2560px表格与列表操作组

Chrome实际视口 `2560×1205`：

- 规则卡宽2248px，内部table-scroll宽2210px。
- 表格实际宽2210px，与内部可用宽精确一致；document/body均 `2560 / 2560`，无整体横向溢出。
- 规则列表数量/新增按钮组距卡片右边153px。
- 18列实测宽度依次为：

| 列 | 宽度px | 列 | 宽度px |
| --- | ---: | --- | ---: |
| 详情 | 76 | 编辑 | 76 |
| 停用/恢复 | 104 | 老师 | 145 |
| 老师分类 | 105 | 老师状态 | 88 |
| 学生 | 175 | 科目 | 165 |
| 结算类型 | 96 | 日元时薪 | 120 |
| 人民币时薪 | 120 | 汇率 | 90 |
| 交通费 | 105 | 教室费 | 105 |
| 启用状态 | 90 | 备注 | 260 |
| 创建时间 | 145 | 更新时间 | 145 |

合计2210px，全部18列、顺序、字段和币种/数值展示均保留。

### 1440与390px

- 1440 popup实际 `1440×889`：页面内容1128px，筛选form `1090×143.5px`自动两行；表格继续2210px并只在1090px内部table-scroll横向滚动。固定标题右留白自动取消，document/body均 `1440 / 1440`。
- 390 popup实际 `390×840`：内容区346px单列，学生后紧跟346px checkbox区；五个输入控件均346px，查询/重置各167×44px、间距12px；表格只在346px内部容器滚动，document/body均 `390 / 390`。
- 三档Console error `0`、warning `0`。

### 只读业务字段与防回退

- 新增弹窗只读打开后，老师、学生、科目、结算类型、JPY/CNY时薪及备注均存在；未点击保存。
- 首条规则编辑弹窗正确回填老师、学生、科目及 `jpy_hourly`；只点击取消。
- 首条详情正常显示老师分类、结算类型、费率、状态和ID；没有业务归属、个人名义或 `business_entity_id` UI。
- 未点击新增保存、编辑保存、停用、恢复或其他写入口；浏览器没有service-role，page-layer直接RPC/DML为0。

## 部署与最终数据复核

- 实现commit：`11b3118e9590bd457486cf56adbaf28d3f70e4fb`。
- Pages run：`31231194573` success，部署commit与实现commit一致。
- 生产版本：`v10.5.24`。
- 部署后全部School/Cash/Storage数量、金额和MD5与“部署前只读指纹”逐项一致。
- Gate前后均为 `enabled / blocked / enabled`。
- 数据库部署SQL、DDL/DML、业务RPC、写RPC：0。
- School、Cash、Storage及真实业务写入：0；fixture：0；测试record ID：无。

本轮到此停止，只完成工资规则页面修复，不继续调整其他页面。
