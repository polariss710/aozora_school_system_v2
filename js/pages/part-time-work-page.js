import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { initSchoolAuth, isLoggedIn } from "../auth.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createPartTimeWorkIncomeRequest,
  createPartTimeWorkPlannedLesson,
  deletePartTimeWorkLesson,
  fetchPartTimeWorkLessons,
  fetchPartTimeWorkMonthlySettlements,
  fetchPartTimeWorkSettlementExport,
  generatePartTimeWorkActualFromPlanned,
  lockPartTimeWorkMonthlySettlement,
  unlockPartTimeWorkMonthlySettlement,
  updatePartTimeWorkLesson,
} from "../api/part-time-work-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  initialYearMonthFromUrl,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
  updateMonthScopedNavigation,
  updateUrlMonthParams,
} from "../utils/month-filter.js";
import { formatCurrency, safeText } from "../utils/format.js";

const WORKPLACE_OPTIONS = ["诺应教育", "致远教育", "新领域"];
const SUBJECT_OPTIONS = [
  "EJU文数班课",
  "EJU理数班课",
  "EJU文数一对一",
  "EJU理数一对一",
  "大学院一对一",
];
const DEFAULT_TEACHER_NAME = "吴峰";
const DIALOG_MODES = {
  CREATE_PLANNED: "create_planned",
  EDIT_LESSON: "edit_lesson",
  GENERATE_ACTUAL: "generate_actual",
};

const LESSON_KIND_LABELS = {
  planned: "预定",
  actual: "实际",
};

const SETTLEMENT_STATUS_LABELS = {
  draft: "草稿",
  locked: "已锁定",
  income_request_created: "已生成收入记录",
};

const INCOME_REQUEST_STATUS_LABELS = {
  pending: "收入记录待提交 Cash",
  pending_cash_request: "待提交 Cash 请求",
  awaiting_cash_confirmation: "Cash 待确认",
  received: "收入已确认",
  synced: "已同步",
  cash_rejected: "Cash 已拒绝",
  failed: "失败",
  blocked: "阻塞",
};

const dom = {};
let lessons = [];
let wageLessons = [];
let settlements = [];
let editingLesson = null;
let dialogMode = DIALOG_MODES.CREATE_PLANNED;
let isSubmitting = false;
const expandedWorkplaces = new Set();
const collapsedWageWorkplaces = new Set(WORKPLACE_OPTIONS);
let initialMonth = "";
const appliedFilters = {
  yearMonth: "",
  workplaceName: "",
  classDescription: "",
};

export async function initPartTimeWorkPage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  initialMonth = initialYearMonthFromUrl();
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, initialMonth);
  appliedFilters.yearMonth = initialMonth;
  updateMonthScopedNavigation(initialMonth);
  renderOptionSelect(dom.workplaceFilter, WORKPLACE_OPTIONS, { includeAll: true });
  renderOptionSelect(dom.classDescriptionFilter, [], { includeAll: true });
  renderClassDescriptionOptions([], "", "");
  renderOptionSelect(dom.workplaceNameInput, WORKPLACE_OPTIONS);
  renderOptionSelect(dom.subjectNameInput, SUBJECT_OPTIONS);
  bindEvents();
  renderLessons([]);
  renderWageCalculation([], []);

  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。");
    return;
  }

  await initSchoolAuth();
  if (!isLoggedIn()) {
    showMessage("error", "请先登录后查看或编辑私塾打工记录。");
    return;
  }

  await loadPageData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#partTimeWorkMessageArea");
  dom.filterForm = document.querySelector("#partTimeWorkFilterForm");
  dom.yearFilter = document.querySelector("#partTimeWorkYearFilter");
  dom.monthFilter = document.querySelector("#partTimeWorkMonthFilter");
  dom.workplaceFilter = document.querySelector("#partTimeWorkWorkplaceFilter");
  dom.classDescriptionFilter = document.querySelector("#partTimeWorkContentFilter");
  dom.resetButton = document.querySelector("#partTimeWorkResetButton");
  dom.openCreateButton = document.querySelector("#openPartTimeWorkCreateButton");
  dom.lessonColumns = document.querySelector("#partTimeWorkLessonColumns");
  dom.wageCalculationContainer = document.querySelector("#partTimeWorkWageCalculationContainer");
  dom.loadingState = document.querySelector("#partTimeWorkLoadingState");
  dom.emptyState = document.querySelector("#partTimeWorkEmptyState");
  dom.dialog = document.querySelector("#partTimeWorkDialog");
  dom.dialogTitle = document.querySelector("#partTimeWorkDialogTitle");
  dom.dialogKindText = document.querySelector("#partTimeWorkDialogKindText");
  dom.dialogError = document.querySelector("#partTimeWorkDialogError");
  dom.workDateInput = document.querySelector("#partTimeWorkDateInput");
  dom.workplaceNameInput = document.querySelector("#partTimeWorkWorkplaceInput");
  dom.subjectNameInput = document.querySelector("#partTimeWorkSubjectInput");
  dom.classDescriptionInput = document.querySelector("#partTimeWorkClassDescriptionInput");
  dom.startTimeInput = document.querySelector("#partTimeWorkStartTimeInput");
  dom.endTimeInput = document.querySelector("#partTimeWorkEndTimeInput");
  dom.hoursLabel = document.querySelector("#partTimeWorkHoursLabel");
  dom.hoursInput = document.querySelector("#partTimeWorkHoursInput");
  dom.lessonCountInput = document.querySelector("#partTimeWorkLessonCountInput");
  dom.cumulativeHoursInput = document.querySelector("#partTimeWorkCumulativeHoursInput");
  dom.hourlyRateInput = document.querySelector("#partTimeWorkHourlyRateInput");
  dom.transportationFeeInput = document.querySelector("#partTimeWorkTransportationFeeInput");
  dom.memoInput = document.querySelector("#partTimeWorkMemoInput");
  dom.preview = document.querySelector("#partTimeWorkPreview");
  dom.cancelButton = document.querySelector("#partTimeWorkCancelButton");
  dom.submitButton = document.querySelector("#partTimeWorkSubmitButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    applyDraftFilters();
    loadPageData({ expandSelectedWorkplace: true });
  });
  dom.yearFilter.addEventListener("change", updateMonthNavigationFromCurrentSelection);
  dom.monthFilter.addEventListener("change", updateMonthNavigationFromCurrentSelection);
  dom.workplaceFilter.addEventListener("change", () => {
    renderClassDescriptionOptions(wageLessons, dom.classDescriptionFilter.value, dom.workplaceFilter.value);
  });

  dom.resetButton.addEventListener("click", () => {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
    dom.workplaceFilter.value = "";
    dom.classDescriptionFilter.value = "";
    renderClassDescriptionOptions(wageLessons, "", "");
    applyDraftFilters();
    loadPageData();
  });

  dom.classDescriptionFilter.addEventListener("change", () => {
    // Draft-only change. The list is updated only when the filter form is submitted.
  });

  dom.openCreateButton.addEventListener("click", openCreatePlannedDialog);
  dom.cancelButton.addEventListener("click", closeDialog);
  dom.submitButton.addEventListener("click", submitDialog);
  dom.lessonColumns.addEventListener("click", handleWorkplaceToggleClick);
  dom.lessonColumns.addEventListener("click", handleLessonActionClick);
  dom.wageCalculationContainer.addEventListener("click", handleWageToggleClick);
  dom.wageCalculationContainer.addEventListener("click", handleSettlementActionClick);
  dom.wageCalculationContainer.addEventListener("input", handleSettlementInputChange);

  for (const input of [
    dom.workDateInput,
    dom.workplaceNameInput,
    dom.subjectNameInput,
    dom.classDescriptionInput,
    dom.startTimeInput,
    dom.endTimeInput,
    dom.hoursInput,
    dom.lessonCountInput,
    dom.cumulativeHoursInput,
    dom.hourlyRateInput,
    dom.transportationFeeInput,
    dom.memoInput,
  ]) {
    input.addEventListener("input", () => {
      clearFieldInvalid(input);
      hideDialogErrorIfClean();
      updatePreview();
    });
  }

}

