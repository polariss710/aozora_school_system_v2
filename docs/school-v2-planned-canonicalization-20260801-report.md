# School V2 固定279条legacy planned规范化实施报告

日期：2026-08-01
状态：planned阶段完成，停在commit前审查点
School DB：正式迁移已COMMIT
Cash DB：未连接

## 1. 结论

- 固定279条legacy planned已全部补齐既有canonical归属字段，legacy planned由279降为0。
- 全部417条planned现均为完整canonical，并全部归属青空进学塾`2cf7b72f-6e3c-4d09-80f7-7c58593cd466`。
- 本次唯一source为`approved_legacy_planned_canonicalization_20260801`，279条共用业务批准时间`2026-08-01 13:39:37.829675+00`。
- 146条planned发生课时表内业务归属变更；actual、账单、收入、支出、结算、工资、账户、School Cash linkage和evidence未写。
- 孙陈锋2026-07整月及四周的planned reader已恢复，整月18条/36小时/JPY306,000。
- 234条legacy actual未迁移。8条跨月补课actual继续按冻结actual evidence读取其实际履约月，不追随source planned收费月。
- Gate保持`student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=blocked`，没有生成真实账单或收入。

## 2. 批准合同复核

本次实施只使用已批准模型：

- 不新增表、列、状态、月份、身份、snapshot或可写事实。
- 新增既有字段允许值`approved_legacy_planned_canonicalization_20260801`，仅用于固定279条cutover前planned历史回填；新建课时writer不会生成该值。
- canonical planned字段回填后为生产权威；planned legacy evidence保留为cutover审计，不再决定已迁移planned的生产月份。
- actual未迁移，其legacy actual evidence仍是实际履约学生月的唯一权威。
- planned-only实体统一后，142条legacy actual与source planned的当前实体不再相等。既有resolver仅在这种差异下使用immutable planned evidence与actual evidence交叉证明迁移前student/entity关联；planned evidence不提供actual履约月，也不改变source planned收费月。
- 未新增长期月份fallback、双写或第二月份权威。

## 3. 固定时间与字段规则

School DB执行一次`SELECT clock_timestamp()`并冻结：

```text
2026-08-01 13:39:37.829675+00
```

279条统一规则：

```text
billing_week_start_date = lesson_date所在ISO自然周周一
billing_month           = billing_week_start_date所在月份
student_settlement_month= billing_month
billing_month_source    = approved_legacy_planned_canonicalization_20260801
billing_month_decided_at= 2026-08-01 13:39:37.829675+00
business_entity_id      = 青空进学塾
```

两条批准跨月记录精确命中：

| ID | lesson date | week start | billing/student month |
|---|---:|---:|---:|
| `f256bca9-fac5-4909-b113-8077efd27d65` | 2026-10-01 | 2026-09-28 | 2026-09 |
| `552c54e3-2d0c-4607-962d-aad39dfff7f7` | 2026-11-01 | 2026-10-26 | 2026-10 |

这两条是legacy evidence month与自然周收费月不一致的全部记录；没有其他证据冲突。

## 4. 固定清单

清单文件：

- `sql/current/school_lesson_planned_canonicalization_20260801_manifest.tsv`
  - SHA-256：`432cbbadb9f8630ccb9c8c644c946187df8ea288c19d2caef3d7aae65b8f05de`
- `sql/current/school_lesson_planned_canonicalization_20260801_manifest_values.sql`
  - 正式执行时SHA-256：`f1b2eeef8c9ca7033aee7e0dc251df39ab88f2d787bd665e0f2c9d962911d7ed`
  - Git交付SHA-256：`c7be1d1597b6fe023fc43f1b56e3a5cbe46302d63110b7a4d36a716863b98169`（仅移除文件末尾多余空行以通过`git diff --check`，SQL内容不变）

TSV逐条包含ID、学生、日期、status、generation batch、当前/目标业务归属、当前/目标canonical字段、evidence、bill relation、locked settlement、locked wage、linked actual、before全行hash、before `updated_at`、before稳定hash和预期after稳定hash。

