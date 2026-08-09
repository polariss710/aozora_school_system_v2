# School V2 学生月度结算东京自然月封口实施报告

日期：2026-08-10（Asia/Tokyo）

范围：禁止当前月及未来月份保存／锁定，保留DB权威Preview

生产页面：`v10.5.37 · student-settlement-tokyo-month-close-20260810-3`

## 1. 实施结论

- 长期规则已部署：目标月份必须严格早于DB事务时间换算后的东京当前自然月，才可继续save／lock资格判断。
- 当前月与未来月份均为`can_save=false / can_lock=false`；owner核心writer、service-role online/local wrapper均不能绕过。
- 当前月与未来月份的status及DB权威Preview保持开放；active admin可切换source treatment／adjustment mode并重新Preview，但保存按钮禁用，lock入口不存在。
- DB migration、两支Edge与Pages均部署成功。Edge均为ACTIVE v2；最终功能Pages run `31328565311`成功。
- 真实online/local save成功0、lock成功0、unlock/relock 0；没有创建fixture或生产业务行。
- 未发现硬阻断。当前／未来active draft、ordinary locked及历史完成证据均为0。

## 2. 实时Git

- 分支：`main`。
- 初始HEAD：`e95d13e54c8332e6ef7ba321d6571851bdc7c0a6`；fetch后初始`origin/main`相同，ahead/behind `0/0`，互为祖先。
- 本轮前向提交：
  - `88e0c06` `feat: enforce Tokyo settlement month closure`
  - `01fa452` `fix: expose preview-only closed month state`
  - `6acfb87` `fix: accept authoritative month preview blocker shape`
  - `b304e62` `chore: refresh settlement month guard assets`
  - `dc9110b` `fix: clarify preview-only month copy`
  - 最终报告／current-status提交见本报告后的Git历史。
- 最近结算链路检查点：Phase A `937b70e/1f5168f/109d189`；Phase B `008dfe2`；Phase C `3f3a12d/a318a5e/562c3c7`；Phase C-R1 `32d1cde/2333ac4/569bb85/23906a9/fcc5362`。
- 未reset、rebase、checkout回退或amend任何合法提交。
- 本任务tracked/staged最终无残留；9份外来untracked始终未修改、移动、删除、执行、暂存或提交：

| 路径 | SHA-256 |
|---|---|
| `docs/school-v1-decommission-p1-b2a-session-service-worker-readonly-design-20260810.md` | `75474786ac2de0d9881be17b298acf51b1ad68099b6c1f88c7b0d7aac1736a47` |
| `docs/school-v1-decommission-preflight-p1a-online-evidence-20260809.md` | `1047c2d686a43499e21a43055973475aeb0d52a9fd36c0604aa98ce8ebf0c519` |
| `docs/school-v1-decommission-readonly-investigation-20260809.md` | `3e65e0091e68cd419ac13f0e692fcce99f07041abfcdab3b8786e526a800fcaa` |
| `docs/school-v2-2026-05-06-tuition-candidate-manual-review-completed-20260801.csv` | `272d08531c39b69d1f7392f367229536174e20f54c86883f6cf469c0d2578432` |
| `docs/school-v2-r1b-eight-api-complete-git-diff-20260727.txt` | `5b11f064b4caa01c3015b3b55b6db8bf5c38fd3607182d1b124a120662db2093` |
| `sql/current/school_tuition_atomic_void_reissue_reader_fragment_20260803.sql` | `b8e02481d282fa681d7cef332f70c92b302415563810f4d160c087a65202ab54` |
| `sql/current/school_tuition_atomic_void_reissue_registration_fragment_20260803.sql` | `5dc7c39c2c663a03eff34223a8a86ebcbd091fbf976b2295cbace9940e7fda1a` |
| `sql/current/school_tuition_atomic_void_reissue_schema_fragment_20260803.sql` | `b9c13ddc107a799a914aabbc2eac4663314cacc4f31005ffb4c365902b040773` |
| `sql/current/school_tuition_atomic_void_reissue_writer_fragment_20260803.sql` | `7ed27844edde2b18b241ec9c23de8c5faed07bd8d5bcee2d97b3252f1855939b` |

## 3. 业务合同

- `business_today = (transaction_timestamp() at time zone 'Asia/Tokyo')::date`。
- `current_business_month`为`business_today`所在月份第一天；目标`YYYY-MM`经严格格式、日期构造与规范化回验后转换为月份日期。
- `target_month < current_business_month`：月份guard放行，继续执行既有scope、不可变、source、manifest及并发资格。
- `target_month = current_business_month`：`SETTLEMENT_MONTH_NOT_CLOSED`。
- `target_month > current_business_month`：`SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED`。
- 跨月自动开放来自DB事务时间，不依赖session timezone、Edge/浏览器UTC、设备时间或客户端参数；未新增人工关账表、按钮或Gate。
- 业务模型扩展声明：新表、业务列、enum、人工Gate、双写、fallback及历史解释均为`none`；本轮只实施业务负责人明确批准的既有settlement month可写性语义变更。

