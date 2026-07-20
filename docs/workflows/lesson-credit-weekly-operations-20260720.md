# 课时余额与周运营工作流

## 业务口径

- 正式预定课时是学生学费上限和履约来源；月中新增正式预定课时才增加学生学费。
- 取消课、待补课和部分完成的剩余时长均为已收未履约的课时余额；不退款、不新增学费，可跨月保留。
- 补课 actual 不计学生学费；老师工资只按实际完成的老师、科目、日期和时长结算。
- 补课可更换老师、科目和内容，但学生与业务归属必须保持原预定来源一致。

## 数据模型

- 不新增余额主表：余额来源固定为 `school_lesson_records` 的 active planned 行。
- 一个 planned 的权威剩余小时为：`planned.duration_hours - sum(linked actual.duration_hours)`，其中只累计 `completed` / `makeup_completed`；`cancelled` 为 0。
- 新写入不得让累计完成时长超过预定时长；历史超额或多 actual 关联只读兼容，不自动修复。
- 部分完成会生成一条 `completed actual` 并把来源 planned 标为 `pending_makeup`；取消会生成 `cancelled actual` 并同样标记来源为 `pending_makeup`。
- 补课完成会生成 `makeup_completed actual`，`is_billable = false`、`lesson_fee = 0`，允许选择有效老师与科目，且 `teacher_settlement_month` 取补课实际日期月份；来源余额消耗完后 planned 标记为 `makeup_completed`。

## 学生结算

- 学费通知已按 planned 课时生成；本阶段不新建学费收入或账单。
- 未锁定学生月结的应收差额改由 planned 课时费（加结转、减已收）计算；actual 课时费保留为履约展示指标，不用于把取消/补课变成退款或追加收费。
- 已锁定历史结算不回写；未来锁定及合法 unlock/relock 使用新口径。

## 周运营视图

- 课时管理新增周一开始的周筛选，首周允许周一落在上月，以覆盖当月 1 日所在自然周。
- 新增 Beta 本周课时待处理，只读返回每位在籍学生本周预定、已登记、待登记、取消、待补与全部未履约余额，并可深链至课时管理。
- 统计与余额均由 School DB read RPC 返回；页面不计算或保存业务事实。

## 周课表图片联动

- 周课表页面支持 `week_start`、`student_id`、`auto_preview=1` URL 参数。
- 课时管理在选定单学生和单周时可一键跳转并生成该学生的周课表预览。
- 图片旁显示可编辑的课程清单；每项直达课时详情并自动打开既有编辑弹窗。下载的 PNG 保持纯图片。

## 保护与验收

- 所有新课时写入经专用 security-definer RPC；页面只能调用 API wrapper。
- 部分完成/取消会改动来源 planned，因此受来源学生结算锁保护；补课可消化已锁定月份留下的余额，只受补课实际日期所在学生结算锁及目标老师工资锁保护。老师/科目/业务归属有效性、时长余额和 optimistic/update guard 均在 DB 端验证。
- 不自动修改历史真实课时、结算、工资、账单、收入、Cash 或账户流水。
- 回滚与 commit 测试仅使用明确 `codex-test` 白名单数据；正式 SQL 不写任何真实业务数据。
