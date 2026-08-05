# School V2 学生月份状态 Phase B2：legacy status 冻结与状态变更临时关闭报告

日期：2026-08-06（Asia/Tokyo）

## 1. 结论

Phase B2 已完成并上线，可以进入 B3 的独立授权；本轮没有启动 B3、B4 或 B5。

- `school_students.status` 已成为冻结的 legacy snapshot：新行只能是精确 `active`，已有行禁止改变。
- 学生普通资料新增、编辑已切换到不接受 `status` 的新 canonical writer；active admin 可继续正常使用，其他角色拒绝。
- 3 个旧 create overload、6 个旧 update overload 已全部收紧为 owner-only；不存在客户端 fallback。
- Phase A 的 record/correction event writer 已临时收紧为 owner-only；resolver/history 不变，唯一真实事件不变。
- 学生页创建/编辑表单均无可写状态字段，保留旧顶部 legacy 状态筛选，并显示指定冻结说明。
- rollback、角色矩阵、双会话、postdeploy、静态检查和生产 Chrome 无写验收通过；业务行持久写入 0，fixture residue 0。

## 2. 实时起点

| 项目 | 起点结果 |
|---|---|
| 分支 | `main` |
| HEAD / fetch 后 `origin/main` | `dbd34a4941f0f50f9356241fe9e4ebf9c14c9444` |
| ahead / behind | `0 / 0` |
| 工作区 | 仅六份受保护 untracked 文件 |
| 页面版本 | `v10.5.6` |
| Pages | run `31016412587`，success |
| 学生 | 8；active 7、paused 1；全行 MD5 `431ae7f350902dde0642ddc4982054ed` |
| 状态事件 | 1；MD5 `eeeb492ac7577ff85eb0926aa0b57301` |
| 课时 | 738；MD5 `fc802f6d7da3ece1182bd2c217955562` |
| B1 weekly reader | MD5 `e7eac5f3bb07c31ad15e750e8721c01f` |
| Gate | preview=`enabled` / generate=`blocked` / cash_submit=`enabled` |

起点课时 738 比 B1 报告的 736 多 2 条；两条均在 B2 数据库变更前由正常生产操作创建：`aec2dc15-f31f-409b-8c75-6ba1f6ac9486`、`434932cf-efbb-4fc9-9ee8-a3b9df7eaf74`。本轮以实时 738 为基线，没有回退合法业务数据。

`school_students.status` 起点为 `text NOT NULL DEFAULT 'active'`，无 status CHECK；起点业务 trigger 只有 `trg_school_students_updated_at`。表 ACL/RLS 延续学生主数据 P0 合同：authenticated 的 active admin/operator/read_only 可读，service_role 仅保留后台所需 SELECT，所有客户端表级 DML 关闭。

profile writer 起点共 3 个 create、6 个 update overload。页面只调用当时 canonical create/update，旧 overload 已是 owner-only；没有合法 service_role 学生 profile 写链。事件 writer 冻结前两签名均为 `postgres` 与 `authenticated` 可执行，PUBLIC/anon/service_role 拒绝，组合 ACL MD5 为 `e691cc9c700dc80a858da21011bd9bb4`。

## 3. 业务模型扩展声明与依赖复核

本阶段无新业务表、业务列、状态值、月份、身份、来源、snapshot、可写事实、历史重解释、双写、兼容 fallback 或破坏性变更。业务负责人在本任务中逐项批准的语义变化是：冻结 `school_students.status`；新增不含 status 的唯一客户端 create/update；旧 profile writer owner-only；临时将两个事件 writer owner-only；B5 仅在 B3/B4 验收后恢复 authenticated 执行权。

依赖扫描结论：

- 实际修改 `school_students` 的运行时函数仅 3 个 create 和 6 个 update overload；浏览器调用方仅 `js/api/student-api.js`。
- student page 对学生表仅 SELECT，写操作经 API wrapper；无 page-layer `.rpc()` 或直接 INSERT/UPDATE/DELETE/UPSERT。
- Edge 的 service_role 用途仅为读取学生姓名，不写学生；无需要迁移的合法后台 profile writer。
- 唯一学生 view 不可写；import、历史 migration、测试与运维 SQL 不是客户端运行时入口，并均受到新表级 guard 约束。
- B2 没有修改任何 B3 writer 资格、B4 顶部候选、lesson/tuition/wage/finance reader 或 writer。

