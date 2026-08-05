# School V2 学生月份状态 Phase B3：服务端业务 writer 权威切换报告

日期：2026-08-06（Asia/Tokyo）

## 1. 结论

Phase B3 已完成实现、回滚验证、提交、推送、School DB 正式部署、postdeploy 与 Chrome 无写验收。B4、B5 均未启动。

- 新教学事实由 DB 自己计算权威业务月，并要求 `school_student_status_events` resolver 在该月解析为 `active`。
- 既有 planned/source 的完成、取消、部分完成、补课、跨月补课与受控修正不再读取冻结的 `school_students.status`。
- 计划课同学生、同权威月份的历史修正不加状态门控；更换学生或改变权威月份时检查目标月 active。
- 工资规则新建、换学生、重新启用按 DB 东京当前月检查 active；同学生普通修正和停用继续允许。
- Tuition preview/snapshot/generate 链已移除 legacy status 门控；void/reissue 链确认原本无该门控。生成 Gate 继续为 `blocked`。
- 12 个正式目标函数中的 legacy status 资格谓词由 12 处降为 0；没有新增 legacy status 写入点、状态权威、fallback、双写、业务列或历史回填。
- 最新取消 writer 的 admin/operator、DB 时长、15 分钟网格、零费用/零学生分钟、`pending_makeup`、锁、claim、账单消费、工资消费和重复 actual 合同均未回退。
- 页面/API/`js/config.js` 均未修改，生产继续 `v10.5.9`；工资页顶部仍是“业务归属”，没有开始 B4。

## 2. 实时起点

| 项目 | 起点 |
|---|---|
| 分支 | `main` |
| HEAD / `origin/main` | `e4a6f2b08fbc7a2c2ea96c4a1468d67993c291e0` |
| ahead / behind | `0 / 0` |
| 工作区 | 仅六份受保护 untracked 文件 |
| 页面版本 | `v10.5.9` |
| Pages | run `31028890122`，success，HEAD `e4a6f2b…` |
| Gate | preview=`enabled` / generate=`blocked` / cash_submit=`enabled` |
| 学生 / legacy status | 8；active 7、paused 1；MD5 `431ae7f350902dde0642ddc4982054ed` |
| 状态事件 | 1；MD5 `eeeb492ac7577ff85eb0926aa0b57301` |
| 课时 | 738；MD5 `fc802f6d7da3ece1182bd2c217955562` |
| B1 weekly reader | MD5 `e7eac5f3bb07c31ad15e750e8721c01f` |

起点已吸收课时编辑/取消任务的全部合法提交；未 reset、回退或覆盖任何提交与生产业务数据。最新取消函数起点 MD5 重新读取为 `726c3f76786167bc70cb40b0ec9be613`。

## 3. Business-model expansion declaration

| 项目 | 声明 | 审批映射 |
|---|---|---|
| 新业务表、列、状态值、identity、source、snapshot/version、可写事实 | `none` | 不适用 |
| 新日期/月概念、历史重解释、回填、破坏性 schema | `none` | 不适用 |
| 新 fallback、dual read/write、长期兼容路径、Gate | `none` | 不适用 |
| 唯一月份状态权威 | 不变，仍为 `school_student_status_events` + Phase A resolver | 本任务第三、四、六节 |
| writer authority | 12 个点名正式函数从 legacy status 切换到已批准的月份 resolver/既有事实合同 | 本任务第四、五、六节逐项批准 |
| reader authority | Tuition preview/snapshot 不再以 legacy status 拒绝既有义务；B1 weekly reader不变 | 本任务第四、五-F节 |
| 新内部 helper | `school_assert_student_active_at_business_month_v1(uuid,date,text)`；仅封装 Phase A resolver 断言，不形成第二权威，owner-only | 本任务第六节明确允许最小内部 helper |

声明在设计和 SQL 草拟前完成，所有 non-`none` 项均映射到本任务对精确对象与语义的明确批准，Schema And Business Model Expansion Gate 通过。

## 4. 生产依赖与权威矩阵

### 4.1 正式调用链

