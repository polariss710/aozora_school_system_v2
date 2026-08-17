# School V2 Phase 2C-C-R1：Clearance权威Preview与History只读合同部署报告

日期：2026-08-17
生产页面版本：`v10.5.47`（未修改页面、JS、CSS、版本或缓存）

## 1. 实时基线与范围

- 起始 HEAD / `origin/main`：`e57460cc55f315b85ae5ac242dae0df4b41768a6`，ahead/behind `0/0`。
- clearance主表/明细表：`0/0`；普通待补：`21 source / 2400分钟`；可用overage：`4 source / 135分钟`；P002：`1200/0/1200分钟`。
- lessons实时基线为`772`行/`9b393f82ac424ac9df30234fbf44617d`。上一阶段报告为771行；新增actual创建于本轮首次数据库操作之前（2026-08-17 17:43 JST），属于外部正常业务活动。本轮从772行指纹开始并以前后相等验收。
- 本阶段只新增3个版本化read RPC及其ACL/comment；没有新表、列、状态、业务权威、writer、RLS、页面接入或真实clearance/reversal。

## 2. Business-model expansion declaration

| 项目 | 声明 | 当前任务批准依据 |
|---|---|---|
| 新业务表/列/状态/余额/锁/forward语义 | `none` | 第II、XVI节禁止修改表结构和writer语义 |
| 新只读合同 | 3个versioned read RPC | 第II、IV、VI、VIII、IX节明确批准 |
| 新owner-only helper | `none` | 现有Preview/helper足够 |
| 新写入权限/表ACL/RLS | `none` | 第II、VII、XVI节禁止扩大权限 |
| 历史事实解释 | 仅`snapshot`/`immutable_reference`/`current_derived`/`unavailable`证据标签 | 第IX、X节明确批准NULL和证据状态，禁止伪造快照 |

Gate结论：没有未批准的业务模型扩展。

## 3. 原RPC缺口与持久证据

旧`school_preview_lesson_clearance`只返回source UUID、前后余额、单价/金额、forward和actor role；不返回名称、请求identity、source行指纹、FIFO推荐/偏离、same/cross、细分锁证据或结构化actor blocker。旧history也不返回推荐/偏离、reversal聚合状态或证据等级，且生产不存在reversal Preview。

现有writer与表已经保存/重算：

- create writer的`idempotency_key`、推荐pending、是否偏离、偏离code/note、input manifest、actor、forward事实；
- detail的source UUID、分钟、单价/金额、前后余额、source row MD5/updated_at；
- reversal关联、原事实有效性和active reversal；
- writer执行时重新校验余额、同学生/归属/价格、claim、锁/forward、角色、并发和幂等。

没有持久保存操作时的两个独立source locked布尔，也没有独立的teacher/subject快照。History因此仅在当前source整行MD5等于保存MD5时把teacher/subject比较标为`immutable_reference`；否则返回NULL/`unavailable`。操作时单源locked固定返回NULL/`unavailable`，而`requires_forward_adjustment`和`financial_year_month`继续使用已保存snapshot。Reversal的`entered_settlement_source`在当前schema不能精确证明，同样返回NULL/`unavailable`。没有为补齐显示而擅自加列。

## 4. 新RPC与旧合同

```text
school_preview_lesson_clearance_v2(
  uuid,text,uuid,uuid,integer,date,text,text,text,text
) returns jsonb

school_preview_lesson_clearance_reversal_v1(
  uuid,uuid,date
) returns jsonb

school_list_lesson_clearance_history_v2(uuid) returns jsonb
```

三者owner=`postgres`、`SECURITY DEFINER`、固定`search_path=pg_catalog, public`；仅`authenticated`有EXECUTE，PUBLIC/anon/service_role无EXECUTE。旧Preview、旧history及create/reversal wrapper/core定义MD5、owner和ACL均未修改。

## 5. Request identity与manifest

- 页面未来生成UUID request identity并原样传给Preview；DB原样返回为`request_identity`与`idempotency_key`。
- Preview manifest绑定contract version、identity、类型、两个source UUID、分钟、operation date、偏离/说明输入、source整行MD5和旧权威Preview JSON。
- Preview不reservation、不写行，也不承诺余额不变；返回`writer_revalidation_required=true`。
- 最终writer继续使用同一idempotency key并在事务中重算全部事实；不存在第二套身份。

## 6. Clearance Preview V2完整结构样例

以下是production rehearsal中synthetic locked/cross source样例的完整字段结构；UUID、时间和MD5均来自该回滚事务：

