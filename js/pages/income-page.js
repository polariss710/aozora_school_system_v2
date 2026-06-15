import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { initSchoolAuth, requireLoginForCashConfirmation } from "../auth.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createCashSystemIncome,
  createIncomeRecord,
  fetchIncomeLookups,
  fetchIncomeRecords,
  requestCashIncomeConfirmationForRecord,
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
  part_time_work: "外部塾打工收入",
};

const EDITABLE_INCOME_CATEGORIES = ["tuition", "material_fee", "registration_fee", "other_fee"];
const CREATE_MODE_SCHOOL_ACCOUNT = "school_account";
const CREATE_MODE_CASH_SYSTEM_INCOME = "cash_system_income";
const CASH_INCOME_CURRENCIES = ["JPY", "CNY"];

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
let renderedIncomeRows = [];
let selectedIncomeIds = new Set();
let loadedMonth = "";
let isCreateSubmitting = false;
let cashRequestIncomeRecord = null;
let isCashRequestSubmitting = false;
let batchCashIncomeRows = [];
let isBatchCashSubmitting = false;

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
  dom.resetButton = document.querySelector("#incomeResetButton");
  dom.tableBody = document.querySelector("#incomeTableBody");
  dom.loadingState = document.querySelector("#incomeLoadingState");
  dom.emptyState = document.querySelector("#incomeEmptyState");
  dom.incomeCount = document.querySelector("#incomeCount");
  dom.openCreateIncomeButton = document.querySelector("#openCreateIncomeButton");
  dom.openBatchCashIncomeButton = document.querySelector("#openBatchCashIncomeButton");
  dom.selectAllCashRequests = document.querySelector("#incomeSelectAllCashRequests");
  dom.batchCashIncomeDialog = document.querySelector("#batchCashIncomeDialog");
  dom.batchCashIncomeError = document.querySelector("#batchCashIncomeError");
  dom.batchCashIncomeTableBody = document.querySelector("#batchCashIncomeTableBody");
  dom.batchCashIncomeSubmitButton = document.querySelector("#batchCashIncomeSubmitButton");
  dom.batchCashIncomeCancelButton = document.querySelector("#batchCashIncomeCancelButton");
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
  dom.cashIncomeRequestDialog = document.querySelector("#cashIncomeRequestDialog");
  dom.cashIncomeRequestError = document.querySelector("#cashIncomeRequestError");
  dom.cashIncomeRequestSummary = document.querySelector("#cashIncomeRequestSummary");
  dom.cashIncomeActualAmountInput = document.querySelector("#cashIncomeActualAmountInput");
  dom.cashIncomeActualCurrencySelect = document.querySelector("#cashIncomeActualCurrencySelect");
  dom.cashIncomeExchangeRateInput = document.querySelector("#cashIncomeExchangeRateInput");
  dom.cashIncomeAccountSelect = document.querySelector("#cashIncomeAccountSelect");
  dom.cashIncomeNoteInput = document.querySelector("#cashIncomeNoteInput");
  dom.cashIncomeRequestPreview = document.querySelector("#cashIncomeRequestPreview");
  dom.cashIncomeRequestSubmitButton = document.querySelector("#cashIncomeRequestSubmitButton");
  dom.cashIncomeRequestCancelButton = document.querySelector("#cashIncomeRequestCancelButton");
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
  dom.createIncomeCancelButton.addEventListener("click", closeCreateIncomeDialog);
  dom.createIncomeSubmitButton.addEventListener("click", submitCreateIncome);
  dom.cashIncomeRequestCancelButton.addEventListener("click", closeCashIncomeRequestDialog);
  dom.cashIncomeRequestSubmitButton.addEventListener("click", submitCashIncomeRequest);
  for (const [input, fieldId] of [
    [dom.cashIncomeActualAmountInput, "actualAmount"],
    [dom.cashIncomeActualCurrencySelect, "actualCurrency"],
    [dom.cashIncomeAccountSelect, "cashAccount"],
    [dom.cashIncomeNoteInput, "note"],
  ]) {
    input.addEventListener("input", () => {
      if (input === dom.cashIncomeActualCurrencySelect) {
        renderCashIncomeAccountOptions();
      }
      clearCashIncomeRequestFieldInvalid(fieldId);
      hideCashIncomeRequestErrorIfClean();
      updateCashIncomeRequestPreview();
    });
  }
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
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.studentSelect.value = filters.studentId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.accountSelect.value = filters.accountId;
  dom.currencySelect.value = filters.currency;
}

