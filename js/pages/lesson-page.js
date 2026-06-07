import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createPlannedLessonRecord,
  fetchLessonBusinessEntities,
  fetchLessonRecords,
  fetchLessonStudents,
  fetchLessonSubjects,
  fetchLessonTeachers,
} from "../api/lesson-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatMonth, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  studentId: "",
  teacherId: "",
  subjectId: "",
  businessEntityId: "",
  lessonType: "",
  status: "",
  isBillable: "",
  keyword: "",
};

const WEEKDAY_LABELS = ["日", "一", "二", "三", "四", "五", "六"];

const LESSON_TYPE_LABELS = {
  planned: "计划",
  actual: "实际",
};

const LESSON_STATUS_LABELS = {
  planned: "待上课",
  completed: "已完成",
  pending_makeup: "待补课",
  makeup_completed: "补课完成",
  cancelled: "已取消",
};

const CREATE_PLANNED_LESSON_FIELD_IDS = [
  "lessonDate",
  "status",
  "student",
  "teacher",
  "subject",
  "businessEntity",
  "startTime",
  "endTime",
  "durationHours",
  "unitPrice",
  "lessonFee",
  "lessonCount",
];

const dom = {};
let students = [];
let teachers = [];
let subjects = [];
let businessEntities = [];
let lessonRecords = [];
let loadedMonth = "";
let activeView = "list";
let isCreatePlannedLessonSubmitting = false;
let isCreateLessonFeeManual = false;

