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
let batchCashIncomeRows = [];
let isBatchCashSubmitting = false;
let initialMonth = "";

export function initIncomePage() {
  cacheDom();
  initSchoolAuth();
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
  dom.batchCashIncomeTotal = document.querySelector("#batchCashIncomeTotal");
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
  dom.batchCashIncomeTableBody.addEventListener("click", handleBatchCashIncomeClick);
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

function setDefaultFilters(overrides = null) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, overrides?.month || initialMonth || currentYearMonth());
  dom.studentSelect.value = DEFAULT_FILTERS.studentId;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.accountSelect.value = DEFAULT_FILTERS.accountId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  updateMonthScopedNavigation(getYearMonthSelectValue(dom.yearFilter, dom.monthFilter));
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
    const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter) || currentYearMonth();
    await loadIncomeMonth(month);
    updateUrlMonthParams(month);
    updateMonthScopedNavigation(month);
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

  updateUrlMonthParams(filters.month);
  updateMonthScopedNavigation(filters.month);

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
  const primary = businessNameById(row.business_entity_id);
  const secondary = [
    incomeAccountDisplayName(row),
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
  return `
    <div class="income-row-actions">
      <a class="button table-action-button" href="${escapeAttribute(incomeDetailHref(row.id))}">详情</a>
      ${cashButton}
    </div>
  `;
}

function incomeDetailHref(incomeId) {
  const params = new URLSearchParams();
  params.set("id", incomeId);
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (month) {
    const [year, monthPart] = month.split("-");
    params.set("year", year);
    params.set("month", monthPart);
  }
  return `./income-detail.html?${params.toString()}`;
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
    receivedDate: currentJapanDate(),
    accountId: "",
    note: defaultCashIncomeNote(income),
    exchangeRate: "",
    theoreticalAmount: "",
    roundingMode: "",
    rateStatus: "",
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
  updateBatchCashIncomeDerivedValues();
  dom.batchCashIncomeTableBody.innerHTML = batchCashIncomeRows.map((state) => {
    const income = state.income;
    return `
      <tr data-batch-income-row-id="${escapeAttribute(income.id)}">
        <td>${escapeHtml(incomeObjectName(income))}</td>
        <td class="income-nowrap">${escapeHtml(formatMonth(income.year_month))}</td>
        <td><input data-batch-income-date="${escapeAttribute(income.id)}" type="date" value="${escapeAttribute(state.receivedDate)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
        <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(income.amount, income.currency))}</td>
        <td><input data-batch-income-amount="${escapeAttribute(income.id)}" type="number" min="0" step="0.01" inputmode="decimal" value="${escapeAttribute(state.amount)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
        <td>
          <select data-batch-income-currency="${escapeAttribute(income.id)}" ${isBatchCashSubmitting ? "disabled" : ""}>
            ${CASH_INCOME_CURRENCIES.map((currency) => `<option value="${escapeAttribute(currency)}" ${currency === state.currency ? "selected" : ""}>${escapeHtml(currency)}</option>`).join("")}
          </select>
        </td>
        <td>${renderBatchCashIncomeRateReference(state)}</td>
        <td>
          <select data-batch-income-account="${escapeAttribute(income.id)}" ${isBatchCashSubmitting ? "disabled" : ""}>
            ${renderBatchCashIncomeAccountOptions(state)}
          </select>
        </td>
        <td><input data-batch-income-note="${escapeAttribute(income.id)}" type="text" value="${escapeAttribute(state.note)}" ${isBatchCashSubmitting ? "disabled" : ""}></td>
        <td>${escapeHtml(state.result || "-")}</td>
      </tr>
      ${renderBatchCashIncomeRateRow(state)}
    `;
  }).join("");
  updateBatchCashIncomeTotal();
}

