# R1D-F1 planned收费归属最小writer切换实施报告

日期：2026-07-30
阶段：R1D-F1
状态：正式部署及验收完成，停在数据库审查点

## 1. 目标与边界

本阶段只把新建planned lesson的五字段收费归属和整数时长切为数据库权威，并封闭lesson表direct INSERT/UPDATE旁路。不写venue或费率，不计算空调费，不修改页面、actual writer、settlement reader、普通actual `<>`校验、历史lesson/evidence或R0。

## 2. current catalog调用关系

preflight确认8个入口均存在且签名、返回结构、ACL与E-A-E冻结值一致：

- `school_create_planned_lesson_record_with_venue`调用`school_create_planned_lesson_record`；
- `school_generate_planned_lessons_batch_with_venue`调用`school_generate_planned_lessons_batch`；
- `school_import_lesson_records_batch_with_venue`调用`school_import_lesson_records_batch`；
- `school_update_lesson_record_guarded_with_venue`调用`school_update_lesson_record_guarded`；
- 两个update入口同时属于actual编辑链，因此定义和ACL必须原样保持，由table invariant覆盖其planned分支。

## 3. canonical输入与source

B1-B已批准并部署：

- 单条/导入既有明确`lesson_date`输入，使用`scheduled_date_at_create`；
- 批量生成器把每个生成行归一为收费周周一，使用`explicit_billing_week_at_create`；
- DB helper计算ISO周一、周一所在`YYYY-MM`、相同student month；决定时间使用`statement_timestamp()`；
- `scheduled_lesson_date`保持独立且不由旧`lesson_date`自动填充。

cutover version固定为`r1d_f1_planned_attribution_v1`。

## 4. 实施设计

只替换三个纯planned core的同签名facade：single、batch、import。原定义改名为仅owner可调用的内部legacy core，新facade先用`school_resolve_planned_duration`生成/验证不低于2的整数时长，再调用原core。四个venue wrapper和两个shared update函数保持定义不变。

新增`BEFORE INSERT OR UPDATE` table invariant：

- planned INSERT忽略客户端五字段并由DB重写完整canonical bundle；
- direct NULL/partial/伪造月份不能落库；
- fixed279必须命中immutable evidence，并保持NULL bundle及student/entity/year_month/identity；
- fixed118和新canonical bundle冻结，不允许清空或部分修改；
- 新canonical的时间必须全NULL或成对，禁止跨午夜，DB验证整数时长；
- actual INSERT/UPDATE不进入planned逻辑。

## 5. 执行结果

### 5.1 执行次数与事务

- School只读preflight执行2次，均通过并显式`ROLLBACK`；第二次为正式部署前边界复核。
- 同字节rehearsal执行3次：前2次因纯测试配置/隔离错误由连接关闭回滚，第3次完整通过，显式回滚DDL与测试事务，并在同连接只读确认目录和测试数据零残留。
- 正式cutover SQL执行1次，全部事务内断言通过并明确`COMMIT`；生产SQL错误0。
- postdeploy执行1次，`REPEATABLE READ READ ONLY`验收通过并显式`ROLLBACK`。
- 独立rollback tests执行2次：第1次业务矩阵通过且测试事务已`ROLLBACK`，随后只读残留块因括号错误停止；修正后第2次完整通过，测试事务与只读核验事务均显式`ROLLBACK`。
- legacy完整hash恢复脚本执行3次：第1次因`import_batch_id`类型写错而在只读事务中停止；修正后分别在rehearsal和最终rollback tests后通过并显式`ROLLBACK`。
- 正式持久化业务DML、业务RPC、测试数据COMMIT均为0；Cash连接0。

### 5.2 测试脚本修正记录

所有修正均未删除或放宽业务断言，也未修改生产cutover定义：

1. rollback tests `640a6234db36fbb8590f6204d72193787a759cc200329eb726f0180815695cf3` → `306d8e6d65b535bcb9ba69c59be0ac33af64d9bbef0445b36b5d4249c0756295`：删除4个不属于279 evidence的硬编码UUID，改为确定性fixture查询。
2. `306d8e6d65b535bcb9ba69c59be0ac33af64d9bbef0445b36b5d4249c0756295` → `11241a14cdc8c503cd5ffb85357e7b7824c510123bacd274aa012fc21f7e3eb2`：既有batch/import函数在同一事务重复创建固定名称临时表；将core用例分别置于验证后主动回滚的子事务，venue wrapper仍独立完成正向验证。
3. `11241a14cdc8c503cd5ffb85357e7b7824c510123bacd274aa012fc21f7e3eb2` → `1496887526311ce524082ef274a3999517ec24046836a7f988487b9ffdcf86d5`：补齐post-rollback只读核验中第一处`EXISTS`右括号。
4. 仓库外legacy恢复脚本 `e5a8a29805d11d3663e9995c4045d2becc24dd101af46345398c5beedbfe00d2` → `6cd6b293d730a767748354d89ba23e5d3db4747b78ea6b3da68b75c7e5920487`：按真实text类型比较`import_batch_id`。

