import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const html = readFileSync("wage.html", "utf8");
const page = readFileSync("js/pages/wage-page.js", "utf8");
const app = readFileSync("js/wage-app.js", "utf8");
const css = readFileSync("css/app.css", "utf8");
const config = readFileSync("js/config.js", "utf8");
const filterMarkup = html.match(/<form id="wageFilterForm"[\s\S]*?<\/form>/)?.[0] || "";

for (const id of [
  "wageYearFilter",
  "wageMonthFilter",
  "wageTeacherSelect",
  "wageStudentSelect",
  "wageIncludeInactiveCheckbox",
  "wageStatusSelect",
  "wageKeywordInput",
  "wageResetButton",
]) {
  assert.match(filterMarkup, new RegExp(`id="${id}"`), `missing wage filter: ${id}`);
}

assert.doesNotMatch(filterMarkup, /结算类型|wageSettlementTypeSelect|name="settlementType"/);
assert.match(filterMarkup, /wage-filter-month-field[\s\S]*wage-filter-teacher-field[\s\S]*wage-filter-student-field[\s\S]*wage-include-inactive-field[\s\S]*wage-filter-status-field[\s\S]*wage-filter-keyword-field[\s\S]*wage-filter-flex-spacer[\s\S]*wage-filter-actions[\s\S]*wage-filter-right-spacer/);
assert.match(filterMarkup, /wage-filter-label-spacer[\s\S]*wage-include-inactive-control/);

assert.doesNotMatch(page, /settlementType:\s*""|dom\.settlementTypeSelect|filters\.settlementType/);
assert.doesNotMatch(page, /params\.(?:get|set)\("settlementType"/);
assert.doesNotMatch(page, /row\.settlement_type\s*!==\s*filters/);
assert.match(page, /RETIRED_WAGE_FILTER_PARAMS = \["settlementType", "settlement_type"\]/);
assert.match(page, /searchParams\.has\(name\)[\s\S]*searchParams\.delete\(name\)[\s\S]*history\.replaceState/);
assert.match(page, /teacherId:\s*dom\.teacherSelect\.value/);
assert.match(page, /studentId:\s*dom\.studentSelect\.value/);
assert.match(page, /includeInactive:\s*Boolean\(dom\.includeInactiveCheckbox/);
assert.match(page, /status:\s*dom\.statusSelect\.value/);
assert.match(page, /keyword:\s*dom\.keywordInput\.value\.trim\(\)/);
assert.match(page, /params\.get\("student_id"\)/);
assert.match(page, /params\.set\("include_inactive", "1"\)/);

assert.match(css, /\.wage-filter-panel \.wage-filter-grid\s*\{[\s\S]*?196px[\s\S]*?300px[\s\S]*?300px[\s\S]*?176px[\s\S]*?300px[\s\S]*?300px[\s\S]*?minmax\(0, 1fr\)[\s\S]*?auto[\s\S]*?140px/);
assert.match(css, /\.wage-filter-panel \.wage-filter-actions\s*\{[\s\S]*?gap:\s*12px/);
assert.match(css, /@media \(max-width: 1799px\)[\s\S]*?\.wage-filter-panel \.wage-filter-grid/);
assert.match(css, /@media \(max-width: 767px\)[\s\S]*?\.wage-filter-panel \.wage-filter-grid[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\)/);

const generateCall = page.match(/generateTeacherMonthlyWage\(\{[\s\S]*?\}\)/)?.[0] || "";
assert.match(generateCall, /yearMonth:\s*filters\.month/);
assert.match(generateCall, /teacherId:\s*filters\.teacherId \|\| null/);
assert.doesNotMatch(generateCall, /student|settlementType/i);
assert.match(page, /generationScopeCandidateLessonsForFilters\(filters\)[\s\S]*filters\?\.teacherId/);
assert.match(page, /<td><span class="status-badge status-neutral">\$\{escapeHtml\(settlementTypeLabel\(row\.settlement_type\)\)\}<\/span><\/td>/);

assert.match(html, /wage-filter-single-row-20260808-1/);
assert.match(app, /wage-filter-single-row-20260808-1/);
assert.match(config, /APP_VERSION = "v10\.5\.23"/);
assert.doesNotMatch(css, /\.settlement-filter-panel[^\n{]*\.wage-|\.lesson-filter-panel[^\n{]*\.wage-/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/, `page-layer DML regression: ${pageFile}`);
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker: js/${browserFile}`);
}

console.log("WAGE_FILTER_LAYOUT_STATIC_TEST_PASS");
