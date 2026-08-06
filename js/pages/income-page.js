import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import {
  initSchoolAuth,
  isActiveAdmin,
  requireActiveAdminForCashConfirmation,
} from "../auth.js?v=p0-g1-b1-20260804-1";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createIncomeRecord,
  createPendingCashIncomeRecord,
  fetchCashIncomeSubmissionPreflight,
  fetchIncomeLookups,
  fetchIncomeRecords,
  fetchStudentTuitionValidationPreviewDetails,
  generateStudentTuitionBillAtomic,
  requestCashIncomeConfirmationForRecord,
} from "../api/income-api.js?v=phase-b4-finance-20260807-1";
import { fetchSchoolEligibleCashAccountsViaFunction } from "../api/payment-api.js";
import { fetchLessonSubjects, fetchLessonTeachers } from "../api/lesson-api.js";
import {
  currentJapanDate,
  currentYearMonth,
  getYearMonthSelectValue,
  initialYearMonthFromUrl,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
  updateMonthScopedNavigation,
  updateUrlMonthParams,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";
import {
  buildAtomicTuitionGeneratePayload,
  createLatestTuitionPreviewRequestGate,
  createTuitionAtomicGenerateState,
  formatAuthoritativeBillingWeek,
  isAtomicTuitionGenerateEnabled,
  mapAtomicTuitionGenerateError,
  mapTuitionValidationPreviewError,
  validateTuitionValidationPreviewDetails,
} from "../utils/tuition-validation-preview.js?v=v2.115.2-tuition-duplicate-message";
import {
  requirePrimarySchoolBusinessEntityId,
} from "../utils/business-entity-policy.js?v=be-ui-20260806-1";
import {
  fetchStudentMonthCandidates,
  readStudentCandidateQuery,
  renderStudentMonthCandidateOptions,
  writeStudentCandidateQuery,
} from "../api/student-status-api.js?v=phase-b4-finance-20260807-1";

const DEFAULT_FILTERS = {
  studentId: "",
  includeInactive: false,
  accountId: "",
  incomeCategory: "",
  currency: "",
};

const INCOME_STATUS_LABELS = {
  pending: "待确认",
  received: "已收款",
  reversed: "已冲销",
  cancelled: "已作废",
};

const INCOME_CATEGORY_LABELS = {
  tuition: "学费",
  material_fee: "教材费",
  registration_fee: "报名费",
  other_fee: "其他费用",
  part_time_work: "外部塾打工收入",
};

const EDITABLE_INCOME_CATEGORIES = ["tuition", "material_fee", "registration_fee", "other_fee"];
const CREATE_MODE_SCHOOL_ACCOUNT = "school_account";
const CREATE_MODE_CASH_SYSTEM_INCOME = "cash_system_income";
const CASH_INCOME_CURRENCIES = ["JPY", "CNY"];
const JPY_CNY_RATE_API_URL = "https://api.frankfurter.dev/v2/rate/JPY/CNY";
const ROUNDING_MODE_LABELS = {
  round: "四舍五入",
  ceil: "向上取整",
  floor: "向下取整",
};

const PAYMENT_METHOD_LABELS = {
  alipay: "支付宝",
  bank_transfer: "银行转账",
  cash: "现金",
  card: "银行卡",
  wechat: "微信",
};

const CASH_LINKAGE_STATUS_LABELS = {
  pending_cash_request: "Cash待提交",
  awaiting_cash_confirmation: "Cash待确认",
  pending: "Cash待同步",
  synced: "Cash已同步",
  historical_confirmed: "历史已确认",
  cash_rejected: "Cash已拒绝",
  blocked: "Cash已阻止",
  failed: "Cash失败",
};

const dom = {};
let students = [];
let businessEntities = [];
let accounts = [];
let teachers = [];
let subjects = [];
let cashEligibleAccounts = [];
let hasLoadedCashEligibleAccounts = false;
let incomeRecords = [];
let renderedIncomeRows = [];
let selectedIncomeIds = new Set();
let loadedMonth = "";
let isCreateSubmitting = false;
let batchCashIncomeRows = [];
let isBatchCashSubmitting = false;
let initialMonth = "";
let initialFilters = null;
let topStudentCandidates = [];
let topStudentCandidateKey = "";
let createStudentCandidates = [];
let tuitionBillStudentCandidates = [];
let createStudentCandidateRequestId = 0;
let tuitionStudentCandidateRequestId = 0;
let isTuitionBillPreviewLoading = false;
let tuitionBillPreviewSignature = "";
const tuitionBillPreviewRequestGate = createLatestTuitionPreviewRequestGate();
const tuitionBillGenerationState = createTuitionAtomicGenerateState();

export function initIncomePage() {
  cacheDom();
  initSchoolAuth();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  initialMonth = initialYearMonthFromUrl();
  initialFilters = readIncomeQuery();
  setDefaultFilters(initialFilters);
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderIncomeRecords([]);
    return;
  }

  loadInitialData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#incomeMessageArea");
  dom.filterForm = document.querySelector("#incomeFilterForm");
  dom.yearFilter = document.querySelector("#incomeYearFilter");
  dom.monthFilter = document.querySelector("#incomeMonthFilter");
  dom.studentSelect = document.querySelector("#incomeStudentSelect");
  dom.includeInactiveCheckbox = document.querySelector("#incomeIncludeInactiveCheckbox");
  dom.accountSelect = document.querySelector("#incomeAccountSelect");
  dom.categorySelect = document.querySelector("#incomeCategorySelect");
  dom.currencySelect = document.querySelector("#incomeCurrencySelect");
  dom.resetButton = document.querySelector("#incomeResetButton");
  dom.tableBody = document.querySelector("#incomeTableBody");
  dom.loadingState = document.querySelector("#incomeLoadingState");
  dom.emptyState = document.querySelector("#incomeEmptyState");
  dom.incomeCount = document.querySelector("#incomeCount");
  dom.openCreateIncomeButton = document.querySelector("#openCreateIncomeButton");
  dom.openGenerateTuitionBillButton = document.querySelector("#openGenerateTuitionBillButton");
  dom.openBatchCashIncomeButton = document.querySelector("#openBatchCashIncomeButton");
  dom.selectAllCashRequests = document.querySelector("#incomeSelectAllCashRequests");
  dom.batchCashIncomeDialog = document.querySelector("#batchCashIncomeDialog");
  dom.batchCashIncomeError = document.querySelector("#batchCashIncomeError");
  dom.batchCashIncomeTableBody = document.querySelector("#batchCashIncomeTableBody");
  dom.batchCashIncomeTotal = document.querySelector("#batchCashIncomeTotal");
  dom.batchCashIncomeSubmitButton = document.querySelector("#batchCashIncomeSubmitButton");
  dom.batchCashIncomeCancelButton = document.querySelector("#batchCashIncomeCancelButton");
  dom.createIncomeDialog = document.querySelector("#createIncomeDialog");
  dom.createIncomeError = document.querySelector("#createIncomeError");
  dom.createIncomeModeSelect = document.querySelector("#createIncomeModeSelect");
  dom.createIncomeDateInput = document.querySelector("#createIncomeDateInput");
  dom.createSettlementMonthInput = document.querySelector("#createSettlementMonthInput");
  dom.createIncomeStudentSelect = document.querySelector("#createIncomeStudentSelect");
  dom.createIncomeIncludeInactiveCheckbox = document.querySelector("#createIncomeIncludeInactiveCheckbox");
  dom.createIncomeAccountSelect = document.querySelector("#createIncomeAccountSelect");
  dom.createIncomeCurrencySelect = document.querySelector("#createIncomeCurrencySelect");
  dom.createIncomeCashMappingSelect = document.querySelector("#createIncomeCashMappingSelect");
  dom.createIncomeCategorySelect = document.querySelector("#createIncomeCategorySelect");
  dom.createIncomeAmountInput = document.querySelector("#createIncomeAmountInput");
  dom.createIncomePaymentMethodSelect = document.querySelector("#createIncomePaymentMethodSelect");
  dom.createIncomeDescriptionInput = document.querySelector("#createIncomeDescriptionInput");
  dom.createIncomeExchangeRateInput = document.querySelector("#createIncomeExchangeRateInput");
  dom.createIncomeTaxableSelect = document.querySelector("#createIncomeTaxableSelect");
  dom.createIncomeTaxCategoryInput = document.querySelector("#createIncomeTaxCategoryInput");
  dom.createIncomeReceiptStatusInput = document.querySelector("#createIncomeReceiptStatusInput");
  dom.createIncomeNoteInput = document.querySelector("#createIncomeNoteInput");
  dom.createIncomeSubmitButton = document.querySelector("#createIncomeSubmitButton");
  dom.createIncomeCancelButton = document.querySelector("#createIncomeCancelButton");
  dom.generateTuitionBillDialog = document.querySelector("#generateTuitionBillDialog");
  dom.generateTuitionBillError = document.querySelector("#generateTuitionBillError");
  dom.generateTuitionBillPreview = document.querySelector("#generateTuitionBillPreview");
  dom.tuitionBillCandidateDetails = document.querySelector("#tuitionBillCandidateDetails");
  dom.tuitionBillCandidateCount = document.querySelector("#tuitionBillCandidateCount");
  dom.tuitionBillCandidateRows = document.querySelector("#tuitionBillCandidateRows");
  dom.tuitionBillMonthInput = document.querySelector("#tuitionBillMonthInput");
  dom.tuitionBillStudentSelect = document.querySelector("#tuitionBillStudentSelect");
  dom.tuitionBillIncludeInactiveCheckbox = document.querySelector("#tuitionBillIncludeInactiveCheckbox");
  dom.tuitionBillBillingRateInput = document.querySelector("#tuitionBillBillingRateInput");
  dom.tuitionBillNoteInput = document.querySelector("#tuitionBillNoteInput");
  dom.generateTuitionBillCancelButton = document.querySelector("#generateTuitionBillCancelButton");
  dom.generateTuitionBillPreviewButton = document.querySelector("#generateTuitionBillPreviewButton");
  dom.generateTuitionBillSubmitButton = document.querySelector("#generateTuitionBillSubmitButton");
  dom.confirmGenerateTuitionBillDialog = document.querySelector("#confirmGenerateTuitionBillDialog");
  dom.confirmGenerateTuitionBillError = document.querySelector("#confirmGenerateTuitionBillError");
  dom.confirmGenerateTuitionBillSummary = document.querySelector("#confirmGenerateTuitionBillSummary");
  dom.confirmGenerateTuitionBillCancelButton = document.querySelector("#confirmGenerateTuitionBillCancelButton");
  dom.confirmGenerateTuitionBillSubmitButton = document.querySelector("#confirmGenerateTuitionBillSubmitButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    applyQuery();
  });
  dom.yearFilter.addEventListener("change", applyQuery);
  dom.monthFilter.addEventListener("change", applyQuery);
  dom.includeInactiveCheckbox.addEventListener("change", applyQuery);

  dom.resetButton.addEventListener("click", () => {
    clearTuitionBillPreview();
    setDefaultFilters({ month: currentYearMonth() });
    applyQuery();
  });

  dom.openCreateIncomeButton.addEventListener("click", openCreateIncomeDialog);
  dom.openGenerateTuitionBillButton.addEventListener("click", openGenerateTuitionBillDialog);
  dom.openBatchCashIncomeButton.addEventListener("click", () => {
    openBatchCashIncomeDialog(selectedIncomeRows());
  });
  dom.selectAllCashRequests.addEventListener("change", handleIncomeSelectAllChange);
  dom.tableBody.addEventListener("click", handleIncomeTableClick);
  dom.tableBody.addEventListener("change", handleIncomeTableChange);
  dom.batchCashIncomeCancelButton.addEventListener("click", closeBatchCashIncomeDialog);
  dom.batchCashIncomeSubmitButton.addEventListener("click", submitBatchCashIncomeRequests);
  dom.batchCashIncomeTableBody.addEventListener("input", handleBatchCashIncomeInput);
  dom.batchCashIncomeTableBody.addEventListener("change", handleBatchCashIncomeInput);
  dom.batchCashIncomeTableBody.addEventListener("click", handleBatchCashIncomeClick);
  dom.createIncomeCancelButton.addEventListener("click", closeCreateIncomeDialog);
  dom.createIncomeSubmitButton.addEventListener("click", submitCreateIncome);
  dom.generateTuitionBillCancelButton.addEventListener("click", closeGenerateTuitionBillDialog);
  dom.generateTuitionBillPreviewButton.addEventListener("click", handlePreviewTuitionBill);
  dom.generateTuitionBillSubmitButton.addEventListener("click", submitGenerateTuitionBill);
  dom.confirmGenerateTuitionBillCancelButton.addEventListener("click", closeGenerateTuitionBillConfirmation);
  dom.confirmGenerateTuitionBillSubmitButton.addEventListener("click", confirmGenerateTuitionBill);
  dom.tuitionBillStudentSelect.addEventListener("change", () => {
    clearTuitionBillFieldInvalid("student");
    clearTuitionBillPreview();
  });
  dom.tuitionBillMonthInput.addEventListener("change", () => {
    clearTuitionBillFieldInvalid("billingMonth");
    clearTuitionBillPreview();
    refreshTuitionBillStudentCandidates();
  });
  dom.tuitionBillIncludeInactiveCheckbox.addEventListener("change", () => {
    clearTuitionBillPreview();
    refreshTuitionBillStudentCandidates();
  });
  dom.tuitionBillBillingRateInput.addEventListener("input", () => {
    clearTuitionBillFieldInvalid("billingRate");
    clearTuitionBillPreview();
  });
  dom.createIncomeModeSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("createMode");
    hideCreateErrorIfClean();

    updateCreateModeUi({ preserveBusinessEntity: true });
  });
  dom.createIncomeStudentSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("student");
    hideCreateErrorIfClean();
  });
  dom.createIncomeIncludeInactiveCheckbox.addEventListener("change", refreshCreateStudentCandidates);
  dom.createSettlementMonthInput.addEventListener("change", refreshCreateStudentCandidates);
  dom.createIncomeAccountSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("account");
    hideCreateErrorIfClean();
  });
  dom.createIncomeCashMappingSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("cashMapping");
    hideCreateErrorIfClean();
  });
  dom.createIncomeCurrencySelect.addEventListener("change", () => {
    dom.createIncomeCashMappingSelect.value = "";
    renderCreateCashAccountOptions();
    clearCreateFieldInvalid("cashCurrency");
    clearCreateFieldInvalid("cashMapping");
    hideCreateErrorIfClean();
  });
  dom.createIncomeCategorySelect.addEventListener("change", () => {
    clearCreateFieldInvalid("incomeCategory");
    hideCreateErrorIfClean();
  });

  for (const [input, fieldId] of [
    [dom.createIncomeDateInput, "incomeDate"],
    [dom.createSettlementMonthInput, "settlementMonth"],
    [dom.createIncomeAmountInput, "amount"],
    [dom.createIncomePaymentMethodSelect, "paymentMethod"],
    [dom.createIncomeExchangeRateInput, "exchangeRate"],
  ]) {
    input.addEventListener("input", () => {
      clearCreateFieldInvalid(fieldId);
      hideCreateErrorIfClean();
    });
  }
}

