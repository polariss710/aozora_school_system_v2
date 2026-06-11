import { hasSupabaseConfig } from "../supabase-client.js";
import {
  adjustTeacherWageDetail,
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

const DUTY_REPORT_MIN_DETAIL_ROWS = 31;
const DUTY_REPORT_HEADERS = [
  "日期及星期",
  "学生",
  "课程 / 工作内容",
  "",
  "开始时间",
  "结束时间",
  "结算课时",
  "课时工资 JPY",
  "交通费 JPY",
  "教室费 JPY",
  "明细合计 JPY",
  "备注",
];

const dom = {};
let detailData = null;
let activeAdjustWageDetail = null;

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
  dom.wageDutyReportExportButton = document.querySelector("#wageDutyReportExportButton");
  dom.createPaymentRequestDialog = document.querySelector("#createPaymentRequestDialog");
  dom.createPaymentRequestSummary = document.querySelector("#createPaymentRequestSummary");
  dom.createPaymentRequestError = document.querySelector("#createPaymentRequestError");
  dom.createPaymentRequestConfirmCheckbox = document.querySelector("#createPaymentRequestConfirmCheckbox");
  dom.createPaymentRequestSubmitButton = document.querySelector("#createPaymentRequestSubmitButton");
  dom.createPaymentRequestCancelButton = document.querySelector("#createPaymentRequestCancelButton");
  dom.rowCount = document.querySelector("#wageDetailRowCount");
  dom.rowEmpty = document.querySelector("#wageDetailRowEmpty");
  dom.rows = document.querySelector("#wageDetailRows");
  dom.adjustmentAuditCount = document.querySelector("#wageAdjustmentAuditCount");
  dom.adjustmentAuditEmpty = document.querySelector("#wageAdjustmentAuditEmpty");
  dom.adjustmentAuditList = document.querySelector("#wageAdjustmentAuditList");
  dom.adjustWageDetailDialog = document.querySelector("#adjustWageDetailDialog");
  dom.adjustWageDetailSummary = document.querySelector("#adjustWageDetailSummary");
  dom.adjustWageDetailError = document.querySelector("#adjustWageDetailError");
  dom.adjustWagePayHoursInput = document.querySelector("#adjustWagePayHoursInput");
  dom.adjustWageTransportFeeInput = document.querySelector("#adjustWageTransportFeeInput");
  dom.adjustWageClassroomFeeInput = document.querySelector("#adjustWageClassroomFeeInput");
  dom.adjustWageReasonInput = document.querySelector("#adjustWageReasonInput");
  dom.adjustWageDetailSubmitButton = document.querySelector("#adjustWageDetailSubmitButton");
  dom.adjustWageDetailCancelButton = document.querySelector("#adjustWageDetailCancelButton");
}

