# School V2 私塾打工 PTW-P1-B 筛选重置修复

## 结论

PTW-P0-A2权限封口通过并独立交付后，PTW-P1-B于2026-08-16完成。生产版本为`v10.5.44`，实现commit `02b2255`，Pages run `31896047497`成功。页面API文件保持原SHA-256 `476d5364e7f32ac00b2644e0285ccd3865debd9eff455e73d57cd57d84e524a9`，RPC签名、编辑/删除/复制/生成实际的record ID路径、数据库函数及工资计算均未改。

## 状态机前后

| 事件 | 修复前 | 修复后 |
| --- | --- | --- |
| 年月change | 立即`replaceState`并改月度导航 | 只改draft控件；URL、reader、results render均为0 |
| 打工先change | 改依赖下拉 | 仍只改draft依赖下拉，并清除筛选校验状态 |
| 重置 | 控件归默认后立即apply并执行3个reader、课时/工资render、URL更新 | 仅将年月恢复当前月、清空打工先/工作内容、重建依赖下拉、清除校验并显示`已重置筛选条件` |
| 查询 | apply并读取，但URL只保存年月 | 唯一apply入口；push完整`year/month/workplace_name/class_description`，保留`view`和无关参数，再执行reader/render |
| cold/reload | 只恢复年月 | 恢复`view/year/month`及非默认打工先/工作内容 |
| back/forward | 无专用恢复 | `popstate`从当前URL恢复applied与draft，再读取并重绘 |

reset不修改`appliedFilters`、URL、`history.state`、课时/工资DOM、view、展开/折叠集合或scroll。未查询draft不会进入URL；只有查询后才成为applied。

## 结算月份安全

每个工资结算DOM行现在携带DB reader返回的`year_month`。锁定前同时比较：

1. 内存中的唯一reader结算行`year_month`；
2. 当前渲染行`data-settlement-year-month`；
3. 当前applied筛选月份。

三者必须都是严格`YYYY-MM`且完全一致，否则在API前抛出“结算月份缺失或与当前结果不一致”，writer调用0。lock payload不再读取年月select。无reader行、重复机构结算行、缺失/非法月份或渲染漂移均fail-closed；空结算行没有权威月份时锁定按钮禁用。收入确认摘要和导出文件名也不再回退读取draft年月。

## 专用测试与生产Chrome

`scripts/part-time-work-filter-reset-state-test.mjs`覆盖draft/applied、reset零副作用、URL cold/reload/back/forward、依赖筛选、DB结算月份与缺失/不一致fail-closed，并锁定API文件字节哈希。`part-time-work-p0-a2-permission-static-test.mjs`、`lesson-time-grid-frontend-test.mjs`、JS语法检查及`git diff --check`均通过。

生产Chrome使用现有authenticated会话、全程不接受写入确认：

- cold URL `view=settlement/year=2026/month=07/workplace_name=致远教育`正确恢复控件和DB结果行月份；
- draft月份改为08后，URL/history/scroll不变，新resource 0，RPC 0；
- reset后toast准确，课时DOM哈希`efb14f81`、工资DOM哈希`3f827302`均不变，URL/history/scroll/折叠不变，RPC 0；
- reset后点击查询才更新为2026-08，课时/工资DOM均变化，恰好调用2次lesson reader和1次settlement reader，writer 0；
- 非默认`诺应教育 / 骆德锋理数一对一`查询后URL完整编码，reload、back、forward均恢复对应控件并只调用reader；
- applied为2026-08时把draft改为2026-07但不查询，点击可见锁定按钮仅打开“确认锁定 诺应教育 2026-08…”对话框并立即取消，RPC 0；证明payload未读取draft；
- 390px下`innerWidth/bodyScrollWidth/rootScrollWidth=390/390/390`，筛选/课时/工资panel均372px，无横向溢出；Console warning/error 0。

全部浏览器网络事件中真实课时、结算、解锁、收入及Cash writer均为0。

## 零业务变化

P1前后5张业务表继续为：收入56 / 旧请求1 / PTW课时651 / 结算明细289 / 结算28，整行MD5依次保持`5410e667…`、`3911bf3d…`、`56047b96…`、`7fb54916…`、`ef867ba6…`。最近课时更新时间仍为`2026-08-15 07:39:17.169072+00`，最近结算更新时间仍为`2026-08-12 12:12:07.364663+00`。

Storage保持57对象、6,936,405 bytes、MD5 `62fac5521274c58c6f6982a0c690c134`；Gate保持3行、MD5 `b04952a0603194dd5592124bdee2f7d7`及`enabled / blocked / enabled`；Cash的School范围request/CNY/JPY保持44/38/3，MD5 `635bbfe0… / b93aa52d… / 654485db…`，fixture residue 0。11份受保护untracked文件SHA-256与P0/R1起点逐项一致，未修改、移动、执行、暂存或提交。

本阶段没有执行SQL文件或调用写RPC；数据库写入0、测试业务记录0、回滚0。任务在PTW-P1-B完成后停止。
