import assert from "node:assert/strict";
import fs from "node:fs";

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

const shared = read("js/api/student-status-api.js");
const settlement = read("js/pages/settlement-page.js");
const income = read("js/pages/income-page.js");
const incomeDetail = read("js/pages/income-detail-page.js");
const expense = read("js/pages/expense-page.js");
const settlementDetailApi = read("js/api/settlement-detail-api.js");
const incomeDetailApi = read("js/api/income-detail-api.js");
const expenseDetailApi = read("js/api/expense-detail-api.js");

assert.match(shared, /school_list_student_month_candidates_v1/);
for (const exportedName of [
  "normalizeStudentMonthCandidate",
  "studentMonthCandidateLabel",
  "renderStudentMonthCandidateOptions",
  "readStudentCandidateQuery",
  "writeStudentCandidateQuery",
]) {
  assert.match(shared, new RegExp(`export function ${exportedName}\\b`));
}
assert.match(shared, /本月暂停/);
assert.match(shared, /本月已离校/);
assert.match(shared, /p_target_month: `\$\{normalizedMonth\}-01`/);
assert.match(shared, /p_include_inactive: Boolean\(includeInactive\)/);
assert.match(shared, /p_selected_student_id: selectedStudentId \|\| null/);

for (const [name, page, html, prefix] of [
  ["settlement", settlement, read("settlement.html"), "settlement"],
  ["income", income, read("income.html"), "income"],
  ["expense", expense, read("expense.html"), "expense"],
]) {
  assert.match(page, /student-status-api\.js\?v=phase-b4-finance-20260807-1/, `${name}: shared API import`);
  assert.match(page, /fetchStudentMonthCandidates\(\{[\s\S]*?month:[\s\S]*?includeInactive:[\s\S]*?selectedStudentId:/, `${name}: authoritative candidate args`);
  assert.match(page, /writeStudentCandidateQuery\(/, `${name}: URL serializer`);
  assert.match(page, /student_id/, `${name}: student_id URL/filter`);
  assert.match(html, new RegExp(`id="${prefix}IncludeInactiveCheckbox"`), `${name}: include inactive control`);
  assert.doesNotMatch(page, /\.rpc\(|\.from\([^)]*\)\s*\.(?:insert|update|delete|upsert)\(/, `${name}: page-layer DB write/RPC`);
  assert.doesNotMatch(html, /业务归属|个人名义|business[_-]?entity/i, `${name}: BE UI regression`);
}

assert.match(settlement, /row\.student_id !== filters\.studentId/);
assert.match(income, /row\.student_id !== filters\.studentId/);
assert.match(expense, /row\.student_id !== filters\.studentId/);

assert.match(income, /createSettlementMonthInput\.value/);
assert.match(income, /tuitionBillMonthInput\.value/);
assert.match(income, /createIncomeIncludeInactiveCheckbox/);
assert.match(income, /tuitionBillIncludeInactiveCheckbox/);
assert.match(income, /createIncomeIncludeInactiveCheckbox\.addEventListener\("change", \(\) => refreshCreateStudentCandidates\(\)\)/);
assert.match(income, /createSettlementMonthInput\.addEventListener\("change", \(\) => refreshCreateStudentCandidates\(\)\)/);
assert.doesNotMatch(income, /addEventListener\("change", refreshCreateStudentCandidates\)/);
assert.doesNotMatch(income, /filteredCreateStudents|isActiveStudent/);
assert.doesNotMatch(income, /selectedStudent\?\.business_entity_id/);

assert.match(incomeDetail, /editSettlementMonthInput\.value/);
assert.match(incomeDetail, /editIncomeIncludeInactiveCheckbox/);
assert.match(incomeDetail, /editIncludeInactiveCheckbox\.addEventListener\("change", \(\) => refreshEditStudentCandidates\(\)\)/);
assert.match(incomeDetail, /editSettlementMonthInput\.addEventListener\("change", \(\) => refreshEditStudentCandidates\(\)\)/);
assert.doesNotMatch(incomeDetail, /addEventListener\("change", refreshEditStudentCandidates\)/);
assert.match(incomeDetail, /selectedStudentId: selectedStudentId \|\| null/);
assert.doesNotMatch(incomeDetail, /filteredEditStudents|isActiveStudent/);

for (const [name, api, call] of [
  ["settlement detail", settlementDetailApi, /fetchSettlementDetailLookups\(physicalSettlement\.student_id\)/],
  ["income detail", incomeDetailApi, /fetchIncomeDetailLookups\(income\)/],
  ["expense detail", expenseDetailApi, /fetchExpenseDetailLookups\(expense\)/],
]) {
  assert.match(api, call, `${name}: record student lookup input`);
  assert.match(api, /\.eq\("id", (?:studentId|income\.student_id|expense\.student_id)/, `${name}: minimal student id lookup`);
}

assert.match(expense, /studentId:\s*null/);
assert.doesNotMatch(read("expense.html"), /createExpenseStudent/);

for (const path of [
  "js/pages/settlement-page.js",
  "js/pages/settlement-detail-page.js",
  "js/pages/income-page.js",
  "js/pages/income-detail-page.js",
  "js/pages/expense-page.js",
  "js/pages/expense-detail-page.js",
]) {
  assert.doesNotMatch(read(path), /service[_-]?role/i, `${path}: browser service role`);
}

assert.match(read("js/config.js"), /APP_VERSION = "v10\.5\.\d+"/);
console.log("student status Phase B4 Finance static checks passed");
