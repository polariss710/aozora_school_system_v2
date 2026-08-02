# School V2 学费 Cash External Transaction 不可变硬化结项

日期：2026-08-02

## 1. 结论

首次真实学费 Cash 全链保持正确终态，Cash CNY/JPY external transaction 已完成数据库与页面不可变硬化；普通手工 Cash transaction CRUD 不受影响；CNY 两位小数显示修复已上线；30项验收全部通过；Gate 已重新开放。当前不存在本轮 HARD STOP。

## 2. 业务模型扩展声明

- 新表、列、状态、日期/月、source、可写事实、权威源：`none`。
- 已批准语义变化：既有 CNY/JPY external transaction 创建后不可普通更新、复制或删除。
- 唯一创建权威：既有受控 external writer；普通 authenticated 路径仅维护普通流水。
- 保护层：数据库 trigger 最终防线，RLS/ACL/RPC fail-closed，页面只读呈现。
- 纠错：本轮不开放 reversal；未来须另行批准独立冲正流程。

## 3. Cash 数据库硬化

执行：

- `supabase-update-20260802-external-transaction-immutability.sql`
- `supabase-update-20260802-external-transaction-immutability-rollback-tests.sql`
- `supabase-update-20260802-external-transaction-immutability-postdeploy.sql`
- `sql/current/school_tuition_cash_external_transaction_immutability_postdeploy_20260802.sql`

部署完成：

- CNY/JPY 两个 `BEFORE UPDATE OR DELETE` trigger 均为 enabled；
- guard稳定返回`EXTERNAL_TRANSACTION_IMMUTABLE`；
- 两表各4条authenticated最小RLS策略，共8条；
- anon/PUBLIC表写权限及普通update/delete RPC execute已撤销；
- 四个普通RPC owner为postgres、security invoker、固定`search_path = pg_catalog, public`，保留authenticated/service role业务所需execute；
- canonical external判定覆盖created flag、source、event、idempotency、reference、external note、payload hash和external timestamp；
- 安全切换只修改trigger/RLS/ACL/function定义，未修改任何Cash业务行。

## 4. 30项矩阵

- 后端1–24：`24/24 PASS`。普通CNY增改删/复制及普通JPY CRUD通过；external CNY金额、日期、账户、文本、删除全部拒绝；external JPY update/delete拒绝；RLS、trigger、RPC、ACL对称；受控writer及approve幂等通过。
- 页面25–28：本地及GitHub Pages浏览器合同均`7/7 PASS`。External CNY/JPY无编辑、复制、删除入口；普通行三项入口保留；CNY为`1,120.50 CNY`；JPY零位规则不变。
- 29：所有`f3f10000-*` fixture写入同事务ROLLBACK。
- 30：Cash fixture residue `0 / 0 / 0 / 0`，School writer context/student fixture residue `0 / 0`。

写测试仅使用`f3f10000-*`固定fixture；未对任何真实transaction调用update/delete/copy/approve/reject。

## 5. 真实对象保护

| 对象 | 最终状态 |
|---|---|
| School income | `4a6efa01-82c4-4e61-b4ff-d558e52c1f16 / received / Cash已确认` |
| School linkage | `c6e0c77f-e5f3-461f-a9a9-8863ebc0e239 / synced / approved` |
| Cash request | `dd141707-9b9f-47c7-91fe-aaa243db13a6 / approved / 1120.50 CNY` |
| Cash transaction | `2feb333c-6228-4f57-a1fa-c8aa3d40616c / 1120.50 CNY / 2026-08-02 / 余额宝` |
| Cash transaction MD5 | `7c94d3e343e26713a54e779e1d3b53da` |

School income/linkage updated_at仍为首次真实approve callback时间；Cash request与transaction引用唯一一致。硬化未新增或修改真实Cash request/transaction。

## 6. 400元合法并发运营增量

- 旧余额基线：`111441.82 CNY`。
- 业务负责人批准的新余额基线：`111041.82 CNY`。
- 差异：`-400.00 CNY`，已明确确认为合法普通Cash运营支出。
- Codex未修改、删除、回滚、重新解释或测试该运营事实。
- 新基线：余额宝expense `37 / 124069.05 CNY`，CNY transaction `64`，JPY transaction `31`。
- 新64条CNY全集指纹：`8e5f62d1e256228b956ca7155bed65db`；部署、rollback、页面发布与Gate开放后保持不变。
- 本轮硬化造成的真实业务transaction增量：`0`。

## 7. 最终集合与分类

| 对象 | 最终 count / MD5 |
|---|---|
| School bills | `17 / b18f15673637280bf1455667ccd3cc00` |
| School income | `50 / 6d2b5b7a3b021007b857a261e4bdf94d` |
| School linkage | `36 / d8f8e4b8556c38fba9873d343aec16d3` |
| Billing identity | `15 / d8d72d5f886e363b80bca4aecfe22522` |
| Normalized relation | `256 / dfa2bdb71f812f4b2aa0a23613edf289` |
| Cash accounts | `7 / 89b057e2cdeb7324ef73f73e252174f1` |
| Cash requests | `35 / 4a7319eb294222cb5057ecfe262a885f` |
| Cash CNY transactions | `64 / 8e5f62d1e256228b956ca7155bed65db` |
| Cash JPY transactions | `31 / 95ab7cf8a8d167e9b052d3fc6b64614b` |

School分类：

- `7 ELIGIBLE_FOR_CASH_SUBMIT`，冻结CNY `108806.22`，carryover `107.50`；
- `8 ALREADY_SYNCED`；
- `2 BLOCKED_CONFLICT`；
- `0 ALREADY_SUBMITTED`。

其余7条eligible未由Codex提交。

## 8. Gate、部署与数据库写入

Gate执行记录：

1. 本轮开始前emergency disable正式`UPDATE 1 + COMMIT`，仅将`student_tuition_cash_submit`设为blocked；
2. 硬化与页面部署期间保持`enabled / enabled / blocked`；
3. Gate enable `commit=0`演练：`UPDATE 1 + ROLLBACK`；
4. Gate enable `commit=1`正式：`UPDATE 1 + COMMIT`；
5. 最终：`student_tuition_preview / generate / cash_submit = enabled / enabled / enabled`，release `tuition-cash-external-immutable-20260802`。

持久数据库写入：

- School：同一目标feature gate行的正式blocked与最终enabled配置写入；
- Cash：不可变安全DDL/RLS/ACL/RPC定义部署；
- 真实School/Cash业务行写入：`0`；
- rollback-only fixture写入：固定`f3f10000-*`白名单，最终残留0；
- commit whitelist test：未执行，因用户明确要求所有fixture写测试必须ROLLBACK。

## 9. 文件与Git

Cash页面版本`20260802-external-transaction-immutable-1`已部署至GitHub Pages并线上通过UI合同；Cash commit为`d2e99db`并已普通push。School本报告、Gate enable证据脚本及current-status由本阶段单独提交并普通push。两个既有保护文件未读取正文、未修改、未暂存。
