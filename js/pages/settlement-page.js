import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";
import {
  fetchAuthoritativeLockFacts,
  fetchAuthoritativeLockStatus,
  fetchSettlementStudents,
  fetchStudentSettlementAdjustmentDialogPreview,
  fetchStudentSettlements,
} from "../api/settlement-api.js?v=phase-d-lock-authoritative-source-20260826-1";
import {
  getStudentSettlementOnlineStatus,
  lockStudentSettlementOnline,
  saveStudentSettlementDraftOnline,
  StudentSettlementOnlineError,
} from "../api/student-settlement-online-api.js?v=student-settlement-tokyo-month-close-20260810-3";
import {
  ONLINE_ADJUSTMENT_MODES as ADJUSTMENT_MODES,
  ONLINE_SOURCE_TREATMENT_MODES as SOURCE_TREATMENT_MODES,
  LOCK_FAILURE_STATES,
  buildOnlineDraftLockInput,
  buildOnlineDraftSaveInput,
  canUseOnlineDraftLock,
  canUseOnlineDraftPreview,
  canUseOnlineDraftSave,
  canonicalDecimal,
  classifyLockFailure,
  classifySaveRecovery,
  createSingleFlight,
  decimalString,
  isPositiveDecimalString,
  lockConfirmationAccepted,
  onlineStatusDisplay,
  readRegisteredVarianceSummary,
  statusConfirmsDraftSave,
} from "./settlement-online-state.js?v=phase-d-lock-authoritative-source-20260826-1";
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
const FILTER_RESET_MESSAGE = "已重置筛选条件；点击“查询”后刷新结果。";

const SETTLEMENT_STATUS_LABELS = {
  locked: "已锁定",
  ordinary_locked: "已正式锁定",
  unlocked: "锁定已撤销",
  preview: "未锁定 / 预览",
  incomplete: "未完成",
  historically_consumed_immutable: "已被历史学费账单消费（不可重开）",
  historical_zero_carry_complete: "历史零结转已完成",
};

const dom = {};
let students = [];
let studentMonthCandidates = [];
let settlements = [];
let initialFilters = null;
let appliedFilters = null;
let membershipRole = "";
let queryRequestSequence = 0;
let currentAdjustmentSettlement = null;
let isAdjustmentSubmitting = false;

// Phase D 锁定侧的模块私有状态。
// lockStatusSnapshot / lockPreviewSnapshot 来自 API 层的 scope-only 权威读取入口
// （fetchAuthoritativeLockFacts / fetchAuthoritativeLockStatus），已在那一层深
// 拷贝、递归冻结并登记。本文件没有产出此类快照的正常途径。
//
// 这不等于锁定金额已被结构性地保护住：buildOnlineDraftLockInput 的产出未冻结，
// 而 lockStudentSettlementOnline 是公开的、接受任意 payload。见 2026-08-26 审查
// （docs/school-v2-settlement-phase-d-p0-boundary-authoritative-source-20260826.md
// 第 7 节 P0）。
let currentLockSettlement = null;
let lockStatusSnapshot = null;
let lockPreviewSnapshot = null;
let isLockSubmitting = false;
let lockRequestSequence = 0;
let lockCorrelationId = null;
let lockPendingRecoveryInput = null;
let isAdjustmentPreviewLoading = false;
let currentAdjustmentPreview = null;
let currentAdjustmentPreviewSignature = "";
let currentOnlineStatus = null;
let currentOnlineStatusError = null;
let adjustmentPreviewRequestSequence = 0;
let dialogRequestSequence = 0;
const saveSingleFlight = createSingleFlight();
const lockSingleFlight = createSingleFlight();

