# R2-C 两条跨月 legacy planned 月份纠正与课时筛选报告

日期：2026-07-31（Asia/Tokyo）

## 结论

R2-C 数据库 corrective、只读 reader 补口、lesson 页面/API 修复及验收完成。两条授权 legacy planned 的学生结算月由 `2026-08` 精确纠正为 `2026-07`，实际 lesson date 保持 8 月；其他 277 条 legacy planned、bill、income、actual、settlement snapshot、历史19条 overage 与 R0 均未漂移。Cash DB 未连接。

## 目标记录

| UUID | 科目 | 修正前 year/evidence/resolver | 修正后 year/evidence/resolver | lesson_date | evidence identity MD5（前 → 后） |
|---|---|---|---|---|---|
| `8b737b58-cd14-42c5-afd2-34730dcef963` | EJU物理 | `2026-08 / 2026-08 / 2026-08` | `2026-07 / 2026-07 / 2026-07` | `2026-08-01` | `c2885609f6dfc82f02a42855c1628c86` → `0a287ea42649e517879295c772aed039` |
| `685ad45e-b5da-42ca-8f43-7732e8d6e40d` | EJU化学 | `2026-08 / 2026-08 / 2026-08` | `2026-07 / 2026-07 / 2026-07` | `2026-08-02` | `bfd2ee4ab236743905e3db1af85e242a` → `9efda43df96dfb1a36f0e461fab173e6` |

两条继续满足：`lesson_type=planned`、`app_type=school`、billing五字段全NULL、approved evidence source/version不变。student、business entity、teacher、subject、金额、时长、单价、课次数、lesson date及其他业务字段未修改；通用 `updated_at` trigger 将两条 lesson 的时间更新为 `2026-07-30 19:11:54.096633+00`。

两条已有 canonical charge 关系继续指向 bill `2a9f1c25-a060-461e-ae10-b02295dec381`，bill月份为 `2026-07`、状态为 `income_created`，income为 `468ab75b-312e-4ba0-8d8d-8ae2f6ace00e`。账单关系和账单JSON未改写。

## Corrective执行

工件：`sql/current/school_tuition_r2_c_two_legacy_planned_month_correction.sql`

- rehearsal：1次，通过，`r2_c_commit=0`，最终ROLLBACK；独立新连接确认纠正残留0、immutable trigger为enabled。
- 正式执行：1次，通过，`r2_c_commit=1`，正式COMMIT。
- 正式业务DML：2条 lesson 的 `year_month`；2条对应 evidence 的 legacy month和identity hash，共4行。
- evidence保护方式：单一事务取得 evidence `ACCESS EXCLUSIVE` 和 lesson `SHARE ROW EXCLUSIVE`；仅在精确 evidence UPDATE期间临时停用 `school_legacy_planned_evidence_row_immutable`，更新2行后立即恢复。ACL及trigger定义未修改。
- corrective没有重复执行；正式COMMIT后没有回滚或再次修改目标行。

其他277条不变：

- lesson full-row manifest MD5：`e7229e67b167b794112ab7a0efa0c946`
- evidence full-row manifest MD5：`072666dd4191a5009d7f92af680e02fc`
- legacy evidence总数：279

## Postdeploy失败与修正

首次只读postdeploy在正式corrective COMMIT后失败：关系表alias `r`错误使用不存在的 `bill_id`。真实schema列为 `tuition_bill_id`。这是测试脚本列名错误，不是生产corrective错误。

- 失败工件SHA：`90abc392e1c200ad2a72165504e27fcb08e75dc0687f13848cb8ee70ad6bc25c`
- 修正：仅将 join 从 `r.bill_id` 改为 `r.tuition_bill_id`；账单ID、canonical role、billing month、bill status、income ID及全表manifest断言全部保留。
- 首次修正后SHA：`1827ef2d132a14c6665c00cd5da50acd6f080c6fa0dd9865260e1a22693629a9`
- 加入最终只读统计reader定义断言后的SHA：见最终交付清单。
- postdeploy执行共4次：第1次列名错误失败；第2次修正后通过；第3次reader部署后增强断言通过；第4次为最终新连接验收并通过。每次均为只读事务并ROLLBACK，测试残留0。

## 最小只读统计reader补口

列表 API 原先在周筛选时只按lesson date取数，统计RPC也在 `p_week_start` 非NULL时忽略 `p_year_month`。这会使学生结算月列表与顶部统计在存在跨归属月actual时范围不一致。

