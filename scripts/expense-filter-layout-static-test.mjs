import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const html = read("expense.html");
const page = read("js/pages/expense-page.js");
const app = read("js/expense-app.js");
const api = read("js/api/expense-api.js");
const css = read("css/app.css");
const config = read("js/config.js");
const filterMarkup = html.match(/<form id="expenseFilterForm"[\s\S]*?<\/form>/)?.[0] || "";
const bindEvents = page.match(/function bindEvents\(\) \{[\s\S]*?\n\}/)?.[0] || "";
const candidateRefresh = page.match(/async function refreshDraftStudentCandidates\(\) \{[\s\S]*?\n\}\n\nasync function queryDraftFilters/)?.[0] || "";
const queryFunction = page.match(/async function queryDraftFilters\([\s\S]*?\n\}\n\nfunction clearQueryResults/)?.[0] || "";
const clearFunction = page.match(/function clearQueryResults\(\) \{[\s\S]*?\n\}(?=\n\nasync function fetchExpenseMonthSnapshot)/)?.[0] || "";
const snapshotFunction = page.match(/async function fetchExpenseMonthSnapshot\(month\) \{[\s\S]*?\n\}/)?.[0] || "";

for (const id of [
  "expenseYearFilter",
  "expenseMonthFilter",
  "expenseStudentSelect",
  "expenseIncludeInactiveCheckbox",
  "expenseTeacherSelect",
  "expenseAccountSelect",
  "expenseCurrencySelect",
  "expenseResetButton",
]) {
  assert.match(filterMarkup, new RegExp(`id="${id}"`), `missing expense filter: ${id}`);
}

