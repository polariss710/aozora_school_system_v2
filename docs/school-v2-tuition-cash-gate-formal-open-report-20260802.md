# School V2 学费 Cash Gate 正式开放报告

日期：2026-08-02（JST）
阶段结论：Cash Gate已正式开放；真实Cash request尚未创建

## 1. 结果

业务负责人批准的动态Lesson增量已经只读审计，Cash冻结对象、金额、RPC、ACL和Edge部署均无漂移。既有Gate脚本先完成`commit=0` rehearsal，输出`UPDATE 1`后`ROLLBACK`；随后以`commit=1`正式执行，输出`UPDATE 1`和`COMMIT`。

最终Gate为：

```text
student_tuition_preview     = enabled
student_tuition_generate    = enabled
student_tuition_cash_submit = enabled
```

本轮唯一持久数据库写入是`school_feature_gates.feature_key = student_tuition_cash_submit`一行从`blocked`切换为`enabled`。没有提交真实income，没有创建School Cash linkage、Cash request或Cash transaction，没有调用approve/reject。

Business-model expansion declaration：新表、列、状态、日期/月/归属、identity、source、snapshot/version、可写事实、字段语义/可变性、writer/reader权威、锁、权威来源、fallback/dual-read、dual-write、历史重解释和破坏性schema变更均为`none`。

## 2. 动态Lesson增量审计

Lesson运营基线由`728 / d06db03678401889422e3049018b7615`刷新为业务负责人批准的：

```text
729 / fdddb50d53ff8be527186aa01dc4f710
```

普通completed actual：

- actual `66abbc60-2211-40f8-b86e-30feb87fafa6`，来源planned `a76dece8-64b8-48bf-b9a6-36efcc163cf5`；
- `created_at = 2026-08-02 07:50:59.352504+00`，行MD5 `6e1d1ee40097ff6b03824785d7dd5cf0`；
- `duration_hours=2 / actual_minutes=120`，与来源planned 2小时相等；
- `status=completed / is_billable=true / lesson_fee=20000`；
- overage分钟和金额字段均为NULL，无overage；
- 来源planned仍为`planned`，该来源只有这一条linked actual，无linked `pending_makeup`；
- actual尚未进入工资明细，writer context和固定fixture学生残留均为0；
- 全库normalized relation仍为固定`256 / dfa2bdb71f812f4b2aa0a23613edf289`。该planned的2条既有relation属于开放前固定账单分类，actual创建没有新增relation或第二条收费事实。

该记录由业务负责人确认通过正式页面创建。页面通过`lesson-page -> lesson-api -> school_create_actual_lesson_from_planned`既有权威链写入；行内没有独立的writer-provenance字段，因此“正式入口”证据由业务负责人确认、唯一linked actual及RPC不变量共同构成，不把推断伪装为单行审计字段。

补课完成actual继续精确不变：

- actual `2de1d906-0682-4890-88a7-fd82a12cf27e`，来源planned `f7e7fe6f-858d-4a9c-b9ba-b416e204df1e`；
- `makeup_completed / 2小时 / actual_minutes=120`；
- 学生月`2026-07`，老师工资月`2026-08`；
- `is_billable=false / lesson_fee=0`；
- 行MD5 `197d42d8cf2254c5c5cd1113b23df64a`。

## 3. Lesson动态边界与Cash固定边界

Gate enable SQL、既有School postdeploy和Cash postdeploy从未包含Lesson全集`728/旧MD5`条件，因此Gate SQL无需修改。Lesson全集会随正常运营增长，而Cash提交只消费冻结bill、income、billing identity、normalized relation/source snapshot、School linkage及Cash对象；Lesson全集不再作为固定Gate阻断条件。

保护没有删除：每次出现Lesson增量仍须只读审计正式writer、来源、时长、overage/pending makeup及收费链副作用。Gate开放前后继续精确阻断的对象为bill、income、identity、normalized relation、School Cash linkage、Cash request、Cash transaction、Cash account、固定eligible ID集合和冻结金额。

## 4. 工资月份只读核验与独立问题

业务负责人确认实际授课日期应为`2026-08-02`、老师工资应归属`2026-08`。数据库当前实际存储为：

```text
lesson_date              = 2026-07-31
year_month               = 2026-07
student_settlement_month = 2026-07
teacher_settlement_month = 2026-07
```

课时列表/详情展示读取`lesson_date`，因此会展示`2026-07-31`。工资页面候选先读取`teacher_settlement_month = 选择月份`，仅当该字段为NULL时才fallback到`year_month`；工资生成RPC同样使用`coalesce(teacher_settlement_month, year_month)`。因此该actual当前会进入`2026-07`工资候选，不会进入业务期望的`2026-08`。

