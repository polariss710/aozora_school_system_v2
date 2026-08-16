# School V2 补课完成日期常驻说明移除与字段对齐

日期：2026-08-16（Asia/Tokyo）

## 范围与修改

- 唯一实际渲染实例位于`lesson.html`的`#createCrossMonthMakeupActualDialog`，在`data-create-cross-month-makeup-field="lessonDate"`内，是日期input后的`<small class="field-hint">`。共删除1个。
- `lesson-detail.html`和`js/pages/lesson-page.js`动态模板中没有重复常驻实例；原节点无ID、无`aria-describedby`，因此没有悬空引用需要清理。
- dialog顶部“请在补课实际发生月份登记……”及补课月份、写入结果、计费summary全部保留。
- `.field-hint`仍被来源候选计数和其他页面使用，故保留通用CSS；没有专用目标CSS，也没有新增不可见占位、`min-height`或grid补偿。
- 版本升至`v10.5.46`，`lesson.html`、`lesson-detail.html`和lesson app/module缓存链更新为`makeup-date-hint-removal-20260816-1`。

## 动态校验合同

- 抽取纯函数`validateCrossMonthMakeupLessonDate(lessonDate, targetMonth)`，沿用原完整动态提示：`补课完成日期必须属于当前页面月份。若补课实际发生在其他月份，请先切换到实际发生月份，再在‘来源月份’中选择原待补课程所在月份。`
- 日期input/change会调用同一校验：跨月时复用现有dialog error并给日期field添加`is-invalid`；恢复本月日期后清除该字段错误和动态提示。
- submit路径仍在构造payload时执行同一校验，`payload=null`即return；`createCrossMonthMakeupCompletedActualFromPlanned(payload)`只位于通过之后。DB writer/guard及错误兜底映射未改。
- 生产输入`2026-07-31`时原值保持，不自动修改、截断或替换；恢复`2026-08-01`后错误消失。

## 布局测量

修复前生产`v10.5.45`：日期`top 473 / height 40`，状态`top 488 / height 55`，top差`-15px`；目标常驻hint为1。

修复后生产`v10.5.46`：

| 状态 | 日期input top/height | 状态控件 top/height | top差 | 横向溢出 |
| --- | ---: | ---: | ---: | ---: |
| 正常 | 473 / 40px | 473 / 40px | 0px | 0px |
| 月份错误 | 549 / 40px | 549 / 40px | 0px | 0px |
| 恢复合法 | 310 / 40px | 310 / 40px | 0px | 0px |
| 390px单列 | 662.5 / 44px | 740 / 44px | -77.5px（正常纵向排列） | document 0px / panel 0px |

错误状态的现有dialog error使内容自然向下扩展，但两个input始终40px且top差0；恢复时现有panel滚动上下文保留，两个控件仍同步对齐。390px两控件宽度均332px，无空白hint占位。

## 测试与生产验收

- HTML目标常驻文字实例0；`lesson-detail.html`及动态模板常驻实例0；通用`.field-hint`仍保留。
- 纯函数覆盖本月valid、跨月error、空值incomplete；跨月输入不被改写。
- JS语法、makeup静态合同、15分钟刻度、月份reader、刷新、课时operations/generation/cancellation、planned aircon、P0F reader及`git diff --check`全部通过。
- Chrome生产只进行了打开/关闭dialog、输入跨月日期、恢复合法日期和测量；没有选择来源或点击最终登记。
- CDP网络证据只有1个只读RPC：`school_list_open_lesson_credit_sources`；writer RPC为0。Console error/warning为0。

## 数据零变化

- 未创建或执行SQL migration，未调用业务writer，School/Cash业务写入0，测试白名单写入0。
- 部署前后School函数MD5、目标课时链、课时/settlement/bill/revision/income/Cash-link、工资、correction event、Storage及Gate完整指纹一致。
- Cash request/CNY/JPY/account及目标Cash请求/流水完整指纹一致。

实现提交：`6772bc6`。实现Pages run：`31932721238`，success。
