# School V2 P0-F 彭宇晗月结 Preview 与 Dialog 修复报告

日期：2026-08-03  
基线：`90555442d5ac8580e103df997c5f8a06d8b19e5a`  
实现提交：`56c77832a4730683f8d8976dfbce238d353194cc`（parent `90555442d5ac8580e103df997c5f8a06d8b19e5a`，已普通推送 `origin/main`）

## 结论

生产 DB 的 P0-F 财务净额公式本身正确。彭宇晗 2026-07 以显式汇率 `0.042` 只读预览时，DB 权威结果为：待补 2 小时、unused `-JPY17,000 / -CNY714.00`，actual overage 0.25 小时、`+JPY2,125 / +CNY89.25`，净额 `-1.75小时 / -JPY14,875 / -CNY624.75`，`carry_final_balance` 的 projected adjustment 为 CNY0、projected final carryover 为 `-CNY624.75`。

故障根因是旧 Dialog 摘要继续展示列表行的旧分离模式预览；切换 mode/rate/source/date 没有针对未保存表单调用完整的 DB 只读 preview。页面只有在真实 draft 保存后才可能看到 P0-F 状态，且旧异步响应存在覆盖新输入的风险。此次没有改动 P0-F 业务公式。

修复后，当前已保存状态与表单待提交 Preview 分成两张卡；输入变更立即使 preview 过期并禁用保存，只有完整 expected facts 与当前表单一致的 DB 响应才能重新启用保存。关闭 Dialog 不产生写入。

## 业务模型声明与权限

- 新表、业务列、状态、身份、业务日期、可写事实、锁定语义、fallback、dual write、历史解释：`none`。
- 获批变更仅为纯只读 reader `school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)`。
- 函数为 `SECURITY DEFINER`、固定 `search_path=pg_catalog,public`，函数体无 INSERT/UPDATE/DELETE/MERGE/TRUNCATE，调用既有 P0-F source reader 与 P0-B2 resolver，不调用 owner writer。
- EXECUTE 仅为 `anon/authenticated/service_role`；`school_tuition_p0f_source_lines` 与 `school_tuition_p0b2_resolve_adjustment` 继续拒绝 anon。
- 没有新增 anon writer 权限。ACL 终态同时记录了既有权限：source-treatment writer 对 anon 为 false；P0-B2 adjustment writer 对 anon 为 true（本任务前已存在，本任务未 grant/revoke）。

## 彭宇晗 2026-07 DB source 事实

显式输入：学生 `eb705aad-de4d-45e6-a391-42dcdd89aeda`、业务归属 `2cf7b72f-6e3c-4d09-80f7-7c58593cd466`、月份 `2026-07`、mode `net_lesson_variance_to_financial_credit_v1`、rate `0.042`、source `business_owner_confirmed_monthly_settlement_rate_v1`、effective date `2026-07-01`、adjustment mode `carry_final_balance`。

| source | planned UUID | actual UUID | 日期/科目 | 小时 | 单价 | JPY | CNY | claim |
|---|---|---|---|---:|---:|---:|---:|---|
| unused planned credit | `1a370095-dd14-444f-8ffb-778e92e03c88` | - | 2026-07-13 / EJU日语 | 2.00 | 8,500 | -17,000 | -714.00 | eligible |
| actual duration overage | `8d5ec9a9-6b8a-4203-8ee4-7d3513d45978` | `d7b53eb8-e7ba-49e3-9259-1a2cdf389822` | 2026-07-29 / EJU日语 | 0.25 / 15分钟 | 8,500 | +2,125 | +89.25 | eligible |

两行 exclusion reason 均为 NULL；line manifest 分别为 `16df05b80c2342d5c828f202851f518e7e880045e293f9195aa5ea34eeffcdbd` 与 `f7863fa4f039127580cc5e26782337058e64cca5d782688ebb7baa6f643cba03`。source reader 总 manifest 为 `864818e4d7c688e5dc4904a626ca8b426a94385f80b4a8e820b50ddffe64f38d`；生产 Dialog preview manifest 为 `c7a8041210061a56d4b100430c10655931cb0f732e19d73f471a4af7be7a6c83`。

当前保存事实仍为：settlement 0、source-treatment draft 0、adjustment draft 0、active variance claim 0。因此页面明确显示“尚未保存”和“以下金额为数据库只读预览，尚未保存”。

## `+92.44` 与 `-624.75`

两者不是同一 mode 下的竞态计算，而是两个明确合同的结果：

旧分离模式使用学生 preset `0.0435`：

```text
planned tuition       JPY102,000 × 0.0435 = CNY4,437.00
duration overage        JPY2,125 × 0.0435 = CNY   92.44
previous carry                                      CNY    0.00
received tuition      JPY102,000 × 0.0435 = CNY4,437.00
system difference = 4,437.00 + 92.44 + 0.00 - 4,437.00 = +92.44
```

新财务净额模式使用显式 `0.042`：

