# School V2 月结 Writer P0 封口与待补课／工资只读调查

日期：2026-08-09（Asia/Tokyo）

范围：Phase 1 生产权限封口、浏览器只读收口与部署；Phase 2 生产只读调查和后续合同设计。
结论边界：本报告没有执行 2026-07/08 月结、工资规则写入或老师工资生成。

## 1. 结论

1. 五个学生月结核心 writer 已全部封口。所有生产签名均为 owner `postgres` 直接执行；`PUBLIC`、`anon`、`authenticated`、`service_role` 均无直接 `EXECUTE`：
   - `school_lock_student_monthly_settlement(uuid,text,text)`
   - `school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)`
   - `school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)`
   - `school_unlock_student_monthly_settlement(uuid,text)`
   - `school_relock_student_monthly_settlement(uuid,text)`
2. 浏览器运行时中五个核心 writer 的 RPC 字符串为 0；月结列表和详情没有 unlock/relock 按钮、handler 或必然返回 permission denied 的死入口。生产列表和详情仍为 DB 权威只读，Console error/warning 为 0。
3. 正式本机 `save-draft/lock` 继续可用：只允许 `service_role` 调用既有 local wrapper，wrapper 的 manifest、lesson manifest、expected facts/version、active revision、工资链、确认文本、幂等和事务锁合同均未改、未放宽。unlock/relock 没有运营 wrapper。
4. 新旧待补课模型在收费、学生归属月、待补余额、可计 actual minutes、老师工资和现行月结默认财务结果上业务等价；证据形态不等价。新模型有一条明确的 `cancelled actual / actual_minutes=0 / fee=0 / no wage`，旧模型没有 actual UUID。
5. 新模型不是当前唯一前向合同。当前 authenticated “新增预定课时” writer 仍允许直接创建 `pending_makeup` planned 而不创建 cancelled actual；浏览器批量导入 API 字符串仍在，但其生产 RPC ACL 已全部拒绝。推荐方案 B：前向只允许取消 writer 生成 planned＋cancelled actual，同时 reader/page 兼容旧事实并标记“历史待补课记录”；在实施前，页面可先采用方案 A 的纯展示识别原则。不得伪造历史 actual。
6. 陈加恩 `31d9c783-4950-4197-9b58-4f5dddc8b0e2` 是 2026-07-20 EJU 文综 2 小时 planned，不是数学；2026-08-09 经当前取消 writer 生成 cancelled actual `c7a71952-d00b-4c7d-ac50-28aac2786f4d`。7 月 27 日数学 planned `b42b711b-747f-4c13-98a9-f86b38a70f69` 仍是旧模型。两节都是真实未上课程，不应改成普通已上课。
7. 历史月结／工资兼容推荐单一 effective-state resolver：
   - 张倬闻直接复用现有 `historically_consumed_immutable`，工资 preflight 不应只看物理 `locked`。
   - 陈红卓、陈加恩、袁振轩以及审计一致性需要的李天伦，只能在业务负责人另行逐项批准后建立不可变“历史零结转完成证据”，并由 resolver 读取；不得补写普通 settlement。
   - 彭宇晗的 2026-05 personal settlement 与青空进学塾 makeup actual 之间没有 migration item 或 legacy actual evidence，当前必须独立阻断；不得做通用跨归属 fallback。
8. 2026-07 工资仍不可生成：56 条候选、8 名老师；当前 writer 物理规则看到 40 条课时／5 个学生月结组未完成，另有 30 条课时缺 10 个工资规则组合。工资锁、工资明细、坏 actual、重复启用规则均为 0。
9. 2026-08 学生月结行数仍为 0，必须保持未结算、未修改。

## 2. 实时基线与 Phase 1 部署

### 2.1 Git、生产与 Gate

| 项目 | 初始值 | Phase 1 完成值 |
|---|---|---|
| 分支 | `main` | `main` |
| HEAD | `6e3e88872e59bdfb0778dcd926c56e8bb6dd89d8` | `1d84f38abebfea74511d2187d9b1a58fd8ab0c1c` |
| `origin/main` | `6e3e88872e59bdfb0778dcd926c56e8bb6dd89d8` | `1d84f38abebfea74511d2187d9b1a58fd8ab0c1c` |
| ahead/behind | `0/0` | `0/0` |
| 页面版本 | `v10.5.26` | `v10.5.27` |
| 页面缓存链 | 旧版本 | `settlement-writer-p0-closure-20260809-1` |
| 最近成功 Pages | run `31255599559` | run `31298123785`，commit `1d84f38` |
| Gate | `enabled / blocked / enabled` | `enabled / blocked / enabled` |

