import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createBusinessEntityProfile,
  fetchBusinessEntities,
  updateBusinessEntityProfile,
} from "../api/business-entity-api.js";
import { formatDate, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  keyword: "",
  entityType: "",
  defaultCurrency: "",
  activeState: "",
  companyReportState: "",
};

const ENTITY_TYPE_LABELS = {
  company: "公司",
  personal: "个人",
};

const EDITABLE_ENTITY_TYPE_OPTIONS = ["company", "personal"];
const EDITABLE_CURRENCY_OPTIONS = ["JPY", "CNY"];
const CREATE_FIELD_IDS = ["code", "name", "entityType", "defaultCurrency", "active"];

const dom = {};
let allBusinessEntities = [];
let editingEntity = null;
let isEditSubmitting = false;
let isCreateSubmitting = false;

export function initBusinessEntityPage() {
  cacheDom();
  setDefaultFilters();
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderBusinessEntities([]);
    return;
  }

  loadBusinessEntityData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#businessEntityMessageArea");
  dom.filterForm = document.querySelector("#businessEntityFilterForm");
  dom.keywordInput = document.querySelector("#businessEntityKeywordInput");
  dom.entityTypeSelect = document.querySelector("#businessEntityTypeSelect");
  dom.defaultCurrencySelect = document.querySelector("#businessEntityDefaultCurrencySelect");
  dom.activeSelect = document.querySelector("#businessEntityActiveSelect");
  dom.companyReportSelect = document.querySelector("#businessEntityCompanyReportSelect");
  dom.resetButton = document.querySelector("#businessEntityResetButton");
  dom.entityGrid = document.querySelector("#businessEntityGrid");
  dom.loadingState = document.querySelector("#businessEntityLoadingState");
  dom.emptyState = document.querySelector("#businessEntityEmptyState");
  dom.entityCount = document.querySelector("#businessEntityCount");
  dom.createButton = document.querySelector("#createBusinessEntityButton");
  dom.createDialog = document.querySelector("#createBusinessEntityProfileDialog");
  dom.createError = document.querySelector("#createBusinessEntityProfileError");
  dom.createCodeInput = document.querySelector("#createBusinessEntityCodeInput");
  dom.createNameInput = document.querySelector("#createBusinessEntityNameInput");
  dom.createEntityTypeSelect = document.querySelector("#createBusinessEntityTypeSelect");
  dom.createDefaultCurrencySelect = document.querySelector("#createBusinessEntityDefaultCurrencySelect");
  dom.createActiveSelect = document.querySelector("#createBusinessEntityActiveSelect");
  dom.createNoteInput = document.querySelector("#createBusinessEntityNoteInput");
  dom.createCancelButton = document.querySelector("#createBusinessEntityCancelButton");
  dom.createSubmitButton = document.querySelector("#createBusinessEntitySubmitButton");
  dom.editDialog = document.querySelector("#editBusinessEntityProfileDialog");
  dom.editSummary = document.querySelector("#editBusinessEntityProfileSummary");
  dom.editError = document.querySelector("#editBusinessEntityProfileError");
  dom.editNameInput = document.querySelector("#editBusinessEntityNameInput");
  dom.editEntityTypeSelect = document.querySelector("#editBusinessEntityTypeSelect");
  dom.editDefaultCurrencySelect = document.querySelector("#editBusinessEntityDefaultCurrencySelect");
  dom.editActiveSelect = document.querySelector("#editBusinessEntityActiveSelect");
  dom.editNoteInput = document.querySelector("#editBusinessEntityNoteInput");
  dom.editCancelButton = document.querySelector("#editBusinessEntityCancelButton");
  dom.editSubmitButton = document.querySelector("#editBusinessEntitySubmitButton");
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
  dom.createCodeInput.addEventListener("input", () => {
    clearCreateFieldInvalid("code");
    hideCreateErrorIfClean();
  });
  dom.createNameInput.addEventListener("input", () => {
    clearCreateFieldInvalid("name");
    hideCreateErrorIfClean();
  });
  dom.createEntityTypeSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("entityType");
    hideCreateErrorIfClean();
  });
  dom.createDefaultCurrencySelect.addEventListener("change", () => {
    clearCreateFieldInvalid("defaultCurrency");
    hideCreateErrorIfClean();
  });
  dom.createActiveSelect.addEventListener("change", () => {
    clearCreateFieldInvalid("active");
    hideCreateErrorIfClean();
  });

  dom.entityGrid.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-business-entity-id]");
    if (!button) {
      return;
    }

    openEditDialog(button.dataset.editBusinessEntityId);
  });

  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditDialog);
  dom.editNameInput.addEventListener("input", () => {
    clearEditFieldInvalid("name");
    hideEditErrorIfClean();
  });
  dom.editEntityTypeSelect.addEventListener("change", () => {
    clearEditFieldInvalid("entityType");
    hideEditErrorIfClean();
  });
  dom.editDefaultCurrencySelect.addEventListener("change", () => {
    clearEditFieldInvalid("defaultCurrency");
    hideEditErrorIfClean();
  });
  dom.editActiveSelect.addEventListener("change", () => {
    clearEditFieldInvalid("active");
    hideEditErrorIfClean();
  });
}

