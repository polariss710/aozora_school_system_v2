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
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
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
  income_request_created: "已生成收入请求",
};

const INCOME_REQUEST_STATUS_LABELS = {
  pending_cash_request: "待生成 Cash 请求",
  awaiting_cash_confirmation: "Cash 待确认",
  synced: "已同步",
  cash_rejected: "Cash 已拒绝",
  failed: "失败",
  blocked: "阻塞",
};

const dom = {};
let lessons = [];
let settlements = [];
let editingLesson = null;
let dialogMode = DIALOG_MODES.CREATE_PLANNED;
let isSubmitting = false;
const expandedWorkplaces = new Set();

export async function initPartTimeWorkPage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  renderOptionSelect(dom.workplaceFilter, WORKPLACE_OPTIONS, { includeAll: true });
  renderOptionSelect(dom.workplaceNameInput, WORKPLACE_OPTIONS);
  renderOptionSelect(dom.subjectNameInput, SUBJECT_OPTIONS);
  bindEvents();
  renderLessons([]);
  renderSettlements([]);

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
  dom.resetButton = document.querySelector("#partTimeWorkResetButton");
  dom.openCreateButton = document.querySelector("#openPartTimeWorkCreateButton");
  dom.lessonColumns = document.querySelector("#partTimeWorkLessonColumns");
  dom.estimatedLessonWage = document.querySelector("#partTimeWorkEstimatedLessonWage");
  dom.estimatedTransportationFee = document.querySelector("#partTimeWorkEstimatedTransportationFee");
  dom.estimatedTotal = document.querySelector("#partTimeWorkEstimatedTotal");
  dom.settlementTableBody = document.querySelector("#partTimeWorkSettlementTableBody");
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
    loadPageData();
  });

  dom.resetButton.addEventListener("click", () => {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
    dom.workplaceFilter.value = "";
    loadPageData();
  });

  dom.openCreateButton.addEventListener("click", openCreatePlannedDialog);
  dom.cancelButton.addEventListener("click", closeDialog);
  dom.submitButton.addEventListener("click", submitDialog);
  dom.lessonColumns.addEventListener("click", handleWorkplaceToggleClick);
  dom.lessonColumns.addEventListener("click", handleLessonActionClick);
  dom.settlementTableBody.addEventListener("click", handleSettlementActionClick);

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

