# School V2 Phase 2C-D2-A2 清偿工作台业务化表达与待补对象日期修正

## 结论

Phase 2C-D2-A2 已完成并上线为 `v10.5.51`。本阶段没有建立真实清偿、没有预占余额、没有调用 create/reversal writer，也没有修改任何业务行。

三项反馈均已闭合：

1. 清偿工作台删除“业务归属”筛选、个人名义选项及日常重复业务范围显示；`business_entity_id`、同业务范围 Gate、writer 重验和 History 审计均保留。
2. 用户术语统一为“待补对象”“可用超额”“系统核对结果”等业务语言；主界面不再常驻 UUID、manifest、fingerprint 或英文错误码。
3. 待补对象运营日期改由 DB V3 reader 权威返回；袁振轩目标由错误的自然周周一 `2026-08-10` 修正显示为部分履约实际日 `2026-08-14`。

## 业务模型扩展声明

- 新业务表、字段、状态、可写事实、锁语义、双写、历史重解释、破坏性变更：`none`。
- 新只读对象：`school_list_lesson_clearance_pending_balances_v3(uuid,boolean)`。
- 新只读 JSON 字段：`operational_display_date`、`operational_display_date_basis`、`origin_partial_actual_id`、`origin_partial_actual_date`、`origin_evidence_status`、`operational_display_explanation`。
- V2 定义、字段和调用方保持不变；页面运营日期只消费 V3 权威字段，不联查 lesson、不解析 note、不按日期/created_at 猜测。
- 批准依据：本阶段任务第二、三节明确允许在 V2 payload 不完整时新增向后兼容 V3 reader，并逐项批准上述只读语义。

## 只读调查

生产调查全部在 `BEGIN TRANSACTION READ ONLY ... ROLLBACK` 内完成。

- V2 MD5：`94dcc95f7c64325e77ea5fa326dc5d05`；payload 不含 partial actual UUID、partial actual 日期或运营显示日期。
- 目标 planned：`8870f57f-bca5-4114-90db-ee592cca2f45`，行 MD5 `dce7c9c99e8e1f7bdb09c80fe0b9e958`。
- 唯一有效 partial actual：`2da1ec9a-6f19-49af-a9bd-48984a255aa9`，日期 `2026-08-14`，行 MD5 `09c20f056b66c872ca63da98454bdcc4`。
- 21 个当前可用 pending 中，有且仅有 3 个存在唯一有效 partial actual；其余 18 个使用来源自然周周一；歧义证据 0。
- cancelled、makeup_completed、voided 均不覆盖产生日期；后续 makeup 消费不会改变运营日期。
- V2 authenticated reader 可见 21 源／2400 分钟；clearance 主表／明细表 0／0。

## V3 日期合同

有效 partial 必须同时满足正式字段关联：School actual、`status=completed`、未 void、精确 `planned_lesson_id`、同学生/老师/科目/业务范围、actual minutes 大于 0 且小于 planned 初始分钟。

日期决策：

| 情况 | `operational_display_date` | basis |
|---|---|---|
| 唯一有效 partial actual | partial actual 的 `lesson_date` | `partial_actual_date` |
| 无有效 partial | 来源东京自然周周一 | `source_natural_week_start` |
| 多个有效候选或证据不可用 | fail-safe 来源自然周周一 | `source_natural_week_start` |

V3 保留 V2 全部余额、金额、claim、lock、FIFO 和资格语义。最终 catalog：

- MD5：`7628cd1ddfe1fd917de0637a898659da`
- owner：`postgres`
- `SECURITY DEFINER` / `STABLE`
- `search_path=pg_catalog, public`
- authenticated 可执行；PUBLIC、anon、service_role 不可执行
- active membership 及 admin/operator/read_only 合同不变

## 日期矩阵

- 袁振轩 partial 目标：planned `8870f57f...` → actual `2da1ec9a...` → `2026-08-14 / partial_actual_date`。
- 袁振轩 8 月 3 日 cancelled：`2026-08-03 / source_natural_week_start`。
- 袁振轩 8 月 17 日 cancelled：`2026-08-17 / source_natural_week_start`。
- direct pending / legacy / 无可证明 partial：自然周周一。
- makeup 消费：显示日期保持初始余额产生日期。
- FIFO 排序字段及 rank 未读取运营显示日期，结果不变。

## 部署记录

1. 本地字段矩阵、角色矩阵、exact rollback 通过。
2. 首次生产 ROLLBACK rehearsal 通过。
3. 首次正式部署后，postdeploy 发现 basis 机器值使用了草案值 `origin_partial_actual_date / tokyo_natural_week_monday`，与批准的精确合同不一致。
4. 立即执行 exact rollback；独立连接证明 V3 不存在、V2/业务数据/ACL/指纹不变。
5. 仅修正机器值与 explanation；本地矩阵及第二次生产 ROLLBACK rehearsal 通过。
6. 正式部署修正版 V3；postdeploy 通过。

没有删除、注释或弱化任何断言。首次部署的精确回滚属于 catalog 回滚，业务行始终为 0 变化。

## 页面分层

主界面只显示姓名、运营日期、老师、科目、当前可用余额、可清偿金额、建议顺序和中文状态。删除业务归属筛选、个人名义选项、卡片/下拉中的业务范围名称。

