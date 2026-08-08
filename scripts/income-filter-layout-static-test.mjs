import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const html = read("income.html");
const page = read("js/pages/income-page.js");
const app = read("js/income-app.js");
const api = read("js/api/income-api.js");
const css = read("css/app.css");
const config = read("js/config.js");
const filterMarkup = html.match(/<form id="incomeFilterForm"[\s\S]*?<\/form>/)?.[0] || "";
const bindEvents = page.match(/function bindEvents\(\) \{[\s\S]*?\n\}/)?.[0] || "";
const candidateRefresh = page.match(/async function refreshDraftStudentCandidates\(\) \{[\s\S]*?\n\}\n\nasync function queryDraftFilters/)?.[0] || "";
const queryFunction = page.match(/async function queryDraftFilters\([\s\S]*?\n\}\n\nasync function resetAndQueryFilters/)?.[0] || "";
const resetFunction = page.match(/async function resetAndQueryFilters\(\) \{[\s\S]*?\n\}\n\nasync function loadIncomeMonth/)?.[0] || "";

for (const id of [
  "incomeYearFilter",
  "incomeMonthFilter",
  "incomeStudentSelect",
  "incomeIncludeInactiveCheckbox",
  "incomeAccountSelect",
  "incomeCategorySelect",
  "incomeCurrencySelect",
  "incomeResetButton",
]) {
  assert.match(filterMarkup, new RegExp(`id="${id}"`), `missing income filter: ${id}`);
}

assert.match(filterMarkup, /income-filter-month-field[\s\S]*income-filter-student-field[\s\S]*income-include-inactive-field[\s\S]*income-filter-account-field[\s\S]*income-filter-category-field[\s\S]*income-filter-currency-field[\s\S]*income-filter-flex-spacer[\s\S]*income-filter-actions[\s\S]*income-filter-right-spacer/);
assert.match(filterMarkup, /income-filter-label-spacer[\s\S]*income-include-inactive-control/);
assert.match(html, /id="incomeFilterStatus"[\s\S]*aria-live="polite"/);
assert.match(html, /income-filter-panel"[\s\S]*aria-busy="false"/);
assert.doesNotMatch(html, /incomeLoadingState/);

assert.match(page, /let draftFilters = \{ month: "", \.\.\.DEFAULT_FILTERS \}/);
assert.match(page, /let appliedFilters = \{ month: "", \.\.\.DEFAULT_FILTERS \}/);
assert.match(bindEvents, /dom\.filterForm\.addEventListener\("submit",[\s\S]*queryDraftFilters\(\)/);
assert.match(bindEvents, /dom\.yearFilter,[\s\S]*dom\.monthFilter,[\s\S]*dom\.studentSelect,[\s\S]*dom\.accountSelect,[\s\S]*dom\.categorySelect,[\s\S]*dom\.currencySelect,[\s\S]*field\.addEventListener\("change", updateDraftFiltersFromControls\)/);
assert.doesNotMatch(bindEvents, /(?:yearFilter|monthFilter)\.addEventListener\("change",\s*(?:queryDraftFilters|applyQuery)/);
assert.match(bindEvents, /includeInactiveCheckbox\.addEventListener\("change", handleDraftCandidateScopeChange\)/);
assert.match(bindEvents, /resetButton\.addEventListener\("click", resetAndQueryFilters\)/);

assert.match(candidateRefresh, /fetchStudentMonthCandidates\(\{/);
assert.match(candidateRefresh, /requestId !== topStudentCandidateRequestSequence/);
assert.match(candidateRefresh, /draftFilters = \{ \.\.\.filters, studentId: dom\.studentSelect\.value \}/);
assert.doesNotMatch(candidateRefresh, /fetchIncomeRecords|syncIncomeQuery|renderIncomeRecords|filterIncomeRecords/);
assert.equal((queryFunction.match(/fetchIncomeRecords\(/g) || []).length, 1, "explicit query must call the income reader exactly once");
assert.match(queryFunction, /appliedFilters = \{ \.\.\.nextAppliedFilters \}/);
assert.match(queryFunction, /syncIncomeQuery\(appliedFilters\)/);
assert.match(queryFunction, /applyCurrentFilters\(appliedFilters\)/);
assert.match(queryFunction, /if \(!hasSupabaseConfig\(\) \|\| isIncomeQuerying\)/);
assert.match(resetFunction, /forceCandidateRefresh: true/);
assert.doesNotMatch(page, /function applyQuery|setLoading\(|showMessage\("info", "正在加载收入记录/);

assert.match(css, /\.income-filter-panel \.income-filter-grid\s*\{[\s\S]*?196px[\s\S]*?300px[\s\S]*?176px[\s\S]*?300px[\s\S]*?300px[\s\S]*?300px[\s\S]*?minmax\(0, 1fr\)[\s\S]*?auto[\s\S]*?140px/);
assert.match(css, /\.income-filter-panel \.income-include-inactive-control input\s*\{[\s\S]*?width:\s*16px[\s\S]*?height:\s*16px/);
assert.match(css, /\.income-filter-panel \.income-filter-actions\s*\{[\s\S]*?gap:\s*12px/);
assert.match(css, /\.income-filter-panel \.income-filter-actions \.button\s*\{[\s\S]*?width:\s*96px[\s\S]*?height:\s*42px/);
assert.match(css, /\.income-filter-status\s*\{[\s\S]*?height:\s*20px/);
assert.match(css, /\.income-filter-status\[data-state="idle"\]\s*\{[\s\S]*?visibility:\s*hidden/);
assert.match(css, /@media \(max-width: 1799px\)[\s\S]*?\.income-filter-panel \.income-filter-grid/);
assert.match(css, /@media \(max-width: 767px\)[\s\S]*?\.income-filter-panel \.income-filter-grid[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\)/);
assert.doesNotMatch(css, /\.expense-filter-panel[^\n{]*\.income-filter-|\.wage-filter-panel[^\n{]*\.income-filter-|\.settlement-filter-panel[^\n{]*\.income-filter-/);

assert.match(api, /export async function fetchIncomeRecords\(month\)/);
assert.match(html, /income-filter-explicit-query-20260808-1/);
assert.match(app, /income-filter-explicit-query-20260808-1/);
assert.match(config, /APP_VERSION = "v10\.5\.25"/);
assert.doesNotMatch(page, /legacy-core\.js/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = read(`js/pages/${pageFile}`);
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/, `page-layer DML regression: ${pageFile}`);
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = read(`js/${browserFile}`);
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker: js/${browserFile}`);
}

console.log("INCOME_FILTER_LAYOUT_STATIC_TEST_PASS");
