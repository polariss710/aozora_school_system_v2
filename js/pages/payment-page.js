import { DEFAULT_FILTERS, PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  cancelPaymentRequest,
  confirmPaymentRequest,
  fetchAccounts,
  fetchBusinessEntities,
  fetchPaymentRequests,
  fetchPaymentSummary,
  reissueReversedPaymentRequest,
  reversePaidPaymentRequest,
  restoreCancelledPaymentRequest,
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
let currentReverseRow = null;
let isReverseSubmitting = false;
let currentStatusActionRow = null;
let currentStatusActionType = null;
let isStatusActionSubmitting = false;
let currentReissueRow = null;
let isReissueSubmitting = false;

export function initPaymentPage() {
  cacheDom();
  populateYearOptions();
  populateMonthOptions();
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
  dom.yearFilter = document.querySelector("#yearFilter");
  dom.monthFilter = document.querySelector("#monthFilter");
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
  dom.reversePaymentDialog = document.querySelector("#reversePaymentDialog");
  dom.reversePaymentSummary = document.querySelector("#reversePaymentSummary");
  dom.reversePaymentError = document.querySelector("#reversePaymentError");
  dom.reverseDateInput = document.querySelector("#reverseDateInput");
  dom.reverseReasonInput = document.querySelector("#reverseReasonInput");
  dom.reverseConfirmCheck = document.querySelector("#reverseConfirmCheck");
  dom.reverseSubmitButton = document.querySelector("#reverseSubmitButton");
  dom.reverseCancelButton = document.querySelector("#reverseCancelButton");
  dom.statusActionDialog = document.querySelector("#statusActionDialog");
  dom.statusActionTitle = document.querySelector("#statusActionTitle");
  dom.statusActionSummary = document.querySelector("#statusActionSummary");
  dom.statusActionMessage = document.querySelector("#statusActionMessage");
  dom.statusActionError = document.querySelector("#statusActionError");
  dom.statusActionSubmitButton = document.querySelector("#statusActionSubmitButton");
  dom.statusActionCancelButton = document.querySelector("#statusActionCancelButton");
  dom.reissuePaymentDialog = document.querySelector("#reissuePaymentDialog");
  dom.reissuePaymentSummary = document.querySelector("#reissuePaymentSummary");
  dom.reissuePaymentError = document.querySelector("#reissuePaymentError");
  dom.reissueReasonInput = document.querySelector("#reissueReasonInput");
  dom.reissueSubmitButton = document.querySelector("#reissueSubmitButton");
  dom.reissueCancelButton = document.querySelector("#reissueCancelButton");
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
    const confirmButton = event.target.closest("[data-confirm-payment-id]");
    if (confirmButton) {
      const row = findRenderedRow(confirmButton.dataset.confirmPaymentId);
      if (row) {
        openConfirmPaymentDialog(row);
      }
    }

    const reverseButton = event.target.closest("[data-reverse-payment-id]");
    if (reverseButton) {
      const row = findRenderedRow(reverseButton.dataset.reversePaymentId);
      if (row) {
        openReversePaymentDialog(row);
      }
    }

    const statusButton = event.target.closest("[data-status-action]");
    if (statusButton) {
      const row = findRenderedRow(statusButton.dataset.paymentId);
      if (row) {
        openStatusActionDialog(row, statusButton.dataset.statusAction);
      }
    }

    const reissueButton = event.target.closest("[data-reissue-payment-id]");
    if (reissueButton) {
      const row = findRenderedRow(reissueButton.dataset.reissuePaymentId);
      if (row) {
        openReissuePaymentDialog(row);
      }
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
  dom.reverseCancelButton.addEventListener("click", closeReversePaymentDialog);
  dom.reverseSubmitButton.addEventListener("click", submitReversePayment);
  dom.reverseDateInput.addEventListener("input", () => {
    setReverseFieldInvalid("reverseDate", false);
    hideReverseErrorIfClean();
  });
  dom.reverseReasonInput.addEventListener("input", () => {
    setReverseFieldInvalid("reason", false);
    hideReverseErrorIfClean();
  });
  dom.reverseConfirmCheck.addEventListener("change", () => {
    setReverseFieldInvalid("confirmCheck", false);
    hideReverseErrorIfClean();
  });
  dom.statusActionCancelButton.addEventListener("click", closeStatusActionDialog);
  dom.statusActionSubmitButton.addEventListener("click", submitStatusAction);
  dom.reissueCancelButton.addEventListener("click", closeReissuePaymentDialog);
  dom.reissueSubmitButton.addEventListener("click", submitReissuePayment);
  dom.reissueReasonInput.addEventListener("input", () => {
    setReissueFieldInvalid("reason", false);
    hideReissueErrorIfClean();
  });
}

function setDefaultFilters() {
  setMonthSelectValue(currentYearMonth());
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
  if (!filters) {
    return;
  }

  setLoading(true);
  showMessage("info", "正在加载老师工资支付数据...");

  try {
    const [summary, requests] = await Promise.all([
      fetchPaymentSummary(filters),
      fetchPaymentRequests(filters),
    ]);

    renderSummary(normalizeSummary(summary));
    renderRows(requests);
    showMessage("success", "老师工资支付数据已加载。");
  } catch (error) {
    renderSummary({});
    renderRows([]);
    showMessage("error", `读取老师工资支付数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readFilters() {
  const selectedMonth = getSelectedYearMonth();
  if (!selectedMonth) {
    showMessage("error", "请选择正确的年月。");
    return null;
  }

  return {
    month: selectedMonth,
    status: dom.statusSelect.value,
    sourceType: dom.sourceTypeSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    currency: dom.currencySelect.value,
  };
}

function populateYearOptions() {
  const currentYear = new Date().getFullYear();
  const startYear = Number(PAYMENT_MONTH_FILTER_YEAR_RANGE.start);
  const endYear = Number(PAYMENT_MONTH_FILTER_YEAR_RANGE.end);
  const years = new Set();

  for (let year = startYear; year <= endYear; year += 1) {
    years.add(year);
  }

  years.add(currentYear);

  dom.yearFilter.innerHTML = Array.from(years)
    .sort((a, b) => a - b)
    .map((year) => `<option value="${year}">${year}年</option>`)
    .join("");
}

function populateMonthOptions() {
  const options = [];

  for (let month = 1; month <= 12; month += 1) {
    const value = String(month).padStart(2, "0");
    options.push(`<option value="${value}">${value}月</option>`);
  }

  dom.monthFilter.innerHTML = options.join("");
}

function setMonthSelectValue(yearMonth) {
  const [year, month] = String(yearMonth || "").split("-");
  dom.yearFilter.value = year || "";
  dom.monthFilter.value = month || "";
}

function getSelectedYearMonth() {
  const year = dom.yearFilter.value;
  const month = dom.monthFilter.value;
  const yearMonth = `${year}-${month}`;

  if (!year || !month || !/^\d{4}-\d{2}$/.test(yearMonth)) {
    return "";
  }

  return yearMonth;
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
          <td><a class="table-action-button" href="./payment-detail.html?id=${encodeURIComponent(row.id)}">详情</a></td>
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
  if (row.status === "pending") {
    return `
      <div class="action-buttons">
        <button class="button table-action-button" type="button" data-confirm-payment-id="${escapeAttribute(row.id)}">
          确认支付
        </button>
        <button class="button table-action-button" type="button" data-status-action="cancel" data-payment-id="${escapeAttribute(row.id)}">
          取消
        </button>
      </div>
    `;
  }

  if (row.status === "paid") {
    return `
      <div class="action-buttons">
        <button class="button button-danger table-action-button" type="button" data-reverse-payment-id="${escapeAttribute(row.id)}">
          撤销支付
        </button>
      </div>
    `;
  }

  if (row.status === "cancelled") {
    return `
      <div class="action-buttons">
        <button class="button table-action-button" type="button" data-status-action="restore" data-payment-id="${escapeAttribute(row.id)}">
          恢复待支付
        </button>
      </div>
    `;
  }

  if (row.status === "reversed") {
    if (row.replacement_payment_request_id) {
      return "已重新生成";
    }

    return `
      <div class="action-buttons">
        <button class="button table-action-button" type="button" data-reissue-payment-id="${escapeAttribute(row.id)}">
          重新生成待支付
        </button>
      </div>
    `;
  }

  return "-";
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

function openReversePaymentDialog(row) {
  if (row.status !== "paid") {
    showMessage("error", "只有已支付的支付要求可以撤销。");
    return;
  }

  currentReverseRow = row;
  clearReverseErrors();
  dom.reversePaymentSummary.innerHTML = renderReverseSummary(row);
  dom.reverseDateInput.value = currentDate();
  dom.reverseReasonInput.value = "";
  dom.reverseConfirmCheck.checked = false;
  setReverseSubmitting(false);
  dom.reversePaymentDialog.classList.remove("is-hidden");
  dom.reversePaymentDialog.setAttribute("aria-hidden", "false");
}

function closeReversePaymentDialog() {
  if (isReverseSubmitting) {
    return;
  }

  currentReverseRow = null;
  dom.reversePaymentDialog.classList.add("is-hidden");
  dom.reversePaymentDialog.setAttribute("aria-hidden", "true");
}

async function submitReversePayment() {
  if (isReverseSubmitting) {
    return;
  }

  clearReverseErrors();

  if (!currentReverseRow) {
    showReverseError("撤销对象不存在，请关闭后重试。");
    return;
  }

  if (currentReverseRow.status !== "paid") {
    showReverseError("只有已支付的支付要求可以撤销。");
    return;
  }

  const reverseDate = dom.reverseDateInput.value;
  if (!reverseDate) {
    showReverseError("请选择撤销日期。", ["reverseDate"]);
    return;
  }

  const reason = dom.reverseReasonInput.value.trim();
  if (!reason) {
    showReverseError("请输入撤销原因。", ["reason"]);
    return;
  }

  if (!dom.reverseConfirmCheck.checked) {
    showReverseError("请勾选确认撤销说明。", ["confirmCheck"]);
    return;
  }

  setReverseSubmitting(true);

  try {
    await reversePaidPaymentRequest({
      paymentRequestId: currentReverseRow.id,
      reason,
      reverseDate,
    });

    setReverseSubmitting(false);
    closeReversePaymentDialog();
    await loadPaymentData();
    showMessage("success", "支付已撤销，账户余额已恢复。");
  } catch (error) {
    console.error(error);
    showReverseError(`撤销支付失败：${error.message || error}`);
  } finally {
    setReverseSubmitting(false);
  }
}

function setReverseSubmitting(isSubmitting) {
  isReverseSubmitting = isSubmitting;
  dom.reverseSubmitButton.disabled = isSubmitting;
  dom.reverseCancelButton.disabled = isSubmitting;
  dom.reverseSubmitButton.textContent = isSubmitting ? "撤销中..." : "确认撤销支付";
}

function renderReverseSummary(row) {
  const items = [
    ["支付对象", row.payee_name || row.source_id || row.id],
    ["业务归属", row.business_name || row.business_entity_id || "-"],
    ["请求月份", formatMonth(row.request_month)],
    ["来源类型", sourceTypeLabel(row.source_type)],
    ["支付金额", formatCurrency(row.amount, row.currency)],
    ["支付时间", formatDate(row.paid_at)],
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

function clearReverseErrors() {
  dom.reversePaymentError.textContent = "";
  dom.reversePaymentError.classList.add("is-hidden");
  setReverseFieldInvalid("reverseDate", false);
  setReverseFieldInvalid("reason", false);
  setReverseFieldInvalid("confirmCheck", false);
}

function showReverseError(message, fieldIds = []) {
  dom.reversePaymentError.textContent = message;
  dom.reversePaymentError.classList.remove("is-hidden");

  for (const fieldId of fieldIds) {
    setReverseFieldInvalid(fieldId, true);
  }
}

function setReverseFieldInvalid(fieldId, invalid) {
  const field = dom.reversePaymentDialog.querySelector(`[data-reverse-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function hideReverseErrorIfClean() {
  const hasInvalidField = Boolean(dom.reversePaymentDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.reversePaymentError.textContent = "";
    dom.reversePaymentError.classList.add("is-hidden");
  }
}

function openStatusActionDialog(row, actionType) {
  if (actionType === "cancel" && row.status !== "pending") {
    showMessage("error", "只有待支付的支付要求可以取消。");
    return;
  }

  if (actionType === "restore" && row.status !== "cancelled") {
    showMessage("error", "只有已取消的支付要求可以恢复。");
    return;
  }

  if (!["cancel", "restore"].includes(actionType)) {
    showMessage("error", "未知的状态操作。");
    return;
  }

  currentStatusActionRow = row;
  currentStatusActionType = actionType;
  clearStatusActionErrors();
  renderStatusActionContent(row, actionType);
  setStatusActionSubmitting(false);
  dom.statusActionDialog.classList.remove("is-hidden");
  dom.statusActionDialog.setAttribute("aria-hidden", "false");
}

function closeStatusActionDialog() {
  if (isStatusActionSubmitting) {
    return;
  }

  currentStatusActionRow = null;
  currentStatusActionType = null;
  dom.statusActionDialog.classList.add("is-hidden");
  dom.statusActionDialog.setAttribute("aria-hidden", "true");
}

async function submitStatusAction() {
  if (isStatusActionSubmitting) {
    return;
  }

  clearStatusActionErrors();

  if (!currentStatusActionRow) {
    showStatusActionError("操作对象不存在，请关闭后重试。");
    return;
  }

  if (currentStatusActionType === "cancel" && currentStatusActionRow.status !== "pending") {
    showStatusActionError("只有待支付的支付要求可以取消。");
    return;
  }

  if (currentStatusActionType === "restore" && currentStatusActionRow.status !== "cancelled") {
    showStatusActionError("只有已取消的支付要求可以恢复。");
    return;
  }

  if (!["cancel", "restore"].includes(currentStatusActionType)) {
    showStatusActionError("未知的状态操作。");
    return;
  }

  setStatusActionSubmitting(true);

  try {
    if (currentStatusActionType === "cancel") {
      await cancelPaymentRequest({
        paymentRequestId: currentStatusActionRow.id,
        reason: null,
      });
    } else {
      await restoreCancelledPaymentRequest({
        paymentRequestId: currentStatusActionRow.id,
      });
    }

    const successMessage =
      currentStatusActionType === "cancel"
        ? "支付要求已取消。"
        : "支付要求已恢复为待支付。";

    setStatusActionSubmitting(false);
    closeStatusActionDialog();
    await loadPaymentData();
    showMessage("success", successMessage);
  } catch (error) {
    console.error(error);
    showStatusActionError(`操作失败：${error.message || error}`);
  } finally {
    setStatusActionSubmitting(false);
  }
}

function renderStatusActionContent(row, actionType) {
  const config =
    actionType === "cancel"
      ? {
          title: "取消支付要求",
          message: "取消后该支付要求将不再计入待支付，但不会影响账户余额，也不会生成支出或账户流水。",
          submitText: "确认取消",
        }
      : {
          title: "恢复待支付",
          message: "恢复后该支付要求会重新进入待支付列表，可再次确认支付。",
          submitText: "确认恢复",
        };

  dom.statusActionTitle.textContent = config.title;
  dom.statusActionSummary.innerHTML = renderStatusActionSummary(row);
  dom.statusActionMessage.textContent = config.message;
  dom.statusActionSubmitButton.textContent = config.submitText;
}

function renderStatusActionSummary(row) {
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

function clearStatusActionErrors() {
  dom.statusActionError.textContent = "";
  dom.statusActionError.classList.add("is-hidden");
}

function showStatusActionError(message) {
  dom.statusActionError.textContent = message;
  dom.statusActionError.classList.remove("is-hidden");
}

function setStatusActionSubmitting(isSubmitting) {
  isStatusActionSubmitting = isSubmitting;
  dom.statusActionSubmitButton.disabled = isSubmitting;
  dom.statusActionCancelButton.disabled = isSubmitting;
  dom.statusActionSubmitButton.textContent = isSubmitting ? "处理中..." : getStatusActionSubmitText();
}

function getStatusActionSubmitText() {
  if (currentStatusActionType === "cancel") {
    return "确认取消";
  }

  if (currentStatusActionType === "restore") {
    return "确认恢复";
  }

  return "确认";
}

function openReissuePaymentDialog(row) {
  if (row.status !== "reversed") {
    showMessage("error", "只有已撤销的支付请求可以重新生成待支付。");
    return;
  }

  if (row.replacement_payment_request_id) {
    showMessage("error", "该支付请求已重新生成待支付。");
    return;
  }

  currentReissueRow = row;
  clearReissueErrors();
  dom.reissuePaymentSummary.innerHTML = renderReissueSummary(row);
  dom.reissueReasonInput.value = "";
  setReissueSubmitting(false);
  dom.reissuePaymentDialog.classList.remove("is-hidden");
  dom.reissuePaymentDialog.setAttribute("aria-hidden", "false");
}

function closeReissuePaymentDialog() {
  if (isReissueSubmitting) {
    return;
  }

  currentReissueRow = null;
  dom.reissuePaymentDialog.classList.add("is-hidden");
  dom.reissuePaymentDialog.setAttribute("aria-hidden", "true");
}

async function submitReissuePayment() {
  if (isReissueSubmitting) {
    return;
  }

  clearReissueErrors();

  if (!currentReissueRow) {
    showReissueError("重新生成对象不存在，请关闭后重试。");
    return;
  }

  if (currentReissueRow.status !== "reversed") {
    showReissueError("只有已撤销的支付请求可以重新生成待支付。");
    return;
  }

  if (currentReissueRow.replacement_payment_request_id) {
    showReissueError("该支付请求已重新生成待支付。");
    return;
  }

  const reason = dom.reissueReasonInput.value.trim();
  if (!reason) {
    showReissueError("请输入重新生成原因。", ["reason"]);
    return;
  }

  setReissueSubmitting(true);

  try {
    await reissueReversedPaymentRequest({
      paymentRequestId: currentReissueRow.id,
      reason,
    });

    setReissueSubmitting(false);
    closeReissuePaymentDialog();
    await loadPaymentData();
    showMessage("success", "已重新生成待支付请求。");
  } catch (error) {
    console.error(error);
    showReissueError(`重新生成待支付失败：${error.message || error}`);
  } finally {
    setReissueSubmitting(false);
  }
}

function renderReissueSummary(row) {
  const items = [
    ["支付对象", row.payee_name || row.source_id || row.id],
    ["业务归属", row.business_name || row.business_entity_id || "-"],
    ["请求月份", formatMonth(row.request_month)],
    ["币种", row.currency || "-"],
    ["支付金额", formatCurrency(row.amount, row.currency)],
    ["原撤销时间", formatDate(row.reversed_at)],
    ["原撤销原因", row.reversal_reason || "-"],
    ["原请求 ID", row.id],
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

function clearReissueErrors() {
  dom.reissuePaymentError.textContent = "";
  dom.reissuePaymentError.classList.add("is-hidden");
  setReissueFieldInvalid("reason", false);
}

function showReissueError(message, fieldIds = []) {
  dom.reissuePaymentError.textContent = message;
  dom.reissuePaymentError.classList.remove("is-hidden");

  for (const fieldId of fieldIds) {
    setReissueFieldInvalid(fieldId, true);
  }
}

function setReissueFieldInvalid(fieldId, invalid) {
  const field = dom.reissuePaymentDialog.querySelector(`[data-reissue-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function hideReissueErrorIfClean() {
  const hasInvalidField = Boolean(dom.reissuePaymentDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.reissuePaymentError.textContent = "";
    dom.reissuePaymentError.classList.add("is-hidden");
  }
}

function setReissueSubmitting(isSubmitting) {
  isReissueSubmitting = isSubmitting;
  dom.reissueSubmitButton.disabled = isSubmitting;
  dom.reissueCancelButton.disabled = isSubmitting;
  dom.reissueSubmitButton.textContent = isSubmitting ? "生成中..." : "重新生成待支付";
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