## 4. 数据库合同

### 4.1 新 canonical create

```sql
public.school_create_student_profile_v2(
  text, uuid, text, numeric, text, text, date, text, text
)
```

函数为 `SECURITY DEFINER`、`search_path=pg_catalog, public`，首段调用 `school_require_current_app_admin()`；仅 authenticated 有 EXECUTE，anon/service_role 拒绝，operator/read_only/无 membership/inactive 由 DB admin guard 拒绝。客户端不能传 status，DB 精确写 `status='active'`，不创建状态事件；无事件时 Phase A resolver fallback 为 active。既有姓名、业务归属、文理、汇率、联系方式、入学日、目标学校和备注校验及 canonical 返回保持。

### 4.2 新 canonical update

```sql
public.school_update_student_profile_v2(
  uuid, text, uuid, text, numeric, text, text, date, text, text, timestamptz
)
```

权限与安全属性同 create。函数接受 student UUID 与 `p_expected_updated_at`，对目标行 `FOR UPDATE` 后精确比较版本；陈旧版本以 SQLSTATE `40001` 拒绝。函数不接受、不赋值 status，也不写状态事件，只更新普通资料并返回 canonical 学生记录。

### 4.3 全部旧 profile 签名终态

以下签名的 PUBLIC、anon、authenticated、service_role EXECUTE 全部撤销，仅 owner 保留：

```text
school_create_student_profile(text,text,text,text,text,text,text,text,uuid,text,text)
school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text)
school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text,text)

school_update_student_profile(uuid,text,text,text,text,text,text,text,uuid,text,numeric,text)
school_update_student_profile(uuid,text,text,text,text,text)
school_update_student_profile(uuid,text,text,text,text,uuid,text,text)
school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text)
school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text)
school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text,timestamptz)
```

旧函数体不作为客户端 fallback；即使 owner 调用，也不能绕过表级 immutable guard。

### 4.4 immutable guard

`school_students_legacy_status_immutable_guard` 是 `BEFORE INSERT OR UPDATE FOR EACH ROW` trigger，调用 owner-only `school_guard_legacy_student_status_immutable_v1()`：

- INSERT：`NEW.status IS DISTINCT FROM 'active'` 时以 SQLSTATE `23514` / `STUDENT_LEGACY_STATUS_INSERT_MUST_BE_ACTIVE` 拒绝。
- UPDATE：`NEW.status IS DISTINCT FROM OLD.status` 时以 SQLSTATE `23514` / `STUDENT_LEGACY_STATUS_IMMUTABLE` 拒绝。
- NULL、大小写、未知值、直接表写、service_role、旧 owner 函数和间接写入均不能绕过；status 不变的普通资料更新允许。
- 本轮不新增 status CHECK，不映射 graduated/withdrawn，不重写现有 7 active / 1 paused，也不回填事件。

### 4.5 事件 writer 临时冻结与 B5 恢复合同

签名：

```text
school_record_student_status_event_v1(uuid,date,text,text,uuid,text)
school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)
```

冻结后每个 ACL 都精确为 `{postgres=X/postgres}`；PUBLIC、anon、authenticated、service_role 均无 EXECUTE，owner 保留。组合 ACL MD5 从 `e691cc9c700dc80a858da21011bd9bb4` 变为 `dcae288bf402686f19991094bb6c588d`。record/correction 函数体 MD5 分别保持 `2ce0885969021516a804d5c887b6af39`、`4ba55f37406f7d2d3a4d0d8e24a7496b`；事件表 ACL/RLS、mutation guard、resolver 和 history reader 未改。

B5 的精确恢复前置条件是 B3、B4 均已验收，且只能执行：

```sql
revoke all on function public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)
  to authenticated;

revoke all on function public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)
  to authenticated;
```