assert.match(filterMarkup, /expense-filter-month-field[\s\S]*expense-filter-student-field[\s\S]*expense-include-inactive-field[\s\S]*expense-filter-teacher-field[\s\S]*expense-filter-account-field[\s\S]*expense-filter-currency-field[\s\S]*expense-filter-flex-spacer[\s\S]*expense-filter-actions[\s\S]*expense-filter-right-spacer/);
assert.match(filterMarkup, /expense-filter-label-spacer[\s\S]*expense-include-inactive-control/);
assert.match(html, /id="expenseFilterStatus"[\s\S]*aria-live="polite"/);
assert.match(html, /expense-filter-panel"[\s\S]*aria-busy="false"/);
assert.doesNotMatch(html, /expenseLoadingState/);

assert.match(page, /let draftFilters = \{ month: "", \.\.\.DEFAULT_FILTERS \}/);
assert.match(page, /let appliedFilters = \{ month: "", \.\.\.DEFAULT_FILTERS \}/);
assert.match(bindEvents, /dom\.filterForm\.addEventListener\("submit",[\s\S]*queryDraftFilters\(\)/);
assert.match(bindEvents, /dom\.yearFilter,[\s\S]*dom\.monthFilter,[\s\S]*dom\.studentSelect,[\s\S]*dom\.teacherSelect,[\s\S]*dom\.accountSelect,[\s\S]*dom\.currencySelect,[\s\S]*field\.addEventListener\("change", updateDraftFiltersFromControls\)/);
assert.doesNotMatch(bindEvents, /(?:yearFilter|monthFilter|studentSelect|teacherSelect|accountSelect|currencySelect)\.addEventListener\("change",\s*(?:queryDraftFilters|applyQuery)/);
assert.match(bindEvents, /includeInactiveCheckbox\.addEventListener\("change", handleDraftCandidateScopeChange\)/);
assert.match(bindEvents, /resetButton\.addEventListener\("click", \(\) => \{[\s\S]*clearQueryResults\(\)[\s\S]*refreshDraftStudentCandidates\(\)/);

assert.match(candidateRefresh, /fetchStudentMonthCandidates\(\{/);
assert.match(candidateRefresh, /requestId !== topStudentCandidateRequestSequence/);
assert.match(candidateRefresh, /draftFilters = \{ \.\.\.filters, studentId: dom\.studentSelect\.value \}/);
assert.doesNotMatch(candidateRefresh, /fetchExpenseMonthSnapshot|fetchExpenseRecords|syncExpenseQuery|renderExpenseRecords|filterExpenseRecords|pruneSelectedExpenseIds/);
assert.equal((queryFunction.match(/fetchExpenseMonthSnapshot\(/g) || []).length, 1, "explicit query must request one expense snapshot");
assert.equal((snapshotFunction.match(/fetchExpenseRecords\(/g) || []).length, 1, "one expense snapshot must call the expense reader exactly once");
assert.match(queryFunction, /appliedFilters = \{ \.\.\.nextAppliedFilters \}/);
assert.match(queryFunction, /syncExpenseQuery\(appliedFilters\)/);
assert.match(queryFunction, /applyCurrentFilters\(appliedFilters\)/);
assert.match(queryFunction, /if \(!hasSupabaseConfig\(\) \|\| isExpenseQuerying\)/);
assert.match(queryFunction, /setExpenseQuerying\(true\)/);
assert.match(clearFunction, /expenseQueryRequestSequence \+= 1/);
assert.match(clearFunction, /appliedFilters = null/);
assert.match(clearFunction, /selectedExpenseIds = new Set\(\)/);
assert.match(clearFunction, /renderExpenseRecords\(\[\]\)/);
assert.doesNotMatch(clearFunction, /fetchExpenseRecords|fetchExpenseMonthSnapshot|queryDraftFilters|loadExpenseMonth/);
assert.doesNotMatch(page, /function applyQuery|setLoading\(|showMessage\("info", "正在加载支出记录/);

assert.match(css, /\.expense-filter-panel \.expense-filter-grid\s*\{[\s\S]*?196px[\s\S]*?300px[\s\S]*?176px[\s\S]*?300px[\s\S]*?300px[\s\S]*?300px[\s\S]*?minmax\(0, 1fr\)[\s\S]*?auto[\s\S]*?140px/);
assert.match(css, /\.expense-filter-panel \.expense-include-inactive-control input\s*\{[\s\S]*?width:\s*16px[\s\S]*?height:\s*16px/);
assert.match(css, /\.expense-filter-panel \.expense-filter-actions\s*\{[\s\S]*?gap:\s*12px/);
assert.match(css, /\.expense-filter-panel \.expense-filter-actions \.button\s*\{[\s\S]*?width:\s*96px[\s\S]*?height:\s*42px/);
assert.match(css, /\.expense-filter-status\s*\{[\s\S]*?height:\s*20px/);
assert.match(css, /\.expense-filter-status\[data-state="idle"\]\s*\{[\s\S]*?visibility:\s*hidden/);
assert.match(css, /@media \(max-width: 1799px\)[\s\S]*?\.expense-filter-panel \.expense-filter-grid/);
assert.match(css, /@media \(max-width: 767px\)[\s\S]*?\.expense-filter-panel \.expense-filter-grid[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\)/);
assert.doesNotMatch(css, /\.income-filter-panel[^\n{]*\.expense-filter-|\.wage-filter-panel[^\n{]*\.expense-filter-|\.settlement-filter-panel[^\n{]*\.expense-filter-/);

assert.match(api, /export async function fetchExpenseRecords\(month\)/);
// Historical cache-key literals are intentionally not asserted; see the week-close handoff section 8.6.
assert.match(config, /APP_VERSION = "v10\.5\.63"/);
assert.doesNotMatch(page, /legacy-core\.js/);
assert.doesNotMatch(filterMarkup, /业务归属|个人名义|business_entity_id/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = read(`js/pages/${pageFile}`);
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/, `page-layer DML regression: ${pageFile}`);
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = read(`js/${browserFile}`);
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker: js/${browserFile}`);
}

console.log("EXPENSE_FILTER_LAYOUT_STATIC_TEST_PASS");