function setDefaultFilters(overrides = null) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, overrides?.month || initialMonth || currentYearMonth());
  dom.studentSelect.value = DEFAULT_FILTERS.studentId;
  dom.includeInactiveCheckbox.checked = Boolean(overrides?.includeInactive);
  dom.accountSelect.value = DEFAULT_FILTERS.accountId;
  dom.categorySelect.value = DEFAULT_FILTERS.incomeCategory;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  if (overrides) {
    dom.studentSelect.value = overrides.studentId || "";
    dom.accountSelect.value = overrides.accountId || "";
    dom.categorySelect.value = overrides.incomeCategory || "";
    dom.currencySelect.value = overrides.currency || "";
  }
  updateMonthScopedNavigation(getYearMonthSelectValue(dom.yearFilter, dom.monthFilter));
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载收入记录数据...");

  try {
    const [lookups, lessonTeachers, lessonSubjects] = await Promise.all([
      fetchIncomeLookups(),
      fetchLessonTeachers(),
      fetchLessonSubjects(),
    ]);
    students = lookups.students;
    businessEntities = lookups.businessEntities;
    requirePrimarySchoolBusinessEntityId(businessEntities);
    accounts = lookups.accounts;
    teachers = lessonTeachers;
    subjects = lessonSubjects;
    const filters = initialFilters || readFilters();
    await Promise.all([loadIncomeMonth(filters.month), loadTopStudentCandidates(filters)]);
    renderMasterOptions();
    restoreFilterSelections(filters);
    syncIncomeQuery(filters);
    updateMonthScopedNavigation(filters.month);
    applyCurrentFilters();
    showMessage("success", "收入记录数据已加载。");
  } catch (error) {
    students = [];
    businessEntities = [];
    accounts = [];
    teachers = [];
    subjects = [];
    cashEligibleAccounts = [];
    hasLoadedCashEligibleAccounts = false;
    incomeRecords = [];
    loadedMonth = "";
    topStudentCandidates = [];
    topStudentCandidateKey = "";
    renderMasterOptions();
    renderDataOptions([]);
    renderIncomeRecords([]);
    showMessage("error", `读取收入记录数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

async function applyQuery() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  if (!filters) {
    return;
  }

  syncIncomeQuery(filters);
  updateMonthScopedNavigation(filters.month);

  if (filters.month !== loadedMonth || studentCandidateKey(filters) !== topStudentCandidateKey) {
    setLoading(true);
    showMessage("info", "正在加载收入记录...");

    try {
      await Promise.all([loadIncomeMonth(filters.month), loadTopStudentCandidates(filters)]);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "收入记录已加载。");
    } catch (error) {
      incomeRecords = [];
      loadedMonth = "";
      topStudentCandidates = [];
      topStudentCandidateKey = "";
      renderDataOptions([]);
      renderIncomeRecords([]);
      showMessage("error", `读取收入记录失败：${error.message || error}`);
    } finally {
      setLoading(false);
    }
    return;
  }

  applyCurrentFilters();
}

async function loadIncomeMonth(month) {
  incomeRecords = await fetchIncomeRecords(month);
  loadedMonth = month;
  renderDataOptions(incomeRecords);
}

async function loadTopStudentCandidates(filters) {
  topStudentCandidates = await fetchStudentMonthCandidates({
    month: filters.month,
    includeInactive: filters.includeInactive,
    selectedStudentId: filters.studentId || null,
  });
  topStudentCandidateKey = studentCandidateKey(filters);
  renderStudentMonthCandidateOptions(dom.studentSelect, topStudentCandidates, {
    selectedStudentId: filters.studentId,
  });
}

function applyCurrentFilters() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  restoreFilterSelections(filters);
  renderIncomeRecords(filterIncomeRecords(incomeRecords, filters));
}

function readFilters() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    showMessage("error", "请选择正确的年月。");
    return null;
  }

  return {
    month,
    studentId: dom.studentSelect.value,
    includeInactive: dom.includeInactiveCheckbox.checked,
    accountId: dom.accountSelect.value,
    incomeCategory: dom.categorySelect.value,
    currency: dom.currencySelect.value,
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.studentSelect.value = filters.studentId;
  dom.includeInactiveCheckbox.checked = Boolean(filters.includeInactive);
  dom.accountSelect.value = filters.accountId;
  dom.categorySelect.value = filters.incomeCategory;
  dom.currencySelect.value = filters.currency;
  updateMonthNavigationFromCurrentSelection();
}

function updateMonthNavigationFromCurrentSelection() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    return;
  }
  updateMonthScopedNavigation(month);
}

function studentCandidateKey(filters) {
  return `${filters.month}::${filters.includeInactive ? "1" : "0"}::${filters.studentId || ""}`;
}

function readIncomeQuery() {
  const params = new URLSearchParams(window.location.search);
  const candidate = readStudentCandidateQuery(window.location.search);
  return {
    month: initialMonth || currentYearMonth(),
    ...DEFAULT_FILTERS,
    ...candidate,
    accountId: params.get("account_id") || "",
    incomeCategory: params.get("income_category") || "",
    currency: params.get("currency") || "",
  };
}

function syncIncomeQuery(filters) {
  if (!window.history?.replaceState) return;
  const [year, month] = filters.month.split("-");
  const url = new URL(window.location.href);
  url.searchParams.set("year", year);
  url.searchParams.set("month", month);
  writeStudentCandidateQuery(url.searchParams, filters);
  setOptionalQuery(url.searchParams, "account_id", filters.accountId);
  setOptionalQuery(url.searchParams, "income_category", filters.incomeCategory);
  setOptionalQuery(url.searchParams, "currency", filters.currency);
  window.history.replaceState({}, "", url);
}

function setOptionalQuery(params, key, value) {
  if (value) params.set(key, value);
  else params.delete(key);
}

function renderMasterOptions() {
  renderStudentMonthCandidateOptions(dom.studentSelect, topStudentCandidates, {
    selectedStudentId: dom.studentSelect.value,
  });
  renderEntityOptions(dom.accountSelect, accounts, accountName);
}

function renderDataOptions(rows) {
  renderValueOptions(dom.categorySelect, distinctValues(rows, "income_category"), incomeCategoryLabel);
  renderValueOptions(dom.currencySelect, distinctValues(rows, "currency"), displayValue);
}

function renderEntityOptions(selectEl, rows, labelGetter) {
  const options = ['<option value="">全部</option>'];

  for (const row of rows) {
    options.push(
      `<option value="${escapeAttribute(row.id)}">${escapeHtml(labelGetter(row))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function renderValueOptions(selectEl, values, labelGetter) {
  const options = ['<option value="">全部</option>'];

  for (const value of values) {
    options.push(
      `<option value="${escapeAttribute(value)}">${escapeHtml(labelGetter(value))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function renderIncomeRecords(rows) {
  renderedIncomeRows = rows;
  pruneSelectedIncomeIds();
  const cashRequestableCount = rows.filter(canRequestCashIncome).length;
  dom.incomeCount.textContent = `共 ${rows.length} 条｜可提交 Cash ${cashRequestableCount} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    updateIncomeBatchControls();
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td class="income-select-cell">${renderIncomeSelectionCell(row)}</td>
      <td class="income-source-cell">${renderIncomeSourceCell(row)}</td>
      <td><span class="status-badge status-neutral">${escapeHtml(incomeCategoryLabel(row.income_category))}</span></td>
      <td class="income-nowrap month-cell">${escapeHtml(formatMonth(row.year_month))}</td>
      <td class="income-nowrap date-cell">${escapeHtml(formatDateOnly(row.income_date))}</td>
      <td class="number-cell income-nowrap amount-cell">${escapeHtml(formatIncomeListAmount(row))}</td>
      <td class="number-cell income-nowrap carryover-amount-cell">${renderIncomeListCarryoverImpact(row)}</td>
      <td class="number-cell income-nowrap notice-amount-cell">${escapeHtml(formatIncomeListNoticeAmount(row))}</td>
      <td>${renderIncomeStatusSummary(row)}</td>
      <td class="income-related-cell">${renderIncomeRelatedCell(row)}</td>
      <td class="action-cell income-action-cell">${renderIncomeRowActions(row)}</td>
    </tr>
  `).join("");
  updateIncomeBatchControls();
}

function renderIncomeSourceCell(row) {
  const primary = incomeObjectName(row);
  const secondary = [
    displayValue(row.source_label || row.description),
    paymentMethodLabel(row.payment_method),
  ].filter((value) => value && value !== "-").join(" / ");
  const title = [
    primary,
    secondary,
    safeText(row.note),
  ].filter(Boolean).join(" / ");
  return `
    <div class="income-list-primary" title="${escapeAttribute(title || "无业务备注")}">${escapeHtml(primary)}</div>
    <div class="income-list-secondary" title="${escapeAttribute(secondary || "无业务备注")}">${escapeHtml(secondary || "无业务备注")}</div>
  `;
}

function renderIncomeRelatedCell(row) {
  const primary = incomeAccountDisplayName(row);
  const secondary = [
    row.settlement_month ? `结算 ${formatMonth(row.settlement_month)}` : "",
    row.receipt_status ? `收据 ${row.receipt_status}` : "",
  ].filter((value) => value && value !== "-").join(" / ");
  return `
    <div class="income-list-primary" title="${escapeAttribute(primary)}">${escapeHtml(primary)}</div>
    <div class="income-list-secondary" title="${escapeAttribute(secondary || "-")}">${escapeHtml(secondary || "-")}</div>
  `;
}

function renderIncomeStatusSummary(row) {
  const event = row.cashIncomeLinkageEvent;
  return `
    <div class="income-cash-status-cell">
      <span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(incomeStatusLabel(row.status))}</span>
      ${event ? renderCashSyncBadge(event) : `<span class="income-cash-hint">${escapeHtml(canRequestCashIncome(row) ? "可提交 Cash" : cashIncomeRequestNotAllowedMessage(row) || "未提交 Cash")}</span>`}
      ${event ? `<span class="income-cash-hint">${escapeHtml(cashLinkageStatusHint(event.sync_status))}</span>` : ""}
    </div>
  `;
}

function renderIncomeSelectionCell(row) {
  const selectable = canRequestCashIncome(row);
  const disabledReason = selectable ? "" : cashIncomeRequestNotAllowedMessage(row);
  return `
    <input
      type="checkbox"
      data-income-select-id="${escapeAttribute(row.id)}"
      aria-label="选择收入记录 ${escapeAttribute(incomeObjectName(row))}"
      ${disabledReason ? `title="${escapeAttribute(disabledReason)}"` : ""}
      ${selectable ? "" : "disabled"}
      ${selectedIncomeIds.has(row.id) ? "checked" : ""}
    >
  `;
}

function renderIncomeRowActions(row) {
  const cashButton = canRequestCashIncome(row)
    ? `<button class="table-action-button" type="button" data-income-cash-request-id="${escapeAttribute(row.id)}">提交Cash</button>`
    : "";
  const receiptButton = canGenerateTuitionReceipt(row)
    ? `<a class="button table-action-button" href="${escapeAttribute(tuitionReceiptHref(row.id))}">生成收据</a>`
    : "";
  return `
    <div class="income-row-actions">
      <a class="button table-action-button" href="${escapeAttribute(incomeDetailHref(row.id))}">详情</a>
      ${cashButton}
      ${receiptButton}
    </div>
  `;
}

function incomeDetailHref(incomeId) {
  const params = new URLSearchParams();
  params.set("id", incomeId);
  const filters = readFilters();
  if (filters?.month) {
    const [year, monthPart] = filters.month.split("-");
    params.set("year", year);
    params.set("month", monthPart);
    writeStudentCandidateQuery(params, filters);
    setOptionalQuery(params, "account_id", filters.accountId);
    setOptionalQuery(params, "income_category", filters.incomeCategory);
    setOptionalQuery(params, "currency", filters.currency);
  }
  return `./income-detail.html?${params.toString()}`;
}

function tuitionReceiptHref(incomeId) {
  const params = new URLSearchParams();
  params.set("income_record_id", incomeId);
  return `./tuition-receipt.html?${params.toString()}`;
}

function handleIncomeTableClick(event) {
  const button = event.target.closest("[data-income-cash-request-id]");
  if (!button) {
    return;
  }

  const incomeId = button.getAttribute("data-income-cash-request-id");
  const income = incomeRecords.find((row) => row.id === incomeId);
  if (!income) {
    showMessage("error", "收入记录不存在，请刷新后重试。");
    return;
  }

  openBatchCashIncomeDialog([income]);
}

function handleIncomeTableChange(event) {
  const checkbox = event.target.closest("[data-income-select-id]");
  if (!checkbox) {
    return;
  }

  const incomeId = checkbox.getAttribute("data-income-select-id");
  const income = renderedIncomeRows.find((row) => row.id === incomeId);
  if (!income || !canRequestCashIncome(income)) {
    checkbox.checked = false;
    selectedIncomeIds.delete(incomeId);
    updateIncomeBatchControls();
    return;
  }

  if (checkbox.checked) {
    selectedIncomeIds.add(incomeId);
  } else {
    selectedIncomeIds.delete(incomeId);
  }
  updateIncomeBatchControls();
}

function handleIncomeSelectAllChange() {
  const selectableIds = renderedIncomeRows.filter(canRequestCashIncome).map((row) => row.id);
  if (dom.selectAllCashRequests.checked) {
    selectedIncomeIds = new Set(selectableIds);
  } else {
    for (const id of selectableIds) {
      selectedIncomeIds.delete(id);
    }
  }
  renderIncomeRecords(renderedIncomeRows);
}

function selectedIncomeRows() {
  return renderedIncomeRows.filter((row) => selectedIncomeIds.has(row.id) && canRequestCashIncome(row));
}

function pruneSelectedIncomeIds() {
  const selectableIds = new Set(renderedIncomeRows.filter(canRequestCashIncome).map((row) => row.id));
  for (const id of Array.from(selectedIncomeIds)) {
    if (!selectableIds.has(id)) {
      selectedIncomeIds.delete(id);
    }
  }
}

function updateIncomeBatchControls() {
  const selectableRows = renderedIncomeRows.filter(canRequestCashIncome);
  const selectedRows = selectedIncomeRows();
  dom.openBatchCashIncomeButton.disabled = selectedRows.length === 0;
  dom.openBatchCashIncomeButton.textContent = selectedRows.length > 0
    ? `批量提交 Cash（已选 ${selectedRows.length} 条）`
    : "批量提交 Cash";
  dom.selectAllCashRequests.disabled = selectableRows.length === 0;
  dom.selectAllCashRequests.checked = selectableRows.length > 0 && selectedRows.length === selectableRows.length;
  dom.selectAllCashRequests.indeterminate = selectedRows.length > 0 && selectedRows.length < selectableRows.length;
}

async function openBatchCashIncomeDialog(rows) {
  const targets = (rows || []).filter(canRequestCashIncome);
  if (!targets.length) {
    showMessage("error", "请选择可提交 Cash 确认的收入记录。");
    return;
  }

  if (
    !requireActiveAdminForCashConfirmation((_type, message) => {
      showMessage("error", message);
    })
  ) {
    return;
  }

  try {
    await ensureCashEligibleAccountsLoaded();
  } catch (error) {
    showMessage("error", `Cash System 账户读取失败：${error.message || error}`);
    return;
  }

  batchCashIncomeRows = targets.map((income) => ({
    income,
    amount: income.source_type === "student_tuition_bill"
      ? formatDecimal(income.cashSubmissionPreflight?.payment_amount, 2)
      : defaultBatchCashIncomeAmount(income),
    amountSource: "db",
    currency: income.source_type === "student_tuition_bill"
      ? "CNY"
      : defaultBatchCashIncomeCurrency(income),
    receivedDate: currentJapanDate(),
    accountId: "",
    note: defaultCashIncomeNote(income),
    exchangeRate: income.source_type === "student_tuition_bill"
      ? formatRateValue(income.cashSubmissionPreflight?.payment_exchange_rate)
      : defaultBatchCashIncomeExchangeRate(income),
    theoreticalAmount: "",
    roundingMode: "",
    rateStatus: "",
    errors: {},
  }));
  clearBatchCashIncomeError();
  setBatchCashIncomeSubmitting(false);
  renderBatchCashIncomeRows();
  dom.batchCashIncomeDialog.classList.remove("is-hidden");
  dom.batchCashIncomeDialog.setAttribute("aria-hidden", "false");
}

function closeBatchCashIncomeDialog() {
  if (isBatchCashSubmitting) {
    return;
  }

  batchCashIncomeRows = [];
  dom.batchCashIncomeDialog.classList.add("is-hidden");
  dom.batchCashIncomeDialog.setAttribute("aria-hidden", "true");
}

function renderBatchCashIncomeRows() {
  updateBatchCashIncomeDerivedValues();
  dom.batchCashIncomeTableBody.innerHTML = batchCashIncomeRows.map((state) => {
    const income = state.income;
    const isTuition = income.source_type === "student_tuition_bill";
    return `
      <tr data-batch-income-row-id="${escapeAttribute(income.id)}">
        <td>${escapeHtml(incomeObjectName(income))}</td>
        <td class="income-nowrap">${escapeHtml(formatMonth(income.year_month))}</td>
        <td>${renderBatchCashIncomeField(state, "date", `<input data-batch-income-date="${escapeAttribute(income.id)}" type="date" value="${escapeAttribute(state.receivedDate)}" ${isBatchCashSubmitting ? "disabled" : ""}>`)}</td>
        <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(income.amount, income.currency))}</td>
        <td>${renderBatchCashIncomeField(state, "amount", `<input data-batch-income-amount="${escapeAttribute(income.id)}" type="number" min="0" step="0.01" inputmode="decimal" value="${escapeAttribute(state.amount)}" ${isTuition ? "readonly" : ""} ${isBatchCashSubmitting ? "disabled" : ""}>${isTuition ? '<div class="income-batch-cash-field-hint">冻结账单权威金额（只读）</div>' : renderBatchCashIncomeAmountHint(state)}`)}</td>
        <td>
          ${renderBatchCashIncomeField(state, "currency", `<select data-batch-income-currency="${escapeAttribute(income.id)}" ${isTuition || isBatchCashSubmitting ? "disabled" : ""}>
            ${CASH_INCOME_CURRENCIES.map((currency) => `<option value="${escapeAttribute(currency)}" ${currency === state.currency ? "selected" : ""}>${escapeHtml(currency)}</option>`).join("")}
          </select>`)}
        </td>
        <td>${renderBatchCashIncomeRateReference(state)}</td>
        <td>
          ${renderBatchCashIncomeField(state, "account", `<select data-batch-income-account="${escapeAttribute(income.id)}" ${isBatchCashSubmitting ? "disabled" : ""}>
            ${renderBatchCashIncomeAccountOptions(state)}
          </select>`)}
        </td>
        <td><input data-batch-income-note="${escapeAttribute(income.id)}" type="text" value="${escapeAttribute(state.note)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
      </tr>
      ${renderBatchCashIncomeRateRow(state)}
    `;
  }).join("");
  updateBatchCashIncomeTotal();
}

function renderBatchCashIncomeField(state, fieldId, controlHtml) {
  const error = state.errors?.[fieldId] || "";
  return `
    <div class="income-batch-cash-field${error ? " is-invalid" : ""}" data-batch-income-field="${escapeAttribute(fieldId)}">
      ${controlHtml}
      ${error ? `<div class="income-batch-cash-field-error">${escapeHtml(error)}</div>` : ""}
    </div>
  `;
}

function renderBatchCashIncomeAmountHint(state) {
  if (state.amountSource === "backend") {
    return '<div class="income-batch-cash-field-hint">提交时按汇率和取整方式确认。</div>';
  }

  if (state.amountSource === "db") {
    if (state.income?.source_type === "student_tuition_bill" && state.currency === "CNY") {
      return '<div class="income-batch-cash-field-hint">未手动修改时使用通知金额。</div>';
    }
    return '<div class="income-batch-cash-field-hint">未手动修改时使用原始金额。</div>';
  }

  return "";
}

function renderBatchCashIncomeRateReference(state) {
  if (state.income?.source_type === "student_tuition_bill") {
    return `<div class="expense-rate-assist expense-rate-assist--muted"><span>冻结汇率 ${escapeHtml(state.exchangeRate || "-")}</span></div>`;
  }
  if (!requiresCashIncomeExchangeRate(state)) {
    return `
      <div class="expense-rate-assist expense-rate-assist--muted">
        <span>同币种到账不需要汇率</span>
      </div>
    `;
  }

  return `
    <div class="expense-rate-assist expense-rate-assist--compact">
      <div class="expense-rate-assist-theory">
        <span>理论金额</span>
        <span class="expense-rate-assist-value">${escapeHtml(formatTheoreticalCashIncomeAmount(state))}</span>
      </div>
      <div class="expense-rounding-buttons" aria-label="取整方式">
        <button class="button compact-button" title="四舍五入" data-batch-income-round="${escapeAttribute(state.income.id)}" data-rounding-mode="round" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>≈</button>
        <button class="button compact-button" title="向上取整" data-batch-income-round="${escapeAttribute(state.income.id)}" data-rounding-mode="ceil" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>↑</button>
        <button class="button compact-button" title="向下取整" data-batch-income-round="${escapeAttribute(state.income.id)}" data-rounding-mode="floor" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>↓</button>
      </div>
      <div class="expense-rate-assist-status">${escapeHtml(state.rateStatus || incomeRateAssistHint(state))}</div>
    </div>
  `;
}

function renderBatchCashIncomeRateRow(state) {
  if (!requiresCashIncomeExchangeRate(state)) {
    return "";
  }

  const incomeId = state.income.id;
  return `
    <tr class="expense-batch-cash-rate-row income-batch-cash-rate-row" data-batch-income-row-id="${escapeAttribute(incomeId)}">
      <td colspan="9">
        <div class="expense-rate-toolbar-card${state.errors?.exchangeRate ? " is-invalid" : ""}" data-batch-income-field="exchangeRate">
          <div class="expense-rate-toolbar-title">
            <strong>CNY / JPY 汇率辅助</strong>
            <span>${escapeHtml(`${incomeObjectName(state.income)} / School 原始金额 ${formatCurrency(state.income.amount, state.income.currency)}`)}</span>
          </div>
          <div class="expense-rate-toolbar-controls">
            <span>1 JPY =</span>
            <input data-batch-income-rate="${escapeAttribute(incomeId)}" type="number" min="0" step="0.0000001" inputmode="decimal" value="${escapeAttribute(state.exchangeRate)}" placeholder="0.0358629" ${isBatchCashSubmitting ? "disabled" : ""}>
            <span>CNY</span>
            <button class="button compact-button" data-batch-income-rate-fetch="${escapeAttribute(incomeId)}" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>获取今日汇率</button>
          </div>
          ${state.errors?.exchangeRate ? `<div class="income-batch-cash-field-error">${escapeHtml(state.errors.exchangeRate)}</div>` : ""}
        </div>
      </td>
    </tr>
  `;
}

function renderBatchCashIncomeAccountOptions(state) {
  const rows = cashEligibleAccounts.filter((account) => (
    account?.is_active === true &&
    account?.allow_school_requests === true &&
    account.currency === state.currency
  ));
  return [
    '<option value="">请选择</option>',
    ...rows.map((account) => (
      `<option value="${escapeAttribute(account.id)}" ${account.id === state.accountId ? "selected" : ""}>${escapeHtml(createCashAccountLabel(account))}</option>`
    )),
  ].join("");
}

function handleBatchCashIncomeInput(event) {
  if (!event.target.closest("[data-batch-income-row-id]")) {
    return;
  }

  const amountInput = event.target.closest("[data-batch-income-amount]");
  const currencySelect = event.target.closest("[data-batch-income-currency]");
  const shouldRerender = Boolean(currencySelect);
  const shouldRefreshRateReference = event.type === "change" && Boolean(
    event.target.closest("[data-batch-income-rate]")
    || amountInput
  );
  syncBatchCashIncomeRowsFromDom();
  if (amountInput) {
    const incomeId = amountInput.dataset.batchIncomeAmount;
    const state = batchCashIncomeRows.find((row) => row.income.id === incomeId);
    if (state) {
      state.amountSource = "manual";
      state.roundingMode = "";
    }
  }
  clearBatchCashIncomeFieldError(event.target);
  updateBatchCashIncomeDerivedValues();
  if (shouldRerender) {
    for (const state of batchCashIncomeRows) {
      const account = cashEligibleAccounts.find((row) => row.id === state.accountId);
      if (account?.currency !== state.currency) {
        state.accountId = "";
      }
      if (state.amountSource !== "manual") {
        state.amount = defaultBatchCashIncomeAmountForCurrency(state.income, state.currency);
        state.amountSource = state.amount ? "db" : "";
        state.exchangeRate = defaultBatchCashIncomeExchangeRate(state.income);
        state.roundingMode = "";
      }
    }
    renderBatchCashIncomeRows();
  } else if (shouldRefreshRateReference) {
    renderBatchCashIncomeRows();
  }
  clearBatchCashIncomeError();
}

async function handleBatchCashIncomeClick(event) {
  const fetchButton = event.target.closest("[data-batch-income-rate-fetch]");
  const roundButton = event.target.closest("[data-batch-income-round]");
  if (!fetchButton && !roundButton) {
    return;
  }

  event.preventDefault();
  syncBatchCashIncomeRowsFromDom();
  updateBatchCashIncomeDerivedValues();

  const incomeId = fetchButton?.dataset.batchIncomeRateFetch || roundButton?.dataset.batchIncomeRound;
  const state = batchCashIncomeRows.find((row) => row.income.id === incomeId);
  if (!state || !requiresCashIncomeExchangeRate(state)) {
    return;
  }

  if (fetchButton) {
    await fetchTodayJpyCnyRateForIncomeState(state);
    return;
  }

  applyBatchCashIncomeRounding(state, roundButton.dataset.roundingMode);
}

function syncBatchCashIncomeRowsFromDom() {
  for (const state of batchCashIncomeRows) {
    const id = state.income.id;
    state.amount = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-amount="${cssEscape(id)}"]`)?.value ?? state.amount;
    state.receivedDate = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-date="${cssEscape(id)}"]`)?.value ?? state.receivedDate;
    state.currency = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-currency="${cssEscape(id)}"]`)?.value ?? state.currency;
    state.accountId = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-account="${cssEscape(id)}"]`)?.value ?? state.accountId;
    state.note = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-note="${cssEscape(id)}"]`)?.value ?? state.note;
    state.exchangeRate = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-rate="${cssEscape(id)}"]`)?.value ?? state.exchangeRate;
  }
  updateBatchCashIncomeTotal();
}

async function submitBatchCashIncomeRequests() {
  if (isBatchCashSubmitting) {
    return;
  }

  if (
    !requireActiveAdminForCashConfirmation((_type, message) => {
      showBatchCashIncomeError(message);
    })
  ) {
    return;
  }

  const payloads = readBatchCashIncomePayloads();
  if (!payloads) {
    return;
  }

  let confirmationText;
  try {
    confirmationText = await buildFreshCashSubmissionConfirmation(payloads);
  } catch (error) {
    showBatchCashIncomeError(error?.message || "Cash 提交资格已变化，请刷新后重试。");
    return;
  }

  if (!window.confirm(confirmationText)) {
    return;
  }

  setBatchCashIncomeSubmitting(true);
  let successCount = 0;
  for (const item of payloads) {
    try {
      await requestCashIncomeConfirmationForRecord(item.payload);
      selectedIncomeIds.delete(item.state.income.id);
      successCount += 1;
    } catch (error) {
      console.error(error);
    }
    renderBatchCashIncomeRows();
  }
  setBatchCashIncomeSubmitting(false);
  await refreshCurrentIncomeList();

  const failedCount = payloads.length - successCount;
  if (failedCount > 0) {
    showBatchCashIncomeError(`已提交 ${successCount} 条，失败 ${failedCount} 条。请查看每行结果。`);
  } else {
    closeBatchCashIncomeDialog();
    showMessage("success", `已提交 ${successCount} 条 Cash 收入确认请求，等待 Cash 侧确认。`);
  }
}

async function buildFreshCashSubmissionConfirmation(payloads) {
  const tuitionItems = payloads.filter((item) => item.payload.isTuition === true);
  const freshByIncomeId = new Map();
  if (tuitionItems.length > 0) {
    const freshRows = await fetchCashIncomeSubmissionPreflight(
      tuitionItems.map((item) => item.payload.incomeRecordId)
    );
    for (const row of freshRows) {
      freshByIncomeId.set(row.income_record_id, row);
    }
  }

  const summaries = [];
  for (const item of payloads) {
    const { income } = item.state;
    if (!item.payload.isTuition) {
      summaries.push(
        `${incomeObjectName(income)}｜income ${shortId(income.id)}｜幂等：同一收入仅允许一个active Cash request`
      );
      continue;
    }

    const fresh = freshByIncomeId.get(item.payload.incomeRecordId);
    if (
      !fresh ||
      fresh.eligible !== true ||
      fresh.gate_state !== "enabled" ||
      fresh.classification !== "ELIGIBLE_FOR_CASH_SUBMIT" ||
      fresh.payment_currency !== item.payload.expectedPaymentCurrency ||
      Number(fresh.payment_amount) !== item.payload.expectedPaymentAmount ||
      income.source_id !== item.payload.expectedTuitionBillId ||
      income.source_snapshot?.generation_revision_id !==
        item.payload.expectedGenerationRevisionId
    ) {
      throw new Error("学费账单、收入、金额或active revision已变化，请刷新页面后重新核对。");
    }

    income.cashSubmissionPreflight = fresh;
    summaries.push([
      `学生 ${studentNameById(income.student_id)}`,
      `结算月 ${income.settlement_month}`,
      `bill ${shortId(item.payload.expectedTuitionBillId)}`,
      `income ${shortId(income.id)}`,
      `active revision ${shortId(item.payload.expectedGenerationRevisionId)}`,
      `冻结到账 ${formatCurrency(fresh.payment_amount, fresh.payment_currency)}`,
      `幂等：同一income/active attempt仅创建一个Cash request`,
    ].join("｜"));
  }

  return [
    `最终确认：提交 ${payloads.length} 条 Cash 待确认请求。`,
    ...summaries,
    "警告：提交Cash后不可通过普通页面撤销；Cash确认后才会生成交易。",
    "请再次确认以上学生、月份、bill、income、active revision、币种和金额均正确。",
  ].join("\n");
}

function readBatchCashIncomePayloads() {
  syncBatchCashIncomeRowsFromDom();
  clearBatchCashIncomeError();
  let hasError = false;
  let errorRowCount = 0;
  const payloads = [];

  for (const state of batchCashIncomeRows) {
    const income = state.income;
    state.errors = {};
    if (!canRequestCashIncome(income)) {
      hasError = true;
      errorRowCount += 1;
      continue;
    }

    if (!/^\d{4}-\d{2}-\d{2}$/.test(state.receivedDate || "")) {
      state.errors.date = "请选择实际到账日";
    }

    if (income.source_type === "student_tuition_bill") {
      const cashAccount = cashEligibleAccounts.find((account) => account.id === state.accountId);
      const expectedRevisionId = safeText(
        income.source_snapshot?.generation_revision_id
      ).trim();
      const expectedBillId = safeText(income.source_id).trim();
      const expectedPaymentCurrency = safeText(
        income.cashSubmissionPreflight?.payment_currency
      ).trim();
      const expectedPaymentAmount = Number(
        income.cashSubmissionPreflight?.payment_amount
      );
      if (!cashAccount || cashAccount.currency !== "CNY") {
        state.errors.account = "请选择 CNY Cash 收款账户";
      }
      if (
        !income.student_id ||
        !income.settlement_month ||
        !expectedBillId ||
        !expectedRevisionId ||
        expectedPaymentCurrency !== "CNY" ||
        !Number.isFinite(expectedPaymentAmount) ||
        expectedPaymentAmount <= 0
      ) {
        state.errors.amount = "账单、active revision 或冻结到账事实不完整，请刷新后重试";
      }
      if (Object.keys(state.errors).length > 0) {
        hasError = true;
        errorRowCount += 1;
        continue;
      }
      payloads.push({
        state,
        payload: {
          incomeRecordId: income.id,
          cashAccountId: state.accountId,
          actualReceivedDate: state.receivedDate,
          isTuition: true,
          note: state.note,
          expectedStudentId: income.student_id,
          expectedSettlementMonth: income.settlement_month,
          expectedTuitionBillId: expectedBillId,
          expectedGenerationRevisionId: expectedRevisionId,
          expectedPaymentCurrency,
          expectedPaymentAmount,
        },
      });
      continue;
    }

    const actualReceivedAmount = parseNumberInput(state.amount);
    const useBackendAmount = state.amountSource === "backend"
      || (state.amountSource === "db" && !requiresCashIncomeExchangeRate(state));
    const useManualAmount = !useBackendAmount;
    if (useManualAmount && (!Number.isFinite(actualReceivedAmount) || actualReceivedAmount <= 0)) {
      state.errors.amount = "请输入实际到账金额";
    }

    if (!CASH_INCOME_CURRENCIES.includes(state.currency)) {
      state.errors.currency = "请选择实际到账币种";
    }

    const cashAccount = cashEligibleAccounts.find((account) => account.id === state.accountId);
    if (!cashAccount || cashAccount.currency !== state.currency) {
      state.errors.account = "请选择 Cash 收款账户";
    }

    const exchangeRate = calculatedCashIncomeExchangeRate(income, actualReceivedAmount, state.currency, state.exchangeRate);
    if (requiresCashIncomeExchangeRate(state) && (!Number.isFinite(exchangeRate) || exchangeRate <= 0)) {
      state.errors.exchangeRate = "原始币种与到账币种不一致，请填写参考汇率";
    }
    if (state.amountSource === "backend" && !ROUNDING_MODE_LABELS[state.roundingMode]) {
      state.errors.amount = "请选择有效取整方式，或手动输入实际到账金额";
    }

    if (Object.keys(state.errors).length > 0) {
      hasError = true;
      errorRowCount += 1;
      continue;
    }

    payloads.push({
      state,
      payload: {
        incomeRecordId: income.id,
        cashAccountId: state.accountId,
        actualReceivedAmount: useBackendAmount ? null : actualReceivedAmount,
        actualReceivedCurrency: state.currency,
        actualReceivedDate: state.receivedDate,
        exchangeRate,
        roundingMode: state.amountSource === "backend" ? state.roundingMode : "",
        note: buildCashIncomeRequestNoteFromBase(
          income,
          useBackendAmount ? null : actualReceivedAmount,
          state.currency,
          exchangeRate,
          state.receivedDate,
          state.note,
          incomeRateAssistNote(state)
        ),
      },
    });
  }

  renderBatchCashIncomeRows();
  if (hasError) {
    showBatchCashIncomeError(`请修正 ${errorRowCount} 条记录的标红字段，未提交任何请求。`);
    return null;
  }

  if (!payloads.length) {
    showBatchCashIncomeError("没有可提交的收入记录。");
    return null;
  }

  return payloads;
}

function calculatedCashIncomeExchangeRate(income, actualAmount, actualCurrency, referenceRate = "") {
  if (!requiresCashIncomeExchangeRate({ income, currency: actualCurrency })) {
    return 1;
  }

  const rate = parseNumberInput(referenceRate);
  if (requiresCashIncomeExchangeRate({ income, currency: actualCurrency }) && Number.isFinite(rate) && rate > 0) {
    return roundDecimal(rate, 7);
  }

  if (!Number.isFinite(actualAmount) || actualAmount <= 0) {
    return NaN;
  }

  return NaN;
}

function updateBatchCashIncomeDerivedValues() {
  for (const state of batchCashIncomeRows) {
    updateBatchCashIncomeDerivedValue(state);
  }
}

function updateBatchCashIncomeDerivedValue(state) {
  if (!requiresCashIncomeExchangeRate(state)) {
    state.theoreticalAmount = "";
    state.roundingMode = "";
    state.rateStatus = "";
    return;
  }

  const rate = parseNumberInput(state.exchangeRate);
  const sourceAmount = originalIncomeAmount(state.income);
  if (!Number.isFinite(rate) || rate <= 0 || !Number.isFinite(sourceAmount) || sourceAmount <= 0) {
    state.theoreticalAmount = "";
    return;
  }

  const carryoverCny = studentTuitionBillCarryoverCny(state.income);
  state.theoreticalAmount = state.currency === "CNY"
    ? formatDecimal(sourceAmount * rate + carryoverCny, 2)
    : formatDecimal(sourceAmount / rate, 0);
}

async function fetchTodayJpyCnyRateForIncomeState(state) {
  try {
    const rate = await fetchLatestJpyCnyRate();
    state.exchangeRate = formatRateValue(rate);
    updateBatchCashIncomeDerivedValue(state);
    state.rateStatus = "已获取今日参考汇率，可取整或手动修改金额。";
    delete state.errors?.exchangeRate;
    clearBatchCashIncomeError();
  } catch (error) {
    state.rateStatus = "汇率获取失败，可手动输入参考汇率。";
    showBatchCashIncomeError(`今日汇率获取失败：${error.message || error}。可手动输入金额继续。`);
  } finally {
    renderBatchCashIncomeRows();
  }
}

async function fetchLatestJpyCnyRate() {
  const response = await fetch(JPY_CNY_RATE_API_URL, {
    headers: { accept: "application/json" },
  });
  if (!response.ok) {
    throw new Error(`Frankfurter API HTTP ${response.status}`);
  }

  const data = await response.json();
  const rate = Number(data?.rate ?? data?.rates?.CNY);
  if (!Number.isFinite(rate) || rate <= 0) {
    throw new Error("Frankfurter API 未返回有效 CNY/JPY 汇率");
  }

  return rate;
}

function applyBatchCashIncomeRounding(state, mode) {
  updateBatchCashIncomeDerivedValue(state);
  const theoreticalAmount = parseNumberInput(state.theoreticalAmount);
  if (!Number.isFinite(theoreticalAmount) || theoreticalAmount <= 0) {
    state.rateStatus = "请先获取或输入有效参考汇率。";
    renderBatchCashIncomeRows();
    return;
  }

  const roundedAmount = roundCnyIncomeAmount(theoreticalAmount, mode);
  state.amount = String(roundedAmount);
  state.amountSource = "backend";
  state.roundingMode = ROUNDING_MODE_LABELS[mode] ? mode : "";
  state.rateStatus = `${ROUNDING_MODE_LABELS[mode] || "取整"}已预览实际到账金额，提交时按相同规则确认，仍可手动修改。`;
  renderBatchCashIncomeRows();
}

function roundCnyIncomeAmount(amount, mode) {
  if (mode === "ceil") {
    return Math.ceil(amount);
  }

  if (mode === "floor") {
    return Math.floor(amount);
  }

  return Math.round(amount);
}

function originalIncomeAmount(income) {
  const amount = Number(income?.amount);
  return Number.isFinite(amount) && amount > 0 ? amount : NaN;
}

function defaultBatchCashIncomeCurrency(income) {
  return income?.source_type === "student_tuition_bill" ? "CNY" : (income.currency || "JPY");
}

function defaultBatchCashIncomeAmount(income) {
  return defaultBatchCashIncomeAmountForCurrency(income, defaultBatchCashIncomeCurrency(income));
}

function defaultBatchCashIncomeAmountForCurrency(income, currency) {
  if (income?.source_type === "student_tuition_bill" && currency === "CNY") {
    return studentTuitionBillBillingAmountCny(income) || "";
  }

  return currency === incomeOriginalCurrency(income)
    ? income.amount ?? ""
    : "";
}

function studentTuitionBillCarryoverCny(income) {
  if (income?.source_type !== "student_tuition_bill") {
    return 0;
  }

  const snapshot = income.source_snapshot && typeof income.source_snapshot === "object"
    ? income.source_snapshot
    : {};
  const carryover = Number(snapshot.previous_carryover_cny);
  return Number.isFinite(carryover) ? carryover : 0;
}

function studentTuitionBillBillingAmountCny(income) {
  if (income?.source_type !== "student_tuition_bill") {
    return "";
  }

  const snapshot = income.source_snapshot && typeof income.source_snapshot === "object"
    ? income.source_snapshot
    : {};
  const amount = Number(snapshot.billing_amount_cny);
  return Number.isFinite(amount) && amount > 0 ? formatDecimal(amount, 2) : "";
}

function studentTuitionBillBillingExchangeRate(income) {
  if (income?.source_type !== "student_tuition_bill") {
    return "";
  }

  const snapshot = income.source_snapshot && typeof income.source_snapshot === "object"
    ? income.source_snapshot
    : {};
  return formatRateValue(snapshot.billing_exchange_rate);
}

function defaultBatchCashIncomeExchangeRate(income) {
  return studentTuitionBillBillingExchangeRate(income);
}

function incomeOriginalCurrency(income) {
  return CASH_INCOME_CURRENCIES.includes(income?.currency) ? income.currency : "";
}

function requiresCashIncomeExchangeRate(state) {
  const originalCurrency = incomeOriginalCurrency(state.income);
  return Boolean(originalCurrency && CASH_INCOME_CURRENCIES.includes(state.currency) && originalCurrency !== state.currency);
}

function formatTheoreticalCashIncomeAmount(state) {
  const amount = parseNumberInput(state.theoreticalAmount);
  if (!Number.isFinite(amount) || amount <= 0) {
    return "-";
  }

  return state.currency === "JPY" ? `${formatDecimal(amount, 0)} JPY` : `${formatDecimal(amount, 2)} CNY`;
}

function incomeRateAssistHint(state) {
  if (!requiresCashIncomeExchangeRate(state)) {
    return "同币种到账不需要汇率。";
  }

  if (!Number.isFinite(originalIncomeAmount(state.income))) {
    return "缺少 School 原始金额，可手动输入实际到账金额。";
  }

  return "获取或输入汇率后可计算理论到账金额。";
}

function incomeRateAssistNote(state) {
  if (!requiresCashIncomeExchangeRate(state)) {
    return "";
  }

  const rate = parseNumberInput(state.exchangeRate);
  const theoreticalAmount = parseNumberInput(state.theoreticalAmount);
  const parts = [];
  if (Number.isFinite(rate) && rate > 0) {
    parts.push(`参考汇率 CNY/JPY ${formatRateValue(rate)}`);
  }
  if (state.amountSource === "backend") {
    parts.push("实际到账金额按提交规则计算");
  } else if (Number.isFinite(theoreticalAmount) && theoreticalAmount > 0) {
    parts.push(`理论到账 ${state.currency === "JPY" ? formatDecimal(theoreticalAmount, 0) : formatDecimal(theoreticalAmount, 2)} ${state.currency}`);
  }
  const carryoverCny = studentTuitionBillCarryoverCny(state.income);
  if (carryoverCny) {
    parts.push(`含上月结转 ${formatCurrency(carryoverCny, "CNY")}`);
  }
  if (ROUNDING_MODE_LABELS[state.roundingMode]) {
    parts.push(`取整方式 ${ROUNDING_MODE_LABELS[state.roundingMode]}`);
  }

  return parts.join("，");
}

function clearBatchCashIncomeFieldError(target) {
  const field = target.closest("[data-batch-income-field]");
  const row = target.closest("[data-batch-income-row-id]");
  const incomeId = row?.dataset.batchIncomeRowId;
  const fieldId = field?.dataset.batchIncomeField;
  const state = batchCashIncomeRows.find((item) => item.income.id === incomeId);
  if (!state?.errors || !fieldId) {
    return;
  }

  delete state.errors[fieldId];
  field.classList.remove("is-invalid");
  field.querySelector(".income-batch-cash-field-error")?.remove();
}

function formatRateValue(value) {
  const rate = Number(value);
  return Number.isFinite(rate) ? rate.toFixed(7).replace(/0+$/, "").replace(/\.$/, "") : "";
}

function formatDecimal(value, decimals) {
  const numberValue = Number(value);
  if (!Number.isFinite(numberValue)) {
    return "";
  }

  return numberValue.toFixed(decimals).replace(/0+$/, "").replace(/\.$/, "");
}

function defaultCashIncomeNote(income) {
  if (income.source_type === "student_tuition_bill") {
    const carryoverCny = studentTuitionBillCarryoverCny(income);
    const billingAmountCny = studentTuitionBillBillingAmountCny(income);
    const billingExchangeRate = studentTuitionBillBillingExchangeRate(income);
    return [
      `${income.source_label || "学生学费应收"}，JPY学费${formatCurrency(income.amount_jpy || income.amount, "JPY")}`,
      carryoverCny ? `上月结转${formatCurrency(carryoverCny, "CNY")}` : "",
      billingAmountCny ? `通知金额${formatCurrency(billingAmountCny, "CNY")}` : "",
      billingExchangeRate ? `通知汇率${billingExchangeRate}` : "",
    ].filter(Boolean).join("，");
  }

  if (income.source_type === "part_time_work") {
    return `${income.source_label || "外部塾打工收入"}，JPY工资总额${formatCurrency(income.amount_jpy || income.amount, "JPY")}。`;
  }
  const standardParts = [
    incomeCategoryLabel(income.income_category),
    incomeObjectName(income),
    income.year_month,
  ].map((value) => safeText(value)).filter((value) => value && value !== "-");
  const extraNote = defaultCashIncomeExtraNote(income.note || income.description || income.source_label, standardParts);
  return [
    standardParts.join(" / "),
    extraNote,
  ].filter(Boolean).join(" / ");
}

function defaultCashIncomeExtraNote(value, standardParts) {
  const text = safeText(value).trim();
  if (!text) {
    return "";
  }

  let extra = text;
  for (const part of defaultCashIncomeDuplicateTerms(standardParts)) {
    extra = extra.replace(new RegExp(escapeRegExp(part), "g"), " ");
  }
  extra = extra.replace(/[／/|,，、;；:：()（）\[\]【】]+/g, " ").replace(/\s+/g, " ").trim();
  if (!extra) {
    return "";
  }

  const standardTokens = noteComparisonTokens(standardParts.join(" "));
  const extraTokens = noteComparisonTokens(extra);
  if (extraTokens.length && extraTokens.every((token) => standardTokens.includes(token))) {
    return "";
  }

  return extra;
}

function defaultCashIncomeDuplicateTerms(standardParts) {
  const terms = new Set(standardParts);
  for (const part of standardParts) {
    const monthMatch = part.match(/^(\d{4})-(\d{2})$/);
    if (monthMatch) {
      terms.add(`${monthMatch[1]} ${monthMatch[2]}`);
      terms.add(`${monthMatch[1]}/${monthMatch[2]}`);
      terms.add(`${monthMatch[1]}年${monthMatch[2]}月`);
    }
  }
  return Array.from(terms).sort((a, b) => b.length - a.length);
}

function noteComparisonTokens(value) {
  return safeText(value)
    .toLowerCase()
    .replace(/[／/|,，、;；:：()（）\[\]【】]+/g, " ")
    .replace(/-/g, " ")
    .split(/\s+/)
    .filter(Boolean);
}

function escapeRegExp(value) {
  return safeText(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function buildCashIncomeRequestNoteFromBase(income, amount, currency, exchangeRate, receivedDate, baseNote, extraNote = "") {
  const base = safeText(baseNote).trim();
  const actualAmountText = Number.isFinite(Number(amount))
    ? `实际到账${formatCurrency(amount, currency)}`
    : `实际到账金额按提交规则计算，币种${currency}`;
  const requiredText = [
    `${income.source_label || incomeObjectName(income)}，实际到账日${receivedDate}，School原始金额${formatCurrency(income.amount, income.currency)}，${actualAmountText}${exchangeRate ? `，参考汇率${exchangeRate}` : ""}`,
    extraNote,
  ].filter(Boolean).join("；");
  if (!base) {
    return requiredText;
  }
  if (base.includes("实际到账日")) {
    return extraNote && !base.includes("理论到账") ? `${base}；${extraNote}` : base;
  }
  return `${base}；${requiredText}`;
}

async function openGenerateTuitionBillDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  clearTuitionBillErrors();
  setTuitionBillSubmitting(false);

  const filters = readFilters();
  dom.tuitionBillMonthInput.value = filters?.month || currentYearMonth();
  dom.tuitionBillBillingRateInput.value = "";
  dom.tuitionBillNoteInput.value = "";
  dom.tuitionBillIncludeInactiveCheckbox.checked = Boolean(filters?.includeInactive);
  clearTuitionBillPreview();
  tuitionBillStudentCandidates = [];
  renderStudentMonthCandidateOptions(dom.tuitionBillStudentSelect, [], {
    placeholder: "正在按学费月份加载...",
  });

  dom.generateTuitionBillDialog.classList.remove("is-hidden");
  dom.generateTuitionBillDialog.setAttribute("aria-hidden", "false");
  await refreshTuitionBillStudentCandidates(filters?.studentId || "");
}

function closeGenerateTuitionBillDialog() {
  if (tuitionBillGenerationState.isSubmitting()) {
    return;
  }

  closeGenerateTuitionBillConfirmation();
  tuitionStudentCandidateRequestId += 1;
  dom.generateTuitionBillDialog.classList.add("is-hidden");
  dom.generateTuitionBillDialog.setAttribute("aria-hidden", "true");
  clearTuitionBillPreview();
}

async function handlePreviewTuitionBill() {
  if (tuitionBillGenerationState.isSubmitting() || isTuitionBillPreviewLoading) {
    return;
  }

  clearTuitionBillErrors();
  const payload = readGenerateTuitionBillPayload();
  if (!payload) {
    return;
  }

  const requestSignature = buildTuitionBillPreviewSignature(payload);
  const requestToken = tuitionBillPreviewRequestGate.begin(requestSignature);
  setTuitionBillPreviewLoading(true);
  try {
    const response = await fetchStudentTuitionValidationPreviewDetails({
      studentId: payload.studentId,
      billingMonth: payload.billingMonth,
      billingExchangeRate: payload.billingExchangeRate,
    });
    if (!tuitionBillPreviewRequestGate.isCurrent(
      requestToken,
      currentTuitionBillPreviewSignature()
    )) {
      return;
    }
    const preview = validateTuitionValidationPreviewDetails(response, {
      studentId: payload.studentId,
      businessEntityId: payload.businessEntityId,
      billingMonth: payload.billingMonth,
      billingExchangeRate: payload.billingExchangeRate,
    });
    tuitionBillGenerationState.storePreview(preview);
    tuitionBillPreviewSignature = requestSignature;
    renderTuitionBillPreview(preview);
  } catch (error) {
    if (tuitionBillPreviewRequestGate.isCurrent(
      requestToken,
      currentTuitionBillPreviewSignature()
    )) {
      console.error(error);
      clearTuitionBillPreview({ invalidateRequest: false });
      const mapped = mapTuitionValidationPreviewError(error);
      showTuitionBillError(mapped.message, tuitionBillFieldIdsForError(error.message || ""));
    }
  } finally {
    if (tuitionBillPreviewRequestGate.isCurrent(
      requestToken,
      currentTuitionBillPreviewSignature()
    )) {
      setTuitionBillPreviewLoading(false);
    }
  }
}

async function submitGenerateTuitionBill() {
  const preview = tuitionBillGenerationState.getPreview();
  if (!preview || tuitionBillPreviewSignature !== currentTuitionBillPreviewSignature()) {
    clearTuitionBillPreview();
    showTuitionBillError("当前预览已失效，请重新生成预览。");
    return;
  }
  if (!isAtomicTuitionGenerateEnabled(preview)) {
    showTuitionBillError("学费应收生成功能维护中，当前只能预览。");
    return;
  }
  openGenerateTuitionBillConfirmation(preview);
}

function readGenerateTuitionBillPayload() {
  const billingMonth = dom.tuitionBillMonthInput.value;
  if (!billingMonth || !/^[0-9]{4}-(0[1-9]|1[0-2])$/.test(billingMonth)) {
    showTuitionBillError("学费月份格式无效。", ["billingMonth"]);
    return null;
  }

  const studentId = dom.tuitionBillStudentSelect.value;
  if (!studentId) {
    showTuitionBillError("请选择学生。", ["student"]);
    return null;
  }
  const businessEntityId = requirePrimarySchoolBusinessEntityId(businessEntities);

  const billingExchangeRate = parseNumberInput(dom.tuitionBillBillingRateInput.value);
  if (!Number.isFinite(billingExchangeRate) || billingExchangeRate <= 0) {
    showTuitionBillError("通知汇率必须大于 0。", ["billingRate"]);
    return null;
  }

  return {
    billingMonth,
    studentId,
    businessEntityId,
    billingExchangeRate,
    note: dom.tuitionBillNoteInput.value.trim(),
  };
}

async function refreshTuitionBillStudentCandidates(selectedOverride = "") {
  const month = dom.tuitionBillMonthInput.value;
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) return;
  const selectedStudentId = selectedOverride || dom.tuitionBillStudentSelect.value || "";
  const requestId = ++tuitionStudentCandidateRequestId;
  dom.tuitionBillStudentSelect.disabled = true;
  try {
    tuitionBillStudentCandidates = await fetchStudentMonthCandidates({
      month,
      includeInactive: dom.tuitionBillIncludeInactiveCheckbox.checked,
      selectedStudentId: selectedStudentId || null,
    });
    if (requestId !== tuitionStudentCandidateRequestId) return;
    renderStudentMonthCandidateOptions(dom.tuitionBillStudentSelect, tuitionBillStudentCandidates, {
      placeholder: "请选择学生",
      selectedStudentId,
    });
  } catch (error) {
    if (requestId !== tuitionStudentCandidateRequestId) return;
    tuitionBillStudentCandidates = [];
    renderStudentMonthCandidateOptions(dom.tuitionBillStudentSelect, [], { placeholder: "学生候选加载失败" });
    showTuitionBillError(`读取学费月份学生候选失败：${error.message || error}`, ["student"]);
  } finally {
    if (requestId === tuitionStudentCandidateRequestId) dom.tuitionBillStudentSelect.disabled = false;
  }
}

function setTuitionBillSubmitting(isSubmitting) {
  dom.generateTuitionBillPreviewButton.disabled = isSubmitting || isTuitionBillPreviewLoading;
  const preview = tuitionBillGenerationState.getPreview();
  dom.generateTuitionBillSubmitButton.disabled = isSubmitting || !isAtomicTuitionGenerateEnabled(preview);
  dom.generateTuitionBillCancelButton.disabled = isSubmitting;
  dom.generateTuitionBillSubmitButton.textContent = isAtomicTuitionGenerateEnabled(preview)
    ? "生成学费应收"
    : "请先生成预览";
  dom.confirmGenerateTuitionBillCancelButton.disabled = isSubmitting;
  dom.confirmGenerateTuitionBillSubmitButton.disabled = isSubmitting;
  dom.confirmGenerateTuitionBillSubmitButton.textContent = isSubmitting
    ? "生成中..."
    : "确认生成学费应收";
}

function setTuitionBillPreviewLoading(isLoading) {
  isTuitionBillPreviewLoading = isLoading;
  dom.generateTuitionBillPreviewButton.disabled = isLoading || tuitionBillGenerationState.isSubmitting();
  const preview = tuitionBillGenerationState.getPreview();
  dom.generateTuitionBillSubmitButton.disabled = isLoading || !isAtomicTuitionGenerateEnabled(preview);
  dom.generateTuitionBillPreviewButton.textContent = isLoading ? "预览中..." : "生成预览";
}

function clearTuitionBillErrors() {
  dom.generateTuitionBillError.textContent = "";
  dom.generateTuitionBillError.classList.add("is-hidden");
  for (const fieldId of ["billingMonth", "student", "billingRate"]) {
    clearTuitionBillFieldInvalid(fieldId);
  }
}

function showTuitionBillError(message, fieldIds = []) {
  dom.generateTuitionBillError.textContent = message;
  dom.generateTuitionBillError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setTuitionBillFieldInvalid(fieldId, true);
  }
}

function renderTuitionBillPreview(preview) {
  const student = students.find((row) => row.id === preview.student_id);
  const existingText = preview.existing_tuition_bill_id
    ? `${preview.existing_tuition_bill_status || "-"} / ${preview.existing_income_status || "-"}`
    : "无";
  dom.generateTuitionBillPreview.innerHTML = `
    <div><dt>预览状态</dt><dd>${escapeHtml(preview.feature_state)}</dd></div>
    <div><dt>原子生成状态</dt><dd>${escapeHtml(preview.generate_feature_state)}</dd></div>
    <div><dt>Revision</dt><dd>${escapeHtml(preview.message || "-")}</dd></div>
    <div><dt>学生</dt><dd>${escapeHtml(student ? studentName(student) : "-")}</dd></div>
    <div><dt>学费月份</dt><dd>${escapeHtml(formatMonth(preview.billing_month))}</dd></div>
    <div><dt>candidate / 课次数</dt><dd>${escapeHtml(`${preview.candidate_count} 条 / ${preview.total_lesson_count} 次`)}</dd></div>
    <div><dt>总时长</dt><dd>${escapeHtml(`${formatDecimal(preview.total_duration_hours, 2)} h`)}</dd></div>
    <div><dt>基础课时费（服务端）</dt><dd>${escapeHtml(formatCurrency(preview.total_base_lesson_fee_jpy, "JPY"))}</dd></div>
    <div><dt>空调费（服务端）</dt><dd>${escapeHtml(formatCurrency(preview.total_aircon_fee_jpy, "JPY"))}</dd></div>
    <div><dt>课程总价（服务端）</dt><dd>${escapeHtml(formatCurrency(preview.total_fee_jpy, "JPY"))}</dd></div>
    <div><dt>上月结转</dt><dd>${escapeHtml(formatCurrency(preview.previous_carryover_cny, "CNY"))}</dd></div>
    <div><dt>通知汇率</dt><dd>${escapeHtml(formatRateValue(preview.billing_exchange_rate))}</dd></div>
    <div><dt>通知金额（服务端）</dt><dd>${escapeHtml(formatCurrency(preview.billing_amount_cny, "CNY"))}</dd></div>
    <div><dt>既有应收</dt><dd>${escapeHtml(existingText)}</dd></div>
  `;
  dom.generateTuitionBillPreview.classList.remove("is-hidden");
  dom.tuitionBillCandidateCount.textContent = `${preview.candidate_count} 条`;
  dom.tuitionBillCandidateRows.innerHTML = preview.candidates.map((candidate) => `
    <tr>
      <td class="income-nowrap">${escapeHtml(formatMonth(candidate.billing_month))}</td>
      <td class="income-nowrap">${escapeHtml(formatAuthoritativeBillingWeek(candidate.billing_week_start_date))}</td>
      <td class="income-nowrap">${escapeHtml(formatDateOnly(candidate.lesson_date))}</td>
      <td>${escapeHtml(subjectNameById(candidate.subject_id))}</td>
      <td>${escapeHtml(teacherNameById(candidate.teacher_id))}</td>
      <td class="number-cell">${escapeHtml(String(candidate.lesson_count))}</td>
      <td class="number-cell">${escapeHtml(formatDecimal(candidate.duration_hours, 2))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(candidate.base_lesson_fee_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(candidate.aircon_fee_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(candidate.course_total_jpy, "JPY"))}</td>
    </tr>
  `).join("");
  dom.tuitionBillCandidateDetails.classList.remove("is-hidden");
  setTuitionBillSubmitting(false);
}

function clearTuitionBillPreview({ invalidateRequest = true } = {}) {
  if (invalidateRequest) {
    tuitionBillPreviewRequestGate.invalidate();
    if (isTuitionBillPreviewLoading) {
      setTuitionBillPreviewLoading(false);
    }
  }
  tuitionBillGenerationState.clearPreview();
  tuitionBillPreviewSignature = "";
  closeGenerateTuitionBillConfirmation();
  if (dom.generateTuitionBillPreview) {
    dom.generateTuitionBillPreview.textContent = "";
    dom.generateTuitionBillPreview.classList.add("is-hidden");
  }
  if (dom.tuitionBillCandidateDetails) {
    dom.tuitionBillCandidateDetails.classList.add("is-hidden");
    dom.tuitionBillCandidateDetails.open = false;
  }
  if (dom.tuitionBillCandidateCount) {
    dom.tuitionBillCandidateCount.textContent = "0 条";
  }
  if (dom.tuitionBillCandidateRows) {
    dom.tuitionBillCandidateRows.innerHTML = "";
  }
  if (dom.generateTuitionBillSubmitButton) {
    dom.generateTuitionBillSubmitButton.disabled = true;
    dom.generateTuitionBillSubmitButton.textContent = "请先生成预览";
  }
}

function openGenerateTuitionBillConfirmation(preview) {
  const student = students.find((row) => row.id === preview.student_id);
  const note = dom.tuitionBillNoteInput.value.trim() || "无";
  dom.confirmGenerateTuitionBillError.textContent = "";
  dom.confirmGenerateTuitionBillError.classList.add("is-hidden");
  dom.confirmGenerateTuitionBillSummary.innerHTML = `
    <div><dt>学生</dt><dd>${escapeHtml(student ? studentName(student) : "-")}</dd></div>
    <div><dt>学费月份</dt><dd>${escapeHtml(formatMonth(preview.billing_month))}</dd></div>
    <div><dt>candidate课程</dt><dd>${escapeHtml(`${preview.candidate_count} 条`)}</dd></div>
    <div><dt>总课次数</dt><dd>${escapeHtml(`${preview.total_lesson_count} 次`)}</dd></div>
    <div><dt>总时长</dt><dd>${escapeHtml(`${formatDecimal(preview.total_duration_hours, 2)} h`)}</dd></div>
    <div><dt>基础课时费</dt><dd>${escapeHtml(formatCurrency(preview.total_base_lesson_fee_jpy, "JPY"))}</dd></div>
    <div><dt>空调费</dt><dd>${escapeHtml(formatCurrency(preview.total_aircon_fee_jpy, "JPY"))}</dd></div>
    <div><dt>课程总额</dt><dd>${escapeHtml(formatCurrency(preview.total_fee_jpy, "JPY"))}</dd></div>
    <div><dt>上月结转</dt><dd>${escapeHtml(formatCurrency(preview.previous_carryover_cny, "CNY"))}</dd></div>
    <div><dt>通知汇率</dt><dd>${escapeHtml(formatRateValue(preview.billing_exchange_rate))}</dd></div>
    <div><dt>最终通知金额</dt><dd>${escapeHtml(formatCurrency(preview.billing_amount_cny, "CNY"))}</dd></div>
    <div><dt>备注</dt><dd>${escapeHtml(note)}</dd></div>
    <div><dt>生成结果</dt><dd>正式学费应收及待收款记录（Cash仍不提交）</dd></div>
  `;
  dom.confirmGenerateTuitionBillDialog.classList.remove("is-hidden");
  dom.confirmGenerateTuitionBillDialog.setAttribute("aria-hidden", "false");
}

function closeGenerateTuitionBillConfirmation() {
  if (!dom.confirmGenerateTuitionBillDialog || tuitionBillGenerationState.isSubmitting()) {
    return;
  }
  dom.confirmGenerateTuitionBillDialog.classList.add("is-hidden");
  dom.confirmGenerateTuitionBillDialog.setAttribute("aria-hidden", "true");
  dom.confirmGenerateTuitionBillSummary.textContent = "";
  dom.confirmGenerateTuitionBillError.textContent = "";
  dom.confirmGenerateTuitionBillError.classList.add("is-hidden");
}

async function confirmGenerateTuitionBill() {
  const preview = tuitionBillGenerationState.getPreview();
  if (!preview || tuitionBillPreviewSignature !== currentTuitionBillPreviewSignature()) {
    clearTuitionBillPreview();
    showTuitionBillError("当前预览已失效，请重新生成预览。");
    return;
  }
  if (!isAtomicTuitionGenerateEnabled(preview)) {
    showTuitionBillError("学费应收生成功能维护中，当前只能预览。");
    return;
  }
  if (!tuitionBillGenerationState.beginSubmission()) {
    return;
  }

  setTuitionBillSubmitting(true);
  try {
    const payload = buildAtomicTuitionGeneratePayload(preview, dom.tuitionBillNoteInput.value);
    const result = await generateStudentTuitionBillAtomic(payload);
    if (result.student_id !== preview.student_id
        || result.billing_month !== preview.billing_month
        || result.generation_manifest_sha256 !== preview.generation_manifest_sha256) {
      throw new Error("R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE: 返回结果与当前预览不一致");
    }

    const currentFilters = readFilters();
    tuitionBillGenerationState.endSubmission({ consumePreview: true });
    setTuitionBillSubmitting(false);
    closeGenerateTuitionBillConfirmation();
    dom.generateTuitionBillDialog.classList.add("is-hidden");
    dom.generateTuitionBillDialog.setAttribute("aria-hidden", "true");
    clearTuitionBillPreview();

    if (currentFilters) {
      await loadIncomeMonth(currentFilters.month);
      restoreFilterSelections(currentFilters);
      renderIncomeRecords(filterIncomeRecords(incomeRecords, currentFilters));
    }
    const resultKind = result.idempotent ? "已返回既有幂等结果" : "已原子生成";
    showMessage(
      "success",
      `${resultKind}：账单 ${shortId(result.tuition_bill_id)}，identity ${shortId(result.billing_identity_id)}，pending收入 ${shortId(result.income_record_id)}。`
    );
  } catch (error) {
    console.error(error);
    const mapped = mapAtomicTuitionGenerateError(error);
    tuitionBillGenerationState.endSubmission();
    setTuitionBillSubmitting(false);
    dom.confirmGenerateTuitionBillError.textContent = mapped.message;
    dom.confirmGenerateTuitionBillError.classList.remove("is-hidden");
    showTuitionBillError(mapped.message);
    if (mapped.clearPreview) {
      clearTuitionBillPreview();
    }
  }
}

function buildTuitionBillPreviewSignature(payload) {
  return [
    payload.studentId || "",
    payload.billingMonth || "",
    String(payload.billingExchangeRate ?? ""),
  ].join("|");
}

function currentTuitionBillPreviewSignature() {
  return [
    dom.tuitionBillStudentSelect.value || "",
    dom.tuitionBillMonthInput.value || "",
    String(parseNumberInput(dom.tuitionBillBillingRateInput.value) ?? ""),
  ].join("|");
}

function tuitionBillFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("日期")) fields.push("incomeDate");
  if (text.includes("月份") || text.includes("月度结算") || text.includes("学费")) fields.push("billingMonth");
  if (text.includes("学生")) fields.push("student");
  if (text.includes("汇率") || text.includes("通知")) fields.push("billingRate");
  return fields;
}

function setTuitionBillFieldInvalid(fieldId, invalid) {
  const field = dom.generateTuitionBillDialog.querySelector(`[data-tuition-bill-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearTuitionBillFieldInvalid(fieldId) {
  setTuitionBillFieldInvalid(fieldId, false);
}

async function openCreateIncomeDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  clearCreateErrors();
  setCreateSubmitting(false);

  const filters = readFilters();
  const defaultStudentId = filters?.studentId || "";
  const defaultAccountId = filters?.accountId || "";

  dom.createIncomeModeSelect.value = CREATE_MODE_SCHOOL_ACCOUNT;
  dom.createIncomeDateInput.value = currentDate();
  dom.createSettlementMonthInput.value = filters?.month || currentYearMonth();
  dom.createIncomeAmountInput.value = "";
  dom.createIncomePaymentMethodSelect.value = "";
  dom.createIncomeCurrencySelect.value = "JPY";
  dom.createIncomeCashMappingSelect.value = "";
  dom.createIncomeCategorySelect.value = "tuition";
  dom.createIncomeDescriptionInput.value = "";
  dom.createIncomeExchangeRateInput.value = "";
  dom.createIncomeTaxableSelect.value = "false";
  dom.createIncomeTaxCategoryInput.value = "売上";
  dom.createIncomeReceiptStatusInput.value = "待确认";
  dom.createIncomeNoteInput.value = "";
  dom.createIncomeIncludeInactiveCheckbox.checked = Boolean(filters?.includeInactive);

  createStudentCandidates = [];
  renderStudentMonthCandidateOptions(dom.createIncomeStudentSelect, [], {
    placeholder: "正在按结算月份加载...",
  });

  renderCreateAccountOptions();
  dom.createIncomeAccountSelect.value = filteredCreateAccounts().some((account) => account.id === defaultAccountId)
    ? defaultAccountId
    : "";
  renderCreateCashAccountOptions();
  updateCreateModeUi();

  dom.createIncomeDialog.classList.remove("is-hidden");
  dom.createIncomeDialog.setAttribute("aria-hidden", "false");
  await refreshCreateStudentCandidates(defaultStudentId);
}

function closeCreateIncomeDialog() {
  if (isCreateSubmitting) {
    return;
  }

  createStudentCandidateRequestId += 1;
  dom.createIncomeDialog.classList.add("is-hidden");
  dom.createIncomeDialog.setAttribute("aria-hidden", "true");
}

async function submitCreateIncome() {
  if (isCreateSubmitting) {
    return;
  }

  clearCreateErrors();

  const payload = readCreateIncomePayload();
  if (!payload) {
    return;
  }

  setCreateSubmitting(true);

  try {
    const result = isCashIncomeCreateModeValue(payload.createMode)
      ? await createPendingCashIncomeRecord(payload)
      : await createIncomeRecord(payload);
    setCreateSubmitting(false);
    closeCreateIncomeDialog();
    await refreshCurrentIncomeList();
    showIncomeCreateSuccess(result, payload.createMode);
  } catch (error) {
    console.error(error);
    showCreateError(`新增收入失败：${error.message || error}`, createFieldIdsForError(error.message || ""));
  } finally {
    setCreateSubmitting(false);
  }
}

function readCreateIncomePayload() {
  const incomeDate = dom.createIncomeDateInput.value;
  if (!incomeDate) {
    showCreateError("请选择实际收款日期。", ["incomeDate"]);
    return null;
  }

  const settlementMonth = dom.createSettlementMonthInput.value;
  if (!settlementMonth || !/^[0-9]{4}-(0[1-9]|1[0-2])$/.test(settlementMonth)) {
    showCreateError("结算月份格式无效。", ["settlementMonth"]);
    return null;
  }

  const businessEntityId = requirePrimarySchoolBusinessEntityId(businessEntities);

  const createMode = dom.createIncomeModeSelect.value || CREATE_MODE_SCHOOL_ACCOUNT;

  const studentId = dom.createIncomeStudentSelect.value;
  if (!studentId) {
    showCreateError("请选择学生。", ["student"]);
    return null;
  }

  const amount = Number(dom.createIncomeAmountInput.value);
  if (!Number.isFinite(amount) || amount <= 0) {
    showCreateError("收入金额必须大于 0。", ["amount"]);
    return null;
  }

  const incomeCategory = dom.createIncomeCategorySelect.value;
  if (!EDITABLE_INCOME_CATEGORIES.includes(incomeCategory)) {
    showCreateError("请选择收入分类。", ["incomeCategory"]);
    return null;
  }

  const exchangeRateText = dom.createIncomeExchangeRateInput.value.trim();
  const exchangeRate = exchangeRateText ? Number(exchangeRateText) : null;
  if (exchangeRateText && (!Number.isFinite(exchangeRate) || exchangeRate <= 0)) {
    showCreateError("汇率必须大于 0。", ["exchangeRate"]);
    return null;
  }

  if (isCashIncomeCreateModeValue(createMode)) {
    const currency = dom.createIncomeCurrencySelect.value;
    if (!CASH_INCOME_CURRENCIES.includes(currency)) {
      showCreateError("请选择 Cash System 收入币种。", ["cashCurrency"]);
      return null;
    }

    return {
      createMode,
      incomeDate,
      settlementMonth,
      businessEntityId,
      studentId,
      amount,
      incomeCategory,
      currency,
      paymentCurrency: currency,
      exchangeRate: null,
      paymentMethod: "",
      description: dom.createIncomeDescriptionInput.value.trim(),
      isTaxableIncome: dom.createIncomeTaxableSelect.value === "true",
      taxCategory: dom.createIncomeTaxCategoryInput.value.trim(),
      receiptStatus: "Cash待提交",
      note: dom.createIncomeNoteInput.value.trim(),
    };
  }

  const accountId = dom.createIncomeAccountSelect.value;
  if (!accountId) {
    showCreateError("请选择入账账户。", ["account"]);
    return null;
  }

  const account = accounts.find((item) => item.id === accountId);
  if (!account || account.is_active !== true || account.app_type !== "school") {
    showCreateError("入账账户无效或已停用。", ["account"]);
    return null;
  }

  if (account.business_entity_id !== businessEntityId) {
    showCreateError("入账账户与内部范围不一致。", ["account"]);
    return null;
  }

  if (!account.currency) {
    showCreateError("入账账户缺少币种。", ["account"]);
    return null;
  }

  const paymentMethod = dom.createIncomePaymentMethodSelect.value;
  if (!paymentMethod) {
    showCreateError("请选择收款方式。", ["paymentMethod"]);
    return null;
  }

  return {
    createMode,
    incomeDate,
    settlementMonth,
    businessEntityId,
    studentId,
    accountId,
    amount,
    incomeCategory,
    currency: account.currency,
    paymentCurrency: account.currency,
    exchangeRate,
    paymentMethod,
    description: dom.createIncomeDescriptionInput.value.trim(),
    isTaxableIncome: dom.createIncomeTaxableSelect.value === "true",
    taxCategory: dom.createIncomeTaxCategoryInput.value.trim(),
    receiptStatus: dom.createIncomeReceiptStatusInput.value.trim(),
    note: dom.createIncomeNoteInput.value.trim(),
  };
}

async function refreshCurrentIncomeList() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  await loadIncomeMonth(filters.month);
  restoreFilterSelections(filters);
  applyCurrentFilters();
}

