# School V2 学生月份状态 Phase A 实施报告

日期：2026-08-05

范围：事件表、active-admin writer、correction writer、单月/候选/区间 resolver、legacy fallback、shadow、唯一生产事件

结论：`PHASE_A_COMPLETE_CONCURRENCY_PROVEN`

## 1. 结果摘要

Phase A 后端已部署，唯一获批生产事件已通过正式 writer 创建：

- event id：`4190bddf-d995-4e6a-af6b-85997e6f999b`
- student id：`cff85c52-6acc-4b0f-8c92-3db280a5dd77`
- effective month：`2026-07-01`
- status：`paused`
- reason：`2026年6月为最后在读月份，从2026年7月起暂停上课。`
- row version：`70debcb4-6caf-42dd-ba99-b10a83ecb68d`
- creator user：`25331ae9-3412-48b9-bdc3-e516caeaeba4`
- creator membership：`25331ae9-3412-48b9-bdc3-e516caeaeba4`
- created at：`2026-08-05 04:10:36.79144+00`，东京时间 `2026-08-05 13:10:36.79144+09`
- void/correction 字段：全部 NULL

事件后权威结果：

| 月份 | active | paused | include inactive=false | include inactive=true |
|---|---:|---:|---:|---:|
| 2026-06 | 8 | 0 | 8 | 8 |
| 2026-07 | 7 | 1 | 7 | 8 |
| 2026-08 | 7 | 1 | 7 | 8 |

唯一 paused 学生在 2026-06 解析为 `active / fallback=true`，在 2026-07、08 解析为 `paused / source event=4190bddf-…`。selected override 在 2026-07 返回 1 条。

2026-08-05 补证已使用独立 `a0520000-*` synthetic fixture 形成两个正式 writer 事务的真实重叠：Session B 实际等待 Session A 的 transaction id 锁，A COMMIT 后 B 以稳定 `40001 / STUDENT_STATUS_EXPECTED_CURRENT_EVENT_MISMATCH` 拒绝；有效事件严格为 1，随后 event/student 均按精确 UUID 清理为 0。Phase A 的并发验收缺口已关闭。

本阶段没有切换 12 个 API 模块、页面顶部筛选、weekly reader 或任何 lesson/tuition/settlement/income/expense/wage writer 的状态资格规则；旧页面仍按 `school_students.status` 运行。

## 2. 实时基线

### 2.1 Git 与部署

- branch：`main`
- 本次并发补证开始 HEAD / `origin/main`：`57928ac5f9aff5d36992ff7770d5b58769dade42`
- ahead/behind：`0 / 0`
- 页面版本：`v10.5.6`
- 本次并发补证开始部署：Pages run `30974598069`，成功，head `57928ac5…`
- 后端检查点：`150feccb8a1829518730fe6dddd6c6220a9ba483`
- SQL 分层修正：`a30e6c347e69e7610c318080b8008050d0f26815`
- shadow 修正：`5097428`
- production session ACL 修正：`8001555`

六份受保护 untracked 文件开始与结束均未修改、移动、暂存或提交：

| 文件 | SHA-256 |
|---|---|
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

### 2.2 生产事实

- School DB timezone：UTC；业务月由 Tokyo date/month 传入并以月首 date 保存。
- Tokyo 当前日期/月：`2026-08-05 / 2026-08-01`。
- 学生：8，legacy snapshot 为 7 active / 1 paused。
- 唯一 paused UUID：`cff85c52-6acc-4b0f-8c92-3db280a5dd77`。
- active admin membership：唯一 `25331ae9-3412-48b9-bdc3-e516caeaeba4 / admin / active`。
- Gate：preview=`enabled`、generate=`blocked`、cash_submit=`enabled`。
- 写入前 event table 不存在；部署后、真实事件前为 0 行。
- 唯一 paused 学生课时 40：2026-04 4 条、05 16 条、06 20 条；7 月以后 0。
- 月结 3：2026-04/05/06；收入 1：2026-06；工资详情 52：6/16/30；bill 0；学生关联支出 0。

## 3. 业务模型扩展声明与审批映射

本轮实现的扩展全部直接对应任务书 V–X 节：