- 单条 planned：页面 → `js/api/lesson-api.js` → `school_create_planned_lesson_record_with_venue` → wrapper → `school_create_planned_lesson_record_r1d_f1_legacy_core`。
- 批量 planned：API → `school_generate_planned_lessons_batch_with_venue` → wrapper → `school_generate_planned_lessons_batch_r1d_f1_legacy_core`。
- 导入 planned：API → `school_import_lesson_records_batch_with_venue` → wrapper → `school_import_lesson_records_batch_r1d_f1_legacy_core`。
- 课时编辑：API → `school_update_lesson_record_guarded_with_venue`/overload → 17 参数 base `school_update_lesson_record_guarded`。
- ordinary actual：`school_create_actual_lesson_from_planned`。
- partial：`school_create_partial_completed_actual_from_planned`。
- makeup/cross-month wrappers：最终统一委托 `school_create_lesson_credit_makeup_actual`。
- 受控 replace/correction：`school_replace_unconsumed_makeup_actual_v1` 只处理已批准既有事实并委托同一 makeup core；它读取的是课时行 `status`，不读取学生 legacy status 作为资格。
- 取消：`school_create_cancelled_actual_lesson_from_planned`。
- 工资规则：`school_create_teacher_wage_rule_config`、13 参数 `school_update_teacher_wage_rule_config`；旧短签名仅 owner wrapper。
- Tuition：validation/atomic/generate/reissue 均调用 `school_build_student_tuition_generation_snapshot`；legacy preview 为 `school_preview_student_tuition_bill`；void/reissue core 本身无 legacy status 资格谓词。

没有发现完全不关联 planned/source 的 standalone actual 正式 writer；因此没有需要猜测或硬停的模糊业务语义。

### 4.2 修改函数、MD5 与 ACL

所有函数 owner 均为 `postgres`、均为 `SECURITY DEFINER`，终态 `search_path` 均为 `pg_catalog, public`。未列出的权限均为拒绝。

| 签名（`public.` 省略） | 前 MD5 | 后 MD5 | 终态 EXECUTE |
|---|---|---|---|
| `school_assert_student_active_at_business_month_v1(uuid,date,text)` | 新增 | `7dc0f8c7fdd57f07cffc468d569cf319` | postgres only |
| `school_build_student_tuition_generation_snapshot(uuid,text,numeric)` | `083bcb58c2b92f34ded07dceafbbbbfe` | `4e7ddd85b884bf3607f14bb905bd9ed6` | postgres, service_role |
| `school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)` | `5cd35ca2bcbeff1f0b32e46e89d4a2cb` | `ff5181679cda96b26d2f27c17f6b9665` | postgres, anon, authenticated, service_role |
| `school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)` | `726c3f76786167bc70cb40b0ec9be613` | `e1d7414424dada7e1a77c0130c67d159` | postgres, authenticated |
| `school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)` | `e46c39ab2b35f9cc69b358402350ca17` | `23ee5d41a11f8a7b6ebf46283f3b0f6a` | postgres, anon, authenticated, service_role |
| `school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)` | `5e9138050f2c1a83bbca9eb605dde9ea` | `5727fa8abbb3037dfbcbff1ae06ddacd` | postgres, anon, authenticated, service_role |
| `school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)` | `f969a00b87a6e584d4b0696f8076208f` | `1b603474f0a0372652c4000ef0fec13d` | postgres only |
| `school_create_teacher_wage_rule_config(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)` | `09095668a484d00b9776f90d9f290610` | `5f8dec3835568ec0310a66ff6d41f0aa` | postgres, authenticated |
| `school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)` | `c4f710f9599140d443b8213ebab3855e` | `bb9c71e08ad87e428297e64bcf0751d7` | postgres only |
| `school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)` | `95030c052cdc39dd4f73344869509239` | `524b4703b08c6f91d366ac8ad4e969a0` | postgres only |
| `school_preview_student_tuition_bill(uuid,text,numeric)` | `8e9496463c1d54247f25042be3f6e5c5` | `87d3b1d7bed93a7c43d39748a1d69762` | postgres, authenticated, service_role |
| `school_update_lesson_record_guarded(uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)` | `f0f003006e6989c046a8139f7b123795` | `c684da67b5b35e6de1aeb0a14230e2f0` | postgres, anon, authenticated, service_role |
| `school_update_teacher_wage_rule_config(uuid,uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)` | `ed1929ef774f1d7f244222512bf54d44` | `3a20185c9548f1d3182c0585bbc2fd74` | postgres, authenticated |

三个 owner-only legacy core 与 legacy preview 的不安全旧 `search_path=public` 同时收紧为 `pg_catalog, public`；角色 ACL 未扩大。所有 wrapper/overload ACL 与 MD5保持不变。

### 4.3 Legacy status 谓词前后

部署前的 12 个正式资格谓词：

1. snapshot：`inactive/disabled/archived` 拒绝；
2. ordinary actual：`inactive/graduated` 拒绝；
3. cancel actual：`inactive/graduated` 拒绝；
4. makeup core：`inactive/graduated` 拒绝；
5. partial core：`inactive/graduated` 拒绝；
6. planned create：`inactive/graduated` 拒绝；
7. planned batch：`inactive/graduated` 拒绝；
8. planned import 两处学生检查：同一旧谓词；
9. planned update：`inactive/graduated` 拒绝；
10. wage create：`inactive/graduated/withdrawn` 拒绝；
11. wage update：`inactive/graduated/withdrawn` 拒绝；
12. legacy tuition preview：`inactive/disabled/archived` 拒绝。

