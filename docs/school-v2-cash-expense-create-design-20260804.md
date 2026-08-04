# School V2 Cash 端新增支出正式设计（2026-08-04）

## 状态

- 当前阶段：后端、前端与生产部署均已完成；双库终态只读审计、回滚矩阵、双会话、静态检查、Pages 与 Chrome 无写验收通过。技术结论为 Go，第一笔真实业务 Cash 支出由业务负责人执行。
- 业务授权：本轮任务《恢复“Cash端新增支出”——正式设计、实现、部署与验收》及其明确引用的两阶段 P0 权限封口结论。
- 非目标：学费 Gate、历史 30 条孤儿数据、历史支出回填、删除式测试清理、Cash Edge 协议改造。

## 唯一业务事实与权威来源

| 事实 | 唯一权威来源 | 写入规则 |
| --- | --- | --- |
| 普通支出的原币、金额、汇率、折算金额、年月 | School DB writer | 前端只提交显式用户输入；折算金额与年月由 RPC 计算 |
| 创建渠道 | `school_expense_records.source_type` | `manual_school` 或 `manual_cash`，创建后不可变 |
| 创建人 | `school_expense_records.created_by_user_id` | RPC 从 `auth.uid()`/active-admin membership 取得，前端不可传 |
| Cash 创建动作身份 | `school_expense_records.cash_creation_event_id` | 前端生成稳定 UUID；同键唯一、同载荷幂等、异载荷失败 |
| School 账户余额和流水 | School paid writer | 仅 School 直接支付模式写入 |
| Cash 支付请求和 Cash 交易 | 既有 Cash Edge / Cash DB writer | 仅第一阶段 School pending 记录成功后发起 |

## 获批业务模型扩展声明

- 新增可空列 `school_expense_records.cash_creation_event_id uuid`：只用于未来 `manual_cash` 创建动作，非空值唯一且不可变；历史、老师工资、School 直接支付记录均为 `NULL`。
- 新增可空列 `school_expense_records.created_by_user_id uuid`：未来普通支出的数据库权威创建人，外键到 `auth.users(id)`；该 UUID 同时是 `school_app_memberships.user_id`，不可变；不回填历史。
- 新增未来 `source_type` 值 `manual_school`、`manual_cash`；`teacher_wage` 语义不变，历史 `NULL` 保持未知来源。
- 不新增表、status、Cash 业务快照、取消 writer、双写、fallback 或历史兼容分支。

## 两条创建路径

### School 直接支付（默认）

1. active admin 调用既有 `school_create_expense_record`。
2. RPC 写一条 `status='paid'`、`source_type='manual_school'` 的支出，记录数据库创建人。
3. RPC 在同一事务扣减一个 School 账户余额并写一条负数 `expense_adjust` 流水。
4. 既有财务含义、校验和原子性不变。

### Cash 审批支付

1. active admin 调用新 `school_create_pending_cash_expense_record_v1`。
2. RPC 写一条 `status='pending'`、`source_type='manual_cash'` 的 School 权威支出；`account_id`、`payment_method` 和全部 Cash 回写字段初始为空，attempt 为 0。
3. 第一阶段明确不改 School 账户余额、不写 School 账户流水、不写 Cash DB。
4. 页面拿 RPC 返回的完整权威记录，进入既有 `request-cash-expense-confirmation` Edge 链；Cash 账户与支付币种在第二阶段选择。
5. Cash 请求成功后沿用既有 School service-only callback；拒绝、批准和同步语义不变。

## 幂等与并发

- 页面每次打开新增对话框生成一个稳定 `client_request_id`；失败重试继续使用，关闭并新开才换新 UUID。
- writer 先按该 UUID 获取 blocking transaction advisory lock，再查询唯一索引。
- 已有同键记录时比较全部规范化创建载荷；相同则返回同一记录并标记 `idempotent=true`，不同则以 `P0_PENDING_CASH_EXPENSE_IDENTITY_PAYLOAD_CONFLICT` 失败。
- 记录后续进入 Cash pending/paid 状态不改变创建载荷的幂等身份；创建身份和创建渠道由 trigger 禁止更新。

## 权限边界

- 两个普通支出创建 writer：仅 `authenticated` 可执行，函数内部强制 `school_require_current_app_admin()`。
- Cash prepare / submitted / confirmed / rejected：继续仅 `service_role` 可执行。
- `anon`、普通 operator、read-only、inactive admin、无 membership 用户均不能创建。
- 页面模块不直接 `.rpc()` 或写表；所有 Supabase RPC 调用集中在 API 层。

## 测试与发布约束

- 后端部署包装器在一个事务内依次执行 schema、immutable guard、paid writer、pending writer、Cash prepare writer。
- 生产演练必须显式 `ROLLBACK`，并验证新对象未持久化、旧函数定义哈希恢复。
- 功能测试使用 `e4200000-*` 白名单 fixture，所有行和账务效果在同一事务回滚。
- 不通过提交后 `DELETE` 清理测试数据，因此不执行会留下真实 School/Cash 记录的跨库 commit E2E；首个真实 Cash 业务动作留给业务负责人。
- 后端 SQL 必须先 commit/push，之后才允许正式 DB 部署；DB postdeploy 通过后才实施前端。

## 最终发布结论

- School DB 已正式部署最小 identity/creator audit schema、新 pending writer、paid writer audit 补强及 Cash prepare 来源约束。
- 页面版本为 `v10.5.4`；Pages run `30885216682` 成功，未修改或部署任何 Cash Edge Function。
- 生产浏览器仅完成 active-admin 无写验收：验证两种处理方式、默认 School、Cash 字段切换、文案和按钮后取消弹窗；未创建 School 支出、Cash request 或 Cash transaction。
- 没有可证明能跨 School/Cash/Storage 完整清理的双库白名单 E2E，因此未制造虚假生产 Cash request；这不构成技术未完成，剩余步骤是业务负责人使用真实业务事实提交第一笔支出并观察既有审批链。