该问题记录为独立课时日期/工资归属bug。本轮没有修改actual、工资RPC或工资数据，也没有把该问题合并到Cash任务；Cash提交不读取lesson或工资事实，因此不阻塞本次Cash Gate开放。

## 5. 固定基线

| DB对象 | 开放前 | 开放后 |
|---|---|---|
| School bill | `17 / b18f15673637280bf1455667ccd3cc00` | 相同 |
| School income | `50 / d393822a95c6121a2e754919b1464a5b` | 相同 |
| Billing identity | `15 / d8d72d5f886e363b80bca4aecfe22522` | 相同 |
| Normalized relation | `256 / dfa2bdb71f812f4b2aa0a23613edf289` | 相同 |
| School Cash linkage | `35 / 6e76a4dc2fc2954b28b7ad0a8d203ba0` | 相同 |
| Dynamic Lesson | `729 / fdddb50d53ff8be527186aa01dc4f710` | 相同，仅运营证据，不作固定Cash阻断 |
| Cash external request | `34 / ba0571247a869843c3ddda9075ea78dd` | 相同 |
| Cash CNY transaction | `63 / 3759e3d726400d5dd2225d79c78b9ac2` | 相同 |
| Cash JPY transaction | `31 / 95ab7cf8a8d167e9b052d3fc6b64614b` | 相同 |
| Cash account | `7 / 89b057e2cdeb7324ef73f73e252174f1` | 相同 |

17条分类开放前后均为`ELIGIBLE_FOR_CASH_SUBMIT=8 / ALREADY_SYNCED=7 / BLOCKED_CONFLICT=2`。8条eligible固定合计为JPY `2,605,800.00`、冻结CNY `109,926.72`、carryover CNY `107.50`；开放前`eligible=true`为0，开放后为8。8条eligible对应School linkage、active Cash request、CNY/JPY transaction均为0。

原16条TSV SHA-256为`33d0cb9a8d0cb62c4de5f6ea26ed658b6898293def3cc2ee205d58721295ec35`；当前17条TSV为`b91cb9dacef0c0c68013c5a2435a32a27cbef5089a159f30c49247a1145ccf46`；8条eligible集合为`e1ad372ffea00b113088d7a39d7ab3ee2841f9b18ae3e18fd22952711b3cfd09`。

## 6. 部署、ACL与Gate执行

- Edge `request-cash-income-confirmation`：ACTIVE version 10；bundle SHA-256 `bd5a0924ae6fb2ab9114f6103a90f825968520784069d9f704a4ac74374cb6a3`；本地源SHA-256 `e3e42e2f7b03654c03612def0c1f9d9515dc702432bdf2ec44e55c7cddd4ad54`。
- School/Cash硬化函数MD5和ACL与实施报告一致；School bridge仅service role，Cash create/internal writer仅service role，approve/reject保留authenticated及service role。
- Gate脚本未修改：`sql/current/school_tuition_cash_submit_gate_enable_20260802.sql`，SHA-256 `656cd8155c07cf00f765ce040ef49df54bd1e4804ec6fa6a56673b022fce7914`。
- Emergency disable脚本存在且未修改，SHA-256 `3e0a6a12858b63cc8165dcde37a207e675406d6038f5f81e1c4c878fb39da596`。
- rehearsal：`BEGIN ... UPDATE 1 ... ROLLBACK`；Gate复核仍为blocked，双库业务指纹不变。
- 正式执行：`BEGIN ... UPDATE 1 ... COMMIT`。
- Gate审计：reason=`学费Cash技术硬化、双库回滚矩阵、ACL、Edge和冻结金额权威验收完成。`，release=`tuition-cash-hardening-20260802`，evidence hash为17条TSV SHA，`updated_at=2026-08-02 08:24:13.778515+00`，`updated_by=postgres`。
- postdeploy：三个Gate均enabled；冻结对象、分类、金额、两个actual和Cash四项指纹全部通过；未调用真实request Edge probe。
- 所有检查通过，因此emergency disable未执行。

## 7. 数据库写入与下一步

本轮没有执行schema/RPC SQL，没有调用写RPC，没有测试白名单写入或测试记录ID。唯一真实数据库写入是一条明确批准的Gate配置UPDATE；它不是income、bill、identity、relation、lesson、settlement、工资、linkage、Cash request、transaction或account写入。

下一步由业务负责人在正式页面手动选择第一条真实eligible income提交，并人工观察单条request的幂等状态；Codex不得代为提交、approve或reject。独立后续必须调查`66abbc60…`的实际日期输入与`teacher_settlement_month`为何落入2026-07，并在新任务明确授权前保持该真实记录不变。
