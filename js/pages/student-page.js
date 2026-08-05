import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createStudentProfile,
  fetchBusinessEntitiesForStudents,
  fetchStudentFilterOptions,
  fetchStudents,
  updateStudentProfile,
} from "../api/student-api.js";
import { formatDate, safeText } from "../utils/format.js";
import {
  defaultNewBusinessEntityId,
  historicalEditBusinessEntities,
  newBusinessEntities,
} from "../utils/business-entity-policy.js";

const DEFAULT_FILTERS = {
  keyword: "",
  status: "",
  courseTrack: "",
  businessEntityId: "",
};

const UNSET_VALUE = "__unset__";

const STUDENT_STATUS_LABELS = {
  active: "在籍",
  paused: "暂停",
  graduated: "毕业",
  withdrawn: "退出",
  inactive: "停用",
};

const COURSE_TRACK_LABELS = {
  humanities: "文科",
  science: "理科",
};

const EDITABLE_COURSE_TRACK_OPTIONS = ["science", "humanities"];
const LEGACY_STUDENT_STATUS_FILTER_OPTIONS = ["active", "paused", "graduated", "withdrawn"];
const STUDENT_FIELD_IDS = [
  "name",
  "defaultBusinessEntity",
  "courseTrack",
  "presetExchangeRate",
  "targetSchools",
];

const dom = {};
let businessEntities = [];
let students = [];
let editingStudent = null;
let isEditSubmitting = false;
let isCreateSubmitting = false;

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
  dom.businessEntitySelect = document.querySelector("#studentBusinessEntitySelect");
  dom.resetButton = document.querySelector("#studentResetButton");
  dom.studentGrid = document.querySelector("#studentGrid");
  dom.studentLoadingState = document.querySelector("#studentLoadingState");
  dom.studentEmptyState = document.querySelector("#studentEmptyState");
  dom.studentCount = document.querySelector("#studentCount");
  dom.createButton = document.querySelector("#createStudentButton");

  dom.createDialog = document.querySelector("#createStudentProfileDialog");
  dom.createError = document.querySelector("#createStudentProfileError");
  dom.createNameInput = document.querySelector("#createStudentNameInput");
  dom.createBusinessEntitySelect = document.querySelector("#createStudentBusinessEntitySelect");
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
  dom.editBusinessEntitySelect = document.querySelector("#editStudentBusinessEntitySelect");
  dom.editCourseTrackSelect = document.querySelector("#editStudentCourseTrackSelect");
  dom.editPresetExchangeRateInput = document.querySelector("#editStudentPresetExchangeRateInput");
  dom.editWechatInput = document.querySelector("#editStudentWechatInput");
  dom.editPhoneInput = document.querySelector("#editStudentPhoneInput");
  dom.editEntranceDateInput = document.querySelector("#editStudentEntranceDateInput");
  dom.editTargetSchoolsInput = document.querySelector("#editStudentTargetSchoolsInput");
  dom.editNoteInput = document.querySelector("#editStudentNoteInput");
  dom.editCancelButton = document.querySelector("#editStudentCancelButton");
  dom.editSubmitButton = document.querySelector("#editStudentSubmitButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    loadStudentData();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    loadStudentData();
  });

  dom.createButton.addEventListener("click", openCreateDialog);
  dom.createCancelButton.addEventListener("click", closeCreateDialog);
  dom.createSubmitButton.addEventListener("click", submitCreateDialog);
  bindDialogFieldEvents("create");

  dom.studentGrid.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-student-id]");
    if (!button) {
      return;
    }

    openEditDialog(button.dataset.editStudentId);
  });

  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditDialog);
  bindDialogFieldEvents("edit");
}

