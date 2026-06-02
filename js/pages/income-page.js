import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchIncomeLookups, fetchIncomeRecords } from "../api/income-api.js";
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
  received: "已收款",
};

const INCOME_CATEGORY_LABELS = {
  tuition: "学费",
};

const PAYMENT_METHOD_LABELS = {
  alipay: "支付宝",
  bank_transfer: "银行转账",
  cash: "现金",
  card: "银行卡",
  wechat: "微信",
};

const dom = {};
let students = [];
let businessEntities = [];
let accounts = [];
let incomeRecords = [];
let loadedMonth = "";

export function initIncomePage() {
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
      <td>${escapeHtml(accountNameById(row.account_id))}</td>
      <td><span class="status-badge status-neutral">${escapeHtml(incomeCategoryLabel(row.income_category))}</span></td>
      <td class="income-nowrap">${escapeHtml(displayValue(row.currency))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(row.amount_jpy, "JPY"))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(row.amount_cny, "CNY"))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(displayValue(row.exchange_rate))}</td>
      <td>${escapeHtml(paymentMethodLabel(row.payment_method))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(incomeStatusLabel(row.status))}</span></td>
      <td>${escapeHtml(displayValue(row.receipt_status))}</td>
      <td class="income-nowrap">${escapeHtml(booleanLabel(row.include_in_student_settlement))}</td>
      <td class="income-note-cell">${escapeHtml(displayValue(row.note))}</td>
      <td class="income-nowrap">${escapeHtml(formatDate(row.created_at))}</td>
      <td class="income-nowrap">${escapeHtml(formatDate(row.updated_at))}</td>
    </tr>
  `).join("");
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
    accountNameById(row.account_id),
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
  if (status === "received") {
    return "status-paid";
  }

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
