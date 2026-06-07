import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createWageRuleConfig,
  fetchWageRuleLookups,
  fetchWageRules,
  setWageRuleActiveState,
  updateWageRuleConfig,
} from "../api/wage-rule-api.js";
import { formatCurrency, formatDate, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  keyword: "",
  teacherId: "",
  studentId: "",
  subjectId: "",
  businessEntityId: "",
  settlementType: "",
  activeState: "",
  teacherDepartment: "",
};

const SETTLEMENT_TYPE_LABELS = {
  jpy_hourly: "日元时给",
  no_wage: "无工资",
};

const EDITABLE_SETTLEMENT_TYPES = ["jpy_hourly", "no_wage"];
const CREATE_FIELD_IDS = [
  "teacher",
  "student",
  "subject",
  "businessEntity",
  "settlementType",
  "hourlyRateJpy",
  "hourlyRateCny",
  "exchangeRate",
  "transportFeeJpy",
  "classroomFeeJpy",
  "activeState",
];

const TEACHER_STATUS_LABELS = {
  employed: "在职",
  inactive: "停用",
  paused: "暂停",
  resigned: "离职",
  retired: "退职",
};

const dom = {};
let wageRules = [];
let teachers = [];
let students = [];
let subjects = [];
let businessEntities = [];
let editingWageRule = null;
let activeStateTargetRule = null;
let isCreateSubmitting = false;
let isEditSubmitting = false;
let isActiveStateSubmitting = false;