function showIncomeCreateSuccess(result, createMode) {
  const incomeId = result?.income_id;
  dom.messageArea.className = "message message-success";
  const message = isCashIncomeCreateModeValue(createMode)
    ? "Cash 收入记录已保存，尚未提交 Cash。"
    : "收入已新增并自动入账。";
  if (incomeId) {
    dom.messageArea.innerHTML = `${escapeHtml(message)}<a href="./income-detail.html?id=${encodeURIComponent(incomeId)}">查看详情</a>`;
  } else {
    dom.messageArea.textContent = message;
  }
}

async function refreshCreateStudentCandidates(selectedOverride = "") {
  const month = dom.createSettlementMonthInput.value;
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) return;
  const selectedStudentId = selectedOverride || dom.createIncomeStudentSelect.value || "";
  const requestId = ++createStudentCandidateRequestId;
  dom.createIncomeStudentSelect.disabled = true;
  try {
    createStudentCandidates = await fetchStudentMonthCandidates({
      month,
      includeInactive: dom.createIncomeIncludeInactiveCheckbox.checked,
      selectedStudentId: selectedStudentId || null,
    });
    if (requestId !== createStudentCandidateRequestId) return;
    renderStudentMonthCandidateOptions(dom.createIncomeStudentSelect, createStudentCandidates, {
      placeholder: "请选择学生",
      selectedStudentId,
    });
  } catch (error) {
    if (requestId !== createStudentCandidateRequestId) return;
    createStudentCandidates = [];
    renderStudentMonthCandidateOptions(dom.createIncomeStudentSelect, [], { placeholder: "学生候选加载失败" });
    showCreateError(`读取结算月份学生候选失败：${error.message || error}`, ["student"]);
  } finally {
    if (requestId === createStudentCandidateRequestId) dom.createIncomeStudentSelect.disabled = false;
  }
}

