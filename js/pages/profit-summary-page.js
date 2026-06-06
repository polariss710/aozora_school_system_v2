import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchProfitSummaryPageData } from "../api/profit-summary-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatMonth, safeText } from "../utils/format.js";

const CURRENCIES = ["JPY", "CNY"];

const PROFIT_POLICY_ROWS = [
  ["收入", "计入经营收入", "使用 posted 收入记录；reversed / void / cancelled 不计入。"],
  ["支出", "计入经营支出", "使用 posted 支出记录；老师工资支出单列展示但仍属于支出。"],
  ["报销", "不重复计入利润", "报销只是账户间资金流，原始支出已计入经营支出。"],
  ["老师工资支付请求", "不重复计入利润", "已支付工资通过 paid expense / teacher_wage 支出体现，支付请求只做状态参考。"],
  ["账户调整", "不计入经营利润", "属于账户余额校正，单列为非经营调整。"],
  ["账户转账/调拨", "不计入经营利润", "属于账户间资金移动，只做账户审计。"],
];

const NON_OPERATING_TRANSACTION_TYPES = new Set([
  "account_adjustment",
  "account_adjustment_reversal",
  "transfer_out",
  "transfer_in",
  "transfer_reverse_in",
  "transfer_reverse_out",
]);

const dom = {};
let pageData = null;

export function initProfitSummaryPage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  bindEvents();
  renderPolicyTable();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderBusinessEntityOptions([]);
    renderEmptyState();
    return;
  }

  loadProfitSummary();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#profitSummaryMessageArea");
  dom.filterForm = document.querySelector("#profitSummaryFilterForm");
  dom.yearFilter = document.querySelector("#profitSummaryYearFilter");
  dom.monthFilter = document.querySelector("#profitSummaryMonthFilter");
  dom.businessEntitySelect = document.querySelector("#profitSummaryBusinessEntitySelect");
  dom.resetButton = document.querySelector("#profitSummaryResetButton");
  dom.loadingState = document.querySelector("#profitSummaryLoadingState");
  dom.summaryGrid = document.querySelector("#profitSummaryGrid");
  dom.policyTableBody = document.querySelector("#profitSummaryPolicyTableBody");
  dom.currencyTableBody = document.querySelector("#profitSummaryCurrencyTableBody");
  dom.auditTableBody = document.querySelector("#profitSummaryAuditTableBody");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    loadProfitSummary();
  });

  dom.resetButton.addEventListener("click", () => {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
    dom.businessEntitySelect.value = "";
    loadProfitSummary();
  });
}