function renderMasterOptions() {
  renderEntityOptions(dom.studentSelect, students, studentName);
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
  renderEntityOptions(dom.accountSelect, accounts, accountName);
}

function renderDataOptions(rows) {
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
  dom.incomeCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    updateIncomeBatchControls();
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td>${renderIncomeSelectionCell(row)}</td>
      <td>${renderIncomeRowActions(row)}</td>
      <td class="income-nowrap">${escapeHtml(formatDateOnly(row.income_date))}</td>
      <td class="income-nowrap">${escapeHtml(formatMonth(row.year_month))}</td>
      <td class="income-nowrap">${escapeHtml(formatMonth(incomeReceivedMonth(row)))}</td>
      <td class="income-nowrap">${escapeHtml(formatMonth(row.settlement_month))}</td>
      <td>${escapeHtml(incomeObjectName(row))}</td>
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
      <td>${renderCashSyncSummary(row.cashIncomeLinkageEvent)}</td>
      <td>${escapeHtml(displayValue(row.receipt_status))}</td>
      <td class="income-nowrap">${escapeHtml(booleanLabel(row.include_in_student_settlement))}</td>
      <td class="income-note-cell">${escapeHtml(displayValue(row.note))}</td>
      <td class="income-nowrap">${escapeHtml(formatDate(row.created_at))}</td>
      <td class="income-nowrap">${escapeHtml(formatDate(row.updated_at))}</td>
    </tr>
  `).join("");
  updateIncomeBatchControls();
}

function renderIncomeSelectionCell(row) {
  const selectable = canRequestCashIncome(row);
  return `
    <input
      type="checkbox"
      data-income-select-id="${escapeAttribute(row.id)}"
      aria-label="选择收入记录 ${escapeAttribute(incomeObjectName(row))}"
      ${selectable ? "" : "disabled"}
      ${selectedIncomeIds.has(row.id) ? "checked" : ""}
    >
  `;
}

function renderIncomeRowActions(row) {
  const cashButton = canRequestCashIncome(row)
    ? `<button class="table-action-button" type="button" data-income-cash-request-id="${escapeAttribute(row.id)}">提交 Cash 确认</button>`
    : "";
  return `
    <div class="income-row-actions">
      <a class="table-action-button" href="./income-detail.html?id=${encodeURIComponent(row.id)}">详情</a>
      ${cashButton}
    </div>
  `;
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

  openCashIncomeRequestDialog(income);
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

async function openCashIncomeRequestDialog(income) {
  if (!canRequestCashIncome(income)) {
    showMessage("error", "当前收入记录不能提交 Cash 确认请求。");
    return;
  }

  if (
    !requireLoginForCashConfirmation((_type, message) => {
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

  cashRequestIncomeRecord = income;
  clearCashIncomeRequestErrors();
  setCashRequestSubmitting(false);
  dom.cashIncomeRequestSummary.innerHTML = renderCashIncomeRequestSummary(income);
  dom.cashIncomeActualAmountInput.value = "";
  dom.cashIncomeActualCurrencySelect.value = income.source_type === "part_time_work" ? "CNY" : income.currency || "JPY";
  dom.cashIncomeExchangeRateInput.value = "";
  dom.cashIncomeNoteInput.value = defaultCashIncomeNote(income);
  renderCashIncomeAccountOptions();
  updateCashIncomeRequestPreview();
  dom.cashIncomeRequestDialog.classList.remove("is-hidden");
  dom.cashIncomeRequestDialog.setAttribute("aria-hidden", "false");
  dom.cashIncomeActualAmountInput.focus();
}

function closeCashIncomeRequestDialog() {
  if (isCashRequestSubmitting) {
    return;
  }

  cashRequestIncomeRecord = null;
  dom.cashIncomeRequestDialog.classList.add("is-hidden");
  dom.cashIncomeRequestDialog.setAttribute("aria-hidden", "true");
}

async function submitCashIncomeRequest() {
  if (isCashRequestSubmitting || !cashRequestIncomeRecord) {
    return;
  }

  const payload = readCashIncomeRequestPayload();
  if (!payload) {
    return;
  }

  if (!window.confirm("确认提交 Cash 待确认请求？Cash 确认后才会生成 Cash 交易。")) {
    return;
  }

  setCashRequestSubmitting(true);
  try {
    await requestCashIncomeConfirmationForRecord(payload);
    closeCashIncomeRequestDialog();
    await refreshCurrentIncomeList();
    showMessage("success", "Cash 收入确认请求已提交，等待 Cash 侧确认。");
  } catch (error) {
    showCashIncomeRequestError(`Cash 收入确认请求提交失败：${error.message || error}`);
  } finally {
    setCashRequestSubmitting(false);
  }
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
    !requireLoginForCashConfirmation((_type, message) => {
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
    amount: income.amount ?? "",
    currency: income.currency || "JPY",
    accountId: "",
    note: defaultCashIncomeNote(income),
    result: "",
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
  dom.batchCashIncomeTableBody.innerHTML = batchCashIncomeRows.map((state) => {
    const income = state.income;
    return `
      <tr data-batch-income-row-id="${escapeAttribute(income.id)}">
        <td>${escapeHtml(incomeObjectName(income))}</td>
        <td class="income-nowrap">${escapeHtml(formatMonth(income.year_month))}</td>
        <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(income.amount, income.currency))}</td>
        <td><input data-batch-income-amount="${escapeAttribute(income.id)}" type="number" min="0" step="0.01" inputmode="decimal" value="${escapeAttribute(state.amount)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
        <td>
          <select data-batch-income-currency="${escapeAttribute(income.id)}" ${isBatchCashSubmitting ? "disabled" : ""}>
            ${CASH_INCOME_CURRENCIES.map((currency) => `<option value="${escapeAttribute(currency)}" ${currency === state.currency ? "selected" : ""}>${escapeHtml(currency)}</option>`).join("")}
          </select>
        </td>
        <td>
          <select data-batch-income-account="${escapeAttribute(income.id)}" ${isBatchCashSubmitting ? "disabled" : ""}>
            ${renderBatchCashIncomeAccountOptions(state)}
          </select>
        </td>
        <td><input data-batch-income-note="${escapeAttribute(income.id)}" type="text" value="${escapeAttribute(state.note)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
        <td>${escapeHtml(state.result || "-")}</td>
      </tr>
    `;
  }).join("");
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

  const shouldRerender = Boolean(event.target.closest("[data-batch-income-currency]"));
  syncBatchCashIncomeRowsFromDom();
  if (shouldRerender) {
    for (const state of batchCashIncomeRows) {
      const account = cashEligibleAccounts.find((row) => row.id === state.accountId);
      if (account?.currency !== state.currency) {
        state.accountId = "";
      }
    }
    renderBatchCashIncomeRows();
  }
  clearBatchCashIncomeError();
}

function syncBatchCashIncomeRowsFromDom() {
  for (const state of batchCashIncomeRows) {
    const id = state.income.id;
    state.amount = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-amount="${cssEscape(id)}"]`)?.value ?? state.amount;
    state.currency = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-currency="${cssEscape(id)}"]`)?.value ?? state.currency;
    state.accountId = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-account="${cssEscape(id)}"]`)?.value ?? state.accountId;
    state.note = dom.batchCashIncomeTableBody.querySelector(`[data-batch-income-note="${cssEscape(id)}"]`)?.value ?? state.note;
  }
}