UUID、request identity、manifest、source fingerprint、证据机器值、lock 证据、原始错误信息保留在默认折叠的“系统详情”。点击普通卡片或系统详情不再触发无条件列表重绘，展开状态可以正常保留。

跨业务范围在 Preview RPC 前由状态机稳定拒绝，文案为：

`该学生存在不同业务范围的课时余额，当前不能合并清偿，请分别处理。`

正式 Preview/create writer 仍通过精确 source UUID 在 DB 内解析并重验业务范围；没有新增 RPC 参数或旁路。

主要术语：

- 待补来源 → 待补对象
- 可用超额 source → 可用超额
- DB 权威 Preview → 系统核对结果
- 读取 Preview → 核对清偿结果
- current available → 当前可用余额
- DB 可用金额 → 可清偿金额
- FIFO → 建议顺序（较早产生的余额优先）
- 可作为候选 → 可选择

稳定错误码已覆盖 claim/clearance 占用、余额不足、学生/业务范围/单价不一致、package 禁止、Preview/fingerprint 失效、membership、locked forward、reversal、幂等和网络结果不确定。主提示为中文；未知原始错误只进入“系统详情”。

## 最终确认 Dialog

主区域显示业务决策事实；request identity、manifest、完整 UUID 和 fingerprint 默认隐藏在“系统详情”。业务说明仍只从 `previewInputSnapshot` 读取，修改表单会使旧 Preview/manifest/快照失效。

生产唯一 Preview：

- request identity：`9a13559f-4ec9-49a3-8ffe-f9df0daea1b4`
- manifest：`c752fe8add92ea9123d1c9e178e2e3101edb384fe069cd09ed04e40ed0071eae`
- pending fingerprint：`dce7c9c99e8e1f7bdb09c80fe0b9e958`
- overage fingerprint：`056696397aae3d1f1701dc0ef974e928`
- 待补对象日期：`2026-08-14`
- 待补／超额余额：`60 → 0 / 60 → 0` 分钟
- 金额：`JPY -9,000 / JPY 9,000 / JPY 0`
- FIFO 一致、同老师、同科目、无锁定、无 forward
- `reservation_created=false`
- 业务说明完整显示且与发送快照一致

Network：Preview POST 1；浏览器 CORS OPTIONS 1；create POST 0；reversal POST 0。最终红色按钮从未点击，Dialog 截图后关闭。Console error/warning 0。

截图：

- `/private/tmp/phase2c-d2-a2-production-final-dialog-desktop.png`
- `/private/tmp/phase2c-d2-a2-production-final-dialog-system-details.png`
- `/private/tmp/phase2c-d2-a2-production-final-dialog-390.png`

1440 与 390 的 document/panel 横向溢出均为 0；390 系统详情默认折叠，标准按钮可在 Dialog 内滚动到达。

## 测试

- JavaScript syntax：通过。
- V3 SQL 静态检查：通过。
- 一次性本地 PostgreSQL 字段、角色、ACL、exact rollback：通过，全部 fixture 位于临时库。
- 新业务表达静态/状态机/浏览器专项：通过，writer 0。
- 现有 D2A static/state/browser 回归：通过；browser writer 仅为内存 mock，生产 writer 0。
- 1440/1024/768/390 横向溢出 0；Console 0。
- 页面直接 `.rpc()` / 表级 DML：0。
- `git diff --check`：通过。

旧 Phase 2I-A postdeploy 脚本在最终复核时因后续合法 clearance 对象触发其历史 `PHASE2I_A_POSTDEPLOY_FORBIDDEN_OBJECT` 断言；连接退出并回滚。未弱化旧断言，改用本阶段新增的专用纯只读 School/Cash 指纹脚本完成最终审计。

## 最终零业务变化证据

最终 School 指纹与阶段基线逐项相同：lessons 772、settlements 18、claims 2、bills 22、bill lessons 330、revisions 20、income 56、Cash linkages 44、wage locks 104、wage details 624、package lots 1、Storage 57、Gate 3；各自 MD5 均未变化。

- Clearance 主表／明细表：`0 / 0`，空表 MD5 均 `d41d8cd98f00b204e9800998ecf8427e`。
- pending：21 源／2400 分钟；目标 60 分钟。
- overage：4 源／135 分钟；目标 60 分钟。
- History：0。
- P002：`1200 / 0 / 1200` 分钟。
- School Storage：57，MD5 `62fac5521274c58c6f6982a0c690c134`。
- Gate：3，MD5 `b04952a0603194dd5592124bdee2f7d7`。
- Cash CNY/JPY/request/account/Storage 分别为 75/34/44/7/0，MD5 与基线一致。
- School/Cash 相关开放事务：0。

数据库持久变化仅为获批的只读 V3 函数、ACL 和 comment；业务数据写入 0。调用的生产 RPC 仅为页面既有 readers 与唯一一次只读 Preview；create/reversal 未调用。

## Git 与部署

- 实现提交：`8efb0d0234469ac6dfbf87a1e637e9df2abb5938`
- Pages run：`32099918594`，success
- 生产版本：`v10.5.51`
- 最终审计文档提交：见本文件后续 Git 记录

阶段开始时记录的全部既有 untracked 文件路径与 SHA-256 在结束时逐项一致；本阶段文件独立提交，没有暂存或修改受保护文件。
