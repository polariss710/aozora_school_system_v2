import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const shared = read("js/api/student-status-api.js");
const lessonApi = read("js/api/lesson-api.js");
const weeklyPage = read("js/pages/weekly-schedule-image-page.js");
const weeklyHtml = read("weekly-schedule-image.html");
const weeklyApp = read("js/weekly-schedule-image-app.js");
const wageApi = read("js/api/wage-api.js");
const wagePage = read("js/pages/wage-page.js");
const wageRuleApi = read("js/api/wage-rule-api.js");
const wageRulePage = read("js/pages/wage-rule-page.js");
const wageRuleDetail = read("js/pages/wage-rule-detail-page.js");
const wageRuleHtml = read("wage-rule.html");
const classroom = read("js/pages/classroom-schedule-page.js");
const classroomHtml = read("classroom-schedule.html");
const classroomApp = read("js/classroom-schedule-app.js");
const weeklyOperations = read("js/pages/weekly-lesson-dashboard-page.js");
const weeklyOperationsHtml = read("weekly-lesson-dashboard.html");
const weeklyOperationsApp = read("js/weekly-lesson-dashboard-app.js");
const readerCore = read("sql/current/school_student_status_phase_b4_remaining_current_month_reader_core_20260807.sql");

assert.match(shared, /school_list_student_range_candidates_v1/);
assert.match(shared, /school_list_current_student_month_candidates_v1/);
assert.match(shared, /export async function fetchStudentRangeCandidates/);
assert.match(shared, /export async function fetchCurrentStudentMonthCandidates/);
assert.match(shared, /is_active_in_range/);
assert.match(shared, /本月暂停/);
assert.match(shared, /p_selected_student_id: selectedStudentId \|\| null/);