```json
{
  "contract_version": "lesson_clearance_preview_v2",
  "request_identity": "2c100000-0000-4000-8000-00000000f002",
  "idempotency_key": "2c100000-0000-4000-8000-00000000f002",
  "clearance_type": "overtime_offset",
  "requested_minutes": 30,
  "operation_date": "2020-03-10",
  "preview_generated_at": "transaction_timestamp",
  "preview_manifest_sha256": "64-hex",
  "writer_revalidation_required": true,
  "reservation_created": false,
  "pending_source": {
    "planned_id": "2c100000-0000-4000-8000-000000001101",
    "student_id": "2c100000-0000-4000-8000-00000000a001",
    "student_name": "codex-test R1 student",
    "business_entity_id": "2cf7b72f-6e3c-4d09-80f7-7c58593cd466",
    "business_entity_name": "青空进学塾",
    "source_date": "2019-12-16",
    "student_settlement_month": "2019-12",
    "teacher_id": "2c100000-0000-4000-8000-000000007001",
    "teacher_name": "codex-test R1 pending teacher",
    "subject_id": "2c100000-0000-4000-8000-00000000d001",
    "subject_name": "codex-test R1 pending subject",
    "initial_minutes": 120,
    "makeup_consumed_minutes": 0,
    "clearance_net_allocated_minutes": 30,
    "before_remaining_minutes": 90,
    "allocated_minutes": 30,
    "after_remaining_minutes": 60,
    "unit_price_jpy": 1000,
    "amount_jpy": -500,
    "active_claimed": false,
    "source_locked": true,
    "lock_evidence": [{"settlement_id":"2c100000-0000-4000-8000-00000000b001","year_month":"2019-12","settlement_status":"locked"}],
    "updated_at": "transaction_timestamp",
    "row_md5": "32-hex",
    "evidence_status": "current_derived"
  },
  "overtime_source": {
    "actual_id": "2c100000-0000-4000-8000-000000001201",
    "student_id": "2c100000-0000-4000-8000-00000000a001",
    "student_name": "codex-test R1 student",
    "business_entity_id": "2cf7b72f-6e3c-4d09-80f7-7c58593cd466",
    "business_entity_name": "青空进学塾",
    "actual_date": "2020-02-03",
    "student_settlement_month": "2020-02",
    "teacher_wage_month": "2020-02",
    "teacher_id": "2c100000-0000-4000-8000-000000007002",
    "teacher_name": "codex-test R1 overtime teacher",
    "subject_id": "2c100000-0000-4000-8000-00000000d002",
    "subject_name": "codex-test R1 overtime subject",
    "frozen_overtime_minutes": 120,
    "clearance_net_allocated_minutes": 30,
    "before_available_minutes": 90,
    "allocated_minutes": 30,
    "after_available_minutes": 60,
    "unit_price_jpy": 1000,
    "amount_jpy": 500,
    "active_claimed": false,
    "source_locked": false,
    "lock_evidence": [],
    "updated_at": "transaction_timestamp",
    "row_md5": "32-hex",
    "evidence_status": "current_derived"
  },
  "comparison": {
    "same_student": true,
    "same_business_entity": true,
    "same_unit_price": true,
    "same_teacher": false,
    "same_subject": false,
    "cross_teacher": true,
    "cross_subject": true,
    "evidence_status": "current_derived"
  },
  "fifo": {
    "recommended_pending_planned_id": "2c100000-0000-4000-8000-000000001101",
    "recommendation_rank": 1,
    "recommendation_timestamp": "transaction_timestamp",
    "recommendation_timestamp_source": "planned_updated_at_fallback",
    "selected_pending_planned_id": "2c100000-0000-4000-8000-000000001101",
    "is_recommended_target": true,
    "deviation_required": false,
    "deviation_reason_code": null,
    "deviation_reason_note": null,
    "deviation_reason_valid": true,
    "selection_mode": "manual"
  },
  "financial": {
    "pending_amount_jpy": -500,
    "overtime_amount_jpy": 500,
    "net_amount_jpy": 0,
    "requires_forward_adjustment": true,
    "forward_destination_month": "2020-03",
    "forward_destination_basis": "operation_date_month_v1",
    "forward_adjustment_direction": "none",
    "forward_adjustment_amount_jpy": 0,
    "amount_rule_version": "lesson_clearance_v2_same_price_v1"
  },
  "authorization": {
    "actor_role": "admin",
    "requires_admin": true,
    "can_execute_for_current_actor": true,
    "blocker_code": null,
    "blocker_message": null
  },
  "source_versions": {
    "pending_updated_at": "transaction_timestamp",
    "pending_row_md5": "32-hex",
    "overtime_updated_at": "transaction_timestamp",
    "overtime_row_md5": "32-hex"
  },
  "legacy_preview": {
    "contract_version": "lesson_clearance_v2_same_price_v1",
    "clearance_type": "overtime_offset",
    "pending_source_planned_id": "2c100000-0000-4000-8000-000000001101",
    "overtime_source_actual_id": "2c100000-0000-4000-8000-000000001201",
    "allocated_minutes": 30,
    "pending_before_minutes": 90,
    "pending_after_minutes": 60,
    "overtime_before_minutes": 90,
    "overtime_after_minutes": 60,
    "pending_unit_price_jpy": 1000,
    "overtime_unit_price_jpy": 1000,
    "pending_amount_jpy": -500,
    "overtime_amount_jpy": 500,
    "financial_net_amount_jpy": 0,
    "requires_forward_adjustment": true,
    "financial_year_month": "2020-03",
    "forward_adjustment_direction": "none",
    "forward_adjustment_amount_jpy": 0,
    "reader_actor_role": "admin",
    "manifest": {
      "pending_source_year_month": "2019-12",
      "overtime_source_year_month": "2020-02",
      "selection_mode": "manual",
      "ordinary_makeup_duplicated": false,
      "package_source": false
    }
  }
}
```

