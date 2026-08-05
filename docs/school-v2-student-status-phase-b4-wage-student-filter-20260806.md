# School V2 学生月份状态 Phase B4-Wage：工资顶部学生筛选报告

日期：2026-08-06（Asia/Tokyo）

## 1. 结论

Phase B4-Wage 已完成实现、推送、Pages 部署、生产 Chrome 无写验收和最终只读复核。本轮只完成“老师工资结算顶部筛选由业务归属替换为学生”，没有启动 B4 其他项目或 B5。

- 顶部筛选现为月份、老师、学生、结算类型、状态、关键字；真实业务归属列、详情、快照和 DB 字段均保留。
- 学生候选以工资页所选月份调用 Phase A `school_list_student_month_candidates_v1`；默认只含本月在读，勾选“包含暂停/离校学生”后显示全部。
- 暂停、离校标签分别为“本月暂停”“本月已离校”；URL 已选非在读学生在默认模式下由 selected override 保留，切月后重新解析。
- 工资快照按既有冻结明细 `school_teacher_wage_lock_details.lock_id + student_id` 匹配；候选课时按课时事实 `student_id` 匹配。学生状态只控制下拉候选，不裁剪真实工资或候选事实。
- 学生筛选不进入工资生成参数；页面生成调用只传月份和可选老师，DB 继续按完整 `teacher + business_entity + month` 范围生成。
- 没有新增或修改 DB schema、函数、ACL、RLS、writer、Gate 或业务行；没有调用任何写 RPC。

## 2. 起点与范围

| 项目 | 起点 |
|---|---|
| 分支 | `main` |
| HEAD / `origin/main` | `74405cf9bf20cb0401ca3847e5ebeeb103ca83d5` |
| ahead / behind | `0 / 0` |
| 工作区 | 仅六份任务书点名的受保护 untracked 文件 |
| 页面版本 | `v10.5.9` |
| Pages | run `31032614260`，success，head `74405cf…` |
| 工资顶部 | 月份 / 老师 / 业务归属 / 结算类型 / 状态 / 关键字 |
| Gate | preview=`enabled` / generate=`blocked` / cash_submit=`enabled` |

本轮未删除或重解释 `business_entity_id`，未删除个人明细，未改工资规则、快照金额、锁、支出、Cash、学生月结、学费、课时或状态事件 writer。

## 3. Business-model expansion declaration

| 声明项 | 结果 |
|---|---|
| 新表 | `none` |
| 新列 | `none` |
| 新 enum/status values | `none` |
| 新日期/月/归属概念 | `none`；复用工资页既有月份和 Phase A target month |
| 新 identity/source/snapshot/version/writable facts | `none` |
| 既有字段语义或 mutability 变化 | `none` |
| locking 变化 | `none` |
| 新权威源 | `none` |
| legacy fallback / dual read / dual write | `none` |
| 历史重解释 / destructive schema | `none` |
| reader authority | 顶部学生资格读取既有 Phase A resolver；快照学生归属读取冻结工资明细；候选读取课时事实。均由本任务逐项明确批准 |
| writer 调用范围 | DB writer/ABI 不变；页面不再从顶部传业务归属，也从不传学生，只按月份/老师调用完整范围。由本任务“学生仅查询展示、不得改变生成范围”明确批准 |

声明在业务代码修改前完成。无需 schema/RPC 设计与执行，扩展门通过。

## 4. 依赖调查与权威关系

### 4.1 页面与 API

- 原页面 `wageBusinessEntitySelect` 同时影响快照、候选、生成预览与 `school_generate_teacher_monthly_wage` 的 `p_business_entity_id`。
- 月度汇总导出原本固定导出当月全部未作废快照，不复用顶部业务归属筛选；本轮保持。
- 批量勤务申报表导出使用当前显示快照；学生筛选可以缩小其只读快照集合，但每份仍导出完整工资快照明细。
- 单条/批量支付始终以显式选择的完整工资快照 ID 为单位；学生不进入支付 RPC，也不会生成学生级部分支付。
- 页面模块没有直接 `.rpc()` 或表 DML；resolver 仍通过 `js/api/wage-api.js` 调用。

### 4.2 生产工资事实

`school_teacher_wage_lock_details` 已有非空可用的 `lock_id`、`student_id` 和学生姓名 snapshot，足以表达“某工资快照是否包含某学生”，无需新 reader。

