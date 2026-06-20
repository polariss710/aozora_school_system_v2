import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchSettlementDetailPage } from "../api/settlement-detail-api.js";
import {
  relockStudentMonthlySettlement,
  unlockStudentMonthlySettlement,
} from "../api/settlement-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const SETTLEMENT_STATUS_LABELS = {
  locked: "已锁定",
  unlocked: "锁定已撤销",
};

const LESSON_TYPE_LABELS = {
  actual: "实际",
  planned: "预定",
};

const LESSON_STATUS_LABELS = {
  completed: "已完成",
  planned: "待上课",
  cancelled: "已取消",
  pending_makeup: "待补课",
  makeup_completed: "补课完成",
};

const INCOME_STATUS_LABELS = {
  received: "已收款",
};

const INCOME_CATEGORY_LABELS = {
  tuition: "学费",
};

const PAYMENT_METHOD_LABELS = {
  alipay: "支付宝",
  bank: "银行",
  bank_transfer: "银行转账",
  cash: "现金",
  wechat: "微信",
};

const ADJUSTMENT_SOURCE_LABELS = {
  carry_final_balance: "按最终差额结转",
  clear_balance: "抹平差额",
  manual_adjustment: "手动调整",
  manual: "手动调整",
};

const dom = {};
let detailData = null;
let currentStatusAction = "";
let isStatusActionSubmitting = false;

export function initSettlementDetailPage() {
  cacheDom();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    setContentVisible(false);
    return;
  }

  const settlementId = readSettlementId();
  if (!settlementId) {
    showMessage("error", "缺少学生月度结算记录 ID，请从学生月度结算一览进入详情页。");
    setContentVisible(false);
    return;
  }

  loadSettlementDetail(settlementId);
}

function cacheDom() {
  dom.messageArea = document.querySelector("#settlementDetailMessageArea");
  dom.loadingState = document.querySelector("#settlementDetailLoadingState");
  dom.content = document.querySelector("#settlementDetailContent");
  dom.actionStatus = document.querySelector("#settlementDetailActionStatus");
  dom.unlockButton = document.querySelector("#openUnlockSettlementButton");
  dom.relockButton = document.querySelector("#openRelockSettlementButton");
  dom.titleText = document.querySelector("#settlementDetailTitleText");
  dom.basicInfo = document.querySelector("#settlementDetailBasicInfo");
  dom.feeInfo = document.querySelector("#settlementDetailFeeInfo");
  dom.receiptInfo = document.querySelector("#settlementDetailReceiptInfo");
  dom.balanceInfo = document.querySelector("#settlementDetailBalanceInfo");
  dom.studentInfo = document.querySelector("#settlementDetailStudentInfo");
  dom.systemInfo = document.querySelector("#settlementDetailSystemInfo");
  dom.noteBlock = document.querySelector("#settlementDetailNoteBlock");
  dom.adjustmentCount = document.querySelector("#settlementDetailAdjustmentCount");
  dom.adjustmentEmpty = document.querySelector("#settlementDetailAdjustmentEmpty");
  dom.adjustmentRows = document.querySelector("#settlementDetailAdjustmentRows");
  dom.lessonCount = document.querySelector("#settlementDetailLessonCount");
  dom.lessonEmpty = document.querySelector("#settlementDetailLessonEmpty");
  dom.lessonRows = document.querySelector("#settlementDetailLessonRows");
  dom.incomeCount = document.querySelector("#settlementDetailIncomeCount");
  dom.incomeEmpty = document.querySelector("#settlementDetailIncomeEmpty");
  dom.incomeRows = document.querySelector("#settlementDetailIncomeRows");
  dom.statusActionDialog = document.querySelector("#detailSettlementStatusActionDialog");
  dom.statusActionTitle = document.querySelector("#detailSettlementStatusActionTitle");
  dom.statusActionDescription = document.querySelector("#detailSettlementStatusActionDescription");
  dom.statusActionSummary = document.querySelector("#detailSettlementStatusActionSummary");
  dom.statusActionWarning = document.querySelector("#detailSettlementStatusActionWarning");
  dom.statusActionError = document.querySelector("#detailSettlementStatusActionError");
  dom.statusActionReasonField = document.querySelector("#detailSettlementStatusActionReasonField");
  dom.statusActionReasonInput = document.querySelector("#detailSettlementStatusActionReasonInput");
  dom.statusActionNoteField = document.querySelector("#detailSettlementStatusActionNoteField");
  dom.statusActionNoteInput = document.querySelector("#detailSettlementStatusActionNoteInput");
  dom.statusActionConfirmCheckbox = document.querySelector("#detailSettlementStatusActionConfirmCheckbox");
  dom.statusActionSubmitButton = document.querySelector("#detailSettlementStatusActionSubmitButton");
  dom.statusActionCancelButton = document.querySelector("#detailSettlementStatusActionCancelButton");
  bindEvents();
}

