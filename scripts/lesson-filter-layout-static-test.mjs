import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const html = readFileSync("lesson.html", "utf8");
const page = readFileSync("js/pages/lesson-page.js", "utf8");
const api = readFileSync("js/api/lesson-api.js", "utf8");
const css = readFileSync("css/app.css", "utf8");
const config = readFileSync("js/config.js", "utf8");

const filterForm = html.match(/<form id="lessonFilterForm"[\s\S]*?<\/form>/)?.[0] || "";
assert.ok(filterForm, "lesson filter form missing");
assert.doesNotMatch(filterForm, /课时类型|lessonTypeSelect|name="lessonType"/);
assert.doesNotMatch(filterForm, /lessonStatusSelect|name="status"|lessonBillableSelect|name="isBillable"/);
assert.match(filterForm, /lessonIncludeInactiveCheckbox[\s\S]*包含暂停\/离校学生/);
assert.match(
  filterForm,
  /lesson-filter-month-field[\s\S]*lesson-filter-week-field[\s\S]*lesson-student-filter-field[\s\S]*lesson-include-inactive-field[\s\S]*lesson-filter-teacher-field[\s\S]*lesson-filter-subject-field[\s\S]*lesson-filter-keyword-field[\s\S]*lesson-filter-flex-spacer[\s\S]*lesson-filter-actions/
);

assert.doesNotMatch(page, /lessonTypeSelect|filters\.lessonType|params\.set\("lesson_type"/);
assert.doesNotMatch(page, /readLessonQueryLessonType/);
assert.doesNotMatch(page, /statusSelect|billableSelect|filters\.status|filters\.isBillable/);
assert.doesNotMatch(page, /normalizeLessonStatusFilter|readLessonQueryBillable|recordMatchesStatusFilter/);
assert.match(page, /clearRetiredLessonFilterQuery\(params\)/);
assert.match(page, /\["lesson_type", "lessonType", "status", "is_billable", "isBillable"\]/);
assert.match(page, /retiredNames\.forEach\(\(name\) => params\["delete"\]\(name\)\)/);
assert.match(page, /window\.history\.replaceState/);
assert.match(page, /params\.get\("include_inactive"\) === "1"/);
assert.match(page, /params\.set\("include_inactive", "1"\)/);
assert.match(page, /params\.set\("student_id", filters\.studentId\)/);
assert.match(page, /params\.set\("view", normalizeLessonView\(filters\.view\)\)/);
assert.match(api, /p_lesson_type:\s*null/);
assert.match(api, /p_status:\s*null/);
assert.match(api, /p_is_billable:\s*null/);

assert.match(html, /lesson-filter-single-row/);
assert.doesNotMatch(html, /lesson-filter-primary-row|lesson-filter-secondary-row/);
assert.match(css, /\.lesson-filter-single-row\s*\{[\s\S]*196px[\s\S]*300px[\s\S]*250px[\s\S]*176px[\s\S]*250px[\s\S]*250px[\s\S]*250px[\s\S]*minmax\(0, 1fr\)[\s\S]*auto/);
assert.match(css, /\.lesson-filter-label-spacer[\s\S]*min-height: 18px/);
assert.match(css, /\.lesson-filter-panel \.lesson-filter-actions\s*\{[\s\S]*grid-column: auto/);
assert.match(css, /@media \(max-width: 1799px\)[\s\S]*\.lesson-filter-single-row[\s\S]*repeat\(4, minmax\(160px, 1fr\)\)/);
assert.match(css, /@media \(max-width: 767px\)[\s\S]*\.lesson-filter-single-row[\s\S]*grid-template-columns: minmax\(0, 1fr\)/);
assert.match(config, /APP_VERSION = "v10\.5\.59"/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/, `page-layer DML regression: ${pageFile}`);
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker: js/${browserFile}`);
}

console.log("LESSON_FILTER_LAYOUT_STATIC_TEST_PASS");
