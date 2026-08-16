# School V2 锁定收费月后的非计费补课与孙陈锋单笔纠错

日期：2026-08-16（Asia/Tokyo）
阶段：R3完整Gate、正式部署、单笔纠错及生产只读/Chrome验收完成。

## 业务模型扩展声明

| 声明项 | 对象与语义 | 当前任务批准依据 |
| --- | --- | --- |
| 新表、字段、状态、长期兼容字段、双写 | `none` | 当前任务“本轮不授权”明确禁止 |
| 新业务事实或权威来源 | `none`；学生收费仍由来源 planned / 既有账单承担，补课学生费固定为0；老师工资月仍由actual日期决定 | 当前任务§IV、§V |
| 变更锁定规则 | `public.school_create_lesson_credit_makeup_actual(...)`与`public.school_enforce_r1d_e_b2_actual_attribution()`：来源学生收费月锁定不再阻断严格的`makeup_completed + is_billable=false + lesson_fee=0`履约；目标老师工资月锁定仍阻断；ordinary和其他收费变化仍阻断 | 当前任务§II、§IV明确批准该对象边界和完整条件 |
| 精确历史事实纠错 | 仅目标planned `8b737b58-cd14-42c5-afd2-34730dcef963`与错误actual `c8e6cf21-850c-4700-af9e-7ebf3c2a577d`：以前向soft-void排除错误actual，复用正式取消/转待补与makeup writer生成8月1日取消actual和8月11日补课actual | 当前任务§II、§V、§VII明确批准该精确链、审计、乐观并发和正式writer要求 |
| 通用取消writer合同 | 不变；如需为上述单笔纠错加入内部通道，只能由精确UUID、预期`updated_at`/整行MD5、active admin、事务内专用context及完整财务指纹同时授权，不能形成通用管理员绕过 | 当前任务§II、§V“允许修复既有正式writer安全边界；不允许无约束强制修改RPC” |
| 历史影响 | 仅上述精确课时链；不重算、不解锁、不改2026-07 settlement/bill/revision/income/Cash，不触碰2026-07-06待补来源 | 当前任务§II、§V、§VIII |

结论：本阶段不引入新业务模型。唯一通用语义变化是业务负责人已逐项批准的非计费补课锁定边界；唯一历史变化是已批准的精确单笔纠错。

## 只读Gate结论

### 唯一目标链

- 学生：孙陈锋 `b17abc58-2f64-4bad-bf20-c9643ead60bc`。
- 老师：田宇辰 `edaf30da-1315-4455-99d1-ead1b7147662`。
- 科目：EJU物理 `14257e03-4d08-478e-b1dc-33c685c3d8f9`。
- planned：`8b737b58-cd14-42c5-afd2-34730dcef963`，2026-08-01 13:00–15:00，2小时，学生月2026-07，JPY 17,000，`status=planned`，`updated_at=2026-08-01 14:02:23.647108+00`，整行MD5 `07296184e3ffaf443f89109e2b54d9b9`。
- 错误ordinary actual：`c8e6cf21-850c-4700-af9e-7ebf3c2a577d`，同日同时间，120分钟，学生月2026-07、老师月2026-08，JPY 17,000，`status=completed`，`updated_at=2026-07-31 15:51:01.478823+00`，整行MD5 `1086af5afd9a91d3a6a03b2d5b9cc458`。
- planned仅有上述一条linked actual；无cancelled、makeup或重复消费；当前remaining为0。
- 排除来源2026-07-06：`6722e5a8-d7a1-453a-93a8-9cbaab227378`，remaining 2小时，整行MD5 `94050771268fa97cda680affb81e9364`；与目标planned不同且无linked actual。

### 锁定财务与Cash