## 4. DB实施

文件：

- `sql/current/school_student_settlement_tokyo_month_close_guard_20260810.sql`
- `sql/current/school_student_settlement_tokyo_month_close_guard_rollback_tests_20260810.sql`
- `sql/current/school_student_settlement_tokyo_month_close_guard_postdeploy_20260810.sql`

单一规则源：

- `school_get_student_settlement_month_write_eligibility_at_core(text,timestamptz)`：确定性边界测试helper。
- `school_get_student_settlement_month_write_eligibility_core(text)`：使用东京DB事务时间。
- `school_assert_student_settlement_month_write_allowed(text,text)`：writer共享断言。

接入点：online eligibility/status、online save/lock、local save/lock、source treatment draft core、adjustment draft core及ordinary lock core。online wrapper通过共享eligibility消费月份规则；local/core在写入前显式调用同一断言。unlock/relock定义与语义未改。

完整生产签名及直接EXECUTE合同：

| 签名组 | PUBLIC | anon | authenticated | service_role |
|---|---:|---:|---:|---:|
| 三个month helper（上述完整签名） | 0 | 0 | 0 | 0 |
| `school_get_student_monthly_settlement_online_status(uuid,text)` | 0 | 0 | 1 | 0 |
| `school_get_student_monthly_settlement_online_status_core(uuid,text)` | 0 | 0 | 0 | 0 |
| `school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)` | 0 | 0 | 0 | 1 |
| `school_lock_student_monthly_settlement_online_admin(uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,uuid)` | 0 | 0 | 0 | 1 |
| `school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)` | 0 | 0 | 0 | 1 |
| `school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,text,text,text)` | 0 | 0 | 0 | 1 |
| `school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)` | 0 | 0 | 0 | 0 |
| `school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)` | 0 | 0 | 0 | 0 |
| `school_lock_student_monthly_settlement(uuid,text,text)` | 0 | 0 | 0 | 0 |

以上均owner `postgres`、`SECURITY DEFINER`、`search_path=pg_catalog, public`。settlement/draft三表对anon/authenticated/service_role的I/U/D/T grant计数0。blocker顺序保持：scope不唯一 → ordinary locked → 历史消费 → 历史零结转 → successor/canonical bill/不可变学费 → 工资不可变 → 月份 → source empty → 其他资格。

## 5. Edge

- 修改共享安全错误映射；两支独立函数均重新部署：
  - `save-student-settlement-draft`：ACTIVE v2，ID `d643ab21-9306-4031-b5f4-2727e904a48a`，bundle SHA-256 `2a280ba1e64e52737f229b687bf2b542108107500c93db70fb2893d87e77a91e`。
  - `lock-student-settlement`：ACTIVE v2，ID `8fab9f4d-96de-43c8-8a15-98cec8096f9b`，bundle SHA-256 `603ece4399abd29ce8cd2b817b9c3aee8caae3c79f95e47932a3b08a5106c6d4`。
- 两个月份错误映射为安全409/`stop`，非法月份为422/`repreview`；无SQL、函数名、JWT、service-role或连接信息泄露。
- 精确Origin、用户JWT `auth.getUser`、active-admin、actor绑定、响应allowlist及server-only service-role边界不变；save不调用lock，lock不调用save。

## 6. 页面

- 当前月：普通scope显示“当前月份仅可预览”及“只读预览”按钮；可切换模式并重新读取DB Preview；“保存草稿”禁用。
- 未来月：显示“未来月份仅可预览”；Preview可用，保存禁用。
- Preview资格只消费DB稳定blocker与effective status，不读取浏览器日期，不提交today或`is_month_closed`；save资格仍唯一使用DB `can_save`。
- 更高优先级不可变blocker继续只读且不开放Preview表单，例如孙陈锋2026-08仍显示“后继学费事实已冻结”。
- lock UI/handler仍不存在；unlock/relock页面、API及运行时引用仍为0；page-layer直接RPC/DML为0；浏览器service-role为0；`js/legacy-core.js`零修改。
- 筛选draft/applied边界保持：选择09月后列表和URL不自动刷新，只有点击“查询”才应用。

## 7. 数据检查

部署前后均为：

| 当前／未来事实 | 数量 |
|---|---:|
| active source treatment draft | 0 |
| active adjustment draft | 0 |
| ordinary locked settlement | 0 |
| historical completion evidence | 0 |

没有需要删除、unlock、void或业务处理的异常；新规则只阻止后续save/lock。

## 8. 测试

