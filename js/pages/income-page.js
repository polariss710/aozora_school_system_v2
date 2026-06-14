import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { initSchoolAuth, requireLoginForCashConfirmation } from "../auth.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createCashSystemIncome,
  createIncomeRecord,
  fetchIncomeLookups,
  fetchIncomeRecords,
} from "../api/income-api.js";
import { fetchSchoolEligibleCashAccountsViaFunction } from "../api/payment-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  studentId: "",
  businessEntityId: "",
  accountId: "",
  currency: "",
  incomeCategory: "",
  paymentMethod: "",
  status: "",
  includeInSettlement: "",
  keyword: "",
};

const INCOME_STATUS_LABELS = {
  pending: "待确认",
  received: "已收款",
  reversed: "已冲销",
};

const INCOME_CATEGORY_LABELS = {
  tuition: "学费",
  material_fee: "教材费",
  registration_fee: "报名费",
  other_fee: "其他费用",
};

const EDITABLE_INCOME_CATEGORIES = ["tuition", "material_fee", "registration_fee", "other_fee"];
const CREATE_MODE_SCHOOL_ACCOUNT = "school_account";
const CREATE_MODE_CASH_SYSTEM_INCOME = "cash_system_income";
const CASH_INCOME_CURRENCIES = ["JPY", "CNY"];
const SCHOOL_ELIGIBLE_CASH_ACCOUNT_NAMES = new Set(["余额宝", "日元现金", "日元三菱卡", "日元乐天卡"]);

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
  cash_rejected: "Cash已拒绝",
  blocked: "Cash已阻止",
  failed: "Cash失败",
};

const dom = {};
let students = [];
let businessEntities = [];
let accounts = [];
let cashEligibleAccounts = [];
let hasLoadedCashEligibleAccounts = false;
let incomeRecords = [];
let loadedMonth = "";
let isCreateSubmitting = false;

export function initIncomePage() {
  cacheDom();
  initSchoolAuth();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  setDefaultFilters();
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
  dom.businessEntitySelect = document.querySelector("#incomeBusinessEntitySelect");
  dom.accountSelect = document.querySelector("#incomeAccountSelect");
  dom.currencySelect = document.querySelector("#incomeCurrencySelect");
  dom.incomeCategorySelect = document.querySelector("#incomeCategorySelect");
  dom.paymentMethodSelect = document.querySelector("#incomePaymentMethodSelect");
  dom.statusSelect = document.querySelector("#incomeStatusSelect");
  dom.includeSelect = document.querySelector("#incomeIncludeSelect");
  dom.keywordInput = document.querySelector("#incomeKeywordInput");
  dom.resetButton = document.querySelector("#incomeResetButton");
  dom.tableBody = document.querySelector("#incomeTableBody");
  dom.loadingState = document.querySelector("#incomeLoadingState");
  dom.emptyState = document.querySelector("#incomeEmptyState");
  dom.incomeCount = document.querySelector("#incomeCount");
  dom.openCreateIncomeButton = document.querySelector("#openCreateIncomeButton");
  dom.createIncomeDialog = document.querySelector("#createIncomeDialog");
  dom.createIncomeError = document.querySelector("#createIncomeError");
  dom.createIncomeModeSelect = document.querySelector("#createIncomeModeSelect");
  dom.createIncomeDateInput = document.querySelector("#createIncomeDateInput");
  dom.createSettlementMonthInput = document.querySelector("#createSettlementMonthInput");
  dom.createIncomeBusinessEntitySelect = document.querySelector("#createIncomeBusinessEntitySelect");
  dom.createIncomeStudentSelect = document.querySelector("#createIncomeStudentSelect");
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

  dom.openCreateIncomeButton.addEventListener("click", openCreateIncomeDialog);
  dom.createIncomeCancelButton.addEventListener("click", closeCreateIncomeDialog);
  dom.createIncomeSubmitButton.addEventListener("click", submitCreateIncome);
  dom.createIncomeModeSelect.addEventListener("change", async () => {
    clearCreateFieldInvalid("createMode");
    hideCreateErrorIfClean();

    if (isCashIncomeCreateMode()) {
      if (
        !requireLoginForCashConfirmation((_type, message) => {
          showCreateError(message, ["createMode"]);
        })
      ) {
        updateCreateModeUi({ preserveBusinessEntity: true });
        return;
      }

      try {
        await ensureCashEligibleAccountsLoaded();
      } catch (error) {
        showCreateError(`读取 Cash System 账户失败：${error.message || error}`, ["createMode"]);
        updateCreateModeUi({ preserveBusinessEntity: true });
        return;
      }
    }

    updateCreateModeUi({ preserveBusinessEntity: true });
  });
  dom.createIncomeBusinessEntitySelect.addEventListener("change", () => {
    renderCreateStudentOptions();
    renderCreateAccountOptions();
    renderCreateCashAccountOptions();
    clearCreateFieldInvalid("businessEntity");
    hideCreateErrorIfClean();
  });
  dom.createIncomeStudentSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("student");
    hideCreateErrorIfClean();
  });
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