export function initSettlementPage(options = {}) {
  membershipRole = options.membershipRole || "";
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
  dom.adjustmentDialog = document.querySelector("#settlementAdjustmentDialog");
  dom.adjustmentCurrentState = document.querySelector("#settlementAdjustmentCurrentState");
  dom.adjustmentCurrentStateBadge = document.querySelector("#settlementAdjustmentCurrentStateBadge");
  dom.adjustmentSummary = document.querySelector("#settlementAdjustmentSummary");
  dom.adjustmentSourceLines = document.querySelector("#settlementAdjustmentSourceLines");
  dom.adjustmentPreviewStatus = document.querySelector("#settlementAdjustmentPreviewStatus");
  dom.adjustmentPreviewBadge = document.querySelector("#settlementAdjustmentPreviewBadge");
  dom.adjustmentError = document.querySelector("#settlementAdjustmentError");
  dom.adjustmentAmountInput = document.querySelector("#settlementAdjustmentAmountInput");
  dom.adjustmentAmountField = document.querySelector("#settlementAdjustmentAmountField");
  dom.sourceTreatmentModeInput = document.querySelector("#settlementSourceTreatmentModeInput");
  dom.sourceTreatmentRateFields = document.querySelector("#settlementSourceTreatmentRateFields");
  dom.sourceTreatmentWarning = document.querySelector("#settlementSourceTreatmentWarning");
  dom.settlementExchangeRateInput = document.querySelector("#settlementExchangeRateInput");
  dom.settlementExchangeRateSourceInput = document.querySelector("#settlementExchangeRateSourceInput");
  dom.settlementExchangeRateEffectiveDateInput = document.querySelector("#settlementExchangeRateEffectiveDateInput");
  dom.adjustmentSourceInput = document.querySelector("#settlementAdjustmentSourceInput");
  dom.adjustmentReasonInput = document.querySelector("#settlementAdjustmentReasonInput");
  dom.adjustmentNoteInput = document.querySelector("#settlementAdjustmentNoteInput");
  dom.adjustmentPreviewButton = document.querySelector("#settlementAdjustmentPreviewButton");
  dom.adjustmentSubmitButton = document.querySelector("#settlementAdjustmentSubmitButton");
  dom.adjustmentCancelButton = document.querySelector("#settlementAdjustmentCancelButton");
  dom.lockDialog = document.querySelector("#settlementLockDialog");
  dom.lockError = document.querySelector("#settlementLockError");
  dom.lockStudent = document.querySelector("#settlementLockStudent");
  dom.lockMonth = document.querySelector("#settlementLockMonth");
  dom.lockDifference = document.querySelector("#settlementLockDifference");
  dom.lockCarryover = document.querySelector("#settlementLockCarryover");
  dom.lockConfirmationInput = document.querySelector("#settlementLockConfirmationInput");
  dom.lockConfirmationHint = document.querySelector("#settlementLockConfirmationHint");
  dom.lockNoteInput = document.querySelector("#settlementLockNoteInput");
  dom.lockSubmitButton = document.querySelector("#settlementLockSubmitButton");
  dom.lockCancelButton = document.querySelector("#settlementLockCancelButton");
  dom.lockRecheckButton = document.querySelector("#settlementLockRecheckButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    applyQuery();
  });
  dom.resetButton.addEventListener("click", () => {
    const defaults = { month: currentYearMonth(), ...DEFAULT_FILTERS };
    setDefaultFilters(defaults);
    syncSettlementQuery(defaults);
    clearQueryResults();
    showMessage("info", FILTER_RESET_MESSAGE);
  });

  dom.tableBody.addEventListener("click", (event) => {
    const adjustmentButton = event.target.closest("[data-settlement-adjustment-id]");
    if (adjustmentButton) {
      openAdjustmentDialog(adjustmentButton.dataset.settlementAdjustmentId);
      return;
    }
    const lockButton = event.target.closest("[data-settlement-lock-id]");
    if (lockButton) {
      openLockDialog(lockButton.dataset.settlementLockId);
    }
  });

  dom.lockCancelButton?.addEventListener("click", () => closeLockDialog());
  dom.lockSubmitButton?.addEventListener("click", handleLockSubmit);
  dom.lockRecheckButton?.addEventListener("click", handleLockRecheck);
  dom.lockConfirmationInput?.addEventListener("input", updateLockActionState);
  dom.lockDialog?.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !isLockSubmitting) closeLockDialog();
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
      if (["amount", "reason"].includes(fieldId)) {
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
  dom.adjustmentDialog?.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !isAdjustmentSubmitting) closeAdjustmentDialog();
  });
  window.addEventListener("popstate", () => {
    const filters = readSettlementQuery();
    setDefaultFilters(filters);
    void runQuery(filters, { updateUrl: false });
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
  try {
    students = await fetchSettlementStudents();
    const filters = initialFilters || readFilters();
    await runQuery(filters, { updateUrl: false, initial: true });
  } catch (error) {
    students = [];
    settlements = [];
    studentMonthCandidates = [];
    renderMasterOptions();
    renderStatusOptions([]);
    renderSettlements([]);
    showMessage("error", `读取学生月度结算数据失败：${error.message || error}`);
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

  await runQuery(filters, { updateUrl: true });
}

async function runQuery(filters, { updateUrl, initial = false }) {
  if (!filters) return;
  const requestSequence = ++queryRequestSequence;
  setLoading(true, initial ? "正在加载学生月度结算…" : "正在查询并读取在线状态…");
  showMessage("info", initial ? "正在加载学生月度结算数据..." : "正在加载学生月度结算记录...");
  try {
    const [nextCandidates, nextSettlements] = await Promise.all([
      fetchStudentMonthCandidates({
        month: filters.month,
        includeInactive: filters.includeInactive,
        selectedStudentId: filters.studentId || null,
      }),
      fetchStudentSettlements(filters.month, filters.studentId || null),
    ]);
    if (requestSequence !== queryRequestSequence) return;
    studentMonthCandidates = nextCandidates;
    settlements = sortSettlements(nextSettlements);
    appliedFilters = { ...filters };
    renderStudentMonthCandidateOptions(dom.studentSelect, studentMonthCandidates, {
      selectedStudentId: filters.studentId,
    });
    renderStatusOptions(settlements);
    renderWithFilters(appliedFilters);
    if (updateUrl) syncSettlementQuery(appliedFilters);
    showMessage("success", "学生月度结算数据和DB权威在线状态已加载。");
  } catch (error) {
    if (requestSequence !== queryRequestSequence) return;
    showMessage("error", `读取学生月度结算记录失败：${error.message || error}`);
  } finally {
    if (requestSequence === queryRequestSequence) setLoading(false);
  }
}

function clearQueryResults() {
  queryRequestSequence += 1;
  appliedFilters = null;
  settlements = [];
  if (!isAdjustmentSubmitting) closeAdjustmentDialog(true);
  renderStatusOptions([]);
  renderSettlements([]);
  setLoading(false);
}

function renderWithFilters(filters) {
  const safeFilters = {
    month: filters?.month || appliedFilters?.month || currentYearMonth(),
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
  const statusDisplay = onlineStatusDisplay(row.online_status, row.online_status_error);
  const canSave = canUseOnlineDraftSave(membershipRole, row.online_status);
  const canPreview = canUseOnlineDraftPreview(membershipRole, row.online_status);
  const physicalSettlementId = row.online_status?.physical_settlement?.settlement_id;
  const detailLink = physicalSettlementId
    ? `<a class="button table-action-button" href="${escapeAttribute(settlementDetailHref(physicalSettlementId))}">详情</a>`
    : "";
  const action = canPreview
    ? `<button class="button table-action-button" type="button" data-settlement-adjustment-id="${escapeAttribute(row.id)}">${canSave ? "编辑草稿" : "只读预览"}</button>`
    : `<span class="table-cell-summary">只读</span>`;

  // Phase D：正式锁定入口。canUseOnlineDraftLock 完整判定，不只看 can_lock——
  // 角色、effective state、blocker、requires_repreview 缺一不可。
  const canLock = canUseOnlineDraftLock(membershipRole, row.online_status);
  const lockAction = canLock
    ? `<button class="button table-action-button button-danger" type="button" data-settlement-lock-id="${escapeAttribute(row.id)}">正式锁定</button>`
    : "";

  // 顺序引导必须始终可见，不能只放在禁用按钮的 tooltip 里——
  // 触屏没有 hover，键盘用户也拿不到。
  const needsDraftFirst = !canLock
    && canSave
    && row.online_status?.lock_blocker_code === "SETTLEMENT_REPREVIEW_REQUIRED";
  const lockHint = needsDraftFirst
    ? `<span class="table-cell-summary settlement-lock-next-step">下一步：请先完成预览并保存草稿。保存成功并刷新状态后，才可正式锁定。</span>`
    : "";

  return `
    <div class="table-action-group">
      ${detailLink}
      ${action}
      ${lockAction}
      <span class="status-badge ${escapeAttribute(statusDisplay.className)}" title="${escapeAttribute(statusDisplay.detail)}">${escapeHtml(statusDisplay.label)}</span>
      ${lockHint}
    </div>
  `;
}

function settlementDetailHref(settlementId) {
  const filters = appliedFilters;
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

async function openAdjustmentDialog(settlementId) {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能保存差额调整。");
    return;
  }

  const row = settlements.find((item) => item.id === settlementId);
  if (!row) {
    showMessage("error", "未找到可调整的结算预览。");
    return;
  }

  currentAdjustmentSettlement = row;
  applySettlementRateDateRange(row.year_month);
  clearAdjustmentErrors();
  adjustmentPreviewRequestSequence += 1;
  const requestSequence = ++dialogRequestSequence;
  currentAdjustmentPreview = null;
  currentAdjustmentPreviewSignature = "";
  currentOnlineStatus = null;
  currentOnlineStatusError = null;
  isAdjustmentPreviewLoading = false;
  renderAdjustmentCurrentState(null, row);
  renderAdjustmentPendingPreview(null, "正在读取DB权威在线状态…", "读取中");
  setAdjustmentSubmitting(false);
  setAdjustmentFormDisabled(true);
  dom.adjustmentDialog.classList.remove("is-hidden");
  dom.adjustmentDialog.setAttribute("aria-hidden", "false");
  dom.adjustmentCancelButton.focus();
  try {
    const status = await getStudentSettlementOnlineStatus(row.student_id, row.year_month);
    if (requestSequence !== dialogRequestSequence || currentAdjustmentSettlement !== row) return;
    currentOnlineStatus = status;
    row.online_status = status;
    row.online_status_error = null;
    renderAdjustmentCurrentState(status, row);
    if (!canUseOnlineDraftPreview(membershipRole, status)) {
      const display = onlineStatusDisplay(status);
      renderAdjustmentPendingPreview(null, display.detail, display.label);
      showAdjustmentError(display.detail);
      updateAdjustmentActionState();
      renderSettlements(filterSettlements(settlements, appliedFilters || DEFAULT_FILTERS));
      return;
    }
    populateAdjustmentFormFromStatus(status);
    setAdjustmentFormDisabled(false);
    dom.adjustmentSourceInput.focus();
    await refreshAdjustmentDialogPreview({ silentValidation: true });
  } catch (error) {
    if (requestSequence !== dialogRequestSequence) return;
    currentOnlineStatusError = error;
    renderAdjustmentCurrentState(null, row, error);
    renderAdjustmentPendingPreview(null, "在线状态读取失败，本条保持只读。", "状态未知");
    showAdjustmentError(safeOnlineErrorDisplay(error));
    updateAdjustmentActionState();
  }
}

function closeAdjustmentDialog(force = false) {
  if (isAdjustmentSubmitting && !force) {
    return;
  }

  dom.adjustmentDialog?.classList.add("is-hidden");
  dom.adjustmentDialog?.setAttribute("aria-hidden", "true");
  adjustmentPreviewRequestSequence += 1;
  dialogRequestSequence += 1;
  currentAdjustmentSettlement = null;
  currentAdjustmentPreview = null;
  currentAdjustmentPreviewSignature = "";
  currentOnlineStatus = null;
  currentOnlineStatusError = null;
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

function populateAdjustmentFormFromStatus(status) {
  const source = status.source_treatment_draft || {};
  const adjustment = status.adjustment_draft || {};
  const preview = status.authoritative_preview || {};
  dom.sourceTreatmentModeInput.value = source.source_treatment_mode
    || preview.source_treatment_mode || SOURCE_TREATMENT_MODES.SEPARATE;
  dom.settlementExchangeRateInput.value = source.settlement_exchange_rate ?? "";
  dom.settlementExchangeRateSourceInput.value = source.settlement_exchange_rate_source || "";
  dom.settlementExchangeRateEffectiveDateInput.value = source.settlement_exchange_rate_effective_date || "";
  dom.adjustmentSourceInput.value = adjustment.adjustment_mode || ADJUSTMENT_MODES.CARRY_FINAL_BALANCE;
  dom.adjustmentAmountInput.value = adjustment.adjustment_mode === ADJUSTMENT_MODES.MANUAL_ADJUSTMENT
    ? String(adjustment.adjustment_amount_cny ?? "") : "";
  dom.adjustmentReasonInput.value = adjustment.reason || "";
  dom.adjustmentNoteInput.value = adjustment.note || "";
  applyAdjustmentMode({ preserveManualAmount: true });
  applySourceTreatmentMode();
}

function setAdjustmentFormDisabled(disabled) {
  [
    dom.sourceTreatmentModeInput,
    dom.settlementExchangeRateInput,
    dom.settlementExchangeRateSourceInput,
    dom.settlementExchangeRateEffectiveDateInput,
    dom.adjustmentAmountInput,
    dom.adjustmentSourceInput,
    dom.adjustmentReasonInput,
    dom.adjustmentNoteInput,
  ].forEach((element) => { if (element) element.disabled = disabled; });
}

function renderAdjustmentCurrentState(state, row = currentAdjustmentSettlement, statusError = null) {
  if (!row) return;
  if (!state) {
    dom.adjustmentCurrentStateBadge.textContent = statusError ? "状态未知" : "读取中";
    dom.adjustmentCurrentState.innerHTML = renderSummaryRows([
      ["学生", nameById(students, row.student_id, studentName)],
      ["结算月份", formatMonth(row.year_month)],
      ["数据库状态", statusError ? "读取失败，本条保持只读" : "正在读取…"],
    ]);
    return;
  }
  const source = state.source_treatment_draft || {};
  const adjustment = state.adjustment_draft || {};
  const display = onlineStatusDisplay(state);
  const hasSavedDrafts = source.status === "active" && adjustment.status === "active";
  dom.adjustmentCurrentStateBadge.textContent = hasSavedDrafts ? "草稿已保存" : display.label;
  dom.adjustmentCurrentState.innerHTML = renderSummaryRows([
    ["学生", nameById(students, row.student_id, studentName)],
    ["结算月份", formatMonth(row.year_month)],
    ["有效状态", display.label],
    ["状态说明", display.detail],
    ["source draft", draftVersionLabel(source)],
    ["当前处理方式", source.source_treatment_mode
      ? sourceTreatmentModeLabel(source.source_treatment_mode) : "尚未保存"],
    ["adjustment draft", draftVersionLabel(adjustment)],
    ["当前调整方式", adjustment.adjustment_mode
      ? adjustmentModeLabel(adjustment.adjustment_mode) : "尚未保存"],
    ["草稿更新时间", latestDraftUpdatedAt(source, adjustment)],
    ["DB权威系统差额", formatCurrency(state.authoritative_system_difference_cny, "CNY")],
    ["DB权威最终结转", formatCurrency(state.final_carryover_cny, "CNY")],
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
  renderAdjustmentSourceLines(preview.source_lines || [], preview);
}

function renderAdjustmentSourceLines(lines, preview) {
  const registeredSummary = readRegisteredVarianceSummary(preview);
  if (registeredSummary.status !== "hidden") {
    renderRegisteredVarianceSummary(registeredSummary);
    return;
  }
  if (!lines.length) {
    dom.adjustmentSourceLines.innerHTML = '<p class="section-note">当前 net Preview 没有可财务化的 eligible source line。</p>';
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

function renderRegisteredVarianceSummary(summary) {
  if (summary.status === "unavailable") {
    dom.adjustmentSourceLines.innerHTML = `
      <section class="settlement-registered-variance-card" aria-labelledby="settlementRegisteredVarianceTitle">
        <h4 id="settlementRegisteredVarianceTitle">当前已登记课时差额</h4>
        <p class="section-note">暂时无法读取已登记课时差额，请重新预览。</p>
      </section>`;
    return;
  }
  if (summary.status === "empty") {
    dom.adjustmentSourceLines.innerHTML = `
      <section class="settlement-registered-variance-card" aria-labelledby="settlementRegisteredVarianceTitle">
        <h4 id="settlementRegisteredVarianceTitle">当前已登记课时差额</h4>
        <p>当前没有已登记的待补或超额事实。</p>
        <p class="section-note">当前为“待补与超额分别处理”模式，上述差额仅展示已登记事实，不在本模式中执行财务净额化。</p>
      </section>`;
    return;
  }

  const netDirectionLabel = {
    pending: "待补",
    overage: "超额",
    balanced: "平衡",
  }[summary.netDirection];
  const overageSystemDifferenceNote = summary.overageIncludedInSystemDifference
    ? `<p class="section-note">超额折算 ${escapeHtml(formatCurrency(summary.overageAmountCny, "CNY"))} 已计入当前 system difference。</p>`
    : "";
  const unresolvedNote = summary.unresolvedPlannedCount > 0
    ? `尚有 ${summary.unresolvedPlannedCount} 条 planned 未决，当前不能生成可保存的 net Preview。`
    : "当前没有普通 planned 未决；正式 net Preview 仍以数据库权威校验为准。";
  dom.adjustmentSourceLines.innerHTML = `
    <section class="settlement-registered-variance-card" aria-labelledby="settlementRegisteredVarianceTitle">
      <h4 id="settlementRegisteredVarianceTitle">当前已登记课时差额</h4>
      <div class="dialog-summary">
        ${renderSummaryRows([
          ["已登记待补", `${displayValue(summary.pendingHours)} 小时 / ${formatCurrency(summary.pendingAmountJpy, "JPY")}`],
          ["已登记超额", `${displayValue(summary.overageHours)} 小时 / ${formatCurrency(summary.overageAmountJpy, "JPY")}`],
          ["当前已登记净差额", `${netDirectionLabel} ${displayValue(summary.netHours)} 小时 / ${formatCurrency(summary.netAmountJpy, "JPY")}`],
        ])}
      </div>
      ${overageSystemDifferenceNote}
      <p class="section-note">${escapeHtml(unresolvedNote)}</p>
      <p class="section-note">当前为“待补与超额分别处理”模式，上述差额仅展示已登记事实，不在本模式中执行财务净额化。</p>
    </section>`;
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
    "表单已变更，旧预览已失效。请点击“重新预览”。",
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
    currentAdjustmentPreview = result;
    currentAdjustmentPreviewSignature = requestSignature;
    renderAdjustmentCurrentState(currentOnlineStatus);
    renderAdjustmentPendingPreview(
      result,
      canUseOnlineDraftSave(membershipRole, currentOnlineStatus)
        ? "以下金额为数据库权威预览；请另行点击“保存草稿”。"
        : "以下金额为数据库权威预览；该月份仅可预览，不能保存。",
      "预览已更新"
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
  const rateSource = dom.settlementExchangeRateSourceInput.value.trim();
  const effectiveDate = dom.settlementExchangeRateEffectiveDateInput.value;
  if (!validate && (!isPositiveDecimalString(rateText)
      || !rateSource || !effectiveDate)) return null;
  const invalid = [];
  if (!isPositiveDecimalString(rateText)) invalid.push("settlementRate");
  if (!rateSource) invalid.push("settlementRateSource");
  if (!effectiveDate) invalid.push("settlementRateDate");
  if (validate) invalid.forEach((fieldId) => setAdjustmentFieldInvalid(fieldId, true));
  if (invalid.length) return null;
  return {
    sourceTreatmentMode,
    settlementExchangeRate: rateText,
    settlementExchangeRateSource: rateSource,
    settlementExchangeRateEffectiveDate: effectiveDate,
  };
}

function readAdjustmentPreviewInput({ validate = true } = {}) {
  const treatment = readSourceTreatmentInput({ validate });
  const adjustmentMode = dom.adjustmentSourceInput.value.trim();
  const isManual = adjustmentMode === ADJUSTMENT_MODES.MANUAL_ADJUSTMENT;
  const amountText = dom.adjustmentAmountInput.value.trim();
  let explicitUserAmountCny = null;
  const invalid = [];
  if (!treatment) invalid.push("sourceTreatmentMode");
  if (!Object.values(ADJUSTMENT_MODES).includes(adjustmentMode)) invalid.push("source");
  if (isManual) {
    try {
      explicitUserAmountCny = decimalString(amountText, "manualAdjustmentAmountCny");
    } catch (_error) {
      invalid.push("amount");
    }
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
    settlementExchangeRate: input.settlementExchangeRate === null
      ? null : canonicalDecimal(input.settlementExchangeRate),
    settlementExchangeRateSource: input.settlementExchangeRateSource || null,
    settlementExchangeRateEffectiveDate: input.settlementExchangeRateEffectiveDate || null,
    adjustmentMode: input.adjustmentMode,
    explicitUserAmountCny: input.explicitUserAmountCny === null
      ? null : canonicalDecimal(input.explicitUserAmountCny),
  });
}

function responsePreviewSignature(result) {
  const expected = result?.preview_expected_facts || {};
  return adjustmentPreviewSignature({
    sourceTreatmentMode: expected.source_treatment_mode,
    settlementExchangeRate: expected.settlement_exchange_rate === null
      || expected.settlement_exchange_rate === undefined
      ? null : String(expected.settlement_exchange_rate),
    settlementExchangeRateSource: expected.settlement_exchange_rate_source || null,
    settlementExchangeRateEffectiveDate: expected.settlement_exchange_rate_effective_date || null,
    adjustmentMode: expected.adjustment_mode,
    explicitUserAmountCny: expected.explicit_user_amount_cny === null
      || expected.explicit_user_amount_cny === undefined
      ? null : String(expected.explicit_user_amount_cny),
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
  dom.adjustmentAmountField.classList.toggle("is-hidden", !isManual);
  dom.adjustmentAmountInput.disabled = !isManual || isAdjustmentSubmitting
    || !canUseOnlineDraftPreview(membershipRole, currentOnlineStatus);

  if (!isManual || !preserveManualAmount) {
    dom.adjustmentAmountInput.value = "";
    clearAdjustmentFieldInvalid("amount");
  }

  updateAdjustmentActionState();
}

async function handleAdjustmentSubmit() {
  if (!currentAdjustmentSettlement || isAdjustmentSubmitting || saveSingleFlight.active) return;
  clearAdjustmentPreviewFieldErrors();
  const previewInput = readAdjustmentPreviewInput({ validate: true });
  if (!previewInput || !currentAdjustmentPreview
      || adjustmentPreviewSignature(previewInput) !== currentAdjustmentPreviewSignature) {
    showAdjustmentError("当前输入尚无对应的DB权威预览，请先点击“重新预览”。");
    return;
  }
  const reason = dom.adjustmentReasonInput.value.trim();
  if (!reason) {
    setAdjustmentFieldInvalid("reason", true);
    showAdjustmentError("保存合同要求填写调整理由；手动调整还必须填写明确金额。请填写后重新预览。");
    return;
  }
  if (reason.length > 2000 || dom.adjustmentNoteInput.value.length > 4000) {
    showAdjustmentError("调整理由或备注过长，请缩短后重新预览。");
    return;
  }
  if (!canUseOnlineDraftSave(membershipRole, currentOnlineStatus)) {
    showAdjustmentError("DB权威状态当前不允许保存，请刷新查询后确认。 ");
    return;
  }
  const input = {
    ...previewInput,
    reason,
    note: dom.adjustmentNoteInput.value,
  };
  let saveInput;
  try {
    saveInput = buildOnlineDraftSaveInput({
      row: currentAdjustmentSettlement,
      status: currentOnlineStatus,
      previewResult: currentAdjustmentPreview,
      input,
    });
  } catch (error) {
    showAdjustmentError(safeOnlineErrorDisplay(error));
    return;
  }
  const beforeStatus = currentOnlineStatus;
  const expectedSignature = currentAdjustmentPreviewSignature;
  const activeDialogSequence = dialogRequestSequence;
  await saveSingleFlight.run(async () => {
    setAdjustmentSubmitting(true);
    clearAdjustmentErrors();
    renderAdjustmentPendingPreview(currentAdjustmentPreview, "正在保存草稿…", "保存中");
    let requestId = "";
    try {
      const edgeResponse = await saveStudentSettlementDraftOnline(saveInput);
      requestId = edgeResponse.request_id || "";
      await confirmSaveWithStatus({
        beforeStatus,
        input,
        requestId,
        expectedSignature,
        activeDialogSequence,
      });
    } catch (error) {
      requestId = error?.requestId || requestId;
      if (error instanceof StudentSettlementOnlineError && error.requiresStatusRecovery) {
        renderAdjustmentPendingPreview(currentAdjustmentPreview, "请求结果暂不明确，正在确认服务器状态…", "确认中");
        try {
          await confirmSaveWithStatus({
            beforeStatus,
            input,
            requestId,
            expectedSignature,
            activeDialogSequence,
            uncertain: true,
          });
        } catch (statusError) {
          showAdjustmentError(safeOnlineErrorDisplay(statusError, requestId));
          renderAdjustmentPendingPreview(currentAdjustmentPreview, "服务器状态仍无法确认；禁止直接重试，请稍后刷新。", "结果未知");
          currentAdjustmentPreview = null;
          currentAdjustmentPreviewSignature = "";
        }
      } else {
        showAdjustmentError(safeOnlineErrorDisplay(error, requestId));
        if (requestId || error?.action === "repreview" || error?.action === "refresh_status") {
          currentAdjustmentPreview = null;
          currentAdjustmentPreviewSignature = "";
          renderAdjustmentPendingPreview(
            null,
            requestId
              ? "Edge已响应，但最终DB状态未能确认；禁止直接重试，请刷新状态。"
              : "服务器权威事实已变化，请重新读取状态并预览。",
            requestId ? "结果未确认" : "已过期",
          );
        }
      }
    } finally {
      if (activeDialogSequence === dialogRequestSequence) setAdjustmentSubmitting(false);
    }
  });
}

async function confirmSaveWithStatus({
  beforeStatus,
  input,
  requestId,
  expectedSignature,
  activeDialogSequence,
  uncertain = false,
}) {
  const status = await getStudentSettlementOnlineStatus(
    currentAdjustmentSettlement.student_id,
    currentAdjustmentSettlement.year_month,
  );
  if (activeDialogSequence !== dialogRequestSequence
      || expectedSignature !== currentAdjustmentPreviewSignature) return;
  const recovery = classifySaveRecovery(beforeStatus, status, currentAdjustmentPreview, input);
  currentOnlineStatus = status;
  currentAdjustmentSettlement.online_status = status;
  renderAdjustmentCurrentState(status);
  renderSettlements(filterSettlements(settlements, appliedFilters || DEFAULT_FILTERS));
  if (recovery === "confirmed" && statusConfirmsDraftSave(status, currentAdjustmentPreview, input)) {
    const requestSuffix = requestId ? `（请求ID ${requestId}）` : "";
    renderAdjustmentPendingPreview(currentAdjustmentPreview, `草稿已保存并经DB状态确认${requestSuffix}。`, "草稿已保存");
    currentAdjustmentPreview = null;
    currentAdjustmentPreviewSignature = "";
    showMessage("success", "月结草稿已保存。刷新状态后可正式锁定。");
    return;
  }
  currentAdjustmentPreview = null;
  currentAdjustmentPreviewSignature = "";
  if (recovery === "unchanged") {
    throw new Error(uncertain
      ? "请求结果未确认，DB仍显示原草稿版本；请稍后刷新，禁止直接重试。"
      : "保存返回后DB仍显示原草稿版本，请刷新后重新预览。");
  }
  throw new Error("草稿已由其他会话更新；请刷新页面并重新预览，不能盲目覆盖。");
}

function setAdjustmentSubmitting(isSubmitting) {
  isAdjustmentSubmitting = isSubmitting;
  dom.adjustmentCancelButton.disabled = isSubmitting;
  dom.adjustmentSubmitButton.textContent = isSubmitting ? "保存中…" : "保存草稿";
  setAdjustmentFormDisabled(isSubmitting || !canUseOnlineDraftPreview(membershipRole, currentOnlineStatus));
  applyAdjustmentMode({ preserveManualAmount: true });
  updateAdjustmentActionState();
}

function updateAdjustmentActionState() {
  const canPreview = canUseOnlineDraftPreview(membershipRole, currentOnlineStatus)
    && !currentOnlineStatusError;
  const canSave = canUseOnlineDraftSave(membershipRole, currentOnlineStatus)
    && !currentOnlineStatusError;
  dom.adjustmentPreviewButton.disabled = !canPreview || isAdjustmentSubmitting || isAdjustmentPreviewLoading;
  dom.adjustmentPreviewButton.textContent = isAdjustmentPreviewLoading
    ? "预览中…" : "重新预览";
  const currentInput = readAdjustmentPreviewInput({ validate: false });
  const hasMatchingPreview = Boolean(currentInput && currentAdjustmentPreview
    && currentAdjustmentPreviewSignature === adjustmentPreviewSignature(currentInput));
  const hasRequiredReason = Boolean(dom.adjustmentReasonInput.value.trim());
  dom.adjustmentSubmitButton.disabled = !canSave || isAdjustmentSubmitting
    || isAdjustmentPreviewLoading || !hasMatchingPreview || !hasRequiredReason;
  dom.adjustmentSubmitButton.title = dom.adjustmentSubmitButton.disabled
    ? (canPreview && !canSave
      ? "当前月份、未来月份或自然周未结束的月份仅可读取DB权威预览，不能保存。"
      : "只有active admin且DB权威状态允许、当前输入已重新预览时才能保存。")
    : "保存草稿（不会锁定）";
}

function clearAdjustmentErrors() {
  dom.adjustmentError.replaceChildren();
  dom.adjustmentError.classList.add("is-hidden");
  ["amount", "source", "reason", "sourceTreatmentMode",
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
  if (display?.requestId) {
    const request = document.createElement("p");
    request.className = "dialog-error-code";
    request.textContent = `请求ID：${display.requestId}`;
    container.append(request);
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
    if (!rateText) return "请输入结算汇率。";
    if (!isPositiveDecimalString(rateText)) return "结算汇率必须是大于0的有效十进制数。";
    if (!dom.settlementExchangeRateSourceInput.value.trim()) return "请输入汇率来源。";
    if (!dom.settlementExchangeRateEffectiveDateInput.value) return "请选择汇率生效日。";
  }
  if (dom.adjustmentSourceInput.value === ADJUSTMENT_MODES.MANUAL_ADJUSTMENT
      && !dom.adjustmentAmountInput.value.trim()) {
    return "手动调整必须明确填写调整金额。";
  }
  return "请完整填写当前模式所需输入后再更新数据库预览。";
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

function draftVersionLabel(draft) {
  if (!draft?.draft_id) return "尚未保存";
  return `${shortId(draft.draft_id)} · ${formatDate(draft.updated_at)}`;
}

function latestDraftUpdatedAt(source, adjustment) {
  const values = [source?.updated_at, adjustment?.updated_at].filter(Boolean).sort();
  return values.length ? formatDate(values.at(-1)) : "尚未保存";
}

function safeOnlineErrorDisplay(error, fallbackRequestId = "") {
  const code = safeText(error?.code) || "SETTLEMENT_ONLINE_REQUEST_FAILED";
  const message = {
    SETTLEMENT_ADMIN_REQUIRED: "当前账号没有结算管理权限。",
    SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE: "该月份已通过历史零结转证据完成，只能查看。",
    SETTLEMENT_HISTORICALLY_CONSUMED: "该月份已被历史账单或不可变事实消费，不能修改。",
    SETTLEMENT_ORDINARY_ALREADY_LOCKED: "该月份已正式锁定，只能查看。",
    SETTLEMENT_SUCCESSOR_REVISION_BLOCKED: "该月份已存在后继学费账单或不可变结算事实，不能保存新的月结草稿。",
    SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED: "该月份已进入不可变财务链，不能修改。",
    SETTLEMENT_WAGE_BLOCKED: "该月份已进入不可变工资链，不能修改。",
    SETTLEMENT_MONTH_NOT_CLOSED: "当前月份尚未结束，仅可读取数据库权威预览，不能保存或锁定。",
    SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED: "未来月份仅可读取数据库权威预览，不能保存或锁定。",
    SETTLEMENT_LESSON_WEEK_NOT_CLOSED: "该月最后一个自然周尚未结束，仅可读取数据库权威预览，不能保存或锁定。",
    SETTLEMENT_SOURCE_FACTS_EMPTY: "该月份没有可用于月结的课时或收款来源，不能保存草稿。",
    SETTLEMENT_PREVIEW_MANIFEST_STALE: "课时或金额事实已变化，请重新预览。",
    SETTLEMENT_LESSON_MANIFEST_STALE: "课时明细已变化，请重新预览。",
    SETTLEMENT_SOURCE_DRAFT_STALE: "source草稿已被其他会话更新，请刷新页面。",
    SETTLEMENT_ADJUSTMENT_DRAFT_STALE: "adjustment草稿已被其他会话更新，请刷新页面。",
    SETTLEMENT_EXPECTED_FACTS_MISMATCH: "服务器权威金额已变化，请重新预览。",
    SETTLEMENT_SCOPE_BUSY: "当前记录正在处理中，请先刷新状态，稍后重试。",
    SETTLEMENT_EDGE_RESULT_UNCERTAIN: "网络结果不明确，系统将先读取状态；禁止直接重试保存。",
    SETTLEMENT_EDGE_UNAUTHORIZED: "登录状态已失效，请重新登录。",
    SETTLEMENT_EDGE_FORBIDDEN: "当前账号没有结算管理权限。",
  }[code]
    // 本地无专属文案时回落到 Edge 返回的业务消息，消除「两张平行映射表各自
    // 漂移」：2026-08-25 实测 Edge 映射 25 个 code，前端只有 17 个有专属文案。
    // 逐条补齐只能解决当下，新增 code 仍会重现。
    //
    // 必须先判类型。本函数也接收非 Edge 异常——例如 handleAdjustmentSubmit 中
    // buildOnlineDraftSaveInput 抛出的普通 Error，其 message 是
    // "decimal must be a decimal string" 这类内部英文文本。无条件回落会把它
    // 直接显示给用户，是真实回归（2026-08-25 初版即如此，由 Codex 审出）。
    // 只有 StudentSettlementOnlineError 的 message 才来自 Edge 的公开消息表
    // （api 层以 safeText(details.message) 构造），可安全展示；此处经
    // textContent 渲染，见 renderDialogBusinessError。
    || (error instanceof StudentSettlementOnlineError ? safeText(error.message) : "")
    || "在线结算操作未完成，请刷新状态后重试。";
  return {
    message,
    code,
    requestId: safeText(error?.requestId || fallbackRequestId),
  };
}

function formatSignedCurrency(value, currency) {
  if (value === null || value === undefined || value === "") return "-";
  const numberValue = Number(value);
  if (!Number.isFinite(numberValue)) return formatCurrency(value, currency);
  const formatted = formatCurrency(numberValue, currency);
  return numberValue > 0 ? `+${formatted}` : formatted;
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
  if (["preview", "incomplete"].includes(status)) {
    return "status-pending";
  }
  if (status === "unlocked") {
    return "status-cancelled";
  }
  return ["locked", "ordinary_locked", "historically_consumed_immutable",
    "historical_zero_carry_complete"].includes(status) ? "status-paid" : "status-neutral";
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

function setLoading(isLoading, message = "") {
  dom.loadingState.textContent = isLoading ? message : "";
  dom.loadingState.classList.toggle("is-loading", isLoading);
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

// ===========================================================================
// Phase D —— 正式锁定
//
// 设计依据：docs/school-v2-settlement-phase-d-lock-ui-design-20260825.md
// 与草稿对话框完全分离；确认金额只作闸门，不进 payload。
// ===========================================================================

async function openLockDialog(settlementId) {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能锁定月结。");
    return;
  }
  const row = settlements.find((item) => item.id === settlementId);
  if (!row) {
    showMessage("error", "未找到可锁定的结算记录。");
    return;
  }

  currentLockSettlement = row;
  lockStatusSnapshot = null;
  lockPreviewSnapshot = null;
  lockPendingRecoveryInput = null;
  lockCorrelationId = createCorrelationId();
  const requestSequence = ++lockRequestSequence;

  clearLockError();
  dom.lockConfirmationInput.value = "";
  dom.lockNoteInput.value = "";
  dom.lockRecheckButton.hidden = true;
  setLockSubmitting(false);
  renderLockFacts(row, null);
  dom.lockDialog.classList.remove("is-hidden");
  dom.lockDialog.setAttribute("aria-hidden", "false");
  dom.lockCancelButton.focus();

  try {
    // status 与 preview 都由 API 层读取、冻结并登记。本函数只递 scope，
    // 拿不到登记入口，也无法影响 preview 的任何 RPC 参数。
    const { status, preview } = await fetchAuthoritativeLockFacts(
      row.student_id, row.year_month,
    );
    if (requestSequence !== lockRequestSequence) return;
    if (!canUseOnlineDraftLock(membershipRole, status)) {
      const display = onlineStatusDisplay(status);
      showLockError(display.detail || "当前状态不允许正式锁定。");
      updateLockActionState();
      return;
    }
    // canUseOnlineDraftLock 依赖 membershipRole，API 层判不了，因此那边只按
    // 「两份草稿是否齐全」决定要不要预读 preview。两个条件不完全重合时会多走
    // 一次只读 RPC，无副作用。
    if (!preview) {
      showLockError("两份草稿尚未齐全，无法读取锁定所需的权威预览。");
      updateLockActionState();
      return;
    }

    lockStatusSnapshot = status;
    lockPreviewSnapshot = preview;
    renderLockFacts(row, lockPreviewSnapshot);
    dom.lockConfirmationInput.focus();
    updateLockActionState();
  } catch (error) {
    if (requestSequence !== lockRequestSequence) return;
    showLockError(safeOnlineErrorDisplay(error));
    updateLockActionState();
  }
}

// 锁定用的 Preview 取参已下沉到 js/api/settlement-api.js 的
// fetchAuthoritativeLockFacts。此处曾有 fetchLockPreviewFromDrafts，虽然它取的
// 是草稿值而非 DOM 值，但它经 fetchStudentSettlementAdjustmentDialogPreview 的
// payload 通道，而该通道有 explicitUserAmountCny 直通 DB——只要取参留在页面层，
// 「金额来自 DB 而非页面」就仍是一条约定，不是结构。

function renderLockFacts(row, previewResult) {
  dom.lockStudent.textContent = row?.student_name || "-";
  dom.lockMonth.textContent = row?.year_month || "-";
  const expected = previewResult?.preview_expected_facts;
  const preview = previewResult?.preview;
  dom.lockDifference.textContent = expected
    ? formatCurrency(expected.system_difference_cny, "CNY") : "-";
  dom.lockCarryover.textContent = preview
    ? formatCurrency(preview.projected_final_carryover_cny, "CNY") : "-";
}

function lockConfirmationMatches() {
  // 比对逻辑在 state 层的纯函数里，此处只负责取值——
  // 这样闸门本身可以脱离 DOM 测试，不会因为「需要浏览器」而被跳过。
  return lockConfirmationAccepted(
    dom.lockConfirmationInput?.value,
    lockPreviewSnapshot?.preview?.projected_final_carryover_cny,
  );
}

function updateLockActionState() {
  const ready = Boolean(lockStatusSnapshot && lockPreviewSnapshot);
  const allowed = ready && canUseOnlineDraftLock(membershipRole, lockStatusSnapshot);
  const matches = allowed && lockConfirmationMatches();
  dom.lockSubmitButton.disabled = !matches || isLockSubmitting;

  if (!ready) {
    dom.lockConfirmationHint.textContent = "正在读取数据库权威事实…";
  } else if (!allowed) {
    dom.lockConfirmationHint.textContent = "当前状态不允许正式锁定。";
  } else if (!matches) {
    dom.lockConfirmationHint.textContent = "输入的金额需与上方「最终结转 CNY」一致。";
  } else {
    dom.lockConfirmationHint.textContent = "确认金额一致，可以锁定。";
  }
}

function setLockSubmitting(submitting) {
  isLockSubmitting = submitting;
  dom.lockConfirmationInput.disabled = submitting;
  dom.lockNoteInput.disabled = submitting;
  dom.lockCancelButton.disabled = submitting;
  dom.lockSubmitButton.textContent = submitting ? "锁定中…" : "确认锁定";
  updateLockActionState();
}

async function handleLockSubmit() {
  if (!currentLockSettlement || isLockSubmitting || lockSingleFlight.active) return;
  if (!lockStatusSnapshot || !lockPreviewSnapshot) return;
  if (!lockConfirmationMatches()) return;

  let lockInput;
  try {
    // 确认输入不出现在参数表中；全部字段取自冻结快照
    lockInput = lockPendingRecoveryInput || buildOnlineDraftLockInput({
      row: currentLockSettlement,
      status: lockStatusSnapshot,
      previewResult: lockPreviewSnapshot,
      membershipRole,
      note: dom.lockNoteInput.value,
      clientCorrelationId: lockCorrelationId,
    });
  } catch (error) {
    showLockError(safeOnlineErrorDisplay(error));
    return;
  }

  const beforeStatus = lockStatusSnapshot;
  await lockSingleFlight.run(async () => {
    setLockSubmitting(true);
    clearLockError();
    try {
      await lockStudentSettlementOnline(lockInput);
      await finishLockSuccess();
    } catch (error) {
      await recoverFromLockFailure(error, beforeStatus, lockInput);
    } finally {
      setLockSubmitting(false);
    }
  });
}

async function finishLockSuccess() {
  showMessage("success", "月结已正式锁定。");
  closeLockDialog(true);
  await loadSettlements();
}

// 失败一律经 classifyLockFailure 分流。此处不自行判断能否重试——
// 尤其不得因为「status 看起来没变」就重放请求：超时不取消底层调用。
async function recoverFromLockFailure(error, beforeStatus, lockInput) {
  let afterStatus = null;
  let statusReadFailed = false;
  try {
    // 已登记的权威快照——classifyLockFailure 会把它与 beforeStatus 逐项比对，
    // 比对结果决定能否重试，因此两侧都必须来自权威读取。
    afterStatus = await fetchAuthoritativeLockStatus(
      currentLockSettlement.student_id, currentLockSettlement.year_month,
    );
  } catch {
    statusReadFailed = true;
  }

  const outcome = classifyLockFailure({
    error,
    beforeStatus,
    afterStatus,
    statusReadFailed,
    previewResult: lockPreviewSnapshot,
    membershipRole,
    lockInput,
  });

  const S = LOCK_FAILURE_STATES;
  if (outcome === S.CONFIRMED) {
    await finishLockSuccess();
    return;
  }

  lockPendingRecoveryInput = outcome === S.RETRIABLE ? lockInput : null;
  dom.lockRecheckButton.hidden = outcome !== S.UNKNOWN;

  if (afterStatus && !statusReadFailed) {
    lockStatusSnapshot = afterStatus;
  }

  const display = safeOnlineErrorDisplay(error);
  const guidance = {
    [S.BLOCKED]: "该操作已被拒绝，请先解决上述前置条件。",
    [S.STALE]: "权威事实已变化，请关闭本对话框并重新预览后再锁定。",
    [S.BUSY]: "同一结算范围正在处理中。请稍后关闭并重新打开本对话框。",
    [S.RETRIABLE]: "本次请求未写入任何数据，可以再次提交。",
    [S.CONFLICT]: "当前状态与本次请求不一致，请关闭并重新预览。",
    [S.UNKNOWN]: "结果未确认，请勿重复锁定。请点击「再次检查状态」确认。",
  }[outcome] || "";

  showLockError({ ...display, message: `${display.message}${guidance ? `　${guidance}` : ""}` });

  // stale / conflict / blocked 之后不允许在本对话框内直接重提
  if (outcome !== S.RETRIABLE) {
    lockPreviewSnapshot = outcome === S.UNKNOWN ? lockPreviewSnapshot : null;
  }
  updateLockActionState();
}

// unknown 态专用：只读地再查一次状态，不重发锁定请求
async function handleLockRecheck() {
  if (!currentLockSettlement || isLockSubmitting) return;
  try {
    const status = await fetchAuthoritativeLockStatus(
      currentLockSettlement.student_id, currentLockSettlement.year_month,
    );
    lockStatusSnapshot = status;
    if (statusConfirmsLockedNow(status)) {
      await finishLockSuccess();
      return;
    }
    showLockError("状态已刷新：该月结仍未锁定。请关闭对话框重新预览后再决定。");
    dom.lockRecheckButton.hidden = true;
    lockPreviewSnapshot = null;
    updateLockActionState();
  } catch (error) {
    showLockError(safeOnlineErrorDisplay(error));
  }
}

function statusConfirmsLockedNow(status) {
  return status?.effective_state?.effective_status === "ordinary_locked";
}

function closeLockDialog(force = false) {
  if (isLockSubmitting && !force) return;
  dom.lockDialog?.classList.add("is-hidden");
  dom.lockDialog?.setAttribute("aria-hidden", "true");
  lockRequestSequence += 1;
  currentLockSettlement = null;
  lockStatusSnapshot = null;
  lockPreviewSnapshot = null;
  lockPendingRecoveryInput = null;
  lockCorrelationId = null;
  dom.lockConfirmationInput.value = "";
  dom.lockNoteInput.value = "";
  dom.lockRecheckButton.hidden = true;
  clearLockError();
}

function showLockError(errorDisplay) {
  renderDialogBusinessError(dom.lockError, errorDisplay);
  dom.lockError.classList.remove("is-hidden");
}

function clearLockError() {
  dom.lockError?.replaceChildren();
  dom.lockError?.classList.add("is-hidden");
}

function createCorrelationId() {
  return typeof crypto !== "undefined" && crypto.randomUUID
    ? crypto.randomUUID()
    : null;
}