Gate 顺序为 `student_tuition_preview / student_tuition_generate / student_tuition_cash_submit`。未 reset、rebase、checkout 或回退合法提交。

### 2.2 实现

- 新增：
  - `sql/current/school_student_settlement_writer_p0_permission_closure_20260809.sql`
  - `sql/current/school_student_settlement_writer_p0_permission_closure_rollback_tests_20260809.sql`
  - `sql/current/school_student_settlement_writer_p0_permission_closure_postdeploy_20260809.sql`
- 浏览器移除五个核心 writer API export/RPC 字符串及 unlock/relock UI、handler、dialog；列表和详情保留只读 reader。
- direct core lock 在月结 mutation scope lock 后调用共享权威 `school_assert_tuition_settlement_month_mutable(student,month)`；owner 内部 direct lock 也不能绕过 active successor tuition revision。
- 两个 local wrapper 定义和 ACL 未改：save-draft/lock 仍为 `service_role` only；五个核心 writer 为 owner-only。
- `SECURITY DEFINER` 保持 `search_path=pg_catalog, public`，没有调用者可控动态 SQL；表级客户端 DML 没有扩大。
- `js/legacy-core.js` 未修改。

### 2.3 验证与持久写入边界

- ROLLBACK rehearsal：第一轮因负向 wrapper 测试遗留 JWT claims 而整事务失败、无提交；清空 claims 后第二轮通过。
- owner direct core lock 与 local wrapper 在 active successor revision 下均返回 `P0001 / TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE`，无半写入。
- synthetic service-role wrapper 矩阵通过：确认文本、stale facts/manifest、金额、save/lock、stale duplicate、idempotent duplicate；全部 ROLLBACK，residue 0。
- 五个 writer 全签名 ACL、anon/authenticated/service-role 直接拒绝、角色矩阵、表 DML、page direct RPC/DML、浏览器 service-role、静态引用、postdeploy 均通过。
- 正式执行 SQL：
  - `school_student_settlement_writer_p0_permission_closure_20260809.sql`
  - `school_student_settlement_writer_p0_permission_closure_postdeploy_20260809.sql`
- 正式 DB 持久写入仅为核心函数定义、ACL、comment；业务行写入 0。ROLLBACK SQL 内调用仅作用于 synthetic fixture。
- 实现提交并推送：`1d84f38abebfea74511d2187d9b1a58fd8ab0c1c`（`security: close settlement core writers`）。

## 3. 2026-07 七名学生月结事实

DB 权威 preview 和 effective-state reader 的实时结果：