function bindEvents() {
  dom.openCreatePaymentRequestButton?.addEventListener("click", openCreatePaymentRequestDialog);
  dom.wageDutyReportExportButton?.addEventListener("click", handleWageDutyReportExport);
  dom.rows?.addEventListener("click", handleWageDetailRowActionClick);
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
  dom.adjustWageDetailCancelButton?.addEventListener("click", closeAdjustWageDetailDialog);
  dom.adjustWageDetailSubmitButton?.addEventListener("click", submitAdjustWageDetail);
  dom.adjustWageDetailDialog?.addEventListener("click", (event) => {
    if (event.target === dom.adjustWageDetailDialog) {
      closeAdjustWageDetailDialog();
    }
  });
  for (const input of [
    dom.adjustWagePayHoursInput,
    dom.adjustWageTransportFeeInput,
    dom.adjustWageClassroomFeeInput,
    dom.adjustWageReasonInput,
  ]) {
    input?.addEventListener("input", () => {
      const fieldId = input.id === "adjustWagePayHoursInput"
        ? "payHours"
        : input.id === "adjustWageTransportFeeInput"
          ? "transportFeeJpy"
          : input.id === "adjustWageClassroomFeeInput"
            ? "classroomFeeJpy"
            : "reason";
      setAdjustWageDetailFieldInvalid(fieldId, false);
      hideAdjustWageDetailErrorIfClean();
    });
  }
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
  const { wageLock, details, paymentRequests, adjustments } = data;
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
    ["结算课时", displayValue(wageLock.pay_hours)],
    ["课时工资 JPY", formatCurrency(wageLock.lesson_wage_jpy, "JPY")],
    ["课时工资 CNY", formatCurrency(wageLock.lesson_wage_cny, "CNY")],
    ["费用 JPY", formatCurrency(wageLock.fee_jpy, "JPY")],
    ["合计 JPY", formatCurrency(wageLock.total_jpy, "JPY")],
    ["合计 CNY", formatCurrency(wageLock.total_cny, "CNY")],
  ]);

  dom.summaryInfo.innerHTML = `
    ${renderDefinitionList([
      ["明细条数", displayCount(details.length)],
      ["明细结算课时合计", displayValue(detailPayHours)],
      ["明细合计 JPY", formatCurrency(detailTotalJpy, "JPY")],
      ["主表合计 JPY", formatCurrency(wageLock.total_jpy, "JPY")],
      ["JPY 差异", formatCurrency(totalJpyDifference, "JPY")],
      ["明细合计 CNY", formatCurrency(detailTotalCny, "CNY")],
      ["主表合计 CNY", formatCurrency(wageLock.total_cny, "CNY")],
      ["CNY 差异", formatCurrency(totalCnyDifference, "CNY")],
    ])}
    <p class="section-note">本区仅用于明细对账辅助；如需调整，请通过明细行操作触发 DB/RPC 重新计算并写入审计记录。</p>
  `;

  dom.systemInfo.innerHTML = renderDefinitionList([
    ["wage snapshot id", shortId(wageLock.id)],
    ["teacher_id", shortId(wageLock.teacher_id)],
    ["business_entity_id", shortId(wageLock.business_entity_id)],
    ["created_at", formatDate(wageLock.created_at)],
    ["updated_at", formatDate(wageLock.updated_at)],
  ]);

  renderPaymentRequests(paymentRequests);
  renderCreatePaymentRequestAction(wageLock, paymentRequests);
  renderDetailRows(details, canAdjustWageDetails(wageLock, paymentRequests));
  renderAdjustmentAudits(adjustments || [], details || []);
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