```text
planned tuition       JPY102,000 × 0.042 = CNY4,284.00
unused credit          -JPY17,000 × 0.042 = -CNY714.00
duration overage        +JPY2,125 × 0.042 = +CNY 89.25
net lesson variance                         = -CNY624.75
received tuition      JPY102,000 × 0.042 = CNY4,284.00
system difference = 4,284.00 - 624.75 + 0.00 - 4,284.00 = -624.75
```

`carry_final_balance` 复用 DB resolver，adjustment 为 CNY0，final carryover 等于 `-CNY624.75`；没有使用 manual adjustment。

## 两名学生既有受控作废事实

这些写入由业务负责人在本任务前通过正式页面完成，本任务仅只读保留。

### 彭宇晗

| UUID | 日期 | 科目 | 金额 JPY | reason | voided_at / updated_at (UTC) |
|---|---|---|---:|---|---|
| `6f22f125-4bd3-4278-8265-b04f39b3e8c2` | 2026-08-12 | EJU日语 | 17,000 | 错误登记 | 2026-08-03 11:31:36.517323 |
| `d4d261bb-5b6b-4ab5-8dc8-7a2c7d6ca5dc` | 2026-08-13 | EJU数学 | 17,000 | 错误预定 | 2026-08-03 11:31:50.808382 |
| `8edaeefc-9295-4da5-83a2-5f38e4beda8d` | 2026-08-14 | EJU物理 | 17,000 | 错误预定 | 2026-08-03 11:31:56.497015 |

August active tuition claim 为 0。当前 candidate 为 12 行/12课次/24小时/JPY204,000，manifest `51fd7e9750cac88b917d6c94a7fa5f7fce1956efff5c89814941bb704c30bfa3`；UUID：`0f6e6dba-1ba4-4117-8dee-7fe06842abcd`、`44641bf9-c445-4bf8-b35d-d9f20c33e206`、`67477810-f00b-41bc-8205-98f60047520f`、`6f9e97c2-12d3-4ec4-96e6-dedd2707c321`、`79502518-0c0d-4025-87e8-58e2177ae3dd`、`8636f89e-e838-4d0e-89c1-4953b5596bda`、`91020ea0-2111-4aad-98e5-1f5a720ec267`、`99c11176-0e31-4a2f-95cd-2999e1877c28`、`bcb98247-a630-458b-95bf-de91c249c1ef`、`d147d783-8c20-4d9e-bb94-03ea03c19a21`、`e1b67843-469c-473a-82fa-23aa8c2df260`、`edcc994a-85f4-48f6-9266-fd414eceaba3`。

### 李天伦

| UUID | 日期 | 科目 | 金额 JPY | reason | voided_at / updated_at (UTC) |
|---|---|---|---:|---|---|
| `40b45df8-6ed3-4ccd-9ffd-25fb06de18fe` | 2026-08-10 | EJU数学 | 22,000 | 错误预定 | 2026-08-03 11:32:33.871735 |
| `538ee794-8185-4d42-ac48-a44a7ce8cca6` | 2026-08-24 | EJU数学 | 22,000 | 错误预定 | 2026-08-03 11:32:40.866579 |
| `61e9b683-9bff-4c30-9174-a4ad3463f430` | 2026-08-31 | EJU数学 | 22,000 | 错误预定 | 2026-08-03 11:32:45.843076 |
| `f71185d0-92d0-4d73-8b0e-ea5c56ea7c49` | 2026-08-10 | EJU文综 | 22,000 | 错误预定 | 2026-08-03 11:33:33.093646 |
| `0667c085-73ae-495e-ad05-e29ae98ca5cb` | 2026-08-24 | EJU文综 | 22,000 | 错误预定 | 2026-08-03 11:33:38.753431 |
| `6ce1da2f-0621-4ceb-ace4-b9994ef21fb1` | 2026-08-31 | EJU文综 | 22,000 | 错误预定 | 2026-08-03 11:33:44.683873 |

August active tuition claim 为 0。当前 candidate 为 10 行/15课次/20小时/JPY220,000，manifest `56348ea803f4f992be3586bb5ff8aeabee3a2463f86d548477da425a148b23be`；UUID：`155dc1c7-f9d1-4cef-bcc1-4894f4b6837a`、`1ff01de9-c67f-49ff-a3cd-6cadf0e108cf`、`42e48eb1-4ce7-420e-a17c-d42080d20101`、`50c6cedc-1433-4e3c-b4a0-7e54e11a44d8`、`514e1578-00fc-4291-b135-704f8193b5b4`、`6068a0c1-7d2a-49a3-b659-35cf998e0b15`、`61172854-98d8-4069-bcfb-c2904b4316b4`、`7fe11097-509e-469e-9fbe-301412c9a0e9`、`886373fa-bfd3-4016-b4f7-f9d4f3f14f51`、`8eacbb08-ea3a-4b5d-9f62-fc772a36d31c`。

同一作废时间窗的其他学生 planned void 数为 0；两人的 voided lesson 和 `voided_at/updated_at` 在最终复核中保持不变。

## 实施内容

