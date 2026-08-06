import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import {
  initSchoolAuth,
  isActiveAdmin,
  requireActiveAdminForCashConfirmation,
} from "../auth.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createExpenseRecord,
  createPendingCashExpenseRecord,
  fetchExpenseAttachmentCounts,
  fetchExpenseLookups,
  fetchExpensePaymentRequests,
  fetchExpenseRecords,
  requestCashExpenseConfirmation,
} from "../api/expense-api.js?v=phase-b4-finance-20260807-1";
import { fetchSchoolEligibleCashAccountsViaFunction } from "../api/payment-api.js";
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
  teacherId: "",
  accountId: "",
  currency: "",
};

const EXPENSE_STATUS_LABELS = {
  pending: "待支付",
  paid: "已支付",
  reversed: "已撤销",
  void: "已作废",
  cancelled: "已取消",
  voided: "已作废",
};

const EXPENSE_CATEGORY_LABELS = {
  advertising: "广告宣传",
  classroom: "教室费用",
  other: "其他",
  software: "软件 / 系统",
  tax_accounting: "税务会计",
  teacher_wage: "老师工资",
};

const PAYMENT_METHOD_LABELS = {
  alipay: "支付宝",
  bank: "银行",
  bank_transfer: "银行转账",
  card: "信用卡",
  cash: "现金支付",
  wechat: "微信",
};

const REIMBURSEMENT_STATUS_LABELS = {
  not_required: "无需报销",
  paid: "已报销",
  pending: "待报销",
};

const WAGE_PAYMENT_STATUS_LABELS = {
  paid: "工资支付：已支付",
  reversed: "工资支付：已撤销",
  void: "工资支付：已作废",
  pending: "工资支付：待支付",
  cancelled: "工资支付：已取消",
  unlinked: "未关联",
};

const CREATE_EXPENSE_CATEGORY_OPTIONS = [
  "classroom",
  "other",
  "tax_accounting",
  "advertising",
  "software",
];

const CREATE_RECEIPT_STATUS_OPTIONS = ["有", "无需收据", "待确认"];
const CREATE_REIMBURSEMENT_STATUS_OPTIONS = ["not_required", "pending"];
const CREATE_PAYMENT_METHOD_OPTIONS = ["cash", "bank_transfer", "card", "alipay"];
const CREATE_EXPENSE_FIELD_IDS = [
  "expenseDate",
  "account",
  "currency",
  "expenseCategory",
  "description",
  "amount",
  "paymentMethod",
  "receiptStatus",
  "reimbursementStatus",
  "taxCategory",
  "exchangeRate",
];
const CASH_EXPENSE_CURRENCIES = ["JPY", "CNY"];
const CASH_REQUEST_STATUS_LABELS = {
  pending_cash_request: "Cash待提交",
  awaiting_cash_confirmation: "Cash待确认",
  pending: "Cash待确认",
  approved: "Cash已确认",
  synced: "Cash已同步",
  rejected: "Cash已拒绝",
  cash_rejected: "Cash已拒绝",
  failed: "Cash失败",
};
const JPY_CNY_RATE_API_URL = "https://api.frankfurter.dev/v2/rate/JPY/CNY";
const ROUNDING_MODE_LABELS = {
  round: "四舍五入",
  ceil: "向上取整",
  floor: "向下取整",
};

const dom = {};
let businessEntities = [];
let accounts = [];
let teachers = [];
let students = [];
let expenseRecords = [];
let renderedExpenseRows = [];
let selectedExpenseIds = new Set();
let paymentRequestsByExpenseId = new Map();
let attachmentCountsByExpenseId = new Map();
let cashEligibleAccounts = [];
let hasLoadedCashEligibleAccounts = false;
let loadedMonth = "";
let isCreateSubmitting = false;
let createExpenseClientRequestId = "";
let batchCashExpenseRows = [];
let isBatchCashSubmitting = false;
let initialMonth = "";
let initialFilters = null;
let topStudentCandidates = [];
let topStudentCandidateKey = "";

export async function initExpensePage() {
  cacheDom();
  await initSchoolAuth();
  updateExpenseAdminControls();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  initialMonth = initialYearMonthFromUrl();
  initialFilters = readExpenseQuery();
  setDefaultFilters(initialFilters);
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderExpenseRecords([]);
    return;
  }

  loadInitialData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#expenseMessageArea");
  dom.filterForm = document.querySelector("#expenseFilterForm");
  dom.yearFilter = document.querySelector("#expenseYearFilter");
  dom.monthFilter = document.querySelector("#expenseMonthFilter");
  dom.studentSelect = document.querySelector("#expenseStudentSelect");
  dom.includeInactiveCheckbox = document.querySelector("#expenseIncludeInactiveCheckbox");
  dom.teacherSelect = document.querySelector("#expenseTeacherSelect");
  dom.accountSelect = document.querySelector("#expenseAccountSelect");
  dom.currencySelect = document.querySelector("#expenseCurrencySelect");
  dom.resetButton = document.querySelector("#expenseResetButton");
  dom.tableBody = document.querySelector("#expenseTableBody");
  dom.loadingState = document.querySelector("#expenseLoadingState");
  dom.emptyState = document.querySelector("#expenseEmptyState");
  dom.expenseCount = document.querySelector("#expenseCount");
  dom.openCreateExpenseButton = document.querySelector("#openCreateExpenseButton");
  dom.openBatchCashExpenseButton = document.querySelector("#openBatchCashExpenseButton");
  dom.selectAllCashRequests = document.querySelector("#expenseSelectAllCashRequests");
  dom.batchCashExpenseDialog = document.querySelector("#batchCashExpenseDialog");
  dom.batchCashExpenseError = document.querySelector("#batchCashExpenseError");
  dom.batchCashExpenseRateToolbar = document.querySelector("#batchCashExpenseRateToolbar");
  dom.batchCashExpenseTableBody = document.querySelector("#batchCashExpenseTableBody");
  dom.batchCashExpenseTotal = document.querySelector("#batchCashExpenseTotal");
  dom.batchCashExpenseSubmitButton = document.querySelector("#batchCashExpenseSubmitButton");
  dom.batchCashExpenseCancelButton = document.querySelector("#batchCashExpenseCancelButton");
  dom.createExpenseDialog = document.querySelector("#createExpenseDialog");
  dom.createExpenseError = document.querySelector("#createExpenseError");
  dom.createExpenseDateInput = document.querySelector("#createExpenseDateInput");
  dom.createExpenseAccountSelect = document.querySelector("#createExpenseAccountSelect");
  dom.createExpenseCurrencySelect = document.querySelector("#createExpenseCurrencySelect");
  dom.createExpenseModeSummary = document.querySelector("#createExpenseModeSummary");
  dom.createExpenseCategorySelect = document.querySelector("#createExpenseCategorySelect");
  dom.createExpenseAmountInput = document.querySelector("#createExpenseAmountInput");
  dom.createExpenseDescriptionInput = document.querySelector("#createExpenseDescriptionInput");
  dom.createExpensePaymentMethodSelect = document.querySelector("#createExpensePaymentMethodSelect");
  dom.createExpenseReceiptStatusSelect = document.querySelector("#createExpenseReceiptStatusSelect");
  dom.createExpenseReimbursementStatusSelect = document.querySelector("#createExpenseReimbursementStatusSelect");
  dom.createExpenseTaxCategoryInput = document.querySelector("#createExpenseTaxCategoryInput");
  dom.createExpenseExchangeRateInput = document.querySelector("#createExpenseExchangeRateInput");
  dom.createExpenseNoteInput = document.querySelector("#createExpenseNoteInput");
  dom.createExpenseSubmitButton = document.querySelector("#createExpenseSubmitButton");
  dom.createExpenseCancelButton = document.querySelector("#createExpenseCancelButton");
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
    setDefaultFilters({ month: currentYearMonth() });
    applyQuery();
  });

  dom.openCreateExpenseButton.addEventListener("click", openCreateExpenseDialog);
  dom.openBatchCashExpenseButton.addEventListener("click", () => {
    openBatchCashExpenseDialog(selectedExpenseRows());
  });
  dom.selectAllCashRequests.addEventListener("change", handleExpenseSelectAllChange);
  dom.tableBody.addEventListener("click", handleExpenseTableClick);
  dom.tableBody.addEventListener("change", handleExpenseTableChange);
  dom.batchCashExpenseCancelButton.addEventListener("click", closeBatchCashExpenseDialog);
  dom.batchCashExpenseSubmitButton.addEventListener("click", submitBatchCashExpenseRequests);
  dom.batchCashExpenseTableBody.addEventListener("input", handleBatchCashExpenseInput);
  dom.batchCashExpenseTableBody.addEventListener("change", handleBatchCashExpenseInput);
  dom.batchCashExpenseTableBody.addEventListener("click", handleBatchCashExpenseClick);
  dom.batchCashExpenseRateToolbar?.addEventListener("input", handleBatchCashExpenseInput);
  dom.batchCashExpenseRateToolbar?.addEventListener("change", handleBatchCashExpenseInput);
  dom.batchCashExpenseRateToolbar?.addEventListener("click", handleBatchCashExpenseClick);
  dom.createExpenseCancelButton.addEventListener("click", closeCreateExpenseDialog);
  dom.createExpenseSubmitButton.addEventListener("click", submitCreateExpense);
  for (const input of dom.createExpenseDialog.querySelectorAll('[name="createExpenseHandlingMode"]')) {
    input.addEventListener("change", updateCreateExpenseMode);
  }
  dom.createExpenseAccountSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("account");
    hideCreateErrorIfClean();
  });

  for (const [input, fieldId] of [
    [dom.createExpenseDateInput, "expenseDate"],
    [dom.createExpenseCategorySelect, "expenseCategory"],
    [dom.createExpenseDescriptionInput, "description"],
    [dom.createExpenseAmountInput, "amount"],
    [dom.createExpensePaymentMethodSelect, "paymentMethod"],
    [dom.createExpenseReceiptStatusSelect, "receiptStatus"],
    [dom.createExpenseReimbursementStatusSelect, "reimbursementStatus"],
    [dom.createExpenseTaxCategoryInput, "taxCategory"],
    [dom.createExpenseExchangeRateInput, "exchangeRate"],
    [dom.createExpenseCurrencySelect, "currency"],
  ]) {
    input.addEventListener("input", () => {
      clearCreateFieldInvalid(fieldId);
      hideCreateErrorIfClean();
    });
    input.addEventListener("change", () => {
      clearCreateFieldInvalid(fieldId);
      hideCreateErrorIfClean();
    });
  }
}

