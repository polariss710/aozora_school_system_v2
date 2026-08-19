# School V2 → Cash Phase 3C1 实施报告（2026-08-19）

## 1. Phase 3C1结论

Phase 3C1 已正式 COMMIT 到 School 生产数据库：新增 `public.school_expense_cash_attempts`，将 24 条现有结构化 expense Cash 请求确定性回填为逐-attempt审计记录，并在既有 `public.school_feature_gates` 新增 `cash_fixed_credit_card_route_enabled = blocked`。技术结论为 Go。

本阶段没有修改 home/Cash 数据库、School 页面、API、Edge Function 或现有 expense latest-state writer/reader；没有创建 fixed route attempt、Cash request/transaction、fixed projection/item 或账户余额变动。当前即时账户链保持原样。

## 2. 两仓库和生产初始／最终基线

- School 项目：`xlcdqvlfzspcxdoidsrr`；初始 `main`、HEAD/origin `3eecb6890161eb9537bfa5a8ce23e3cdc48ca854`、ahead/behind `0/0`、tracked/staged `0`，页面生产版本 `v10.5.54`。
- home/Cash 项目：`ahtgiwdzocerkonrjmdo`；全程只读，`main`、HEAD/origin `3880722c6b3da48a3012a17622429b9ded58e9d8`、ahead/behind `0/0`，页面生产版本 `20260819-accounting-scope-filter-2`。
- School 根目录没有 README；`AGENTS.md`、`docs/current-status.md`、`docs/workflows/write-rpc-flow.md`、system/module map、expense/Cash/Edge/ACL相关文档和实现均已读取。
- 生产 Edge endpoint 的 OPTIONS 可达，项目 ref 与区域正常；无纯只读远端管理凭证可取得部署 bundle/version/hash，CLI又会尝试写用户目录 telemetry，因此没有运行管理型 CLI。仓库已知版本仍为 expense request `v4`、sync result `v8`；本地源码 SHA-256 分别为 `a3b23918b2dcd30c0319013e25f0c4deca66cf4cbb1c6f191c0941360bd7de0e`、`cecf3e014055de689b751d3d374895d840b7c47e61219bc2eba6ddc720b7e5d0`。

## 3. School与Cash历史映射

- School expense 总数 53；具有 attempt/event/request/transaction 结构化字段的行 24。
- Cash `aozora_school + school_expense_records + expense_paid` request 24：approved 16、pending 6、rejected 2。
- School 24 ↔ Cash request 24 完整一一对应；缺失 0、多余 0。
- event、request ID、transaction ID、公式化 idempotency key、状态、Cash请求金额、Cash请求币种差异均为 0；重复 event/idempotency/request/transaction/reference 均为 0。
- 16 个 approved request 均有唯一 transaction；request payload hash 与 transaction `external_payload_hash`、event/reference/idempotency/type/amount/currency/date/scope 差异均为 0。
- 6 个 pending、2 个 rejected 均没有 transaction；rejected reason 均为结构化 `金额错误`。
- 24 条均为 `accounting_scope=school`、`payment_route=immediate_account`；fixed route 为 0。
- School `expense_date` 与 Cash request `transacted_at` 是不同业务事实：23/24 不同；attempt `charge_date` 保存 Cash结构化 `transacted_at`，不覆盖 School `expense_date`。任务点名的 `2026-05-31 → 2026-06-15` 日期差异属于 `school_income_records` request `475b2b7f-2e86-415f-87a0-580759fb50a4`，不属于本次24条expense attempt，未修正。
- School侧没有 payload hash 字段，因此不能声称双侧 payload hash 相等；只验证了 Cash request snapshot hash 与对应 Cash transaction hash。

## 4. attempt表实际合同

`public.school_expense_cash_attempts` 为 postgres owner，30列：任务要求的全部 identity、route、Cash引用、原始金额/币种、账期、生命周期、error、version和timestamps均已实现。

