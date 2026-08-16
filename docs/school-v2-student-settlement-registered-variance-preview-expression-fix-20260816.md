# School V2 月结 Preview 已登记课时差额表达修复

日期：2026-08-16
生产版本：`v10.5.47`

## 1. 根因与范围

`school_preview_student_settlement_source_treatment`在`separate_makeup_and_overage_v1`模式下按既有兼容合同将财务化待补、超额、net和source lines固定为0/空；页面只读取这些财务化字段，因此显示“当前模式没有可财务净额化的source”。生产`school_tuition_p0f_source_lines`实际已识别袁振轩2026-08的4条待补source和1条超额source，问题是只读wrapper没有同时暴露“已登记事实”投影，不是数据或结算计算缺失。

本次只替换`school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)`的只读返回定义；未新增表/列/状态/writer，未改变source eligibility、结算计算、carryover、system difference、月份Gate、save/lock/unlock/relock或ACL/RLS。

## 2. 新增只读返回字段

`preview`新增：

- `registered_variance_contract_version`
- `registered_pending_hours`
- `registered_pending_amount_jpy`
- `registered_overage_hours`
- `registered_overage_amount_jpy`
- `registered_overage_amount_cny`
- `registered_net_direction`
- `registered_net_hours`
- `registered_net_amount_jpy`
- `registered_source_count`
- `unresolved_planned_count`
- `registered_overage_included_in_system_difference`
- `variance_summary_status`
- `variance_summary_manifest_sha256`

数值由DB复用现有`school_tuition_p0f_source_lines`、legacy summary汇率和与`school_tuition_p0f_assert_sources_resolved`相同的unresolved predicate生成。前端只校验字段格式并原样格式化，不使用`Number`、`parseFloat`、`Math.round`或加减乘除反推业务事实。摘要缺失/非法/不可用时显示“暂时无法读取已登记课时差额，请重新预览。”，不回退为0。

## 3. 新旧 Preview 对照

| 项目 | 修复前 | 修复后 |
|---|---|---|
| 分离模式财务化字段 | 待补/超额/net均0 | 保持0 |
| 分离模式source lines | `[]` | 保持`[]` |
| 已登记事实 | 未暴露 | 独立摘要字段和信息卡 |
| 无source | 误导性“没有可财务净额化source” | “当前没有已登记的待补或超额事实。” |
| 摘要读取失败 | 容易表现为0或无说明 | 明确失败文案，不显示0 |
| net模式 | 正式source lines | 保持原实现，不重复摘要 |
| unresolved | net Preview拒绝 | 继续拒绝，分离模式只显示未决数量 |

## 4. 袁振轩生产验收

目标：学生`4c6f1473-7d44-467d-a70b-30f02e7cf8cd`、业务归属`2cf7b72f-6e3c-4d09-80f7-7c58593cd466`、`2026-08`。

生产DB raw JSON与Chrome UI逐字段一致：

- 已登记待补：`7h / JPY63,000`
- 已登记超额：`1h / JPY9,000`
- 当前已登记净差额：`pending / 6h / JPY54,000`
- 已计入system difference的超额：`CNY373.50`
- unresolved planned：`6`
- 分离模式正式财务化待补、超额、net：仍全部`0`
- `projected system difference`：仍`+CNY373.50`
- 原`preview_manifest_sha256`：仍`53403da32a891321be8d12dadd157548b5680dd8b0e2d74e7ce412847a80f85d`
- 新摘要manifest：`00b96cd9e1820b945c09b60172bcebcb7061be3863f517337bcdeed5f5496a1b`

net Preview继续以`SETTLEMENT_LESSON_SOURCE_UNRESOLVED`拒绝；当前月status继续为`can_save=false / can_lock=false / SETTLEMENT_MONTH_NOT_CLOSED`，生产保存按钮始终disabled。

## 5. SQL、rehearsal与部署

文件：

- `sql/current/school_student_settlement_registered_variance_preview_20260816.sql`
- `sql/current/school_student_settlement_registered_variance_preview_exact_rollback_20260816.sql`
- `sql/current/school_student_settlement_registered_variance_preview_rollback_rehearsal_20260816.sql`
- `sql/current/school_student_settlement_registered_variance_preview_preflight_readonly_20260816.sql`
- `sql/current/school_student_settlement_registered_variance_preview_postdeploy_readonly_20260816.sql`
- `sql/current/school_student_settlement_registered_variance_preview_catalog_diagnostic_rollback_20260816.sql`

