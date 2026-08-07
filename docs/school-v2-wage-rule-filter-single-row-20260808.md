# School V2 老师工资规则筛选栏单行布局优化实施报告

日期：2026-08-08（Asia/Tokyo）

## 结论

老师工资规则页顶部“老师分类”和“结算类型”筛选已完整退役，工资规则页主体已局部扩宽，页面版本由 `v10.5.22` 前进至 `v10.5.23`。老师、学生、包含暂停/离校学生、科目、启用状态、关键词及查询/重置全部保留；删除后的结果与原两项均为“全部”一致。

实现提交为 `5ea88da13fe86ce916c90a8f51abf2fb0f777d86`，Pages run `31201698984` 成功，部署 commit 与实现提交一致。生产 Chrome、URL、筛选、弹窗、详情、三档响应式及部署前后只读数据指纹全部通过。

## 实时基线与工作区保护

- 初始分支：`main`。
- 初始 `HEAD` / `origin/main`：`4f9bc3da384ce944dc7003f934a12cad395ba484`，ahead/behind `0/0`。
- 初始生产版本：`v10.5.22`；Pages run `31199458586` success。
- 开始时没有 tracked 修改，只有六份既有受保护 untracked 文件；没有 reset、rebase、checkout 或回退。
- 业务模型扩展声明：表、字段、状态、权威来源、writer/reader、ACL/RLS 均为 `none`。

六份受保护文件开始、实现部署后哈希一致，且从未暂存：

| 文件 | SHA-256 |
| --- | --- |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 筛选退役与 URL 合同

代码和 Git 历史确认，顶部实际状态名为 `teacherDepartment` 与 `settlementType`；底层权威字段分别为老师主数据 `department` 和规则 `settlement_type`。reader/API 原本一次读取全部规则，不接受这两项筛选参数，因此无需修改 API 签名或传递隐藏空值。

本轮仅从顶部筛选删除：

- 两个 label/select DOM。
- `DEFAULT_FILTERS`、DOM cache、读取、恢复和 option 生成。
- `filterWageRules` 中的老师分类与结算类型本地过滤。
- 已失去用途的 distinct/option helper。

现有 `syncCandidateUrl` 继续是唯一受控 URL 写回点，并删除 `teacherDepartment / teacher_department / settlementType / settlement_type`。生产旧链接同时携带四个参数时，四者由一次 `history.replaceState` 清除；`teacher_id / include_inactive / subject / active / keyword / view` 等其他参数原样保留，没有刷新循环。页面从不读取这两项旧参数，因此清理前也不存在隐藏过滤窗口。

## 业务字段保留

- 表格继续显示“老师分类”和“结算类型”两列；20条规则均正常渲染。
- 详情页继续显示老师分类与结算类型。paused 历史规则 `940c282f-e713-4ae7-9305-30909d2af1e4` 显示“バイト老师 / 日元时给”。
- 新增/编辑继续保留老师、学生、科目、结算类型、日元/人民币时薪与备注，`p_settlement_type` 及全部 writer payload 未改。
- 实时基线和现有模型中，新增/编辑从来没有独立“老师分类”输入；分类由所选老师的 `school_teachers.department` 权威关联。为避免本轮凭空新增可写事实，前后均保持该合同。列表与详情的分类展示没有删除。
- 新增弹窗只列DB东京当前月7名active学生；编辑 paused 学生“厦门吕同学”时原值以“本月暂停（当前不可新选）”保留，老师、科目和日元时给均正确回填。
- 未点击新增、保存、停用、恢复或任何写入口。

## 页面宽度与局部 CSS

`wage-rule.html` 增加工资规则专属 `app-shell--wage-rule`、filter panel/grid及字段 class。`css/app.css` 仅以 `.app-shell--wage-rule` 和 `.wage-rule-*` 选择器扩宽并布局；没有修改工资结算、月结、课时或全局容器规则。

2560px宽屏列合同为：

`300 / 300 / 176 / 300 / 300 / 300 / 弹性 / 按钮 / 140px`

常规 gap 与按钮 gap 均为12px；没有绝对定位。checkbox使用独立区域并显式限定 `16×16px`，不再继承全宽 input 尺寸。

## 静态与语法回归

新增 `scripts/wage-rule-filter-layout-static-test.mjs`，并同步当前版本精确断言。以下全部通过：

- `node --check`：wage-rule page/app/API/detail。
- wage-rule filter layout、B4-Remaining、B3 writer authority、B2 legacy freeze、B5。
- 工资学生候选与工资筛选布局。
- lesson/settlement布局与B4-Lesson/B4-Finance。
- BE-UI、BE-P0权限及系统blocker展示。