- `original_amount/original_currency` 是 School expense 原始事实的不可变快照。
- Cash实际请求金额/币种继续由既有 `school_expense_records.cash_payment_amount/cash_payment_currency` 与 home request 权威保存；3C1不重复新增 settlement/payment 金额快照。
- `charge_date` 来自 home request `transacted_at`；`cash_funding_account_id` 来自 home request `account_id`。
- 当前 `request_type` 只允许 `expense_paid`。
- `attempt_no > 0`、原始金额 `> 0`、币种仅 JPY/CNY、月份必须月初、version `> 0`。
- `expense_id` FK 到 `school_expense_records(id)`；删除被默认 FK 和新表 DELETE trigger共同保护。

## 5. 历史回填计数

- 总计 24，表全行 hash `d579452036c7a8d79d964b2b3882d324`。
- `approved_immediate = 16`。
- `submitted = 6`。
- `rejected = 2`。
- `prepared/approved_pending_funding/funded/corrected = 0`。
- `immediate_account = 24`，`fixed_credit_card = 0`。
- 必填 NULL、非法状态、非法 route 组合、2099 fixture residue均为 0。

## 6. 当前教室租金attempt证明

- expense `ed23a346-2ba5-47fb-a496-4c4ba781ec86`
- attempt `1`，route `immediate_account`
- event `fa3aad38-5886-4154-a7d4-8c8331fb71fe`
- request `ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc`
- transaction `01e910b8-bf54-486c-a13a-597ca9dbf684`
- funding account `b06f29c4-67cd-4d55-b39c-7cff0eab99a1`
- original `202,991 JPY`，charge date `2026-08-13`
- status `approved_immediate`

该记录没有被改为 fixed/corrected，原 School expense、Cash request/transaction和余额均未修改。

## 7. 唯一性、条件约束和不可变边界

唯一性已覆盖：主键、`expense+attempt_no`、event、idempotency、非空Cash request、非空Cash transaction、非空fixed projection、非空fixed item。

条件约束已覆盖：

- immediate 不允许 fixed projection/item/card/month/funding date，且不能使用 `approved_pending_funding/funded`。
- `approved_immediate` 必须有 request、transaction、submitted/approved时间。
- `submitted` 必须有 request/submitted时间且无成功引用。
- `rejected` 必须有 request/submitted/rejected时间，且无transaction/projection/approved/funded事实。
- fixed必须有card、suggested/target month、funding date；approved-pending/funded还必须有projection/item，funded必须有transaction与funded_at。
- 创建后普通UPDATE不能改变expense、attempt、route、request type、event、idempotency、request、card/account、原始金额/币种、charge/月/资金日、submitted/created时间。
- 未来窄生命周期更新仅可改变transaction/projection/item、status、approved/funded/rejected/corrected时间、error与version，并必须 `version = old + 1`；本阶段没有创建该writer。
- 所有DELETE以 `SCHOOL_EXPENSE_CASH_ATTEMPT_DELETE_FORBIDDEN` 拒绝。

## 8. feature flag状态

复用 `school_feature_gates`，新增 key `cash_fixed_credit_card_route_enabled`，生产状态为 `blocked`，等价于 false。新表 INSERT trigger在 fixed route 时要求该Gate精确为 `enabled`，否则以 `SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED` fail closed。现有 active admin页面/writer没有attempt写入口，且所有客户端表DML均关闭。

## 9. RLS、ACL和权限

- 新表 owner `postgres`，RLS enabled，policy 0。
- PUBLIC/anon/authenticated/service_role均无SELECT/INSERT/UPDATE/DELETE；service_role不保留直接DML。
- trigger function owner `postgres`、SECURITY DEFINER、`search_path=pg_catalog, public`，只有postgres EXECUTE。
- 本阶段没有新增客户端reader、authenticated writer或service-role writer。
- 现有 prepare/submitted/confirmed/rejected RPC的owner、SECURITY DEFINER、search_path、ACL和定义MD5全部不变。

## 10. ROLLBACK演练

最终SQL SHA-256：`15372811a34943928f933152f957905e2c679b29c44e4c88ff2dcf515e60094b`。

