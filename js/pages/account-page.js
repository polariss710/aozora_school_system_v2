import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchAccountTransactions,
  fetchAccounts,
  fetchBusinessEntitiesForAccounts,
} from "../api/account-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  accountId: "",
  businessEntityId: "",
  currency: "",
  transactionType: "",
};

const TRANSACTION_TYPE_LABELS = {
  payment: "支付扣款",
  payment_reversal: "支付撤销",
  income: "收入",
  expense: "支出",
  transfer: "转账",
  adjustment: "调整",
};

const ACCOUNT_TYPE_LABELS = {
  cash: "现金",
  bank: "银行",
  wallet: "钱包",
  receivable: "应收",
  payable: "应付",
};

const dom = {};
let accounts = [];
let businessEntities = [];
let transactions = [];

export function initAccountPage() {
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
    renderAccounts([]);
    renderTransactions([]);
    return;
  }

  loadAccountData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#accountMessageArea");
  dom.filterForm = document.querySelector("#accountFilterForm");
  dom.yearFilter = document.querySelector("#accountYearFilter");
  dom.monthFilter = document.querySelector("#accountMonthFilter");
  dom.accountSelect = document.querySelector("#accountSelect");
  dom.businessEntitySelect = document.querySelector("#accountBusinessEntitySelect");
  dom.currencySelect = document.querySelector("#accountCurrencySelect");
  dom.transactionTypeSelect = document.querySelector("#transactionTypeSelect");
  dom.resetButton = document.querySelector("#accountResetButton");
  dom.accountGrid = document.querySelector("#accountGrid");
  dom.accountLoadingState = document.querySelector("#accountLoadingState");
  dom.accountEmptyState = document.querySelector("#accountEmptyState");
  dom.transactionTableBody = document.querySelector("#accountTransactionTableBody");
  dom.transactionLoadingState = document.querySelector("#accountTransactionLoadingState");
  dom.transactionEmptyState = document.querySelector("#accountTransactionEmptyState");
  dom.transactionCount = document.querySelector("#accountTransactionCount");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    loadAccountData();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    loadAccountData();
  });
}

function setDefaultFilters() {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  dom.accountSelect.value = DEFAULT_FILTERS.accountId;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  dom.transactionTypeSelect.value = DEFAULT_FILTERS.transactionType;
}