- 新表：`public.school_student_status_events`。
- 新月份事实：`effective_month`，仅接受月首 date。
- 新状态集合：事件层 `active / paused / left`；未修改 legacy status 约束。
- 新版本事实：DB 生成 `row_version`，供 correction 乐观锁。
- 新 actor 审计：user UUID 与 membership stable identity 均由 DB/JWT 推导。
- 新可变性：普通 writer 仅 append；correction 仅一向 void + replacement；无通用 UPDATE/DELETE。
- 新 reader 权威：事件为新 resolver 唯一权威；首事件前/无事件固定 fallback active，明确不读取 legacy status。
- 临时兼容：旧页面/旧 writer 继续读取 legacy snapshot，不双写；Phase B 完成消费者迁移后退出。
- 历史解释：只新增已批准的一条 2026-07 paused 事件，不回填其他学生。

未新增双写、金额、财务快照、历史修复、fallback COALESCE、页面 writer 资格或 destructive migration。

### 3.1 并发补证业务模型扩展声明

本次补证的 new table/column/status/date/month/identity/source/snapshot/version/writable fact、既有字段语义/可变性、writer/reader authority、locking rule、authoritative source、legacy fallback/dual read、dual write、历史解释及 destructive schema change 均为 `none`。不修改生产 schema、writer、resolver、ACL 或 Gate。任务书逐项授权的 synthetic fixture 短暂 COMMIT、正式 writer 调用和精确 UUID 清理属于测试生命周期，不产生新的持久业务合同。

## 4. 事件表合同

`public.school_student_status_events` 共 14 列：

- `id`
- `student_id`
- `effective_month`
- `status`
- `reason`
- `row_version`
- `created_by_user_id`
- `created_by_membership_id`
- `created_at`
- `voided_at`
- `voided_by_user_id`
- `voided_by_membership_id`
- `void_reason`
- `replacement_event_id`

约束与索引：

- student/auth user/membership/replacement 均为 `ON DELETE RESTRICT`。
- replacement FK 为 `DEFERRABLE INITIALLY DEFERRED`，支持同事务旧事件 void、替代事件 insert。
- status check 仅三状态。
- effective month 月首 check。
- reason/void reason trim 后 1–1000 字符。
- creator user 必须等于 membership stable identity；void actor 同理。
- void bundle 要么全部 NULL，要么全部存在。
- active `(student_id,effective_month)` partial unique。
- replacement event partial unique。
- resolver、created actor 索引。
- RLS enabled，无客户端 policy；public/anon/authenticated/service_role 表级权限全部撤销。
- 3 个 trigger：UPDATE correction guard、DELETE guard、TRUNCATE guard。

## 5. RPC 合同

### 5.1 普通 writer

`school_record_student_status_event_v1(uuid,date,text,text,uuid,text)`：

- 仅 authenticated EXECUTE；函数第一步调用 `school_require_current_app_admin()`。
- anon/operator/read_only/inactive/no membership/service_role 均拒绝。
- confirmation 固定 `RECORD_STUDENT_STATUS_EVENT_V1`。
- 先锁 student row，再锁该学生全部 event row。
- 比较 expected latest active event UUID。
- DB 获取 actor，不接收 actor 参数。
- 插入后对整个 active 序列重验转换矩阵。
- 返回事件、row version、actor、created_at、latest event 和 event 后 canonical status。

### 5.2 correction writer

`school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)`：

- active admin only；confirmation 固定 `CORRECT_STUDENT_STATUS_EVENT_V1`。
- target event + expected row version。
- 同事务锁 student/event sequence。
- 旧事件只允许设置 void actor/time/reason/replacement 并推进 row version。
- 新事件完整走三状态、月份、reason 和全序列转换校验。
- 返回旧/新 event、row versions、student、替代月份/状态、受影响月份范围、actor/time。
- 本阶段不提供页面入口。

### 5.3 resolver/readers

- `school_resolve_student_status_at_month_v1(uuid,date)`
- `school_list_student_month_candidates_v1(date,boolean,uuid)`
- `school_list_student_range_candidates_v1(date,date,boolean,uuid)`
- `school_list_student_status_shadow_v1(date)`

reader 仅 active admin/operator/read_only，可返回最小身份字段；不返回 phone、wechat、家长或 note。core/helper 均 owner-only。区间 reader 将 start/end date 视为 Tokyo 业务日期，覆盖其自然月份，并以“范围内任一月份 active”为 active-in-range。

## 6. 转换矩阵

通过：

- fallback active → paused
- fallback active → left
- active → paused
- active → left
- paused → active
- paused → left
- left → active
- pause → resume → pause

拒绝：