function renderCreateAccountOptions() {
  const selectedValue = dom.createIncomeAccountSelect.value;
  const options = ['<option value="">请选择入账账户</option>'];
  for (const account of filteredCreateAccounts()) {
    options.push(`<option value="${escapeAttribute(account.id)}">${escapeHtml(createAccountLabel(account))}</option>`);
  }
  dom.createIncomeAccountSelect.innerHTML = options.join("");
  if (filteredCreateAccounts().some((account) => account.id === selectedValue)) {
    dom.createIncomeAccountSelect.value = selectedValue;
  }
}

function renderCreateCashAccountOptions() {
  const selectedValue = dom.createIncomeCashMappingSelect.value;
  const options = ['<option value="">请选择 Cash System 账户</option>'];
  for (const account of filteredCreateCashAccounts()) {
    options.push(`<option value="${escapeAttribute(account.id)}">${escapeHtml(createCashAccountLabel(account))}</option>`);
  }
  dom.createIncomeCashMappingSelect.innerHTML = options.join("");
  if (filteredCreateCashAccounts().some((account) => account.id === selectedValue)) {
    dom.createIncomeCashMappingSelect.value = selectedValue;
  }
}

async function ensureCashEligibleAccountsLoaded() {
  if (hasLoadedCashEligibleAccounts) {
    return;
  }

  const rows = await fetchSchoolEligibleCashAccountsViaFunction();
  cashEligibleAccounts = (rows || []).filter((account) => (
    account?.is_active === true &&
    account?.allow_school_requests === true &&
    CASH_INCOME_CURRENCIES.includes(account.currency)
  ));
  hasLoadedCashEligibleAccounts = true;
}

