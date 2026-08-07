# School V2 学生月份状态 Phase B4-Finance 实施报告

日期：2026-08-07（Asia/Tokyo）

## 结论

Phase B4-Finance 已完整闭环并生产上线：学生月度结算、收入和支出顶部学生候选统一改用既有 `school_list_student_month_candidates_v1`；收入新增、收入编辑和学费 validation preview 的学生候选分别使用其结算月份、记录结算月份和 billing month。默认只列当月 `active`，开启“包含暂停/离校学生”后列全部；URL/页面已有 `student_id` 通过 resolver 的 selected override 保留并显示月份状态标签。

本阶段只改变 F（候选）和必要的 L（详情按记录原 `student_id` 最小查询）。D（财务业务 reader）仍按月读取完整月结/收入/支出事实，W（writer 资格、金额、状态机、Cash、账户和学费 Gate）未变。最终补丁还只在展示层把工资快照 blocker 的内部归属明细转换为中性系统文案，并修正 DOM `change` Event 被误传为 selected UUID 的候选重载问题。没有新增或执行数据库部署 SQL，没有 DB、Cash、Storage 或真实业务数据写入。

## 实时起点与模型声明

- 初始分支/HEAD/origin：`main` / `ec1f964c353bfbc6b309bd13bfea0cf970a2fc0d` / 相同，ahead/behind `0/0`。
- 初始工作区：仅 6 份既有受保护 untracked 文件，无同文件未完成任务。
- 实时代码版本为 `v10.5.14`；因连续 runner 排队失败，初始生产 Pages 实际仍为最后成功部署的 `v10.5.13`。本阶段代码版本前进为 `v10.5.15`。
- 模型扩展声明：新表、列、状态、月份、身份、快照、版本、可写事实、锁、双写、reader precedence、历史解释和 destructive change 全部为 `none`。
- 已批准 authority 变化：仅任务明确批准的 Finance 候选读取改用 Phase A 月份状态 resolver；业务 reader 与 writer authority 均不变。

## 修改前 F/D/L/W 矩阵

| 页面/入口 | F：原候选 | 权威月份/URL | D：业务 reader | L：详情 lookup | W：writer 资格 |
|---|---|---|---|---|---|
| 月度结算顶部 | `fetchSettlementStudents()` 全量 `school_students`，含冻结 legacy status | 页面年月；原无稳定筛选 URL | 当月 snapshot + lesson/income preview，选择后只按 `settlement.student_id` 本地过滤 | 详情原加载全部学生 | draft/preview/lock/unlock/relock/adjustment 不变 |
| 收入顶部 | `fetchIncomeLookups()` 全量学生 | 页面年月；原只保存 year/month | 当月完整 income，选择后按 `income.student_id` | 详情原加载全部学生 | income/Cash/取消/冲销不变 |
| 收入新增 | Aozora 默认 entity + legacy `status=active` | `settlement_month` | 不适用 | 不适用 | writer 仍使用唯一 fail-closed Aozora |
| 收入编辑 | 原 entity + legacy `status=active` | 记录 `settlement_month || year_month` | 原 income ID | 原学生可能从编辑候选消失 | expected/current immutable guards 不变 |
| 学费 preview | Aozora 默认 entity + legacy `status=active` | `billing_month` | DB validation preview | 不适用 | generate Gate 保持 blocked |
| 支出顶部 | 全量学生 | 页面年月；原只保存 year/month | 当月完整 expense，选择后按 `expense.student_id` | 详情原加载全部学生 | 新增合同仍固定 `student_id=NULL`，paid/pending/Cash 不变 |

业务归属关闭后的真实调用链保持：页面不展示 business entity；新增收入/学费/支出仍通过 `requirePrimarySchoolBusinessEntityId(...)` 唯一 fail-closed Aozora resolver 取得内部 ID；历史记录保留原 `business_entity_id`。

## 修改后矩阵

