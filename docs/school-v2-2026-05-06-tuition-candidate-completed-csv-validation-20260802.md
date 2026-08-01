# School V2 2026年5–6月64条completed CSV完整性验证

## 结论

**验证失败，HARD STOP。**

completed CSV保留了固定64个`planned_id`，但Excel改写了全部64行中的非人工字段，共260个单元格变化。根据本任务合同“任何非人工填写字段发生变化必须HARD STOP”，本轮未连接School DB或Cash DB，未继续历史收费事实、永久排除模型或proposal调查。

同时发现业务语义冲突：64行`manual_decision`虽全部为`ALREADY_CHARGED_EXCLUDE`，但2026-06的34行`manual_note`明确写“历史未收费、业务决定不再追收”，与任务正文声明的“6月已通过School学费收入及Cash确认链完成收费”相反，并提出未获批准的`VALID_NO_FURTHER_CHARGE_EXCLUDE`分类。

## 文件与固定集合

| 项目 | 原始TSV | completed CSV | 结果 |
|---|---|---|---|
| SHA-256 | `5f2c7320568630b2e04af8bd8b7d593f7dd80a6cee1df7fa57c541775bd53ddc` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` | 文件内容不同，符合存在人工填写及Excel改写 |
| 列数 | 43 | 43 | 一致 |
| 数据行 | 64 | 64 | 一致 |
| 表头及顺序 | 基线 | 相同 | 一致 |
| 重复planned ID | 0 | 0 | 通过 |
| 缺失planned ID | — | 0 | 通过 |
| 新增planned ID | — | 0 | 通过 |
| 空planned ID | — | 0 | 通过 |
| ID集合SHA-256 | `7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85` | 相同 | 通过 |
| 唯一before row hash | 64 | 64 | 通过 |

解析使用Python标准库`csv`，以`utf-8-sig`及CSV RFC引号规则读取completed CSV；没有按逗号直接切割。

## 非人工列变化

除`manual_decision`和`manual_note`外，要求逐字段原样相等。实际为：

| 字段 | 变化单元格 | 典型变化 |
|---|---:|---|
| `billing_month` | 64 | `2026-05` → `2026/5/1`；`2026-06` → `2026/6/1` |
| `billing_week_start_date` | 64 | `2026-05-04` → `2026/5/4`等 |
| `lesson_date` | 64 | ISO日期被改为斜杠日期并去除前导零 |
| `actual_dates` | 64 | ISO日期被改为斜杠日期并去除前导零 |
| `start_time` | 2 | `20:30` → `z 20:30:00`；`15:40` → `z 15:40:00` |
| `end_time` | 2 | `22:30` → `z 22:30:00`；`17:10` → `z 17:10:00` |
| **合计** | **260** | **全部64个planned ID至少有一项非人工字段变化** |

两组被改写时间的planned ID：

- `2ac7b22a-2058-476c-9adf-4c189c7c5585`
- `0a6a9f56-d2b8-40fd-b0e4-502773f648b6`

UUID、金额、小数、其他空值、长文本和`before_row_hash`未发现额外差异；但月份、日期、时间和日期前导零已明确损坏，因此完整性门禁不通过。

## 人工填写汇总

| 范围 | manual_decision | 条数 | 小时 | 基础费JPY | 空调费JPY | 总额JPY |
|---|---|---:|---:|---:|---:|---:|
| 2026-05（按原TSV ID归组） | `ALREADY_CHARGED_EXCLUDE` | 30 | 60.5 | 650,500 | 0 | 650,500 |
| 2026-06（按原TSV ID归组） | `ALREADY_CHARGED_EXCLUDE` | 34 | 68.5 | 729,500 | 0 | 729,500 |
| 合计 | `ALREADY_CHARGED_EXCLUDE` | 64 | 129.0 | 1,380,000 | 0 | 1,380,000 |

所有64行决定值均在原合同允许集合内，所有64行`manual_note`均非空。

人工备注分布：

- 2026-05共30行：`2026年5月已通过系统外方式收取，V2无收入记录，禁止重复收费。`
- 2026-06共34行：`真实有效课程，历史未收费，但业务决定不再追收；需要增加VALID_NO_FURTHER_CHARGE_EXCLUDE审核分类。`

第二条不是“已收费”的同义表达，而是“未收费但放弃追收”的新业务事实。它与`ALREADY_CHARGED_EXCLUDE`决定值及任务正文的6月已收费事实冲突。不能由Codex自行选择哪一个为准，也不能把两种原因合并为同一个永久排除权威。

## HARD STOP后的未执行范围

由于第一阶段失败，本轮未执行：

- School DB连接、candidate/hash/关系/结算/工资复核；
- Cash DB连接及5月手工收入匹配；
- 64条最终只读分类表；
- 现有永久排除机制调查；
- 业务模型扩张proposal contract；
- 任何DDL、DML、RPC、rehearsal或迁移。

因此本报告不声称当前candidate仍有多少条，也不声称现有模型能否处理5月或6月。继续这些结论会违反第一阶段HARD STOP。

## 解除HARD STOP所需输入

业务负责人需要提供一个不改写基线字段的completed文件。推荐任选其一：

1. 从原TSV重新生成，所有非人工列强制为文本，只填写`manual_decision`和`manual_note`；或
2. 单独提供仅含`planned_id,manual_decision,manual_note`三列的UTF-8 CSV，以固定TSV作为其他字段唯一基线。

同时必须明确2026-06的唯一业务事实：

- 若确实已经收费：保留`ALREADY_CHARGED_EXCLUDE`，并把备注修正为已收费证据语义；
- 若真实情况是未收费但决定不再追收：不得继续使用“已收费”语义，需要另行提交并批准精确的放弃追收/永久排除业务模型proposal；`VALID_NO_FURTHER_CHARGE_EXCLUDE`目前只是备注文本，不是已批准的数据库状态、source或authority。

在文件完整性和6月业务语义都明确前，本轮停在CSV验证HARD STOP，不进入`64条历史已收费candidate永久排除方案业务审查点`。

## 执行状态

- 数据库连接：0；School DB与Cash DB均未连接。
- SQL/RPC：0。
- 数据库写入：0；测试白名单及测试ID不适用。
- completed CSV：只读，未修改。
- 本轮新增文件：本验证报告。
- Git：未add、commit或push。