function updateExpenseAdminControls() {
  const activeAdmin = isActiveAdmin();
  dom.openCreateExpenseButton.hidden = !activeAdmin;
  dom.openBatchCashExpenseButton.hidden = !activeAdmin;
  dom.selectAllCashRequests.hidden = !activeAdmin;
}

function setDefaultFilters(overrides = null) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, overrides?.month || initialMonth || currentYearMonth());
  dom.studentSelect.value = DEFAULT_FILTERS.studentId;
  dom.includeInactiveCheckbox.checked = Boolean(overrides?.includeInactive);
  dom.teacherSelect.value = DEFAULT_FILTERS.teacherId;
  dom.accountSelect.value = DEFAULT_FILTERS.accountId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  if (overrides) {
    dom.studentSelect.value = overrides.studentId || "";
    dom.teacherSelect.value = overrides.teacherId || "";
    dom.accountSelect.value = overrides.accountId || "";
    dom.currencySelect.value = overrides.currency || "";
  }
  updateMonthScopedNavigation(getYearMonthSelectValue(dom.yearFilter, dom.monthFilter));
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载支出记录数据...");

  try {
    const lookups = await fetchExpenseLookups();
    businessEntities = lookups.businessEntities;
    requirePrimarySchoolBusinessEntityId(businessEntities);
    accounts = lookups.accounts;
    teachers = lookups.teachers;
    students = lookups.students;
    const filters = initialFilters || readFilters();
    await Promise.all([loadExpenseMonth(filters.month), loadTopStudentCandidates(filters)]);
    renderMasterOptions();
    restoreFilterSelections(filters);
    syncExpenseQuery(filters);
    updateMonthScopedNavigation(filters.month);
    applyCurrentFilters();
    showMessage("success", "支出记录数据已加载。");
  } catch (error) {
    businessEntities = [];
    accounts = [];
    teachers = [];
    students = [];
    expenseRecords = [];
    paymentRequestsByExpenseId = new Map();
    attachmentCountsByExpenseId = new Map();
    loadedMonth = "";
    topStudentCandidates = [];
    topStudentCandidateKey = "";
    renderMasterOptions();
    renderDataOptions([]);
    renderExpenseRecords([]);
    showMessage("error", `读取支出记录数据失败：${error.message || error}`);
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

  syncExpenseQuery(filters);
  updateMonthScopedNavigation(filters.month);

  if (filters.month !== loadedMonth || studentCandidateKey(filters) !== topStudentCandidateKey) {
    setLoading(true);
    showMessage("info", "正在加载支出记录...");

    try {
      await Promise.all([loadExpenseMonth(filters.month), loadTopStudentCandidates(filters)]);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "支出记录已加载。");
    } catch (error) {
      expenseRecords = [];
      paymentRequestsByExpenseId = new Map();
      attachmentCountsByExpenseId = new Map();
      loadedMonth = "";
      topStudentCandidates = [];
      topStudentCandidateKey = "";
      renderDataOptions([]);
      renderExpenseRecords([]);
      showMessage("error", `读取支出记录失败：${error.message || error}`);
    } finally {
      setLoading(false);
    }
    return;
  }

  applyCurrentFilters();
}

