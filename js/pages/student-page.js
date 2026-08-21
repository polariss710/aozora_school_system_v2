import { hasSupabaseConfig } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";
import { isActiveAdmin } from "../auth.js?v=b5-20260807-1";
import {
  createStudentProfile,
  fetchBusinessEntitiesForStudents,
  fetchStudentFilterOptions,
  fetchStudents,
  updateStudentProfile,
} from "../api/student-api.js?v=b5-20260807-1";
import {
  correctStudentStatusEvent,
  fetchStudentStatusHistory,
  fetchStudentStatusManagement,
  previewStudentStatusCorrection,
  previewStudentStatusTransition,
  transitionStudentStatus,
} from "../api/student-status-api.js?v=b5-20260807-1";
import { formatDate, safeText } from "../utils/format.js";
import {
  requirePrimarySchoolBusinessEntityId,
} from "../utils/business-entity-policy.js?v=be-ui-20260806-1";

const DEFAULT_FILTERS = {
  keyword: "",
  status: "",
  courseTrack: "",
};

const STUDENT_STATUS_LABELS = {
  active: "在读",
  paused: "暂停",
  left: "离校",
};

const COURSE_TRACK_LABELS = {
  humanities: "文科",
  science: "理科",
};

const EDITABLE_COURSE_TRACK_OPTIONS = ["science", "humanities"];
const STUDENT_STATUS_FILTER_OPTIONS = ["active", "paused", "left"];
const STUDENT_FIELD_IDS = [
  "name",
  "courseTrack",
  "presetExchangeRate",
  "targetSchools",
];
const FILTER_RESET_MESSAGE = "已重置筛选条件；点击“查询”后刷新结果。";

const dom = {};
let businessEntities = [];
let students = [];
let activeFilters = null;
let resultRequestId = 0;
let editingStudent = null;
let isEditSubmitting = false;
let isCreateSubmitting = false;
let statusTransitionContext = null;
let statusHistoryContext = null;
let statusCorrectionContext = null;
let isStatusSubmitting = false;
let isCorrectionSubmitting = false;

