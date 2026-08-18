# School V2 Phase 2C-D2-A3：首笔清偿审计、必填标识与成功后自动关闭

日期：2026-08-18
生产版本：`v10.5.52`
实现提交：`f327c20c3f353cab40759780466ed9fed90872f5`
Pages run：`32105569205`（success）

## 1. 范围与Gate

- Business-model expansion declaration：新表、字段、状态、writer、reader优先级、ACL/RLS、业务语义均为`none`。
- 本阶段只修改前端状态收敛、必填表达、测试、版本和文档；clearance API/RPC、数据库函数、schema、RLS、ACL、membership及业务计算均未修改。
- 生产数据库调查和结束复核全部位于`REPEATABLE READ READ ONLY`事务并`ROLLBACK`。
- 本阶段生产create/reversal writer调用均为0；没有执行第二笔Preview。

## 2. 首笔真实清偿唯一事实

该写入由业务负责人在本阶段开始前完成。本阶段只读审计确认：

| 事实 | 生产权威值 |
|---|---|
| clearance header | `cbf5e5f9-8397-4bea-8297-e66a3ebdb32b` |
| clearance detail | `3fdfd160-8c73-4a7d-8a5c-49d03b3306e3` |
| 学生 | 袁振轩 / `4c6f1473-7d44-467d-a70b-30f02e7cf8cd` |
| 待补对象 | `8870f57f-bca5-4114-90db-ee592cca2f45` |
| partial actual | `2da1ec9a-6f19-49af-a9bd-48984a255aa9`，运营显示日`2026-08-14` |
| 超额actual | `e58457a1-89c5-441b-9bcb-73ffc6168d8a`，日期`2026-08-11` |
| 类型 / 日期 | `overtime_offset` / `2026-08-18` |
| 分钟 | 60 |
| 金额 | pending `-JPY 9,000` / overage `+JPY 9,000` / net `JPY 0` |
| FIFO | 推荐对象与实际对象一致，未偏离 |
| 老师 / 科目 | 均一致 |
| locked / forward | 无 / 无，financial month为NULL |
| actor | `25331ae9-3412-48b9-bdc3-e516caeaeba4` / `admin` |
| 创建时间 | `2026-08-18 05:12:52.408595+00`（JST 14:12:52） |
| request identity / idempotency key | `dea5d4d5-ca96-490d-ac48-f1074eadf1d5` |
| persisted input manifest | `5c578d148105adfaa31470ea6fa4dbeb9aebfffb4ed38e56aa32e4ffcc3b7c40` |
| 业务说明 | `首次课时清偿测试` |

正式header保存的manifest由数据库输入重新计算后仍为同一SHA-256。History V2在authenticated admin上下文唯一返回上述记录，`is_effective=true`、`is_reversed=false`、request identity、来源、分钟、日期、说明和manifest全部闭合。

审计同时确认：header 1行、detail 1行；重复header 0、重复detail 0、reversal 0。

### 与此前只读Preview的区别

此前验收Preview的request identity为`9a13559f-4ec9-49a3-8ffe-f9df0daea1b4`、manifest为`c752fe8add92ea9123d1c9e178e2e3101edb384fe069cd09ed04e40ed0071eae`，说明为长文本。正式写入没有沿用该Preview身份，而是使用上表新的identity、manifest和说明。正式记录内部证据唯一且自洽；本报告不把旧Preview身份误报为正式写入身份，也未回写说明。

## 3. 余额、来源与外围不变量

- 目标待补余额：`60 → 0`；目标超额余额：`60 → 0`。
- dashboard权威可分配汇总：pending `2400 → 2340`分钟、候选`21 → 20`；overage `135 → 75`分钟、候选`4 → 3`；History `0 → 1`。
- V3原始集合仍保留gross证据：pending 21行/2460分钟，其中active claim 120分钟，当前可分配2340；overage 4行/90分钟，其中active claim 15分钟，当前可分配75。零余额目标不再进入候选。
- planned、partial actual和overage actual整行MD5仍分别为`dce7c9c99e8e1f7bdb09c80fe0b9e958`、`09c20f056b66c872ca63da98454bdcc4`、`056696397aae3d1f1701dc0ef974e928`，与清偿前Preview证据一致，原课时行未改写。
- P002保持`1200 / 0 / 1200`分钟，未进入普通清偿。

袁振轩2026-08 raw settlement Preview当前返回：已登记待补6小时/JPY54,000、已登记超额0、已登记净差额为待补6小时/JPY54,000、unresolved planned 6。`registered_overage_included_in_system_difference=false`，但raw `system_difference_cny`及projected final carryover仍为`+CNY373.50`，没有按任务中的“预计方向”消失。本阶段以raw返回为准记录该差异，没有修改settlement计算、保存或锁定任何月结；如需收敛该派生表达，应另立只读调查/修复任务。

