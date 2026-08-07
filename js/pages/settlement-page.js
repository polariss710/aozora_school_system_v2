import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchSettlementStudents,
  fetchStudentSettlementAdjustmentDialogPreview,
  fetchStudentSettlements,
} from "../api/settlement-api.js?v=phase-b4-finance-20260807-1";
import {
  formatSettlementBusinessError,
  settlementMonthDateRange,
} from "../api/business-error.js?v=be-ui-20260806-1";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import {
  fetchStudentMonthCandidates,
  readStudentCandidateQuery,
  renderStudentMonthCandidateOptions,
  writeStudentCandidateQuery,
} from "../api/student-status-api.js?v=phase-b4-finance-20260807-1";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";
import { hasFrozenSettlementOverage } from "../utils/actual-overage.js";
import { formatTeacherWageBlockerDisplayReason } from "../utils/system-blocker-display.js?v=be-ui-blocker-20260807-1";

const DEFAULT_FILTERS = {
  studentId: "",
  includeInactive: false,
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

const SOURCE_TREATMENT_MODES = {
  SEPARATE: "separate_makeup_and_overage_v1",
  NET_FINANCIAL: "net_lesson_variance_to_financial_credit_v1",
};

const TRUSTED_TOOL_MESSAGE = "V2财务写操作请使用本机受信管理工具执行。";

const dom = {};
let students = [];
let studentMonthCandidates = [];
let settlements = [];
let loadedMonth = "";
let loadedStudentCandidateKey = "";
let initialFilters = null;
let currentLockSettlement = null;
let isLockSubmitting = false;
let currentStatusActionSettlement = null;
let currentStatusAction = "";
let isStatusActionSubmitting = false;
let currentAdjustmentSettlement = null;
let isAdjustmentSubmitting = false;
let isAdjustmentPreviewLoading = false;
let currentAdjustmentPreview = null;
let currentAdjustmentPreviewSignature = "";
let currentAdjustmentState = null;
let adjustmentPreviewRequestSequence = 0;

export function initSettlementPage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  initialFilters = readSettlementQuery();
  setDefaultFilters(initialFilters);
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
  dom.includeInactiveCheckbox = document.querySelector("#settlementIncludeInactiveCheckbox");
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
  dom.adjustmentCurrentState = document.querySelector("#settlementAdjustmentCurrentState");
  dom.adjustmentCurrentStateBadge = document.querySelector("#settlementAdjustmentCurrentStateBadge");
  dom.adjustmentSummary = document.querySelector("#settlementAdjustmentSummary");
  dom.adjustmentSourceLines = document.querySelector("#settlementAdjustmentSourceLines");
  dom.adjustmentPreviewStatus = document.querySelector("#settlementAdjustmentPreviewStatus");
  dom.adjustmentPreviewBadge = document.querySelector("#settlementAdjustmentPreviewBadge");
  dom.adjustmentError = document.querySelector("#settlementAdjustmentError");
  dom.adjustmentAmountInput = document.querySelector("#settlementAdjustmentAmountInput");
  dom.sourceTreatmentModeInput = document.querySelector("#settlementSourceTreatmentModeInput");
  dom.sourceTreatmentRateFields = document.querySelector("#settlementSourceTreatmentRateFields");
  dom.sourceTreatmentWarning = document.querySelector("#settlementSourceTreatmentWarning");
  dom.settlementExchangeRateInput = document.querySelector("#settlementExchangeRateInput");
  dom.settlementExchangeRateSourceInput = document.querySelector("#settlementExchangeRateSourceInput");
  dom.settlementExchangeRateEffectiveDateInput = document.querySelector("#settlementExchangeRateEffectiveDateInput");
  dom.adjustmentSourceInput = document.querySelector("#settlementAdjustmentSourceInput");
  dom.adjustmentReasonInput = document.querySelector("#settlementAdjustmentReasonInput");
  dom.adjustmentNoteInput = document.querySelector("#settlementAdjustmentNoteInput");
  dom.adjustmentConfirmCheckbox = document.querySelector("#settlementAdjustmentConfirmCheckbox");
  dom.adjustmentPreviewButton = document.querySelector("#settlementAdjustmentPreviewButton");
  dom.adjustmentSubmitButton = document.querySelector("#settlementAdjustmentSubmitButton");
  dom.adjustmentCancelButton = document.querySelector("#settlementAdjustmentCancelButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    applyQuery();
  });
  dom.yearFilter.addEventListener("change", applyQuery);
  dom.monthFilter.addEventListener("change", applyQuery);
  dom.includeInactiveCheckbox.addEventListener("change", applyQuery);

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
  dom.adjustmentPreviewButton?.addEventListener("click", () => refreshAdjustmentDialogPreview());
  dom.adjustmentSubmitButton?.addEventListener("click", handleAdjustmentSubmit);
  [
    ["amount", dom.adjustmentAmountInput],
    ["reason", dom.adjustmentReasonInput],
    ["note", dom.adjustmentNoteInput],
  ].forEach(([fieldId, element]) => {
    element?.addEventListener("input", () => {
      clearAdjustmentFieldInvalid(fieldId);
      if (fieldId === "amount") {
        invalidateAdjustmentPreview();
      }
      hideAdjustmentErrorIfClean();
    });
  });
  dom.adjustmentSourceInput?.addEventListener("change", () => {
    clearAdjustmentFieldInvalid("source");
    applyAdjustmentMode();
    invalidateAdjustmentPreview();
    hideAdjustmentErrorIfClean();
  });
  dom.sourceTreatmentModeInput?.addEventListener("change", () => {
    applySourceTreatmentMode();
    invalidateAdjustmentPreview();
  });
  [
    ["settlementRate", dom.settlementExchangeRateInput],
    ["settlementRateSource", dom.settlementExchangeRateSourceInput],
    ["settlementRateDate", dom.settlementExchangeRateEffectiveDateInput],
  ].forEach(([fieldId, element]) => {
    element?.addEventListener("input", () => {
      clearAdjustmentFieldInvalid(fieldId);
      invalidateAdjustmentPreview();
      if (fieldId === "settlementRateDate") {
        validateSettlementRateDateInput({ showError: true });
      }
      hideAdjustmentErrorIfClean();
    });
  });
  dom.adjustmentConfirmCheckbox?.addEventListener("change", () => {
    clearAdjustmentFieldInvalid("confirm");
    hideAdjustmentErrorIfClean();
  });
}