| 学生 | student UUID | 2026-07 settlement UUID | 物理／effective 状态 | planned / actual | 金额 JPY / CNY | 已收／结转／调整 | 工资前置 |
|---|---|---|---|---:|---|---|---|
| 陈红卓 | `eceb2c59-9689-4ec8-9d3f-799b90bfdb27` | 尚未生成 | realtime preview | 24h / 19h | planned `204000 / 8772.00`; actual `161500 / 6944.50` | 上月0；已收`204000 JPY / 8772.00 CNY等值`；系统差额0；draft/adjustment/carry均0 | 当前阻断10条/1140分钟；普通 lock 会被8月active revision保护阻断 |
| 陈加恩 | `881dd60c-b92b-44ae-98e1-98448567a8d2` | 尚未生成 | realtime preview | 24h / 20h | planned `216000 / 9374.40`; actual `180000 / 7812.00` | 上月0；已收`216000 JPY / 9374.40 CNY等值`；系统差额0；draft/adjustment/carry均0 | 当前阻断10条/1200分钟；普通 lock 会被8月active revision保护阻断 |
| 李天伦 | `a7b163a0-201e-4867-9b94-372343356a80` | 尚未生成 | realtime preview | 20h / 0h | planned `260000 / 13000.00`; actual `0 / 0` | 上月0；已收`260000 JPY / 13000.00 CNY等值`；系统差额0；draft/adjustment/carry均0 | 7月工资候选为0，不是当前工资阻断；审计完成证据仍缺 |
| 袁振轩 | `4c6f1473-7d44-467d-a70b-30f02e7cf8cd` | 尚未生成 | realtime preview | 3h / 3h | planned/actual `27000 / 1120.50` | 上月0；已收`27000 JPY / 1120.50 CNY等值`；系统差额0；无draft/adjustment/carry | 当前阻断1条/180分钟；普通 lock 会被8月active revision保护阻断 |
| 彭宇晗 | `eb705aad-de4d-45e6-a391-42dcdd89aeda` | `6ec3b815-5540-44bd-88ee-9e30a5284770` | locked / `historically_consumed_immutable`；updated `2026-08-03 14:40:17.227562+00` | 12h / 10.25h | planned `102000 / 4284.00`; actual `87125 / 3659.25` | snapshot system diff/carry `-624.75`，adjustment 0；已被revision `f7bbd000…`、bill `a5cac133…`消费 | 7月月结本身完成且不可变；但工资课时 `145a…` 权威学生月为5月且BE不匹配，仍独立阻断 |
| 孙陈锋 | `b17abc58-2f64-4bad-bf20-c9643ead60bc` | `5e0a23ff-0e1e-48c6-9866-5fc335b3e42d` | locked / `historically_consumed_immutable`；updated `2026-07-31 16:20:39.414529+00` | 36h / 25h | planned `306000 / 12852.00`; actual `212500 / 8925.00` | 上月0；已收`306000 JPY / 12852.00 CNY等值`；snapshot system diff/adjustment/carry 0 | 学生月结前置已完成；不应解锁或重建 |
| 张倬闻 | `7aef8061-7037-4881-a847-a2cdb031c0f4` | `b699209d-2f61-4cfa-959b-45686e2fe19b` | unlocked / `historically_consumed_immutable`；updated `2026-08-02 07:22:46.109515+00` | 52h / 39.25h | planned `520000 / 22360.00`; actual `392500 / 16877.50` | 冻结carry `107.50` 已被identity `960…0009`、revision `7d319b0d…`、bill `013a7766…`消费；现有active draft为manual `-107.50`，不是可继续写入的权威历史结果 | 业务上已完成且不可变；当前工资 writer 因只看物理locked而错误阻断18条/2235分钟 |

结论：截图的四条“未锁定/预览”和三条“历史消费只读”分类由 DB 事实确认。7名同月没有重复权威 settlement；2026-08 settlement 为0。已消费记录必须保持只读，不解锁、不重建、不作废下游账单、收入或 Cash。

四名无普通 settlement 的学生已存在 2026-08 active revision＋received income＋approved Cash：

| 学生 | active revision | bill | income | Cash request |
|---|---|---|---|---|
| 陈红卓 | `96000000-0000-4000-8000-202608031014` | `51f746c5-cede-4609-b845-06ba10d17de5` | `895a7be3-7a38-4744-94f7-e2ac7fdb7cef` | `dfe3daa5-b81f-4d8d-8e49-564b8fccf5db` approved |
| 陈加恩 | `96000000-0000-4000-8000-202608031010` | `1b546782-1b39-4c73-a85d-27ab1e5086ad` | `cdf3da68-e578-4f1b-b759-2fff394e1906` | `2d414d6d-96de-40f7-b5fb-8b5c6c870b7c` approved |
| 李天伦 | `f7150ce5-fb77-4b7f-99f8-207bfbbced91` rev3 | `66a1f276-2756-466f-b709-b8ca29063fd9` | `efd670bc-8dba-4926-82c4-2d194281a609` | `cd3c277a-801e-4743-9345-1e07b2b31ccf` approved |
| 袁振轩 | `96000000-0000-4000-8000-202608031008` | `13bc7bc1-4f93-4b7c-b447-a8ec595953d1` | `54b281ee-78ce-47ab-8fd2-f17791230698` | `cfa29d05-cd16-493e-ad39-9b86acf63735` approved |

因此，不能再用普通 July settlement lock 去“补齐”这四条；Phase 1 新增的 active successor revision guard 会正确拒绝。

## 4. 待补课逐条事实

### 4.1 来源与余额

