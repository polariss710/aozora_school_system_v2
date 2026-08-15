# School V2 私塾打工 PTW-P0-A2 Writer权限封口

## 结论

PTW-P0-A2于2026-08-16完成生产部署。业务模型扩展声明全部为`none`；没有新增表、字段、状态、日期/月度概念或历史解释。持久变化仅限12个既有函数的固定`search_path`、7个运营writer的DB membership guard、函数EXECUTE ACL，以及2个owner-only guard函数。业务行DML、真实writer、Cash调用、Storage对象操作均为0。

## R1准确修正与rehearsal

上一轮Attempt 1在preflight中由PL/pgSQL循环变量`r`遮蔽同名旧请求表别名，解析`r.deleted_at`时报错。失败连接退出后事务完整回滚；12个原始函数MD5/ACL、guard不存在状态和5张业务表指纹均与基线一致。

R1只做命名消歧：函数循环改为`fn_row`，函数重写循环改为`fn_rewrite_row`/`fn_restore_row`，业务指纹循环改为`fingerprint_row`，旧请求别名改为`legacy_req`；`deleted_at`、`cash_request_id`和`cash_transaction_id`均由`legacy_req`明确限定。未删除或弱化preflight、postcondition、角色合同或函数业务语义。精确回滚postcondition同时明确验证`postgres` owner和`SECURITY DEFINER`。

| 尝试 | 结果 | 事务与零变化证明 |
| --- | --- | --- |
| Attempt 1 | `record "r" has no field "deleted_at"`，技术失败 | 连接退出完整回滚；原12 MD5/ACL、guard不存在、5表指纹一致；writer成功调用0 |
| Attempt 2 | 全部事务内断言通过，输出`PTW_P0_A2_WRITER_PERMISSION_CLOSURE_REHEARSAL_ROLLBACK` | 明确ROLLBACK；独立连接确认原12 MD5/ACL/search_path恢复、guard不存在、5表/Storage/Gate/Cash指纹一致 |

正式部署后第一次负向探针使用全NULL参数，在planned writer的`DECLARE`初始化校验先触发“打工先无效”；该负向测试事务完整回滚，独立复核确认已部署权限和全部业务指纹不变。随后仅把探针替换为固定合成日期、时间、合法枚举和不存在UUID，并增加无membership合成UUID碰撞preflight；第二次14/14返回预期`42501` marker并ROLLBACK。

## 最终12个Writer权限矩阵

全部函数owner为`postgres`、`SECURITY DEFINER=true`、`search_path=pg_catalog, public`，PUBLIC与anon均无EXECUTE。

| 函数 | 合同 | authenticated | service_role | DB内部约束 |
| --- | --- | --- | --- | --- |
| `school_create_part_time_work_planned_lesson(...)` | 运营课时 | EXECUTE | 拒绝 | active admin/operator |
| `school_update_part_time_work_lesson(...)` | 运营课时 | EXECUTE | 拒绝 | active admin/operator |
| `school_generate_part_time_work_actual_from_planned(...)` | 运营课时 | EXECUTE | 拒绝 | active admin/operator |
| `school_delete_part_time_work_lesson(...)` | 运营课时 | EXECUTE | 拒绝 | active admin/operator |
| `school_lock_part_time_work_monthly_settlement(...)` | 财务 | EXECUTE | 拒绝 | active admin |
| `school_unlock_part_time_work_monthly_settlement(...)` | 财务 | EXECUTE | 拒绝 | active admin |
| `school_create_part_time_work_income_record(uuid)` | 财务 | EXECUTE | 拒绝 | active admin |
| `school_create_part_time_work_income_request(uuid)` | 旧入口退役 | 拒绝 | 拒绝 | owner-only |
| `school_mark_part_time_work_cash_request_submitted(...)` | 旧回调退役 | 拒绝 | 拒绝 | owner-only |
| `school_mark_part_time_work_cash_income_confirmed(...)` | 旧回调退役 | 拒绝 | 拒绝 | owner-only |
| `school_mark_part_time_work_cash_income_rejected(...)` | 旧回调退役 | 拒绝 | 拒绝 | owner-only |
| `school_import_historical_part_time_work_batch(jsonb)` | 历史导入 | 拒绝 | EXECUTE | 既有service-role-only |