新增工件：`sql/current/school_tuition_r2_c_lesson_week_stats_authoritative_month_reader.sql`

只替换既有只读 overload：

`school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)`

修复后 `year_month` 与可选 lesson-date week 是累积谓词。签名、12个返回字段、`STABLE / SECURITY INVOKER`及 `anon/authenticated/service_role` EXECUTE ACL保持不变；无表DML。

- 原函数MD5：`5a4563357fcf676ed853b69115dab101`
- 新函数MD5：`f535f4649f870097a350208b64da643e`
- rehearsal共4次：前三次均因 `pg_get_functiondef` 文本空格/换行 verifier不匹配而ROLLBACK；未改变业务断言。第4次完整通过。
- 关键工件SHA轨迹：`99b4b099…c3b2` → `7e072590…f542` → `bf430523…38c1` → `424a7a95…b39b`。
- 正式部署1次，COMMIT；只修改该只读函数定义和comment/ACL重申，业务数据写入0。

## 前端/API修复

- `js/api/lesson-api.js`：lesson记录查询始终先以数据库 `year_month` 限定学生结算月；选周时再叠加 `[weekStart, weekStart+7)` lesson date范围，不再以日期周替代学生月。
- `js/utils/lesson-settlement-filter.js`：仅生成“周一位于所选月份”的自然周；非法URL/恢复周组合清空；响应必须为请求学生月，UUID缺失或重复直接拒绝显示。
- `js/pages/lesson-page.js`：月/周/学生切换立即清空旧记录与统计；request token阻止旧响应覆盖新筛选；结果采用替换赋值而非追加；主列表及跨月关联列表均验证UUID唯一。
- `lesson.html`：月份明确标为“学生结算月”，自然周说明明确按周一归属；实际发生日期不改变学生结算月。
- 详情页继续使用数据库 `year_month` 显示“学生结算月（DB 权威）”，同时保留预计/实际lesson date。
- 页面模块没有新增 `.rpc()`、`.from()`或insert/update/delete/upsert；所有调用继续经过 `js/api`。`js/legacy-core.js`未修改。
- 顶部金额、课时与次数继续读取数据库RPC，不在页面重新计算或持久化业务事实。

## 验收结果

数据库：

- 两个resolver均为 `2026-07`；7月reader集合包含两条，8月reader集合不包含。
- 2026-07的07/27周：统计RPC与权威直接范围均为28条。
- 非法 `2026-08 + 2026-07-27` 周组合：统计RPC为0，页面侧同时fail-closed。
- 2026-08的08/31周：统计RPC为12条。
- rollback tests执行3次，均通过并ROLLBACK；evidence直接更新、lesson month与evidence不一致、partial attribution三项负向测试均拒绝；marker残留0。

前端fixture：

- 2026-07包含 `07/27–08/02`；2026-08不包含；2026-08包含 `08/31–09/06`。
- 两个目标UUID以8月lesson date显示，但只接受 `year_month=2026-07` 的7月视图；8月响应被拒绝。
- 详情月份为 `2026-07`，日期仍为 `2026-08-01/02`。
- 重复UUID拒绝、非法月/周组合拒绝、旧request token失效、切换清空均通过。
- fixture首次因测试正则把既有 `Array.from(...)` 误判为Supabase `.from(...)`而失败；测试SHA `014f5f76…ab07`。正则收紧为 `supabase.from(...)` 后SHA `b91221ad…52f9`并通过；未删除页面边界断言。
- `actual-overage-ui`既有回归通过；修改JS及测试脚本语法检查通过；页面边界扫描0命中；`git diff --check`通过。

## 不变边界

- actual evidence：234，manifest `e685566ddeb27bc9deb8ceb20a272374`
- locked snapshot evidence：15，manifest `f235ba58a0bac368ad50229e50a97ef7`
- settlements：15，manifest `8d40d937d45c64eca0ec0ba7b1c5e65d`
- bills：9，manifest `0f0323b79e7ff1c47ff6b90c75477a2d`
- income：42，manifest `2a4897b752f272b1f192045418b4940c`
- bill relations：121，manifest `285172fedeb923c67ea9a179480d8692`
- 固定历史19条overage：五字段继续全NULL，manifest `352e72ac33d648a23be84bb27b3580d1`
- R2-B candidate function：`1770f3469dbc3bc030a977381b853deb`
- R0：`validation_preview_only / blocked / blocked`
- Cash：未连接；bill、income、actual、snapshot、其余277条均未写入。

本阶段未执行Git add、commit或push，停在R2-C数据库及前端验收审查点。