| 工资月 | 明细数 | 学生数 | 多学生快照数 | 明细 MD5 |
|---|---:|---:|---:|---|
| 2026-02 | 52 | 1 | 0 | `776609a8e9361ef9f2f103a756a263d7` |
| 2026-03 | 110 | 1 | 0 | `fc2a093f7d28e468f383bc29f5f78702` |
| 2026-04 | 129 | 3 | 8 | `d56cb146e93e28532dc0517f0149c48c` |
| 2026-05 | 146 | 5 | 11 | `c2c46abcd9e06438247dcaa0e6178a6d` |
| 2026-06 | 119 | 5 | 8 | `54e7942e52ca880864f46b99b9c7ba9c` |

生产现状中没有学生跨多个工资快照业务归属，但实现没有据此做单归属假设；匹配始终按 lock-detail 关系处理。多学生快照证明学生只能作为查看筛选，不能成为快照生成或支付粒度。

## 5. 实现合同

### 5.1 候选与 URL

- `student_id` 和 `include_inactive=1` 为新 URL 参数；月份、老师、学生、类型、状态、关键字均可刷新保留。
- 旧 `business_entity_id` 及既有 camel-case business filter 不读取、不转换；页面同步 URL 时会清除。
- 默认候选：2026-06 为 8、2026-07 为 7、2026-08 为 7；包含非在读后三个月均为 8。
- 唯一事件学生 `cff85c52-6acc-4b0f-8c92-3db280a5dd77` 在 6 月为 fallback active，在 7/8 月为 event paused；selected override 在非包含模式下仍返回并显示暂停标签。

### 5.2 快照、候选与关键字

- API 批量读取当前月份工资 lock IDs 对应的 `lock_id,student_id`，页面仅以这个冻结关系判断快照是否包含所选学生。
- 候选课时直接以其 `student_id` 筛选；状态筛选仍只作用于工资快照。
- 关键字新增匹配工资快照包含学生的姓名，同时保留老师、业务归属、类型与状态匹配。
- 下拉月份状态绝不参与 `wageCandidateLessons` 资格判断，因此 paused/left 的真实历史课时不会被删除。

### 5.3 生成、支付与导出

- `handleGenerateSubmit` 调用 `generateTeacherMonthlyWage` 时只传 `yearMonth`、`teacherId`；没有 `studentId` 或顶部 business filter 参数。
- 生成前学生结算检查与预计生成分组只按月份/老师完整范围计算；当前显示分组可反映学生筛选。
- 对话框固定说明：`学生仅用于筛选查看，生成老师工资仍按完整工资快照范围执行。`
- 支付仍写完整工资快照，不产生学生级部分支付；页面顶部也显示相同完整快照边界。
- 月度汇总保持全月未作废快照；勤务申报表可按当前学生筛选缩小快照集合，但每个导出文件仍是完整快照。

## 6. 测试

### 6.1 静态

- `git diff --check`：通过。
- `node --check`：`wage-api.js`、`wage-page.js`、`wage-app.js`、B4 静态脚本全部通过。
- `STUDENT_STATUS_PHASE_B4_WAGE_STUDENT_FILTER_STATIC_TEST_PASS`。
- `STUDENT_STATUS_PHASE_B1_WEEKLY_READER_STATIC_TEST_PASS`。
- 全页面直接 `.rpc()` / table DML：0；浏览器 service-role marker：0。
- 静态断言覆盖 resolver 参数、selected override、detail membership、candidate student、URL、legacy 清理、生成参数、完整范围说明、版本与 cache bust。

### 6.2 DB 只读

Phase A resolver：

| 月份 | 默认 | 包含非在读 | 唯一事件学生 |
|---|---:|---:|---|
| 2026-06 | 8 | 8 | active / fallback |
| 2026-07 | 7 | 8 | paused / event `4190bddf-…` |
| 2026-08 | 7 | 8 | paused / event `4190bddf-…` |

候选课时全量基线：

| 工资月 | 条数 | 分钟 | MD5 |
|---|---:|---:|---|
| 2026-04 | 31 | 3809 | `ac759723134d2e70147dda20c2ea0a3d` |
| 2026-05 | 57 | 6930 | `7191ab2270e92c141d839d0e75e9aa92` |
| 2026-06 | 63 | 7530 | `cc36d4a20bebdd67c8329c6b4aa32385` |
| 2026-07 | 56 | 6660 | `19955596e11633e3b5e64b47a57fbfbb` |
| 2026-08 | 14 | 1650 | `070d6264f7c4c941d762df27ec57667b` |

唯一 paused 学生对应候选为 2026-04 `2 / 240`、05 `8 / 960`、06 `10 / 1200`，7/8 月为 0。