export function initWageRulePage() {
  cacheDom();
  setDefaultFilters();
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderWageRules([]);
    return;
  }

  loadWageRuleData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#wageRuleMessageArea");
  dom.filterForm = document.querySelector("#wageRuleFilterForm");
  dom.keywordInput = document.querySelector("#wageRuleKeywordInput");
  dom.teacherSelect = document.querySelector("#wageRuleTeacherSelect");
  dom.studentSelect = document.querySelector("#wageRuleStudentSelect");
  dom.subjectSelect = document.querySelector("#wageRuleSubjectSelect");
  dom.businessEntitySelect = document.querySelector("#wageRuleBusinessEntitySelect");
  dom.settlementTypeSelect = document.querySelector("#wageRuleSettlementTypeSelect");
  dom.activeSelect = document.querySelector("#wageRuleActiveSelect");
  dom.teacherDepartmentSelect = document.querySelector("#wageRuleTeacherDepartmentSelect");
  dom.resetButton = document.querySelector("#wageRuleResetButton");
  dom.tableBody = document.querySelector("#wageRuleTableBody");
  dom.loadingState = document.querySelector("#wageRuleLoadingState");
  dom.emptyState = document.querySelector("#wageRuleEmptyState");
  dom.ruleCount = document.querySelector("#wageRuleCount");
  dom.createButton = document.querySelector("#createWageRuleButton");
  dom.createDialog = document.querySelector("#createWageRuleConfigDialog");
  dom.createError = document.querySelector("#createWageRuleConfigError");
  dom.createTeacherSelect = document.querySelector("#createWageRuleTeacherSelect");
  dom.createStudentSelect = document.querySelector("#createWageRuleStudentSelect");
  dom.createSubjectSelect = document.querySelector("#createWageRuleSubjectSelect");
  dom.createBusinessEntitySelect = document.querySelector("#createWageRuleBusinessEntitySelect");
  dom.createSettlementTypeSelect = document.querySelector("#createWageRuleSettlementTypeSelect");
  dom.createHourlyRateJpyInput = document.querySelector("#createWageRuleHourlyRateJpyInput");
  dom.createHourlyRateCnyInput = document.querySelector("#createWageRuleHourlyRateCnyInput");
  dom.createExchangeRateInput = document.querySelector("#createWageRuleExchangeRateInput");
  dom.createTransportFeeJpyInput = document.querySelector("#createWageRuleTransportFeeJpyInput");
  dom.createClassroomFeeJpyInput = document.querySelector("#createWageRuleClassroomFeeJpyInput");
  dom.createActiveSelect = document.querySelector("#createWageRuleActiveSelect");
  dom.createNoteInput = document.querySelector("#createWageRuleNoteInput");
  dom.createSubmitButton = document.querySelector("#createWageRuleSubmitButton");
  dom.createCancelButton = document.querySelector("#createWageRuleCancelButton");
  dom.editDialog = document.querySelector("#editWageRuleConfigDialog");
  dom.editSummary = document.querySelector("#editWageRuleConfigSummary");
  dom.editError = document.querySelector("#editWageRuleConfigError");
  dom.editSettlementTypeSelect = document.querySelector("#editWageRuleSettlementTypeSelect");
  dom.editHourlyRateJpyInput = document.querySelector("#editWageRuleHourlyRateJpyInput");
  dom.editHourlyRateCnyInput = document.querySelector("#editWageRuleHourlyRateCnyInput");
  dom.editExchangeRateInput = document.querySelector("#editWageRuleExchangeRateInput");
  dom.editTransportFeeJpyInput = document.querySelector("#editWageRuleTransportFeeJpyInput");
  dom.editClassroomFeeJpyInput = document.querySelector("#editWageRuleClassroomFeeJpyInput");
  dom.editActiveSelect = document.querySelector("#editWageRuleActiveSelect");
  dom.editNoteInput = document.querySelector("#editWageRuleNoteInput");
  dom.editSubmitButton = document.querySelector("#editWageRuleSubmitButton");
  dom.editCancelButton = document.querySelector("#editWageRuleCancelButton");
  dom.activeStateDialog = document.querySelector("#wageRuleActiveStateDialog");
  dom.activeStateTitle = document.querySelector("#wageRuleActiveStateTitle");
  dom.activeStateDescription = document.querySelector("#wageRuleActiveStateDescription");
  dom.activeStateSummary = document.querySelector("#wageRuleActiveStateSummary");
  dom.activeStateError = document.querySelector("#wageRuleActiveStateError");
  dom.activeStateNoteInput = document.querySelector("#wageRuleActiveStateNoteInput");
  dom.activeStateConfirmCheck = document.querySelector("#wageRuleActiveStateConfirmCheck");
  dom.activeStateSubmitButton = document.querySelector("#wageRuleActiveStateSubmitButton");
  dom.activeStateCancelButton = document.querySelector("#wageRuleActiveStateCancelButton");
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

  [
    dom.createTeacherSelect,
    dom.createStudentSelect,
    dom.createSubjectSelect,
    dom.createBusinessEntitySelect,
    dom.createSettlementTypeSelect,
    dom.createHourlyRateJpyInput,
    dom.createHourlyRateCnyInput,
    dom.createExchangeRateInput,
    dom.createTransportFeeJpyInput,
    dom.createClassroomFeeJpyInput,
    dom.createActiveSelect,
  ].forEach((field) => {
    field.addEventListener("input", hideCreateErrorIfClean);
    field.addEventListener("change", handleCreateFieldChange);
  });

  dom.tableBody.addEventListener("click", (event) => {
    const editButton = event.target.closest("[data-edit-wage-rule-id]");
    if (editButton) {
      openEditDialog(editButton.dataset.editWageRuleId);
      return;
    }

    const activeStateButton = event.target.closest("[data-active-state-wage-rule-id]");
    if (activeStateButton) {
      openActiveStateDialog(activeStateButton.dataset.activeStateWageRuleId);
    }
  });

  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditDialog);
  dom.activeStateCancelButton.addEventListener("click", closeActiveStateDialog);
  dom.activeStateSubmitButton.addEventListener("click", submitActiveStateDialog);
  dom.activeStateNoteInput.addEventListener("input", hideActiveStateErrorIfClean);
  dom.activeStateConfirmCheck.addEventListener("change", hideActiveStateErrorIfClean);

  [
    dom.editSettlementTypeSelect,
    dom.editHourlyRateJpyInput,
    dom.editHourlyRateCnyInput,
    dom.editExchangeRateInput,
    dom.editTransportFeeJpyInput,
    dom.editClassroomFeeJpyInput,
    dom.editActiveSelect,
  ].forEach((field) => {
    field.addEventListener("input", hideEditErrorIfClean);
    field.addEventListener("change", handleEditFieldChange);
  });
}

function setDefaultFilters() {
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
  dom.teacherSelect.value = DEFAULT_FILTERS.teacherId;
  dom.studentSelect.value = DEFAULT_FILTERS.studentId;
  dom.subjectSelect.value = DEFAULT_FILTERS.subjectId;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.settlementTypeSelect.value = DEFAULT_FILTERS.settlementType;
  dom.activeSelect.value = DEFAULT_FILTERS.activeState;
  dom.teacherDepartmentSelect.value = DEFAULT_FILTERS.teacherDepartment;
}