生产演练以 `phase3c1_commit=0` 执行同一文件：BEGIN、精确表锁、schema/Gate/backfill、2099 SAVEPOINT fixture、完整矩阵、ROLLBACK TO SAVEPOINT、最终显式ROLLBACK。独立新连接确认attempt表与Gate均不存在、fixture 0、School expense/RPC和Cash指纹恢复原值。

矩阵覆盖 immediate approved/pending/rejected、重复attempt/event/idempotency/request/transaction、非法status/route、fixed Gate=false、immutable update、DELETE、anon/authenticated/service_role直接DML、允许的versioned窄更新。

## 11. 正式COMMIT及后检

正式迁移使用相同哈希文件，以 `phase3c1_commit=1` 执行；事务内先再次运行相同fixture矩阵并回滚fixture，然后 COMMIT。独立连接后检确认30列、12个约束、8个唯一索引（含PK）、1个enabled trigger、RLS/ACL、Gate、24条回填和教室租金逐字段均符合合同。

执行的SQL文件仅为 `/private/tmp/school_phase3c1_expense_cash_attempts_20260819.sql`；没有调用业务RPC。迁移SQL没有加入仓库，也没有读取/执行/覆盖任何受保护untracked SQL。

## 12. 原School/Cash业务零回归

- School `school_expense_records`：53，full hash仍 `ac6a210ea34f9d377111cdc4757d0abe`，金额/状态/主键/updated_at均未改。
- 六个现有expense/admin函数定义MD5、owner、SECURITY、search_path、ACL逐个不变。
- Cash requests：50，hash `764fe302dcf1eaccd148f518898cc33b`。
- Cash JPY transactions：35，hash `d0386dfd604ee54fe9ce42915b40bd32`。
- Cash CNY transactions：75，hash `6ae2f6eb0a6bce4d86244777e71a0272`。
- card instruments：1，hash `9fcaeed275e97252f4b72e3cdb64dc97`；西武卡active=true、School route=false。
- statement cycles 0、fixed projections 0；home fixed item、账户余额和页面/RPC均未写。

## 13. 文档、commit、push及untracked保护

本阶段只更新 `docs/current-status.md`、`docs/system-map.md`、`docs/module-status.md` 和本报告。HTML/CSS/JS/config/API/Edge/home仓库均不修改。

初始16个顶层untracked对象（21个文件）已逐项记录SHA-256；正式迁移后内容/路径/数量不变。最终commit/push和Git状态记录在交付报告中。

## 14. 当前生产限制

- attempt表尚未接入现有 prepare/submitted/confirmed/rejected RPC，不会自动记录新attempt或推进历史attempt。
- 页面/API/Edge不会读取该表，也没有attempt详情或重试历史UI。
- fixed Gate仍blocked，home西武卡 School route仍false；fixed attempt、projection、fixed item、funding均为0。
- 3C1不复制Cash payment amount/currency到attempt；跨币种实际支付事实仍需通过现有School cash字段和Cash request读取。
- 跨School/home无法共享数据库事务；3C1使用提交前实时24/24只读映射Gate与静态结构化快照，未引入伪原子双写。

## 15. Phase 3C2建议入口

另行授权后，Phase 3C2可设计单一DB-authoritative attempt创建/提交writer，并明确与现有 expense latest-state RPC的原子写入顺序、失败恢复、callback幂等、reader与页面展示。进入前必须再次完成业务模型扩展声明；不得仅因Gate/key已存在就启用 fixed route。

## 16. 风险、异常和未决事项

- 远端Edge部署version/bundle hash无法从当前纯只读接口取得；只有endpoint可达性、历史部署版本记录和本地源码hash证据。
- 23条 expense date/charge date差异是已保留的不同结构化事实；未来UI必须明确字段语义，不能互相覆盖。
- 如果未来要求attempt自身独立展示跨币种Cash实际支付金额/币种，需要业务负责人另行批准新增不可变payment/settlement snapshot字段及唯一权威合同。
- 未来 Gate enable、fixed writer、callback双写、correction、funding writer、页面/reader均不在3C1范围。
