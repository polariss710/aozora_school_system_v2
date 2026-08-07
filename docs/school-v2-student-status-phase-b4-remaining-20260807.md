# School V2 学生月份状态 Phase B4-Remaining 实施报告

日期：2026-08-07（Asia/Tokyo）

## Business-model expansion declaration

- New tables: none
- New columns: none
- New enum/status values: none
- New date/month/attribution concepts: none（沿用 Phase A 已批准的 Tokyo 业务月与自然月区间）
- New identity concepts: none
- New source concepts: none
- New snapshot/version concepts: none
- New writable facts: none
- Changed existing-field semantics: none
- Changed field mutability: none
- Changed writer or reader authority: none
- Changed locking rules: none
- New authoritative sources: none（学生月份状态仍唯一来自 `school_student_status_events` + Phase A resolver）
- Legacy fallbacks or dual-read rules: none
- Dual-write behavior: none
- Historical reinterpretation: none
- Destructive schema changes: none

Approval reference: not required — no business-model expansion。当前任务明确授权 B4-Remaining 候选切换；新增的最小只读 current-month wrapper 仅在 DB 计算 Tokyo 当前月并复用既有 Phase A reader，不引入业务事实、权限、writer、reader precedence 或历史解释。

## 实时基线

- 初始分支/HEAD/origin：`main` / `3089f3a40e10336a77e9ca6e5c072b0a846da823` / 相同，ahead/behind `0/0`。
- 页面版本：`v10.5.16`。
- 初始工作区仅有六份既有受保护 untracked 文件；SHA-256 见最终封口章节。
- 初始 Gate：`enabled / blocked / enabled`。
- 初始学生候选：2026-06 `8/8`，2026-07、2026-08 均为默认 `7`、包含 inactive `8`；2026-06-29～07-05 跨月区间默认 `8`。

## 修改前读取矩阵与设计结论

| 分类 | 入口 | 封口合同 |
| --- | --- | --- |
| F 候选 | Phase A 单月/range resolver、planned/preflight reader、本阶段 current-month wrapper | 周图片用周一至周日 range-any-active；工资规则浏览/新建用 DB Tokyo 当前月 |
| D 业务 reader | `school_v_student_month_summary`，课时、工资、学费、月结、收入、支出 reader | 业务行按自身事实读取，学生状态不得裁剪 |
| L record-ID lookup | tuition receipt、wage、income/expense/settlement/lesson detail、classroom/weekly schedule、Cash income confirmation Edge | 从业务记录先取得 `student_id`，再只读最小学生资料；不经过 active 候选 resolver |
| M 学生管理 | `student-api.js` 与学生 Profile 函数 | 继续显示全部学生，留待 B5 |
| O 诊断/测试 | shadow reader、冻结的 P0C baseline 函数与测试 | 仅诊断/历史验证，不参与候选或业务资格 |
| W writer 资格读取 | B3 planned、工资规则、tuition 等既有 writer | 仍由已验收 writer 在 DB 校验；本阶段未修改 |

运行时页面不存在直接 `school_students` 查询。JS/API/Edge 的剩余直接读取已逐项收敛或确认合法：tuition receipt（L）、wage（L）、income（D）、lesson（D/L）、settlement detail（L）、income detail（L）、lesson detail（L）、settlement（D/L）、expense（D）、student（M）、expense detail（L）、wage-rule（L）以及 Cash income confirmation Edge（L）。生产 catalog 另有一个 D 类 view、61 个直接引用 `school_students` 的函数；其用途均可归入上述 F/D/L/M/O/W，未发现未分类的页面资格旁路或 materialized view。

## 实现

- 页面版本由 `v10.5.16` 前进至 `v10.5.17`。
- `student-status-api.js` 新增共享 current-month 与 range 候选读取；页面模块仍只经 API，未新增直接 `.rpc()` 或 DML。
- 周课表图片按页面周一至周日调用 Phase A range resolver；支持 `week_start`、`student_id`、`include_inactive=1`、selected override 和 URL 恢复。课时/排班/图片内容先按业务事实读取，姓名仅按业务行引用的 ID lookup。
- 工资规则顶部浏览默认使用 DB Tokyo 当前月 active 候选，include inactive 和 selected override 可查看历史规则；“全部学生”始终保留全部规则。新建只提供当前月 active 学生；编辑始终保留原学生，更换学生只提供 active 候选；重新启用仍由 B3 writer 校验。
- 新增只读 helper `school_list_current_student_month_candidates_v1(boolean, uuid)`：DB 以 `statement_timestamp() at time zone 'Asia/Tokyo'` 得出当前月并委托 Phase A reader；`SECURITY DEFINER`、固定 `search_path = pg_catalog, public`，仅 authenticated 可执行。未新增业务事实、fallback、writer 或表权限。
- 未修改工资规则金额、expected version、状态、工资锁、月结、课时、Cash、Gate、历史 `business_entity_id` 或事件 writer。

## SQL、静态测试与发布

- ROLLBACK rehearsal：`school_student_status_phase_b4_remaining_current_month_reader_rollback_test_20260807.sql`，显式回滚、residue `0`。
- 正式执行：`school_student_status_phase_b4_remaining_current_month_reader_deploy_20260807.sql`，只创建/授权/注释只读 helper；未执行业务 DML。
- 部署后：`school_student_status_phase_b4_remaining_current_month_reader_postdeploy_20260807.sql` 在 READ ONLY transaction 中通过并回滚。
- 新增 B4-Remaining 静态测试通过；B1/B2/B3/B4-Wage/B4-Lesson/B4-Finance、BE-UI/BE-blocker/BE-P0、lesson writer P0、取消 writer、tuition lesson read failure、planned aircon 回归均通过；所有修改 JS syntax、`git diff --check`、page-layer RPC/DML 扫描通过。
- 实现提交与 Pages：
  - `9c84e3c64c14ad21f4e9c3bb11131e5210da4806`，run `31157722827` success；
  - `62ce35b40117426aaaf22a9c050eaf0fcc57617b`，run `31158466575` success；
  - `84289c76ed053a58f127828627117259c0809a29`，run `31158538156` success。
