# School V2 学生月度结算线上开放 Phase C 实施报告

日期：2026-08-10
范围：只开放 active admin 在线保存草稿；正式锁定继续隐藏。

## 1. 实施结论

Phase C 已完成并部署 Pages，生产版本为 `v10.5.32`。页面以统一 online status 和 DB 权威 Preview 驱动保存资格；只有 active admin 且 DB 返回 `can_save=true` 的普通 incomplete scope 显示“编辑草稿”。lock、unlock、relock 仍不可达，保存后不会自动锁定。本轮生产真实 save/lock 均为 0。Phase D 尚不应立即开放：首次真实保存仍需业务负责人批准精确 student UUID/month 并取得生产证据。

## 2. 实时 Git 状态

- 初始基线：`main`，HEAD/origin/main 均为 `6170f0ceda11d40b796e17fa7830fa39755fbc3f`，ahead/behind `0/0`。
- Phase C 前向提交：`3f3a12d963ca8877da361d63d30bda011c30f60e`、`a318a5e957cc6b4b9c07a2d4a48117854fa9388a`、`562c3c7f003055eab48e10d1eedd39d85d122702`。
- 三个提交均已 push 到 `origin/main`，未 reset、rebase、checkout 回退或 amend 合法提交。
- 本任务没有暂存或提交任何受保护 untracked 文件。并行 V1 Storage 调查留下的 `docs/current-status.md` 工作区修改及其新报告也未被本任务覆盖或纳入 Phase C 代码提交。

## 3. Phase B 遗留收敛

- `settlement-p0b2-adjustment-authority-static-test.mjs`仍假定浏览器直达旧 adjustment writer；现已改为断言页面只能通过 Phase C status/save API、十进制定点字符串及 DB 权威 expected facts，继续禁止旧 writer、直接 RPC 和前端财务计算。
- `p0-g1-a-auth-guard-static-test.mjs`把旧缓存版本写死为全局常量；现改为验证每个入口均带版本、auth guard 顺序正确并复用 canonical Supabase client，没有放松登录或角色边界。
- lesson Console error 来自验收前另一 lesson tab 的旧请求事件，不属于 settlement 页面。5 条 GoTrueClient warning 来自旧测试动态创建多个客户端。使用新的独立 tab、事件游标和页面 canonical client 复测后，settlement 正常路径 error/warning 均为 0。

## 4. 页面改动

- `settlement.html`：增加保存草稿对话框、稳定 loading slot 和只读/可编辑文案；移除旧 lock 控件。
- `js/pages/settlement-page.js`：实现 `runQuery` latest-request-wins、`openAdjustmentDialog` status-first、`refreshAdjustmentDialogPreview`、`handleAdjustmentSubmit` 及保存后 status 恢复。
- `js/pages/settlement-online-state.js`：新增 `canUseOnlineDraftSave`、`onlineStatusDisplay`、`buildOnlineDraftSaveInput`、`classifySaveRecovery` 和 single-flight；十进制只做字符串规范化/比较。
- `js/api/settlement-api.js`：以并发 4、失败隔离方式附加 online status；Preview wrapper 从 DB status 取得 scope，不由页面提交 business entity。
- `js/settlement-app.js`：把既有 auth guard 的 membership role 传入页面。
- `css/app.css`：增加稳定 loading 占位及对话框响应式约束。
- `js/config.js`：页面版本前向升级到 `v10.5.32`；最终缓存链为 `student-settlement-online-phase-c-20260810-2`。
- `js/legacy-core.js`未修改。

## 5. 角色与状态模型

- active admin：仅在 DB `can_save=true`、effective incomplete 且无 blocker 时可编辑/保存。
- operator、read_only：只读，不显示 save。
- inactive、无 membership、anon：继续由既有 session/membership guard 拒绝或跳转登录。
- ordinary locked、historically consumed immutable、historical zero-carry complete：只读；页面使用 DB effective state，而非 physical settlement 是否存在。
- successor revision、wage/other immutable blocker、status/network unknown：均不开放 save，并显示安全业务提示。
- 按钮可见性仅为 UX；Edge JWT active-admin 校验和 DB wrapper 二次校验仍是真实安全边界。

## 6. Preview 与 save 流程

流程为 `status → DB Preview → 用户选择 → Preview失效 → 重新Preview → 单独save → status确认`。支持 `separate_makeup_and_overage_v1`、`net_lesson_variance_to_financial_credit_v1`，以及 carry、clear、manual 三种 adjustment。carry/clear 不要求 manual amount；manual 使用十进制字符串并要求 reason。页面只传用户选择、最近 DB Preview 的 manifest/expected facts、status draft UUID/version 及 student/month；不传 actor、role、business entity、authority、service-role 或 canonical confirmation，不计算 system difference、resolved adjustment 或 final carry。single-flight 阻止双击；网络结果不明确时只读 status-first，绝不盲目重试 POST；成功后也以 status 为最终权威，不自动 lock。

## 7. 筛选和 loading