## 7. Reversal Preview完整结构样例

```json
{
  "contract_version": "lesson_clearance_reversal_preview_v1",
  "request_identity": "2c100000-0000-4000-8000-00000000f003",
  "idempotency_key": "2c100000-0000-4000-8000-00000000f003",
  "preview_generated_at": "transaction_timestamp",
  "reversal_manifest_sha256": "64-hex",
  "writer_revalidation_required": true,
  "reservation_created": false,
  "original_clearance": {
    "clearance_id": "2c100000-0000-4000-8000-00000000c001",
    "clearance_type": "overtime_offset",
    "allocated_minutes": 30,
    "pending_source_planned_id": "2c100000-0000-4000-8000-000000001101",
    "overtime_source_actual_id": "2c100000-0000-4000-8000-000000001201",
    "pending_unit_price_jpy": 1000,
    "overtime_unit_price_jpy": 1000,
    "forward_adjustment_direction": "none",
    "forward_adjustment_amount_jpy": 0,
    "actor_user_id": "2c100000-0000-4000-8000-000000000001",
    "actor_role": "admin",
    "created_at": "transaction_timestamp",
    "input_manifest_sha256": "64-hex"
  },
  "current_state": {
    "is_effective": true,
    "already_reversed": false,
    "reversal_clearance_id": null,
    "pending_before_reversal_minutes": 90,
    "pending_after_reversal_minutes": 120,
    "overtime_before_reversal_minutes": 90,
    "overtime_after_reversal_minutes": 120,
    "pending_active_claimed": false,
    "overtime_active_claimed": false,
    "affects_active_claim": false,
    "entered_settlement_source": null,
    "entered_settlement_source_evidence_status": "unavailable"
  },
  "forward": {
    "involves_locked_history": true,
    "only_forward": true,
    "forward_destination_month": "2020-04",
    "forward_destination_basis": "reversal_operation_date_month_v1",
    "forward_adjustment_direction": "none",
    "forward_adjustment_amount_jpy": 0
  },
  "authorization": {
    "actor_role": "admin",
    "requires_admin": true,
    "can_reverse": true,
    "blocker_code": null,
    "blocker_message": null
  },
  "source_versions": {
    "pending_saved_row_md5": "32-hex",
    "pending_current_row_md5": "32-hex",
    "pending_evidence_status": "immutable_reference",
    "overtime_saved_row_md5": "32-hex",
    "overtime_current_row_md5": "32-hex",
    "overtime_evidence_status": "immutable_reference"
  }
}
```

## 8. History V2完整结构样例