部署后上述目标 W 链运行时计数为 0。生产 catalog 仍能搜到的其他 `school_students` + `status` 上下文均属于：Phase A resolver/shadow/event guard、B2 profile/immutable guard、页面显示/候选 reader、历史 diagnostic/baseline、其他业务行自身 `status`、或只读取学生姓名后检查 lesson/settlement/income 状态；未发现新的学生 legacy status 资格 writer。view `school_v_student_month_summary` 与两个 trigger 的宽泛命中也均不是学生 status 资格判断。

## 5. 实施后的业务合同

### 5.1 Planned

- 单条创建用 `school_resolve_planned_billing_attribution` 计算 billing month，再调用 owner-only active-at-month helper。
- 批量在展开 occurrence 后逐行 resolver；导入按每个 row 的日期逐行 resolver。错误包含 student UUID、日期、billing month 与解析状态；任一错误沿用原 `batch_committed=false` 原子合同，不产生部分行。
- 编辑先用既有 `school_resolve_r1d_e_c_lesson_student_month` 取得旧权威月；已被 evidence/bill 消费的 planned 保持旧月，否则目标日期重新走 billing attribution resolver。只有学生 UUID 或权威月变化才检查 active。
- `expected_updated_at`、`FOR UPDATE`、业务归属、学费/月结/工资/claim/immutable 锁均未改。

### 5.2 Actual / partial / makeup / correction

- ordinary actual、partial、direct makeup 与跨月 wrapper 均不再以学生后来 paused/left 拒绝既有 source。
- makeup 学生结算月仍来自 source planned；老师工资月仍来自 actual 真实日期。
- 不计费 makeup、余额、重复 consumption、overage、未来日期、locked settlement/wage、claim 与 bill consumption 保护均未放宽。
- 通用 actual 编辑能力没有扩大；受控 replace writer 的固定 scope/service_role/immutable 检查未改，只会委托已切换的 makeup core。

### 5.3 取消 writer

- 终态 MD5 `e1d7414424dada7e1a77c0130c67d159` 与 canonical source 一致；相对起点仅删除 `student.status` 资格谓词并更新 comment。
- owner `postgres`、SECURITY DEFINER、安全 search path；PUBLIC/anon/service_role 无 EXECUTE，仅 authenticated 入口，函数内 active admin/operator membership 断言不变。
- `school_tuition_p0b1_lock_existing_lesson_scope`、source `FOR UPDATE`、linked actual 单例检查、账单消费（含 void/reissue revision）、学生月结锁、工资锁、P0-F claim 均仍在定义中。
- DB 按起止时间计算时长并校验 15 分钟网格；cancel actual 固定 nonbillable、`lesson_fee=0`、`actual_minutes=0`；source 原子改为 `pending_makeup`。
- 本轮 rollback 重验第二次调用拒绝、完整角色与 guard 矩阵。最新取消任务已经对同一锁合同完成真实双会话并发：Session B 等待 Session A，随后以 `LESSON_CANCELLATION_LINKED_ACTUAL_EXISTS` 拒绝，只保留一条 actual。本轮定义差异和 postdeploy 精确证明锁、`FOR UPDATE` 与单例检查未变化。为遵守本项目禁止自动 DELETE 清理的新运行 guardrail，没有再次执行会先 commit 再 DELETE `c609` fixture 的旧并发脚本。

### 5.4 工资规则

- create、换学生、false→true 重新启用都用 DB `clock_timestamp() AT TIME ZONE 'Asia/Tokyo'` 计算当前月并要求 active。
- 同学生普通字段修正与 true→false 停用不加状态门控。
- 历史规则 reader、工资生成与顶部筛选未改；没有给工资、expense、reimbursement、Cash 新增学生状态门控。

### 5.5 Tuition 与财务收尾

- snapshot 与 legacy preview 删除冻结状态拒绝；atomic base/core、validation、generate、reissue 通过同一 snapshot 获得候选与既有财务合同。
- void/reissue/generate-next-revision core 实时定义原本不含学生 legacy status 谓词，无需修改。
- 是否可生成继续由课时、月结、bill、income、不可变合同与 Gate 决定。生产 `student_tuition_generate=blocked`，本轮 rollback 的 generate 调用被 Gate 拒绝。
- 没有生成、void、reissue、提交 Cash 或修改真实 bill/income/settlement。