export function initLessonPage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  setDefaultFilters();
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderLessonRecords([]);
    return;
  }

  loadInitialData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#lessonMessageArea");
  dom.filterForm = document.querySelector("#lessonFilterForm");
  dom.yearFilter = document.querySelector("#lessonYearFilter");
  dom.monthFilter = document.querySelector("#lessonMonthFilter");
  dom.studentSelect = document.querySelector("#lessonStudentSelect");
  dom.teacherSelect = document.querySelector("#lessonTeacherSelect");
  dom.subjectSelect = document.querySelector("#lessonSubjectSelect");
  dom.businessEntitySelect = document.querySelector("#lessonBusinessEntitySelect");
  dom.lessonTypeSelect = document.querySelector("#lessonTypeSelect");
  dom.statusSelect = document.querySelector("#lessonStatusSelect");
  dom.billableSelect = document.querySelector("#lessonBillableSelect");
  dom.keywordInput = document.querySelector("#lessonKeywordInput");
  dom.resetButton = document.querySelector("#lessonResetButton");
  dom.listViewButton = document.querySelector("#lessonListViewButton");
  dom.pairViewButton = document.querySelector("#lessonPairViewButton");
  dom.openCreatePlannedLessonButton = document.querySelector("#openCreatePlannedLessonButton");
  dom.listView = document.querySelector("#lessonListView");
  dom.pairView = document.querySelector("#lessonPairView");
  dom.pairRows = document.querySelector("#lessonPairRows");
  dom.tableBody = document.querySelector("#lessonTableBody");
  dom.loadingState = document.querySelector("#lessonLoadingState");
  dom.emptyState = document.querySelector("#lessonEmptyState");
  dom.lessonCount = document.querySelector("#lessonCount");
  dom.createPlannedLessonDialog = document.querySelector("#createPlannedLessonDialog");
  dom.createPlannedLessonError = document.querySelector("#createPlannedLessonError");
  dom.createPlannedLessonDateInput = document.querySelector("#createPlannedLessonDateInput");
  dom.createPlannedLessonStatusSelect = document.querySelector("#createPlannedLessonStatusSelect");
  dom.createPlannedLessonStudentSelect = document.querySelector("#createPlannedLessonStudentSelect");
  dom.createPlannedLessonTeacherSelect = document.querySelector("#createPlannedLessonTeacherSelect");
  dom.createPlannedLessonSubjectSelect = document.querySelector("#createPlannedLessonSubjectSelect");
  dom.createPlannedLessonBusinessEntitySelect = document.querySelector("#createPlannedLessonBusinessEntitySelect");
  dom.createPlannedLessonStartTimeInput = document.querySelector("#createPlannedLessonStartTimeInput");
  dom.createPlannedLessonEndTimeInput = document.querySelector("#createPlannedLessonEndTimeInput");
  dom.createPlannedLessonDurationInput = document.querySelector("#createPlannedLessonDurationInput");
  dom.createPlannedLessonUnitPriceInput = document.querySelector("#createPlannedLessonUnitPriceInput");
  dom.createPlannedLessonFeeInput = document.querySelector("#createPlannedLessonFeeInput");
  dom.createPlannedLessonCountInput = document.querySelector("#createPlannedLessonCountInput");
  dom.createPlannedLessonContentInput = document.querySelector("#createPlannedLessonContentInput");
  dom.createPlannedLessonNoteInput = document.querySelector("#createPlannedLessonNoteInput");
  dom.createPlannedLessonSubmitButton = document.querySelector("#createPlannedLessonSubmitButton");
  dom.createPlannedLessonCancelButton = document.querySelector("#createPlannedLessonCancelButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    applyQuery();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    applyQuery();
  });

  [dom.listViewButton, dom.pairViewButton].forEach((button) => {
    button?.addEventListener("click", () => {
      setActiveView(button.dataset.lessonView || "list");
      applyCurrentFilters();
    });
  });

  dom.openCreatePlannedLessonButton?.addEventListener("click", openCreatePlannedLessonDialog);
  dom.createPlannedLessonCancelButton?.addEventListener("click", () => closeCreatePlannedLessonDialog());
  dom.createPlannedLessonSubmitButton?.addEventListener("click", handleCreatePlannedLessonSubmit);

  dom.createPlannedLessonDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createPlannedLessonDialog) {
      closeCreatePlannedLessonDialog();
    }
  });

  [
    ["lessonDate", dom.createPlannedLessonDateInput],
    ["status", dom.createPlannedLessonStatusSelect],
    ["student", dom.createPlannedLessonStudentSelect],
    ["teacher", dom.createPlannedLessonTeacherSelect],
    ["subject", dom.createPlannedLessonSubjectSelect],
    ["businessEntity", dom.createPlannedLessonBusinessEntitySelect],
    ["startTime", dom.createPlannedLessonStartTimeInput],
    ["endTime", dom.createPlannedLessonEndTimeInput],
    ["durationHours", dom.createPlannedLessonDurationInput],
    ["unitPrice", dom.createPlannedLessonUnitPriceInput],
    ["lessonFee", dom.createPlannedLessonFeeInput],
    ["lessonCount", dom.createPlannedLessonCountInput],
  ].forEach(([fieldId, element]) => {
    element?.addEventListener("input", () => {
      clearCreatePlannedLessonFieldInvalid(fieldId);
      hideCreatePlannedLessonErrorIfClean();
    });
    element?.addEventListener("change", () => {
      clearCreatePlannedLessonFieldInvalid(fieldId);
      hideCreatePlannedLessonErrorIfClean();
    });
  });

  dom.createPlannedLessonDurationInput?.addEventListener("input", updateCreatePlannedLessonFeePreview);
  dom.createPlannedLessonUnitPriceInput?.addEventListener("input", updateCreatePlannedLessonFeePreview);
  dom.createPlannedLessonFeeInput?.addEventListener("input", () => {
    isCreateLessonFeeManual = dom.createPlannedLessonFeeInput.value.trim() !== "";
  });
}