| 学生／来源 | planned 事实 | actual 事实 | remaining | writer／审计 |
|---|---|---|---:|---|
| 陈红卓 | `4dd90c49-e9ae-4dec-a447-ea3c75259fea`; pending_makeup; 2026-07-20; 2h; EJU数学; 吴峰; JPY `8500/h`, `17000`; student/billing month `2026-07` | 无 | 2h | batch `a5343c4c…`; created `2026-07-08 06:53:08.639382+00`; canonicalized updated `2026-08-01 14:02:23.647108+00`; approved legacy planned evidence |
| 李天伦（另外2h） | `505fff69-8f6f-40bb-8cd8-a1d571ab5d7a`; pending_makeup; 2026-06-29; 2h; EJU日语; 赵天歌; JPY `13000/h`, `26000`; month `2026-06` | 无 | 2h | import `lesson_import_20260524170743533_tzqpua` / `小李六月课时.xlsx`; created 2026-05-24; canonicalized 2026-08-01; approved legacy evidence |
| 李天伦（已知20h） | `8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9`; pending_makeup; 2026-07-06; 20h; 面试; 吴峰; JPY `13000/h`, `260000`; month `2026-07` | 无 | 20h | created 2026-07-06; canonicalized 2026-08-01; approved legacy evidence |
| 陈加恩 7/20 | `31d9c783-4950-4197-9b58-4f5dddc8b0e2`; pending_makeup; EJU文综; 高若天; 2h; JPY `9000/h`, `18000`; month `2026-07` | `c7a71952-d00b-4c7d-ac50-28aac2786f4d`; cancelled; 2026-07-20 16:00–18:00; duration 2h; `actual_minutes=0`; fee JPY0; teacher wage month `2026-07` | 2h | planned batch `60d8456e…`, created 2026-07-01；当前取消 writer 同事务于 `2026-08-09 05:25:42.908488+00` 更新 planned 并创建 actual |
| 陈加恩 7/27 | `b42b711b-747f-4c13-98a9-f86b38a70f69`; pending_makeup; EJU数学; 丛琪润; 2h; JPY `9000/h`, `18000`; month `2026-07` | 无 | 2h | batch `60d8456e…`; created `2026-07-01 15:47:04.38512+00`; canonicalized updated `2026-08-01 14:02:23.647108+00`; approved legacy evidence |

李天伦页面 22 小时由 `505fff69…` 的 2 小时和 `8b9ea410…` 的 20 小时精确组成。另有未来 voided pending 行，但 open-credit reader 已排除，不计入22小时。

### 4.2 下游引用

| planned | tuition / revision / income / Cash | settlement / claim / wage |
|---|---|---|
| `4dd90c49…` | relation `3debdbf0…`; bill `7472f73f…`; active revision `960…1007`; income `3a5542c5…` received；Cash approved | 无variance claim、工资锁/明细 |
| `505fff69…` | 无直接 bill relation；2026-06 locked settlement `5527d3a1…` 存在，但不能据此伪造单课relation | 无claim、工资引用 |
| `8b9ea410…` | relation `de834352…`; bill `07a02092…`; active revision `960…1004`; income `91756564…` received；Cash approved | 无claim、工资引用 |
| `31d9c783…` | active relation `1a258ead…`→bill `2608806a…`→revision `960…1003`→income `4a63f0ca…` received/Cash approved；另有历史 cancelled bill `4109a4ec…` 与 cancelled income `474f0fd2…` | 无variance claim、工资引用；cancelled actual不进工资 |
| `b42b711b…` | active relation `b2d22433…`，其余链与 `31d9…` 相同；另有历史 cancelled relation `3595533a…` | 无claim、工资引用 |

五条来源均不存在重复 completion、重复可计 actual、overage、孤儿 relation、工资锁或工资明细。`31d9…` 唯一 linked actual 是 cancelled；其余四条没有 linked actual。

业务负责人已确认：陈红卓2h、李天伦22h、陈加恩两节各2h均继续保留为补课义务，不退款、不转财务抵扣、不减少待补余额。

## 5. 新旧模型

### 5.1 writer 与时期