function renderBatchCashIncomeRateReference(state) {
  if (state.currency !== "CNY") {
    return `
      <div class="expense-rate-assist expense-rate-assist--muted">
        <span>JPY 到账不需要汇率</span>
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
        <button class="button compact-button" title="四舍五入" data-batch-income-round="${escapeAttribute(state.income.id)}" data-rounding-mode="round" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>≈</button>
        <button class="button compact-button" title="向上取整" data-batch-income-round="${escapeAttribute(state.income.id)}" data-rounding-mode="ceil" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>↑</button>
        <button class="button compact-button" title="向下取整" data-batch-income-round="${escapeAttribute(state.income.id)}" data-rounding-mode="floor" type="button" ${isBatchCashSubmitting ? "disabled" : ""}>↓</button>
      </div>
      <div class="expense-rate-assist-status">${escapeHtml(state.rateStatus || incomeRateAssistHint(state))}</div>
    </div>
  `;
}

function renderBatchCashIncomeRateRow(state) {
  if (state.currency !== "CNY") {
    return "";
  }

  const incomeId = state.income.id;
  return `
    <tr class="expense-batch-cash-rate-row income-batch-cash-rate-row" data-batch-income-row-id="${escapeAttribute(incomeId)}">
      <td colspan="10">
        <div class="expense-rate-toolbar-card">
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

  const shouldRerender = Boolean(event.target.closest("[data-batch-income-currency]"));
  const shouldRefreshRateReference = event.type === "change" && Boolean(
    event.target.closest("[data-batch-income-rate]")
    || event.target.closest("[data-batch-income-amount]")
  );
  syncBatchCashIncomeRowsFromDom();
  updateBatchCashIncomeDerivedValues();
  if (shouldRerender) {
    for (const state of batchCashIncomeRows) {
      const account = cashEligibleAccounts.find((row) => row.id === state.accountId);
      if (account?.currency !== state.currency) {
        state.accountId = "";
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
  if (!state || state.currency !== "CNY") {
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

    if (!/^\d{4}-\d{2}-\d{2}$/.test(state.receivedDate || "")) {
      state.result = "请选择实际到账日";
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
        actualReceivedDate: state.receivedDate,
        exchangeRate: state.currency === "JPY" ? 1 : exchangeRate,
        note: buildCashIncomeRequestNoteFromBase(
          income,
          actualReceivedAmount,
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
    showBatchCashIncomeError("部分记录缺少必要信息，未提交任何请求。");
    return null;
  }

  if (!payloads.length) {
    showBatchCashIncomeError("没有可提交的收入记录。");
    return null;
  }

  return payloads;
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

function updateBatchCashIncomeDerivedValues() {
  for (const state of batchCashIncomeRows) {
    updateBatchCashIncomeDerivedValue(state);
  }
}

function updateBatchCashIncomeDerivedValue(state) {
  if (state.currency !== "CNY") {
    state.theoreticalAmount = "";
    state.roundingMode = "";
    state.rateStatus = "";
    return;
  }

  const rate = parseNumberInput(state.exchangeRate);
  const jpyAmount = originalIncomeJpyAmount(state.income);
  if (!Number.isFinite(rate) || rate <= 0 || !Number.isFinite(jpyAmount) || jpyAmount <= 0) {
    state.theoreticalAmount = "";
    return;
  }

  state.theoreticalAmount = formatDecimal(jpyAmount * rate, 2);
}

async function fetchTodayJpyCnyRateForIncomeState(state) {
  try {
    const rate = await fetchLatestJpyCnyRate();
    state.exchangeRate = formatRateValue(rate);
    updateBatchCashIncomeDerivedValue(state);
    state.rateStatus = "已获取今日参考汇率，可取整或手动修改金额。";
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
  state.roundingMode = ROUNDING_MODE_LABELS[mode] ? mode : "";
  state.rateStatus = `${ROUNDING_MODE_LABELS[mode] || "取整"}已填入实际到账金额，仍可手动修改。`;
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

function originalIncomeJpyAmount(income) {
  const amountJpy = Number(income?.amount_jpy);
  if (Number.isFinite(amountJpy) && amountJpy > 0) {
    return amountJpy;
  }

  const amount = Number(income?.amount);
  if (income?.currency === "JPY" && Number.isFinite(amount) && amount > 0) {
    return amount;
  }

  return NaN;
}

function formatTheoreticalCnyAmount(value) {
  const amount = parseNumberInput(value);
  return Number.isFinite(amount) && amount > 0 ? `${formatDecimal(amount, 2)} CNY` : "-";
}

function incomeRateAssistHint(state) {
  if (!Number.isFinite(originalIncomeJpyAmount(state.income))) {
    return "缺少 JPY 原始金额，可手动输入实际到账金额。";
  }

  return "获取或输入汇率后可计算理论到账金额。";
}

function incomeRateAssistNote(state) {
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
    parts.push(`理论到账 ${formatDecimal(theoreticalAmount, 2)} CNY`);
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
  const numberValue = Number(value);
  if (!Number.isFinite(numberValue)) {
    return "";
  }

  return numberValue.toFixed(decimals).replace(/0+$/, "").replace(/\.$/, "");
}

function defaultCashIncomeNote(income) {
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
  const requiredText = [
    `${income.source_label || incomeObjectName(income)}，实际到账日${receivedDate}，School原始金额${formatCurrency(income.amount, income.currency)}，实际到账${formatCurrency(amount, currency)}${exchangeRate ? `，参考汇率${exchangeRate}` : ""}`,
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

function cashIncomeRequestNotAllowedMessage(row) {
  if (!row) return "收入记录不存在，请刷新后重试。";
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
  if (value === "synced") return "status-paid";
  if (value === "failed" || value === "cash_rejected" || value === "blocked") return "status-cancelled";
  return "status-neutral";
}

function cashLinkageStatusHint(value) {
  if (value === "pending" || value === "pending_cash_request" || value === "awaiting_cash_confirmation") return "请求已生成";
  if (value === "synced") return "已生成流水";
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
