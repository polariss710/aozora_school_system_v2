# School V2 Atomic Tuition 专用作废与重新生成只读调查报告

日期：2026-08-02（JST）
阶段：只读调查与业务模型扩展门；**HARD STOP，未实施作废/重新生成**

## 1. 结论

彭宇晗、李天伦 2026-08 的 Atomic Tuition 链当前完整，income 均为
`pending`，School/Cash 两库均不存在 linkage、request、transaction 或 journal
事实；二人的现有账单具备“数据层面可进入专用作废前置校验”的条件。现有 DB 模型
却只允许学生/月存在一个永久 billing identity，并让历史 canonical lesson relation
永久占用 planned lesson。它不能在保留旧 bill、income、snapshot、manifest、relation
的同时释放 claim、创建新 revision，并证明始终最多一个 active revision。

因此，本阶段按 `AGENTS.md` 的 Schema And Business Model Expansion Gate 硬停止：
未起草/执行 schema 或 RPC，未修改前端，未作废任何真实记录，未生成新账单，未连接
Cash。任务中的“必要扩模”属于一般授权，不能替代下面每个 exact object 与 semantics
的业务负责人逐项批准。

此外，仓库、文档和 Git 历史均未找到任务要求必读的 R2-F-A 产物；R2-F-B、R2-F-C、
R2-F-D、Cash 恢复/硬化/Gate/不可变报告及其 SQL、rollback、postdeploy 已读取。

## 2. 目标链只读事实

| 学生 | student | identity | bill | income | manifest | 课时关系 | 冻结金额 |
|---|---|---|---|---|---|---:|---:|
| 彭宇晗 | `eb705aad-de4d-45e6-a391-42dcdd89aeda` | `2dd30b2f-45ea-431f-893b-d294a767266a` | `1e02dc09-8f42-4a93-85c6-e27809d68a83` | `ae4d8b66-491b-4db2-ac91-86765f56155c` | `1e75fd1456114d53b5c575d27d103ec4c038675b35586576d4ec40a28c91d801` | 15 | JPY255,000 / CNY10,582.50 |
| 李天伦 | `a7b163a0-201e-4867-9b94-372343356a80` | `45b7ebb6-c991-4f04-b85b-40ecd5adb6ff` | `5e032651-f3b0-40f9-b1ad-6bcce4e6fb93` | `1de45ea6-6cf7-45d9-9df5-1275bf5051d4` | `bf7d219c70cf8904824a5a318a46ef90ed0b02a198921624b6682ec61eed702e` | 16 | JPY352,000 / CNY15,030.40 |

- 两条 bill 均为 `income_created`，income 均为 `pending`，source/generation 均为
  `student_tuition_bill` / `student_tuition_atomic_generate_v1`。
- identity、bill、income 与全部 normalized lesson relation 的 manifest 一致；三个
  authoritative validator 对二人均通过。
- 二人的上一月 carryover 均是冻结的 `zero_carryover_verified_v1`，无 settlement、
  carryover relation 或可释放金额事实。
- School Cash preflight 均为 `ELIGIBLE_FOR_CASH_SUBMIT`，但 School linkage 为 0；
  Cash request、CNY transaction、JPY transaction 均为 0。Cash schema 中不存在
  journal 表。没有 rejected linkage。
- 当前 Gate 为 `enabled / enabled / enabled`，因此“作废与 Cash submit 并发”不是理论
  问题：新流程必须与已开放的 Cash writer 使用一致锁协议并在写前二次验证。
- 只读 preview 对二人均返回 `R2_F_B_ALREADY_BILLED`；candidate reader 默认各返回
  0。包含排除项时，彭宇晗 15 行、李天伦 16 行均为
  `already_canonical_charged`。

若 claim 能按 active revision 权威正确释放，当前数据预计可恢复：彭宇晗 15 行、
30h、JPY255,000；李天伦 16 行、32h、JPY352,000。李天伦 normalized relation 的
`lesson_count` 合计为 21，但 candidate 行数仍为 16，二者不是同一统计口径。