- 新模型 writer：`school_create_cancelled_actual_lesson_from_planned(...)`。最初提交 `373810793525c62b5aa81c28095505eb3d149576`（2026-06-07），当前恢复并加固版本来自 `27410ed776e181738712e374967f636d40495ecb`（2026-08-06）。authenticated 仅 active admin/operator 可用，anon/service-role拒绝。
- 旧模型事实可由 2026-06-08 上线的批量导入 writer（提交 `cb579d7980d77f31715a7dacd54619390266a55a`）及 planned create status 直接产生。当前批量导入 RPC 已 owner-only，但 authenticated `school_create_planned_lesson_record_with_venue(...,integer)` 和页面新增表单仍接受 `pending_makeup`，只落 planned，不创建 cancelled actual。
- 因此，“标记取消并转待补课”操作的唯一正式路径是新 writer；但整个系统的前向数据合同仍允许旧证据形态，尚未唯一化。

### 5.2 结果对比

| 结果 | 旧模型 | 新模型 | 是否业务等价 |
|---|---|---|---|
| planned收费／学费账单 | pending planned继续按已冻结relation收费 | 相同 | 是 |
| 学生结算月 | planned权威student month | planned权威student month | 是 |
| 待补余额 | planned duration减makeup consumption | 相同；cancelled actual不消费credit | 是 |
| actual minutes | 无actual，运营可计分钟为0 | cancelled actual明确0 | 结果是，证据否 |
| 老师工资 | 无候选actual | cancelled不进入completed/makeup_completed候选 | 是 |
| settlement preview | pending source按同一planned读取 | 同一planned；cancelled actual排除 | 是 |
| claim及补课完成 | 后续makeup actual消费planned | 相同 | 是 |
| 审计/页面 | 无actual UUID，只能显示历史待补课 | 可展开取消证据 | 否 |

`SETTLEMENT_LESSON_SOURCE_UNRESOLVED` 不是旧模型缺少 cancelled actual 引起。生产函数明确把 `pending_makeup` 排除在 unresolved guard 外；该码针对没有有效actual且planned状态也不是 pending_makeup/completed/cancelled 等已解释状态的来源。旧模型不是金额或义务异常，只是缺少显式取消证据。

### 5.3 页面方案

- A 纯展示统一：安全、无需改历史数据；reader同时识别两种模型，统一显示“待补课”，旧记录不显示actual UUID。
- B 前向统一＋历史标识：推荐。先采用A的reader原则，再独立授权收窄 planned create/import，使取消只能走新writer；旧行显示“历史待补课记录”。
- C 历史补证据：不推荐。新增cancelled actual会改变审计、幂等、actual集合及潜在settlement/wage reader输入，且部分来源已有账单/收入/Cash消费；没有真实业务必要性。

## 6. 历史月结／工资兼容设计（未实施）

### 6.1 推荐权威边界

建议新增且只新增一个不可变证据模型（具体对象属于业务模型扩展，下一轮必须逐项批准）：

1. `school_historical_student_settlement_completion_evidence`
   - 唯一键：`student_id + year_month + business_entity_id`。
   - 冻结：完成类型、`carryover_cny=0`、lesson manifest、active successor revision/bill/income/Cash request IDs、审批文本、manifest hash、created_at/by。
   - 不表达普通 settlement，不可更新/删除，不改变待补课credit、lesson、bill、income或Cash。
2. owner-only core writer；如需运营，只通过新的 local active-admin/service-role wrapper，要求 exact student/month/entity allowlist、expected manifests、active revision、received income、approved Cash、确认文本、幂等键和事务锁。页面无writer。
3. 单一 reader/resolver：优先验证普通 locked settlement；其次读取现有 `historically_consumed_immutable`；最后读取上述精确历史完成证据。不得按NULL/跨归属/姓名做fallback。
4. 工资 preflight 使用该resolver，不再自行 `LEFT JOIN ... settlement_status='locked'`。返回稳定分类和证据 UUID；工资 writer仍保留学生月结前置规则。

### 6.2 对象适用性

- 陈红卓、陈加恩、袁振轩：8月active revision、received income、approved Cash和previous carry0已构成可验证输入；在精确批准后可建立历史零结转完成证据。补课credit保持不变。
- 李天伦：同样可建立审计完成证据；但7月工资候选为0，所以它不是解除本次工资生成的必要阻断。
- 张倬闻：无需新证据；现有 effective resolver 已返回 `TUITION_CONSUMED_SETTLEMENT_IMMUTABLE`。工资 preflight 只需消费该结果。不得解锁、重建、作废账单或Cash链。
- 彭宇晗：工资候选 actual `145a8219-0fcf-4e0b-8230-c6a092668836` 的student month为2026-05、BE为青空进学塾；来源planned `b38ec53e-877d-4a79-877e-fc4cca88133c`也是青空进学塾，但唯一2026-05 settlement `41e018bd-bbf6-4673-83d9-56b8c71c49c4`属于个人名义。两UUID在 `school_business_entity_migration_items` 为0，`school_legacy_actual_settlement_evidence`也为0。当前不能兼容；必须保留独立阻断，等待精确不可变迁移证据的业务授权。