async function loadExpenseMonth(month) {
  expenseRecords = await fetchExpenseRecords(month);
  const [paymentRequests, attachmentCounts] = await Promise.all([
    fetchExpensePaymentRequests(teacherWageExpenseIds(expenseRecords)),
    fetchExpenseAttachmentCounts(expenseRecords.map((row) => row.id)),
  ]);
  paymentRequestsByExpenseId = groupPaymentRequestsByExpenseId(paymentRequests);
  attachmentCountsByExpenseId = attachmentCounts;
  loadedMonth = month;
  renderDataOptions(expenseRecords);
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
  renderExpenseRecords(filterExpenseRecords(expenseRecords, filters));
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
    teacherId: dom.teacherSelect.value,
    accountId: dom.accountSelect.value,
    currency: dom.currencySelect.value,
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.studentSelect.value = filters.studentId;
  dom.includeInactiveCheckbox.checked = Boolean(filters.includeInactive);
  dom.teacherSelect.value = filters.teacherId;
  dom.accountSelect.value = filters.accountId;
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

function readExpenseQuery() {
  const params = new URLSearchParams(window.location.search);
  const candidate = readStudentCandidateQuery(window.location.search);
  return {
    month: initialMonth || currentYearMonth(),
    ...DEFAULT_FILTERS,
    ...candidate,
    teacherId: params.get("teacher_id") || "",
    accountId: params.get("account_id") || "",
    currency: params.get("currency") || "",
  };
}

function syncExpenseQuery(filters) {
  if (!window.history?.replaceState) return;
  const [year, month] = filters.month.split("-");
  const url = new URL(window.location.href);
  url.searchParams.set("year", year);
  url.searchParams.set("month", month);
  writeStudentCandidateQuery(url.searchParams, filters);
  setOptionalQuery(url.searchParams, "teacher_id", filters.teacherId);
  setOptionalQuery(url.searchParams, "account_id", filters.accountId);
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
  renderEntityOptions(dom.teacherSelect, teachers, teacherName, "全部老师");
  renderEntityOptions(dom.accountSelect, accounts, accountName);
}

function renderDataOptions(rows) {
  renderValueOptions(dom.currencySelect, distinctValues(rows, "currency"), displayValue);
}

function renderEntityOptions(selectEl, rows, labelGetter, emptyLabel = "全部") {
  const options = [`<option value="">${escapeHtml(emptyLabel)}</option>`];

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

function renderExpenseRecords(rows) {
  updateExpenseAdminControls();
  renderedExpenseRows = rows;
  pruneSelectedExpenseIds();
  const cashRequestableCount = rows.filter(canRequestCashExpense).length;
  dom.expenseCount.textContent = `共 ${rows.length} 条｜可提交 Cash ${cashRequestableCount} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    updateExpenseBatchControls();
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td class="expense-select-cell">${renderExpenseSelectionCell(row)}</td>
      <td class="expense-source-cell">${renderExpenseSourceCell(row)}</td>
      <td><span class="status-badge status-neutral">${escapeHtml(expenseCategoryLabel(row.expense_category))}</span></td>
      <td class="expense-nowrap month-cell">${escapeHtml(formatMonth(row.year_month))}</td>
      <td class="expense-nowrap date-cell">${escapeHtml(formatDateOnly(row.expense_date))}</td>
      <td class="number-cell expense-nowrap amount-cell">${escapeHtml(formatExpenseListAmount(row))}</td>
      <td>${renderExpenseStatusCash(row)}</td>
      <td class="expense-related-cell">${renderExpenseRelatedCell(row)}</td>
      <td class="action-cell expense-action-cell">${renderExpenseRowActions(row)}</td>
    </tr>
  `).join("");
  updateExpenseBatchControls();
}

function renderExpenseSourceCell(row) {
  const description = businessListText(row?.description, "");
  const descriptionDisplay = description || "-";
  const note = businessListText(row?.note, "");
  const title = [
    expenseObjectName(row),
    description,
    note,
  ].filter(Boolean).join(" / ");
  return `
    <div class="expense-list-primary" title="${escapeAttribute(title || "无业务备注")}">${escapeHtml(expenseObjectName(row))}</div>
    <div class="expense-list-secondary" title="${escapeAttribute(descriptionDisplay)}">${escapeHtml(descriptionDisplay)}</div>
  `;
}

function renderExpenseRelatedCell(row) {
  const primary = relatedObjectLabel(row);
  const secondary = accountNameById(row.account_id);
  return `
    <div class="expense-list-primary" title="${escapeAttribute(primary)}">${escapeHtml(primary)}</div>
    <div class="expense-list-secondary" title="${escapeAttribute(secondary)}">${escapeHtml(secondary || "-")}</div>
  `;
}

function renderExpenseSelectionCell(row) {
  const selectable = canRequestCashExpense(row);
  const disabledReason = selectable ? "" : cashRequestDisabledTitle(row);
  return `
    <input
      type="checkbox"
      data-expense-select-id="${escapeAttribute(row.id)}"
      aria-label="选择支出记录 ${escapeAttribute(expenseObjectName(row))}"
      ${disabledReason ? `title="${escapeAttribute(disabledReason)}"` : ""}
      ${selectable ? "" : "disabled"}
      ${selectedExpenseIds.has(row.id) ? "checked" : ""}
    >
  `;
}

function renderExpenseRowActions(row) {
  const cashButton = canRequestCashExpense(row)
    ? `<button class="table-action-button" type="button" data-expense-cash-request-id="${escapeAttribute(row.id)}">提交Cash</button>`
    : "";
  return `
    <div class="income-row-actions">
      <a class="button table-action-button" href="${escapeAttribute(expenseDetailUrl(row.id))}">详情</a>
      ${cashButton}
    </div>
  `;
}

function handleExpenseTableClick(event) {
  const button = event.target.closest("[data-expense-cash-request-id]");
  if (!button) {
    return;
  }

  const expenseId = button.getAttribute("data-expense-cash-request-id");
  const expense = expenseRecords.find((row) => row.id === expenseId);
  if (!expense) {
    showMessage("error", "支出记录不存在，请刷新后重试。");
    return;
  }

  openBatchCashExpenseDialog([expense]);
}

function handleExpenseTableChange(event) {
  const checkbox = event.target.closest("[data-expense-select-id]");
  if (!checkbox) {
    return;
  }

  const expenseId = checkbox.getAttribute("data-expense-select-id");
  const expense = renderedExpenseRows.find((row) => row.id === expenseId);
  if (!expense || !canRequestCashExpense(expense)) {
    checkbox.checked = false;
    selectedExpenseIds.delete(expenseId);
    updateExpenseBatchControls();
    return;
  }

  if (checkbox.checked) {
    selectedExpenseIds.add(expenseId);
  } else {
    selectedExpenseIds.delete(expenseId);
  }
  updateExpenseBatchControls();
}

function handleExpenseSelectAllChange() {
  const selectableIds = renderedExpenseRows.filter(canRequestCashExpense).map((row) => row.id);
  if (dom.selectAllCashRequests.checked) {
    selectedExpenseIds = new Set(selectableIds);
  } else {
    for (const id of selectableIds) {
      selectedExpenseIds.delete(id);
    }
  }
  renderExpenseRecords(renderedExpenseRows);
}

function openCreateExpenseDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  if (
    !requireActiveAdminForCashConfirmation((_type, message) => {
      showMessage("error", message.replace("提交 Cash 确认请求", "新增支出"));
    })
  ) {
    return;
  }

  if (!globalThis.crypto?.randomUUID) {
    showMessage("error", "当前浏览器无法生成安全的新增请求身份，请升级浏览器后重试。");
    return;
  }

  clearCreateErrors();
  setCreateSubmitting(false);
  createExpenseClientRequestId = globalThis.crypto.randomUUID();

  const filters = readFilters();
  const defaultAccountId = filters?.accountId || "";

  dom.createExpenseDateInput.value = currentDate();
  dom.createExpenseAmountInput.value = "";
  dom.createExpenseDescriptionInput.value = "";
  dom.createExpensePaymentMethodSelect.value = "";
  dom.createExpenseReceiptStatusSelect.value = "待确认";
  dom.createExpenseReimbursementStatusSelect.value = "";
  dom.createExpenseTaxCategoryInput.value = "待确认";
  dom.createExpenseExchangeRateInput.value = "";
  dom.createExpenseCurrencySelect.value = "JPY";
  dom.createExpenseNoteInput.value = "";
  const schoolModeInput = dom.createExpenseDialog.querySelector('[name="createExpenseHandlingMode"][value="school"]');
  if (schoolModeInput) schoolModeInput.checked = true;
  renderCreateCategoryOptions();

  renderCreateAccountOptions();
  dom.createExpenseAccountSelect.value = filteredCreateAccounts().some((account) => account.id === defaultAccountId)
    ? defaultAccountId
    : "";

  updateCreateExpenseMode();

  dom.createExpenseDialog.classList.remove("is-hidden");
  dom.createExpenseDialog.setAttribute("aria-hidden", "false");
}

function closeCreateExpenseDialog() {
  if (isCreateSubmitting) {
    return;
  }

  dom.createExpenseDialog.classList.add("is-hidden");
  dom.createExpenseDialog.setAttribute("aria-hidden", "true");
  createExpenseClientRequestId = "";
}

async function submitCreateExpense() {
  if (isCreateSubmitting) {
    return;
  }

  clearCreateErrors();

  const payload = readCreateExpensePayload();
  if (!payload) {
    return;
  }

  setCreateSubmitting(true);

  try {
    if (payload.handlingMode === "cash") {
      const result = await createPendingCashExpenseRecord(payload);
      setCreateSubmitting(false);
      closeCreateExpenseDialog();
      let refreshSucceeded = true;
      try {
        await refreshCurrentExpenseList();
      } catch (refreshError) {
        console.error(refreshError);
        refreshSucceeded = false;
      }
      showPendingCashExpenseCreateSuccess(result, { refreshSucceeded });
      return;
    }

    const result = await createExpenseRecord(payload);
    setCreateSubmitting(false);
    closeCreateExpenseDialog();
    await refreshCurrentExpenseList();
    showExpenseCreateSuccess(result);
  } catch (error) {
    console.error(error);
    showCreateError(`新增支出失败：${error.message || error}`, createFieldIdsForError(error.message || ""));
  } finally {
    setCreateSubmitting(false);
  }
}

function readCreateExpensePayload() {
  const handlingMode = createExpenseHandlingMode();
  const expenseDate = dom.createExpenseDateInput.value;
  if (!expenseDate) {
    showCreateError("请选择支出日期。", ["expenseDate"]);
    return null;
  }

  const businessEntityId = requirePrimarySchoolBusinessEntityId(businessEntities);

  let accountId = null;
  let account = null;
  let currency = "";
  if (handlingMode === "school") {
    accountId = dom.createExpenseAccountSelect.value;
    if (!accountId) {
      showCreateError("请选择付款账户。", ["account"]);
      return null;
    }

    account = accounts.find((item) => item.id === accountId);
    if (!account || account.is_active !== true || account.app_type !== "school") {
      showCreateError("付款账户无效或已停用。", ["account"]);
      return null;
    }

    if (account.business_entity_id !== businessEntityId) {
      showCreateError("付款账户与内部范围不一致。", ["account"]);
      return null;
    }

    if (!account.currency) {
      showCreateError("付款账户缺少币种。", ["account"]);
      return null;
    }
    currency = account.currency;
  } else {
    currency = dom.createExpenseCurrencySelect.value;
    if (!CASH_EXPENSE_CURRENCIES.includes(currency)) {
      showCreateError("请选择 JPY 或 CNY 支出币种。", ["currency"]);
      return null;
    }
    if (!createExpenseClientRequestId) {
      showCreateError("新增请求身份已失效，请关闭对话框后重新打开。");
      return null;
    }
  }

  const expenseCategory = dom.createExpenseCategorySelect.value;
  if (!expenseCategory) {
    showCreateError("支出分类不能为空。", ["expenseCategory"]);
    return null;
  }

  if (expenseCategory === "teacher_wage" || !CREATE_EXPENSE_CATEGORY_OPTIONS.includes(expenseCategory)) {
    showCreateError("暂不支持该支出分类。", ["expenseCategory"]);
    return null;
  }

  const description = dom.createExpenseDescriptionInput.value.trim();
  if (!description) {
    showCreateError("支出内容不能为空。", ["description"]);
    return null;
  }

  const amount = Number(dom.createExpenseAmountInput.value);
  if (!Number.isFinite(amount) || amount <= 0) {
    showCreateError("支出金额必须大于 0。", ["amount"]);
    return null;
  }

  const paymentMethod = handlingMode === "school"
    ? dom.createExpensePaymentMethodSelect.value
    : null;
  if (handlingMode === "school" && !CREATE_PAYMENT_METHOD_OPTIONS.includes(paymentMethod)) {
    showCreateError("请选择支付方式。", ["paymentMethod"]);
    return null;
  }

  const receiptStatus = dom.createExpenseReceiptStatusSelect.value;
  if (!CREATE_RECEIPT_STATUS_OPTIONS.includes(receiptStatus)) {
    showCreateError("收据状态无效。", ["receiptStatus"]);
    return null;
  }

  const reimbursementStatus = dom.createExpenseReimbursementStatusSelect.value;
  if (handlingMode === "cash" && !CREATE_REIMBURSEMENT_STATUS_OPTIONS.includes(reimbursementStatus)) {
    showCreateError("报销状态无效。", ["reimbursementStatus"]);
    return null;
  }
  if (handlingMode === "school" && reimbursementStatus
      && !CREATE_REIMBURSEMENT_STATUS_OPTIONS.includes(reimbursementStatus)) {
    showCreateError("报销状态无效。", ["reimbursementStatus"]);
    return null;
  }

  const exchangeRateText = dom.createExpenseExchangeRateInput.value.trim();
  const parsedExchangeRate = exchangeRateText ? Number(exchangeRateText) : null;
  if (exchangeRateText && (!Number.isFinite(parsedExchangeRate) || parsedExchangeRate < 0)) {
    showCreateError("汇率必须为空、0 或大于 0。", ["exchangeRate"]);
    return null;
  }
  const exchangeRate = parsedExchangeRate && parsedExchangeRate > 0 ? parsedExchangeRate : null;

  return {
    handlingMode,
    clientRequestId: handlingMode === "cash" ? createExpenseClientRequestId : null,
    expenseDate,
    businessEntityId,
    accountId,
    expenseCategory,
    description,
    currency,
    amount,
    exchangeRate,
    paymentMethod,
    isBusinessExpense: true,
    taxCategory: dom.createExpenseTaxCategoryInput.value.trim(),
    receiptStatus,
    reimbursementStatus: reimbursementStatus || null,
    teacherId: null,
    studentId: null,
    note: dom.createExpenseNoteInput.value.trim(),
  };
}