- fallback active → active
- 同状态冗余事件
- left → paused
- 同学生同月第二条 active event
- 非月首 date
- 非法状态、空 reason、错误 confirmation
- expected latest event/row version 漂移

## 7. 测试与执行

### 7.1 演练和 rollback

执行：

- `school_student_status_phase_a_rehearsal_20260805.sql`
- `school_student_status_phase_a_rollback_tests_20260805.sql`

结果：

- schema/guard/RPC 同字节 rehearsal 通过并 ROLLBACK。
- 正式部署后完整 runtime rollback matrix 再次通过。
- synthetic auth 5、membership 4、student 3 及全部 synthetic events 残留均为 0。
- anon/service_role 无 reader/writer execute。
- no membership/inactive 无 reader；operator/read_only 可读但不可写；active admin 可读写。
- active admin 也不能直接 SELECT/INSERT/UPDATE/DELETE event table。
- owner 直接 UPDATE 被 trigger 拒绝；物理 DELETE/TRUNCATE 由 ACL + trigger definition 双重封口。
- correction、fallback、转换、候选、区间和 selected override 均通过。

### 7.2 真实双会话重叠证据

fixture：

- synthetic student：`a0520000-0000-4000-8000-000000000100`
- rollback-only rehearsal event：`a0520000-0000-4000-8000-000000000200`
- Session A committed event：`3838c80d-9ce5-4ce9-a8dd-9d32638764eb`
- synthetic auth user/membership：未创建
- actor：既有真实 active admin user/membership `25331ae9-3412-48b9-bdc3-e516caeaeba4`

cleanup rehearsal 首版尝试在同事务 event DML 后切换 trigger 状态，PostgreSQL 以 `cannot ALTER TABLE ... because it has pending trigger events` 拒绝并自动回滚，fixture residue 0。修正方案在事件表 `ACCESS EXCLUSIVE` 锁内，仅用 transaction-local `session_replication_role=replica` 包围一条精确 event DELETE，立即恢复 `origin`，再以正常 FK/trigger 语义删除学生；回滚演练 event/student 各命中 1，三个生产 trigger 始终 enabled，回滚后 residue 0。

真实并发时间线（UTC）：

| 证据 | Session A | Session B |
|---|---|---|
| PID | `2253575` | `2253593` |
| transaction start | `04:57:02.824281` | `04:57:23.268425` |
| writer call/start observation | `04:57:03.231018` | `04:57:23.686848`；query start `04:57:23.787636` |
| writer result | event `3838c80d-…`，created `04:57:03.336642` | 等待后拒绝，event 0 |
| writer returned | `04:57:03.416930`，保持外层事务 | — |
| lock observer | `04:57:30.556857` | `active / Lock / transactionid` |
| transaction end | COMMIT `04:57:36.243952` | `40001` 后 ROLLBACK `04:57:36.412910` |

锁证据：

- A 为 `idle in transaction / ClientRead`，继续持有 student row 及 event insert 事务锁；测试未使用 `pg_sleep`。
- A 对 transaction id `10123` 持有 granted `ExclusiveLock`。
- B 对同一 transaction id `10123` 的 `ShareLock` 为 `granted=false`。
- `pg_blocking_pids(2253593)={2253575}`，observer assertion=1。
- A COMMIT 后 B 恢复并重新检查 latest active event；expected 仍为 NULL，返回 `40001 / STUDENT_STATUS_EXPECTED_CURRENT_EVENT_MISMATCH`。
- post-writer 检查：total event=1、active event=1、exact A event=1、Session B reason event=0；partial unique `school_student_status_events_active_month_uniq` 保持有效。
- 无 `40P01` deadlock、无 `55P03`/`57014` timeout、无第二条事件、无半写入。

### 7.3 精确清理与 residue

正式清理只接受 `synthetic_event_id=3838c80d-9ce5-4ce9-a8dd-9d32638764eb`，并再次匹配固定 student UUID、effective month、status、完整 reason 及 actor。事件 DELETE 命中 1 后恢复 `session_replication_role=origin`，学生 DELETE 命中 1，再 COMMIT。最终 synthetic student/event/membership/user 均为 0，lesson/settlement/income/expense/bill/wage 引用均为 0，残留 `idle in transaction`/Lock 测试会话为 0，三个事件 trigger 均为 enabled。

## 8. 正式部署与数据库写入

正式执行 SQL：

