# School V2 学生月度结算线上开放 Phase C-R1 实施报告

日期：2026-08-10（JST）
范围：`can_save`结构资格收敛；不进入Phase D；不执行真实save/lock/unlock/relock。

## 1. 实施结论

Phase C-R1已成功完成并部署。孙陈锋`b17abc58-2f64-4bad-bf20-c9643ead60bc / 2026-06`与张倬闻`7aef8061-7037-4881-a847-a2cdb031c0f4 / 2026-06`现均为`can_save=false`、`can_lock=false`，稳定blocker为`SETTLEMENT_SUCCESSOR_REVISION_BLOCKED`。DB migration和Pages均已上线，生产版本`v10.5.36`。

生产真实online/local save为0、lock为0、unlock/relock为0。ROLLBACK负向测试仅调用online save wrapper 2次，均在业务写入前拒绝并显式ROLLBACK；成功save为0。2026-08仍未结束，本轮未作真实验收，仍需等待自然月结束并重新执行只读白名单preflight。

Business-model expansion declaration：新表`none`、新列`none`、新enum/status`none`、新日期/月/归属/identity/source/snapshot/version/权威事实`none`、既有字段业务语义/可变性/authority/reader precedence变化`none`、历史数据解释/回填`none`。本轮owner-only helper只执行已批准模型的共享资格约束，无扩展审批需求。

## 2. 实时Git

- 初始分支：`main`。
- 初始HEAD／`origin/main`：`1fa67b1aa3701c2b01066293937dbaca804a55cc`，ahead/behind `0/0`。
- 实现提交：
  - `32d1cde` `fix: align online settlement save eligibility`
  - `2333ac4` `test: fix settlement eligibility postdeploy alias`
  - `569bb85` `fix: show authoritative settlement save blockers`
  - `23906a9` `fix: surface filtered settlement blockers`
  - `fcc5362` `fix: simplify successor blocker wording`
- 上述提交均已push到`main`；最终文档提交及最终HEAD见本报告提交后的Git现场。
- 本任务提交前tracked/staged无残留；仅本报告、全scope只读脚本和`current-status`进入最终文档提交。
- 现场9份外来untracked均作为受保护文件保持原状：

| 路径 | SHA-256 |
|---|---|
| `docs/school-v1-decommission-p1-b2a-session-service-worker-readonly-design-20260810.md` | `75474786ac2de0d9881be17b298acf51b1ad68099b6c1f88c7b0d7aac1736a47` |
| `docs/school-v1-decommission-preflight-p1a-online-evidence-20260809.md` | `1047c2d686a43499e21a43055973475aeb0d52a9fd36c0604aa98ce8ebf0c519` |
| `docs/school-v1-decommission-readonly-investigation-20260809.md` | `3e65e0091e68cd419ac13f0e692fcce99f07041abfcdab3b8786e526a800fcaa` |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 3. 根因

旧status只按当前学生业务归属解析physical/effective状态与通用mutability，未沿“当前generation identity业务归属＋后继billing month＋canonical bill的`previous_settlement_month`”识别历史跨归属后继链，也没有把“所有正式模式都无法满足的source facts为空”纳入`can_save`结构资格。因此两个scope虽已有canonical bill/active revision且无任何source fact，仍被标成`can_save=true`。

online writer后续会进入更深的Preview/source校验并拒绝，形成“status允许、writer结构上必然拒绝”的规则漂移。历史canonical bill保留个人名义、当前identity/income位于青空进学塾是既有迁移事实；本轮只读取该链作为不可变证据，未改业务归属、bill、revision、identity或income。

## 4. DB修复

正式migration：`sql/current/school_student_settlement_online_can_save_qualification_20260810.sql`。配套ROLLBACK、postdeploy与全scope脚本分别为：

- `school_student_settlement_online_can_save_qualification_rollback_tests_20260810.sql`
- `school_student_settlement_online_can_save_qualification_postdeploy_20260810.sql`
- `school_student_settlement_online_can_save_qualification_full_scope_readonly_20260810.sql`

单一规则源为owner-only `school_get_student_settlement_online_save_eligibility_core(uuid,text) returns jsonb`。它读取权威student业务归属、effective resolver、physical/evidence唯一性、精确lesson/income source facts、既有mutability assertion、active successor revision/canonical bill、跨归属历史链及工资不可变引用；不写业务行、不计算金额、不增加月份关闭规则。

