# School V2 × Cash Phase 3C2-R 即时账户 attempt 正式接入报告

## 1. Phase 3C2-R结论

Phase 3C2-R已完成并正式启用。School即时账户Cash支出链现在由V2 prepare/submitted/approved/rejected RPC原子维护`school_expense_records` latest-state兼容镜像与`school_expense_cash_attempts`逐attempt审计状态；request/sync两个Edge均已部署并只向V2合同提交完整结构化证据。

`cash_expense_attempt_writer_v2_enabled=enabled`；旧四个expense Cash签名在该Gate启用后DB fail closed。`cash_fixed_credit_card_route_enabled`始终为`blocked`，fixed attempt/request/projection/statement cycle及home写入均为0。

## 2. School/home/Git/生产基线

- School初始HEAD/origin/main：`b2872056e9e55d4d8fcac601ccdc7b6910d0253e`，ahead/behind `0/0`，tracked/staged 0；仅原16个受保护untracked对象。
- home HEAD/origin/main：`3880722c6b3da48a3012a17622429b9ded58e9d8`，ahead/behind `0/0`，工作树干净；全阶段未修改。
- School页面版本：`v10.5.54`，未修改页面/API静态资源。
- 初始attempt：24（approved_immediate 16、submitted 6、rejected 2、fixed 0）；expense 53；latest-state滞后0。
- 初始Cash：external request 50，School expense request 24（pending 6、approved 16、rejected 2），JPY transaction 35，CNY transaction 75。
- 初始/最终home request指纹：`764fe302dcf1eaccd148f518898cc33b`；JPY/CNY transaction指纹分别为`d0386dfd604ee54fe9ce42915b40bd32`、`6ae2f6eb0a6bce4d86244777e71a0272`。
- 切换窗口前后Cash request均为50，最大`requested_at=2026-08-18 13:00:12.729199+00`，School expense request均为24；未出现legacy drift。

## 3. attempt新增字段及历史回填

`school_expense_cash_attempts`由30列增加至36列：

- `payment_amount numeric NOT NULL`：逐attempt实际Cash请求金额；
- `payment_currency text NOT NULL`：逐attempt实际Cash请求币种；
- `request_payload_fingerprint text GENERATED ALWAYS ... STORED NOT NULL`：DB调用owner-only immutable helper生成的SHA-256；
- `callback_recovered_from_prepared boolean NOT NULL DEFAULT false`；
- `callback_recovered_at timestamptz`；
- `callback_recovery_source text`，恢复时固定为`sync-cash-request-result-v2`。

指纹覆盖canonical external source/reference/transaction type、expense ID、attempt number、request type、payment route、event、idempotency key、School原始金额/币种、Cash实际请求金额/币种、funding account及charge date；状态、批准/拒绝时间和error不进入原始请求指纹。

24条历史记录只使用`home_external_transaction_requests`中唯一`aozora_school + school_expense_records + expense_paid`映射回填，并逐字段验证request/event/idempotency/account/amount/currency/transacted date/transaction。未使用名称、备注或模糊文本。回填后24/24均有合法64位指纹，恢复标志均为false，原30列指纹`cdeae8f7929556445447fd26df887223`、状态、主键及映射不变。

回填在单一锁表迁移事务中短暂禁用既有attempt trigger，仅用于新增快照列从NULL到确定值；随后立即重新启用并以V2 transition-aware定义替换。日常writer不存在trigger bypass。

## 4. V2 RPC及helper

新增service-role业务wrapper：

- `school_request_cash_expense_payment_confirmation_v2(...)`
- `school_mark_cash_expense_request_submitted_v2(...)`
- `school_mark_cash_expense_confirmed_v2(...)`
- `school_mark_cash_expense_rejected_v2(...)`

新增postgres-only helper：

- `school_expense_cash_attempt_payload_fingerprint_v2(...)`
- `school_apply_expense_cash_attempt_transition_v2(...)`

核心转换固定锁序为expense→attempt，验证完整Cash证据后在一个School事务内更新attempt与expense镜像。旧prepare/submitted/confirmed/rejected签名保留既有ACL，但函数体在V2 Gate enabled时抛出`SCHOOL_EXPENSE_CASH_LEGACY_RPC_DISABLED`。

## 5. prepare规范payload合同

V2 prepare接收实际支付日、用户显式金额或DB计算意图、币种、Cash账户、external reference及必要身份字段。DB执行：

1. Gate和source/audit invariant检查；
2. expense `FOR UPDATE`；
3. 同币种默认金额或跨币种按既有rate/rounding合同计算；
4. 创建唯一`prepared` immediate attempt，或逐字段完全一致时返回既有prepared；
5. DB生成event、attempt number、idempotency和payload fingerprint；
6. 同事务更新expense latest-state镜像；
7. 返回完整`cash_payload_snapshot`、Cash description及Cash writer全部参数。