async function loadPageData() {
  if (!isLoggedIn()) {
    renderLessons([]);
    renderSettlements([]);
    showMessage("error", "请先登录后查看或编辑私塾打工记录。");
    return;
  }

  const filters = readFilters();
  setLoading(true);
  showMessage("", "");

  try {
    const [lessonRows, settlementRows] = await Promise.all([
      fetchPartTimeWorkLessons(filters),
      fetchPartTimeWorkMonthlySettlements({ yearMonth: filters.yearMonth }),
    ]);
    lessons = lessonRows || [];
    settlements = settlementRows || [];
    renderLessons(lessons);
    renderSettlements(settlements);
  } catch (error) {
    lessons = [];
    settlements = [];
    renderLessons([]);
    renderSettlements([]);
    showMessage("error", `私塾打工数据读取失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readFilters() {
  return {
    yearMonth: getYearMonthSelectValue(dom.yearFilter, dom.monthFilter),
    workplaceName: dom.workplaceFilter.value,
  };
}

function renderLessons(rows) {
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);
  dom.lessonColumns.innerHTML = renderWorkflowColumns(rows);
  renderEstimatedSummary(rows);
}

function renderEstimatedSummary(rows) {
  const plannedRows = rows.filter((row) => row.record_kind === "planned");
  const lessonWageJpy = plannedRows.reduce((sum, row) => (
    sum + Math.round(Number(row.planned_hours || 0) * Number(row.hourly_rate_jpy || 0))
  ), 0);
  const transportationFeeJpy = plannedRows.reduce((sum, row) => (
    sum + Number(row.transportation_fee_jpy || 0)
  ), 0);

  dom.estimatedLessonWage.textContent = formatCurrency(lessonWageJpy, "JPY");
  dom.estimatedTransportationFee.textContent = formatCurrency(transportationFeeJpy, "JPY");
  dom.estimatedTotal.textContent = formatCurrency(lessonWageJpy + transportationFeeJpy, "JPY");
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

function renderSettlements(rows) {
  dom.settlementTableBody.innerHTML = rows.map(renderSettlementRow).join("");
}

function renderSettlementRow(row) {
  const isLocked = row.status === "locked" || row.status === "income_request_created";
  const isDraft = row.status === "draft";
  const canLock = row.status === "draft" && Number(row.actual_lesson_count || 0) > 0;
  const canUnlock = row.status === "locked" && !row.income_request_id;
  const canCreateRequest = row.status === "locked" && !row.income_request_id;
  const canExport = Boolean(row.id) && isLocked;
  const saveDisabled = isLocked ? "disabled" : "";

  return `
    <tr data-settlement-workplace="${escapeAttribute(row.workplace_name)}" data-settlement-id="${escapeAttribute(row.id || "")}">
      <td>${escapeHtml(row.workplace_name || "-")}</td>
      <td class="number-cell">${escapeHtml(formatHours(row.actual_hours_total))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(row.lesson_wage_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(row.transportation_fee_jpy, "JPY"))}</td>
      <td class="number-cell">
        <input class="inline-number-input" data-settlement-input="adjustmentJpy" type="number" step="1" value="${escapeAttribute(row.adjustment_jpy ?? 0)}" ${saveDisabled}>
      </td>
      <td class="number-cell">${escapeHtml(formatCurrency(row.total_wage_jpy, "JPY"))}</td>
      <td><span class="status-badge ${escapeAttribute(settlementStatusClass(row.status))}">${escapeHtml(settlementStatusLabel(row.status))}</span></td>
      <td>${escapeHtml(incomeRequestStatusLabel(row.income_request_status))}</td>
      <td>
        <input class="inline-text-input" data-settlement-input="memo" type="text" value="${escapeAttribute(row.memo || "")}" ${saveDisabled}>
      </td>
      <td class="action-cell">
        <div class="action-buttons">
          ${isDraft ? `<button class="button table-action-button" type="button" data-settlement-action="lock" ${canLock ? "" : "disabled"}>锁定结算</button>` : ""}
          ${canUnlock ? `<button class="button table-action-button" type="button" data-settlement-action="unlock">撤销锁定</button>` : ""}
          ${canExport ? `<button class="button table-action-button" type="button" data-settlement-action="export">导出 Excel</button>` : ""}
          ${canCreateRequest ? `<button class="button table-action-button" type="button" data-settlement-action="request">生成收入请求</button>` : ""}
        </div>
      </td>
    </tr>
  `;
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

  renderLessons(lessons);
}

async function handleSettlementActionClick(event) {
  const button = event.target.closest("[data-settlement-action]");
  if (!button) {
    return;
  }

  const row = button.closest("tr");
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
      if (!window.confirm("再次确认撤销锁定？已生成收入请求的结算不能撤销。")) {
        return;
      }
      await unlockPartTimeWorkMonthlySettlement(settlementId);
      showMessage("success", `${workplaceName} 月度工资结算已撤销锁定。`);
    } else if (action === "request") {
      if (!window.confirm(`确认为 ${workplaceName} 生成 School 侧收入请求？本轮不会写入 Cash。`)) {
        return;
      }
      await createPartTimeWorkIncomeRequest(settlementId);
      showMessage("success", `${workplaceName} 收入请求已生成。`);
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
    { wch: 16 },
    { wch: 12 },
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
      "打工先",
      "日期",
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
      row.workplace_name || "",
      formatDateOnly(row.work_date),
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
    `<option value="${escapeAttribute(option)}">${escapeHtml(option)}</option>`
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
  if (status === "locked" || status === "income_request_created") return "status-paid";
  if (status === "draft") return "status-pending";
  return "status-neutral";
}

function incomeRequestStatusLabel(status) {
  return INCOME_REQUEST_STATUS_LABELS[status] || (status ? safeText(status) : "-");
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
