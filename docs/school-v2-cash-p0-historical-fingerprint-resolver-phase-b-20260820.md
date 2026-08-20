# School V2 × Cash P0 Phase B：历史 fingerprint resolver 最小实现与本地验证

日期：2026-08-20
范围：仅本地实现和隔离验证；未部署、未提交、未调用真实 callback。

## 1. 结论

Phase 3C2-R 历史 immediate expense request 的 missing-fingerprint 兼容路径已完成最小实现。现有 schema 足以区分：

- 历史首次 callback：`submitted/version 1`；
- 回填时已终态：`approved_immediate|rejected/version 1`；
- 兼容恢复后的 exact replay：`approved_immediate|rejected/version 2`；
- native 正常 submitted/terminal：version 2/3，不可进入历史 resolver；
- native prepared 直接恢复：terminal/version 3 且 callback recovery 标志为真，不可进入。

本地 Gate 全部通过，允许进入 Phase C 的生产全事务 ROLLBACK 演练；本阶段没有部署或真实恢复。

## 2. Business-model expansion declaration

```text
New tables: none
New columns: none
New enum/status values: none
New date/month/attribution concepts: none
New identity concepts: none
New source concepts: none
New snapshot/version concepts: none
New writable facts: none
Changed existing-field semantics: none
Changed field mutability: none
Changed writer or reader authority: none；继续以School attempt冻结字段和Home request/transaction为各自权威
Changed locking rules: none
New authoritative sources: none
Legacy fallbacks or dual-read rules: 仅当Home snapshot真正缺字段时，允许Phase 3C2-R结构化历史resolver返回School DB重算fingerprint
Dual-write behavior: none
Historical reinterpretation: 既有status/version、submitted/terminal证据和callback recovery字段共同证明Phase 3C2-R历史生命周期
Destructive schema changes: none

Approval reference: 当前Phase B指令第3—7节明确批准historical resolver、missing-field分类、生命周期矩阵、service-role wrapper及既有DB canonical fingerprint authority。
```

兼容路径退休条件：24条Phase 3C2-R request不再需要callback replay，且生产监控确认不存在missing-fingerprint历史request后，另阶段移除resolver分支；不得扩大为一般NULL fallback。

## 3. Git与临时文件基线

- Home：`main`，HEAD/origin `4028903d845e2bb61980e43954317f80f50b4afd`，ahead/behind `0/0`。
- School：`main`，HEAD/origin `604ad40dd4c325168f09c48c03044ad52c17dbcb`，ahead/behind `0/0`。
- 两仓库起点均无P0重叠tracked修改。
- School原有16个top-level untracked项保持不动。
- Home `1necho`经确认路径、untracked、0字节普通文件且无引用后，按Phase B授权删除。
- 隔离PostgreSQL全部位于系统临时目录，测试结束后停止并删除；无fixture/build/coverage/lockfile残留。

## 4. 修改文件

- `sql/current/school_expense_cash_historical_fingerprint_resolver_v1_20260820.sql`
- `supabase/functions/_shared/expense-cash-attempt-v2.js`
- `supabase/functions/sync-cash-request-result/index.ts`
- `scripts/school-expense-cash-attempt-v2-edge-mock-test.mjs`
- `scripts/school-expense-cash-historical-resolver-local-test.mjs`
- 本报告。

Home业务源码、request Edge、页面、页面版本、fixed mapper/RPC、income mapper/RPC、既有callback core/signature均未修改。

## 5. 新增函数

### Owner-only core

`public.school_resolve_historical_expense_cash_attempt_fp_v1_core(...)`

### Service-role wrapper

`public.school_resolve_historical_expense_cash_attempt_fingerprint_v1(...)`

共同输入类型签名：

```text
(uuid,uuid,uuid,text,timestamptz,timestamptz,text,uuid,text,text,uuid,
 text,text,text,integer,numeric,text,numeric,text,uuid,date,uuid,uuid,uuid,
 text,numeric,text,uuid,date,text,text,uuid,text,text,uuid,text,boolean)
```

返回：

```text
(resolved_expense_id uuid,
 resolved_attempt_id uuid,
 resolved_attempt_status text,
 resolved_attempt_version integer,
 historical_shape text,
 resolved_request_payload_fingerprint text)
```

两个函数均为`STABLE / SECURITY DEFINER / search_path=pg_catalog, public / owner=postgres`。core仅postgres可执行；wrapper仅service_role和postgres可执行。

## 6. Resolver资格合同

共同必要条件：

- canonical `aozora_school / school_expense_records / expense_paid / expense`；
- `payment_route=immediate_account`；
- attempt no、expense/event/request/idempotency唯一关联；
- original及settlement金额/币种、账户、日期逐字段一致；
- Cash request、submitted时间和School expense镜像完整；
- callback recovery三字段必须保持未使用；
- 使用`school_expense_cash_attempt_payload_fingerprint_v2(...)`重算；
- 重算结果必须与attempt冻结fingerprint严格相同。

不使用teacher/source名称、备注、描述、cutover时间、运行时24-ID allowlist或常量fingerprint。