`updated_at`由既有通用trigger写正式事务时间，没有伪造历史时间。正式279条唯一`updated_at`为：

```text
2026-08-01 14:02:23.647108+00
```

正式迁移聚合指纹：

```text
full-row hash     = 0b25d6bdc8ced4cd88191d0dc12f7d30
stable after hash = 165f279cbcd79d3f4539d8b5930f4ee0
```

稳定after hash仅排除live `updated_at`；rollback同时要求正式`updated_at`精确匹配，因此仍是完整定向after fingerprint。

## 5. 清单汇总

| 维度 | 数量 |
|---|---:|
| 固定planned | 279 |
| 可执行 | 279 |
| 冲突 | 0 |
| canonical五字段补齐 | 279 |
| 业务归属变更 | 146 |
| 有bill relation | 85 |
| locked student settlement（任一旧/目标scope） | 229 |
| 有linked locked wage detail | 182 |
| 有linked actual | 243 |

按学生：

| 学生 | 数量 |
|---|---:|
| 李天伦 | 93 |
| 陈加恩 | 48 |
| 彭宇晗 | 40 |
| 陈红卓 | 36 |
| 张倬闻 | 24 |
| 厦门吕同学 | 20 |
| 孙陈锋 | 18 |

按目标billing month：

| 月份 | 数量 | 月份 | 数量 |
|---|---:|---|---:|
| 2026-02 | 16 | 2026-07 | 73 |
| 2026-03 | 20 | 2026-08 | 12 |
| 2026-04 | 30 | 2026-09 | 1 |
| 2026-05 | 60 | 2026-10 | 3 |
| 2026-06 | 61 | 2026-11 | 3 |

status分布：`planned=181 / completed=63 / pending_makeup=33 / makeup_completed=2`。本次不改变status。

## 6. 孙陈锋2026-07验收

页面使用的`school_list_lesson_management_records_authoritative(text,date)`在最终reader兼容部署后实测：

| 范围 | planned条数 | 小时 | 金额 | status分布 |
|---|---:|---:|---:|---|
| 整月 | 18 | 36 | JPY306,000 | planned 12 / pending_makeup 6 |
| 07/06–07/12 | 4 | 8 | JPY68,000 | pending_makeup 4 |
| 07/13–07/19 | 4 | 8 | JPY68,000 | planned 4 |
| 07/20–07/26 | 5 | 10 | JPY85,000 | planned 5 |
| 07/27–08/02 | 5 | 10 | JPY85,000 | planned 3 / pending_makeup 2 |

四周合计与整月完全一致。

跨月课`aa55dc2e-3b1b-4d2d-863f-9f64e84b8578`保持：

```text
lesson_date              = 2026-09-06
billing_week_start_date  = 2026-08-31
billing_month            = 2026-08
student_settlement_month = 2026-08
```

## 7. 待补来源与余额

07/06周4条pending_makeup均为原始2小时、消费0、剩余2小时、已有bill relation：

| planned ID | 原始h | 已消费h | 剩余h | consuming actual |
|---|---:|---:|---:|---:|
| `1bb16d8a-bbbd-44e4-91e3-222c8ad1ac2c` | 2 | 0 | 2 | 0 |
| `28fa9db8-675d-4e3e-a0a0-89b5c37ad00b` | 2 | 0 | 2 | 0 |
| `6722e5a8-d7a1-453a-93a8-9cbaab227378` | 2 | 0 | 2 | 0 |
| `d561416a-1d32-419e-9ce7-3c534cc744df` | 2 | 0 | 2 | 0 |

因此该周原始总量和当前剩余均为8小时。

学生全局另有两条7月底开放来源：一条剩余2小时；一条原始2小时、已消费1小时、剩余1小时。故卡片的真实含义为：

```text
全局开放来源 = 4 + 2 = 6
全局剩余余额 = 8 + 2 + 1 = 11小时
```

该卡片不是按筛选周统计，迁移前后定义与数值均未改变。

## 8. Actual保持与跨月补课规则

actual全行指纹迁移前后完全一致：