| 入口 | F 权威月份与候选 | selected/include inactive | D/L/W 结果 |
|---|---|---|---|
| 月度结算顶部 | 页面选择年月第一天 | URL `student_id`、`include_inactive=1`；paused/left 标签 | D 完整；L 仅 `.eq("id", settlement.student_id)`；W 不变 |
| 收入顶部 | 页面选择年月第一天 | 同上，并稳定保存 account/category/currency | D 完整；W 不变 |
| 收入新增 | `createSettlementMonthInput` | 默认 active；可包含 inactive；原选择 override | 新业务 entity resolver 不变；无状态 writer gate |
| 收入编辑 | `income.settlement_month || year_month`，随合法月份修改重载 | 原 `student_id` 永久 selected override；可包含 inactive | L 先按记录 ID 取原学生；expected/锁/Cash 不变 |
| 学费 validation preview | `tuitionBillMonthInput` | 默认 active；可包含 inactive；原选择 override | DB 课时/月结/bill/income/Gate 决定；未执行 generate |
| 支出顶部 | 页面选择年月第一天 | 同上，并稳定保存 teacher/account/currency | D 完整；47 条无 student 关联记录在“全部学生”下保留；新增仍无学生写入能力 |
| 三个详情 | 记录 ID → 原 `student_id` | 不经过 active 候选 | 最小学生 ID lookup；历史姓名保留；writer 不变 |

共享 `js/api/student-status-api.js` 现在统一提供 candidate normalization、月份状态标签、option 渲染、`student_id/include_inactive` URL 读取和序列化；三个 Finance 页面没有复制状态解析算法。

## BE-UI 工资 blocker 展示补漏

生产 `v10.5.15` 首轮 Chrome 验收发现月结页直接显示 `teacher_wage_blocker_reason` 原始内部文本，其中含“业务归属：青空进学塾 / 个人名义”。只读溯源结论如下：

- 原因由 DB `school_get_student_monthly_settlement_wage_blockers(text,uuid)` 动态生成；不是 `school_student_monthly_settlements`、工资锁或工资明细的持久字段，也不是冻结工资快照内容。
- API 保留原始 `blocker_reason`；月结列表和详情曾直接渲染它。全仓运行时消费者只有这两个页面。
- 原始 `business_entity_id`、`wage_business_names`、工资锁、工资明细及 DB 内部阻断判断均保留。没有改 reader、guard、writer 或历史数据。

新增共享展示工具 `js/utils/system-blocker-display.js`，仅根据结构化 blocker level、工资快照数和明细数生成中性文案；原始 reason 只用于判断 blocker 是否存在，不参与展示，也不通过字符串改写影响锁判断。修改前示例为“老师工资已生成或锁定（业务归属：青空进学塾、个人名义）”；修改后为“老师工资已生成或锁定，涉及 N 个工资快照、M 条工资明细；当前月结操作受工资快照保护。如需变更，请先按受控流程处理未支付工资快照。”

防回退扫描覆盖 settlement/wage/income/expense/lesson 的列表与详情、PDF、导出、tooltip、错误提示及隐藏区域；系统字段不再向用户显示“业务归属”“个人名义”或 `business_entity_id`。品牌/发行语义及用户自由输入内容不作全局替换。

首轮 `v10.5.16` 无写验收还发现收入新增/编辑的月份与 include-inactive `change` 监听器把 DOM Event 直接传给 `selectedOverride`，导致 Event JSON 被当成 UUID。四个监听器已改为显式无参调用，并加入静态防回退断言；不改变 resolver、API、writer 或财务事实。

## 实时只读证据

### 月份候选

| 月份 | 默认 | include inactive | paused selected override | 目标学生状态 |
|---|---:|---:|---:|---|
| 2026-06 | 8 | 8 | 8 | active / fallback |
| 2026-07 | 7 | 8 | 8 | paused / event |
| 2026-08 | 7 | 8 | 8 | paused / event |

唯一真实事件保持：`4190bddf-d995-4e6a-af6b-85997e6f999b`，学生 `cff85c52-6acc-4b0f-8c92-3db280a5dd77`，`2026-07-01 paused`；event 表 `1 / eeeb492ac7577ff85eb0926aa0b57301`。