export function initStudentPage() {
  cacheDom();
  setDefaultFilters();
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderStudents([]);
    return;
  }

  loadStudentData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#studentMessageArea");
  dom.filterForm = document.querySelector("#studentFilterForm");
  dom.keywordInput = document.querySelector("#studentKeywordInput");
  dom.statusSelect = document.querySelector("#studentStatusSelect");
  dom.courseTrackSelect = document.querySelector("#studentCourseTrackSelect");
  dom.resetButton = document.querySelector("#studentResetButton");
  dom.studentGrid = document.querySelector("#studentGrid");
  dom.studentLoadingState = document.querySelector("#studentLoadingState");
  dom.studentEmptyState = document.querySelector("#studentEmptyState");
  dom.studentCount = document.querySelector("#studentCount");
  dom.createButton = document.querySelector("#createStudentButton");

  dom.createDialog = document.querySelector("#createStudentProfileDialog");
  dom.createError = document.querySelector("#createStudentProfileError");
  dom.createNameInput = document.querySelector("#createStudentNameInput");
  dom.createCourseTrackSelect = document.querySelector("#createStudentCourseTrackSelect");
  dom.createPresetExchangeRateInput = document.querySelector("#createStudentPresetExchangeRateInput");
  dom.createWechatInput = document.querySelector("#createStudentWechatInput");
  dom.createPhoneInput = document.querySelector("#createStudentPhoneInput");
  dom.createEntranceDateInput = document.querySelector("#createStudentEntranceDateInput");
  dom.createTargetSchoolsInput = document.querySelector("#createStudentTargetSchoolsInput");
  dom.createNoteInput = document.querySelector("#createStudentNoteInput");
  dom.createCancelButton = document.querySelector("#createStudentCancelButton");
  dom.createSubmitButton = document.querySelector("#createStudentSubmitButton");

  dom.editDialog = document.querySelector("#editStudentProfileDialog");
  dom.editError = document.querySelector("#editStudentProfileError");
  dom.editNameInput = document.querySelector("#editStudentNameInput");
  dom.editCourseTrackSelect = document.querySelector("#editStudentCourseTrackSelect");
  dom.editPresetExchangeRateInput = document.querySelector("#editStudentPresetExchangeRateInput");
  dom.editWechatInput = document.querySelector("#editStudentWechatInput");
  dom.editPhoneInput = document.querySelector("#editStudentPhoneInput");
  dom.editEntranceDateInput = document.querySelector("#editStudentEntranceDateInput");
  dom.editTargetSchoolsInput = document.querySelector("#editStudentTargetSchoolsInput");
  dom.editNoteInput = document.querySelector("#editStudentNoteInput");
  dom.editCancelButton = document.querySelector("#editStudentCancelButton");
  dom.editSubmitButton = document.querySelector("#editStudentSubmitButton");

  dom.statusDialog = document.querySelector("#studentStatusTransitionDialog");
  dom.statusTitle = document.querySelector("#studentStatusTransitionTitle");
  dom.statusDescription = document.querySelector("#studentStatusTransitionDescription");
  dom.statusError = document.querySelector("#studentStatusTransitionError");
  dom.statusSummary = document.querySelector("#studentStatusTransitionSummary");
  dom.statusMonthLabel = document.querySelector("#studentStatusTransitionMonthLabel");
  dom.statusMonthInput = document.querySelector("#studentStatusTransitionMonthInput");
  dom.statusReasonInput = document.querySelector("#studentStatusTransitionReasonInput");
  dom.statusPreview = document.querySelector("#studentStatusTransitionPreview");
  dom.statusConfirmField = document.querySelector("#studentStatusTransitionConfirmField");
  dom.statusConfirmInput = document.querySelector("#studentStatusTransitionConfirmInput");
  dom.statusCancelButton = document.querySelector("#studentStatusTransitionCancelButton");
  dom.statusPreviewButton = document.querySelector("#studentStatusTransitionPreviewButton");
  dom.statusSubmitButton = document.querySelector("#studentStatusTransitionSubmitButton");

  dom.historyDialog = document.querySelector("#studentStatusHistoryDialog");
  dom.historySubtitle = document.querySelector("#studentStatusHistorySubtitle");
  dom.historyError = document.querySelector("#studentStatusHistoryError");
  dom.historyList = document.querySelector("#studentStatusHistoryList");
  dom.historyCloseButton = document.querySelector("#studentStatusHistoryCloseButton");

  dom.correctionDialog = document.querySelector("#studentStatusCorrectionDialog");
  dom.correctionError = document.querySelector("#studentStatusCorrectionError");
  dom.correctionOriginal = document.querySelector("#studentStatusCorrectionOriginal");
  dom.correctionMonthInput = document.querySelector("#studentStatusCorrectionMonthInput");
  dom.correctionStatusSelect = document.querySelector("#studentStatusCorrectionStatusSelect");
  dom.correctionReasonInput = document.querySelector("#studentStatusCorrectionReasonInput");
  dom.correctionAuditReasonInput = document.querySelector("#studentStatusCorrectionAuditReasonInput");
  dom.correctionPreview = document.querySelector("#studentStatusCorrectionPreview");
  dom.correctionConfirmField = document.querySelector("#studentStatusCorrectionConfirmField");
  dom.correctionConfirmInput = document.querySelector("#studentStatusCorrectionConfirmInput");
  dom.correctionCancelButton = document.querySelector("#studentStatusCorrectionCancelButton");
  dom.correctionPreviewButton = document.querySelector("#studentStatusCorrectionPreviewButton");
  dom.correctionSubmitButton = document.querySelector("#studentStatusCorrectionSubmitButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    loadStudentData();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    clearQueryResults();
    showMessage("info", FILTER_RESET_MESSAGE);
  });

  dom.createButton.addEventListener("click", openCreateDialog);
  dom.createCancelButton.addEventListener("click", closeCreateDialog);
  dom.createSubmitButton.addEventListener("click", submitCreateDialog);
  bindDialogFieldEvents("create");

  dom.studentGrid.addEventListener("click", (event) => {
    const editButton = event.target.closest("[data-edit-student-id]");
    if (editButton) {
      openEditDialog(editButton.dataset.editStudentId);
      return;
    }
    const historyButton = event.target.closest("[data-status-history-student-id]");
    if (historyButton) {
      openStatusHistoryDialog(historyButton.dataset.statusHistoryStudentId);
      return;
    }
    const actionButton = event.target.closest("[data-status-action-student-id]");
    if (actionButton) {
      openStatusTransitionDialog(
        actionButton.dataset.statusActionStudentId,
        actionButton.dataset.requestedStatus
      );
    }
  });

  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditDialog);
  bindDialogFieldEvents("edit");

  dom.statusCancelButton.addEventListener("click", closeStatusTransitionDialog);
  dom.statusPreviewButton.addEventListener("click", handleStatusTransitionPreview);
  dom.statusSubmitButton.addEventListener("click", handleStatusTransitionSubmit);
  dom.statusMonthInput.addEventListener("input", invalidateStatusTransitionPreview);
  dom.statusReasonInput.addEventListener("input", invalidateStatusTransitionPreview);
  dom.historyCloseButton.addEventListener("click", closeStatusHistoryDialog);
  dom.historyList.addEventListener("click", (event) => {
    const button = event.target.closest("[data-correct-status-event-id]");
    if (button) openStatusCorrectionDialog(button.dataset.correctStatusEventId);
  });
  dom.correctionCancelButton.addEventListener("click", closeStatusCorrectionDialog);
  dom.correctionPreviewButton.addEventListener("click", handleStatusCorrectionPreview);
  dom.correctionSubmitButton.addEventListener("click", handleStatusCorrectionSubmit);
  for (const input of [
    dom.correctionMonthInput,
    dom.correctionStatusSelect,
    dom.correctionReasonInput,
    dom.correctionAuditReasonInput,
  ]) {
    input.addEventListener("input", invalidateStatusCorrectionPreview);
    input.addEventListener("change", invalidateStatusCorrectionPreview);
  }
}

function bindDialogFieldEvents(scope) {
  const fields = scope === "create"
    ? [
        ["name", dom.createNameInput, "input"],
        ["courseTrack", dom.createCourseTrackSelect, "change"],
        ["presetExchangeRate", dom.createPresetExchangeRateInput, "input"],
        ["targetSchools", dom.createTargetSchoolsInput, "input"],
      ]
    : [
        ["name", dom.editNameInput, "input"],
        ["courseTrack", dom.editCourseTrackSelect, "change"],
        ["presetExchangeRate", dom.editPresetExchangeRateInput, "input"],
        ["targetSchools", dom.editTargetSchoolsInput, "input"],
      ];

  for (const [fieldId, element, eventName] of fields) {
    element.addEventListener(eventName, () => {
      if (scope === "create") {
        clearCreateFieldInvalid(fieldId);
        hideCreateErrorIfClean();
      } else {
        clearEditFieldInvalid(fieldId);
        hideEditErrorIfClean();
      }
    });
  }
}

function setDefaultFilters() {
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.courseTrackSelect.value = DEFAULT_FILTERS.courseTrack;
}

