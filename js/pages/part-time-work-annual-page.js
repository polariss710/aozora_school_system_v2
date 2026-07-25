import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { initSchoolAuth, isLoggedIn } from "../auth.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchPartTimeWorkAnnualSummary } from "../api/part-time-work-api.js";
import { populateYearSelect } from "../utils/month-filter.js";
import { formatCurrency } from "../utils/format.js";

const WORKPLACE_OPTIONS = ["诺应教育", "致远教育", "新领域"];
const MIN_FISCAL_YEAR = PAYMENT_MONTH_FILTER_YEAR_RANGE.start;
const MAX_FISCAL_YEAR = PAYMENT_MONTH_FILTER_YEAR_RANGE.end;
const TERMINAL_INCOME_STATUSES = new Set(["cancelled", "voided", "rejected", "cash_rejected", "reversed"]);
const CASH_CONFIRMED_STATUSES = new Set(["approved", "received", "settled", "synced", "historical_confirmed"]);
const dom = {};

export async function initPartTimeWorkAnnualPage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  setYearFilterValue(initialFiscalYearFromUrl());
  bindEvents();
  renderAnnualSummary({ months: [], settlements: [], incomeRecords: [] }, selectedFiscalYear());

  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。");
    return;
  }

  await initSchoolAuth();
  if (!isLoggedIn()) {
    showMessage("error", "请先登录后查看私塾打工年度汇总。");
    return;
  }

  await loadAnnualSummary();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#partTimeWorkAnnualMessageArea");
  dom.filterForm = document.querySelector("#partTimeWorkAnnualFilterForm");
  dom.yearFilter = document.querySelector("#partTimeWorkAnnualYearFilter");
  dom.resetButton = document.querySelector("#partTimeWorkAnnualResetButton");
  dom.summaryTitle = document.querySelector("#partTimeWorkAnnualSummaryTitle");
  dom.summaryContainer = document.querySelector("#partTimeWorkAnnualSummaryContainer");
  dom.loadingState = document.querySelector("#partTimeWorkAnnualLoadingState");
}

function bindEvents() {
  dom.filterForm?.addEventListener("submit", (event) => {
    event.preventDefault();
    loadAnnualSummary();
  });

  dom.yearFilter?.addEventListener("change", () => {
    updateYearUrl(selectedFiscalYear());
  });

  dom.resetButton?.addEventListener("click", () => {
    setYearFilterValue(currentFiscalYear());
    loadAnnualSummary();
  });
}

