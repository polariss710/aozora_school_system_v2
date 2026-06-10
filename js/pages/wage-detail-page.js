import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createTeacherWagePaymentRequest,
  fetchWageDetailPage,
} from "../api/wage-detail-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const WAGE_STATUS_LABELS = {
  locked: "已生成快照",
  void: "已作废",
};

const SETTLEMENT_TYPE_LABELS = {
  jpy_hourly: "日元时给",
  no_wage: "无工资",
};

const DETAIL_STATUS_LABELS = {
  completed: "已完成",
  makeup_completed: "补课完成",
};

const PAYMENT_REQUEST_STATUS_LABELS = {
  pending: "待支付",
  paid: "已支付",
  reversed: "已撤销",
  void: "已作废",
  cancelled: "已取消",
};

const dom = {};
let detailData = null;

export function initWageDetailPage() {
  cacheDom();
  configureReturnLink();
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    setContentVisible(false);
    return;
  }

  const wageLockId = readWageLockId();
  if (!wageLockId) {
    showMessage("error", "缺少老师工资快照记录 ID，请从老师工资结算一览进入详情页。");
    setContentVisible(false);
    return;
  }

  loadWageDetail(wageLockId);
}

function cacheDom() {
  dom.messageArea = document.querySelector("#wageDetailMessageArea");
  dom.loadingState = document.querySelector("#wageDetailLoadingState");
  dom.content = document.querySelector("#wageDetailContent");
  dom.returnLink = document.querySelector("#wageDetailReturnLink");
  dom.titleText = document.querySelector("#wageDetailTitleText");
  dom.basicInfo = document.querySelector("#wageDetailBasicInfo");
  dom.amountInfo = document.querySelector("#wageDetailAmountInfo");
  dom.summaryInfo = document.querySelector("#wageDetailSummaryInfo");
  dom.systemInfo = document.querySelector("#wageDetailSystemInfo");
  dom.paymentRequests = document.querySelector("#wageDetailPaymentRequests");
  dom.openCreatePaymentRequestButton = document.querySelector("#openCreatePaymentRequestButton");
  dom.createPaymentRequestDialog = document.querySelector("#createPaymentRequestDialog");
  dom.createPaymentRequestSummary = document.querySelector("#createPaymentRequestSummary");
  dom.createPaymentRequestError = document.querySelector("#createPaymentRequestError");
  dom.createPaymentRequestConfirmCheckbox = document.querySelector("#createPaymentRequestConfirmCheckbox");
  dom.createPaymentRequestSubmitButton = document.querySelector("#createPaymentRequestSubmitButton");
  dom.createPaymentRequestCancelButton = document.querySelector("#createPaymentRequestCancelButton");
  dom.rowCount = document.querySelector("#wageDetailRowCount");
  dom.rowEmpty = document.querySelector("#wageDetailRowEmpty");
  dom.rows = document.querySelector("#wageDetailRows");
}

function bindEvents() {
  dom.openCreatePaymentRequestButton?.addEventListener("click", openCreatePaymentRequestDialog);
  dom.createPaymentRequestCancelButton?.addEventListener("click", closeCreatePaymentRequestDialog);
  dom.createPaymentRequestSubmitButton?.addEventListener("click", submitCreatePaymentRequest);
  dom.createPaymentRequestDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createPaymentRequestDialog) {
      closeCreatePaymentRequestDialog();
    }
  });
  dom.createPaymentRequestConfirmCheckbox?.addEventListener("change", () => {
    setCreatePaymentRequestFieldInvalid("confirm", false);
    hideCreatePaymentRequestErrorIfClean();
  });
}

function readWageLockId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || "";
}

function configureReturnLink() {
  if (dom.returnLink) {
    dom.returnLink.href = buildReturnUrl();
  }
}

function buildReturnUrl() {
  const sourceParams = new URLSearchParams(window.location.search);
  const targetParams = new URLSearchParams();
  const filterKeys = [
    "year",
    "month",
    "teacherId",
    "businessEntityId",
    "settlementType",
    "status",
    "keyword",
  ];

  for (const key of filterKeys) {
    const value = safeText(sourceParams.get(key)).trim();
    if (value) {
      targetParams.set(key, value);
    }
  }

  const query = targetParams.toString();
  return query ? `./wage.html?${query}` : "./wage.html";
}