async function loadWageRuleData() {
  setLoading(true);
  showMessage("info", "正在加载老师工资规则数据...");

  try {
    const [lookupRows, ruleRows] = await Promise.all([
      fetchWageRuleLookups(),
      fetchWageRules(),
    ]);

    teachers = lookupRows.teachers;
    students = lookupRows.students;
    subjects = lookupRows.subjects;
    businessEntities = lookupRows.businessEntities;
    wageRules = sortWageRules(ruleRows);

    renderFilterOptions(wageRules);
    restoreFilterSelections(readFilters());
    applyCurrentFilters();
    showMessage("success", "老师工资规则数据已加载。");
  } catch (error) {
    teachers = [];
    students = [];
    subjects = [];
    businessEntities = [];
    wageRules = [];
    renderFilterOptions([]);
    renderWageRules([]);
    showMessage("error", `读取老师工资规则数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function applyCurrentFilters() {
  const filters = readFilters();
  restoreFilterSelections(filters);
  renderWageRules(filterWageRules(wageRules, filters));
}

function readFilters() {
  return {
    keyword: dom.keywordInput.value.trim(),
    teacherId: dom.teacherSelect.value,
    studentId: dom.studentSelect.value,
    subjectId: dom.subjectSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    settlementType: dom.settlementTypeSelect.value,
    activeState: dom.activeSelect.value,
    teacherDepartment: dom.teacherDepartmentSelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.keywordInput.value = filters.keyword;
  dom.teacherSelect.value = filters.teacherId;
  dom.studentSelect.value = filters.studentId;
  dom.subjectSelect.value = filters.subjectId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.settlementTypeSelect.value = filters.settlementType;
  dom.activeSelect.value = filters.activeState;
  dom.teacherDepartmentSelect.value = filters.teacherDepartment;
}

function renderFilterOptions(rows) {
  renderEntityOptions(dom.teacherSelect, teachers, teacherName);
  renderEntityOptions(dom.studentSelect, students, studentName);
  renderEntityOptions(dom.subjectSelect, subjects, subjectName);
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
  renderValueOptions(dom.settlementTypeSelect, distinctValues(rows, "settlement_type"), settlementTypeLabel);
  renderValueOptions(dom.teacherDepartmentSelect, distinctTeacherDepartments(), displayValue);
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

function renderValueOptions(selectEl, values, labelGetter) {
  const options = ['<option value="">全部</option>'];

  for (const value of values) {
    options.push(
      `<option value="${escapeAttribute(value)}">${escapeHtml(labelGetter(value))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function renderWageRules(rows) {
  dom.ruleCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = rows.map((rule) => {
    const teacher = teacherById(rule.teacher_id);

    return `
      <tr>
        <td class="wage-rule-nowrap"><a class="table-action-button" href="./wage-rule-detail.html?id=${encodeURIComponent(rule.id)}">详情</a></td>
        <td class="wage-rule-nowrap"><button class="button table-action-button" type="button" data-edit-wage-rule-id="${escapeAttribute(rule.id)}">编辑</button></td>
        <td class="wage-rule-nowrap">${renderActiveStateAction(rule)}</td>
        <td>${escapeHtml(teacherNameById(rule.teacher_id))}</td>
        <td>${escapeHtml(displayValue(teacher?.department))}</td>
        <td><span class="status-badge status-neutral">${escapeHtml(teacherStatusLabel(teacher?.status))}</span></td>
        <td>${escapeHtml(studentNameById(rule.student_id))}</td>
        <td>${escapeHtml(subjectNameById(rule.subject_id))}</td>
        <td>${escapeHtml(businessNameById(rule.business_entity_id))}</td>
        <td><span class="status-badge status-neutral">${escapeHtml(settlementTypeLabel(rule.settlement_type))}</span></td>
        <td class="number-cell wage-rule-nowrap">${escapeHtml(formatCurrency(rule.hourly_rate_jpy, "JPY"))}</td>
        <td class="number-cell wage-rule-nowrap">${escapeHtml(formatCurrency(rule.hourly_rate_cny, "CNY"))}</td>
        <td class="number-cell wage-rule-nowrap">${escapeHtml(displayValue(rule.exchange_rate))}</td>
        <td class="number-cell wage-rule-nowrap">${escapeHtml(formatCurrency(rule.transport_fee_jpy, "JPY"))}</td>
        <td class="number-cell wage-rule-nowrap">${escapeHtml(formatCurrency(rule.classroom_fee_jpy, "JPY"))}</td>
        <td><span class="status-badge ${escapeAttribute(activeClass(rule.is_active))}">${escapeHtml(activeLabel(rule.is_active))}</span></td>
        <td class="wage-rule-note-cell"><span class="table-cell-summary">${escapeHtml(displayValue(rule.note))}</span></td>
        <td class="wage-rule-nowrap">${escapeHtml(formatDate(rule.created_at))}</td>
        <td class="wage-rule-nowrap">${escapeHtml(formatDate(rule.updated_at))}</td>
      </tr>
    `;
  }).join("");
}

function openCreateDialog() {
  clearCreateErrors();
  setCreateSubmitting(false);
  renderCreateLookupOptions();
  dom.createSettlementTypeSelect.value = "jpy_hourly";
  dom.createHourlyRateJpyInput.value = "0";
  dom.createHourlyRateCnyInput.value = "0";
  dom.createExchangeRateInput.value = "0";
  dom.createTransportFeeJpyInput.value = "0";
  dom.createClassroomFeeJpyInput.value = "0";
  dom.createActiveSelect.value = "active";
  dom.createNoteInput.value = "";
  syncCreateNoWageFields();
  dom.createDialog.classList.remove("is-hidden");
  dom.createDialog.setAttribute("aria-hidden", "false");
  dom.createTeacherSelect.focus();
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
    teacherId: dom.createTeacherSelect.value,
    studentId: dom.createStudentSelect.value,
    subjectId: dom.createSubjectSelect.value,
    businessEntityId: dom.createBusinessEntitySelect.value,
    settlementType: dom.createSettlementTypeSelect.value,
    hourlyRateJpy: readNonNegativeNumber(dom.createHourlyRateJpyInput.value),
    hourlyRateCny: readNonNegativeNumber(dom.createHourlyRateCnyInput.value),
    exchangeRate: readNonNegativeNumber(dom.createExchangeRateInput.value),
    transportFeeJpy: readNonNegativeNumber(dom.createTransportFeeJpyInput.value),
    classroomFeeJpy: readNonNegativeNumber(dom.createClassroomFeeJpyInput.value),
    isActive: dom.createActiveSelect.value === "active",
    note: dom.createNoteInput.value.trim(),
  };

  const invalidFields = validateCreatePayload(payload);
  if (invalidFields.length > 0) {
    showCreateError("请检查老师、学生、科目、业务归属、结算类型、费率、汇率、费用和启用状态。", invalidFields);
    return;
  }

  if (payload.settlementType === "no_wage") {
    payload.hourlyRateJpy = 0;
    payload.hourlyRateCny = 0;
    payload.exchangeRate = 0;
    payload.transportFeeJpy = 0;
    payload.classroomFeeJpy = 0;
  }

  setCreateSubmitting(true);

  try {
    await createWageRuleConfig(payload);
    closeCreateDialog({ force: true });
    await loadWageRuleData();
    showMessage("success", "老师工资规则已新增；仅影响未来工资锁定。");
  } catch (error) {
    showCreateError(error.message || String(error), createFieldIdsForError(error));
  } finally {
    setCreateSubmitting(false);
  }
}

function validateCreatePayload(payload) {
  const invalidFields = [];

  if (!usableTeacherById(payload.teacherId)) {
    invalidFields.push("teacher");
  }

  if (!usableStudentById(payload.studentId)) {
    invalidFields.push("student");
  }

  if (!usableSubjectById(payload.subjectId)) {
    invalidFields.push("subject");
  }

  if (!usableBusinessEntityById(payload.businessEntityId)) {
    invalidFields.push("businessEntity");
  }

  return uniqueFieldIds([...invalidFields, ...validateConfigPayload(payload, dom.createActiveSelect)]);
}

function renderCreateLookupOptions() {
  renderCreateEntityOptions(dom.createTeacherSelect, teachers.filter(isUsableTeacher), teacherName, "请选择老师");
  renderCreateEntityOptions(dom.createStudentSelect, students.filter(isUsableStudent), studentName, "请选择学生");
  renderCreateEntityOptions(dom.createSubjectSelect, subjects.filter(isUsableSubject), subjectName, "请选择科目");
  renderCreateEntityOptions(dom.createBusinessEntitySelect, businessEntities.filter(isUsableBusinessEntity), businessEntityName, "请选择业务归属");
}

function renderCreateEntityOptions(selectEl, rows, labelGetter, placeholder) {
  const options = [`<option value="">${escapeHtml(placeholder)}</option>`];

  for (const row of rows) {
    options.push(
      `<option value="${escapeAttribute(row.id)}">${escapeHtml(labelGetter(row))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function openEditDialog(wageRuleId) {
  const rule = wageRules.find((item) => item.id === wageRuleId);
  if (!rule) {
    showMessage("error", "没有找到要编辑的老师工资规则。");
    return;
  }

  editingWageRule = rule;
  dom.editSummary.innerHTML = renderEditSummary(rule);
  dom.editSettlementTypeSelect.value = rule.settlement_type || "jpy_hourly";
  dom.editHourlyRateJpyInput.value = displayNumberInput(rule.hourly_rate_jpy);
  dom.editHourlyRateCnyInput.value = displayNumberInput(rule.hourly_rate_cny);
  dom.editExchangeRateInput.value = displayNumberInput(rule.exchange_rate);
  dom.editTransportFeeJpyInput.value = displayNumberInput(rule.transport_fee_jpy);
  dom.editClassroomFeeJpyInput.value = displayNumberInput(rule.classroom_fee_jpy);
  dom.editActiveSelect.value = rule.is_active === false ? "inactive" : "active";
  dom.editActiveSelect.disabled = true;
  dom.editNoteInput.value = rule.note || "";
  clearEditErrors();
  setEditSubmitting(false);
  syncNoWageFields();
  dom.editDialog.classList.remove("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "false");
  dom.editSettlementTypeSelect.focus();
}

function openActiveStateDialog(wageRuleId) {
  const rule = wageRules.find((item) => item.id === wageRuleId);
  if (!rule) {
    showMessage("error", "没有找到要更新状态的老师工资规则。");
    return;
  }

  activeStateTargetRule = rule;
  clearActiveStateErrors();
  const willActivate = rule.is_active === false;
  dom.activeStateTitle.textContent = willActivate ? "恢复工资规则" : "停用工资规则";
  dom.activeStateDescription.textContent = willActivate
    ? "恢复后该规则会重新参与未来工资规则匹配；不会重算历史工资锁定，也不会修改支付、支出或账户流水。"
    : "停用后该规则不会参与未来工资规则匹配；历史工资锁定、支付请求、支出和账户流水都会保留。";
  dom.activeStateSummary.innerHTML = renderActiveStateSummary(rule);
  dom.activeStateNoteInput.value = activeStateDefaultNote(rule, willActivate);
  dom.activeStateConfirmCheck.checked = false;
  setActiveStateSubmitting(false);
  dom.activeStateDialog.classList.remove("is-hidden");
  dom.activeStateDialog.setAttribute("aria-hidden", "false");
  dom.activeStateNoteInput.focus();
}

function closeActiveStateDialog({ force = false } = {}) {
  if (isActiveStateSubmitting && !force) {
    return;
  }

  activeStateTargetRule = null;
  dom.activeStateDialog.classList.add("is-hidden");
  dom.activeStateDialog.setAttribute("aria-hidden", "true");
}

async function submitActiveStateDialog() {
  if (isActiveStateSubmitting) {
    return;
  }

  clearActiveStateErrors();

  if (!activeStateTargetRule) {
    showActiveStateError("没有找到要更新状态的老师工资规则。");
    return;
  }

  if (!dom.activeStateConfirmCheck.checked) {
    showActiveStateError("请先勾选确认说明。", ["confirmCheck"]);
    return;
  }

  const payload = {
    wageRuleId: activeStateTargetRule.id,
    isActive: activeStateTargetRule.is_active === false,
    note: dom.activeStateNoteInput.value.trim(),
  };

  setActiveStateSubmitting(true);

  try {
    await setWageRuleActiveState(payload);
    closeActiveStateDialog({ force: true });
    await loadWageRuleData();
    showMessage("success", payload.isActive ? "老师工资规则已恢复；仅影响未来工资锁定。" : "老师工资规则已停用；历史数据已保留。");
  } catch (error) {
    showActiveStateError(error.message || String(error));
  } finally {
    setActiveStateSubmitting(false);
  }
}

function closeEditDialog({ force = false } = {}) {
  if (isEditSubmitting && !force) {
    return;
  }

  editingWageRule = null;
  dom.editDialog.classList.add("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "true");
}

async function submitEditDialog() {
  if (isEditSubmitting) {
    return;
  }

  clearEditErrors();

  if (!editingWageRule) {
    showEditError("没有找到要编辑的老师工资规则。");
    return;
  }

  const payload = {
    wageRuleId: editingWageRule.id,
    settlementType: dom.editSettlementTypeSelect.value,
    hourlyRateJpy: readNonNegativeNumber(dom.editHourlyRateJpyInput.value),
    hourlyRateCny: readNonNegativeNumber(dom.editHourlyRateCnyInput.value),
    exchangeRate: readNonNegativeNumber(dom.editExchangeRateInput.value),
    transportFeeJpy: readNonNegativeNumber(dom.editTransportFeeJpyInput.value),
    classroomFeeJpy: readNonNegativeNumber(dom.editClassroomFeeJpyInput.value),
    isActive: dom.editActiveSelect.value === "active",
    note: dom.editNoteInput.value.trim(),
  };

  const invalidFields = validateEditPayload(payload);
  if (invalidFields.length > 0) {
    showEditError("请检查结算类型、费率、汇率、费用和启用状态。", invalidFields);
    return;
  }

  if (payload.settlementType === "no_wage") {
    payload.hourlyRateJpy = 0;
    payload.hourlyRateCny = 0;
    payload.exchangeRate = 0;
    payload.transportFeeJpy = 0;
    payload.classroomFeeJpy = 0;
  }

  setEditSubmitting(true);

  try {
    await updateWageRuleConfig(payload);
    closeEditDialog({ force: true });
    await loadWageRuleData();
    showMessage("success", "老师工资规则配置已更新；仅影响未来工资锁定。");
  } catch (error) {
    showEditError(error.message || String(error), editFieldIdsForError(error));
  } finally {
    setEditSubmitting(false);
  }
}

function validateEditPayload(payload) {
  return validateConfigPayload(payload, dom.editActiveSelect);
}

function validateConfigPayload(payload, activeSelect) {
  const invalidFields = [];

  if (!EDITABLE_SETTLEMENT_TYPES.includes(payload.settlementType)) {
    invalidFields.push("settlementType");
  }

  [
    ["hourlyRateJpy", payload.hourlyRateJpy],
    ["hourlyRateCny", payload.hourlyRateCny],
    ["exchangeRate", payload.exchangeRate],
    ["transportFeeJpy", payload.transportFeeJpy],
    ["classroomFeeJpy", payload.classroomFeeJpy],
  ].forEach(([fieldId, value]) => {
    if (!Number.isFinite(value) || value < 0) {
      invalidFields.push(fieldId);
    }
  });

  if (!["active", "inactive"].includes(activeSelect.value)) {
    invalidFields.push("activeState");
  }

  return invalidFields;
}

function renderEditSummary(rule) {
  const rows = [
    ["老师", teacherNameById(rule.teacher_id)],
    ["学生", studentNameById(rule.student_id)],
    ["科目", subjectNameById(rule.subject_id)],
    ["业务归属", businessNameById(rule.business_entity_id)],
    ["不可编辑字段", "老师、学生、科目、业务归属、历史工资锁定、支付请求、支出、账户流水"],
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

function renderActiveStateAction(rule) {
  const isInactive = rule.is_active === false;
  const label = isInactive ? "恢复" : "停用";
  const buttonClass = isInactive ? "button table-action-button" : "button button-danger table-action-button";
  return `<button class="${buttonClass}" type="button" data-active-state-wage-rule-id="${escapeAttribute(rule.id)}">${escapeHtml(label)}</button>`;
}

function renderActiveStateSummary(rule) {
  const rows = [
    ["老师", teacherNameById(rule.teacher_id)],
    ["学生", studentNameById(rule.student_id)],
    ["科目", subjectNameById(rule.subject_id)],
    ["业务归属", businessNameById(rule.business_entity_id)],
    ["当前状态", activeLabel(rule.is_active)],
    ["结算类型", settlementTypeLabel(rule.settlement_type)],
    ["当前备注", displayValue(rule.note)],
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

function activeStateDefaultNote(rule, willActivate) {
  return safeText(rule.note);
}

function showActiveStateError(message, fieldIds = []) {
  dom.activeStateError.textContent = message;
  dom.activeStateError.classList.remove("is-hidden");
  fieldIds.forEach(setActiveStateFieldInvalid);
}

function clearActiveStateErrors() {
  dom.activeStateError.textContent = "";
  dom.activeStateError.classList.add("is-hidden");
  clearActiveStateFieldInvalid("confirmCheck");
}

function hideActiveStateErrorIfClean() {
  const hasInvalidField = dom.activeStateDialog.querySelector(".field.is-invalid");
  if (!hasInvalidField) {
    dom.activeStateError.textContent = "";
    dom.activeStateError.classList.add("is-hidden");
  }
}

function setActiveStateFieldInvalid(fieldId) {
  const field = dom.activeStateDialog.querySelector(`[data-wage-rule-active-state-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearActiveStateFieldInvalid(fieldId) {
  const field = dom.activeStateDialog.querySelector(`[data-wage-rule-active-state-field="${fieldId}"]`);
  field?.classList.remove("is-invalid");
}

function setActiveStateSubmitting(isSubmitting) {
  isActiveStateSubmitting = isSubmitting;
  dom.activeStateSubmitButton.disabled = isSubmitting;
  dom.activeStateCancelButton.disabled = isSubmitting;
  dom.activeStateSubmitButton.textContent = isSubmitting ? "处理中..." : "确认";
}

function handleEditFieldChange(event) {
  if (event.currentTarget === dom.editSettlementTypeSelect) {
    syncNoWageFields();
  }

  hideEditErrorIfClean();
}

function handleCreateFieldChange(event) {
  clearCreateFieldInvalid(createFieldIdForElement(event.currentTarget));

  if (event.currentTarget === dom.createSettlementTypeSelect) {
    syncCreateNoWageFields();
  }

  hideCreateErrorIfClean();
}

function syncNoWageFields() {
  const isNoWage = dom.editSettlementTypeSelect.value === "no_wage";
  const amountFields = [
    dom.editHourlyRateJpyInput,
    dom.editHourlyRateCnyInput,
    dom.editExchangeRateInput,
    dom.editTransportFeeJpyInput,
    dom.editClassroomFeeJpyInput,
  ];

  amountFields.forEach((field) => {
    if (isNoWage) {
      field.value = "0";
    }
    field.disabled = isNoWage;
  });
}

function syncCreateNoWageFields() {
  const isNoWage = dom.createSettlementTypeSelect.value === "no_wage";
  const amountFields = [
    dom.createHourlyRateJpyInput,
    dom.createHourlyRateCnyInput,
    dom.createExchangeRateInput,
    dom.createTransportFeeJpyInput,
    dom.createClassroomFeeJpyInput,
  ];

  amountFields.forEach((field) => {
    if (isNoWage) {
      field.value = "0";
    }
    field.disabled = isNoWage;
  });
}

function readNonNegativeNumber(value) {
  const trimmed = safeText(value).trim();
  if (!trimmed) {
    return NaN;
  }

  return Number(trimmed);
}

function displayNumberInput(value) {
  const text = safeText(value);
  return text || "0";
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
  const hasInvalidField = document.querySelector("[data-create-wage-rule-field].is-invalid");
  if (!hasInvalidField) {
    dom.createError.textContent = "";
    dom.createError.classList.add("is-hidden");
  }
}

function setCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-wage-rule-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearCreateFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-create-wage-rule-field="${fieldId}"]`);
  field?.classList.remove("is-invalid");
}

function setCreateSubmitting(isSubmitting) {
  isCreateSubmitting = isSubmitting;
  dom.createSubmitButton.disabled = isSubmitting;
  dom.createCancelButton.disabled = isSubmitting;
  dom.createSubmitButton.textContent = isSubmitting ? "新增中..." : "新增";
}

function createFieldIdForElement(field) {
  if (field === dom.createTeacherSelect) return "teacher";
  if (field === dom.createStudentSelect) return "student";
  if (field === dom.createSubjectSelect) return "subject";
  if (field === dom.createBusinessEntitySelect) return "businessEntity";
  if (field === dom.createSettlementTypeSelect) return "settlementType";
  if (field === dom.createHourlyRateJpyInput) return "hourlyRateJpy";
  if (field === dom.createHourlyRateCnyInput) return "hourlyRateCny";
  if (field === dom.createExchangeRateInput) return "exchangeRate";
  if (field === dom.createTransportFeeJpyInput) return "transportFeeJpy";
  if (field === dom.createClassroomFeeJpyInput) return "classroomFeeJpy";
  if (field === dom.createActiveSelect) return "activeState";
  return "";
}

function createFieldIdsForError(error) {
  const message = error?.message || String(error || "");
  if (message.includes("老师")) return ["teacher"];
  if (message.includes("学生")) return ["student"];
  if (message.includes("科目")) return ["subject"];
  if (message.includes("业务归属")) return ["businessEntity"];
  if (message.includes("结算类型")) return ["settlementType"];
  if (message.includes("负数") || message.includes("费率") || message.includes("汇率") || message.includes("费用")) {
    return ["hourlyRateJpy", "hourlyRateCny", "exchangeRate", "transportFeeJpy", "classroomFeeJpy"];
  }
  if (message.includes("启用状态")) return ["activeState"];
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
  [
    "settlementType",
    "hourlyRateJpy",
    "hourlyRateCny",
    "exchangeRate",
    "transportFeeJpy",
    "classroomFeeJpy",
    "activeState",
  ].forEach(clearEditFieldInvalid);
}

function hideEditErrorIfClean() {
  const hasInvalidField = document.querySelector("[data-edit-wage-rule-field].is-invalid");
  if (!hasInvalidField) {
    dom.editError.textContent = "";
    dom.editError.classList.add("is-hidden");
  }
}

function setEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-wage-rule-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearEditFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-edit-wage-rule-field="${fieldId}"]`);
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
  if (message.includes("结算类型")) return ["settlementType"];
  if (message.includes("负数")) {
    return ["hourlyRateJpy", "hourlyRateCny", "exchangeRate", "transportFeeJpy", "classroomFeeJpy"];
  }
  if (message.includes("无工资规则")) {
    return ["settlementType", "hourlyRateJpy", "hourlyRateCny", "exchangeRate", "transportFeeJpy", "classroomFeeJpy"];
  }
  if (message.includes("启用状态")) return ["activeState"];
  return [];
}

function filterWageRules(rows, filters) {
  return rows.filter((rule) => {
    const teacher = teacherById(rule.teacher_id);

    if (filters.teacherId && rule.teacher_id !== filters.teacherId) {
      return false;
    }

    if (filters.studentId && rule.student_id !== filters.studentId) {
      return false;
    }

    if (filters.subjectId && rule.subject_id !== filters.subjectId) {
      return false;
    }

    if (filters.businessEntityId && rule.business_entity_id !== filters.businessEntityId) {
      return false;
    }

    if (filters.settlementType && rule.settlement_type !== filters.settlementType) {
      return false;
    }

    if (filters.activeState === "active" && rule.is_active !== true) {
      return false;
    }

    if (filters.activeState === "inactive" && rule.is_active !== false) {
      return false;
    }

    if (filters.teacherDepartment && safeText(teacher?.department) !== filters.teacherDepartment) {
      return false;
    }

    return matchesKeyword(rule, filters.keyword);
  });
}

function matchesKeyword(rule, keyword) {
  if (!keyword) {
    return true;
  }

  const teacher = teacherById(rule.teacher_id);
  const normalizedKeyword = keyword.toLowerCase();
  return [
    teacherNameById(rule.teacher_id),
    teacher?.department,
    teacherStatusLabel(teacher?.status),
    studentNameById(rule.student_id),
    subjectNameById(rule.subject_id),
    businessNameById(rule.business_entity_id),
    settlementTypeLabel(rule.settlement_type),
    rule.settlement_type,
    rule.note,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function sortWageRules(rows) {
  return [...rows].sort((left, right) => {
    const teacherCompare = teacherNameById(left.teacher_id).localeCompare(
      teacherNameById(right.teacher_id),
      "zh-CN"
    );
    if (teacherCompare !== 0) {
      return teacherCompare;
    }

    const studentCompare = studentNameById(left.student_id).localeCompare(
      studentNameById(right.student_id),
      "zh-CN"
    );
    if (studentCompare !== 0) {
      return studentCompare;
    }

    return safeText(left.created_at).localeCompare(safeText(right.created_at));
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

function distinctTeacherDepartments() {
  return Array.from(
    new Set(
      teachers
        .map((teacher) => safeText(teacher.department).trim())
        .filter(Boolean)
    )
  ).sort((left, right) => left.localeCompare(right, "zh-CN"));
}

function teacherById(id) {
  return teachers.find((teacher) => teacher.id === id) || null;
}

function usableTeacherById(id) {
  return teachers.find((teacher) => teacher.id === id && isUsableTeacher(teacher)) || null;
}

function usableStudentById(id) {
  return students.find((student) => student.id === id && isUsableStudent(student)) || null;
}

function usableSubjectById(id) {
  return subjects.find((subject) => subject.id === id && isUsableSubject(subject)) || null;
}

function usableBusinessEntityById(id) {
  return businessEntities.find((entity) => entity.id === id && isUsableBusinessEntity(entity)) || null;
}

function teacherNameById(id) {
  const teacher = teacherById(id);
  if (!teacher) {
    return id ? "未知" : "未设置";
  }

  return teacherName(teacher);
}

function studentNameById(id) {
  const student = students.find((item) => item.id === id);
  if (!student) {
    return id ? "未知" : "未设置";
  }

  return studentName(student);
}

function subjectNameById(id) {
  const subject = subjects.find((item) => item.id === id);
  if (!subject) {
    return id ? "未知" : "未设置";
  }

  return subjectName(subject);
}

function businessNameById(id) {
  const entity = businessEntities.find((item) => item.id === id);
  if (!entity) {
    return id ? "未知" : "未设置";
  }

  return businessEntityName(entity);
}

function teacherName(teacher) {
  return safeText(teacher.display_name || teacher.name) || "未设置";
}

function studentName(student) {
  const name = safeText(student.display_name || student.name) || "未设置";
  const code = safeText(student.student_code);
  return code ? `${name} / ${code}` : name;
}

function subjectName(subject) {
  return safeText(subject.name) || "未设置";
}

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
}

function settlementTypeLabel(value) {
  return SETTLEMENT_TYPE_LABELS[value] || displayValue(value);
}

function teacherStatusLabel(value) {
  return TEACHER_STATUS_LABELS[value] || displayValue(value);
}

function activeLabel(value) {
  if (value === true) {
    return "启用";
  }

  if (value === false) {
    return "停用";
  }

  return "-";
}

function activeClass(value) {
  if (value === true) {
    return "status-active";
  }

  if (value === false) {
    return "status-inactive";
  }

  return "status-neutral";
}

function isUsableTeacher(teacher) {
  return Boolean(teacher && !["inactive", "resigned", "retired"].includes(safeText(teacher.status)));
}

function isUsableStudent(student) {
  return Boolean(student && !["inactive", "graduated", "withdrawn"].includes(safeText(student.status)));
}

function isUsableSubject(subject) {
  return Boolean(subject && subject.is_active !== false);
}

function isUsableBusinessEntity(entity) {
  return Boolean(entity && entity.is_active !== false);
}

function uniqueFieldIds(fieldIds) {
  return fieldIds.filter((fieldId, index, list) => fieldId && list.indexOf(fieldId) === index);
}

function displayValue(value) {
  return safeText(value) || "-";
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
