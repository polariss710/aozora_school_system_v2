# School V2 学生月份状态 Phase B5 实施报告

日期：2026-08-07（Asia/Tokyo）

## Business-model expansion declaration

- New tables: none
- New columns: none
- New enum/status values: none（继续仅使用既有 `active / paused / left`）
- New date/month/attribution concepts: none（复用 Phase A `effective_month` 与 Tokyo 自然月；active→paused/left 的“最后在读月份”、paused→left 的“离校生效月份”、paused/left→active 的“恢复/重新入学月份”均由本任务第三、四节明确批准）
- New identity concepts: none（actor 继续唯一来自 `auth.uid()` 与同 UUID membership）
- New source concepts: none
- New snapshot/version concepts: none（继续使用事件 `row_version` 与 expected latest event UUID）
- New writable facts: none（唯一写入仍是既有 append-only `school_student_status_events` 事件及 correction void/replacement bundle）
- Changed existing-field semantics: none
- Changed field mutability: none（普通事件仍 append-only；更正仍仅单向 void + replacement；legacy `school_students.status` 永久冻结）
- Changed writer or reader authority: `school_transition_student_status_v1(uuid,text,date,text,uuid,text)` 成为 authenticated 浏览器正式 transition 入口；`school_correct_student_status_event_v1(uuid,uuid,uuid,date,text,text,text,text)` 成为带 expected-current 的 authenticated 正式 correction overload；原始 `school_record_student_status_event_v1(uuid,date,text,text,uuid,text)` 与旧 7 参数 correction overload 继续 owner-only。管理、历史及两个 preview reader 仅向 authenticated 开放并在 DB 校验 active membership。
- Changed locking rules: 正式 transition 与 correction overload 在同事务按 student row → 该学生全部事件行顺序锁定，锁后校验 expected latest event；随后调用既有 Phase A 权威 writer，不绕过 mutation guard。
- New authoritative sources: none（`school_student_status_events` 仍为唯一状态权威；无事件固定 fallback active）
- Legacy fallbacks or dual-read rules: none（不读取 `school_students.status` 作为 resolver fallback）
- Dual-write behavior: none
- Historical reinterpretation: none（本阶段不新增、更正或作废任何真实事件）
- Destructive schema changes: none

Approval reference:

- 当前任务第四节第 3 项逐项批准 transition wrapper 的输入语义、DB 月份计算、actor、expected-current、锁、同事务及调用既有 writer 合同；对应 writer authority 与 locking 两个 non-none 项。
- 当前任务第四节第 5 项及第七节逐项批准 correction 的锁、expected row/current event、原子 void + replacement、历史保留与 preview；对应 correction overload 的 authority/locking。
- 当前任务第四节第 2 项、第五节及第九节明确批准只向 authenticated 解冻正式交互入口，active admin 才能写，operator/read_only 只读，anon/无 membership/inactive/service_role 拒绝；对应全部 ACL 变化。

## 实时基线

- 分支：`main`。
- 初始 HEAD / origin：`da02fba32610503e1706849edaf3c4535dcb743e`，ahead/behind `0/0`。
- 页面版本：`v10.5.17`。
- Gate：`cash_submit=enabled / generate=blocked / preview=enabled`。
- 初始工作区仅有六份既有受保护 untracked 文件；本报告为本轮新增文件。

## 实现结果

### DB 权威与正式写入口

- `school_student_status_events` 继续是唯一状态权威；学生无事件及首事件前固定解析为 `active`，不读取 legacy `school_students.status`。
- 新增正式 transition wrapper `school_transition_student_status_v1`：第一步断言 active admin，DB 使用 Tokyo 当前月，actor 只取 `auth.uid()`；锁定 student row 及该学生事件行后校验 expected latest event，再调用 Phase A append-only writer。
- active→paused/left 的客户端只提交“最后在读月份”，DB 将 `effective_month` 计算为下一自然月；paused→active/left、left→active 直接使用输入月份。页面不计算或提交生效月份。
- 新增 8 参数 correction overload：锁后同时校验目标事件 `row_version` 和 expected latest event，并调用既有原子 void + replacement writer；原事件只作废、replacement 追加，历史不更新、不删除。
- 原始 `school_record_student_status_event_v1` 和旧 7 参数 correction overload 继续 owner-only；authenticated 只获得新 transition 和新 correction overload 的 EXECUTE。两个正式 writer 都在读取业务对象前断言 active admin；operator/read_only 只读，anon、无 membership、inactive、service_role 均拒绝。
- `school_students.status` 表级冻结继续有效；新增/编辑学生页面及 canonical writer 均不恢复 legacy status 写入。

