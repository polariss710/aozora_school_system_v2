import { DEFAULT_FILTERS } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  confirmPaymentRequest,
  fetchAccounts,
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
  { key: "filtered_amount_jpy", label: "筛选合计 JPY", currency: "JPY" },
  { key: "filtered_amount_cny", label: "筛选合计 CNY", currency: "CNY" },
  { key: "pending_amount_jpy", label: "待支付金额 JPY", currency: "JPY" },
  { key: "pending_amount_cny", label: "待支付金额 CNY", currency: "CNY" },
  { key: "paid_amount_jpy", label: "已支付金额 JPY", currency: "JPY" },
  { key: "paid_amount_cny", label: "已支付金额 CNY", currency: "CNY" },
  { key: "record_count", label: "请求数量" },
  { key: "pending_count", label: "待支付数量" },
  { key: "paid_count", label: "已支付数量" },
  { key: "cancelled_count", label: "已取消数量" },
  { key: "void_count", label: "已作废数量" },
];

const dom = {};
let accounts = [];
let currentConfirmRow = null;
let isConfirmSubmitting = false;

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
  loadAccounts();
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
  dom.confirmPaymentDialog = document.querySelector("#confirmPaymentDialog");
  dom.confirmPaymentSummary = document.querySelector("#confirmPaymentSummary");
  dom.confirmPaymentError = document.querySelector("#confirmPaymentError");
  dom.confirmAccountSelect = document.querySelector("#confirmAccountSelect");
  dom.confirmPayDateInput = document.querySelector("#confirmPayDateInput");
  dom.confirmAmountInput = document.querySelector("#confirmAmountInput");
  dom.confirmNoteInput = document.querySelector("#confirmNoteInput");
  dom.confirmSubmitButton = document.querySelector("#confirmSubmitButton");
  dom.confirmCancelButton = document.querySelector("#confirmCancelButton");
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

  dom.tableBody.addEventListener("click", (event) => {
    const button = event.target.closest("[data-confirm-payment-id]");
    if (!button) {
      return;
    }

    const row = findRenderedRow(button.dataset.confirmPaymentId);
    if (row) {
      openConfirmPaymentDialog(row);
    }
  });

  dom.confirmCancelButton.addEventListener("click", closeConfirmPaymentDialog);
  dom.confirmSubmitButton.addEventListener("click", submitConfirmPayment);
  dom.confirmAccountSelect.addEventListener("change", () => {
    setConfirmFieldInvalid("account", false);
    hideConfirmErrorIfClean();
  });
  dom.confirmPayDateInput.addEventListener("input", () => {
    setConfirmFieldInvalid("payDate", false);
    hideConfirmErrorIfClean();
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

async function loadAccounts() {
  try {
    accounts = await fetchAccounts();
  } catch (error) {
    accounts = [];
    showMessage("warning", `支付账户读取失败，确认支付暂不可用：${error.message || error}`);
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
    const displayValue = formatSummaryValue(field, value);

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
  dom.tableBody.dataset.rows = JSON.stringify(rows);
  dom.recordCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  dom.tableBody.innerHTML = rows
    .map((row) => {
      const month = row.request_month;
      const targetText = row.payee_name || row.note || row.source_id || row.id;

      return `
        <tr>
          <td>${escapeHtml(formatMonth(month))}</td>
          <td><span class="status-badge status-${escapeAttribute(row.status)}">${escapeHtml(statusLabel(row.status))}</span></td>
          <td>${escapeHtml(sourceTypeLabel(row.source_type))}</td>
          <td>${escapeHtml(row.business_name || row.business_entity_id || "-")}</td>
          <td class="description-cell">${escapeHtml(targetText || "-")}</td>
          <td>${escapeHtml(row.currency || "-")}</td>
          <td class="number-cell">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
          <td>${escapeHtml(formatDate(row.created_at))}</td>
          <td>${escapeHtml(formatDate(row.paid_at))}</td>
          <td>${escapeHtml(formatDate(row.reversed_at))}</td>
          <td class="action-cell">${renderPaymentActions(row)}</td>
        </tr>
      `;
    })
    .join("");
}

function renderPaymentActions(row) {
  if (row.status !== "pending") {
    return "-";
  }

  return `
    <button class="button table-action-button" type="button" data-confirm-payment-id="${escapeAttribute(row.id)}">
      确认支付
    </button>
  `;
}

function openConfirmPaymentDialog(row) {
  if (row.status !== "pending") {
    showMessage("error", "只有待支付的请求可以确认支付。");
    return;
  }

  if (accounts.length === 0) {
    showMessage("error", "暂无可用支付账户，无法确认支付。");
    return;
  }

  currentConfirmRow = row;
  clearConfirmErrors();
  dom.confirmPaymentSummary.innerHTML = renderConfirmSummary(row);
  dom.confirmPayDateInput.value = currentDate();
  dom.confirmAmountInput.value = row.amount || "";
  dom.confirmNoteInput.value = "";
  renderAccountOptions(row);
  setConfirmSubmitting(false);
  dom.confirmPaymentDialog.classList.remove("is-hidden");
  dom.confirmPaymentDialog.setAttribute("aria-hidden", "false");
}

function closeConfirmPaymentDialog() {
  if (isConfirmSubmitting) {
    return;
  }

  currentConfirmRow = null;
  dom.confirmPaymentDialog.classList.add("is-hidden");
  dom.confirmPaymentDialog.setAttribute("aria-hidden", "true");
}

function renderAccountOptions(row) {
  const orderedAccounts = [...accounts].sort((left, right) => {
    const leftMatches = left.business_entity_id === row.business_entity_id ? 0 : 1;
    const rightMatches = right.business_entity_id === row.business_entity_id ? 0 : 1;
    return leftMatches - rightMatches || safeText(left.name).localeCompare(safeText(right.name), "zh-CN");
  });

  const options = ['<option value="">请选择支付账户</option>'];

  for (const account of orderedAccounts) {
    const label = [
      account.name || account.account_code || account.id,
      account.currency || "-",
      formatCurrency(account.current_balance, account.currency),
      account.account_type || "",
    ]
      .filter(Boolean)
      .join(" / ");

    options.push(
      `<option value="${escapeAttribute(account.id)}">${escapeHtml(label)}</option>`
    );
  }

  dom.confirmAccountSelect.innerHTML = options.join("");
}

async function submitConfirmPayment() {
  if (isConfirmSubmitting) {
    return;
  }

  clearConfirmErrors();

  if (!currentConfirmRow || currentConfirmRow.status !== "pending") {
    showConfirmError("当前支付请求不是待支付状态，无法确认。");
    return;
  }

  const accountId = dom.confirmAccountSelect.value;
  if (!accountId) {
    showConfirmError("请选择支付账户。", ["account"]);
    return;
  }

  const account = accounts.find((item) => item.id === accountId);
  if (!account) {
    showConfirmError("支付账户信息无效，请重新选择。", ["account"]);
    return;
  }

  if (account.currency !== currentConfirmRow.currency) {
    showConfirmError("支付账户币种与支付请求币种不一致。", ["account"]);
    return;
  }

  const payDate = dom.confirmPayDateInput.value;
  if (!payDate) {
    showConfirmError("请选择支付日期。", ["payDate"]);
    return;
  }

  if (
    currentConfirmRow.amount === null ||
    currentConfirmRow.amount === undefined ||
    currentConfirmRow.amount === ""
  ) {
    showConfirmError("支付金额无效，请刷新后重试。", ["amount"]);
    return;
  }

  setConfirmSubmitting(true);

  try {
    await confirmPaymentRequest({
      paymentRequestId: currentConfirmRow.id,
      accountId,
      payDate,
      amount: currentConfirmRow.amount,
      note: dom.confirmNoteInput.value.trim(),
    });

    setConfirmSubmitting(false);
    closeConfirmPaymentDialog();
    await loadPaymentData();
    showMessage("success", "支付已确认。");
  } catch (error) {
    console.error(error);
    showConfirmError(`确认支付失败：${error.message || error}`);
  } finally {
    setConfirmSubmitting(false);
  }
}

function setConfirmSubmitting(isSubmitting) {
  isConfirmSubmitting = isSubmitting;
  dom.confirmSubmitButton.disabled = isSubmitting;
  dom.confirmCancelButton.disabled = isSubmitting;
  dom.confirmSubmitButton.textContent = isSubmitting ? "确认中..." : "确认支付";
}

function renderConfirmSummary(row) {
  const items = [
    ["支付对象", row.payee_name || row.source_id || row.id],
    ["业务归属", row.business_name || row.business_entity_id || "-"],
    ["请求月份", formatMonth(row.request_month)],
    ["来源类型", sourceTypeLabel(row.source_type)],
    ["支付金额", formatCurrency(row.amount, row.currency)],
  ];

  return items
    .map(
      ([label, value]) => `
        <div class="dialog-summary-row">
          <span class="dialog-summary-label">${escapeHtml(label)}</span>
          <span>${escapeHtml(value)}</span>
        </div>
      `
    )
    .join("");
}

function clearConfirmErrors() {
  dom.confirmPaymentError.textContent = "";
  dom.confirmPaymentError.classList.add("is-hidden");
  setConfirmFieldInvalid("account", false);
  setConfirmFieldInvalid("payDate", false);
  setConfirmFieldInvalid("amount", false);
}

function showConfirmError(message, fieldIds = []) {
  dom.confirmPaymentError.textContent = message;
  dom.confirmPaymentError.classList.remove("is-hidden");

  for (const fieldId of fieldIds) {
    setConfirmFieldInvalid(fieldId, true);
  }
}

function setConfirmFieldInvalid(fieldId, invalid) {
  const field = dom.confirmPaymentDialog.querySelector(`[data-confirm-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function hideConfirmErrorIfClean() {
  const hasInvalidField = Boolean(dom.confirmPaymentDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.confirmPaymentError.textContent = "";
    dom.confirmPaymentError.classList.add("is-hidden");
  }
}

function findRenderedRow(id) {
  try {
    const rows = JSON.parse(dom.tableBody.dataset.rows || "[]");
    return rows.find((row) => row.id === id) || null;
  } catch {
    return null;
  }
}

function normalizeSummary(summary) {
  if (Array.isArray(summary)) {
    return summary[0] || {};
  }

  return summary || {};
}

function formatSummaryValue(field, value) {
  if (value === null || value === undefined || value === "") {
    return field.key.endsWith("_count") ? "0" : "-";
  }

  if (field.currency) {
    return formatCurrency(value, field.currency);
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

function currentDate() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
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
