# School V2 私塾打工 PTW-P1-B1 筛选折叠状态统一

## 结论

PTW-P1-B1于2026-08-16完成生产上线。生产版本`v10.5.45`，实现commit `51ba379`，Pages run `31897286841`成功。相同URL和相同applied filters现在确定性产生相同的课时及工资折叠状态；reset合同、reader数量、API/RPC、结算月份来源和所有writer路径均未改。

## 原因与修复

修复前课时区域使用长期存活的`expandedWorkplaces`集合，具体私塾查询只执行`add`，不会清除上一次展开值；工资区域另由`collapsedWageWorkplaces`保存手工状态。查询、cold load、reload和`popstate`没有从applied filters统一重建两套集合，因此相同筛选会受操作历史影响。

新增纯状态函数`partTimeWorkCollapseStateFromFilters`，每次正式`loadPageData`在reader和render前依据applied `workplaceName`重建两套集合：全部筛选使课时展开集合为空、工资折叠集合包含全部私塾；具体私塾使课时仅包含目标、工资仅将目标从折叠集合移除。reset处理器不调用该函数、不触碰集合，也不load或render。

修改文件：

- `js/pages/part-time-work-page.js`
- `js/utils/part-time-work-filter-state.js`
- `scripts/part-time-work-filter-collapse-state-test.mjs`
- `js/config.js`
- `js/part-time-work-app.js`
- `part-time-work.html`

`js/api/part-time-work-api.js`保持原SHA-256 `476d5364e7f32ac00b2644e0285ccd3865debd9eff455e73d57cd57d84e524a9`。

## 状态矩阵

| 事件 / applied筛选 | 课时区域 | 工资区域 |
| --- | --- | --- |
| cold/reload/query：全部 | 全部折叠 | 全部折叠 |
| cold/reload/query：具体私塾 | 仅目标展开 | 仅目标展开 |
| 具体私塾＋工作内容 | 所属目标展开 | 所属目标展开 |
| 从具体私塾切换另一私塾并查询 | 旧目标折叠，新目标展开 | 旧目标折叠，新目标展开 |
| 手工展开后重新查询全部 | 全部折叠 | 全部折叠 |
| reset | 保持当前状态 | 保持当前状态 |
| back/forward | 由各自URL applied筛选重建 | 由各自URL applied筛选重建 |

reset仍只恢复控件、清除筛选校验并显示`已重置筛选条件`；生产验证结果DOM哈希、URL、scroll及折叠状态不变，Network请求0。随后查询才应用全部筛选、执行既有2次lesson reader和1次settlement reader并将两个区域全部折叠。

## 测试与生产Chrome

本地通过：专用折叠状态测试、P1-B筛选重置状态测试、P0-A2权限静态测试、课时时间网格前端回归、相关JS语法检查和`git diff --check`。专用测试覆盖全部、三个具体私塾、具体私塾＋工作内容、手工展开后查询重置，以及reset不得访问两套集合或render/load。

生产Chrome使用现有authenticated会话，仅操作查询、重置和展开/折叠：

- 默认全部、再次查询全部、手工展开后查询全部：lessons/wage均全部折叠；
- 诺应教育、致远教育查询：lessons/wage均仅展开目标；
- 诺应教育＋`骆德锋理数一对一`：两个区域仅诺应教育展开；
- 具体私塾展开后reset：状态保持、toast准确、lesson/wage DOM SHA-256均不变、URL与scroll不变、Network 0；
- reset后查询全部：两个区域全部折叠，网络仅3个既有reader，12个writer命中0；
- cold、reload、back、forward均与各自URL一致；
- 390px下inner/body/root宽度`390/390/390`，filter/lessons/wage宽度`372/346/346`，无横向溢出；Console warning/error 0。

## 零业务变化

本阶段未执行migration、DDL、DML或写RPC。最终仅执行P0 postdeploy、School基线和Cash基线三份显式READ ONLY/ROLLBACK SQL进行复核。

School五表继续保持：收入56 / `5410e66708a01d7017de7dc331d32674`；旧请求1 / `3911bf3d82fba1b2f825c5510af0feb9`；课时651 / `56047b966a14e46bcc9fada5fe2e7fea`；结算明细289 / `7fb549166e78b2f7e09dcbfd85a6aac5`；结算28 / `ef867ba66009e1ae602b58717f90e99a`。最近课时及结算更新时间仍为`2026-08-15 07:39:17.169072+00`与`2026-08-12 12:12:07.364663+00`。

Storage保持57对象、6,936,405 bytes、MD5 `62fac5521274c58c6f6982a0c690c134`；Gate保持3行、MD5 `b04952a0603194dd5592124bdee2f7d7`和`enabled / blocked / enabled`；Cash的School范围request/CNY/JPY保持44/38/3、MD5 `635bbfe049d06ffd1bbf88500d8ef2d1 / b93aa52d1030a922811fdeef8d087e01 / 654485db35df0657c0bf7121d464baa3`，旧引用0。11份受保护untracked文件路径和SHA-256逐项保持不变。