## 6. 测试

### 6.1 静态与彩排

- `git diff --check`：通过。
- `node --check scripts/student-status-phase-b3-writer-authority-static-test.mjs`：通过。
- B3 静态测试：`STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_STATIC_TEST_PASS`。
- B1 防回退静态测试：`STUDENT_STATUS_PHASE_B1_WEEKLY_READER_STATIC_TEST_PASS`。
- 完整部署 rehearsal：13 个终态 MD5、ACL、search path、Gate、事件 writer、B1 reader 和 residue 全通过，输出 `STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_REHEARSAL_PASS` 后显式 ROLLBACK。

### 6.2 B3 rollback matrix

最终输出 `STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_ROLLBACK_PASS` 并显式 ROLLBACK，覆盖：

- 无事件 fallback active、最后 active、下月 paused、恢复 active、left 与跨月边界；
- planned active 创建、paused/left 拒绝；
- batch/import 每 occurrence/row 独立月份验证和整批不提交；
- 当前已 left 学生的同学生同权威月历史修正允许，移入 paused 月及换为目标月 paused 学生拒绝；
- paused 后 ordinary actual、取消、partial、direct makeup、cross-month wrapper 均成功；学生月来自 source、老师月来自 actual；
- 工资规则 active 创建、paused 创建拒绝、换 paused 学生拒绝、停用允许、同 paused 学生普通修正允许、重新启用拒绝；
- paused snapshot、left preview 不再命中旧状态错误，generate 仍被 Gate 拒绝，void/reissue/generate-next core 无旧谓词；
- helper、event writer、cancel writer 与 B1 reader metadata 不回退。

### 6.3 取消专项 rollback

`school_cancelled_actual_writer_hardening_rollback_tests_20260806.sql` 使用 B3 canonical source重跑并输出 `CANCELLATION_WRITER_HARDENING_ROLLBACK_TEST_PASS`：active admin/operator成功；anon、service_role、read_only、inactive、无membership和无auth拒绝；DB duration、网格、费用、分钟、余额、单例、pending_makeup、locked settlement/wage、consumed bill/revision、claim 和失败零残留均通过。

## 7. SQL、RPC、fixture 与数据库写入

### 7.1 执行的 SQL 文件

- 回滚/只读：
  - `sql/tests/student_status_phase_b3_writer_authority_rehearsal_20260806.sql`
  - `sql/tests/student_status_phase_b3_writer_authority_rollback_test_20260806.sql`
  - `sql/current/school_cancelled_actual_writer_hardening_rollback_tests_20260806.sql`
  - `sql/current/school_student_status_phase_b3_writer_authority_postdeploy_20260806.sql`
  - `sql/current/school_cancelled_actual_writer_hardening_postdeploy_20260806.sql`
  - `sql/current/school_student_status_phase_b2_legacy_freeze_postdeploy_20260806.sql`
- 正式 School DB COMMIT：
  - `sql/current/school_student_status_phase_b3_writer_authority_deploy_20260806.sql`
  - 仅函数/helper/comment/ACL 定义；业务行 DML 0。

### 7.2 回滚内调用的写 RPC

`school_create_planned_lesson_record`、`school_generate_planned_lessons_batch`、`school_import_lesson_records_batch`、`school_update_lesson_record_guarded`、`school_create_actual_lesson_from_planned`、`school_create_cancelled_actual_lesson_from_planned`、`school_create_partial_completed_actual_from_planned`、`school_create_lesson_credit_makeup_actual`、`school_create_cross_month_makeup_completed_actual_from_planned`、`school_create_teacher_wage_rule_config`、`school_update_teacher_wage_rule_config`。另调用 tuition generate 验证 Gate，函数在任何业务写入前 fail-closed。

fixture 均为固定 `codex-test` 白名单范围：auth user `b301…`、student `b302…`、lesson/batch/import `b303…`、teacher/subject `b304…`、event `b305…`、wage rule `b306…`；取消专项为 `c608…`。全部显式 ROLLBACK，最终 residue 0。没有 commit-test 业务行，没有调用两个真实事件 writer，没有修改唯一真实事件。

### 7.3 持久写入

- School DB：只持久更新 13 个函数/helper定义、12条函数注释和 helper 最小 ACL；真实学生、状态事件、课时、月结、收入、bill、工资、支出、账户、流水业务行写入 0。
- Cash DB：只读；写入 0，请求/交易 0。
- Storage：只读指纹核验；上传、替换、删除 0。
- 页面：无写验收，未点击任何保存、生成、取消或 Cash 操作。

## 8. 前后业务指纹

