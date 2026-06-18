import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createTeacherProfile,
  fetchBusinessEntitiesForTeachers,
  fetchSubjectsForTeachers,
  fetchTeacherFilterOptions,
  fetchTeachers,
  updateTeacherProfile,
} from "../api/teacher-api.js";
import { formatDate, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  keyword: "",
  status: "",
  department: "",
  businessEntityId: "",
};

const UNSET_VALUE = "__unset__";

const TEACHER_STATUS_LABELS = {
  active: "在职",
  employed: "在职",
  paused: "暂停",
  inactive: "停用",
  resigned: "离职",
};

const TEACHER_DEPARTMENT_OPTIONS = ["常勤老师", "バイト老师", "事务老师"];
const EDITABLE_STATUS_OPTIONS = [
  { value: "employed", label: "在职" },
  { value: "paused", label: "暂停" },
  { value: "resigned", label: "离职" },
];
const TEACHER_FIELD_IDS = [
  "name",
  "department",
  "defaultSubject",
  "businessEntity",
  "status",
];

const dom = {};
let businessEntities = [];
let subjects = [];
let teachers = [];
let editingTeacher = null;
let isEditSubmitting = false;
let isCreateSubmitting = false;

export function initTeacherPage() {
  cacheDom();
  setDefaultFilters();
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderTeachers([]);
    return;
  }

  loadTeacherData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#teacherMessageArea");
  dom.filterForm = document.querySelector("#teacherFilterForm");
  dom.keywordInput = document.querySelector("#teacherKeywordInput");
  dom.statusSelect = document.querySelector("#teacherStatusSelect");
  dom.departmentSelect = document.querySelector("#teacherDepartmentSelect");
  dom.businessEntitySelect = document.querySelector("#teacherBusinessEntitySelect");
  dom.resetButton = document.querySelector("#teacherResetButton");
  dom.teacherGrid = document.querySelector("#teacherGrid");
  dom.teacherLoadingState = document.querySelector("#teacherLoadingState");
  dom.teacherEmptyState = document.querySelector("#teacherEmptyState");
  dom.teacherCount = document.querySelector("#teacherCount");
  dom.createButton = document.querySelector("#createTeacherButton");

  dom.createDialog = document.querySelector("#createTeacherProfileDialog");
  dom.createError = document.querySelector("#createTeacherProfileError");
  dom.createNameInput = document.querySelector("#createTeacherNameInput");
  dom.createDepartmentSelect = document.querySelector("#createTeacherDepartmentSelect");
  dom.createSubjectSelect = document.querySelector("#createTeacherSubjectSelect");
  dom.createBusinessEntitySelect = document.querySelector("#createTeacherBusinessEntitySelect");
  dom.createStatusSelect = document.querySelector("#createTeacherStatusSelect");
  dom.createNoteInput = document.querySelector("#createTeacherNoteInput");
  dom.createAlipayAccountInput = document.querySelector("#createTeacherAlipayAccountInput");
  dom.createWechatAccountInput = document.querySelector("#createTeacherWechatAccountInput");
  dom.createBankNameInput = document.querySelector("#createTeacherBankNameInput");
  dom.createBankBranchCodeInput = document.querySelector("#createTeacherBankBranchCodeInput");
  dom.createBankBranchNameInput = document.querySelector("#createTeacherBankBranchNameInput");
  dom.createBankAccountNumberInput = document.querySelector("#createTeacherBankAccountNumberInput");
  dom.createCancelButton = document.querySelector("#createTeacherCancelButton");
  dom.createSubmitButton = document.querySelector("#createTeacherSubmitButton");

  dom.editDialog = document.querySelector("#editTeacherProfileDialog");
  dom.editError = document.querySelector("#editTeacherProfileError");
  dom.editNameInput = document.querySelector("#editTeacherNameInput");
  dom.editDepartmentSelect = document.querySelector("#editTeacherDepartmentSelect");
  dom.editSubjectSelect = document.querySelector("#editTeacherSubjectSelect");
  dom.editBusinessEntitySelect = document.querySelector("#editTeacherBusinessEntitySelect");
  dom.editStatusSelect = document.querySelector("#editTeacherStatusSelect");
  dom.editNoteInput = document.querySelector("#editTeacherNoteInput");
  dom.editAlipayAccountInput = document.querySelector("#editTeacherAlipayAccountInput");
  dom.editWechatAccountInput = document.querySelector("#editTeacherWechatAccountInput");
  dom.editBankNameInput = document.querySelector("#editTeacherBankNameInput");
  dom.editBankBranchCodeInput = document.querySelector("#editTeacherBankBranchCodeInput");
  dom.editBankBranchNameInput = document.querySelector("#editTeacherBankBranchNameInput");
  dom.editBankAccountNumberInput = document.querySelector("#editTeacherBankAccountNumberInput");
  dom.editCancelButton = document.querySelector("#editTeacherCancelButton");
  dom.editSubmitButton = document.querySelector("#editTeacherSubmitButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    loadTeacherData();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    loadTeacherData();
  });

  dom.createButton.addEventListener("click", openCreateDialog);
  dom.createCancelButton.addEventListener("click", closeCreateDialog);
  dom.createSubmitButton.addEventListener("click", submitCreateDialog);
  bindDialogFieldEvents("create");

  dom.teacherGrid.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-teacher-id]");
    if (!button) {
      return;
    }

    openEditDialog(button.dataset.editTeacherId);
  });

  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditDialog);
  bindDialogFieldEvents("edit");
}

