import { hasSupabaseConfig } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";
import { createSubjectProfile, fetchSubjects, updateSubjectProfile } from "../api/subject-api.js";
import { formatDate, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  keyword: "",
  activeState: "",
  primaryCategory: "",
  category: "",
};

const UNSET_VALUE = "__unset__";
const EDITABLE_STATUS_OPTIONS = ["active", "inactive"];
const PRIMARY_CATEGORY_OPTIONS = ["班课", "VIP"];
const SECONDARY_CATEGORY_OPTIONS = ["学部进学", "大学院进学", "资格考对策", "特殊课程"];
const CREATE_FIELD_IDS = ["name", "status", "primaryCategory", "category", "sortOrder"];

const dom = {};
let allSubjects = [];
let editingSubject = null;
let isEditSubmitting = false;
let isCreateSubmitting = false;

export function initSubjectPage() {
  cacheDom();
  setDefaultFilters();
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderSubjects([]);
    return;
  }

  loadSubjectData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#subjectMessageArea");
  dom.filterForm = document.querySelector("#subjectFilterForm");
  dom.keywordInput = document.querySelector("#subjectKeywordInput");
  dom.activeSelect = document.querySelector("#subjectActiveSelect");
  dom.primaryCategorySelect = document.querySelector("#subjectPrimaryCategorySelect");
  dom.categorySelect = document.querySelector("#subjectCategorySelect");
  dom.resetButton = document.querySelector("#subjectResetButton");
  dom.subjectGrid = document.querySelector("#subjectGrid");
  dom.subjectLoadingState = document.querySelector("#subjectLoadingState");
  dom.subjectEmptyState = document.querySelector("#subjectEmptyState");
  dom.subjectCount = document.querySelector("#subjectCount");
  dom.createButton = document.querySelector("#createSubjectButton");
  dom.createDialog = document.querySelector("#createSubjectProfileDialog");
  dom.createError = document.querySelector("#createSubjectProfileError");
  dom.createNameInput = document.querySelector("#createSubjectNameInput");
  dom.createStatusSelect = document.querySelector("#createSubjectStatusSelect");
  dom.createPrimaryCategorySelect = document.querySelector("#createSubjectPrimaryCategorySelect");
  dom.createCategorySelect = document.querySelector("#createSubjectCategorySelect");
  dom.createSortOrderInput = document.querySelector("#createSubjectSortOrderInput");
  dom.createNoteInput = document.querySelector("#createSubjectNoteInput");
  dom.createCancelButton = document.querySelector("#createSubjectCancelButton");
  dom.createSubmitButton = document.querySelector("#createSubjectSubmitButton");
  dom.editDialog = document.querySelector("#editSubjectProfileDialog");
  dom.editError = document.querySelector("#editSubjectProfileError");
  dom.editNameInput = document.querySelector("#editSubjectNameInput");
  dom.editStatusSelect = document.querySelector("#editSubjectStatusSelect");
  dom.editPrimaryCategorySelect = document.querySelector("#editSubjectPrimaryCategorySelect");
  dom.editCategorySelect = document.querySelector("#editSubjectCategorySelect");
  dom.editSortOrderInput = document.querySelector("#editSubjectSortOrderInput");
  dom.editNoteInput = document.querySelector("#editSubjectNoteInput");
  dom.editCancelButton = document.querySelector("#editSubjectCancelButton");
  dom.editSubmitButton = document.querySelector("#editSubjectSubmitButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    applyCurrentFilters();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    applyCurrentFilters();
  });

  dom.createButton.addEventListener("click", openCreateDialog);
  dom.createCancelButton.addEventListener("click", closeCreateDialog);
  dom.createSubmitButton.addEventListener("click", submitCreateDialog);
  dom.createNameInput.addEventListener("input", () => {
    clearCreateFieldInvalid("name");
    hideCreateErrorIfClean();
  });
  dom.createStatusSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("status");
    hideCreateErrorIfClean();
  });
  dom.createPrimaryCategorySelect.addEventListener("change", () => {
    clearCreateFieldInvalid("primaryCategory");
    hideCreateErrorIfClean();
  });
  dom.createCategorySelect.addEventListener("change", () => {
    clearCreateFieldInvalid("category");
    hideCreateErrorIfClean();
  });
  dom.createSortOrderInput.addEventListener("input", () => {
    clearCreateFieldInvalid("sortOrder");
    hideCreateErrorIfClean();
  });

  dom.subjectGrid.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-subject-id]");
    if (!button) {
      return;
    }

    openEditDialog(button.dataset.editSubjectId);
  });

  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditDialog);
  dom.editNameInput.addEventListener("input", () => {
    clearEditFieldInvalid("name");
    hideEditErrorIfClean();
  });
  dom.editStatusSelect.addEventListener("change", () => {
    clearEditFieldInvalid("status");
    hideEditErrorIfClean();
  });
  dom.editPrimaryCategorySelect.addEventListener("change", () => {
    clearEditFieldInvalid("primaryCategory");
    hideEditErrorIfClean();
  });
  dom.editCategorySelect.addEventListener("change", () => {
    clearEditFieldInvalid("category");
    hideEditErrorIfClean();
  });
  dom.editSortOrderInput.addEventListener("input", () => {
    clearEditFieldInvalid("sortOrder");
    hideEditErrorIfClean();
  });
}