```json
[
  {
    "contract_version": "lesson_clearance_history_v2",
    "clearance_id": "2c100000-0000-4000-8000-00000000c001",
    "clearance_type": "overtime_offset",
    "student_id": "2c100000-0000-4000-8000-00000000a001",
    "student_name": "codex-test R1 student",
    "business_entity_id": "2cf7b72f-6e3c-4d09-80f7-7c58593cd466",
    "business_entity_name": "青空进学塾",
    "operation_date": "2020-02-10",
    "operational_year_month": "2020-02",
    "financial_year_month": "2020-02",
    "pending_source_planned_id": "2c100000-0000-4000-8000-000000001101",
    "overtime_source_actual_id": "2c100000-0000-4000-8000-000000001201",
    "allocated_minutes": 30,
    "balance_effect": "consume",
    "pending_unit_price_jpy": 1000,
    "overtime_unit_price_jpy": 1000,
    "pending_amount_jpy": -500,
    "overtime_amount_jpy": 500,
    "financial_net_amount_jpy": 0,
    "recommended_pending_planned_id": "2c100000-0000-4000-8000-000000001101",
    "selected_pending_planned_id": "2c100000-0000-4000-8000-000000001101",
    "is_recommended_target": true,
    "deviated_from_recommendation": false,
    "deviation_reason_code": null,
    "deviation_reason_note": null,
    "same_teacher": false,
    "cross_teacher": true,
    "same_subject": false,
    "cross_subject": true,
    "source_comparison_evidence_status": "immutable_reference",
    "pending_source_locked_at_operation": null,
    "overtime_source_locked_at_operation": null,
    "source_lock_evidence_status": "unavailable",
    "requires_forward_adjustment": true,
    "forward_destination_month": "2020-02",
    "forward_adjustment_direction": "none",
    "forward_adjustment_amount_jpy": 0,
    "request_identity": "2c100000-0000-4000-8000-00000000f001",
    "idempotency_key": "2c100000-0000-4000-8000-00000000f001",
    "input_manifest_sha256": "64-hex",
    "actor_user_id": "2c100000-0000-4000-8000-000000000001",
    "actor_role": "admin",
    "business_note": "codex-test direct fixture",
    "created_at": "transaction_timestamp",
    "is_effective": true,
    "is_reversed": false,
    "reversal_clearance_id": null,
    "reversal_created_at": null,
    "reversal_actor_user_id": null,
    "reversal_actor_role": null,
    "effective_allocated_minutes": 30,
    "can_reverse": true,
    "reverse_blocker_code": null,
    "evidence_status": {
      "selection": "snapshot",
      "forward": "snapshot",
      "request_identity": "snapshot",
      "pending_source": "immutable_reference",
      "overtime_source": "immutable_reference",
      "source_lock_at_operation": "unavailable"
    }
  }
]
```

## 9. 推荐、偏离、same/cross、锁和forward

- FIFO继续由既有`school_suggest_lesson_clearance_targets_core`权威排序；V2返回推荐UUID、排序时间/来源、选择UUID、是否推荐及偏离原因合法性，不自动选择。
- teacher/subject比较由DB完成；Preview为`current_derived`，History只有source整行指纹完全一致时为`immutable_reference`。
- Preview的source month先走既有权威month resolver，再按与writer一致的locked settlement判断返回`source_locked`与settlement证据；`requires_forward_adjustment`和destination直接复用旧权威Preview。
- operator只对普通unlocked overtime offset得到可执行Preview；locked/forward或其他类型要求admin。read_only可看数据但`can_execute=false`。

## 10. Reversal eligibility

Reversal Preview不调用writer。它读取原clearance/detail、active reversal、当前余额/claim、保存的forward和source指纹，计算冲正后余额及只forward目标月；仅admin可得到`can_reverse=true`。不存在的clearance稳定拒绝`LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID`，已reversed稳定返回`LESSON_CLEARANCE_ALREADY_REVERSED`。

## 11. Phase 2C-B字段映射

机器可检查映射位于`docs/school-v2-phase2c-c-r1-clearance-read-contract-field-map-20260817.json`，逐项记录mock字段、新Preview/History/Reversal字段、authority、evidence status及NULL语义。Phase 2C-B生产入口和本地原型均未修改。

## 12. 本地测试

一次性PostgreSQL 17.10，Unix socket only：

- R1主合同：14/14；request identity/manifest、DB余额金额、same/cross、FIFO/偏离、锁/forward、read_only、reversal/history/P002、Preview/reversal零写入全部通过。
- R1角色矩阵：admin、operator、read_only、inactive、无membership、anon、authenticated、service_role、owner ACL合同通过。
- 既有Phase 2C-C：主合同30/30、扩展14/14；P002隔离12/12。
- exact rollback移除3个R1函数（count=0），旧对象保留；migration可再次成功应用。
- 所有本地业务fixture最终ROLLBACK；没有生产连接或真实writer调用。

## 13. Production ROLLBACK rehearsal

