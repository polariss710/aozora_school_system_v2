# School V2 学费财务 P0-D E2E 与本机受信工具实施报告

日期：2026-08-03。结论：代码、DB RPC、Edge、页面收口、全链只读验收、synthetic rollback/并发/Cash blocker/张倬闻镜像均已完成；但当前本机 shell 缺少 `SCHOOL_SUPABASE_URL` 与 `SCHOOL_SUPABASE_SERVICE_ROLE_KEY`，因此无法按正式 Edge 路径完成工具 `void --execute` 的 committed synthetic 验收。P0-D 按 hard stop 记为未完全完成，真实运营继续冻结。

## Business-model expansion declaration

- New tables/columns/enum/status/date/month/attribution/identity/source/snapshot/version/writable facts: none。
- Changed amount formula、historical interpretation、dual read/write、fallback、destructive schema: none。
- Changed writer/reader authority：现有 P0-C Void/Reissue 的本机工具调用固定记录 `local_trusted_business_owner_v1`；新增 owner/service-role 受限 wrapper 只能处理已有 voided revision 且 exact expected facts 全匹配的单条 generation。批准来源：当前 P0-D 指令第三、四、十、十二节。
- Changed permission boundary：既有 Edge 接受 service-role bearer 作为本机受信来源，并提供 `preflight_only` Cash 只读核验；没有新增 anon 权限。批准来源：当前 P0-D 指令第三、四、五、十二节。
- Changed locking rules/new authority: none；继续复用 P0-A/B1/B2/C operation lock、claims、validators 与 DB snapshot authority。

## 本机工具

路径：`scripts/manage-atomic-tuition.zsh`。命令：`status`、`void-preflight`、`void`、`reissue-preview`、`reissue`、`history`。Void/Reissue 默认 dry-run；execute 要求 exact scope、revision/bill/income/manifest或candidate manifest/rate/JPY/CNY、非空 reason/note 和固定确认文本。无 `eval`，无 Cash DB 连接，无业务表 DML，无 generic cancel，无一键 Void+Reissue；SQL 使用固定 heredoc + psql variables，HTTP body 使用 `jq` JSON 编码。网络/RPC 错误退出非 0 且不自动重试。

正式 Void 只走现有 Edge：School preflight → Cash request/CNY/JPY 0 核验 → local owner Void wrapper → P0-C core。Reissue 只走 `school_reissue_atomic_student_tuition_generation_local(...)`，DB 再核对 existing generation、voided previous revision、无冲突 active revision、candidate/generation manifests、rate、JPY/CNY 后调用 P0-C atomic core；公共 Generate Gate 保持 blocked，新 generation 无法走该 wrapper。

## E2E 结果

| 范围 | 结果 |
|---|---|
| generation authority | identity/revision/active = 15/15/15；Atomic/historical = 8/7；void event 0；manifest NULL、identity duplicate、active duplicate均0；15/15四 validator通过 |
| P0-A | consumed settlement reader继续跨 active/voided revision；app roles 对 settlement/draft/adjustment/carryover无直接DML；Void rollback 后 settlement 仍报 `TUITION_CONSUMED_SETTLEMENT_IMMUTABLE` |
| P0-B1 | app-role direct lesson DML 15个拒绝+3个SELECT通过；formal RPC 3/3保存DB fee 4200；18/18 lesson authority矩阵通过；页面/API不提交决定性fee |
| Lesson动态基线 | 当前731 / `72a983e3d3341b6a00ff47235dbaa83c`；新增2条为陈加恩合法页面actual `8e6549bf-194a-4fa4-b753-def0edf2a430`、`f5dca0c1-a553-46dd-99b0-59d6b6753009`；排除后精确恢复729 / `fdddb50d53ff8be527186aa01dc4f710`，未回滚 |
| P0-B2 | 部署对象、公式authority与生产事实保持；旧P0-A/P0-B2固定fixture脚本因后续P0-B2 mode/fixture占用合同不再可原样复跑，P0-D postdeploy与现有P0-B2部署校验通过；真实draft/adjustment/carryover未写 |
| P0-C | generic cancel拒绝、historical不可Void、pending/no-Cash preflight、received/Cash/downstream/manifest blockers、claim释放、settlement永久冻结、append-only Reissue、duplicate idempotency均通过 |
| Cash | request/CNY/JPY = 39/68/31，hash分别为 `303e10bc1a28a0abd8b27afd3929cfd8` / `cba640a696f4c7da59d8df2be7fe79e5` / `95ab7cf8a8d167e9b052d3fc6b64614b`；P0-D Cash fixture 0；Cash写入0 |
| Gate | `preview=enabled / generate=blocked / cash submit=blocked`；仅rollback事务内 rehearsal，正式未开启 |
| V2 页面 | anon 张倬闻 Atomic detail browser smoke 正常，无console error/permission denied；revision 1/active、历史金额/carry/Cash可见；Atomic取消与Cash提交按钮隐藏；普通取消代码保持 |