function setDefaultFilters() {
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
  dom.activeSelect.value = DEFAULT_FILTERS.activeState;
  dom.primaryCategorySelect.value = DEFAULT_FILTERS.primaryCategory;
  dom.categorySelect.value = DEFAULT_FILTERS.category;
}

async function loadSubjectData() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  setLoading(true);
  showMessage("info", "正在加载科目管理数据...");

  try {
    allSubjects = sortSubjects(await fetchSubjects());
    renderFilterOptions(allSubjects);
    restoreFilterSelections(filters);
    applyCurrentFilters();
    showMessage("success", "科目管理数据已加载。");
  } catch (error) {
    allSubjects = [];
    renderFilterOptions([]);
    renderSubjects([]);
    showMessage("error", `读取科目管理数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function applyCurrentFilters() {
  const filters = readFilters();
  restoreFilterSelections(filters);
  renderSubjects(filterSubjects(allSubjects, filters));
}

function readFilters() {
  return {
    keyword: dom.keywordInput.value.trim(),
    activeState: dom.activeSelect.value,
    primaryCategory: dom.primaryCategorySelect.value,
    category: dom.categorySelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.keywordInput.value = filters.keyword;
  dom.activeSelect.value = filters.activeState;
  dom.primaryCategorySelect.value = filters.primaryCategory;
  dom.categorySelect.value = filters.category;
}

function renderFilterOptions(subjects) {
  renderSelectOptions(dom.primaryCategorySelect, subjects, "primary_category");
  renderSelectOptions(dom.categorySelect, subjects, "category");
}

function renderSelectOptions(selectEl, subjects, key) {
  const options = ['<option value="">全部</option>'];

  if (subjects.some((subject) => !safeText(subject[key]).trim())) {
    options.push(`<option value="${UNSET_VALUE}">未设置</option>`);
  }

  for (const value of distinctValues(subjects, key)) {
    options.push(
      `<option value="${escapeAttribute(value)}">${escapeHtml(displayValue(value))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function renderSubjects(subjects) {
  dom.subjectCount.textContent = `共 ${subjects.length} 条`;
  dom.subjectEmptyState.classList.toggle("is-hidden", subjects.length > 0);

  if (!subjects.length) {
    dom.subjectGrid.innerHTML = "";
    return;
  }

  dom.subjectGrid.innerHTML = subjects.map((subject) => {
    return `
      <article class="subject-card">
        <div class="subject-card-header">
          <div>
            <div class="subject-title">${escapeHtml(displayValue(subject.name))}</div>
          </div>
          <span class="status-badge ${subject.is_active === false ? "status-inactive" : "status-active"}">
            ${subject.is_active === false ? "停用" : "启用"}
          </span>
        </div>

        <div class="table-actions">
          <button class="button" type="button" data-edit-subject-id="${escapeAttribute(subject.id)}">编辑基础信息</button>
        </div>

        <dl class="subject-meta">
          <div>
            <dt>一级分类</dt>
            <dd>${escapeHtml(displayValue(subject.primary_category))}</dd>
          </div>
          <div>
            <dt>二级分类</dt>
            <dd>${escapeHtml(displayValue(subject.category))}</dd>
          </div>
          <div>
            <dt>排序</dt>
            <dd>${escapeHtml(displayValue(subject.sort_order))}</dd>
          </div>
          <div>
            <dt>备注</dt>
            <dd class="subject-note">${escapeHtml(displayValue(subject.note))}</dd>
          </div>
          <div>
            <dt>更新时间</dt>
            <dd>${escapeHtml(formatDate(subject.updated_at))}</dd>
          </div>
        </dl>
      </article>
    `;
  }).join("");
}

function openCreateDialog() {
  clearCreateErrors();
  setCreateSubmitting(false);
  dom.createNameInput.value = "";
  renderCreateStatusOptions("active");
  renderPrimaryCategoryOptions(dom.createPrimaryCategorySelect, "班课");
  renderSecondaryCategoryOptions(dom.createCategorySelect, "学部进学");
  dom.createSortOrderInput.value = "0";
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

  const payload = {
    name: dom.createNameInput.value.trim(),
    status: dom.createStatusSelect.value,
    primaryCategory: dom.createPrimaryCategorySelect.value,
    category: dom.createCategorySelect.value,
    tertiaryCategory: null,
    color: null,
    sortOrder: parseOptionalInteger(dom.createSortOrderInput.value),
    note: dom.createNoteInput.value.trim(),
  };

  if (!payload.name) {
    showCreateError("请输入科目名称。", ["name"]);
    return;
  }

  if (!payload.status) {
    showCreateError("请选择科目状态。", ["status"]);
    return;
  }

  if (!EDITABLE_STATUS_OPTIONS.includes(payload.status)) {
    showCreateError("请选择有效科目状态。", ["status"]);
    return;
  }

  if (!PRIMARY_CATEGORY_OPTIONS.includes(payload.primaryCategory)) {
    showCreateError("请选择有效一级分类。", ["primaryCategory"]);
    return;
  }

  if (!SECONDARY_CATEGORY_OPTIONS.includes(payload.category)) {
    showCreateError("请选择有效二级分类。", ["category"]);
    return;
  }

  if (payload.sortOrder === null) {
    showCreateError("排序需为 0 或正整数。", ["sortOrder"]);
    return;
  }

  setCreateSubmitting(true);

  try {
    await createSubjectProfile(payload);
    closeCreateDialog({ force: true });
    await reloadSubjectDataPreservingViewport();
    showMessage("success", "科目已新增，可用于未来录入和筛选。");
  } catch (error) {
    showCreateError(error.message || String(error), createFieldIdsForError(error));
  } finally {
    setCreateSubmitting(false);
  }
}

function openEditDialog(subjectId) {
  const subject = allSubjects.find((item) => item.id === subjectId);
  if (!subject) {
    showMessage("error", "没有找到要编辑的科目。");
    return;
  }

  editingSubject = subject;
  dom.editNameInput.value = subject.name || "";
  renderEditStatusOptions(subject.is_active === false ? "inactive" : "active");
  renderPrimaryCategoryOptions(dom.editPrimaryCategorySelect, subject.primary_category || "班课", { preserveCurrent: true });
  renderSecondaryCategoryOptions(dom.editCategorySelect, subject.category || "学部进学", { preserveCurrent: true });
  dom.editSortOrderInput.value = String(subject.sort_order ?? 0);
  dom.editNoteInput.value = subject.note || "";
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

  editingSubject = null;
  dom.editDialog.classList.add("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "true");
}

async function submitEditDialog() {
  if (isEditSubmitting) {
    return;
  }

  clearEditErrors();

  if (!editingSubject) {
    showEditError("没有找到要编辑的科目。");
    return;
  }

  const payload = {
    subjectId: editingSubject.id,
    name: dom.editNameInput.value.trim(),
    status: dom.editStatusSelect.value,
    primaryCategory: dom.editPrimaryCategorySelect.value,
    category: dom.editCategorySelect.value,
    tertiaryCategory: editingSubject.tertiary_category || null,
    color: editingSubject.color || null,
    sortOrder: parseOptionalInteger(dom.editSortOrderInput.value),
    note: dom.editNoteInput.value.trim(),
  };

  if (!payload.name) {
    showEditError("请输入科目名称。", ["name"]);
    return;
  }

  if (!payload.status) {
    showEditError("请选择科目状态。", ["status"]);
    return;
  }

  if (!EDITABLE_STATUS_OPTIONS.includes(payload.status)) {
    showEditError("请选择有效科目状态。", ["status"]);
    return;
  }

  if (!isAllowedCurrentValue(payload.primaryCategory, PRIMARY_CATEGORY_OPTIONS, editingSubject.primary_category)) {
    showEditError("请选择有效一级分类。", ["primaryCategory"]);
    return;
  }

  if (!isAllowedCurrentValue(payload.category, SECONDARY_CATEGORY_OPTIONS, editingSubject.category)) {
    showEditError("请选择有效二级分类。", ["category"]);
    return;
  }

  if (payload.sortOrder === null) {
    showEditError("排序需为 0 或正整数。", ["sortOrder"]);
    return;
  }

  setEditSubmitting(true);

  try {
    await updateSubjectProfile(payload);
    closeEditDialog({ force: true });
    await reloadSubjectDataPreservingViewport();
    showMessage("success", "科目基础信息已更新。");
  } catch (error) {
    showEditError(error.message || String(error), editFieldIdsForError(error));
  } finally {
    setEditSubmitting(false);
  }
}

function renderEditStatusOptions(selectedStatus) {
  dom.editStatusSelect.innerHTML = EDITABLE_STATUS_OPTIONS
    .map((status) => `<option value="${escapeAttribute(status)}">${escapeHtml(subjectStatusLabel(status))}</option>`)
    .join("");
  dom.editStatusSelect.value = selectedStatus || "active";
}

function renderCreateStatusOptions(selectedStatus) {
  dom.createStatusSelect.innerHTML = EDITABLE_STATUS_OPTIONS
    .map((status) => `<option value="${escapeAttribute(status)}">${escapeHtml(subjectStatusLabel(status))}</option>`)
    .join("");
  dom.createStatusSelect.value = selectedStatus || "active";
}

function renderPrimaryCategoryOptions(selectEl, selectedValue, options = {}) {
  renderFixedOptions(selectEl, PRIMARY_CATEGORY_OPTIONS, selectedValue || PRIMARY_CATEGORY_OPTIONS[0], options);
}

function renderSecondaryCategoryOptions(selectEl, selectedValue, options = {}) {
  renderFixedOptions(selectEl, SECONDARY_CATEGORY_OPTIONS, selectedValue || SECONDARY_CATEGORY_OPTIONS[0], options);
}

function renderFixedOptions(selectEl, options, selectedValue, { preserveCurrent = false } = {}) {
  const optionValues = preserveCurrent && selectedValue && !options.includes(selectedValue)
    ? [selectedValue, ...options]
    : options;

  selectEl.innerHTML = optionValues
    .map((option) => `<option value="${escapeAttribute(option)}">${escapeHtml(option)}</option>`)
    .join("");
  selectEl.value = optionValues.includes(selectedValue) ? selectedValue : options[0];
}

function isAllowedCurrentValue(value, options, currentValue) {
  return options.includes(value) || (safeText(value) && value === safeText(currentValue));
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
  const hasInvalidField = document.querySelector("[data-create-subject-field].is-invalid");
  if (!hasInvalidField) {
    dom.createError.textContent = "";
    dom.createError.classList.add("is-hidden");
  }
}

function setCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-subject-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-subject-field="${fieldId}"]`);
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
  if (message.includes("名称")) return ["name"];
  if (message.includes("状态")) return ["status"];
  if (message.includes("一级分类")) return ["primaryCategory"];
  if (message.includes("二级分类") || message.includes("分类")) return ["category"];
  if (message.includes("排序")) return ["sortOrder"];
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
  ["name", "status", "primaryCategory", "category", "sortOrder"].forEach(clearEditFieldInvalid);
}

function hideEditErrorIfClean() {
  const hasInvalidField = document.querySelector("[data-edit-subject-field].is-invalid");
  if (!hasInvalidField) {
    dom.editError.textContent = "";
    dom.editError.classList.add("is-hidden");
  }
}

function setEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-subject-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-subject-field="${fieldId}"]`);
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
  if (message.includes("名称")) return ["name"];
  if (message.includes("状态")) return ["status"];
  if (message.includes("一级分类")) return ["primaryCategory"];
  if (message.includes("二级分类") || message.includes("分类")) return ["category"];
  if (message.includes("排序")) return ["sortOrder"];
  return [];
}

async function reloadSubjectDataPreservingViewport() {
  const scrollX = window.scrollX;
  const scrollY = window.scrollY;
  await loadSubjectData();
  window.scrollTo(scrollX, scrollY);
}

function parseOptionalInteger(value) {
  const text = safeText(value).trim();
  if (!text) {
    return 0;
  }

  if (!/^[0-9]+$/.test(text)) {
    return null;
  }

  return Number.parseInt(text, 10);
}

function filterSubjects(subjects, filters) {
  return subjects.filter((subject) => {
    if (filters.activeState === "active" && subject.is_active === false) {
      return false;
    }

    if (filters.activeState === "inactive" && subject.is_active !== false) {
      return false;
    }

    if (!matchesSelectFilter(subject.primary_category, filters.primaryCategory)) {
      return false;
    }

    if (!matchesSelectFilter(subject.category, filters.category)) {
      return false;
    }

    return matchesKeyword(subject, filters.keyword);
  });
}

function matchesSelectFilter(value, filterValue) {
  if (!filterValue) {
    return true;
  }

  const text = safeText(value).trim();
  if (filterValue === UNSET_VALUE) {
    return !text;
  }

  return text === filterValue;
}

function matchesKeyword(subject, keyword) {
  if (!keyword) {
    return true;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return [
    subject.name,
    subject.note,
    subject.category,
    subject.primary_category,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function sortSubjects(subjects) {
  return [...subjects].sort((left, right) => {
    const leftOrder = Number(left.sort_order);
    const rightOrder = Number(right.sort_order);
    const leftHasOrder = Number.isFinite(leftOrder);
    const rightHasOrder = Number.isFinite(rightOrder);

    if (leftHasOrder && rightHasOrder && leftOrder !== rightOrder) {
      return leftOrder - rightOrder;
    }

    if (leftHasOrder !== rightHasOrder) {
      return leftHasOrder ? -1 : 1;
    }

    const createdCompare = safeText(left.created_at).localeCompare(safeText(right.created_at));
    if (createdCompare !== 0) {
      return createdCompare;
    }

    return safeText(left.name).localeCompare(safeText(right.name), "zh-CN");
  });
}

function distinctValues(subjects, key) {
  return Array.from(
    new Set(
      subjects
        .map((subject) => safeText(subject[key]).trim())
        .filter(Boolean)
    )
  ).sort((left, right) => left.localeCompare(right, "zh-CN"));
}

function displayValue(value) {
  return safeText(value) || "未设置";
}

function subjectStatusLabel(status) {
  if (status === "inactive") {
    return "停用";
  }

  return "启用";
}

function setLoading(isLoading) {
  dom.subjectLoadingState.classList.toggle("is-hidden", !isLoading);
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