function bindDialogFieldEvents(scope) {
  const fields = scope === "create"
    ? [
        ["name", dom.createNameInput, "input"],
        ["defaultBusinessEntity", dom.createBusinessEntitySelect, "change"],
        ["courseTrack", dom.createCourseTrackSelect, "change"],
        ["presetExchangeRate", dom.createPresetExchangeRateInput, "input"],
        ["targetSchools", dom.createTargetSchoolsInput, "input"],
      ]
    : [
        ["name", dom.editNameInput, "input"],
        ["defaultBusinessEntity", dom.editBusinessEntitySelect, "change"],
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
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
}

async function loadStudentData() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  setLoading(true);
  showMessage("info", "正在加载学生管理数据...");

  try {
    const [studentRows, filterRows, businessEntityRows] = await Promise.all([
      fetchStudents(filters),
      fetchStudentFilterOptions(),
      fetchBusinessEntitiesForStudents(),
    ]);

    businessEntities = businessEntityRows;
    renderStatusOptions(filterRows);
    renderCourseTrackOptions(filterRows);
    renderBusinessEntityOptions(businessEntities, filterRows);
    restoreFilterSelections(filters);
    students = studentRows;
    renderStudents(filterStudentsByKeyword(studentRows, filters.keyword));
    showMessage("success", "学生管理数据已加载。");
  } catch (error) {
    businessEntities = [];
    students = [];
    renderStatusOptions([]);
    renderCourseTrackOptions([]);
    renderBusinessEntityOptions([], []);
    renderStudents([]);
    showMessage("error", `读取学生管理数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readFilters() {
  return {
    keyword: dom.keywordInput.value.trim(),
    status: dom.statusSelect.value,
    courseTrack: dom.courseTrackSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.keywordInput.value = filters.keyword;
  dom.statusSelect.value = filters.status;
  dom.courseTrackSelect.value = filters.courseTrack;
  dom.businessEntitySelect.value = filters.businessEntityId;
}

function renderStatusOptions(rows) {
  const options = ['<option value="">全部</option>'];
  const fixedStatuses = new Set(LEGACY_STUDENT_STATUS_FILTER_OPTIONS);

  for (const status of LEGACY_STUDENT_STATUS_FILTER_OPTIONS) {
    options.push(
      `<option value="${escapeAttribute(status)}">${escapeHtml(studentStatusLabel(status))}</option>`
    );
  }

  for (const status of distinctValues(rows, "status")) {
    if (!fixedStatuses.has(status)) {
      options.push(
        `<option value="${escapeAttribute(status)}">${escapeHtml(studentStatusLabel(status))}</option>`
      );
    }
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

function renderBusinessEntityOptions(items, studentRows) {
  const options = ['<option value="">全部</option>'];

  if (studentRows.some((student) => !student.business_entity_id)) {
    options.push(`<option value="${UNSET_VALUE}">未设置</option>`);
  }

  for (const entity of items.filter((item) => item.is_active !== false)) {
    options.push(
      `<option value="${escapeAttribute(entity.id)}">${escapeHtml(entity.name || entity.id)}</option>`
    );
  }

  dom.businessEntitySelect.innerHTML = options.join("");
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
        <span class="status-badge status-${escapeAttribute(student.status || "unset")}">
          ${escapeHtml(studentStatusLabel(student.status))}
        </span>
      </div>

      <div class="table-actions">
        <button class="button" type="button" data-edit-student-id="${escapeAttribute(student.id)}">编辑学生</button>
      </div>

      <dl class="student-meta">
        <div>
          <dt>文理区分</dt>
          <dd>${escapeHtml(courseTrackLabel(student.course_track))}</dd>
        </div>
        <div>
          <dt>目标学校</dt>
          <dd>${escapeHtml(targetSchoolsDisplay(student.target_schools))}</dd>
        </div>
        <div>
          <dt>业务归属</dt>
          <dd>${escapeHtml(businessEntityName(student.business_entity_id))}</dd>
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

function openCreateDialog() {
  clearCreateErrors();
  setCreateSubmitting(false);
  dom.createNameInput.value = "";
  renderCreateBusinessEntityOptions(defaultNewBusinessEntityId(businessEntities));
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
    defaultBusinessEntityId: dom.createBusinessEntitySelect.value,
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
  renderEditBusinessEntityOptions(student.business_entity_id);
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
    defaultBusinessEntityId: dom.editBusinessEntitySelect.value,
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

function renderEditBusinessEntityOptions(selectedBusinessEntityId) {
  dom.editBusinessEntitySelect.innerHTML = businessEntityEditOptions(
    historicalEditBusinessEntities(businessEntities, selectedBusinessEntityId),
    true
  );
  dom.editBusinessEntitySelect.value = selectedBusinessEntityId || "";
}

function renderCreateBusinessEntityOptions(selectedBusinessEntityId) {
  dom.createBusinessEntitySelect.innerHTML = businessEntityEditOptions(newBusinessEntities(businessEntities), false);
  dom.createBusinessEntitySelect.value = selectedBusinessEntityId || "";
}

function businessEntityEditOptions(rows, allowUnset) {
  const options = rows
    .filter((entity) => entity?.id)
    .map((entity) =>
      `<option value="${escapeAttribute(entity.id)}">${escapeHtml(entity.name || entity.id)}</option>`
    );

  return [
    ...(allowUnset ? ['<option value="">未设置</option>'] : []),
    ...options,
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
  if (message.includes("业务归属")) return ["defaultBusinessEntity"];
  if (message.includes("预设汇率")) return ["presetExchangeRate"];
  if (message.includes("目标学校")) return ["targetSchools"];
  return [];
}

async function reloadStudentDataPreservingViewport() {
  const scrollX = window.scrollX;
  const scrollY = window.scrollY;
  await loadStudentData();
  window.scrollTo(scrollX, scrollY);
}

function filterStudentsByKeyword(items, keyword) {
  if (!keyword) {
    return items;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return items.filter((student) =>
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

function businessEntityName(entityId) {
  if (!entityId) {
    return "未设置";
  }

  const entity = businessEntities.find((item) => item.id === entityId);
  return entity?.name || entityId;
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