async function submitBatchCashIncomeRequests() {
  if (isBatchCashSubmitting) {
    return;
  }

  const payloads = readBatchCashIncomePayloads();
  if (!payloads) {
    return;
  }

  if (!window.confirm(`确认提交 ${payloads.length} 条 Cash 收入确认请求？Cash 确认后才会生成交易。`)) {
    return;
  }

  setBatchCashIncomeSubmitting(true);
  let successCount = 0;
  for (const item of payloads) {
    try {
      await requestCashIncomeConfirmationForRecord(item.payload);
      item.state.result = "已提交";
      selectedIncomeIds.delete(item.state.income.id);
      successCount += 1;
    } catch (error) {
      item.state.result = `失败：${error.message || error}`;
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

function readBatchCashIncomePayloads() {
  syncBatchCashIncomeRowsFromDom();
  clearBatchCashIncomeError();
  let hasError = false;
  const payloads = [];

  for (const state of batchCashIncomeRows) {
    const income = state.income;
    state.result = "";
    if (!canRequestCashIncome(income)) {
      state.result = "当前状态不可提交";
      hasError = true;
      continue;
    }

    const actualReceivedAmount = parseNumberInput(state.amount);
    if (!Number.isFinite(actualReceivedAmount) || actualReceivedAmount <= 0) {
      state.result = "请输入大于 0 的金额";
      hasError = true;
      continue;
    }

    if (!CASH_INCOME_CURRENCIES.includes(state.currency)) {
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

    const exchangeRate = calculatedCashIncomeExchangeRate(income, actualReceivedAmount, state.currency);
    if (state.currency === "CNY" && (!Number.isFinite(exchangeRate) || exchangeRate <= 0)) {
      state.result = "CNY 请求缺少有效参考汇率";
      hasError = true;
      continue;
    }

    payloads.push({
      state,
      payload: {
        incomeRecordId: income.id,
        cashAccountId: state.accountId,
        actualReceivedAmount,
        actualReceivedCurrency: state.currency,
        exchangeRate: state.currency === "JPY" ? 1 : exchangeRate,
        note: buildCashIncomeRequestNoteFromBase(income, actualReceivedAmount, state.currency, exchangeRate, state.note),
      },
    });
  }

  renderBatchCashIncomeRows();
  if (hasError) {
    showBatchCashIncomeError("部分记录缺少必要信息，未提交任何请求。");
    return null;
  }

  if (!payloads.length) {
    showBatchCashIncomeError("没有可提交的收入记录。");
    return null;
  }

  return payloads;
}

function readCashIncomeRequestPayload() {
  clearCashIncomeRequestErrors();
  const income = cashRequestIncomeRecord;
  if (!income?.id) {
    showCashIncomeRequestError("收入记录不存在，请刷新后重试。");
    return null;
  }

  const actualReceivedAmount = parseNumberInput(dom.cashIncomeActualAmountInput.value);
  if (!Number.isFinite(actualReceivedAmount) || actualReceivedAmount <= 0) {
    showCashIncomeRequestError("请输入大于 0 的实际到账金额。", ["actualAmount"]);
    return null;
  }

  const actualReceivedCurrency = dom.cashIncomeActualCurrencySelect.value;
  if (!CASH_INCOME_CURRENCIES.includes(actualReceivedCurrency)) {
    showCashIncomeRequestError("请选择实际到账币种。", ["actualCurrency"]);
    return null;
  }

  const cashAccountId = dom.cashIncomeAccountSelect.value;
  if (!cashAccountId) {
    showCashIncomeRequestError("请选择 Cash 收款账户。", ["cashAccount"]);
    return null;
  }

  const cashAccount = cashEligibleAccounts.find((account) => account.id === cashAccountId);
  if (!cashAccount || cashAccount.currency !== actualReceivedCurrency) {
    showCashIncomeRequestError("Cash 收款账户币种与实际到账币种不一致。", ["cashAccount"]);
    return null;
  }

  const exchangeRate = calculatedCashIncomeExchangeRate(income, actualReceivedAmount, actualReceivedCurrency);
  if (actualReceivedCurrency === "CNY" && (!Number.isFinite(exchangeRate) || exchangeRate <= 0)) {
    showCashIncomeRequestError("CNY 实际到账必须能根据 School JPY 原始金额计算参考汇率。", ["exchangeRate"]);
    return null;
  }

  return {
    incomeRecordId: income.id,
    cashAccountId,
    actualReceivedAmount,
    actualReceivedCurrency,
    exchangeRate: actualReceivedCurrency === "JPY" ? 1 : exchangeRate,
    note: buildCashIncomeRequestNote(income, actualReceivedAmount, actualReceivedCurrency, exchangeRate),
  };
}

function renderCashIncomeRequestSummary(income) {
  return `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">收入记录</span>
      <span>${escapeHtml(shortId(income.id))}</span>
    </div>
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">对象 / 来源</span>
      <span>${escapeHtml(incomeObjectName(income))}</span>
    </div>
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">业务归属月</span>
      <span>${escapeHtml(formatMonth(income.year_month))}</span>
    </div>
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">School 原始金额</span>
      <span>${escapeHtml(formatCurrency(income.amount, income.currency))}</span>
    </div>
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">JPY 金额</span>
      <span>${escapeHtml(formatCurrency(income.amount_jpy, "JPY"))}</span>
    </div>
  `;
}

function renderCashIncomeAccountOptions() {
  const selectedValue = dom.cashIncomeAccountSelect.value;
  const currency = dom.cashIncomeActualCurrencySelect.value;
  const rows = cashEligibleAccounts.filter((account) => (
    account?.is_active === true &&
    account?.allow_school_requests === true &&
    account.currency === currency
  ));
  dom.cashIncomeAccountSelect.innerHTML = [
    '<option value="">请选择 Cash 收款账户</option>',
    ...rows.map((account) => (
      `<option value="${escapeAttribute(account.id)}">${escapeHtml(createCashAccountLabel(account))}</option>`
    )),
  ].join("");

  if (rows.some((account) => account.id === selectedValue)) {
    dom.cashIncomeAccountSelect.value = selectedValue;
  }
}

function updateCashIncomeRequestPreview() {
  const income = cashRequestIncomeRecord;
  if (!income) {
    dom.cashIncomeRequestPreview.textContent = "Cash 请求预览：-";
    return;
  }

  const amount = parseNumberInput(dom.cashIncomeActualAmountInput.value);
  const currency = dom.cashIncomeActualCurrencySelect.value;
  const exchangeRate = calculatedCashIncomeExchangeRate(income, amount, currency);
  dom.cashIncomeExchangeRateInput.value = Number.isFinite(exchangeRate) ? String(exchangeRate) : "";

  if (!Number.isFinite(amount) || amount <= 0) {
    dom.cashIncomeRequestPreview.textContent = `Cash 请求预览：School 原始金额 ${formatCurrency(income.amount, income.currency)} / 实际到账 -`;
    return;
  }

  dom.cashIncomeRequestPreview.textContent = [
    "Cash 请求预览：",
    income.source_label || incomeObjectName(income),
    `School 原始金额 ${formatCurrency(income.amount, income.currency)}`,
    `实际到账 ${formatCurrency(amount, currency)}`,
    Number.isFinite(exchangeRate) ? `参考汇率 ${exchangeRate}` : "",
  ].filter(Boolean).join(" / ");
}

function calculatedCashIncomeExchangeRate(income, actualAmount, actualCurrency) {
  if (actualCurrency === "JPY") {
    return 1;
  }

  const originalJpy = Number(income.amount_jpy || (income.currency === "JPY" ? income.amount : 0));
  if (!Number.isFinite(actualAmount) || actualAmount <= 0 || !Number.isFinite(originalJpy) || originalJpy <= 0) {
    return NaN;
  }

  return roundDecimal(actualAmount / originalJpy, 7);
}

function defaultCashIncomeNote(income) {
  if (income.source_type === "part_time_work") {
    return `${income.source_label || "外部塾打工收入"}，JPY工资总额${formatCurrency(income.amount_jpy || income.amount, "JPY")}。`;
  }
  return income.note || income.source_label || incomeCategoryLabel(income.income_category);
}

function buildCashIncomeRequestNote(income, amount, currency, exchangeRate) {
  const base = dom.cashIncomeNoteInput.value.trim();
  return buildCashIncomeRequestNoteFromBase(income, amount, currency, exchangeRate, base);
}

function buildCashIncomeRequestNoteFromBase(income, amount, currency, exchangeRate, baseNote) {
  const base = safeText(baseNote).trim();
  const requiredText = `${income.source_label || incomeObjectName(income)}，School原始金额${formatCurrency(income.amount, income.currency)}，实际到账${formatCurrency(amount, currency)}${exchangeRate ? `，参考汇率${exchangeRate}` : ""}`;
  if (!base) {
    return requiredText;
  }
  return base.includes("实际到账") ? base : `${base}；${requiredText}`;
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

    return true;
  });
}

function canRequestCashIncome(row) {
  if (!row || row.status !== "pending") {
    return false;
  }

  const event = row.cashIncomeLinkageEvent;
  if (!event) {
    return true;
  }

  return event.sync_status === "cash_rejected" || event.cash_request_status === "rejected";
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

function renderCashSyncSummary(event) {
  if (!event) {
    return "-";
  }

  const amountText = event.payment_amount && event.payment_currency
    ? `<span class="income-cash-amount">${escapeHtml(formatCurrency(event.payment_amount, event.payment_currency))}</span>`
    : "";
  return `
    <div class="income-cash-sync-cell">
      ${renderCashSyncBadge(event)}
      ${amountText}
    </div>
  `;
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

function clearCashIncomeRequestErrors() {
  dom.cashIncomeRequestError.textContent = "";
  dom.cashIncomeRequestError.classList.add("is-hidden");
  for (const fieldId of ["actualAmount", "actualCurrency", "exchangeRate", "cashAccount", "note"]) {
    clearCashIncomeRequestFieldInvalid(fieldId);
  }
}

function showCashIncomeRequestError(message, fieldIds = []) {
  dom.cashIncomeRequestError.textContent = message;
  dom.cashIncomeRequestError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCashIncomeRequestFieldInvalid(fieldId, true);
  }
  dom.cashIncomeRequestDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function setCashIncomeRequestFieldInvalid(fieldId, invalid) {
  const field = dom.cashIncomeRequestDialog.querySelector(`[data-cash-income-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearCashIncomeRequestFieldInvalid(fieldId) {
  setCashIncomeRequestFieldInvalid(fieldId, false);
}

function hideCashIncomeRequestErrorIfClean() {
  const hasInvalidField = Boolean(dom.cashIncomeRequestDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.cashIncomeRequestError.textContent = "";
    dom.cashIncomeRequestError.classList.add("is-hidden");
  }
}

function setCashRequestSubmitting(isSubmitting) {
  isCashRequestSubmitting = isSubmitting;
  dom.cashIncomeRequestSubmitButton.disabled = isSubmitting;
  dom.cashIncomeRequestCancelButton.disabled = isSubmitting;
  dom.cashIncomeRequestSubmitButton.textContent = isSubmitting ? "提交中..." : "提交 Cash 确认";
}

function setBatchCashIncomeSubmitting(isSubmitting) {
  isBatchCashSubmitting = isSubmitting;
  dom.batchCashIncomeSubmitButton.disabled = isSubmitting;
  dom.batchCashIncomeCancelButton.disabled = isSubmitting;
  dom.batchCashIncomeSubmitButton.textContent = isSubmitting ? "提交中..." : "提交所选 Cash 确认";
  renderBatchCashIncomeRows();
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