```text
rows = 245
hash = accf575ee9927fc6960420867c4552f5
legacy actual = 234
canonical actual = 11
```

8条makeup_completed actual最终resolver结果：

```text
bd07e78c-eeaf-4881-9bd7-6b80bde0f11b = 2026-05
1318070d-363a-486d-b0a4-bac2160cc600 = 2026-05
6e6cf820-5c47-40b4-a7aa-6852127d3fe3 = 2026-06
2785117a-a3e0-484f-a803-2d023ab22499 = 2026-06
45dd767f-a7e2-4d7b-9ce5-e627c7d93d5f = 2026-06
6cb328c3-2af8-4205-9c1c-3183783614e8 = 2026-06
68f7cc0f-231b-4fa1-985a-5ecfac59b4e8 = 2026-07
9fe69b4b-c5e9-4392-b926-f47ab59c58f7 = 2026-07
```

暂缓actual也保持：

| ID | status | resolver学生履约月 | 教师月 |
|---|---|---:|---:|
| `b147065c-721a-40cf-8789-eaaeae553611` | completed | 2026-02 | 2026-02 |
| `e52b0da9-9c9d-41b3-b9d0-acb06f3269a6` | makeup_completed | 2026-03 | 2026-03 |
| `e890424d-407d-4fc2-b8ad-84745b242cdd` | completed | 2026-11 | NULL/后续调查 |

验证结论：

- actual不进入tuition candidate；candidate函数只读取planned。
- bill/income数量和全行hash未变化，没有新增收费。
- source planned的收费归属由canonical planned字段承担，没有因makeup actual改变。
- 待补余额仍按linked completed/makeup_completed actual时长消费一次；本次未改变任何duration/status/link。
- wage lock/detail全行hash不变，教师工资冻结事实未改变。

## 9. Candidate与preview只读验收

迁移279条在canonical candidate reader中的最终分类：

| 分类 | 数量 |
|---|---:|
| candidate | 68 |
| already_canonical_charged | 85 |
| historical_paid_exclusion | 42 |
| invalid_or_incomplete_data | 4 |
| voided_or_inactive | 80 |

68条candidate按月为：`2026-05=30 / 2026-06=34 / 2026-09=1 / 2026-10=2 / 2026-11=1`。这些是canonical化后reader的真实输出，不代表已生成账单。generate保持blocked；业务负责人必须在未来解除generate前单独审查历史5/6月候选。

孙陈锋2026-08只读validation preview：

```text
preview gate       = enabled
generate gate      = blocked
candidate_count    = 25
lesson_count       = 30
duration           = 50h
base fee           = JPY425,000
aircon fee         = JPY9,240
total              = JPY434,240
existing bill      = none
message            = validation preview only; no business data written
```

孙陈锋2026-07为locked settlement，preview正确返回`R2_F_B_TARGET_SETTLEMENT_LOCKED`，因此没有用锁月preview冒充验收。

## 10. Reader/trigger调整

最终替换既有函数4个，没有新增函数或schema对象：

| 函数 | 最终MD5 | 作用 |
|---|---|---|
| `school_enforce_r1d_f1_planned_attribution()` | `3651e01ad3f475a1b4ebe5cd28c26355` | canonical-first；已迁移planned不再因保留legacy evidence回到legacy分支 |
| `school_resolve_r1d_e_b2_actual_student_month(uuid)` | `6f2a5af36aee84b0fcf2d5eeaedca7cd` | source planned canonical allowlist加入获批source |
| `school_resolve_r1d_e_c_lesson_student_month(uuid)` | `0a9ed8ad8f2b8015fe5979a15e5e0e69` | planned canonical allowlist；legacy actual月仍取actual evidence；实体差异用两侧evidence验证关联 |
| `school_list_student_tuition_candidates(uuid,uuid,text,boolean)` | `788ffc50c559116653e4fdb07d6db851` | candidate canonical allowlist加入获批source |

迁移事务内临时停用并在COMMIT前恢复planned attribution及aircon guard trigger，原因是旧guard会正确拒绝已收费legacy行的一般归属变更。固定清单、逐行before hash、evidence和目标值取代一般更新入口，只对批准279条生效。通用`updated_at` trigger始终启用。