直接补写普通 settlement、取消工资对学生月结依赖、或通用跨归属fallback均不推荐。

## 7. 2026-07 工资只读 preflight

### 7.1 候选老师

| 老师 | UUID | 课时数 | 分钟 |
|---|---|---:|---:|
| 丛琪润 | `ba4210e8-95ef-4f8c-9974-8825923912b7` | 3 | 360 |
| 吴峰 | `bbc3d827-ba8b-4ded-a5ac-cafca88f26bd` | 14 | 1590 |
| 李雯coco | `1ed3ef4e-4168-425d-a264-0fa3747e7448` | 3 | 420 |
| 王亚楠 | `f3b8735b-1966-4dae-ac4e-846cbedc54e6` | 7 | 840 |
| 王黎曦 | `c92ffb8f-c2af-48cd-99b1-2a2a75d70384` | 4 | 480 |
| 田宇辰 | `edaf30da-1315-4455-99d1-ead1b7147662` | 5 | 600 |
| 赵天歌 | `ea58874b-3656-4b14-8977-dc8bf9423997` | 12 | 1410 |
| 高若天 | `78119d7d-624b-45ec-9f22-d24eef22553f` | 8 | 960 |
| 合计 | 8名 | 56 | 6660 |

当前物理月结阻断：

| 学生 | 权威月／BE | 候选 | 具体阻断 |
|---|---|---:|---|
| 彭宇晗 | 2026-05／青空进学塾 | 1条/30分钟：`145a8219-0fcf-4e0b-8230-c6a092668836` | 只有个人名义May locked settlement，且无迁移证据 |
| 张倬闻 | 2026-07／青空进学塾 | 18条/2235分钟 | 物理unlocked；effective已历史消费不可变，writer未读取resolver |
| 袁振轩 | 2026-07／青空进学塾 | 1条/180分钟：`57fc877b-c87f-464e-ad2e-c7caa5585d68` | 无普通settlement；需历史零结转证据 |
| 陈加恩 | 2026-07／青空进学塾 | 10条/1200分钟 | 无普通settlement；需历史零结转证据 |
| 陈红卓 | 2026-07／青空进学塾 | 10条/1140分钟 | 无普通settlement；需历史零结转证据 |

合计40条/4785分钟。当前工资函数没有稳定错误码，仅返回中文异常；兼容resolver应新增稳定分类，但本轮未实施。

其他独立 preflight：existing locked wage group 0、existing wage detail 0、坏actual 0、重复启用规则0；缺工资规则30条／10组合。因此，即使完成历史月结兼容，也不能立即生成工资。

## 8. 10 个缺失工资规则组合

所有组合内部BE均为青空进学塾 `2cf7b72f-6e3c-4d09-80f7-7c58593cd466`。10项都没有exact inactive/history rule，也没有历史工资明细或exact `no_wage` 证据；下列可比值只供负责人判断，不代表建议时薪。

