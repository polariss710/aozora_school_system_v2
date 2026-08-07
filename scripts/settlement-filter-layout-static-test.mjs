import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const html = readFileSync("settlement.html", "utf8");
const css = readFileSync("css/app.css", "utf8");
const page = readFileSync("js/pages/settlement-page.js", "utf8");
const app = readFileSync("js/settlement-app.js", "utf8");
const config = readFileSync("js/config.js", "utf8");
const cacheKey = "settlement-filter-single-row-20260808-1";

const filterForm = html.match(/<form id="settlementFilterForm"[\s\S]*?<\/form>/)?.[0] || "";
const studentField = filterForm.match(/<div class="field student-month-candidate-field settlement-student-filter-field">[\s\S]*?<\/div>/)?.[0] || "";

assert.ok(filterForm, "settlement filter form missing");
assert.ok(studentField, "settlement student field missing");
for (const id of [
  "settlementYearFilter",
  "settlementMonthFilter",
  "settlementStudentSelect",
  "settlementIncludeInactiveCheckbox",
  "settlementStatusSelect",
  "settlementKeywordInput",
  "settlementResetButton",
]) {
  assert.match(filterForm, new RegExp(`id="${id}"`), `missing settlement filter ${id}`);
}
assert.doesNotMatch(studentField, /settlementIncludeInactiveCheckbox/, "include inactive must be independent of student field");
assert.match(
  filterForm,
  /settlement-filter-month-field[\s\S]*settlement-student-filter-field[\s\S]*settlement-include-inactive-field[\s\S]*settlement-filter-status-field[\s\S]*settlement-filter-keyword-field[\s\S]*settlement-filter-flex-spacer[\s\S]*settlement-filter-actions[\s\S]*settlement-filter-right-spacer/
);

assert.match(css, /Student monthly settlement owns this compact single-row filter layout/);
assert.match(css, /\.settlement-filter-panel \.settlement-filter-grid\s*\{[\s\S]*196px[\s\S]*300px[\s\S]*176px[\s\S]*300px[\s\S]*300px[\s\S]*minmax\(0, 1fr\)[\s\S]*auto[\s\S]*140px/);
assert.match(css, /\.settlement-filter-panel \.settlement-filter-actions\s*\{[\s\S]*grid-column: auto;[\s\S]*gap: 12px/);
assert.match(css, /@media \(max-width: 1799px\)[\s\S]*\.settlement-filter-right-spacer[\s\S]*display: none/);
assert.match(css, /@media \(max-width: 767px\)[\s\S]*\.settlement-filter-panel \.settlement-filter-grid[\s\S]*grid-template-columns: minmax\(0, 1fr\)/);
assert.match(css, /@media \(max-width: 767px\)[\s\S]*\.settlement-filter-label-spacer[\s\S]*display: none/);

assert.match(page, /readSettlementQuery\(\)/);
assert.match(page, /writeStudentCandidateQuery\(url\.searchParams, filters\)/);
assert.match(page, /setOptionalQuery\(url\.searchParams, "status", filters\.status\)/);
assert.match(page, /setOptionalQuery\(url\.searchParams, "keyword", filters\.keyword\)/);
assert.match(page, /fetchStudentMonthCandidates\(\{[\s\S]*month:[\s\S]*includeInactive:[\s\S]*selectedStudentId:/);
assert.match(page, /row\.student_id !== filters\.studentId/);

assert.match(html, new RegExp(`app\\.css\\?v=${cacheKey}`));
assert.match(html, new RegExp(`settlement-app\\.js\\?v=${cacheKey}`));
assert.match(app, new RegExp(`config\\.js\\?v=${cacheKey}`));
assert.match(config, /APP_VERSION = "v10\.5\.22"/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(
    source,
    /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,
    `page-layer DML regression: ${pageFile}`
  );
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker: js/${browserFile}`);
}

console.log("SETTLEMENT_FILTER_LAYOUT_STATIC_TEST_PASS");