年份、月份、包含停用、学生、状态和关键词均采用 pending/applied 分离：输入变化不查询、不改 URL；只有“查询”应用全部条件、更新 URL 和列表。候选重载不改变 applied 结果；query sequence 防止旧响应覆盖新查询；popstate 恢复 URL 中已应用状态。固定高度 loading slot 覆盖初载、查询、status、Preview、save/status 恢复，桌面与窄屏不因提示显示/隐藏上下跳动。

## 8. 安全边界

静态和浏览器证据确认：page-layer `.rpc()` 0、DML 0、service-role 0；save payload 中 actor/role/membership/business entity/authority/canonical confirmation 0；页面 lock API import/handler/request 0，核心 lock writer引用 0，unlock/relock 页面入口 0。lock Edge保持已部署但隐藏。表级权限、五个owner-only核心writer、Phase A wrapper ACL均未改变。

## 9. 测试结果

- JS语法、import、`git diff --check`通过。
- Phase C unit 7/7，覆盖角色、状态、source/adjustment、Preview对应、十进制字符串、save recovery 和 single-flight。
- Phase C/Phase B static、P0-G1 auth、P0-B2、P0-F、trusted-tool、business-error、filter-layout、lesson settlement、actual overage、system blocker、student-status-finance测试均通过。
- 旧断言为前向更新，没有删除测试或放松RPC/权限/P0财务权威边界。
- mock覆盖双击一次请求、旧响应隔离、status确认成功/旧版本/其他会话/失败和不自动重试POST。

## 10. Chrome 验收

- 生产页面实际加载 `v10.5.32`和最终缓存资产；新鲜事件游标下 Console error 0、warning 0、HTTP >=400 0。
- 2026-07共7个scope：4个historical zero-carry、2个ordinary locked、1个historically consumed，均无编辑/save/lock；冻结carry显示保持正确。
- 2026-08只读验证：陈红卓、陈加恩为可编辑 incomplete；孙陈锋为 successor revision blocked。打开陈红卓对话框后只执行status/Preview、切换clear/manual并重新Preview；未点击save。
- 选择变化前列表和URL不刷新，点击查询后才应用；桌面、1440px、390px无页面级横向溢出，窄屏表格滚动受控、对话框留在viewport内。
- Network仅出现既有reader/status/Preview请求；save、lock、核心writer、表DML、service-role请求均为0。
- 页面未出现业务归属或“个人名义”UI，未观察到loading导致的明显上下跳动。

## 11. 生产零变化证明

实施前后 count/MD5 完全一致：settlements `18/481ffa7e…`、adjustment drafts `7/0b162413…`、source drafts `1/c2a01866…`、历史证据 `4/9cb22ef4…`、lessons `744/3cd0c2ce…`、income `55/c55f82c7…`、tuition bills `22/e50673ac…`、revisions `20/ffdc498a…`、wage locks `103/ea395407…`、wage details `612/1d45d0ce…`、payment requests `51/6ce63e69…`、expenses `47/34a7a323…`、account transactions `187/00516a76…`、Auth users `1/326b5a73…`、membership `1/332d6f2e…`、Storage `57/62fac552…`；Cash CNY `74/070c262e…`、requests `43/f4b1876e…`、JPY `31/95ab7cf8…`。Gate保持 `enabled / blocked / enabled`。Phase A postdeploy再次返回 `SETTLEMENT_ONLINE_PHASE_A_POSTDEPLOY_PASS`并ROLLBACK。两个Edge仍为原ID、ACTIVE/version 1及原hash。本轮业务SQL/RPC/Edge部署、真实业务写入、fixture写入均为0。

## 12. Pages 部署

- run `31321666401`：commit `3f3a12d`，成功部署主实现。
- run `31321753211`：commit `a318a5e`，成功部署冻结显示事实修复。
- run `31321821627`：commit `562c3c7`，成功部署完整缓存链。
- 生产实际加载 `v10.5.32`和 `student-settlement-online-phase-c-20260810-2`。最终部署commit包含Phase C全部前向修复；初始基线中的并行合法提交均被保留。

## 13. 回滚方案

若需关闭Phase C，创建新的前向提交：在 `settlement.html`隐藏“编辑草稿”和save dialog；在 `settlement-page.js`移除status/save交互入口，并从页面调用链断开save API；提升缓存版本、push并等待Pages成功。Phase A DB合同、Phase B两个Edge和既有draft/status reader保留，页面恢复Phase B只读状态；不删除或覆盖业务draft，不修改Gate或任何DB/Edge事实。

## 14. 遗留事项

- 尚未进行任何真实生产save；首次成功save仍需业务负责人明确授权精确student UUID和month。
- Phase D正式lock UI/handler尚未实现，页面不可达。
- Phase E仍需使用合规测试身份完成active admin、operator、read_only、inactive、无membership、anon的生产角色回归；本轮未修改membership或创建Auth用户。

## 15. Phase D 建议

Phase A lock wrapper、Phase B独立lock Edge、DB manifests/version/transaction lock和Phase C status-first基础已具备，但开放lock前仍缺少一次业务负责人授权白名单scope的真实save成功证据及其status/draft版本闭环。建议顺序：`授权精确scope → status/preflight → 单次save → status与零旁路验收 → 独立Phase D设计lock二次确认/幂等/不明确结果恢复 → 全角色与不可变scope回归 → Pages上线`。本轮不提前开放lock。
