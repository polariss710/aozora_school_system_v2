import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";
import { fetchProfitSummaryPageData } from "../api/profit-summary-api.js?v=be-ui-20260806-1";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatMonth, safeText } from "../utils/format.js";

const dom = {};
let pageData = null;
let resultRequestId = 0;

const FILTER_PENDING_MESSAGE = "筛选条件已变化；点击“查询”后刷新结果。";
const FILTER_RESET_MESSAGE = "已重置筛选条件；点击“查询”后刷新结果。";

const REQUIRED_DOM_SELECTORS = {
  messageArea: "#profitSummaryMessageArea",
  filterForm: "#profitSummaryFilterForm",
  yearFilter: "#profitSummaryYearFilter",
  monthFilter: "#profitSummaryMonthFilter",
  currencySelect: "#profitSummaryCurrencySelect",
  resetButton: "#profitSummaryResetButton",
  loadingState: "#profitSummaryLoadingState",
  summaryGrid: "#profitSummaryGrid",
  currencyTableBody: "#profitSummaryCurrencyTableBody",
  auditTableBody: "#profitSummaryAuditTableBody",
  incomeDetailCount: "#profitSummaryIncomeDetailCount",
  incomeDetailTableBody: "#profitSummaryIncomeDetailTableBody",
  expenseDetailCount: "#profitSummaryExpenseDetailCount",
  expenseDetailTableBody: "#profitSummaryExpenseDetailTableBody",
};

export function initProfitSummaryPage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。");
    renderEmptyState();
    return;
  }

  loadProfitSummary();
}

function cacheDom() {
  const missingSelectors = [];
  Object.entries(REQUIRED_DOM_SELECTORS).forEach(([key, selector]) => {
    dom[key] = document.querySelector(selector);
    if (!dom[key]) missingSelectors.push(selector);
  });
  if (missingSelectors.length) {
    throw new Error(`利润分析页面缺少 DOM 容器：${missingSelectors.join(", ")}`);
  }
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    loadProfitSummary();
  });
  [dom.yearFilter, dom.monthFilter, dom.currencySelect].forEach((control) => {
    control.addEventListener("change", () => invalidateQueryResults(FILTER_PENDING_MESSAGE));
  });
  dom.resetButton.addEventListener("click", () => {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
    dom.currencySelect.value = "";
    invalidateQueryResults(FILTER_RESET_MESSAGE);
  });
}

async function loadProfitSummary() {
  const requestId = ++resultRequestId;
  const filters = readFilters();
  if (!filters.month) {
    showMessage("error", "请选择有效月份。");
    return;
  }

  setLoading(true);
  showMessage("info", "正在加载学校整体利润分析数据...");
  try {
    const nextPageData = await fetchProfitSummaryPageData(filters);
    if (requestId !== resultRequestId) return;
    pageData = nextPageData;
    renderSummary(pageData, filters);
    showMessage("success", "学校整体利润分析数据已加载。");
  } catch (error) {
    if (requestId !== resultRequestId) return;
    pageData = null;
    renderEmptyState();
    showMessage("error", `读取利润分析数据失败：${error.message || error}`);
  } finally {
    if (requestId === resultRequestId) setLoading(false);
  }
}

function invalidateQueryResults(message) {
  resultRequestId += 1;
  pageData = null;
  renderEmptyState();
  setLoading(false);
  showMessage("info", message);
}

function readFilters() {
  return {
    month: getYearMonthSelectValue(dom.yearFilter, dom.monthFilter),
    currency: dom.currencySelect.value || "",
  };
}

function renderSummary(data, filters) {
  const rows = filterByCurrency(data.summaryRows, filters.currency);
  const incomeDetails = filterByCurrency(data.incomeRecords, filters.currency);
  const expenseDetails = filterByCurrency(data.expenseRecords, filters.currency);

  dom.summaryGrid.innerHTML = [
    renderSummaryCard("月份", formatMonth(filters.month)),
    renderSummaryCard("汇总范围", "学校整体"),
    renderSummaryCard("币种筛选", filters.currency || "全部"),
    ...rows.flatMap((row) => [
      renderSummaryCard(`经营收入 ${row.currency}`, formatCurrency(row.income_amount, row.currency)),
      renderSummaryCard(`经营支出 ${row.currency}`, formatCurrency(row.expense_amount, row.currency)),
      renderSummaryCard(`经营利润 ${row.currency}`, formatCurrency(row.profit_amount, row.currency)),
    ]),
  ].join("");

  dom.currencyTableBody.innerHTML = rows.length
    ? rows.map((row) => `
      <tr>
        <td>${escapeHtml(row.currency)}</td>
        <td class="number-cell">${escapeHtml(String(row.income_count))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.income_amount, row.currency))}</td>
        <td class="number-cell">${escapeHtml(String(row.expense_count))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.expense_amount, row.currency))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.teacher_wage_amount, row.currency))}</td>
        <td class="number-cell ${Number(row.profit_amount) < 0 ? "amount-negative" : "amount-positive"}">${escapeHtml(formatCurrency(row.profit_amount, row.currency))}</td>
      </tr>
    `).join("")
    : emptyRow(7, "该月份暂无对应币种的经营收支。");

  dom.auditTableBody.innerHTML = data.auditRows.length
    ? data.auditRows.map((row) => `
      <tr>
        <td>${escapeHtml(row.name)}</td>
        <td>${escapeHtml(row.profit_policy)}</td>
        <td class="number-cell">${escapeHtml(String(row.record_count))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.jpy_amount, "JPY"))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.cny_amount, "CNY"))}</td>
        <td>${escapeHtml(row.note)}</td>
      </tr>
    `).join("")
    : emptyRow(6, "暂无资金流审计参考记录。");

  renderIncomeDetails(incomeDetails);
  renderExpenseDetails(expenseDetails);
}