- 2026-07 settlement：`5e0a23ff-0e1e-48c6-9866-5fc335b3e42d`，`locked`，整行MD5 `c96670560d491a82b552b32492cd1a55`；不存在独立settlement details表，锁定行自身保存聚合快照字段。
- 该settlement已被2026-08账单 `7d764343-8aef-4905-999a-24e07c34e2f4`消费，因此取消writer当前先后会命中`LESSON_FINANCIAL_FACT_IMMUTABLE`和locked guard。
- 2026-07账单：`2a9f1c25-a060-461e-ae10-b02295dec381`，整行MD5 `e6f0b5df93101ea1c9f07c9c7aea0e07`；目标planned关系行MD5 `355b2c378a9f2d20d03facfbbbe24079`。
- revision：`96000000-0000-4000-8000-202608031005`，manifest SHA-256 `74a2308525cf2f4c00065c06463f79a9c2e8ad8169fec389a815e7145d34ea78`，整行MD5 `cf30373f4e86abe1568c8516ae0c4a7c`。
- income：`468ab75b-312e-4ba0-8d8d-8ae2f6ace00e`，JPY 306,000 received，整行MD5 `88cd48e56ce1b8637625d0b6b2a22993`。
- School Cash linkage：`43256fb6-3f6e-41f7-9802-1d1c42a3f2c5`，整行MD5 `8ce313f76c78e838d23425ce74801983`。
- Cash request：`b0baf105-c98f-4b8d-ae23-1f9f6e35ac44`，approved，整行MD5 `cca63292eebd405165c9e217b08ab3e8`；Cash transaction `c37665ea-e8bc-4b90-859c-292ef37c35eb`，CNY 12,852，整行MD5 `077b4406ea8d26ed119e98f60d73fcbc`。

### 工资与阻断层

- 田宇辰2026-08无`school_teacher_wage_locks`行、无target wage detail、未锁定、未支付。
- 当前错误actual是2026-08工资候选，active rule `8b943b71-d2fb-4938-bcee-3d728800bc2b`，JPY 4,000/小时，2小时=JPY 8,000。
- 当前田宇辰/目标业务归属2026-08候选为5条、总工资JPY 40,000；纠错后必须仍为5条/JPY 40,000，只替换目标候选UUID。
- 第一阻断：`school_create_lesson_credit_makeup_actual(...)`，SQLSTATE `P0001`，稳定码`LESSON_MAKEUP_STUDENT_SETTLEMENT_LOCKED`。
- 第二阻断：`trg_school_lesson_r1d_e_b2_actual_attribution` → `school_enforce_r1d_e_b2_actual_attribution()`，SQLSTATE `P0001`，稳定码`R1D_E_B2_STUDENT_SETTLEMENT_LOCKED`。
- 两层均使用来源planned解析出的`student_settlement_month`；老师锁使用actual日期派生的`teacher_settlement_month`。当前guard没有区分ordinary计费actual与fee=0的makeup actual，范围过宽。

### 调用方与既有样本

- 页面只经`js/api/lesson-api.js`调用canonical `school_create_lesson_credit_makeup_actual`；页面模块无直接`.rpc()`。
- cancellation同样经API层调用`school_create_cancelled_actual_lesson_from_planned`；仓库Edge Functions、GitHub Actions和其他页面未发现这两个RPC的服务端调用方或动态名称拼接。
- 两个旧makeup compatibility函数为owner-only，页面不调用。
- 生产已有多条“来源学生月已锁定、后月完成、fee=0、non-billable”的历史makeup样本，证明收费月与后续履约月分离是既有业务事实；部分更早legacy行缺少当前canonical月份字段，不能作为新writer放宽字段约束的依据。

## 基线指纹

- lessons全部：`759 / 7bef22fea2b4b024c5cd1cb66690fae6`。
- lessons排除目标链：`757 / 2e1a32b9cbcba335172e07eece344a09`。
- settlements：`18 / 481ffa7ed5173da852f0f28ce66c2e9b`。
- bills：`22 / e50673ac998ee2d84573a076a64d3d42`；bill_lessons：`330 / e3e2e0044c17864bc66c7e2861176c8b`；revisions：`20 / ffdc498a6e256aa29064f021f22e4b00`。
- income：`56 / 5410e66708a01d7017de7dc331d32674`；School Cash linkage：`44 / f1c336c43533b9d9b81d88b6fa55feef`。
- wage locks：`104 / bb9d5e027e482547ba4ca58b3731651a`；wage details：`624 / b68ada9b934d4de511da93104228eb4b`。
- correction events：`11 / 772dcc5c2c5e3d822d19eb3eb26766da`。
- Gate：`3 / b04952a0603194dd5592124bdee2f7d7`；Storage：`57 / 62fac5521274c58c6f6982a0c690c134`。
- Cash requests：`44 / 635bbfe049d06ffd1bbf88500d8ef2d1`；CNY：`75 / b5d8b7d466532b90531814e5ccf61ad2`；JPY：`32 / 4606ae01e81710ccb6efb4504210f410`；accounts：`7 / 89b057e2cdeb7324ef73f73e252174f1`。