async function loadWageDetail(wageLockId) {
  setLoading(true);
  setContentVisible(false);
  showMessage("info", "正在加载老师工资结算详情...");

  try {
    detailData = await fetchWageDetailPage(wageLockId);
    renderWageDetail(detailData);
    setContentVisible(true);
    showMessage("success", "老师工资结算详情已加载。");
  } catch (error) {
    detailData = null;
    setContentVisible(false);
    showMessage("error", `读取老师工资结算详情失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderWageDetail(data) {
  const { wageLock, details, paymentRequests } = data;
  const detailTotalJpy = sumBy(details, "total_jpy");
  const detailTotalCny = sumBy(details, "total_cny");
  const detailPayHours = sumBy(details, "pay_hours");
  const totalJpyDifference = detailTotalJpy - Number(wageLock.total_jpy || 0);
  const totalCnyDifference = detailTotalCny - Number(wageLock.total_cny || 0);

  dom.titleText.textContent = `${formatMonth(wageLock.settlement_month)} / ${displayValue(wageLock.teacher_name)} / ${formatCurrency(wageLock.total_jpy, "JPY")}`;
  dom.basicInfo.innerHTML = renderDefinitionList([
    ["结算月份", formatMonth(wageLock.settlement_month)],
    ["老师", displayValue(wageLock.teacher_name)],
    ["业务归属", displayValue(wageLock.business_name)],
    ["结算类型", settlementTypeLabel(wageLock.settlement_type)],
    ["状态", wageStatusLabel(wageLock.status)],
    ["生成时间", formatDate(wageLock.locked_at)],
    ["作废时间", formatDate(wageLock.voided_at)],
    ["创建时间", formatDate(wageLock.created_at)],
    ["更新时间", formatDate(wageLock.updated_at)],
  ]);

  dom.amountInfo.innerHTML = renderDefinitionList([
    ["汇率", displayValue(wageLock.exchange_rate)],
    ["课时数", displayValue(wageLock.lesson_count)],
    ["总分钟", displayValue(wageLock.total_minutes)],
    ["支付小时", displayValue(wageLock.pay_hours)],
    ["课时工资 JPY", formatCurrency(wageLock.lesson_wage_jpy, "JPY")],
    ["课时工资 CNY", formatCurrency(wageLock.lesson_wage_cny, "CNY")],
    ["费用 JPY", formatCurrency(wageLock.fee_jpy, "JPY")],
    ["合计 JPY", formatCurrency(wageLock.total_jpy, "JPY")],
    ["合计 CNY", formatCurrency(wageLock.total_cny, "CNY")],
  ]);

  dom.summaryInfo.innerHTML = `
    ${renderDefinitionList([
      ["明细条数", displayCount(details.length)],
      ["明细支付小时合计", displayValue(detailPayHours)],
      ["明细合计 JPY", formatCurrency(detailTotalJpy, "JPY")],
      ["主表合计 JPY", formatCurrency(wageLock.total_jpy, "JPY")],
      ["JPY 差异", formatCurrency(totalJpyDifference, "JPY")],
      ["明细合计 CNY", formatCurrency(detailTotalCny, "CNY")],
      ["主表合计 CNY", formatCurrency(wageLock.total_cny, "CNY")],
      ["CNY 差异", formatCurrency(totalCnyDifference, "CNY")],
    ])}
    <p class="section-note">本区仅用于明细对账辅助，不重新计算或覆盖工资快照主表金额。</p>
  `;

  dom.systemInfo.innerHTML = renderDefinitionList([
    ["wage lock id", shortId(wageLock.id)],
    ["teacher_id", shortId(wageLock.teacher_id)],
    ["business_entity_id", shortId(wageLock.business_entity_id)],
    ["created_at", formatDate(wageLock.created_at)],
    ["updated_at", formatDate(wageLock.updated_at)],
  ]);

  renderPaymentRequests(paymentRequests);
  renderCreatePaymentRequestAction(wageLock, paymentRequests);
  renderDetailRows(details);
}

function renderCreatePaymentRequestAction(wageLock, paymentRequests) {
  const canCreate = wageLock.status === "locked"
    && !wageLock.voided_at
    && Number(wageLock.total_jpy || 0) > 0
    && paymentRequests.length === 0;

  dom.openCreatePaymentRequestButton.classList.toggle("is-hidden", !canCreate);
}

function openCreatePaymentRequestDialog() {
  const wageLock = detailData?.wageLock;
  const paymentRequests = detailData?.paymentRequests || [];

  if (!wageLock) {
    showMessage("error", "工资快照记录尚未加载。");
    return;
  }

  if (paymentRequests.length > 0) {
    showMessage("error", "该工资快照记录已有关联支付请求，不能重复生成。");
    return;
  }

  if (wageLock.status !== "locked" || wageLock.voided_at) {
    showMessage("error", "只有未作废的已生成工资快照可以生成支付请求。");
    return;
  }

  if (Number(wageLock.total_jpy || 0) <= 0) {
    showMessage("error", "工资结算金额为 0，不能生成支付请求。");
    return;
  }

  hideCreatePaymentRequestError();
  setCreatePaymentRequestFieldInvalid("confirm", false);
  dom.createPaymentRequestConfirmCheckbox.checked = false;
  dom.createPaymentRequestSummary.innerHTML = renderCreatePaymentRequestSummary(wageLock);
  dom.createPaymentRequestDialog.classList.remove("is-hidden");
  dom.createPaymentRequestDialog.setAttribute("aria-hidden", "false");
}

function closeCreatePaymentRequestDialog(force = false) {
  if (!force && dom.createPaymentRequestSubmitButton.disabled) {
    return;
  }

  dom.createPaymentRequestDialog.classList.add("is-hidden");
  dom.createPaymentRequestDialog.setAttribute("aria-hidden", "true");
  dom.createPaymentRequestConfirmCheckbox.checked = false;
  hideCreatePaymentRequestError();
  setCreatePaymentRequestFieldInvalid("confirm", false);
}

async function submitCreatePaymentRequest() {
  const wageLock = detailData?.wageLock;
  if (!wageLock) {
    showCreatePaymentRequestError("工资快照记录尚未加载。");
    return;
  }

  if (!dom.createPaymentRequestConfirmCheckbox.checked) {
    showCreatePaymentRequestError("请先勾选确认说明。", ["confirm"]);
    return;
  }

  setCreatePaymentRequestSubmitting(true);
  hideCreatePaymentRequestError();

  try {
    const paymentRequest = await createTeacherWagePaymentRequest({
      wageLockId: wageLock.id,
    });

    await loadWageDetail(wageLock.id);
    closeCreatePaymentRequestDialog(true);
    showMessage(
      "success",
      `老师工资支付请求已生成：${shortId(paymentRequest?.payment_request_id)} / ${formatCurrency(paymentRequest?.amount, paymentRequest?.currency || "JPY")}。`
    );
  } catch (error) {
    showCreatePaymentRequestError(formatCreatePaymentRequestError(error));
  } finally {
    setCreatePaymentRequestSubmitting(false);
  }
}

function renderPaymentRequests(requests) {
  if (!requests.length) {
    dom.paymentRequests.innerHTML = '<div class="state-text">尚未生成支付请求。</div>';
    return;
  }

  dom.paymentRequests.innerHTML = requests.map((request) => `
    <article class="detail-list-card">
      <div class="detail-list-card-header">
        <strong>${escapeHtml(shortId(request.id))}</strong>
        <span class="status-badge ${escapeAttribute(paymentRequestStatusClass(request.status))}">${escapeHtml(paymentRequestStatusLabel(request.status))}</span>
      </div>
      <p><a class="table-action-button" href="./payment-detail.html?id=${encodeURIComponent(request.id)}">支付请求详情</a></p>
      ${request.status === "reversed" || request.status === "void" ? '<p class="section-note">该支付请求已撤销或作废；本页仅展示工资支付状态链，不提供任何支付操作。</p>' : ""}
      ${renderDefinitionList([
        ["请求月份", formatMonth(request.request_month)],
        ["收款方", displayValue(request.payee_name)],
        ["金额", formatCurrency(request.amount, request.currency)],
        ["paid_at", formatDate(request.paid_at)],
        ["reversed_at", formatDate(request.reversed_at)],
        ["撤销原因", displayValue(request.reversal_reason)],
        ["paid_account_transaction_id", shortId(request.paid_account_transaction_id)],
        ["reversal_transaction_id", shortId(request.reversal_transaction_id)],
        ["reissued_from", shortId(request.reissued_from_payment_request_id)],
        ["replacement", shortId(request.replacement_payment_request_id)],
        ["reissue_reason", displayValue(request.reissue_reason)],
        ["reissued_at", formatDate(request.reissued_at)],
        ["created_at", formatDate(request.created_at)],
      ])}
      ${request.paid_expense_id ? `<p><a class="table-action-button" href="./expense-detail.html?id=${encodeURIComponent(request.paid_expense_id)}">支出详情</a></p>` : ""}
    </article>
  `).join("");
}

function renderCreatePaymentRequestSummary(wageLock) {
  return [
    renderDialogSummaryRow("工资月份", formatMonth(wageLock.settlement_month)),
    renderDialogSummaryRow("老师", displayValue(wageLock.teacher_name)),
    renderDialogSummaryRow("业务归属", displayValue(wageLock.business_name)),
    renderDialogSummaryRow("支付对象", "老师"),
    renderDialogSummaryRow("请求金额", formatCurrency(wageLock.total_jpy, "JPY")),
    renderDialogSummaryRow("来源", `工资快照 ${shortId(wageLock.id)}`),
  ].join("");
}

function renderDialogSummaryRow(label, value) {
  return `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(value)}</span>
    </div>
  `;
}

function formatCreatePaymentRequestError(error) {
  const message = error?.message || String(error || "");

  if (message.includes("already exists")) {
    return `生成失败：该工资快照记录已有关联支付请求，不能重复生成。${message}`;
  }

  if (message.includes("total_jpy")) {
    return `生成失败：工资结算金额必须大于 0。${message}`;
  }

  return `生成失败：${message}`;
}

function setCreatePaymentRequestSubmitting(isSubmitting) {
  dom.createPaymentRequestSubmitButton.disabled = isSubmitting;
  dom.createPaymentRequestCancelButton.disabled = isSubmitting;
  dom.openCreatePaymentRequestButton.disabled = isSubmitting;
  dom.createPaymentRequestSubmitButton.textContent = isSubmitting ? "生成中..." : "确认生成";
}

function showCreatePaymentRequestError(message, fieldIds = []) {
  dom.createPaymentRequestError.textContent = message;
  dom.createPaymentRequestError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCreatePaymentRequestFieldInvalid(fieldId, true);
  }
  dom.createPaymentRequestDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function hideCreatePaymentRequestError() {
  dom.createPaymentRequestError.textContent = "";
  dom.createPaymentRequestError.classList.add("is-hidden");
}

function hideCreatePaymentRequestErrorIfClean() {
  const hasInvalidField = Boolean(dom.createPaymentRequestDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    hideCreatePaymentRequestError();
  }
}

function setCreatePaymentRequestFieldInvalid(fieldId, isInvalid) {
  const field = dom.createPaymentRequestDialog.querySelector(`[data-create-payment-request-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", isInvalid);
}

function renderDetailRows(rows) {
  dom.rowCount.textContent = `${rows.length} 条`;
  dom.rowEmpty.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.rows.innerHTML = "";
    return;
  }

  dom.rows.innerHTML = rows.map((row) => `
    <tr>
      <td class="wage-nowrap">${escapeHtml(formatDateOnly(row.lesson_date))}</td>
      <td class="wage-nowrap">${escapeHtml(timeRange(row.start_time, row.end_time))}</td>
      <td>${escapeHtml(displayValue(row.student_name))}</td>
      <td>${escapeHtml(displayValue(row.subject_name))}</td>
      <td>${escapeHtml(displayValue(row.business_name))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(displayValue(row.pay_hours))}</td>
      <td><span class="status-badge status-neutral">${escapeHtml(settlementTypeLabel(row.settlement_type))}</span></td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.lesson_wage_jpy, "JPY"))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.lesson_wage_cny, "CNY"))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.transport_fee_jpy, "JPY"))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.classroom_fee_jpy, "JPY"))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.total_jpy, "JPY"))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.total_cny, "CNY"))}</td>
      <td class="wage-nowrap">${escapeHtml(booleanLabel(row.is_no_wage))}</td>
      <td><span class="status-badge ${escapeAttribute(detailStatusClass(row.status))}">${escapeHtml(detailStatusLabel(row.status))}</span></td>
      <td class="wage-detail-content-cell"><span class="table-cell-summary">${escapeHtml(displayValue(row.lesson_content))}</span></td>
    </tr>
  `).join("");
}

function renderDefinitionList(items) {
  return `
    <dl class="detail-definition-list">
      ${items.map(([label, value]) => `
        <div>
          <dt>${escapeHtml(label)}</dt>
          <dd>${escapeHtml(displayValue(value))}</dd>
        </div>
      `).join("")}
    </dl>
  `;
}

function wageStatusLabel(value) {
  return WAGE_STATUS_LABELS[value] || displayValue(value);
}

function settlementTypeLabel(value) {
  return SETTLEMENT_TYPE_LABELS[value] || displayValue(value);
}

function detailStatusLabel(value) {
  return DETAIL_STATUS_LABELS[value] || displayValue(value);
}

function paymentRequestStatusLabel(value) {
  return PAYMENT_REQUEST_STATUS_LABELS[value] || displayValue(value);
}

function paymentRequestStatusClass(value) {
  if (value === "paid") return "status-paid";
  if (value === "pending") return "status-pending";
  if (value === "reversed" || value === "void" || value === "cancelled") return "status-cancelled";
  return "status-neutral";
}

function detailStatusClass(value) {
  if (value === "completed" || value === "makeup_completed") {
    return "status-paid";
  }

  return "status-neutral";
}

function timeRange(startTime, endTime) {
  const start = safeText(startTime);
  const end = safeText(endTime);
  if (start && end) return `${start} - ${end}`;
  return start || end || "-";
}

function booleanLabel(value) {
  if (value === true) return "是";
  if (value === false) return "否";
  return "-";
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
}

function sumBy(rows, key) {
  return rows.reduce((total, row) => total + Number(row[key] || 0), 0);
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

function setContentVisible(isVisible) {
  dom.content.classList.toggle("is-hidden", !isVisible);
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