function renderEmptyState() {
  dom.summaryGrid.innerHTML = "";
  dom.currencyTableBody.innerHTML = "";
  dom.auditTableBody.innerHTML = "";
  dom.incomeDetailCount.textContent = "0 条";
  dom.incomeDetailTableBody.innerHTML = "";
  dom.expenseDetailCount.textContent = "0 条";
  dom.expenseDetailTableBody.innerHTML = "";
}

function renderIncomeDetails(rows) {
  dom.incomeDetailCount.textContent = `${rows.length} 条`;
  dom.incomeDetailTableBody.innerHTML = rows.length
    ? rows.map((row) => `
      <tr>
        <td><a class="button table-action-button" href="./income-detail.html?id=${escapeAttribute(row.id)}">查看</a></td>
        <td>${escapeHtml(formatDateOnly(row.income_date))}</td>
        <td>${escapeHtml(displayValue(row.income_category))}</td>
        <td class="profit-detail-text-cell" title="${escapeAttribute(displayValue(row.description))}"><span class="table-cell-summary">${escapeHtml(displayValue(row.description))}</span></td>
        <td>${escapeHtml(displayValue(row.currency))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.amount_jpy, "JPY"))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.amount_cny, "CNY"))}</td>
        <td>${escapeHtml(displayValue(row.status))}</td>
        <td class="profit-detail-text-cell" title="${escapeAttribute(displayValue(row.note))}"><span class="table-cell-summary">${escapeHtml(displayValue(row.note))}</span></td>
      </tr>
    `).join("")
    : emptyRow(10, "暂无符合条件的收入明细。");
}

function renderExpenseDetails(rows) {
  dom.expenseDetailCount.textContent = `${rows.length} 条`;
  dom.expenseDetailTableBody.innerHTML = rows.length
    ? rows.map((row) => `
      <tr>
        <td><a class="button table-action-button" href="./expense-detail.html?id=${escapeAttribute(row.id)}">查看</a></td>
        <td>${escapeHtml(formatDateOnly(row.expense_date))}</td>
        <td>${escapeHtml(expenseCategoryLabel(row.expense_category))}</td>
        <td class="profit-detail-text-cell" title="${escapeAttribute(displayValue(row.description))}"><span class="table-cell-summary">${escapeHtml(displayValue(row.description))}</span></td>
        <td>${escapeHtml(displayValue(row.currency))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.amount_jpy, "JPY"))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.amount_cny, "CNY"))}</td>
        <td>${escapeHtml(displayValue(row.status))}</td>
        <td>${escapeHtml(reimbursementStatusLabel(row.reimbursement_status, row.expense_category))}</td>
        <td class="profit-detail-text-cell" title="${escapeAttribute(displayValue(row.note))}"><span class="table-cell-summary">${escapeHtml(displayValue(row.note))}</span></td>
      </tr>
    `).join("")
    : emptyRow(11, "暂无符合条件的支出明细。");
}

function filterByCurrency(rows, currency) {
  return currency ? rows.filter((row) => row.currency === currency) : rows;
}

function renderSummaryCard(title, value) {
  return `<article class="summary-card"><div class="summary-card-title">${escapeHtml(title)}</div><div class="summary-card-value">${escapeHtml(value)}</div></article>`;
}

function emptyRow(colspan, message) {
  return `<tr><td colspan="${colspan}" class="state-text">${escapeHtml(message)}</td></tr>`;
}

function expenseCategoryLabel(category) {
  return category === "teacher_wage" ? "老师工资 / teacher_wage" : displayValue(category);
}

function reimbursementStatusLabel(value, expenseCategory = "") {
  if (expenseCategory === "teacher_wage") {
    if (value === "pending") return "工资垫付待清算";
    if (value === "not_required") return "无需清算（公司账户支付）";
  }
  if (value === "pending") return "待报销";
  if (value === "paid") return "已报销";
  if (value === "not_required") return "无需报销";
  return displayValue(value);
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

function showMessage(type, message) {
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = message;
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