不得授予 PUBLIC、anon 或 service_role；函数内部 active-admin 断言和表级保护必须保留。本轮没有执行上述恢复。

## 5. 页面与 API

- `student.html` 的新增、编辑 dialog 均移除可写 status；两处显示：`学生状态管理正在切换为按月份生效，当前暂不可修改。`
- 新增说明明确新学生由 DB 固定为在籍且不自动建立状态事件。
- `student-page.js` 的 create/update payload 不再包含 status，update 继续携带 expected `updated_at`。
- `student-api.js` 仅调用两个新 `_v2` canonical 签名，没有旧签名 fallback。
- 顶部 status 筛选及卡片 legacy status 显示保持原行为；默认仍显示全部学生。
- 版本从 `v10.5.6` 递增为 `v10.5.7`。

## 6. 测试与部署

### 6.1 静态、rehearsal 与 rollback

- `git diff --check`、API/page/test `node --check`、P0 静态测试、B1 静态测试和 B2 静态测试全部通过。
- 第一次 rehearsal 发现 PostgreSQL 不允许用 `CREATE OR REPLACE` 移除既有默认参数，事务自动回滚、residue 0；因此采用不会产生默认参数解析歧义的独立 `_v2` 名称，没有 DROP 旧函数。
- 两次 rollback 测试初稿因调用 6 参数旧 update 命中默认参数歧义而安全回滚；矩阵改为精确 12 参数旧路径后通过。
- 最终 runtime rollback matrix 输出 `STUDENT_STATUS_PHASE_B2_LEGACY_FREEZE_ROLLBACK_PASS` 并显式 ROLLBACK。
- 覆盖 active admin create/update、固定 active、event 0、resolver fallback、stale `40001`、anon/无 membership/inactive/operator/read_only/service_role、旧签名 ACL、直接 active→paused、真实 paused→active、非 active/NULL/大小写 INSERT、旧 owner 函数、事件 writer 冻结；所有 synthetic UUID 最终 residue 0。

### 6.2 双会话

对真实 active 学生 `4c6f1473-7d44-467d-a70b-30f02e7cf8cd` 使用完全相同的普通资料 payload：Session A PID `2301333` 在事务内取得行锁，Session B PID `2301365` 调用新 update 后实际等待 A 的 transactionid lock；观察到 B 的未授予 ShareLock 与 blocker A。A ROLLBACK 后 B 成功返回，B 也 ROLLBACK。没有 lost update、deadlock、半写入或真实学生持久变更；陈旧版本 `40001` 另由 rollback matrix 验证。

### 6.3 正式部署和 fail-closed 窗口

- 实现提交：`a9493aba9c1e5ca3633fd9f7c240386fb607d854`，已 push `main`。
- School DB 执行 `sql/current/school_student_status_phase_b2_legacy_freeze_deploy_20260806.sql`，COMMIT；只写 function/trigger/ACL/comment 定义，业务行写入 0。
- postdeploy 输出 `STUDENT_STATUS_PHASE_B2_LEGACY_FREEZE_POSTDEPLOY_PASS`。
- Pages run `31023458610`（HEAD `a9493ab…`）于 `2026-08-06 01:04:28 JST` success，生产为 `v10.5.7`。

push 自动触发的 Pages 比人工 DB 部署更快完成，因此实际顺序为“新 UI 先可见、DB 随后完成”，不是建议的 DB→Pages 顺序。该窗口仍严格 fail-closed：新 UI 只能调用尚不存在的 `_v2`，会失败，不能回退旧 writer、不能双写 status，也不能恢复事件权限。未取得 DB COMMIT 的独立时间戳；从 Pages success `01:04:28 JST` 到首次已部署 runtime 测试时间 `01:06:14 JST` 的可验证上界为 **1 分 46 秒**，实际 DB 完成更早。没有观察到或提交任何窗口期业务写入。

## 7. 生产 Chrome 验收

使用既有 active-admin Chrome session 强制刷新生产 `student.html`，只读验收：

