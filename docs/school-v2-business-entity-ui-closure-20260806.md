# School V2 Phase BE-UI 实施与验收报告

日期：2026-08-06

阶段：Phase BE-UI — 单一业务主体 UI 收口

结论：代码、只读 reader、Profile ACL、生产对账与 Chrome 验收已完成；生产业务数据零修改。Git 与 Pages 值见文末“发布闭环”。

## 1. 授权、恢复与工作区所有权

恢复时重新读取了 `AGENTS.md`，执行 `git fetch origin`，实时 `HEAD` 与 `origin/main` 均为 `057ca44048bdc4661d3b4c5914741783863be8d4`，ahead/behind 为 `0/0`；Pages run `31080490500` 为 success，页面版本 `v10.5.11`。Gate 为 `student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=enabled`；Auth 为 `disable_signup=true`、`mailer_autoconfirm=false`。

恢复时工作区按所有权分为三类：

1. BE-UI 拥有：全部 tracked 修改，以及本阶段新增的 1 个静态 fixture、2 个只读基线 SQL、4 个 School reader/ACL SQL。
2. 原六份受保护 untracked：只读保留，不属于 BE-UI。
3. 已停止的“课时 writer 权限与余额封口”任务留下的 3 份 untracked 草案：外来草案，只读隔离，不属于 BE-UI。

复核确认全部 tracked 修改均为 BE-UI 页面、API、缓存版本、fixture 或模块状态说明，没有来自已停止任务的 tracked 修改。恢复后外来草案多次复核大小、mtime 与 SHA-256 均稳定，因此工作区独占条件成立。

## 2. 受保护与外来草案指纹

### 原六份受保护文件

| 路径 | 大小 | mtime | 开始 SHA-256 |
|---|---:|---|---|
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | 61681 | 2026-08-01T23:59:45+0900 | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | 4483 | 2026-07-27T18:20:55+0900 | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | 15861 | 2026-08-03T01:05:16+0900 | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | 10345 | 2026-08-03T01:03:51+0900 | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | 15089 | 2026-08-03T01:02:30+0900 | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | 27370 | 2026-08-03T01:07:52+0900 | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

### 外来课时 writer 草案

| 路径 | 大小 | mtime | 开始 SHA-256 |
|---|---:|---|---|
| `sql/current/school_lesson_writer_p0_permission_balance_closure_core_20260806.sql` | 30866 | 2026-08-06T16:57:09+0900 | `3282804943061e3e3436a056ecf6c3a9e19eafdcb0d43b48fb7a22b050e3b6c8` |
| `sql/current/school_lesson_writer_p0_permission_balance_closure_deploy_20260806.sql` | 247 | 2026-08-06T16:58:01+0900 | `b6cf7f6bf98d025b133673571f31d8262b38dac46f12f8274bbf77350b2e341f` |
| `sql/current/school_lesson_writer_p0_permission_balance_closure_postdeploy_20260806.sql` | 7973 | 2026-08-06T16:58:01+0900 | `63615240b37518b0618bd5e7bd9005cad20649c606ae7fb3610eed0b291c6e1c` |

这 9 份文件均未修改、移动、删除、执行、测试、暂存、提交或部署。SQL 部署前、实现提交前及 Chrome 验收后的结束复核中，大小、mtime 与 SHA-256 均与上表完全一致；结束 SHA-256 即各自行“开始 SHA-256”。

## 3. Business-model expansion declaration

- 新业务表、业务列、状态、日期、身份、snapshot、可写事实、历史解释：`none`。
- 业务字段 authority、mutability、writer/reader precedence 变化：`none`。
- 新只读 authority：`public.school_get_profit_summary_schoolwide_v1(text,text)`，业务负责人在本阶段明确批准；学校整体、全部合法历史 entity、逐币种返回，金额与利润由 DB 聚合。
- 权限边界变化：四个 business entity Profile create/update overload 全部改为 owner-only；业务负责人在本阶段明确批准。
- destructive schema、历史修复、backfill、fallback、dual write：`none`。

## 4. 修改前可见依赖与逐页面收口