function filteredCreateAccounts() {
  const businessEntityId = requirePrimarySchoolBusinessEntityId(businessEntities);
  return accounts.filter((account) => {
    if (account.is_active !== true || account.app_type !== "school") {
      return false;
    }

    if (businessEntityId && account.business_entity_id !== businessEntityId) {
      return false;
    }

    return true;
  });
}

function filteredCreateCashAccounts() {
  const currency = dom.createIncomeCurrencySelect.value;
  return cashEligibleAccounts.filter((account) => {
    if (account.is_active !== true || account.allow_school_requests !== true) {
      return false;
    }

    if (currency && account.currency !== currency) {
      return false;
    }

    return CASH_INCOME_CURRENCIES.includes(account.currency);
  });
}

function createCashAccountLabel(account) {
  return [
    account.name || account.id,
    account.currency || "-",
    account.account_type,
  ].filter(Boolean).join(" / ");
}

function updateCreateModeUi() {
  const cashMode = isCashIncomeCreateMode();
  setCreateFieldHidden("account", cashMode);
  setCreateFieldHidden("cashCurrency", !cashMode);
  setCreateFieldHidden("cashMapping", true);
  setCreateFieldHidden("paymentMethod", cashMode);
  setCreateFieldHidden("exchangeRate", cashMode);

  dom.createIncomeAccountSelect.disabled = cashMode;
  dom.createIncomeCurrencySelect.disabled = !cashMode;
  dom.createIncomeCashMappingSelect.disabled = true;
  dom.createIncomePaymentMethodSelect.disabled = cashMode;
  dom.createIncomeExchangeRateInput.disabled = cashMode;
  dom.createIncomeCategorySelect.disabled = false;

  if (cashMode) {
    dom.createIncomeAccountSelect.value = "";
    dom.createIncomePaymentMethodSelect.value = "";
    dom.createIncomeExchangeRateInput.value = "";
  } else {
    dom.createIncomeCashMappingSelect.value = "";
  }

  renderStudentMonthCandidateOptions(dom.createIncomeStudentSelect, createStudentCandidates, {
    placeholder: "请选择学生",
    selectedStudentId: dom.createIncomeStudentSelect.value,
  });
  renderCreateAccountOptions();
  renderCreateCashAccountOptions();
}

