import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createExpenseRecord,
  fetchExpenseAttachmentCounts,
  fetchExpenseLookups,
  fetchExpensePaymentRequests,
  fetchExpenseRecords,
} from "../api/expense-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  businessEntityId: "",
  accountId: "",
  teacherId: "",
  currency: "",
  expenseCategory: "",
  paymentMethod: "",
  status: "",
  wagePaymentStatus: "",
  receiptStatus: "",
  reimbursementStatus: "",
  keyword: "",
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

const WAGE_PAYMENT_STATUS_FILTER_OPTIONS = [
  ["paid", "已支付"],
  ["reversed", "已撤销"],
  ["void", "已作废"],
  ["pending", "待支付"],
  ["cancelled", "已取消"],
  ["unlinked", "未关联"],
];

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

const dom = {};
let businessEntities = [];
let accounts = [];
let teachers = [];
let students = [];
let expenseRecords = [];
let paymentRequestsByExpenseId = new Map();
let attachmentCountsByExpenseId = new Map();
let loadedMonth = "";
let isCreateSubmitting = false;

export function initExpensePage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
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
  dom.businessEntitySelect = document.querySelector("#expenseBusinessEntitySelect");
  dom.accountSelect = document.querySelector("#expenseAccountSelect");
  dom.teacherSelect = document.querySelector("#expenseTeacherSelect");
  dom.currencySelect = document.querySelector("#expenseCurrencySelect");
  dom.expenseCategorySelect = document.querySelector("#expenseCategorySelect");
  dom.paymentMethodSelect = document.querySelector("#expensePaymentMethodSelect");
  dom.statusSelect = document.querySelector("#expenseStatusSelect");
  dom.wagePaymentStatusSelect = document.querySelector("#expenseWagePaymentStatusSelect");
  dom.receiptStatusSelect = document.querySelector("#expenseReceiptStatusSelect");
  dom.reimbursementStatusSelect = document.querySelector("#expenseReimbursementStatusSelect");
  dom.keywordInput = document.querySelector("#expenseKeywordInput");
  dom.resetButton = document.querySelector("#expenseResetButton");
  dom.tableBody = document.querySelector("#expenseTableBody");
  dom.loadingState = document.querySelector("#expenseLoadingState");
  dom.emptyState = document.querySelector("#expenseEmptyState");
  dom.expenseCount = document.querySelector("#expenseCount");
  dom.openCreateExpenseButton = document.querySelector("#openCreateExpenseButton");
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

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    applyQuery();
  });

  dom.openCreateExpenseButton.addEventListener("click", openCreateExpenseDialog);
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

function setDefaultFilters() {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.accountSelect.value = DEFAULT_FILTERS.accountId;
  dom.teacherSelect.value = DEFAULT_FILTERS.teacherId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  dom.expenseCategorySelect.value = DEFAULT_FILTERS.expenseCategory;
  dom.paymentMethodSelect.value = DEFAULT_FILTERS.paymentMethod;
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.wagePaymentStatusSelect.value = DEFAULT_FILTERS.wagePaymentStatus;
  dom.receiptStatusSelect.value = DEFAULT_FILTERS.receiptStatus;
  dom.reimbursementStatusSelect.value = DEFAULT_FILTERS.reimbursementStatus;
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
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
    await loadExpenseMonth(currentYearMonth());
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
    businessEntityId: dom.businessEntitySelect.value,
    accountId: dom.accountSelect.value,
    teacherId: dom.teacherSelect.value,
    currency: dom.currencySelect.value,
    expenseCategory: dom.expenseCategorySelect.value,
    paymentMethod: dom.paymentMethodSelect.value,
    status: dom.statusSelect.value,
    wagePaymentStatus: dom.wagePaymentStatusSelect.value,
    receiptStatus: dom.receiptStatusSelect.value,
    reimbursementStatus: dom.reimbursementStatusSelect.value,
    keyword: dom.keywordInput.value.trim(),
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.accountSelect.value = filters.accountId;
  dom.teacherSelect.value = filters.teacherId;
  dom.currencySelect.value = filters.currency;
  dom.expenseCategorySelect.value = filters.expenseCategory;
  dom.paymentMethodSelect.value = filters.paymentMethod;
  dom.statusSelect.value = filters.status;
  dom.wagePaymentStatusSelect.value = filters.wagePaymentStatus;
  dom.receiptStatusSelect.value = filters.receiptStatus;
  dom.reimbursementStatusSelect.value = filters.reimbursementStatus;
  dom.keywordInput.value = filters.keyword;
}

