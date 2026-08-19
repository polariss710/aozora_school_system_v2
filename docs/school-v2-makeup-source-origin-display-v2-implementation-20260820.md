# School V2 待补来源日期语义 V2 实施报告（2026-08-20）

## 结论

“登记待补课完成”Dialog 已切换到只读 `school_list_open_lesson_credit_sources_v2`。候选业务身份、V1 的 17 个字段、排序、结算月和剩余课时保持不变；新增字段只决定来源日期文案。生产页面为 `v10.5.55`，Pages run `32271217654` 成功。

本轮没有调用任何真实课时 writer，没有写入、修正或补造课时、待补余额、工资、账单、结算或其他业务数据。数据库变更仅为新增一个只读函数及其 comment/ACL；V1 保留，可由前端恢复调用 V1 回滚。

## 基线与工作区保护

- 初始 `HEAD`、`origin/main`：`2929a8fd69a9b3e434ab7cee0f1b3e7a226da879`；ahead/behind `0/0`。
- 初始 tracked/staged：0；存在 21 个其他任务所有的 untracked 文件。
- 初始 Pages：`v10.5.54`。
- School/Cash 并行任务没有 tracked/staged 修改；21 个 untracked 文件全程未执行、修改、移动、删除或暂存。
- 实施提交：`b0e16c22fa68906069b9afc196055bed740373e1`。

21 个受保护文件的初始、部署后 SHA-256 逐项一致：

```text
75474786ac2de0d9881be17b298acf51b1ad68099b6c1f88c7b0d7aac1736a47  docs/school-v1-decommission-p1-b2a-session-service-worker-readonly-design-20260810.md
fd703860ef2bb5ca5e159f14b0ef138ddad765c9025960aab40c245e901aec0e  docs/school-v1-decommission-p1-ca-archive-restore-observation-readonly-design-20260810.md
1047c2d686a43499e21a43055973475aeb0d52a9fd36c0604aa98ce8ebf0c519  docs/school-v1-decommission-preflight-p1a-online-evidence-20260809.md
3e65e0091e68cd419ac13f0e692fcce99f07041abfcdab3b8786e526a800fcaa  docs/school-v1-decommission-readonly-investigation-20260809.md
272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432  docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv
d77a967b4aea7e82bc2ada248f700082749c0a38c0cfa6319eb2ae834932b9ed  docs/school-v2-lesson-clearance-package-isolation-phase2c-a-local-design-validation-20260817.md
f7947c070040b60f5fbb5148cc8333b5a9fd560205793ee7c6ddd970157a4ee0  docs/school-v2-lesson-clearance-phase2c-b-local-ui-validation-20260817.md
5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093  docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt
1f6f2cc50cb07f55e12d27163f453342baa56fc5e49ef7a6a4df79a041028903  favicon.ico
7afada926f82fddeb5ad843c47bb1ab6939620c3887c5e2fa507c54d87b8b27d  local/phase2c-b/index.html
bd005199686f28dcd3e4b25fab9cf7eea2a92641ae3814b00a8fd971b442e7da  local/phase2c-b/phase2c-b-api-contract.mjs
b29d1906d90e232dffc668a2232991740e52f16106b8130dfd35e6d652320ccf  local/phase2c-b/phase2c-b-mock-adapter.mjs
49a69b4f6369c6592f6960f0b47c3fb9358657aafcb2fc0a45eeaaa034f8fe38  local/phase2c-b/phase2c-b-page.mjs
dfe58c7b0876ac4a7079669d12e2c87ce00621554d23a435622fc8c63caee07a  local/phase2c-b/phase2c-b-state.mjs
b8904ebd8feb33c1e3598450936d930551d75d5ea0bc88a7673c0b9c1fab7fd6  local/phase2c-b/phase2c-b.css
47d555808b980dbc486764e153ec076f09f06d84b43dced0608fcc8502b793ff  scripts/school-lesson-clearance-phase2c-b-static-test-20260817.mjs
88f28e9e00980bb179a5faf8d8253f0f2dac2c2a1a84e32423b04dd9616264ae  scripts/school-lesson-clearance-phase2c-b-ui-state-test-20260817.mjs
b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54  sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql
5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a  sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql
b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773  sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql
7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b  sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql
```

## 数据库实现与安全边界

新增 `sql/current/school_open_lesson_credit_sources_v2_origin_display_20260820.sql`，未修改旧迁移或 V1。V2 完整复用 V1 候选，再聚合有效 causal actual；0、1、多条显式分类，不含 `LIMIT 1` 或 `FETCH FIRST`。

新增返回字段：

- `origin_display_kind`
- `origin_actual_lesson_id`
- `origin_display_date`
- `origin_display_start_time`
- `origin_display_end_time`
- `origin_display_selectable`

生产安全属性：

| 对象 | owner | SECURITY DEFINER | volatility | search_path | EXECUTE ACL | MD5 |
| --- | --- | --- | --- | --- | --- | --- |
| V1 reader | postgres | 是 | STABLE | `pg_catalog, public` | postgres, anon, authenticated, service_role | `bbbc1eff71bc3f8f3ad468e8543537e8` |
| V2 reader | postgres | 是 | STABLE | `pg_catalog, public` | postgres, authenticated | `28fe65d426d340331da90044ac9533bf` |
| canonical makeup writer | postgres | 是 | VOLATILE | `pg_catalog, public` | postgres, authenticated | `c0f9485be9783283db8c61c75473c43d` |

