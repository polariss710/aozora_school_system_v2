# R1D-D-B1-B Planned/Aircon Schema 实施报告

- 阶段：`R1D-D-B1-B-R2`
- 日期：2026-07-30
- 数据库：School only
- 范围：加法型 schema、内部 helper、约束、索引及新增对象最小权限
- 状态：数据库实施完成，停在 B1-B 数据库审查点

## 兼容映射冻结

真实 catalog 已通过 `REPEATABLE READ READ ONLY` 映射 SQL 核验。既有列只复用，不改名、不改型、不改 nullable/default、不回填。

| 业务语义 | 处理 | 物理列 |
|---|---|---|
| planned duration 快照 | 复用 | `duration_hours_snapshot` |
| unit price 快照 | 复用 | `unit_price_jpy_snapshot` |
| lesson 最终总额快照 | 复用 | `lesson_fee_jpy_snapshot` |
| billing week 快照 | 复用 | `week_start_date_snapshot` |
| scheduled date 快照 | 复用 | `scheduled_lesson_date_snapshot` |
| 通用来源证据 | 复用 | `source_snapshot` |

relation 仅新增下列 8 个真正缺失组件：

- `base_lesson_fee_jpy_snapshot`
- `aircon_rate_id_snapshot`
- `aircon_unit_price_jpy_snapshot`
- `aircon_billable_hours_snapshot`
- `aircon_fee_jpy_snapshot`
- `fee_calculation_version_snapshot`
- `lesson_venue_id_snapshot`
- `lesson_venue_code_snapshot`

映射基线：lesson 630；actual 233（仅披露）；旧 RPC 数量 11；旧 RPC 定义 MD5 `8ecb87eeab8dbf2953a985038927375d`；旧 RPC ACL MD5 `200f9f7c5cb7983b2aa90aeec65693b2`；lesson ACL MD5 `e4b4638d16b9a1a0e6c2662833bed732`；lesson policy MD5 `664065c128a736b78af24bec527dbf2c`；relation trigger MD5 `5948fe7078a69ef943990208bd5aa532`。

## 实施对象

新建且正式部署后保持空表：

- `public.school_lesson_venues`
- `public.school_student_aircon_rates`
- `public.school_planned_writer_commands`
- `public.school_venue_rate_change_audit`

`school_lesson_records` 新增 11 个 nullable、无 default 字段；历史行保持全 NULL。`school_student_tuition_bill_lessons` 仅新增上述 8 个 nullable、无 default 字段；历史行保持全 NULL。

内部 helper：

- `school_resolve_planned_billing_attribution(date,date)`
- `school_resolve_planned_duration(text,text,numeric)`
- `school_calculate_planned_fee_components(uuid,date,uuid,numeric,numeric)`

helper 均为 `SECURITY INVOKER`、固定 `search_path=pg_catalog, public`，且未向 PUBLIC、anon、authenticated、service_role 授予执行权限。四张新表启用 RLS，未创建开放 policy，未向上述角色授予写权限。

## 回滚演练与部署结果

- DDL 主体 SHA-256：`bed54c8b4f8aacc774adb5c493a771dacfef8149a9e2b2cb3d9a1d3e4226a8d2`。
- rehearsal 文件不复制 DDL；它设置 rehearsal 开关后直接 `\i` 正式 schema 文件，因此演练和正式部署使用同一字节来源。
- 完整 rehearsal 执行 1 次：DDL、结构断言、权限、半开区间、0/660/负数/661、相邻/重叠、duration、billing attribution、fee component 测试全部通过；捕获重叠 SQLSTATE `23P01`；显式 `ROLLBACK`；同连接零残留确认通过。
- 正式 schema 执行 1 次：全部断言通过并 `COMMIT`；生产 SQL 错误 0。
- postdeploy 执行 1 次：`REPEATABLE READ READ ONLY`，全部断言通过，显式 `ROLLBACK`。
- rollback tests 执行 1 次：向四张新表写入 7 条虚构测试记录，负数/661/重叠为捕获式预期失败；显式 `ROLLBACK`；同连接确认测试残留 0。
- 持久化数据库写入仅为获批 DDL；业务 DML 0、业务 RPC 0。四张新表正式行数均为 0；lesson 11 个新增字段与 relation 8 个新增字段在全部历史行上均为 NULL。

主要结构包括学生费率 `daterange [)` 与 GiST exclusion、venue/rate 外键、nullable 安全 check、必要索引、四张新表 RLS，以及三个未开放给客户端或 service role 的内部 helper。旧 writer 行为、旧 relation immutable trigger、旧 RPC 定义/ACL 和 lesson ACL/RLS 均未改变。

## 数据边界

部署前后均保持：`btree_gist` 为 `1.7 / extensions / supabase_admin / 264`，`extensions.gist_uuid_ops` 有效；R0 `validation_preview_only / blocked / blocked`；candidate MD5 `8981a2ce07abf8c28231bfaf05451368`；planned 397；五字段 118 / 279 / 0；candidate 118 / 254 小时 / JPY2,474,000；UUID MD5 `77f697f82e547d84dcabf88a3c868aa1`；Manifest SHA-256 `f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1`；legacy MD5 `0975fdc91b533680e5ccc909f076ac62`。School 资金链仍为 9 / 42 / 121 / 42，hash 分别为 `0f0323b79e7ff1c47ff6b90c75477a2d`、`2a4897b752f272b1f192045418b4940c`、`09dfee7d8833e09384fb41a84f2959e0`、`680b6e5aaa718569aee4c36fe1cdc058`；relation hash 对新增全 NULL 列采用部署前原业务列投影。actual 为 233，仅披露。

## 边界声明

本阶段未写正式 venue/学生费率配置，未回填 118/279，未修改现有 writer/API/page/candidate/generate/R0，未修改旧 RPC/ACL/RLS，未连接 Cash，未进入 B1-C，未执行 Git add/commit/push。