### 财务与基础数据（修改前后相同）

| 对象 | 数量 | 金额/关联摘要 | 指纹 |
|---|---:|---|---|
| settlements | 18 | planned JPY 4,902,875；actual JPY 4,544,145；received JPY 1,744,000；received CNY 151,094；carryover CNY -519.75 | `7986db5dd35c0ecfa180a04aef7f4051` |
| income | 55 | student-linked 30；JPY 9,667,830；CNY 36,396 | `eb40e1ea59767e4299cd23b332f57d2a` |
| tuition bills | 22 | planned JPY 6,663,800；previous carryover CNY -1,034.50 | `d079f068c0fa19fc07d4dcd94094fae2` |
| expense | 47 | student-linked 0 / unlinked 47；JPY 2,890,406；CNY 21,098.95 | `141c76e4cf6148007e182704941a0c4a` |
| accounts | 3 | current balance sum 1,401,412 | `443b3170f50bc23a56834d398069c565` |
| account transactions | 187 | amount sum 310,494 | `21694ff060e23289566f0a6e9fe3e449` |
| Cash external requests | 43 | 全库当前值 | `f4b1876e981ef75828600e0c7f0dc371` |
| Cash CNY/JPY transactions | 74 / 31 | 全库当前值 | `070c262ec01008d404b424233d2a6e47` / `95ab7cf8a8d167e9b052d3fc6b64614b` |
| Storage objects/orphans | 57 / 30 | 不变 | `c2852a4dbcd13b9cddb1da0b1115b18f` |

目标 paused 学生的 2026-04/05/06 月结 ID 分别为 `9d8e23f3-a102-4934-a34a-c568030bd73e`、`d70374bc-f8a5-43f3-a5a1-c45cfff78512`、`dd1a599e-a4f1-4656-ad3a-33dcdc0004f7`；2026-06 CNY 收入 `ac685f46-e924-435f-99e9-6797cca7e922` 保持可读。当前所有 47 条支出均无 student 关联，因此选择任一学生结果为 0，而“全部学生”仍显示完整 47 条。

