import { DEFAULT_FILTERS } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchBusinessEntities,
  fetchPaymentRequests,
  fetchPaymentSummary,
} from "../api/payment-api.js";
import {
  formatCurrency,
  formatDate,
  formatMonth,
  safeText,
  sourceTypeLabel,
  statusLabel,
} from "../utils/format.js";

const SUMMARY_FIELDS = [
  { key: "total_amount", label: "总金额" },
  { key: "pending_amount", label: "待支付金额" },
  { key: "paid_amount", label: "已支付金额" },
  { key: "cancelled_amount", label: "已取消金额" },
  { key: "reversed_amount", label: "已撤销金额" },
  { key: "request_count", label: "请求数量" },
  { key: "pending_count", label: "待支付数量" },
  { key: "paid_count", label: "已支付数量" },
];

const dom = {};

export function initPaymentPage() {
  cacheDom();
  setDefaultFilters();
  bindEvents();
  renderSummary({});

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    setLoading(false);
    renderRows([]);
    return;
  }

  loadBusinessEntities();
  loadPaymentData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#messageArea");
  dom.filterForm = document.querySelector("#filterForm");
  dom.monthInput = document.querySelector("#monthInput");
  dom.statusSelect = document.querySelector("#statusSelect");
  dom.sourceTypeSelect = document.querySelector("#sourceTypeSelect");
  dom.businessEntitySelect = document.querySelector("#businessEntitySelect");
  dom.currencySelect = document.querySelector("#currencySelect");
  dom.resetButton = document.querySelector("#resetButton");
  dom.summaryGrid = document.querySelector("#summaryGrid");
  dom.loadingState = document.querySelector("#loadingState");
  dom.emptyState = document.querySelector("#emptyState");
  dom.tableBody = document.querySelector("#paymentTableBody");
  dom.recordCount = document.querySelector("#recordCount");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    loadPaymentData();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    loadPaymentData();
  });
}

function setDefaultFilters() {
  dom.monthInput.value = currentYearMonth();
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.sourceTypeSelect.value = DEFAULT_FILTERS.sourceType;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
}

async function loadBusinessEntities() {
  const result = await fetchBusinessEntities();
  renderBusinessEntities(result.data);

  if (result.warning) {
    showMessage("warning", `业务归属选项读取失败，已继续加载支付数据：${result.warning}`);
  }
}

async function loadPaymentData() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  setLoading(true);
  showMessage("info", "正在加载支付管理数据...");

  try {
    const [summary, requests] = await Promise.all([
      fetchPaymentSummary(filters),
      fetchPaymentRequests(filters),
    ]);

    renderSummary(normalizeSummary(summary));
    renderRows(requests);
    showMessage("success", "支付管理数据已加载。");
  } catch (error) {
    renderSummary({});
    renderRows([]);
    showMessage("error", `读取支付管理数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readFilters() {
  return {
    month: dom.monthInput.value,
    status: dom.statusSelect.value,
    sourceType: dom.sourceTypeSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    currency: dom.currencySelect.value,
  };
}

function renderBusinessEntities(items) {
  const options = ['<option value="">全部</option>'];

  for (const item of items) {
    const name = item.name || item.id;
    options.push(
      `<option value="${escapeAttribute(item.id)}">${escapeHtml(name)}</option>`
    );
  }

  dom.businessEntitySelect.innerHTML = options.join("");
}

function renderSummary(summary) {
  const cards = SUMMARY_FIELDS.map((field) => {
    const value = summary[field.key];
    const displayValue = formatSummaryValue(field.key, value, summary.currency);

    return `
      <article class="summary-card">
        <div class="summary-card-title">${escapeHtml(field.label)}</div>
        <div class="summary-card-value">${escapeHtml(displayValue)}</div>
      </article>
    `;
  });

  dom.summaryGrid.innerHTML = cards.join("");
}

function renderRows(rows) {
  dom.recordCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  dom.tableBody.innerHTML = rows
    .map((row) => {
      const month = row.year_month || row.request_month || row.month;
      const targetText =
        row.target_name || row.teacher_name || row.description || row.memo || row.id;

      return `
        <tr>
          <td>${escapeHtml(formatMonth(month))}</td>
          <td><span class="status-badge status-${escapeAttribute(row.status)}">${escapeHtml(statusLabel(row.status))}</span></td>
          <td>${escapeHtml(sourceTypeLabel(row.source_type))}</td>
          <td>${escapeHtml(row.business_entity_name || row.business_entity_id || "-")}</td>
          <td class="description-cell">${escapeHtml(targetText || "-")}</td>
          <td>${escapeHtml(row.currency || "-")}</td>
          <td class="number-cell">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
          <td>${escapeHtml(formatDate(row.created_at))}</td>
          <td>${escapeHtml(formatDate(row.paid_at))}</td>
          <td>${escapeHtml(formatDate(row.reversed_at))}</td>
        </tr>
      `;
    })
    .join("");
}

function normalizeSummary(summary) {
  if (Array.isArray(summary)) {
    return summary[0] || {};
  }

  return summary || {};
}

function formatSummaryValue(key, value, currency) {
  if (value === null || value === undefined || value === "") {
    return key.endsWith("_count") ? "0" : "-";
  }

  if (key.endsWith("_amount")) {
    return formatCurrency(value, currency);
  }

  return safeText(value);
}

function showMessage(type, text) {
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = text;
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
}

function currentYearMonth() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
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