function bindDialogFieldEvents(scope) {
  const fields = scope === "create"
    ? [
        ["name", dom.createNameInput, "input"],
        ["department", dom.createDepartmentSelect, "change"],
        ["defaultSubject", dom.createSubjectSelect, "change"],
        ["businessEntity", dom.createBusinessEntitySelect, "change"],
        ["status", dom.createStatusSelect, "change"],
      ]
    : [
        ["name", dom.editNameInput, "input"],
        ["department", dom.editDepartmentSelect, "change"],
        ["defaultSubject", dom.editSubjectSelect, "change"],
        ["businessEntity", dom.editBusinessEntitySelect, "change"],
        ["status", dom.editStatusSelect, "change"],
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
  dom.departmentSelect.value = DEFAULT_FILTERS.department;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
}

async function loadTeacherData() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  setLoading(true);
  showMessage("info", "正在加载老师管理数据...");

  try {
    const [teacherRows, filterRows, businessEntityRows, subjectRows] = await Promise.all([
      fetchTeachers(filters),
      fetchTeacherFilterOptions(),
      fetchBusinessEntitiesForTeachers(),
      fetchSubjectsForTeachers(),
    ]);

    businessEntities = businessEntityRows;
    subjects = subjectRows;
    renderStatusOptions(filterRows);
    renderDepartmentOptions(filterRows);
    renderBusinessEntityOptions(businessEntities, filterRows);
    restoreFilterSelections(filters);
    teachers = teacherRows;
    renderTeachers(filterTeachersByKeyword(teacherRows, filters.keyword));
    showMessage("success", "老师管理数据已加载。");
  } catch (error) {
    businessEntities = [];
    subjects = [];
    teachers = [];
    renderStatusOptions([]);
    renderDepartmentOptions([]);
    renderBusinessEntityOptions([], []);
    renderTeachers([]);
    showMessage("error", `读取老师管理数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readFilters() {
  return {
    keyword: dom.keywordInput.value.trim(),
    status: dom.statusSelect.value,
    department: dom.departmentSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.keywordInput.value = filters.keyword;
  dom.statusSelect.value = filters.status;
  dom.departmentSelect.value = filters.department;
  dom.businessEntitySelect.value = filters.businessEntityId;
}

function renderStatusOptions(rows) {
  const options = ['<option value="">全部</option>'];

  for (const status of distinctValues(rows, "status")) {
    options.push(
      `<option value="${escapeAttribute(status)}">${escapeHtml(teacherStatusLabel(status))}</option>`
    );
  }

  dom.statusSelect.innerHTML = options.join("");
}

function renderDepartmentOptions(rows) {
  const options = ['<option value="">全部</option>'];

  for (const department of distinctValues(rows, "department")) {
    options.push(
      `<option value="${escapeAttribute(department)}">${escapeHtml(displayValue(department))}</option>`
    );
  }

  dom.departmentSelect.innerHTML = options.join("");
}

function renderBusinessEntityOptions(items, teacherRows) {
  const options = ['<option value="">全部</option>'];

  if (teacherRows.some((teacher) => !teacher.default_business_entity_id)) {
    options.push(`<option value="${UNSET_VALUE}">未设置</option>`);
  }

  for (const entity of items.filter((item) => item.is_active !== false)) {
    options.push(
      `<option value="${escapeAttribute(entity.id)}">${escapeHtml(entity.name || entity.id)}</option>`
    );
  }

  dom.businessEntitySelect.innerHTML = options.join("");
}

function renderTeachers(items) {
  dom.teacherCount.textContent = `共 ${items.length} 名`;
  dom.teacherEmptyState.classList.toggle("is-hidden", items.length > 0);

  if (!items.length) {
    dom.teacherGrid.innerHTML = "";
    return;
  }

  dom.teacherGrid.innerHTML = items.map((teacher) => `
    <article class="teacher-card">
      <div class="teacher-card-header">
        <div>
          <div class="teacher-name">${escapeHtml(teacherName(teacher))}</div>
          <div class="teacher-code">${escapeHtml(teacher.teacher_code || shortId(teacher.id))}</div>
        </div>
        <span class="status-badge status-${escapeAttribute(teacher.status || "unset")}">
          ${escapeHtml(teacherStatusLabel(teacher.status))}
        </span>
      </div>

      <div class="table-actions">
        <button class="button" type="button" data-edit-teacher-id="${escapeAttribute(teacher.id)}">编辑老师</button>
      </div>

      <dl class="teacher-meta">
        <div>
          <dt>老师分类</dt>
          <dd>${escapeHtml(displayValue(teacher.department))}</dd>
        </div>
        <div>
          <dt>默认科目</dt>
          <dd>${escapeHtml(subjectName(teacher.default_subject_id))}</dd>
        </div>
        <div>
          <dt>默认业务归属</dt>
          <dd>${escapeHtml(businessEntityName(teacher.default_business_entity_id))}</dd>
        </div>
        <div>
          <dt>人民币支付</dt>
          <dd>${escapeHtml(chinaPaymentSummary(teacher))}</dd>
        </div>
        <div>
          <dt>日元支付</dt>
          <dd>${escapeHtml(japanPaymentSummary(teacher))}</dd>
        </div>
        <div>
          <dt>备注</dt>
          <dd>${escapeHtml(displayValue(teacher.note))}</dd>
        </div>
        <div>
          <dt>更新时间</dt>
          <dd>${escapeHtml(formatDate(teacher.updated_at))}</dd>
        </div>
      </dl>
    </article>
  `).join("");
}

function openCreateDialog() {
  clearCreateErrors();
  setCreateSubmitting(false);
  dom.createNameInput.value = "";
  renderCreateDepartmentOptions("常勤老师");
  renderCreateSubjectOptions("");
  renderCreateBusinessEntityOptions("");
  renderCreateStatusOptions("employed");
  dom.createNoteInput.value = "";
  dom.createAlipayAccountInput.value = "";
  dom.createWechatAccountInput.value = "";
  dom.createBankNameInput.value = "";
  dom.createBankBranchCodeInput.value = "";
  dom.createBankBranchNameInput.value = "";
  dom.createBankAccountNumberInput.value = "";
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
  const validation = validateTeacherPayload(payload);
  if (validation) {
    showCreateError(validation.message, validation.fieldIds);
    return;
  }

  setCreateSubmitting(true);

  try {
    await createTeacherProfile(payload);
    closeCreateDialog({ force: true });
    await reloadTeacherDataPreservingViewport();
    showMessage("success", "老师已新增，可用于未来排课、筛选和工资规则配置。");
  } catch (error) {
    showCreateError(error.message || String(error), teacherFieldIdsForError(error));
  } finally {
    setCreateSubmitting(false);
  }
}

function readCreatePayload() {
  return {
    name: dom.createNameInput.value.trim(),
    department: dom.createDepartmentSelect.value,
    defaultSubjectId: dom.createSubjectSelect.value,
    defaultBusinessEntityId: dom.createBusinessEntitySelect.value,
    status: dom.createStatusSelect.value,
    note: dom.createNoteInput.value.trim(),
    alipayAccount: dom.createAlipayAccountInput.value.trim(),
    wechatAccount: dom.createWechatAccountInput.value.trim(),
    bankName: dom.createBankNameInput.value.trim(),
    bankBranchCode: dom.createBankBranchCodeInput.value.trim(),
    bankBranchName: dom.createBankBranchNameInput.value.trim(),
    bankAccountNumber: dom.createBankAccountNumberInput.value.trim(),
  };
}

function openEditDialog(teacherId) {
  const teacher = teachers.find((item) => item.id === teacherId);
  if (!teacher) {
    showMessage("error", "没有找到要编辑的老师。");
    return;
  }

  editingTeacher = teacher;
  dom.editNameInput.value = teacher.name || teacher.display_name || "";
  renderEditDepartmentOptions(normalizeDepartmentForEdit(teacher.department));
  renderEditSubjectOptions(teacher.default_subject_id);
  renderEditBusinessEntityOptions(teacher.default_business_entity_id);
  renderEditStatusOptions(normalizeStatusForEdit(teacher.status));
  dom.editNoteInput.value = teacher.note || "";
  dom.editAlipayAccountInput.value = teacher.alipay_account || "";
  dom.editWechatAccountInput.value = teacher.wechat_account || "";
  dom.editBankNameInput.value = teacher.bank_name || "";
  dom.editBankBranchCodeInput.value = teacher.bank_branch_code || "";
  dom.editBankBranchNameInput.value = teacher.bank_branch_name || "";
  dom.editBankAccountNumberInput.value = teacher.bank_account_number || "";
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

  editingTeacher = null;
  dom.editDialog.classList.add("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "true");
}

async function submitEditDialog() {
  if (isEditSubmitting) {
    return;
  }

  clearEditErrors();

  if (!editingTeacher) {
    showEditError("没有找到要编辑的老师。");
    return;
  }

  const payload = readEditPayload();
  const validation = validateTeacherPayload(payload);
  if (validation) {
    showEditError(validation.message, validation.fieldIds);
    return;
  }

  setEditSubmitting(true);

  try {
    await updateTeacherProfile(payload);
    closeEditDialog({ force: true });
    await reloadTeacherDataPreservingViewport();
    showMessage("success", "老师资料已更新。");
  } catch (error) {
    showEditError(error.message || String(error), teacherFieldIdsForError(error));
  } finally {
    setEditSubmitting(false);
  }
}

function readEditPayload() {
  return {
    teacherId: editingTeacher.id,
    name: dom.editNameInput.value.trim(),
    department: dom.editDepartmentSelect.value,
    defaultSubjectId: dom.editSubjectSelect.value,
    defaultBusinessEntityId: dom.editBusinessEntitySelect.value,
    status: dom.editStatusSelect.value,
    note: dom.editNoteInput.value.trim(),
    alipayAccount: dom.editAlipayAccountInput.value.trim(),
    wechatAccount: dom.editWechatAccountInput.value.trim(),
    bankName: dom.editBankNameInput.value.trim(),
    bankBranchCode: dom.editBankBranchCodeInput.value.trim(),
    bankBranchName: dom.editBankBranchNameInput.value.trim(),
    bankAccountNumber: dom.editBankAccountNumberInput.value.trim(),
  };
}

function validateTeacherPayload(payload) {
  if (!payload.name) {
    return { message: "请输入老师姓名。", fieldIds: ["name"] };
  }

  if (!TEACHER_DEPARTMENT_OPTIONS.includes(payload.department)) {
    return { message: "请选择有效老师分类。", fieldIds: ["department"] };
  }

  if (!EDITABLE_STATUS_OPTIONS.some((option) => option.value === payload.status)) {
    return { message: "请选择有效老师状态。", fieldIds: ["status"] };
  }

  return null;
}

function renderEditDepartmentOptions(selectedDepartment) {
  dom.editDepartmentSelect.innerHTML = departmentEditOptions();
  dom.editDepartmentSelect.value = selectedDepartment || "常勤老师";
}

function renderCreateDepartmentOptions(selectedDepartment) {
  dom.createDepartmentSelect.innerHTML = departmentEditOptions();
  dom.createDepartmentSelect.value = selectedDepartment || "常勤老师";
}

function departmentEditOptions() {
  return TEACHER_DEPARTMENT_OPTIONS
    .map((department) => `<option value="${escapeAttribute(department)}">${escapeHtml(department)}</option>`)
    .join("");
}

function renderEditStatusOptions(selectedStatus) {
  dom.editStatusSelect.innerHTML = statusEditOptions();
  dom.editStatusSelect.value = selectedStatus || "employed";
}

function renderCreateStatusOptions(selectedStatus) {
  dom.createStatusSelect.innerHTML = statusEditOptions();
  dom.createStatusSelect.value = selectedStatus || "employed";
}

function statusEditOptions() {
  return EDITABLE_STATUS_OPTIONS
    .map((status) => `<option value="${escapeAttribute(status.value)}">${escapeHtml(status.label)}</option>`)
    .join("");
}

function renderEditSubjectOptions(selectedSubjectId) {
  dom.editSubjectSelect.innerHTML = subjectEditOptions();
  dom.editSubjectSelect.value = selectedSubjectId || "";
}

function renderCreateSubjectOptions(selectedSubjectId) {
  dom.createSubjectSelect.innerHTML = subjectEditOptions();
  dom.createSubjectSelect.value = selectedSubjectId || "";
}

function subjectEditOptions() {
  const subjectOptions = subjects
    .filter((subject) => subject?.id)
    .map((subject) => {
      const activeSuffix = subject.is_active === false ? "（停用）" : "";
      const categoryPrefix = subject.primary_category || subject.category || "";
      const label = categoryPrefix ? `${categoryPrefix} / ${subject.name}${activeSuffix}` : `${subject.name}${activeSuffix}`;
      return `<option value="${escapeAttribute(subject.id)}">${escapeHtml(label)}</option>`;
    });

  return [
    '<option value="">未设置</option>',
    ...subjectOptions,
  ].join("");
}

function renderEditBusinessEntityOptions(selectedBusinessEntityId) {
  dom.editBusinessEntitySelect.innerHTML = businessEntityEditOptions();
  dom.editBusinessEntitySelect.value = selectedBusinessEntityId || "";
}

function renderCreateBusinessEntityOptions(selectedBusinessEntityId) {
  dom.createBusinessEntitySelect.innerHTML = businessEntityEditOptions();
  dom.createBusinessEntitySelect.value = selectedBusinessEntityId || "";
}

function businessEntityEditOptions() {
  const activeOptions = businessEntities
    .filter((entity) => entity?.id && entity.is_active !== false)
    .map((entity) =>
      `<option value="${escapeAttribute(entity.id)}">${escapeHtml(entity.name || entity.id)}</option>`
    );

  return [
    '<option value="">未设置</option>',
    ...activeOptions,
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
  TEACHER_FIELD_IDS.forEach(clearCreateFieldInvalid);
}

function hideCreateErrorIfClean() {
  const hasInvalidField = document.querySelector("[data-create-teacher-field].is-invalid");
  if (!hasInvalidField) {
    dom.createError.textContent = "";
    dom.createError.classList.add("is-hidden");
  }
}

function setCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-teacher-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-teacher-field="${fieldId}"]`);
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
  TEACHER_FIELD_IDS.forEach(clearEditFieldInvalid);
}

function hideEditErrorIfClean() {
  const hasInvalidField = document.querySelector("[data-edit-teacher-field].is-invalid");
  if (!hasInvalidField) {
    dom.editError.textContent = "";
    dom.editError.classList.add("is-hidden");
  }
}

function setEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-teacher-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-teacher-field="${fieldId}"]`);
  field?.classList.remove("is-invalid");
}

function setEditSubmitting(isSubmitting) {
  isEditSubmitting = isSubmitting;
  dom.editSubmitButton.disabled = isSubmitting;
  dom.editCancelButton.disabled = isSubmitting;
  dom.editSubmitButton.textContent = isSubmitting ? "保存中..." : "保存";
}

function teacherFieldIdsForError(error) {
  const message = error?.message || String(error || "");
  if (message.includes("姓名")) return ["name"];
  if (message.includes("分类")) return ["department"];
  if (message.includes("默认科目")) return ["defaultSubject"];
  if (message.includes("业务归属")) return ["businessEntity"];
  if (message.includes("状态")) return ["status"];
  return [];
}

async function reloadTeacherDataPreservingViewport() {
  const scrollX = window.scrollX;
  const scrollY = window.scrollY;
  await loadTeacherData();
  window.scrollTo(scrollX, scrollY);
}

function filterTeachersByKeyword(items, keyword) {
  if (!keyword) {
    return items;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return items.filter((teacher) =>
    [
      teacher.teacher_code,
      teacher.name,
      teacher.display_name,
      teacher.department,
      subjectName(teacher.default_subject_id),
      businessEntityName(teacher.default_business_entity_id),
      teacher.alipay_account,
      teacher.wechat_account,
      teacher.bank_name,
      teacher.bank_branch_code,
      teacher.bank_branch_name,
      teacher.bank_account_number,
      teacher.note,
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

function subjectName(subjectId) {
  if (!subjectId) {
    return "未设置";
  }

  const subject = subjects.find((item) => item.id === subjectId);
  return subject?.name || subjectId;
}

function teacherName(teacher) {
  return teacher.name || teacher.display_name || "未命名老师";
}

function teacherStatusLabel(status) {
  if (!status) {
    return "未设置";
  }

  return TEACHER_STATUS_LABELS[status] || safeText(status);
}

function normalizeDepartmentForEdit(department) {
  return TEACHER_DEPARTMENT_OPTIONS.includes(department) ? department : "常勤老师";
}

function normalizeStatusForEdit(status) {
  if (status === "active") {
    return "employed";
  }

  if (status === "inactive") {
    return "resigned";
  }

  return EDITABLE_STATUS_OPTIONS.some((option) => option.value === status) ? status : "employed";
}

function chinaPaymentSummary(teacher) {
  const parts = [
    teacher.alipay_account ? `支付宝：${teacher.alipay_account}` : "",
    teacher.wechat_account ? `微信：${teacher.wechat_account}` : "",
  ].filter(Boolean);
  return parts.length ? parts.join(" / ") : "未设置";
}

function japanPaymentSummary(teacher) {
  const parts = [
    teacher.bank_name,
    teacher.bank_branch_code ? `支店番号 ${teacher.bank_branch_code}` : "",
    teacher.bank_branch_name,
    teacher.bank_account_number ? `账户 ${teacher.bank_account_number}` : "",
  ].filter(Boolean);
  return parts.length ? parts.join(" / ") : "未设置";
}

function displayValue(value) {
  return safeText(value) || "未设置";
}

function shortId(id) {
  return id ? `${String(id).slice(0, 8)}...` : "未设置";
}

function setLoading(isLoading) {
  dom.teacherLoadingState.classList.toggle("is-hidden", !isLoading);
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