function isCashIncomeCreateMode() {
  return isCashIncomeCreateModeValue(dom.createIncomeModeSelect.value);
}

function isCashIncomeCreateModeValue(value) {
  return value === CREATE_MODE_CASH_SYSTEM_INCOME;
}

function setCreateFieldHidden(fieldId, hidden) {
  const field = dom.createIncomeDialog.querySelector(`[data-create-income-field="${fieldId}"]`);
  field?.classList.toggle("is-hidden", hidden);
}

function createAccountLabel(account) {
  return [
    account.name || account.account_code || account.id,
    account.currency || "-",
    formatCurrency(account.current_balance, account.currency),
  ].filter(Boolean).join(" / ");
}

function setCreateSubmitting(isSubmitting) {
  isCreateSubmitting = isSubmitting;
  dom.createIncomeSubmitButton.disabled = isSubmitting;
  dom.createIncomeCancelButton.disabled = isSubmitting;
  dom.createIncomeSubmitButton.textContent = isSubmitting ? "保存中..." : "保存收入";
}

function clearCreateErrors() {
  dom.createIncomeError.textContent = "";
  dom.createIncomeError.classList.add("is-hidden");
  for (const fieldId of ["createMode", "incomeDate", "settlementMonth", "student", "account", "cashCurrency", "cashMapping", "incomeCategory", "amount", "paymentMethod", "exchangeRate"]) {
    clearCreateFieldInvalid(fieldId);
  }
}

