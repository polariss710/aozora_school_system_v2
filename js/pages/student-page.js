import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchBusinessEntitiesForStudents,
  fetchStudentFilterOptions,
  fetchStudents,
  updateStudentProfile,
} from "../api/student-api.js";
import { formatDate, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  keyword: "",
  status: "",
  courseTrack: "",
  targetType: "",
  businessEntityId: "",
  defaultCurrency: "",
};

const UNSET_VALUE = "__unset__";

const STUDENT_STATUS_LABELS = {
  active: "在籍",
  inactive: "停用",
  paused: "暂停",
  graduated: "毕业",
};

const COURSE_TRACK_LABELS = {
  humanities: "文科",
  science: "理科",
};

const EDITABLE_STATUS_OPTIONS = ["active", "paused", "inactive", "graduated"];
const EDITABLE_COURSE_TRACK_OPTIONS = ["science", "humanities"];

const dom = {};
let businessEntities = [];
let students = [];
let editingStudent = null;
let isEditSubmitting = false;

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
  dom.targetTypeSelect = document.querySelector("#studentTargetTypeSelect");
  dom.businessEntitySelect = document.querySelector("#studentBusinessEntitySelect");
  dom.defaultCurrencySelect = document.querySelector("#studentDefaultCurrencySelect");
  dom.resetButton = document.querySelector("#studentResetButton");
  dom.studentGrid = document.querySelector("#studentGrid");
  dom.studentLoadingState = document.querySelector("#studentLoadingState");
  dom.studentEmptyState = document.querySelector("#studentEmptyState");
  dom.studentCount = document.querySelector("#studentCount");
  dom.editDialog = document.querySelector("#editStudentProfileDialog");
  dom.editSummary = document.querySelector("#editStudentProfileSummary");
  dom.editError = document.querySelector("#editStudentProfileError");
  dom.editDisplayNameInput = document.querySelector("#editStudentDisplayNameInput");
  dom.editStatusSelect = document.querySelector("#editStudentStatusSelect");
  dom.editCourseTrackSelect = document.querySelector("#editStudentCourseTrackSelect");
  dom.editTargetTypeInput = document.querySelector("#editStudentTargetTypeInput");
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

  dom.studentGrid.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-student-id]");
    if (!button) {
      return;
    }

    openEditDialog(button.dataset.editStudentId);
  });

  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditDialog);
  dom.editDisplayNameInput.addEventListener("input", () => {
    clearEditFieldInvalid("displayName");
    hideEditErrorIfClean();
  });
  dom.editStatusSelect.addEventListener("change", () => {
    clearEditFieldInvalid("status");
    hideEditErrorIfClean();
  });
  dom.editCourseTrackSelect.addEventListener("change", () => {
    clearEditFieldInvalid("courseTrack");
    hideEditErrorIfClean();
  });
}

function setDefaultFilters() {
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.courseTrackSelect.value = DEFAULT_FILTERS.courseTrack;
  dom.targetTypeSelect.value = DEFAULT_FILTERS.targetType;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.defaultCurrencySelect.value = DEFAULT_FILTERS.defaultCurrency;
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
    renderTargetTypeOptions(filterRows);
    renderBusinessEntityOptions(businessEntities, filterRows);
    renderDefaultCurrencyOptions(filterRows);
    restoreFilterSelections(filters);
    students = studentRows;
    renderStudents(filterStudentsByKeyword(studentRows, filters.keyword));
    showMessage("success", "学生管理数据已加载。");
  } catch (error) {
    businessEntities = [];
    students = [];
    renderStatusOptions([]);
    renderCourseTrackOptions([]);
    renderTargetTypeOptions([]);
    renderBusinessEntityOptions([], []);
    renderDefaultCurrencyOptions([]);
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
    targetType: dom.targetTypeSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    defaultCurrency: dom.defaultCurrencySelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.keywordInput.value = filters.keyword;
  dom.statusSelect.value = filters.status;
  dom.courseTrackSelect.value = filters.courseTrack;
  dom.targetTypeSelect.value = filters.targetType;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.defaultCurrencySelect.value = filters.defaultCurrency;
}