修改前依赖覆盖全局桌面/移动导航、首页快捷入口、业务归属管理页、学生、老师、课时/详情/批量/导入/PDF、工资规则/详情、工资/详情/生成/支付/导出、收入/详情、支出/详情、报销/详情、账户/流水/调拨/调整、月结/详情、支付/详情、利润汇总、兼职课时、classroom、weekly、schedule、quote、receipt、contract，以及 URL、缓存、空状态、tooltip、移动端标签。

完成结果：

- 全部用户页面移除业务归属筛选、选择器、列表列、详情行、徽章、tooltip、导出/PDF列、提示和导航入口。
- `business-entity.html` 仅保留 session guard 后跳转首页；列表、新增和编辑 DOM 已删除；`js/pages/business-entity-page.js` 删除，business entity API 仅保留内部读取。
- `auth-guard.js` 在认证后清除 `business_entity_id`、`businessEntityId`、`business_entity`、`businessEntity`，使用 `replaceState`，刷新与历史恢复不再重新启用旧筛选。
- 用户页面源码没有“业务归属”或“个人名义”字面；动态 `business_entity_name` 展示也已移除。兼职课时只显示独立的 `workplace_name`“授课地点”。
- 查询不强制 Aozora，历史 personal 行继续由月份、学生、老师、状态等原 reader 范围返回；只移除可见维度。
- 学校品牌只有在原本独立的文档/品牌语义中继续显示；未把 personal 事实解释成 Aozora。

## 5. 新建、编辑和内部范围

`js/utils/business-entity-policy.js` 是唯一前端 canonical resolver：精确查找唯一启用的 Aozora code；不存在或重复即 fail closed，不取第一条、不回退 personal、不硬编码生产 UUID。学生、老师、课时、工资规则、收入、支出和 School 账户等新业务调用该 resolver；writer 的 DB 校验继续是最终 authority。

编辑路径使用记录读取到的原始 `business_entity_id`：学生、老师默认归属、历史课时、工资规则、收入、支出、账户等不会因控件删除被置 NULL 或替换为 Aozora。复制/另存为新业务才走 canonical resolver。reimbursement 继续从被选支出集合继承唯一内部范围，账户匹配继续按原内部 ID。

页面层没有新增直接 `.rpc()`、insert、update、delete 或 upsert；写操作仍经 API/verified RPC。`js/legacy-core.js` 没有修改，浏览器没有 service-role。

## 6. 工资、学费、财务、PDF 与导出

- 工资仍以 `teacher + business_entity + month` 生成、锁定和阻断；候选 group、lock ID、detail、支付目标、Cash linkage 都保留内部 ID。UI 不按老师/月合并不同 snapshot，操作按钮仍绑定原 lock/request ID。
- B4 学生月份候选、lesson authoritative month、生成与支付 writer 参数没有改变；不改变工资金额、snapshot、状态或 Cash 目标。
- tuition preview、bill/revision/claim、月结 lock/adjustment、收入、支出、payment、account transaction、Cash request/linkage 均不改变。
- 普通 PDF、内部打印和工资 duty report 移除纯技术归属列；行数、record/snapshot 对应、金额、币种与总计逻辑不改。quote、receipt、contract 的独立学校发行/品牌字段保留，不用历史 entity 字段重写。
- CNY 与 JPY 始终分币种；前端仅格式化 DB 结果，不直接相加或重算权威金额。

## 7. 学校整体利润 reader

`school_get_profit_summary_schoolwide_v1(text,text)` 为 `STABLE SECURITY DEFINER`、固定 `search_path=pg_catalog, public` 的只读 JSONB reader；先验证 active admin/operator/read_only membership，不接收 business entity 参数，聚合全部合法历史范围，并按 currency 分组返回收入、支出、利润与 raw detail。页面仅切换 DB 已返回的币种结果，不从 raw 表重算或跨币种相加。

最小 ACL 为仅 authenticated EXECUTE；PUBLIC、anon、service_role 无 EXECUTE。原 business entity reader/RLS 没有放宽。

## 8. Profile RPC 最终 ACL