## Synthetic 张倬闻镜像

固定 revision 1：JPY650,000、rate0.042、frozen carry107.50、CNY27,407.50；current settlement unlocked/current carry0。local Void rollback 成功，event operator为 `local_trusted_business_owner_v1`，claim释放而 consumed settlement继续immutable。DB authoritative Reissue preview(rate0.043)明确返回 carry0、JPY650,000、CNY27,950；revision 2、四 validator 与 duplicate idempotency通过，整个写矩阵ROLLBACK。

结论：按当前权威公式，张倬闻可仅通过 `Void → rate 0.043 Reissue` 得到 CNY27,950；但真实操作仍禁止。

## Fixture UUID 与 residue

- entity `d0d00000-0000-4000-8000-00000000e001`
- subject `d0d00000-0000-4000-8000-00000000d001`
- teacher `d0d00000-0000-4000-8000-000000007001`
- student `d0d00000-0000-4000-8000-00000000a001`
- settlement `d0d00000-0000-4000-8000-00000000b001`
- lessons `d0d00000-0000-4000-8000-000000001101`、`d0d00000-0000-4000-8000-000000001102`
- bill relations `d0d00000-0000-4000-8000-000000005001`、`d0d00000-0000-4000-8000-000000005002`
- legacy identity `d0d00000-0000-4000-8000-000000002001`
- generation `d0d00000-0000-4000-8000-000000003001`
- revision 1 `d0d00000-0000-4000-8000-000000004001`
- bill `d0d00000-0000-4000-8000-000000006001`
- income `d0d00000-0000-4000-8000-000000007101`
- rollback-only School Cash linkage events `d0d00000-0000-4000-8000-000000008101` 至 `...8104`；cash user/account `...9001` / `...9002`；request/transaction placeholders使用相同固定 `d0d...` 测试命名空间。

Fixture 曾 committed insert，随后按固定UUID/marker精确 cleanup；最终 School residue 0、Cash residue 0。真实15条 revision、三名真实学生、真实lesson与Cash均未写。

## 执行与测试

已部署 `school_tuition_p0d_local_management_rpcs_20260803.sql` 和更新后的 `void-atomic-tuition-generation` Edge。已执行 P0-D fixture lifecycle、Void/Reissue rollback、Cash blocker rollback、Void-vs-Void双会话、School/Cash postdeploy、11/11工具/页面静态检查、shell/JS语法、浏览器smoke。P0-D SQL/RPC业务写仅限固定fixture；真实业务行变更0；Cash写入0。

## Hard stop 与 Gate建议

当前缺少本机工具正式 execute 所需的两项环境变量，不能声称“工具 committed Void execute 已验收”。不得把 DB rollback 成功替代 Edge/Cash正式路径。建议继续保持 Gate `enabled/blocked/blocked`；配置这两项既有 secret 后，仅对上述固定fixture重跑 `void-preflight`、`void --execute`、`reissue-preview`、`reissue --execute`、history/cleanup/residue，再做最终P0-D关闭。此之前禁止任何真实学生 Void/Reissue、课时修改、Cash提交或Gate开启。
