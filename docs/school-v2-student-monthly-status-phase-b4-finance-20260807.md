# School V2 学生月份状态 Phase B4-Finance 实施报告

日期：2026-08-07（Asia/Tokyo）

## 结论

Phase B4-Finance 已在实时 `main` 上完成实现：学生月度结算、收入和支出顶部学生候选统一改用既有 `school_list_student_month_candidates_v1`；收入新增、收入编辑和学费 validation preview 的学生候选分别使用其结算月份、记录结算月份和 billing month。默认只列当月 `active`，开启“包含暂停/离校学生”后列全部；URL/页面已有 `student_id` 通过 resolver 的 selected override 保留并显示月份状态标签。

本阶段只改变 F（候选）和必要的 L（详情按记录原 `student_id` 最小查询）。D（财务业务 reader）仍按月读取完整月结/收入/支出事实，W（writer 资格、金额、状态机、Cash、账户和学费 Gate）未变。没有新增或执行 SQL/RPC，没有 DB、Cash、Storage 或真实业务数据写入。

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
| income | 55 | student-linked 30；JPY 9,667,830；CNY 36,396 | `bd2d538d1de901621ff0e6757984a41e` |
| tuition bills | 22 | planned JPY 6,663,800；previous carryover CNY -1,034.50 | `d079f068c0fa19fc07d4dcd94094fae2` |
| expense | 47 | student-linked 0 / unlinked 47；JPY 2,890,406；CNY 21,098.95 | `141c76e4cf6148007e182704941a0c4a` |
| accounts | 3 | current balance sum 1,401,412 | `443b3170f50bc23a56834d398069c565` |
| account transactions | 187 | amount sum 310,494 | `21694ff060e23289566f0a6e9fe3e449` |
| Cash external requests | 42 | expense approved 15/pending 1/rejected 2；income approved 6；tuition approved 18 | `39bed8915955b3fb8cbe6553928edc71` |
| Cash CNY/JPY transactions | 36 / 3 | 不变 | `38b0e164d2a0b20ec149116002c4adc7` / `654485db35df0657c0bf7121d464baa3` |
| Storage objects/orphans | 57 / 30 | 不变 | `c2852a4dbcd13b9cddb1da0b1115b18f` |

目标 paused 学生的 2026-04/05/06 月结 ID 分别为 `9d8e23f3-a102-4934-a34a-c568030bd73e`、`d70374bc-f8a5-43f3-a5a1-c45cfff78512`、`dd1a599e-a4f1-4656-ad3a-33dcdc0004f7`；2026-06 CNY 收入 `ac685f46-e924-435f-99e9-6797cca7e922` 保持可读。当前所有 47 条支出均无 student 关联，因此选择任一学生结果为 0，而“全部学生”仍显示完整 47 条。

Gate 前后均为：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=enabled`。

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
- Pages：实现 run `31120145520` 的 attempt 1、attempt 2 均在排队约 15 分钟后以 build `cancelled`、deploy `skipped` 结束，两个 build job 的 steps 均为空。同期 GitHub 官方状态确认 Actions 与 Pages 均为 `major_outage`，故障说明为 workflow 延迟或无法开始；这不是 checkout、构建或仓库代码失败。待平台恢复后需重跑并补做生产验收。
- Chrome 桌面/390px：平台恢复并部署后执行；仅只读，不点击保存、生成、到账、取消、reverse、Cash、结算或调整。故障前生产基线仍为最后成功部署的 `v10.5.13`。
- SQL/RPC 部署：无；本阶段仅执行只读 `SELECT`/`READ ONLY` 基线与 postdeploy 核验。

B4-Remaining 与 B5 均未启动。
