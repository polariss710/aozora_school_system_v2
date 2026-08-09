# School V2 老师工资候选区 effective 前置展示修复

日期：2026-08-09（Asia/Tokyo）

范围：只修复老师工资结算页候选区的只读工资前置状态展示；不处理Excel/CSV/勤务申报表导出，不生成或修改工资、学生月结、历史完成证据、支付请求、支出、账户流水、Cash、Storage或Gate。

## 1. 结论

1. 原页面错误的精确根因是`js/api/wage-api.js`直接读取`school_student_monthly_settlements`物理行，`js/pages/wage-page.js`再以`settlement_status='locked'`和内部范围是否精确匹配自行统计、渲染并形成生成前提示；该链没有使用正式工资preflight/effective resolver，所以已合法完成的历史事实和`no_wage`被误报为未完成。
2. 现有`school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)`只读合同增加`candidate_prerequisites`逐课时数组。其分类仍唯一来自既有owner-only candidate helper、effective resolver与工资writer同一`classified` CTE；没有新增业务事实、authority、fallback或writer语义。
3. 页面文案改为“工资前置满足 / 阻断”；`ordinary_locked`、`historically_consumed_immutable`、`historical_zero_carry_complete`计入满足，active `no_wage_not_required`显示“无需月结”并计入工资前置满足，其他DB blocker显示“阻断”。页面不再读取物理月结作为工资资格权威。
4. 生产`v10.5.29`的2026-07显示：候选56、6660实际分钟、工资前置满足/阻断`56/0`、no_wage `11条/1230分钟`、未生成/已生成`0/56`；8条active快照、56条active明细、90.5计薪小时、JPY410,750全部保持。
5. 彭宇晗课时`145a8219-0fcf-4e0b-8230-c6a092668836`（30分钟）显示“无需月结”；张倬闻14条应结算课时以`historically_consumed_immutable`显示前置满足；陈红卓、陈加恩、袁振轩共21条候选以`historical_zero_carry_complete`显示前置满足。李天伦的第4条历史证据仍有效且未变，但2026-07工资候选为0，因此页面没有可对应的课时行。
6. 2026-08真实未完成范围仍显示10满足/8阻断，证明页面没有强制把所有课时标成满足。

## 2. 实时基线与Git

| 项目 | 初始 | 最终功能部署 |
|---|---|---|
| 分支 | `main` | `main` |
| HEAD / origin/main | `615d4907aed5815cd1e3a03e18f2738ce897dd6b` / 同值 | `70cf1cee502caa4c87e1ec12193a18147162a64a` / 同值 |
| ahead/behind | `0/0` | `0/0` |
| 页面版本 | `v10.5.27` | `v10.5.29` |
| Pages | run `31305837075`成功 | `31307059227`（`3b67e72`）及`31307376972`（`70cf1ce`）成功 |
| Gate | `enabled / blocked / enabled` | 同值 |

实现提交：

- `3b67e72a2e2b21fb353ffa092f550e5cae08d9b4` `fix wage prerequisite candidate display`
- `70cf1cee502caa4c87e1ec12193a18147162a64a` `stabilize wage loading layout`

## 3. DB只读合同与权限

正式定义文件：`sql/current/school_wage_candidate_effective_display_reader_20260809.sql`。

- `candidate_prerequisites`逐课时返回：lesson UUID、DB判定的`prerequisite_satisfied`、effective/no_wage状态、blocker code/detail、结算类型和effective source。
- 原`summary`、`teacher_previews`、`blockers`保持；工资writer定义、candidate helper、effective resolver均未修改。
- 函数仍为`STABLE SECURITY DEFINER`、`search_path=pg_catalog, public`；PUBLIC/anon/service_role无EXECUTE，只有authenticated可调用且函数内继续要求active admin；无membership返回既有`P0G1_ACTIVE_ADMIN_REQUIRED`。
- 没有表级DML、业务DML、DDL、数据迁移或ACL扩大。

执行记录：

- `school_wage_candidate_effective_display_reader_rollback_20260809.sql`：首次因测试预期错误码名称不符而失败，连接关闭自动回滚；修正后两次完整PASS。
- `school_wage_candidate_effective_display_reader_20260809.sql`：正式执行1次，仅`CREATE OR REPLACE FUNCTION`、REVOKE/GRANT和COMMENT。
- `school_wage_candidate_effective_display_reader_postdeploy_20260809.sql`：两次PASS，事务均`READ ONLY`并ROLLBACK。
- 业务写RPC调用0；页面和验收仅调用正式只读preflight/reader。

