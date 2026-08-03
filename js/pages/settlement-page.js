import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchSettlementBusinessEntities,
  fetchSettlementStudents,
  fetchStudentSettlements,
  lockStudentMonthlySettlement,
  relockStudentMonthlySettlement,
  setStudentMonthlySettlementDraftAdjustment,
  unlockStudentMonthlySettlement,
} from "../api/settlement-api.js?v=p0e-20260803-1";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";
import { hasFrozenSettlementOverage } from "../utils/actual-overage.js";

const DEFAULT_FILTERS = {
  studentId: "",
  businessEntityId: "",
  status: "",
  keyword: "",
};

const SETTLEMENT_STATUS_LABELS = {
  locked: "已锁定",
  unlocked: "锁定已撤销",
  preview: "未锁定 / 预览",
  historically_consumed_immutable: "已被历史学费账单消费（不可重开）",
};

const ADJUSTMENT_MODES = {
  CARRY_FINAL_BALANCE: "carry_final_balance",
  CLEAR_BALANCE: "clear_balance",
  MANUAL_ADJUSTMENT: "manual_adjustment",
};

const dom = {};
let students = [];
let businessEntities = [];
let settlements = [];
let loadedMonth = "";
let currentLockSettlement = null;
let isLockSubmitting = false;
let currentStatusActionSettlement = null;
let currentStatusAction = "";
let isStatusActionSubmitting = false;
let currentAdjustmentSettlement = null;
let isAdjustmentSubmitting = false;

