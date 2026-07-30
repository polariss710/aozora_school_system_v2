# R1D-E-B1 Legacy结算月证据基础实施报告

日期：2026-07-30
阶段：R1D-E-B1-R
状态：`R1D-E-B1数据库审查点`

## 1. 范围

本阶段只部署两组不可变证据：固定279条legacy planned lesson的结算月证据，以及固定15条locked settlement snapshot的basis证据。新增两个只读helper；不接入writer/reader，不修改lesson、actual、settlement、overage、makeup、资金链或R0。

## 2. 上轮停止点与本轮修正

上轮只读preflight在第275行以SQLSTATE `42703`停止。原因是统计`base_lesson_fee_jpy`、`aircon_fee_jpy`、`fee_calculation_version`的表达式缺少`school_lesson_records`的FROM范围，并非schema缺列。数据库写入、B1对象和B1工件均为0。

本轮唯一修正是在仓库外preflight的该表达式增加：

```sql
FROM public.school_lesson_records lesson
```

并将三个字段限定为`lesson.<column>`。未增加、删除或放宽任何业务断言。

- 修正前preflight SHA-256：`371b18f9d5d88e5abc398f5e517acda6343399adaa5246d92b5970d488d9d506`
- 修正后preflight SHA-256：`68ea597f4494c896bcf1ed7f9b2f79053c42d08d65cc88ab7bb63a523532474b`
- 修正后执行结果：通过；`REPEATABLE READ READ ONLY`；显式`ROLLBACK`
- 第二次SQL错误：无

## 3. 设计

### 3.1 固定279 planned evidence

`public.school_legacy_planned_settlement_evidence`以`planned_lesson_id`为主键并对lesson使用`ON DELETE RESTRICT`外键，保存student/business entity快照、冻结的legacy结算月、lesson identity MD5、manifest批准标记、来源、版本和记录时间。

固定边界：279条、UUID MD5 `0975fdc91b533680e5ccc909f076ac62`、identity manifest SHA-256 `34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627`。

### 3.2 固定15 snapshot basis evidence

`public.school_legacy_settlement_snapshot_basis_evidence`以settlement snapshot ID为主键并使用`ON DELETE RESTRICT`外键，保存student/entity/month/status、planned/actual/lesson计数、lesson UUID MD5、amount basis MD5、完整settlement structure MD5、来源、版本和记录时间。

固定边界：15条、snapshot UUID MD5 `c87016564bb4ab954993ddf9f37ff955`、basis manifest SHA-256 `68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26`。

### 3.3 不可变与权限

两表在seed完成后由同一`SECURITY DEFINER` guard拒绝`INSERT/UPDATE/DELETE/TRUNCATE`。两表启用RLS；anon/authenticated无读写权限，service_role仅SELECT。两个helper均为`SECURITY INVOKER`、`STABLE`、固定安全`search_path`，仅service_role可执行。

## 4. 执行与验收

### 4.1 连接与SQL执行

本轮共建立5次School数据库连接并执行5个文件入口；全部使用`psql -X -v ON_ERROR_STOP=1 -f <file>`，SQL错误为0，第二次SQL错误未发生。两次仅检查环境变量的shell命令均在调用`psql`前结束，不计数据库连接或SQL执行。

1. 修正后preflight执行1次：只读事务通过并`ROLLBACK`。
2. 仓库外rehearsal wrapper执行1次：以`r1d_e_b1_commit=0`包含正式schema文件，事务内279+15、4 trigger和既有业务指纹断言通过后`ROLLBACK`；同连接只读确认公开对象与业务残留均为0。
3. 正式schema执行1次：以`r1d_e_b1_commit=1`执行同一字节文件，全部断言通过并`COMMIT`。
4. postdeploy执行1次：`REPEATABLE READ READ ONLY`验收通过并`ROLLBACK`。
5. rollback tests执行1次：owner不可变拒绝、anon/authenticated拒绝、service_role只读全部通过，虚构UUID残留0；测试事务和事后只读事务均`ROLLBACK`。

同字节schema SHA-256：`0386bf1646da1c787d1e5cc05130201c9fab987cb2873a5c49b8a37cfb84c764`。

### 4.2 正式持久化范围

- 新表：2张。
- 新证据行：294条，仅279 planned evidence与15 snapshot basis evidence。
- 新trigger：4个，覆盖两表的row级`INSERT/UPDATE/DELETE`与statement级`TRUNCATE`拒绝。
- 新函数：1个不可变guard、2个只读helper。
- 其他持久化DDL：两表约束、主键隐式索引、注释、RLS与最小ACL。
- 既有表`UPDATE/DELETE`：0；既有lesson、actual、settlement、snapshot、overage、makeup、资金链写入：0。
- 业务RPC：0；Cash连接：0。

### 4.3 验收结果

- planned evidence：279；manifest SHA-256 `34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627`。
- snapshot basis evidence：15；manifest SHA-256 `68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26`。
- planned五字段：118完整 / 279全NULL / 0部分，未改变。
- fixed actual：233条，`student_settlement_month`仍全部NULL，仅披露。
- 8条makeup历史事实、19条overage历史集合：无写入；正式事务既有lesson完整指纹前后相同。
- R0：`validation_preview_only / blocked / blocked`。
- candidate MD5：`8981a2ce07abf8c28231bfaf05451368`。
- planned writer、actual writer、settlement reader/writer定义与ACL hash不变。
- School资金链：9 bills / 42 income / 121 relations / 42 historical exclusions，数量与hash不变。
- rollback tests虚构ID：`00000000-0000-4000-8000-00000000eb11`、`00000000-0000-4000-8000-00000000eb12`；持久化测试记录0。

## 5. 边界

本阶段不修改279条planned五字段，不修改233条actual的`student_settlement_month`，不修改19条overage、8条makeup历史事实或15条settlement；不修改writer/reader/candidate/R0；不连接Cash；不进入E-B2、E-C或S1-B；不执行Git add/commit/push。