function renderDetailRows(rows, canAdjust = false) {
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
      <td class="wage-nowrap">${renderWageDetailRowAction(row, canAdjust)}</td>
    </tr>
  `).join("");
}

function renderWageDetailRowAction(row, canAdjust) {
  if (!canAdjust) {
    return '<span class="section-note">只读</span>';
  }

  return `
    <button
      class="table-action-button"
      type="button"
      data-wage-detail-adjust-id="${escapeAttribute(row.id)}"
    >调整</button>
  `;
}

function handleWageDetailRowActionClick(event) {
  const button = event.target.closest("[data-wage-detail-adjust-id]");
  if (!button) {
    return;
  }

  const detailId = button.getAttribute("data-wage-detail-adjust-id");
  const detail = (detailData?.details || []).find((row) => row.id === detailId);
  if (!detail) {
    showMessage("error", "没有找到要调整的工资明细，请刷新页面后重试。");
    return;
  }

  openAdjustWageDetailDialog(detail);
}

function canAdjustWageDetails(wageLock, paymentRequests = []) {
  return wageLock?.status === "locked"
    && !wageLock?.voided_at
    && paymentRequests.length === 0;
}

function wageAdjustmentReadonlyReason(wageLock, paymentRequests = []) {
  if (!wageLock) return "工资快照尚未加载。";
  if (wageLock.status !== "locked") return "只有已生成且未作废的工资快照可以调整。";
  if (wageLock.voided_at) return "已作废的工资快照不能调整。";
  if (paymentRequests.length > 0) return "该工资快照已生成支付请求，不能直接调整。";
  return "";
}

function openAdjustWageDetailDialog(detail) {
  const wageLock = detailData?.wageLock;
  const paymentRequests = detailData?.paymentRequests || [];
  const readonlyReason = wageAdjustmentReadonlyReason(wageLock, paymentRequests);
  if (readonlyReason) {
    showMessage("error", readonlyReason);
    return;
  }

  activeAdjustWageDetail = detail;
  dom.adjustWageDetailSummary.innerHTML = renderAdjustWageDetailSummary(detail, wageLock);
  dom.adjustWagePayHoursInput.value = numberInputValue(detail.pay_hours);
  dom.adjustWageTransportFeeInput.value = numberInputValue(detail.transport_fee_jpy);
  dom.adjustWageClassroomFeeInput.value = numberInputValue(detail.classroom_fee_jpy);
  dom.adjustWageReasonInput.value = "";
  hideAdjustWageDetailError();
  clearAdjustWageDetailInvalidFields();
  dom.adjustWageDetailDialog.classList.remove("is-hidden");
  dom.adjustWageDetailDialog.setAttribute("aria-hidden", "false");
}

function closeAdjustWageDetailDialog(force = false) {
  if (!force && dom.adjustWageDetailSubmitButton.disabled) {
    return;
  }

  activeAdjustWageDetail = null;
  dom.adjustWageDetailDialog.classList.add("is-hidden");
  dom.adjustWageDetailDialog.setAttribute("aria-hidden", "true");
  hideAdjustWageDetailError();
  clearAdjustWageDetailInvalidFields();
}

async function submitAdjustWageDetail() {
  const wageLock = detailData?.wageLock;
  const detail = activeAdjustWageDetail;
  if (!wageLock || !detail) {
    showAdjustWageDetailError("工资明细尚未加载。");
    return;
  }

  const validation = validateAdjustWageDetailForm(detail);
  if (validation.errors.length) {
    showAdjustWageDetailError(validation.errors[0], validation.fields);
    return;
  }

  setAdjustWageDetailSubmitting(true);
  hideAdjustWageDetailError();

  try {
    const result = await adjustTeacherWageDetail({
      wageDetailId: detail.id,
      payHours: validation.values.payHours,
      transportFeeJpy: validation.values.transportFeeJpy,
      classroomFeeJpy: validation.values.classroomFeeJpy,
      reason: validation.values.reason,
    });

    await loadWageDetail(wageLock.id);
    closeAdjustWageDetailDialog(true);
    showMessage(
      "success",
      `工资明细已调整：${shortId(result?.adjustment_id)} / 快照合计 ${formatCurrency(result?.lock_total_jpy, "JPY")}。`
    );
  } catch (error) {
    showAdjustWageDetailError(formatAdjustWageDetailError(error));
  } finally {
    setAdjustWageDetailSubmitting(false);
  }
}

function validateAdjustWageDetailForm(detail) {
  const errors = [];
  const fields = [];
  const payHours = Number(dom.adjustWagePayHoursInput.value);
  const transportFeeJpy = Number(dom.adjustWageTransportFeeInput.value || 0);
  const classroomFeeJpy = Number(dom.adjustWageClassroomFeeInput.value || 0);
  const reason = safeText(dom.adjustWageReasonInput.value).trim();

  if (!Number.isFinite(payHours) || payHours < 0 || payHours > 24) {
    errors.push("结算课时必须在 0 到 24 之间。");
    fields.push("payHours");
  }

  if (!Number.isFinite(transportFeeJpy) || transportFeeJpy < 0 || transportFeeJpy > 1000000) {
    errors.push("交通费必须在 0 到 1,000,000 JPY 之间。");
    fields.push("transportFeeJpy");
  }

  if (!Number.isFinite(classroomFeeJpy) || classroomFeeJpy < 0 || classroomFeeJpy > 1000000) {
    errors.push("教室费必须在 0 到 1,000,000 JPY 之间。");
    fields.push("classroomFeeJpy");
  }

  if (!reason) {
    errors.push("请输入调整备注。");
    fields.push("reason");
  }

  if (!errors.length
    && payHours === Number(detail.pay_hours || 0)
    && Math.round(transportFeeJpy) === Number(detail.transport_fee_jpy || 0)
    && Math.round(classroomFeeJpy) === Number(detail.classroom_fee_jpy || 0)) {
    errors.push("调整前后数值没有变化。");
    fields.push("payHours", "transportFeeJpy", "classroomFeeJpy");
  }

  return {
    errors,
    fields,
    values: {
      payHours,
      transportFeeJpy: Math.round(transportFeeJpy),
      classroomFeeJpy: Math.round(classroomFeeJpy),
      reason,
    },
  };
}

function renderAdjustWageDetailSummary(detail, wageLock) {
  return [
    renderDialogSummaryRow("工资月份", formatMonth(wageLock?.settlement_month)),
    renderDialogSummaryRow("老师", displayValue(wageLock?.teacher_name)),
    renderDialogSummaryRow("课时日期", formatDateOnly(detail.lesson_date)),
    renderDialogSummaryRow("学生", displayValue(detail.student_name)),
    renderDialogSummaryRow("科目", displayValue(detail.subject_name)),
    renderDialogSummaryRow("当前结算课时", displayValue(detail.pay_hours)),
    renderDialogSummaryRow("当前交通费", formatCurrency(detail.transport_fee_jpy, "JPY")),
    renderDialogSummaryRow("当前教室费", formatCurrency(detail.classroom_fee_jpy, "JPY")),
    renderDialogSummaryRow("当前明细合计", formatCurrency(detail.total_jpy, "JPY")),
  ].join("");
}

function formatAdjustWageDetailError(error) {
  const message = error?.message || String(error || "");
  if (message.includes("已生成支付请求")) {
    return "调整失败：该工资快照已生成支付请求，不能直接修改。";
  }
  return `调整失败：${message}`;
}

function setAdjustWageDetailSubmitting(isSubmitting) {
  dom.adjustWageDetailSubmitButton.disabled = isSubmitting;
  dom.adjustWageDetailCancelButton.disabled = isSubmitting;
  dom.adjustWageDetailSubmitButton.textContent = isSubmitting ? "保存中..." : "保存调整";
}

function showAdjustWageDetailError(message, fieldIds = []) {
  dom.adjustWageDetailError.textContent = message;
  dom.adjustWageDetailError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setAdjustWageDetailFieldInvalid(fieldId, true);
  }
  dom.adjustWageDetailDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function hideAdjustWageDetailError() {
  dom.adjustWageDetailError.textContent = "";
  dom.adjustWageDetailError.classList.add("is-hidden");
}

function hideAdjustWageDetailErrorIfClean() {
  const hasInvalidField = Boolean(dom.adjustWageDetailDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    hideAdjustWageDetailError();
  }
}

function clearAdjustWageDetailInvalidFields() {
  for (const field of dom.adjustWageDetailDialog.querySelectorAll(".field.is-invalid")) {
    field.classList.remove("is-invalid");
  }
}

function setAdjustWageDetailFieldInvalid(fieldId, isInvalid) {
  const field = dom.adjustWageDetailDialog.querySelector(`[data-adjust-wage-detail-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", isInvalid);
}

function renderAdjustmentAudits(adjustments, details) {
  dom.adjustmentAuditCount.textContent = `${adjustments.length} 条`;
  dom.adjustmentAuditEmpty.classList.toggle("is-hidden", adjustments.length > 0);

  if (!adjustments.length) {
    dom.adjustmentAuditList.innerHTML = "";
    return;
  }

  const detailsById = new Map(details.map((detail) => [detail.id, detail]));
  dom.adjustmentAuditList.innerHTML = adjustments.map((adjustment) => {
    const detail = detailsById.get(adjustment.wage_detail_id);
    return `
      <article class="detail-list-card">
        <div class="detail-list-card-header">
          <strong>${escapeHtml(shortId(adjustment.id))}</strong>
          <span>${escapeHtml(formatDate(adjustment.created_at))}</span>
        </div>
        ${renderDefinitionList([
          ["明细", adjustmentDetailLabel(detail, adjustment)],
          ["结算课时", formatNumberChange(adjustment.old_pay_hours, adjustment.new_pay_hours)],
          ["课时工资 JPY", formatCurrencyChange(adjustment.old_lesson_wage_jpy, adjustment.new_lesson_wage_jpy, "JPY")],
          ["交通费 JPY", formatCurrencyChange(adjustment.old_transport_fee_jpy, adjustment.new_transport_fee_jpy, "JPY")],
          ["教室费 JPY", formatCurrencyChange(adjustment.old_classroom_fee_jpy, adjustment.new_classroom_fee_jpy, "JPY")],
          ["明细合计 JPY", formatCurrencyChange(adjustment.old_total_jpy, adjustment.new_total_jpy, "JPY")],
          ["快照合计 JPY", formatCurrencyChange(adjustment.old_lock_total_jpy, adjustment.new_lock_total_jpy, "JPY")],
          ["备注", displayValue(adjustment.reason)],
        ])}
      </article>
    `;
  }).join("");
}

function adjustmentDetailLabel(detail, adjustment) {
  if (!detail) {
    return `工资明细 ${shortId(adjustment.wage_detail_id)}`;
  }

  return [
    formatDateOnly(detail.lesson_date),
    displayValue(detail.student_name),
    displayValue(detail.subject_name),
  ].filter((value) => value && value !== "-").join(" / ");
}

function formatNumberChange(oldValue, newValue) {
  return `${displayValue(oldValue)} -> ${displayValue(newValue)}`;
}

function formatCurrencyChange(oldValue, newValue, currency) {
  return `${formatCurrency(oldValue, currency)} -> ${formatCurrency(newValue, currency)}`;
}

function handleWageDutyReportExport() {
  if (!detailData?.wageLock) {
    showMessage("error", "工资快照记录尚未加载，不能导出勤务申报表。");
    return;
  }

  if (!window.XLSX?.utils?.aoa_to_sheet || !window.XLSX?.writeFile) {
    showMessage("error", "Excel 导出库尚未加载，请刷新页面后重试。");
    return;
  }

  try {
    exportWageDutyReportXlsx(detailData);
    showMessage("success", "勤务申报表 Excel 已导出。");
  } catch (error) {
    showMessage("error", `导出勤务申报表失败：${error.message || error}`);
  }
}

function exportWageDutyReportXlsx(data) {
  const { wageLock, details } = data;
  const xlsx = window.XLSX;
  const workbook = xlsx.utils.book_new();
  const report = buildWageDutyReport(wageLock, details || []);
  const sheet = xlsx.utils.aoa_to_sheet(report.rows);

  sheet["!cols"] = [
    { wch: 18 },
    { wch: 16 },
    { wch: 28 },
    { wch: 28 },
    { wch: 12 },
    { wch: 12 },
    { wch: 12 },
    { wch: 14 },
    { wch: 14 },
    { wch: 14 },
    { wch: 16 },
    { wch: 22 },
  ];
  sheet["!rows"] = report.rows.map((_, index) => ({
    hpt: index === 0 ? 28 : index === 2 ? 34 : 22,
  }));
  sheet["!merges"] = report.merges.map((range) => xlsx.utils.decode_range(range));

  styleWageDutyReportSheet(sheet, report);
  xlsx.utils.book_append_sheet(workbook, sheet, "勤务申报表");
  xlsx.writeFile(workbook, buildWageDutyReportFileName(wageLock), {
    bookType: "xlsx",
    cellStyles: true,
  });
}

function buildWageDutyReport(wageLock, details) {
  const detailRowCount = Math.max(DUTY_REPORT_MIN_DETAIL_ROWS, details.length);
  const rows = [
    ["勤务申报表（讲师填写用）", "", "", "", "", "", "", "", "", "", "", ""],
    [
      "月份",
      japaneseMonthText(wageLock.settlement_month),
      "姓名",
      displayValue(wageLock.teacher_name),
      "",
      "",
      "支付方式",
      "日元银行 / 支付宝 / 微信",
      "",
      "",
      "",
      "",
    ],
    [
      "※ 本表用于老师确认工资快照明细并补充交通费、教室费、备注和支付信息。请勿修改系统已填写的日期、学生、课程、开始时间、结束时间、结算课时和课时工资。",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
    DUTY_REPORT_HEADERS,
  ];

  for (let index = 0; index < detailRowCount; index += 1) {
    const detail = details[index] || null;
    const excelRow = 5 + index;
    rows.push(buildDutyDetailRow(detail, excelRow));
  }

  const detailStartRow = 5;
  const detailEndRow = detailStartRow + detailRowCount - 1;
  const totalRowNumber = detailEndRow + 1;
  rows.push([
    "合计",
    "",
    "",
    "",
    "",
    "",
    { f: `SUM(G${detailStartRow}:G${detailEndRow})` },
    { f: `SUM(H${detailStartRow}:H${detailEndRow})` },
    { f: `SUM(I${detailStartRow}:I${detailEndRow})` },
    { f: `SUM(J${detailStartRow}:J${detailEndRow})` },
    { f: `SUM(K${detailStartRow}:K${detailEndRow})` },
    "",
  ]);

  rows.push([
    `系统快照合计：结算课时 ${displayValue(wageLock.pay_hours)} / 课时工资 ${formatCurrency(wageLock.lesson_wage_jpy, "JPY")} / 费用 ${formatCurrency(wageLock.fee_jpy, "JPY")} / 合计 ${formatCurrency(wageLock.total_jpy, "JPY")}`,
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
  ]);

  rows.push(["日元支付（银行振込）", "", "", "", "", "", "", "", "", "", "", ""]);
  rows.push(["銀行名", "支店番号", "支店名", "口座番号", "名義", "", "", "备注", "", "", "", ""]);
  rows.push(["", "", "", "", "", "", "", "", "", "", "", ""]);
  rows.push(["人民币支付", "", "", "", "", "", "", "", "", "", "", ""]);
  rows.push(["支付宝", "微信", "", "", "", "备注", "", "", "", "", "", ""]);
  rows.push(["", "", "", "", "", "", "", "", "", "", "", ""]);
  rows.push(["老师确认", "", "", "", "", "", "", "", "", "", "", ""]);
  rows.push(["确认日期", "", "老师签名", "", "", "备注", "", "", "", "", "", ""]);
  rows.push(["", "", "", "", "", "", "", "", "", "", "", ""]);

  const totalRowIndex = totalRowNumber - 1;
  const summaryRowIndex = totalRowIndex + 1;
  const bankTitleRowIndex = summaryRowIndex + 1;
  const bankHeaderRowIndex = bankTitleRowIndex + 1;
  const bankInputRowIndex = bankHeaderRowIndex + 1;
  const cnyTitleRowIndex = bankInputRowIndex + 1;
  const cnyHeaderRowIndex = cnyTitleRowIndex + 1;
  const cnyInputRowIndex = cnyHeaderRowIndex + 1;
  const confirmTitleRowIndex = cnyInputRowIndex + 1;
  const confirmHeaderRowIndex = confirmTitleRowIndex + 1;
  const confirmInputRowIndex = confirmHeaderRowIndex + 1;

  return {
    rows,
    detailStartRow,
    detailEndRow,
    totalRowIndex,
    summaryRowIndex,
    bankTitleRowIndex,
    bankHeaderRowIndex,
    bankInputRowIndex,
    cnyTitleRowIndex,
    cnyHeaderRowIndex,
    cnyInputRowIndex,
    confirmTitleRowIndex,
    confirmHeaderRowIndex,
    confirmInputRowIndex,
    merges: [
      "A1:L1",
      "D2:F2",
      "H2:L2",
      "A3:L3",
      ...Array.from({ length: detailRowCount }, (_, index) => `C${detailStartRow + index}:D${detailStartRow + index}`),
      `A${totalRowNumber}:F${totalRowNumber}`,
      `A${totalRowNumber + 1}:L${totalRowNumber + 1}`,
      `A${totalRowNumber + 2}:L${totalRowNumber + 2}`,
      `E${totalRowNumber + 3}:G${totalRowNumber + 3}`,
      `H${totalRowNumber + 3}:L${totalRowNumber + 3}`,
      `E${totalRowNumber + 4}:G${totalRowNumber + 4}`,
      `H${totalRowNumber + 4}:L${totalRowNumber + 4}`,
      `A${totalRowNumber + 5}:L${totalRowNumber + 5}`,
      `B${totalRowNumber + 6}:E${totalRowNumber + 6}`,
      `F${totalRowNumber + 6}:L${totalRowNumber + 6}`,
      `B${totalRowNumber + 7}:E${totalRowNumber + 7}`,
      `F${totalRowNumber + 7}:L${totalRowNumber + 7}`,
      `A${totalRowNumber + 8}:L${totalRowNumber + 8}`,
      `C${totalRowNumber + 9}:E${totalRowNumber + 9}`,
      `F${totalRowNumber + 9}:L${totalRowNumber + 9}`,
      `C${totalRowNumber + 10}:E${totalRowNumber + 10}`,
      `F${totalRowNumber + 10}:L${totalRowNumber + 10}`,
    ],
  };
}

function buildDutyDetailRow(detail, excelRow) {
  if (!detail) {
    return ["", "", "", "", "", "", 0, 0, 0, 0, { f: `H${excelRow}+I${excelRow}+J${excelRow}` }, ""];
  }

  return [
    dutyDateText(detail.lesson_date),
    displayValue(detail.student_name),
    dutyWorkContent(detail),
    "",
    timeOnly(detail.start_time),
    timeOnly(detail.end_time),
    numberOrZero(detail.pay_hours),
    numberOrZero(detail.lesson_wage_jpy),
    numberOrZero(detail.transport_fee_jpy),
    numberOrZero(detail.classroom_fee_jpy),
    { f: `H${excelRow}+I${excelRow}+J${excelRow}` },
    "",
  ];
}

function styleWageDutyReportSheet(sheet, report) {
  const allRange = `A1:L${report.rows.length}`;
  const baseStyle = {
    font: { name: "Arial", sz: 10 },
    alignment: { vertical: "center", wrapText: true },
    border: {
      top: { style: "thin", color: { rgb: "D9D9D9" } },
      bottom: { style: "thin", color: { rgb: "D9D9D9" } },
      left: { style: "thin", color: { rgb: "D9D9D9" } },
      right: { style: "thin", color: { rgb: "D9D9D9" } },
    },
  };
  const labelStyle = {
    ...baseStyle,
    font: { name: "Arial", sz: 10, bold: true },
    fill: { fgColor: { rgb: "EAF2F8" } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
  };
  const lockedStyle = {
    ...baseStyle,
    fill: { fgColor: { rgb: "F7F9FC" } },
  };
  const editableStyle = {
    ...baseStyle,
    fill: { fgColor: { rgb: "FFFCEB" } },
  };
  const totalStyle = {
    ...baseStyle,
    font: { name: "Arial", sz: 10, bold: true },
    fill: { fgColor: { rgb: "E2F0D9" } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
  };
  const sectionStyle = {
    ...baseStyle,
    font: { name: "Arial", sz: 11, bold: true },
    fill: { fgColor: { rgb: "D9EAD3" } },
    alignment: { horizontal: "left", vertical: "center", wrapText: true },
  };

  applyCellStyle(sheet, allRange, baseStyle);
  applyCellStyle(sheet, "A1:L1", {
    ...baseStyle,
    font: { name: "Arial", sz: 16, bold: true },
    alignment: { horizontal: "center", vertical: "center" },
    fill: { fgColor: { rgb: "D9EAF7" } },
  });
  applyCellStyle(sheet, "A2:A2", labelStyle);
  applyCellStyle(sheet, "C2:C2", labelStyle);
  applyCellStyle(sheet, "G2:G2", labelStyle);
  applyCellStyle(sheet, "B2:F2", lockedStyle);
  applyCellStyle(sheet, "H2:L2", editableStyle);
  applyCellStyle(sheet, "A3:L3", {
    ...baseStyle,
    fill: { fgColor: { rgb: "FFF2CC" } },
    alignment: { vertical: "center", wrapText: true },
  });
  applyCellStyle(sheet, "A4:L4", labelStyle);
  applyCellStyle(sheet, `A${report.detailStartRow}:H${report.detailEndRow}`, lockedStyle);
  applyCellStyle(sheet, `K${report.detailStartRow}:K${report.detailEndRow}`, lockedStyle);
  applyCellStyle(sheet, `I${report.detailStartRow}:J${report.detailEndRow}`, editableStyle);
  applyCellStyle(sheet, `L${report.detailStartRow}:L${report.detailEndRow}`, editableStyle);
  applyCellStyle(sheet, `A${report.totalRowIndex + 1}:L${report.totalRowIndex + 1}`, totalStyle);
  applyCellStyle(sheet, `A${report.summaryRowIndex + 1}:L${report.summaryRowIndex + 1}`, {
    ...baseStyle,
    font: { name: "Arial", sz: 10, bold: true },
    fill: { fgColor: { rgb: "F3F6FA" } },
  });

  for (const rowIndex of [report.bankTitleRowIndex, report.cnyTitleRowIndex, report.confirmTitleRowIndex]) {
    applyCellStyle(sheet, `A${rowIndex + 1}:L${rowIndex + 1}`, sectionStyle);
  }
  for (const rowIndex of [report.bankHeaderRowIndex, report.cnyHeaderRowIndex, report.confirmHeaderRowIndex]) {
    applyCellStyle(sheet, `A${rowIndex + 1}:L${rowIndex + 1}`, labelStyle);
  }
  for (const rowIndex of [report.bankInputRowIndex, report.cnyInputRowIndex, report.confirmInputRowIndex]) {
    applyCellStyle(sheet, `A${rowIndex + 1}:L${rowIndex + 1}`, editableStyle);
  }

  for (let row = report.detailStartRow; row <= report.detailEndRow; row += 1) {
    applyNumberFormat(sheet, `G${row}:G${row}`, "0.##");
    applyNumberFormat(sheet, `H${row}:K${row}`, "#,##0");
  }
  applyNumberFormat(sheet, `G${report.totalRowIndex + 1}:G${report.totalRowIndex + 1}`, "0.##");
  applyNumberFormat(sheet, `H${report.totalRowIndex + 1}:K${report.totalRowIndex + 1}`, "#,##0");
}

function applyCellStyle(sheet, range, style) {
  const decodedRange = window.XLSX.utils.decode_range(range);
  for (let row = decodedRange.s.r; row <= decodedRange.e.r; row += 1) {
    for (let column = decodedRange.s.c; column <= decodedRange.e.c; column += 1) {
      const address = window.XLSX.utils.encode_cell({ r: row, c: column });
      if (!sheet[address]) {
        sheet[address] = { t: "s", v: "" };
      }
      sheet[address].s = { ...(sheet[address].s || {}), ...style };
    }
  }
}

function applyNumberFormat(sheet, range, format) {
  const decodedRange = window.XLSX.utils.decode_range(range);
  for (let row = decodedRange.s.r; row <= decodedRange.e.r; row += 1) {
    for (let column = decodedRange.s.c; column <= decodedRange.e.c; column += 1) {
      const address = window.XLSX.utils.encode_cell({ r: row, c: column });
      if (sheet[address]) {
        sheet[address].z = format;
      }
    }
  }
}

function buildWageDutyReportFileName(wageLock) {
  const teacherName = sanitizeFileName(displayValue(wageLock.teacher_name)).replaceAll("-", "") || "teacher";
  const month = formatMonth(wageLock.settlement_month).replaceAll("/", "-");
  return `${teacherName}_${month}_勤务申报表.xlsx`;
}

function sanitizeFileName(value) {
  return safeText(value).replace(/[\\/:*?"<>|]/g, "-").trim();
}

function japaneseMonthText(value) {
  const text = safeText(value);
  const match = text.match(/^(\d{4})-(\d{2})/);
  if (!match) {
    return displayValue(text);
  }
  return `${match[1]}年${match[2]}月`;
}

function dutyDateText(value) {
  const text = safeText(value);
  const match = text.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!match) {
    return displayValue(text);
  }

  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  const weekday = ["日", "月", "火", "水", "木", "金", "土"][date.getDay()];
  return `${match[1]}/${match[2]}/${match[3]}（${weekday}）`;
}

function dutyWorkContent(detail) {
  const subject = safeText(detail.subject_name).trim();
  const content = safeText(detail.lesson_content).trim();
  if (subject && content) {
    return `${subject} / ${content}`;
  }
  return subject || content || "";
}

function timeOnly(value) {
  const text = safeText(value);
  return text ? text.slice(0, 5) : "";
}

function numberOrZero(value) {
  const numberValue = Number(value || 0);
  return Number.isFinite(numberValue) ? numberValue : 0;
}

function numberInputValue(value) {
  const numberValue = Number(value || 0);
  return Number.isFinite(numberValue) ? String(numberValue) : "0";
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
