# School V2 P0-F 月结 42501 权限冲突修复报告

日期：2026-08-03  
Git 基线：`649c14eb08b726172dd95535286e07d3d2f59f97`  
功能提交：`fb3812c`（parent `649c14e`）、`1d3e08c`（parent `fb3812c`）

## 结论

42501 是浏览器 anon 对 writer RPC 缺少函数 `EXECUTE` 权限造成的，发生在函数体执行前，不是 RPC 内部表权限或 owner helper 权限错误。未发生部分写入。修复没有给 anon 增加 writer 权限，而是把真实月结写入收口到本机受信管理工具；生产页面仅保留 DB 只读 Preview，并隐藏保存、锁定、解锁、重锁入口。

业务模型扩展声明：新表 `none`；新列 `none`；新状态/金额/汇率/结转权威 `none`；历史解释或回填 `none`。仅新增 service-role-only 编排 wrapper、收紧 ACL、调整页面操作面和静态资源版本，复用 P0-F/P0-B2 既有 resolver、writer 和共享锁合同。

## 失败证据与根因

生产 Chrome 在 `v10.4.6 · settlement-error-i18n-20260803-1` 复现的首个失败请求：

- RPC：`school_set_student_settlement_source_treatment_draft`
- HTTP：`401`
- PostgREST body：`{"code":"42501","details":null,"hint":null,"message":"permission denied for function school_set_student_settlement_source_treatment_draft"}`
- role：浏览器 anon
- 参数：彭宇晗、青空进学塾、`2026-07`、`net_lesson_variance_to_financial_credit_v1`、rate `0.042`、source `business_owner_confirmed_monthly_settlement_rate_v1`、effective date `2026-07-01`及正式 reason
- 调用顺序：页面先调用 source-treatment draft writer；因此 adjustment writer 和 lock writer 尚未开始
- 精确位置：PostgreSQL 函数 EXECUTE ACL；函数体、表 DML、owner helper 均未进入

当时彭宇晗 2026-07 的 source draft、adjustment draft、settlement、lesson-variance claim、carryover 均为 0；generation/revision、Cash 与 Gate 未变化。不存在需要修复或清理的部分状态。

## 权限与实现

最终权限合同：

- anon：只允许正式只读 Preview；source draft、adjustment draft、lock、unlock、relock 均无 EXECUTE；业务表无 INSERT/UPDATE/DELETE/TRUNCATE。
- authenticated：未增加任何上述财务 writer 权限。
- service_role：仅可执行两个本机 wrapper。
- owner core/helper：继续 owner-only。

新增 wrapper：

- `school_save_student_settlement_draft_local(...)`
- `school_lock_student_monthly_settlement_local(...)`

两者均为 `SECURITY DEFINER`、固定 `search_path=pg_catalog, public`，校验 `auth.role()='service_role'`、固定 operator authority、完整 expected facts、manifest 和精确确认文本；先取得既有共享锁，再调用既有 owner writer/core，不复制任何结算公式。重复 lock 仅在 settlement、两份 consumed draft UUID/version、manifest、source count、claim count 和金额全部一致时返回原 settlement；否则稳定拒绝。

页面升级为 `v10.4.7 · settlement-trusted-tool-20260803-1`：

- 保留“更新数据库预览”；
- 保存按钮恒禁用，真实 lock/unlock/relock 不再显示；
- 显示“V2财务写操作请使用本机受信管理工具执行。”；
- `42501` 主文案为“当前页面没有执行该财务写操作的受信权限，请使用本机管理工具。”，次要位置保留错误代码。

生产 Chrome 强制刷新后，页面与 JS 资源版本一致、请求均 200、Console error/unhandled rejection 为 0；彭宇晗合法 Preview 显示 `-JPY17,000 + JPY2,125 = -JPY14,875 / -CNY624.75`，保存不可用。锁定后页面只读显示 locked、carry `-CNY624.75`，不显示解锁入口。

## 验证与数据保护

- wrapper rollback：错误确认、过期 manifest、缺/错 expected facts、过期 draft version、重复 lock exact-facts、ACL 全通过并回滚。
- P0-F 原回归：claimed source 重复消费、consumed settlement unlock/relock、直接 DML 等拒绝合同通过。
- 并发：P0-F lock 与 makeup writer 实际阻塞；本机 save-draft 双会话实际阻塞 `3.999329s`；Reissue scope 与 settlement scope 实际阻塞 `6.275927s`。全部 rollback，无 deadlock、半写或重复 claim。
- synthetic 固定 student：`f0f40000-0000-4000-8000-00000000a001`。committed save-draft 后精确清理；source/adjustment draft UUID 为 `56dc0791-a486-487e-9b9f-2a7700bed055` / `a4c26a21-e655-4620-be17-fa678a2a5326`；最终 School/Cash residue 0。committed lock 不用于 fixture，因为 immutable claim 不允许以破坏审计合同的 delete 清理；lock 在 rollback 矩阵和随后获授权的真实彭宇晗操作中完成验证。

部署的 SQL：`sql/current/school_tuition_p0f_local_settlement_management_20260803.sql`。执行结果仅为函数、ACL和 comment 元数据；没有真实业务行写入。测试 SQL：`sql/current/school_tuition_p0f_local_settlement_management_rollback_20260803.sql`，全事务回滚。

## Git 与受保护文件

实现及幂等收紧提交已随本轮最终交付普通 push 至 `origin/main`；报告提交为 `31d90d6`（parent `1d3e08c`）。最终 `git status --short` 仅列下述六份受保护 untracked 文件，无 tracked 修改。六份文件保持未跟踪且 SHA-256 不变：

- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`：`272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`：`b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`：`5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`：`b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`：`7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

Gate 终态：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=blocked`。
