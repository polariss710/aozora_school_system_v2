# School V2 月结业务错误中文化与汇率日期限制报告（2026-08-03）

## 1. 结论

本任务已完成。生产数据库的汇率生效日 guard、月结公式、日期合同和数据库权威均未修改；前端在既有 API 层新增统一稳定错误码翻译，并按当前 settlement month 为汇率生效日设置动态 `min/max`。

对彭宇晗 `2026-07` 的生产 Chrome 只读验收确认：

- 日期范围为 `2026-07-01` 至 `2026-07-31`；
- 输入 `2026-08-01` 时，页面立即显示动态中文主提示，旧 Preview 失效且保存禁用；
- 继续点击只读 Preview 后，DB 仍以 HTTP 400 / `SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH` 拒绝；
- 改回 `2026-07-01` 后必须重新点击 Preview，DB 权威结果恢复为 `-JPY17,000 + JPY2,125 = -JPY14,875 / -CNY624.75`；
- 未点击保存、锁定、撤销、重锁或其他写入口，真实业务写入为 0。

## 2. 业务模型与数据库边界

Business-model expansion declaration：

- 新业务表、字段、枚举、状态、日期/月份事实、权威来源、可写事实、锁定语义：`none`；
- 现有字段语义、writer/reader precedence、兼容路径、历史解释：`none`；
- DB函数、ACL、RLS、comment、schema：`none`。

本次只改变展示、输入约束和客户端 Preview 状态保护。`school_preview_student_settlement_adjustment_dialog(...)` 的既有日期 guard 保持不变，DB 继续是最终校验者；HTML `min/max` 和前端越界提示不能绕过或替代 DB guard。

## 3. 统一错误翻译

仓库原有 `js/api/function-error.js` 仅用于 Edge Function，`js/utils/lesson-error-message.js` 仅用于 lesson；不存在可复用的月结/PostgREST稳定业务错误 formatter。因此新增集中 API 模块 `js/api/business-error.js`，页面层只接收安全的 `{message, code}`，不解析 PostgREST 内部结构，也不通过英文 substring 推断业务语义。

从 P0-A 至 P0-F 的正式 SQL/RPC 中核实并加入的真实稳定码：

| 范围 | 稳定错误码 |
|---|---|
| 汇率 | `SETTLEMENT_EXPLICIT_EXCHANGE_RATE_REQUIRED`、`SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH` |
| source treatment | `SETTLEMENT_SOURCE_TREATMENT_MODE_INVALID`、`SETTLEMENT_SOURCE_TREATMENT_SCOPE_INVALID`、`SETTLEMENT_SOURCE_TREATMENT_REASON_REQUIRED`、`SETTLEMENT_SOURCE_TREATMENT_LOCKED_READ_ONLY`、`SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED`、`SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED_FOR_RELOCK` |
| Dialog scope | `SETTLEMENT_ADJUSTMENT_DIALOG_SCOPE_INVALID`、`SETTLEMENT_ADJUSTMENT_DIALOG_BUSINESS_ENTITY_MISMATCH` |
| lesson/source | `SETTLEMENT_LESSON_SOURCE_UNRESOLVED`、`SETTLEMENT_LESSON_SOURCE_VALUE_INVALID`、`SETTLEMENT_LESSON_VARIANCE_SOURCE_CHANGED_AFTER_DRAFT`、`SETTLEMENT_LESSON_VARIANCE_CLAIM_COUNT_MISMATCH`、`SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED`、`SETTLEMENT_LESSON_VARIANCE_SOURCE_IMMUTABLE` |
| adjustment | `SETTLEMENT_ADJUSTMENT_MODE_INVALID`、`SETTLEMENT_ADJUSTMENT_AMOUNT_FORBIDDEN_FOR_MODE`、`SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED`、`SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_INVALID`、`SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH`、`SETTLEMENT_ADJUSTMENT_SCOPE_INVALID`、`SETTLEMENT_ADJUSTMENT_REASON_REQUIRED`、`SETTLEMENT_ADJUSTMENT_LOCKED_READ_ONLY`、`SETTLEMENT_ADJUSTMENT_SOURCE_FACTS_EMPTY`、`SETTLEMENT_POSTED_ADJUSTMENT_IMMUTABLE` |
| 历史冻结 | `TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE`、`TUITION_CONSUMED_SETTLEMENT_IMMUTABLE`、`R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE` |
| 并发 | PostgreSQL `55P03` |