function renderStatusOptions(rows) {
  const options = ['<option value="">全部</option>'];

  for (const status of distinctValues(rows, "status")) {
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

function renderTargetTypeOptions(rows) {
  const options = ['<option value="">全部</option>'];

  if (rows.some((student) => !student.target_type)) {
    options.push(`<option value="${UNSET_VALUE}">未设置</option>`);
  }

  for (const targetType of distinctValues(rows, "target_type")) {
    options.push(
      `<option value="${escapeAttribute(targetType)}">${escapeHtml(displayValue(targetType))}</option>`
    );
  }

  dom.targetTypeSelect.innerHTML = options.join("");
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

function renderDefaultCurrencyOptions(rows) {
  const options = ['<option value="">全部</option>'];

  for (const currency of distinctValues(rows, "default_currency")) {
    options.push(
      `<option value="${escapeAttribute(currency)}">${escapeHtml(displayValue(currency))}</option>`
    );
  }

  dom.defaultCurrencySelect.innerHTML = options.join("");
}

function renderStudents(items) {
  dom.studentCount.textContent = `${items.length} 人`;
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
        <button class="button" type="button" data-edit-student-id="${escapeAttribute(student.id)}">编辑基础信息</button>
      </div>

      <dl class="student-meta">
        <div>
          <dt>读音</dt>
          <dd>${escapeHtml(displayValue(student.kana_name))}</dd>
        </div>
        <div>
          <dt>课程方向</dt>
          <dd>${escapeHtml(courseTrackLabel(student.course_track))}</dd>
        </div>
        <div>
          <dt>目标类型</dt>
          <dd>${escapeHtml(displayValue(student.target_type))}</dd>
        </div>
        <div>
          <dt>目标学校</dt>
          <dd>${escapeHtml(displayValue(student.target_schools))}</dd>
        </div>
        <div>
          <dt>业务归属</dt>
          <dd>${escapeHtml(businessEntityName(student.business_entity_id))}</dd>
        </div>
        <div>
          <dt>默认币种</dt>
          <dd>${escapeHtml(displayValue(student.default_currency))}</dd>
        </div>
        <div>
          <dt>预设汇率</dt>
          <dd>${escapeHtml(displayValue(student.preset_exchange_rate))}</dd>
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

function openEditDialog(studentId) {
  const student = students.find((item) => item.id === studentId);
  if (!student) {
    showMessage("error", "没有找到要编辑的学生。");
    return;
  }

  editingStudent = student;
  dom.editSummary.innerHTML = renderEditSummary(student);
  dom.editDisplayNameInput.value = student.display_name || student.name || "";
  renderEditStatusOptions(student.status);
  renderEditCourseTrackOptions(student.course_track);
  dom.editTargetTypeInput.value = student.target_type || "";
  dom.editNoteInput.value = student.note || "";
  clearEditErrors();
  setEditSubmitting(false);
  dom.editDialog.classList.remove("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "false");
  dom.editDisplayNameInput.focus();
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

  const payload = {
    studentId: editingStudent.id,
    displayName: dom.editDisplayNameInput.value.trim(),
    status: dom.editStatusSelect.value,
    courseTrack: dom.editCourseTrackSelect.value,
    targetType: dom.editTargetTypeInput.value.trim(),
    note: dom.editNoteInput.value.trim(),
  };

  if (!payload.displayName) {
    showEditError("请输入学生显示名称。", ["displayName"]);
    return;
  }

  if (!payload.status) {
    showEditError("请选择学生状态。", ["status"]);
    return;
  }

  if (payload.courseTrack && !EDITABLE_COURSE_TRACK_OPTIONS.includes(payload.courseTrack)) {
    showEditError("请选择有效课程方向。", ["courseTrack"]);
    return;
  }

  setEditSubmitting(true);

  try {
    await updateStudentProfile(payload);
    closeEditDialog({ force: true });
    await loadStudentData();
    showMessage("success", "学生基础信息已更新。");
  } catch (error) {
    showEditError(error.message || String(error), editFieldIdsForError(error));
  } finally {
    setEditSubmitting(false);
  }
}

function renderEditSummary(student) {
  const rows = [
    ["学生编号", student.student_code || shortId(student.id)],
    ["系统姓名", student.name],
    ["业务归属", businessEntityName(student.business_entity_id)],
    ["不可编辑字段", "余额、结算、学费规则、联系方式、家长信息、生日"],
  ];

  return `
    <dl class="detail-definition-list">
      ${rows.map(([label, value]) => `
        <div>
          <dt>${escapeHtml(label)}</dt>
          <dd>${escapeHtml(displayValue(value))}</dd>
        </div>
      `).join("")}
    </dl>
  `;
}

function renderEditStatusOptions(selectedStatus) {
  dom.editStatusSelect.innerHTML = EDITABLE_STATUS_OPTIONS
    .map((status) => `<option value="${escapeAttribute(status)}">${escapeHtml(studentStatusLabel(status))}</option>`)
    .join("");
  dom.editStatusSelect.value = selectedStatus || "active";
}

function renderEditCourseTrackOptions(selectedCourseTrack) {
  dom.editCourseTrackSelect.innerHTML = [
    '<option value="">未设置</option>',
    ...EDITABLE_COURSE_TRACK_OPTIONS.map((courseTrack) =>
      `<option value="${escapeAttribute(courseTrack)}">${escapeHtml(courseTrackLabel(courseTrack))}</option>`
    ),
  ].join("");
  dom.editCourseTrackSelect.value = selectedCourseTrack || "";
}

function showEditError(message, fieldIds = []) {
  dom.editError.textContent = message;
  dom.editError.classList.remove("is-hidden");
  fieldIds.forEach(setEditFieldInvalid);
}

function clearEditErrors() {
  dom.editError.textContent = "";
  dom.editError.classList.add("is-hidden");
  ["displayName", "status", "courseTrack"].forEach(clearEditFieldInvalid);
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

function editFieldIdsForError(error) {
  const message = error?.message || String(error || "");
  if (message.includes("显示名称")) return ["displayName"];
  if (message.includes("状态")) return ["status"];
  if (message.includes("课程方向")) return ["courseTrack"];
  return [];
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
      student.kana_name,
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
  return student.display_name || student.name || "未命名学生";
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
