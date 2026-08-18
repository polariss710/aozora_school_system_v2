# School V2 Phase 2C-D2-A1 最终清偿确认 Dialog 业务说明

日期：2026-08-18

生产版本：`v10.5.50`

实现提交：`0075a494b9949a145e4973d4e16dc21c13651c9a`

Pages run：`32086294317`（success）

## 结论

Phase 2C-D2-A1已完成。最终确认Dialog现在显示与当前有效Preview绑定的完整业务说明；生产只执行候选reader、一次`school_preview_lesson_clearance_v2`及Dialog打开/关闭，未点击最终清偿或撤销按钮，create/reversal writer请求均为0。

## 根因与最小修复

根因是`openCreateFinalDialog()`原有事实列表只显示Preview返回事实、request identity和manifest，没有持有或渲染本次实际发送给DB的标准化业务说明。直接读取`state.selection.businessNote`会把Preview之后的可变表单值带入最终确认，不能证明Dialog与有效Preview属于同一输入。

最小修复包括：

- `LessonClearanceWorkspaceState.selection`新增仅内存`previewInputSnapshot`；不写入localStorage、sessionStorage或URL。
- Preview成功时，`acceptPreview(preview, payload)`保存实际发送payload及返回manifest；快照包含request identity、manifest、两个source UUID、分钟、日期、业务说明、偏离原因、财务处理和确认项。
- source、分钟、日期、类型、原因、业务说明或确认项变化时，旧Preview、binding和快照立即清空，request identity按既有规则轮换。
- `prepareValidationMessage()`同时验证当前表单、快照、binding、Preview identity及manifest；快照或说明缺失时返回`业务说明缺失，请重新预览`。
- `writerRequest()`只复制快照字段，不再从可变表单重建请求。
- Dialog的业务说明节点以`textContent`赋值；没有把用户输入拼入`innerHTML`。
- 局部CSS只处理标签区分、自动换行和横向收缩，没有固定高度或截断。

RPC签名、Preview/writer/manifest/idempotency合同、数据库对象、其他业务模块和reversal流程均未修改。

## 快照生命周期

`previewInputSnapshot`在页面内存中的生命周期为：

1. 选择source和填写输入时不存在。
2. `previewRequest()`产生标准化payload；业务说明执行前后空格trim，空白说明在API前拒绝。
3. DB Preview成功且identity、source、分钟、日期、指纹及manifest全部匹配时，冻结保存payload和manifest。
4. 最终Dialog和潜在writer请求只读取快照。
5. 任一Preview输入变化、Preview失败、重新加载数据、切换角色或清空选择时销毁快照。

## 本地测试

- 状态机：PASS。覆盖首次显示、快照来源、说明变化失效、identity/manifest轮换、缺失快照、空白Gate、trim一致、read_only拒绝及reversal回归。
- 静态边界：PASS。页面直接RPC 0、表级DML 0；API仍只有既有两个writer RPC；无SQL改动。
- Chrome Mock：PASS。覆盖重新Preview、HTML/脚本纯文本、最终按钮唯一writer路径、打开/关闭writer 0、网络不确定、稳定业务错误、重复点击、reversal及角色合同。
- JavaScript `node --check`：PASS。
- `git diff --check`：PASS。
- 1440/1024/768/390：document/dialog/panel/note横向溢出均0，按钮区存在，390px正文区可滚动。

注入用例包含`<script>`、HTML标签、单双引号和换行；Dialog `textContent`与输入逐字符一致，DOM内没有生成`script`或`b`节点，脚本未执行。

## 生产只读验收

输入：

- pending：`8870f57f-bca5-4114-90db-ee592cca2f45`
- overage：`e58457a1-89c5-441b-9bcb-73ffc6168d8a`
- 分钟：60
- 日期：`2026-08-18`
- 业务说明：`同一自然周课时差额清偿：2026-08-11超额1小时清偿2026-08-14部分履约不足1小时。`

新绑定：

- request identity：`a58ed106-bb70-49f6-9743-a2725aa74427`
- manifest：`0d586b51bd6ce1c780f78f633961bbf2217642f85d22383608345b057ae5daa0`
- 旧identity和旧manifest均未复用。

DB权威Preview为pending `60→0`、overage `60→0`、JPY `-9,000/+9,000/net 0`、same teacher/subject、FIFO推荐对象、无偏离、无锁、无forward、actor blocker无、`reservation_created=false`。Dialog显示identity/manifest前缀和完整业务说明。Chrome网络事件只有1个POST到`school_preview_lesson_clearance_v2`；`school_create_lesson_clearance`和`school_reverse_lesson_clearance`均为0。Console warning/error为0。

生产截图保存在本次验收临时目录：

- `/private/tmp/phase2c-d2a1-final-dialog-1440-20260818.png`
- `/private/tmp/phase2c-d2a1-final-dialog-390-20260818.png`

390px底部截图同时显示完整业务说明、审计警告、返回核对和最终按钮；最终按钮未点击。

## 生产数据复核

仓库既有School/Cash指纹脚本均以`BEGIN TRANSACTION READ ONLY`开始并以`ROLLBACK`结束：

- Clearance主表/明细表：`0/0`
- History：页面authenticated reader为0；主/明细0与之相符
- pending汇总：21源/2400分钟；目标pending Preview前60分钟
- overage汇总：4源/135分钟；目标overage Preview前60分钟
- P002：`1200/0/1200`
- School fingerprints：lessons `772/9b393f82...`、settlements `18/481ffa7e...`、claims `2/fbce3906...`、bills `22/e50673ac...`、bill_lessons `330/e3e2e004...`、revisions `20/ffdc498a...`、income `56/5410e667...`、cash_linkages `44/f1c336c4...`、wage_locks `104/bb9d5e02...`、wage_details `624/b68ada9b...`、package `1/8c2b70b0...`、Storage `57/62fac552...`、Gate `3/b04952a0...`，均与基线一致。
- Cash fingerprints：CNY `75/b5d8b7d4...`、requests `44/1fc51497...`、Storage `0/d41d8cd9...`，均与基线一致。

额外直接History reader SQL在只读事务中被actor Gate以`LESSON_CLEARANCE_AUTH_REQUIRED`拒绝；没有伪造JWT或绕过角色合同，事务未产生数据变化。History与目标source余额采用已认证生产页面reader/Preview核对。

## Git与受保护文件

实现提交已推送到`origin/main`。实现提交后HEAD与origin/main均为`0075a494b9949a145e4973d4e16dc21c13651c9a`；本报告另作docs-only提交。原有20个受保护untracked文件逐文件SHA-256均与阶段开始记录一致，当前有序哈希清单摘要为`a5d96124b4d6358bddf5665fa341fc419c356a4940240913a818a2153bf9ec45`；没有把这些文件加入暂存区或提交。

本阶段在此停止，等待业务负责人亲自执行首笔真实清偿。
