import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createTeacherProfile,
  fetchBusinessEntitiesForTeachers,
  fetchTeacherFilterOptions,
  fetchTeachers,
  updateTeacherProfile,
} from "../api/teacher-api.js";
import { formatCurrency, formatDate, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  keyword: "",
  status: "",
  department: "",
  businessEntityId: "",
};

const UNSET_BUSINESS_ENTITY_VALUE = "__unset__";

const TEACHER_STATUS_LABELS = {
  employed: "在职",
  inactive: "停用",
  paused: "暂停",
  resigned: "离职",
};

const EDITABLE_STATUS_OPTIONS = ["employed", "paused", "inactive", "resigned"];
const EDITABLE_CURRENCY_OPTIONS = ["JPY", "CNY"];
const CREATE_FIELD_IDS = ["teacherCode", "displayName", "status", "businessEntity"];

const dom = {};
let businessEntities = [];
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
  dom.createTeacherCodeInput = document.querySelector("#createTeacherCodeInput");
  dom.createDisplayNameInput = document.querySelector("#createTeacherDisplayNameInput");
  dom.createNameInput = document.querySelector("#createTeacherNameInput");
  dom.createKanaNameInput = document.querySelector("#createTeacherKanaNameInput");
  dom.createStatusSelect = document.querySelector("#createTeacherStatusSelect");
  dom.createDepartmentInput = document.querySelector("#createTeacherDepartmentInput");
  dom.createBusinessEntitySelect = document.querySelector("#createTeacherBusinessEntitySelect");
  dom.createNoteInput = document.querySelector("#createTeacherNoteInput");
  dom.createCancelButton = document.querySelector("#createTeacherCancelButton");
  dom.createSubmitButton = document.querySelector("#createTeacherSubmitButton");
  dom.editDialog = document.querySelector("#editTeacherProfileDialog");
  dom.editSummary = document.querySelector("#editTeacherProfileSummary");
  dom.editError = document.querySelector("#editTeacherProfileError");
  dom.editDisplayNameInput = document.querySelector("#editTeacherDisplayNameInput");
  dom.editNameInput = document.querySelector("#editTeacherNameInput");
  dom.editKanaNameInput = document.querySelector("#editTeacherKanaNameInput");
  dom.editStatusSelect = document.querySelector("#editTeacherStatusSelect");
  dom.editDepartmentInput = document.querySelector("#editTeacherDepartmentInput");
  dom.editBusinessEntitySelect = document.querySelector("#editTeacherBusinessEntitySelect");
  dom.editDefaultHourlyRateInput = document.querySelector("#editTeacherDefaultHourlyRateInput");
  dom.editDefaultCurrencySelect = document.querySelector("#editTeacherDefaultCurrencySelect");
  dom.editDefaultPaymentCurrencySelect = document.querySelector("#editTeacherDefaultPaymentCurrencySelect");
  dom.editDefaultPaymentMethodInput = document.querySelector("#editTeacherDefaultPaymentMethodInput");
  dom.editNoteInput = document.querySelector("#editTeacherNoteInput");
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
  dom.createTeacherCodeInput.addEventListener("input", () => {
    clearCreateFieldInvalid("teacherCode");
    hideCreateErrorIfClean();
  });
  dom.createDisplayNameInput.addEventListener("input", () => {
    clearCreateFieldInvalid("displayName");
    hideCreateErrorIfClean();
  });
  dom.createStatusSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("status");
    hideCreateErrorIfClean();
  });
  dom.createBusinessEntitySelect.addEventListener("change", () => {
    clearCreateFieldInvalid("businessEntity");
    hideCreateErrorIfClean();
  });

  dom.teacherGrid.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-teacher-id]");
    if (!button) {
      return;
    }

    openEditDialog(button.dataset.editTeacherId);
  });

  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditDialog);
  dom.editDisplayNameInput.addEventListener("input", () => {
    clearEditFieldInvalid("displayName");
    hideEditErrorIfClean();
  });
  dom.editNameInput.addEventListener("input", () => {
    clearEditFieldInvalid("name");
    hideEditErrorIfClean();
  });
  dom.editStatusSelect.addEventListener("change", () => {
    clearEditFieldInvalid("status");
    hideEditErrorIfClean();
  });
  dom.editBusinessEntitySelect.addEventListener("change", () => {
    clearEditFieldInvalid("businessEntity");
    hideEditErrorIfClean();
  });
  dom.editDefaultHourlyRateInput.addEventListener("input", () => {
    clearEditFieldInvalid("defaultHourlyRate");
    hideEditErrorIfClean();
  });
  dom.editDefaultCurrencySelect.addEventListener("change", () => {
    clearEditFieldInvalid("defaultCurrency");
    hideEditErrorIfClean();
  });
  dom.editDefaultPaymentCurrencySelect.addEventListener("change", () => {
    clearEditFieldInvalid("defaultPaymentCurrency");
    hideEditErrorIfClean();
  });
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
    const [teacherRows, filterRows, businessEntityRows] = await Promise.all([
      fetchTeachers(filters),
      fetchTeacherFilterOptions(),
      fetchBusinessEntitiesForTeachers(),
    ]);

    businessEntities = businessEntityRows;
    renderStatusOptions(filterRows);
    renderDepartmentOptions(filterRows);
    renderBusinessEntityOptions(businessEntities, filterRows);
    restoreFilterSelections(filters);
    teachers = teacherRows;
    renderTeachers(filterTeachersByKeyword(teacherRows, filters.keyword));
    showMessage("success", "老师管理数据已加载。");
  } catch (error) {
    businessEntities = [];
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
    options.push(`<option value="${UNSET_BUSINESS_ENTITY_VALUE}">未设置</option>`);
  }

  for (const entity of items.filter((item) => item.is_active !== false)) {
    options.push(
      `<option value="${escapeAttribute(entity.id)}">${escapeHtml(entity.name || entity.id)}</option>`
    );
  }

  dom.businessEntitySelect.innerHTML = options.join("");
}