生产纯SELECT按实现后的完整predicate复核结果为`24 total / 24 eligible`；分布仍为`approved_immediate/v1=16`、`rejected/v1=2`、`submitted/v1=6`。本阶段没有在生产执行resolver migration。

## 7. 状态矩阵

| School形态 | Home终态 | resolver | callback结果 |
|---|---|---|---|
| submitted/v1 | approved | 允许 | approved_immediate/v2 |
| submitted/v1 | rejected | 允许 | rejected/v2 |
| approved_immediate/v1 | approved | 允许 | exact replay，version不变 |
| rejected/v1 | rejected | 允许 | exact replay，version不变 |
| approved_immediate/v2 | approved | 允许 | 兼容恢复后exact replay，version不变 |
| rejected/v2 | rejected | 允许 | 兼容恢复后exact replay，version不变 |
| submitted/v2 | 任意 | 拒绝 | native submitted不可误入 |
| native terminal/v3 | 任意 | 拒绝 | native terminal不可误入 |
| recovery flag=true | 任意 | 拒绝 | prepared直接恢复不可误入 |
| terminal与Home action冲突 | 冲突 | 拒绝 | `TERMINAL_CONFLICT` |

## 8. Home证据与唯一性

sync仍只接受body中的request ID和action；action必须与实时Home status一致，后续callback action从Home status推导。

只有immediate expense且snapshot字段真正不存在时，sync才：

1. 同时只读查询`home_jpy_transactions`和`home_cny_transactions`，防止跨币种表重复身份被掩盖；
2. 使用transaction ID、event、idempotency和reference的OR联合身份读取全部候选；
3. 不使用`LIMIT 1`；
4. approved要求恰好1条；rejected要求0条；
5. 将完整transaction证据传给School resolver；
6. resolver核验ID、user、type、amount/currency、account/date、scope、source/event、event type、reference、idempotency及`created_by_external`。

0条返回`HOME_TRANSACTION_MISSING`，多条返回`HOME_TRANSACTION_AMBIGUOUS`，字段冲突返回`HOME_TRANSACTION_EVIDENCE_CONFLICT`。

## 9. Shared与sync修改

Shared新增`inspectSchoolExpenseCashFingerprint()`：

- 字段存在且合法：native strict路径；
- 字段存在但空、格式错或长度错：继续拒绝；
- 字段真正不存在：仅返回`state=missing`；
- shared不生成fingerprint、不查DB、不判定历史；
- native fingerprint不能被resolver结果覆盖。

Sync顺序：认证 → Home request → user/status → income/expense/fixed分类 → immediate fingerprint分类 → 历史transaction唯一读取 → School resolver → 现有strict evidence → 现有confirmed/rejected V2 callback。

fixed和income不调用resolver。sync中不存在Home approve/reject/create request/create transaction writer，也不存在JS fingerprint算法。

## 10. ACL、RLS与原子边界

- core：PUBLIC/anon/authenticated/service_role无EXECUTE。
- wrapper：PUBLIC/anon/authenticated无EXECUTE；service_role有EXECUTE。
- 未增加service_role对attempt表的DML。
- 未改变attempt RLS/policy、expense权限或trigger。
- resolver全部为SELECT及DB canonical计算，不含INSERT/UPDATE/DELETE。
- resolver失败发生在现有callback writer之前。
- 状态更新仍由既有`school_apply_expense_cash_attempt_transition_v2`原子完成。

## 11. 测试结果

通过：

- JS/shared语法检查；
- TypeScript strip-types语法检查；
- Edge mock：native JPY/CNY、ordinary immediate、missing/malformed/wrong-length；
- approved/rejected历史首次恢复；
- backfilled terminal/v1 replay；
- compat terminal/v2 replay且version不增加；
- native v2/v3及recovery flag拒绝；
- transaction 0/1/many；
- fixed/income隔离；
- 本机隔离PostgreSQL实际加载fingerprint helper和resolver migration；
- owner/SECURITY/search_path/ACL；
- expense、attempt no/status/version、event、request、idempotency、route/type/source、两套金额币种、账户日期、reference、transaction全字段及重算fingerprint逐项负向测试。

成功标识：

```text
P0_HISTORICAL_RESOLVER_EDGE_MOCK_TEST_PASS
P0_HISTORICAL_RESOLVER_LOCAL_POSTGRES_TEST_PASS
```

已解决的测试环境失败：

1. 沙箱首次拒绝PostgreSQL共享内存；改为获准的本机临时实例后通过。
2. 首次临时实例输出管道被Postgres继承；精确停止/清理后增加独立日志文件，重跑通过。
3. 一条负向用例预期错误码比resolver前置identity guard更晚；修正测试预期后全部通过，resolver逻辑未放宽。

未解决失败：0。

## 12. 生产与发布状态

- 生产School DB migration执行：0
- 生产fixture/ROLLBACK测试：0
- Home/School业务数据写入：0
- 真实sync/callback调用：0
- Edge部署：0
- Pages部署：0
- commit/push：0
- 目标request/transaction/expense/attempt/wage lock修改：0

Phase C只能进行获准的生产全事务ROLLBACK演练；Phase D前不得正式部署，Phase E前不得恢复目标request。