- DB：新增组合型只读 Dialog preview RPC，返回 current state、pending preview、逐 source、expected facts、preview manifest 与 DB resolver 的 projected adjustment/carryover。
- API：`js/api/settlement-api.js` 通过统一 API 层传递全部 9 个正式参数；page module 无 `.rpc()`、无表 DML。
- 状态管理：mode/rate/source/effective date/manual amount 变化会使旧 preview 失效；request sequence、scope key、input signature 和 response expected-fact signature 四重检查阻止旧响应覆盖。
- 页面：当前状态与待提交 preview 分卡展示；来源明细表显示 UUID、日期、科目、小时、单价、JPY/CNY、claim。
- CSS：1040px 桌面双列，标题与 footer 固定，内容区内部滚动；窄屏回落单列。
- 静态资源版本：`v10.4.6 · p0f-dialog-20260803-1`。

## SQL、RPC 与测试

执行 SQL：

- `sql/current/school_tuition_p0f_settlement_adjustment_dialog_preview_20260803.sql`：生产安装函数与最小 ACL；只写函数/ACL元数据。
- `sql/current/school_tuition_p0f_settlement_adjustment_dialog_preview_rollback_test_20260803.sql`：`BEGIN READ ONLY` + anon reader + `ROLLBACK`，返回 2/0.25/-1.75、-17000/+2125/-14875/-624.75、2 sources、64位 manifest。
- `sql/current/school_tuition_p0f_settlement_adjustment_dialog_preview_postdeploy_20260803.sql`：函数体、ACL、search_path、owner helper 与生产结果核验通过；函数定义 SHA-256 `04bb8160837677911b00ecde77f678f91e87afc96918c058c28c05f5e3103a9a`。

调用的业务 RPC 均为只读：`school_preview_student_settlement_source_treatment`、`school_tuition_p0f_source_lines`、`school_tuition_p0b2_resolve_adjustment`、`school_preview_student_settlement_adjustment_dialog`、tuition candidate preview reader。writer RPC 调用 0。

静态/回归：三个 JS module syntax、lesson month fixture、P0-B2 adjustment authority、P0-F Dialog contract、`git diff --check` 全部通过。未创建 synthetic/whitelist 业务数据，因此测试记录 UUID 为 `none`、fixture residue 为 0。

## 生产 Chrome 验收

- GitHub Pages 加载版本 `v10.4.6 · p0f-dialog-20260803-1`，页面与资源版本一致。
- 1710×869 viewport 下 Dialog 1040×782，双列实际宽度约 552/434px，footer bottom 824.55 小于 viewport 869；内容区 619/1108px 内部滚动，标题/footer始终可见。
- 彭宇晗净额模式显式输入后，页面精确显示 `-JPY17,000`、`+JPY2,125`、`-JPY14,875`、`-1.75小时`、`-CNY624.75`、projected final carryover `-CNY624.75`，2条 source UUID 可见。
- 输入由 `0.041` 请求后立刻改回 `0.042`，旧响应被丢弃，badge 为“已过期”、保存禁用；重新更新 `0.042` 后才启用。
- 李天伦 2026-07 列表与 Dialog 只读 preview 正常，system difference/final carryover 均为 CNY0，证明其他学生未回归。
- Console error 0、warning 0；页面性能资源失败项 0，所有 reader UI 请求均成功返回，Dialog error 为空。
- 未点击“保存锁定前设置”、lock、unlock 或 relock；使用“取消”关闭。

## 数据保护与哈希

School 前后及 Chrome 关闭后完全相同：

| 对象 | 行数 | MD5 |
|---|---:|---|
| lesson | 731 | `f3cb7c99e78b9fb26b5d557c53dc4f20` |
| settlement | 17 | `b890bdc29a27d842d3e3c6a28b84d526` |
| source-treatment draft | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| variance claim | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| adjustment draft | 6 | `059c5187ad6513f9501076193aa55696` |
| generation identity | 15 | `60f11efc1aebad6b182f7d0da08d36d7` |
| generation revision | 16 | `3fb1700c806e58cb0f8a75358a09dbd5` |
| tuition bill | 18 | `bc7fe1fc6d904c5f6a0380583e430c9e` |
| income | 51 | `4468607bc30770376ce6aaca9016e598` |
| generation adjustment | 1 | `30304a8ab7a3edbe796b5528512ac242` |

Cash 前后完全相同：request `39 / 303e10bc1a28a0abd8b27afd3929cfd8`；CNY `71 / d7e72182970de4ea8849c994b67e8dcc`；JPY `31 / 95ab7cf8a8d167e9b052d3fc6b64614b`。

本任务数据库发生的写入仅为获批 reader 函数定义与 ACL 元数据；真实 lesson、settlement、draft、claim、adjustment、generation、revision、bill、income、Cash、Gate 业务写入均为 0。没有测试白名单业务写入。

Gate 终态：`student_tuition_preview=enabled`、`student_tuition_generate=blocked`、`student_tuition_cash_submit=blocked`。

## 受保护 untracked 文件

六份文件保持 untracked 且 SHA-256 未变：

- `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv`: `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432`
- `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt`: `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093`
- `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql`: `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54`
- `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql`: `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a`
- `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql`: `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773`
- `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql`: `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b`

最终状态：实现提交已普通推送；交付文档提交完成后再次普通推送。工作树只应保留上述六份受保护 untracked 文件。
