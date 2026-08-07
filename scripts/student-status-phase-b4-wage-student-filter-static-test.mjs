import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const api = readFileSync("js/api/wage-api.js", "utf8");
const page = readFileSync("js/pages/wage-page.js", "utf8");
const app = readFileSync("js/wage-app.js", "utf8");
const html = readFileSync("wage.html", "utf8");
const css = readFileSync("css/app.css", "utf8");
const config = readFileSync("js/config.js", "utf8");
const statusApi = readFileSync("js/api/student-status-api.js", "utf8");

assert.match(html, /<span>学生<\/span>[\s\S]*id="wageStudentSelect"[\s\S]*>全部学生<\/option>/);
assert.match(html, /id="wageIncludeInactiveCheckbox"[\s\S]*包含暂停\/离校学生/);
assert.match(html, /placeholder="老师 \/ 学生 \/ 类型 \/ 状态"/);
assert.match(html, /学生仅用于筛选查看，生成工资和支付仍按完整工资快照范围执行/);
assert.doesNotMatch(html, /wageBusinessEntitySelect|name="businessEntityId"/);
assert.match(css, /wage-include-inactive-control/);

assert.match(api, /fetchStudentMonthCandidates/);
assert.match(statusApi, /school_list_student_month_candidates_v1/);
assert.match(statusApi, /p_target_month:\s*`\$\{normalizedMonth\}-01`/);
assert.match(statusApi, /p_include_inactive:\s*Boolean\(includeInactive\)/);
assert.match(statusApi, /p_selected_student_id:\s*selectedStudentId \|\| null/);
assert.match(api, /school_teacher_wage_lock_details"\)[\s\S]*\.select\("lock_id,student_id"\)/);
assert.equal((api.match(/\.is\("voided_at", null\)/g) || []).length >= 2, true);
assert.doesNotMatch(api, /select\("id,student_code,name,display_name,status"\)/);

assert.match(page, /studentId:\s*""/);
assert.match(page, /includeInactive:\s*false/);
assert.match(page, /student\.resolved_status === "paused"[\s\S]*本月暂停/);
assert.match(page, /student\.resolved_status === "left"[\s\S]*本月已离校/);
assert.match(page, /wageLockStudentIdsByLockId\.get\(row\.id\)\?\.has\(filters\.studentId\)/);
assert.match(page, /filters\.studentId && row\.student_id !== filters\.studentId/);
assert.match(page, /params\.get\("student_id"\)/);
assert.match(page, /params\.get\("include_inactive"\) === "1"/);
assert.match(page, /params\.set\("include_inactive", "1"\)/);
assert.doesNotMatch(page, /params\.(?:get|set)\("business_entity_id"/);
assert.doesNotMatch(page, /params\.(?:get|set)\("businessEntityId"/);

const generateCall = page.match(/generateTeacherMonthlyWage\(\{[\s\S]*?\}\)/)?.[0] || "";
assert.match(generateCall, /yearMonth:\s*filters\.month/);
assert.match(generateCall, /teacherId:\s*filters\.teacherId \|\| null/);
assert.doesNotMatch(generateCall, /student|businessEntity/i);
assert.match(page, /generationScopeCandidateLessonsForFilters\(filters\)[\s\S]*filters\?\.teacherId/);
assert.doesNotMatch(
  page.match(/function generationScopeCandidateLessonsForFilters[\s\S]*?\n\}/)?.[0] || "",
  /studentId|businessEntityId/,
);
assert.match(page, /学生仅用于筛选查看，生成老师工资仍按完整工资快照范围执行/);

assert.match(app, /phase-b4-remaining-20260807-1/);
assert.match(config, /APP_VERSION = "v10\.5\.\d+"/);
assert.doesNotMatch(page, /legacy-core\.js/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(
    source,
    /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,
    `page-layer table DML regression: ${pageFile}`,
  );
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker: js/${browserFile}`);
}

console.log("STUDENT_STATUS_PHASE_B4_WAGE_STUDENT_FILTER_STATIC_TEST_PASS");