function showCreateError(message, fieldIds = []) {
  dom.createIncomeError.textContent = message;
  dom.createIncomeError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCreateFieldInvalid(fieldId, true);
  }
  dom.createIncomeDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function createFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("金额")) fields.push("amount");
  if (text.includes("收款日期")) fields.push("incomeDate");
  if (text.includes("结算月份") || text.includes("已锁定")) fields.push("settlementMonth");
  if (text.includes("学生")) fields.push("student");
  if (text.includes("Cash")) fields.push("cashMapping");
  if (text.includes("币种") && isCashIncomeCreateMode()) fields.push("cashCurrency");
  if (text.includes("账户") || text.includes("币种")) fields.push(isCashIncomeCreateMode() ? "cashMapping" : "account");
  if (text.includes("分类")) fields.push("incomeCategory");
  if (text.includes("汇率")) fields.push("exchangeRate");
  return fields;
}

function setCreateFieldInvalid(fieldId, invalid) {
  const field = dom.createIncomeDialog.querySelector(`[data-create-income-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function clearCreateFieldInvalid(fieldId) {
  setCreateFieldInvalid(fieldId, false);
}

function hideCreateErrorIfClean() {
  const hasInvalidField = Boolean(dom.createIncomeDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.createIncomeError.textContent = "";
    dom.createIncomeError.classList.add("is-hidden");
  }
}

function filterIncomeRecords(rows, filters) {
  return rows.filter((row) => {
    if (filters.studentId && row.student_id !== filters.studentId) {
      return false;
    }


    if (filters.accountId && row.account_id !== filters.accountId) {
      return false;
    }

    if (filters.incomeCategory && row.income_category !== filters.incomeCategory) {
      return false;
    }

    if (filters.currency && row.currency !== filters.currency) {
      return false;
    }

    return true;
  });
}

function canRequestCashIncome(row) {
  if (!isActiveAdmin()) {
    return false;
  }
  if (!row || row.status !== "pending" || row.status === "cancelled") {
    return false;
  }

  if (row.source_type === "student_tuition_bill") {
    return row.cashSubmissionPreflight?.eligible === true;
  }

  const event = row.cashIncomeLinkageEvent;
  if (!event) {
    return true;
  }

  return event.sync_status === "cash_rejected" || event.cash_request_status === "rejected";
}

function canGenerateTuitionReceipt(row) {
  if (!row || row.status !== "received" || !row.student_id) {
    return false;
  }
  if (row.income_category !== "tuition" && row.source_type !== "student_tuition_bill") {
    return false;
  }

  const event = row.cashIncomeLinkageEvent;
  if (!event || event.sync_status !== "synced") {
    return false;
  }

  return event.payment_amount !== null &&
    event.payment_amount !== undefined &&
    Number(event.payment_amount) > 0 &&
    Boolean(event.payment_currency);
}

function cashIncomeRequestNotAllowedMessage(row) {
  if (!row) return "收入记录不存在，请刷新后重试。";
  if (!isActiveAdmin()) return "仅已启用的管理员账号可以提交 Cash。";
  if (row.source_type === "student_tuition_bill") {
    const preflight = row.cashSubmissionPreflight;
    if (preflight?.gate_state !== "enabled") return "学费 Cash Gate 当前未开放。";
    if (preflight?.classification === "ALREADY_SUBMITTED") return "该学费收入正在等待 Cash 确认。";
    if (preflight?.classification === "ALREADY_SYNCED") return "该学费收入已同步到 Cash。";
    return "该学费收入未通过服务端提交资格检查。";
  }
  if (row.status === "cancelled") return "已作废收入不能提交 Cash。";
  if (row.status !== "pending") return "只有待确认收入记录可以提交 Cash 收入确认。";
  const event = row.cashIncomeLinkageEvent;
  if (!event) return "";
  if (event.sync_status === "cash_rejected" || event.cash_request_status === "rejected") return "";
  if (event.sync_status === "pending_cash_request" || event.sync_status === "awaiting_cash_confirmation") return "该收入记录已有待确认 Cash request。";
  if (event.sync_status === "synced") return "该收入记录已同步到 Cash。";
  if (event.sync_status === "failed") return "该收入记录 Cash 同步失败，请先处理同步事件。";
  if (event.sync_status === "blocked") return "该收入记录 Cash 同步已被阻止。";
  return "当前收入记录不能提交 Cash 确认。";
}

function distinctValues(rows, key) {
  return Array.from(
    new Set(
      rows
        .map((row) => safeText(row[key]).trim())
        .filter(Boolean)
    )
  ).sort((left, right) => left.localeCompare(right, "zh-CN"));
}

function studentNameById(id) {
  const student = students.find((item) => item.id === id);
  if (!student) {
    return id ? "未知" : "未设置";
  }

  return studentName(student);
}

function incomeObjectName(row) {
  if (row?.source_type === "part_time_work") {
    return partTimeWorkSourceObjectName(row);
  }

  return studentNameById(row?.student_id);
}

function partTimeWorkSourceObjectName(row) {
  const snapshot = row?.source_snapshot && typeof row.source_snapshot === "object"
    ? row.source_snapshot
    : {};
  const workplaceName = safeText(snapshot.workplace_name);
  if (workplaceName) {
    return workplaceName;
  }

  const sourceLabel = safeText(row?.source_label);
  if (sourceLabel) {
    const firstToken = sourceLabel.split(/\s+/)[0];
    return firstToken || sourceLabel;
  }

  return "外部塾打工收入";
}

function incomeReceivedMonth(row) {
  const dateText = safeText(row?.income_date);
  return /^\d{4}-\d{2}/.test(dateText) ? dateText.slice(0, 7) : "";
}

function accountNameById(id) {
  const account = accounts.find((item) => item.id === id);
  if (!account) {
    return id ? "未知" : "未设置";
  }

  return accountName(account);
}

function incomeAccountDisplayName(row) {
  if (row?.cashIncomeLinkageEvent) {
    return cashIncomeAccountName(row.cashIncomeLinkageEvent);
  }

  if (!row?.account_id && isCashIncomeRow(row)) {
    return row?.status === "pending" ? "未提交 Cash" : "Cash账户未取得";
  }

  return accountNameById(row?.account_id);
}

function isCashIncomeRow(row) {
  return safeText(row?.receipt_status).includes("Cash");
}

function cashIncomeAccountName(event) {
  if (event.sync_status === "historical_confirmed") {
    return "历史人工确认（无 Cash 账户）";
  }

  const name = safeText(event.cash_account_name_snapshot);
  const currency = safeText(event.currency);
  const suffix = currency ? ` / ${currency}` : "";

  if (name) {
    return `${name}（Cash）${suffix}`;
  }

  if (event.cash_request_id || event.sync_status) {
    return event.cash_request_status === "pending" ||
      event.sync_status === "awaiting_cash_confirmation"
      ? "Cash待确认"
      : "Cash账户未取得";
  }

  return "Cash账户未取得";
}

function studentName(student) {
  return safeText(student.display_name || student.name) || "未设置";
}

function teacherNameById(id) {
  const teacher = teachers.find((row) => row.id === id);
  return safeText(teacher?.display_name || teacher?.name) || "未设置老师";
}

function subjectNameById(id) {
  return safeText(subjects.find((row) => row.id === id)?.name) || "未设置科目";
}

function accountName(account) {
  const name = safeText(account.name) || "未设置";
  const currency = safeText(account.currency);
  return currency ? `${name} / ${currency}` : name;
}

function incomeCategoryLabel(value) {
  return INCOME_CATEGORY_LABELS[value] || displayValue(value);
}

function paymentMethodLabel(value) {
  return PAYMENT_METHOD_LABELS[value] || displayValue(value);
}

function incomeStatusLabel(value) {
  return INCOME_STATUS_LABELS[value] || displayValue(value);
}

function statusClass(status) {
  if (status === "pending") {
    return "status-pending";
  }

  if (status === "received") {
    return "status-paid";
  }

  if (status === "cancelled" || status === "reversed") {
    return "status-cancelled";
  }

  return "status-neutral";
}

function renderCashSyncBadge(event) {
  if (!event) {
    return "-";
  }

  return `<span class="status-badge ${escapeAttribute(cashLinkageStatusClass(event.sync_status))}">${escapeHtml(cashLinkageStatusLabel(event.sync_status))}</span>`;
}

function renderCashSyncSummary(event) {
  if (!event) {
    return "-";
  }

  const amountText = event.payment_amount && event.payment_currency
    ? `<span class="income-cash-amount">${escapeHtml(formatCurrency(event.payment_amount, event.payment_currency))}</span>`
    : "";
  const noteText = safeText(event.note);
  return `
    <div class="income-cash-sync-cell">
      ${renderCashSyncBadge(event)}
      ${amountText}
      ${noteText ? `<div class="table-cell-summary">${escapeHtml(noteText)}</div>` : ""}
    </div>
  `;
}

function cashLinkageStatusLabel(value) {
  return CASH_LINKAGE_STATUS_LABELS[value] || displayValue(value);
}

function cashLinkageStatusClass(value) {
  if (value === "pending" || value === "pending_cash_request" || value === "awaiting_cash_confirmation") return "status-pending";
  if (value === "synced" || value === "historical_confirmed") return "status-paid";
  if (value === "failed" || value === "cash_rejected" || value === "blocked") return "status-cancelled";
  return "status-neutral";
}

function cashLinkageStatusHint(value) {
  if (value === "pending" || value === "pending_cash_request" || value === "awaiting_cash_confirmation") return "请求已生成";
  if (value === "synced") return "已生成流水";
  if (value === "historical_confirmed") return "系统上线前人工确认";
  if (value === "failed" || value === "cash_rejected" || value === "blocked") return "需要处理";
  return "";
}

function booleanLabel(value) {
  if (value === true) {
    return "是";
  }

  if (value === false) {
    return "否";
  }

  return "-";
}

function formatIncomeListAmount(row) {
  if (!row) {
    return "-";
  }
  return formatCurrency(row.amount, row.currency);
}

function renderIncomeListCarryoverImpact(row) {
  if (row?.source_type !== "student_tuition_bill") {
    return "-";
  }

  const snapshot = row.source_snapshot && typeof row.source_snapshot === "object"
    ? row.source_snapshot
    : {};
  if (!Object.prototype.hasOwnProperty.call(snapshot, "previous_carryover_cny")) {
    return "-";
  }

  const carryover = Number(snapshot.previous_carryover_cny);
  if (!Number.isFinite(carryover)) return "-";
  const display = row.forwardAdjustmentDisplay;
  if (!display) {
    return escapeHtml(formatCurrency(carryover, "CNY"));
  }
  return `
    <div title="历史结转">历史 ${escapeHtml(formatCurrency(display.historical_carryover_cny, "CNY"))}</div>
    <div title="本期 forward adjustment">调整 ${escapeHtml(formatCurrency(display.forward_adjustment_cny, "CNY"))}</div>
    <div title="净结转影响">净影响 ${escapeHtml(formatCurrency(display.net_carryover_impact_cny, "CNY"))}</div>
  `;
}

function formatIncomeListNoticeAmount(row) {
  if (row?.forwardAdjustmentDisplay) {
    return formatCurrency(row.forwardAdjustmentDisplay.final_notice_amount_cny, "CNY");
  }
  const billingAmountCny = studentTuitionBillBillingAmountCny(row);
  return billingAmountCny ? formatCurrency(billingAmountCny, "CNY") : "-";
}

function formatDateOnly(value) {
  return safeText(value) || "-";
}

function parseNumberInput(value) {
  const normalized = String(value ?? "").replace(/,/g, "").trim();
  if (!normalized) {
    return NaN;
  }
  return Number(normalized);
}

function roundDecimal(value, precision) {
  if (!Number.isFinite(value)) {
    return NaN;
  }
  const factor = 10 ** precision;
  return Math.round(value * factor) / factor;
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
}

function currentDate() {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function displayValue(value) {
  return safeText(value) || "-";
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
}

function showMessage(type, text) {
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = text;
}

function setBatchCashIncomeSubmitting(isSubmitting) {
  isBatchCashSubmitting = isSubmitting;
  dom.batchCashIncomeSubmitButton.disabled = isSubmitting;
  dom.batchCashIncomeCancelButton.disabled = isSubmitting;
  dom.batchCashIncomeSubmitButton.textContent = isSubmitting ? "提交中..." : "提交所选 Cash 确认";
  renderBatchCashIncomeRows();
}

function updateBatchCashIncomeTotal() {
  if (!dom.batchCashIncomeTotal) {
    return;
  }

  const totals = new Map();
  for (const state of batchCashIncomeRows) {
    const amount = parseNumberInput(state.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      continue;
    }
    const currency = state.currency || "-";
    totals.set(currency, (totals.get(currency) || 0) + amount);
  }

  const totalText = Array.from(totals.entries())
    .map(([currency, amount]) => formatCurrency(amount, currency))
    .join(" / ");
  dom.batchCashIncomeTotal.textContent = `本次提交合计：${totalText || "-"}`;
}

function clearBatchCashIncomeError() {
  dom.batchCashIncomeError.textContent = "";
  dom.batchCashIncomeError.classList.add("is-hidden");
}

function showBatchCashIncomeError(message) {
  dom.batchCashIncomeError.textContent = message;
  dom.batchCashIncomeError.classList.remove("is-hidden");
  dom.batchCashIncomeDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function cssEscape(value) {
  if (window.CSS?.escape) {
    return window.CSS.escape(String(value));
  }

  return String(value).replaceAll('"', '\\"');
}

function escapeHtml(value) {
  return safeText(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttribute(value) {
  return escapeHtml(value);
}