async function loadAccountData() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  if (!filters) {
    return;
  }

  setLoading(true);
  showMessage("info", "正在加载账户管理数据...");

  try {
    const [accountRows, businessEntityRows, transactionRows] = await Promise.all([
      fetchAccounts(),
      fetchBusinessEntitiesForAccounts(),
      fetchAccountTransactions(filters),
    ]);

    accounts = accountRows;
    businessEntities = businessEntityRows;
    transactions = transactionRows;

    renderAccountOptions(accounts);
    renderBusinessEntityOptions(businessEntities);
    restoreFilterSelections(filters);
    renderAccounts(filterAccountsForDisplay(accounts, filters));
    renderTransactions(transactions);
    showMessage("success", "账户管理数据已加载。");
  } catch (error) {
    accounts = [];
    businessEntities = [];
    transactions = [];
    renderAccountOptions([]);
    renderBusinessEntityOptions([]);
    renderAccounts([]);
    renderTransactions([]);
    showMessage("error", `读取账户管理数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readFilters() {
  const selectedMonth = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!selectedMonth) {
    showMessage("error", "请选择正确的年月。");
    return null;
  }

  return {
    month: selectedMonth,
    accountId: dom.accountSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    currency: dom.currencySelect.value,
    transactionType: dom.transactionTypeSelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.accountSelect.value = filters.accountId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.currencySelect.value = filters.currency;
  dom.transactionTypeSelect.value = filters.transactionType;
}

function renderAccountOptions(items) {
  const options = ['<option value="">全部</option>'];

  for (const account of items) {
    const label = [
      account.name,
      account.currency,
      formatCurrency(account.current_balance, account.currency),
    ].filter(Boolean).join(" / ");

    options.push(
      `<option value="${escapeAttribute(account.id)}">${escapeHtml(label)}</option>`
    );
  }

  dom.accountSelect.innerHTML = options.join("");
}

function renderBusinessEntityOptions(items) {
  const options = ['<option value="">全部</option>'];

  for (const entity of items) {
    const name = entity.name || entity.id;
    options.push(
      `<option value="${escapeAttribute(entity.id)}">${escapeHtml(name)}</option>`
    );
  }

  dom.businessEntitySelect.innerHTML = options.join("");
}

function filterAccountsForDisplay(items, filters) {
  return items.filter((account) => {
    if (filters.accountId && account.id !== filters.accountId) {
      return false;
    }

    if (filters.businessEntityId && account.business_entity_id !== filters.businessEntityId) {
      return false;
    }

    if (filters.currency && account.currency !== filters.currency) {
      return false;
    }

    return true;
  });
}

function renderAccounts(items) {
  dom.accountEmptyState.classList.toggle("is-hidden", items.length > 0);

  if (!items.length) {
    dom.accountGrid.innerHTML = "";
    return;
  }

  dom.accountGrid.innerHTML = items.map((account) => `
    <article class="account-card">
      <div class="account-card-header">
        <div>
          <div class="account-name">${escapeHtml(account.name)}</div>
          <div class="account-code">${escapeHtml(account.account_code || "-")}</div>
        </div>
        <span class="status-badge ${account.is_active ? "status-paid" : "status-cancelled"}">
          ${account.is_active ? "启用" : "停用"}
        </span>
      </div>
      <div class="account-balance">${escapeHtml(formatCurrency(account.current_balance, account.currency))}</div>
      <dl class="account-meta">
        <div>
          <dt>币种</dt>
          <dd>${escapeHtml(account.currency || "-")}</dd>
        </div>
        <div>
          <dt>类型</dt>
          <dd>${escapeHtml(accountTypeLabel(account.account_type))}</dd>
        </div>
        <div>
          <dt>公司账户</dt>
          <dd>${account.is_company_account ? "是" : "否"}</dd>
        </div>
        <div>
          <dt>备注</dt>
          <dd>${escapeHtml(account.note || "-")}</dd>
        </div>
      </dl>
    </article>
  `).join("");
}

function renderTransactions(items) {
  dom.transactionCount.textContent = `${items.length} 条`;
  dom.transactionEmptyState.classList.toggle("is-hidden", items.length > 0);

  if (!items.length) {
    dom.transactionTableBody.innerHTML = "";
    return;
  }

  dom.transactionTableBody.innerHTML = items.map((item) => {
    const account = findAccount(item.account_id);
    const businessEntity = findBusinessEntity(item.business_entity_id);
    const amountClass = Number(item.amount) >= 0 ? "amount-positive" : "amount-negative";
    const relatedText = [item.related_table, item.related_id].filter(Boolean).join(" / ") || "-";
    const description = item.description || item.note || "-";

    return `
      <tr>
        <td>${escapeHtml(formatDate(item.transaction_date))}</td>
        <td>${escapeHtml(account?.name || item.account_id || "-")}</td>
        <td>${escapeHtml(businessEntity?.name || item.business_entity_id || "-")}</td>
        <td>${escapeHtml(transactionTypeLabel(item.transaction_type))}</td>
        <td>${escapeHtml(item.currency || "-")}</td>
        <td class="number-cell ${amountClass}">${escapeHtml(formatCurrency(item.amount, item.currency))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(item.balance_after, item.currency))}</td>
        <td class="description-cell">${escapeHtml(description)}</td>
        <td>${escapeHtml(relatedText)}</td>
        <td>${escapeHtml(formatDate(item.created_at))}</td>
      </tr>
    `;
  }).join("");
}

function findAccount(accountId) {
  return accounts.find((account) => account.id === accountId);
}

function findBusinessEntity(entityId) {
  return businessEntities.find((entity) => entity.id === entityId);
}

function transactionTypeLabel(type) {
  return TRANSACTION_TYPE_LABELS[type] || safeText(type) || "-";
}

function accountTypeLabel(type) {
  return ACCOUNT_TYPE_LABELS[type] || safeText(type) || "-";
}

function setLoading(isLoading) {
  dom.accountLoadingState.classList.toggle("is-hidden", !isLoading);
  dom.transactionLoadingState.classList.toggle("is-hidden", !isLoading);
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
