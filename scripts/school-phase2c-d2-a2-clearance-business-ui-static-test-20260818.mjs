import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const html = read("lesson.html");
const app = read("js/lesson-app.js");
const page = read("js/pages/lesson-page.js");
const api = read("js/api/lesson-clearance-api.js");
const component = read("js/components/lesson-clearance-workspace.js");
const state = read("js/utils/lesson-clearance-state.js");
const css = read("css/lesson-clearance.css");
const config = read("js/config.js");

assert.match(config, /APP_VERSION = "v10\.5\.52"/);
for (const source of [html, app, page, component]) {
  assert.match(source, /phase2c-d2-a3-clearance-completion-20260818-1/);
}
assert.match(api, /school_list_lesson_clearance_pending_balances_v3/);
assert.doesNotMatch(api, /school_list_lesson_clearance_pending_balances_v2/);
assert.equal((api.match(/supabase\.rpc\(/g) || []).length, 2);
assert.doesNotMatch(page + component + state + html, /\.rpc\s*\(/);
assert.doesNotMatch(page + component + state + html, /\.from\s*\([^)]*\)\s*\.\s*(insert|update|delete|upsert)\s*\(/);

assert.doesNotMatch(html, /id="lessonClearanceEntityFilter"/);
assert.doesNotMatch(state, /businessEntityId/);
assert.doesNotMatch(component, /dom\.entityFilter/);
assert.match(state, /pending\.business_entity_id !== overage\.business_entity_id/);
assert.match(state, /该学生存在不同业务范围的课时余额，当前不能合并清偿，请分别处理/);
assert.match(component, /待补业务范围编号/);
assert.match(component, /超额业务范围编号/);

const workspaceHtml = html.match(/id="lessonClearanceWorkspaceDialog"[\s\S]*?id="lessonClearanceFinalConfirmDialog"/)?.[0] || "";
assert.doesNotMatch(workspaceHtml, />业务归属</);
assert.doesNotMatch(workspaceHtml, /个人名义/);
assert.doesNotMatch(component, /待补来源/);
assert.doesNotMatch(component, /DB权威Preview|读取DB权威Preview|DB Preview绑定|DB权威行|当前available|DB可用金额|可作为候选/);
assert.match(component, /选择待补对象/);
assert.match(component, /核对清偿结果/);
assert.match(component, /系统核对结果/);
assert.match(component, /建议顺序（较早产生的余额优先）/);
assert.match(component, /按超额产生时间排序/);
assert.match(component, /该超额课时已被其他结算或清偿流程占用，当前不可选择/);

assert.match(component, /row\.operational_display_date/);
assert.match(component, /selectedPending\.operational_display_date/);
assert.doesNotMatch(component, /date_trunc|startOfWeek|setDate\(|getDay\(/);
assert.match(component, /lesson-clearance-system-details/);
assert.match(component, /<summary>系统详情<\/summary>/);
assert.match(css, /\.lesson-clearance-system-details/);
assert.doesNotMatch(css, /lesson-clearance-system-details\[open\]/);
assert.match(component, /业务范围当前名称/);
assert.match(component, /待补对象指纹/);
assert.match(component, /核对清单指纹/);
assert.match(component, /原始错误信息/);

assert.match(component, /businessNoteValue\.textContent = inputSnapshot\.businessNote/);
assert.doesNotMatch(component, /\$\{inputSnapshot\.businessNote\}/);
assert.match(component, /本动作只建立课时差额清偿事实，不修改原课时、老师工资、既有账单或收款/);
assert.match(state, /previewInputSnapshot/);
assert.match(state, /writer_revalidation_required/);
assert.match(state, /same_business_entity/);
assert.match(state, /same_unit_price/);
assert.doesNotMatch(component + state, /localStorage|sessionStorage/);

assert.match(css, /@media \(max-width: 480px\)/);
assert.match(css, /overflow-x: auto/);
assert.match(css, /grid-template-columns: 1fr/);

console.log("SCHOOL_PHASE2C_D2_A2_CLEARANCE_BUSINESS_UI_STATIC_PASS");