function setDefaultFilters() {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  dom.studentSelect.value = DEFAULT_FILTERS.studentId;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.accountSelect.value = DEFAULT_FILTERS.accountId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  dom.incomeCategorySelect.value = DEFAULT_FILTERS.incomeCategory;
  dom.paymentMethodSelect.value = DEFAULT_FILTERS.paymentMethod;
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.includeSelect.value = DEFAULT_FILTERS.includeInSettlement;
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载收入记录数据...");

  try {
    const lookups = await fetchIncomeLookups();
    students = lookups.students;
    businessEntities = lookups.businessEntities;
    accounts = lookups.accounts;
    renderMasterOptions();
    await loadIncomeMonth(currentYearMonth());
    applyCurrentFilters();
    showMessage("success", "收入记录数据已加载。");
  } catch (error) {
    students = [];
    businessEntities = [];
    accounts = [];
    cashEligibleAccounts = [];
    hasLoadedCashEligibleAccounts = false;
    incomeRecords = [];
    loadedMonth = "";
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

  if (filters.month !== loadedMonth) {
    setLoading(true);
    showMessage("info", "正在加载收入记录...");

    try {
      await loadIncomeMonth(filters.month);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "收入记录已加载。");
    } catch (error) {
      incomeRecords = [];
      loadedMonth = "";
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
    businessEntityId: dom.businessEntitySelect.value,
    accountId: dom.accountSelect.value,
    currency: dom.currencySelect.value,
    incomeCategory: dom.incomeCategorySelect.value,
    paymentMethod: dom.paymentMethodSelect.value,
    status: dom.statusSelect.value,
    includeInSettlement: dom.includeSelect.value,
    keyword: dom.keywordInput.value.trim(),
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.studentSelect.value = filters.studentId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.accountSelect.value = filters.accountId;
  dom.currencySelect.value = filters.currency;
  dom.incomeCategorySelect.value = filters.incomeCategory;
  dom.paymentMethodSelect.value = filters.paymentMethod;
  dom.statusSelect.value = filters.status;
  dom.includeSelect.value = filters.includeInSettlement;
  dom.keywordInput.value = filters.keyword;
}

function renderMasterOptions() {
  renderEntityOptions(dom.studentSelect, students, studentName);
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
  renderEntityOptions(dom.accountSelect, accounts, accountName);
}

function renderDataOptions(rows) {
  renderValueOptions(dom.currencySelect, distinctValues(rows, "currency"), displayValue);
  renderValueOptions(dom.incomeCategorySelect, distinctValues(rows, "income_category"), incomeCategoryLabel);
  renderValueOptions(dom.paymentMethodSelect, distinctValues(rows, "payment_method"), paymentMethodLabel);
  renderValueOptions(dom.statusSelect, distinctValues(rows, "status"), incomeStatusLabel);
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
  dom.incomeCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td><a class="table-action-button" href="./income-detail.html?id=${encodeURIComponent(row.id)}">详情</a></td>
      <td class="income-nowrap">${escapeHtml(formatDateOnly(row.income_date))}</td>
      <td class="income-nowrap">${escapeHtml(formatMonth(row.year_month))}</td>
      <td class="income-nowrap">${escapeHtml(formatMonth(row.settlement_month))}</td>
      <td>${escapeHtml(studentNameById(row.student_id))}</td>
      <td>${escapeHtml(businessNameById(row.business_entity_id))}</td>
      <td>${escapeHtml(incomeAccountDisplayName(row))}</td>
      <td><span class="status-badge status-neutral">${escapeHtml(incomeCategoryLabel(row.income_category))}</span></td>
      <td class="income-nowrap">${escapeHtml(displayValue(row.currency))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(row.amount_jpy, "JPY"))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(row.amount_cny, "CNY"))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(displayValue(row.exchange_rate))}</td>
      <td>${escapeHtml(paymentMethodLabel(row.payment_method))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(incomeStatusLabel(row.status))}</span></td>
      <td>${renderCashSyncBadge(row.cashIncomeLinkageEvent)}</td>
      <td>${escapeHtml(displayValue(row.receipt_status))}</td>
      <td class="income-nowrap">${escapeHtml(booleanLabel(row.include_in_student_settlement))}</td>
      <td class="income-note-cell">${escapeHtml(displayValue(row.note))}</td>
      <td class="income-nowrap">${escapeHtml(formatDate(row.created_at))}</td>
      <td class="income-nowrap">${escapeHtml(formatDate(row.updated_at))}</td>
    </tr>
  `).join("");
}

function openCreateIncomeDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  clearCreateErrors();
  setCreateSubmitting(false);

  const filters = readFilters();
  const defaultBusinessEntityId = filters?.businessEntityId || "";
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

  renderCreateBusinessEntityOptions();
  dom.createIncomeBusinessEntitySelect.value = filteredCreateBusinessEntities().some((entity) => entity.id === defaultBusinessEntityId)
    ? defaultBusinessEntityId
    : "";

  renderCreateStudentOptions();
  dom.createIncomeStudentSelect.value = filteredCreateStudents().some((student) => student.id === defaultStudentId)
    ? defaultStudentId
    : "";

  renderCreateAccountOptions();
  dom.createIncomeAccountSelect.value = filteredCreateAccounts().some((account) => account.id === defaultAccountId)
    ? defaultAccountId
    : "";
  renderCreateCashAccountOptions();
  updateCreateModeUi();

  dom.createIncomeDialog.classList.remove("is-hidden");
  dom.createIncomeDialog.setAttribute("aria-hidden", "false");
}

function closeCreateIncomeDialog() {
  if (isCreateSubmitting) {
    return;
  }

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
      ? await createCashSystemIncome(payload)
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

  const businessEntityId = dom.createIncomeBusinessEntitySelect.value;
  if (!businessEntityId) {
    showCreateError("请选择业务归属。", ["businessEntity"]);
    return null;
  }

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

    const cashAccountId = dom.createIncomeCashMappingSelect.value;
    if (!cashAccountId) {
      showCreateError("请选择 Cash System 账户。", ["cashMapping"]);
      return null;
    }

    const cashAccount = filteredCreateCashAccounts().find((item) => item.id === cashAccountId);
    if (!cashAccount) {
      showCreateError("Cash System 账户无效、未在白名单内，或币种与收入币种不一致。", ["cashMapping"]);
      return null;
    }

    return {
      createMode,
      incomeDate,
      settlementMonth,
      businessEntityId,
      studentId,
      cashAccountId,
      cashAccountName: cashAccount.name || cashAccount.id,
      cashAccountType: cashAccount.account_type || null,
      amount,
      incomeCategory,
      currency,
      paymentCurrency: currency,
      exchangeRate: null,
      paymentMethod: "",
      description: dom.createIncomeDescriptionInput.value.trim(),
      isTaxableIncome: dom.createIncomeTaxableSelect.value === "true",
      taxCategory: dom.createIncomeTaxCategoryInput.value.trim(),
      receiptStatus: dom.createIncomeReceiptStatusInput.value.trim(),
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
    showCreateError("入账账户与业务归属不一致。", ["account"]);
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
    ? "已提交 Cash System 待确认。"
    : "收入已新增并自动入账。";
  if (incomeId) {
    dom.messageArea.innerHTML = `${escapeHtml(message)}<a href="./income-detail.html?id=${encodeURIComponent(incomeId)}">查看详情</a>`;
  } else {
    dom.messageArea.textContent = message;
  }
}

function renderCreateBusinessEntityOptions() {
  const selectedValue = dom.createIncomeBusinessEntitySelect.value;
  const rows = filteredCreateBusinessEntities();
  const options = ['<option value="">请选择业务归属</option>'];
  for (const entity of rows) {
    options.push(`<option value="${escapeAttribute(entity.id)}">${escapeHtml(businessEntityName(entity))}</option>`);
  }
  dom.createIncomeBusinessEntitySelect.innerHTML = options.join("");
  if (rows.some((entity) => entity.id === selectedValue)) {
    dom.createIncomeBusinessEntitySelect.value = selectedValue;
  }
}

function renderCreateStudentOptions() {
  const selectedValue = dom.createIncomeStudentSelect.value;
  const options = ['<option value="">请选择学生</option>'];
  for (const student of filteredCreateStudents()) {
    options.push(`<option value="${escapeAttribute(student.id)}">${escapeHtml(studentName(student))}</option>`);
  }
  dom.createIncomeStudentSelect.innerHTML = options.join("");
  if (filteredCreateStudents().some((student) => student.id === selectedValue)) {
    dom.createIncomeStudentSelect.value = selectedValue;
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
    SCHOOL_ELIGIBLE_CASH_ACCOUNT_NAMES.has(account.name || "") &&
    CASH_INCOME_CURRENCIES.includes(account.currency)
  ));
  hasLoadedCashEligibleAccounts = true;
}

function filteredCreateBusinessEntities() {
  const rows = businessEntities.filter((entity) => entity.is_active !== false);
  return rows;
}

function filteredCreateStudents() {
  const businessEntityId = dom.createIncomeBusinessEntitySelect.value;
  return students.filter((student) => {
    if (businessEntityId && student.business_entity_id !== businessEntityId) {
      return false;
    }

    return student.status !== "inactive" && student.status !== "disabled" && student.status !== "archived";
  });
}

function filteredCreateAccounts() {
  const businessEntityId = dom.createIncomeBusinessEntitySelect.value;
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

    if (!SCHOOL_ELIGIBLE_CASH_ACCOUNT_NAMES.has(account.name || "")) {
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

function updateCreateModeUi(options = {}) {
  const previousBusinessEntityId = options.preserveBusinessEntity
    ? dom.createIncomeBusinessEntitySelect.value
    : "";

  renderCreateBusinessEntityOptions();
  if (previousBusinessEntityId && filteredCreateBusinessEntities().some((entity) => entity.id === previousBusinessEntityId)) {
    dom.createIncomeBusinessEntitySelect.value = previousBusinessEntityId;
  }

  const cashMode = isCashIncomeCreateMode();
  setCreateFieldHidden("account", cashMode);
  setCreateFieldHidden("cashCurrency", !cashMode);
  setCreateFieldHidden("cashMapping", !cashMode);
  setCreateFieldHidden("paymentMethod", cashMode);
  setCreateFieldHidden("exchangeRate", cashMode);

  dom.createIncomeAccountSelect.disabled = cashMode;
  dom.createIncomeCurrencySelect.disabled = !cashMode;
  dom.createIncomeCashMappingSelect.disabled = !cashMode;
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

  renderCreateStudentOptions();
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
  for (const fieldId of ["createMode", "incomeDate", "settlementMonth", "businessEntity", "student", "account", "cashCurrency", "cashMapping", "incomeCategory", "amount", "paymentMethod", "exchangeRate"]) {
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
  if (text.includes("业务归属")) fields.push("businessEntity");
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

    if (filters.businessEntityId && row.business_entity_id !== filters.businessEntityId) {
      return false;
    }

    if (filters.accountId && row.account_id !== filters.accountId) {
      return false;
    }

    if (filters.currency && row.currency !== filters.currency) {
      return false;
    }

    if (filters.incomeCategory && row.income_category !== filters.incomeCategory) {
      return false;
    }

    if (filters.paymentMethod && row.payment_method !== filters.paymentMethod) {
      return false;
    }

    if (filters.status && row.status !== filters.status) {
      return false;
    }

    if (filters.includeInSettlement && String(row.include_in_student_settlement) !== filters.includeInSettlement) {
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
    studentNameById(row.student_id),
    businessNameById(row.business_entity_id),
    incomeAccountDisplayName(row),
    incomeCategoryLabel(row.income_category),
    row.income_category,
    paymentMethodLabel(row.payment_method),
    row.payment_method,
    incomeStatusLabel(row.status),
    row.status,
    row.receipt_status,
    row.note,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
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

function incomeAccountDisplayName(row) {
  if (row?.cashIncomeLinkageEvent) {
    return cashIncomeAccountName(row.cashIncomeLinkageEvent);
  }

  if (!row?.account_id && isCashIncomeRow(row)) {
    return row?.status === "pending" ? "Cash待确认" : "Cash账户未取得";
  }

  return accountNameById(row?.account_id);
}

function isCashIncomeRow(row) {
  return safeText(row?.receipt_status).includes("Cash");
}

function cashIncomeAccountName(event) {
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

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
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

  return "status-neutral";
}

function renderCashSyncBadge(event) {
  if (!event) {
    return "-";
  }

  return `<span class="status-badge ${escapeAttribute(cashLinkageStatusClass(event.sync_status))}">${escapeHtml(cashLinkageStatusLabel(event.sync_status))}</span>`;
}

function cashLinkageStatusLabel(value) {
  return CASH_LINKAGE_STATUS_LABELS[value] || displayValue(value);
}

function cashLinkageStatusClass(value) {
  if (value === "pending" || value === "pending_cash_request" || value === "awaiting_cash_confirmation") return "status-pending";
  if (value === "synced") return "status-paid";
  if (value === "failed" || value === "cash_rejected" || value === "blocked") return "status-cancelled";
  return "status-neutral";
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