function createExpenseHandlingMode() {
  return dom.createExpenseDialog.querySelector('[name="createExpenseHandlingMode"]:checked')?.value === "cash"
    ? "cash"
    : "school";
}

function updateCreateExpenseMode() {
  const cashMode = createExpenseHandlingMode() === "cash";
  const databaseDefaultOption = dom.createExpenseReimbursementStatusSelect.options[0];
  for (const field of dom.createExpenseDialog.querySelectorAll("[data-create-expense-school-only]")) {
    field.hidden = cashMode;
  }
  for (const field of dom.createExpenseDialog.querySelectorAll("[data-create-expense-cash-only]")) {
    field.hidden = !cashMode;
  }
  dom.createExpenseAccountSelect.disabled = cashMode;
  dom.createExpensePaymentMethodSelect.disabled = cashMode;
  dom.createExpenseCurrencySelect.disabled = !cashMode;
  if (databaseDefaultOption) {
    databaseDefaultOption.disabled = cashMode;
    databaseDefaultOption.textContent = cashMode
      ? "请选择报销状态"
      : "School 模式由数据库按账户判定";
  }
  dom.createExpenseModeSummary.textContent = cashMode
    ? "提交至 Cash 审批：保存为待支付支出，不会扣减 School 账户余额。保存后可从支出列表单独提交至 Cash。"
    : "从 School 账户直接支出：保存后立即记为已支付，并扣减 School 账户余额。";
  dom.createExpenseSubmitButton.textContent = cashMode ? "保存待支付支出" : "保存 School 支出";
  clearCreateFieldInvalid(cashMode ? "account" : "currency");
  clearCreateFieldInvalid(cashMode ? "paymentMethod" : "currency");
  hideCreateErrorIfClean();
}

async function refreshCurrentExpenseList() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  await loadExpenseMonth(filters.month);
  restoreFilterSelections(filters);
  applyCurrentFilters();
}

function showExpenseCreateSuccess(result) {
  const expenseId = result?.expense_id;
  dom.messageArea.className = "message message-success";
  if (expenseId) {
    dom.messageArea.innerHTML = `支出已新增并自动出账。<a href="${escapeAttribute(expenseDetailUrl(expenseId))}">查看详情</a>`;
  } else {
    dom.messageArea.textContent = "支出已新增并自动出账。";
  }
}

function showPendingCashExpenseCreateSuccess(result, options = {}) {
  const expenseId = result?.expense_id || result?.expense_record?.id;
  const isVisible = Boolean(expenseId) && renderedExpenseRows.some((row) => row.id === expenseId);
  let message = "支出已保存为待支付记录，尚未提交 Cash。请从支出列表单独提交至 Cash。";
  if (options.refreshSucceeded === false) {
    message += " 列表刷新失败，请刷新页面后继续。";
  } else if (!isVisible) {
    message += " 当前筛选条件未显示该记录，请调整月份或筛选条件后继续。";
  }

  dom.messageArea.className = "message message-success";
  if (expenseId) {
    dom.messageArea.innerHTML = `${escapeHtml(message)} <a href="${escapeAttribute(expenseDetailUrl(expenseId))}">查看详情</a>`;
  } else {
    dom.messageArea.textContent = message;
  }
}

function selectedExpenseRows() {
  return renderedExpenseRows.filter((row) => selectedExpenseIds.has(row.id) && canRequestCashExpense(row));
}

function pruneSelectedExpenseIds() {
  const selectableIds = new Set(renderedExpenseRows.filter(canRequestCashExpense).map((row) => row.id));
  for (const id of Array.from(selectedExpenseIds)) {
    if (!selectableIds.has(id)) {
      selectedExpenseIds.delete(id);
    }
  }
}

function updateExpenseBatchControls() {
  const selectableRows = renderedExpenseRows.filter(canRequestCashExpense);
  const selectedRows = selectedExpenseRows();
  dom.openBatchCashExpenseButton.disabled = selectedRows.length === 0;
  dom.openBatchCashExpenseButton.textContent = selectedRows.length > 0
    ? `批量提交 Cash（已选 ${selectedRows.length} 条）`
    : "批量提交 Cash";
  dom.selectAllCashRequests.disabled = selectableRows.length === 0;
  dom.selectAllCashRequests.checked = selectableRows.length > 0 && selectedRows.length === selectableRows.length;
  dom.selectAllCashRequests.indeterminate = selectedRows.length > 0 && selectedRows.length < selectableRows.length;
}