`school_assert_student_monthly_settlement_online_writable(uuid,text,uuid,text) returns void`改为调用上述helper；online save和lock wrapper继续在Preview及draft写入前调用该assert。`school_get_student_monthly_settlement_online_status_core(uuid,text) returns jsonb`也消费同一helper，保持`student_settlement_online_status_v1`兼容字段并加法返回`source_facts_available`、save/lock blocker code/message。

相关完整签名：

- `school_get_student_monthly_settlement_online_status(uuid,text) returns jsonb`
- `school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid) returns jsonb`
- `school_lock_student_monthly_settlement_online_admin(uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,uuid) returns jsonb`

helper、assert与status core均postgres owner、`SECURITY DEFINER`、固定`search_path=pg_catalog, public`，PUBLIC/anon/authenticated/service_role直接EXECUTE均为false。外层status保持authenticated合法读取；online save/lock wrapper保持service-role-only，核心writer仍owner-only，表级客户端DML未扩大。

blocker优先级为：scope不唯一 → ordinary locked → historically consumed → historical zero-carry →其他非incomplete/physical事实 → 既有mutability → active successor revision → canonical consumption → 跨归属冲突 → wage不可变 → source facts为空。两个回归scope因此返回更强且真实的successor blocker，而非较弱的source-empty。

## 5. 页面修复

`js/api/settlement-api.js`优先解析DB返回的`save_blocker_code/message`；明确筛选学生时，即使普通列表reader因无lesson/income/settlement而没有行，也会通过既有status API补一个只读status-only行，不伪造Preview、金额或actual事实。

`settlement-online-state.js`以DB `can_save`及save blocker决定入口；`settlement-page.js`只做安全错误映射。两个2026-06 scope均无save入口，显示“只读 / 后继学费事实已冻结”，详情提示“该月份已存在后继学费账单或不可变结算事实，不能保存新的月结草稿。”不暴露UUID、SQL或跨归属内部细节。

lock按钮/引用仍为0，unlock/relock入口仍为0；page-layer直接RPC/DML为0，浏览器service-role为0，`js/legacy-core.js`未修改。

## 6. 39-scope实时全scope矩阵

实施前两个已知回归scope为错误`can_save=true`；实施后两者均变为false。实时全事实union得到39个唯一scope（2026-02～2026-11）：`can_save=true` 11、false 28、`can_lock=true` 0、`can_save=true`却有结构blocker的漂移0。

false分组：

- `SETTLEMENT_SCOPE_NOT_UNIQUE` 11：李天伦2026-02/03/04/05/06；厦门吕同学2026-04/05/06；彭宇晗2026-04/05/06。
- `SETTLEMENT_ORDINARY_ALREADY_LOCKED` 6：陈加恩2026-05/06、陈红卓2026-05/06、孙陈锋2026-07、彭宇晗2026-07。
- `SETTLEMENT_HISTORICALLY_CONSUMED` 1：张倬闻2026-07。
- `SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE` 4：陈红卓、陈加恩、李天伦、袁振轩2026-07。
- `SETTLEMENT_SUCCESSOR_REVISION_BLOCKED` 4：孙陈锋/张倬闻/袁振轩2026-06，孙陈锋2026-08。
- `SETTLEMENT_SOURCE_FACTS_EMPTY` 2：李天伦2026-09/10。

全部`can_save=true` scope均为当前/未来月份且只有结构资格，不代表获准生产验收：2026-08张倬闻、彭宇晗、李天伦、袁振轩、陈加恩、陈红卓；2026-09孙陈锋、张倬闻；2026-10张倬闻；2026-11张倬闻、李天伦。未新增“只允许已结束月份”、当前月关闭或未来月禁止规则。

## 7. 测试

