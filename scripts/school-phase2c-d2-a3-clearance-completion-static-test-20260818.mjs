import assert from "node:assert/strict";
import { assertAppVersionAtLeast } from "./static-test-helpers.mjs";
import fs from "node:fs";

const read = (path) => fs.readFileSync(path, "utf8");
const html = read("lesson.html");
const app = read("js/lesson-app.js");
const page = read("js/pages/lesson-page.js");
const api = read("js/api/lesson-clearance-api.js");
const component = read("js/components/lesson-clearance-workspace.js");
const state = read("js/utils/lesson-clearance-state.js");
const config = read("js/config.js");
const cacheKey = "phase2c-d2-a3-clearance-completion-20260818-1";

assertAppVersionAtLeast(config, "v10.5.52");
for (const source of [html, app, page, component]) assert.match(source, new RegExp(cacheKey));

for (const [label, id] of [
  ["选择待补对象", "lessonClearancePendingSelect"],
  ["选择可用超额", "lessonClearanceOverageSelect"],
  ["本次清偿分钟", "lessonClearanceAllocatedMinutesInput"],
  ["清偿日期", "lessonClearanceOperationDateInput"],
  ["业务说明", "lessonClearanceBusinessNoteInput"],
]) {
  assert.match(component, new RegExp(`<label class="field(?: is-wide)?" for="${id}"><span>${label} <b class="required-mark">必填</b>`));
}
assert.equal((component.match(/class="required-mark">必填<\/b>/g) || []).length, 5);
assert.doesNotMatch(component, /偏离建议顺序原因 <b class="required-mark">必填/);

assert.match(component, /清偿结果正在确认，请勿重复提交。/);
assert.match(component, /系统无法确认幂等结果与当前核对一致，请勿重复提交。/);
assert.match(component, /state\.historyMatchesCreateSnapshot/);
assert.match(component, /state\.createResultMatchesSnapshot/);
assert.match(component, /onCreateSuccess/);
assert.match(component, /onCreateRefreshFailure/);
assert.match(page, /课时差额清偿成功：\$\{allocatedMinutes\}分钟。/);
assert.match(page, /清偿已成功，但页面刷新失败，请重新查询。/);
assert.match(page, /refreshLessonMonthPreservingFilters\(filters\.month, filters\)/);

assert.equal((component.match(/api\.createClearance\(payload\)/g) || []).length, 1);
assert.equal((component.match(/api\.reverseClearance\(payload\)/g) || []).length, 1);
assert.doesNotMatch(page + component + state + html, /\.rpc\s*\(/);
assert.doesNotMatch(page + component + state + html, /\.from\s*\([^)]*\)\s*\.\s*(insert|update|delete|upsert)\s*\(/);
assert.doesNotMatch(component + state, /localStorage|sessionStorage/);
assert.equal((api.match(/supabase\.rpc\(/g) || []).length, 2);

console.log("SCHOOL_PHASE2C_D2_A3_CLEARANCE_COMPLETION_STATIC_PASS");