function renderTeachers(items) {
  dom.teacherCount.textContent = `${items.length} 人`;
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
        <button class="button" type="button" data-edit-teacher-id="${escapeAttribute(teacher.id)}">编辑基础信息</button>
      </div>

      <dl class="teacher-meta">
        <div>
          <dt>分类</dt>
          <dd>${escapeHtml(displayValue(teacher.department))}</dd>
        </div>
        <div>
          <dt>业务归属</dt>
          <dd>${escapeHtml(businessEntityName(teacher.default_business_entity_id))}</dd>
        </div>
        <div>
          <dt>默认时给</dt>
          <dd>${escapeHtml(formatTeacherRate(teacher))}</dd>
        </div>
        <div>
          <dt>默认币种</dt>
          <dd>${escapeHtml(displayValue(teacher.default_currency))}</dd>
        </div>
        <div>
          <dt>支付币种</dt>
          <dd>${escapeHtml(displayValue(teacher.default_payment_currency))}</dd>
        </div>
        <div>
          <dt>支付方式</dt>
          <dd>${escapeHtml(displayValue(teacher.default_payment_method))}</dd>
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
  dom.createTeacherCodeInput.value = "";
  dom.createDisplayNameInput.value = "";
  dom.createNameInput.value = "";
  dom.createKanaNameInput.value = "";
  renderCreateStatusOptions("employed");
  dom.createDepartmentInput.value = "";
  renderCreateBusinessEntityOptions("");
  dom.createNoteInput.value = "";
  dom.createDialog.classList.remove("is-hidden");
  dom.createDialog.setAttribute("aria-hidden", "false");
  dom.createDisplayNameInput.focus();
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

  const payload = {
    teacherCode: dom.createTeacherCodeInput.value.trim(),
    displayName: dom.createDisplayNameInput.value.trim(),
    name: dom.createNameInput.value.trim(),
    kanaName: dom.createKanaNameInput.value.trim(),
    status: dom.createStatusSelect.value,
    department: dom.createDepartmentInput.value.trim(),
    defaultBusinessEntityId: dom.createBusinessEntitySelect.value,
    note: dom.createNoteInput.value.trim(),
  };

  if (!payload.displayName) {
    showCreateError("请输入老师显示名称。", ["displayName"]);
    return;
  }

  if (!payload.status) {
    showCreateError("请选择老师状态。", ["status"]);
    return;
  }

  if (!EDITABLE_STATUS_OPTIONS.includes(payload.status)) {
    showCreateError("请选择有效老师状态。", ["status"]);
    return;
  }

  setCreateSubmitting(true);

  try {
    await createTeacherProfile(payload);
    closeCreateDialog({ force: true });
    await reloadTeacherDataPreservingViewport();
    showMessage("success", "老师已新增，可用于未来排课、筛选和工资规则配置。");
  } catch (error) {
    showCreateError(error.message || String(error), createFieldIdsForError(error));
  } finally {
    setCreateSubmitting(false);
  }
}

