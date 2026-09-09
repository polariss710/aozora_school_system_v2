import assert from "node:assert/strict";
import fs from "node:fs";

const read = (path) => fs.readFileSync(path, "utf8");
const html = read("lesson.html");
const page = read("js/pages/lesson-page.js");
const api = read("js/api/lesson-clearance-api.js");
const component = read("js/components/lesson-clearance-workspace.js");
const state = read("js/utils/lesson-clearance-state.js");
const css = read("css/lesson-clearance.css");

assert.match(html, /id="openLessonClearanceWorkspaceButton"[^>]*>课时余额与清偿</);
assert.match(html, /id="lessonClearanceWorkspaceDialog"/);
assert.match(html, /id="lessonClearanceConfirmButton"[^>]*disabled/);
// Historical cache-key snapshots are intentionally not asserted; see the week-close handoff section 8.6.

assert.match(page, /lessonClearanceApi/);
assert.match(page, /createLessonClearanceWorkspace/);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(page, /\.from\s*\([^)]*\)\s*\.\s*(insert|update|delete|upsert)\s*\(/);

const rpcNames = [
  "school_list_lesson_clearance_pending_balances_v3",
  "school_list_lesson_clearance_available_overages_v2",
  "school_list_student_package_credit_lots_v2",
  "school_list_cross_month_makeup_projection_v2",
  "school_get_lesson_clearance_dashboard_summary_v1",
  "school_preview_lesson_clearance_v2",
  "school_preview_lesson_clearance_reversal_v1",
  "school_list_lesson_clearance_history_v2",
];
for (const name of rpcNames) assert.equal(api.split(name).length - 1, 1, name);
assert.doesNotMatch(api, /\.from\s*\(|\.insert\s*\(|\.update\s*\(|\.delete\s*\(|\.upsert\s*\(/);
assert.doesNotMatch(component, /\.rpc\s*\(|\.from\s*\(|\.insert\s*\(|\.update\s*\(|\.delete\s*\(|\.upsert\s*\(/);
assert.doesNotMatch(component + state, /localStorage|sessionStorage/);

assert.match(component, /系统不会自动选择待补对象/);
assert.match(component, /请选择，不自动勾选/);
assert.match(component, /package_business_type/);
assert.match(component, /套餐余额与普通待补余额隔离/);
assert.match(component, /尚无课时差额清偿记录/);
assert.match(component, /current_reference: "当前主数据引用"/);
assert.match(component, /immutable_reference: "不可变引用"/);
assert.match(component, /unavailable: "证据不可用"/);
assert.match(component, /本次清偿跨老师或跨科目/);
assert.match(component, /不会回写已锁月结、账单、收款或工资/);
assert.match(component, /writer_revalidation_required/);
assert.match(component, /请求编号/);

const resetBlock = component.match(/dom\.filterReset\?\.addEventListener\("click",[\s\S]*?\n    \}\);/)?.[0] || "";
assert.match(resetBlock, /state\.resetDraftFilters\(\)/);
assert.match(resetBlock, /已重置筛选条件/);
assert.doesNotMatch(resetBlock, /loadData\(|renderAll\(|renderTabPanel\(|history\.pushState|location\./);
const queryBlock = component.match(/dom\.filterForm\?\.addEventListener\("submit",[\s\S]*?\n    \}\);/)?.[0] || "";
assert.match(queryBlock, /state\.applyDraftFilters\(\)/);
assert.match(queryBlock, /loadData\(\)/);

assert.doesNotMatch(component, /initial_credit_minutes\s*[-+]|remaining_minutes\s*\*|available_minutes\s*\*/);
assert.doesNotMatch(component, /unit_price_jpy\s*\*|remaining_amount_jpy\s*=|available_amount_jpy\s*=/);
assert.match(state, /Number\(row\.fifo_rank\) !== 1/);
assert.match(state, /this\.selection\.requestIdentity = this\.selection\.pendingId && this\.selection\.overtimeId \? uuid\(\) : ""/);

assert.match(css, /@media \(max-width: 1200px\)/);
assert.match(css, /@media \(max-width: 768px\)/);
assert.match(css, /@media \(max-width: 480px\)/);
assert.match(css, /overflow-x: auto/);
assert.match(css, /grid-template-rows: auto minmax\(0, 1fr\) auto/);

// 筛选候选是 auxiliary，不能由主结果派生。学生是唯一在服务端生效的筛选，
// 按学生查询后返回的行只剩这个人；照返回行重建下拉，它就会塌缩成一项，
// 逼着业务人员先重置才能换人查。
const optionsBlock = component.match(/function populateFilterOptions\(\) \{[\s\S]*?\n  \}/)?.[0] || "";
// 两个筛选都在服务端生效：studentId 影响六个 reader，settlementMonth 影响
// fetchCrossMonthProjection，而它的 items 也进 optionRows()。只守住其一，
// 按月份查询照样会让候选变窄。
assert.match(optionsBlock, /!state\.appliedFilters\.studentId/);
assert.match(optionsBlock, /!state\.appliedFilters\.settlementMonth/);
assert.match(optionsBlock, /filterOptions\.students/);
const closeBlock = component.match(/function closeDialog\(force = false\) \{[\s\S]*?\n  \}/)?.[0] || "";
assert.match(closeBlock, /filterOptions = null/);

// 清偿成功后工作区【不关闭】：连续清偿是常态。但刚清掉的那笔必须从候选里消失，
// 否则留在屏幕上的是一份已经不成立的选择。
const successBlock = component.match(/async function completeCreateSuccess\([\s\S]*?\n  \}/)?.[0] || "";
assert.doesNotMatch(successBlock, /closeDialog\(/);
assert.match(successBlock, /closeFinalDialog\(true\)/);
assert.match(successBlock, /state\.clearSelection\(\)/);
// loadData 开头会清空提示；读取失败时它写的是自己的错误，成功提示不得盖掉它。
assert.match(successBlock, /if \(await loadData\(\)\) \{/);

// 三环缓存链必须同键。workspace 的 ?v= 写在 lesson-page.js 里，浏览器不重新取
// lesson-page.js 就永远拿不到新的 workspace。部分升比整体不升更糟：新页面配旧组件，
// 症状是改动「没生效」，而屏幕上没有任何线索指向缓存。
const app = read("js/lesson-app.js");
const versionChain = [
  ["lesson.html → lesson-app.js", html, /\.\/js\/lesson-app\.js\?v=([^"']+)/],
  ["lesson-app.js → lesson-page.js", app, /\.\/pages\/lesson-page\.js\?v=([^"']+)/],
  ["lesson-page.js → lesson-clearance-workspace.js", page, /\.\.\/components\/lesson-clearance-workspace\.js\?v=([^"']+)/],
].map(([link, source, pattern]) => {
  const matched = pattern.exec(source);
  assert.ok(matched, `${link}: 找不到 ?v= 缓存版本键`);
  return [link, matched[1]];
});
for (const [link, key] of versionChain) {
  assert.equal(key, versionChain[0][1], `${link} 的版本键与链上其余不一致 ⇒ 新页面会配到旧组件`);
}

console.log("SCHOOL_PHASE2C_D1_CLEARANCE_WORKSPACE_STATIC_PASS");