function setDefaultFilters() {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  dom.studentSelect.value = DEFAULT_FILTERS.studentId;
  dom.teacherSelect.value = DEFAULT_FILTERS.teacherId;
  dom.subjectSelect.value = DEFAULT_FILTERS.subjectId;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.lessonTypeSelect.value = DEFAULT_FILTERS.lessonType;
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.billableSelect.value = DEFAULT_FILTERS.isBillable;
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载课时管理数据...");

  try {
    [students, teachers, subjects, businessEntities] = await Promise.all([
      fetchLessonStudents(),
      fetchLessonTeachers(),
      fetchLessonSubjects(),
      fetchLessonBusinessEntities(),
    ]);

    renderMasterOptions();
    await loadLessonMonth(currentYearMonth());
    applyCurrentFilters();
    showMessage("success", "课时管理数据已加载。");
  } catch (error) {
    students = [];
    teachers = [];
    subjects = [];
    businessEntities = [];
    lessonRecords = [];
    loadedMonth = "";
    renderMasterOptions();
    renderDataOptions([]);
    renderLessonRecords([]);
    showMessage("error", `读取课时管理数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

async function applyQuery() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  if (!filters) {
    return;
  }

  if (filters.month !== loadedMonth) {
    setLoading(true);
    showMessage("info", "正在加载课时记录...");

    try {
      await loadLessonMonth(filters.month);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "课时记录已加载。");
    } catch (error) {
      lessonRecords = [];
      loadedMonth = "";
      renderDataOptions([]);
      renderLessonRecords([]);
      showMessage("error", `读取课时记录失败：${error.message || error}`);
    } finally {
      setLoading(false);
    }
    return;
  }

  applyCurrentFilters();
}

async function loadLessonMonth(month) {
  lessonRecords = sortLessonRecords(await fetchLessonRecords(month));
  loadedMonth = month;
  renderDataOptions(lessonRecords);
}

function applyCurrentFilters() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  restoreFilterSelections(filters);
  renderLessonRecords(filterLessonRecords(lessonRecords, filters));
}

function readFilters() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    showMessage("error", "请选择正确的年月。");
    return null;
  }

  return {
    month,
    studentId: dom.studentSelect.value,
    teacherId: dom.teacherSelect.value,
    subjectId: dom.subjectSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    lessonType: dom.lessonTypeSelect.value,
    status: dom.statusSelect.value,
    isBillable: dom.billableSelect.value,
    keyword: dom.keywordInput.value.trim(),
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.studentSelect.value = filters.studentId;
  dom.teacherSelect.value = filters.teacherId;
  dom.subjectSelect.value = filters.subjectId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.lessonTypeSelect.value = filters.lessonType;
  dom.statusSelect.value = filters.status;
  dom.billableSelect.value = filters.isBillable;
  dom.keywordInput.value = filters.keyword;
}

function renderMasterOptions() {
  renderEntityOptions(dom.studentSelect, students, studentName);
  renderEntityOptions(dom.teacherSelect, teachers, teacherName);
  renderEntityOptions(dom.subjectSelect, subjects, subjectName);
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
}

function renderDataOptions(records) {
  renderValueOptions(dom.lessonTypeSelect, distinctValues(records, "lesson_type"), lessonTypeLabel);
  renderValueOptions(dom.statusSelect, distinctValues(records, "status"), lessonStatusLabel);
}

function renderEntityOptions(selectEl, rows, labelGetter) {
  renderEntityOptionsWithPlaceholder(selectEl, rows, labelGetter, "全部");
}

function renderEntityOptionsWithPlaceholder(selectEl, rows, labelGetter, placeholder) {
  const options = [`<option value="">${escapeHtml(placeholder)}</option>`];

  for (const row of rows) {
    options.push(
      `<option value="${escapeAttribute(row.id)}">${escapeHtml(labelGetter(row))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function openCreatePlannedLessonDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能新增预定课时。");
    return;
  }

  renderCreatePlannedLessonOptions();
  resetCreatePlannedLessonForm();
  clearCreatePlannedLessonErrors();
  setCreatePlannedLessonSubmitting(false);
  dom.createPlannedLessonDialog.classList.remove("is-hidden");
  dom.createPlannedLessonDialog.setAttribute("aria-hidden", "false");
  dom.createPlannedLessonDateInput.focus();
}

function closeCreatePlannedLessonDialog(force = false) {
  if (isCreatePlannedLessonSubmitting && !force) {
    return;
  }

  dom.createPlannedLessonDialog.classList.add("is-hidden");
  dom.createPlannedLessonDialog.setAttribute("aria-hidden", "true");
}

function renderCreatePlannedLessonOptions() {
  renderEntityOptionsWithPlaceholder(
    dom.createPlannedLessonStudentSelect,
    students.filter((student) => !["inactive", "graduated"].includes(safeText(student.status))),
    studentName,
    "请选择学生"
  );
  renderEntityOptionsWithPlaceholder(
    dom.createPlannedLessonTeacherSelect,
    teachers.filter((teacher) => !["inactive", "retired"].includes(safeText(teacher.status))),
    teacherName,
    "请选择老师"
  );
  renderEntityOptionsWithPlaceholder(
    dom.createPlannedLessonSubjectSelect,
    subjects.filter((subject) => subject.is_active !== false),
    subjectName,
    "请选择科目"
  );
  renderEntityOptionsWithPlaceholder(
    dom.createPlannedLessonBusinessEntitySelect,
    businessEntities.filter((entity) => entity.is_active !== false),
    businessEntityName,
    "请选择业务归属"
  );
}

function resetCreatePlannedLessonForm() {
  const selectedMonth = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter) || currentYearMonth();
  dom.createPlannedLessonDateInput.value = `${selectedMonth}-01`;
  dom.createPlannedLessonStatusSelect.value = "planned";
  dom.createPlannedLessonStudentSelect.value = dom.studentSelect.value || "";
  dom.createPlannedLessonTeacherSelect.value = dom.teacherSelect.value || "";
  dom.createPlannedLessonSubjectSelect.value = dom.subjectSelect.value || "";
  dom.createPlannedLessonBusinessEntitySelect.value = dom.businessEntitySelect.value || "";
  dom.createPlannedLessonStartTimeInput.value = "";
  dom.createPlannedLessonEndTimeInput.value = "";
  dom.createPlannedLessonDurationInput.value = "";
  dom.createPlannedLessonUnitPriceInput.value = "0";
  dom.createPlannedLessonFeeInput.value = "";
  dom.createPlannedLessonCountInput.value = "";
  dom.createPlannedLessonContentInput.value = "";
  dom.createPlannedLessonNoteInput.value = "";
  isCreateLessonFeeManual = false;
}

async function handleCreatePlannedLessonSubmit() {
  if (isCreatePlannedLessonSubmitting) {
    return;
  }

  clearCreatePlannedLessonErrors();
  const payload = readCreatePlannedLessonPayload();
  if (!payload) {
    return;
  }

  setCreatePlannedLessonSubmitting(true);

  try {
    const createdLesson = await createPlannedLessonRecord(payload);
    closeCreatePlannedLessonDialog(true);
    await refreshAfterCreatePlannedLesson(createdLesson);
    showMessage("success", `预定课时已新增：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    const message = error.message || String(error);
    showCreatePlannedLessonError(message, createPlannedLessonFieldIdsForError(message));
  } finally {
    setCreatePlannedLessonSubmitting(false);
  }
}

function readCreatePlannedLessonPayload() {
  const lessonDate = dom.createPlannedLessonDateInput.value;
  const status = dom.createPlannedLessonStatusSelect.value;
  const studentId = dom.createPlannedLessonStudentSelect.value;
  const teacherId = dom.createPlannedLessonTeacherSelect.value;
  const subjectId = dom.createPlannedLessonSubjectSelect.value;
  const businessEntityId = dom.createPlannedLessonBusinessEntitySelect.value;
  const startTime = dom.createPlannedLessonStartTimeInput.value;
  const endTime = dom.createPlannedLessonEndTimeInput.value;
  const durationHours = numberFromInput(dom.createPlannedLessonDurationInput.value);
  const unitPrice = numberFromInput(dom.createPlannedLessonUnitPriceInput.value);
  const lessonFee = nullableNumberFromInput(dom.createPlannedLessonFeeInput.value);
  const lessonCount = nullableIntegerFromInput(dom.createPlannedLessonCountInput.value);
  const invalidFields = [];

  if (!lessonDate || Number.isNaN(new Date(`${lessonDate}T00:00:00`).getTime())) invalidFields.push("lessonDate");
  if (!["planned", "pending_makeup"].includes(status)) invalidFields.push("status");
  if (!studentId) invalidFields.push("student");
  if (!teacherId) invalidFields.push("teacher");
  if (!subjectId) invalidFields.push("subject");
  if (!businessEntityId) invalidFields.push("businessEntity");
  if (startTime && !isTimeValue(startTime)) invalidFields.push("startTime");
  if (endTime && !isTimeValue(endTime)) invalidFields.push("endTime");
  if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (lessonFee !== null && (!Number.isFinite(lessonFee) || lessonFee < 0)) invalidFields.push("lessonFee");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreatePlannedLessonError("请检查新增预定课时表单中的必填项和数字格式。", invalidFields);
    return null;
  }

  return {
    lessonDate,
    status,
    studentId,
    teacherId,
    subjectId,
    businessEntityId,
    startTime,
    endTime,
    durationHours,
    unitPrice,
    lessonFee,
    lessonCount,
    lessonContent: dom.createPlannedLessonContentInput.value.trim(),
    note: dom.createPlannedLessonNoteInput.value.trim(),
  };
}

async function refreshAfterCreatePlannedLesson(createdLesson) {
  const createdMonth = createdLesson.year_month || safeText(createdLesson.lesson_date).slice(0, 7);
  if (createdMonth) {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, createdMonth);
  }

  dom.lessonTypeSelect.value = "";
  dom.statusSelect.value = "";
  dom.billableSelect.value = "";
  dom.keywordInput.value = "";

  await loadLessonMonth(createdMonth || currentYearMonth());
  renderDataOptions(lessonRecords);
  restoreFilterSelections({
    month: createdMonth || loadedMonth,
    studentId: createdLesson.student_id || "",
    teacherId: "",
    subjectId: "",
    businessEntityId: "",
    lessonType: "",
    status: "",
    isBillable: "",
    keyword: "",
  });
  applyCurrentFilters();
}

function setCreatePlannedLessonSubmitting(isSubmitting) {
  isCreatePlannedLessonSubmitting = isSubmitting;
  dom.createPlannedLessonSubmitButton.disabled = isSubmitting;
  dom.createPlannedLessonCancelButton.disabled = isSubmitting;
  dom.openCreatePlannedLessonButton.disabled = isSubmitting;
  dom.createPlannedLessonSubmitButton.textContent = isSubmitting ? "保存中..." : "新增";
}

function clearCreatePlannedLessonErrors() {
  dom.createPlannedLessonError.textContent = "";
  dom.createPlannedLessonError.classList.add("is-hidden");
  for (const fieldId of CREATE_PLANNED_LESSON_FIELD_IDS) {
    clearCreatePlannedLessonFieldInvalid(fieldId);
  }
}

function showCreatePlannedLessonError(message, fieldIds = []) {
  dom.createPlannedLessonError.textContent = message;
  dom.createPlannedLessonError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCreatePlannedLessonFieldInvalid(fieldId, true);
  }
  dom.createPlannedLessonDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function createPlannedLessonFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("日期") || text.includes("月份") || text.includes("已锁定")) fields.push("lessonDate");
  if (text.includes("状态")) fields.push("status");
  if (text.includes("学生")) fields.push("student");
  if (text.includes("老师")) fields.push("teacher");
  if (text.includes("科目")) fields.push("subject");
  if (text.includes("业务归属")) fields.push("businessEntity");
  if (text.includes("开始时间")) fields.push("startTime");
  if (text.includes("结束时间")) fields.push("endTime");
  if (text.includes("时长")) fields.push("durationHours");
  if (text.includes("单价")) fields.push("unitPrice");
  if (text.includes("课时费") || text.includes("金额")) fields.push("lessonFee");
  if (text.includes("回数")) fields.push("lessonCount");
  return fields;
}

function setCreatePlannedLessonFieldInvalid(fieldId, invalid) {
  const field = dom.createPlannedLessonDialog.querySelector(`[data-create-planned-lesson-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearCreatePlannedLessonFieldInvalid(fieldId) {
  setCreatePlannedLessonFieldInvalid(fieldId, false);
}

function hideCreatePlannedLessonErrorIfClean() {
  const hasInvalidField = Boolean(dom.createPlannedLessonDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.createPlannedLessonError.textContent = "";
    dom.createPlannedLessonError.classList.add("is-hidden");
  }
}

function updateCreatePlannedLessonFeePreview() {
  if (isCreateLessonFeeManual) {
    return;
  }

  const durationHours = numberFromInput(dom.createPlannedLessonDurationInput.value);
  const unitPrice = numberFromInput(dom.createPlannedLessonUnitPriceInput.value);
  if (!Number.isFinite(durationHours) || !Number.isFinite(unitPrice) || durationHours <= 0 || unitPrice < 0) {
    dom.createPlannedLessonFeeInput.value = "";
    return;
  }

  dom.createPlannedLessonFeeInput.value = String(Math.round(durationHours * unitPrice));
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

function renderLessonRecords(records) {
  dom.lessonCount.textContent = `${records.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", records.length > 0);
  syncViewVisibility();

  if (!records.length) {
    dom.tableBody.innerHTML = "";
    dom.pairRows.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = records.map((record) => `
    <tr>
      <td class="lesson-nowrap"><a class="table-action-button" href="./lesson-detail.html?id=${encodeURIComponent(record.id)}">详情</a></td>
      <td class="lesson-nowrap">${escapeHtml(formatDateOnly(record.lesson_date))}</td>
      <td class="lesson-nowrap">${escapeHtml(formatWeekday(record.lesson_date))}</td>
      <td class="lesson-nowrap">${escapeHtml(formatTimeRange(record.start_time, record.end_time))}</td>
      <td>${escapeHtml(nameById(students, record.student_id, studentName))}</td>
      <td>${escapeHtml(nameById(teachers, record.teacher_id, teacherName))}</td>
      <td>${escapeHtml(nameById(subjects, record.subject_id, subjectName))}</td>
      <td>${escapeHtml(nameById(businessEntities, record.business_entity_id, businessEntityName))}</td>
      <td><span class="status-badge status-neutral">${escapeHtml(lessonTypeLabel(record.lesson_type))}</span></td>
      <td><span class="status-badge ${escapeAttribute(statusClass(record.status))}">${escapeHtml(lessonStatusLabel(record.status))}</span></td>
      <td class="lesson-nowrap">${escapeHtml(billableLabel(record.is_billable))}</td>
      <td class="number-cell">${escapeHtml(displayValue(record.duration_hours))}</td>
      <td class="number-cell">${escapeHtml(displayValue(record.actual_minutes))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(record.unit_price, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(record.lesson_fee, "JPY"))}</td>
      <td class="lesson-content-cell">${escapeHtml(displayValue(record.lesson_content))}</td>
      <td class="lesson-note-cell">${escapeHtml(displayValue(record.note))}</td>
      <td class="lesson-nowrap">${escapeHtml(formatMonth(record.teacher_settlement_month))}</td>
      <td class="lesson-content-cell">${escapeHtml(displayValue(record.import_source))}</td>
    </tr>
  `).join("");

  renderLessonPairs(records);
}

function setActiveView(view) {
  activeView = view === "pair" ? "pair" : "list";
  syncViewVisibility();
}

function syncViewVisibility() {
  const isPairView = activeView === "pair";
  dom.listView.classList.toggle("is-hidden", isPairView);
  dom.pairView.classList.toggle("is-hidden", !isPairView);
  dom.listViewButton.classList.toggle("is-active", !isPairView);
  dom.pairViewButton.classList.toggle("is-active", isPairView);
  dom.listViewButton.setAttribute("aria-pressed", String(!isPairView));
  dom.pairViewButton.setAttribute("aria-pressed", String(isPairView));
}

function renderLessonPairs(records) {
  const grouped = buildLessonPairs(records);
  const sections = [];

  if (grouped.pairs.length) {
    sections.push(grouped.pairs.map(renderLessonPairRow).join(""));
  }

  if (grouped.unlinkedActuals.length) {
    sections.push(renderPairSection("未关联实际课时", grouped.unlinkedActuals.map(renderUnlinkedActualRow).join("")));
  }

  if (grouped.otherRecords.length) {
    sections.push(renderPairSection("其他课时记录", grouped.otherRecords.map(renderOtherLessonRow).join("")));
  }

  dom.pairRows.innerHTML = sections.join("") || '<div class="state-text">暂无可对应显示的课时记录。</div>';
}

function buildLessonPairs(records) {
  const plannedRecords = records.filter((record) => record.lesson_type === "planned");
  const actualRecords = records.filter((record) => record.lesson_type === "actual");
  const otherRecords = records.filter((record) => !["planned", "actual"].includes(record.lesson_type));
  const plannedIds = new Set(plannedRecords.map((record) => record.id));
  const actualsByPlannedId = new Map();
  const unlinkedActuals = [];

  for (const actual of actualRecords) {
    if (actual.planned_lesson_id && plannedIds.has(actual.planned_lesson_id)) {
      const rows = actualsByPlannedId.get(actual.planned_lesson_id) || [];
      rows.push(actual);
      actualsByPlannedId.set(actual.planned_lesson_id, rows);
    } else {
      unlinkedActuals.push(actual);
    }
  }

  return {
    pairs: plannedRecords.map((planned) => ({
      planned,
      actuals: actualsByPlannedId.get(planned.id) || [],
    })),
    unlinkedActuals,
    otherRecords,
  };
}

function renderLessonPairRow(pair) {
  const actualHtml = pair.actuals.length
    ? pair.actuals.map((actual) => renderLessonPairCard(actual, "actual")).join("")
    : renderMissingActualCard(pair.planned);

  return `
    <article class="lesson-pair-row">
      <div class="lesson-pair-column lesson-pair-column-planned">
        <div class="lesson-pair-column-title">planned</div>
        ${renderLessonPairCard(pair.planned, "planned")}
      </div>
      <div class="lesson-pair-column lesson-pair-column-actual">
        <div class="lesson-pair-column-title">actual</div>
        <div class="lesson-pair-actual-stack">${actualHtml}</div>
      </div>
    </article>
  `;
}

function renderPairSection(title, rowsHtml) {
  return `
    <section class="lesson-pair-section" aria-label="${escapeAttribute(title)}">
      <h3>${escapeHtml(title)}</h3>
      <div class="lesson-pair-list">${rowsHtml}</div>
    </section>
  `;
}

function renderUnlinkedActualRow(actual) {
  return `
    <article class="lesson-pair-row lesson-pair-row-unlinked">
      <div class="lesson-pair-column lesson-pair-column-empty">
        <div class="lesson-pair-column-title">planned</div>
        <div class="lesson-pair-placeholder">未找到对应 planned 记录</div>
      </div>
      <div class="lesson-pair-column lesson-pair-column-actual">
        <div class="lesson-pair-column-title">actual</div>
        ${renderLessonPairCard(actual, "actual")}
      </div>
    </article>
  `;
}

function renderOtherLessonRow(record) {
  return `
    <article class="lesson-pair-row lesson-pair-row-unlinked">
      <div class="lesson-pair-column lesson-pair-column-empty">
        <div class="lesson-pair-column-title">planned</div>
        <div class="lesson-pair-placeholder">当前类型无法配对</div>
      </div>
      <div class="lesson-pair-column">
        <div class="lesson-pair-column-title">记录</div>
        ${renderLessonPairCard(record, "actual")}
      </div>
    </article>
  `;
}

function renderMissingActualCard(planned) {
  const statusText = planned.status === "pending_makeup" ? "待补课，尚无 actual 记录" : "尚无 actual 记录";
  return `
    <div class="lesson-pair-placeholder">
      <span>${escapeHtml(statusText)}</span>
      <span class="lesson-pair-placeholder-id">planned ${escapeHtml(shortId(planned.id))}</span>
    </div>
  `;
}

function renderLessonPairCard(record, side) {
  const isActual = side === "actual";
  const modifierClass = [
    isActual && record.status === "cancelled" ? "lesson-pair-card-cancelled" : "",
    isActual && record.status === "makeup_completed" ? "lesson-pair-card-makeup" : "",
    isActual && record.is_billable === false ? "lesson-pair-card-nonbillable" : "",
  ].filter(Boolean).join(" ");
  const billableText = isActual ? actualBillableSummary(record) : billableLabel(record.is_billable);

  return `
    <article class="lesson-pair-card ${escapeAttribute(modifierClass)}">
      <div class="lesson-pair-card-header">
        <div>
          <a class="table-action-button" href="./lesson-detail.html?id=${encodeURIComponent(record.id)}">详情</a>
          <span class="lesson-pair-id">${escapeHtml(shortId(record.id))}</span>
        </div>
        <span class="status-badge ${escapeAttribute(statusClass(record.status))}">${escapeHtml(lessonStatusLabel(record.status))}</span>
      </div>
      <div class="lesson-pair-main">
        <strong>${escapeHtml(formatDateOnly(record.lesson_date))}</strong>
        <span>${escapeHtml(formatWeekday(record.lesson_date))}</span>
        <span>${escapeHtml(formatTimeRange(record.start_time, record.end_time))}</span>
      </div>
      <dl class="lesson-pair-meta">
        <div><dt>学生</dt><dd>${escapeHtml(nameById(students, record.student_id, studentName))}</dd></div>
        <div><dt>老师</dt><dd>${escapeHtml(nameById(teachers, record.teacher_id, teacherName))}</dd></div>
        <div><dt>科目</dt><dd>${escapeHtml(nameById(subjects, record.subject_id, subjectName))}</dd></div>
        <div><dt>业务归属</dt><dd>${escapeHtml(nameById(businessEntities, record.business_entity_id, businessEntityName))}</dd></div>
        <div><dt>计费</dt><dd>${escapeHtml(billableText)}</dd></div>
        <div><dt>时长</dt><dd>${escapeHtml(displayValue(record.duration_hours))}</dd></div>
        <div><dt>金额</dt><dd>${escapeHtml(formatCurrency(record.lesson_fee, "JPY"))}</dd></div>
        <div><dt>planned ID</dt><dd>${escapeHtml(shortId(record.planned_lesson_id))}</dd></div>
      </dl>
      <div class="lesson-pair-text">
        <span>${escapeHtml(displayValue(record.lesson_content))}</span>
        <span>${escapeHtml(displayValue(record.note))}</span>
      </div>
    </article>
  `;
}

function actualBillableSummary(record) {
  if (record.status === "cancelled") {
    return "不计费（取消课）";
  }

  if (record.status === "makeup_completed") {
    return record.is_billable ? "计费（补课完成）" : "不计费（补课完成）";
  }

  return billableLabel(record.is_billable);
}

function filterLessonRecords(records, filters) {
  return records.filter((record) => {
    if (filters.studentId && record.student_id !== filters.studentId) {
      return false;
    }

    if (filters.teacherId && record.teacher_id !== filters.teacherId) {
      return false;
    }

    if (filters.subjectId && record.subject_id !== filters.subjectId) {
      return false;
    }

    if (filters.businessEntityId && record.business_entity_id !== filters.businessEntityId) {
      return false;
    }

    if (filters.lessonType && record.lesson_type !== filters.lessonType) {
      return false;
    }

    if (filters.status && record.status !== filters.status) {
      return false;
    }

    if (filters.isBillable && String(record.is_billable) !== filters.isBillable) {
      return false;
    }

    return matchesKeyword(record, filters.keyword);
  });
}

function matchesKeyword(record, keyword) {
  if (!keyword) {
    return true;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return [
    nameById(students, record.student_id, studentName),
    nameById(teachers, record.teacher_id, teacherName),
    nameById(subjects, record.subject_id, subjectName),
    nameById(businessEntities, record.business_entity_id, businessEntityName),
    record.lesson_content,
    record.note,
    record.import_source,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function sortLessonRecords(records) {
  return [...records].sort((left, right) => {
    const dateCompare = safeText(left.lesson_date).localeCompare(safeText(right.lesson_date));
    if (dateCompare !== 0) {
      return dateCompare;
    }

    const timeCompare = safeText(left.start_time).localeCompare(safeText(right.start_time));
    if (timeCompare !== 0) {
      return timeCompare;
    }

    const studentCompare = nameById(students, left.student_id, studentName)
      .localeCompare(nameById(students, right.student_id, studentName), "zh-CN");
    if (studentCompare !== 0) {
      return studentCompare;
    }

    return nameById(teachers, left.teacher_id, teacherName)
      .localeCompare(nameById(teachers, right.teacher_id, teacherName), "zh-CN");
  });
}

function distinctValues(records, key) {
  return Array.from(
    new Set(
      records
        .map((record) => safeText(record[key]).trim())
        .filter(Boolean)
    )
  ).sort((left, right) => left.localeCompare(right, "zh-CN"));
}

function nameById(rows, id, labelGetter) {
  const row = rows.find((item) => item.id === id);
  if (!row) {
    return id ? "未知" : "未设置";
  }

  return labelGetter(row);
}

function studentName(student) {
  return safeText(student.display_name || student.name) || "未设置";
}

function teacherName(teacher) {
  return safeText(teacher.display_name || teacher.name) || "未设置";
}

function subjectName(subject) {
  return safeText(subject.name) || "未设置";
}

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
}

function lessonTypeLabel(value) {
  return LESSON_TYPE_LABELS[value] || displayValue(value);
}

function lessonStatusLabel(value) {
  return LESSON_STATUS_LABELS[value] || displayValue(value);
}

function statusClass(status) {
  const classMap = {
    planned: "status-pending",
    completed: "status-paid",
    pending_makeup: "status-pending",
    makeup_completed: "status-paid",
    cancelled: "status-cancelled",
  };

  return classMap[status] || "status-neutral";
}

function billableLabel(value) {
  if (value === true) {
    return "计费";
  }

  if (value === false) {
    return "不计费";
  }

  return "-";
}

function formatDateOnly(value) {
  if (!value) {
    return "-";
  }

  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) {
    return safeText(value);
  }

  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function formatWeekday(value) {
  if (!value) {
    return "-";
  }

  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) {
    return "-";
  }

  return WEEKDAY_LABELS[date.getDay()];
}

function formatTimeRange(start, end) {
  const startText = formatTime(start);
  const endText = formatTime(end);

  if (startText === "-" && endText === "-") {
    return "-";
  }

  return `${startText} - ${endText}`;
}

function formatTime(value) {
  const text = safeText(value);
  if (!text) {
    return "-";
  }

  return text.slice(0, 5);
}

function isTimeValue(value) {
  return /^\d{2}:\d{2}$/.test(safeText(value));
}

function numberFromInput(value) {
  const text = safeText(value).trim();
  if (!text) {
    return Number.NaN;
  }

  return Number(text);
}

function nullableNumberFromInput(value) {
  const text = safeText(value).trim();
  if (!text) {
    return null;
  }

  return Number(text);
}

function nullableIntegerFromInput(value) {
  const text = safeText(value).trim();
  if (!text) {
    return null;
  }

  return Number(text);
}

function displayValue(value) {
  return safeText(value) || "-";
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
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