全部生产调查SQL均在`BEGIN TRANSACTION READ ONLY ... ROLLBACK`内。两次catalog包装查询因别名/列名错误进入aborted，均立即显式ROLLBACK，并在独立连接中复核三条课时、settlement、bill和income指纹不变。调查阶段writer/RPC调用0、数据库写入0。

## 根因与最终guard合同

- 根因是canonical makeup writer和`school_enforce_r1d_e_b2_actual_attribution()`都把“来源planned的学生收费月已锁定”当作所有后续actual的绝对阻断，没有区分会改学生收费的ordinary actual与严格fee-zero/non-billable makeup履约。
- writer现在只为以下集合跳过学生锁阻断：精确来源planned、`pending_makeup`有正余额、`status=makeup_completed`、`is_billable=false`、最终`lesson_fee=0`、actual日期不早于source；学生/老师/科目/业务归属、时间刻度、duration、余额、权限、工资月锁和并发校验不变。
- attribution trigger只对同一严格集合允许保留锁定的`student_settlement_month`；ordinary计费actual、其他历史改写和工资月锁定继续拒绝。
- 最终函数MD5：makeup writer `3434e8ece09ec210511aec8b8eb1960f`，cancel writer `3e3a8771174d454451e630c29d558a64`，attribution guard `e0c833da212018b236ef72e090dd6c29`。
- 三者均为postgres owner、`SECURITY DEFINER`、固定`search_path=pg_catalog, public`。两个正式writer只给authenticated EXECUTE并继续执行DB membership；guard只给owner。表ACL/RLS未放宽：anon/authenticated/service_role只有SELECT，INSERT/UPDATE/DELETE均false。

## R2/R3可见性与rehearsal记录

- Attempt 3准确原因：合成source `2020-01-01`按DB收费周权威归属到周一`2019-12-30`，因此学生月是`2019-12`，测试却固定期望`2020-01`；不是RLS或writer失败。authenticated对底表原合同有SELECT，RLS policy为`USING(true)`；正式reader因正确月份过滤不返回该错误fixture。修正为source `2020-01-06`、actual `2020-01-07`后，writer返回成功、owner字段diff `{}`、authenticated底表与正式reader各可见1行。
- Attempt 4：ordinary负测错误匹配英文`LOCKED`，实际稳定消息为“目标学生月度结算已锁定，不能生成 actual。”；回滚与独立指纹复核通过。
- Attempt 5：证据SQL使用PostgreSQL不支持的`min(uuid)`；改为精确UUID/确定性读取；回滚与独立复核通过。
- Attempt 6：旧断言要求`is_billable=false + lesson_fee=1`必须抛错；事务内实际未抛错，按R2规则回滚停止，独立复核通过。
- R3 Attempt 7：新增下游快照误写不存在的`school_teacher_wage_details`，正确表为`school_teacher_wage_lock_details`；连接退出自动回滚，随后School/Cash完整独立指纹复核通过。
- R3 Attempt 8：完整通过并显式ROLLBACK。fee=1输入的`RETURNING`和owner精确读取均为`is_billable=false / lesson_fee=0`，余额0；settlement、bill、bill lesson、revision、income、Cash-link、wage lock/detail八类快照零差异。触发器顺序证明`trg_school_lesson_p0b1_financial_authority`先于attribution guard执行并权威归零，故最终安全不变量成立，无需新增异常。
- 完整矩阵覆盖合法锁定月fee-zero makeup、ordinary拒绝、billable拒绝、无/不足余额、重复、日期倒置、工资锁定、并发单winner、admin/operator/read_only/inactive/无membership/anon、owner字段diff、authenticated底表及正式reader可见性；全部合成fixture最终ROLLBACK。

