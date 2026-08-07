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
assert.match(filterForm, /lessonIncludeInactiveCheckbox[\s\S]*包含暂停\/离校学生/);
assert.match(filterForm, /lesson-student-filter-field[\s\S]*lesson-include-inactive-field/);

assert.doesNotMatch(page, /lessonTypeSelect|filters\.lessonType|params\.set\("lesson_type"/);
assert.doesNotMatch(page, /readLessonQueryLessonType/);
assert.match(page, /clearLegacyLessonTypeQuery\(params\)/);
assert.match(page, /params\["delete"\]\("lesson_type"\)/);
assert.match(page, /params\["delete"\]\("lessonType"\)/);
assert.match(page, /window\.history\.replaceState/);
assert.match(page, /params\.get\("include_inactive"\) === "1"/);
assert.match(page, /params\.set\("include_inactive", "1"\)/);
assert.match(page, /params\.set\("student_id", filters\.studentId\)/);
assert.match(page, /params\.set\("view", normalizeLessonView\(filters\.view\)\)/);
assert.match(api, /p_lesson_type:\s*null/);

assert.match(html, /lesson-filter-primary-row[\s\S]*lesson-filter-secondary-row/);
assert.match(css, /\.lesson-filter-primary-row[\s\S]*196px[\s\S]*minmax\(0, 176px\)/);
assert.match(css, /\.lesson-filter-secondary-row[\s\S]*repeat\(3, minmax\(0, 450px\)\)[\s\S]*minmax\(0, 1fr\)[\s\S]*auto/);
assert.match(css, /minmax\(0, 176px\)/);
assert.match(css, /\.lesson-filter-panel \.lesson-filter-actions\s*\{[\s\S]*grid-column: auto/);
assert.match(css, /@media \(max-width: 767px\)[\s\S]*\.lesson-filter-primary-row,[\s\S]*\.lesson-filter-secondary-row[\s\S]*grid-template-columns: minmax\(0, 1fr\)/);
assert.match(config, /APP_VERSION = "v10\.5\.19"/);

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