request Edge通过`buildCashCreateRpcPayload()`只使用prepare V2返回值创建Cash request，不再在prepare之后用浏览器金额、币种、账户或日期重拼业务payload。实际支付日不得回退为expense date或当前日期。

## 6. submitted/approved/rejected转换

request Edge在Cash create成功或幂等返回后重新读取该Cash request完整结构化行，再调用submitted V2。School逐字段比较event、idempotency、request/reference/type、amount/currency/account/transacted date及payload fingerprint，只有完全一致才允许`prepared→submitted`并version +1。

sync Edge读取同一完整证据：

- submitted→approved_immediate：保存transaction/approved time，expense变paid/approved，version +1；
- submitted→rejected：保存rejected time/error，expense保持可重试pending latest-state，version +1；
- terminal完全相同重放：不更新、不增加version；
- request/transaction/payload任一不同：稳定冲突；
- fixed route：即时helper拒绝。

transaction ID具备跨attempt唯一约束及helper冲突检查。

## 7. 网络失败与callback恢复

主恢复路径保持同一event/idempotency：prepare重试返回同一prepared attempt，Cash返回同一request，Edge再执行submitted V2，不创建第二attempt或request。

callback先到而attempt仍prepared时，仅`sync-cash-request-result-v2`携带完整且与snapshot完全一致的证据才可恢复：

- prepared→submitted→approved_immediate；或
- prepared→submitted→rejected。

实现为一个School事务中的等价双转换，version一次增加2，并写`callback_recovered_from_prepared=true`、恢复时间和固定来源。缺失或错误证据、普通callback来源、不同payload均拒绝；不存在无证据prepared→terminal。

## 8. 幂等、并发、version和回滚测试

生产同一迁移体ROLLBACK矩阵覆盖：24条回填、prepare/submit/approve/reject、完全重放、金额/币种/账户/日期/reference/event/fingerprint冲突、rejected新attempt、submitted失败重试、approved/rejected prepared恢复、错误恢复证据、legacy fail closed、fixed Gate、ACL、强制attempt先更新而expense后半段失败。结果`PHASE3C2R_ROLLBACK_MATRIX_PASS`，2099 expense/attempt/auth fixture residue0，生产恢复30列/24 attempt/53 expense。

独立临时PostgreSQL加载生产三表结构与数据并应用同一迁移，使用两个真实连接验证：

- 同expense双prepare：唯一attempt；
- 同attempt双submitted：一次转换、一次幂等；
- 同attempt双approved：一次转换、一次幂等；
- approved/rejected竞争：仅approved终态成功，rejected稳定失败；
- 最终expense与attempt一致、version=3。

结果：`PHASE3C2R_LOCAL_TWO_SESSION_CONCURRENCY_PASS`、`PHASE3C2R_APPROVED_REJECTED_RACE_PASS`。临时实例关闭，不触碰生产业务数据。

## 9. Edge修改、hash、部署及签名

本地源码SHA-256：

- request Edge：`a94dcc13feb4a85cb3232513a37da03a08ccb9c517ac5ffbfbf881df6c7ff045`
- sync Edge：`58f1864a5af64877c2df7266db939f76421dbb3d3c6bc140a58f72a08d8850f5`
- shared evidence mapper：`88a123889cf27746d3432e5a316c1a2c10d50754656a17ef82d8ca1d46621b0d`

正式部署：

- `request-cash-expense-confirmation`：v4→v5，ACTIVE，remote bundle SHA-256 `d4dbed43fb60a3ba81c9a01f8e82a6a6655903ecd2278506017dda7af852a74b`，verify_jwt=true；
- `sync-cash-request-result`：v8→v9，ACTIVE，remote bundle SHA-256 `505c0160644cbc19aa919d6a980a4779036259092c71eea1467f47b0b85a7a37`，verify_jwt=false。

两个endpoint OPTIONS均返回204。active admin双重校验、School/Cash service-role边界和原HTTP错误层级保留；未部署页面。

Edge mock/static测试证明prepare V2返回值是Cash writer唯一payload来源、Cash idempotent retry不产生新identity、submitted失败可重试、sync转发完整证据、缺失/错误fingerprint fail closed。既有Cash expense与P0 permission静态测试继续通过。

## 10. Gate与切换过程