function setDefaultFilters(filters = null) {
  const values = filters || { month: currentYearMonth(), ...DEFAULT_FILTERS };
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, values.month);
  dom.studentSelect.value = values.studentId;
  dom.includeInactiveCheckbox.checked = Boolean(values.includeInactive);
  dom.statusSelect.value = values.status;
  dom.keywordInput.value = values.keyword;
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载学生月度结算数据...");

  try {
    students = await fetchSettlementStudents();

    const filters = initialFilters || readFilters();
    await Promise.all([
      loadStudentCandidates(filters),
      loadSettlementMonth(filters.month),
    ]);
    restoreFilterSelections(filters);
    applyCurrentFilters();
    showMessage("success", "学生月度结算数据已加载。");
  } catch (error) {
    students = [];
    settlements = [];
    studentMonthCandidates = [];
    loadedMonth = "";
    loadedStudentCandidateKey = "";
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

  syncSettlementQuery(filters);
  if (filters.month !== loadedMonth || studentCandidateKey(filters) !== loadedStudentCandidateKey) {
    setLoading(true);
    showMessage("info", "正在加载学生月度结算记录...");

    try {
      await Promise.all([
        loadSettlementMonth(filters.month),
        loadStudentCandidates(filters),
      ]);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "学生月度结算记录已加载。");
    } catch (error) {
      settlements = [];
      studentMonthCandidates = [];
      loadedMonth = "";
      loadedStudentCandidateKey = "";
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

async function loadStudentCandidates(filters) {
  studentMonthCandidates = await fetchStudentMonthCandidates({
    month: filters.month,
    includeInactive: filters.includeInactive,
    selectedStudentId: filters.studentId || null,
  });
  loadedStudentCandidateKey = studentCandidateKey(filters);
  renderStudentMonthCandidateOptions(dom.studentSelect, studentMonthCandidates, {
    selectedStudentId: filters.studentId,
  });
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
    includeInactive: dom.includeInactiveCheckbox.checked,
    status: dom.statusSelect.value,
    keyword: dom.keywordInput.value.trim(),
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.studentSelect.value = filters.studentId;
  dom.includeInactiveCheckbox.checked = Boolean(filters.includeInactive);
  dom.statusSelect.value = filters.status;
  dom.keywordInput.value = filters.keyword;
}

function renderMasterOptions() {
  renderStudentMonthCandidateOptions(dom.studentSelect, studentMonthCandidates, {
    selectedStudentId: dom.studentSelect.value,
  });
}

function studentCandidateKey(filters) {
  return `${filters.month}::${filters.includeInactive ? "1" : "0"}::${filters.studentId || ""}`;
}

function readSettlementQuery() {
  const params = new URLSearchParams(window.location.search);
  const year = params.get("year") || "";
  const monthPart = String(params.get("month") || "").padStart(2, "0");
  const parsedMonth = `${year}-${monthPart}`;
  const candidate = readStudentCandidateQuery(window.location.search);
  return {
    month: /^\d{4}-(0[1-9]|1[0-2])$/.test(parsedMonth) ? parsedMonth : currentYearMonth(),
    ...DEFAULT_FILTERS,
    ...candidate,
    status: params.get("status") || "",
    keyword: params.get("keyword") || "",
  };
}

function syncSettlementQuery(filters) {
  if (!window.history?.replaceState) return;
  const [year, month] = filters.month.split("-");
  const url = new URL(window.location.href);
  url.searchParams.set("year", year);
  url.searchParams.set("month", month);
  writeStudentCandidateQuery(url.searchParams, filters);
  setOptionalQuery(url.searchParams, "status", filters.status);
  setOptionalQuery(url.searchParams, "keyword", filters.keyword);
  window.history.replaceState({}, "", url);
}

function setOptionalQuery(params, key, value) {
  if (value) params.set(key, value);
  else params.delete(key);
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
        <button class="button table-action-button" type="button" data-settlement-adjustment-id="${escapeAttribute(row.id)}">DB只读 Preview</button>
        <span class="table-cell-summary" title="${TRUSTED_TOOL_MESSAGE}">本机工具写入</span>
      </div>
    `;
  }

  const actionButton = renderSettlementStatusAction(row);
  return `
    <div class="table-action-group">
      <a class="button table-action-button" href="${escapeAttribute(settlementDetailHref(row.id))}">详情</a>
      ${actionButton}
    </div>
  `;
}

function settlementDetailHref(settlementId) {
  const filters = readFilters();
  const params = new URLSearchParams({ id: settlementId });
  if (filters?.month) {
    const [year, month] = filters.month.split("-");
    params.set("year", year);
    params.set("month", month);
    writeStudentCandidateQuery(params, filters);
    setOptionalQuery(params, "status", filters.status);
    setOptionalQuery(params, "keyword", filters.keyword);
  }
  return `./settlement-detail.html?${params.toString()}`;
}

function renderSettlementStatusAction(row) {
  if (row.editable === false || effectiveSettlementStatus(row) === "historically_consumed_immutable") {
    return `<span class="table-cell-summary" title="${escapeAttribute(row.immutable_reason || row.display_label || "不可修改")}">只读</span>`;
  }
  return `<span class="table-cell-summary" title="${TRUSTED_TOOL_MESSAGE}">只读；写入使用本机工具</span>`;
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
  return formatTeacherWageBlockerDisplayReason({
    blockerLevel: row?.teacher_wage_blocker_level,
    counts: row?.teacher_wage_blocker_counts,
    hasBlocker: Boolean(safeText(row?.teacher_wage_blocker_reason)),
  });
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
    ["预定课时费", formatCurrency(row.planned_lesson_fee_jpy, "JPY")],
    ["实际课时费", formatCurrency(row.actual_lesson_fee_jpy, "JPY")],
    ["课时差额处理", sourceTreatmentModeLabel(row.source_treatment_mode)],
    ["未履约 credit", formatCurrency(row.unused_planned_credit_jpy, "JPY")],
    ["待补权益小时", displayValue(row.pending_makeup_hours)],
    ["实际超额收费", formatCurrency(row.overage_charge_jpy ?? row.duration_overage_fee_jpy, "JPY")],
    ["课时净额", formatCurrency(row.net_lesson_variance_jpy, "JPY")],
    ["显式结算汇率", displayValue(row.settlement_exchange_rate)],
    ["课时净额 CNY", formatCurrency(row.net_lesson_variance_cny, "CNY")],
    ["source 数量", displayValue(row.lesson_variance_source_count)],
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
  showLockError(TRUSTED_TOOL_MESSAGE);
}

function setLockSubmitting(isSubmitting) {
  isLockSubmitting = isSubmitting;
  if (dom.lockSubmitButton) {
    dom.lockSubmitButton.disabled = true;
    dom.lockSubmitButton.textContent = "仅本机受信工具可锁定";
    dom.lockSubmitButton.title = TRUSTED_TOOL_MESSAGE;
  }
  if (dom.lockCancelButton) {
    dom.lockCancelButton.disabled = isSubmitting;
  }
}

function showLockError(errorDisplay) {
  renderDialogBusinessError(dom.lockError, errorDisplay);
  dom.lockError.classList.remove("is-hidden");
}

function clearLockErrors() {
  dom.lockError.replaceChildren();
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
  showStatusActionError(TRUSTED_TOOL_MESSAGE);
}

function setStatusActionSubmitting(isSubmitting) {
  isStatusActionSubmitting = isSubmitting;
  if (dom.statusActionSubmitButton) {
    dom.statusActionSubmitButton.disabled = true;
    dom.statusActionSubmitButton.textContent = "仅本机受信工具可变更";
    dom.statusActionSubmitButton.title = TRUSTED_TOOL_MESSAGE;
  }
  if (dom.statusActionCancelButton) {
    dom.statusActionCancelButton.disabled = isSubmitting;
  }
}

function showStatusActionError(errorDisplay) {
  renderDialogBusinessError(dom.statusActionError, errorDisplay);
  dom.statusActionError.classList.remove("is-hidden");
}

function clearStatusActionErrors() {
  dom.statusActionError.replaceChildren();
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
  applySettlementRateDateRange(row.year_month);
  dom.sourceTreatmentModeInput.value = row.source_treatment_mode
    || SOURCE_TREATMENT_MODES.SEPARATE;
  dom.settlementExchangeRateInput.value = row.settlement_exchange_rate ?? "";
  dom.settlementExchangeRateSourceInput.value = row.settlement_exchange_rate_source || "";
  dom.settlementExchangeRateEffectiveDateInput.value = row.settlement_exchange_rate_effective_date
    || `${row.year_month}-01`;
  dom.adjustmentAmountInput.value = Number.isFinite(Number(row.adjustment_amount_cny))
    ? formatCnyInput(row.adjustment_amount_cny)
    : "";
  dom.adjustmentSourceInput.value = adjustmentModeForRow(row);
  dom.adjustmentReasonInput.value = row.adjustment_reason || "";
  dom.adjustmentNoteInput.value = row.adjustment_note || "";
  dom.adjustmentConfirmCheckbox.checked = false;
  clearAdjustmentErrors();
  applyAdjustmentMode({ preserveManualAmount: true });
  applySourceTreatmentMode();
  adjustmentPreviewRequestSequence += 1;
  currentAdjustmentPreview = null;
  currentAdjustmentPreviewSignature = "";
  currentAdjustmentState = null;
  isAdjustmentPreviewLoading = false;
  renderAdjustmentCurrentState(null, row);
  renderAdjustmentPendingPreview(null, "正在取得数据库只读预览…", "读取中");
  setAdjustmentSubmitting(false);
  dom.adjustmentDialog.classList.remove("is-hidden");
  dom.adjustmentDialog.setAttribute("aria-hidden", "false");
  dom.adjustmentSourceInput.focus();
  void refreshAdjustmentDialogPreview({ silentValidation: true });
}

function closeAdjustmentDialog(force = false) {
  if (isAdjustmentSubmitting && !force) {
    return;
  }

  dom.adjustmentDialog?.classList.add("is-hidden");
  dom.adjustmentDialog?.setAttribute("aria-hidden", "true");
  adjustmentPreviewRequestSequence += 1;
  currentAdjustmentSettlement = null;
  currentAdjustmentPreview = null;
  currentAdjustmentPreviewSignature = "";
  currentAdjustmentState = null;
  isAdjustmentPreviewLoading = false;
  clearAdjustmentErrors();
}

function renderSummaryRows(rows) {
  return rows.map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");
}

function renderAdjustmentCurrentState(state, row = currentAdjustmentSettlement) {
  if (!row) return;
  if (!state) {
    dom.adjustmentCurrentStateBadge.textContent = "读取中";
    dom.adjustmentCurrentState.innerHTML = renderSummaryRows([
      ["学生", nameById(students, row.student_id, studentName)],
      ["结算月份", formatMonth(row.year_month)],
      ["数据库状态", "正在读取…"],
    ]);
    return;
  }
  dom.adjustmentCurrentStateBadge.textContent = state.is_saved ? "已保存" : "尚未保存";
  dom.adjustmentCurrentState.innerHTML = renderSummaryRows([
    ["学生", nameById(students, row.student_id, studentName)],
    ["结算月份", formatMonth(row.year_month)],
    ["保存状态", state.is_saved ? "已有数据库保存事实" : "尚未保存"],
    ["结算状态", state.settlement_status
      ? (SETTLEMENT_STATUS_LABELS[state.settlement_status] || state.settlement_status)
      : "尚未创建"],
    ["锁定状态", state.is_locked ? "已锁定" : "未锁定"],
    ["source draft", state.source_treatment_draft_id || "尚未保存"],
    ["当前处理方式", state.source_treatment_mode
      ? sourceTreatmentModeLabel(state.source_treatment_mode) : "尚未保存"],
    ["当前汇率", state.settlement_exchange_rate ?? "-"],
    ["adjustment draft", state.adjustment_draft_id || "尚未保存"],
    ["当前调整方式", state.adjustment_mode
      ? adjustmentModeLabel(state.adjustment_mode) : "尚未保存"],
    ["当前 draft 调整", formatCurrency(state.draft_adjustment_amount_cny, "CNY")],
    ["已固化调整", formatCurrency(state.posted_adjustment_amount_cny, "CNY")],
    ["已固化结转", formatCurrency(state.posted_carryover_cny, "CNY")],
  ]);
}

function renderAdjustmentPendingPreview(result, message, badge = "待更新") {
  dom.adjustmentPreviewBadge.textContent = badge;
  dom.adjustmentPreviewStatus.textContent = message;
  if (!result?.preview) {
    dom.adjustmentSummary.innerHTML = "";
    dom.adjustmentSourceLines.innerHTML = "";
    return;
  }
  const preview = result.preview;
  const state = result.current_state || {};
  dom.adjustmentSummary.innerHTML = renderSummaryRows([
    ["课时差额处理", sourceTreatmentModeLabel(preview.source_treatment_mode)],
    ["预定摘要", `${displayValue(preview.planned_hours)} 小时 / ${formatCurrency(preview.planned_fee_jpy, "JPY")}`],
    ["实际摘要", `${displayValue(preview.actual_hours)} 小时 / ${formatCurrency(preview.actual_fee_jpy, "JPY")}`],
    ["待补小时", `${displayValue(preview.pending_makeup_hours)} 小时`],
    ["未履约 credit", formatSignedCurrency(preview.unused_planned_credit_jpy, "JPY")],
    ["超额小时", `${displayValue(preview.overage_hours)} 小时`],
    ["超额收费", formatSignedCurrency(preview.overage_charge_jpy, "JPY")],
    ["课时净小时", `${displayValue(preview.lesson_variance_display_hours)} 小时`],
    ["课时净额 JPY", formatSignedCurrency(preview.net_lesson_variance_jpy, "JPY")],
    ["显式结算汇率", displayValue(preview.settlement_exchange_rate)],
    ["课时净额 CNY", formatSignedCurrency(preview.net_lesson_variance_cny, "CNY")],
    ["前期结转", formatSignedCurrency(preview.previous_carryover_cny, "CNY")],
    ["收款等值", formatSignedCurrency(preview.received_equivalent_cny, "CNY")],
    ["收款基础差额", formatSignedCurrency(preview.base_receivable_difference_cny, "CNY")],
    ["当前 draft 调整", formatSignedCurrency(state.draft_adjustment_amount_cny, "CNY")],
    ["已固化调整", formatSignedCurrency(state.posted_adjustment_amount_cny, "CNY")],
    ["projected system difference", formatSignedCurrency(preview.system_difference_cny, "CNY")],
    ["projected adjustment", formatSignedCurrency(preview.projected_adjustment_amount_cny, "CNY")],
    ["projected final carryover", formatSignedCurrency(preview.projected_final_carryover_cny, "CNY")],
    ["来源 manifest", result.preview_manifest_sha256],
    ["来源更新时间", formatDate(preview.source_updated_at)],
    ["预览生成时间", formatDate(result.preview_generated_at)],
  ]);
  renderAdjustmentSourceLines(preview.source_lines || []);
}

function renderAdjustmentSourceLines(lines) {
  if (!lines.length) {
    dom.adjustmentSourceLines.innerHTML = '<p class="section-note">当前模式没有可财务净额化的 source。</p>';
    return;
  }
  dom.adjustmentSourceLines.innerHTML = `
    <table class="settlement-adjustment-source-table">
      <thead><tr><th>来源</th><th>日期 / 科目</th><th>小时</th><th>单价</th><th>JPY</th><th>CNY</th><th>claim</th></tr></thead>
      <tbody>${lines.map((line) => {
        const isUnused = line.source_type === "unused_planned_credit_v1";
        const sourceId = isUnused ? line.source_planned_lesson_id : line.source_actual_lesson_id;
        const sourceDate = isUnused ? line.planned_lesson_date : line.actual_lesson_date;
        const sourceHours = isUnused
          ? `${displayValue(line.remaining_hours)} 小时剩余`
          : `${displayValue(line.overage_hours)} 小时 / ${displayValue(line.overage_minutes)} 分钟`;
        return `<tr>
          <td>${escapeHtml(isUnused ? "待补未履约" : "actual 超额")}
            <code class="settlement-adjustment-source-id">${escapeHtml(sourceId)}</code></td>
          <td>${escapeHtml(displayValue(sourceDate))}<br>${escapeHtml(displayValue(line.subject_name))}</td>
          <td>${escapeHtml(sourceHours)}</td>
          <td>${escapeHtml(formatCurrency(line.unit_price_jpy, "JPY"))}</td>
          <td>${escapeHtml(formatSignedCurrency(line.source_amount_jpy, "JPY"))}</td>
          <td>${escapeHtml(formatSignedCurrency(line.source_amount_cny, "CNY"))}</td>
          <td>${escapeHtml(line.claim_eligible ? "eligible" : (line.exclusion_reason || "excluded"))}</td>
        </tr>`;
      }).join("")}</tbody>
    </table>`;
}

function applySourceTreatmentMode() {
  const isNet = dom.sourceTreatmentModeInput.value === SOURCE_TREATMENT_MODES.NET_FINANCIAL;
  dom.sourceTreatmentRateFields.classList.toggle("is-hidden", !isNet);
  dom.sourceTreatmentWarning.classList.toggle("is-hidden", !isNet);
  if (!isNet) {
    dom.settlementExchangeRateInput.value = "";
    dom.settlementExchangeRateSourceInput.value = "";
    ["settlementRate", "settlementRateSource", "settlementRateDate"]
      .forEach(clearAdjustmentFieldInvalid);
  }
}

function invalidateAdjustmentPreview() {
  if (!currentAdjustmentSettlement) return;
  adjustmentPreviewRequestSequence += 1;
  isAdjustmentPreviewLoading = false;
  currentAdjustmentPreview = null;
  currentAdjustmentPreviewSignature = "";
  renderAdjustmentPendingPreview(
    null,
    "表单已变更，旧预览已失效。请点击“更新数据库预览”。",
    "已过期"
  );
  updateAdjustmentActionState();
}

async function refreshAdjustmentDialogPreview({ silentValidation = false } = {}) {
  if (!currentAdjustmentSettlement || isAdjustmentSubmitting) return;
  clearAdjustmentPreviewFieldErrors();
  const input = readAdjustmentPreviewInput({ validate: !silentValidation });
  if (!input) {
    invalidateAdjustmentPreview();
    if (!silentValidation) {
      showAdjustmentError(adjustmentPreviewValidationMessage());
    }
    return;
  }
  const requestSequence = ++adjustmentPreviewRequestSequence;
  const requestSignature = adjustmentPreviewSignature(input);
  const settlementKey = `${currentAdjustmentSettlement.student_id}|${currentAdjustmentSettlement.year_month}`;
  isAdjustmentPreviewLoading = true;
  currentAdjustmentPreview = null;
  currentAdjustmentPreviewSignature = "";
  renderAdjustmentPendingPreview(null, "正在更新数据库只读预览…", "更新中");
  updateAdjustmentActionState();
  try {
    const result = await fetchStudentSettlementAdjustmentDialogPreview({
      studentId: currentAdjustmentSettlement.student_id,
      businessEntityId: currentAdjustmentSettlement.business_entity_id,
      yearMonth: currentAdjustmentSettlement.year_month,
      ...input,
    });
    const activeKey = currentAdjustmentSettlement
      ? `${currentAdjustmentSettlement.student_id}|${currentAdjustmentSettlement.year_month}` : "";
    if (requestSequence !== adjustmentPreviewRequestSequence || activeKey !== settlementKey) return;
    const currentInput = readAdjustmentPreviewInput({ validate: false });
    if (!currentInput || adjustmentPreviewSignature(currentInput) !== requestSignature) {
      invalidateAdjustmentPreview();
      return;
    }
    if (responsePreviewSignature(result) !== requestSignature) {
      const mismatchError = new Error("数据库预览返回的 expected facts 与当前表单不一致，请重新更新预览。");
      mismatchError.userMessage = "数据库预览与当前表单不一致，请重新更新预览。";
      throw mismatchError;
    }
    currentAdjustmentState = result.current_state || null;
    currentAdjustmentPreview = result;
    currentAdjustmentPreviewSignature = requestSignature;
    renderAdjustmentCurrentState(currentAdjustmentState);
    renderAdjustmentPendingPreview(
      result,
      "以下金额为数据库只读预览，尚未保存。",
      "DB 已更新"
    );
  } catch (error) {
    if (requestSequence !== adjustmentPreviewRequestSequence) return;
    const displayError = formatAdjustmentBusinessError(error);
    currentAdjustmentPreview = null;
    currentAdjustmentPreviewSignature = "";
    renderAdjustmentPendingPreview(null, displayError.message, "失败");
    if (displayError.code === "SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH") {
      setAdjustmentFieldInvalid("settlementRateDate", true);
    }
    showAdjustmentError(displayError);
  } finally {
    if (requestSequence === adjustmentPreviewRequestSequence) {
      isAdjustmentPreviewLoading = false;
      updateAdjustmentActionState();
    }
  }
}

function readSourceTreatmentInput({ validate = true } = {}) {
  const sourceTreatmentMode = dom.sourceTreatmentModeInput.value;
  if (sourceTreatmentMode === SOURCE_TREATMENT_MODES.SEPARATE) {
    return {
      sourceTreatmentMode,
      settlementExchangeRate: null,
      settlementExchangeRateSource: null,
      settlementExchangeRateEffectiveDate: null,
    };
  }
  const rateText = dom.settlementExchangeRateInput.value.trim();
  const rate = rateText === "" ? null : Number(rateText);
  const rateSource = dom.settlementExchangeRateSourceInput.value.trim();
  const effectiveDate = dom.settlementExchangeRateEffectiveDateInput.value;
  if (!validate && (rate === null || !Number.isFinite(rate) || rate <= 0
      || !rateSource || !effectiveDate)) return null;
  const invalid = [];
  if (rate === null || !Number.isFinite(rate) || rate <= 0) invalid.push("settlementRate");
  if (!rateSource) invalid.push("settlementRateSource");
  if (!effectiveDate) invalid.push("settlementRateDate");
  if (validate) invalid.forEach((fieldId) => setAdjustmentFieldInvalid(fieldId, true));
  if (invalid.length) return null;
  return {
    sourceTreatmentMode,
    settlementExchangeRate: rate,
    settlementExchangeRateSource: rateSource,
    settlementExchangeRateEffectiveDate: effectiveDate,
  };
}

function readAdjustmentPreviewInput({ validate = true } = {}) {
  const treatment = readSourceTreatmentInput({ validate });
  const adjustmentMode = dom.adjustmentSourceInput.value.trim();
  const isManual = adjustmentMode === ADJUSTMENT_MODES.MANUAL_ADJUSTMENT;
  const amountText = dom.adjustmentAmountInput.value.trim();
  const explicitUserAmountCny = isManual && amountText !== "" ? Number(amountText) : null;
  const invalid = [];
  if (!treatment) invalid.push("sourceTreatmentMode");
  if (!Object.values(ADJUSTMENT_MODES).includes(adjustmentMode)) invalid.push("source");
  if (isManual && (explicitUserAmountCny === null || !Number.isFinite(explicitUserAmountCny))) {
    invalid.push("amount");
  }
  if (!validate && invalid.length) return null;
  if (validate) invalid.forEach((fieldId) => setAdjustmentFieldInvalid(fieldId, true));
  if (invalid.length) return null;
  return {
    ...treatment,
    adjustmentMode,
    explicitUserAmountCny,
  };
}

function adjustmentPreviewSignature(input) {
  return JSON.stringify({
    sourceTreatmentMode: input.sourceTreatmentMode,
    settlementExchangeRate: input.settlementExchangeRate ?? null,
    settlementExchangeRateSource: input.settlementExchangeRateSource || null,
    settlementExchangeRateEffectiveDate: input.settlementExchangeRateEffectiveDate || null,
    adjustmentMode: input.adjustmentMode,
    explicitUserAmountCny: input.explicitUserAmountCny ?? null,
  });
}

function responsePreviewSignature(result) {
  const expected = result?.preview_expected_facts || {};
  return adjustmentPreviewSignature({
    sourceTreatmentMode: expected.source_treatment_mode,
    settlementExchangeRate: expected.settlement_exchange_rate === null
      || expected.settlement_exchange_rate === undefined
      ? null : Number(expected.settlement_exchange_rate),
    settlementExchangeRateSource: expected.settlement_exchange_rate_source || null,
    settlementExchangeRateEffectiveDate: expected.settlement_exchange_rate_effective_date || null,
    adjustmentMode: expected.adjustment_mode,
    explicitUserAmountCny: expected.explicit_user_amount_cny === null
      || expected.explicit_user_amount_cny === undefined
      ? null : Number(expected.explicit_user_amount_cny),
  });
}

function clearAdjustmentPreviewFieldErrors() {
  ["amount", "source", "sourceTreatmentMode", "settlementRate",
    "settlementRateSource", "settlementRateDate"].forEach(clearAdjustmentFieldInvalid);
  hideAdjustmentErrorIfClean();
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

  updateAdjustmentActionState();
}

async function handleAdjustmentSubmit() {
  showAdjustmentError(TRUSTED_TOOL_MESSAGE);
}

function setAdjustmentSubmitting(isSubmitting) {
  isAdjustmentSubmitting = isSubmitting;
  dom.adjustmentCancelButton.disabled = isSubmitting;
  dom.adjustmentSubmitButton.textContent = "仅本机受信工具可保存";
  updateAdjustmentActionState();
}

function updateAdjustmentActionState() {
  dom.adjustmentPreviewButton.disabled = isAdjustmentSubmitting || isAdjustmentPreviewLoading;
  dom.adjustmentPreviewButton.textContent = isAdjustmentPreviewLoading
    ? "更新中..." : "更新数据库预览";
  dom.adjustmentSubmitButton.disabled = true;
  dom.adjustmentSubmitButton.title = TRUSTED_TOOL_MESSAGE;
}

function clearAdjustmentErrors() {
  dom.adjustmentError.replaceChildren();
  dom.adjustmentError.classList.add("is-hidden");
  ["amount", "source", "reason", "confirm", "sourceTreatmentMode",
    "settlementRate", "settlementRateSource", "settlementRateDate"]
    .forEach(clearAdjustmentFieldInvalid);
}

function showAdjustmentError(errorDisplay) {
  renderDialogBusinessError(dom.adjustmentError, errorDisplay);
  dom.adjustmentError.classList.remove("is-hidden");
}

function renderDialogBusinessError(container, errorDisplay) {
  const display = typeof errorDisplay === "string"
    ? { message: errorDisplay, code: "" }
    : errorDisplay;
  const primary = document.createElement("p");
  primary.className = "dialog-error-primary";
  primary.textContent = display?.message || "操作未完成，请检查输入或刷新数据后重试。";
  container.replaceChildren(primary);
  if (display?.code) {
    const code = document.createElement("p");
    code.className = "dialog-error-code";
    code.textContent = `错误代码：${display.code}`;
    container.append(code);
  }
}

function hideAdjustmentErrorIfClean() {
  if (!dom.adjustmentDialog?.querySelector(".field.is-invalid")) {
    dom.adjustmentError.replaceChildren();
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

function applySettlementRateDateRange(yearMonth) {
  const range = settlementMonthDateRange(yearMonth);
  dom.settlementExchangeRateEffectiveDateInput.min = range?.min || "";
  dom.settlementExchangeRateEffectiveDateInput.max = range?.max || "";
}

function validateSettlementRateDateInput({ showError = false } = {}) {
  const range = settlementMonthDateRange(currentAdjustmentSettlement?.year_month);
  const value = dom.settlementExchangeRateEffectiveDateInput.value;
  const invalid = Boolean(range && value && (value < range.min || value > range.max));
  setAdjustmentFieldInvalid("settlementRateDate", invalid);
  if (invalid && showError) {
    showAdjustmentError(formatSettlementBusinessError(
      new Error("SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH"),
      { yearMonth: currentAdjustmentSettlement?.year_month }
    ));
  }
  return !invalid;
}

function formatAdjustmentBusinessError(error) {
  if (error?.userMessage) {
    return { message: error.userMessage, code: "" };
  }
  return formatSettlementBusinessError(error, {
    yearMonth: currentAdjustmentSettlement?.year_month,
  });
}

function adjustmentPreviewValidationMessage() {
  if (dom.sourceTreatmentModeInput.value === SOURCE_TREATMENT_MODES.NET_FINANCIAL) {
    const rateText = dom.settlementExchangeRateInput.value.trim();
    const rate = rateText === "" ? null : Number(rateText);
    if (rate === null) return "请输入结算汇率。";
    if (!Number.isFinite(rate) || rate <= 0) return "结算汇率必须是大于0的有效数字。";
    if (!dom.settlementExchangeRateSourceInput.value.trim()) return "请输入汇率来源。";
    if (!dom.settlementExchangeRateEffectiveDateInput.value) return "请选择汇率生效日。";
  }
  if (dom.adjustmentSourceInput.value === ADJUSTMENT_MODES.MANUAL_ADJUSTMENT
      && !dom.adjustmentAmountInput.value.trim()) {
    return "手动调整必须明确填写调整金额。";
  }
  return "请完整填写当前模式所需输入后再更新数据库预览。";
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

function sourceTreatmentModeLabel(value) {
  if (value === SOURCE_TREATMENT_MODES.NET_FINANCIAL) {
    return "待补与超额转财务净额";
  }
  return "待补与超额分别处理（旧合同）";
}

function adjustmentModeLabel(value) {
  if (value === ADJUSTMENT_MODES.CARRY_FINAL_BALANCE) return "按最终差额结转";
  if (value === ADJUSTMENT_MODES.CLEAR_BALANCE) return "抹平差额";
  if (value === ADJUSTMENT_MODES.MANUAL_ADJUSTMENT) return "手动调整";
  return displayValue(value);
}

function formatSignedCurrency(value, currency) {
  if (value === null || value === undefined || value === "") return "-";
  const numberValue = Number(value);
  if (!Number.isFinite(numberValue)) return formatCurrency(value, currency);
  const formatted = formatCurrency(numberValue, currency);
  return numberValue > 0 ? `+${formatted}` : formatted;
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
