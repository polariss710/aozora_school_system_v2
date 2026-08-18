# School V2 私塾打工写后刷新折叠状态修复

## 结论

生产`v10.5.53`已将查询型加载与写后刷新分流。首次加载、查询及`popstate`使用`canonical_from_filters`；所有既有writer成功后的reader刷新使用`preserve_current`。生成actual成功后，当前展开的课时卡片继续展开并显示新actual，工资区域保持自己独立的展开状态。API/RPC、数据库及业务数据均未修改。

## 调用结构

`loadPageData`不提供collapse policy默认值，缺失或未知值稳定抛出`PTW_COLLAPSE_POLICY_INVALID`。页面只通过两个语义入口调用：

| 入口 | 策略 | 调用方 |
| --- | --- | --- |
| `loadPageDataForQuery()` | `canonical_from_filters` | cold/reload初始化、查询submit、back/forward `popstate` |
| `refreshPageDataAfterMutation()` | `preserve_current` | 新增/复制保存、生成actual、planned/actual编辑、删除、结算lock/unlock、收入记录生成 |

reset仍只恢复控件、清除校验并显示`已重置筛选条件`，不调用任一加载入口。

## Preserve合同

reader开始前快照课时/工资各自已渲染key和折叠集合；reader成功后，课时只保留`旧expanded ∩ 新key`，工资保留旧key的原状态并将新key默认加入collapsed，消失key自然删除。DOM重绘只消费更新后的集合。mutation refresh不调用URL同步、月份导航、view切换、scroll或整页reload。

writer成功但reader失败时不清空旧数据、DOM或折叠集合，不重试writer，页面只显示：

`保存已成功，但页面刷新失败。请重新查询确认，不要重复提交。`

## 测试

Node专用Mock验证生成actual时writer 1、reader 3，新actual进入结果，课时和工资均保持诺应教育展开；writer失败时reader 0；writer成功但reader失败时writer仍为1、重试0、旧数据及两套集合保持。纯状态测试覆盖key消失、新key默认折叠、两区独立、非法policy拒绝及全部raw `loadPageData`调用仅存在于两个语义wrapper与函数定义。

本地Chrome全Mock页面结果为`PTW_MUTATION_REFRESH_BROWSER_TEST_PASS`：writer 1、reader 3、actual可见、lessons/wage均展开诺应、reader失败writer重试0，Console warning/error 0。P1-B reset、P1-B1 collapse及P0-A2权限静态回归、JS语法、页面直接RPC/DML扫描和`git diff --check`全部通过。`js/api/part-time-work-api.js`SHA-256保持`476d5364e7f32ac00b2644e0285ccd3865debd9eff455e73d57cd57d84e524a9`。

## 生产无写验收

实现commit`5f81ed7`已推送`origin/main`，Pages run`32139459736`成功。生产静态资源的app、page、filter-state及config均命中`ptw-p1-b2-mutation-collapse-20260818-1`，页面显示`v10.5.53`。

- cold全部及再次查询全部：lessons/wage全部折叠；
- 查询诺应教育：lessons/wage仅诺应展开；
- reset：draft恢复全部、toast准确，URL及两区诺应展开状态不变，Network 0；
- reset后查询：URL恢复全部筛选，两区全部折叠；
- Network观察6个请求全部为2组既有lesson/settlement reader，writer 0；
- 390px为inner/body/root `390/390/390`，filter/lessons/wage为`346/346/346`，无横向溢出；
- Console warning/error 0。

生产未打开或提交新增、编辑、复制、删除、生成actual、lock/unlock或收入Dialog。未执行SQL或RPC测试，数据库写入、业务数据、School/Cash/Storage/Gate变化均为0。