## 3. “哪些课时需要调整”调查结果

当前 DB 无法证明任何一条目标 planned lesson 需要业务调整：31/31 source planned
均仍为 `planned`、未 void、无 linked actual；冻结后没有目标行更新，收费相关字段与
normalized snapshot 无差异。现有 billed guard 也会阻止对这些课时的收费事实编辑。

因此不能从数据库安全推断调整清单。业务负责人必须另行明确 planned lesson UUID、
目标字段与目标值；本报告不把“想重生成”反推为任何课程事实变更。

## 4. 当前 generic cancellation 被拒绝的准确原因

- `school_cancel_pending_income_record(...)` 对 Atomic Tuition 明确抛出
  `TUITION_ATOMIC_CANCEL_FORBIDDEN`。这是正确的 fail-closed：generic RPC 只会取消
  income/bill，无法处理 identity、normalized relations、candidate/carryover claim、
  revision/supersession 与并发锁。
- `income-detail.html` 仍显示 generic `作废收入`；
  `js/pages/income-detail-page.js` 的 `canCancelPendingIncome` 只看 pending/linkage，未排除
  Atomic Tuition；API wrapper 随后调用 generic cancel，于是服务端拒绝。
- 普通非学费 pending income 的 generic cancellation 现有回归合同必须保持不变。

## 5. 现模型不能原地支持 revision 的证据

1. `school_student_tuition_billing_identities` 只有一个 `canonical_bill_id`，并有
   `UNIQUE(student_id,billing_month)`；没有 business entity、revision、active/void、
   previous/supersession 字段。
2. `school_student_tuition_bill_lessons_canonical_planned_key` 对
   `relation_role='canonical_charge'` 永久唯一约束 `planned_lesson_id`。保留旧 relation
   时，新 revision 无法重用同一 planned lesson。
3. candidate reader 和 billed lesson edit guard 对“是否存在历史 relation/snapshot”
   作无条件判断，不区分 active/voided revision；即使把 bill/income 标记 cancelled，
   candidate 与编辑仍不会恢复。
4. bill 的 active partial unique index只保护 bill 本身，不能证明 identity、relation、
   carryover claim 和 Cash submit 使用同一 active revision authority。
5. Cash submit 当前锁定 income→bill→identity，但没有 active revision 概念，也没有与
   Atomic operation key 完全统一的作废互斥协议。
6. V2 是无登录内部系统，没有可验证的 manager identity/role authority；现有 generic
   cancel ACL 过宽，不能据此声称满足“当前操作者有管理权限”。

## 6. Business-model expansion declaration（未获批准）

以下均为 `non-none`，本阶段没有可匹配的逐项业务 owner 批准：