实际月结 SQL 没有独立的“updated_at不一致”稳定业务码，当前并发/expected facts保护由 `SETTLEMENT_LESSON_VARIANCE_SOURCE_CHANGED_AFTER_DRAFT`、`SETTLEMENT_LESSON_VARIANCE_CLAIM_COUNT_MISMATCH`、`SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH` 和 `55P03` 表达；未为中文需求创造不存在的 DB 错误码。页面本身的旧 Preview 过期和 response expected facts 不一致继续使用明确中文客户端状态。

未知稳定业务码统一显示：`操作未完成，请检查输入或刷新数据后重试。`

次要位置保留精确稳定错误码。页面不显示数据库 SQL、堆栈、连接信息、secret、函数体或英文内部详情；Console 可由开发工具保留脱敏诊断信息。

## 4. 日期与 Preview 状态保护

- Dialog 打开时由当前 `year_month` 生成当月首日和末日；闰年也由测试覆盖；
- 彭宇晗 `2026-07`：`min=2026-07-01`、`max=2026-07-31`；切换至 `2026-08` 后同步变为 `2026-08-01..2026-08-31`；
- 日期输入下方新增：`请选择结算月份内的汇率生效日。该日期用于冻结本次结算采用的汇率依据。`；
- 手工输入或脚本产生越界值时立即标红，动态中文主提示为：`汇率生效日必须位于结算月份2026-07内，请选择2026-07-01至2026-07-31之间的日期。`；
- 次要信息为：`错误代码：SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH`；
- 任一输入变化立即将旧 Preview 标记为“已过期”，清除旧权威结果并禁用保存；
- DB Preview 错误时 badge 为“失败”、Preview 区显示中文原因、保存继续禁用；
- 修正日期只会清除字段错误，仍保持 Preview 过期和保存禁用，必须重新点击“更新数据库预览”；
- 只有当前表单 signature 与最新成功 DB Preview 完全一致时才允许保存。

页面没有计算、推导或舍入任何将保存的金额、差额或结转；全部财务结果仍来自 DB Preview/保存 RPC。

## 5. 精确生产 Chrome 证据

页面与静态资源：

- URL：`https://polariss710.github.io/aozora_school_system_v2/settlement.html?codex=7ad4305`
- 页面版本：`v10.4.6 · settlement-error-i18n-20260803-1`
- CSS：`css/app.css?v=settlement-error-i18n-20260803-1`
- app JS：`js/settlement-app.js?v=settlement-error-i18n-20260803-1`
- 无旧 `p0f-dialog-20260803-1` 混用。

越界请求：

- RPC：`school_preview_student_settlement_adjustment_dialog`
- HTTP method/status：`POST / 400`
- student：`eb705aad-de4d-45e6-a391-42dcdd89aeda`
- month：`2026-07`
- mode：`net_lesson_variance_to_financial_credit_v1`
- rate/source/date：`0.042 / business_owner_confirmed_monthly_settlement_rate_v1 / 2026-08-01`
- adjustment mode/amount：`carry_final_balance / NULL`
- response：`{"code":"P0001","details":null,"hint":null,"message":"SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH"}`

合法日期重新 Preview 后：

| DB Preview事实 | 结果 |
|---|---:|
| 未履约 credit | `-JPY17,000` |
| actual overage | `+JPY2,125` |
| 课时净小时 | `-1.75h` |
| 课时净额 | `-JPY14,875` |
| 课时净额 CNY | `-CNY624.75` |
| projected system difference | `-CNY624.75` |
| projected final carryover | `-CNY624.75` |