结束只读指纹与开始审计完全一致：

- School：lessons `772/9b393f82…`、settlements `18/481ffa7e…`、claims `2/fbce3906…`、clearance `1/b1877269…`、detail `1/f7c62616…`、bills `22/e50673ac…`、bill lessons `330/e3e2e004…`、revisions `20/ffdc498a…`、income `56/5410e667…`、Cash linkages `44/f1c336c4…`、wage locks/details `104/bb9d5e02…` / `624/b68ada9b…`、package `1/8c2b70b0…`、Storage `57/62fac552…`、Gate `3/b04952a0…`。
- Cash：CNY `75/b5d8b7d4…`、JPY `34/0dd45c68…`、requests `44/1fc51497…`、accounts `7/89b057e2…`、Storage `0/d41d8cd9…`。
- School/Cash相关开放事务均为0。

本阶段没有lesson、makeup actual、wage、settlement、bill、revision、income、Cash、variance claim、Storage或Gate持久写入。

## 4. 前端修改

五个无条件必填字段复用项目既有`.required-mark`红色样式，并补齐明确`label for`：

1. 选择待补对象
2. 选择可用超额
3. 本次清偿分钟
4. 清偿日期
5. 业务说明

筛选字段和条件性偏离原因未被误标为无条件必填。原中文校验、Preview与writer合同均保留。

清偿流程仍为三次关键点击：DB权威Preview → 核对并准备清偿 → 最终确认清偿。状态收敛如下：

| 结果 | 最终Dialog | 外层Dialog | Preview/identity | writer | 后续动作 |
|---|---|---|---|---:|---|
| 新建明确成功 | 关闭 | 关闭 | 清除可提交状态 | 1 | 现有主课时reader链刷新1次，提示`课时差额清偿成功：60分钟。` |
| 幂等成功且History精确一致 | 关闭 | 关闭 | 清除可提交状态 | 不重试 | 只读History确认后按成功处理 |
| 幂等身份/来源/分钟/说明不一致 | 保持并禁用 | 保持 | 冻结 | 不重试 | `系统无法确认幂等结果与当前核对一致，请勿重复提交。` |
| 网络结果不确定 | 保持并禁用 | 保持 | 冻结 | 不重试 | 仅查询History；提示`清偿结果正在确认，请勿重复提交。` |
| DB明确拒绝 | 关闭 | 保持 | 失效并轮换identity，输入保留 | 1次失败调用 | 回到可修正、重新Preview状态，显示中文原因 |
| 写入成功、主页面刷新失败 | 关闭 | 关闭 | 清除 | 不重试 | 提示`清偿已成功，但页面刷新失败，请重新查询。` |

重新打开工作台会重新执行六个正式reader，不恢复旧Preview、manifest、identity或snapshot。reversal路径未改。

## 5. 测试与生产验收

通过：

- JavaScript语法检查、A3 static/state、D2-A2业务UI state/static、D2A submit state/static。
- 本地Mock Chrome完整状态矩阵：正常成功、快速双击、精确幂等、幂等不一致、网络成功确认、网络未确认、DB拒绝、主页面刷新失败、重开重新读库；create最多1次，reversal 0。
- 1440/1024/768/390布局与Dialog滚动；全部横向溢出0。
- lesson筛选布局、15分钟刻度、权威月份刷新、月结筛选、Phase2C-C/R1/R2 reader合同和D2-A2运营日期回归。
- `git diff --check`。

生产Chrome：

- 页头显示`v10.5.52`；五个必填标识均为`rgb(185, 28, 28)`且关联正确ID。
- 清偿History主区域只显示业务事实，系统详情默认折叠；唯一60分钟记录可见。
- 默认2560px及390×844下page/dialog/panel横向溢出均0；390px五个字段均为302px单列。
- Console error/warning为0。
- 捕获到工作台六个RPC：pending V3、overage V2、package V2、cross-month V2、dashboard V1、history V2，均为reader；Preview/create/reversal均0。
- 未点击核对撤销、最终清偿或任何其他writer入口。

## 6. 修改文件与交付

- `js/components/lesson-clearance-workspace.js`
- `js/utils/lesson-clearance-state.js`
- `js/pages/lesson-page.js`
- `js/lesson-app.js`
- `js/config.js`
- `lesson.html`
- 3份A3专用测试及3份必要既有断言更新
- 本报告与`docs/current-status.md`

实现提交`f327c20c3f353cab40759780466ed9fed90872f5`已push至`origin/main`；Pages run `32105569205`成功。生产数据库部署、SQL定义修改及RPC部署均为0。

受保护untracked文件逐项SHA-256与起点一致；未修改、移动、执行、暂存或提交。