async function loadPageData(options = {}) {
  if (!isLoggedIn()) {
    renderLessons([]);
    renderWageCalculation([], []);
    showMessage("error", "请先登录后查看或编辑私塾打工记录。");
    return;
  }

  const filters = readAppliedFilters();
  updateUrlMonthParams(filters.yearMonth);
  updateMonthScopedNavigation(filters.yearMonth);
  setLoading(true);
  showMessage("", "");

  try {
    const [lessonRows, wageLessonRows, settlementRows] = await Promise.all([
      fetchPartTimeWorkLessons({
        yearMonth: filters.yearMonth,
        workplaceName: filters.workplaceName,
      }),
      fetchPartTimeWorkLessons({ yearMonth: filters.yearMonth }),
      fetchPartTimeWorkMonthlySettlements({ yearMonth: filters.yearMonth }),
    ]);
    lessons = lessonRows || [];
    wageLessons = wageLessonRows || [];
    settlements = settlementRows || [];
    const classDescription = normalizedAppliedClassDescription(filters);
    renderClassDescriptionOptions(wageLessons, dom.classDescriptionFilter.value, dom.workplaceFilter.value);
    if (options.expandSelectedWorkplace && filters.workplaceName) {
      expandedWorkplaces.add(filters.workplaceName);
    }
    renderVisibleLessons({ ...filters, classDescription });
    renderWageCalculation(wageLessons, settlements);
  } catch (error) {
    lessons = [];
    wageLessons = [];
    settlements = [];
    renderClassDescriptionOptions([], "");
    renderLessons([]);
    renderWageCalculation([], []);
    showMessage("error", `私塾打工数据读取失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readDraftFilters() {
  return {
    yearMonth: getYearMonthSelectValue(dom.yearFilter, dom.monthFilter),
    workplaceName: dom.workplaceFilter.value,
    classDescription: dom.classDescriptionFilter.value,
  };
}

function applyDraftFilters() {
  const draft = readDraftFilters();
  appliedFilters.yearMonth = draft.yearMonth;
  appliedFilters.workplaceName = draft.workplaceName;
  appliedFilters.classDescription = draft.workplaceName ? draft.classDescription : "";
  return readAppliedFilters();
}

function readAppliedFilters() {
  return {
    yearMonth: appliedFilters.yearMonth,
    workplaceName: appliedFilters.workplaceName,
    classDescription: appliedFilters.classDescription,
  };
}

function updateMonthNavigationFromCurrentSelection() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    return;
  }
  updateUrlMonthParams(month);
  updateMonthScopedNavigation(month);
}

function renderLessons(rows) {
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);
  dom.lessonColumns.innerHTML = renderWorkflowColumns(rows);
}

function renderVisibleLessons(filters = readAppliedFilters()) {
  renderLessons(filterLessonsByClassDescription(lessons, filters.classDescription));
}

function renderClassDescriptionOptions(rows, selectedValue = "", workplaceName = "") {
  const normalizedWorkplace = safeText(workplaceName).trim();
  if (!normalizedWorkplace) {
    dom.classDescriptionFilter.innerHTML = '<option value="">请先选择私塾</option>';
    dom.classDescriptionFilter.value = "";
    dom.classDescriptionFilter.disabled = true;
    return "";
  }

  const normalizedSelected = safeText(selectedValue).trim();
  const options = distinctClassDescriptions(rows, workplaceName);
  const nextSelected = normalizedSelected && options.includes(normalizedSelected)
    ? normalizedSelected
    : "";

  dom.classDescriptionFilter.disabled = false;
  renderOptionSelect(dom.classDescriptionFilter, options, { includeAll: true });
  dom.classDescriptionFilter.value = nextSelected;
  return nextSelected;
}

function normalizedAppliedClassDescription(filters) {
  if (!filters.workplaceName || !filters.classDescription) {
    appliedFilters.classDescription = "";
    return "";
  }

  const options = distinctClassDescriptions(wageLessons, filters.workplaceName);
  if (!options.includes(filters.classDescription)) {
    appliedFilters.classDescription = "";
    return "";
  }

  return filters.classDescription;
}

function distinctClassDescriptions(rows, workplaceName = "") {
  const normalizedWorkplace = safeText(workplaceName).trim();
  return Array.from(
    new Set(
      rows
        .filter((row) => !normalizedWorkplace || row.workplace_name === normalizedWorkplace)
        .map((row) => safeText(row.class_description).trim())
        .filter(Boolean)
    )
  ).sort((left, right) => left.localeCompare(right, "zh-CN"));
}

function filterLessonsByClassDescription(rows, classDescription) {
  const target = safeText(classDescription).trim();
  if (!target) {
    return rows;
  }

  const matchingPlannedIds = new Set();
  for (const row of rows) {
    if (safeText(row.class_description).trim() !== target) {
      continue;
    }
    if (row.record_kind === "planned") {
      matchingPlannedIds.add(row.id);
    } else if (row.planned_lesson_id) {
      matchingPlannedIds.add(row.planned_lesson_id);
    }
  }

  return rows.filter((row) => (
    safeText(row.class_description).trim() === target
    || (row.record_kind === "planned" && matchingPlannedIds.has(row.id))
    || (row.record_kind === "actual" && matchingPlannedIds.has(row.planned_lesson_id))
  ));
}

function buildEstimatedSummary(rows, workplaceName) {
  const plannedRows = rows.filter((row) => row.record_kind === "planned" && row.workplace_name === workplaceName);
  const lessonWageJpy = plannedRows.reduce((sum, row) => (
    sum + Math.round(Number(row.planned_hours || 0) * Number(row.hourly_rate_jpy || 0))
  ), 0);
  const transportationFeeJpy = plannedRows.reduce((sum, row) => (
    sum + Number(row.transportation_fee_jpy || 0)
  ), 0);

  return {
    lessonWageJpy,
    transportationFeeJpy,
    totalJpy: lessonWageJpy + transportationFeeJpy,
  };
}

function renderWorkflowColumns(rows) {
  const plannedRows = rows.filter((row) => row.record_kind === "planned");
  const actualRows = rows.filter((row) => row.record_kind === "actual");

  return WORKPLACE_OPTIONS.map((workplace) => {
    const workplacePlannedRows = plannedRows.filter((row) => row.workplace_name === workplace);
    const isExpanded = expandedWorkplaces.has(workplace);
    const body = workplacePlannedRows.length
      ? workplacePlannedRows.map((planned) => renderLessonPair(planned, actualRows.find((actual) => actual.planned_lesson_id === planned.id))).join("")
      : `<div class="lesson-pair-placeholder">暂无预定课时</div>`;
    return `
      <section class="part-time-work-workplace-section">
        <div class="part-time-work-workplace-title">
          <span>${escapeHtml(workplace)}</span>
          <button class="button table-action-button" type="button" data-part-time-work-toggle-workplace="${escapeAttribute(workplace)}" aria-expanded="${String(isExpanded)}">${isExpanded ? "折叠" : "展开"}</button>
        </div>
        <div class="part-time-work-workplace-body ${isExpanded ? "" : "is-hidden"}">${body}</div>
      </section>
    `;
  }).join("");
}

function renderLessonPair(planned, actual) {
  return `
    <article class="lesson-pair-row part-time-work-pair-row">
      <div class="lesson-pair-column">
        <div class="lesson-pair-column-title">预定课时</div>
        ${renderLessonCard(planned, { side: "planned", pairedActual: actual })}
      </div>
      <div class="lesson-pair-column">
        <div class="lesson-pair-column-title">实际课时</div>
        ${actual ? renderLessonCard(actual, { side: "actual", pairedPlanned: planned }) : renderActualPlaceholder(planned)}
      </div>
    </article>
  `;
}

function renderActualPlaceholder(planned) {
  return `
    <div class="lesson-pair-placeholder part-time-work-actual-placeholder">
      <span>暂无实际课时</span>
      <button class="button table-action-button" type="button" data-part-time-work-generate-id="${escapeAttribute(planned.id)}">生成实际</button>
    </div>
  `;
}

function renderLessonCard(row, options = {}) {
  const isActual = row.record_kind === "actual";
  const hours = isActual ? row.actual_hours : row.planned_hours;
  const count = lessonCount(row);
  const isLocked = row.settlement_status === "locked" || row.settlement_status === "income_request_created";
  const hasActual = row.record_kind === "planned" && Boolean(options.pairedActual || row.generated_actual_id);
  const canEdit = !isActual || !isLocked;
  const canDelete = row.record_kind === "planned" && !isLocked;
  const canCopy = row.record_kind === "planned";
  const editConfirm = hasActual || isActual ? "true" : "false";
  const deleteConfirm = hasActual ? "true" : "false";

  return `
    <article class="lesson-pair-card part-time-work-pair-card">
      <div class="lesson-pair-card-header">
        <div class="action-buttons">
          ${canCopy ? `<button class="button table-action-button" type="button" data-part-time-work-copy-id="${escapeAttribute(row.id)}">复制</button>` : ""}
          ${canEdit ? `<button class="button table-action-button" type="button" data-part-time-work-edit-id="${escapeAttribute(row.id)}" data-part-time-work-confirm-edit="${editConfirm}">编辑</button>` : ""}
          ${canDelete ? `<button class="button button-danger table-action-button" type="button" data-part-time-work-delete-id="${escapeAttribute(row.id)}" data-part-time-work-confirm-delete="${deleteConfirm}">删除</button>` : ""}
        </div>
        <span class="status-badge ${escapeAttribute(lessonStatusClass(row))}">${escapeHtml(lessonStatusLabel(row))}</span>
      </div>
      <div class="lesson-pair-main">
        <strong>${escapeHtml(formatDateOnly(row.work_date))}</strong>
        <span>${escapeHtml(timeRange(row.start_time, row.end_time))}</span>
        <span>${escapeHtml(row.subject_name || "-")}</span>
        <span>${escapeHtml(row.class_description || "-")}</span>
      </div>
      <dl class="lesson-pair-meta">
        <div><dt>${isActual ? "实际课时" : "预定课时"}</dt><dd>${escapeHtml(formatHours(hours))} h</dd></div>
        <div><dt>回数</dt><dd>${escapeHtml(formatLessonCount(count))}</dd></div>
        <div><dt>累计课时</dt><dd>${escapeHtml(formatHours(cumulativeHours(row)))} h</dd></div>
        <div><dt>时给</dt><dd>${escapeHtml(formatCurrency(row.hourly_rate_jpy, "JPY"))}</dd></div>
        <div><dt>交通费</dt><dd>${escapeHtml(formatCurrency(row.transportation_fee_jpy, "JPY"))}</dd></div>
        <div><dt>课时工资</dt><dd>${escapeHtml(formatCurrency(row.lesson_wage_jpy, "JPY"))}</dd></div>
        <div><dt>结算</dt><dd>${escapeHtml(settlementStatusLabel(row.settlement_status))}</dd></div>
      </dl>
      <div class="lesson-pair-text">
        <div class="lesson-pair-text-row">
          <span class="lesson-pair-text-label">备注</span>
          <span class="lesson-pair-text-value">${escapeHtml(row.memo || "-")}</span>
        </div>
      </div>
    </article>
  `;
}

function renderWageCalculation(lessonRows, settlementRows) {
  dom.wageCalculationContainer.innerHTML = WORKPLACE_OPTIONS.map((workplaceName) => {
    const estimated = buildEstimatedSummary(lessonRows, workplaceName);
    const settlement = settlementRows.find((row) => row.workplace_name === workplaceName)
      || buildEmptySettlementRow(workplaceName);
    return renderWageWorkplaceSection(workplaceName, estimated, settlement);
  }).join("");
}

function buildEmptySettlementRow(workplaceName) {
  return {
    id: "",
    workplace_name: workplaceName,
    actual_hours_total: 0,
    lesson_wage_jpy: 0,
    transportation_fee_jpy: 0,
    adjustment_jpy: 0,
    total_wage_jpy: 0,
    status: "draft",
    income_request_status: "",
    income_request_id: "",
    income_record_id: "",
    income_record_status: "",
    income_record_cash_status: "",
    memo: "",
  };
}

function renderWageWorkplaceSection(workplaceName, estimated, row) {
  const isLocked = row.status === "locked" || row.status === "income_request_created";
  const canLock = row.status === "draft";
  const canUnlock = row.status === "locked" && !row.income_record_id && !row.income_request_id;
  const canCreateRequest = isLocked && !row.income_record_id;
  const canExport = Boolean(row.id) && isLocked;
  const saveDisabled = isLocked ? "disabled" : "";
  const isCollapsed = collapsedWageWorkplaces.has(workplaceName);
  const incomeStatus = row.income_record_cash_status || row.income_record_status || row.income_request_status || "";

  return `
    <section class="part-time-work-wage-section" data-settlement-row data-settlement-workplace="${escapeAttribute(workplaceName)}" data-settlement-id="${escapeAttribute(row.id || "")}">
      <div class="part-time-work-wage-title-row">
        <div class="part-time-work-wage-title-main">
          <strong>${escapeHtml(workplaceName)}</strong>
          <div class="part-time-work-wage-summary-line">
            <span>预计总额 ${escapeHtml(formatCurrency(estimated.totalJpy, "JPY"))}</span>
            <span>实际总额 <span data-settlement-total-summary>${escapeHtml(formatCurrency(row.total_wage_jpy, "JPY"))}</span></span>
            <span>${renderStatusBadge(settlementStatusLabel(row.status), settlementStatusClass(row.status))}</span>
            <span>${renderOptionalStatusBadge(incomeStatus, incomeRequestStatusLabel(incomeStatus), incomeRequestStatusClass(incomeStatus))}</span>
          </div>
        </div>
        <button class="button table-action-button" type="button" data-wage-workplace-toggle="${escapeAttribute(workplaceName)}" aria-expanded="${String(!isCollapsed)}">${isCollapsed ? "展开" : "收起"}</button>
      </div>

      <div class="part-time-work-wage-body ${isCollapsed ? "is-hidden" : ""}">
      <div class="part-time-work-wage-block">
        <h3>预计工资</h3>
        <div class="part-time-work-summary-grid">
          <article class="summary-card part-time-work-summary-card">
            <p class="summary-label">预计课时工资</p>
            <p class="summary-value">${escapeHtml(formatCurrency(estimated.lessonWageJpy, "JPY"))}</p>
          </article>
          <article class="summary-card part-time-work-summary-card">
            <p class="summary-label">预计交通费</p>
            <p class="summary-value">${escapeHtml(formatCurrency(estimated.transportationFeeJpy, "JPY"))}</p>
          </article>
          <article class="summary-card part-time-work-summary-card">
            <p class="summary-label">预计总额</p>
            <p class="summary-value">${escapeHtml(formatCurrency(estimated.totalJpy, "JPY"))}</p>
          </article>
        </div>
      </div>

      <div class="part-time-work-wage-block">
        <h3>实际工资结算</h3>
        <div class="part-time-work-settlement-grid">
          ${renderSettlementMetric("实际课时", `${formatHours(row.actual_hours_total)} h`)}
          ${renderSettlementMetric("实际课时工资", formatCurrency(row.lesson_wage_jpy, "JPY"))}
          ${renderSettlementMetric("交通费", formatCurrency(row.transportation_fee_jpy, "JPY"))}
          <label class="field part-time-work-settlement-field part-time-work-settlement-metric">
            <span>调整额</span>
            <input class="inline-number-input" data-settlement-input="adjustmentJpy" type="number" step="1" value="${escapeAttribute(row.adjustment_jpy ?? 0)}" ${saveDisabled}>
          </label>
          <div class="part-time-work-settlement-metric">
            <span>工资总额</span>
            <strong data-settlement-total>${escapeHtml(formatCurrency(row.total_wage_jpy, "JPY"))}</strong>
          </div>
          ${renderSettlementMetric("结算状态", renderStatusBadge(settlementStatusLabel(row.status), settlementStatusClass(row.status)), { raw: true, className: "part-time-work-status-metric" })}
          ${renderSettlementMetric("收入记录状态", renderOptionalStatusBadge(incomeStatus, incomeRequestStatusLabel(incomeStatus), incomeRequestStatusClass(incomeStatus)), { raw: true, className: "part-time-work-status-metric" })}
        </div>
        ${row.income_record_id ? `<p class="section-note part-time-work-income-record-link">收入记录：<a href="./income-detail.html?id=${encodeURIComponent(row.income_record_id)}">查看详情</a></p>` : ""}
        <div class="part-time-work-settlement-control-row">
          <label class="field part-time-work-settlement-field part-time-work-settlement-note-card">
            <span>备注</span>
            <input class="inline-text-input" data-settlement-input="memo" type="text" value="${escapeAttribute(row.memo || "")}" ${saveDisabled}>
          </label>
          <div class="action-buttons part-time-work-settlement-actions">
            <button class="button table-action-button" type="button" data-settlement-action="lock" ${canLock ? "" : "disabled"}>锁定结算</button>
            <button class="button table-action-button" type="button" data-settlement-action="unlock" ${canUnlock ? "" : "disabled"}>撤销锁定</button>
            <button class="button table-action-button" type="button" data-settlement-action="request" ${canCreateRequest ? "" : "disabled"}>生成收入记录</button>
            <button class="button table-action-button" type="button" data-settlement-action="export" ${canExport ? "" : "disabled"}>导出 Excel</button>
          </div>
        </div>
      </div>
      </div>
    </section>
  `;
}

function renderSettlementMetric(label, value, options = {}) {
  const className = options.className ? ` ${escapeAttribute(options.className)}` : "";
  return `
    <div class="part-time-work-settlement-metric${className}">
      <span>${escapeHtml(label)}</span>
      <strong>${options.raw ? value : escapeHtml(value)}</strong>
    </div>
  `;
}

function renderStatusBadge(label, className) {
  return `<span class="status-badge part-time-work-status-badge ${escapeAttribute(className)}">${escapeHtml(label)}</span>`;
}

function renderOptionalStatusBadge(status, label, className) {
  if (!status) return "-";
  return renderStatusBadge(label, className);
}

function openCreatePlannedDialog() {
  if (!isLoggedIn()) {
    showMessage("error", "请先登录后新增预定打工课时。");
    return;
  }

  dialogMode = DIALOG_MODES.CREATE_PLANNED;
  editingLesson = null;
  dom.dialogTitle.textContent = "新增预定打工课时";
  dom.dialogKindText.textContent = "预定课时";
  dom.hoursLabel.textContent = "预定课时";
  clearDialog();
  dom.workDateInput.value = todayDate();
  setLessonFieldsReadonly(false);
  updatePreview();
  showDialog();
}

function openCopyPlannedDialog(lesson) {
  if (!isLoggedIn()) {
    showMessage("error", "请先登录后复制预定打工课时。");
    return;
  }

  dialogMode = DIALOG_MODES.CREATE_PLANNED;
  editingLesson = null;
  dom.dialogTitle.textContent = "复制预定打工课时";
  dom.dialogKindText.textContent = "预定课时";
  dom.hoursLabel.textContent = "预定课时";
  clearDialog();
  fillDialogFromLesson(lesson, lesson.planned_hours);
  setLessonFieldsReadonly(false);
  updatePreview();
  showDialog();
}

function openEditDialog(lesson) {
  dialogMode = DIALOG_MODES.EDIT_LESSON;
  editingLesson = lesson;
  const isActual = lesson.record_kind === "actual";
  dom.dialogTitle.textContent = isActual ? "编辑实际打工课时" : "编辑预定打工课时";
  dom.dialogKindText.textContent = isActual ? "实际课时" : "预定课时";
  dom.hoursLabel.textContent = isActual ? "实际课时" : "预定课时";
  clearDialog();
  fillDialogFromLesson(lesson, isActual ? lesson.actual_hours : lesson.planned_hours);
  setLessonFieldsReadonly(false);
  updatePreview();
  showDialog();
}

function openGenerateActualDialog(lesson) {
  dialogMode = DIALOG_MODES.GENERATE_ACTUAL;
  editingLesson = lesson;
  dom.dialogTitle.textContent = "生成实际打工课时";
  dom.dialogKindText.textContent = "从预定生成实际";
  dom.hoursLabel.textContent = "实际课时";
  clearDialog();
  fillDialogFromLesson(lesson, lesson.planned_hours);
  setLessonFieldsReadonly(true);
  updatePreview();
  showDialog();
}

function fillDialogFromLesson(lesson, hours) {
  dom.workDateInput.value = lesson.work_date || "";
  setSelectValueWithFallback(dom.workplaceNameInput, lesson.workplace_name || "");
  setSelectValueWithFallback(dom.subjectNameInput, lesson.subject_name || "");
  dom.classDescriptionInput.value = lesson.class_description || "";
  dom.startTimeInput.value = formatTimeInput(lesson.start_time);
  dom.endTimeInput.value = formatTimeInput(lesson.end_time);
  dom.hoursInput.value = hours ?? 0;
  dom.lessonCountInput.value = String(lessonCount(lesson));
  dom.cumulativeHoursInput.value = formatHours(cumulativeHours(lesson));
  dom.hourlyRateInput.value = lesson.hourly_rate_jpy ?? 0;
  dom.transportationFeeInput.value = lesson.transportation_fee_jpy ?? 0;
  dom.memoInput.value = lesson.memo || "";
}

function closeDialog() {
  if (isSubmitting) {
    return;
  }
  dom.dialog.classList.add("is-hidden");
  dom.dialog.setAttribute("aria-hidden", "true");
}

function showDialog() {
  dom.dialog.classList.remove("is-hidden");
  dom.dialog.setAttribute("aria-hidden", "false");
  dom.workDateInput.focus();
}

async function submitDialog() {
  if (!isLoggedIn()) {
    showDialogError("请先登录后保存私塾打工课时。");
    return;
  }

  const payload = readDialogPayload();
  const validationError = validatePayload(payload);

  if (validationError) {
    showDialogError(validationError);
    return;
  }

  setSubmitting(true);

  try {
    if (dialogMode === DIALOG_MODES.CREATE_PLANNED) {
      await createPartTimeWorkPlannedLesson(payload);
      showMessage("success", "预定打工课时已新增。");
    } else if (dialogMode === DIALOG_MODES.GENERATE_ACTUAL) {
      await generatePartTimeWorkActualFromPlanned({
        ...payload,
        plannedLessonId: editingLesson.id,
      });
      showMessage("success", "实际打工课时已生成。");
    } else {
      await updatePartTimeWorkLesson({ ...payload, id: editingLesson.id });
      showMessage("success", "打工课时已更新。");
    }
    closeDialogAfterSubmit();
    await loadPageData();
  } catch (error) {
    showDialogError(error.message || String(error));
  } finally {
    setSubmitting(false);
  }
}

async function handleLessonActionClick(event) {
  if (event.target.closest("[data-part-time-work-toggle-workplace]")) {
    return;
  }

  const copyButton = event.target.closest("[data-part-time-work-copy-id]");
  if (copyButton) {
    const lesson = lessons.find((item) => item.id === copyButton.dataset.partTimeWorkCopyId);
    if (lesson) {
      openCopyPlannedDialog(lesson);
    }
    return;
  }

  const generateButton = event.target.closest("[data-part-time-work-generate-id]");
  if (generateButton) {
    const lesson = lessons.find((item) => item.id === generateButton.dataset.partTimeWorkGenerateId);
    if (lesson) {
      openGenerateActualDialog(lesson);
    }
    return;
  }

  const editButton = event.target.closest("[data-part-time-work-edit-id]");
  if (editButton) {
    const lesson = lessons.find((item) => item.id === editButton.dataset.partTimeWorkEditId);
    if (lesson) {
      if (editButton.dataset.partTimeWorkConfirmEdit === "true"
        && !window.confirm("该预定课时已生成实际课时，或当前正在编辑实际课时。确认继续编辑？")) {
        return;
      }
      openEditDialog(lesson);
    }
    return;
  }

  const deleteButton = event.target.closest("[data-part-time-work-delete-id]");
  if (!deleteButton) {
    return;
  }

  const lesson = lessons.find((item) => item.id === deleteButton.dataset.partTimeWorkDeleteId);
  if (!lesson) {
    return;
  }

  const hasGeneratedActual = lesson.record_kind === "planned" && lesson.generated_actual_id;
  const needsSecondConfirm = deleteButton.dataset.partTimeWorkConfirmDelete === "true";
  const firstConfirmText = hasGeneratedActual
    ? `预定课时 ${formatDateOnly(lesson.work_date)} 已生成实际课时，删除会同时删除未锁定的实际课时。确认继续？`
    : `确认删除 ${lesson.workplace_name || "该"} 的 ${formatDateOnly(lesson.work_date)} ${lessonKindLabel(lesson.record_kind)}课时？`;
  if (!window.confirm(firstConfirmText)) {
    return;
  }
  if (needsSecondConfirm && !window.confirm("再次确认删除这组预定 / 实际打工课时？")) {
    return;
  }

  try {
    await deletePartTimeWorkLesson(lesson.id, { confirmGeneratedActual: hasGeneratedActual });
    showMessage("success", "打工课时已删除。");
    await loadPageData();
  } catch (error) {
    showMessage("error", `打工课时删除失败：${error.message || error}`);
  }
}

function handleWorkplaceToggleClick(event) {
  const button = event.target.closest("[data-part-time-work-toggle-workplace]");
  if (!button) {
    return;
  }

  const workplace = button.dataset.partTimeWorkToggleWorkplace;
  if (!workplace) {
    return;
  }

  if (expandedWorkplaces.has(workplace)) {
    expandedWorkplaces.delete(workplace);
  } else {
    expandedWorkplaces.add(workplace);
  }

  renderVisibleLessons();
}

function handleWageToggleClick(event) {
  const button = event.target.closest("[data-wage-workplace-toggle]");
  if (!button) {
    return;
  }

  const workplaceName = button.dataset.wageWorkplaceToggle;
  if (!workplaceName) {
    return;
  }

  if (collapsedWageWorkplaces.has(workplaceName)) {
    collapsedWageWorkplaces.delete(workplaceName);
  } else {
    collapsedWageWorkplaces.add(workplaceName);
  }

  renderWageCalculation(wageLessons, settlements);
}

async function handleSettlementActionClick(event) {
  const button = event.target.closest("[data-settlement-action]");
  if (!button) {
    return;
  }

  const row = button.closest("[data-settlement-row]");
  const action = button.dataset.settlementAction;
  const settlementId = row?.dataset.settlementId || "";
  const workplaceName = row?.dataset.settlementWorkplace || "";

  try {
    if (action === "lock") {
      if (!window.confirm(`确认锁定 ${workplaceName} 的月度工资结算？当前调整额和备注会一并保存，锁定后关联实际课时不能再编辑。`)) {
        return;
      }
      await lockPartTimeWorkMonthlySettlement(readSettlementPayload(row, workplaceName));
      showMessage("success", `${workplaceName} 月度工资结算已锁定。`);
    } else if (action === "unlock") {
      if (!window.confirm(`确认撤销 ${workplaceName} 的月度工资结算锁定？锁定快照会被删除，调整额和备注将重新可编辑。`)) {
        return;
      }
      if (!window.confirm("再次确认撤销锁定？已生成收入记录的结算不能撤销。")) {
        return;
      }
      await unlockPartTimeWorkMonthlySettlement(settlementId);
      showMessage("success", `${workplaceName} 月度工资结算已撤销锁定。`);
    } else if (action === "request") {
      if (!window.confirm(`确认为 ${workplaceName} 生成 School 收入记录？Cash 请求需要到收入记录详情页提交。`)) {
        return;
      }
      await createPartTimeWorkIncomeRequest(settlementId);
      showMessage("success", `${workplaceName} 收入记录已生成。`);
    } else if (action === "export") {
      await handleSettlementExport(settlementId, workplaceName);
      return;
    }
    await loadPageData();
  } catch (error) {
    showMessage("error", `月度工资结算操作失败：${error.message || error}`);
  }
}

async function handleSettlementExport(settlementId, workplaceName) {
  if (!settlementId) {
    showMessage("error", "请先锁定月度工资结算后再导出。");
    return;
  }

  if (!window.XLSX?.utils?.aoa_to_sheet || !window.XLSX?.writeFile) {
    showMessage("error", "Excel 导出库尚未加载，请刷新页面后重试。");
    return;
  }

  try {
    const rows = await fetchPartTimeWorkSettlementExport(settlementId);
    if (!rows.length) {
      showMessage("error", `${workplaceName || "该打工先"} 没有可导出的锁定明细。`);
      return;
    }
    exportSettlementWorkbook(rows);
    showMessage("success", `${workplaceName || rows[0].workplace_name} 工资结算 Excel 已导出。`);
  } catch (error) {
    showMessage("error", `导出打工工资结算失败：${error.message || error}`);
  }
}

function exportSettlementWorkbook(rows) {
  const firstRow = rows[0] || {};
  const xlsx = window.XLSX;
  const workbook = xlsx.utils.book_new();
  const reportRows = buildSettlementExportRows(rows);
  const sheet = xlsx.utils.aoa_to_sheet(reportRows);

  sheet["!cols"] = [
    { wch: 12 },
    { wch: 12 },
    { wch: 10 },
    { wch: 10 },
    { wch: 16 },
    { wch: 14 },
    { wch: 28 },
    { wch: 12 },
    { wch: 10 },
    { wch: 12 },
    { wch: 12 },
    { wch: 14 },
    { wch: 12 },
    { wch: 12 },
    { wch: 14 },
    { wch: 28 },
  ];

  xlsx.utils.book_append_sheet(workbook, sheet, sanitizeSheetName(firstRow.workplace_name || "打工工资"));
  xlsx.writeFile(
    workbook,
    `part_time_work_${sanitizeFileName(firstRow.year_month || getYearMonthSelectValue(dom.yearFilter, dom.monthFilter))}_${sanitizeFileName(firstRow.workplace_name || "workplace")}.xlsx`,
    { bookType: "xlsx", cellStyles: true }
  );
}

function buildSettlementExportRows(rows) {
  return [
    [
      "年月",
      "日期",
      "开始时间",
      "结束时间",
      "打工先",
      "科目",
      "工作内容",
      "实际课时",
      "回数",
      "累计课时",
      "时给",
      "课时工资",
      "交通费",
      "调整额",
      "工资总额",
      "备注",
    ],
    ...rows.map((row) => [
      row.year_month || "",
      formatDateOnly(row.work_date),
      formatTimeInput(row.start_time),
      formatTimeInput(row.end_time),
      row.workplace_name || "",
      row.subject_name || "",
      row.class_description || "",
      Number(row.actual_hours || 0),
      Number(row.lesson_count || 1),
      Number(row.cumulative_hours || 0),
      Number(row.hourly_rate_jpy || 0),
      Number(row.lesson_wage_jpy || 0),
      Number(row.transportation_fee_jpy || 0),
      Number(row.adjustment_jpy || 0),
      Number(row.total_wage_jpy || 0),
      row.memo || "",
    ]),
  ];
}

function readSettlementPayload(row, workplaceName) {
  return {
    yearMonth: getYearMonthSelectValue(dom.yearFilter, dom.monthFilter),
    workplaceName,
    adjustmentJpy: parseInteger(row.querySelector('[data-settlement-input="adjustmentJpy"]')?.value),
    memo: row.querySelector('[data-settlement-input="memo"]')?.value.trim() || "",
  };
}

function handleSettlementInputChange(event) {
  const input = event.target.closest('[data-settlement-input="adjustmentJpy"]');
  if (!input) {
    return;
  }

  const row = input.closest("[data-settlement-row]");
  const totalElement = row?.querySelector("[data-settlement-total]");
  const summaryTotalElement = row?.querySelector("[data-settlement-total-summary]");
  const workplaceName = row?.dataset.settlementWorkplace || "";
  const settlement = settlements.find((item) => item.workplace_name === workplaceName);
  if (!row || !totalElement || !settlement || settlement.status !== "draft") {
    return;
  }

  const adjustmentJpy = parseInteger(input.value);
  if (!Number.isFinite(adjustmentJpy)) {
    totalElement.textContent = "-";
    if (summaryTotalElement) {
      summaryTotalElement.textContent = "-";
    }
    return;
  }

  const totalJpy = Number(settlement.lesson_wage_jpy || 0)
    + Number(settlement.transportation_fee_jpy || 0)
    + adjustmentJpy;
  totalElement.textContent = formatCurrency(totalJpy, "JPY");
  if (summaryTotalElement) {
    summaryTotalElement.textContent = formatCurrency(totalJpy, "JPY");
  }
}

function readDialogPayload() {
  return {
    workDate: dom.workDateInput.value,
    workplaceName: dom.workplaceNameInput.value,
    teacherName: DEFAULT_TEACHER_NAME,
    subjectName: dom.subjectNameInput.value,
    classDescription: dom.classDescriptionInput.value.trim(),
    startTime: dom.startTimeInput.value,
    endTime: dom.endTimeInput.value,
    hours: calculateHoursFromTimes(dom.startTimeInput.value, dom.endTimeInput.value),
    lessonCount: parseInteger(dom.lessonCountInput.value),
    cumulativeHours: parseDecimal(dom.cumulativeHoursInput.value),
    hourlyRateJpy: parseInteger(dom.hourlyRateInput.value),
    transportationFeeJpy: parseInteger(dom.transportationFeeInput.value),
    memo: dom.memoInput.value.trim(),
  };
}

function validatePayload(payload) {
  clearInvalidFields();

  if (!payload.workDate) {
    markFieldInvalid(dom.workDateInput);
    return "请选择日期。";
  }

  if (!payload.workplaceName) {
    markFieldInvalid(dom.workplaceNameInput);
    return "请选择打工先。";
  }

  if (!payload.subjectName) {
    markFieldInvalid(dom.subjectNameInput);
    return "请选择科目。";
  }

  if (!payload.startTime) {
    markFieldInvalid(dom.startTimeInput);
    return "请选择开始时间。";
  }

  if (!payload.endTime) {
    markFieldInvalid(dom.endTimeInput);
    return "请选择结束时间。";
  }

  if (!Number.isFinite(payload.hours) || payload.hours < 0) {
    markFieldInvalid(dom.endTimeInput);
    return "结束时间必须晚于开始时间。";
  }

  if (!Number.isInteger(payload.lessonCount) || payload.lessonCount < 1) {
    markFieldInvalid(dom.lessonCountInput);
    return "请输入大于等于 1 的整数回数。";
  }

  if (!Number.isFinite(payload.cumulativeHours) || payload.cumulativeHours < 0) {
    markFieldInvalid(dom.cumulativeHoursInput);
    return "请输入大于等于 0 的累计课时。";
  }

  if (!Number.isInteger(payload.hourlyRateJpy) || payload.hourlyRateJpy < 0) {
    markFieldInvalid(dom.hourlyRateInput);
    return "时给必须是大于等于 0 的整数。";
  }

  if (!Number.isInteger(payload.transportationFeeJpy) || payload.transportationFeeJpy < 0) {
    markFieldInvalid(dom.transportationFeeInput);
    return "交通费必须是大于等于 0 的整数。";
  }

  return "";
}

function updatePreview() {
  const payload = readDialogPayload();
  const hours = Number.isFinite(payload.hours) ? payload.hours : 0;
  const count = Number.isInteger(payload.lessonCount) && payload.lessonCount > 0 ? payload.lessonCount : 1;
  const cumulativeHourValue = Number.isFinite(payload.cumulativeHours) ? payload.cumulativeHours : 0;
  const hourlyRate = Number.isFinite(payload.hourlyRateJpy) ? payload.hourlyRateJpy : 0;
  const transportationFee = Number.isFinite(payload.transportationFeeJpy) ? payload.transportationFeeJpy : 0;
  const lessonWageJpy = Math.round(hours * hourlyRate);
  dom.hoursInput.value = Number.isFinite(payload.hours) ? formatHours(payload.hours) : "0";
  dom.preview.textContent = `预览：工资课时 ${formatHours(hours)} h / 回数 ${formatLessonCount(count)} / 累计课时 ${formatHours(cumulativeHourValue)} h / 课时工资 ${formatCurrency(lessonWageJpy, "JPY")} / 交通费 ${formatCurrency(transportationFee, "JPY")}`;
}

function clearDialog() {
  for (const input of [
    dom.workDateInput,
    dom.workplaceNameInput,
    dom.subjectNameInput,
    dom.classDescriptionInput,
    dom.startTimeInput,
    dom.endTimeInput,
    dom.hoursInput,
    dom.lessonCountInput,
    dom.cumulativeHoursInput,
    dom.hourlyRateInput,
    dom.transportationFeeInput,
    dom.memoInput,
  ]) {
    input.value = "";
  }
  dom.hoursInput.value = "0";
  dom.lessonCountInput.value = "1";
  dom.cumulativeHoursInput.value = "0";
  dom.startTimeInput.value = "";
  dom.endTimeInput.value = "";
  dom.hourlyRateInput.value = "0";
  dom.transportationFeeInput.value = "0";
  dom.workplaceNameInput.value = WORKPLACE_OPTIONS[0];
  dom.subjectNameInput.value = SUBJECT_OPTIONS[0];
  hideDialogError();
  clearInvalidFields();
}

function closeDialogAfterSubmit() {
  dom.dialog.classList.add("is-hidden");
  dom.dialog.setAttribute("aria-hidden", "true");
}

function setLessonFieldsReadonly(readonly) {
  for (const input of [dom.workplaceNameInput, dom.subjectNameInput, dom.classDescriptionInput]) {
    input.disabled = readonly;
  }
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
}

function setSubmitting(nextValue) {
  isSubmitting = nextValue;
  dom.submitButton.disabled = nextValue;
  dom.cancelButton.disabled = nextValue;
  dom.submitButton.textContent = nextValue ? "保存中..." : "保存";
}

function showMessage(type, text) {
  if (!text) {
    dom.messageArea.textContent = "";
    dom.messageArea.className = "message is-hidden";
    return;
  }

  dom.messageArea.textContent = text;
  dom.messageArea.className = `message message-${type}`;
}

function showDialogError(text) {
  dom.dialogError.textContent = text;
  dom.dialogError.classList.remove("is-hidden");
}

function hideDialogError() {
  dom.dialogError.textContent = "";
  dom.dialogError.classList.add("is-hidden");
}

function hideDialogErrorIfClean() {
  if (!dom.dialogError.textContent) {
    dom.dialogError.classList.add("is-hidden");
  }
}

function markFieldInvalid(input) {
  input?.closest(".field")?.classList.add("is-invalid");
}

function clearFieldInvalid(input) {
  input?.closest(".field")?.classList.remove("is-invalid");
}

function clearInvalidFields() {
  for (const input of [
    dom.workDateInput,
    dom.workplaceNameInput,
    dom.subjectNameInput,
    dom.startTimeInput,
    dom.endTimeInput,
    dom.hoursInput,
    dom.lessonCountInput,
    dom.cumulativeHoursInput,
    dom.hourlyRateInput,
    dom.transportationFeeInput,
  ]) {
    clearFieldInvalid(input);
  }
}

function renderOptionSelect(select, options, config = {}) {
  const optionHtml = [];
  if (config.includeAll) {
    optionHtml.push('<option value="">全部</option>');
  }
  optionHtml.push(...options.map((option) => (
    `<option value="${escapeAttribute(option)}" title="${escapeAttribute(option)}">${escapeHtml(option)}</option>`
  )));
  select.innerHTML = optionHtml.join("");
}

function setSelectValueWithFallback(select, value) {
  const normalized = safeText(value);
  if (normalized && !Array.from(select.options).some((option) => option.value === normalized)) {
    select.insertAdjacentHTML(
      "beforeend",
      `<option value="${escapeAttribute(normalized)}">${escapeHtml(normalized)}</option>`
    );
  }
  select.value = normalized || select.options[0]?.value || "";
}

function parseInteger(value) {
  if (value === "") {
    return 0;
  }
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? Math.round(numberValue) : Number.NaN;
}

function parseDecimal(value) {
  if (value === "") {
    return Number.NaN;
  }
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? Math.round(numberValue * 100) / 100 : Number.NaN;
}

function calculateHoursFromTimes(startTime, endTime) {
  if (!startTime || !endTime) {
    return Number.NaN;
  }

  const startMinutes = timeToMinutes(startTime);
  const endMinutes = timeToMinutes(endTime);
  if (!Number.isFinite(startMinutes) || !Number.isFinite(endMinutes) || endMinutes <= startMinutes) {
    return Number.NaN;
  }

  return Math.round(((endMinutes - startMinutes) / 60) * 100) / 100;
}

function lessonCount(row) {
  const count = Number(row?.lesson_count ?? 1);
  return Number.isInteger(count) && count >= 1 ? count : 1;
}

function cumulativeHours(row) {
  const value = Number(row?.cumulative_hours ?? 0);
  return Number.isFinite(value) && value >= 0 ? value : 0;
}

function timeToMinutes(value) {
  const match = String(value || "").match(/^(\d{2}):(\d{2})/);
  if (!match) {
    return Number.NaN;
  }
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  return hours * 60 + minutes;
}

function lessonKindLabel(kind) {
  return LESSON_KIND_LABELS[kind] || safeText(kind) || "-";
}

function lessonStatusLabel(row) {
  if (row.record_kind === "planned" && row.generated_actual_id) {
    return "已生成实际";
  }
  return lessonKindLabel(row.record_kind);
}

function lessonStatusClass(row) {
  if (row.record_kind === "actual") {
    return row.settlement_status === "locked" || row.settlement_status === "income_request_created"
      ? "status-paid"
      : "status-pending";
  }
  return row.generated_actual_id ? "status-neutral" : "status-pending";
}

function settlementStatusLabel(status) {
  return SETTLEMENT_STATUS_LABELS[status] || (status ? safeText(status) : "-");
}

function settlementStatusClass(status) {
  if (status === "income_request_created") return "status-paid";
  if (status === "locked") return "status-reversed";
  if (status === "draft") return "status-pending";
  return "status-neutral";
}

function incomeRequestStatusLabel(status) {
  return INCOME_REQUEST_STATUS_LABELS[status] || (status ? safeText(status) : "-");
}

function incomeRequestStatusClass(status) {
  if (status === "synced" || status === "received") return "status-paid";
  if (status === "pending" || status === "pending_cash_request" || status === "awaiting_cash_confirmation") return "status-reversed";
  if (status === "cash_rejected" || status === "failed" || status === "blocked") return "status-cancelled";
  return "status-neutral";
}

function formatHours(value) {
  const numberValue = Number(value || 0);
  if (!Number.isFinite(numberValue)) {
    return "0";
  }
  return numberValue.toLocaleString("zh-CN", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

function formatLessonCount(value) {
  return `${Number(value || 1).toLocaleString("zh-CN", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })} 回`;
}

function formatDateOnly(value) {
  if (!value) {
    return "-";
  }
  return String(value).slice(0, 10);
}

function formatTimeInput(value) {
  return value ? String(value).slice(0, 5) : "";
}

function timeRange(startTime, endTime) {
  const start = formatTimeInput(startTime);
  const end = formatTimeInput(endTime);
  if (!start && !end) {
    return "-";
  }
  return `${start || "-"}-${end || "-"}`;
}

function todayDate() {
  const now = new Date();
  const offset = now.getTimezoneOffset();
  const local = new Date(now.getTime() - offset * 60 * 1000);
  return local.toISOString().slice(0, 10);
}

function sanitizeSheetName(value) {
  const normalized = safeText(value).replace(/[:\\/?*[\]]/g, "").trim();
  return (normalized || "打工工资").slice(0, 31);
}

function sanitizeFileName(value) {
  return safeText(value).replace(/[\\/:*?"<>|]/g, "_").replace(/\s+/g, "_").trim() || "part_time_work";
}

function escapeHtml(value) {
  return safeText(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function escapeAttribute(value) {
  return escapeHtml(value);
}