### API 与学生管理 UI

- 新建/扩展 `js/api/student-status-api.js`，页面模块只调用 API wrapper；页面 `.rpc()`、直接 insert/update/delete/upsert 均为 0。
- 学生卡片显示 DB Tokyo 当前月解析状态、来源事件/fallback、系统原因；顶部筛选使用权威 `active / paused / left`，不再按 legacy status 过滤。
- active admin 可按当前态发起暂停、离校、恢复、重新入学和历史更正；每次先调用只读 preview，展示 DB 返回的生效月份与影响区间，要求显式确认后才出现最终提交入口。
- 历史抽屉展示事件、actor、创建时间、void/replacement/correction 关系；更正不允许编辑 actor 或 created_at。
- operator/read_only 不渲染状态写按钮，DB 仍是最终权限边界。
- 页面版本由 `v10.5.17` 前进为 `v10.5.18`；未在 `js/legacy-core.js` 增加代码，浏览器无 service-role。

## 测试与并发证据

### 回滚、权限与回归矩阵

- `sql/tests/student_status_phase_b5_rollback_test_20260807.sql` 全程事务内运行并显式 `ROLLBACK`，结果 `STUDENT_STATUS_PHASE_B5_ROLLBACK_PASS`，fixture residue 为 0。
- 覆盖 active→paused、active→left、paused→active、paused→left、left→active、多轮循环、同月重复、同状态、非法 left→paused、空原因、过期 expected event、乱序事件和更正 stale row/current event。
- 覆盖 anon、service_role、无 membership、inactive、operator、read_only、admin；只有 active admin 可写。
- 更正验证原事件 void、replacement 追加、历史链完整；legacy status 不变、事件表直接 DML 拒绝、原始/旧 writer owner-only。
- 在同一 rollback fixture 中补充 B4 月份候选、selected override、range-any-active、DB Tokyo 当前月工资规则候选及 planned lesson selected override 回归，全部通过。
- B1/B2/B3/B4-Wage/B4-Lesson/B4-Finance/B4-Remaining、BE-UI、lesson-writer P0 静态测试与 JS syntax 全部通过；page-layer 直接 RPC/DML 为 0。
- B4-Lesson candidate postdeploy 与最新 lesson-writer P0 postdeploy 通过。两份历史 postdeploy（B3 writer authority 与 cancellation）仍把后续合法部署前的整段函数 MD5 固定为旧值，因此对当前定义报 snapshot drift；其事务失败/回滚、无数据写入。现行 ACL、函数首段权限、候选资格和 writer 边界已由 B5 rollback、当前 catalog 校验及最新测试覆盖，不把旧 MD5 失配误报为当前业务回退。

### 真实双连接并发

- 固定 synthetic actor：`b5010000-0000-4000-8000-000000000001`；固定 synthetic student：`b5010000-0000-4000-8000-000000000100`。
- Session A PID `2481478` 持锁并提交 active→paused，生成 event `5f8adaa2-ef6d-4b48-9219-527e03ee3653`、row version `57ca635a-619b-4ad7-b779-6163ecc08691`。
- Session B PID `2481480` 对相同 expected-current 真实等待；A 提交后 B 以 `STUDENT_STATUS_EXPECTED_CURRENT_EVENT_MISMATCH` 拒绝。最终 A event 恰为 1，B event 为 0，无部分写入。
- 随后按固定 UUID 精确清理 synthetic event/student/membership/auth user，全部目标各删除 1，`b501` residue 为 0；没有触碰真实学生或真实状态事件。

## 部署与生产无写验收