function bindEvents() {
  dom.unlockButton?.addEventListener("click", () => openStatusActionDialog("unlock"));
  dom.relockButton?.addEventListener("click", () => openStatusActionDialog("relock"));
  dom.statusActionCancelButton?.addEventListener("click", () => closeStatusActionDialog());
  dom.statusActionSubmitButton?.addEventListener("click", handleStatusActionSubmit);
  dom.statusActionDialog?.addEventListener("click", (event) => {
    if (event.target === dom.statusActionDialog) {
      closeStatusActionDialog();
    }
  });
  dom.statusActionReasonInput?.addEventListener("input", () => {
    clearStatusActionFieldInvalid("reason");
    hideStatusActionErrorIfClean();
  });
  dom.statusActionNoteInput?.addEventListener("input", () => hideStatusActionErrorIfClean());
  dom.statusActionConfirmCheckbox?.addEventListener("change", () => {
    clearStatusActionFieldInvalid("confirm");
    hideStatusActionErrorIfClean();
  });
}

function readSettlementId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || "";
}

async function loadSettlementDetail(settlementId) {
  setLoading(true);
  setContentVisible(false);
  showMessage("info", "正在加载学生月度结算详情...");

  try {
    detailData = await fetchSettlementDetailPage(settlementId);
    renderSettlementDetail(detailData);
    setContentVisible(true);
    showMessage("success", "学生月度结算详情已加载。");
  } catch (error) {
    detailData = null;
    setContentVisible(false);
    showMessage("error", `读取学生月度结算详情失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderSettlementDetail(data) {
  const { settlement } = data;
  const student = studentById(settlement.student_id);

  renderActionControls(settlement);
  dom.titleText.textContent = `${formatMonth(settlement.year_month)} / ${studentNameById(settlement.student_id)} / ${businessNameById(settlement.business_entity_id)}`;
  dom.basicInfo.innerHTML = renderDefinitionList([
    ["结算年月", formatMonth(settlement.year_month)],
    ["学生", studentNameById(settlement.student_id)],
    ["学生编号", displayValue(student?.student_code)],
    ["业务归属", businessNameById(settlement.business_entity_id)],
    ["结算状态", settlementStatusLabel(settlement.settlement_status)],
    ["后续锁定", teacherWageBlockerDisplay(settlement)],
    ["锁定时间", formatDate(settlement.locked_at)],
    ["撤销锁定时间", formatDate(settlement.unlocked_at)],
    ["撤销锁定原因", displayValue(settlement.unlock_reason)],
    ["创建时间", formatDate(settlement.created_at)],
    ["更新时间", formatDate(settlement.updated_at)],
  ]);

  dom.feeInfo.innerHTML = renderDefinitionList([
    ["预定学费 JPY", formatCurrency(settlement.planned_lesson_fee_jpy, "JPY")],
    ["预定学费 CNY", formatCurrency(settlement.planned_lesson_fee_cny, "CNY")],
    ["实际学费 JPY", formatCurrency(settlement.actual_lesson_fee_jpy, "JPY")],
    ["实际学费 CNY", formatCurrency(settlement.actual_lesson_fee_cny, "CNY")],
    ["预设汇率", displayValue(settlement.preset_exchange_rate)],
  ]);

  dom.receiptInfo.innerHTML = renderDefinitionList([
    ["收款 JPY", formatCurrency(settlement.received_jpy, "JPY")],
    ["收款 CNY", formatCurrency(settlement.received_cny, "CNY")],
    ["收款折算 CNY", formatCurrency(settlement.received_equivalent_cny, "CNY")],
  ]);

  dom.balanceInfo.innerHTML = renderDefinitionList([
    ["前期余额 CNY", formatCurrency(settlement.previous_balance_cny, "CNY")],
    ["系统差额 CNY", formatCurrency(settlement.system_difference_cny, "CNY")],
    ["调整金额 CNY", formatCurrency(settlement.adjustment_amount_cny, "CNY")],
    ["调整理由", displayValue(settlement.adjustment_reason)],
    ["本月结转 CNY", formatCurrency(settlement.carryover_amount_cny, "CNY")],
  ]);

  dom.studentInfo.innerHTML = renderDefinitionList([
    ["显示名", studentNameById(settlement.student_id)],
    ["学生状态", displayValue(student?.status)],
    ["课程方向", displayValue(student?.course_track)],
    ["目标类型", displayValue(student?.target_type)],
    ["默认币种", displayValue(student?.default_currency)],
  ]);

  dom.systemInfo.innerHTML = renderDefinitionList([
    ["settlement id", shortId(settlement.id)],
    ["student_id", shortId(settlement.student_id)],
    ["business_entity_id", shortId(settlement.business_entity_id)],
    ["teacher_wage_blocker", teacherWageBlockerDisplay(settlement)],
    ["created_at", formatDate(settlement.created_at)],
    ["updated_at", formatDate(settlement.updated_at)],
  ]);

  dom.noteBlock.textContent = displayValue([settlement.note, settlement.unlock_reason, settlement.adjustment_reason].filter(Boolean).join("\n"));
  renderAdjustmentReferences(data.adjustments || []);
  renderLessonReferences(data.lessons);
  renderIncomeReferences(data.incomes);
}

function renderActionControls(settlement) {
  const status = settlement.settlement_status;
  const blockerReason = teacherWageBlockerReason(settlement);
  dom.actionStatus.textContent = settlementStatusLabel(status);
  dom.actionStatus.className = `status-badge ${statusClass(status)}`;
  dom.unlockButton.classList.toggle("is-hidden", status !== "locked");
  dom.relockButton.classList.toggle("is-hidden", status !== "unlocked");
  dom.unlockButton.disabled = Boolean(blockerReason);
  dom.relockButton.disabled = Boolean(blockerReason);
  dom.unlockButton.title = blockerReason;
  dom.relockButton.title = blockerReason;
  if (blockerReason) {
    dom.actionStatus.textContent = teacherWageBlockerLabel(settlement.teacher_wage_blocker_level);
    dom.actionStatus.className = `status-badge ${teacherWageBlockerClass(settlement.teacher_wage_blocker_level)}`;
  }
}

function renderAdjustmentReferences(rows) {
  dom.adjustmentCount.textContent = `${rows.length} 条`;
  dom.adjustmentEmpty.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.adjustmentRows.innerHTML = "";
    return;
  }

  dom.adjustmentRows.innerHTML = rows.map((row) => `
    <tr>
      <td class="settlement-nowrap">${escapeHtml(formatDate(row.created_at))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.adjustment_amount_cny, "CNY"))}</td>
      <td>${escapeHtml(adjustmentSourceLabel(row.adjustment_source))}</td>
      <td class="settlement-detail-text-cell">${escapeHtml(displayValue(row.adjustment_reason))}</td>
      <td class="settlement-detail-text-cell">${escapeHtml(displayValue(row.note))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(displayValue(row.status))}</span></td>
      <td class="settlement-nowrap">${escapeHtml(shortId(row.id))}</td>
    </tr>
  `).join("");
}

function renderLessonReferences(rows) {
  dom.lessonCount.textContent = `${rows.length} 条`;
  dom.lessonEmpty.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.lessonRows.innerHTML = "";
    return;
  }

  dom.lessonRows.innerHTML = rows.map((row) => `
    <tr>
      <td class="settlement-nowrap">${escapeHtml(formatDateOnly(row.lesson_date))}</td>
      <td class="settlement-nowrap">${escapeHtml(lessonTypeLabel(row.lesson_type))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(lessonStatusLabel(row.status))}</span></td>
      <td>${escapeHtml(teacherNameById(row.teacher_id))}</td>
      <td>${escapeHtml(subjectNameById(row.subject_id))}</td>
      <td class="settlement-nowrap">${escapeHtml(displayValue(row.start_time))}</td>
      <td class="settlement-nowrap">${escapeHtml(displayValue(row.end_time))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(displayValue(row.duration_hours))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(displayValue(row.actual_minutes))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(displayValue(row.lesson_count))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.unit_price, "JPY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.lesson_fee, "JPY"))}</td>
      <td class="settlement-nowrap">${escapeHtml(booleanLabel(row.is_billable))}</td>
      <td class="settlement-nowrap">${escapeHtml(shortId(row.planned_lesson_id))}</td>
      <td class="settlement-detail-text-cell"><span class="table-cell-summary">${escapeHtml(displayValue(row.lesson_content))}</span></td>
    </tr>
  `).join("");
}

function renderIncomeReferences(rows) {
  dom.incomeCount.textContent = `${rows.length} 条`;
  dom.incomeEmpty.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.incomeRows.innerHTML = "";
    return;
  }

  dom.incomeRows.innerHTML = rows.map((row) => `
    <tr>
      <td class="settlement-nowrap">${escapeHtml(formatDateOnly(row.income_date))}</td>
      <td class="settlement-nowrap">${escapeHtml(incomeCategoryLabel(row.income_category))}</td>
      <td class="settlement-detail-text-cell"><span class="table-cell-summary">${escapeHtml(displayValue(row.description))}</span></td>
      <td class="settlement-nowrap">${escapeHtml(displayValue(row.currency))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.amount_jpy, "JPY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.amount_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(displayValue(row.exchange_rate))}</td>
      <td class="settlement-nowrap">${escapeHtml(displayValue(row.payment_currency))}</td>
      <td class="settlement-nowrap">${escapeHtml(paymentMethodLabel(row.payment_method))}</td>
      <td>${escapeHtml(accountNameById(row.account_id))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(incomeStatusLabel(row.status))}</span></td>
      <td class="settlement-nowrap">${escapeHtml(displayValue(row.receipt_status))}</td>
      <td class="settlement-nowrap">${escapeHtml(booleanLabel(row.include_in_student_settlement))}</td>
      <td class="settlement-detail-text-cell"><span class="table-cell-summary">${escapeHtml(displayValue(row.note))}</span></td>
    </tr>
  `).join("");
}

function openStatusActionDialog(action) {
  if (!detailData?.settlement) {
    showMessage("error", "未找到可变更状态的结算快照。");
    return;
  }

  const settlement = detailData.settlement;
  if (action === "unlock" && settlement.settlement_status !== "locked") {
    showMessage("error", "只有已锁定的结算可以撤销锁定。");
    return;
  }

  if (action === "relock" && settlement.settlement_status !== "unlocked") {
    showMessage("error", "只有锁定已撤销的结算可以重新锁定。");
    return;
  }

  const blockerReason = teacherWageBlockerReason(settlement);
  if (blockerReason) {
    showMessage("error", blockerReason);
    return;
  }

  currentStatusAction = action;
  dom.statusActionReasonInput.value = "";
  dom.statusActionNoteInput.value = "";
  dom.statusActionConfirmCheckbox.checked = false;
  clearStatusActionErrors();
  renderStatusActionDialog(settlement, action);
  setStatusActionSubmitting(false);
  dom.statusActionDialog.classList.remove("is-hidden");
  dom.statusActionDialog.setAttribute("aria-hidden", "false");
  if (action === "unlock") {
    dom.statusActionReasonInput.focus();
  } else {
    dom.statusActionConfirmCheckbox.focus();
  }
}

function closeStatusActionDialog(force = false) {
  if (isStatusActionSubmitting && !force) {
    return;
  }

  dom.statusActionDialog?.classList.add("is-hidden");
  dom.statusActionDialog?.setAttribute("aria-hidden", "true");
  currentStatusAction = "";
  clearStatusActionErrors();
}

function renderStatusActionDialog(settlement, action) {
  const isUnlock = action === "unlock";
  dom.statusActionTitle.textContent = isUnlock ? "撤销锁定学生月度结算" : "重新锁定学生月度结算";
  dom.statusActionDescription.textContent = isUnlock
    ? "撤销锁定会把当前快照状态改为锁定已撤销，保留同一条结算记录和撤销原因。"
    : "重新锁定会复用当前实时结算口径覆盖同一条快照金额，不创建历史版本。";
  dom.statusActionWarning.textContent = isUnlock
    ? "撤销锁定后，该学生该月份的课时和学费收入写入 guard 会放开；如果该结算已作为有效结转来源或已进入老师工资链路，RPC 会拒绝本操作。"
    : "重新锁定后，该学生该月份的课时和学费收入写入 guard 会恢复；如果该结算已进入老师工资链路，RPC 会拒绝本操作。";
  dom.statusActionReasonField.classList.toggle("is-hidden", !isUnlock);
  dom.statusActionNoteField.classList.toggle("is-hidden", isUnlock);
  dom.statusActionSubmitButton.classList.toggle("button-danger", isUnlock);
  dom.statusActionSubmitButton.classList.toggle("button-primary", !isUnlock);
  dom.statusActionSubmitButton.textContent = isUnlock ? "确认撤销锁定" : "确认重新锁定";
  renderStatusActionSummary(settlement);
}

function renderStatusActionSummary(settlement) {
  dom.statusActionSummary.innerHTML = [
    ["学生", studentNameById(settlement.student_id)],
    ["结算月份", formatMonth(settlement.year_month)],
    ["业务归属", businessNameById(settlement.business_entity_id)],
    ["当前状态", settlementStatusLabel(settlement.settlement_status)],
    ["后续锁定", teacherWageBlockerDisplay(settlement)],
    ["锁定时间", formatDate(settlement.locked_at)],
    ["撤销时间", formatDate(settlement.unlocked_at)],
    ["系统差额", formatCurrency(settlement.system_difference_cny, "CNY")],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");
}

async function handleStatusActionSubmit() {
  if (isStatusActionSubmitting) {
    return;
  }

  clearStatusActionErrors();

  const settlement = detailData?.settlement;
  if (!settlement || !currentStatusAction) {
    showStatusActionError("未找到可变更状态的结算快照。");
    return;
  }

  if (currentStatusAction === "unlock") {
    const reason = dom.statusActionReasonInput.value.trim();
    if (!reason) {
      setStatusActionFieldInvalid("reason", true);
      showStatusActionError("请填写撤销锁定原因。");
      return;
    }
  }

  if (!dom.statusActionConfirmCheckbox.checked) {
    setStatusActionFieldInvalid("confirm", true);
    showStatusActionError("请先勾选确认后再继续。");
    return;
  }

  setStatusActionSubmitting(true);

  try {
    const action = currentStatusAction;
    const result = action === "unlock"
      ? await unlockStudentMonthlySettlement({
        settlementId: settlement.id,
        reason: dom.statusActionReasonInput.value.trim(),
      })
      : await relockStudentMonthlySettlement({
        settlementId: settlement.id,
        note: dom.statusActionNoteInput.value.trim(),
      });
    closeStatusActionDialog(true);
    await loadSettlementDetail(settlement.id);
    showMessage("success", action === "unlock"
      ? `学生月度结算锁定已撤销：${shortId(result?.settlement_id || result?.id)}。`
      : `学生月度结算已重新锁定：${shortId(result?.settlement_id || result?.id)}。`);
  } catch (error) {
    showStatusActionError(error.message || String(error));
  } finally {
    setStatusActionSubmitting(false);
  }
}

function setStatusActionSubmitting(isSubmitting) {
  isStatusActionSubmitting = isSubmitting;
  if (dom.statusActionSubmitButton) {
    dom.statusActionSubmitButton.disabled = isSubmitting;
    if (isSubmitting) {
      dom.statusActionSubmitButton.textContent = currentStatusAction === "unlock"
        ? "撤销中..."
        : "重新锁定中...";
    } else {
      dom.statusActionSubmitButton.textContent = currentStatusAction === "unlock"
        ? "确认撤销锁定"
        : "确认重新锁定";
    }
  }
  if (dom.statusActionCancelButton) {
    dom.statusActionCancelButton.disabled = isSubmitting;
  }
}

function showStatusActionError(message) {
  dom.statusActionError.textContent = message;
  dom.statusActionError.classList.remove("is-hidden");
}

function clearStatusActionErrors() {
  dom.statusActionError.textContent = "";
  dom.statusActionError.classList.add("is-hidden");
  clearStatusActionFieldInvalid("reason");
  clearStatusActionFieldInvalid("confirm");
}

function hideStatusActionErrorIfClean() {
  if (!dom.statusActionDialog?.querySelector(".field.is-invalid")) {
    dom.statusActionError.textContent = "";
    dom.statusActionError.classList.add("is-hidden");
  }
}

function setStatusActionFieldInvalid(fieldId, invalid) {
  const field = dom.statusActionDialog?.querySelector(`[data-detail-settlement-status-action-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearStatusActionFieldInvalid(fieldId) {
  setStatusActionFieldInvalid(fieldId, false);
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

function studentById(id) {
  return detailData?.lookups.students.find((item) => item.id === id);
}

function studentNameById(id) {
  const student = studentById(id);
  if (!student) {
    return id ? "未知" : "未设置";
  }

  return safeText(student.display_name || student.name) || "未设置";
}

function businessNameById(id) {
  const entity = detailData?.lookups.businessEntities.find((item) => item.id === id);
  if (!entity) {
    return id ? "未知" : "未设置";
  }

  const code = safeText(entity.code);
  const name = safeText(entity.name) || "未设置";
  return code ? `${name} / ${code}` : name;
}

function teacherNameById(id) {
  const teacher = detailData?.lookups.teachers.find((item) => item.id === id);
  if (!teacher) {
    return id ? "未知" : "未设置";
  }

  return safeText(teacher.display_name || teacher.name) || "未设置";
}

function subjectNameById(id) {
  const subject = detailData?.lookups.subjects.find((item) => item.id === id);
  if (!subject) {
    return id ? "未知" : "未设置";
  }

  return safeText(subject.name) || "未设置";
}

function accountNameById(id) {
  const account = detailData?.lookups.accounts.find((item) => item.id === id);
  if (!account) {
    return id ? "未知" : "未设置";
  }

  const name = safeText(account.name) || "未设置";
  const currency = safeText(account.currency);
  return currency ? `${name} / ${currency}` : name;
}

function settlementStatusLabel(value) {
  return SETTLEMENT_STATUS_LABELS[value] || displayValue(value);
}

function teacherWageBlockerReason(settlement) {
  return safeText(settlement?.teacher_wage_blocker_reason);
}

function teacherWageBlockerDisplay(settlement) {
  return teacherWageBlockerReason(settlement) || "未进入老师工资链路";
}

function teacherWageBlockerLabel(value) {
  if (value === "payment_completed") {
    return "老师工资已支付";
  }
  if (value === "payment_requested") {
    return "已生成工资支付请求";
  }
  if (value === "wage_snapshot") {
    return "已生成老师工资";
  }
  return "未进入工资链路";
}

function lessonTypeLabel(value) {
  return LESSON_TYPE_LABELS[value] || displayValue(value);
}

function lessonStatusLabel(value) {
  return LESSON_STATUS_LABELS[value] || displayValue(value);
}

function incomeStatusLabel(value) {
  return INCOME_STATUS_LABELS[value] || displayValue(value);
}

function incomeCategoryLabel(value) {
  return INCOME_CATEGORY_LABELS[value] || displayValue(value);
}

function paymentMethodLabel(value) {
  return PAYMENT_METHOD_LABELS[value] || displayValue(value);
}

function adjustmentSourceLabel(value) {
  const source = safeText(value).trim();
  return ADJUSTMENT_SOURCE_LABELS[source] || displayValue(source);
}

function statusClass(value) {
  if (value === "locked" || value === "received" || value === "completed" || value === "makeup_completed") {
    return "status-paid";
  }

  if (value === "unlocked") {
    return "status-cancelled";
  }

  if (value === "planned" || value === "pending_makeup") {
    return "status-pending";
  }

  if (value === "cancelled") {
    return "status-cancelled";
  }

  return "status-neutral";
}

function teacherWageBlockerClass(value) {
  if (value === "payment_completed" || value === "payment_requested") {
    return "status-paid";
  }
  if (value === "wage_snapshot") {
    return "status-pending";
  }
  return "status-neutral";
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

function formatDateOnly(value) {
  return safeText(value) || "-";
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
