# School V2 P0-G1-B1 Active Admin Cash 写入链与 Gate 验收

日期：2026-08-04

生产版本：`v10.5.1`

School项目：`xlcdqvlfzspcxdoidsrr`

## 结论

P0-C首次生成匿名record返回已按窄合同修复并完成最低充分验收；P0-G1-B1已部署Edge与Pages，Cash提交权限由School当前active admin membership唯一决定。`student_tuition_cash_submit`已开启，`student_tuition_generate`继续blocked。本轮没有点击或调用任何真实Cash提交。

## P0-C窄修复

- 目标函数仍为`school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)`，原20列名称、顺序和类型不变。
- 唯一变更是首次生成分支由`return query select v_result.*`改为20个显式字段及原类型cast；base-core仍只调用一次，其他分支与业务合同未改。
- owner仍为postgres，仍为SECURITY DEFINER；search_path、volatility、parallel、cost、rows与仅postgres ACL均未变化。
- postdeploy原第59行错误修复为先`SELECT p.* INTO STRICT v_proc`，再单独赋值`v_definition:=pg_get_functiondef(v_proc.oid)`。
- synthetic首次生成成功返回1行/20列，无SQLSTATE 42809；identity、revision 1、bill、pending income与relation唯一一致。duplicate返回同一identity/revision/bill/income且不新增事实；stale manifest拒绝。
- fixture：student `c0c0…0001`；事务内lesson/bill/income/generation/revision仅用于验收并全部ROLLBACK，最终residue 0。
- 函数生产MD5：`95a68598215b61f55e5b63c74eeaa3f1`。

## Admin授权与Edge边界

```text
Browser School JWT
  -> Edge auth.getUser(token)
  -> same Bearer user-scoped school_require_current_app_admin()
  -> create server-only School/Cash service-role clients
  -> recheck active admin before School writer
  -> recheck active admin before Cash writer
```

- anon、无membership、inactive admin、operator、read_only均拒绝；仅active admin返回与JWT `sub`相同actor UUID。
- email、body user_id、body role和body membership均不参与授权。
- School/Cash owner writer对anon/authenticated仍无EXECUTE；membership表anon/authenticated/service_role DML仍为false。
- 学费提交必须带当前student/month/bill/active revision/currency/amount expected facts；Edge用最新user-scoped DB preflight比较，客户端不得传金额、币种、汇率或取整作为writer事实。
- 页面模块`.rpc()`为0，`js/legacy-core.js`零改动，浏览器service-role/secret marker为0；31入口session guard回归通过，signup页面入口仍不存在。

## 部署与生产验收

- Edge：Gate blocked时部署`request-cash-income-confirmation`到School项目成功；匿名空POST返回401。
- Pages：功能分支workflow artifact build成功，但受保护Pages environment不允许非main deploy；快进main后run `30843337884` build/deploy成功。
- blocked生产Chrome：`v10.5.1`、active admin、收入页12行、目标三条不可选择、批量提交disabled、Console 0 error/warning。
- enabled生产Chrome：三条目标pending income各显示“可提交 Cash”且checkbox可用；未勾选、未打开确认框、未调用提交，Console 0 error/warning。

## 生产事实终态

| 学生 | active revision | bill | income | CNY | status | School Cash linkage |
|---|---|---|---|---:|---|---:|
| 张倬闻 | `7d319b0d-…` | `013a7766-…` | `d980cedd-…` | 27,950.00 | pending | 0 |
| 彭宇晗 | `f7bbd000-…` | `a5cac133-…` | `648e264d-…` | 8,147.25 | pending | 0 |
| 李天伦 | `f7150ce5-…` | `66a1f276-…` | `efd670bc-…` | 9,240.00 | pending | 0 |

Cash Gate前后均为：request `39 / 303e10bc1a28a0abd8b27afd3929cfd8`；CNY `71 / d7e72182970de4ea8849c994b67e8dcc`；JPY `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`。

最终Gate：

- `student_tuition_preview = enabled`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = enabled`

真实Cash request/CNY/JPY新增均为0；月结、Void、Reissue页面writer未恢复。

## Git

- `edf3ab2`：P0-C显式返回窄修复。
- `dec2574`：postdeploy复合record接收和测试runner兼容修复。
- `e48d55b`：P0-G1-B1 active-admin Edge/API/UI/ACL/测试。
- `7c1d70e`：受控Cash Gate enable SQL。

以上提交均已进入`codex/p0-g1-b1-admin-cash`与`main`。六份受保护untracked文件未暂存、未修改。