export function initSettlementPage() {
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
    renderSettlements([]);
    return;
  }

  loadInitialData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#settlementMessageArea");
  dom.filterForm = document.querySelector("#settlementFilterForm");
  dom.yearFilter = document.querySelector("#settlementYearFilter");
  dom.monthFilter = document.querySelector("#settlementMonthFilter");
  dom.studentSelect = document.querySelector("#settlementStudentSelect");
  dom.businessEntitySelect = document.querySelector("#settlementBusinessEntitySelect");
  dom.statusSelect = document.querySelector("#settlementStatusSelect");
  dom.keywordInput = document.querySelector("#settlementKeywordInput");
  dom.resetButton = document.querySelector("#settlementResetButton");
  dom.tableBody = document.querySelector("#settlementTableBody");
  dom.loadingState = document.querySelector("#settlementLoadingState");
  dom.emptyState = document.querySelector("#settlementEmptyState");
  dom.settlementCount = document.querySelector("#settlementCount");
  dom.lockDialog = document.querySelector("#lockSettlementDialog");
  dom.lockSummary = document.querySelector("#lockSettlementSummary");
  dom.lockError = document.querySelector("#lockSettlementError");
  dom.lockNoteInput = document.querySelector("#lockSettlementNoteInput");
  dom.lockConfirmCheckbox = document.querySelector("#lockSettlementConfirmCheckbox");
  dom.lockSubmitButton = document.querySelector("#lockSettlementSubmitButton");
  dom.lockCancelButton = document.querySelector("#lockSettlementCancelButton");
  dom.statusActionDialog = document.querySelector("#settlementStatusActionDialog");
  dom.statusActionTitle = document.querySelector("#settlementStatusActionTitle");
  dom.statusActionDescription = document.querySelector("#settlementStatusActionDescription");
  dom.statusActionSummary = document.querySelector("#settlementStatusActionSummary");
  dom.statusActionWarning = document.querySelector("#settlementStatusActionWarning");
  dom.statusActionError = document.querySelector("#settlementStatusActionError");
  dom.statusActionReasonField = document.querySelector("#settlementStatusActionReasonField");
  dom.statusActionReasonInput = document.querySelector("#settlementStatusActionReasonInput");
  dom.statusActionNoteField = document.querySelector("#settlementStatusActionNoteField");
  dom.statusActionNoteInput = document.querySelector("#settlementStatusActionNoteInput");
  dom.statusActionConfirmCheckbox = document.querySelector("#settlementStatusActionConfirmCheckbox");
  dom.statusActionSubmitButton = document.querySelector("#settlementStatusActionSubmitButton");
  dom.statusActionCancelButton = document.querySelector("#settlementStatusActionCancelButton");
  dom.adjustmentDialog = document.querySelector("#settlementAdjustmentDialog");
  dom.adjustmentSummary = document.querySelector("#settlementAdjustmentSummary");
  dom.adjustmentError = document.querySelector("#settlementAdjustmentError");
  dom.adjustmentAmountInput = document.querySelector("#settlementAdjustmentAmountInput");
  dom.adjustmentSourceInput = document.querySelector("#settlementAdjustmentSourceInput");
  dom.adjustmentReasonInput = document.querySelector("#settlementAdjustmentReasonInput");
  dom.adjustmentNoteInput = document.querySelector("#settlementAdjustmentNoteInput");
  dom.adjustmentConfirmCheckbox = document.querySelector("#settlementAdjustmentConfirmCheckbox");
  dom.adjustmentSubmitButton = document.querySelector("#settlementAdjustmentSubmitButton");
  dom.adjustmentCancelButton = document.querySelector("#settlementAdjustmentCancelButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    applyQuery();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    applyQuery();
  });

  dom.tableBody.addEventListener("click", (event) => {
    const lockButton = event.target.closest("[data-lock-settlement-id]");
    if (lockButton) {
      openLockDialog(lockButton.dataset.lockSettlementId);
      return;
    }

    const actionButton = event.target.closest("[data-settlement-action-id]");
    if (actionButton) {
      openStatusActionDialog(
        actionButton.dataset.settlementActionId,
        actionButton.dataset.settlementAction
      );
      return;
    }

    const adjustmentButton = event.target.closest("[data-settlement-adjustment-id]");
    if (adjustmentButton) {
      openAdjustmentDialog(adjustmentButton.dataset.settlementAdjustmentId);
    }
  });

  dom.lockCancelButton?.addEventListener("click", () => closeLockDialog());
  dom.lockSubmitButton?.addEventListener("click", handleLockSubmit);
  dom.lockDialog?.addEventListener("click", (event) => {
    if (event.target === dom.lockDialog) {
      closeLockDialog();
    }
  });
  dom.lockNoteInput?.addEventListener("input", () => hideLockErrorIfClean());
  dom.lockConfirmCheckbox?.addEventListener("change", () => {
    clearLockFieldInvalid("confirm");
    hideLockErrorIfClean();
  });

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

  dom.adjustmentCancelButton?.addEventListener("click", () => closeAdjustmentDialog());
  dom.adjustmentSubmitButton?.addEventListener("click", handleAdjustmentSubmit);
  [
    ["amount", dom.adjustmentAmountInput],
    ["reason", dom.adjustmentReasonInput],
    ["note", dom.adjustmentNoteInput],
  ].forEach(([fieldId, element]) => {
    element?.addEventListener("input", () => {
      clearAdjustmentFieldInvalid(fieldId);
      if (fieldId === "amount") {
        renderAdjustmentSummary(currentAdjustmentSettlement);
      }
      hideAdjustmentErrorIfClean();
    });
  });
  dom.adjustmentSourceInput?.addEventListener("change", () => {
    clearAdjustmentFieldInvalid("source");
    applyAdjustmentMode();
    hideAdjustmentErrorIfClean();
  });
  dom.adjustmentConfirmCheckbox?.addEventListener("change", () => {
    clearAdjustmentFieldInvalid("confirm");
    hideAdjustmentErrorIfClean();
  });
}