async function openBatchCashExpenseDialog(rows) {
  const targets = (rows || []).filter(canRequestCashExpense);
  if (!targets.length) {
    showMessage("error", "请选择可提交 Cash 支付确认的支出记录。");
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

  batchCashExpenseRows = targets.map((expense) => ({
    expense,
    amount: expense.amount ?? "",
    amountSource: "db",
    currency: expense.currency || "JPY",
    paymentDate: currentJapanDate(),
    accountId: "",
    note: defaultCashExpenseNote(expense),
    exchangeRate: "",
    theoreticalAmount: "",
    roundingMode: "",
    rateStatus: "",
  }));
  clearBatchCashExpenseError();
  setBatchCashExpenseSubmitting(false);
  renderBatchCashExpenseRows();
  dom.batchCashExpenseDialog.classList.remove("is-hidden");
  dom.batchCashExpenseDialog.setAttribute("aria-hidden", "false");
}

function closeBatchCashExpenseDialog() {
  if (isBatchCashSubmitting) {
    return;
  }

  batchCashExpenseRows = [];
  dom.batchCashExpenseDialog.classList.add("is-hidden");
  dom.batchCashExpenseDialog.setAttribute("aria-hidden", "true");
}

async function ensureCashEligibleAccountsLoaded() {
  if (hasLoadedCashEligibleAccounts) {
    return;
  }

  const rows = await fetchSchoolEligibleCashAccountsViaFunction();
  cashEligibleAccounts = (rows || []).filter((account) => (
    account?.is_active === true &&
    account?.allow_school_requests === true &&
    CASH_EXPENSE_CURRENCIES.includes(account.currency)
  ));
  hasLoadedCashEligibleAccounts = true;
}

function renderBatchCashExpenseRows() {
  renderBatchCashExpenseRateToolbar();
  dom.batchCashExpenseTableBody.innerHTML = batchCashExpenseRows.map((state) => {
    const expense = state.expense;
    return `
      <tr data-batch-expense-row-id="${escapeAttribute(expense.id)}">
        <td>${escapeHtml(expenseObjectName(expense))}</td>
        <td class="expense-nowrap">${escapeHtml(formatMonth(expense.year_month))}</td>
        <td><input data-batch-expense-date="${escapeAttribute(expense.id)}" type="date" value="${escapeAttribute(state.paymentDate)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
        <td class="number-cell expense-nowrap">${escapeHtml(formatCurrency(expense.amount, expense.currency))}</td>
        <td><input data-batch-expense-amount="${escapeAttribute(expense.id)}" type="number" min="0" step="0.01" inputmode="decimal" value="${escapeAttribute(state.amount)}" ${isBatchCashSubmitting ? "disabled" : ""}>${renderBatchCashExpenseAmountHint(state)}</td>
        <td>
          <select data-batch-expense-currency="${escapeAttribute(expense.id)}" ${isBatchCashSubmitting ? "disabled" : ""}>
            ${CASH_EXPENSE_CURRENCIES.map((currency) => `<option value="${escapeAttribute(currency)}" ${currency === state.currency ? "selected" : ""}>${escapeHtml(currency)}</option>`).join("")}
          </select>
        </td>
        <td>${renderBatchCashExpenseRateAssist(state)}</td>
        <td>
          <select data-batch-expense-account="${escapeAttribute(expense.id)}" ${isBatchCashSubmitting ? "disabled" : ""}>
            ${renderBatchCashExpenseAccountOptions(state)}
          </select>
        </td>
        <td><input data-batch-expense-note="${escapeAttribute(expense.id)}" type="text" value="${escapeAttribute(state.note)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
      </tr>
      ${renderBatchCashExpenseRateRow(state)}
    `;
  }).join("");
  updateBatchCashExpenseTotal();
}

function renderBatchCashExpenseAmountHint(state) {
  if (state.amountSource === "backend") {
    return '<div class="field-hint">提交时按汇率和取整方式确认。</div>';
  }

  if (state.amountSource === "db") {
    return '<div class="field-hint">未手动修改时使用原始金额。</div>';
  }

  return "";
}

function renderBatchCashExpenseRateAssist(state) {
  if (state.currency !== "CNY") {
    return `
      <div class="expense-rate-assist expense-rate-assist--muted">
        <span>JPY 支付不需要汇率</span>
      </div>
    `;
  }

  return `
    <div class="expense-rate-assist expense-rate-assist--compact">
      <div class="expense-rate-assist-theory">
        <span>理论金额</span>
        <span class="expense-rate-assist-value">${escapeHtml(formatTheoreticalCnyAmount(state.theoreticalAmount))}</span>
      </div>
      <div class="expense-rounding-buttons" aria-label="取整方式">
        <button class="button compact-button" title="四舍五入" data-batch-expense-round="${escapeAttribute(state.expense.id)}" data-rounding-mode="round" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>≈</button>
        <button class="button compact-button" title="向上取整" data-batch-expense-round="${escapeAttribute(state.expense.id)}" data-rounding-mode="ceil" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>↑</button>
        <button class="button compact-button" title="向下取整" data-batch-expense-round="${escapeAttribute(state.expense.id)}" data-rounding-mode="floor" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>↓</button>
      </div>
      <div class="expense-rate-assist-status">${escapeHtml(state.rateStatus || rateAssistHint(state))}</div>
    </div>
  `;
}

function renderBatchCashExpenseRateRow(state) {
  if (state.currency !== "CNY") {
    return "";
  }

  const expenseId = state.expense.id;
  return `
    <tr class="expense-batch-cash-rate-row" data-batch-expense-row-id="${escapeAttribute(expenseId)}">
      <td colspan="9">
        <div class="expense-rate-toolbar-card">
          <div class="expense-rate-toolbar-title">
            <strong>CNY / JPY 汇率辅助</strong>
            <span>${escapeHtml(`${expenseObjectName(state.expense)} / ${formatCurrency(state.expense.amount, state.expense.currency)}`)}</span>
          </div>
          <div class="expense-rate-toolbar-controls">
            <span>1 JPY =</span>
            <input data-batch-expense-rate="${escapeAttribute(expenseId)}" type="number" min="0" step="0.0000001" inputmode="decimal" value="${escapeAttribute(state.exchangeRate)}" placeholder="0.0358629" ${isBatchCashSubmitting ? "disabled" : ""}>
            <span>CNY</span>
            <button class="button compact-button" data-batch-expense-rate-fetch="${escapeAttribute(expenseId)}" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>获取今日汇率</button>
          </div>
        </div>
      </td>
    </tr>
  `;
}

function renderBatchCashExpenseRateToolbar() {
  if (!dom.batchCashExpenseRateToolbar) {
    return;
  }

  dom.batchCashExpenseRateToolbar.innerHTML = "";
  dom.batchCashExpenseRateToolbar.hidden = true;
}

function renderBatchCashExpenseAccountOptions(state) {
  const rows = cashEligibleAccounts.filter((account) => (
    account?.is_active === true &&
    account?.allow_school_requests === true &&
    account.currency === state.currency
  ));
  return [
    '<option value="">请选择</option>',
    ...rows.map((account) => (
      `<option value="${escapeAttribute(account.id)}" ${account.id === state.accountId ? "selected" : ""}>${escapeHtml(cashAccountLabel(account))}</option>`
    )),
  ].join("");
}

function handleBatchCashExpenseInput(event) {
  if (!event.target.closest("[data-batch-expense-row-id]")) {
    return;
  }

  const amountInput = event.target.closest("[data-batch-expense-amount]");
  const currencySelect = event.target.closest("[data-batch-expense-currency]");
  const shouldRerender = Boolean(currencySelect);
  const shouldRefreshRateAssist = event.type === "change" && Boolean(
    event.target.closest("[data-batch-expense-rate]")
    || amountInput
  );
  syncBatchCashExpenseRowsFromDom();
  if (amountInput) {
    const expenseId = amountInput.dataset.batchExpenseAmount;
    const state = batchCashExpenseRows.find((row) => row.expense.id === expenseId);
    if (state) {
      state.amountSource = "manual";
      state.roundingMode = "";
    }
  }
  updateBatchCashExpenseDerivedValues();
  refreshBackendBatchCashExpensePreviewAmounts();
  if (shouldRerender) {
    for (const state of batchCashExpenseRows) {
      const account = cashEligibleAccounts.find((row) => row.id === state.accountId);
      if (account?.currency !== state.currency) {
        state.accountId = "";
      }
      if (state.amountSource !== "manual") {
        state.amount = state.currency === expenseOriginalCurrency(state.expense)
          ? String(state.expense.amount ?? "")
          : "";
        state.amountSource = state.currency === expenseOriginalCurrency(state.expense) ? "db" : "";
        state.roundingMode = "";
      }
    }
    renderBatchCashExpenseRows();
  } else if (shouldRefreshRateAssist) {
    renderBatchCashExpenseRows();
  }
  clearBatchCashExpenseError();
}

function refreshBackendBatchCashExpensePreviewAmounts() {
  for (const state of batchCashExpenseRows) {
    if (state.amountSource !== "backend" || !ROUNDING_MODE_LABELS[state.roundingMode]) {
      continue;
    }

    const theoreticalAmount = parseNumberInput(state.theoreticalAmount);
    if (Number.isFinite(theoreticalAmount) && theoreticalAmount > 0) {
      state.amount = String(roundCnyPaymentAmount(theoreticalAmount, state.roundingMode));
    }
  }
}

async function handleBatchCashExpenseClick(event) {
  const fetchButton = event.target.closest("[data-batch-expense-rate-fetch]");
  const roundButton = event.target.closest("[data-batch-expense-round]");
  if (!fetchButton && !roundButton) {
    return;
  }

  event.preventDefault();
  syncBatchCashExpenseRowsFromDom();
  updateBatchCashExpenseDerivedValues();

  const expenseId = fetchButton?.dataset.batchExpenseRateFetch || roundButton?.dataset.batchExpenseRound;
  const state = batchCashExpenseRows.find((row) => row.expense.id === expenseId);
  if (!state || state.currency !== "CNY") {
    return;
  }

  if (fetchButton) {
    await fetchTodayJpyCnyRateForState(state);
    return;
  }

  applyBatchCashExpenseRounding(state, roundButton.dataset.roundingMode);
}

function syncBatchCashExpenseRowsFromDom() {
  for (const state of batchCashExpenseRows) {
    const id = state.expense.id;
    state.amount = dom.batchCashExpenseTableBody.querySelector(`[data-batch-expense-amount="${cssEscape(id)}"]`)?.value ?? state.amount;
    state.paymentDate = dom.batchCashExpenseTableBody.querySelector(`[data-batch-expense-date="${cssEscape(id)}"]`)?.value ?? state.paymentDate;
    state.currency = dom.batchCashExpenseTableBody.querySelector(`[data-batch-expense-currency="${cssEscape(id)}"]`)?.value ?? state.currency;
    state.accountId = dom.batchCashExpenseTableBody.querySelector(`[data-batch-expense-account="${cssEscape(id)}"]`)?.value ?? state.accountId;
    state.note = dom.batchCashExpenseTableBody.querySelector(`[data-batch-expense-note="${cssEscape(id)}"]`)?.value ?? state.note;
    state.exchangeRate = dom.batchCashExpenseRateToolbar?.querySelector(`[data-batch-expense-rate="${cssEscape(id)}"]`)?.value
      ?? dom.batchCashExpenseTableBody.querySelector(`[data-batch-expense-rate="${cssEscape(id)}"]`)?.value
      ?? state.exchangeRate;
  }
  updateBatchCashExpenseTotal();
}

async function submitBatchCashExpenseRequests() {
  if (isBatchCashSubmitting) {
    return;
  }

  const payloads = readBatchCashExpensePayloads();
  if (!payloads) {
    return;
  }

  if (!window.confirm(`确认提交 ${payloads.length} 条 Cash 支付确认请求？Cash 确认后才会生成支出交易。`)) {
    return;
  }

  setBatchCashExpenseSubmitting(true);
  let successCount = 0;
  for (const item of payloads) {
    try {
      await requestCashExpenseConfirmation(item.payload);
      selectedExpenseIds.delete(item.state.expense.id);
      successCount += 1;
    } catch {
    }
    renderBatchCashExpenseRows();
  }
  setBatchCashExpenseSubmitting(false);
  await refreshCurrentExpenseList();

  const failedCount = payloads.length - successCount;
  if (failedCount > 0) {
    showBatchCashExpenseError(`已提交 ${successCount} 条，失败 ${failedCount} 条。请稍后重试或回到支出列表确认 Cash 状态。`);
  } else {
    closeBatchCashExpenseDialog();
    showMessage("success", `已提交 ${successCount} 条 Cash 支付确认请求，等待 Cash 侧确认。`);
  }
}

function readBatchCashExpensePayloads() {
  syncBatchCashExpenseRowsFromDom();
  clearBatchCashExpenseError();
  let hasError = false;
  const payloads = [];

  for (const state of batchCashExpenseRows) {
    const expense = state.expense;
    if (!canRequestCashExpense(expense)) {
      hasError = true;
      continue;
    }

    const actualPaymentAmount = parseNumberInput(state.amount);
    const isCrossCurrency = state.currency !== expenseOriginalCurrency(expense);
    const useBackendAmount = state.amountSource === "backend"
      || (state.amountSource === "db" && !isCrossCurrency);
    const useManualAmount = !useBackendAmount;
    if (useManualAmount && (!Number.isFinite(actualPaymentAmount) || actualPaymentAmount <= 0)) {
      hasError = true;
      continue;
    }

    if (!/^\d{4}-\d{2}-\d{2}$/.test(state.paymentDate || "")) {
      hasError = true;
      continue;
    }

    if (!CASH_EXPENSE_CURRENCIES.includes(state.currency)) {
      hasError = true;
      continue;
    }

    const cashAccount = cashEligibleAccounts.find((account) => account.id === state.accountId);
    if (!cashAccount || cashAccount.currency !== state.currency) {
      hasError = true;
      continue;
    }

    const exchangeRate = isCrossCurrency ? parseOptionalPositiveNumber(state.exchangeRate) : null;
    if (isCrossCurrency && (!Number.isFinite(exchangeRate) || exchangeRate <= 0)) {
      hasError = true;
      continue;
    }
    if (state.amountSource === "backend" && !ROUNDING_MODE_LABELS[state.roundingMode]) {
      hasError = true;
      continue;
    }

    payloads.push({
      state,
      payload: {
        expenseId: expense.id,
        cashAccountId: state.accountId,
        actualPaymentAmount: useBackendAmount ? null : actualPaymentAmount,
        actualPaymentCurrency: state.currency,
        actualPaymentDate: state.paymentDate,
        exchangeRate,
        roundingMode: state.amountSource === "backend" ? state.roundingMode : "",
        note: buildCashExpenseRequestNote(
          expense,
          useBackendAmount ? null : actualPaymentAmount,
          state.currency,
          state.paymentDate,
          state.note,
          rateAssistNote(state)
        ),
      },
    });
  }

  renderBatchCashExpenseRows();
  if (hasError) {
    showBatchCashExpenseError("部分记录缺少必要信息，未提交任何请求。");
    return null;
  }

  if (!payloads.length) {
    showBatchCashExpenseError("没有可提交的支出记录。");
    return null;
  }

  return payloads;
}

function renderCreateCategoryOptions() {
  const options = ['<option value="">请选择支出分类</option>'];
  for (const category of CREATE_EXPENSE_CATEGORY_OPTIONS) {
    options.push(`<option value="${escapeAttribute(category)}">${escapeHtml(expenseCategoryLabel(category))}</option>`);
  }
  dom.createExpenseCategorySelect.innerHTML = options.join("");
}

function renderCreateAccountOptions() {
  const selectedValue = dom.createExpenseAccountSelect.value;
  const options = ['<option value="">请选择付款账户</option>'];
  for (const account of filteredCreateAccounts()) {
    options.push(`<option value="${escapeAttribute(account.id)}">${escapeHtml(createAccountLabel(account))}</option>`);
  }
  dom.createExpenseAccountSelect.innerHTML = options.join("");
  if (filteredCreateAccounts().some((account) => account.id === selectedValue)) {
    dom.createExpenseAccountSelect.value = selectedValue;
  }
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

function createAccountLabel(account) {
  const accountKind = account.is_company_account ? "公司账户" : "个人垫付账户";
  return [
    account.name || account.account_code || account.id,
    account.currency || "-",
    formatCurrency(account.current_balance, account.currency),
    accountKind,
  ].filter(Boolean).join(" / ");
}

function setCreateSubmitting(isSubmitting) {
  isCreateSubmitting = isSubmitting;
  dom.createExpenseSubmitButton.disabled = isSubmitting;
  dom.createExpenseCancelButton.disabled = isSubmitting;
  dom.createExpenseSubmitButton.textContent = isSubmitting
    ? (createExpenseHandlingMode() === "cash" ? "正在保存待支付记录..." : "正在保存 School 支出...")
    : (createExpenseHandlingMode() === "cash" ? "保存待支付支出" : "保存 School 支出");
}

function clearCreateErrors() {
  dom.createExpenseError.textContent = "";
  dom.createExpenseError.classList.add("is-hidden");
  for (const fieldId of CREATE_EXPENSE_FIELD_IDS) {
    clearCreateFieldInvalid(fieldId);
  }
}

function showCreateError(message, fieldIds = []) {
  dom.createExpenseError.textContent = message;
  dom.createExpenseError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCreateFieldInvalid(fieldId, true);
  }
  dom.createExpenseDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function createFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("金额")) fields.push("amount");
  if (text.includes("支出日期")) fields.push("expenseDate");
  if (text.includes("支出分类") || text.includes("老师工资支出")) fields.push("expenseCategory");
  if (text.includes("支出内容")) fields.push("description");
  if (text.includes("付款账户")) fields.push("account");
  if (text.includes("币种")) fields.push(createExpenseHandlingMode() === "cash" ? "currency" : "account");
  if (text.includes("汇率")) fields.push("exchangeRate");
  if (text.includes("支付方式")) fields.push("paymentMethod");
  if (text.includes("报销状态")) fields.push("reimbursementStatus");
  if (text.includes("收据状态")) fields.push("receiptStatus");
  return fields;
}

