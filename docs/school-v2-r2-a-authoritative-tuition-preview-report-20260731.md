# R2-A 权威学费月份与 validation preview detail 交付报告

日期：2026-07-31
Git 基线：`46632137d2597006f1c32985fae971fd14612772`

## 结果

新增只读 RPC：

```sql
public.school_get_student_tuition_validation_preview_details(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric
)
```

函数为 `STABLE SECURITY DEFINER`，固定 `search_path=pg_catalog, public`。`PUBLIC`、`anon` 无执行权，`authenticated` 与 `service_role` 可执行；内部 canonical reader `school_list_student_tuition_candidates(uuid,uuid,text,boolean)` 仍仅允许 `service_role`，ACL 与函数定义均未改变。

RPC 先调用既有 `school_preview_student_tuition_bill`，复用其 R0 与 School preview 边界；再调用 canonical candidate reader，并仅按 reader 返回的 planned UUID 读取权威 `billing_week_start_date`。未复制 candidate 筛选规则，未连接 Cash，未调用 generate，未创建或修改 bill、income 或 lesson。

返回同一快照的 preview 状态、学生、业务归属、学费月份、结转、candidate/课次数/时长/JPY 费用、通知汇率与金额、既有应收状态、UUID MD5、manifest SHA-256 及稳定排序的 candidate JSON 明细。每条明细包含 planned UUID、学生、业务归属、`billing_month`、`billing_week_start_date`、`lesson_date`、课次数、时长和服务端费用。

服务端在返回前 fail-closed 校验 UUID 唯一性、请求归属、月份、周一、自然周所属月份、汇总/明细一致性及 JSON 数量；未静默去重。

## 数据库执行

- 完整 rollback rehearsal 通过，函数残留 0。
- 正式执行 `sql/current/school_tuition_r2_a_validation_preview_details.sql` 并 COMMIT 成功。
- 函数定义 MD5：`13fbc4d680d3b223cd2c6b59d66f2384`。
- canonical candidate reader MD5 保持 `8981a2ce07abf8c28231bfaf05451368`。
- 正式部署后 `postdeploy` 与独立 rollback tests 均通过。
- authenticated 实际调用成功；anon 实际调用被拒绝；PUBLIC 无执行 ACL。
- rollback tests 唯一 DML 是事务内把 preview gate 临时改为 `blocked`，验证 RPC fail-closed 后 `ROLLBACK`，残留 0。
- 最终 R0：preview=`validation_preview_only`，generate=`blocked`，cash_submit=`blocked`。
- 最终业务行计数：lesson 652、tuition bill 9、income 42；部署前后业务 fingerprint 不变。

真实 2026-08 validation preview 返回 30 个唯一 candidate、35 课次、65 小时、JPY 650,000；UUID MD5 为 `29389fd78b127bc9b42cf90559e2ac56`，manifest SHA-256 为 `79b9119d4f6ed50dd187c448b80c91160ee9f7e26cc2c411bec4ad767b707c74`。响应不含 `2026-07-27` 起始周，包含 `2026-08-31` 起始周。数据库权威周期检查确认 `2026-07-27～2026-08-02` 只属于 2026-07，`2026-08-31～2026-09-06` 属于 2026-08。

## 前端

`income.html` 通过 `js/api/income-api.js` 调用新 RPC；页面模块没有直接 `.rpc()` 或表写。页面显示 validation-only 状态、权威学费月份、自然周、实际 lesson date、planned UUID 与服务端费用。学生、月份或汇率变化会清空旧结果；request token 阻止旧响应覆盖新选择；加载锁阻止连续点击；每次渲染替换 candidate 表而非追加。

前端再次 fail-closed 校验响应的学生/业务归属/月/汇率、UUID 唯一性、稳定顺序及汇总/明细一致性。校验时累加明细仅用于识别契约漂移；显示金额始终直接使用 RPC 返回值，不按 duration、unit price 或 overage 重算。正式 generate 按钮继续禁用，Cash 提交继续阻断。

fixture 覆盖并通过：

- 2026-07 包含 `2026-07-27～2026-08-02`；
- 2026-08 排除该周并包含 `2026-08-31～2026-09-06`；
- lesson date 跨月不改变 billing month；
- 重复 UUID、汇总不一致均拒绝渲染；
- 旧请求不覆盖新月份，刷新不重复追加；
- 页面直接使用服务端 fee，generate/Cash 保持 blocked。

## 修正记录与剩余边界

正式部署没有 SQL 错误。部署前 rehearsal 共修正 3 项：PUBLIC ACL 检查方式、PL/pgSQL 输出变量歧义、postdeploy 版本函数名。前端测试共修正 2 项误报断言：普通 `Set.delete()` 被误识别为表写、维护文案断言不精确。最终 postdeploy 首次调用因非交互 shell 未加载 `load_both_db`，数据库尚未连接；改用既有交互式 zsh 后通过。另将验收中当前 candidate 数量/金额的固定断言改为动态内部一致性，避免未来运营数据变化造成不可重放。

仍存在正式 generate 恢复前需要单独处理的后端缺口：当前 canonical candidate reader 对新的 F1 `explicit_billing_week_at_create` 来源尚未纳入允许来源，因此真实 `2026-07-27` planned 行目前被标记为 `invalid_or_incomplete_data`。本阶段没有修改 candidate 业务规则，也没有解除 R0。