## 4. 页面与P0边界

- 页面模块直接`.rpc()`和DML仍为0；API wrapper调用正式preflight，并对preflight逐课时覆盖做fail-closed校验。
- 物理月结查询、`studentSettlementStatus`、`studentSettlementMatchedBusiness`及“学生结算完成 / 未完成”资格判断已从工资候选链移除。
- 年/月、老师、学生、状态、关键词及include inactive均为draft；值变化不刷新候选、不改URL，只有“查询”或“重置”应用。
- 生成弹窗和客户端预提示也只消费同一DB preflight结果；正式writer仍在DB内重新校验。
- 加载文字改为固定21px占位。390px实测查询前/中/后，工资表、候选区、统计卡和候选表的绝对Y坐标完全一致。
- 没有修改`js/legacy-core.js`，没有修改Excel/CSV/勤务申报表导出函数。

## 5. 测试与生产Chrome

静态/语法：

- `node --check`：`wage-api.js`、`wage-page.js`、`wage-app.js`通过。
- `wage-effective-prerequisite-display-static-test.mjs`、`wage-filter-layout-static-test.mjs`、`student-status-phase-b4-wage-student-filter-static-test.mjs`、`student-status-phase-b4-remaining-static-test.mjs`全部PASS。
- page-layer直接RPC/DML、浏览器service-role、物理月结资格字段、旧错误文案扫描均为0；`git diff --check`通过。

生产Chrome：

- 桌面1710px：v10.5.29、8快照、56明细、6660分钟、90.5计薪小时、JPY410,750；候选56，前置满足56、阻断0，no_wage 11/1230，水平溢出0。
- 逐课时title确认：ordinary locked 10条、historically consumed 14条、historical zero carry 21条、no_wage 11条；合计56。
- 2026-08：18候选、10满足、8阻断、no_wage 2/240，真实未完成仍被显示为阻断。
- 390px：筛选栏宽346px、document scroll width 390px、水平溢出0；2026-07仍为8快照/56候选/56满足/0阻断。
- 月份、checkbox、老师、学生、状态和关键词变化前，URL和已应用结果保持不变；查询与重置正常。
- Console error/warning 0；未点击生成工资、生成支付请求、支出、支付、作废或其他写入口。

## 6. 数据不变量

部署前后全行指纹完全相同：

| 对象 | count / MD5 |
|---|---|
| lessons | `744 / 02b9109c53d1a3d320d4c9f8899fdb40` |
| settlements | `18 / 481ffa7ed5173da852f0f28ce66c2e9b` |
| bills / revisions / income | `22 / e50673ac998ee2d84573a076a64d3d42`; `20 / ffdc498a6e256aa29064f021f22e4b00`; `55 / c55f82c7d62dbe92d0b49714a911a234` |
| wage rules | `30 / 97a601d0ea3f8c610f4b50c8acb93b77` |
| wage locks / details | `103 / ea395407134045e7623e171b02d3d910`; `612 / 1d45d0ce37696051c233465efaf3de5e` |
| historical evidence | `4 / 9cb22ef4ddd83f7a77c8fcd2e3ab3966` |
| expenses / payment requests | `47 / 34a7a32319d8e538ef7997e1ba59c9d4`; `51 / 6ce63e69edfa19a020013634b686f5ce` |
| accounts / transactions | `3 / ac9fa3e0b92dde16dddfffff2c70c222`; `187 / 00516a76f236d51406c82f37b0e468ee` |
| Cash requests / CNY / JPY | `43 / f4b1876e981ef75828600e0c7f0dc371`; `74 / 070c262ec01008d404b424233d2a6e47`; `31 / 95ab7cf8a8d167e9b052d3fc6b64614b` |
| Storage buckets / objects | `1 / 9b1be72d5b5fb2ac22b7f7b49d9f8f90`; `57 / 62fac5521274c58c6f6982a0c690c134` |

Gate保持`student_tuition_cash_submit=enabled / student_tuition_generate=blocked / student_tuition_preview=enabled`。

本轮School/Cash/Storage真实业务行写入0，工资/财务变化0；持久DB变化仅为获准的只读preflight定义、原ACL重授予和COMMENT。生成工资、支付请求、支出、账户流水、Cash、Storage写入均0。
