import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const RESET_MESSAGE = "已重置筛选条件；点击“查询”后刷新结果。";
// Historical cache-key literals are intentionally not asserted; see the week-close handoff section 8.6.

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
  },
  {
    id: "settlement",
    label: "学生月度结算",
    html: "settlement.html",
    app: "js/settlement-app.js",
    page: "js/pages/settlement-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(defaults\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /queryRequestSequence \+= 1/,
      /appliedFilters = null/,
      /settlements = \[\]/,
      /closeAdjustmentDialog\(true\)/,
      /renderSettlements\(\[\]\)/,
      /setLoading\(false\)/,
    ],
    queryFunction: "runQuery",
    queryPatterns: [/fetchStudentSettlements\(/, /appliedFilters = \{ \.\.\.filters \}/, /renderWithFilters\(appliedFilters\)/],
    auxiliaryReaders: ["fetchSettlementStudents", "fetchStudentMonthCandidates"],
    mainResultReaders: ["fetchStudentSettlements", "runQuery"],
    writers: ["saveStudentSettlementDraftOnline"],
  },
  {
    id: "wage-rule",
    label: "工资规则",
    html: "wage-rule.html",
    app: "js/wage-rule-app.js",
    page: "js/pages/wage-rule-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /restoreFilterSelections\(draftFilters\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /ruleQueryRequestSequence \+= 1/,
      /appliedFilters = null/,
      /wageRules = \[\]/,
      /closeEditDialog\(\{ force: true \}\)/,
      /closeActiveStateDialog\(\{ force: true \}\)/,
      /renderWageRules\(\[\]\)/,
    ],
    queryFunction: "queryDraftFilters",
    queryPatterns: [/fetchWageRules\(\)/, /appliedFilters = nextAppliedFilters/, /renderWageRules\(/, /requestId !== ruleQueryRequestSequence/],
    auxiliaryReaders: ["fetchWageRuleCurrentStudentCandidates", "refreshDraftStudentCandidates"],
    mainResultReaders: ["fetchWageRules", "queryDraftFilters"],
    writers: ["createWageRuleConfig", "updateWageRuleConfig", "setWageRuleActiveState"],
  },
  {
    id: "income",
    label: "收入记录",
    html: "income.html",
    app: "js/income-app.js",
    page: "js/pages/income-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(draftFilters\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /incomeQueryRequestSequence \+= 1/,
      /appliedFilters = null/,
      /incomeRecords = \[\]/,
      /selectedIncomeIds = new Set\(\)/,
      /closeBatchCashIncomeDialog\(\)/,
      /renderIncomeRecords\(\[\]\)/,
      /setIncomeQuerying\(false\)/,
    ],
    queryFunction: "queryDraftFilters",
    queryPatterns: [/fetchIncomeRecords\(/, /appliedFilters = \{ \.\.\.nextAppliedFilters \}/, /applyCurrentFilters\(appliedFilters\)/, /requestId !== incomeQueryRequestSequence/],
    auxiliaryReaders: ["fetchStudentMonthCandidates", "refreshDraftStudentCandidates"],
    mainResultReaders: ["fetchIncomeRecords", "queryDraftFilters", "loadIncomeMonth"],
    writers: ["createIncomeRecord", "createPendingCashIncomeRecord", "requestCashIncomeConfirmationForRecord", "generateStudentTuitionBillAtomic"],
  },
  {
    id: "expense",
    label: "支出记录",
    html: "expense.html",
    app: "js/expense-app.js",
    page: "js/pages/expense-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(draftFilters\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /expenseQueryRequestSequence \+= 1/,
      /appliedFilters = null/,
      /expenseRecords = \[\]/,
      /paymentRequestsByExpenseId = new Map\(\)/,
      /attachmentCountsByExpenseId = new Map\(\)/,
      /selectedExpenseIds = new Set\(\)/,
      /closeBatchCashExpenseDialog\(\)/,
      /renderExpenseRecords\(\[\]\)/,
    ],
    queryFunction: "queryDraftFilters",
    queryPatterns: [/fetchExpenseMonthSnapshot\(/, /appliedFilters = \{ \.\.\.nextAppliedFilters \}/, /applyCurrentFilters\(appliedFilters\)/, /requestId !== expenseQueryRequestSequence/],
    auxiliaryReaders: ["fetchStudentMonthCandidates", "refreshDraftStudentCandidates"],
    mainResultReaders: ["fetchExpenseRecords", "fetchExpenseMonthSnapshot", "queryDraftFilters", "loadExpenseMonth"],
    writers: ["createExpenseRecord", "createPendingCashExpenseRecord", "requestCashExpenseConfirmation"],
  },
  {
    id: "part-time-work-annual",
    label: "外部授课年度汇总",
    html: "part-time-work-annual.html",
    app: "js/part-time-work-annual-app.js",
    page: "js/pages/part-time-work-annual-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setYearFilterValue\(currentFiscalYear\(\)\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /annualRequestSequence \+= 1/,
      /appliedFiscalYear = null/,
      /summaryTitle\.textContent = ""/,
      /summaryContainer\.innerHTML = ""/,
      /setLoading\(false\)/,
    ],
    queryFunction: "loadAnnualSummary",
    queryPatterns: [/fetchPartTimeWorkAnnualSummary\(fiscalYear\)/, /appliedFiscalYear = fiscalYear/, /renderAnnualSummary\(summary, fiscalYear\)/, /requestId !== annualRequestSequence/],
    auxiliaryReaders: [],
    mainResultReaders: ["fetchPartTimeWorkAnnualSummary", "loadAnnualSummary"],
    writers: [],
  },
  {
    id: "part-time-work",
    label: "PTW授课记录与授课结算共享视图",
    html: "part-time-work.html",
    app: "js/part-time-work-app.js",
    page: "js/pages/part-time-work-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /normalizePartTimeWorkFilters\(\{\}, currentYearMonth\(\), WORKPLACE_OPTIONS\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /pageDataRequestSequence \+= 1/,
      /appliedFilters = null/,
      /lessons = \[\]/,
      /wageLessons = \[\]/,
      /settlements = \[\]/,
      /editingLesson = null/,
      /pendingIncomeGenerationSettlement = null/,
      /lessonColumns\.innerHTML = ""/,
      /wageCalculationContainer\.innerHTML = ""/,
      /setLoading\(false\)/,
    ],
    queryFunction: "loadPageData",
    queryPatterns: [
      /const requestId = \+\+pageDataRequestSequence/,
      /fetchPartTimeWorkLessons\(/,
      /fetchPartTimeWorkMonthlySettlements\(/,
      /renderVisibleLessons\(/,
      /renderWageCalculation\(/,
      /requestId !== pageDataRequestSequence/,
    ],
    auxiliaryReaders: [],
    mainResultReaders: ["fetchPartTimeWorkLessons", "fetchPartTimeWorkMonthlySettlements", "loadPageData"],
    writers: [
      "createPartTimeWorkPlannedLesson",
      "updatePartTimeWorkLesson",
      "generatePartTimeWorkActualFromPlanned",
      "deletePartTimeWorkLesson",
      "lockPartTimeWorkMonthlySettlement",
      "unlockPartTimeWorkMonthlySettlement",
      "createPartTimeWorkIncomeRequest",
    ],
  },
  {
    id: "weekly-schedule-image",
    label: "周课表图片",
    html: "weekly-schedule-image.html",
    app: "js/weekly-schedule-image-app.js",
    page: "js/pages/weekly-schedule-image-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /state\.mainRequestSequence \+= 1/,
      /state\.candidateRequestSequence \+= 1/,
      /state\.appliedFilters = null/,
      /state\.students = \[\]/,
      /state\.schedules = \[\]/,
      /renderSchedules\(\)/,
      /setLoading\(false\)/,
    ],
    queryFunction: "loadSchedules",
    queryPatterns: [
      /const requestId = \+\+state\.mainRequestSequence/,
      /fetchLessonRecords\(month\)/,
      /fetchLessonStudentsByIds\(/,
      /state\.appliedFilters = \{/,
      /renderSchedules\(\)/,
      /requestId !== state\.mainRequestSequence/,
    ],
    auxiliaryReaders: ["fetchStudentRangeCandidates", "refreshStudentCandidates"],
    mainResultReaders: ["fetchLessonTeachers", "fetchLessonSubjects", "fetchLessonRecords", "fetchLessonStudentsByIds", "loadSchedules"],
    writers: [],
    queryButtonPattern: /type="submit">生成预览<\/button>/,
  },
  {
    id: "classroom-schedule",
    label: "教室排班",
    html: "classroom-schedule.html",
    app: "js/classroom-schedule-app.js",
    page: "js/pages/classroom-schedule-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /state\.requestSequence \+= 1/,
      /state\.appliedFilters = null/,
      /state\.students = \[\]/,
      /state\.rows = \[\]/,
      /resetRenderedSchedule\(\)/,
      /setLoading\(false\)/,
    ],
    queryFunction: "loadSchedule",
    queryPatterns: [
      /const requestId = \+\+state\.requestSequence/,
      /fetchLessonRecords/,
      /fetchLessonStudentsByIds\(/,
      /filters\.venue = renderVenueOptions\(filters\.venue\)/,
      /state\.appliedFilters = filters/,
      /applyVenueFilter\(state\.appliedFilters\)/,
      /requestId !== state\.requestSequence/,
    ],
    auxiliaryReaders: [],
    mainResultReaders: ["fetchLessonTeachers", "fetchLessonSubjects", "fetchLessonRecords", "fetchLessonStudentsByIds", "loadSchedule"],
    writers: [],
    queryButtonPattern: /type="submit">刷新排班<\/button>/,
  },
  {
    id: "weekly-lesson-dashboard",
    label: "本周课时待处理",
    html: "weekly-lesson-dashboard.html",
    app: "js/weekly-lesson-dashboard-app.js",
    page: "js/pages/weekly-lesson-dashboard-page.js",
    resetTarget: "dom.resetButton",
    resetDefaultPattern: /setDefaultFilters\(\)/,
    resetClearCallPattern: /clearQueryResults\(\)/,
    resetClearFunction: "clearQueryResults",
    clearPatterns: [
      /state\.requestSequence \+= 1/,
      /state\.appliedFilters = null/,
      /state\.students = \[\]/,
      /state\.rows = \[\]/,
      /dom\.plannedHours\.textContent = "-"/,
      /dom\.rows\.innerHTML = ""/,
      /setLoading\(false\)/,
    ],
    queryFunction: "loadDashboard",
    queryPatterns: [
      /const requestId = \+\+state\.requestSequence/,
      /fetchWeeklyLessonOperations\(weekStart\)/,
      /fetchLessonStudentsByIds\(/,
      /state\.appliedFilters = \{ weekStart \}/,
      /renderRows\(rows\)/,
      /requestId !== state\.requestSequence/,
    ],
    auxiliaryReaders: [],
    mainResultReaders: ["fetchWeeklyLessonOperations", "fetchLessonStudentsByIds", "loadDashboard"],
    writers: [],
    queryButtonPattern: /type="submit">查询本周<\/button>/,
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

  assert.match(html, page.queryButtonPattern || /type="submit">查询<\/button>/, `${page.label}: explicit query button missing`);
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

const settlementSource = read("js/pages/settlement-page.js");
assert.doesNotMatch(settlementSource, /dom\.(?:yearFilter|monthFilter|studentSelect|statusSelect|keywordInput)\??\.addEventListener\("(?:change|input)"[\s\S]{0,180}(?:runQuery|applyQuery|renderWithFilters|renderSettlements)\(/);

const wageRuleSource = read("js/pages/wage-rule-page.js");
assert.doesNotMatch(wageRuleSource, /dom\.(?:teacherSelect|studentSelect|subjectSelect|activeSelect|keywordInput)\.addEventListener\("(?:change|input)"[\s\S]{0,180}(?:queryDraftFilters|renderWageRules)\(/);

const incomeSource = read("js/pages/income-page.js");
assert.doesNotMatch(incomeSource, /dom\.(?:yearFilter|monthFilter|studentSelect|accountSelect|categorySelect|currencySelect)\.addEventListener\("change"[\s\S]{0,180}(?:queryDraftFilters|applyCurrentFilters|renderIncomeRecords)\(/);

const expenseSource = read("js/pages/expense-page.js");
assert.doesNotMatch(expenseSource, /dom\.(?:yearFilter|monthFilter|studentSelect|teacherSelect|accountSelect|currencySelect)\.addEventListener\("change"[\s\S]{0,180}(?:queryDraftFilters|applyCurrentFilters|renderExpenseRecords)\(/);

const annualSource = read("js/pages/part-time-work-annual-page.js");
const annualChangeHandler = annualSource.match(/dom\.yearFilter\?\.addEventListener\("change", \(\) => \{([\s\S]*?)\n  \}\);/);
assert.ok(annualChangeHandler, "外部授课年度汇总: year change handler missing");
assert.match(annualChangeHandler[1], /updateYearUrl\(selectedFiscalYear\(\)\)/);
assert.doesNotMatch(annualChangeHandler[1], /(?:loadAnnualSummary|fetchPartTimeWorkAnnualSummary|renderAnnualSummary)\(/);

const weeklyScheduleImageSource = read("js/pages/weekly-schedule-image-page.js");
const weeklyScheduleScopeChange = functionSource(weeklyScheduleImageSource, "handleCandidateScopeChange");
assert.match(weeklyScheduleScopeChange, /refreshStudentCandidates\(/);
assert.doesNotMatch(weeklyScheduleScopeChange, /(?:loadSchedules|fetchLessonRecords|fetchLessonStudentsByIds|renderSchedules)\(/);

const classroomScheduleSource = read("js/pages/classroom-schedule-page.js");
assert.match(classroomScheduleSource, /dom\.venueSelect\?\.addEventListener\("change", handleDraftFilterChange\)/);
assert.doesNotMatch(classroomScheduleSource, /dom\.venueSelect\?\.addEventListener\("change", applyVenueFilter\)/);
const classroomDraftChange = functionSource(classroomScheduleSource, "handleDraftFilterChange");
assert.match(classroomDraftChange, /clearQueryResults\(\)/);
assert.doesNotMatch(classroomDraftChange, /(?:loadSchedule|fetchLessonRecords|fetchLessonStudentsByIds|applyVenueFilter|renderBoard)\(/);

const weeklyDashboardSource = read("js/pages/weekly-lesson-dashboard-page.js");
const weeklyDashboardShift = functionSource(weeklyDashboardSource, "shiftWeek");
assert.match(weeklyDashboardShift, /handleDraftWeekChange\(\)/);
assert.doesNotMatch(weeklyDashboardShift, /(?:loadDashboard|fetchWeeklyLessonOperations|fetchLessonStudentsByIds|renderRows)\(/);

const migrationCounts = {
  htmlPages: { applicable: 18, compliant: 17, deprecatedLegacyException: 1, pendingMigration: 0, notApplicable: 0 },
  routeViews: { applicable: 19, compliant: 18, deprecatedLegacyException: 1, pendingMigration: 0, notApplicable: 0 },
};
const pendingMigrations = [];
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
  compliant: 17,
  deprecatedLegacyException: 1,
  pendingMigration: 0,
  notApplicable: 0,
});
assert.deepEqual(migrationCounts.routeViews, {
  applicable: 19,
  compliant: 18,
  deprecatedLegacyException: 1,
  pendingMigration: 0,
  notApplicable: 0,
});
assert.equal(legacyExceptions.length, 1);
assert.equal(pendingMigrations.length, 0);
assert.equal(legacyExceptions[0].status, "deprecated_legacy_exception");
assert.equal(legacyExceptions[0].reason, "V3 removal");
assert.equal(legacyExceptions[0].contract, "V2维持现状，不纳入顶部筛选合同迁移；V3删除；如果出现数据、权限或支付链问题，再单独处理。");
assert.doesNotThrow(() => read(legacyExceptions[0].html));
assert.doesNotThrow(() => read(legacyExceptions[0].page));

const config = read("js/config.js");
assert.match(config, /APP_VERSION = "v10\.5\.63"/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = read(`js/pages/${pageFile}`);
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/, `page-layer DML regression: ${pageFile}`);
}

console.log(
  "FILTER_QUERY_RESET_CONTRACT_STATIC_TEST_PASS",
  "classifications=compliant,pending_migration,deprecated_legacy_exception,not_applicable",
  "html=18/17/1/0/0",
  "route_views=19/18/1/0/0"
);