### 5.3 rehearsal whitelist与测试

确定性选择条件为：`approved_manifest=true`、evidence source/version为固定279批准值、关联lesson为`school/planned`、五字段全NULL、student/entity/year_month及identity MD5全部匹配evidence，按`planned_lesson_id`升序取第一条。

- whitelist UUID：`00003ee2-4358-457c-8727-7a4c8299b952`
- 测试前完整lesson JSON MD5：`c28fa6b5902bac4d923fd07488bee28e`
- 真实行只执行`note=note`的最小非归属正向测试，以及identity修改的预期拒绝测试；均位于未提交事务并回滚。
- rehearsal及最终独立测试后均以新连接确认完整MD5恢复；固定测试ID与batch/import ID残留0。
- 通过矩阵：2/3小时、时间推导整数、1/1.5/2.25/2.5小时拒绝、17:15/单边/反向/跨午夜拒绝、周一/周末/跨月/跨年、single/batch/import及venue wrapper、两个update路径、direct INSERT覆盖伪造值、direct UPDATE清空/部分修改拒绝、legacy/118冻结、actual隔离。
- 成功rehearsal披露10条外层事务测试lesson UUID：`144f3861-b465-4a3e-854e-e78186c576f9`、`385a190e-fe76-4440-ac4d-826bcd37c1a7`、`4e6c837f-b06f-4994-87f6-b33f464261a2`、`51271356-cf58-474f-b6f3-e74e04a4866c`、`5edf9f85-eb72-4cf5-9c9e-02c1d45a16fe`、`e594695c-2347-4486-b11b-e4f909656503`及`f1000000-0000-4000-8000-00000000d001`至`d004`；全部回滚。
- 最终独立测试披露10条外层事务测试lesson UUID：`2f8d917e-1402-4a76-b0d9-3b5486787dd5`、`848ee526-66c8-4af6-bd80-d92d1d6834b2`、`929f71ce-bba9-4fd8-8c03-8ffd2e78ae41`、`a50fdc13-aeb5-4b8d-ba62-88a7c869341f`、`c4769447-4e83-4dde-a589-178abca6917a`、`e5b7e671-9580-44d3-9548-686f909d89c2`及`f1000000-0000-4000-8000-00000000d001`至`d004`；全部回滚。
- batch/import控制UUID为`f1000000-0000-4000-8000-00000000b001`、`b002`、`c001`、`c002`；残留0。前两次失败rehearsal在NOTICE输出前终止，自动生成lesson UUID未披露，但未提交事务均由连接关闭回滚，后续完整rehearsal与新连接核验均证明测试来源、固定ID和业务fingerprint无残留。

### 5.4 正式持久化范围

- 原single、batch、import三个core改名为仅owner可执行的`*_r1d_f1_legacy_core`。
- 原公共签名各新增同签名facade；rehearsal定义MD5依次为`607a6030f28fecdcefbeb94f23306d2e`、`d37839bb96797fb4f7a91246eb96f0ba`、`78176ed41f87b8ad9ac1bba5e456a8b8`。
- 新增version函数`school_r1d_f1_planned_attribution_cutover_version()`，返回`r1d_f1_planned_attribution_v1`。
- 新增trigger函数`school_enforce_r1d_f1_planned_attribution()`及lesson表`BEFORE INSERT OR UPDATE` trigger。
- 四个venue wrapper和两个shared update函数定义/ACL保持冻结hash；actual writer组、settlement reader/writer组及普通actual校验hash不变。
- 未新增表、业务行、evidence、aircon配置或command ledger；未修改RLS/表ACL。

### 5.5 postdeploy边界

- planned分布：固定118完整 / 固定279全NULL / partial 0 / 切换后新增0。
- candidate：118条 / 254小时 / JPY2,474,000；函数MD5、UUID MD5及manifest SHA-256均保持冻结值。
- evidence：279与15，manifest分别为`34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627`和`68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26`。
- 固定切点前actual仍为233，UUID MD5 `606b4cce348e67e4cffac62eb9e4a487`，全行投影MD5 `b7307877cd924a20fc1e96f844f68a74`；当前总量只披露为234，新增行位于固定切点之外。本阶段actual测试行0。
- 19条overage新增字段仍全NULL，8条makeup冻结投影不变；空调相关四表0行、lesson空调组件字段0。
- 资金链仍为9/42/121/42及冻结hash；R0仍为`validation_preview_only / blocked / blocked`。

## 6. 停止边界

已停在`R1D-F1数据库审查点`。未执行Git add/commit/push，未进入R1D-E-B2、S1-B或planned页面/空调费后续阶段。