1. 记录Cash request count/max timestamp/full fingerprint；
2. School schema/backfill/RPC在一个事务正式COMMIT，新增V2 Gate保持blocked；
3. 独立连接确认36列、24快照、ACL及双Gate；
4. 部署sync v9；
5. 部署request v5；
6. 读取远端version/status/bundle hash；
7. 再次确认Cash request仍50、School expense request仍24、max timestamp和指纹不变；
8. 2026-08-19 13:45:37.813583 JST启用`cash_expense_attempt_writer_v2_enabled`；
9. 旧四签名进入fail closed；fixed Gate仍blocked。

## 11. ACL、RLS和search_path

- V2四个业务wrapper：owner postgres、SECURITY DEFINER、`search_path=pg_catalog, public`，EXECUTE仅postgres/service_role。
- fingerprint helper：owner postgres、SECURITY INVOKER、fixed search_path，EXECUTE仅postgres。
- transition helper与trigger：owner postgres、SECURITY DEFINER、fixed search_path，EXECUTE仅postgres。
- attempt表：owner postgres、RLS enabled、policy 0、table ACL仅postgres；PUBLIC/anon/authenticated/service_role均无直接INSERT/UPDATE/DELETE。
- 未改变active admin、JWT、expense RLS或页面权限。

## 12. 正式COMMIT及独立后检

正式School DB执行：

- `school_expense_cash_attempt_v2_deploy_20260819.sql`：COMMIT成功，V2 Gate blocked；
- 两个Edge部署成功；
- `school_expense_cash_attempt_v2_gate_enable_20260819.sql`：COMMIT成功。

独立新连接只读后检：36列、1个generated fingerprint列、24/24快照有效、恢复0、fixed0、状态16/6/2、expense/attempt lag0、Gate enabled/fixed blocked、RPC定义/owner/security/search_path/ACL正确、2099 residue0。未调用真实业务writer。

## 13. 历史attempt和原业务零回归

- 历史attempt主键、原30列、状态、event/idempotency/request/transaction及charge date不变；
- expense 53，全表指纹仍`ac6a210ea34f9d377111cdc4757d0abe`；
- School/Cash 24条逐行规范映射差异0；
- home request 50、JPY 35、CNY 75及其指纹不变；
- projection/cycle/School-enabled card均0；
- 202,991 JPY教室租金未修改；
- fixed route未创建、未开放；
- 真实writer调用0，账户余额与流水写入0。

一次后检最初以文本直接比较numeric，因School `2739`与Cash `2739.00`的显示scale以及pending→submitted状态名映射产生diff；改用numeric规范化和明确状态映射后24行diff为0。这是验证格式修正，不是数据异常。

## 14. 文档、commit、push及untracked保护

更新`current-status.md`、`system-map.md`、`module-status.md`及本报告；新增本阶段SQL、Edge shared mapper、Edge mock与并发测试。未修改HTML/CSS/页面JS/API或home仓库。

原16个untracked对象在实施前后路径、数量与SHA-256完全一致；不会加入本阶段commit。Git commit/push结果在本阶段最终交付中记录。

## 15. 当前生产限制

- 仅即时账户路径接入V2；fixed credit-card route仍blocked且不可达。
- attempt尚无页面reader或UI展示，本阶段只接入writer和审计。
- expense `cash_payment_*`仍为latest-state兼容镜像；不得反向覆盖历史attempt。
- 不提供correction、funding、projection或fixed statement流程。
- 不改变Cash“approve生成transaction、reject不生成transaction”的最终权威。

## 16. Phase 3C3建议入口

Phase 3C3如获独立批准，应从fixed card request的DB模型与Card/statement/projection证据合同开始，保持fixed Gate blocked完成ROLLBACK、并发、Edge和home只读门禁后再设计切换。不得把即时账户V2 wrapper泛化为fixed writer，不得自动进入3D/3E/3F/3G或Phase 4。

## 17. 风险、异常和未决事项

- 新真实请求尚未由业务用户端到端执行；本阶段遵守“真实writer调用0”，以生产ROLLBACK、Edge mock、远端部署状态和独立后检验收。首次运营提交应观察一个即时request的attempt/event/fingerprint与Cash证据，但不需要新代码。
- Supabase CLI提示Docker未运行，但远端bundle上传与部署均成功，远端函数状态ACTIVE；Docker只影响本地容器化serve，不影响本次部署。
- 一次非交互shell未加载DB环境、两次早期只读查询使用错误列名、一次DNS解析短暂失败、ROLLBACK测试中两次temp-table角色权限测试脚本错误，以及本地initdb两次环境路径/role错误；均在正式COMMIT前修正或重试，失败事务未写生产，最终矩阵全部通过。
- fixed credit-card Gate、attempt reader/UI、correction、funding和兼容镜像退出仍需分别授权。