## 正式部署与精确纠错

- migration正式部署一次，随后catalog/ACL只读检查和完整合成负向矩阵通过；负向矩阵最终ROLLBACK，业务行仍为基线。
- 一次性函数部署时为owner-only：PUBLIC、anon、authenticated、service_role均无EXECUTE。函数硬编码并校验目标planned/错误actual/排除source UUID、预期`updated_at`、整行MD5、唯一actor、confirmation和全部财务/工资指纹。
- 正式actor：`25331ae9-3412-48b9-bdc3-e516caeaeba4`。执行结果：
  - planned：`8b737b58-cd14-42c5-afd2-34730dcef963` → `pending_makeup`；
  - 错误ordinary actual：`c8e6cf21-850c-4700-af9e-7ebf3c2a577d` → soft-void，MD5 `d74258d470dfbc18cf8f9ae3bd0673aa`；
  - 8月1日cancelled actual：`ff517a87-39fd-4282-89a9-e4fef28b728c`，13:00–15:00、fee0、minutes0、MD5 `1cda6bbd6f01b4f0de61ea7740dca615`；
  - 8月11日makeup actual：`e69d9745-884a-401f-a4dc-d6672ea2a602`，13:00–15:00、`简谐+万有引力`、fee0、minutes120、学生月2026-07、工资月2026-08、MD5 `8aaf2931dd88a53bc04b233d72d2f009`。
- actor/source/correction batch保存在新actual note与旧actual void_reason；新actual均精确关联目标planned。一次性函数在同一提交事务内DROP，最终catalog不存在该函数或新增可复用写入口。

## 最终不变量与生产页面验收

- 目标待补余额为0；排除的7月6日source仍为2小时且MD5仍`94050771268fa97cda680affb81e9364`。
- 田宇辰2026-08工资候选仍为5笔/JPY 40,000；旧actual退出候选，新makeup actual唯一贡献JPY 8,000，工资未锁/未支付且无重复。
- 目标settlement、bill、bill lesson、revision、income、School Cash-link六个MD5全部保持基线；Cash request/transaction及Cash全库四类指纹保持基线。
- lessons由759变为761，仅新增目标链两条actual；排除目标链仍`757 / 2e1a32b9cbcba335172e07eece344a09`。settlement、bill、bill lesson、revision、income、Cash-link、wage lock/detail、correction event、Gate、Storage的行数与全表指纹全部保持基线。
- 生产`v10.5.45`无需前端改动。Chrome在2026-07筛选下显示8月1日“待补课/已取消/JPY 0”和8月11日“已补课/JPY 0/简谐+万有引力”，老师、科目、时间、学生月和工资月均正确；Console error/warning 0。仅加载、选择月份和查询，writer点击0。

## 文件与回滚

- migration/精确入口：`sql/current/school_locked_billing_month_nonbilling_makeup_sun_chenfeng_correction_20260816.sql`。
- 部署前精确定义与回滚：`sql/current/school_locked_billing_month_nonbilling_makeup_predeployment_definitions_20260816.sql`、`sql/current/school_locked_billing_month_nonbilling_makeup_sun_chenfeng_correction_exact_rollback_20260816.sql`。精确回滚仅用于数据纠错前恢复函数定义；文件本身对纠错后的使用设有硬停。
- rehearsal/负测/最终审计：`sql/current/school_locked_billing_month_nonbilling_makeup_rehearsal_20260816.sql`、`sql/current/school_locked_billing_month_nonbilling_makeup_negative_rollback_tests_20260816.sql`、`sql/current/school_locked_billing_month_nonbilling_makeup_sun_chenfeng_postcorrection_readonly_20260816.sql`及两库只读审计文件。
- 正式业务写入只有一次精确纠错事务：soft-void目标错误actual、更新目标planned、创建上述cancelled/makeup actual；未调用其他真实业务writer，未写Cash/Storage/Gate。