- 明确ROLLBACK rehearsal通过；正式migration与rollback矩阵组合运行并最终显式ROLLBACK，fixture residue 0。
- 时间：上月、当前月、下月、更远未来、非法月份、东京月初00:00、UTC/东京边界、2026-12→2027-01、2028闰年2月、session UTC/Tokyo/Los Angeles一致。
- status：当前／未来false且Preview非空；scope-not-unique及successor优先；已结束月份继续既有资格。
- writer：current/future × online save/lock、local save/lock、两个core draft及core lock共14个负向路径均在业务写入前稳定拒绝；没有成功save/lock。
- 权限：helper/core owner-only，online/local仅service-role wrapper，表DML 0，unlock/relock不变。
- Edge：严格parser、Origin/JWT/admin、响应allowlist、月份错误映射及独立部署单元测试通过。
- 页面：全部相关语法、单元、静态、P0-F Preview、P0-B2 authority、trusted tool、business error、本地筛选/布局回归通过。
- Chrome：2026-08六个普通scope、2026-09两个scope均Preview可用/save禁用；390px `scrollWidth/clientWidth=390/390`；Console error/warning 0。

测试过程中两次SQL脚本技术修正均由事务自动回滚：一次测试引用了不存在的membership列，一次online lock负向fixture缺少必填draft UUID；没有业务持久变化。Chrome首次验收发现月份blocker同时位于`immutable_blocker`的真实status形状，使用前向提交`6acfb87`修复，未回退已部署合同。

## 9. 全scope矩阵

- 部署前：39 scope，`can_save=true` 11（全部位于当前／未来月份），`can_lock=true` 0。
- 部署后：39/39 `can_save=false`，`can_lock=true` 0，资格结构漂移0。
- 最终blocker分组：scope不唯一11、ordinary locked6、历史消费1、历史零结转4、successor4、当前月未结束6、未来月份7。
- 当前月孙陈锋继续命中更高优先级successor；普通6 scope命中`SETTLEMENT_MONTH_NOT_CLOSED`。
- 未来9/10/11月合计7 scope命中`SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED`；月份优先于source empty。
- 已结束月份不受月份guard阻断，继续由既有不可变、source及manifest事实决定；当前生产没有其他可save scope。

## 10. 生产零变化

School关键指纹部署前后完全一致：settlements `18/481ffa7e…`、adjustment drafts `7/0b162413…`、source drafts `1/c2a01866…`、历史证据 `4/9cb22ef4…`、lessons `744/3cd0c2ce…`、income `55/c55f82c…`、bills `22/e50673ac…`、revisions `20/ffdc498a…`、wage locks `103/ea395407…`、wage details `612/1d45d0ce…`、payment requests `51/6ce63e69…`、expenses `47/34a7a323…`、account transactions `187/00516a76…`、membership `1/332d6f2e…`。

- Cash：CNY `74/070c262e…`、external requests `43/f4b1876e…`、JPY `31/95ab7cf…`，完全一致。
- Storage：bucket `1/9b1be72d…`、objects `57/62fac552…`，完全一致。
- Auth UUID/email/role/aud/confirmed_at/last_sign_in_at及membership不变。生产Chrome会话刷新使唯一`auth.users.updated_at`更新为`2026-08-09 18:09:01.977099+00`，因此全行易变指纹由`e25b6f…`变为`8548bb…`；这是既有Auth会话元数据刷新，不是本任务Auth/membership writer或授权变化。
- Gate保持`student_tuition_preview=enabled / student_tuition_generate=blocked / student_tuition_cash_submit=enabled`。
- 成功online/local save 0、成功online/local lock 0、unlock/relock 0；真实业务DML 0。DB持久变化只限函数定义、ACL及comment；Edge仅代码部署；Pages仅静态资产。

## 11. Pages部署

- 最终功能run：`31328565311`，commit `dc9110bc3c5b0fd96c6843b8f96f71250699b23d`，success。
- 生产版本：`v10.5.37`；资产：`student-settlement-tokyo-month-close-20260810-3`。
- 中间前向修复run `31328222953 / 31328367819 / 31328423932`均成功；最终资产包含status形状兼容与中性Preview文案。
- 最终Chrome Network：89请求，GET47/只读RPC POST40/OPTIONS2，失败0；save/lock/unlock/relock/core writer请求0，浏览器service-role 0；Console error/warning 0。

## 12. 回滚

- 已形成的合法DB、Edge、Pages与Git提交不得reset/rebase/amend或回退业务事实。
- 如发现实现缺陷，只能创建新的前向修复；不得恢复“当前／未来月份可写”的旧错误合同。
- 不删除draft、不修改settlement/lesson/bill/income/wage/Cash/Auth/Storage事实，不修改Gate。

## 13. 后续

1. 继续等待2026-08自然结束；Phase D仍未开放。
2. 2026-09-01 00:00 Asia/Tokyo后重新运行白名单只读preflight，确认月份blocker自动消失且其他实时资格通过。
3. 由业务负责人批准精确学生scope与source treatment／adjustment mode。
4. 下一轮只对获批scope执行单次真实save，并status-first验收；不得在本轮继续save或lock。
