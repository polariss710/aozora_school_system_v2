# School V2 勤务申报表第37行汇总文案修复

日期：2026-08-09

## 结论

老师工资“批量导出勤务申报表”已仅修复第37行汇总文案。日期、星期、排序、actual关联、工资明细reader和第36行公式均零修改；生产版本为`v10.5.30`，Pages run `31309201505`对应实现commit `be724cf7438a2bed76f34fe8b30a9f7e4946ac8b`并成功。

第37行由：

`系统快照合计：内部范围1：结算课时 16 / 课时工资 JPY 64,000 / 费用 JPY 0 / 合计 JPY 64,000`

改为：

`合计：结算课时 16 / 课时工资 JPY 64,000 / 费用 JPY 0 / 合计 JPY 64,000`

“系统快照合计”和“内部范围1”已从导出模块的用户可见文案中移除。课时、课时工资、费用和合计仍来自每份工资快照的动态数据；同一老师存在多个既有导出scope时只做展示合计，不改变任何工资事实。

## 实时基线

| 项目 | 值 |
|---|---|
| 初始分支 | `main` |
| 初始HEAD / origin/main | `3d8008f804c8ac99fe73a09bd0019bd69921770a` / 同值 |
| 初始ahead/behind | `0/0` |
| 初始生产版本 | `v10.5.29` |
| 初始最新成功Pages | `31307580602`，commit `3d8008f804c8ac99fe73a09bd0019bd69921770a` |
| 实现版本 / commit | `v10.5.30` / `be724cf7438a2bed76f34fe8b30a9f7e4946ac8b` |
| 实现Pages | `31309201505`，success |
| Gate | `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled` |

没有reset、rebase、checkout回退或覆盖合法提交。

## 日期逻辑零修改证明

相对初始HEAD，导出模块仍使用既有逻辑：

- A列：`dutyDateText(detail.lesson_date)`；
- 排序：`lesson_date → start_time → student_name`；
- 没有修改工资明细reader、API、actual关联、week_start或任何日期字段；
- 没有SQL、RPC、schema、ACL或数据库reader变更。

上一份已被替代Prompt产生的未提交日期helper和排序包装已在本次提交前精确撤销，未进入commit。

## 工作簿验收

参考文件：既有`高若天_2026-07_勤务申报表.xlsx`。生产下载文件仍为单sheet“勤务申报表”，使用范围`A1:J45`。

表格工具逐单元格比较通过：

- `A1:J36`与修复前完全一致；
- `A38:J45`与修复前完全一致；
- 全部公式完全一致；
- 第37行是唯一内容变化；
- 公式错误扫描0；
- 合并、样式、字体、颜色、边框、行高和可视布局无变化。

高若天8条明细保持：

| 行 | 日期及星期 | 开始 | 结束 | 结算课时 |
|---:|---|---|---|---:|
| 5 | `2026/07/05（日）` | `16:00` | `18:00` | 2 |
| 6 | `2026/07/05（日）` | `18:00` | `20:00` | 2 |
| 7 | `2026/07/06（月）` | `16:00` | `18:00` | 2 |
| 8 | `2026/07/12（日）` | `13:00` | `15:00` | 2 |
| 9 | `2026/07/19（日）` | `15:00` | `17:00` | 2 |
| 10 | `2026/07/19（日）` | `17:00` | `19:00` | 2 |
| 11 | `2026/07/27（月）` | `15:00` | `17:00` | 2 |
| 12 | `2026/07/27（月）` | `19:00` | `21:00` | 2 |

第36行保持：

- `G36=SUM(G5:G35)`
- `H36=SUM(H5:H35)`
- `I36=SUM(I5:I35)`

生产第二样本王亚楠正常动态显示：

`合计：结算课时 14 / 课时工资 JPY 77,000 / 费用 JPY 0 / 合计 JPY 77,000`

证明文案不是高若天专用硬编码。

## 测试与生产Chrome

- JS语法：导出模块、工资列表/详情page与app全部通过`node --check`。
- 新增`wage-duty-report-export-test.mjs`，覆盖高若天8行原日期/星期/时间/课时、第36行三公式、第37行目标文案、吴峰零工资样本和王亚楠动态数字。
- 既有工资effective、学生筛选、工资筛选和工资规则回归共6组全部通过。
- 表格工具导入、公式扫描、逐单元格比较及高若天/王亚楠全表渲染通过，无截断或布局变化。
- 生产Chrome：`v10.5.30`；2026-07显示8条工资快照、56候选/56已生成；点击且仅点击“批量导出勤务申报表”，成功下载8个老师Excel的ZIP。
- 生产下载的高若天和王亚楠文件均正常打开；Console error/warning为0（仅版本info）。
- 未点击生成工资、生成支付请求、支付、支出、作废或其他写入口。

## 数据与安全边界

本替代Prompt生效后没有执行手工数据库SQL、SQL文件、DDL/DML或任何写RPC；生产Chrome仅使用既有只读页面reader/preflight和本地文件下载。没有业务模型扩展。

- 直接SQL：0；SQL文件：0；DDL/DML：0；写RPC：0；测试fixture：0；测试记录ID：无。
- School/Cash/Storage业务写入：0。
- 工资快照仍为8条；工资明细/已生成候选仍为56条；工资总额保持JPY410,750。
- 支付请求、支出、账户流水和Cash写入：0。
- Gate保持`enabled / blocked / enabled`。
- `js/legacy-core.js`、数据库reader、API列、日期/排序和Excel其他区域均未修改。

## 受保护文件

业务负责人指定的7份受保护untracked文件均未修改、移动、删除、执行、暂存或提交。文档提交阶段另发现一份并发产生的外来untracked文件，同样已纳入保护；最终现场共8份。终态SHA-256：

| 文件 | SHA-256 |
|---|---|
| `docs/school-v1-decommission-preflight-p1a-online-evidence-20260809.md` | `a6237ad5b57a4c7ea3afce49a6ec9f7753d4e82c1ff7087000259055d7653317` |
| `docs/school-v1-decommission-readonly-investigation-20260809.md` | `3e65e0091e68cd419ac13f0e692fcce99f07041abfcdab3b8786e526a800fcaa` |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

`school-v1-decommission-readonly-investigation-20260809.md`在本任务初始读取时即为上述SHA；新增的P1A文件是在文档提交阶段首次出现。本任务从未读取两者正文或改动任一受保护文件。
