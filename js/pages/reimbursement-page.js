import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchReimbursementItemCounts,
  fetchReimbursementLookups,
  fetchReimbursementRecords,
  fetchReimbursementTransactionCounts,
} from "../api/reimbursement-api.js";
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
  fromAccountId: "",
  toAccountId: "",
  currency: "",
  status: "",
  hasItems: "",
  hasTransactions: "",
  keyword: "",
};

const REIMBURSEMENT_STATUS_LABELS = {
  paid: "已支付",
};

const dom = {};
let businessEntities = [];
let accounts = [];
let reimbursementRecords = [];
let itemCounts = new Map();
let transactionCounts = new Map();
let loadedMonth = "";

export function initReimbursementPage() {
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
    renderReimbursements([]);
    return;
  }

  loadInitialData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#reimbursementMessageArea");
  dom.filterForm = document.querySelector("#reimbursementFilterForm");
  dom.yearFilter = document.querySelector("#reimbursementYearFilter");
  dom.monthFilter = document.querySelector("#reimbursementMonthFilter");
  dom.businessEntitySelect = document.querySelector("#reimbursementBusinessEntitySelect");
  dom.fromAccountSelect = document.querySelector("#reimbursementFromAccountSelect");
  dom.toAccountSelect = document.querySelector("#reimbursementToAccountSelect");
  dom.currencySelect = document.querySelector("#reimbursementCurrencySelect");
  dom.statusSelect = document.querySelector("#reimbursementStatusSelect");
  dom.hasItemsSelect = document.querySelector("#reimbursementHasItemsSelect");
  dom.hasTransactionsSelect = document.querySelector("#reimbursementHasTransactionsSelect");
  dom.keywordInput = document.querySelector("#reimbursementKeywordInput");
  dom.resetButton = document.querySelector("#reimbursementResetButton");
  dom.tableBody = document.querySelector("#reimbursementTableBody");
  dom.loadingState = document.querySelector("#reimbursementLoadingState");
  dom.emptyState = document.querySelector("#reimbursementEmptyState");
  dom.reimbursementCount = document.querySelector("#reimbursementCount");
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
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.fromAccountSelect.value = DEFAULT_FILTERS.fromAccountId;
  dom.toAccountSelect.value = DEFAULT_FILTERS.toAccountId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.hasItemsSelect.value = DEFAULT_FILTERS.hasItems;
  dom.hasTransactionsSelect.value = DEFAULT_FILTERS.hasTransactions;
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载报销管理数据...");

  try {
    const lookups = await fetchReimbursementLookups();
    businessEntities = lookups.businessEntities;
    accounts = lookups.accounts;
    renderMasterOptions();
    await loadReimbursementMonth(currentYearMonth());
    applyCurrentFilters();
    showMessage("success", "报销管理数据已加载。");
  } catch (error) {
    businessEntities = [];
    accounts = [];
    reimbursementRecords = [];
    itemCounts = new Map();
    transactionCounts = new Map();
    loadedMonth = "";
    renderMasterOptions();
    renderDataOptions([]);
    renderReimbursements([]);
    showMessage("error", `读取报销管理数据失败：${error.message || error}`);
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
    showMessage("info", "正在加载报销记录...");

    try {
      await loadReimbursementMonth(filters.month);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "报销记录已加载。");
    } catch (error) {
      reimbursementRecords = [];
      itemCounts = new Map();
      transactionCounts = new Map();
      loadedMonth = "";
      renderDataOptions([]);
      renderReimbursements([]);
      showMessage("error", `读取报销记录失败：${error.message || error}`);
    } finally {
      setLoading(false);
    }
    return;
  }

  applyCurrentFilters();
}

async function loadReimbursementMonth(month) {
  reimbursementRecords = await fetchReimbursementRecords(month);
  const ids = reimbursementRecords.map((row) => row.id).filter(Boolean);
  const [itemRows, transactionRows] = await Promise.all([
    fetchReimbursementItemCounts(ids),
    fetchReimbursementTransactionCounts(ids),
  ]);

  itemCounts = countByKey(itemRows, "reimbursement_id");
  transactionCounts = countByKey(transactionRows, "related_id");
  loadedMonth = month;
  renderDataOptions(reimbursementRecords);
}

