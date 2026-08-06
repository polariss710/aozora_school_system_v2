# School V2 李天伦＋吴峰 11-ID Exact Void/Correction 完成报告

## 结论

- 11 条已批准的 2026-09～11 测试/误建课时已使用 `voided_at/void_reason` 前向纠正；未物理删除课时或 legacy evidence。
- 正式 RPC `school_correct_li_wu_test_lessons_v1(text,text,text)` 仅调用一次，返回 11 条 `applied`，事务内断言通过后于 `2026-08-06 15:32:40.160387+00` COMMIT。
- 仅 `voided_at`、`void_reason`、`updated_at` 发生变化；status、duration、actual_minutes、lesson_fee、is_billable、来源和结算月份均保持原值。
- 11 条审计事件完整；学费候选由 4 条 / JPY 104,000 降为 0，工资候选由 3 条降为 0，raw remaining 由 -2 前向恢复为 2。
- planned legacy evidence 保持 7 条、MD5 `11b2bfdadaf78e6b4d853044c64f576d`；actual legacy evidence 保持 4 条、MD5 `f5c2e715af4180af16576c32eb46f0ad`。
- 账单、月结、收入、工资锁/调整、Cash linkage、claim 等批准检查对象仍为 0；Gate 保持 `enabled / blocked / enabled`，signup 保持 disabled，mailer autoconfirm 保持 false。
- 未写 Cash DB，未修改 11-ID 以外真实业务记录，未关闭 trigger、RLS 或不可变保护。

## Exact-ID 范围

Planned 7 条：

- `f256bca9-fac5-4909-b113-8077efd27d65`
- `a722a49e-dbe5-447d-8068-fd5fb743f6ab`
- `265f4d3d-2372-42e3-aec3-b963bbdddf95`
- `552c54e3-2d0c-4607-962d-aad39dfff7f7`
- `ac16b068-a58b-4ca5-be95-7c57c3f1b82b`
- `f759623b-ce28-4c5f-8556-95c4381b6b1b`
- `39aa30ab-d66c-43c0-bbde-3b3a35d71fb7`

Actual 4 条：

- `e890424d-407d-4fc2-b8ad-84745b242cdd`
- `b186fa1c-a56b-4ed7-b566-178a5708ae96`
- `dc06b98c-360f-4661-a294-52ecb82830a7`
- `c582a187-32f6-4a24-bb7b-d590b25c1854`

正式 manifest：`e2bc9f4380f5bf5a95ff0341ae47183b`。

## Trigger/RPC 收敛与演练

业务模型扩展声明为 `none`：未新增业务表、字段、状态、权威来源、双写或历史解释。实现只使用已经批准的 exact void 语义、现有审计对象和 reader 过滤。

四条 Actual 的旧 trigger 顺序会对 cancelled/makeup 历史行自动规范化 fee/minutes/billable；最终 exact 分支在固定 batch、manifest、actor、11-ID 与逐行旧哈希全部匹配时仅允许 void 三字段变化，并仍继续执行普通来源锁、余额和不可变检查。同步分钟 trigger 与财务 authority trigger 同时拒绝伪造的显式 minutes/fee 变化，避免前序规范化掩盖攻击；resolver 只对“Actual 与来源 Planned 同批已 Void”的 legacy evidence 路径保留既有解析。

最终生产函数 MD5：

- exact correction RPC：`02240223f82a28820cfc7309c1fd49e6`
- lesson writer P0 trigger：`e5ed12c9897e802fbcc8da699cc9ef5f`
- actual minutes trigger：`87e7587d601f3fe1b2abdec35742e2cc`
- financial authority trigger：`dbc0e193fdd42b940beae7677e1681a6`
- legacy Actual month resolver：`d8a1f092429f9c4ad6918ee680514e4b`

完整整笔 ROLLBACK rehearsal 从原始 11 行开始，覆盖 manifest/audit/evidence/raw/candidate、RPC 11 行返回、void-only diff、历史 Actual fee/minutes/billable、reader、候选归零和 rollback 恢复，结果：

- `LI_WU_CORRECTION_PRODUCTION_REHEARSAL_IN_TRANSACTION_PASS`
- `LI_WU_CORRECTION_PRODUCTION_REHEARSAL_ROLLBACK_PASS`

最终实时只读 preflight 结果：`LI_WU_FINAL_READONLY_PREFLIGHT_PASS`。正式 COMMIT 后独立只读校验结果：`LI_WU_POST_CORRECTION_READONLY_VERIFY_PASS`。

## 正式写入与结果

- batch：`li_wu_2026_09_11_test_lessons_void_v1_20260806`
- actor：`25331ae9-3412-48b9-bdc3-e516caeaeba4`
- lesson writes：11 条 exact void update
- audit writes：11 条 append-only correction event
- 正式 RPC 调用次数：1
- 其他真实业务表写入：0
- Cash DB 写入：0
- rollback/角色测试 fixture：仅事务内 `be130000-*`，最终 residue 0

四条 Actual 历史事实保持：

- `e890…`：completed / 2h / 120min / JPY26,000 / billable true
- `b186…`：cancelled / 2h / 120min / JPY26,000 / billable false
- `dc06…`：makeup_completed / 2h / 120min / JPY26,000 / billable true
- `c582…`：makeup_completed / 2h / NULL minutes / JPY26,000 / billable false

## Reader/API/UI

- lesson API 默认排除所有 voided Planned/Actual；“已作废”读取所有 voided 记录；跨月来源配对按当前 active/voided 视图一致过滤。
- wage API 两条候选查询均增加 `voided_at IS NULL`。
- 生产校验发现页面层仍残留 `isVoidedPlanned()`，导致 DB/API 已返回的四条 Void Actual 被二次过滤；已最小改为任何 `voided_at`，详情页也对 Void Actual 显示“已作废”，版本升至 `v10.5.14`。
- page-layer 未新增 `.rpc()` 或表 DML，`js/legacy-core.js` 未修改，未恢复 business entity UI，浏览器未使用 service-role。

## 代码、SQL 与部署

任务 SQL：

- `sql/current/school_li_wu_exact_correction_schema_20260806.sql`
- `sql/current/school_li_wu_exact_correction_baseline_readonly_20260806.sql`
- `sql/current/school_li_wu_exact_correction_rpc_readers_20260806.sql`
- `sql/current/school_li_wu_exact_correction_role_rollback_test_20260806.sql`
- `sql/current/school_li_wu_exact_correction_production_rollback_rehearsal_20260806.sql`

提交：

- `e317c07fc5c44eecb084a8de72bcfa0a703d9b30`：exact correction trigger/RPC、reader/API、wage 过滤及 `v10.5.13`
- `2a399dc80753fedb0aabf8c6bc67f49a301953ce`：Void Actual 页面二次过滤修复及 `v10.5.14`

Pages：`v10.5.13` run `31113670351` attempt 3 success；`v10.5.14` run `31116902526` 同 SHA rerun 状态待最终记录。

## 保护文件与边界

六份既有 untracked 保护文件未修改、移动、执行、暂存或提交。未使用 `git add -A`、`git add .`、stash、clean、reset 或覆盖合法提交。BE-P0/BE-UI 权限和页面合同未回退，Gate/signup 未变化。