原定义MD5为`44c998671550d2288c7f4960d6d52fdc`，新定义MD5为`13fe9c288069ae785887559e6b475138`。完整rehearsal覆盖forward→exact rollback、袁振轩目标值、旧字段、pending-only、overage-only、mixed、partial余额、未来已取消来源、未来普通planned、无source、历史月、net正常source lines、net unresolved fail-closed和当前月Gate，全部最终ROLLBACK。

第一次正式postdeploy命中测试包装假阳性：ACL检查`position('=X/' ...)`误将合法`postgres=X/postgres`识别为PUBLIC grant。随即执行exact rollback并由独立连接证明原定义和业务指纹恢复；ROLLBACK诊断确认owner/ACL/security/search_path均正确。只将测试改为ACL item边界正则`(^|,)=X/`，再次完整rehearsal后重新部署，正式postdeploy通过。没有弱化权限或业务断言。

DB提交：`858eb46`。前端提交：`d904f2b`。Pages run [`31937341882`](https://github.com/polariss710/aozora_school_system_v2/actions/runs/31937341882)成功。

## 6. 前端与生产 Chrome

修改：`settlement.html`、`css/app.css`、`js/config.js`、`js/settlement-app.js`、`js/pages/settlement-page.js`、`js/pages/settlement-online-state.js`及相关静态/状态机测试。`part-time-work-api.js`、settlement API、writer、RPC参数、保存和锁定逻辑均未改。

生产Chrome仅打开袁振轩只读Preview、点击一次“重新预览”、读取Network/Console、设置390px视口并关闭dialog：

- Network 5个请求均为`school_get_student_monthly_settlement_online_status`或`school_preview_student_settlement_adjustment_dialog` reader；writer 0。
- Console error/warning：0。
- 桌面1710px：document/panel/body/card横向溢出均0；摘要卡526px。
- 390px：document 390、panel 364、body 332、摘要卡270px，四者横向溢出均0；单列summary为250px。
- 保存按钮在Preview前后均disabled；未保存、未锁定、未修改课时。

## 7. 测试

通过：

- JS语法检查：state/page/app及新测试。
- `student-settlement-registered-variance-preview-ui-test.mjs`。
- `student-settlement-registered-variance-preview-sql-static-test.mjs`。
- P0-F dialog Preview、online Phase C unit/static、settlement filter layout、trusted tool回归。
- 页面层`.rpc()`和直接insert/update/delete/upsert扫描为0。
- `git diff --check`。

## 8. 零业务数据变化证明

最终与preflight一致：

| 对象 | 行数 | MD5 |
|---|---:|---|
| lessons | 768 | `18a7a722128d80a0d8a9893429af4455` |
| settlements | 18 | `481ffa7ed5173da852f0f28ce66c2e9b` |
| source drafts | 1 | `c2a01866c1bfe9edd5eb559d6faf4a67` |
| adjustment drafts | 7 | `0b162413935ed3a35920d144faffbc52` |
| bills | 22 | `e50673ac998ee2d84573a076a64d3d42` |
| bill lessons | 330 | `e3e2e0044c17864bc66c7e2861176c8b` |
| revisions | 20 | `ffdc498a6e256aa29064f021f22e4b00` |
| income | 56 | `5410e66708a01d7017de7dc331d32674` |
| School Cash linkages | 44 | `f1c336c43533b9d9b81d88b6fa55feef` |
| wage locks/details | 104 / 624 | `bb9d5e027e482547ba4ca58b3731651a` / `b68ada9b934d4de511da93104228eb4b` |
| Storage objects | 57 | `62fac5521274c58c6f6982a0c690c134` |
| Gate | 3 | `b04952a0603194dd5592124bdee2f7d7` |
| Cash requests/CNY/JPY/accounts | 44 / 75 / 32 / 7 | `635bbfe049d06ffd1bbf88500d8ef2d1` / `b5d8b7d466532b90531814e5ccf61ad2` / `4606ae01e81710ccb6efb4504210f410` / `89b057e2cdeb7324ef73f73e252174f1` |

Gate继续为preview enabled / generate blocked / cash submit enabled。数据库持久变化仅一个只读函数定义/comment；业务行写入0、测试白名单业务写入0、真实writer调用0。

## 9. 受保护untracked文件

11份文件路径保持原状，SHA-256分别保持：

`75474786…`、`fd703860…`、`1047c2d6…`、`3e65e009…`、`272d0853…`、`5b11f064…`、`1f6f2cc5…`、`b8e02481…`、`5dc7c39c…`、`b9c13ddc…`、`7ed27844…`。未移动、未执行、未暂存、未提交。