| 对象 | 前 | 后 |
|---|---|---|
| students | 8 / `431ae7f350902dde0642ddc4982054ed` | 相同 |
| legacy status | active 7 / paused 1 | 相同 |
| status events | 1 / `eeeb492ac7577ff85eb0926aa0b57301` | 相同 |
| lessons | 738 / `fc802f6d7da3ece1182bd2c217955562` | 相同 |
| settlements | 18 / `7986db5dd35c0ecfa180a04aef7f4051` | 相同 |
| student income | 30 / `0380f2e4ab967d37ad898a4e534195a4` | 相同 |
| tuition bills | 22 / `d079f068c0fa19fc07d4dcd94094fae2` | 相同 |
| wage details | 556 / `0b2976f8005835d66b2db25b0b3c1939` | 相同 |
| wage rules | 20 / `2dc430ca4a58416235f2ba771b91b9f1` | 相同 |
| all income | 55 / `bd2d538d1de901621ff0e6757984a41e` | 相同 |
| expenses | 47 / `141c76e4cf6148007e182704941a0c4a` | 相同 |
| accounts | 3 / `443b3170f50bc23a56834d398069c565` | 相同 |
| account transactions | 187 / `21694ff060e23289566f0a6e9fe3e449` | 相同 |
| Cash requests | 42 / `dfb00aaa210894f78c47285e21d2f222` | 相同 |
| Cash CNY | 73 / `937cbd8d10480c5c5dabaab658eb2558` | 相同 |
| Cash JPY | 31 / `3f3f257b14b43c12925a8eecb7a8ca02` | 相同 |
| Storage / orphan | 57 / 30 / `c2852a4dbcd13b9cddb1da0b1115b18f` | 相同 |
| Gate | enabled / blocked / enabled | 相同 |

唯一真实事件仍为 `4190bddf-d995-4e6a-af6b-85997e6f999b`，学生 `cff85c52-6acc-4b0f-8c92-3db280a5dd77`，effective month `2026-07-01`，status `paused`。2026-06 解析为 legacy fallback active；2026-07/08 均由该事件解析为 paused。B1 weekly reader MD5 仍为 `e7eac5f3bb07c31ad15e750e8721c01f`，12 个验收周仍各返回该学生唯一一行。

## 9. 部署、Git、Pages 与 Chrome

- 实现提交：`576c35725ee9edf4878e211cc7e8122e147c61cc`，已 push `main` 后才正式部署 SQL。
- 实现 Pages run：`31032034311`，success，head SHA 精确为 `576c357…`。
- 正式 School SQL COMMIT 与 B3/B2/cancellation 三组 postdeploy 均通过。
- Chrome 使用既有 active-admin session，仅做读取：
  - 学生页 `v10.5.9`、共 8 名、唯一暂停 badge、console warn/error 0；
  - 工资页 `v10.5.9`、2026-08、顶部仍有业务归属筛选、没有学生顶部筛选、console warn/error 0；
  - 没有打开或提交任何写 dialog。

## 10. 修改文件

实现提交 8 个文件：

- `scripts/student-status-phase-b3-writer-authority-static-test.mjs`
- `sql/current/school_cancelled_actual_writer_hardening_postdeploy_20260806.sql`
- `sql/current/school_create_cancelled_actual_lesson_from_planned_rpc.sql`
- `sql/current/school_student_status_phase_b3_writer_authority_core_20260806.sql`
- `sql/current/school_student_status_phase_b3_writer_authority_deploy_20260806.sql`
- `sql/current/school_student_status_phase_b3_writer_authority_postdeploy_20260806.sql`
- `sql/tests/student_status_phase_b3_writer_authority_rehearsal_20260806.sql`
- `sql/tests/student_status_phase_b3_writer_authority_rollback_test_20260806.sql`

收尾文档：本报告与 `docs/current-status.md`。

## 11. 受保护文件

六份 untracked 文件始终未修改、移动、删除、暂存或提交，前后 SHA-256 完全一致：

```text
272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432  docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv
5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093  docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt
b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54  sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql
5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a  sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql
b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773  sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql
7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b  sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql
```

## 12. 后续待办与停止点

Phase B3 已完成，本轮停止，不启动 B4/B5。后续仅在业务负责人单独授权后进行：

1. B4 第一项：工资结算顶部用“学生”替换“业务归属”，学生候选按页面月份 resolver 加载。
2. 上述功能完成后，再单独调查并讨论删除业务归属中的个人明细。
3. B5 仍需在 B3/B4 均验收后单独授权，才可恢复两个状态事件 writer 的 authenticated EXECUTE；本轮两者继续 owner-only。