本地矩阵覆盖active admin、active operator、read_only、inactive、无membership、authless、未知角色以及anon/authenticated/service_role/owner ACL，最终ROLLBACK。生产负向测试覆盖7个运营writer的authless和无membership拒绝，共14/14；anon由函数ACL在进入正文前拒绝，4个旧writer对authenticated/service_role均无EXECUTE。

## 4个旧Writer调用方证据

仓库运行时代码、`.github`、数据库函数/trigger依赖和动态RPC拼接均未发现4个旧名称。生产已部署8个Edge Function重新下载核对：`request-cash-part-time-income-confirmation`固定返回HTTP 410；`sync-cash-request-result`对`school_part_time_work_income_requests`和旧request type固定返回HTTP 410，动态RPC仅选择通用`school_mark_cash_income_*`/`school_mark_cash_expense_*`。

唯一旧请求`03f1e649-44f6-4da9-a94a-01758dece591`与settlement `7709246d-cda6-412a-b571-c008c6fdcca7`均已soft-delete，无Cash request/transaction UUID；活动旧请求0、带Cash引用旧请求0。Cash库中旧外部引用0。因此4个旧writer全部owner-only退役，不保留service-role旁路。

## 文件与恢复

- 正式migration：`sql/current/school_part_time_work_p0_a2_writer_permission_closure_20260816.sql`
- 精确回滚：`sql/current/school_part_time_work_p0_a2_writer_permission_closure_exact_rollback_20260816.sql`
- 生产负向测试：`sql/current/school_part_time_work_p0_a2_writer_permission_negative_rollback_tests_20260816.sql`
- 生产只读验收：`sql/current/school_part_time_work_p0_a2_writer_permission_postdeploy_readonly_20260816.sql`
- 本地角色矩阵：`sql/tests/school_part_time_work_p0_a2_role_matrix_local_20260816.sql`
- 静态门禁：`scripts/part-time-work-p0-a2-permission-static-test.mjs`

六份草案修正前SHA-256依次为`e7d2fb90…`、`d561708a…`、`028cd663…`、`f4c6d80b…`、`68083085…`、`2758a83f…`；作为全新untracked文件，修正前新增差异合计1033行。精确回滚保留原12个定义MD5、owner、SECURITY DEFINER、`search_path=public`和部署前EXECUTE ACL；正常流程未执行回滚。

## 零业务变化证明

| 对象 | 部署前后行数 | 部署前后整行MD5 |
| --- | ---: | --- |
| `school_income_records` | 56 | `5410e66708a01d7017de7dc331d32674` |
| `school_part_time_work_income_requests` | 1 | `3911bf3d82fba1b2f825c5510af0feb9` |
| `school_part_time_work_lessons` | 651 | `56047b966a14e46bcc9fada5fe2e7fea` |
| `school_part_time_work_monthly_settlement_details` | 289 | `7fb549166e78b2f7e09dcbfd85a6aac5` |
| `school_part_time_work_monthly_settlements` | 28 | `ef867ba66009e1ae602b58717f90e99a` |

Storage保持57对象、6,936,405 bytes、整行MD5 `62fac5521274c58c6f6982a0c690c134`。Gate保持3行、MD5 `b04952a0603194dd5592124bdee2f7d7`和`preview=enabled / generate=blocked / cash_submit=enabled`。Cash中School范围request/CNY/JPY分别保持44/38/3，MD5分别为`635bbfe049d06ffd1bbf88500d8ef2d1`、`b93aa52d1030a922811fdeef8d087e01`、`654485db35df0657c0bf7121d464baa3`；fixture residue 0。

11份受保护untracked文件在P0前后SHA-256逐项不变，未修改、移动、执行、暂存或提交。PTW-P1-B在本P0独立交付后另行开始。