- 启动检查：一次本地`-f`路径重复，SQL文件未打开、DB语句0；独立只读连接确认零变化。
- Attempt 1：synthetic overage缺少生产check要求的`planned_lesson_id`，在fixture INSERT阶段失败；事务完整ROLLBACK，独立连接确认新函数/fixture残留0、旧函数MD5/ACL、P002及School/Cash全指纹不变。
- 修正：仅新增独立synthetic ordinary planned并让overage actual精确关联，不改变任何业务断言。
- Attempt 2：Preview V2、Reversal Preview、History V2、admin/operator、锁/forward、reader零写入、fixture savepoint rollback、exact rollback、旧函数/P002恢复和外层ROLLBACK全部通过。
- Attempt 3：在Attempt 2基础上增加read_only和authenticated/anon/service_role ACL断言；完整通过并ROLLBACK。独立连接再次确认零变化。

rehearsal从未调用`school_create_lesson_clearance`或`school_reverse_lesson_clearance`；clearance行仅是固定`2c100000-*` direct synthetic fixture，位于事务savepoint内并回滚。

## 14. 正式部署、postdeploy和生产read RPC

正式执行`school_phase2c_c_r1_clearance_read_contract_deploy_20260817.sql`，advisory lock内原子COMMIT。持久变化仅为3个函数/ACL/comment。

最终函数MD5：

| 函数 | MD5 |
|---|---|
| Preview V2 | `ffeab2952a86c3c40d39cd3a5c806e19` |
| Reversal Preview V1 | `25c4d8f62418f3cec0bec69cf5fe9324` |
| History V2 | `0f0068b523ca6c1c142b6ae55b41bc4d` |

部署后用active admin authenticated JWT在`READ ONLY`事务中：

- Preview V2对真实可用source对返回完整payload、`reservation_created=false`；因选择非FIFO对象准确返回`LESSON_CLEARANCE_FIFO_DEVIATION_REASON_REQUIRED`，没有执行writer。
- History V2返回`[]`，与生产clearance 0行一致。
- Reversal Preview对不存在clearance返回稳定`LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID`；没有为验收创建真实clearance。
- 三个read RPC验收后clearance主/明细仍0/0。

read-RPC验收第一次仅因测试期待了不同错误码而在只读事务回滚；独立零变化复核后把测试匹配改为现行稳定码并通过，没有修改数据库函数。

## 15. ACL与零业务变化

部署前后业务行数/整行指纹一致：

| 对象 | 行数 | MD5 |
|---|---:|---|
| lessons | 772 | `9b393f82ac424ac9df30234fbf44617d` |
| settlements | 18 | `481ffa7ed5173da852f0f28ce66c2e9b` |
| claims | 2 | `fbce39067e6d98167cdb474eb9635c92` |
| bills | 22 | `e50673ac998ee2d84573a076a64d3d42` |
| bill lessons | 330 | `e3e2e0044c17864bc66c7e2861176c8b` |
| revisions | 20 | `ffdc498a6e256aa29064f021f22e4b00` |
| income | 56 | `5410e66708a01d7017de7dc331d32674` |
| Cash linkages | 44 | `f1c336c43533b9d9b81d88b6fa55feef` |
| wage locks | 104 | `bb9d5e027e482547ba4ca58b3731651a` |
| wage details | 624 | `b68ada9b934d4de511da93104228eb4b` |
| package lots | 1 | `8c2b70b087164e5d03defed8cd237f34` |
| School Storage | 57 | `62fac5521274c58c6f6982a0c690c134` |
| feature gates | 3 | `b04952a0603194dd5592124bdee2f7d7` |

Cash DB仍为transactions `75/b5d8b7d466532b90531814e5ccf61ad2`、requests `44/1fc51497aedfaecd72a2ee85714284f0`、Storage `0/d41d8cd98f00b204e9800998ecf8427e`。普通待补、overage、P002均与preflight一致。数据库业务行写入0；白名单业务写入0；真实create/reversal writer调用0；test record持久ID无。

## 16. 文件、回滚与受保护文件

正式文件包括migration、deploy、exact rollback、preflight、production rehearsal、postdeploy、production read-only acceptance、两个本地合同测试、bootstrap、角色矩阵、Node static field-map test、机器字段映射和本报告。Exact rollback只删除本阶段3个versioned read RPC，不触碰旧函数或业务表。

原11份受保护untracked文件路径与SHA-256逐字等于既有基线；Phase 2C-A/B本地草案和原型未暂存、未提交、未执行生产writer。

## 17. Phase 2C-D建议

R1所需DB权威字段已经闭合，允许在独立授权下恢复Phase 2C-D页面接入。页面必须只消费新payload并原样提交request identity/source UUID/分钟/类型/理由/manifest；不得自行推导余额、金额、same/cross、锁或forward。History对`unavailable`必须明确展示“无操作时快照”，不能回退到当前值或猜测值。

本阶段到此停止，不进入生产页面、真实清偿、真实reversal、M016、袁振轩余额处理或package消费。
