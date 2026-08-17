# School V2 Phase 2I-A：P002套餐余额生产隔离实施报告

日期：2026-08-17
生产前端版本：`v10.5.47`（本阶段未修改）

## 结论

P002 planned `8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9` 已保持原行不变，并登记为唯一active package lot `2a000000-0000-4000-8000-202608170002`。权威分钟为 initial `1200`、consumed `0`、remaining `1200`。P002已从普通待补余额、补课来源、registered variance及net settlement source中排除；本阶段没有package消费入口，也没有部署clearance对象。

## Preflight与不可变关系

- HEAD/origin基线：`db5245481466e7ede8c71ff8f191ef973cc47688`，ahead/behind `0/0`。
- P002整行MD5：`686cbf3a566160bf0de0e30abbdaafa5`。
- student：李天伦 `a7b163a0-201e-4867-9b94-372343356a80`。
- business entity：青空进学塾 `2cf7b72f-6e3c-4d09-80f7-7c58593cd466`。
- bill lesson：`de834352-7387-f856-e8ee-213b7419210d`。
- bill：`07a02092-9503-47d1-9000-106f7e3de7e5`。
- revision：`96000000-0000-4000-8000-202608031004`。
- income：`91756564-c48d-4a1d-b6bc-88a041660e46`。
- School Cash linkage：`9de972ff-8e66-470a-8b05-e430ef51562f`。
- Cash request：`a0bee5be-761b-4bc0-a666-411f033e1eba`。
- Cash transaction：`f500dbe4-07a9-4a4d-ac99-e68592a8af6a`。
- active claim、nonvoid actual consumer、clearance及package classification均为0；开放相关事务为0。

## 生产对象

新增：

- `school_student_package_credit_lots`：owner `postgres`、RLS enabled、浏览器及service_role无直接权限；精确CHECK只允许P002事实，UPDATE/DELETE/TRUNCATE由append-only trigger拒绝。
- `school_is_active_package_credit_origin(uuid)`：owner-only、SECURITY DEFINER、固定`pg_catalog, public`。
- `school_list_student_package_credit_lots(uuid)`：authenticated EXECUTE；函数内部要求有效session、active membership及admin/operator/read_only。
- `school_guard_package_credit_actual_insert()`及lesson表trigger：任何active package origin actual在表写入前稳定拒绝。
- `school_create_lesson_credit_makeup_actual_phase2i_a_legacy(...)`：原writer精确保留、owner-only；原签名由wrapper继续对authenticated提供，先做membership及package拒绝，再委托原函数。

未新增：clearance表/明细/writer、FIFO、offset、writeoff、reversal、package reserve/consume writer及页面。

## Reader与writer接入

| 函数 | 部署前MD5 | 部署后MD5 |
|---|---|---|
| raw remaining | `f5da14743858f89d37f17ba2646ab092` | `63dc342b8eeefd4f65732bbda95e91bc` |
| public remaining | `2111a62f998abeeb6933b47fc5c512aa` | `fc179172c6d1eda1bcf1662604aad3d7` |
| student balances | `81823a464f235e72a439867a2c4d395a` | `5290639714c0aba6967d41d014711d0a` |
| open sources | `3b45f8f09d4d63a952ca5ec42f7214d7` | `564a2ac0532af748f52be2945e76aae5` |
| P0F source lines | `4859d04189893b1dfdecc6a3d66df192` | `ab1db690c2736dfadab474e3951e2118` |
| makeup writer | `3434e8ece09ec210511aec8b8eb1960f` | wrapper `c0f9485be9783283db8c61c75473c43d` |

`public remaining`与`student balances`最终采用SECURITY DEFINER和固定search_path，使现有authenticated调用方能够安全穿过owner-only helper；ACL未扩大。首次正式部署后Chrome发现这一兼容性缺口，立即用exact rollback完整恢复，修正并重新完成本地和生产Gate后再部署。

## 测试与Rehearsal

- 静态对象/边界测试：PASS。
- 隔离PostgreSQL：24项合同PASS；普通来源可读可消费；所有测试业务写入最终ROLLBACK；exact rollback恢复生产定义。
- 本地技术重试均发生在临时集群：缺少postgres同名owner、临时断言表权限、generated列负测包装、psql变量可见性、回滚体MD5诊断及旧断言计数；临时集群每次销毁，未连接生产。
- 生产Rehearsal Attempt 1：Preview JSON路径误按顶层读取；事务退出回滚，独立连接确认全部原MD5和指纹。
- 生产Rehearsal Attempt 2：修正为`preview.*`后完整PASS并ROLLBACK。
- 首次正式部署：DB Gate通过，但Chrome发现authenticated统计reader不能执行owner-only helper；立即执行exact rollback，6个原定义MD5全部精确恢复，业务指纹不变。
- 最终兼容修正Rehearsal：增加authenticated真实角色调用，完整PASS并ROLLBACK；独立连接确认无残留。
- 最终正式部署及postdeploy：PASS。

## 最终生产结果

- package lot：1行，`1200/0/1200`分钟。
- P002 raw/public ordinary remaining：`0`。
- P002 open/makeup source：0行。
- P002 registered/net source：0行；不再形成`-20h/-JPY260,000`。
- 2026-07 Preview：registered source/pending/amount均为0；planned/bill/received历史事实保留。
- package consume/reserve writer：不存在。
- clearance表/明细/writer：不存在。
- P002 lesson MD5仍为`686cbf3a566160bf0de0e30abbdaafa5`。

## 生产Chrome只读验收

- 8月课时统计加载成功，Console warning/error 0。
- “登记待补课完成”来源选项中李天伦/P002命中0；未选择其他来源，未提交。
- 2026-07李天伦月结仍显示planned JPY260,000、已收JPY260,000、system difference CNY0.00。
- CDP捕获20次只读RPC；以正式写动词前缀精确匹配，writer请求0。
- 未点击保存、锁定、生成、取消、补课完成或其他writer按钮。

## 数据不变量

最终School指纹与preflight一致：lessons `771/fca4b09572caba906c3f473654f40170`、settlements `18/481ffa7ed5173da852f0f28ce66c2e9b`、claims `2/fbce39067e6d98167cdb474eb9635c92`、bills `22/e50673ac998ee2d84573a076a64d3d42`、bill lessons `330/e3e2e0044c17864bc66c7e2861176c8b`、revisions `20/ffdc498a6e256aa29064f021f22e4b00`、income `56/5410e66708a01d7017de7dc331d32674`、cash linkages `44/f1c336c43533b9d9b81d88b6fa55feef`、wage locks `104/bb9d5e027e482547ba4ca58b3731651a`、wage details `624/b68ada9b934d4de511da93104228eb4b`、Storage `57/62fac5521274c58c6f6982a0c690c134`、Gate `3/b04952a0603194dd5592124bdee2f7d7`。

Cash指纹亦一致：CNY `75/b5d8b7d466532b90531814e5ccf61ad2`、JPY `34/0dd45c68d17318dc42c4dc57236be0e8`、requests `44/1fc51497aedfaecd72a2ee85714284f0`、accounts `7/89b057e2cdeb7324ef73f73e252174f1`、Storage `0/d41d8cd98f00b204e9800998ecf8427e`。准确表述为：新增package分类事实1行；既有lesson、结算、账单、revision、income、工资、Cash、Storage和Gate变化0。

## 当前UI限制与后续

package余额已经可以通过canonical reader和审计SQL读取。现有普通课时卡片仍可能显示原planned状态文字，因为本阶段没有package UI。建议后续进入Phase 2C-B时只改善页面表达；本阶段不授权也未进入package消费或clearance部署。