async function loadStudentData() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  const requestId = ++resultRequestId;
  setLoading(true);
  showMessage("info", "正在加载学生管理数据...");

  try {
    const [studentRows, filterRows, businessEntityRows, statusRows] = await Promise.all([
      fetchStudents(filters),
      fetchStudentFilterOptions(),
      fetchBusinessEntitiesForStudents(),
      fetchStudentStatusManagement(),
    ]);
    if (requestId !== resultRequestId) return;

    businessEntities = businessEntityRows;
    requirePrimarySchoolBusinessEntityId(businessEntities);
    renderStatusOptions(filterRows);
    renderCourseTrackOptions(filterRows);
    restoreFilterSelections(filters);
    const statusByStudentId = new Map(statusRows.map((row) => [row.student_id, row]));
    students = studentRows.map((student) => ({
      ...student,
      ...(statusByStudentId.get(student.id) || {}),
    }));
    activeFilters = { ...filters };
    renderStudents(filterStudents(students, filters));
    showMessage("success", "学生管理数据已加载。");
  } catch (error) {
    if (requestId !== resultRequestId) return;
    businessEntities = [];
    students = [];
    activeFilters = null;
    renderStatusOptions([]);
    renderCourseTrackOptions([]);
    renderStudents([]);
    showMessage("error", `读取学生管理数据失败：${error.message || error}`);
  } finally {
    if (requestId === resultRequestId) setLoading(false);
  }
}

function clearQueryResults() {
  resultRequestId += 1;
  activeFilters = null;
  students = [];

  if (!isEditSubmitting) closeEditDialog({ force: true });
  if (!isStatusSubmitting) closeStatusTransitionDialog({ force: true });
  closeStatusHistoryDialog();
  if (!isCorrectionSubmitting) closeStatusCorrectionDialog({ force: true });

  renderStudents([]);
  setLoading(false);
}

