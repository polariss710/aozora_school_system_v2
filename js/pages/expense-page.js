import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createExpenseRecord,
  fetchExpenseAttachmentCounts,
  fetchExpenseLookups,
  fetchExpensePaymentRequests,
  fetchExpenseRecords,
  requestCashExpenseConfirmation,
} from "../api/expense-api.js";
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

const DEFAULT_FILTERS = {
  studentId: "",
  teacherId: "",
  businessEntityId: "",
  accountId: "",
  currency: "",
};

const EXPENSE_STATUS_LABELS = {
  paid: "已支付",
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
  "businessEntity",
  "account",
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
let batchCashExpenseRows = [];
let isBatchCashSubmitting = false;
let initialMonth = "";

export function initExpensePage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  initialMonth = initialYearMonthFromUrl();
  setDefaultFilters();
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
  dom.teacherSelect = document.querySelector("#expenseTeacherSelect");
  dom.businessEntitySelect = document.querySelector("#expenseBusinessEntitySelect");
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
  dom.batchCashExpenseTableBody = document.querySelector("#batchCashExpenseTableBody");
  dom.batchCashExpenseSubmitButton = document.querySelector("#batchCashExpenseSubmitButton");
  dom.batchCashExpenseCancelButton = document.querySelector("#batchCashExpenseCancelButton");
  dom.createExpenseDialog = document.querySelector("#createExpenseDialog");
  dom.createExpenseError = document.querySelector("#createExpenseError");
  dom.createExpenseDateInput = document.querySelector("#createExpenseDateInput");
  dom.createExpenseBusinessEntitySelect = document.querySelector("#createExpenseBusinessEntitySelect");
  dom.createExpenseAccountSelect = document.querySelector("#createExpenseAccountSelect");
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
  dom.yearFilter.addEventListener("change", updateMonthNavigationFromCurrentSelection);
  dom.monthFilter.addEventListener("change", updateMonthNavigationFromCurrentSelection);

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
  dom.createExpenseCancelButton.addEventListener("click", closeCreateExpenseDialog);
  dom.createExpenseSubmitButton.addEventListener("click", submitCreateExpense);
  dom.createExpenseBusinessEntitySelect.addEventListener("change", () => {
    renderCreateAccountOptions();
    updateCreateReimbursementDefault();
    clearCreateFieldInvalid("businessEntity");
    hideCreateErrorIfClean();
  });
  dom.createExpenseAccountSelect.addEventListener("change", () => {
    updateCreateReimbursementDefault();
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

function setDefaultFilters(overrides = null) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, overrides?.month || initialMonth || currentYearMonth());
  dom.studentSelect.value = DEFAULT_FILTERS.studentId;
  dom.teacherSelect.value = DEFAULT_FILTERS.teacherId;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.accountSelect.value = DEFAULT_FILTERS.accountId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  updateMonthScopedNavigation(getYearMonthSelectValue(dom.yearFilter, dom.monthFilter));
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载支出记录数据...");

  try {
    const lookups = await fetchExpenseLookups();
    businessEntities = lookups.businessEntities;
    accounts = lookups.accounts;
    teachers = lookups.teachers;
    students = lookups.students;
    renderMasterOptions();
    const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter) || currentYearMonth();
    await loadExpenseMonth(month);
    updateUrlMonthParams(month);
    updateMonthScopedNavigation(month);
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

  updateUrlMonthParams(filters.month);
  updateMonthScopedNavigation(filters.month);

  if (filters.month !== loadedMonth) {
    setLoading(true);
    showMessage("info", "正在加载支出记录...");

    try {
      await loadExpenseMonth(filters.month);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "支出记录已加载。");
    } catch (error) {
      expenseRecords = [];
      paymentRequestsByExpenseId = new Map();
      attachmentCountsByExpenseId = new Map();
      loadedMonth = "";
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
    teacherId: dom.teacherSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    accountId: dom.accountSelect.value,
    currency: dom.currencySelect.value,
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.studentSelect.value = filters.studentId;
  dom.teacherSelect.value = filters.teacherId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.accountSelect.value = filters.accountId;
  dom.currencySelect.value = filters.currency;
  updateMonthNavigationFromCurrentSelection();
}

function updateMonthNavigationFromCurrentSelection() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    return;
  }
  updateUrlMonthParams(month);
  updateMonthScopedNavigation(month);
}