function setCreateFieldInvalid(fieldId, invalid) {
  const field = dom.createExpenseDialog.querySelector(`[data-create-expense-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function clearCreateFieldInvalid(fieldId) {
  setCreateFieldInvalid(fieldId, false);
}

function hideCreateErrorIfClean() {
  const hasInvalidField = Boolean(dom.createExpenseDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.createExpenseError.textContent = "";
    dom.createExpenseError.classList.add("is-hidden");
  }
}

function filterExpenseRecords(rows, filters) {
  return rows.filter((row) => {

    if (filters.accountId && row.account_id !== filters.accountId) {
      return false;
    }

    if (filters.studentId && row.student_id !== filters.studentId) {
      return false;
    }

    if (filters.teacherId && (!isTeacherWageExpense(row) || row.teacher_id !== filters.teacherId)) {
      return false;
    }

    if (filters.currency && row.currency !== filters.currency) {
      return false;
    }

    return true;
  });
}

function isTeacherWageExpense(row) {
  return row?.source_type === "teacher_wage" || row?.expense_category === "teacher_wage";
}

function canRequestCashExpense(row) {
  if (!isActiveAdmin()) return false;
  if (!row?.id) return false;
  if (row.app_type !== "school") return false;
  if (!["manual_cash", "teacher_wage"].includes(row.source_type)) return false;
  if (row.status !== "pending") return false;
  if (row.reversed_at || row.reversal_account_transaction_id) return false;
  if (row.cash_transaction_id) return false;
  return !["pending", "approved", "synced"].includes(row.cash_request_status || "");
}

function cashRequestNotAllowedMessage(row) {
  if (!row) return "支出记录不存在，请刷新后重试。";
  if (!isActiveAdmin()) return "仅已启用的管理员账号可以提交 Cash。";
  if (row.app_type !== "school") return "只能提交 School 支出记录。";
  if (!["manual_cash", "teacher_wage"].includes(row.source_type)) return "该支出来源不允许提交 Cash。";
  if (row.status !== "pending") return "只有待支付支出记录可以提交 Cash 支付确认。";
  if (row.reversed_at || row.reversal_account_transaction_id) return "已撤销支出不能提交 Cash 支付确认。";
  if (row.cash_transaction_id) return "该支出记录已经有 Cash transaction。";
  if (row.cash_request_status === "pending") return "该支出记录已有待确认 Cash request。";
  if (row.cash_request_status === "approved" || row.cash_request_status === "synced") return "该支出记录已同步到 Cash。";
  return "";
}

function cashRequestDisabledTitle(row) {
  if (row?.status !== "pending" && !row?.cash_transaction_id) {
    return "已支付支出不能提交 Cash。只有待支付支出可提交 Cash。";
  }
  return cashRequestNotAllowedMessage(row);
}

function renderExpenseStatusCash(row) {
  const businessStatus = expenseListStatus(row);
  return `
    <div class="expense-cash-status-cell expense-status-cash-cell">
      <span class="status-badge ${escapeAttribute(statusClass(businessStatus))}">${escapeHtml(expenseStatusLabel(businessStatus))}</span>
      <span class="expense-cash-substatus">${renderCashRequestStatus(row)}</span>
    </div>
  `;
}

function expenseListStatus(row) {
  if (row?.reversed_at || row?.reversal_account_transaction_id || row?.status === "reversed") {
    return "reversed";
  }

  return row?.status || "";
}

function renderCashRequestStatus(row) {
  if (!row?.cash_request_status && !row?.cash_transaction_id) {
    return '<span class="status-badge status-neutral">Cash未提交</span>';
  }

  const status = row.cash_transaction_id && !row.cash_request_status
    ? "synced"
    : row.cash_request_status;
  return `
    <span class="status-badge ${escapeAttribute(cashRequestStatusClass(status))}">${escapeHtml(cashRequestStatusLabel(status))}</span>
    <span class="expense-cash-hint">${escapeHtml(cashRequestStatusHint(status))}</span>
  `;
}

function cashRequestStatusHint(value) {
  if (value === "pending" || value === "pending_cash_request" || value === "awaiting_cash_confirmation") return "请求已生成";
  if (value === "approved" || value === "synced") return "已生成流水";
  if (value === "rejected" || value === "cash_rejected" || value === "failed") return "需要处理";
  return "";
}

function cashRequestStatusLabel(value) {
  return CASH_REQUEST_STATUS_LABELS[value] || displayValue(value);
}

function cashRequestStatusClass(value) {
  if (value === "pending" || value === "pending_cash_request" || value === "awaiting_cash_confirmation") return "status-pending";
  if (value === "approved" || value === "synced") return "status-paid";
  if (value === "rejected" || value === "cash_rejected" || value === "failed") return "status-cancelled";
  return "status-neutral";
}

function teacherWageExpenseIds(rows) {
  return rows
    .filter((row) => row.expense_category === "teacher_wage")
    .map((row) => row.id)
    .filter(Boolean);
}

function groupPaymentRequestsByExpenseId(rows) {
  const grouped = new Map();

  for (const row of rows) {
    if (!row.paid_expense_id) {
      continue;
    }

    if (!grouped.has(row.paid_expense_id)) {
      grouped.set(row.paid_expense_id, []);
    }

    grouped.get(row.paid_expense_id).push(row);
  }

  return grouped;
}

function paymentRequestForExpense(expenseId) {
  const requests = paymentRequestsByExpenseId.get(expenseId) || [];
  return requests[0] || null;
}

function wagePaymentStatusKey(row) {
  if (row.expense_category !== "teacher_wage") {
    return "";
  }

  return paymentRequestForExpense(row.id)?.status || "unlinked";
}

function renderWagePaymentStatus(row) {
  const status = wagePaymentStatusKey(row);
  if (!status) {
    return "-";
  }

  return `<span class="status-badge ${escapeAttribute(wagePaymentStatusClass(status))}">${escapeHtml(wagePaymentStatusLabel(status))}</span>`;
}

function renderAttachmentStatus(row) {
  const count = attachmentCountsByExpenseId.get(row.id) || 0;
  if (!count) {
    return '<span class="status-badge status-neutral">无</span>';
  }

  return `<span class="status-badge status-active">${escapeHtml(`${count} 个`)}</span>`;
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

function accountNameById(id) {
  const account = accounts.find((item) => item.id === id);
  if (!account) {
    return id ? "未知" : "未设置";
  }

  return accountName(account);
}

function teacherNameById(id) {
  const teacher = teachers.find((item) => item.id === id);
  if (!teacher) {
    return id ? "未知" : "-";
  }

  return teacherName(teacher);
}

function expenseObjectName(row) {
  const payeeName = safeText(row?.payee_name_snapshot);
  if (payeeName) {
    return payeeName;
  }

  if (row?.teacher_id) {
    return teacherNameById(row.teacher_id);
  }

  if (row?.student_id) {
    return studentNameById(row.student_id);
  }

  return displayValue(row?.description);
}

function relatedObjectLabel(row) {
  if (row?.teacher_id) {
    return teacherNameById(row.teacher_id);
  }

  if (row?.student_id) {
    return studentNameById(row.student_id);
  }

  return "-";
}

function formatExpenseListAmount(row) {
  if (!row) {
    return "-";
  }

  return formatCurrency(row.amount, row.currency);
}

function businessListText(value, emptyText = "-") {
  const text = safeText(value);
  if (!text) {
    return emptyText;
  }

  return isSystemMigrationNote(text) ? "无业务备注" : text;
}

function isSystemMigrationNote(value) {
  return /migrated_to_|canonical_flow|payment_request_id=|migration/i.test(safeText(value));
}

function studentNameById(id) {
  const student = students.find((item) => item.id === id);
  if (!student) {
    return id ? "未知" : "-";
  }

  return studentName(student);
}

function accountName(account) {
  const name = safeText(account.name) || "未设置";
  const currency = safeText(account.currency);
  return currency ? `${name} / ${currency}` : name;
}

function cashAccountLabel(account) {
  return [
    account.name || account.id,
    account.currency || "-",
    account.account_type,
  ].filter(Boolean).join(" / ");
}

function teacherName(teacher) {
  return safeText(teacher.display_name || teacher.name) || "未设置";
}

function studentName(student) {
  return safeText(student.display_name || student.name) || "未设置";
}

function expenseCategoryLabel(value) {
  return EXPENSE_CATEGORY_LABELS[value] || displayValue(value);
}

function paymentMethodLabel(value) {
  return PAYMENT_METHOD_LABELS[value] || displayValue(value);
}

function expenseStatusLabel(value) {
  return EXPENSE_STATUS_LABELS[value] || displayValue(value);
}

function reimbursementStatusLabel(value, expenseCategory = "") {
  if (expenseCategory === "teacher_wage") {
    if (value === "pending") {
      return "工资垫付待清算";
    }
    if (value === "not_required") {
      return "无需清算（公司账户支付）";
    }
  }

  return REIMBURSEMENT_STATUS_LABELS[value] || displayValue(value);
}

function wagePaymentStatusLabel(value) {
  return WAGE_PAYMENT_STATUS_LABELS[value] || displayValue(value);
}

function statusClass(status) {
  if (status === "paid") {
    return "status-paid";
  }

  if (status === "reversed" || status === "void" || status === "voided" || status === "cancelled") {
    return "status-cancelled";
  }

  if (status === "pending") {
    return "status-pending";
  }

  return "status-neutral";
}

function wagePaymentStatusClass(status) {
  if (status === "paid") {
    return "status-paid";
  }

  if (status === "reversed" || status === "void" || status === "cancelled") {
    return "status-cancelled";
  }

  if (status === "pending") {
    return "status-pending";
  }

  return "status-neutral";
}

function formatDateOnly(value) {
  return safeText(value) || "-";
}

function defaultCashExpenseNote(expense) {
  const standardParts = [
    expenseCategoryLabel(expense.expense_category),
    expenseObjectName(expense),
    expense.year_month,
  ].map((value) => safeText(value)).filter((value) => value && value !== "-");
  const extraNote = defaultCashExpenseExtraNote(expense.description, standardParts);
  return [
    standardParts.join(" / "),
    extraNote,
  ].filter(Boolean).join(" / ");
}

function defaultCashExpenseExtraNote(value, standardParts) {
  const text = safeText(value).trim();
  if (!text || isSystemMigrationNote(text)) {
    return "";
  }

  let extra = text;
  for (const part of defaultCashExpenseDuplicateTerms(standardParts)) {
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

function defaultCashExpenseDuplicateTerms(standardParts) {
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

function buildCashExpenseRequestNote(expense, amount, currency, paymentDate, baseNote, rateNote = "") {
  const base = safeText(baseNote).trim();
  const actualAmountText = Number.isFinite(Number(amount))
    ? `实际支付${formatCurrency(amount, currency)}`
    : `实际支付金额按提交规则计算，币种${currency}`;
  const requiredText = [
    `${expenseObjectName(expense)}，实际支付日${paymentDate}，${actualAmountText}`,
    rateNote,
  ].filter(Boolean).join("；");
  if (!base) {
    return requiredText;
  }
  if (base.includes("实际支付日")) {
    return rateNote && !base.includes("参考汇率") ? `${base}；${rateNote}` : base;
  }
  return `${base}；${requiredText}`;
}

function updateBatchCashExpenseDerivedValues() {
  for (const state of batchCashExpenseRows) {
    updateBatchCashExpenseDerivedValue(state);
  }
}

function updateBatchCashExpenseDerivedValue(state) {
  if (state.currency !== "CNY") {
    state.theoreticalAmount = "";
    state.roundingMode = "";
    state.rateStatus = "";
    return;
  }

  const rate = parseNumberInput(state.exchangeRate);
  const jpyAmount = originalJpyAmount(state.expense);
  if (!Number.isFinite(rate) || rate <= 0 || !Number.isFinite(jpyAmount) || jpyAmount <= 0) {
    state.theoreticalAmount = "";
    return;
  }

  state.theoreticalAmount = formatDecimal(jpyAmount * rate, 2);
}

async function fetchTodayJpyCnyRateForState(state) {
  try {
    const rate = await fetchLatestJpyCnyRate();
    state.exchangeRate = formatRateValue(rate);
    updateBatchCashExpenseDerivedValue(state);
    state.rateStatus = "已获取今日参考汇率，可取整或手动修改金额。";
    clearBatchCashExpenseError();
  } catch (error) {
    state.rateStatus = "汇率获取失败，可手动输入参考汇率。";
    showBatchCashExpenseError(`今日汇率获取失败：${error.message || error}。可手动输入金额继续。`);
  } finally {
    renderBatchCashExpenseRows();
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

function applyBatchCashExpenseRounding(state, mode) {
  updateBatchCashExpenseDerivedValue(state);
  const theoreticalAmount = parseNumberInput(state.theoreticalAmount);
  if (!Number.isFinite(theoreticalAmount) || theoreticalAmount <= 0) {
    state.rateStatus = "请先获取或输入有效参考汇率。";
    renderBatchCashExpenseRows();
    return;
  }

  const roundedAmount = roundCnyPaymentAmount(theoreticalAmount, mode);
  state.amount = String(roundedAmount);
  state.amountSource = "backend";
  state.roundingMode = ROUNDING_MODE_LABELS[mode] ? mode : "";
  state.rateStatus = `${ROUNDING_MODE_LABELS[mode] || "取整"}已预览实际支付金额，提交时按相同规则确认，仍可手动修改。`;
  renderBatchCashExpenseRows();
}

function updateBatchCashExpenseTotal() {
  if (!dom.batchCashExpenseTotal) {
    return;
  }

  dom.batchCashExpenseTotal.textContent = batchCashExpenseTotalLabel(batchCashExpenseRows);
}

function batchCashExpenseTotalLabel(rows) {
  const totals = new Map();
  for (const state of rows || []) {
    const currency = state?.currency;
    if (!CASH_EXPENSE_CURRENCIES.includes(currency)) {
      continue;
    }

    const amount = parseNumberInput(state.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      continue;
    }

    totals.set(currency, (totals.get(currency) || 0) + amount);
  }

  const parts = CASH_EXPENSE_CURRENCIES
    .filter((currency) => totals.has(currency))
    .map((currency) => `${currency} ${formatBatchCashTotalAmount(totals.get(currency), currency)}`);

  return `本次提交合计：${parts.length ? parts.join(" / ") : "-"}`;
}

function formatBatchCashTotalAmount(amount, currency) {
  if (!Number.isFinite(amount)) {
    return "-";
  }

  if (currency === "JPY") {
    return Math.round(amount).toLocaleString("en-US");
  }

  const rounded = Math.round(amount * 100) / 100;
  return rounded.toLocaleString("en-US", {
    minimumFractionDigits: Number.isInteger(rounded) ? 0 : 2,
    maximumFractionDigits: 2,
  });
}

function roundCnyPaymentAmount(amount, mode) {
  if (mode === "ceil") {
    return Math.ceil(amount);
  }

  if (mode === "floor") {
    return Math.floor(amount);
  }

  return Math.round(amount);
}

function originalJpyAmount(expense) {
  const amountJpy = Number(expense?.amount_jpy);
  if (Number.isFinite(amountJpy) && amountJpy > 0) {
    return amountJpy;
  }

  const amount = Number(expense?.amount);
  if (expense?.currency === "JPY" && Number.isFinite(amount) && amount > 0) {
    return amount;
  }

  return NaN;
}

function expenseOriginalCurrency(expense) {
  return CASH_EXPENSE_CURRENCIES.includes(expense?.currency) ? expense.currency : "";
}

function formatTheoreticalCnyAmount(value) {
  const amount = parseNumberInput(value);
  return Number.isFinite(amount) && amount > 0 ? `${formatDecimal(amount, 2)} CNY` : "-";
}

function rateAssistHint(state) {
  if (!Number.isFinite(originalJpyAmount(state.expense))) {
    return "缺少 JPY 原始金额，可手动输入实际支付金额。";
  }

  return "获取或输入汇率后可计算理论金额。";
}

function rateAssistNote(state) {
  if (state.currency !== "CNY") {
    return "";
  }

  const rate = parseNumberInput(state.exchangeRate);
  const theoreticalAmount = parseNumberInput(state.theoreticalAmount);
  const parts = [];
  if (Number.isFinite(rate) && rate > 0) {
    parts.push(`参考汇率 CNY/JPY ${formatRateValue(rate)}`);
  }
  if (state.amountSource === "backend") {
    parts.push("实际支付金额按提交规则计算");
  } else if (Number.isFinite(theoreticalAmount) && theoreticalAmount > 0) {
    parts.push(`理论金额 ${formatDecimal(theoreticalAmount, 2)} CNY`);
  }
  if (ROUNDING_MODE_LABELS[state.roundingMode]) {
    parts.push(`取整方式 ${ROUNDING_MODE_LABELS[state.roundingMode]}`);
  }

  return parts.join("，");
}

function formatRateValue(value) {
  const rate = Number(value);
  return Number.isFinite(rate) ? rate.toFixed(7).replace(/0+$/, "").replace(/\.$/, "") : "";
}

function formatDecimal(value, decimals) {
  const number = Number(value);
  return Number.isFinite(number) ? number.toFixed(decimals) : "";
}

function parseNumberInput(value) {
  const normalized = String(value ?? "").replace(/,/g, "").trim();
  if (!normalized) {
    return NaN;
  }
  return Number(normalized);
}

function parseOptionalPositiveNumber(value) {
  const number = parseNumberInput(value);
  return Number.isFinite(number) && number > 0 ? number : null;
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

function expenseDetailUrl(expenseId) {
  const params = new URLSearchParams();
  params.set("id", safeText(expenseId));
  const filters = readFilters();
  if (filters?.month) {
    const [year, monthPart] = filters.month.split("-");
    params.set("year", year);
    params.set("month", monthPart);
    writeStudentCandidateQuery(params, filters);
    setOptionalQuery(params, "teacher_id", filters.teacherId);
    setOptionalQuery(params, "account_id", filters.accountId);
    setOptionalQuery(params, "currency", filters.currency);
  }
  return `./expense-detail.html?${params.toString()}`;
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
}

function showMessage(type, text) {
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = text;
}

function setBatchCashExpenseSubmitting(isSubmitting) {
  isBatchCashSubmitting = isSubmitting;
  dom.batchCashExpenseSubmitButton.disabled = isSubmitting;
  dom.batchCashExpenseCancelButton.disabled = isSubmitting;
  dom.batchCashExpenseSubmitButton.textContent = isSubmitting ? "提交中..." : "提交所选 Cash 支付确认";
  renderBatchCashExpenseRows();
}

function clearBatchCashExpenseError() {
  dom.batchCashExpenseError.textContent = "";
  dom.batchCashExpenseError.classList.add("is-hidden");
}

function showBatchCashExpenseError(message) {
  dom.batchCashExpenseError.textContent = message;
  dom.batchCashExpenseError.classList.remove("is-hidden");
  dom.batchCashExpenseDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
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