function setDefaultFilters() {
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
  dom.entityTypeSelect.value = DEFAULT_FILTERS.entityType;
  dom.defaultCurrencySelect.value = DEFAULT_FILTERS.defaultCurrency;
  dom.activeSelect.value = DEFAULT_FILTERS.activeState;
  dom.companyReportSelect.value = DEFAULT_FILTERS.companyReportState;
}

async function loadBusinessEntityData() {
  setLoading(true);
  showMessage("info", "正在加载业务归属数据...");

  try {
    allBusinessEntities = sortBusinessEntities(await fetchBusinessEntities());
    renderFilterOptions(allBusinessEntities);
    restoreFilterSelections(readFilters());
    applyCurrentFilters();
    showMessage("success", "业务归属数据已加载。");
  } catch (error) {
    allBusinessEntities = [];
    renderFilterOptions([]);
    renderBusinessEntities([]);
    showMessage("error", `读取业务归属数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function applyCurrentFilters() {
  const filters = readFilters();
  restoreFilterSelections(filters);
  renderBusinessEntities(filterBusinessEntities(allBusinessEntities, filters));
}

function readFilters() {
  return {
    keyword: dom.keywordInput.value.trim(),
    entityType: dom.entityTypeSelect.value,
    defaultCurrency: dom.defaultCurrencySelect.value,
    activeState: dom.activeSelect.value,
    companyReportState: dom.companyReportSelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.keywordInput.value = filters.keyword;
  dom.entityTypeSelect.value = filters.entityType;
  dom.defaultCurrencySelect.value = filters.defaultCurrency;
  dom.activeSelect.value = filters.activeState;
  dom.companyReportSelect.value = filters.companyReportState;
}

function renderFilterOptions(entities) {
  renderValueOptions(dom.entityTypeSelect, distinctValues(entities, "entity_type"), entityTypeLabel);
  renderValueOptions(dom.defaultCurrencySelect, distinctValues(entities, "default_currency"), displayValue);
}

function renderValueOptions(selectEl, values, labelGetter) {
  const options = ['<option value="">全部</option>'];

  for (const value of values) {
    options.push(
      `<option value="${escapeAttribute(value)}">${escapeHtml(labelGetter(value))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function renderBusinessEntities(entities) {
  dom.entityCount.textContent = `${entities.length} 个`;
  dom.emptyState.classList.toggle("is-hidden", entities.length > 0);

  if (!entities.length) {
    dom.entityGrid.innerHTML = "";
    return;
  }

  dom.entityGrid.innerHTML = entities.map((entity) => `
    <article class="business-entity-card">
      <div class="business-entity-card-header">
        <div>
          <div class="business-entity-name">${escapeHtml(displayValue(entity.name))}</div>
          <div class="business-entity-code">${escapeHtml(displayValue(entity.code))}</div>
        </div>
        <span class="status-badge ${entity.is_active === false ? "status-inactive" : "status-active"}">
          ${entity.is_active === false ? "停用" : "启用"}
        </span>
      </div>

      <div class="table-actions">
        <button class="button" type="button" data-edit-business-entity-id="${escapeAttribute(entity.id)}">编辑基础信息</button>
      </div>

      <dl class="business-entity-meta">
        <div>
          <dt>类型</dt>
          <dd>${escapeHtml(entityTypeLabel(entity.entity_type))}</dd>
        </div>
        <div>
          <dt>默认币种</dt>
          <dd>${escapeHtml(displayValue(entity.default_currency))}</dd>
        </div>
        <div>
          <dt>公司报表</dt>
          <dd>${escapeHtml(booleanLabel(entity.is_company_report))}</dd>
        </div>
        <div>
          <dt>创建时间</dt>
          <dd>${escapeHtml(formatDate(entity.created_at))}</dd>
        </div>
        <div>
          <dt>更新时间</dt>
          <dd>${escapeHtml(formatDate(entity.updated_at))}</dd>
        </div>
        <div>
          <dt>备注</dt>
          <dd class="business-entity-note"><span class="table-cell-summary">${escapeHtml(displayValue(entity.note))}</span></dd>
        </div>
      </dl>
    </article>
  `).join("");
}

function openCreateDialog() {
  clearCreateErrors();
  setCreateSubmitting(false);
  dom.createCodeInput.value = "";
  dom.createNameInput.value = "";
  renderCreateEntityTypeOptions("company");
  renderCreateCurrencyOptions("JPY");
  dom.createActiveSelect.value = "true";
  dom.createNoteInput.value = "";
  dom.createDialog.classList.remove("is-hidden");
  dom.createDialog.setAttribute("aria-hidden", "false");
  dom.createCodeInput.focus();
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
    code: dom.createCodeInput.value.trim(),
    name: dom.createNameInput.value.trim(),
    entityType: dom.createEntityTypeSelect.value,
    defaultCurrency: dom.createDefaultCurrencySelect.value,
    isActive: dom.createActiveSelect.value === "true",
    note: dom.createNoteInput.value.trim(),
  };

  if (!payload.code) {
    showCreateError("请输入业务归属编码。", ["code"]);
    return;
  }

  if (!payload.name) {
    showCreateError("请输入业务归属名称。", ["name"]);
    return;
  }

  if (!EDITABLE_ENTITY_TYPE_OPTIONS.includes(payload.entityType)) {
    showCreateError("请选择有效业务归属类型。", ["entityType"]);
    return;
  }

  if (!EDITABLE_CURRENCY_OPTIONS.includes(payload.defaultCurrency)) {
    showCreateError("请选择有效默认币种。", ["defaultCurrency"]);
    return;
  }

  if (!["true", "false"].includes(dom.createActiveSelect.value)) {
    showCreateError("请选择启用状态。", ["active"]);
    return;
  }

  setCreateSubmitting(true);

  try {
    await createBusinessEntityProfile(payload);
    closeCreateDialog({ force: true });
    await loadBusinessEntityData();
    showMessage("success", "业务归属已新增，可用于未来筛选和主数据配置。");
  } catch (error) {
    showCreateError(error.message || String(error), createFieldIdsForError(error));
  } finally {
    setCreateSubmitting(false);
  }
}

function openEditDialog(entityId) {
  const entity = allBusinessEntities.find((item) => item.id === entityId);
  if (!entity) {
    showMessage("error", "没有找到要编辑的业务归属。");
    return;
  }

  editingEntity = entity;
  dom.editSummary.innerHTML = renderEditSummary(entity);
  dom.editNameInput.value = entity.name || "";
  renderEditEntityTypeOptions(entity.entity_type);
  renderEditCurrencyOptions(entity.default_currency);
  dom.editActiveSelect.value = entity.is_active === false ? "false" : "true";
  dom.editNoteInput.value = entity.note || "";
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

  editingEntity = null;
  dom.editDialog.classList.add("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "true");
}

async function submitEditDialog() {
  if (isEditSubmitting) {
    return;
  }

  clearEditErrors();

  if (!editingEntity) {
    showEditError("没有找到要编辑的业务归属。");
    return;
  }

  const payload = {
    businessEntityId: editingEntity.id,
    name: dom.editNameInput.value.trim(),
    entityType: dom.editEntityTypeSelect.value,
    defaultCurrency: dom.editDefaultCurrencySelect.value,
    isActive: dom.editActiveSelect.value === "true",
    note: dom.editNoteInput.value.trim(),
  };

  if (!payload.name) {
    showEditError("请输入业务归属名称。", ["name"]);
    return;
  }

  if (!EDITABLE_ENTITY_TYPE_OPTIONS.includes(payload.entityType)) {
    showEditError("请选择有效业务归属类型。", ["entityType"]);
    return;
  }

  if (!EDITABLE_CURRENCY_OPTIONS.includes(payload.defaultCurrency)) {
    showEditError("请选择有效默认币种。", ["defaultCurrency"]);
    return;
  }

  if (!["true", "false"].includes(dom.editActiveSelect.value)) {
    showEditError("请选择启用状态。", ["active"]);
    return;
  }

  setEditSubmitting(true);

  try {
    await updateBusinessEntityProfile(payload);
    closeEditDialog({ force: true });
    await loadBusinessEntityData();
    showMessage("success", "业务归属基础信息已更新。");
  } catch (error) {
    showEditError(error.message || String(error), editFieldIdsForError(error));
  } finally {
    setEditSubmitting(false);
  }
}

function renderEditSummary(entity) {
  const rows = [
    ["编码", entity.code],
    ["公司报表", booleanLabel(entity.is_company_report)],
    ["不可编辑字段", "编码、公司报表设置、历史收入、支出、账户、结算、工资、支付"],
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

function renderEditEntityTypeOptions(selectedEntityType) {
  dom.editEntityTypeSelect.innerHTML = EDITABLE_ENTITY_TYPE_OPTIONS
    .map((entityType) => `<option value="${escapeAttribute(entityType)}">${escapeHtml(entityTypeLabel(entityType))}</option>`)
    .join("");
  dom.editEntityTypeSelect.value = selectedEntityType || "company";
}

function renderEditCurrencyOptions(selectedCurrency) {
  dom.editDefaultCurrencySelect.innerHTML = EDITABLE_CURRENCY_OPTIONS
    .map((currency) => `<option value="${escapeAttribute(currency)}">${escapeHtml(currency)}</option>`)
    .join("");
  dom.editDefaultCurrencySelect.value = selectedCurrency || "JPY";
}

function renderCreateEntityTypeOptions(selectedEntityType) {
  dom.createEntityTypeSelect.innerHTML = EDITABLE_ENTITY_TYPE_OPTIONS
    .map((entityType) => `<option value="${escapeAttribute(entityType)}">${escapeHtml(entityTypeLabel(entityType))}</option>`)
    .join("");
  dom.createEntityTypeSelect.value = selectedEntityType || "company";
}

function renderCreateCurrencyOptions(selectedCurrency) {
  dom.createDefaultCurrencySelect.innerHTML = EDITABLE_CURRENCY_OPTIONS
    .map((currency) => `<option value="${escapeAttribute(currency)}">${escapeHtml(currency)}</option>`)
    .join("");
  dom.createDefaultCurrencySelect.value = selectedCurrency || "JPY";
}

function showCreateError(message, fieldIds = []) {
  dom.createError.textContent = message;
  dom.createError.classList.remove("is-hidden");
  fieldIds.forEach(setCreateFieldInvalid);
}

function clearCreateErrors() {
  dom.createError.textContent = "";
  dom.createError.classList.add("is-hidden");
  CREATE_FIELD_IDS.forEach(clearCreateFieldInvalid);
}

function hideCreateErrorIfClean() {
  const hasInvalidField = document.querySelector("[data-create-business-entity-field].is-invalid");
  if (!hasInvalidField) {
    dom.createError.textContent = "";
    dom.createError.classList.add("is-hidden");
  }
}

function setCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-business-entity-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-business-entity-field="${fieldId}"]`);
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
  if (message.includes("编码")) return ["code"];
  if (message.includes("名称")) return ["name"];
  if (message.includes("类型")) return ["entityType"];
  if (message.includes("币种")) return ["defaultCurrency"];
  if (message.includes("启用状态")) return ["active"];
  return [];
}

function showEditError(message, fieldIds = []) {
  dom.editError.textContent = message;
  dom.editError.classList.remove("is-hidden");
  fieldIds.forEach(setEditFieldInvalid);
}

function clearEditErrors() {
  dom.editError.textContent = "";
  dom.editError.classList.add("is-hidden");
  ["name", "entityType", "defaultCurrency", "active"].forEach(clearEditFieldInvalid);
}

function hideEditErrorIfClean() {
  const hasInvalidField = document.querySelector("[data-edit-business-entity-field].is-invalid");
  if (!hasInvalidField) {
    dom.editError.textContent = "";
    dom.editError.classList.add("is-hidden");
  }
}

function setEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-business-entity-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-business-entity-field="${fieldId}"]`);
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
  if (message.includes("类型")) return ["entityType"];
  if (message.includes("币种")) return ["defaultCurrency"];
  if (message.includes("启用状态")) return ["active"];
  return [];
}

function filterBusinessEntities(entities, filters) {
  return entities.filter((entity) => {
    if (filters.entityType && entity.entity_type !== filters.entityType) {
      return false;
    }

    if (filters.defaultCurrency && entity.default_currency !== filters.defaultCurrency) {
      return false;
    }

    if (filters.activeState === "active" && entity.is_active !== true) {
      return false;
    }

    if (filters.activeState === "inactive" && entity.is_active !== false) {
      return false;
    }

    if (filters.companyReportState === "included" && entity.is_company_report !== true) {
      return false;
    }

    if (filters.companyReportState === "excluded" && entity.is_company_report !== false) {
      return false;
    }

    return matchesKeyword(entity, filters.keyword);
  });
}

function matchesKeyword(entity, keyword) {
  if (!keyword) {
    return true;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return [
    entity.name,
    entity.code,
    entity.entity_type,
    entityTypeLabel(entity.entity_type),
    entity.default_currency,
    entity.note,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function sortBusinessEntities(entities) {
  return [...entities].sort((left, right) => {
    const nameCompare = safeText(left.name).localeCompare(safeText(right.name), "zh-CN");
    if (nameCompare !== 0) {
      return nameCompare;
    }

    return safeText(left.code).localeCompare(safeText(right.code), "zh-CN");
  });
}

function distinctValues(entities, key) {
  return Array.from(
    new Set(
      entities
        .map((entity) => safeText(entity[key]).trim())
        .filter(Boolean)
    )
  ).sort((left, right) => left.localeCompare(right, "zh-CN"));
}

function entityTypeLabel(value) {
  return ENTITY_TYPE_LABELS[value] || displayValue(value);
}

function booleanLabel(value) {
  if (value === true) {
    return "是";
  }

  if (value === false) {
    return "否";
  }

  return "未设置";
}

function displayValue(value) {
  return safeText(value) || "未设置";
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