- 三个提交均已推送 `origin/main`，生产实际版本为 `v10.5.17`。

## 生产 Chrome 无写验收

### 周课表图片

- 2026-06-29～07-05 跨月周默认候选 `8`，唯一 paused 学生因 6 月仍 active 而正常出现；选择该生后保留 `1` 张图片卡、`2` 条真实课时链接。
- 2026-07-06 起的完整 7 月周默认 `7`；include inactive 后 `8`，标签为“本月暂停”。“全部学生”在 include inactive 前后均为 `3` 张图片卡、`11` 条课时链接，证明状态未裁剪图片或课时。
- selected override 在未勾选 include inactive 时仍恢复 paused 学生与 URL；`week_start/student_id/include_inactive`、切周与重置均正常。

### 工资规则

- 默认当前月候选 `7`，include inactive 后 `8`；全部规则始终为 `20` 条，active `18`，JPY 时薪合计 `78,400`，金额与规则状态不变。
- paused 学生可通过 include inactive 或 selected override 查看 `2` 条历史规则；URL 稳定，重置恢复默认且无残余查询串。
- 新建弹窗仅有 `7` 名 active 学生，paused 不可选；paused 历史规则的编辑弹窗保留原学生、原时薪 `5,200` 和备注，改选名单仅加入另外 `7` 名 active 学生。仅打开/关闭弹窗，未保存。
- paused 工资规则详情正常显示姓名与“当前月学生状态：暂停”；B3 的新建、换学生、重新启用 writer 合同未变。

### 详情与防回退

- 2026-06 工资 paused 学生仍有 `1` 个快照、`10` 条候选课时、`1,200` 分钟；tuition receipt 可显示对应 paused 学生与 `CNY 7,740`；B1 周运营仍显示该生 `2节/4小时、已登记2节、完成4小时`；课时详情姓名正常。
- classroom 生产数据中该 paused 学生的 35 组历史课时均无 venue/delivery-mode，因而不存在可验证的真实 paused classroom 卡片；页面已按业务行 ID lookup 实现，空样本查询、桌面及 390px 布局均正常。
- 页面未出现“业务归属”“个人名义”或 `business_entity_id`；浏览器无 service-role。
- 桌面与 `390×844` 无横向溢出；Console error `0`、warning `0`。
- 验收只执行筛选、查询、URL 恢复、查看详情和打开/关闭弹窗；未点击保存、生成、上传、下载、打印、停止、重新启用或其他写入口。

## 只读生产指纹与权限

部署前后完全一致：

| 对象 | 数量/关键值 | MD5 |
| --- | --- | --- |
| students | 8 | `431ae7f350902dde0642ddc4982054ed` |
| status events | 1 | `eeeb492ac7577ff85eb0926aa0b57301` |
| lessons | 741 | `bf20280701bb0c5306aae05ba6aad5a6` |
| settlements | 18 | `7986db5dd35c0ecfa180a04aef7f4051` |
| income | 55 | `eb40e1ea59767e4299cd23b332f57d2a` |
| tuition bills | 22 | `d079f068c0fa19fc07d4dcd94094fae2` |
| expenses | 47 | `141c76e4cf6148007e182704941a0c4a` |
| wage rules | 20（active 18，JPY 78,400） | `2dc430ca4a58416235f2ba771b91b9f1` |
| wage locks | 95 | `8474b2adcc3ed39059efd7237da90168` |
| wage details | 556 | `0b2976f8005835d66b2db25b0b3c1939` |
| accounts | 3 | `443b3170f50bc23a56834d398069c565` |
| account transactions | 187 | `21694ff060e23289566f0a6e9fe3e449` |
| Storage objects / orphan | 57 / 30 | `c2852a4dbcd13b9cddb1da0b1115b18f` |
| Cash requests | 43 | `f4b1876e981ef75828600e0c7f0dc371` |
| Cash CNY / JPY transactions | 74 / 31 | `070c262ec01008d404b424233d2a6e47` / `95ab7cf8a8d167e9b052d3fc6b64614b` |

- Gate 前后均为 `enabled / blocked / enabled`。
- `school_record_student_status_event_v1` 与 `school_correct_student_status_event_v1` 仍为 postgres owner，PUBLIC/anon/authenticated/service_role 均无 EXECUTE；定义 MD5 分别为 `2ce0885969021516a804d5c887b6af39`、`4ba55f37406f7d2d3a4d0d8e24a7496b`。
- School/Cash/Storage 真实业务写入均为 `0`；未调用任何业务/write RPC，未创建 fixture，未上传对象。School DB 的唯一持久变化为上述只读函数 DDL、最小 ACL 与 comment；Cash DB 与 Storage 未写。

## 受保护文件与最终结论

六份既有 untracked 文件保持原位置、未暂存，前后 SHA-256 一致：

- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`：`272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`：`5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`：`b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`：`5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`：`b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`：`7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

结论：Phase B4-Remaining 已完成；Phase B4-Wage、B4-Lesson、B4-Finance 与 B4-Remaining 全部子阶段均已闭环。B5 未启动，继续等待业务负责人验收与单独授权。
