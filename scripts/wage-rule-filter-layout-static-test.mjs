import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const html = read("wage-rule.html");
const detailHtml = read("wage-rule-detail.html");
const page = read("js/pages/wage-rule-page.js");
const detailPage = read("js/pages/wage-rule-detail-page.js");
const api = read("js/api/wage-rule-api.js");
const app = read("js/wage-rule-app.js");
const css = read("css/app.css");
const config = read("js/config.js");
const filterMarkup = html.match(/<form id="wageRuleFilterForm"[\s\S]*?<\/form>/)?.[0] || "";
const defaultFilters = page.match(/const DEFAULT_FILTERS = \{[\s\S]*?\n\};/)?.[0] || "";
const filterFunction = page.match(/function filterWageRules\([\s\S]*?\n\}/)?.[0] || "";
const candidateRefreshFunction = page.match(/async function refreshDraftStudentCandidates\(\) \{[\s\S]*?\n\}\n\nasync function queryDraftFilters/)?.[0] || "";
const queryFunction = page.match(/async function queryDraftFilters\(\) \{[\s\S]*?\n\}\n\nasync function resetAndQueryFilters/)?.[0] || "";

for (const id of [
  "wageRuleTeacherSelect",
  "wageRuleStudentSelect",
  "wageRuleIncludeInactiveCheckbox",
  "wageRuleSubjectSelect",
  "wageRuleActiveSelect",
  "wageRuleKeywordInput",
  "wageRuleResetButton",
]) {
  assert.match(filterMarkup, new RegExp(`id="${id}"`), `missing wage-rule filter: ${id}`);
}

assert.doesNotMatch(filterMarkup, /老师分类|wageRuleTeacherDepartmentSelect|teacherDepartment/);
assert.doesNotMatch(filterMarkup, /结算类型|wageRuleSettlementTypeSelect|name="settlementType"/);
assert.match(filterMarkup, /wage-rule-filter-teacher-field[\s\S]*wage-rule-filter-student-field[\s\S]*wage-rule-include-inactive-field[\s\S]*wage-rule-filter-subject-field[\s\S]*wage-rule-filter-active-field[\s\S]*wage-rule-filter-keyword-field[\s\S]*wage-rule-filter-flex-spacer[\s\S]*wage-rule-filter-actions[\s\S]*wage-rule-filter-right-spacer/);
assert.match(filterMarkup, /wage-rule-filter-label-spacer[\s\S]*wage-rule-include-inactive-control/);