| 类别 | exact object / semantics | 状态 |
|---|---|---|
| 新业务表 | `public.school_student_tuition_generation_identities`：`id`、`student_id`、`business_entity_id`、`billing_month`、`legacy_billing_identity_id`、创建审计；`UNIQUE(student_id,business_entity_id,billing_month)`；是学生＋业务归属＋月份稳定 identity 的唯一权威，既有 identity 仅作为初始链审计证据 | 未批准 |
| 新业务表 | `public.school_student_tuition_generation_revisions`：每个 immutable generation 一行；`generation_identity_id`、`tuition_bill_id`、`revision_no`、`previous_revision_id`、`generation_manifest_sha256`、`lifecycle_status(active/voided)`；active row 是当前 bill/claim 的唯一权威，每个 generation identity 最多一条 active | 未批准 |
| 新业务表 | `public.school_student_tuition_generation_void_events`：append-only，一次专用作废一行；保存 revision、expected manifest、reason、operator authority、时间与前后证据；是作废审计的唯一权威 | 未批准 |
| 既有 identity 语义 | 不给既有业务表新增列，不修改旧行；`school_student_tuition_billing_identities` 及其 `canonical_bill_id` 永久保留为初始 canonical generation 审计证据，不再是当前 active bill authority；生产 reader 必须以新 generation identity＋active revision 为唯一权威 | 未批准 |
| 新版本/状态事实 | `revision_no`、`previous_revision_id`、`lifecycle_status` 与 active partial uniqueness；只允许 owner-only core 将 active→voided，新 generate 追加下一 revision，不允许改写旧 revision | 未批准 |
| reader/writer authority | preview、candidate reader、三个 validator、lesson edit guard、Atomic generate、专用 void、Cash preflight/submit 均只读取 revision 表的 active row；前端不计算或传递释放金额/claim 等业务结果 | 未批准 |
| relation uniqueness | 在同一事务中先安装 owner-only `school_assert_active_tuition_lesson_claim(uuid)`、relation INSERT/UPDATE constraint trigger `school_enforce_active_tuition_lesson_claim_on_relation` 与 revision INSERT/UPDATE constraint trigger `school_enforce_active_tuition_lesson_claim_on_revision`，验证后才移除 `school_tuition_bill_lessons_canonical_planned_key`；新约束只禁止同一 planned lesson 同时属于两个 active canonical revision，旧 relation 永久保留且仍可审计，不能出现无保护窗口 | 未批准 |
| locking rule | 专用 void、Atomic generate 与 Cash submit 共用 `student_tuition_operation_v1|student|entity|month` advisory key，使用固定 identity→active revision→bill→income→School linkage/Cash preflight 锁顺序；作废先锁再二次确认 Cash facts 为 0 | 未批准 |
| 历史初始化 | 以固定 15 链清单向新表追加 15 条 generation identity＋15 条 revision 1 active metadata，包含本报告两条目标链；不改任何既有 identity/bill/income/snapshot/manifest/relation。否则必须引入 NULL/legacy fallback 和 reader priority | **与“不得回填目标记录”冲突，未批准** |
| 权限边界 | 专用 RPC 不向 anon/authenticated/PUBLIC 开放，仅允许受信 backend；“manager”必须有单一已批准身份来源。V2 当前无登录，必须选择并批准：引入正式 manager identity authority，或把 service-role-only 明确定义为本阶段运营授权并修改原要求 | 未批准 |
| compatibility/retirement | 推荐不保留 legacy reader fallback；先完成固定 metadata registration，再切 active revision authority。若坚持不注册现有链，必须另行批准 fallback、reader precedence、监控、截止日、完成标准与退休条件 | 未批准 |

没有新增日期/月概念、金额算法、汇率算法或 carryover 算法的提案；冻结金额继续只能由现有
DB authoritative snapshot/generate 计算。没有 dual-write 两个可写金额 authority 的提案。

## 7. 需要业务负责人下一步明确批准的最小集合

继续前必须逐项明确批准第 6 节的三个新表、identity business-entity/authority 语义、
revision lifecycle、active-only readers/writers、relation 唯一约束替换、三方锁协议、
既有 15 链 metadata registration，以及 V2 manager 权限权威。

其中 metadata registration 与原任务“migration 不得自动回填/修改目标记录”存在直接
冲突。推荐的安全选择是：明确允许一次固定清单、仅追加 revision metadata 的初始化，
不修改任何既有 bill/income/snapshot/manifest/relation；初始化前后对这些业务表做整行
fingerprint，并让初始化自身先 rollback 后 whitelist commit。若不批准该窄范围初始化，
则本任务必须继续停止，不能用隐式 `COALESCE`、NULL 分支或永久 legacy fallback 绕过。

## 8. 执行记录

- 执行方式：School/Cash `REPEATABLE READ READ ONLY` 查询及只读 validator/preview/
  candidate-reader 调用。
- SQL 文件执行：0；写 RPC 调用：0；数据库写入：0。
- 真实目标作废/重生成/Cash 提交：0；test whitelist 写入：0；测试记录 ID：无。
- 受保护文件与现有未跟踪文件均未修改。