全仓库运行时消费者已清零。四个 Profile create/update overload 保留函数定义、postgres owner、SECURITY DEFINER 与固定 search_path，但 PUBLIC、anon、authenticated、service_role 均无 EXECUTE；catalog postdeploy 显示 ACL 均仅 `{postgres=X/postgres}`。生产没有调用任何 Profile writer，`school_business_entities` 两条主数据未写。

## 9. SQL 执行、测试与生产对账

本阶段只按明确路径执行以下 BE-UI SQL，未使用目录 glob：

1. `sql/current/school_business_entity_ui_closure_baseline_readonly_20260806.sql`（School，部署前/后只读）
2. `sql/current/cash_business_entity_ui_closure_baseline_readonly_20260806.sql`（Cash，部署前/后只读）
3. `sql/current/school_business_entity_ui_closure_rollback_test_20260806.sql`（transaction 内创建 reader/ACL、断言后 ROLLBACK）
4. `sql/current/school_business_entity_ui_closure_deploy_20260806.sql`（唯一正式部署入口，显式包含本阶段 core；COMMIT）
5. `sql/current/school_business_entity_ui_closure_postdeploy_20260806.sql`（catalog、ACL、角色及只读 reader 对账）

实际生产部署 SQL 仅第 4 项；它应用 `school_business_entity_ui_closure_core_20260806.sql`。数据库持久写入仅函数定义/comment/ACL，生产业务 DML 为 0。rollback test PASS 并 ROLLBACK，未创建生产 fixture；没有调用业务 writer。

School 部署前后关键指纹完全一致：

| 对象 | 数量 | 指纹 |
|---|---:|---|
| business entities | 2 | `41d747d4c403f549c8bdf180ae93c65d` |
| lessons | 739 | `5f46b393a1d353aa1a7a1d68979947cb` |
| settlements | 18 | `481ffa7ed5173da852f0f28ce66c2e9b` |
| tuition bills | 22 | `e50673ac998ee2d84573a076a64d3d42` |
| bill lessons | 330 | `e3e2e0044c17864bc66c7e2861176c8b` |
| wage locks | 95 | `7bbe108d3ac73d4f21530793bf141bc6` |
| wage details | 556 | `6204dc666b3b8e0f64fac901ecf0686a` |
| income | 55 | `ccfb156a42068df78e98f2ce6693aac6` |
| expense | 47 | `34a7a32319d8e538ef7997e1ba59c9d4` |
| payment requests | 51 | `6ce63e69edfa19a020013634b686f5ce` |
| reimbursements | 4 | `2a79805d473f4ae787ca8475ef4d33ba` |
| accounts | 3 | `ac9fa3e0b92dde16dddfffff2c70c222` |
| account transactions | 187 | `00516a76f236d51406c82f37b0e468ee` |
| School/Cash linkage | 42 | `cf9f1f5e109bf91938e74a37d4017c68` |

personal 关键引用计数为 `142/11/2/42/77/463/29/9/43/30`，Aozora 为 `597/7/20/288/18/93/26/38/8/12`；有效工资重复范围为 0。两条已知异常学费链合并指纹为 `56745a8c13e441169d5c739dd250e18d`。所有值部署前后相同。

Cash 部署前后同样一致：external requests 42 / `39bed8915955b3fb8cbe6553928edc71`；CNY transactions 36 / `38b0e164d2a0b20ec149116002c4adc7`；JPY transactions 3 / `654485db35df0657c0bf7121d464baa3`；fixture residue 0。School 与 Cash 均没有业务行写入。

利润 postdeploy 对账按月、按币种比较学校整体 reader 与原逐实体结果，收入、支出、工资与利润一致；没有直接混加 CNY/JPY。

## 10. 静态 fixture 与回归

新增 `scripts/business-entity-ui-closure-static-test.mjs`，覆盖：用户 DOM/导航/详情/导出无归属、legacy URL 清除、唯一 Aozora fail-closed、新建与历史编辑边界、personal 历史查询保留、工资 snapshot 分离、学校整体 DB reader、币种隔离、Profile owner-only、page/API 边界和版本缓存。