## 11. 保护对象指纹

正式事务内before/after完全一致；最终postdeploy再次读取一致：

| 对象 | 行数 | 全行MD5 |
|---|---:|---|
| actual lessons | 245 | `accf575ee9927fc6960420867c4552f5` |
| tuition bills | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| income | 42 | `2a4897b752f272b1f192045418b4940c` |
| expense | 45 | `4d120d8ac0fe843733873664f8c0674e` |
| bill relations | 121 | `285172fedeb923c67ea9a179480d8692` |
| billing identities | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| student settlements | 17 | `1d7328654f6488952dba20640072c3e2` |
| account transactions | 185 | `8f4f6c4365035f6c36bac59ba986b28b` |
| School Cash linkage | 35 | `6e76a4dc2fc2954b28b7ad0a8d203ba0` |
| wage locks | 95 | `7bbe108d3ac73d4f21530793bf141bc6` |
| wage details | 556 | `6204dc666b3b8e0f64fac901ecf0686a` |
| planned evidence | 279 | `380ee5e6cb419572379a0cfa4dfe6821` |
| actual evidence | 234 | `e685566ddeb27bc9deb8ceb20a272374` |
| feature gates | 3 | `941be1f2d3de92dfde24ae34c388ca67` |

## 12. 执行记录

正式迁移文件：

- `school_lesson_planned_canonicalization_20260801.sql`
- 正式执行字节SHA-256：`a1586be4a536ea6a48ea2f8d89d0e6ac341bb6cb1e7222067f50b1eff58e5cd2`
- 同一字节先以`planned_canonicalization_commit=0`完整执行并ROLLBACK，再以`=1`正式COMMIT。

reader兼容文件：

- `school_lesson_planned_canonicalization_20260801_legacy_actual_reader_compat.sql`
- SHA-256：`233d80855a39bb7b902f801cbd2d532d223e3b09866e881855c909b22564d57b`
- 同一字节先rehearsal ROLLBACK，再正式COMMIT。

rollback：

- `school_lesson_planned_canonicalization_20260801_rollback.sql`
- 使用正式`updated_at`、279条after稳定hash和完整字段值定向恢复；事务内恢复原始279条before全行hash及旧函数MD5后ROLLBACK，测试通过。
- rollback测试没有撤销正式迁移。

postdeploy：

- `school_lesson_planned_canonicalization_20260801_postdeploy.sql`
- repeatable-read、read-only执行通过。

执行期间未调用任何write RPC，未创建fixture，未写Cash DB。正式业务数据写入不是白名单测试数据，而是业务负责人明确批准的固定279条真实planned迁移。

## 13. 文件与Git

新增：

- `sql/current/school_lesson_planned_canonicalization_20260801_manifest_query.sql`
- `sql/current/school_lesson_planned_canonicalization_20260801_manifest.tsv`
- `sql/current/school_lesson_planned_canonicalization_20260801_manifest_values.sql`
- `sql/current/school_lesson_planned_canonicalization_20260801.sql`
- `sql/current/school_lesson_planned_canonicalization_20260801_legacy_actual_reader_compat.sql`
- `sql/current/school_lesson_planned_canonicalization_20260801_rollback.sql`
- `sql/current/school_lesson_planned_canonicalization_20260801_postdeploy.sql`
- `docs/school-v2-planned-canonicalization-20260801-report.md`

更新：

- `docs/current-status.md`

没有修改前端、API或其他业务模块。没有`git add`、commit或push；按任务要求停在commit前审查点。

## 14. 后续边界

- 234条legacy actual仍待后续独立固定清单与业务批准，不得把本次planned规则直接套到actual。
- 上述8条makeup actual、`e890424d...`、`b147065c...`、`e52b0da9...`继续进入actual专门清单。
- 在业务负责人审查68条candidate，尤其2026-05/06共64条之前，`student_tuition_generate`必须继续blocked。
- 本轮到此停止，等待业务负责人和ChatGPT审查。