function renderMasterOptions() {
  renderEntityOptions(dom.studentSelect, students, studentName);
  renderEntityOptions(dom.teacherSelect, teachers, teacherName, "全部老师");
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
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
  renderedExpenseRows = rows;
  pruneSelectedExpenseIds();
  dom.expenseCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    updateExpenseBatchControls();
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td>${renderExpenseSelectionCell(row)}</td>
      <td class="action-cell">${renderExpenseRowActions(row)}</td>
      <td class="expense-nowrap">${escapeHtml(formatDateOnly(row.expense_date))}</td>
      <td class="expense-nowrap">${escapeHtml(formatMonth(row.year_month))}</td>
      <td><span class="status-badge status-neutral">${escapeHtml(expenseCategoryLabel(row.expense_category))}</span></td>
      <td>${escapeHtml(businessNameById(row.business_entity_id))}</td>
      <td>${escapeHtml(accountNameById(row.account_id))}</td>
      <td>${escapeHtml(teacherNameById(row.teacher_id))}</td>
      <td class="expense-description-cell">${escapeHtml(displayValue(row.description))}</td>
      <td class="expense-nowrap">${escapeHtml(displayValue(row.currency))}</td>
      <td class="number-cell expense-nowrap">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
      <td class="number-cell expense-nowrap">${escapeHtml(formatCurrency(row.amount_jpy, "JPY"))}</td>
      <td class="number-cell expense-nowrap">${escapeHtml(formatCurrency(row.amount_cny, "CNY"))}</td>
      <td class="number-cell expense-nowrap">${escapeHtml(displayValue(row.exchange_rate))}</td>
      <td>${escapeHtml(paymentMethodLabel(row.payment_method))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(expenseStatusLabel(row.status))}</span></td>
      <td>${renderCashRequestStatus(row)}</td>
      <td>${renderWagePaymentStatus(row)}</td>
      <td>${escapeHtml(displayValue(row.receipt_status))}</td>
      <td>${escapeHtml(reimbursementStatusLabel(row.reimbursement_status, row.expense_category))}</td>
      <td class="expense-nowrap">${renderAttachmentStatus(row)}</td>
      <td class="expense-note-cell">${escapeHtml(displayValue(row.note))}</td>
      <td class="expense-nowrap">${escapeHtml(formatDate(row.created_at))}</td>
      <td class="expense-nowrap">${escapeHtml(formatDate(row.updated_at))}</td>
    </tr>
  `).join("");
  updateExpenseBatchControls();
}

function renderExpenseSelectionCell(row) {
  const selectable = canRequestCashExpense(row);
  return `
    <input
      type="checkbox"
      data-expense-select-id="${escapeAttribute(row.id)}"
      aria-label="选择支出记录 ${escapeAttribute(expenseObjectName(row))}"
      ${selectable ? "" : "disabled"}
      ${selectedExpenseIds.has(row.id) ? "checked" : ""}
    >
  `;
}

function renderExpenseRowActions(row) {
  const cashButton = canRequestCashExpense(row)
    ? `<button class="table-action-button" type="button" data-expense-cash-request-id="${escapeAttribute(row.id)}">提交 Cash 支付确认</button>`
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

  clearCreateErrors();
  setCreateSubmitting(false);

  const filters = readFilters();
  const activeBusinessEntities = businessEntities.filter((entity) => entity.is_active !== false);
  const defaultBusinessEntityId = filters?.businessEntityId || "";
  const defaultAccountId = filters?.accountId || "";

  dom.createExpenseDateInput.value = currentDate();
  dom.createExpenseAmountInput.value = "";
  dom.createExpenseDescriptionInput.value = "";
  dom.createExpensePaymentMethodSelect.value = "";
  dom.createExpenseReceiptStatusSelect.value = "待确认";
  dom.createExpenseTaxCategoryInput.value = "待确认";
  dom.createExpenseExchangeRateInput.value = "";
  dom.createExpenseNoteInput.value = "";
  renderCreateCategoryOptions();

  renderCreateBusinessEntityOptions(activeBusinessEntities);
  dom.createExpenseBusinessEntitySelect.value = activeBusinessEntities.some((entity) => entity.id === defaultBusinessEntityId)
    ? defaultBusinessEntityId
    : "";

  renderCreateAccountOptions();
  dom.createExpenseAccountSelect.value = filteredCreateAccounts().some((account) => account.id === defaultAccountId)
    ? defaultAccountId
    : "";

  updateCreateReimbursementDefault();

  dom.createExpenseDialog.classList.remove("is-hidden");
  dom.createExpenseDialog.setAttribute("aria-hidden", "false");
}

function closeCreateExpenseDialog() {
  if (isCreateSubmitting) {
    return;
  }

  dom.createExpenseDialog.classList.add("is-hidden");
  dom.createExpenseDialog.setAttribute("aria-hidden", "true");
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
  const expenseDate = dom.createExpenseDateInput.value;
  if (!expenseDate) {
    showCreateError("请选择支出日期。", ["expenseDate"]);
    return null;
  }

  const businessEntityId = dom.createExpenseBusinessEntitySelect.value;
  if (!businessEntityId) {
    showCreateError("请选择业务归属。", ["businessEntity"]);
    return null;
  }

  const accountId = dom.createExpenseAccountSelect.value;
  if (!accountId) {
    showCreateError("请选择付款账户。", ["account"]);
    return null;
  }

  const account = accounts.find((item) => item.id === accountId);
  if (!account || account.is_active !== true || account.app_type !== "school") {
    showCreateError("付款账户无效或已停用。", ["account"]);
    return null;
  }

  if (account.business_entity_id !== businessEntityId) {
    showCreateError("付款账户与业务归属不一致。", ["account"]);
    return null;
  }

  if (!account.currency) {
    showCreateError("付款账户缺少币种。", ["account"]);
    return null;
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

  const paymentMethod = dom.createExpensePaymentMethodSelect.value;
  if (!CREATE_PAYMENT_METHOD_OPTIONS.includes(paymentMethod)) {
    showCreateError("请选择支付方式。", ["paymentMethod"]);
    return null;
  }

  const receiptStatus = dom.createExpenseReceiptStatusSelect.value;
  if (!CREATE_RECEIPT_STATUS_OPTIONS.includes(receiptStatus)) {
    showCreateError("收据状态无效。", ["receiptStatus"]);
    return null;
  }

  const reimbursementStatus = dom.createExpenseReimbursementStatusSelect.value;
  if (!CREATE_REIMBURSEMENT_STATUS_OPTIONS.includes(reimbursementStatus)) {
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
    expenseDate,
    businessEntityId,
    accountId,
    expenseCategory,
    description,
    currency: account.currency,
    amount,
    exchangeRate,
    paymentMethod,
    isBusinessExpense: true,
    taxCategory: dom.createExpenseTaxCategoryInput.value.trim(),
    receiptStatus,
    reimbursementStatus,
    teacherId: null,
    studentId: null,
    note: dom.createExpenseNoteInput.value.trim(),
  };
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

  try {
    await ensureCashEligibleAccountsLoaded();
  } catch (error) {
    showMessage("error", `Cash System 账户读取失败：${error.message || error}`);
    return;
  }

  batchCashExpenseRows = targets.map((expense) => ({
    expense,
    amount: expense.amount ?? "",
    currency: expense.currency || "JPY",
    paymentDate: currentJapanDate(),
    accountId: "",
    note: defaultCashExpenseNote(expense),
    exchangeRate: "",
    theoreticalAmount: "",
    roundingMode: "",
    rateStatus: "",
    result: "",
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
  dom.batchCashExpenseTableBody.innerHTML = batchCashExpenseRows.map((state) => {
    const expense = state.expense;
    return `
      <tr data-batch-expense-row-id="${escapeAttribute(expense.id)}">
        <td>${escapeHtml(expenseObjectName(expense))}</td>
        <td class="expense-nowrap">${escapeHtml(formatMonth(expense.year_month))}</td>
        <td><input data-batch-expense-date="${escapeAttribute(expense.id)}" type="date" value="${escapeAttribute(state.paymentDate)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
        <td class="number-cell expense-nowrap">${escapeHtml(formatCurrency(expense.amount, expense.currency))}</td>
        <td><input data-batch-expense-amount="${escapeAttribute(expense.id)}" type="number" min="0" step="0.01" inputmode="decimal" value="${escapeAttribute(state.amount)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
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
        <td>${escapeHtml(state.result || "-")}</td>
      </tr>
    `;
  }).join("");
}

function renderBatchCashExpenseRateAssist(state) {
  const expenseId = state.expense.id;
  if (state.currency !== "CNY") {
    return '<span class="state-text">JPY 支付不需要汇率</span>';
  }

  return `
    <div class="expense-rate-assist">
      <div class="expense-rate-assist-row">
        <span class="expense-rate-assist-label">CNY/JPY</span>
        <input data-batch-expense-rate="${escapeAttribute(expenseId)}" type="number" min="0" step="0.0000001" inputmode="decimal" value="${escapeAttribute(state.exchangeRate)}" placeholder="0.0358629" ${isBatchCashSubmitting ? "disabled" : ""}>
        <button class="button compact-button" data-batch-expense-rate-fetch="${escapeAttribute(expenseId)}" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>获取今日汇率</button>
      </div>
      <div class="expense-rate-assist-row">
        <span class="expense-rate-assist-label">理论</span>
        <span class="expense-rate-assist-value">${escapeHtml(formatTheoreticalCnyAmount(state.theoreticalAmount))}</span>
      </div>
      <div class="expense-rounding-buttons" aria-label="取整方式">
        <button class="button compact-button" data-batch-expense-round="${escapeAttribute(expenseId)}" data-rounding-mode="round" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>四舍五入</button>
        <button class="button compact-button" data-batch-expense-round="${escapeAttribute(expenseId)}" data-rounding-mode="ceil" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>向上取整</button>
        <button class="button compact-button" data-batch-expense-round="${escapeAttribute(expenseId)}" data-rounding-mode="floor" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>向下取整</button>
      </div>
      <div class="expense-rate-assist-status">${escapeHtml(state.rateStatus || rateAssistHint(state))}</div>
    </div>
  `;
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

  const shouldRerender = Boolean(event.target.closest("[data-batch-expense-currency]"));
  const shouldRefreshRateAssist = event.type === "change" && Boolean(
    event.target.closest("[data-batch-expense-rate]")
    || event.target.closest("[data-batch-expense-amount]")
  );
  syncBatchCashExpenseRowsFromDom();
  updateBatchCashExpenseDerivedValues();
  if (shouldRerender) {
    for (const state of batchCashExpenseRows) {
      const account = cashEligibleAccounts.find((row) => row.id === state.accountId);
      if (account?.currency !== state.currency) {
        state.accountId = "";
      }
    }
    renderBatchCashExpenseRows();
  } else if (shouldRefreshRateAssist) {
    renderBatchCashExpenseRows();
  }
  clearBatchCashExpenseError();
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
    state.exchangeRate = dom.batchCashExpenseTableBody.querySelector(`[data-batch-expense-rate="${cssEscape(id)}"]`)?.value ?? state.exchangeRate;
  }
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
      item.state.result = "已提交";
      selectedExpenseIds.delete(item.state.expense.id);
      successCount += 1;
    } catch (error) {
      item.state.result = `失败：${error.message || error}`;
    }
    renderBatchCashExpenseRows();
  }
  setBatchCashExpenseSubmitting(false);
  await refreshCurrentExpenseList();

  const failedCount = payloads.length - successCount;
  if (failedCount > 0) {
    showBatchCashExpenseError(`已提交 ${successCount} 条，失败 ${failedCount} 条。请查看每行结果。`);
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
    state.result = "";
    if (!canRequestCashExpense(expense)) {
      state.result = cashRequestNotAllowedMessage(expense) || "当前状态不可提交";
      hasError = true;
      continue;
    }

    const actualPaymentAmount = parseNumberInput(state.amount);
    if (!Number.isFinite(actualPaymentAmount) || actualPaymentAmount <= 0) {
      state.result = "请输入大于 0 的金额";
      hasError = true;
      continue;
    }

    if (!/^\d{4}-\d{2}-\d{2}$/.test(state.paymentDate || "")) {
      state.result = "请选择实际支付日";
      hasError = true;
      continue;
    }

    if (!CASH_EXPENSE_CURRENCIES.includes(state.currency)) {
      state.result = "币种无效";
      hasError = true;
      continue;
    }

    const cashAccount = cashEligibleAccounts.find((account) => account.id === state.accountId);
    if (!cashAccount || cashAccount.currency !== state.currency) {
      state.result = "请选择同币种 Cash 账户";
      hasError = true;
      continue;
    }

    payloads.push({
      state,
      payload: {
        expenseId: expense.id,
        cashAccountId: state.accountId,
        actualPaymentAmount,
        actualPaymentCurrency: state.currency,
        actualPaymentDate: state.paymentDate,
        exchangeRate: state.currency === "CNY" ? parseOptionalPositiveNumber(state.exchangeRate) : null,
        note: buildCashExpenseRequestNote(expense, actualPaymentAmount, state.currency, state.paymentDate, state.note, rateAssistNote(state)),
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

function renderCreateBusinessEntityOptions(rows) {
  const options = ['<option value="">请选择业务归属</option>'];
  for (const entity of rows) {
    options.push(`<option value="${escapeAttribute(entity.id)}">${escapeHtml(businessEntityName(entity))}</option>`);
  }
  dom.createExpenseBusinessEntitySelect.innerHTML = options.join("");
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
  const businessEntityId = dom.createExpenseBusinessEntitySelect.value;
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

function updateCreateReimbursementDefault() {
  const account = accounts.find((item) => item.id === dom.createExpenseAccountSelect.value);
  dom.createExpenseReimbursementStatusSelect.value = account?.is_company_account ? "not_required" : "pending";
}

function setCreateSubmitting(isSubmitting) {
  isCreateSubmitting = isSubmitting;
  dom.createExpenseSubmitButton.disabled = isSubmitting;
  dom.createExpenseCancelButton.disabled = isSubmitting;
  dom.createExpenseSubmitButton.textContent = isSubmitting ? "保存中..." : "保存支出";
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
  if (text.includes("业务归属")) fields.push("businessEntity");
  if (text.includes("付款账户") || text.includes("币种")) fields.push("account");
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
    if (filters.businessEntityId && row.business_entity_id !== filters.businessEntityId) {
      return false;
    }

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
  if (!row?.id) return false;
  if (row.app_type !== "school") return false;
  if (row.status !== "pending") return false;
  if (row.reversed_at || row.reversal_account_transaction_id) return false;
  if (row.cash_transaction_id) return false;
  return !["pending", "approved", "synced"].includes(row.cash_request_status || "");
}

function cashRequestNotAllowedMessage(row) {
  if (!row) return "支出记录不存在，请刷新后重试。";
  if (row.app_type !== "school") return "只能提交 School 支出记录。";
  if (row.status !== "pending") return "只有待支付支出记录可以提交 Cash 支付确认。";
  if (row.reversed_at || row.reversal_account_transaction_id) return "已撤销支出不能提交 Cash 支付确认。";
  if (row.cash_transaction_id) return "该支出记录已经有 Cash transaction。";
  if (row.cash_request_status === "pending") return "该支出记录已有待确认 Cash request。";
  if (row.cash_request_status === "approved" || row.cash_request_status === "synced") return "该支出记录已同步到 Cash。";
  return "";
}

function renderCashRequestStatus(row) {
  if (!row?.cash_request_status && !row?.cash_transaction_id) {
    return "-";
  }

  const status = row.cash_transaction_id && !row.cash_request_status
    ? "synced"
    : row.cash_request_status;
  const noteText = safeText(row.cash_payment_note);
  return `
    <div class="income-cash-sync-cell">
      <span class="status-badge ${escapeAttribute(cashRequestStatusClass(status))}">${escapeHtml(cashRequestStatusLabel(status))}</span>
      ${noteText ? `<div class="table-cell-summary">${escapeHtml(noteText)}</div>` : ""}
    </div>
  `;
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

function businessNameById(id) {
  const entity = businessEntities.find((item) => item.id === id);
  if (!entity) {
    return id ? "未知" : "未设置";
  }

  return businessEntityName(entity);
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

function studentNameById(id) {
  const student = students.find((item) => item.id === id);
  if (!student) {
    return id ? "未知" : "-";
  }

  return studentName(student);
}

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
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
  return [
    expenseCategoryLabel(expense.expense_category),
    expenseObjectName(expense),
    expense.year_month,
    expense.description,
  ].filter(Boolean).join(" / ");
}

function buildCashExpenseRequestNote(expense, amount, currency, paymentDate, baseNote, rateNote = "") {
  const base = safeText(baseNote).trim();
  const requiredText = [
    `${expenseObjectName(expense)}，实际支付日${paymentDate}，实际支付${formatCurrency(amount, currency)}`,
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
  state.roundingMode = ROUNDING_MODE_LABELS[mode] ? mode : "";
  state.rateStatus = `${ROUNDING_MODE_LABELS[mode] || "取整"}已填入实际支付金额，仍可手动修改。`;
  renderBatchCashExpenseRows();
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
  if (Number.isFinite(theoreticalAmount) && theoreticalAmount > 0) {
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
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (month) {
    const [year, monthPart] = month.split("-");
    params.set("year", year);
    params.set("month", monthPart);
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