function openEditDialog(teacherId) {
  const teacher = teachers.find((item) => item.id === teacherId);
  if (!teacher) {
    showMessage("error", "没有找到要编辑的老师。");
    return;
  }

  editingTeacher = teacher;
  dom.editSummary.innerHTML = renderEditSummary(teacher);
  dom.editDisplayNameInput.value = teacher.display_name || teacher.name || "";
  dom.editNameInput.value = teacher.name || teacher.display_name || "";
  dom.editKanaNameInput.value = teacher.kana_name || "";
  renderEditStatusOptions(teacher.status);
  dom.editDepartmentInput.value = teacher.department || "";
  renderEditBusinessEntityOptions(teacher.default_business_entity_id);
  dom.editDefaultHourlyRateInput.value = displayNumberInput(teacher.default_hourly_rate);
  renderEditCurrencyOptions(dom.editDefaultCurrencySelect, teacher.default_currency || "JPY");
  renderEditCurrencyOptions(dom.editDefaultPaymentCurrencySelect, teacher.default_payment_currency || "JPY");
  dom.editDefaultPaymentMethodInput.value = teacher.default_payment_method || "";
  dom.editNoteInput.value = teacher.note || "";
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

  const payload = {
    teacherId: editingTeacher.id,
    displayName: dom.editDisplayNameInput.value.trim(),
    name: dom.editNameInput.value.trim(),
    kanaName: dom.editKanaNameInput.value.trim(),
    status: dom.editStatusSelect.value,
    department: dom.editDepartmentInput.value.trim(),
    defaultBusinessEntityId: dom.editBusinessEntitySelect.value,
    defaultHourlyRate: readNonNegativeNumber(dom.editDefaultHourlyRateInput.value),
    defaultCurrency: dom.editDefaultCurrencySelect.value,
    defaultPaymentCurrency: dom.editDefaultPaymentCurrencySelect.value,
    defaultPaymentMethod: dom.editDefaultPaymentMethodInput.value.trim(),
    note: dom.editNoteInput.value.trim(),
  };

  if (!payload.displayName) {
    showEditError("请输入老师显示名称。", ["displayName"]);
    return;
  }

  if (!payload.name) {
    showEditError("请输入老师系统姓名。", ["name"]);
    return;
  }

  if (!payload.status) {
    showEditError("请选择老师状态。", ["status"]);
    return;
  }

  if (!EDITABLE_STATUS_OPTIONS.includes(payload.status)) {
    showEditError("请选择有效老师状态。", ["status"]);
    return;
  }

  if (!Number.isFinite(payload.defaultHourlyRate) || payload.defaultHourlyRate < 0) {
    showEditError("默认时薪需为 0 或正数。", ["defaultHourlyRate"]);
    return;
  }

  if (!EDITABLE_CURRENCY_OPTIONS.includes(payload.defaultCurrency)) {
    showEditError("请选择有效默认币种。", ["defaultCurrency"]);
    return;
  }

  if (!EDITABLE_CURRENCY_OPTIONS.includes(payload.defaultPaymentCurrency)) {
    showEditError("请选择有效支付币种。", ["defaultPaymentCurrency"]);
    return;
  }

  setEditSubmitting(true);

  try {
    await updateTeacherProfile(payload);
    closeEditDialog({ force: true });
    await reloadTeacherDataPreservingViewport();
    showMessage("success", "老师基础信息已更新。");
  } catch (error) {
    showEditError(error.message || String(error), editFieldIdsForError(error));
  } finally {
    setEditSubmitting(false);
  }
}