async function loadAnnualSummary() {
  const fiscalYear = selectedFiscalYear();
  setYearFilterValue(fiscalYear);

  if (!isLoggedIn()) {
    renderAnnualSummary({ months: [], settlements: [], incomeRecords: [] }, fiscalYear);
    showMessage("error", "请先登录后查看私塾打工年度汇总。");
    return;
  }

  updateYearUrl(fiscalYear);
  setLoading(true);
  showMessage("", "");

  try {
    const summary = await fetchPartTimeWorkAnnualSummary(fiscalYear);
    renderAnnualSummary(summary, fiscalYear);
  } catch (error) {
    renderAnnualSummary({ months: [], settlements: [], incomeRecords: [] }, fiscalYear);
    showMessage("error", `年度汇总读取失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderAnnualSummary(summary, fiscalYear) {
  const year = Number.isInteger(Number(fiscalYear)) ? Number(fiscalYear) : currentFiscalYear();
  const viewModel = buildAnnualSummaryViewModel(summary, year);
  if (dom.summaryTitle) {
    dom.summaryTitle.textContent = `${year}年度汇总`;
  }
  if (!dom.summaryContainer) {
    return;
  }

  dom.summaryContainer.innerHTML = `
    <div class="part-time-work-annual-summary-grid">
      <article class="summary-card part-time-work-summary-card">
        <p class="summary-label">统计期间</p>
        <p class="summary-value">${escapeHtml(viewModel.periodLabel)}</p>
      </article>
      <article class="summary-card part-time-work-summary-card">
        <p class="summary-label">正式结算月份</p>
        <p class="summary-value">${escapeHtml(`${viewModel.officialMonthCount}个月`)}</p>
      </article>
      <article class="summary-card part-time-work-summary-card">
        <p class="summary-label">年度业务总额</p>
        <p class="summary-value">${escapeHtml(formatCurrency(viewModel.totalJpy, "JPY"))}</p>
      </article>
      <article class="summary-card part-time-work-summary-card">
        <p class="summary-label">实际到账 CNY</p>
        <p class="summary-value">${escapeHtml(formatCurrency(viewModel.totalCny, "CNY"))}</p>
      </article>
      <article class="summary-card part-time-work-summary-card">
        <p class="summary-label">业务月均 JPY</p>
        <p class="summary-value">${escapeHtml(formatCurrency(viewModel.averageJpy, "JPY"))}</p>
      </article>
      <article class="summary-card part-time-work-summary-card">
        <p class="summary-label">到账月均 CNY</p>
        <p class="summary-value">${escapeHtml(formatCurrency(viewModel.averageCny, "CNY"))}</p>
      </article>
    </div>
    <p class="section-note part-time-work-annual-note">JPY 为锁定结算快照金额；CNY 为 Cash 确认后的实际到账金额，不用统一汇率反算。未锁定或未 Cash 确认的人民币金额显示为 -。</p>
    <div class="table-scroll">
      <table class="payment-table part-time-work-annual-table">
        <thead>
          <tr>
            <th rowspan="2">月份</th>
            ${WORKPLACE_OPTIONS.map((workplaceName) => `<th colspan="3">${escapeHtml(workplaceName)}</th>`).join("")}
            <th colspan="2">月度合计</th>
          </tr>
          <tr>
            ${WORKPLACE_OPTIONS.map(() => "<th>JPY</th><th>CNY</th><th>支給日</th>").join("")}
            <th>JPY</th>
            <th>CNY</th>
          </tr>
        </thead>
        <tbody>
          ${viewModel.monthRows.map(renderAnnualSummaryMonthRow).join("")}
        </tbody>
        <tfoot>
          ${renderAnnualSummaryTotalRow("合计", viewModel.workplaceTotals, viewModel.totalJpy, viewModel.totalCny)}
          ${renderAnnualSummaryTotalRow("月均", viewModel.workplaceAverages, viewModel.averageJpy, viewModel.averageCny)}
        </tfoot>
      </table>
    </div>
  `;
}

function buildAnnualSummaryViewModel(summary, fiscalYear) {
  const months = summary?.months?.length ? summary.months : buildFiscalYearMonths(fiscalYear);
  const settlementsByKey = new Map((summary?.settlements || []).map((row) => [
    `${row.year_month || ""}::${row.workplace_name || ""}`,
    row,
  ]));
  const incomeBySettlementId = buildAnnualIncomeBySettlementId(summary?.incomeRecords || []);

  const monthRows = months.map((yearMonth) => {
    const workplaces = WORKPLACE_OPTIONS.map((workplaceName) => {
      const settlement = settlementsByKey.get(`${yearMonth}::${workplaceName}`) || null;
      return buildAnnualWorkplaceCell(settlement, incomeBySettlementId);
    });
    return {
      yearMonth,
      monthLabel: annualMonthLabel(yearMonth),
      workplaces,
      totalJpy: sumAnnualValues(workplaces, "jpy"),
      totalCny: sumAnnualValues(workplaces, "cny"),
    };
  });

  const officialMonthCount = monthRows.filter((row) => row.totalJpy > 0).length;
  const cnyMonthCount = monthRows.filter((row) => row.totalCny > 0).length;
  const workplaceTotals = WORKPLACE_OPTIONS.map((_, index) => ({
    jpy: monthRows.reduce((sum, row) => sum + Number(row.workplaces[index]?.jpy || 0), 0),
    cny: monthRows.reduce((sum, row) => sum + Number(row.workplaces[index]?.cny || 0), 0),
  }));
  const workplaceAverages = workplaceTotals.map((total, index) => {
    const jpyMonthCount = monthRows.filter((row) => Number(row.workplaces[index]?.jpy || 0) > 0).length;
    const cnyCount = monthRows.filter((row) => Number(row.workplaces[index]?.cny || 0) > 0).length;
    return {
      jpy: averageAmount(total.jpy, jpyMonthCount),
      cny: averageAmount(total.cny, cnyCount),
    };
  });
  const totalJpy = monthRows.reduce((sum, row) => sum + row.totalJpy, 0);
  const totalCny = monthRows.reduce((sum, row) => sum + row.totalCny, 0);

  return {
    periodLabel: `${months[0] || "-"} - ${months[months.length - 1] || "-"}`,
    officialMonthCount,
    totalJpy,
    totalCny,
    averageJpy: averageAmount(totalJpy, officialMonthCount),
    averageCny: averageAmount(totalCny, cnyMonthCount),
    workplaceTotals,
    workplaceAverages,
    monthRows,
  };
}

function buildAnnualIncomeBySettlementId(incomeRecords) {
  const incomeBySettlementId = new Map();
  for (const income of incomeRecords) {
    if (!income?.source_id) {
      continue;
    }
    const current = incomeBySettlementId.get(income.source_id);
    if (!current || shouldPreferAnnualIncomeRecord(income, current)) {
      incomeBySettlementId.set(income.source_id, income);
    }
  }
  return incomeBySettlementId;
}

function shouldPreferAnnualIncomeRecord(candidate, current) {
  const candidateRank = annualIncomeRecordRank(candidate);
  const currentRank = annualIncomeRecordRank(current);
  if (candidateRank !== currentRank) {
    return candidateRank > currentRank;
  }
  return String(candidate?.created_at || "") > String(current?.created_at || "");
}

function annualIncomeRecordRank(income) {
  if (TERMINAL_INCOME_STATUSES.has(String(income?.status || ""))) {
    return 0;
  }
  return hasConfirmedAnnualCashIncome(income) ? 2 : 1;
}

function hasConfirmedAnnualCashIncome(income) {
  const event = income?.cashIncomeLinkageEvent;
  return Boolean(
    event
    && CASH_CONFIRMED_STATUSES.has(event.sync_status)
    && Number(event.payment_amount || 0) > 0
  );
}

function buildAnnualWorkplaceCell(settlement, incomeBySettlementId) {
  const isOfficial = Boolean(settlement?.id) && ["locked", "income_request_created"].includes(settlement.status);
  const income = settlement?.id ? incomeBySettlementId.get(settlement.id) : null;
  const event = income?.cashIncomeLinkageEvent || null;
  const isCnyReceived = event
    && CASH_CONFIRMED_STATUSES.has(event.sync_status)
    && event.payment_currency === "CNY"
    && Number(event.payment_amount || 0) > 0;

  return {
    jpy: isOfficial ? Number(settlement.total_wage_jpy || 0) : 0,
    cny: isCnyReceived ? Number(event.payment_amount || 0) : 0,
    paidDate: isCnyReceived ? formatDateOnly(income.income_date || event.synced_at) : "",
  };
}

function renderAnnualSummaryMonthRow(row) {
  return `
    <tr>
      <th>${escapeHtml(row.monthLabel)}</th>
      ${row.workplaces.map((cell) => `
        <td class="number-cell">${escapeHtml(formatOptionalCurrency(cell.jpy, "JPY"))}</td>
        <td class="number-cell">${escapeHtml(formatOptionalCurrency(cell.cny, "CNY"))}</td>
        <td>${escapeHtml(cell.paidDate || "-")}</td>
      `).join("")}
      <td class="number-cell">${escapeHtml(formatOptionalCurrency(row.totalJpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatOptionalCurrency(row.totalCny, "CNY"))}</td>
    </tr>
  `;
}

function renderAnnualSummaryTotalRow(label, workplaceValues, totalJpy, totalCny) {
  return `
    <tr>
      <th>${escapeHtml(label)}</th>
      ${workplaceValues.map((cell) => `
        <td class="number-cell">${escapeHtml(formatOptionalCurrency(cell.jpy, "JPY"))}</td>
        <td class="number-cell">${escapeHtml(formatOptionalCurrency(cell.cny, "CNY"))}</td>
        <td>-</td>
      `).join("")}
      <td class="number-cell">${escapeHtml(formatOptionalCurrency(totalJpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatOptionalCurrency(totalCny, "CNY"))}</td>
    </tr>
  `;
}

function initialFiscalYearFromUrl() {
  return normalizeFiscalYear(new URLSearchParams(window.location.search).get("year"));
}

function selectedFiscalYear() {
  return normalizeFiscalYear(dom.yearFilter?.value);
}

function setYearFilterValue(value) {
  if (!dom.yearFilter) {
    return;
  }
  dom.yearFilter.value = String(normalizeFiscalYear(value));
}

function normalizeFiscalYear(value) {
  const text = String(value ?? "").trim();
  if (!/^\d{4}$/.test(text)) {
    return currentFiscalYear();
  }
  const year = Number(text);
  if (!Number.isInteger(year) || year < MIN_FISCAL_YEAR || year > MAX_FISCAL_YEAR) {
    return currentFiscalYear();
  }
  return year;
}

function updateYearUrl(fiscalYear) {
  const year = normalizeFiscalYear(fiscalYear);
  if (!window.history?.replaceState) {
    return;
  }
  const url = new URL(window.location.href);
  url.searchParams.set("year", String(year));
  window.history.replaceState({}, "", url);
}

function currentFiscalYear() {
  return new Date().getFullYear();
}

function buildFiscalYearMonths(fiscalYear) {
  const year = Number(fiscalYear);
  if (!Number.isInteger(year) || year < MIN_FISCAL_YEAR || year > MAX_FISCAL_YEAR) {
    return [];
  }
  return [
    `${year - 1}-12`,
    ...Array.from({ length: 11 }, (_, index) => `${year}-${String(index + 1).padStart(2, "0")}`),
  ];
}

function annualMonthLabel(yearMonth) {
  const [year, month] = String(yearMonth || "").split("-");
  if (!year || !month) {
    return "-";
  }
  return `${year}年${Number(month)}月`;
}

function sumAnnualValues(rows, key) {
  return rows.reduce((sum, row) => sum + Number(row?.[key] || 0), 0);
}

function averageAmount(total, count) {
  return count > 0 ? total / count : 0;
}

function formatOptionalCurrency(value, currency) {
  const numberValue = Number(value || 0);
  return numberValue > 0 ? formatCurrency(numberValue, currency) : "-";
}

function formatDateOnly(value) {
  if (!value) {
    return "-";
  }
  return String(value).slice(0, 10);
}

function setLoading(isLoading) {
  dom.loadingState?.classList.toggle("is-hidden", !isLoading);
}

function showMessage(type, text) {
  if (!dom.messageArea) {
    return;
  }
  dom.messageArea.textContent = text || "";
  dom.messageArea.classList.toggle("is-hidden", !text);
  dom.messageArea.classList.toggle("message-error", type === "error");
  dom.messageArea.classList.toggle("message-success", type === "success");
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