- `school_student_status_phase_a_deploy_20260805.sql`：一次 COMMIT，创建表、索引、约束、RLS、guard、writer、resolver 和 ACL；业务 DML 0。
- `school_student_status_phase_a_postdeploy_20260805.sql`：只读，多次通过。
- `school_student_status_phase_a_shadow_20260805.sql`：READ ONLY；最终通过。
- `school_student_status_phase_a_cash_readonly_20260805.sql`：Cash 只读；通过。
- production Session A：正式调用 `school_record_student_status_event_v1(...)`，唯一真实业务写入 1 条 event。
- production Session B：相同 expected `NULL` 调用被拒绝，业务写入 0。
- `school_student_status_phase_a_concurrency_cleanup_rehearsal_20260805.sql`：synthetic event/student 精确删除回滚演练，通过。
- `school_student_status_phase_a_concurrency_fixture_setup_20260805.sql`：短暂 COMMIT 1 名 synthetic student。
- `school_student_status_phase_a_concurrency_lock_observer_20260805.sql`：第三会话 READ ONLY 锁证据，通过。
- `school_student_status_phase_a_concurrency_postwriter_verify_20260805.sql`：READ ONLY，一成功/一拒绝及无业务引用，通过。
- `school_student_status_phase_a_concurrency_exact_cleanup_20260805.sql`：精确 COMMIT 删除 synthetic event 1、student 1，最终 residue 0。
- `school_student_status_phase_a_concurrency_final_readonly_20260805.sql`：最终 School 指纹/resolver/Gate/Storage/session 只读验收，通过。

实际调用的 write RPC 只有：

- rollback fixture 中的普通/correction writer，全部回滚；
- 生产 `school_record_student_status_event_v1(...)` 一次成功；
- 生产相同调用一次拒绝。
- 本次 synthetic `school_record_student_status_event_v1(...)`：Session A 一次成功、Session B 在真实锁等待后一次拒绝；成功事件随后精确清理。

没有调用页面/API/Edge 写入口，没有连接 Storage 写 API，没有写 Cash DB。

## 9. 历史不变量

事件写入后 postdeploy 通过以下精确不变量：

| 对象 | 数量 | 全行 MD5 |
|---|---:|---|
| students | 8 | `431ae7f350902dde0642ddc4982054ed` |
| lessons | 733 | `4d0c327cc0d7b2c6cbdae10ede6a3fd4` |
| settlements | 18 | `7986db5dd35c0ecfa180a04aef7f4051` |
| student-linked income | 30 | `0380f2e4ab967d37ad898a4e534195a4` |
| tuition bills | 22 | `d079f068c0fa19fc07d4dcd94094fae2` |
| wage details | 556 | `0b2976f8005835d66b2db25b0b3c1939` |
| wage rules | 20 | `2dc430ca4a58416235f2ba771b91b9f1` |
| all income | 55 | `bd2d538d1de901621ff0e6757984a41e` |
| expenses | 47 | `141c76e4cf6148007e182704941a0c4a` |
| accounts | 3 | `443b3170f50bc23a56834d398069c565` |
| account transactions | 187 | `21694ff060e23289566f0a6e9fe3e449` |

Cash：42 external requests `dfb00aaa210894f78c47285e21d2f222`、73 CNY transactions `937cbd8d10480c5c5dabaab658eb2558`、31 JPY transactions `3f3f257b14b43c12925a8eecb7a8ca02`，全行指纹不变。Storage：57 objects、30 pre-existing orphan，不新增、不删除、不改写。Gate 保持 `enabled / blocked / enabled`。

允许的唯一真实业务行变化为 event table 新增 1 行；event table 最终 count=1，MD5=`eeeb492ac7577ff85eb0926aa0b57301`。

## 10. Phase B 边界

本阶段明确未做：

- 不改页面版本或 UI。
- 不切换 12 个直接读取 `school_students` 的 API 模块。
- 不改顶部筛选、URL selected、月份刷新策略。
- 不改 weekly lesson reader。
- 不改 lesson/tuition/settlement/income/expense/wage-rule/Cash writer 资格。
- 不冻结 legacy student status writer。
- 不回填 7 名 active 学生。

Phase A 已完全闭环，可以进入 Phase B 的独立调查/授权流程。Phase B 只有在新的逐域授权下，才可迁移消费者、定义 writer paused/left 资格并冻结 legacy status；不得把本次 Phase A 完成视为自动授权，本轮未自动开始 Phase B。