生产 Console error 0、warning 0。除刻意触发日期 DB guard 的预期 HTTP 400 外，后续网络失败请求为 0；合法 Preview 成功。Dialog 最终通过“取消”关闭，未点击保存或锁定。

## 6. 修改与测试

修改文件：

- `js/api/business-error.js`
- `js/pages/settlement-page.js`
- `js/settlement-app.js`
- `settlement.html`
- `css/app.css`
- `scripts/settlement-business-error-localization-static-test.mjs`
- `scripts/settlement-p0f-dialog-preview-static-test.mjs`
- 本报告与 `docs/current-status.md`

通过：

- 三个相关 JS 文件 `node --check`；
- 集中错误翻译/动态日期/未知码回退静态契约；
- P0-F Dialog Preview 静态回归；
- P0-B2 adjustment authority 静态回归；
- lesson settlement month filter 回归；
- `git diff --check`；
- 本地 Chrome 与生产 Chrome 全部指定只读场景。

页面模块 `.rpc()` 新增为 0；所有 Preview 调用继续经 `js/api/settlement-api.js`。未修改 `js/legacy-core.js`。

## 7. 数据保护、SQL与RPC

未执行任何 schema/RPC SQL、DDL、DML、grant/revoke 或数据库函数修改。为前后核对执行的临时 SQL 文件均为 `BEGIN READ ONLY ... ROLLBACK`：

- `/private/tmp/p0f_preview_fix_postcheck.sql`
- `/private/tmp/p0f_cash_postcheck.sql`

实际业务 RPC 仅由生产 Chrome 调用只读 `school_preview_student_settlement_adjustment_dialog`（越界与合法 Preview）。未调用任何 save/lock/unlock/relock writer；测试白名单写入为 0，测试记录 ID 不适用。

前后业务数据完全一致：

| 对象 | 行数 | 全行哈希 |
|---|---:|---|
| lesson | 731 | `f3cb7c99e78b9fb26b5d557c53dc4f20` |
| settlement | 17 | `b890bdc29a27d842d3e3c6a28b84d526` |
| source treatment draft | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| variance claim | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| adjustment draft | 6 | `059c5187ad6513f9501076193aa55696` |
| generation identity | 15 | `60f11efc1aebad6b182f7d0da08d36d7` |
| generation revision | 16 | `3fb1700c806e58cb0f8a75358a09dbd5` |
| tuition bill | 18 | `bc7fe1fc6d904c5f6a0380583e430c9e` |
| income | 51 | `4468607bc30770376ce6aaca9016e598` |
| generation adjustment | 1 | `30304a8ab7a3edbe796b5528512ac242` |
| Cash request | 39 | `303e10bc1a28a0abd8b27afd3929cfd8` |
| Cash CNY | 71 | `d7e72182970de4ea8849c994b67e8dcc` |
| Cash JPY | 31 | `95ab7cf8a8d167e9b052d3fc6b64614b` |

彭宇晗 `2026-07` 的 settlement/source draft/adjustment draft/variance claim 均继续为 0。真实 lesson、settlement、draft、claim、adjustment、generation、revision、bill、income、Cash 和 Gate 写入全部为 0；张倬闻及两人既有 lesson void 结果未改变。

Gate 终态：

- `student_tuition_preview = enabled`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

## 8. Git 与保护文件

- 基线/实现 parent：`b481cd2c12636c92acd5c66a1e1310a8841ab523`
- 实现提交：`7ad4305d59927f5029ff8c97d1f7694f9ebfd47d`
- 实现提交已普通推送 `origin/main`；本报告所在文档收尾提交及最终 HEAD/origin 见任务最终交付（提交不能自包含自身哈希）。

六份受保护 untracked 文件 SHA-256 保持：

- `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

工作流已完成，没有遗留业务写入或待清理测试数据。