function renderEditSummary(teacher) {
  const rows = [
    ["老师编号", teacher.teacher_code || shortId(teacher.id)],
    ["不可编辑字段", "老师编号、默认科目、联系方式、收款账户、工资规则、工资锁定、结算、支付、课时"],
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
    .map((status) => `<option value="${escapeAttribute(status)}">${escapeHtml(teacherStatusLabel(status))}</option>`)
    .join("");
  dom.editStatusSelect.value = selectedStatus || "employed";
}

function renderCreateStatusOptions(selectedStatus) {
  dom.createStatusSelect.innerHTML = EDITABLE_STATUS_OPTIONS
    .map((status) => `<option value="${escapeAttribute(status)}">${escapeHtml(teacherStatusLabel(status))}</option>`)
    .join("");
  dom.createStatusSelect.value = selectedStatus || "employed";
}

function renderEditCurrencyOptions(selectEl, selectedCurrency) {
  selectEl.innerHTML = EDITABLE_CURRENCY_OPTIONS
    .map((currency) => `<option value="${escapeAttribute(currency)}">${escapeHtml(currency)}</option>`)
    .join("");
  selectEl.value = selectedCurrency || "JPY";
}

function renderEditBusinessEntityOptions(selectedBusinessEntityId) {
  dom.editBusinessEntitySelect.innerHTML = [
    '<option value="">未设置</option>',
    ...businessEntities
      .filter((entity) => entity.is_active !== false)
      .map((entity) =>
        `<option value="${escapeAttribute(entity.id)}">${escapeHtml(entity.name || entity.id)}</option>`
      ),
  ].join("");
  dom.editBusinessEntitySelect.value = selectedBusinessEntityId || "";
}

function renderCreateBusinessEntityOptions(selectedBusinessEntityId) {
  dom.createBusinessEntitySelect.innerHTML = [
    '<option value="">未设置</option>',
    ...businessEntities
      .filter((entity) => entity.is_active !== false)
      .map((entity) =>
        `<option value="${escapeAttribute(entity.id)}">${escapeHtml(entity.name || entity.id)}</option>`
      ),
  ].join("");
  dom.createBusinessEntitySelect.value = selectedBusinessEntityId || "";
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
  CREATE_FIELD_IDS.forEach(clearCreateFieldInvalid);
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

function createFieldIdsForError(error) {
  const message = error?.message || String(error || "");
  if (message.includes("编号")) return ["teacherCode"];
  if (message.includes("显示名称")) return ["displayName"];
  if (message.includes("状态")) return ["status"];
  if (message.includes("业务归属")) return ["businessEntity"];
  return [];
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
  [
    "displayName",
    "name",
    "status",
    "businessEntity",
    "defaultHourlyRate",
    "defaultCurrency",
    "defaultPaymentCurrency",
  ].forEach(clearEditFieldInvalid);
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

function editFieldIdsForError(error) {
  const message = error?.message || String(error || "");
  if (message.includes("显示名称")) return ["displayName"];
  if (message.includes("系统姓名")) return ["name"];
  if (message.includes("状态")) return ["status"];
  if (message.includes("业务归属")) return ["businessEntity"];
  if (message.includes("时薪")) return ["defaultHourlyRate"];
  if (message.includes("支付币种")) return ["defaultPaymentCurrency"];
  if (message.includes("币种")) return ["defaultCurrency"];
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
      teacher.name,
      teacher.display_name,
      teacher.kana_name,
      teacher.teacher_code,
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

function teacherName(teacher) {
  return teacher.display_name || teacher.name || "未命名老师";
}

function teacherStatusLabel(status) {
  if (!status) {
    return "未设置";
  }

  return TEACHER_STATUS_LABELS[status] || safeText(status);
}

function formatTeacherRate(teacher) {
  if (teacher.default_hourly_rate === null || teacher.default_hourly_rate === undefined || teacher.default_hourly_rate === "") {
    return "未设置";
  }

  return formatCurrency(teacher.default_hourly_rate, teacher.default_currency || "JPY");
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
