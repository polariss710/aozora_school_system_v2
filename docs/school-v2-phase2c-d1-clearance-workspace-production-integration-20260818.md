# School V2 Phase 2C-D1 课时余额与清偿页面生产接入报告

日期：2026-08-18
生产版本：`v10.5.48`
实现提交：`1ba04d77009391794aa062e3050d1dc4da41946c`
Preview失效补丁：`dbd37b9d961c810b43bd9ba5791d60e580039c54`
Pages：`32041499610`、`32042110972`，均success

## 1. 范围与业务模型声明

本阶段只接入现有R1/R2只读合同，不修改数据库对象、schema、业务字段、业务状态、authoritative source、ACL、RLS、trigger、writer或历史事实。

Business-model expansion declaration：

- 新业务表／列／状态／权威事实：none
- 既有字段语义、mutability、reader precedence或locking变化：none
- 新writer或writer权限变化：none
- 历史数据迁移／backfill／repair：none

页面只格式化DB返回的日期、分钟和JPY；不反算余额、金额、锁定、FIFO偏离、same/cross或forward事实。

## 2. 生产只读Gate

修改文件前重新确认：

- HEAD／origin/main：`8677af7fce62436b5a5d3aa6b3c9d9eb23635f99`
- ahead／behind：`0／0`
- 生产版本：`v10.5.47`
- Clearance主／明细：`0／0`
- pending：`21源／2400分钟`
- overage：`4源／135分钟`
- P002：`1200／0／1200分钟`
- cross-month：`16`个唯一actual
- history：`0`
- R2字段机械闭合：`missing_fields=[]`

R1定义MD5：

- Preview V2：`ffeab2952a86c3c40d39cd3a5c806e19`
- Reversal Preview V1：`25c4d8f62418f3cec0bec69cf5fe9324`
- History V2：`0f0068b523ca6c1c142b6ae55b41bc4d`

R2定义MD5：

- Pending V2：`94dcc95f7c64325e77ea5fa326dc5d05`
- Overage V2：`ec54e9c7922c39089028b9ebcf0c340a`
- Package V2：`08f691e9ef9db06da0d8921ce7d8fb9a`
- Cross-month V2：`ea91f56375992bb3c788975ee9787297`
- Dashboard summary：`83c07aea007dea0f7eb0792fd36334dd`

全部函数均为postgres owner、SECURITY DEFINER、固定`search_path=pg_catalog, public`，仅authenticated有EXECUTE；anon/service_role无EXECUTE。所有生产SQL均在`BEGIN TRANSACTION READ ONLY ... ROLLBACK`中执行。

## 3. 页面入口与信息架构

`lesson.html`课时动作区新增独立“课时余额与清偿”入口，打开大型dialog，包含：

1. DB dashboard摘要；
2. draft/applied筛选；
3. 普通待补余额；
4. 可用超额；
5. P002套餐隔离区；
6. 清偿历史；
7. 跨月补课的来源月／履约月双视角；
8. 人工source选择与DB权威Preview。

P002只在套餐区展示，`read_only=true / can_consume=false / can_reserve=false`，没有清偿、补课、消费、reservation或reversal动作。

## 4. 八个只读RPC映射

专用API层`js/api/lesson-clearance-api.js`集中维护且只导出：

1. `school_list_lesson_clearance_pending_balances_v2`
2. `school_list_lesson_clearance_available_overages_v2`
3. `school_list_student_package_credit_lots_v2`
4. `school_list_cross_month_makeup_projection_v2`
5. `school_get_lesson_clearance_dashboard_summary_v1`
6. `school_preview_lesson_clearance_v2`
7. `school_preview_lesson_clearance_reversal_v1`
8. `school_list_lesson_clearance_history_v2`

调用链为`lesson.html → lesson-page.js → lesson-clearance-api.js → Supabase RPC`。page/component无直接`.rpc()`或表级DML；API不包含create/reversal writer名称。

## 5. 状态机与权限

- FIFO只展示DB排名／推荐，不自动选择pending或overage。
- admin/operator可人工选择并读取Preview；read_only只能浏览；inactive、无membership、anon在页面和DB两层fail-closed。
- request identity仅存在内存；关闭dialog即清除。
- 同一输入重复Preview复用identity。
- source、分钟、原因或备注变化时立即清除旧Preview并轮换identity。
- 生产补丁验证：identity `f63245e0-d4a2-47ec-a273-9148ac4c024d` → `b260aae6-c281-41ec-99ad-64806b503ff5`，旧Preview卡片立即为0，新增RPC为0。
- 跨老师／科目由DB `same_teacher/same_subject`驱动确认区。
- locked/forward由DB Preview直接显示；operator的admin forward确认disabled。
- “确认清偿”和“确认Reversal”始终disabled，无事件handler，无writer API导出。

筛选：

- reset只恢复draft控件、toast为“已重置筛选条件”；生产URL、结果、Preview均不变，RPC 0。
- query才apply并调用6个reader。
- applied filters决定行折叠，不依赖历史点击。

## 6. 生产Chrome验收

生产默认读取：

- pending：21源／2400分钟
- overage：4源／135分钟
- P002：1200／0／1200分钟
- history：0
- cross-month：来源视角16行、履约视角16行、唯一actual 16