async function loadProfitSummary() {
  const filters = readFilters();
  if (!filters.month) {
    showMessage("error", "请选择有效月份。");
    return;
  }

  setLoading(true);
  showMessage("info", "正在加载利润分析数据...");

  try {
    pageData = await fetchProfitSummaryPageData(filters);
    renderBusinessEntityOptions(pageData.businessEntities, filters.businessEntityId);
    renderSummary(pageData, filters);
    showMessage("success", "利润分析数据已加载。");
  } catch (error) {
    pageData = null;
    renderEmptyState();
    showMessage("error", `读取利润分析数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readFilters() {
  return {
    month: getYearMonthSelectValue(dom.yearFilter, dom.monthFilter),
    businessEntityId: dom.businessEntitySelect.value || "",
  };
}

function renderBusinessEntityOptions(entities, selectedId = "") {
  const options = [
    '<option value="">全部</option>',
    ...(entities || []).map((entity) => {
      const code = safeText(entity.code);
      const name = safeText(entity.name) || "未命名业务归属";
      const label = code ? `${name} / ${code}` : name;
      return `<option value="${escapeAttribute(entity.id)}">${escapeHtml(label)}</option>`;
    }),
  ];

  dom.businessEntitySelect.innerHTML = options.join("");
  dom.businessEntitySelect.value = selectedId;
}

function renderSummary(data, filters) {
  const rows = buildCurrencyRows(data);
  const totals = buildOverallTotals(rows);
  const auditRows = buildAuditRows(data);

  dom.summaryGrid.innerHTML = [
    renderSummaryCard("月份", formatMonth(filters.month)),
    renderSummaryCard("业务归属", businessEntityLabel(filters.businessEntityId)),
    renderSummaryCard("经营收入 JPY", formatCurrency(totals.JPY.income, "JPY")),
    renderSummaryCard("经营支出 JPY", formatCurrency(totals.JPY.expense, "JPY")),
    renderSummaryCard("经营利润 JPY", formatCurrency(totals.JPY.profit, "JPY")),
    renderSummaryCard("经营收入 CNY", formatCurrency(totals.CNY.income, "CNY")),
    renderSummaryCard("经营支出 CNY", formatCurrency(totals.CNY.expense, "CNY")),
    renderSummaryCard("经营利润 CNY", formatCurrency(totals.CNY.profit, "CNY")),
  ].join("");

  dom.currencyTableBody.innerHTML = rows
    .map((row) => `
      <tr>
        <td>${escapeHtml(row.currency)}</td>
        <td class="number-cell">${escapeHtml(String(row.incomeCount))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.incomeAmount, row.currency))}</td>
        <td class="number-cell">${escapeHtml(String(row.expenseCount))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.expenseAmount, row.currency))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.teacherWageAmount, row.currency))}</td>
        <td class="number-cell ${row.profitAmount < 0 ? "amount-negative" : "amount-positive"}">${escapeHtml(formatCurrency(row.profitAmount, row.currency))}</td>
      </tr>
    `)
    .join("");

  dom.auditTableBody.innerHTML = auditRows
    .map((row) => `
      <tr>
        <td>${escapeHtml(row.name)}</td>
        <td>${escapeHtml(row.profitPolicy)}</td>
        <td class="number-cell">${escapeHtml(String(row.count))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.jpyAmount, "JPY"))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(row.cnyAmount, "CNY"))}</td>
        <td>${escapeHtml(row.note)}</td>
      </tr>
    `)
    .join("");
}

function renderEmptyState() {
  dom.summaryGrid.innerHTML = "";
  dom.currencyTableBody.innerHTML = "";
  dom.auditTableBody.innerHTML = "";
}

function buildCurrencyRows(data) {
  return CURRENCIES.map((currency) => {
    const incomeRecords = data.incomeRecords.filter((row) => isPosted(row.status) && row.currency === currency);
    const expenseRecords = data.expenseRecords.filter((row) => isPosted(row.status) && row.currency === currency);
    const teacherWageRecords = expenseRecords.filter((row) => row.expense_category === "teacher_wage");
    const incomeAmount = sumAmount(incomeRecords, currency);
    const expenseAmount = sumAmount(expenseRecords, currency);

    return {
      currency,
      incomeCount: incomeRecords.length,
      incomeAmount,
      expenseCount: expenseRecords.length,
      expenseAmount,
      teacherWageAmount: sumAmount(teacherWageRecords, currency),
      profitAmount: incomeAmount - expenseAmount,
    };
  });
}

function buildOverallTotals(rows) {
  return rows.reduce((totals, row) => {
    totals[row.currency] = {
      income: row.incomeAmount,
      expense: row.expenseAmount,
      profit: row.profitAmount,
    };
    return totals;
  }, {
    JPY: { income: 0, expense: 0, profit: 0 },
    CNY: { income: 0, expense: 0, profit: 0 },
  });
}

function buildAuditRows(data) {
  const paidReimbursements = data.reimbursements.filter((row) => row.status === "paid");
  const reversedReimbursements = data.reimbursements.filter((row) => row.status === "reversed");
  const paidWageRequests = data.paymentRequests.filter((row) => row.source_type === "teacher_wage" && row.status === "paid");
  const reversedWageRequests = data.paymentRequests.filter((row) => row.source_type === "teacher_wage" && row.status === "reversed");
  const adjustmentTransactions = data.accountTransactions.filter((row) =>
    row.transaction_type === "account_adjustment" || row.transaction_type === "account_adjustment_reversal"
  );
  const transferTransactions = data.accountTransactions.filter((row) =>
    row.transaction_type === "transfer_out" ||
    row.transaction_type === "transfer_in" ||
    row.transaction_type === "transfer_reverse_in" ||
    row.transaction_type === "transfer_reverse_out"
  );
  const otherAuditTransactions = data.accountTransactions.filter((row) =>
    NON_OPERATING_TRANSACTION_TYPES.has(row.transaction_type) === false
  );

  return [
    buildAuditRow("报销记录", "不计入利润", paidReimbursements, "原始支出已计入支出；这里只观察资金报销流。"),
    buildAuditRow("报销撤销", "不计入利润", reversedReimbursements, "撤销改变账户资金流，不重算经营利润。"),
    buildAuditRow("老师工资支付请求", "不重复计入利润", paidWageRequests, "工资通过 teacher_wage 支出计入；支付请求只做状态参考。"),
    buildAuditRow("老师工资支付撤销", "不计入利润", reversedWageRequests, "撤销支付是资金流和状态变化，不直接进入利润。"),
    buildAuditRow("账户调整流水", "不计入经营利润", adjustmentTransactions, "余额校正单列展示，不混入经营利润。"),
    buildAuditRow("账户转账/调拨流水", "不计入经营利润", transferTransactions, "账户间资金移动只做审计。"),
    buildAuditRow("其他账户流水", "仅参考", otherAuditTransactions, "用于发现未归类流水；利润以业务事实表为准。"),
  ];
}

function buildAuditRow(name, profitPolicy, rows, note) {
  return {
    name,
    profitPolicy,
    count: rows.length,
    jpyAmount: sumAmount(rows.filter((row) => row.currency === "JPY"), "JPY"),
    cnyAmount: sumAmount(rows.filter((row) => row.currency === "CNY"), "CNY"),
    note,
  };
}

function sumAmount(rows, currency) {
  return rows.reduce((sum, row) => {
    if (currency === "JPY" && row.amount_jpy !== undefined && row.amount_jpy !== null) {
      return sum + Number(row.amount_jpy || 0);
    }

    if (currency === "CNY" && row.amount_cny !== undefined && row.amount_cny !== null) {
      return sum + Number(row.amount_cny || 0);
    }

    return sum + Number(row.amount || 0);
  }, 0);
}

function renderPolicyTable() {
  dom.policyTableBody.innerHTML = PROFIT_POLICY_ROWS
    .map(([item, policy, note]) => `
      <tr>
        <td>${escapeHtml(item)}</td>
        <td>${escapeHtml(policy)}</td>
        <td>${escapeHtml(note)}</td>
      </tr>
    `)
    .join("");
}

function renderSummaryCard(title, value) {
  return `
    <article class="summary-card">
      <div class="summary-card-title">${escapeHtml(title)}</div>
      <div class="summary-card-value">${escapeHtml(value)}</div>
    </article>
  `;
}

function businessEntityLabel(id) {
  if (!id) {
    return "全部";
  }

  const entity = pageData?.businessEntities.find((item) => item.id === id);
  if (!entity) {
    return "未知";
  }

  const code = safeText(entity.code);
  const name = safeText(entity.name) || "未命名业务归属";
  return code ? `${name} / ${code}` : name;
}

function isPosted(status) {
  return status === "posted" || status === "paid";
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