function applyCurrentFilters() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  restoreFilterSelections(filters);
  renderReimbursements(filterReimbursements(reimbursementRecords, filters));
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
    fromAccountId: dom.fromAccountSelect.value,
    toAccountId: dom.toAccountSelect.value,
    currency: dom.currencySelect.value,
    status: dom.statusSelect.value,
    hasItems: dom.hasItemsSelect.value,
    hasTransactions: dom.hasTransactionsSelect.value,
    keyword: dom.keywordInput.value.trim(),
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.fromAccountSelect.value = filters.fromAccountId;
  dom.toAccountSelect.value = filters.toAccountId;
  dom.currencySelect.value = filters.currency;
  dom.statusSelect.value = filters.status;
  dom.hasItemsSelect.value = filters.hasItems;
  dom.hasTransactionsSelect.value = filters.hasTransactions;
  dom.keywordInput.value = filters.keyword;
}

function renderMasterOptions() {
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
  renderEntityOptions(dom.fromAccountSelect, accounts, accountName);
  renderEntityOptions(dom.toAccountSelect, accounts, accountName);
}

function renderDataOptions(rows) {
  renderValueOptions(dom.currencySelect, distinctValues(rows, "currency"), displayValue);
  renderValueOptions(dom.statusSelect, distinctValues(rows, "status"), reimbursementStatusLabel);
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

function renderReimbursements(rows) {
  dom.reimbursementCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td class="reimbursement-nowrap">${escapeHtml(formatDateOnly(row.reimbursement_date))}</td>
      <td class="reimbursement-nowrap">${escapeHtml(formatMonth(row.year_month))}</td>
      <td>${escapeHtml(businessNameById(row.business_entity_id))}</td>
      <td>${escapeHtml(accountNameById(row.from_account_id))}</td>
      <td>${escapeHtml(accountNameById(row.to_account_id))}</td>
      <td class="reimbursement-nowrap">${escapeHtml(displayValue(row.currency))}</td>
      <td class="number-cell reimbursement-nowrap">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(reimbursementStatusLabel(row.status))}</span></td>
      <td class="number-cell reimbursement-nowrap">${escapeHtml(displayCount(itemCount(row.id)))}</td>
      <td class="number-cell reimbursement-nowrap">${escapeHtml(displayCount(transactionCount(row.id)))}</td>
      <td class="reimbursement-note-cell"><span class="table-cell-summary">${escapeHtml(displayValue(row.note))}</span></td>
      <td class="reimbursement-nowrap">${escapeHtml(formatDate(row.created_at))}</td>
      <td class="reimbursement-nowrap">${escapeHtml(formatDate(row.updated_at))}</td>
    </tr>
  `).join("");
}

function filterReimbursements(rows, filters) {
  return rows.filter((row) => {
    if (filters.businessEntityId && row.business_entity_id !== filters.businessEntityId) {
      return false;
    }

    if (filters.fromAccountId && row.from_account_id !== filters.fromAccountId) {
      return false;
    }

    if (filters.toAccountId && row.to_account_id !== filters.toAccountId) {
      return false;
    }

    if (filters.currency && row.currency !== filters.currency) {
      return false;
    }

    if (filters.status && row.status !== filters.status) {
      return false;
    }

    if (!matchesCountFilter(itemCount(row.id), filters.hasItems)) {
      return false;
    }

    if (!matchesCountFilter(transactionCount(row.id), filters.hasTransactions)) {
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
    accountNameById(row.from_account_id),
    accountNameById(row.to_account_id),
    row.currency,
    reimbursementStatusLabel(row.status),
    row.status,
    row.note,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function matchesCountFilter(count, filterValue) {
  if (!filterValue) {
    return true;
  }

  if (filterValue === "yes") {
    return count > 0;
  }

  if (filterValue === "no") {
    return count === 0;
  }

  return true;
}

function countByKey(rows, key) {
  const result = new Map();

  for (const row of rows) {
    const value = row[key];
    if (!value) {
      continue;
    }

    result.set(value, (result.get(value) || 0) + 1);
  }

  return result;
}

function itemCount(id) {
  return itemCounts.get(id) || 0;
}

function transactionCount(id) {
  return transactionCounts.get(id) || 0;
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

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
}

function accountName(account) {
  const name = safeText(account.name) || "未设置";
  const currency = safeText(account.currency);
  return currency ? `${name} / ${currency}` : name;
}

function reimbursementStatusLabel(value) {
  return REIMBURSEMENT_STATUS_LABELS[value] || displayValue(value);
}

function statusClass(status) {
  if (status === "paid") {
    return "status-paid";
  }

  return "status-neutral";
}

function formatDateOnly(value) {
  return safeText(value) || "-";
}

function displayCount(value) {
  return Number(value || 0).toLocaleString("zh-CN");
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