function renderMasterOptions() {
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
  renderEntityOptions(dom.accountSelect, accounts, accountName);
  renderEntityOptions(dom.teacherSelect, teachers, teacherName);
  renderWagePaymentStatusOptions();
}

function renderDataOptions(rows) {
  renderValueOptions(dom.currencySelect, distinctValues(rows, "currency"), displayValue);
  renderValueOptions(dom.expenseCategorySelect, distinctValues(rows, "expense_category"), expenseCategoryLabel);
  renderValueOptions(dom.paymentMethodSelect, distinctValues(rows, "payment_method"), paymentMethodLabel);
  renderValueOptions(dom.statusSelect, distinctValues(rows, "status"), expenseStatusLabel);
  renderValueOptions(dom.receiptStatusSelect, distinctValues(rows, "receipt_status"), displayValue);
  renderValueOptions(
    dom.reimbursementStatusSelect,
    distinctValues(rows, "reimbursement_status"),
    reimbursementStatusLabel
  );
}

function renderWagePaymentStatusOptions() {
  const options = ['<option value="">全部</option>'];
  for (const [value, label] of WAGE_PAYMENT_STATUS_FILTER_OPTIONS) {
    options.push(`<option value="${escapeAttribute(value)}">${escapeHtml(label)}</option>`);
  }
  dom.wagePaymentStatusSelect.innerHTML = options.join("");
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

function renderExpenseRecords(rows) {
  dom.expenseCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td class="action-cell"><a class="button table-action-button" href="${escapeAttribute(expenseDetailUrl(row.id))}">详情</a></td>
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
      <td>${renderWagePaymentStatus(row)}</td>
      <td>${escapeHtml(displayValue(row.receipt_status))}</td>
      <td>${escapeHtml(reimbursementStatusLabel(row.reimbursement_status, row.expense_category))}</td>
      <td class="expense-nowrap">${renderAttachmentStatus(row)}</td>
      <td class="expense-note-cell">${escapeHtml(displayValue(row.note))}</td>
      <td class="expense-nowrap">${escapeHtml(formatDate(row.created_at))}</td>
      <td class="expense-nowrap">${escapeHtml(formatDate(row.updated_at))}</td>
    </tr>
  `).join("");
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
  const exchangeRate = exchangeRateText ? Number(exchangeRateText) : null;
  if (exchangeRateText && (!Number.isFinite(exchangeRate) || exchangeRate <= 0)) {
    showCreateError("汇率必须大于 0。", ["exchangeRate"]);
    return null;
  }

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

    if (filters.teacherId && row.teacher_id !== filters.teacherId) {
      return false;
    }

    if (filters.currency && row.currency !== filters.currency) {
      return false;
    }

    if (filters.expenseCategory && row.expense_category !== filters.expenseCategory) {
      return false;
    }

    if (filters.paymentMethod && row.payment_method !== filters.paymentMethod) {
      return false;
    }

    if (filters.status && row.status !== filters.status) {
      return false;
    }

    if (filters.wagePaymentStatus && wagePaymentStatusKey(row) !== filters.wagePaymentStatus) {
      return false;
    }

    if (filters.receiptStatus && row.receipt_status !== filters.receiptStatus) {
      return false;
    }

    if (filters.reimbursementStatus && row.reimbursement_status !== filters.reimbursementStatus) {
      return false;
    }

    return matchesKeyword(row, filters.keyword);
  });
}

function matchesKeyword(row, keyword) {
  if (!keyword) {
    return true;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return [
    businessNameById(row.business_entity_id),
    accountNameById(row.account_id),
    teacherNameById(row.teacher_id),
    expenseCategoryLabel(row.expense_category),
    row.expense_category,
    paymentMethodLabel(row.payment_method),
    row.payment_method,
    expenseStatusLabel(row.status),
    row.status,
    wagePaymentStatusLabel(wagePaymentStatusKey(row)),
    row.receipt_status,
    reimbursementStatusLabel(row.reimbursement_status, row.expense_category),
    row.reimbursement_status,
    row.description,
    row.note,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
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

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
}

function accountName(account) {
  const name = safeText(account.name) || "未设置";
  const currency = safeText(account.currency);
  return currency ? `${name} / ${currency}` : name;
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
  return `./expense-detail.html?id=${encodeURIComponent(safeText(expenseId))}`;
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
}

function showMessage(type, text) {
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = text;
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