function readFilters() {
  return {
    keyword: dom.keywordInput.value.trim(),
    status: dom.statusSelect.value,
    courseTrack: dom.courseTrackSelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.keywordInput.value = filters.keyword;
  dom.statusSelect.value = filters.status;
  dom.courseTrackSelect.value = filters.courseTrack;
}

function renderStatusOptions(_rows) {
  const options = ['<option value="">全部</option>'];
  for (const status of STUDENT_STATUS_FILTER_OPTIONS) {
    options.push(
      `<option value="${escapeAttribute(status)}">${escapeHtml(studentStatusLabel(status))}</option>`
    );
  }
  dom.statusSelect.innerHTML = options.join("");
}

function renderCourseTrackOptions(rows) {
  const options = ['<option value="">全部</option>'];

  for (const courseTrack of distinctValues(rows, "course_track")) {
    options.push(
      `<option value="${escapeAttribute(courseTrack)}">${escapeHtml(courseTrackLabel(courseTrack))}</option>`
    );
  }

  dom.courseTrackSelect.innerHTML = options.join("");
}

function renderStudents(items) {
  dom.studentCount.textContent = `共 ${items.length} 名`;
  dom.studentEmptyState.classList.toggle("is-hidden", items.length > 0);

  if (!items.length) {
    dom.studentGrid.innerHTML = "";
    return;
  }

  dom.studentGrid.innerHTML = items.map((student) => `
    <article class="student-card">
      <div class="student-card-header">
        <div>
          <div class="student-name">${escapeHtml(studentName(student))}</div>
          <div class="student-code">${escapeHtml(student.student_code || shortId(student.id))}</div>
        </div>
        <span class="status-badge status-${escapeAttribute(student.resolved_status || "unset")}">
          ${escapeHtml(studentStatusLabel(student.resolved_status))}
        </span>
      </div>

      <div class="table-actions">
        <button class="button" type="button" data-edit-student-id="${escapeAttribute(student.id)}">编辑学生</button>
        <button class="button" type="button" data-status-history-student-id="${escapeAttribute(student.id)}">查看状态历史</button>
        ${statusActionButtons(student)}
      </div>

      <dl class="student-meta">
        <div>
          <dt>当前月份状态</dt>
          <dd>${escapeHtml(`${formatMonth(student.current_month)} · ${studentStatusLabel(student.resolved_status)}`)}</dd>
        </div>
        <div>
          <dt>状态来源</dt>
          <dd>${escapeHtml(student.is_fallback_active ? "无事件 fallback active" : `事件 · ${formatMonth(student.source_effective_month)}生效`)}</dd>
        </div>
        <div class="student-status-meta-wide">
          <dt>最近状态原因</dt>
          <dd>${escapeHtml(safeSummary(student.current_reason))}</dd>
        </div>
        <div>
          <dt>文理区分</dt>
          <dd>${escapeHtml(courseTrackLabel(student.course_track))}</dd>
        </div>
        <div>
          <dt>目标学校</dt>
          <dd>${escapeHtml(targetSchoolsDisplay(student.target_schools))}</dd>
        </div>
        <div>
          <dt>预设汇率</dt>
          <dd>${escapeHtml(displayValue(student.preset_exchange_rate))}</dd>
        </div>
        <div>
          <dt>微信</dt>
          <dd>${escapeHtml(displayValue(student.wechat))}</dd>
        </div>
        <div>
          <dt>电话</dt>
          <dd>${escapeHtml(displayValue(student.phone))}</dd>
        </div>
        <div>
          <dt>入学日期</dt>
          <dd>${escapeHtml(formatDateOnly(student.entrance_date))}</dd>
        </div>
        <div>
          <dt>备注</dt>
          <dd>${escapeHtml(displayValue(student.note))}</dd>
        </div>
        <div>
          <dt>更新时间</dt>
          <dd>${escapeHtml(formatDate(student.updated_at))}</dd>
        </div>
      </dl>
    </article>
  `).join("");
}

function statusActionButtons(student) {
  if (!isActiveAdmin() || student.has_future_event) return "";
  const id = escapeAttribute(student.id);
  if (student.resolved_status === "active") {
    return `
      <button class="button" type="button" data-status-action-student-id="${id}" data-requested-status="paused">设置暂停</button>
      <button class="button" type="button" data-status-action-student-id="${id}" data-requested-status="left">设置离校</button>`;
  }
  if (student.resolved_status === "paused") {
    return `
      <button class="button" type="button" data-status-action-student-id="${id}" data-requested-status="active">恢复上课</button>
      <button class="button" type="button" data-status-action-student-id="${id}" data-requested-status="left">设置离校</button>`;
  }
  if (student.resolved_status === "left") {
    return `<button class="button" type="button" data-status-action-student-id="${id}" data-requested-status="active">重新入学</button>`;
  }
  return "";
}

function openCreateDialog() {
  clearCreateErrors();
  setCreateSubmitting(false);
  dom.createNameInput.value = "";
  requirePrimarySchoolBusinessEntityId(businessEntities);
  renderCreateCourseTrackOptions("science");
  dom.createPresetExchangeRateInput.value = "0";
  dom.createWechatInput.value = "";
  dom.createPhoneInput.value = "";
  dom.createEntranceDateInput.value = "";
  dom.createTargetSchoolsInput.value = "";
  dom.createNoteInput.value = "";
  dom.createDialog.classList.remove("is-hidden");
  dom.createDialog.setAttribute("aria-hidden", "false");
  dom.createNameInput.focus();
}

function closeCreateDialog({ force = false } = {}) {
  if (isCreateSubmitting && !force) {
    return;
  }

  dom.createDialog.classList.add("is-hidden");
  dom.createDialog.setAttribute("aria-hidden", "true");
}

async function submitCreateDialog() {
  if (isCreateSubmitting) {
    return;
  }

  clearCreateErrors();

  const payload = readCreatePayload();
  const validation = validateStudentPayload(payload);
  if (validation) {
    showCreateError(validation.message, validation.fieldIds);
    return;
  }

  setCreateSubmitting(true);

  try {
    await createStudentProfile(payload);
    closeCreateDialog({ force: true });
    await reloadStudentDataPreservingViewport();
    showMessage("success", "学生已新增，可用于未来课时、筛选和结算默认值。");
  } catch (error) {
    showCreateError(error.message || String(error), studentFieldIdsForError(error));
  } finally {
    setCreateSubmitting(false);
  }
}

function readCreatePayload() {
  return {
    name: dom.createNameInput.value.trim(),
    defaultBusinessEntityId: requirePrimarySchoolBusinessEntityId(businessEntities),
    courseTrack: dom.createCourseTrackSelect.value,
    presetExchangeRate: readNonNegativeNumber(dom.createPresetExchangeRateInput.value),
    wechat: dom.createWechatInput.value.trim(),
    phone: dom.createPhoneInput.value.trim(),
    entranceDate: dom.createEntranceDateInput.value,
    targetSchools: normalizeTargetSchools(dom.createTargetSchoolsInput.value),
    note: dom.createNoteInput.value.trim(),
  };
}

function openEditDialog(studentId) {
  const student = students.find((item) => item.id === studentId);
  if (!student) {
    showMessage("error", "没有找到要编辑的学生。");
    return;
  }

  editingStudent = student;
  dom.editNameInput.value = student.name || student.display_name || "";
  renderEditCourseTrackOptions(student.course_track);
  dom.editPresetExchangeRateInput.value = displayNumberInput(student.preset_exchange_rate);
  dom.editWechatInput.value = student.wechat || "";
  dom.editPhoneInput.value = student.phone || "";
  dom.editEntranceDateInput.value = formatDateInput(student.entrance_date);
  dom.editTargetSchoolsInput.value = normalizeTargetSchools(student.target_schools);
  dom.editNoteInput.value = student.note || "";
  clearEditErrors();
  setEditSubmitting(false);
  dom.editDialog.classList.remove("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "false");
  dom.editNameInput.focus();
}

function closeEditDialog({ force = false } = {}) {
  if (isEditSubmitting && !force) {
    return;
  }

  editingStudent = null;
  dom.editDialog.classList.add("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "true");
}

async function submitEditDialog() {
  if (isEditSubmitting) {
    return;
  }

  clearEditErrors();

  if (!editingStudent) {
    showEditError("没有找到要编辑的学生。");
    return;
  }

  const payload = readEditPayload();
  const validation = validateStudentPayload(payload);
  if (validation) {
    showEditError(validation.message, validation.fieldIds);
    return;
  }

  setEditSubmitting(true);

  try {
    await updateStudentProfile(payload);
    closeEditDialog({ force: true });
    await reloadStudentDataPreservingViewport();
    showMessage("success", "学生资料已更新。");
  } catch (error) {
    showEditError(error.message || String(error), studentFieldIdsForError(error));
  } finally {
    setEditSubmitting(false);
  }
}

function readEditPayload() {
  return {
    studentId: editingStudent.id,
    name: dom.editNameInput.value.trim(),
    defaultBusinessEntityId: editingStudent.business_entity_id,
    courseTrack: dom.editCourseTrackSelect.value,
    presetExchangeRate: readNonNegativeNumber(dom.editPresetExchangeRateInput.value),
    wechat: dom.editWechatInput.value.trim(),
    phone: dom.editPhoneInput.value.trim(),
    entranceDate: dom.editEntranceDateInput.value,
    targetSchools: normalizeTargetSchools(dom.editTargetSchoolsInput.value),
    note: dom.editNoteInput.value.trim(),
    expectedUpdatedAt: editingStudent.updated_at,
  };
}

function validateStudentPayload(payload) {
  if (!payload.name) {
    return { message: "请输入学生姓名。", fieldIds: ["name"] };
  }

  if (payload.courseTrack && !EDITABLE_COURSE_TRACK_OPTIONS.includes(payload.courseTrack)) {
    return { message: "请选择有效文理区分。", fieldIds: ["courseTrack"] };
  }

  if (!Number.isFinite(payload.presetExchangeRate) || payload.presetExchangeRate < 0) {
    return { message: "预设汇率需为 0 或正数。", fieldIds: ["presetExchangeRate"] };
  }

  if (targetSchoolCount(payload.targetSchools) > 3) {
    return { message: "目标学校最多填写 3 个。", fieldIds: ["targetSchools"] };
  }

  return null;
}

function renderEditCourseTrackOptions(selectedCourseTrack) {
  dom.editCourseTrackSelect.innerHTML = courseTrackEditOptions();
  dom.editCourseTrackSelect.value = selectedCourseTrack || "";
}

function renderCreateCourseTrackOptions(selectedCourseTrack) {
  dom.createCourseTrackSelect.innerHTML = courseTrackEditOptions();
  dom.createCourseTrackSelect.value = selectedCourseTrack || "";
}

function courseTrackEditOptions() {
  return [
    '<option value="">未设置</option>',
    ...EDITABLE_COURSE_TRACK_OPTIONS.map((courseTrack) =>
      `<option value="${escapeAttribute(courseTrack)}">${escapeHtml(courseTrackLabel(courseTrack))}</option>`
    ),
  ].join("");
}

function showCreateError(message, fieldIds = []) {
  dom.createError.textContent = message;
  dom.createError.classList.remove("is-hidden");
  fieldIds.forEach(setCreateFieldInvalid);
  dom.createDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function clearCreateErrors() {
  dom.createError.textContent = "";
  dom.createError.classList.add("is-hidden");
  STUDENT_FIELD_IDS.forEach(clearCreateFieldInvalid);
}

function hideCreateErrorIfClean() {
  const hasInvalidField = document.querySelector("[data-create-student-field].is-invalid");
  if (!hasInvalidField) {
    dom.createError.textContent = "";
    dom.createError.classList.add("is-hidden");
  }
}

function setCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-student-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-student-field="${fieldId}"]`);
  field?.classList.remove("is-invalid");
}

function setCreateSubmitting(isSubmitting) {
  isCreateSubmitting = isSubmitting;
  dom.createSubmitButton.disabled = isSubmitting;
  dom.createCancelButton.disabled = isSubmitting;
  dom.createSubmitButton.textContent = isSubmitting ? "新增中..." : "新增";
}

function showEditError(message, fieldIds = []) {
  dom.editError.textContent = message;
  dom.editError.classList.remove("is-hidden");
  fieldIds.forEach(setEditFieldInvalid);
  dom.editDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function clearEditErrors() {
  dom.editError.textContent = "";
  dom.editError.classList.add("is-hidden");
  STUDENT_FIELD_IDS.forEach(clearEditFieldInvalid);
}

function hideEditErrorIfClean() {
  const hasInvalidField = document.querySelector("[data-edit-student-field].is-invalid");
  if (!hasInvalidField) {
    dom.editError.textContent = "";
    dom.editError.classList.add("is-hidden");
  }
}

function setEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-student-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-student-field="${fieldId}"]`);
  field?.classList.remove("is-invalid");
}

function setEditSubmitting(isSubmitting) {
  isEditSubmitting = isSubmitting;
  dom.editSubmitButton.disabled = isSubmitting;
  dom.editCancelButton.disabled = isSubmitting;
  dom.editSubmitButton.textContent = isSubmitting ? "保存中..." : "保存";
}

function studentFieldIdsForError(error) {
  const message = error?.message || String(error || "");
  if (message.includes("姓名")) return ["name"];
  if (message.includes("文理")) return ["courseTrack"];
  if (message.includes("预设汇率")) return ["presetExchangeRate"];
  if (message.includes("目标学校")) return ["targetSchools"];
  return [];
}

function openStatusTransitionDialog(studentId, requestedStatus) {
  if (!isActiveAdmin()) {
    showMessage("error", "仅已启用的管理员可以变更学生月份状态。");
    return;
  }
  const student = students.find((item) => item.id === studentId);
  const contract = transitionDialogContract(student?.resolved_status, requestedStatus);
  if (!student || !contract) {
    showMessage("error", "当前状态不允许执行该操作，请刷新后重试。");
    return;
  }

  statusTransitionContext = { student, requestedStatus, preview: null };
  dom.statusTitle.textContent = `${contract.title}：${studentName(student)}`;
  dom.statusDescription.textContent = contract.description;
  dom.statusMonthLabel.textContent = contract.monthLabel;
  dom.statusMonthInput.value = formatMonth(student.current_month);
  dom.statusReasonInput.value = "";
  dom.statusSummary.innerHTML = summaryRows([
    ["当前状态", studentStatusLabel(student.resolved_status)],
    ["当前权威月份", formatMonth(student.current_month)],
    ["状态来源", student.is_fallback_active ? "无事件 fallback active" : `事件 ${formatMonth(student.source_effective_month)}`],
  ]);
  clearStatusTransitionError();
  invalidateStatusTransitionPreview();
  setStatusSubmitting(false);
  openDialog(dom.statusDialog);
  dom.statusMonthInput.focus();
}

function transitionDialogContract(currentStatus, requestedStatus) {
  if (currentStatus === "active" && requestedStatus === "paused") {
    return {
      title: "设置暂停",
      monthLabel: "最后在读月份",
      description: "该学生在所选月份仍会显示，从下个月开始暂停。",
    };
  }
  if (currentStatus === "active" && requestedStatus === "left") {
    return {
      title: "设置离校",
      monthLabel: "最后在读月份",
      description: "该学生在所选月份仍会显示，从下个月开始离校。",
    };
  }
  if (currentStatus === "paused" && requestedStatus === "active") {
    return {
      title: "恢复上课",
      monthLabel: "恢复月份",
      description: "该学生从所选月份开始重新作为在读学生显示。",
    };
  }
  if (currentStatus === "paused" && requestedStatus === "left") {
    return {
      title: "暂停后设置离校",
      monthLabel: "离校生效月份",
      description: "该学生从所选月份起标记为离校，之前的暂停历史保持不变。",
    };
  }
  if (currentStatus === "left" && requestedStatus === "active") {
    return {
      title: "重新入学",
      monthLabel: "重新入学月份",
      description: "历史离校记录保持不变，该学生从所选月份重新作为在读学生显示。",
    };
  }
  return null;
}

async function handleStatusTransitionPreview() {
  if (!statusTransitionContext || isStatusSubmitting) return;
  const inputMonth = dom.statusMonthInput.value;
  const reason = dom.statusReasonInput.value.trim();
  if (!inputMonth || !reason) {
    showStatusTransitionError("请选择月份并填写原因。DB预览不会接受空原因的最终提交。");
    return;
  }
  setStatusSubmitting(true, "preview");
  clearStatusTransitionError();
  try {
    const preview = await previewStudentStatusTransition({
      studentId: statusTransitionContext.student.id,
      requestedStatus: statusTransitionContext.requestedStatus,
      inputMonth,
      expectedCurrentEventId: statusTransitionContext.student.latest_event_id,
    });
    statusTransitionContext.preview = preview;
    dom.statusPreview.innerHTML = `<strong>数据库预览</strong><span>生效月份：${escapeHtml(formatMonth(preview.effective_month))}</span><span>状态：${escapeHtml(studentStatusLabel(preview.requested_status))}</span>`;
    dom.statusPreview.classList.remove("is-hidden");
    dom.statusConfirmField.classList.remove("is-hidden");
    dom.statusSubmitButton.classList.remove("is-hidden");
    dom.statusConfirmInput.checked = false;
  } catch (error) {
    showStatusTransitionError(statusErrorMessage(error));
  } finally {
    setStatusSubmitting(false);
  }
}

async function handleStatusTransitionSubmit() {
  if (!statusTransitionContext?.preview || isStatusSubmitting) return;
  if (!dom.statusConfirmInput.checked) {
    showStatusTransitionError("请先勾选确认项。");
    return;
  }
  setStatusSubmitting(true, "submit");
  clearStatusTransitionError();
  try {
    await transitionStudentStatus({
      studentId: statusTransitionContext.student.id,
      requestedStatus: statusTransitionContext.requestedStatus,
      inputMonth: dom.statusMonthInput.value,
      reason: dom.statusReasonInput.value.trim(),
      expectedCurrentEventId: statusTransitionContext.student.latest_event_id,
    });
    closeStatusTransitionDialog({ force: true });
    await reloadStudentDataPreservingViewport();
    showMessage("success", "学生月份状态已更新，当前状态与候选已重新读取。");
  } catch (error) {
    showStatusTransitionError(statusErrorMessage(error));
  } finally {
    setStatusSubmitting(false);
  }
}

function invalidateStatusTransitionPreview() {
  if (statusTransitionContext) statusTransitionContext.preview = null;
  dom.statusPreview.textContent = "";
  dom.statusPreview.classList.add("is-hidden");
  dom.statusConfirmField.classList.add("is-hidden");
  dom.statusSubmitButton.classList.add("is-hidden");
  dom.statusConfirmInput.checked = false;
}

function closeStatusTransitionDialog({ force = false } = {}) {
  if (isStatusSubmitting && !force) return;
  closeDialog(dom.statusDialog);
  statusTransitionContext = null;
}

function setStatusSubmitting(isSubmitting, action = "") {
  isStatusSubmitting = isSubmitting;
  dom.statusCancelButton.disabled = isSubmitting;
  dom.statusPreviewButton.disabled = isSubmitting;
  dom.statusSubmitButton.disabled = isSubmitting;
  dom.statusPreviewButton.textContent = isSubmitting && action === "preview" ? "预览中..." : "预览生效月份";
  dom.statusSubmitButton.textContent = isSubmitting && action === "submit" ? "提交中..." : "确认变更";
}

async function openStatusHistoryDialog(studentId) {
  const student = students.find((item) => item.id === studentId);
  if (!student) return;
  statusHistoryContext = { student, rows: [] };
  dom.historySubtitle.textContent = `${studentName(student)} · 当前 ${studentStatusLabel(student.resolved_status)} · ${formatMonth(student.current_month)}`;
  dom.historyError.classList.add("is-hidden");
  dom.historyList.innerHTML = '<div class="state-text">正在读取状态历史...</div>';
  openDialog(dom.historyDialog);
  try {
    const rows = await fetchStudentStatusHistory(student.id);
    if (!statusHistoryContext || statusHistoryContext.student.id !== student.id) return;
    statusHistoryContext.rows = rows;
    renderStatusHistory(rows, student);
  } catch (error) {
    dom.historyError.textContent = statusErrorMessage(error);
    dom.historyError.classList.remove("is-hidden");
    dom.historyList.innerHTML = "";
  }
}

function renderStatusHistory(rows, student) {
  if (!rows.length) {
    dom.historyList.innerHTML = '<div class="state-text">尚无状态事件；当前由fallback active解析为在读。</div>';
    return;
  }
  dom.historyList.innerHTML = rows.map((row) => `
    <article class="student-status-history-item ${row.is_voided ? "is-voided" : ""}">
      <div class="student-status-history-heading">
        <strong>${escapeHtml(formatMonth(row.effective_month))} · ${escapeHtml(studentStatusLabel(row.status))}</strong>
        <span class="status-badge ${row.is_voided ? "status-left" : `status-${escapeAttribute(row.status)}`}">${row.is_voided ? "已作废" : "有效"}</span>
      </div>
      <dl class="student-status-history-meta">
        <div><dt>原因</dt><dd>${escapeHtml(row.reason || "未设置")}</dd></div>
        <div><dt>操作人</dt><dd>${escapeHtml(row.created_actor || "未设置")}</dd></div>
        <div><dt>创建时间</dt><dd>${escapeHtml(formatDate(row.created_at))}</dd></div>
        <div><dt>replacement</dt><dd>${escapeHtml(row.replacement_event_id ? shortId(row.replacement_event_id) : "无")}</dd></div>
        ${row.is_voided ? `<div><dt>更正原因</dt><dd>${escapeHtml(row.correction_reason || "未设置")}</dd></div><div><dt>作废时间</dt><dd>${escapeHtml(formatDate(row.voided_at))}</dd></div>` : ""}
      </dl>
      ${isActiveAdmin() && !row.is_voided ? `<div class="table-actions"><button class="button" type="button" data-correct-status-event-id="${escapeAttribute(row.event_id)}">更正此事件</button></div>` : ""}
    </article>
  `).join("");
  dom.historySubtitle.textContent = `${studentName(student)} · 共 ${rows.length} 条（含已作废历史）`;
}

function closeStatusHistoryDialog() {
  closeDialog(dom.historyDialog);
  statusHistoryContext = null;
}

function openStatusCorrectionDialog(eventId) {
  if (!isActiveAdmin() || !statusHistoryContext) return;
  const eventRow = statusHistoryContext.rows.find((row) => row.event_id === eventId && !row.is_voided);
  if (!eventRow) {
    dom.historyError.textContent = "原事件已变化，请关闭历史弹窗后重新读取。";
    dom.historyError.classList.remove("is-hidden");
    return;
  }
  statusCorrectionContext = {
    student: statusHistoryContext.student,
    event: eventRow,
    preview: null,
  };
  dom.correctionOriginal.innerHTML = summaryRows([
    ["原生效月份", formatMonth(eventRow.effective_month)],
    ["原状态", studentStatusLabel(eventRow.status)],
    ["原原因", eventRow.reason || "未设置"],
    ["原操作人", eventRow.created_actor || "未设置"],
  ]);
  dom.correctionMonthInput.value = formatMonth(eventRow.effective_month);
  dom.correctionStatusSelect.value = eventRow.status;
  dom.correctionReasonInput.value = eventRow.reason || "";
  dom.correctionAuditReasonInput.value = "";
  clearStatusCorrectionError();
  invalidateStatusCorrectionPreview();
  setCorrectionSubmitting(false);
  openDialog(dom.correctionDialog);
}

async function handleStatusCorrectionPreview() {
  if (!statusCorrectionContext || isCorrectionSubmitting) return;
  if (!dom.correctionMonthInput.value || !dom.correctionReasonInput.value.trim() || !dom.correctionAuditReasonInput.value.trim()) {
    showStatusCorrectionError("请填写更正月份、状态原因和更正原因。");
    return;
  }
  setCorrectionSubmitting(true, "preview");
  clearStatusCorrectionError();
  try {
    const preview = await previewStudentStatusCorrection({
      eventId: statusCorrectionContext.event.event_id,
      expectedRowVersion: statusCorrectionContext.event.row_version,
      expectedCurrentEventId: statusCorrectionContext.student.latest_event_id,
      replacementMonth: dom.correctionMonthInput.value,
      replacementStatus: dom.correctionStatusSelect.value,
    });
    statusCorrectionContext.preview = preview;
    dom.correctionPreview.innerHTML = `<strong>数据库时间线预览</strong><span>${escapeHtml(formatMonth(preview.original_effective_month))} ${escapeHtml(studentStatusLabel(preview.original_status))} → ${escapeHtml(formatMonth(preview.replacement_effective_month))} ${escapeHtml(studentStatusLabel(preview.replacement_status))}</span><span>影响范围：${escapeHtml(formatMonth(preview.affected_start_month))} ～ ${escapeHtml(preview.affected_end_month ? formatMonth(preview.affected_end_month) : "后续事件之前")}</span>`;
    dom.correctionPreview.classList.remove("is-hidden");
    dom.correctionConfirmField.classList.remove("is-hidden");
    dom.correctionSubmitButton.classList.remove("is-hidden");
    dom.correctionConfirmInput.checked = false;
  } catch (error) {
    showStatusCorrectionError(statusErrorMessage(error));
  } finally {
    setCorrectionSubmitting(false);
  }
}

async function handleStatusCorrectionSubmit() {
  if (!statusCorrectionContext?.preview || isCorrectionSubmitting) return;
  if (!dom.correctionConfirmInput.checked) {
    showStatusCorrectionError("请先勾选确认项。");
    return;
  }
  setCorrectionSubmitting(true, "submit");
  clearStatusCorrectionError();
  try {
    await correctStudentStatusEvent({
      eventId: statusCorrectionContext.event.event_id,
      expectedRowVersion: statusCorrectionContext.event.row_version,
      expectedCurrentEventId: statusCorrectionContext.student.latest_event_id,
      replacementMonth: dom.correctionMonthInput.value,
      replacementStatus: dom.correctionStatusSelect.value,
      replacementReason: dom.correctionReasonInput.value.trim(),
      correctionReason: dom.correctionAuditReasonInput.value.trim(),
    });
    const studentId = statusCorrectionContext.student.id;
    closeStatusCorrectionDialog({ force: true });
    closeStatusHistoryDialog();
    await reloadStudentDataPreservingViewport();
    await openStatusHistoryDialog(studentId);
    showMessage("success", "状态历史已原子更正，原事件继续保留为已作废记录。");
  } catch (error) {
    showStatusCorrectionError(statusErrorMessage(error));
  } finally {
    setCorrectionSubmitting(false);
  }
}

function invalidateStatusCorrectionPreview() {
  if (statusCorrectionContext) statusCorrectionContext.preview = null;
  dom.correctionPreview.textContent = "";
  dom.correctionPreview.classList.add("is-hidden");
  dom.correctionConfirmField.classList.add("is-hidden");
  dom.correctionSubmitButton.classList.add("is-hidden");
  dom.correctionConfirmInput.checked = false;
}

function closeStatusCorrectionDialog({ force = false } = {}) {
  if (isCorrectionSubmitting && !force) return;
  closeDialog(dom.correctionDialog);
  statusCorrectionContext = null;
}

function setCorrectionSubmitting(isSubmitting, action = "") {
  isCorrectionSubmitting = isSubmitting;
  dom.correctionCancelButton.disabled = isSubmitting;
  dom.correctionPreviewButton.disabled = isSubmitting;
  dom.correctionSubmitButton.disabled = isSubmitting;
  dom.correctionPreviewButton.textContent = isSubmitting && action === "preview" ? "预览中..." : "预览更正时间线";
  dom.correctionSubmitButton.textContent = isSubmitting && action === "submit" ? "提交中..." : "确认更正";
}

function showStatusTransitionError(message) {
  dom.statusError.textContent = message;
  dom.statusError.classList.remove("is-hidden");
}

function clearStatusTransitionError() {
  dom.statusError.textContent = "";
  dom.statusError.classList.add("is-hidden");
}

function showStatusCorrectionError(message) {
  dom.correctionError.textContent = message;
  dom.correctionError.classList.remove("is-hidden");
}

function clearStatusCorrectionError() {
  dom.correctionError.textContent = "";
  dom.correctionError.classList.add("is-hidden");
}

function statusErrorMessage(error) {
  const message = error?.message || String(error || "状态操作失败。");
  const translations = [
    ["STUDENT_STATUS_EXPECTED_CURRENT_EVENT_MISMATCH", "状态时间线已被其他操作更新，请刷新后重试。"],
    ["STUDENT_STATUS_EVENT_VERSION_MISMATCH", "原事件已被更正，请重新读取历史。"],
    ["STUDENT_STATUS_REDUNDANT_STATE_EVENT", "所选操作不会产生实际状态变化。"],
    ["STUDENT_STATUS_TRANSITION_OUT_OF_ORDER", "所选月份早于或等于最新状态事件，请改用历史更正。"],
    ["STUDENT_STATUS_FUTURE_EVENT_REQUIRES_CORRECTION", "已有未来生效事件，请先查看并更正该时间线。"],
    ["STUDENT_STATUS_ACTIVE_EVENT_MONTH_EXISTS", "同一生效月份已存在有效状态事件。"],
    ["STUDENT_STATUS_TRANSITION_FORBIDDEN", "当前状态不允许执行该转换。"],
    ["STUDENT_STATUS_CORRECTION_SEQUENCE_INVALID", "更正后的状态时间线不合法。"],
    ["STUDENT_STATUS_REASON_INVALID", "原因不能为空，且最多1000字。"],
  ];
  return translations.find(([code]) => message.includes(code))?.[1] || message;
}

function summaryRows(rows) {
  return rows.map(([label, value]) => `<div class="dialog-summary-row"><span class="dialog-summary-label">${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`).join("");
}

function openDialog(element) {
  element.classList.remove("is-hidden");
  element.setAttribute("aria-hidden", "false");
}

function closeDialog(element) {
  element.classList.add("is-hidden");
  element.setAttribute("aria-hidden", "true");
}

async function reloadStudentDataPreservingViewport() {
  const scrollX = window.scrollX;
  const scrollY = window.scrollY;
  await loadStudentData();
  window.scrollTo(scrollX, scrollY);
}

function filterStudents(items, filters) {
  const normalizedKeyword = filters.keyword.toLowerCase();
  return items.filter((student) => {
    if (filters.status && student.resolved_status !== filters.status) return false;
    if (!normalizedKeyword) return true;
    return (
    [
      student.student_code,
      student.name,
      student.display_name,
      student.wechat,
      student.phone,
      student.note,
      student.target_schools,
    ]
      .map((value) => safeText(value).toLowerCase())
      .some((value) => value.includes(normalizedKeyword))
    );
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

function studentName(student) {
  return student.name || student.display_name || "未命名学生";
}

function studentStatusLabel(status) {
  if (!status) {
    return "未设置";
  }

  return STUDENT_STATUS_LABELS[status] || safeText(status);
}

function courseTrackLabel(courseTrack) {
  if (!courseTrack) {
    return "未设置";
  }

  return COURSE_TRACK_LABELS[courseTrack] || safeText(courseTrack);
}

function normalizeTargetSchools(value) {
  return safeText(value)
    .split(/\r?\n/)
    .map((item) => item.trim())
    .filter(Boolean)
    .join("\n");
}

function targetSchoolCount(value) {
  if (!value) {
    return 0;
  }

  return normalizeTargetSchools(value).split("\n").filter(Boolean).length;
}

function targetSchoolsDisplay(value) {
  const normalized = normalizeTargetSchools(value);
  return normalized ? normalized.replaceAll("\n", "、") : "未设置";
}

function readNonNegativeNumber(value) {
  const text = safeText(value).trim();
  if (!text) {
    return 0;
  }

  return Number(text);
}

function displayNumberInput(value) {
  const text = safeText(value);
  return text || "0";
}

function formatDateInput(value) {
  const text = safeText(value);
  return text ? text.slice(0, 10) : "";
}

function formatDateOnly(value) {
  const text = formatDateInput(value);
  return text || "未设置";
}

function formatMonth(value) {
  const text = safeText(value);
  return /^\d{4}-\d{2}/.test(text) ? text.slice(0, 7) : "未设置";
}

function safeSummary(value) {
  const text = safeText(value).trim();
  if (!text) return "无事件原因";
  return text.length > 80 ? `${text.slice(0, 80)}…` : text;
}

function displayValue(value) {
  return safeText(value) || "未设置";
}

function shortId(id) {
  return id ? `${String(id).slice(0, 8)}...` : "未设置";
}

function setLoading(isLoading) {
  dom.studentLoadingState.classList.toggle("is-hidden", !isLoading);
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