### 6.3 生产 Chrome 无写验收

- 生产版本 `v10.5.10`，顶部业务归属已替换为学生；其他真实业务归属列保持。
- 8 月默认下拉 7 名；包含非在读后 8 名，厦门吕同学显示“本月暂停”。
- 关闭包含非在读后，已选暂停学生继续保留并带标签；URL 只保留 `student_id`，包含时追加 `include_inactive=1`。
- 切到 6 月后同一学生重新解析为 active，显示 1 条有效历史工资快照和 10 条 / 1200 分钟候选。
- 6 月恢复全部学生：9 条有效快照、63 条 / 7530 分钟候选；快照课时数和分钟均为 63 / 7530，与 DB 一致。
- 6 月状态切到 void：快照 8 条，候选仍 63 条，证明状态不裁剪候选事实。
- 8 月选张倬闻并刷新：`student_id`、姓名及 5 条候选保持。
- 生成对话框“当前显示分组”仅显示张倬闻相关组，“预计生成分组”仍为全月 6 个老师分组、业务归属范围为全部；确认 checkbox 未勾选，只点击取消。
- 重置恢复 2026-08 / 全部学生 / 不包含非在读 / 默认状态；旧 `business_entity_id=legacy-test` 自动清除。
- 390×844：无页面横向溢出，学生 select 宽 346px，包含开关可见；恢复默认视口。
- Console error/warning：0；未点击生成提交、支付、导出下载或任何保存操作。

## 7. Postdeploy 与不变量

- `STUDENT_STATUS_PHASE_B1_WEEKLY_READER_POSTDEPLOY_PASS`
- `STUDENT_STATUS_PHASE_B2_LEGACY_FREEZE_POSTDEPLOY_PASS`
- `STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_POSTDEPLOY_PASS`
- `CANCELLATION_WRITER_HARDENING_POSTDEPLOY_PASS`
- 两个状态事件 writer 继续 owner-only；B1 reader MD5 继续为 `e7eac5f3bb07c31ad15e750e8721c01f`。

| 对象 | 最终 count | 最终 MD5 |
|---|---:|---|
| students | 8 | `431ae7f350902dde0642ddc4982054ed` |
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

Gate 最终仍为 `enabled / blocked / enabled`。真实业务数据、Cash 和 Storage 写入均为 0；测试 fixture、commit test 和 test record ID 均无。

## 8. SQL、RPC 与数据库写入

执行的 SQL 文件均为只读/postdeploy：

- `/private/tmp/school_student_status_phase_b4_wage_baseline_readonly.sql`：最终 `BEGIN READ ONLY ... ROLLBACK` 完整通过；早期两次分别在 resolver auth 和 Gate role 读取处中止，连接关闭自动回滚，未执行 DML。
- `/private/tmp/school_student_status_b2_baseline_readonly.sql`
- `/private/tmp/school_student_status_b2_cash_readonly.sql`
- `sql/current/school_student_status_phase_b1_weekly_reader_postdeploy_20260805.sql`
- `sql/current/school_student_status_phase_b2_legacy_freeze_postdeploy_20260806.sql`
- `sql/current/school_student_status_phase_b3_writer_authority_postdeploy_20260806.sql`
- `sql/current/school_cancelled_actual_writer_hardening_postdeploy_20260806.sql`

浏览器/API 只调用 reader：`school_list_student_month_candidates_v1`、既有 `school_resolve_lesson_student_month_authoritative`；DB 基线调用 Phase A resolver 和 B1 weekly reader。没有调用 `school_generate_teacher_monthly_wage` 或任何写 RPC。

未执行 schema/RPC SQL，DB 持久写入 0，白名单写入 0，真实业务写入 0，Cash DB 写入 0。

## 9. Git、Pages 与修改文件

- 实现提交：`20b15b3d8bc8a89173d67ac85428097924fbcc6c`。
- 已 push `main`；Pages run `31033732847` success，head 精确为 `20b15b3…`。
- 生产为 `v10.5.10`。

实现文件：

- `wage.html`
- `css/app.css`
- `js/api/wage-api.js`
- `js/pages/wage-page.js`
- `js/wage-app.js`
- `js/config.js`
- `scripts/student-status-phase-b4-wage-student-filter-static-test.mjs`

收尾文档：本报告与 `docs/current-status.md`。

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

Phase B4-Wage 已完成。B4 其他候选筛选、删除业务归属个人明细及 B5 事件 writer 权限恢复均未启动；两个事件 writer 继续 owner-only。