| # | 老师 / 学生 / 科目 | 候选课时 UUID | 数量/分钟 | 可比启用规则 |
|---:|---|---|---:|---|
| 1 | 吴峰 `bbc3…` / 孙陈锋 `b17a…` / EJU数学 `20ef…` | `1622d82e…`, `50ec3900…`, `696e3bae…` | 3/360 | 同老师同科目：李天伦、彭宇晗为`no_wage JPY0`；陈红卓为`jpy_hourly JPY0`。不得由此推断本组合 |
| 2 | 吴峰 / 张倬闻 `7aef…` / EJU数学 | `024be382…`, `5af1bd4f…`, `c2160cd9…`, `e9735da2…` | 4/480 | 同上 |
| 3 | 吴峰 / 彭宇晗 `eb70…` / EJU日语 `a7f9…` | `145a8219-0fcf-4e0b-8230-c6a092668836` | 1/30 | 同老师同科目李天伦为`no_wage`；同老师同学生EJU数学为`no_wage`；本组合无exact证据 |
| 4 | 李雯coco `1ed3…` / 张倬闻 / TOEFL `e087…` | `3025adcf…`, `8d8e648d…`, `ca45daa0…` | 3/420 | 同老师同科目袁振轩 `JPY5500/h` |
| 5 | 王黎曦 `c92f…` / 孙陈锋 / EJU化学 `7cde…` | `802429f9…`, `a8baa6cd…` | 2/240 | 同老师同科目彭宇晗 `JPY4000/h` |
| 6 | 王黎曦 / 张倬闻 / EJU化学 | `99359354…`, `aabd803c…` | 2/240 | 同上 |
| 7 | 田宇辰 `edaf…` / 孙陈锋 / EJU物理 `1425…` | `a533a79e…`, `f9897917…` | 2/240 | 无相近规则 |
| 8 | 田宇辰 / 张倬闻 / EJU物理 | `36c4826f…`, `5ebd389c…`, `66abbc60…` | 3/360 | 无相近规则 |
| 9 | 赵天歌 `ea58…` / 孙陈锋 / EJU日语 | `178f24ae…`, `29e82377…`, `8d7aa716…`, `aa319215…` | 4/420 | 同老师同科目彭宇晗 `JPY5500/h`、李天伦 `JPY6500/h` |
| 10 | 赵天歌 / 张倬闻 / EJU日语 | `2faa03f2…`, `4a1b74c6…`, `a1977f69…`, `bcc521dc…`, `bfd9beeb…`, `ef5ba751…` | 6/735 | 同上 |

业务负责人必须逐项确认 `jpy_hourly / cny_hourly / no_wage` 及对应权威金额；本报告不猜测、不创建或启用规则。

## 9. 下一轮最小生产执行清单

1. 业务负责人逐项批准历史完成证据的准确对象/语义/ACL/不可变合同，并明确陈红卓、陈加恩、袁振轩（及审计一致性是否包含李天伦）的 `carry=0` 证据。
2. 实现不可变证据 owner core＋service-role local wrapper＋effective-state resolver；ROLLBACK、角色矩阵、manifest/并发/幂等、真实指纹和residue验证后部署。不得补写普通 settlement。
3. 让工资 preflight/writer只读取同一个effective resolver；张倬闻应由既有历史消费事实通过。
4. 对彭宇晗 `145a…` 单独取得精确迁移证据授权；在证据存在前保持阻断。禁止通用跨BE fallback。
5. 负责人逐项确认本报告10个工资规则组合；另行授权后走正式工资规则writer创建/启用，不直接DML。
6. 再跑只读工资preflight；只有月结effective阻断0、缺规则0、坏actual0、重复规则0、工资锁/明细冲突0时，才可在新的明确授权轮次生成2026-07工资。
7. 2026-08继续保持月结0，不结算、不修改。

## 10. 数据不变与现场保护

- Phase 2 SELECT/readers/preflight：SQL写入0、写RPC 0、School/Cash/Storage业务写入0、Gate变化0。
- Phase 1 持久DB变化仅函数定义、ACL、comment；真实settlement、draft、bill、income、Cash、wage、lesson行指纹前后一致。
- 主要指纹：lessons `02b9109c53d1a3d320d4c9f8899fdb40`；settlements `481ffa7ed5173da852f0f28ce66c2e9b`；bills `e50673ac998ee2d84573a076a64d3d42`；bill-lessons `e3e2e0044c17864bc66c7e2861176c8b`；revisions `ffdc498a6e256aa29064f021f22e4b00`；income `c55f82c7d62dbe92d0b49714a911a234`；wage locks `7bbe108d3ac73d4f21530793bf141bc6`；wage details `6204dc666b3b8e0f64fac901ecf0686a`；variance claims `fbce39067e6d98167cdb474eb9635c92`。
- Cash School-filtered指纹：requests `f4b1876e981ef75828600e0c7f0dc371`；CNY `a9ac168e157a00789bd5bff1de469f50`；JPY `654485db35df0657c0bf7121d464baa3`。Storage buckets `9b1be72d5b5fb2ac22b7f7b49d9f8f90`，objects `62fac5521274c58c6f6982a0c690c134`。
- 六份受保护untracked文件保持未修改、未移动、未删除、未暂存、未提交；SHA-256：
  - `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`
  - `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`
  - `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`
  - `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`
  - `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`
  - `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`