通过的本阶段及相关回归包括：BE-UI、BE-P0 permission、cancellation、authoritative lesson month、batch refresh、billing week、expense P0、P0-G1 auth/Cash、planned aircon、settlement P0-B2/P0-F/trusted tool、student P0/B1/B4 lesson/B4 wage、tuition atomic/Cash hardening/P0-D/P0-E/P0-F/preview，以及全部修改 JS/MJS 的 `node --check` 和 `git diff --check`。

历史 `lesson-generation-closure-ui-test.mjs` 仍断言本阶段已退役的业务归属选择器，属于被 BE-UI fixture 取代的旧合同，不作为当前合同通过条件；未修改它来制造虚假通过。生产没有运行写 fixture。

## 11. 发布闭环

- 页面版本：`v10.5.12`，全入口缓存键 `be-ui-20260806-1`。
- BE-UI staged allowlist：实现提交前 `git diff --cached --name-status` 为 126 个明确路径，等于 `git show --name-status --format= 8581c25` 的完整集合；范围仅为根页面、`js/` 页面/API/工具、`docs/module-status-dashboard.html`、本报告、BE-UI fixture 与 6 个明确 BE-UI SQL。cached diff 对 6 份原保护文件和 3 份外来课时 writer 草案均为零命中。
- 实现 commit：`8581c25ca6c5b3f63a8246b9021891d90ec0fd8c`（`feat: close business entity UI surface`）。
- 实现 Pages run：`31087116543`，build/deploy success。
- Chrome active-admin 桌面验收：列表与详情覆盖 index/payment、学生、老师、课时、工资规则、工资、收入、支出、报销、账户、月结、profit summary、兼职、教室、weekly，以及 lesson/wage/income/expense/reimbursement/account transaction/settlement/payment detail；全部 `v10.5.12`，无归属字段、无“个人名义”、无旧入口、无横向溢出。
- 真实 personal 样本：课时 `dc06b98c-360f-4661-a294-52ecb82830a7` 在 2026-11 + 学生过滤下仍可查询，工资 lock `a9b44041-673e-498d-bfa2-c6d24f2a9c91` 在 2026-06 仍可查询；两个详情均未显示归属名称，也未被显示为 Aozora。
- 旧参数：四种 legacy 参数均由 URL 删除；旧 `business-entity.html` 经认证后跳转 `index.html`，无业务归属 DOM 或链接。
- 390×844：12 个核心列表/详情、展开后的 5 组移动导航、lesson PDF 弹窗、工资导出按钮、quote/contract/receipt/weekly image/兼职年度页均无归属文本、空列或横向溢出；测试后恢复默认视口。
- Chrome 网络：对工资、收入、支出、账户、月结、支付与利润页分别建立独立 CDP cursor，均 `truncated=false`；非 GET 仅为 membership 及 `school_get_*`、`school_list_*`、`school_preview_*` 只读 RPC，写型 RPC、Cash Edge、PATCH/PUT/DELETE 均为 0。Console error/warning 为 0。
- 最终 Gate：`enabled / blocked / enabled`；signup：`disable_signup=true`、`mailer_autoconfirm=false`。
- 文档验收 commit、最终 `HEAD`/`origin/main`、ahead/behind 与最终 Pages run 由发布本报告的后续文档提交产生，记录在最终任务交付中；它不改变页面、SQL 或生产验收结果。

## 12. 零变化确认

最终确认：business entity 主数据修改 0；personal 删除/停用/改名/合并 0；历史 `business_entity_id` 改写 0；生产业务 DML 0；Profile writer 生产调用 0；学生、老师、课时修改 0；工资规则/锁/明细/支付修改 0；学费/月结/收入/支出修改 0；School 账户/Cash/claim 修改 0；Storage 修改 0；两条异常学费链修改 0；Gate 变化 0；signup 变化 0；六份受保护文件变化 0；三份外来草案变化 0。

没有未验证的 BE-UI 业务或页面范围。唯一仓库级提示是 GitHub Pages build 使用的 action 收到 Node.js 20 deprecated 警告，但 run 成功且不影响页面；后续可独立升级 action runtime。