- 页面为 `v10.5.7`，显示共 8 名并包含 paused 学生。
- 新增 dialog 无 status 输入，冻结说明与默认 active/无事件说明正确；只点击取消。
- paused 学生编辑 dialog 无可写 status，普通资料字段和冻结说明正常；只点击取消。
- 旧顶部筛选选择“暂停”得到 `共 1 名`，恢复“全部”得到 `共 8 名`。
- Console warning/error 为 0；未点击新增或保存，未产生学生或事件写入；测试后已恢复 Chrome cache 设置。

## 8. 最终数据与不变量

| 对象 | 最终 count / 分布 | 最终 MD5 |
|---|---:|---|
| students | 8；active 7 / paused 1 | `431ae7f350902dde0642ddc4982054ed` |
| status events | 1 | `eeeb492ac7577ff85eb0926aa0b57301` |
| lessons | 738 | `fc802f6d7da3ece1182bd2c217955562` |
| settlements | 18 | `7986db5dd35c0ecfa180a04aef7f4051` |
| student income | 30 | `0380f2e4ab967d37ad898a4e534195a4` |
| tuition bills | 22 | `d079f068c0fa19fc07d4dcd94094fae2` |
| wage details / rules | 556 / 20 | `0b2976f8005835d66b2db25b0b3c1939` / `2dc430ca4a58416235f2ba771b91b9f1` |
| all income / expenses | 55 / 47 | `bd2d538d1de901621ff0e6757984a41e` / `141c76e4cf6148007e182704941a0c4a` |
| accounts / transactions | 3 / 187 | `443b3170f50bc23a56834d398069c565` / `21694ff060e23289566f0a6e9fe3e449` |
| Storage / orphan | 57 / 30 | `c2852a4dbcd13b9cddb1da0b1115b18f` |
| Cash requests / CNY / JPY | 42 / 73 / 31 | `dfb00aaa210894f78c47285e21d2f222` / `937cbd8d10480c5c5dabaab658eb2558` / `3f3f257b14b43c12925a8eecb7a8ca02` |

唯一真实 event `4190bddf-d995-4e6a-af6b-85997e6f999b` 与 paused 学生 `cff85c52-6acc-4b0f-8c92-3db280a5dd77` 不变；resolver 在 2026-06 为 legacy fallback active，在 2026-07/08 为该事件决定的 paused。B1 weekly reader 定义 MD5 仍为 `e7eac5f3bb07c31ad15e750e8721c01f`，12 个验收周均仍返回 paused 学生唯一一行。Gate、Cash、Storage 和全部财务指纹零变化；fixture user/student/event 均 0，开放测试会话 0。

## 9. 修改文件

- `js/api/student-api.js`
- `js/config.js`
- `js/pages/student-page.js`
- `student.html`
- `scripts/student-status-phase-b2-legacy-freeze-static-test.mjs`
- `sql/current/school_student_status_phase_b2_legacy_freeze_core_20260806.sql`
- `sql/current/school_student_status_phase_b2_legacy_freeze_deploy_20260806.sql`
- `sql/current/school_student_status_phase_b2_legacy_freeze_postdeploy_20260806.sql`
- `sql/tests/student_status_phase_b2_legacy_freeze_rollback_test_20260806.sql`
- `docs/school-v2-student-status-phase-b2-legacy-freeze-20260806.md`
- `docs/current-status.md`

没有修改 lesson、tuition、wage、finance、Cash、Storage 或 Edge 文件。

## 10. 受保护文件

六份 untracked 文件始终未修改、移动、删除、暂存或提交；最终 SHA-256：

```text
272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432  docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv
5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093  docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt
b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54  sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql
5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a  sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql
b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773  sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql
7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b  sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql
```

## 11. 交付状态

- School DB：已部署 B2 function/trigger/ACL/comment；真实学生、事件及其他业务行写入 0。
- Cash DB、Storage：只读核验，写入 0。
- 白名单测试：全部 synthetic 且显式 ROLLBACK；没有 commit test 业务行，测试 UUID residue 0。
- B3/B4/B5：均未开始；状态变更请求必须等待 B5，禁止直接 UPDATE legacy status 或手工调用 owner writer。
- 最终判定：**B2 已完成，可以进入 B3 的独立授权。**