- migration rehearsal：以`C_R1_REHEARSAL=1`执行同一migration并显式ROLLBACK，通过。
- 正式migration：仅函数定义、ACL和comment持久化，成功。
- rollback：输出`SETTLEMENT_ONLINE_CAN_SAVE_R1_ROLLBACK_PASS`；两个真实回归scope各1次online save负向调用均写前拒绝，事务ROLLBACK，无fixture residue。
- postdeploy：输出`SETTLEMENT_ONLINE_CAN_SAVE_R1_POSTDEPLOY_PASS`；两scope均effective incomplete/source false/can_save false/can_lock false/successor blocker。
- 39-scope：tracked只读脚本返回39行；11/28、结构漂移0、can_lock 0。
- 权限：owner/security/search_path/ACL矩阵通过；status读权限保持，online wrapper仍service-role-only，核心writer及内部helper不开放。
- JS：4个相关模块`node --check`通过；Phase C unit 7/7；static输出`STUDENT_SETTLEMENT_ONLINE_PHASE_C_STATIC_PASS`；`git diff --check`通过。
- Chrome生产：两个2026-06精确筛选均1行、edit 0、safe blocker正确；2026-07为7行且历史状态不变；陈红卓2026-08仍按既有结构合同显示edit入口但未点击；390×844页面无整体横向溢出；Console error/warning 0。

## 8. 生产零变化

最终School业务数量/整行MD5与基线一致：settlements `18/481ffa7ed5173da852f0f28ce66c2e9b`、adjustment drafts `7/0b162413935ed3a35920d144faffbc52`、source drafts `1/c2a01866c1bfe9edd5eb559d6faf4a67`、historical evidence `4/9cb22ef4ddd83f7a77c8fcd2e3ab3966`、lessons `744/3cd0c2ce1b7baa60c779c257c38e9f50`、income `55/c55f82c7d62dbe92d0b49714a911a234`、bills `22/e50673ac998ee2d84573a076a64d3d42`、revisions `20/ffdc498a6e256aa29064f021f22e4b00`、wage locks `103/ea395407134045e7623e171b02d3d910`、wage details `612/1d45d0ce37696051c233465efaf3de5e`、payment requests `51/6ce63e69edfa19a020013634b686f5ce`、expenses `47/34a7a32319d8e538ef7997e1ba59c9d4`、account transactions `187/00516a76f236d51406c82f37b0e468ee`。

membership `1/332d6f2e305a24e390b058abde88ff68`、Storage buckets `1/9b1be72d5b5fb2ac22b7f7b49d9f8f90`、objects `57/62fac5521274c58c6f6982a0c690c134`。Auth用户数量仍1；全行MD5包含正常会话时间字段，仅作现场值记录，不作为业务不变量；本轮未调用Auth writer，membership/权限事实不变。

Cash不变：requests `43/f4b1876e981ef75828600e0c7f0dc371`、CNY `74/070c262ec01008d404b424233d2a6e47`、JPY `31/95ab7cf8a8d167e9b052d3fc6b64614b`。Gate保持`enabled / blocked / enabled`。真实online/local save、lock、unlock、relock均0；业务DB行写入0，Cash/Auth/Storage writer 0。

两个Edge未部署且不变：save `d643ab21-9306-4031-b5f4-2727e904a48a` ACTIVE/version 1/hash `411ec4de...`；lock `8fab9f4d-96de-43c8-8a15-98cec8096f9b` ACTIVE/version 1/hash `75c72c21...`。

## 9. Pages部署

最终功能Pages run `31325153081`成功，commit `fcc5362d0404aa1f715b0a939e10c9e6cd27348c`；生产版本`v10.5.36`，实际资产`student-settlement-online-phase-c-r1-20260810-3`。生产Chrome Network共记录64个请求，写请求0、service-role header 0、save/lock/unlock/relock/core writer请求0；Console error/warning 0。

## 10. 回滚

页面如需恢复，只能以新的前向提交恢复上一版页面/API/缓存资产并重新部署Pages，不reset/rebase/amend已有合法提交。

DB修复不应通过恢复错误的`can_save=true`回滚：旧状态会再次公开一个writer必然拒绝的入口。若共享guard自身发现缺陷，应以新的前向migration修正或fail-closed，不修改两个历史scope的business entity、bill、revision、identity、income或其他不可变事实。

## 11. 后续决策

- 等待2026-08自然结束；本轮未把当前月任何`can_save=true`当作生产验收授权。
- 月末后重新执行只读白名单preflight，确认稳定、唯一、已结束月份scope。
- 业务负责人再精确授权student/month、source treatment、adjustment mode及确认文本后，方可进行单条真实save验收。
- Phase D仍未开放，本轮停止于Phase C-R1。
- “是否永久禁止当月保存草稿”仍是未决业务规则；当前DB未作该决定，也未添加日期型关闭规则。