- 实现提交：`bf747ac473061b0aae5f8ed5a61eb9ad9f41e489`；Pages run `31164291226` 于 `2026-08-07T09:04:29Z` success，部署 commit 与实现提交一致。
- postdeploy identity-free 技术修复提交：`98a31c60e37e57cc90e478f56e099e73f69a8e5b`；Pages run `31164418707` 于 `2026-08-07T09:05:56Z` success。
- 生产页面显示 `v10.5.18`，active-admin 会话；桌面 `2560px` 与移动端 `390×844` 均无横向溢出，Console error 0 / warning 0。
- 实时 8 名学生：DB Tokyo 2026-08 为 7 active fallback + 1 paused event；paused 筛选为 1，重置后为 8。
- 唯一真实 paused 学生卡片显示 2026-07 生效事件及安全原因；历史抽屉显示 1 条事件、actor、created time、row version/void/replacement 关系。
- active→paused preview：输入最后在读月 2026-08，DB 返回生效月 2026-09；paused→active preview：输入 2026-08，DB 返回生效月 2026-08；更正 preview 显示原/新时间线及影响区间。只执行 preview，所有最终提交按钮均未点击。
- active、paused、left 对应动作集合、历史/更正入口、URL/筛选/重置及 390px dialog 均正常；历史业务卡片和姓名不因状态隐藏。
- 页面无业务归属、个人名义、`business_entity_id` 或 service-role；浏览器未调用 transition/correction 写 RPC，第一条真实状态操作未执行。

## 只读生产复核

### School / Cash / Storage 指纹

部署前后完全一致：

| 对象 | 数量 | 指纹 |
| --- | ---: | --- |
| students | 8 | `431ae7f350902dde0642ddc4982054ed` |
| status events | 1 | `eeeb492ac7577ff85eb0926aa0b57301` |
| lessons | 741 | `bf20280701bb0c5306aae05ba6aad5a6` |
| settlements | 18 | `7986db5dd35c0ecfa180a04aef7f4051` |
| income | 55 | `eb40e1ea59767e4299cd23b332f57d2a` |
| tuition bills | 22 | `d079f068c0fa19fc07d4dcd94094fae2` |
| expenses | 47 | `141c76e4cf6148007e182704941a0c4a` |
| wage rules | 20 | `2dc430ca4a58416235f2ba771b91b9f1` |
| wage locks | 95 | `8474b2adcc3ed39059efd7237da90168` |
| wage details | 556 | `0b2976f8005835d66b2db25b0b3c1939` |
| accounts | 3 | `443b3170f50bc23a56834d398069c565` |
| account transactions | 187 | `21694ff060e23289566f0a6e9fe3e449` |
| Cash external requests | 43 | `38af234da847c517d548c7b6337a40a1` |
| Cash CNY transactions | 74 | `97d2cb2955477319b27664daa9af0b42` |
| Cash JPY transactions | 31 | `3f3f257b14b43c12925a8eecb7a8ca02` |
| Storage objects | 57 | `c2852a4dbcd13b9cddb1da0b1115b18f` |

- Storage 既有 orphan 仍为 30；本轮未上传、移动或删除对象。
- 唯一真实事件仍为 `4190bddf-d995-4e6a-af6b-85997e6f999b`，学生 `cff85c52-6acc-4b0f-8c92-3db280a5dd77`，`2026-07-01 / paused`，row version `70debcb4-6caf-42dd-ba99-b10a83ecb68d`，未 void、无 replacement。
- legacy status 分布仍为 active 7 / paused 1；Gate 前后均为 `enabled / blocked / enabled`。
- 生产持久 DB 变更仅为本阶段函数定义、ACL 与 comment；School 业务数据、Cash、Storage 的真实写入均为 0。唯一 committed DML 是上述受控 synthetic 并发 fixture，已精确清理且 residue 0。

### 最终 ACL

- 新 transition 与 8 参数 correction 仅 `authenticated` 可 EXECUTE，函数内部只允许 active admin。
- 原始 record writer 与旧 7 参数 correction writer 仍为 owner-only；PUBLIC、anon、authenticated、service_role 均无 EXECUTE。
- preview/management/history reader 向 authenticated 开放，但函数内部要求 active membership；无 membership 与 inactive 继续拒绝。
- 未扩大事件表直接 DML、其他函数或表 ACL。

## 受保护文件

前后 SHA-256 完全一致，且从未移动、删除、修改、暂存或提交：

- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`: `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`: `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`: `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`: `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`: `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`: `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

## 结论

- Phase B5 数据库、权限、并发、API、UI、部署、生产 Chrome 无写验收与数据复核全部完成。
- Phase B1–B5 全部完成，Phase B 正式闭环。
- 本轮没有执行任何真实学生状态 transition/correction；首条真实操作明确留给业务负责人。
