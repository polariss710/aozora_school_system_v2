# School V2 Cash 端新增支出实施报告（2026-08-04）

## 结论

Cash 端新增支出已按“School 先建普通业务 pending、再复用既有 Cash 审批链”安全恢复并上线，技术结论为 **Go**。本轮没有生成虚假生产 Cash request/transaction；第一笔真实业务提交及 Cash 人工审批属于业务验收，不是技术未完成项。

## 1. 实时 Git 与部署基线

- 初始分支：`main`。
- 初始 HEAD / `origin/main`：`06f4e0f19225430d87f5544c4d0912e372c920b9`，ahead/behind `0/0`。
- 初始工作区仅有六份受保护 untracked 文件；实现期间未修改、移动、删除、暂存或提交。
- 初始页面：`v10.5.3`；初始 Pages run：`30881223027`。
- 初始/最终相关 Edge：`request-cash-expense-confirmation v4`、`sync-cash-request-result v8`；旁证版本为 Cash confirmation `v8`、Cash income `v11`、part-time `v2`、tuition void `v5`。本轮 Edge 修改和部署均为 0。
- Gate 全程保持：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=enabled`。

## 2. 新 pending writer 完整签名与合同

```sql
public.school_create_pending_cash_expense_record_v1(
  p_client_request_id uuid,
  p_expense_date date,
  p_business_entity_id uuid,
  p_expense_category text,
  p_description text,
  p_currency text,
  p_amount numeric,
  p_reimbursement_status text,
  p_exchange_rate numeric default null,
  p_is_business_expense boolean default true,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_teacher_id uuid default null,
  p_student_id uuid default null,
  p_note text default null
)
```

该函数为 `SECURITY DEFINER`、固定 `search_path=pg_catalog, public`；仅 authenticated 有 EXECUTE，首段调用 DB 权威 active-admin 断言，anon/operator/read_only/inactive/no-membership/service_role 均拒绝。它只创建 `status=pending/source_type=manual_cash` 的 School 支出，`account_id/payment_method/Cash request/Cash transaction` 初始为空、attempt 为 0；创建事务不改 School 账户或流水，也不写 Cash DB。返回 canonical 支出、UUID、状态、创建人、渠道及幂等标记。

## 3. Schema、identity 与 creator audit

- 新增 `school_expense_records.cash_creation_event_id uuid NULL`：客户端每次打开新增弹窗生成稳定 UUID；非空唯一且不可变，历史/老师工资/School 直接支付为 NULL。
- 新增 `school_expense_records.created_by_user_id uuid NULL`：由 DB 从 `auth.uid()` 和 active membership 取得，外键到 `auth.users(id)`，不可变；历史 46 条不回填。
- `source_type` 未来使用 `manual_school` / `manual_cash`；`teacher_wage` 语义不变，历史 NULL 保持 legacy unknown。
- 新增审计一致性 check、4 个 Cash identity/request/transaction 局部唯一索引和 immutable trigger；未新增表、status、fallback、双写、历史解释或通用工作流。

## 4. 两条最终调用链

- School：页面 → `expense-api.js` → 既有 `school_create_expense_record(...)` → `paid/manual_school` → 一次扣减选定 School 账户 → 一条 School 账户流水。未创建 Cash request/transaction。
- Cash：页面 → `expense-api.js` → 新 pending writer → `pending/manual_cash` → 既有 Cash 确认弹窗 → `requestCashExpenseConfirmation()` → `request-cash-expense-confirmation v4` → School prepare → Cash external request → submitted/confirmed/rejected + `sync-cash-request-result v8`。批准后 Cash 建一条 transaction、School 标记 paid；School 账户和流水始终不变。

## 5. 修改文件

- 文档：`docs/school-v2-cash-expense-create-design-20260804.md`、本报告、`docs/current-status.md`。
- Schema/RPC/部署：`school_pending_cash_expense_identity_schema_20260804.sql`、`school_pending_cash_expense_identity_guard_20260804.sql`、`school_create_pending_cash_expense_record_v1_rpc.sql`、`school_create_expense_record_rpc.sql`、`school_expense_cash_request_backend_amount_rpc.sql`、`school_pending_cash_expense_backend_deploy_20260804.sql`、`school_pending_cash_expense_backend_rehearsal_20260804.sql`、`school_pending_cash_expense_backend_postdeploy_20260804.sql`、`school_pending_cash_expense_backend_rollback_tests_20260804.sql`、`school_p0_expense_permission_closure_rollback_tests_20260804.sql`。
- 页面/API：`expense.html`、`expense-detail.html`、`css/app.css`、`js/config.js`、`js/expense-app.js`、`js/expense-detail-app.js`、`js/api/expense-api.js`、`js/api/expense-detail-api.js`、`js/pages/expense-page.js`、`js/pages/expense-detail-page.js`、`scripts/cash-expense-create-static-test.mjs`。
- `js/legacy-core.js`、学费、工资业务、Storage 和 Edge 均未修改。

## 6. 权限矩阵

| Actor | 新 pending writer | School paid writer | Cash prepare/callback | 页面创建/提交控件 |
| --- | --- | --- | --- | --- |
| active admin | 允许 | 允许 | 不直调；经 Edge | 可见可执行 |
| operator/read_only | 拒绝 | 拒绝 | 拒绝 | 不可执行 |
| inactive/no membership | 拒绝 | 拒绝 | 拒绝 | 不可执行 |
| anon | 无 EXECUTE | 无 EXECUTE | 无 EXECUTE | 不可执行 |
| service_role | 交互 writer 拒绝 | 交互 writer 拒绝 | 仅既有 helper 允许 | 浏览器不存在 |

范围内底表没有新增 anon/authenticated 表级 DML；页面模块没有直接 `.rpc()` 或 insert/update/delete/upsert。

## 7. 业务事实权威

- 用户显式输入支出日期、分类、说明、原币金额/币种、business entity、报销/税务/票据等表单事实。
- DB writer 校验 business entity 与所有字段，并权威计算 `year_month`、JPY/CNY 折算结果；页面不计算任何持久化业务金额。
- Cash 第二阶段由 School DB 重读并冻结支出金额/状态；Cash DB 校验目标账户、币种和 `allow_school_requests`。同币种、跨币种、默认换算/舍入由 DB 权威；现有显式实际支付金额合同继续由服务端验证和冻结。

## 8. 顺序与并发幂等

- 同 identity + 同规范化 payload 顺序重试返回同一 expense，`idempotent=true`，不产生第二条记录。
- 同 identity + 不同 payload 以 SQLSTATE `23505`、稳定错误 `P0_PENDING_CASH_EXPENSE_IDENTITY_PAYLOAD_CONFLICT` fail-closed。
- 不同 identity + 相同 payload 允许成为两笔合法支出。
- 两个真实 DB 会话对同 identity 测试：第二会话被 blocking advisory lock 阻塞约 3 秒，最终无重复；测试事务全部回滚。

## 9. 两阶段失败恢复

- Stage 1 失败：事务原子回滚、Cash 变化 0，保留同一 identity 可安全重试。
- Stage 1 成功后取消：pending 保留、Cash request 为 0，列表/详情可继续“提交 Cash”。
- prepare 失败：不新建 Cash request，不新建第二条 School 支出。
- Cash 创建失败或 submitted 回写失败：复用既有 event/idempotency 恢复同一 request UUID；页面不引导重新新增支出。
- 未新增取消 writer；关闭确认弹窗不会删除记录。

## 10. School 余额和流水变化

| 阶段 | School 余额 | School 流水 |
| --- | ---: | ---: |
| pending 创建 | 0 | 0 |
| Cash prepare/submitted | 0 | 0 |
| Cash reject/retry | 0 | 0 |
| Cash approve + School paid | 0 | 0 |

既有 School 直接支付回归仍为一次余额扣减和一条流水。

## 11. Cash approve/reject/retry

更新后的 P0 回滚矩阵验证了新 `manual_cash` fixture 可进入既有 prepare；同币种、跨币种（700 JPY × DB 汇率 0.05 → 35 CNY）、显式 36 CNY、重试、reject、confirm、duplicate callback、错误 event/request/transaction 拒绝及 paid 后 School 余额/流水 0。老师工资来源仍被接受且合同未改变。所有调用均在生产事务内回滚，未创建真实 Cash request/transaction。

## 12. UI 文案和交互

- 默认：`从 School 账户直接支出`；说明 `保存后立即记为已支付，并扣减 School 账户余额。`；按钮 `保存 School 支出`。
- Cash：`提交至 Cash 审批`；说明 `先保存为待支付支出，再提交至 Cash 审批；不会扣减 School 账户余额。`；按钮 `保存并提交至 Cash`。
- Cash 模式隐藏 School 支付方式/账户，复用既有 Cash 确认弹窗选择 Cash 账户、币种和实际金额。
- 取消提示：`支出已保存为待提交，可稍后从支出列表提交 Cash。`
- 第二阶段失败提示：`支出已保存为待支付记录，但尚未成功提交至 Cash。请从支出列表重试。`
- 列表/详情仅对 `manual_cash` 和 `teacher_wage` 的合法 pending 开放既有提交入口，并显示来源与创建审计。

## 13. 验证结果

- 生产 migration rehearsal：实际 `BEGIN ... ROLLBACK`，验证新对象未持久化、旧函数定义哈希恢复。
- 回滚矩阵：新 writer 权限/输入/幂等/audit/paid 回归/Cash prepare 全通过；既有普通支出 P0 Cash 链矩阵更新后全通过；`e410/e420` fixture 全回滚。
- 双会话：相同 identity blocking advisory lock 通过。
- 静态：新 Cash UI、P0 permission、phase2、G1-B1 admin Cash 四套测试和所有变更 JS syntax 全通过；page direct RPC/DML 和浏览器 service-role 为 0。
- postdeploy：列、FK/check、4 个唯一索引、trigger、ACL、search_path、4 个函数定义及 Gate 全通过。
- Chrome：真实 active admin、页面 `v10.5.4`；默认 School 和 Cash 切换、精确文案、字段显隐、按钮均通过；点击取消而非提交。Console 只有版本 info，error/warning 为 0。

## 14. 双库白名单 E2E 与真实业务验收

未执行会 commit 的双库白名单 E2E。原因是仓库没有能够证明跨 School/Cash/Storage 完整清理且无需 DELETE 的隔离合同；按授权边界不得制造虚假生产 Cash request。已用生产事务回滚、双会话、既有链回滚矩阵、历史只读指纹和 Chrome 无写验收替代。

业务负责人下一步应以真实日期、分类、金额、币种、business entity 和备注创建第一笔支出，选择 Cash，确认生成一条 School pending 和一条 Cash pending request；随后在 Cash 作真实审批，核对仅一条 Cash transaction、School 状态 paid 且 School 余额/流水变化 0。

## 15. Fixture 与 residue

- 新 writer fixture：`e4200000-*`；权限/Cash 链 fixture：`e4100000-*`。
- 最终 School：fixture users/memberships/accounts/expenses/account transactions 均 0。
- 最终 Cash：fixture requests/CNY transactions/JPY transactions 均 0。
- Storage 新对象 0；本轮没有 Storage API 调用。

## 16. 历史回归指纹

- School 支出仍为 46：teacher_wage 17、legacy NULL source 29、manual_school/manual_cash 0；旧 schema shape MD5 `1a55bca9448e7549399f0a4abca99ac8`。
- School 账户 3、账户流水 186。
- Cash expense requests 17，MD5 `9fa87228ee67676af1a13cdb7acdcf7f`。
- Cash CNY expense transactions 12，MD5 `912c514fe973023f567036e1e8c36df2`；JPY 3，MD5 `654485db35df0657c0bf7121d464baa3`。
- 17 条老师工资 Cash 链未改变。

## 17. Storage orphan

既有 30 个 Storage orphan 保持未处理；本轮未删除、修改、补绑或调用 Storage。

## 18. Gate

终态仍为 `student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`，未复用或修改学费 Gate。

## 19. Commit、部署与 Pages

- 后端：`4973ae9c79806a6d0c730849648d2625870cb5f6`，已 push。
- School DB migration：`school_pending_cash_expense_backend_deploy_20260804.sql` 已正式 COMMIT；持久化写入仅 schema/RPC/trigger/ACL 定义，业务数据写入 0。
- UI：`8959d8968c1d63d56e54b55b0b421721b00fd386`，已 push。
- Pages：run `30885216682`，HEAD `8959d896...`，success。
- Edge：0 个文件修改、0 次部署；相关版本保持 expense confirmation `v4`、sync `v8`。

## 20. 最终 Git

文档封口提交/push 后在最终对话报告填写最终 HEAD、`origin/main`、ahead/behind 和工作区；合法提交不会 reset 或回退。

## 21. 六份受保护 untracked 文件

| 文件 | SHA-256 |
| --- | --- |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 22. 最终判定

**Cash 端新增支出已安全恢复并上线，技术 Go。** 没有遗留业务/安全 No-Go。唯一待办是业务负责人用第一笔真实支出完成端到端业务验收；不得由技术测试虚构或批准生产 Cash transaction。