assert.doesNotMatch(defaultFilters, /teacherDepartment|settlementType/);
assert.doesNotMatch(page, /dom\.(?:teacherDepartmentSelect|settlementTypeSelect)/);
assert.doesNotMatch(filterFunction, /filters\.(?:teacherDepartment|settlementType)/);
assert.match(page, /RETIRED_WAGE_RULE_FILTER_PARAMS = \[[\s\S]*"teacherDepartment"[\s\S]*"teacher_department"[\s\S]*"settlementType"[\s\S]*"settlement_type"/);
assert.match(page, /RETIRED_WAGE_RULE_FILTER_PARAMS\.forEach\(\(name\) => params\.delete\(name\)\)/);
assert.match(page, /writeStudentCandidateQuery\(new URLSearchParams\(window\.location\.search\)/);
assert.match(page, /window\.history\?\.replaceState\?\.\(null, "", query \?/);

assert.match(filterFunction, /filters\.teacherId/);
assert.match(filterFunction, /filters\.studentId/);
assert.match(filterFunction, /filters\.subjectId/);
assert.match(filterFunction, /filters\.activeState/);
assert.match(filterFunction, /matchesKeyword\(rule, filters\.keyword\)/);
assert.match(page, /includeInactive: Boolean\(dom\.includeInactiveCheckbox\.checked\)/);

assert.match(page, /let draftFilters = \{ \.\.\.DEFAULT_FILTERS \}/);
assert.match(page, /let appliedFilters = \{ \.\.\.DEFAULT_FILTERS \}/);
assert.match(page, /dom\.includeInactiveCheckbox\.addEventListener\("change", handleDraftCandidateScopeChange\)/);
assert.match(page, /dom\.keywordInput\.addEventListener\("input", updateDraftFiltersFromControls\)/);
assert.match(page, /dom\.filterForm\.addEventListener\("submit",[\s\S]*?queryDraftFilters\(\)/);
assert.match(page, /setFilterStatus\("candidate", "正在更新学生候选…"\)/);
assert.match(page, /setFilterStatus\("query", "正在查询工资规则…"\)/);
assert.match(candidateRefreshFunction, /fetchWageRuleCurrentStudentCandidates/);
assert.match(candidateRefreshFunction, /requestId !== candidateRequestSequence/);
assert.doesNotMatch(candidateRefreshFunction, /fetchWageRules|syncCandidateUrl|renderWageRules|filterWageRules/);
assert.equal((queryFunction.match(/fetchWageRules\(\)/g) || []).length, 1, "query must call the wage-rule list reader exactly once");
assert.match(queryFunction, /appliedFilters = nextAppliedFilters/);
assert.match(queryFunction, /syncCandidateUrl\(appliedFilters\)/);
assert.match(queryFunction, /renderWageRules\(filterWageRules\(wageRules, appliedFilters\)\)/);
assert.doesNotMatch(page, /wageRuleLoadingState|refreshFilterCandidatesAndApply|applyCurrentFilters/);

assert.match(html, /<th>老师分类<\/th>/);
assert.match(html, /<th>结算类型<\/th>/);
assert.match(page, /teacher\?\.department/);
assert.match(page, /settlementTypeLabel\(rule\.settlement_type\)/);
assert.match(detailPage, /\["老师分类", displayValue\(teacher\?\.department\)\]/);
assert.match(detailPage, /\["结算类型", settlementTypeLabel\(rule\.settlement_type\)\]/);
assert.match(detailHtml, /老师工资规则详情/);
for (const id of [
  "createWageRuleTeacherSelect",
  "createWageRuleSettlementTypeSelect",
  "editWageRuleTeacherSelect",
  "editWageRuleSettlementTypeSelect",
]) {
  assert.match(html, new RegExp(`id="${id}"`), `missing wage-rule business field: ${id}`);
}
assert.match(page, /settlementType: dom\.createSettlementTypeSelect\.value/);
assert.match(page, /settlementType: dom\.editSettlementTypeSelect\.value/);
assert.match(api, /p_settlement_type: payload\.settlementType/);
assert.match(api, /p_business_entity_id: payload\.businessEntityId/);

assert.match(html, /app-shell app-shell--wage-rule/);
assert.match(html, /id="wageRuleFilterStatus"[\s\S]*aria-live="polite"[\s\S]*aria-busy="true"/);
assert.match(html, /class="panel wage-rule-list-panel"/);
assert.equal((html.match(/<col class="wage-rule-col-/g) || []).length, 18, "wage-rule table must declare all 18 columns");
assert.match(css, /\.app-shell--wage-rule\s*\{[\s\S]*?max-width:\s*none/);
assert.match(css, /\.wage-rule-filter-panel \.wage-rule-filter-grid\s*\{[\s\S]*?300px[\s\S]*?300px[\s\S]*?176px[\s\S]*?300px[\s\S]*?300px[\s\S]*?300px[\s\S]*?minmax\(0, 1fr\)[\s\S]*?auto[\s\S]*?140px/);
assert.match(css, /\.wage-rule-filter-panel \.wage-rule-include-inactive-control input\s*\{[\s\S]*?width:\s*16px[\s\S]*?height:\s*16px/);
assert.match(css, /\.wage-rule-filter-panel \.wage-rule-filter-actions\s*\{[\s\S]*?gap:\s*12px/);
assert.match(css, /\.wage-rule-filter-status\s*\{[\s\S]*?height:\s*20px/);
assert.match(css, /\.wage-rule-filter-status\[data-state="idle"\]\s*\{[\s\S]*?visibility:\s*hidden/);
assert.match(css, /\.wage-rule-list-panel \.wage-rule-list-heading\s*\{[\s\S]*?padding-right:\s*134px/);
assert.match(css, /\.wage-rule-table\s*\{[\s\S]*?width:\s*100%[\s\S]*?min-width:\s*2210px[\s\S]*?table-layout:\s*fixed/);
assert.match(css, /\.wage-rule-table \.wage-rule-col-note\s*\{[\s\S]*?width:\s*260px/);
assert.match(css, /@media \(max-width: 1799px\)[\s\S]*?\.wage-rule-filter-panel \.wage-rule-filter-grid/);
assert.match(css, /@media \(max-width: 767px\)[\s\S]*?\.wage-rule-filter-panel \.wage-rule-filter-grid[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\)/);
assert.doesNotMatch(css, /\.settlement-filter-panel[^\n{]*\.wage-rule-|\.wage-filter-panel[^\n{]*\.wage-rule-/);

assert.match(html, /wage-rule-explicit-filter-20260808-1/);
assert.match(app, /wage-rule-explicit-filter-20260808-1/);
assert.match(config, /APP_VERSION = "v10\.5\.30"/);
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

console.log("WAGE_RULE_FILTER_LAYOUT_STATIC_TEST_PASS");