袁振轩DB Preview：

- pending：`8870f57f-bca5-4114-90db-ee592cca2f45`（FIFO推荐）
- overage：`e58457a1-89c5-441b-9bcb-73ffc6168d8a`
- 60分钟：pending 60→0，overage 60→0
- JPY：-9,000／+9,000／net 0
- same teacher：true
- same subject：true
- pending/overage locked：false
- forward：false
- actor blocker：无
- `reservation_created=false`
- `writer_revalidation_required=true`
- manifest：`acca29fef80e351cb66a0dd0def9972f41b6a2f6db26746287b1937b5f4ba87a`

Network只出现上述6个list/summary reader及Preview V2；create/reversal writer、lesson/makeup/wage/settlement writer、表级DML均为0。Console error/warning为0。

布局：

| viewport | document overflow | dialog overflow | panel overflow | 最终按钮 |
|---:|---:|---:|---:|---|
| 1440 | 0 | 0 | 0 | disabled |
| 1024 | 0 | 0 | 0 | disabled |
| 768 | 0 | 0 | 0 | disabled |
| 390 | 0 | 0 | 0 | disabled |

## 7. 修改文件

- `lesson.html`
- `css/lesson-clearance.css`
- `js/config.js`
- `js/lesson-app.js`
- `js/pages/lesson-page.js`
- `js/api/lesson-clearance-api.js`
- `js/components/lesson-clearance-workspace.js`
- `js/utils/lesson-clearance-state.js`
- `scripts/lesson-filter-layout-static-test.mjs`
- `scripts/school-phase2c-d1-clearance-workspace-static-test-20260818.mjs`
- `scripts/school-phase2c-d1-clearance-workspace-state-test-20260818.mjs`
- `scripts/school-phase2c-d1-clearance-workspace-browser-test-20260818.mjs`

缓存链最终为`phase2c-d1-clearance-workspace-20260817-2`。

## 8. 测试

通过：

- 新增D1静态边界测试
- 新增D1状态机测试
- 新增D1 Chrome mock交互／四档布局测试
- JS语法检查
- Phase 2C-C、R1、R2现有静态合同
- lesson筛选布局回归
- lesson 15分钟网格回归
- `git diff --check`

本地和生产所有测试业务数据为0，测试记录ID：无。

## 9. SQL、RPC与零变化证明

执行SQL文件：

- `sql/current/school_phase2c_c_r1_clearance_read_contract_postdeploy_readonly_20260817.sql`
- `sql/current/school_phase2c_c_r2_clearance_candidate_readers_postdeploy_readonly_20260817.sql`
- `sql/current/school_phase2c_c_r1_clearance_read_contract_production_readonly_acceptance_20260817.sql`
- `sql/current/school_phase2c_c_lesson_clearance_business_fingerprint_readonly_20260817.sql`
- `sql/current/school_phase2c_c_lesson_clearance_cash_readonly_20260817.sql`

没有执行migration、DDL、DML或writer SQL。数据库写入：0。

最终School指纹：

- lessons 772／`9b393f82ac424ac9df30234fbf44617d`
- settlements 18／`481ffa7ed5173da852f0f28ce66c2e9b`
- claims 2／`fbce39067e6d98167cdb474eb9635c92`
- bills 22／`e50673ac998ee2d84573a076a64d3d42`
- bill lessons 330／`e3e2e0044c17864bc66c7e2861176c8b`
- revisions 20／`ffdc498a6e256aa29064f021f22e4b00`
- income 56／`5410e66708a01d7017de7dc331d32674`
- cash linkages 44／`f1c336c43533b9d9b81d88b6fa55feef`
- wage locks 104／`bb9d5e027e482547ba4ca58b3731651a`
- wage details 624／`b68ada9b934d4de511da93104228eb4b`
- package lots 1／`8c2b70b087164e5d03defed8cd237f34`
- Storage 57／`62fac5521274c58c6f6982a0c690c134`
- Gate 3／`b04952a0603194dd5592124bdee2f7d7`

Cash最终指纹：

- CNY transactions 75／`b5d8b7d466532b90531814e5ccf61ad2`
- external requests 44／`1fc51497aedfaecd72a2ee85714284f0`
- Storage 0／`d41d8cd98f00b204e9800998ecf8427e`

Clearance主／明细最终仍为`0／0`；P002仍为`1200／0／1200`；DB对象、ACL、RLS、Auth、Storage、Gate变化0。

## 10. 受保护文件与原型

11份受保护untracked文件的路径和SHA-256与基线一致，未修改、移动、执行、暂存或提交。Phase 2C-A/B文档、脚本和`local/phase2c-b`原型SHA-256不变且未提交。

## 11. Phase 2C-D2建议候选

如后续独立授权首笔受监督试点，最小同价、同学生、同业务归属、同老师／同科目的候选为：

- 袁振轩pending：`8870f57f-bca5-4114-90db-ee592cca2f45`
- 袁振轩overage：`e58457a1-89c5-441b-9bcb-73ffc6168d8a`
- 建议分钟：60

本阶段未执行清偿、reversal、套餐消费或任何业务写入。
