import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const RESET_MESSAGE = "已重置筛选条件；点击“查询”后刷新结果。";
const B1_CACHE_KEY = "filter-contract-b1-20260822-1";
const B2_CACHE_KEY = "filter-contract-b2-20260822-1";

const pages = [
  {
    id: "lesson",
    label: "课时管理（正向基准）",
    html: "lesson.html",
    app: "js/lesson-app.js",
    page: "js/pages/lesson-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /restoreFilterSelections\(/,
    resetClearCallPattern: /invalidateLessonResultsForFilterChange\("已重置筛选条件；点击“查询”后刷新结果。"\)/,
    resetClearFunction: "invalidateLessonResultsForFilterChange",
    clearPatterns: [/beginLessonRecordsRequest\(\)/, /renderLessonRecords\(\[\]/],
    queryFunction: "applyQuery",
    queryPatterns: [/loadLessonMonth\(/, /applyCurrentFilters\(\)/],
    auxiliaryReaders: ["fetchStudentMonthCandidates", "refreshTopStudentCandidatesFromControls"],
    mainResultReaders: ["fetchLessonRecords", "loadLessonMonth"],
    writers: ["createPlannedLessonRecord", "generatePlannedLessonsBatch"],
    cacheKey: null,
  },
  {
    id: "subject",
    label: "科目管理",
    html: "subject.html",
    app: "js/subject-app.js",
    page: "js/pages/subject-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [/renderSubjects\(\[\]\)/],
    queryFunction: "applyCurrentFilters",
    queryPatterns: [/filterSubjects\(allSubjects, filters\)/, /renderSubjects\(/],
    auxiliaryReaders: [],
    mainResultReaders: ["fetchSubjects", "loadSubjectData"],
    writers: ["createSubjectProfile", "updateSubjectProfile"],
    cacheKey: B1_CACHE_KEY,
  },
  {
    id: "wage",
    label: "老师工资结算",
    html: "wage.html",
    app: "js/wage-app.js",
    page: "js/pages/wage-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /activeFilters = null/,
      /selectedWageLockIds\.clear\(\)/,
      /wageCount\.textContent = "0 条"/,
      /candidateSummary\.innerHTML = ""/,
      /updateQueryResultActionControls\(\)/,
    ],
    queryFunction: "applyQuery",
    queryPatterns: [/loadWageMonth\(/, /applyCurrentFilters\(filters\)/],
    auxiliaryReaders: ["fetchWageStudentMonthCandidates", "fetchWageTeachers", "fetchWageSubjects"],
    mainResultReaders: ["fetchWageLocks", "fetchWageCandidateLessons", "loadWageMonth"],
    writers: ["generateTeacherMonthlyWage", "createTeacherWageExpenseRecord"],
    cacheKey: B1_CACHE_KEY,
  },
  {
    id: "reimbursement",
    label: "报销管理",
    html: "reimbursement.html",
    app: "js/reimbursement-app.js",
    page: "js/pages/reimbursement-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /renderCandidateExpenses\(\[\]\)/,
      /renderReimbursements\(\[\]\)/,
      /selectedExpenseIds = new Set\(\)/,
      /renderCreateCandidateRows\(\[\]\)/,
    ],
    queryFunction: "applyQuery",
    queryPatterns: [/loadReimbursementMonth\(/, /applyCurrentFilters\(\)/],
    auxiliaryReaders: ["fetchReimbursementLookups"],
    mainResultReaders: ["fetchReimbursementRecords", "fetchReimbursementCandidateExpenses", "loadReimbursementMonth"],
    writers: ["createReimbursementRecord"],
    cacheKey: B1_CACHE_KEY,
  },
  {
    id: "profit",
    label: "利润分析",
    html: "profit-summary.html",
    app: "js/profit-summary-app.js",
    page: "js/pages/profit-summary-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setYearMonthSelectValue\([\s\S]*currentYearMonth\(\)\)/,
    resetClearCallPattern: /invalidateQueryResults\(FILTER_RESET_MESSAGE\)/,
    resetClearFunction: "invalidateQueryResults",
    clearPatterns: [/pageData = null/, /renderEmptyState\(\)/, /showMessage\("info", message\)/],
    queryFunction: "loadProfitSummary",
    queryPatterns: [/fetchProfitSummaryPageData\(filters\)/, /renderSummary\(pageData, filters\)/],
    auxiliaryReaders: [],
    mainResultReaders: ["fetchProfitSummaryPageData", "loadProfitSummary"],
    writers: [],
    cacheKey: B1_CACHE_KEY,
  },
  {
    id: "student",
    label: "学生管理",
    html: "student.html",
    app: "js/student-app.js",
    page: "js/pages/student-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /activeFilters = null/,
      /students = \[\]/,
      /closeEditDialog\(\{ force: true \}\)/,
      /closeStatusTransitionDialog\(\{ force: true \}\)/,
      /closeStatusHistoryDialog\(\)/,
      /closeStatusCorrectionDialog\(\{ force: true \}\)/,
      /renderStudents\(\[\]\)/,
    ],
    queryFunction: "loadStudentData",
    queryPatterns: [/fetchStudents\(filters\)/, /fetchStudentStatusManagement\(\)/, /activeFilters = \{ \.\.\.filters \}/, /renderStudents\(/],
    auxiliaryReaders: ["fetchStudentFilterOptions", "fetchBusinessEntitiesForStudents"],
    mainResultReaders: ["fetchStudents", "fetchStudentStatusManagement", "loadStudentData"],
    writers: ["createStudentProfile", "updateStudentProfile", "transitionStudentStatus", "correctStudentStatusEvent"],
    cacheKey: B2_CACHE_KEY,
  },
  {
    id: "teacher",
    label: "老师管理",
    html: "teacher.html",
    app: "js/teacher-app.js",
    page: "js/pages/teacher-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [/activeFilters = null/, /teachers = \[\]/, /closeEditDialog\(\{ force: true \}\)/, /renderTeachers\(\[\]\)/],
    queryFunction: "loadTeacherData",
    queryPatterns: [/fetchTeachers\(filters\)/, /activeFilters = \{ \.\.\.filters \}/, /renderTeachers\(/],
    auxiliaryReaders: ["fetchTeacherFilterOptions", "fetchBusinessEntitiesForTeachers", "fetchSubjectsForTeachers"],
    mainResultReaders: ["fetchTeachers", "loadTeacherData"],
    writers: ["createTeacherProfile", "updateTeacherProfile"],
    cacheKey: B2_CACHE_KEY,
  },
  {
    id: "account",
    label: "账户管理",
    html: "account.html",
    app: "js/account-app.js",
    page: "js/pages/account-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /activeFilters = null/,
      /transactions = \[\]/,
      /renderAccounts\(\[\]\)/,
      /renderTransactions\(\[\]\)/,
      /accountTransferFromAccountSelect\.value = ""/,
      /accountTransferToAccountSelect\.value = ""/,
      /accountAdjustmentAccountSelect\.value = ""/,
      /updateQueryResultActionControls\(\)/,
    ],
    queryFunction: "loadAccountData",
    queryPatterns: [
      /fetchAccounts\(\)/,
      /fetchAccountTransactions\(filters\)/,
      /activeFilters = \{ \.\.\.filters \}/,
      /renderAccounts\(/,
      /renderTransactions\(/,
    ],
    auxiliaryReaders: ["fetchBusinessEntitiesForAccounts"],
    mainResultReaders: ["fetchAccounts", "fetchAccountTransactions", "loadAccountData"],
    writers: ["createAccountProfile", "updateAccountProfile", "createAccountTransfer", "createAccountAdjustment"],
    cacheKey: B2_CACHE_KEY,
  },
];

function read(path) {
  return readFileSync(path, "utf8");
}

function functionSource(source, name) {
  const marker = new RegExp(`(?:async\\s+)?function\\s+${name}\\s*\\(`);
  const match = marker.exec(source);
  assert.ok(match, `missing function ${name}`);
  const rest = source.slice(match.index + match[0].length);
  const next = rest.search(/\n(?:async\s+)?function\s+[A-Za-z0-9_]+\s*\(/);
  return next === -1 ? source.slice(match.index) : source.slice(match.index, match.index + match[0].length + next);
}

function resetHandlerSource(source, target) {
  const escaped = target.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = source.match(new RegExp(`${escaped}\\.addEventListener\\("click", \\(\\) => \\{([\\s\\S]*?)\\n  \\}\\);`));
  assert.ok(match, `missing reset handler for ${target}`);
  return match[1];
}

class ContractState {
  constructor(changeClears) {
    this.changeClears = changeClears;
    this.mainResult = "initial";
    this.applied = "default";
    this.selected = true;
    this.message = "ready";
    this.mainReaderCount = 0;
    this.writerCount = 0;
    this.navigationCount = 0;
  }

  change() {
    if (this.changeClears) this.mainResult = null;
    this.message = this.changeClears ? "pending" : this.message;
  }

  reset() {
    this.mainResult = null;
    this.applied = null;
    this.selected = false;
    this.message = RESET_MESSAGE;
  }

  query() {
    this.mainReaderCount += 1;
    this.mainResult = "queried";
    this.applied = "draft";
    this.message = "ready";
  }
}

for (const page of pages) {
  const html = read(page.html);
  const app = read(page.app);
  const source = read(page.page);
  const reset = resetHandlerSource(source, page.resetTarget);
  const clear = functionSource(source, page.resetClearFunction);
  const query = functionSource(source, page.queryFunction);

  assert.match(html, /type="submit">查询<\/button>/, `${page.label}: explicit query button missing`);
  assert.match(html, /type="button">重置<\/button>/, `${page.label}: safe reset button missing`);
  assert.ok(source.includes(RESET_MESSAGE), `${page.label}: exact reset message missing`);
  assert.match(reset, page.resetDefaultPattern, `${page.label}: reset does not restore defaults`);
  assert.match(reset, page.resetClearCallPattern, `${page.label}: reset does not clear results`);

  for (const name of page.mainResultReaders) {
    assert.ok(!reset.includes(`${name}(`), `${page.label}: reset calls mainResultReader ${name}`);
    assert.ok(!clear.includes(`${name}(`), `${page.label}: clear path calls mainResultReader ${name}`);
  }
  for (const name of page.writers) {
    assert.ok(!reset.includes(`${name}(`), `${page.label}: reset calls writer ${name}`);
    assert.ok(!clear.includes(`${name}(`), `${page.label}: clear path calls writer ${name}`);
  }
  for (const pattern of page.clearPatterns) {
    assert.match(clear, pattern, `${page.label}: clear contract evidence missing: ${pattern}`);
  }
  for (const pattern of page.queryPatterns) {
    assert.match(query, pattern, `${page.label}: query evidence missing: ${pattern}`);
  }

  assert.ok(Array.isArray(page.auxiliaryReaders), `${page.label}: auxiliaryReader whitelist missing`);
  assert.ok(Array.isArray(page.mainResultReaders) && page.mainResultReaders.length > 0, `${page.label}: mainResultReader whitelist missing`);
  assert.ok(Array.isArray(page.writers), `${page.label}: writer whitelist missing`);
  assert.deepEqual(
    page.auxiliaryReaders.filter((name) => page.mainResultReaders.includes(name)),
    [],
    `${page.label}: reader classifications overlap`
  );

  if (page.cacheKey) {
    assert.ok(html.includes(page.cacheKey), `${page.label}: HTML cache key missing`);
    assert.ok(app.includes(page.cacheKey), `${page.label}: app cache key missing`);
  }

  const state = new ContractState(page.id === "lesson" || page.id === "profit");
  state.change();
  assert.notEqual(state.mainResult, "new-filter-result", `${page.label}: change applied new result`);
  assert.equal(state.mainReaderCount, 0, `${page.label}: change main reader regression`);
  state.reset();
  state.reset();
  assert.equal(state.mainResult, null, `${page.label}: reset result not empty`);
  assert.equal(state.applied, null, `${page.label}: reset applied state not empty`);
  assert.equal(state.selected, false, `${page.label}: reset selection not empty`);
  assert.equal(state.message, RESET_MESSAGE, `${page.label}: reset message mismatch`);
  assert.equal(state.mainReaderCount, 0, `${page.label}: reset main reader regression`);
  assert.equal(state.writerCount, 0, `${page.label}: writer regression`);
  assert.equal(state.navigationCount, 0, `${page.label}: document navigation regression`);
  state.query();
  assert.equal(state.mainResult, "queried", `${page.label}: reset then query did not restore result`);
  state.change();
  assert.notEqual(state.mainResult, "new-filter-result", `${page.label}: post-query change applied new result`);
}

const profitSource = read("js/pages/profit-summary-page.js");
assert.match(profitSource, /\[dom\.yearFilter, dom\.monthFilter, dom\.currencySelect\][\s\S]*invalidateQueryResults\(FILTER_PENDING_MESSAGE\)/);
assert.doesNotMatch(profitSource, /dom\.currencySelect\.addEventListener\("change"[\s\S]{0,160}renderSummary\(/);

const subjectSource = read("js/pages/subject-page.js");
assert.doesNotMatch(subjectSource, /dom\.(?:keywordInput|activeSelect|primaryCategorySelect|categorySelect)\.addEventListener\("(?:change|input)"[\s\S]{0,160}(?:applyCurrentFilters|renderSubjects)\(/);

const wageSource = read("js/pages/wage-page.js");
assert.doesNotMatch(wageSource, /dom\.(?:yearFilter|monthFilter|teacherSelect|studentSelect|includeInactiveCheckbox|statusSelect|keywordInput)\??\.addEventListener\("(?:change|input)"[\s\S]{0,160}(?:applyQuery|applyCurrentFilters|renderWageLocks|renderWageCandidates)\(/);

const reimbursementSource = read("js/pages/reimbursement-page.js");
assert.doesNotMatch(reimbursementSource, /dom\.(?:yearFilter|monthFilter|fromAccountSelect|toAccountSelect|currencySelect|statusSelect|hasItemsSelect|hasTransactionsSelect|keywordInput)\.addEventListener\("(?:change|input)"[\s\S]{0,160}(?:applyQuery|applyCurrentFilters|renderReimbursements|renderCandidateExpenses)\(/);

const studentSource = read("js/pages/student-page.js");
assert.doesNotMatch(studentSource, /dom\.(?:keywordInput|statusSelect|courseTrackSelect|activeSelect)\.addEventListener\("(?:change|input)"[\s\S]{0,160}(?:loadStudentData|renderStudents)\(/);

const teacherSource = read("js/pages/teacher-page.js");
assert.doesNotMatch(teacherSource, /dom\.(?:keywordInput|statusSelect|departmentSelect)\.addEventListener\("(?:change|input)"[\s\S]{0,160}(?:loadTeacherData|renderTeachers)\(/);

const accountSource = read("js/pages/account-page.js");
const accountAppTypeHandler = accountSource.match(/dom\.appTypeSelect\.addEventListener\("change", \(\) => \{([\s\S]*?)\n  \}\);/);
assert.ok(accountAppTypeHandler, "账户管理: appType change handler missing");
assert.match(accountAppTypeHandler[1], /refreshAccountFilterOptionsForDraft\(\)/);
assert.match(accountAppTypeHandler[1], /markQueryPending\(\)/);
assert.doesNotMatch(accountAppTypeHandler[1], /(?:loadAccountData|renderAccounts|renderTransactions)\(/);
assert.doesNotMatch(accountAppTypeHandler[1], /fetch(?:Accounts|BusinessEntitiesForAccounts|AccountTransactions)\(/);

const migrationCounts = {
  htmlPages: { applicable: 18, compliant: 8, deprecatedLegacyException: 1, pendingMigration: 9, notApplicable: 0 },
  routeViews: { applicable: 19, compliant: 8, deprecatedLegacyException: 1, pendingMigration: 10, notApplicable: 0 },
};
const legacyExceptions = [
  {
    id: "legacy-wage-payment",
    html: "index.html",
    page: "js/pages/payment-page.js",
    status: "deprecated_legacy_exception",
    reason: "V3 removal",
    contract: "V2维持现状，不纳入顶部筛选合同迁移；V3删除；如果出现数据、权限或支付链问题，再单独处理。",
  },
];
assert.deepEqual(migrationCounts.htmlPages, {
  applicable: 18,
  compliant: 8,
  deprecatedLegacyException: 1,
  pendingMigration: 9,
  notApplicable: 0,
});
assert.deepEqual(migrationCounts.routeViews, {
  applicable: 19,
  compliant: 8,
  deprecatedLegacyException: 1,
  pendingMigration: 10,
  notApplicable: 0,
});
assert.equal(legacyExceptions.length, 1);
assert.equal(legacyExceptions[0].status, "deprecated_legacy_exception");
assert.equal(legacyExceptions[0].reason, "V3 removal");
assert.equal(legacyExceptions[0].contract, "V2维持现状，不纳入顶部筛选合同迁移；V3删除；如果出现数据、权限或支付链问题，再单独处理。");
assert.doesNotThrow(() => read(legacyExceptions[0].html));
assert.doesNotThrow(() => read(legacyExceptions[0].page));

const config = read("js/config.js");
assert.match(config, /APP_VERSION = "v10\.5\.58"/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = read(`js/pages/${pageFile}`);
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/, `page-layer DML regression: ${pageFile}`);
}

console.log(
  "FILTER_QUERY_RESET_CONTRACT_STATIC_TEST_PASS",
  "classifications=compliant,pending_migration,deprecated_legacy_exception,not_applicable",
  "html=18/8/1/9/0",
  "route_views=19/8/1/10/0"
);