V2 首行调用 `school_assert_lesson_clearance_reader()`，只允许 active School membership 的 `admin/operator/read_only`；未向 PUBLIC、anon 或 service_role 开放，权限不比 V1 更宽。V1 定义、签名、ACL 和指纹未变；59 个现有 lesson writer 的定义/ACL 部署前后聚合比较一致，canonical makeup writer 指纹亦未变。

## V1 / V2 生产对比

参数：`2024-01` 至 `2026-08`，目标月 `2026-08`。

- V1 候选 22，V2 候选 22。
- planned ID 差集 0；顺序差异 0。
- V1 的 17 个返回字段逐行差异 0，故结算月、`remaining_hours`、planned 时间、同月/跨月规则均不变。
- fully consumed `37a2083e…`：V1/V2 均不出现。
- 当前歧义候选：0。

生产 kind 数量：

| kind | 数量 | 同月 | 跨月 | 已部分消费仍有余额 |
| --- | ---: | ---: | ---: | ---: |
| `cancelled_original` | 8 | 7 | 1 | 0 |
| `partial_planned_original` | 1 | 0 | 1 | 1 |
| `partial_actual` | 2 | 1 | 1 | 2 |
| `week_fallback` | 11 | 0 | 11 | 0 |
| `ambiguous` | 0 | 0 | 0 | 0 |

代表数据：

- cancelled `67477810…`：`原定 2026/08/20 16:00–18:00`，剩余 2 小时。
- partial planned `c770d6fe…`：`原定 2026/07/29 16:30–18:30`，剩余 1 小时；未错误显示 partial actual 的 `17:30–18:30`。
- partial actual `9bdb88c1…`：`部分完成日 2026/08/18 17:30–19:15`，剩余 0.25 小时；planned 开始/结束仍为空，显示 actual 没有进入预填。
- week fallback `28fa9db8…`：`对应周 2026/07/06`，剩余 2 小时。

## 前端合同

- `lesson-api.js` 仅把 reader 切到 V2，并映射六个 display 字段。
- `makeup-source-origin-display.js` 统一五种 kind 文案；未知 kind 与 `ambiguous` 均 fail closed。
- option 与来源摘要使用 display 字段；`ambiguous` 可见但 disabled，并显示“来源日期需核对”。
- `fillCreateCrossMonthMakeupActualFromSource()` 仍读取原有 planned `start_time/end_time`。
- submit 仍发送 `source.id` 作为 `plannedLessonId`；`origin_actual_lesson_id` 不进入 payload。
- writer 名称、确认 Dialog、二次确认、API writer 与 RPC 全部未改。

## 测试与生产验收

数据库：同一最终 SQL 先 `ROLLBACK` 演练后 `COMMIT` 部署；两次均通过 22/22 集合、17 字段、顺序、kind、`c770d6fe…`、fully consumed 排除、歧义 0、ACL、membership guard、V1/writer 指纹断言。部署前后核心业务表 count/hash 逐表一致：lesson 779、settlement 18、tuition bill 22、wage detail 624、wage lock 104。

前端：新五 kind/unknown fail-closed 静态测试、语法检查和 16 项既有 lesson 回归全部通过，覆盖 disabled、planned ID payload、display actual ID 排除、planned 预填、版本/cache 与无直接 page `.rpc()`。

Chrome 生产只读验收：

- 页面 `v10.5.55`，22 条来源；四类当前存在文案与来源摘要均正确。
- `c770d6fe…` option、摘要和 planned 预填均为 `2026/07/29 16:30–18:30`。
- 打开、切换候选、刷新全过程，CDP 只观察到 V2 reader 2 次，课时 writer 0 次。
- Console error 0、warning 0。
- 桌面根页面 `2560/2560px`；390px 根页面、body 均 `390/390px`，Dialog panel 位于 `12–378px`，无新增页面级横向溢出。
- 未提交表单、未创建测试课时或待补数据，也未为已补完的孙陈锋 2026/08/12 来源重新制造余额。

## 实际修改文件

- `sql/current/school_open_lesson_credit_sources_v2_origin_display_20260820.sql`
- `js/api/lesson-api.js`
- `js/config.js`
- `js/lesson-app.js`
- `js/pages/lesson-page.js`
- `js/utils/makeup-source-origin-display.js`
- `lesson.html`
- `scripts/lesson-makeup-source-origin-display-test-20260820.mjs`
- `scripts/lesson-cancellation-hardening-ui-test.mjs`
- `scripts/lesson-filter-layout-static-test.mjs`
- `scripts/lesson-makeup-clearance-copy-static-test-20260818.mjs`
- `scripts/makeup-actual-correction-static-test.mjs`
- `scripts/planned-aircon-ui-test.mjs`
- `scripts/tuition-p0f-lesson-read-failure-static-test.mjs`
- `docs/school-v2-makeup-source-origin-display-v2-implementation-20260820.md`
- `docs/current-status.md`

月结过期但未登记 actual/cancelled 的 planned 检查未调查、未实施，继续保留为 9 月初月度结算页面开放任务。
