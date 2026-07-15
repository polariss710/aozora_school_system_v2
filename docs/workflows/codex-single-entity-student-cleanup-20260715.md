# 单一业务归属白名单测试学生清理

## 授权范围

- 用户明确要求清理学生管理中残留的 `codex-test-single-entity-default-student-20260713` 及相关测试数据。
- 这是一次固定 UUID、固定测试标记、完整依赖扫描后的独立物理清理，不开放通用删除入口。

## 固定目标

- Student: `f8db8d17-6a14-4f5b-9a21-2ac5f3b8c0af`
- Planned lesson: `fdbae3f3-a6e3-42a1-9639-47232e742963`

## 已证明的依赖范围

- 学生由 v10.3.73 单一业务归属 commit smoke 创建，名称和 display name 均为完整 `codex-test` 标记。
- 唯一关联数据是 v10.3.75 场地 commit test 创建的 2027-08 planned lesson；金额、单价均为 0，没有 actual_minutes。
- 全公共基础表 UUID 扫描只命中学生主表、该课时的 `student_id` 和课时自身 id。
- 目标课时没有 linked actual、工资明细、学生结算、账单、收入、支出、Cash 或其他 UUID 下游引用。
- 青空塾业务归属、老师和科目是正常共享主数据，不属于清理范围。

## 执行规则

1. SQL 默认 rollback，只有显式传入 `-v cleanup_commit=1` 才提交。
2. 删除前必须复核学生与课时完整指纹，包括固定 ID、标记、业务归属、老师、科目、月份、日期、时间、状态和零金额。
3. 删除前动态扫描所有 public base table UUID 列；除已批准的三处命中外，任何引用都立即拒绝。
4. 删除顺序固定为 planned lesson，再删除 student。
5. 不删除或修改业务归属、老师、科目、工资、结算、账单、收支、账户、Cash 请求或 Cash 流水。
6. 先执行 rollback 测试并确认两条记录恢复，再提交 verified SQL，最后执行正式白名单清理和零残留验收。

## SQL

- `sql/current/school_cleanup_single_entity_default_student_20260713.sql`