Gate 前后均为：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=enabled`。

相对最初 B4 实现基线，income 全行指纹从 `bd2d538d1de901621ff0e6757984a41e` 合法变化为 `eb40e1ea59767e4299cd23b332f57d2a`。原因不是本任务写入：收入 `efd670bc-8dba-4926-82c4-2d194281a609` 在 2026-08-07 00:14 UTC 由业务负责人完成 Cash 审批后变为 `received`；Cash request `cd3c277a-801e-4743-9345-1e07b2b31ccf` 为 approved/CNY 9,240，对应唯一 CNY transaction `46f135d2-36c5-43eb-b324-bbed9562d54f`。本轮开始复核、实现部署后复核与最终复核之间，上表当前数量和指纹完全一致。

## 测试与权限

- 新增 `scripts/student-status-phase-b4-finance-static-test.mjs`，覆盖共享 resolver、月份、include inactive、selected override、URL、F/D/L/W 边界、详情最小 lookup、支出 `student_id=NULL`、BE-UI 防回退、page-layer RPC/DML 和 service-role。
- 所有修改 JS `node --check`、`git diff --check` 通过。
- B1/B2/B3/B4-Wage/B4-Lesson、BE-P0/BE-UI、取消保护、lesson writer P0、Admin Cash、Cash expense、tuition validation/atomic generate 回归通过；旧版本号断言改为未来安全的 `v10.5.x`，不改变业务断言。
- 页面模块直接 `.rpc()`/表 DML 为 0；浏览器 service-role 为 0。
- 共享 reader 沿用既有 RPC `school_list_student_month_candidates_v1(date, boolean, uuid)`，定义 MD5 为 `0e3bd4b8cecf4d25f2b86d16d1f3838f`；仅 `authenticated` 可执行，`anon/service_role` 均不可执行。没有新增 helper 或 SQL。
- 两个状态 event writer 仍为 owner-only；表级 DML/ACL无变化。
- 当前 BE-UI closure postdeploy 通过。较早的 BE-P0 postdeploy 中“JSON Profile writer 应向 authenticated 开放”的断言已被后续 BE-UI 阶段的 owner-only 合同取代，因此该旧断言失败属于历史脚本过期，不是权限回退；当前 4 个 business-entity Profile writer 全部 owner-only，严格程度更高。
- fixture residue：School/Cash 均 0；本阶段未创建 fixture UUID。

## 发布与验收

- 实现提交：`2fb9859c9432cad4729b09a89c8aa6e4a7b56e17`（已 push）。
- GitHub 官方：Pages deployment lag 于 2026-08-06 16:22:59 UTC resolved；Actions critical incident 于 2026-08-07 02:04:44 UTC resolved。封口时官方为 `All Systems Operational`。
- 原实现 run `31120145520` attempt 2 最终为 failure（零业务步骤的平台故障）；恢复部署 run `31122017463` attempt 2 于 2026-08-07 02:32:40 UTC success，部署 `b3ac7dcaf10fbef1c08cdeded1db3871e6f456bb`，生产首次到 `v10.5.15`。
- BE-UI 展示修复提交：`9bdd82d8a44b78368ae9bf5361b44beb90daffc7`；Pages run `31146449023` success，生产到 `v10.5.16`。
- income 候选 Event 参数修复提交：`37a082373fccf4e0d22aec338e720e331d3f1223`；Pages run `31147062882` success，部署 commit 与生产静态资源均确认包含该提交，版本保持目标 `v10.5.16`。
- Chrome active-admin 桌面：2026-06 月结 5 条、候选 8；2026-07/08 默认 7、include inactive 后 8，paused 标签、selected override、查询 URL、切月、重置均通过。paused 学生 2026-06 历史月结/收入和详情按 record ID 可读；月结 blocker 为中性工资快照保护文案，页面无业务归属/个人名义。
- 收入新增默认 7、include inactive 后 8；学费 preview 默认 7、include inactive 后 8，Generate 按钮继续 blocked，未执行 preview 后生成。支出“全部学生”保留无 student 关联记录，选择 paused 学生为 0；School 直接支付与 pending/manual_cash、“保存待支付”与“提交 Cash”分离合同未回退。
- 390×844：月结 5 条/8 候选、收入 8 条/7 候选、支出 2 条/7 候选，document/body 宽度均为 390，无横向溢出。Console error 0、warning 0；浏览器 service-role 0，page-layer 直接 RPC/DML 0。
- 未点击或调用任何保存、生成、结算、到账、取消、reverse、支出创建、Cash 提交或其他写入口。收入编辑没有符合“可编辑且非 Cash 锁定”的生产样本，因此不制造数据强开；对应月份/include inactive Event 合同由同源修复和静态 fixture 覆盖。
- SQL/RPC 部署：无；本阶段仅执行只读 `SELECT`/`READ ONLY` 基线与 postdeploy 核验。

最终只读核验：students `8/431ae7f…`、events `1/eeeb492a…`、settlements `18/7986db5d…`、income `55/eb40e1ea…`、bills `22/d079f068…`、expenses `47/141c76e4…`、accounts `3/443b3170…`、transactions `187/21694ff0…`、wage locks/details `95/7bbe108d…` / `556/6204dc66…`、business entities `2/41d747d4…`、Storage `57/30/c2852a4d…`；Cash 为上表 `43/74/31`。两个状态事件 writer 均为 postgres owner，anon/authenticated/service_role EXECUTE 全 false。工资历史 `business_entity_id` 与 snapshot 指纹未变。

六份受保护 untracked 文件结束 SHA-256 与开始完全一致：`272d0853…`、`5b11f064…`、`b8e02481…`、`5dc7c39c…`、`b9c13ddc…`、`7ed27844…`；未修改、移动、删除、暂存或提交。

B4-Remaining 与 B5 均未启动。