assert.match(weeklyPage, /fetchStudentRangeCandidates\(\{[\s\S]*startDate:[\s\S]*endDate:[\s\S]*includeInactive:[\s\S]*selectedStudentId:/);
assert.match(weeklyPage, /fetchLessonStudentsByIds\(rows\.map\(\(row\) => row\.student_id\)\)/);
assert.match(weeklyPage, /writeStudentCandidateQuery/);
assert.match(weeklyPage, /params\.set\("week_start"/);
assert.match(weeklyHtml, /id="weeklyScheduleIncludeInactiveCheckbox"/);
assert.doesNotMatch(weeklyPage, /fetchLessonStudents\(\)/);

for (const [html, app, page] of [
  [weeklyHtml, weeklyApp, weeklyPage],
  [classroomHtml, classroomApp, classroom],
  [weeklyOperationsHtml, weeklyOperationsApp, weeklyOperations],
]) {
  assert.match(html, /type="button">重置<\/button>/);
  assert.match(html, /filter-contract-b5-20260822-1/);
  assert.match(app, /filter-contract-b5-20260822-1/);
  assert.match(page, /已重置筛选条件；点击“查询”后刷新结果。/);
  assert.match(page, /(?:mainRequestSequence|requestSequence)/);
  assert.match(page, /appliedFilters/);
}

assert.match(weeklyPage, /function clearQueryResults\(\)[\s\S]*state\.schedules = \[\][\s\S]*renderSchedules\(\)/);
assert.match(weeklyPage, /function refreshStudentCandidates[\s\S]*fetchStudentRangeCandidates/);
assert.match(classroom, /dom\.venueSelect\?\.addEventListener\("change", handleDraftFilterChange\)/);
assert.doesNotMatch(classroom, /dom\.venueSelect\?\.addEventListener\("change", applyVenueFilter\)/);
assert.match(classroom, /function clearQueryResults\(\)[\s\S]*state\.rows = \[\][\s\S]*resetRenderedSchedule\(\)/);
assert.match(weeklyOperations, /function shiftWeek\(days\).*handleDraftWeekChange\(\); \}/);
assert.doesNotMatch(weeklyOperations, /function shiftWeek\(days\).*loadDashboard\(\)/);
assert.match(weeklyOperations, /function clearQueryResults\(\)[\s\S]*dom\.plannedHours\.textContent = "-"/);

assert.match(readerCore, /statement_timestamp\(\) at time zone 'Asia\/Tokyo'/);
assert.match(readerCore, /school_list_student_month_candidates_v1/);
assert.match(readerCore, /security definer/);
assert.match(readerCore, /set search_path = pg_catalog, public/);
assert.match(readerCore, /grant execute[\s\S]*to authenticated/);
assert.doesNotMatch(readerCore, /grant execute[\s\S]*to (?:anon|service_role)/);

assert.match(wageRuleApi, /fetchCurrentStudentMonthCandidates/);
assert.match(wageRuleApi, /fetchWageRuleLookups\(studentIds = \[\]\)/);
assert.match(wageRuleApi, /\.in\("id", ids\)/);
assert.doesNotMatch(wageRuleApi, /student_code,status|status,business_entity_id/);
assert.match(wageRulePage, /filterStudentCandidates/);
assert.match(wageRulePage, /activeStudentCandidates/);
assert.match(wageRulePage, /editStudentCandidates/);
assert.match(wageRulePage, /fetchWageRuleCurrentStudentCandidates\(\{[\s\S]*selectedStudentId: rule\.student_id/);
assert.match(wageRulePage, /activeStudentCandidateById\(payload\.studentId\)/);
assert.match(wageRulePage, /id === editingWageRule\?\.student_id/);
assert.match(wageRulePage, /writeStudentCandidateQuery/);
assert.match(wageRulePage, /params\.delete\("business_entity_id"\)/);
assert.match(wageRulePage, /query \? `\$\{window\.location\.pathname\}\?\$\{query\}` : window\.location\.pathname/);
assert.match(wageRuleHtml, /id="wageRuleIncludeInactiveCheckbox"/);
assert.doesNotMatch(wageRulePage, /student\?\.status|isUsableStudent|isNewBusinessStudent/);
assert.match(wageRuleDetail, /student\?\.resolved_status/);

assert.match(wageApi, /export async function fetchWageStudents\(studentIds\)/);
assert.match(wageApi, /\.in\("id", ids\)/);
assert.match(wagePage, /fetchWageStudents\(referencedStudentIds\)/);
assert.match(classroom, /fetchLessonStudentsByIds\(state\.rows\.map/);
assert.match(weeklyOperations, /fetchLessonStudentsByIds\(rows\.map/);

const directStudentReadClassifications = new Map([
  ["js/api/tuition-receipt-api.js", "L"],
  ["js/api/wage-api.js", "L"],
  ["js/api/income-api.js", "D"],
  ["js/api/lesson-api.js", "D/L"],
  ["js/api/settlement-detail-api.js", "L"],
  ["js/api/income-detail-api.js", "L"],
  ["js/api/lesson-detail-api.js", "L"],
  ["js/api/settlement-api.js", "D/L"],
  ["js/api/expense-api.js", "D"],
  ["js/api/student-api.js", "M"],
  ["js/api/expense-detail-api.js", "L"],
  ["js/api/wage-rule-api.js", "L"],
  ["supabase/functions/request-cash-income-confirmation/index.ts", "L"],
]);
for (const [path, classification] of directStudentReadClassifications) {
  assert.match(read(path), /\.from\(["']school_students["']\)/, `${path} missing ${classification} read`);
}

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = read(`js/pages/${pageFile}`);
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/, `page-layer DML regression: ${pageFile}`);
}

for (const path of [weeklyHtml, wageRuleHtml, read("wage-rule-detail.html")]) {
  assert.doesNotMatch(path, /业务归属|个人名义|business_entity_id/i);
}
for (const source of [weeklyPage, wageRulePage, wageRuleDetail, classroom, weeklyOperations]) {
  assert.doesNotMatch(source, /service[_-]?role/i);
}

assert.match(read("js/config.js"), /APP_VERSION = "v10\.5\.62"/);
console.log("STUDENT_STATUS_PHASE_B4_REMAINING_STATIC_TEST_PASS");