静态扫描确认：顶部无两项退役DOM/state/filter；新增/编辑/详情/列表业务字段仍在；page-layer直接RPC/DML为0；浏览器service-role为0；`js/legacy-core.js`未修改。

## 生产 Chrome 无写验收

### 2560×1440档位

Chrome页面可用视口为 `2560×1204`：

- shell由原 `1440px` 扩为 `2280px`；header/main宽 `2248px`，左右边界一致。
- 筛选form `2210×66px`，筛选卡 `2248×139.5px`，严格单行。
- 老师、学生、科目、启用状态、关键词的 `getBoundingClientRect().width` 均精确为 `300px`，底边均为 `305.5px`。
- checkbox区域 `176px`，checkbox本体 `16×16px`。
- 查询/重置均 `62×42px`，间距 `12px`；按钮组右侧 `152px`。
- document/body横向溢出均为0。

### 1440×900档位

Chrome页面可用视口为 `1440×723`：

- form `1090×143.5px`，自动两行。
- 第一行老师/学生/checkbox/科目；第二行启用状态/关键词/按钮区。
- 普通列约 `292.66px`，checkbox区域 `176px`，按钮区占剩余两列并右对齐。
- 固定右侧留白自动取消；document/body横向溢出均为0。

### 390×844档位

Chrome popup实际可用视口为 `390×841`：

- 内容区 `346px` 单列；顺序为老师、学生、checkbox、科目、启用状态、关键词、按钮。
- 五个输入控件均 `346×44px`；checkbox `16×16px`。
- 查询/重置各 `167×44px`，间距 `12px`。
- document/body横向溢出均为0；规则列表保持既有横向表格容器行为。

三个档位 Console error `0`、warning `0`。

### 筛选、候选与防回退

- 丛琪润 + 陈加恩 + EJU数学 + 启用 + 关键词“丛琪润”联合查询返回唯一1条，字段全部匹配。
- 重置后规则恢复20条、顶部筛选恢复默认；查询和刷新正常。
- DB东京当前月默认7名active候选；include inactive后8名，并显示“厦门吕同学｜本月暂停”。
- paused学生筛选显示2条历史规则；取消include inactive后selected override继续保留同一paused学生和2条历史事实。
- “全部学生”始终显示20条规则，没有被当前学生状态裁剪。
- 页面及详情没有业务归属、个人名义或 `business_entity_id` UI。

## 部署前后只读指纹

| 对象 | 数量/合计 | MD5 |
| --- | --- | --- |
| wage rules | 20条；启用18；JPY时薪合计78,400；CNY时薪0；汇率0.558028；交通/教室费0 | `2dc430ca4a58416235f2ba771b91b9f1` |
| wage rule ID集合 | 20 | `9097d343ec0eddbe9ea061679a3aff44` |
| wage locks | 95 | `8474b2adcc3ed39059efd7237da90168` |
| wage details | 556 | `0b2976f8005835d66b2db25b0b3c1939` |
| income | 55 | `eb40e1ea59767e4299cd23b332f57d2a` |
| expenses | 47 | `141c76e4cf6148007e182704941a0c4a` |
| accounts | 3 | `443b3170f50bc23a56834d398069c565` |
| account transactions | 187 | `21694ff060e23289566f0a6e9fe3e449` |
| School payment requests | 51 | `75f06bc98ad541c77f2ce9c6d7a7978d` |
| Storage objects / orphan | 57 / 30 | `c2852a4dbcd13b9cddb1da0b1115b18f` |
| Cash requests | 43 | `38af234da847c517d548c7b6337a40a1` |
| Cash CNY transactions | 74 | `97d2cb2955477319b27664daa9af0b42` |
| Cash JPY transactions | 31 | `3f3f257b14b43c12925a8eecb7a8ca02` |

以上前后完全一致。Gate前后均为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`。

- 数据库部署SQL：0；DDL/DML：0；写RPC：0。
- 临时只读脚本 `/private/tmp/school_v2_wage_rule_filter_layout_baseline_readonly_20260808.sql` 与 Cash同名脚本各执行两次，均为 `BEGIN READ ONLY ... ROLLBACK`。
- School、Cash、Storage及真实业务写入：0；fixture：0；测试record ID：无。
- 未修改工资规则reader/writer、数据库函数/schema/ACL/RLS、学生状态resolver、Gate、Cash、Storage或其他页面。

本轮到此停止，只完成老师工资规则页面筛选栏优化。
