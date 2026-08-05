# School V2“标记取消并转待补课”修复与权限封口实施报告

日期：2026-08-06  
范围：预定课时取消并生成不计费取消actual、转入待补课余额的既有流程  
结论：DB与页面实现、生产部署、回滚/权限/并发验证均已完成；未操作任何真实业务课时。

## 1. 业务模型声明

- 新表、字段、状态、事实来源：`none`。
- 调整对象：既有writer `school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)`。
- 唯一时间/时长权威：DB依据显式起止时间计算`duration_hours`；客户端duration仅作一致性断言，不是保存权威。
- 既有取消事实：生成actual固定`billing_type=nonbillable`、`lesson_fee=0`、`actual_minutes=0`，来源planned原子转为`pending_makeup`。
- 既有不可变边界：已消费学费结算、P0-F claim、工资锁、学生锁、重复actual继续阻断；不增加fallback、dual write或历史修复。
- 授权依据：本任务附件明确批准上述writer语义、权限、锁顺序和页面入口加固。

## 2. 根因与修复

原页面入口与writer仍允许过宽调用面，且时间/时长校验未形成统一的DB权威合同。修复后：

- 页面仅向active `admin`/`operator`显示入口；`read_only`、inactive、无membership隐藏并在事件处理层再次拒绝。
- 仅`status=planned`、`record_type=planned`且没有关联actual的来源可打开取消弹窗。
- 页面模块只调用API层，不直接`.rpc()`，也不直接DML。
- 起止时间必须为`HH:MM`、15分钟网格且结束晚于开始；DB计算并保存时长，页面只显示预览。
- writer在读取业务行之前先校验`auth.uid()`和`school_app_memberships`，只允许active admin/operator。
- writer ACL仅授予`authenticated`；`PUBLIC`、`anon`、`service_role`均无EXECUTE。
- 消费判断继续复用`school_tuition_p0a_consumed_bill_id(uuid)`，该helper遍历完整generation revision历史，不因Void/Reissue释放已消费事实。
- 保留既有学生结算锁、工资月锁、P0-F immutable claim与duplicate guard；所有变更仍在同一事务和既有锁顺序内完成。

## 3. 生产DB证据

- 部署前writer定义MD5：`fcbb8a4c48cf62c285de45238b219e43`。
- 部署后writer定义MD5：`726c3f76786167bc70cb40b0ec9be613`。
- owner：`postgres`；`SECURITY DEFINER=true`；`search_path=pg_catalog, public`。
- ACL：仅`authenticated`可执行；PUBLIC/anon/service_role均不可执行。
- exact rollback rehearsal已恢复原定义MD5和原ACL，事务ROLLBACK后再正式部署。
- postdeploy检查、rollback测试矩阵与fixture residue检查均通过。

执行的SQL文件：

- `sql/current/school_cancelled_actual_writer_hardening_deploy_20260806.sql`
- `sql/current/school_cancelled_actual_writer_hardening_postdeploy_20260806.sql`
- `sql/current/school_cancelled_actual_writer_hardening_rollback_20260806.sql`（仅事务内exact rollback rehearsal）
- `sql/current/school_cancelled_actual_writer_hardening_rollback_tests_20260806.sql`（全部ROLLBACK）
- `sql/current/school_cancelled_actual_writer_concurrency_fixture_setup_20260806.sql`
- `sql/current/school_cancelled_actual_writer_concurrency_session_a_20260806.sql`
- `sql/current/school_cancelled_actual_writer_concurrency_session_b_20260806.sql`
- `sql/current/school_cancelled_actual_writer_concurrency_verify_cleanup_20260806.sql`

## 4. 权限、业务与并发矩阵

已通过：

- active admin、active operator成功；read_only、inactive admin/operator、无membership、缺失JWT subject拒绝。
- anon与service_role因ACL拒绝。
- 已关联actual、非planned、非15分钟网格、时间倒置、客户端duration不一致拒绝。
- 学生结算锁、voided历史bill仍被revision历史消费、P0-F claim、老师工资月锁拒绝。
- DB权威保存1.25小时，兼容客户端duration为NULL；取消actual的fee/minutes为0且nonbillable。
- 待补课余额reader纳入来源，工资reader排除取消actual。
- 双会话竞争同一planned时，session A成功生成唯一actual；session B等待锁后以duplicate拒绝，未产生第二条记录。

并发fixture：`c609`；唯一临时actual：`d3e7e9ef-8d21-41a0-8426-68293dff9b3b`。该fixture在验证后按精确UUID清理，相关user/membership/student/teacher/subject/lesson residue均为0。rollback fixture `c608`从未持久化。

## 5. 数据不变量

部署前、部署后、并发fixture清理后的10组业务表全量指纹一致：

| 范围 | 行数 | MD5 |
|---|---:|---|
| tuition bill | 22 | `e50673ac998ee2d84573a076a64d3d42` |
| bill lesson | 330 | `e3e2e0044c17864bc66c7e2861176c8b` |
| generation identity | 15 | `60f11efc1aebad6b182f7d0da08d36d7` |
| generation revision | 20 | `ffdc498a6e256aa29064f021f22e4b00` |
| income | 55 | `ccfb156a42068df78e98f2ce6693aac6` |
| lesson | 738 | `a24f18f7016115bd69c86212972f9072` |
| settlement | 18 | `481ffa7ed5173da852f0f28ce66c2e9b` |
| variance claim | 2 | `fbce39067e6d98167cdb474eb9635c92` |
| wage detail | 556 | `6204dc666b3b8e0f64fac901ecf0686a` |
| wage lock | 95 | `7bbe108d3ac73d4f21530793bf141bc6` |

生产DB持久写入仅为目标函数定义、comment与ACL；白名单`c609`业务fixture曾短暂提交并已精确清理。真实业务课时、结算、账单、收入、工资记录写入均为0。

## 6. 前端与静态回归

- 页面版本：`v10.5.8`；cache buster：`cancellation-hardening-20260806-1`。
- 新增取消流程静态测试通过。
- lesson generation closure、lesson operations closure、authoritative month refresh、P0-B1 authority回归均通过。
- `node --check`、page直接RPC扫描、错误环境变量/search_path扫描、`git diff --check`均通过。

## 7. 真实数据处置结论

本任务不需要、也未执行任何真实课时纠正。此次修复是入口与writer合同加固；若业务负责人后续要实际取消某条预定课时，仍应在页面依据最新锁定状态单独操作。已被学费账单历史消费、工资结算、月度结算或P0-F claim锁定的课时会被稳定错误码阻断，禁止绕过。

## 8. 发布与浏览器验收

代码checkpoint：`27410ed776e181738712e374967f636d40495ecb`。Pages run、生产桌面/移动端只读弹窗验收和最终交付提交记录见本任务最终报告。