function setDefaultFilters() {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  dom.studentSelect.value = DEFAULT_FILTERS.studentId;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载学生月度结算数据...");

  try {
    [students, businessEntities] = await Promise.all([
      fetchSettlementStudents(),
      fetchSettlementBusinessEntities(),
    ]);

    renderMasterOptions();
    await loadSettlementMonth(currentYearMonth());
    applyCurrentFilters();
    showMessage("success", "学生月度结算数据已加载。");
  } catch (error) {
    students = [];
    businessEntities = [];
    settlements = [];
    loadedMonth = "";
    renderMasterOptions();
    renderStatusOptions([]);
    renderSettlements([]);
    showMessage("error", `读取学生月度结算数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

async function applyQuery() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  if (!filters) {
    return;
  }

  if (filters.month !== loadedMonth) {
    setLoading(true);
    showMessage("info", "正在加载学生月度结算记录...");

    try {
      await loadSettlementMonth(filters.month);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "学生月度结算记录已加载。");
    } catch (error) {
      settlements = [];
      loadedMonth = "";
      renderStatusOptions([]);
      renderSettlements([]);
      showMessage("error", `读取学生月度结算记录失败：${error.message || error}`);
    } finally {
      setLoading(false);
    }
    return;
  }

  applyCurrentFilters();
}

async function loadSettlementMonth(month) {
  settlements = sortSettlements(await fetchStudentSettlements(month));
  loadedMonth = month;
  renderStatusOptions(settlements);
}

function applyCurrentFilters() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  renderWithFilters(filters);
}

function renderWithFilters(filters) {
  const safeFilters = {
    month: filters?.month || loadedMonth || currentYearMonth(),
    ...DEFAULT_FILTERS,
    ...(filters || {}),
  };
  restoreFilterSelections(safeFilters);
  renderSettlements(filterSettlements(settlements, safeFilters));
}

function readFilters() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    showMessage("error", "请选择正确的年月。");
    return null;
  }

  return {
    month,
    studentId: dom.studentSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    status: dom.statusSelect.value,
    keyword: dom.keywordInput.value.trim(),
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.studentSelect.value = filters.studentId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.statusSelect.value = filters.status;
  dom.keywordInput.value = filters.keyword;
}

function renderMasterOptions() {
  renderEntityOptions(dom.studentSelect, students, studentName);
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
}

function renderStatusOptions(rows) {
  const options = ['<option value="">全部</option>'];

  for (const value of [...new Set(rows.map((row) => effectiveSettlementStatus(row)))].sort()) {
    options.push(
      `<option value="${escapeAttribute(value)}">${escapeHtml(settlementStatusLabel(value))}</option>`
    );
  }

  dom.statusSelect.innerHTML = options.join("");
}

function renderEntityOptions(selectEl, rows, labelGetter) {
  const options = ['<option value="">全部</option>'];

  for (const row of rows) {
    options.push(
      `<option value="${escapeAttribute(row.id)}">${escapeHtml(labelGetter(row))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function renderSettlements(rows) {
  dom.settlementCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td class="settlement-nowrap settlement-action-cell">${renderSettlementDetailAction(row)}</td>
      <td class="settlement-nowrap">${escapeHtml(formatMonth(row.year_month))}</td>
      <td>${escapeHtml(nameById(students, row.student_id, studentName))}</td>
      <td>${escapeHtml(nameById(businessEntities, row.business_entity_id, businessEntityName))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(effectiveSettlementStatus(row)))}" title="${escapeAttribute(row.immutable_reason || "")}">${escapeHtml(settlementStatusLabel(effectiveSettlementStatus(row)))}</span></td>
      <td>${renderTeacherWageBlocker(row)}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.previous_balance_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.planned_lesson_fee_jpy, "JPY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.planned_lesson_fee_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.actual_lesson_fee_jpy, "JPY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.actual_lesson_fee_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.received_jpy, "JPY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.received_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.system_difference_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.carryover_amount_cny, "CNY"))}</td>
      <td class="settlement-nowrap">${escapeHtml(formatDate(row.locked_at))}</td>
    </tr>
  `).join("");
}

function renderSettlementDetailAction(row) {
  const blockerReason = teacherWageBlockerReason(row);

  if (row.is_preview) {
    if (blockerReason) {
      return `
        <div class="table-action-group">
          <span class="status-badge status-pending">预览</span>
          <button class="button table-action-button" type="button" disabled title="${escapeAttribute(blockerReason)}">不可调整</button>
          <button class="button table-action-button" type="button" disabled title="${escapeAttribute(blockerReason)}">不可锁定</button>
        </div>
      `;
    }

    return `
      <div class="table-action-group">
        <span class="status-badge status-pending">预览</span>
        <button class="button table-action-button" type="button" data-settlement-adjustment-id="${escapeAttribute(row.id)}">差额调整</button>
        <button class="button table-action-button button-primary" type="button" data-lock-settlement-id="${escapeAttribute(row.id)}">锁定</button>
      </div>
    `;
  }

  const actionButton = renderSettlementStatusAction(row);
  return `
    <div class="table-action-group">
      <a class="button table-action-button" href="./settlement-detail.html?id=${encodeURIComponent(row.id)}">详情</a>
      ${actionButton}
    </div>
  `;
}

function renderSettlementStatusAction(row) {
  const blockerReason = teacherWageBlockerReason(row);

  if (row.editable === false || effectiveSettlementStatus(row) === "historically_consumed_immutable") {
    return `<span class="table-cell-summary" title="${escapeAttribute(row.immutable_reason || row.display_label || "不可修改")}">只读</span>`;
  }

  if (row.settlement_status === "locked") {
    if (blockerReason) {
      return `
        <button
          class="button table-action-button"
          type="button"
          disabled
          title="${escapeAttribute(blockerReason)}"
        >不可撤销</button>
      `;
    }

    return `
      <button
        class="button table-action-button button-danger"
        type="button"
        data-settlement-action-id="${escapeAttribute(row.id)}"
        data-settlement-action="unlock"
      >撤销锁定</button>
    `;
  }

  if (row.settlement_status === "unlocked") {
    if (blockerReason) {
      return `
        <button class="button table-action-button" type="button" disabled title="${escapeAttribute(blockerReason)}">不可调整</button>
        <button class="button table-action-button" type="button" disabled title="${escapeAttribute(blockerReason)}">不可重新锁定</button>
      `;
    }

    return `
      <button
        class="button table-action-button"
        type="button"
        data-settlement-adjustment-id="${escapeAttribute(row.id)}"
      >差额调整</button>
      <button
        class="button table-action-button button-primary"
        type="button"
        data-settlement-action-id="${escapeAttribute(row.id)}"
        data-settlement-action="relock"
      >重新锁定</button>
    `;
  }

  return "";
}

function renderTeacherWageBlocker(row) {
  const reason = teacherWageBlockerReason(row);
  if (!reason) {
    return '<span class="status-badge status-neutral">未进入工资链路</span>';
  }

  return `
    <div class="settlement-note-cell">
      <span class="status-badge ${escapeAttribute(teacherWageBlockerClass(row.teacher_wage_blocker_level))}">${escapeHtml(teacherWageBlockerLabel(row.teacher_wage_blocker_level))}</span>
      <div class="table-cell-summary">${escapeHtml(reason)}</div>
    </div>
  `;
}

function teacherWageBlockerReason(row) {
  return safeText(row?.teacher_wage_blocker_reason);
}

function openLockDialog(settlementRowId) {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能锁定学生月度结算。");
    return;
  }

  const row = settlements.find((item) => item.id === settlementRowId);
  if (!row || !row.is_preview) {
    showMessage("error", "未找到可锁定的实时预览记录。");
    return;
  }

  currentLockSettlement = row;
  dom.lockNoteInput.value = "";
  dom.lockConfirmCheckbox.checked = false;
  clearLockErrors();
  renderLockSummary(row);
  setLockSubmitting(false);
  dom.lockDialog.classList.remove("is-hidden");
  dom.lockDialog.setAttribute("aria-hidden", "false");
  dom.lockConfirmCheckbox.focus();
}

function closeLockDialog(force = false) {
  if (isLockSubmitting && !force) {
    return;
  }

  dom.lockDialog?.classList.add("is-hidden");
  dom.lockDialog?.setAttribute("aria-hidden", "true");
  currentLockSettlement = null;
  clearLockErrors();
}

function renderLockSummary(row) {
  const rows = [
    ["学生", nameById(students, row.student_id, studentName)],
    ["学生结算月（后端权威）", formatMonth(row.year_month)],
    ["业务归属", nameById(businessEntities, row.business_entity_id, businessEntityName)],
    ["预定课时费", formatCurrency(row.planned_lesson_fee_jpy, "JPY")],
    ["实际课时费", formatCurrency(row.actual_lesson_fee_jpy, "JPY")],
    ["系统差额（含后端冻结超额）", formatCurrency(row.system_difference_cny, "CNY")],
    ["差额调整", formatCurrency(row.adjustment_amount_cny, "CNY")],
    ["锁定后结转", formatCurrency(row.carryover_amount_cny, "CNY")],
  ];
  dom.lockSummary.innerHTML = rows.map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");
}

async function handleLockSubmit() {
  if (isLockSubmitting) {
    return;
  }

  clearLockErrors();

  if (!currentLockSettlement) {
    showLockError("未找到可锁定的实时预览记录。");
    return;
  }

  if (!dom.lockConfirmCheckbox.checked) {
    setLockFieldInvalid("confirm", true);
    showLockError("请先勾选确认后再锁定。");
    return;
  }

  setLockSubmitting(true);

  try {
    const sourceRow = currentLockSettlement;
    const filtersBeforeSubmit = readFilters();
    const result = await lockStudentMonthlySettlement({
      studentId: sourceRow.student_id,
      yearMonth: sourceRow.year_month,
      note: dom.lockNoteInput.value.trim(),
    });
    closeLockDialog(true);
    await loadSettlementMonth(sourceRow.year_month);
    renderWithFilters({
      ...(filtersBeforeSubmit || {}),
      month: sourceRow.year_month,
    });
    showMessage("success", `学生月度结算已锁定：${shortId(result?.settlement_id || result?.id)}。`);
  } catch (error) {
    showLockError(error.message || String(error));
  } finally {
    setLockSubmitting(false);
  }
}

function setLockSubmitting(isSubmitting) {
  isLockSubmitting = isSubmitting;
  if (dom.lockSubmitButton) {
    dom.lockSubmitButton.disabled = isSubmitting;
    dom.lockSubmitButton.textContent = isSubmitting ? "锁定中..." : "确认锁定";
  }
  if (dom.lockCancelButton) {
    dom.lockCancelButton.disabled = isSubmitting;
  }
}

function showLockError(message) {
  dom.lockError.textContent = message;
  dom.lockError.classList.remove("is-hidden");
}

function clearLockErrors() {
  dom.lockError.textContent = "";
  dom.lockError.classList.add("is-hidden");
  clearLockFieldInvalid("confirm");
}

function hideLockErrorIfClean() {
  if (!dom.lockDialog?.querySelector(".field.is-invalid")) {
    dom.lockError.textContent = "";
    dom.lockError.classList.add("is-hidden");
  }
}

function setLockFieldInvalid(fieldId, invalid) {
  const field = dom.lockDialog?.querySelector(`[data-lock-settlement-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearLockFieldInvalid(fieldId) {
  setLockFieldInvalid(fieldId, false);
}

function openStatusActionDialog(settlementId, action) {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能变更学生月度结算状态。");
    return;
  }

  const row = settlements.find((item) => item.id === settlementId);
  if (!row || row.is_preview) {
    showMessage("error", "未找到可变更状态的结算快照。");
    return;
  }

  const blockerReason = teacherWageBlockerReason(row);
  if (blockerReason) {
    showMessage("error", blockerReason);
    return;
  }

  if (!["unlock", "relock"].includes(action)) {
    showMessage("error", "结算状态操作无效。");
    return;
  }

  if (action === "unlock" && row.settlement_status !== "locked") {
    showMessage("error", "只有已锁定的结算可以撤销锁定。");
    return;
  }

  if (action === "relock" && row.settlement_status !== "unlocked") {
    showMessage("error", "只有锁定已撤销的结算可以重新锁定。");
    return;
  }

  currentStatusActionSettlement = row;
  currentStatusAction = action;
  dom.statusActionReasonInput.value = "";
  dom.statusActionNoteInput.value = "";
  dom.statusActionConfirmCheckbox.checked = false;
  clearStatusActionErrors();
  renderStatusActionDialog(row, action);
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
  currentStatusActionSettlement = null;
  currentStatusAction = "";
  clearStatusActionErrors();
}

function renderStatusActionDialog(row, action) {
  const isUnlock = action === "unlock";
  dom.statusActionTitle.textContent = isUnlock ? "撤销锁定学生月度结算" : "重新锁定学生月度结算";
  dom.statusActionDescription.textContent = isUnlock
    ? "撤销锁定会把当前快照状态改为锁定已撤销，保留同一条结算记录和撤销原因。"
    : "重新锁定会复用当前实时结算口径和锁定前差额调整覆盖同一条快照金额，不创建历史版本。";
  dom.statusActionWarning.textContent = isUnlock
    ? "撤销锁定后，该学生该月份的课时和学费收入写入 guard 会放开；如果该结算已作为有效结转来源，RPC 会拒绝本操作。"
    : "重新锁定后，该学生该月份的课时和学费收入写入 guard 会恢复；差额调整会随本次重新锁定固化为只读快照。";
  dom.statusActionReasonField.classList.toggle("is-hidden", !isUnlock);
  dom.statusActionNoteField.classList.toggle("is-hidden", isUnlock);
  dom.statusActionSubmitButton.classList.toggle("button-danger", isUnlock);
  dom.statusActionSubmitButton.classList.toggle("button-primary", !isUnlock);
  dom.statusActionSubmitButton.textContent = isUnlock ? "确认撤销锁定" : "确认重新锁定";
  renderStatusActionSummary(row);
}

function renderStatusActionSummary(row) {
  const rows = [
    ["学生", nameById(students, row.student_id, studentName)],
    ["学生结算月（后端权威）", formatMonth(row.year_month)],
    ["业务归属", nameById(businessEntities, row.business_entity_id, businessEntityName)],
    ["当前状态", settlementStatusLabel(row.settlement_status)],
    ["锁定时间", formatDate(row.locked_at)],
    ["撤销时间", formatDate(row.unlocked_at)],
    ["系统差额（含后端冻结超额）", formatCurrency(row.system_difference_cny, "CNY")],
    ["差额调整", formatCurrency(row.adjustment_amount_cny, "CNY")],
    ["锁定后结转", formatCurrency(row.carryover_amount_cny, "CNY")],
  ];
  if (hasFrozenSettlementOverage(row)) {
    rows.push(
      ["冻结超出时长", `${displayValue(row.duration_overage_minutes)} 分钟`],
      ["冻结超额金额 JPY", formatCurrency(row.duration_overage_fee_jpy, "JPY")],
      ["冻结超额金额 CNY", formatCurrency(row.duration_overage_fee_cny, "CNY")]
    );
  }
  dom.statusActionSummary.innerHTML = rows.map(([label, value]) => `
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

  if (!currentStatusActionSettlement || !currentStatusAction) {
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
    const sourceRow = currentStatusActionSettlement;
    const action = currentStatusAction;
    const filtersBeforeSubmit = readFilters();
    const result = action === "unlock"
      ? await unlockStudentMonthlySettlement({
        settlementId: sourceRow.id,
        reason: dom.statusActionReasonInput.value.trim(),
      })
      : await relockStudentMonthlySettlement({
        settlementId: sourceRow.id,
        note: dom.statusActionNoteInput.value.trim(),
      });
    closeStatusActionDialog(true);
    await loadSettlementMonth(sourceRow.year_month);
    renderWithFilters({
      ...(filtersBeforeSubmit || {}),
      month: sourceRow.year_month,
    });
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
  const field = dom.statusActionDialog?.querySelector(`[data-settlement-status-action-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearStatusActionFieldInvalid(fieldId) {
  setStatusActionFieldInvalid(fieldId, false);
}

function openAdjustmentDialog(settlementId) {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能保存差额调整。");
    return;
  }

  const row = settlements.find((item) => item.id === settlementId);
  if (!row) {
    showMessage("error", "未找到可调整的结算预览。");
    return;
  }

  if (row.editable === false) {
    showMessage("error", row.immutable_reason || row.display_label || "该结算为不可变历史事实，不能调整。");
    return;
  }

  const blockerReason = teacherWageBlockerReason(row);
  if (blockerReason) {
    showMessage("error", blockerReason);
    return;
  }

  if (!row.is_preview && row.settlement_status !== "unlocked") {
    showMessage("error", "差额调整只能在锁定前录入或修改；已锁定结算只能只读查看。");
    return;
  }

  currentAdjustmentSettlement = row;
  dom.adjustmentAmountInput.value = Number.isFinite(Number(row.adjustment_amount_cny))
    ? formatCnyInput(row.adjustment_amount_cny)
    : "";
  dom.adjustmentSourceInput.value = adjustmentModeForRow(row);
  dom.adjustmentReasonInput.value = row.adjustment_reason || "";
  dom.adjustmentNoteInput.value = row.adjustment_note || "";
  dom.adjustmentConfirmCheckbox.checked = false;
  clearAdjustmentErrors();
  applyAdjustmentMode({ preserveManualAmount: true });
  setAdjustmentSubmitting(false);
  dom.adjustmentDialog.classList.remove("is-hidden");
  dom.adjustmentDialog.setAttribute("aria-hidden", "false");
  dom.adjustmentSourceInput.focus();
}

function closeAdjustmentDialog(force = false) {
  if (isAdjustmentSubmitting && !force) {
    return;
  }

  dom.adjustmentDialog?.classList.add("is-hidden");
  dom.adjustmentDialog?.setAttribute("aria-hidden", "true");
  currentAdjustmentSettlement = null;
  clearAdjustmentErrors();
}

function renderAdjustmentSummary(row) {
  if (!row) {
    dom.adjustmentSummary.innerHTML = "";
    return;
  }

  const mode = dom.adjustmentSourceInput.value || adjustmentModeForRow(row);
  const isSavedMode = row.adjustment_source === mode;
  const authoritativeAdjustment = isSavedMode
    ? formatCurrency(row.adjustment_amount_cny, "CNY")
    : "保存后由数据库计算";
  const authoritativeCarryover = isSavedMode
    ? formatCurrency(row.carryover_amount_cny, "CNY")
    : "保存后由数据库计算";
  dom.adjustmentSummary.innerHTML = [
    ["学生", nameById(students, row.student_id, studentName)],
    ["结算月份", formatMonth(row.year_month)],
    ["业务归属", nameById(businessEntities, row.business_entity_id, businessEntityName)],
    ["系统差额", formatCurrency(row.system_difference_cny, "CNY")],
    ["数据库权威调整", authoritativeAdjustment],
    ["数据库权威结转", authoritativeCarryover],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");
}

function applyAdjustmentMode({ preserveManualAmount = false } = {}) {
  if (!currentAdjustmentSettlement) {
    return;
  }

  const mode = dom.adjustmentSourceInput.value || ADJUSTMENT_MODES.MANUAL_ADJUSTMENT;
  const isManual = mode === ADJUSTMENT_MODES.MANUAL_ADJUSTMENT;
  dom.adjustmentAmountInput.readOnly = !isManual;

  if (!preserveManualAmount) {
    dom.adjustmentAmountInput.value = "";
    clearAdjustmentErrors();
  }

  if (mode === ADJUSTMENT_MODES.CARRY_FINAL_BALANCE) {
    dom.adjustmentAmountInput.value = currentAdjustmentSettlement.adjustment_source === mode
      ? formatCnyInput(currentAdjustmentSettlement.adjustment_amount_cny)
      : "";
  } else if (mode === ADJUSTMENT_MODES.CLEAR_BALANCE) {
    dom.adjustmentAmountInput.value = currentAdjustmentSettlement.adjustment_source === mode
      ? formatCnyInput(currentAdjustmentSettlement.adjustment_amount_cny)
      : "";
  } else if (!preserveManualAmount
      && currentAdjustmentSettlement.adjustment_source !== mode) {
    dom.adjustmentAmountInput.value = "";
  }

  renderAdjustmentSummary(currentAdjustmentSettlement);
}

async function handleAdjustmentSubmit() {
  if (isAdjustmentSubmitting) {
    return;
  }

  clearAdjustmentErrors();

  if (!currentAdjustmentSettlement) {
    showAdjustmentError("未找到可调整的结算预览。");
    return;
  }

  const source = dom.adjustmentSourceInput.value.trim();
  const isManual = source === ADJUSTMENT_MODES.MANUAL_ADJUSTMENT;
  const explicitAmountText = dom.adjustmentAmountInput.value.trim();
  const amount = isManual && explicitAmountText !== ""
    ? Number(explicitAmountText)
    : null;
  const reason = dom.adjustmentReasonInput.value.trim();
  const invalidFields = [];
  if (isManual && (amount === null || !Number.isFinite(amount))) invalidFields.push("amount");
  if (!source) invalidFields.push("source");
  if (!reason) invalidFields.push("reason");
  if (!dom.adjustmentConfirmCheckbox.checked) invalidFields.push("confirm");

  if (invalidFields.length) {
    invalidFields.forEach((fieldId) => setAdjustmentFieldInvalid(fieldId, true));
    showAdjustmentError(isManual
      ? "请选择调整方式，填写手动调整金额与理由，并勾选确认。"
      : "请选择调整方式，填写理由，并勾选确认。金额由数据库计算。");
    return;
  }

  setAdjustmentSubmitting(true);

  try {
    const sourceRow = currentAdjustmentSettlement;
    const filtersBeforeSubmit = readFilters();
    const result = await setStudentMonthlySettlementDraftAdjustment({
      studentId: sourceRow.student_id,
      yearMonth: sourceRow.year_month,
      adjustmentAmountCny: amount,
      adjustmentSource: source,
      adjustmentReason: reason,
      note: dom.adjustmentNoteInput.value.trim(),
    });
    closeAdjustmentDialog(true);
    await loadSettlementMonth(sourceRow.year_month);
    renderWithFilters({
      ...(filtersBeforeSubmit || {}),
      month: sourceRow.year_month,
    });
    showMessage("success", `锁定前差额调整已保存：${shortId(result?.draft_id)}；数据库权威调整 ${formatCurrency(result?.adjustment_amount_cny, "CNY")}，权威结转 ${formatCurrency(result?.locked_carryover_cny, "CNY")}。`);
  } catch (error) {
    showAdjustmentError(error.message || String(error));
  } finally {
    setAdjustmentSubmitting(false);
  }
}

function setAdjustmentSubmitting(isSubmitting) {
  isAdjustmentSubmitting = isSubmitting;
  dom.adjustmentSubmitButton.disabled = isSubmitting;
  dom.adjustmentCancelButton.disabled = isSubmitting;
  dom.adjustmentSubmitButton.textContent = isSubmitting ? "保存中..." : "保存差额调整";
}

function clearAdjustmentErrors() {
  dom.adjustmentError.textContent = "";
  dom.adjustmentError.classList.add("is-hidden");
  ["amount", "source", "reason", "confirm"].forEach(clearAdjustmentFieldInvalid);
}

function showAdjustmentError(message) {
  dom.adjustmentError.textContent = message;
  dom.adjustmentError.classList.remove("is-hidden");
}

function hideAdjustmentErrorIfClean() {
  if (!dom.adjustmentDialog?.querySelector(".field.is-invalid")) {
    dom.adjustmentError.textContent = "";
    dom.adjustmentError.classList.add("is-hidden");
  }
}

function setAdjustmentFieldInvalid(fieldId, invalid) {
  const field = dom.adjustmentDialog?.querySelector(`[data-settlement-adjustment-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearAdjustmentFieldInvalid(fieldId) {
  setAdjustmentFieldInvalid(fieldId, false);
}

function adjustmentModeForRow(row) {
  const source = safeText(row?.adjustment_source).trim();
  if (Object.values(ADJUSTMENT_MODES).includes(source)) {
    return source;
  }
  if (!source && numberOrZero(row?.adjustment_amount_cny) === 0) {
    return ADJUSTMENT_MODES.CARRY_FINAL_BALANCE;
  }
  return ADJUSTMENT_MODES.MANUAL_ADJUSTMENT;
}

function numberOrZero(value) {
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? numberValue : 0;
}

function formatCnyInput(value) {
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? String(numberValue) : "";
}

function filterSettlements(rows, filters) {
  return rows.filter((row) => {
    if (filters.studentId && row.student_id !== filters.studentId) {
      return false;
    }

    if (filters.businessEntityId && row.business_entity_id !== filters.businessEntityId) {
      return false;
    }

    if (filters.status && effectiveSettlementStatus(row) !== filters.status) {
      return false;
    }

    return matchesKeyword(row, filters.keyword);
  });
}

function matchesKeyword(row, keyword) {
  if (!keyword) {
    return true;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return [
    nameById(students, row.student_id, studentName),
    nameById(businessEntities, row.business_entity_id, businessEntityName),
    settlementStatusLabel(effectiveSettlementStatus(row)),
    effectiveSettlementStatus(row),
    row.physical_status,
    row.immutable_error_code,
    row.immutable_reason,
    row.note,
    row.adjustment_reason,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function effectiveSettlementStatus(row) {
  return row.effective_status || row.settlement_status;
}

function sortSettlements(rows) {
  return [...rows].sort((left, right) => {
    const studentCompare = nameById(students, left.student_id, studentName)
      .localeCompare(nameById(students, right.student_id, studentName), "zh-CN");
    if (studentCompare !== 0) {
      return studentCompare;
    }

    const businessCompare = nameById(businessEntities, left.business_entity_id, businessEntityName)
      .localeCompare(nameById(businessEntities, right.business_entity_id, businessEntityName), "zh-CN");
    if (businessCompare !== 0) {
      return businessCompare;
    }

    return safeText(left.locked_at).localeCompare(safeText(right.locked_at));
  });
}

function distinctValues(rows, key) {
  return Array.from(
    new Set(
      rows
        .map((row) => safeText(row[key]).trim())
        .filter(Boolean)
    )
  ).sort((left, right) => left.localeCompare(right, "zh-CN"));
}

function nameById(rows, id, labelGetter) {
  const row = rows.find((item) => item.id === id);
  if (!row) {
    return id ? "未知" : "未设置";
  }

  return labelGetter(row);
}

function studentName(student) {
  return safeText(student.display_name || student.name) || "未设置";
}

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
}

function settlementStatusLabel(value) {
  return SETTLEMENT_STATUS_LABELS[value] || displayValue(value);
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

function statusClass(status) {
  if (status === "preview") {
    return "status-pending";
  }
  if (status === "unlocked") {
    return "status-cancelled";
  }
  return status === "locked" ? "status-paid" : "status-neutral";
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

function noteText(row) {
  return displayValue([row.note, row.unlock_reason, row.adjustment_reason].filter(Boolean).join(" / "));
}

function displayValue(value) {
  return safeText(value) || "-";
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
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
