import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createActualLessonFromPlanned,
  createCancelledActualLessonFromPlanned,
  createMakeupCompletedActualLessonFromPlanned,
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

const LESSON_IMPORT_PREVIEW_FIELD_LABELS = {
  student: "学生",
  teacher: "老师",
  subject: "科目",
  businessEntity: "业务归属",
  lessonDate: "日期",
  lessonType: "lesson_type",
  status: "status",
  durationHours: "课时",
  lessonFee: "金额",
};

const LESSON_IMPORT_REQUIRED_FIELDS = [
  "student",
  "teacher",
  "subject",
  "businessEntity",
  "lessonDate",
  "lessonType",
  "status",
  "durationHours",
];

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

const CREATE_ACTUAL_LESSON_FIELD_IDS = [
  "lessonDate",
  "startTime",
  "endTime",
  "durationHours",
  "unitPrice",
  "lessonFee",
  "lessonCount",
];

const CREATE_CANCELLED_ACTUAL_LESSON_FIELD_IDS = [
  "lessonDate",
  "startTime",
  "endTime",
  "durationHours",
  "unitPrice",
  "lessonCount",
];

const CREATE_MAKEUP_ACTUAL_LESSON_FIELD_IDS = [
  "lessonDate",
  "isBillable",
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
let currentActualSourceLesson = null;
let isCreateActualLessonSubmitting = false;
let isActualLessonFeeManual = false;
let currentCancelledActualSourceLesson = null;
let isCreateCancelledActualLessonSubmitting = false;
let currentMakeupActualSourceLesson = null;
let isCreateMakeupActualLessonSubmitting = false;
let isMakeupLessonFeeManual = false;
let importPreviewRows = [];

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
  dom.openLessonImportPreviewButton = document.querySelector("#openLessonImportPreviewButton");
  dom.openCreatePlannedLessonButton = document.querySelector("#openCreatePlannedLessonButton");
  dom.listView = document.querySelector("#lessonListView");
  dom.pairView = document.querySelector("#lessonPairView");
  dom.pairRows = document.querySelector("#lessonPairRows");
  dom.tableBody = document.querySelector("#lessonTableBody");
  dom.loadingState = document.querySelector("#lessonLoadingState");
  dom.emptyState = document.querySelector("#lessonEmptyState");
  dom.lessonCount = document.querySelector("#lessonCount");
  dom.lessonImportPreviewDialog = document.querySelector("#lessonImportPreviewDialog");
  dom.lessonImportPreviewError = document.querySelector("#lessonImportPreviewError");
  dom.lessonImportPreviewFileInput = document.querySelector("#lessonImportPreviewFileInput");
  dom.lessonImportPreviewSummary = document.querySelector("#lessonImportPreviewSummary");
  dom.lessonImportPreviewEmpty = document.querySelector("#lessonImportPreviewEmpty");
  dom.lessonImportPreviewRows = document.querySelector("#lessonImportPreviewRows");
  dom.lessonImportPreviewClearButton = document.querySelector("#lessonImportPreviewClearButton");
  dom.lessonImportPreviewCloseButton = document.querySelector("#lessonImportPreviewCloseButton");
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
  dom.createActualLessonDialog = document.querySelector("#createActualLessonDialog");
  dom.createActualLessonSummary = document.querySelector("#createActualLessonSummary");
  dom.createActualLessonError = document.querySelector("#createActualLessonError");
  dom.createActualLessonDateInput = document.querySelector("#createActualLessonDateInput");
  dom.createActualLessonStartTimeInput = document.querySelector("#createActualLessonStartTimeInput");
  dom.createActualLessonEndTimeInput = document.querySelector("#createActualLessonEndTimeInput");
  dom.createActualLessonDurationInput = document.querySelector("#createActualLessonDurationInput");
  dom.createActualLessonUnitPriceInput = document.querySelector("#createActualLessonUnitPriceInput");
  dom.createActualLessonFeeInput = document.querySelector("#createActualLessonFeeInput");
  dom.createActualLessonCountInput = document.querySelector("#createActualLessonCountInput");
  dom.createActualLessonContentInput = document.querySelector("#createActualLessonContentInput");
  dom.createActualLessonNoteInput = document.querySelector("#createActualLessonNoteInput");
  dom.createActualLessonSubmitButton = document.querySelector("#createActualLessonSubmitButton");
  dom.createActualLessonCancelButton = document.querySelector("#createActualLessonCancelButton");
  dom.createCancelledActualLessonDialog = document.querySelector("#createCancelledActualLessonDialog");
  dom.createCancelledActualLessonSummary = document.querySelector("#createCancelledActualLessonSummary");
  dom.createCancelledActualLessonError = document.querySelector("#createCancelledActualLessonError");
  dom.createCancelledActualLessonDateInput = document.querySelector("#createCancelledActualLessonDateInput");
  dom.createCancelledActualLessonStartTimeInput = document.querySelector("#createCancelledActualLessonStartTimeInput");
  dom.createCancelledActualLessonEndTimeInput = document.querySelector("#createCancelledActualLessonEndTimeInput");
  dom.createCancelledActualLessonDurationInput = document.querySelector("#createCancelledActualLessonDurationInput");
  dom.createCancelledActualLessonUnitPriceInput = document.querySelector("#createCancelledActualLessonUnitPriceInput");
  dom.createCancelledActualLessonFeeInput = document.querySelector("#createCancelledActualLessonFeeInput");
  dom.createCancelledActualLessonCountInput = document.querySelector("#createCancelledActualLessonCountInput");
  dom.createCancelledActualLessonContentInput = document.querySelector("#createCancelledActualLessonContentInput");
  dom.createCancelledActualLessonNoteInput = document.querySelector("#createCancelledActualLessonNoteInput");
  dom.createCancelledActualLessonSubmitButton = document.querySelector("#createCancelledActualLessonSubmitButton");
  dom.createCancelledActualLessonCancelButton = document.querySelector("#createCancelledActualLessonCancelButton");
  dom.createMakeupActualLessonDialog = document.querySelector("#createMakeupActualLessonDialog");
  dom.createMakeupActualLessonSummary = document.querySelector("#createMakeupActualLessonSummary");
  dom.createMakeupActualLessonError = document.querySelector("#createMakeupActualLessonError");
  dom.createMakeupActualLessonDateInput = document.querySelector("#createMakeupActualLessonDateInput");
  dom.createMakeupActualLessonBillableSelect = document.querySelector("#createMakeupActualLessonBillableSelect");
  dom.createMakeupActualLessonStartTimeInput = document.querySelector("#createMakeupActualLessonStartTimeInput");
  dom.createMakeupActualLessonEndTimeInput = document.querySelector("#createMakeupActualLessonEndTimeInput");
  dom.createMakeupActualLessonDurationInput = document.querySelector("#createMakeupActualLessonDurationInput");
  dom.createMakeupActualLessonUnitPriceInput = document.querySelector("#createMakeupActualLessonUnitPriceInput");
  dom.createMakeupActualLessonFeeInput = document.querySelector("#createMakeupActualLessonFeeInput");
  dom.createMakeupActualLessonCountInput = document.querySelector("#createMakeupActualLessonCountInput");
  dom.createMakeupActualLessonContentInput = document.querySelector("#createMakeupActualLessonContentInput");
  dom.createMakeupActualLessonNoteInput = document.querySelector("#createMakeupActualLessonNoteInput");
  dom.createMakeupActualLessonSubmitButton = document.querySelector("#createMakeupActualLessonSubmitButton");
  dom.createMakeupActualLessonCancelButton = document.querySelector("#createMakeupActualLessonCancelButton");
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

  dom.openLessonImportPreviewButton?.addEventListener("click", openLessonImportPreviewDialog);
  dom.lessonImportPreviewCloseButton?.addEventListener("click", closeLessonImportPreviewDialog);
  dom.lessonImportPreviewClearButton?.addEventListener("click", clearLessonImportPreview);
  dom.lessonImportPreviewFileInput?.addEventListener("change", handleLessonImportPreviewFileChange);

  dom.lessonImportPreviewDialog?.addEventListener("click", (event) => {
    if (event.target === dom.lessonImportPreviewDialog) {
      closeLessonImportPreviewDialog();
    }
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

  dom.pairRows?.addEventListener("click", (event) => {
    const textToggleButton = event.target.closest("[data-lesson-pair-text-toggle]");
    if (textToggleButton) {
      handleLessonPairTextToggle(textToggleButton);
      return;
    }

    const actualButton = event.target.closest("[data-generate-actual-id]");
    if (actualButton) {
      openCreateActualLessonDialog(actualButton.dataset.generateActualId || "");
      return;
    }

    const cancelledButton = event.target.closest("[data-generate-cancelled-actual-id]");
    if (cancelledButton) {
      openCreateCancelledActualLessonDialog(cancelledButton.dataset.generateCancelledActualId || "");
      return;
    }

    const makeupButton = event.target.closest("[data-generate-makeup-actual-id]");
    if (makeupButton) {
      openCreateMakeupActualLessonDialog(makeupButton.dataset.generateMakeupActualId || "");
    }
  });

  dom.createActualLessonCancelButton?.addEventListener("click", () => closeCreateActualLessonDialog());
  dom.createActualLessonSubmitButton?.addEventListener("click", handleCreateActualLessonSubmit);

  dom.createActualLessonDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createActualLessonDialog) {
      closeCreateActualLessonDialog();
    }
  });

  [
    ["lessonDate", dom.createActualLessonDateInput],
    ["startTime", dom.createActualLessonStartTimeInput],
    ["endTime", dom.createActualLessonEndTimeInput],
    ["durationHours", dom.createActualLessonDurationInput],
    ["unitPrice", dom.createActualLessonUnitPriceInput],
    ["lessonFee", dom.createActualLessonFeeInput],
    ["lessonCount", dom.createActualLessonCountInput],
  ].forEach(([fieldId, element]) => {
    element?.addEventListener("input", () => {
      clearCreateActualLessonFieldInvalid(fieldId);
      hideCreateActualLessonErrorIfClean();
    });
    element?.addEventListener("change", () => {
      clearCreateActualLessonFieldInvalid(fieldId);
      hideCreateActualLessonErrorIfClean();
    });
  });

  dom.createActualLessonDurationInput?.addEventListener("input", updateCreateActualLessonFeePreview);
  dom.createActualLessonUnitPriceInput?.addEventListener("input", updateCreateActualLessonFeePreview);
  dom.createActualLessonFeeInput?.addEventListener("input", () => {
    isActualLessonFeeManual = dom.createActualLessonFeeInput.value.trim() !== "";
  });

  dom.createCancelledActualLessonCancelButton?.addEventListener("click", () => closeCreateCancelledActualLessonDialog());
  dom.createCancelledActualLessonSubmitButton?.addEventListener("click", handleCreateCancelledActualLessonSubmit);

  dom.createCancelledActualLessonDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createCancelledActualLessonDialog) {
      closeCreateCancelledActualLessonDialog();
    }
  });

  [
    ["lessonDate", dom.createCancelledActualLessonDateInput],
    ["startTime", dom.createCancelledActualLessonStartTimeInput],
    ["endTime", dom.createCancelledActualLessonEndTimeInput],
    ["durationHours", dom.createCancelledActualLessonDurationInput],
    ["unitPrice", dom.createCancelledActualLessonUnitPriceInput],
    ["lessonCount", dom.createCancelledActualLessonCountInput],
  ].forEach(([fieldId, element]) => {
    element?.addEventListener("input", () => {
      clearCreateCancelledActualLessonFieldInvalid(fieldId);
      hideCreateCancelledActualLessonErrorIfClean();
    });
    element?.addEventListener("change", () => {
      clearCreateCancelledActualLessonFieldInvalid(fieldId);
      hideCreateCancelledActualLessonErrorIfClean();
    });
  });

  dom.createMakeupActualLessonCancelButton?.addEventListener("click", () => closeCreateMakeupActualLessonDialog());
  dom.createMakeupActualLessonSubmitButton?.addEventListener("click", handleCreateMakeupActualLessonSubmit);

  dom.createMakeupActualLessonDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createMakeupActualLessonDialog) {
      closeCreateMakeupActualLessonDialog();
    }
  });

  [
    ["lessonDate", dom.createMakeupActualLessonDateInput],
    ["isBillable", dom.createMakeupActualLessonBillableSelect],
    ["startTime", dom.createMakeupActualLessonStartTimeInput],
    ["endTime", dom.createMakeupActualLessonEndTimeInput],
    ["durationHours", dom.createMakeupActualLessonDurationInput],
    ["unitPrice", dom.createMakeupActualLessonUnitPriceInput],
    ["lessonFee", dom.createMakeupActualLessonFeeInput],
    ["lessonCount", dom.createMakeupActualLessonCountInput],
  ].forEach(([fieldId, element]) => {
    element?.addEventListener("input", () => {
      clearCreateMakeupActualLessonFieldInvalid(fieldId);
      hideCreateMakeupActualLessonErrorIfClean();
    });
    element?.addEventListener("change", () => {
      clearCreateMakeupActualLessonFieldInvalid(fieldId);
      hideCreateMakeupActualLessonErrorIfClean();
    });
  });

  dom.createMakeupActualLessonBillableSelect?.addEventListener("change", handleCreateMakeupActualLessonBillableChange);
  dom.createMakeupActualLessonDurationInput?.addEventListener("input", updateCreateMakeupActualLessonFeePreview);
  dom.createMakeupActualLessonUnitPriceInput?.addEventListener("input", updateCreateMakeupActualLessonFeePreview);
  dom.createMakeupActualLessonFeeInput?.addEventListener("input", () => {
    isMakeupLessonFeeManual = dom.createMakeupActualLessonFeeInput.value.trim() !== "";
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

function openCreateActualLessonDialog(plannedLessonId) {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能生成实际课时。");
    return;
  }

  const plannedLesson = lessonRecords.find((record) => record.id === plannedLessonId);
  if (!plannedLesson || plannedLesson.lesson_type !== "planned") {
    showMessage("error", "未找到可生成 actual 的 planned 课时。");
    return;
  }

  if (!["planned", "pending_makeup"].includes(plannedLesson.status)) {
    showMessage("error", "当前 planned 状态不能生成 completed actual。");
    return;
  }

  currentActualSourceLesson = plannedLesson;
  resetCreateActualLessonForm(plannedLesson);
  renderCreateActualLessonSummary(plannedLesson);
  clearCreateActualLessonErrors();
  setCreateActualLessonSubmitting(false);
  dom.createActualLessonDialog.classList.remove("is-hidden");
  dom.createActualLessonDialog.setAttribute("aria-hidden", "false");
  dom.createActualLessonDateInput.focus();
}

function closeCreateActualLessonDialog(force = false) {
  if (isCreateActualLessonSubmitting && !force) {
    return;
  }

  dom.createActualLessonDialog.classList.add("is-hidden");
  dom.createActualLessonDialog.setAttribute("aria-hidden", "true");
}

function resetCreateActualLessonForm(plannedLesson) {
  dom.createActualLessonDateInput.value = safeText(plannedLesson.lesson_date);
  dom.createActualLessonStartTimeInput.value = formatInputTime(plannedLesson.start_time);
  dom.createActualLessonEndTimeInput.value = formatInputTime(plannedLesson.end_time);
  dom.createActualLessonDurationInput.value = displayInputNumber(plannedLesson.duration_hours);
  dom.createActualLessonUnitPriceInput.value = displayInputNumber(plannedLesson.unit_price || 0);
  dom.createActualLessonFeeInput.value = displayInputNumber(plannedLesson.lesson_fee || 0);
  dom.createActualLessonCountInput.value = plannedLesson.lesson_count ? String(plannedLesson.lesson_count) : "";
  dom.createActualLessonContentInput.value = safeText(plannedLesson.lesson_content);
  dom.createActualLessonNoteInput.value = safeText(plannedLesson.note);
  isActualLessonFeeManual = false;
}

function renderCreateActualLessonSummary(plannedLesson) {
  dom.createActualLessonSummary.innerHTML = [
    ["planned id", shortId(plannedLesson.id)],
    ["学生", nameById(students, plannedLesson.student_id, studentName)],
    ["老师", nameById(teachers, plannedLesson.teacher_id, teacherName)],
    ["科目", nameById(subjects, plannedLesson.subject_id, subjectName)],
    ["业务归属", nameById(businessEntities, plannedLesson.business_entity_id, businessEntityName)],
    ["学生结算月", formatMonth(plannedLesson.year_month)],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");
}

async function handleCreateActualLessonSubmit() {
  if (isCreateActualLessonSubmitting) {
    return;
  }

  clearCreateActualLessonErrors();
  const payload = readCreateActualLessonPayload();
  if (!payload) {
    return;
  }

  setCreateActualLessonSubmitting(true);

  try {
    const createdLesson = await createActualLessonFromPlanned(payload);
    closeCreateActualLessonDialog(true);
    await refreshAfterCreateActualLesson(createdLesson);
    showMessage("success", `实际课时已生成：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    const message = error.message || String(error);
    showCreateActualLessonError(message, createActualLessonFieldIdsForError(message));
  } finally {
    setCreateActualLessonSubmitting(false);
  }
}

function readCreateActualLessonPayload() {
  if (!currentActualSourceLesson) {
    showCreateActualLessonError("缺少来源 planned 课时，请重新打开生成窗口。");
    return null;
  }

  const lessonDate = dom.createActualLessonDateInput.value;
  const startTime = dom.createActualLessonStartTimeInput.value;
  const endTime = dom.createActualLessonEndTimeInput.value;
  const durationHours = numberFromInput(dom.createActualLessonDurationInput.value);
  const unitPrice = numberFromInput(dom.createActualLessonUnitPriceInput.value);
  const lessonFee = nullableNumberFromInput(dom.createActualLessonFeeInput.value);
  const lessonCount = nullableIntegerFromInput(dom.createActualLessonCountInput.value);
  const invalidFields = [];

  if (!lessonDate || Number.isNaN(new Date(`${lessonDate}T00:00:00`).getTime())) invalidFields.push("lessonDate");
  if (startTime && !isTimeValue(startTime)) invalidFields.push("startTime");
  if (endTime && !isTimeValue(endTime)) invalidFields.push("endTime");
  if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (lessonFee !== null && (!Number.isFinite(lessonFee) || lessonFee < 0)) invalidFields.push("lessonFee");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreateActualLessonError("请检查实际课时表单中的必填项和数字格式。", invalidFields);
    return null;
  }

  return {
    plannedLessonId: currentActualSourceLesson.id,
    lessonDate,
    startTime,
    endTime,
    durationHours,
    unitPrice,
    lessonFee,
    lessonCount,
    lessonContent: dom.createActualLessonContentInput.value.trim(),
    note: dom.createActualLessonNoteInput.value.trim(),
  };
}

async function refreshAfterCreateActualLesson(createdLesson) {
  const createdMonth = createdLesson.year_month || loadedMonth || currentYearMonth();
  if (createdMonth) {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, createdMonth);
  }

  dom.lessonTypeSelect.value = "";
  dom.statusSelect.value = "";
  dom.billableSelect.value = "";
  dom.keywordInput.value = "";

  await loadLessonMonth(createdMonth);
  renderDataOptions(lessonRecords);
  restoreFilterSelections({
    month: createdMonth,
    studentId: createdLesson.student_id || currentActualSourceLesson?.student_id || "",
    teacherId: "",
    subjectId: "",
    businessEntityId: "",
    lessonType: "",
    status: "",
    isBillable: "",
    keyword: "",
  });
  setActiveView("pair");
  applyCurrentFilters();
}

function setCreateActualLessonSubmitting(isSubmitting) {
  isCreateActualLessonSubmitting = isSubmitting;
  dom.createActualLessonSubmitButton.disabled = isSubmitting;
  dom.createActualLessonCancelButton.disabled = isSubmitting;
  dom.openCreatePlannedLessonButton.disabled = isSubmitting;
  dom.createActualLessonSubmitButton.textContent = isSubmitting ? "生成中..." : "生成 actual";
}

function clearCreateActualLessonErrors() {
  dom.createActualLessonError.textContent = "";
  dom.createActualLessonError.classList.add("is-hidden");
  for (const fieldId of CREATE_ACTUAL_LESSON_FIELD_IDS) {
    clearCreateActualLessonFieldInvalid(fieldId);
  }
}

function showCreateActualLessonError(message, fieldIds = []) {
  dom.createActualLessonError.textContent = message;
  dom.createActualLessonError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCreateActualLessonFieldInvalid(fieldId, true);
  }
  dom.createActualLessonDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function createActualLessonFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("日期") || text.includes("学生月度结算") || text.includes("老师工资月份")) fields.push("lessonDate");
  if (text.includes("开始时间")) fields.push("startTime");
  if (text.includes("结束时间")) fields.push("endTime");
  if (text.includes("时长")) fields.push("durationHours");
  if (text.includes("单价")) fields.push("unitPrice");
  if (text.includes("课时费") || text.includes("金额")) fields.push("lessonFee");
  if (text.includes("回数")) fields.push("lessonCount");
  return fields;
}

function setCreateActualLessonFieldInvalid(fieldId, invalid) {
  const field = dom.createActualLessonDialog.querySelector(`[data-create-actual-lesson-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearCreateActualLessonFieldInvalid(fieldId) {
  setCreateActualLessonFieldInvalid(fieldId, false);
}

function hideCreateActualLessonErrorIfClean() {
  const hasInvalidField = Boolean(dom.createActualLessonDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.createActualLessonError.textContent = "";
    dom.createActualLessonError.classList.add("is-hidden");
  }
}

function updateCreateActualLessonFeePreview() {
  if (isActualLessonFeeManual) {
    return;
  }

  const durationHours = numberFromInput(dom.createActualLessonDurationInput.value);
  const unitPrice = numberFromInput(dom.createActualLessonUnitPriceInput.value);
  if (!Number.isFinite(durationHours) || !Number.isFinite(unitPrice) || durationHours <= 0 || unitPrice < 0) {
    dom.createActualLessonFeeInput.value = "";
    return;
  }

  dom.createActualLessonFeeInput.value = String(Math.round(durationHours * unitPrice));
}

function openCreateCancelledActualLessonDialog(plannedLessonId) {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能生成取消课时。");
    return;
  }

  const plannedLesson = lessonRecords.find((record) => record.id === plannedLessonId);
  if (!plannedLesson || plannedLesson.lesson_type !== "planned") {
    showMessage("error", "未找到可生成取消 actual 的 planned 课时。");
    return;
  }

  if (!["planned", "pending_makeup"].includes(plannedLesson.status)) {
    showMessage("error", "当前 planned 状态不能生成 cancelled actual。");
    return;
  }

  currentCancelledActualSourceLesson = plannedLesson;
  resetCreateCancelledActualLessonForm(plannedLesson);
  renderCreateCancelledActualLessonSummary(plannedLesson);
  clearCreateCancelledActualLessonErrors();
  setCreateCancelledActualLessonSubmitting(false);
  dom.createCancelledActualLessonDialog.classList.remove("is-hidden");
  dom.createCancelledActualLessonDialog.setAttribute("aria-hidden", "false");
  dom.createCancelledActualLessonDateInput.focus();
}

function closeCreateCancelledActualLessonDialog(force = false) {
  if (isCreateCancelledActualLessonSubmitting && !force) {
    return;
  }

  dom.createCancelledActualLessonDialog.classList.add("is-hidden");
  dom.createCancelledActualLessonDialog.setAttribute("aria-hidden", "true");
}

function resetCreateCancelledActualLessonForm(plannedLesson) {
  dom.createCancelledActualLessonDateInput.value = safeText(plannedLesson.lesson_date);
  dom.createCancelledActualLessonStartTimeInput.value = formatInputTime(plannedLesson.start_time);
  dom.createCancelledActualLessonEndTimeInput.value = formatInputTime(plannedLesson.end_time);
  dom.createCancelledActualLessonDurationInput.value = displayInputNumber(plannedLesson.duration_hours);
  dom.createCancelledActualLessonUnitPriceInput.value = displayInputNumber(plannedLesson.unit_price || 0);
  dom.createCancelledActualLessonFeeInput.value = "0";
  dom.createCancelledActualLessonCountInput.value = plannedLesson.lesson_count ? String(plannedLesson.lesson_count) : "";
  dom.createCancelledActualLessonContentInput.value = safeText(plannedLesson.lesson_content);
  dom.createCancelledActualLessonNoteInput.value = safeText(plannedLesson.note);
}

function renderCreateCancelledActualLessonSummary(plannedLesson) {
  dom.createCancelledActualLessonSummary.innerHTML = [
    ["planned id", shortId(plannedLesson.id)],
    ["学生", nameById(students, plannedLesson.student_id, studentName)],
    ["老师", nameById(teachers, plannedLesson.teacher_id, teacherName)],
    ["科目", nameById(subjects, plannedLesson.subject_id, subjectName)],
    ["业务归属", nameById(businessEntities, plannedLesson.business_entity_id, businessEntityName)],
    ["学生结算月", formatMonth(plannedLesson.year_month)],
    ["取消课口径", "不计费 / 课时费 0 / 实际分钟 0"],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");
}

async function handleCreateCancelledActualLessonSubmit() {
  if (isCreateCancelledActualLessonSubmitting) {
    return;
  }

  clearCreateCancelledActualLessonErrors();
  const payload = readCreateCancelledActualLessonPayload();
  if (!payload) {
    return;
  }

  setCreateCancelledActualLessonSubmitting(true);

  try {
    const createdLesson = await createCancelledActualLessonFromPlanned(payload);
    closeCreateCancelledActualLessonDialog(true);
    await refreshAfterCreateCancelledActualLesson(createdLesson);
    showMessage("success", `取消课时已生成：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    const message = error.message || String(error);
    showCreateCancelledActualLessonError(message, createCancelledActualLessonFieldIdsForError(message));
  } finally {
    setCreateCancelledActualLessonSubmitting(false);
  }
}

function readCreateCancelledActualLessonPayload() {
  if (!currentCancelledActualSourceLesson) {
    showCreateCancelledActualLessonError("缺少来源 planned 课时，请重新打开生成窗口。");
    return null;
  }

  const lessonDate = dom.createCancelledActualLessonDateInput.value;
  const startTime = dom.createCancelledActualLessonStartTimeInput.value;
  const endTime = dom.createCancelledActualLessonEndTimeInput.value;
  const durationHours = numberFromInput(dom.createCancelledActualLessonDurationInput.value);
  const unitPrice = numberFromInput(dom.createCancelledActualLessonUnitPriceInput.value);
  const lessonCount = nullableIntegerFromInput(dom.createCancelledActualLessonCountInput.value);
  const invalidFields = [];

  if (!lessonDate || Number.isNaN(new Date(`${lessonDate}T00:00:00`).getTime())) invalidFields.push("lessonDate");
  if (startTime && !isTimeValue(startTime)) invalidFields.push("startTime");
  if (endTime && !isTimeValue(endTime)) invalidFields.push("endTime");
  if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreateCancelledActualLessonError("请检查取消课时表单中的必填项和数字格式。", invalidFields);
    return null;
  }

  return {
    plannedLessonId: currentCancelledActualSourceLesson.id,
    lessonDate,
    startTime,
    endTime,
    durationHours,
    unitPrice,
    lessonCount,
    lessonContent: dom.createCancelledActualLessonContentInput.value.trim(),
    note: dom.createCancelledActualLessonNoteInput.value.trim(),
  };
}

async function refreshAfterCreateCancelledActualLesson(createdLesson) {
  const createdMonth = createdLesson.year_month || loadedMonth || currentYearMonth();
  if (createdMonth) {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, createdMonth);
  }

  dom.lessonTypeSelect.value = "";
  dom.statusSelect.value = "";
  dom.billableSelect.value = "";
  dom.keywordInput.value = "";

  await loadLessonMonth(createdMonth);
  renderDataOptions(lessonRecords);
  restoreFilterSelections({
    month: createdMonth,
    studentId: createdLesson.student_id || currentCancelledActualSourceLesson?.student_id || "",
    teacherId: "",
    subjectId: "",
    businessEntityId: "",
    lessonType: "",
    status: "",
    isBillable: "",
    keyword: "",
  });
  setActiveView("pair");
  applyCurrentFilters();
}

function setCreateCancelledActualLessonSubmitting(isSubmitting) {
  isCreateCancelledActualLessonSubmitting = isSubmitting;
  dom.createCancelledActualLessonSubmitButton.disabled = isSubmitting;
  dom.createCancelledActualLessonCancelButton.disabled = isSubmitting;
  dom.openCreatePlannedLessonButton.disabled = isSubmitting;
  dom.createCancelledActualLessonSubmitButton.textContent = isSubmitting ? "生成中..." : "生成取消课";
}

function clearCreateCancelledActualLessonErrors() {
  dom.createCancelledActualLessonError.textContent = "";
  dom.createCancelledActualLessonError.classList.add("is-hidden");
  for (const fieldId of CREATE_CANCELLED_ACTUAL_LESSON_FIELD_IDS) {
    clearCreateCancelledActualLessonFieldInvalid(fieldId);
  }
}

function showCreateCancelledActualLessonError(message, fieldIds = []) {
  dom.createCancelledActualLessonError.textContent = message;
  dom.createCancelledActualLessonError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCreateCancelledActualLessonFieldInvalid(fieldId, true);
  }
  dom.createCancelledActualLessonDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function createCancelledActualLessonFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("日期") || text.includes("学生月度结算") || text.includes("老师工资月份")) fields.push("lessonDate");
  if (text.includes("开始时间")) fields.push("startTime");
  if (text.includes("结束时间")) fields.push("endTime");
  if (text.includes("时长")) fields.push("durationHours");
  if (text.includes("单价")) fields.push("unitPrice");
  if (text.includes("回数")) fields.push("lessonCount");
  return fields;
}

function setCreateCancelledActualLessonFieldInvalid(fieldId, invalid) {
  const field = dom.createCancelledActualLessonDialog.querySelector(`[data-create-cancelled-actual-lesson-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearCreateCancelledActualLessonFieldInvalid(fieldId) {
  setCreateCancelledActualLessonFieldInvalid(fieldId, false);
}

function hideCreateCancelledActualLessonErrorIfClean() {
  const hasInvalidField = Boolean(dom.createCancelledActualLessonDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.createCancelledActualLessonError.textContent = "";
    dom.createCancelledActualLessonError.classList.add("is-hidden");
  }
}

function openCreateMakeupActualLessonDialog(plannedLessonId) {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能生成补课完成。");
    return;
  }

  const plannedLesson = lessonRecords.find((record) => record.id === plannedLessonId);
  if (!plannedLesson || plannedLesson.lesson_type !== "planned") {
    showMessage("error", "未找到可生成补课完成 actual 的 planned 课时。");
    return;
  }

  if (!["planned", "pending_makeup"].includes(plannedLesson.status)) {
    showMessage("error", "当前 planned 状态不能生成 makeup_completed actual。");
    return;
  }

  currentMakeupActualSourceLesson = plannedLesson;
  resetCreateMakeupActualLessonForm(plannedLesson);
  renderCreateMakeupActualLessonSummary(plannedLesson);
  clearCreateMakeupActualLessonErrors();
  setCreateMakeupActualLessonSubmitting(false);
  dom.createMakeupActualLessonDialog.classList.remove("is-hidden");
  dom.createMakeupActualLessonDialog.setAttribute("aria-hidden", "false");
  dom.createMakeupActualLessonDateInput.focus();
}

function closeCreateMakeupActualLessonDialog(force = false) {
  if (isCreateMakeupActualLessonSubmitting && !force) {
    return;
  }

  dom.createMakeupActualLessonDialog.classList.add("is-hidden");
  dom.createMakeupActualLessonDialog.setAttribute("aria-hidden", "true");
}

function resetCreateMakeupActualLessonForm(plannedLesson) {
  dom.createMakeupActualLessonDateInput.value = safeText(plannedLesson.lesson_date);
  dom.createMakeupActualLessonBillableSelect.value = "true";
  dom.createMakeupActualLessonStartTimeInput.value = formatInputTime(plannedLesson.start_time);
  dom.createMakeupActualLessonEndTimeInput.value = formatInputTime(plannedLesson.end_time);
  dom.createMakeupActualLessonDurationInput.value = displayInputNumber(plannedLesson.duration_hours);
  dom.createMakeupActualLessonUnitPriceInput.value = displayInputNumber(plannedLesson.unit_price || 0);
  dom.createMakeupActualLessonFeeInput.value = displayInputNumber(plannedLesson.lesson_fee || 0);
  dom.createMakeupActualLessonCountInput.value = plannedLesson.lesson_count ? String(plannedLesson.lesson_count) : "";
  dom.createMakeupActualLessonContentInput.value = safeText(plannedLesson.lesson_content);
  dom.createMakeupActualLessonNoteInput.value = safeText(plannedLesson.note);
  isMakeupLessonFeeManual = false;
  syncCreateMakeupActualLessonFeeMode();
}

function renderCreateMakeupActualLessonSummary(plannedLesson) {
  dom.createMakeupActualLessonSummary.innerHTML = [
    ["planned id", shortId(plannedLesson.id)],
    ["学生", nameById(students, plannedLesson.student_id, studentName)],
    ["老师", nameById(teachers, plannedLesson.teacher_id, teacherName)],
    ["科目", nameById(subjects, plannedLesson.subject_id, subjectName)],
    ["业务归属", nameById(businessEntities, plannedLesson.business_entity_id, businessEntityName)],
    ["学生结算月", formatMonth(plannedLesson.year_month)],
    ["补课完成口径", "计费可选；不计费时课时费固定 0"],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");
}

async function handleCreateMakeupActualLessonSubmit() {
  if (isCreateMakeupActualLessonSubmitting) {
    return;
  }

  clearCreateMakeupActualLessonErrors();
  const payload = readCreateMakeupActualLessonPayload();
  if (!payload) {
    return;
  }

  setCreateMakeupActualLessonSubmitting(true);

  try {
    const createdLesson = await createMakeupCompletedActualLessonFromPlanned(payload);
    closeCreateMakeupActualLessonDialog(true);
    await refreshAfterCreateMakeupActualLesson(createdLesson);
    showMessage("success", `补课完成已生成：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    const message = error.message || String(error);
    showCreateMakeupActualLessonError(message, createMakeupActualLessonFieldIdsForError(message));
  } finally {
    setCreateMakeupActualLessonSubmitting(false);
  }
}

function readCreateMakeupActualLessonPayload() {
  if (!currentMakeupActualSourceLesson) {
    showCreateMakeupActualLessonError("缺少来源 planned 课时，请重新打开生成窗口。");
    return null;
  }

  const lessonDate = dom.createMakeupActualLessonDateInput.value;
  const isBillable = dom.createMakeupActualLessonBillableSelect.value !== "false";
  const startTime = dom.createMakeupActualLessonStartTimeInput.value;
  const endTime = dom.createMakeupActualLessonEndTimeInput.value;
  const durationHours = numberFromInput(dom.createMakeupActualLessonDurationInput.value);
  const unitPrice = numberFromInput(dom.createMakeupActualLessonUnitPriceInput.value);
  const lessonFee = isBillable ? nullableNumberFromInput(dom.createMakeupActualLessonFeeInput.value) : 0;
  const lessonCount = nullableIntegerFromInput(dom.createMakeupActualLessonCountInput.value);
  const invalidFields = [];

  if (!lessonDate || Number.isNaN(new Date(`${lessonDate}T00:00:00`).getTime())) invalidFields.push("lessonDate");
  if (!["true", "false"].includes(dom.createMakeupActualLessonBillableSelect.value)) invalidFields.push("isBillable");
  if (startTime && !isTimeValue(startTime)) invalidFields.push("startTime");
  if (endTime && !isTimeValue(endTime)) invalidFields.push("endTime");
  if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (isBillable && lessonFee !== null && (!Number.isFinite(lessonFee) || lessonFee < 0)) invalidFields.push("lessonFee");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreateMakeupActualLessonError("请检查补课完成表单中的必填项和数字格式。", invalidFields);
    return null;
  }

  return {
    plannedLessonId: currentMakeupActualSourceLesson.id,
    lessonDate,
    startTime,
    endTime,
    durationHours,
    unitPrice,
    lessonFee,
    isBillable,
    lessonCount,
    lessonContent: dom.createMakeupActualLessonContentInput.value.trim(),
    note: dom.createMakeupActualLessonNoteInput.value.trim(),
  };
}

async function refreshAfterCreateMakeupActualLesson(createdLesson) {
  const createdMonth = createdLesson.year_month || loadedMonth || currentYearMonth();
  if (createdMonth) {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, createdMonth);
  }

  dom.lessonTypeSelect.value = "";
  dom.statusSelect.value = "";
  dom.billableSelect.value = "";
  dom.keywordInput.value = "";

  await loadLessonMonth(createdMonth);
  renderDataOptions(lessonRecords);
  restoreFilterSelections({
    month: createdMonth,
    studentId: createdLesson.student_id || currentMakeupActualSourceLesson?.student_id || "",
    teacherId: "",
    subjectId: "",
    businessEntityId: "",
    lessonType: "",
    status: "",
    isBillable: "",
    keyword: "",
  });
  setActiveView("pair");
  applyCurrentFilters();
}

function setCreateMakeupActualLessonSubmitting(isSubmitting) {
  isCreateMakeupActualLessonSubmitting = isSubmitting;
  dom.createMakeupActualLessonSubmitButton.disabled = isSubmitting;
  dom.createMakeupActualLessonCancelButton.disabled = isSubmitting;
  dom.openCreatePlannedLessonButton.disabled = isSubmitting;
  dom.createMakeupActualLessonSubmitButton.textContent = isSubmitting ? "生成中..." : "生成补课完成";
}

function clearCreateMakeupActualLessonErrors() {
  dom.createMakeupActualLessonError.textContent = "";
  dom.createMakeupActualLessonError.classList.add("is-hidden");
  for (const fieldId of CREATE_MAKEUP_ACTUAL_LESSON_FIELD_IDS) {
    clearCreateMakeupActualLessonFieldInvalid(fieldId);
  }
}

function showCreateMakeupActualLessonError(message, fieldIds = []) {
  dom.createMakeupActualLessonError.textContent = message;
  dom.createMakeupActualLessonError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCreateMakeupActualLessonFieldInvalid(fieldId, true);
  }
  dom.createMakeupActualLessonDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function createMakeupActualLessonFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("日期") || text.includes("学生月度结算") || text.includes("老师工资月份")) fields.push("lessonDate");
  if (text.includes("计费")) fields.push("isBillable");
  if (text.includes("开始时间")) fields.push("startTime");
  if (text.includes("结束时间")) fields.push("endTime");
  if (text.includes("时长")) fields.push("durationHours");
  if (text.includes("单价")) fields.push("unitPrice");
  if (text.includes("课时费") || text.includes("金额")) fields.push("lessonFee");
  if (text.includes("回数")) fields.push("lessonCount");
  return fields;
}

function setCreateMakeupActualLessonFieldInvalid(fieldId, invalid) {
  const field = dom.createMakeupActualLessonDialog.querySelector(`[data-create-makeup-actual-lesson-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearCreateMakeupActualLessonFieldInvalid(fieldId) {
  setCreateMakeupActualLessonFieldInvalid(fieldId, false);
}

function hideCreateMakeupActualLessonErrorIfClean() {
  const hasInvalidField = Boolean(dom.createMakeupActualLessonDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.createMakeupActualLessonError.textContent = "";
    dom.createMakeupActualLessonError.classList.add("is-hidden");
  }
}

function handleCreateMakeupActualLessonBillableChange() {
  isMakeupLessonFeeManual = false;
  syncCreateMakeupActualLessonFeeMode();
  updateCreateMakeupActualLessonFeePreview();
}

function syncCreateMakeupActualLessonFeeMode() {
  const isBillable = dom.createMakeupActualLessonBillableSelect.value !== "false";
  dom.createMakeupActualLessonFeeInput.readOnly = !isBillable;
  if (!isBillable) {
    dom.createMakeupActualLessonFeeInput.value = "0";
  }
}

function updateCreateMakeupActualLessonFeePreview() {
  const isBillable = dom.createMakeupActualLessonBillableSelect.value !== "false";
  if (!isBillable) {
    dom.createMakeupActualLessonFeeInput.value = "0";
    return;
  }

  if (isMakeupLessonFeeManual) {
    return;
  }

  const durationHours = numberFromInput(dom.createMakeupActualLessonDurationInput.value);
  const unitPrice = numberFromInput(dom.createMakeupActualLessonUnitPriceInput.value);
  if (!Number.isFinite(durationHours) || !Number.isFinite(unitPrice) || durationHours <= 0 || unitPrice < 0) {
    dom.createMakeupActualLessonFeeInput.value = "";
    return;
  }

  dom.createMakeupActualLessonFeeInput.value = String(Math.round(durationHours * unitPrice));
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

function openLessonImportPreviewDialog() {
  dom.lessonImportPreviewDialog.classList.remove("is-hidden");
  dom.lessonImportPreviewDialog.setAttribute("aria-hidden", "false");
  renderLessonImportPreview();
  dom.lessonImportPreviewFileInput?.focus();
}

function closeLessonImportPreviewDialog() {
  dom.lessonImportPreviewDialog.classList.add("is-hidden");
  dom.lessonImportPreviewDialog.setAttribute("aria-hidden", "true");
}

function clearLessonImportPreview() {
  importPreviewRows = [];
  if (dom.lessonImportPreviewFileInput) {
    dom.lessonImportPreviewFileInput.value = "";
  }
  hideLessonImportPreviewError();
  renderLessonImportPreview();
}

async function handleLessonImportPreviewFileChange(event) {
  const file = event.target.files?.[0];
  importPreviewRows = [];
  hideLessonImportPreviewError();

  if (!file) {
    renderLessonImportPreview();
    return;
  }

  try {
    const rows = await parseLessonImportPreviewFile(file);
    importPreviewRows = buildLessonImportPreviewRows(rows);
    if (!importPreviewRows.length) {
      showLessonImportPreviewError("没有读取到可预览的课时行。请确认文件包含表头和课时数据。");
    }
  } catch (error) {
    importPreviewRows = [];
    showLessonImportPreviewError(error.message || String(error));
  }

  renderLessonImportPreview();
}

async function parseLessonImportPreviewFile(file) {
  const extension = file.name.split(".").pop()?.toLowerCase() || "";

  if (["xlsx", "xls"].includes(extension)) {
    if (!window.XLSX) {
      throw new Error("Excel 解析库尚未加载，请刷新页面后重试，或先导出为 CSV。");
    }

    const workbook = window.XLSX.read(await file.arrayBuffer(), {
      type: "array",
      cellDates: true,
    });
    const firstSheetName = workbook.SheetNames[0];
    if (!firstSheetName) {
      throw new Error("Excel 文件没有可读取的工作表。");
    }

    return window.XLSX.utils.sheet_to_json(workbook.Sheets[firstSheetName], {
      header: 1,
      raw: true,
      defval: "",
    });
  }

  if (["csv", "tsv", "txt"].includes(extension)) {
    return parseLessonImportPreviewDelimitedText(await file.text());
  }

  throw new Error("仅支持 .xlsx / .xls / .csv / .tsv / .txt 文件。");
}

function parseLessonImportPreviewDelimitedText(text) {
  const firstLine = text.split(/\r?\n/).find((line) => line.trim()) || "";
  const delimiter = firstLine.includes("\t")
    ? "\t"
    : detectLessonImportPreviewDelimiter(firstLine);
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];

    if (char === '"') {
      if (quoted && next === '"') {
        cell += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
      continue;
    }

    if (!quoted && char === delimiter) {
      row.push(cell);
      cell = "";
      continue;
    }

    if (!quoted && (char === "\n" || char === "\r")) {
      if (char === "\r" && next === "\n") {
        index += 1;
      }
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
      continue;
    }

    cell += char;
  }

  row.push(cell);
  if (row.some((value) => String(value).trim())) {
    rows.push(row);
  }

  return rows;
}

function detectLessonImportPreviewDelimiter(line) {
  const candidates = [",", ";", "，"];
  return candidates
    .map((delimiter) => ({
      delimiter,
      count: countDelimiterOutsideQuotes(line, delimiter),
    }))
    .sort((left, right) => right.count - left.count)[0].delimiter;
}

function countDelimiterOutsideQuotes(line, delimiter) {
  let count = 0;
  let quoted = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    const next = line[index + 1];

    if (char === '"') {
      if (quoted && next === '"') {
        index += 1;
      } else {
        quoted = !quoted;
      }
      continue;
    }

    if (!quoted && char === delimiter) {
      count += 1;
    }
  }

  return count;
}

function buildLessonImportPreviewRows(rows) {
  const headerIndex = findLessonImportPreviewHeaderRow(rows);
  if (headerIndex < 0) {
    throw new Error("没有找到可识别的课时导入表头。");
  }

  const columnMap = buildLessonImportPreviewColumnMap(rows[headerIndex]);
  const previewRows = [];
  const baseYear = importPreviewBaseYear();

  for (let rowIndex = headerIndex + 1; rowIndex < rows.length; rowIndex += 1) {
    const rawRow = rows[rowIndex] || [];
    if (isBlankLessonImportPreviewRow(rawRow)) {
      continue;
    }

    const rowText = rawRow.map((cell) => String(cell || "").trim()).join("");
    if (/合计|总计|總計|小计|小計/.test(rowText)) {
      continue;
    }

    const rowNo = rowIndex + 1;
    const plannedHasData = lessonImportPreviewSideHasData(rawRow, columnMap.plannedSide);
    const actualHasData = lessonImportPreviewSideHasData(rawRow, columnMap.actualSide);
    const usesPairedColumns = lessonImportPreviewUsesPairedColumns(columnMap);

    if (usesPairedColumns && (plannedHasData || actualHasData)) {
      if (plannedHasData) {
        previewRows.push(buildLessonImportPreviewRow(rawRow, rowNo, columnMap, "planned", baseYear));
      }
      if (actualHasData) {
        previewRows.push(buildLessonImportPreviewRow(rawRow, rowNo, columnMap, "actual", baseYear));
      }
      continue;
    }

    if (lessonImportPreviewSideHasData(rawRow, columnMap.genericSide)) {
      previewRows.push(buildLessonImportPreviewRow(rawRow, rowNo, columnMap, "generic", baseYear));
    }
  }

  return previewRows;
}

function findLessonImportPreviewHeaderRow(rows) {
  for (let index = 0; index < Math.min(rows.length, 30); index += 1) {
    const map = buildLessonImportPreviewColumnMap(rows[index]);
    const mappedFields = Object.entries(map)
      .filter(([, value]) => typeof value === "number")
      .map(([key]) => key);
    const hasCommon = mappedFields.includes("student") || mappedFields.includes("teacher");
    const hasLesson = mappedFields.some((key) => /date|status|duration|lessonType/i.test(key));

    if (mappedFields.length >= 3 && hasCommon && hasLesson) {
      return index;
    }
  }

  return -1;
}

function buildLessonImportPreviewColumnMap(header) {
  const map = {};

  (header || []).forEach((cell, index) => {
    const key = normalizeLessonImportHeader(cell);
    if (!key) {
      return;
    }

    const set = (field) => {
      if (map[field] === undefined) {
        map[field] = index;
      }
    };

    if (/^(学生|学生姓名|生徒|student|studentname|student_name)$/.test(key)) set("student");
    if (/^(老师|教师|教師|先生|担当老师|担当教師|teacher|teachername|teacher_name)$/.test(key)) set("teacher");
    if (/^(科目|课程|講座|subject|subjectname|subject_name)$/.test(key)) set("subject");
    if (/^(业务归属|归属|业务|businessentity|business_entity|entity)$/.test(key)) set("businessEntity");
    if (/^(lesson_type|lessontype|课时类型|类型)$/.test(key)) set("lessonType");
    if (/^(status|状态|ステータス)$/.test(key)) set("status");
    if (/^(日期|课时日期|上课日期|date|lessondate|lesson_date)$/.test(key)) set("lessonDate");
    if (/^(开始时间|开始|start|starttime|start_time)$/.test(key)) set("startTime");
    if (/^(结束时间|结束|end|endtime|end_time)$/.test(key)) set("endTime");
    if (/^(时间|时间段|时段|時間帯|time|timerange|time_range)$/.test(key)) set("timeRange");
    if (/^(课时|时长|時間数|授業時間|duration|durationhours|duration_hours)$/.test(key)) set("durationHours");
    if (/^(单价|课程单价|unitprice|unit_price)$/.test(key)) set("unitPrice");
    if (/^(金额|课时费|应收课时费|授業料|金額|lessonfee|lesson_fee|fee)$/.test(key)) set("lessonFee");
    if (/^(备注|備考|メモ|note|memo)$/.test(key)) set("note");

    if (/^(预定日期|予定日|planneddate|planned_date)$/.test(key)) set("plannedDate");
    if (/^(预定开始时间|予定開始|plannedstart|planned_start)$/.test(key)) set("plannedStartTime");
    if (/^(预定结束时间|予定終了|plannedend|planned_end)$/.test(key)) set("plannedEndTime");
    if (/^(预定时间|预定时间段|予定時間帯|plannedtime|planned_time|plannedtimerange|planned_time_range)$/.test(key)) set("plannedTimeRange");
    if (/^(预定课时时长|预定时长|plannedduration|planned_duration)$/.test(key)) set("plannedDurationHours");
    if (/^(预定单价|plannedunitprice|planned_unit_price)$/.test(key)) set("plannedUnitPrice");
    if (/^(预定课时费|预定金额|plannedfee|planned_fee|plannedlessonfee|planned_lesson_fee)$/.test(key)) set("plannedLessonFee");
    if (/^(预定状态|plannedstatus|planned_status)$/.test(key)) set("plannedStatus");
    if (/^(预定备注|plannednote|planned_note)$/.test(key)) set("plannedNote");

    if (/^(实际日期|実際日|actualdate|actual_date)$/.test(key)) set("actualDate");
    if (/^(实际开始时间|実際開始|actualstart|actual_start)$/.test(key)) set("actualStartTime");
    if (/^(实际结束时间|実際終了|actualend|actual_end)$/.test(key)) set("actualEndTime");
    if (/^(实际时间|实际时间段|実際時間帯|actualtime|actual_time|actualtimerange|actual_time_range)$/.test(key)) set("actualTimeRange");
    if (/^(实际课时时长|实际时长|actualduration|actual_duration)$/.test(key)) set("actualDurationHours");
    if (/^(实际课时费|实际金额|actualfee|actual_fee|actuallessonfee|actual_lesson_fee)$/.test(key)) set("actualLessonFee");
    if (/^(实际状态|actualstatus|actual_status)$/.test(key)) set("actualStatus");
    if (/^(实际备注|actualnote|actual_note)$/.test(key)) set("actualNote");
  });

  return {
    ...map,
    genericSide: [
      map.lessonDate,
      map.lessonType,
      map.status,
      map.startTime,
      map.endTime,
      map.timeRange,
      map.durationHours,
      map.lessonFee,
      map.note,
    ],
    plannedSide: [
      map.plannedDate,
      map.plannedStartTime,
      map.plannedEndTime,
      map.plannedTimeRange,
      map.plannedDurationHours,
      map.plannedUnitPrice,
      map.plannedLessonFee,
      map.plannedStatus,
      map.plannedNote,
    ],
    actualSide: [
      map.actualDate,
      map.actualStartTime,
      map.actualEndTime,
      map.actualTimeRange,
      map.actualDurationHours,
      map.actualLessonFee,
      map.actualStatus,
      map.actualNote,
    ],
  };
}

function buildLessonImportPreviewRow(rawRow, rowNo, columnMap, mode, baseYear) {
  const paired = mode !== "generic";
  const raw = {
    student: readLessonImportPreviewCell(rawRow, columnMap.student),
    teacher: readLessonImportPreviewCell(rawRow, columnMap.teacher),
    subject: readLessonImportPreviewCell(rawRow, columnMap.subject),
    businessEntity: readLessonImportPreviewCell(rawRow, columnMap.businessEntity),
    lessonType: paired ? mode : readLessonImportPreviewCell(rawRow, columnMap.lessonType),
    status: paired
      ? readLessonImportPreviewCell(rawRow, mode === "planned" ? columnMap.plannedStatus : columnMap.actualStatus)
      : readLessonImportPreviewCell(rawRow, columnMap.status),
    lessonDate: paired
      ? readLessonImportPreviewCell(rawRow, mode === "planned" ? columnMap.plannedDate : columnMap.actualDate)
      : readLessonImportPreviewCell(rawRow, columnMap.lessonDate),
    startTime: paired
      ? readLessonImportPreviewCell(rawRow, mode === "planned" ? columnMap.plannedStartTime : columnMap.actualStartTime)
      : readLessonImportPreviewCell(rawRow, columnMap.startTime),
    endTime: paired
      ? readLessonImportPreviewCell(rawRow, mode === "planned" ? columnMap.plannedEndTime : columnMap.actualEndTime)
      : readLessonImportPreviewCell(rawRow, columnMap.endTime),
    timeRange: paired
      ? readLessonImportPreviewCell(rawRow, mode === "planned" ? columnMap.plannedTimeRange : columnMap.actualTimeRange)
      : readLessonImportPreviewCell(rawRow, columnMap.timeRange),
    durationHours: paired
      ? readLessonImportPreviewCell(rawRow, mode === "planned" ? columnMap.plannedDurationHours : columnMap.actualDurationHours)
      : readLessonImportPreviewCell(rawRow, columnMap.durationHours),
    unitPrice: paired
      ? readLessonImportPreviewCell(rawRow, mode === "planned" ? columnMap.plannedUnitPrice : columnMap.unitPrice)
      : readLessonImportPreviewCell(rawRow, columnMap.unitPrice),
    lessonFee: paired
      ? readLessonImportPreviewCell(rawRow, mode === "planned" ? columnMap.plannedLessonFee : columnMap.actualLessonFee)
      : readLessonImportPreviewCell(rawRow, columnMap.lessonFee),
    note: paired
      ? readLessonImportPreviewCell(rawRow, mode === "planned" ? columnMap.plannedNote : columnMap.actualNote)
      : readLessonImportPreviewCell(rawRow, columnMap.note),
  };

  const row = {
    rowNo,
    raw,
    values: {
      student: importPreviewCellText(raw.student),
      teacher: importPreviewCellText(raw.teacher),
      subject: importPreviewCellText(raw.subject),
      businessEntity: importPreviewCellText(raw.businessEntity),
      lessonType: normalizeLessonImportPreviewType(raw.lessonType),
      status: normalizeLessonImportPreviewStatus(raw.status),
      lessonDate: parseLessonImportPreviewDate(raw.lessonDate, baseYear),
      startTime: parseLessonImportPreviewTime(raw.startTime),
      endTime: parseLessonImportPreviewTime(raw.endTime),
      durationHours: parseLessonImportPreviewNumber(raw.durationHours),
      unitPrice: parseLessonImportPreviewNumber(raw.unitPrice),
      lessonFee: parseLessonImportPreviewNumber(raw.lessonFee),
      note: importPreviewCellText(raw.note),
    },
    errors: [],
    warnings: [],
    invalidFields: new Set(),
  };

  applyLessonImportPreviewTimeRange(row);
  validateLessonImportPreviewRow(row, mode);
  return row;
}

function validateLessonImportPreviewRow(row, mode) {
  const values = row.values;

  if (!values.lessonType && values.status) {
    const inferredType = inferLessonTypeFromStatus(values.status);
    if (inferredType) {
      values.lessonType = inferredType;
      addLessonImportPreviewIssue(row, "warning", "lessonType", `lesson_type 为空，已按 status 暂时识别为 ${inferredType}。`);
    }
  }

  for (const field of LESSON_IMPORT_REQUIRED_FIELDS) {
    if (!hasLessonImportPreviewValue(values[field])) {
      addLessonImportPreviewIssue(row, "error", field, `${LESSON_IMPORT_PREVIEW_FIELD_LABELS[field]}不能为空。`);
    }
  }

  validateLessonImportPreviewLookup(row, "student", students, studentName);
  validateLessonImportPreviewLookup(row, "teacher", teachers, teacherName);
  validateLessonImportPreviewLookup(row, "subject", subjects, subjectName);
  validateLessonImportPreviewLookup(row, "businessEntity", businessEntities, businessEntityName);

  if (mode === "planned" && values.lessonType !== "planned") {
    addLessonImportPreviewIssue(row, "error", "lessonType", "预定分栏只能预览为 planned。");
  }

  if (mode === "actual" && values.lessonType !== "actual") {
    addLessonImportPreviewIssue(row, "error", "lessonType", "实际分栏只能预览为 actual。");
  }

  if (values.lessonType && !["planned", "actual"].includes(values.lessonType)) {
    addLessonImportPreviewIssue(row, "error", "lessonType", "lesson_type 只支持 planned / actual。");
  }

  if (values.status && !Object.keys(LESSON_STATUS_LABELS).includes(values.status)) {
    addLessonImportPreviewIssue(row, "error", "status", "status 不在 lesson V1 支持范围内。");
  }

  if (values.lessonType === "planned" && values.status && !["planned", "pending_makeup"].includes(values.status)) {
    addLessonImportPreviewIssue(row, "error", "status", "planned 只允许待上课 / 待补课。");
  }

  if (values.lessonType === "actual" && values.status && !["completed", "cancelled", "makeup_completed"].includes(values.status)) {
    addLessonImportPreviewIssue(row, "error", "status", "actual 只允许已完成 / 已取消 / 补课完成。");
  }

  if (hasLessonImportPreviewValue(row.raw.lessonDate) && !values.lessonDate) {
    addLessonImportPreviewIssue(row, "error", "lessonDate", "日期无法转换为 YYYY-MM-DD。");
  }

  if (!Number.isFinite(values.durationHours) || values.durationHours <= 0) {
    addLessonImportPreviewIssue(row, "error", "durationHours", "课时必须是大于 0 的数字。");
  }

  if (hasLessonImportPreviewValue(row.raw.lessonFee) && (!Number.isFinite(values.lessonFee) || values.lessonFee < 0)) {
    addLessonImportPreviewIssue(row, "error", "lessonFee", "金额必须是 0 或正数。");
  }

  if (!hasLessonImportPreviewValue(row.raw.lessonFee)) {
    if (Number.isFinite(values.durationHours) && Number.isFinite(values.unitPrice) && values.durationHours > 0 && values.unitPrice > 0) {
      values.lessonFee = Math.round(values.durationHours * values.unitPrice);
      addLessonImportPreviewIssue(row, "warning", "lessonFee", "金额为空，已按课时 x 单价做 preview 估算。");
    } else {
      addLessonImportPreviewIssue(row, "warning", "lessonFee", "金额为空；preview 阶段不自动写入，后续导入前需确认。");
    }
  }

  if (values.status === "cancelled" && Number(values.lessonFee || 0) !== 0) {
    addLessonImportPreviewIssue(row, "warning", "lessonFee", "已取消 actual 通常应为 0 金额。");
  }

  if (values.status === "makeup_completed") {
    addLessonImportPreviewIssue(row, "warning", "status", "preview 阶段只标识补课完成，不建立 planned 关联。");
  }
}

function validateLessonImportPreviewLookup(row, field, rows, labelGetter) {
  const rawValue = row.values[field];

  if (!rawValue) {
    return;
  }

  const match = findLessonImportPreviewLookup(rawValue, rows, labelGetter);
  if (!match.item) {
    addLessonImportPreviewIssue(row, "error", field, match.ambiguous ? "匹配到多个主数据，请使用更精确名称。" : "未能在当前主数据 lookup 中识别。");
    return;
  }

  row.values[`${field}Id`] = match.item.id;
  row.values[field] = labelGetter(match.item);

  if (isInactiveLessonImportPreviewLookup(match.item)) {
    addLessonImportPreviewIssue(row, "warning", field, "匹配到的主数据疑似非激活状态。");
  }
}

function findLessonImportPreviewLookup(value, rows, labelGetter) {
  const text = normalizeLessonImportLookup(value);
  const candidates = rows
    .map((item) => ({
      item,
      keys: [
        item.id,
        item.name,
        item.display_name,
        item.full_name,
        item.code,
        labelGetter(item),
      ].map(normalizeLessonImportLookup).filter(Boolean),
    }))
    .filter(({ keys }) => keys.length);

  const exact = candidates.find(({ keys }) => keys.includes(text));
  if (exact) {
    return { item: exact.item, ambiguous: false };
  }

  const fuzzy = candidates.filter(({ keys }) => (
    keys.some((key) => key.includes(text) || text.includes(key))
  ));

  if (fuzzy.length === 1) {
    return { item: fuzzy[0].item, ambiguous: false };
  }

  return { item: null, ambiguous: fuzzy.length > 1 };
}

function renderLessonImportPreview() {
  const rows = importPreviewRows;
  const errorCount = rows.filter((row) => row.errors.length).length;
  const warningCount = rows.filter((row) => row.warnings.length).length;
  const plannedCount = rows.filter((row) => row.values.lessonType === "planned").length;
  const actualCount = rows.filter((row) => row.values.lessonType === "actual").length;

  dom.lessonImportPreviewEmpty.classList.toggle("is-hidden", rows.length > 0);
  dom.lessonImportPreviewSummary.classList.toggle("is-hidden", rows.length === 0);
  dom.lessonImportPreviewRows.innerHTML = rows.map(renderLessonImportPreviewRow).join("");

  if (rows.length) {
    dom.lessonImportPreviewSummary.innerHTML = [
      renderDialogSummaryRow("预览行", `${rows.length} 行`),
      renderDialogSummaryRow("planned / actual", `${plannedCount} / ${actualCount}`),
      renderDialogSummaryRow("错误行", `${errorCount} 行`),
      renderDialogSummaryRow("警告行", `${warningCount} 行`),
    ].join("");
  } else {
    dom.lessonImportPreviewSummary.innerHTML = "";
  }
}

function renderLessonImportPreviewRow(row) {
  const rowClass = row.errors.length
    ? "lesson-import-preview-row-error"
    : row.warnings.length
      ? "lesson-import-preview-row-warning"
      : "";
  const values = row.values;

  return `
    <tr class="${escapeAttribute(rowClass)}">
      <td class="lesson-nowrap">${escapeHtml(row.rowNo)}</td>
      ${renderLessonImportPreviewCell(row, "student", values.student)}
      ${renderLessonImportPreviewCell(row, "teacher", values.teacher)}
      ${renderLessonImportPreviewCell(row, "subject", values.subject)}
      ${renderLessonImportPreviewCell(row, "businessEntity", values.businessEntity)}
      ${renderLessonImportPreviewCell(row, "lessonDate", values.lessonDate)}
      <td class="lesson-nowrap">${escapeHtml(formatLessonImportPreviewTime(values.startTime, values.endTime))}</td>
      ${renderLessonImportPreviewCell(row, "lessonType", values.lessonType)}
      ${renderLessonImportPreviewCell(row, "status", values.status ? lessonStatusLabel(values.status) : "")}
      ${renderLessonImportPreviewCell(row, "durationHours", displayImportPreviewNumber(values.durationHours))}
      ${renderLessonImportPreviewCell(row, "lessonFee", displayImportPreviewNumber(values.lessonFee))}
      <td class="lesson-import-preview-note-cell">${escapeHtml(displayValue(values.note))}</td>
      <td>${renderLessonImportPreviewIssues(row)}</td>
    </tr>
  `;
}

function renderLessonImportPreviewCell(row, field, value) {
  const className = row.invalidFields.has(field) ? "lesson-import-preview-cell-error" : "";
  return `<td class="${escapeAttribute(className)}">${escapeHtml(displayValue(value))}</td>`;
}

function renderLessonImportPreviewIssues(row) {
  const issues = [
    ...row.errors.map((message) => ({ type: "error", message })),
    ...row.warnings.map((message) => ({ type: "warning", message })),
  ];

  if (!issues.length) {
    return '<span class="status-badge status-paid">OK</span>';
  }

  return `
    <ul class="lesson-import-preview-issues">
      ${issues.map((issue) => `
        <li class="lesson-import-preview-issue-${escapeAttribute(issue.type)}">${escapeHtml(issue.message)}</li>
      `).join("")}
    </ul>
  `;
}

function renderDialogSummaryRow(label, value) {
  return `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(value)}</span>
    </div>
  `;
}

function showLessonImportPreviewError(message) {
  dom.lessonImportPreviewError.textContent = message;
  dom.lessonImportPreviewError.classList.remove("is-hidden");
}

function hideLessonImportPreviewError() {
  dom.lessonImportPreviewError.textContent = "";
  dom.lessonImportPreviewError.classList.add("is-hidden");
}

function importPreviewBaseYear() {
  const selected = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  const year = Number(selected?.slice(0, 4));
  return Number.isFinite(year) ? year : new Date().getFullYear();
}

function normalizeLessonImportHeader(value) {
  return String(value || "")
    .trim()
    .replace(/\s+/g, "")
    .replace(/[（）()]/g, "")
    .toLowerCase();
}

function normalizeLessonImportLookup(value) {
  return String(value || "")
    .replace(/（.*?）|\(.*?\)|\/.*$/g, "")
    .replace(/\s+/g, "")
    .toLowerCase();
}

function isBlankLessonImportPreviewRow(row) {
  return !(row || []).some((cell) => String(cell ?? "").trim());
}

function lessonImportPreviewSideHasData(row, columnIndexes) {
  return (columnIndexes || []).some((index) => (
    typeof index === "number" && String(row[index] ?? "").trim() !== ""
  ));
}

function lessonImportPreviewUsesPairedColumns(columnMap) {
  return [columnMap.plannedDate, columnMap.plannedStatus, columnMap.actualDate, columnMap.actualStatus]
    .some((index) => typeof index === "number");
}

function readLessonImportPreviewCell(row, index) {
  return typeof index === "number" ? row[index] : "";
}

function importPreviewCellText(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return formatLessonImportPreviewDate(value);
  }

  return String(value ?? "").trim();
}

function normalizeLessonImportPreviewType(value) {
  const text = normalizeLessonImportHeader(value);
  if (!text) {
    return "";
  }

  if (text === "planned" || /计划|預定|预定|予定/.test(text)) {
    return "planned";
  }

  if (text === "actual" || /实际|実際|实绩|實績/.test(text)) {
    return "actual";
  }

  return text;
}

function normalizeLessonImportPreviewStatus(value) {
  const text = normalizeLessonImportHeader(value);
  if (!text) {
    return "";
  }

  if (text === "planned" || /待上课|待上|预定|予定/.test(text)) {
    return "planned";
  }

  if (text === "pending_makeup" || text === "pendingmakeup" || /待补课|待補課|待补|未补/.test(text)) {
    return "pending_makeup";
  }

  if (text === "completed" || /已完成|已上课|已上|上课済|済|完成/.test(text)) {
    return "completed";
  }

  if (text === "cancelled" || text === "canceled" || /已取消|取消课|取消|请假|休|放假/.test(text)) {
    return "cancelled";
  }

  if (text === "makeup_completed" || text === "makeupcompleted" || text === "makeup" || /补课完成|補完|已补课|已補課|已补|已補/.test(text)) {
    return "makeup_completed";
  }

  return text;
}

function inferLessonTypeFromStatus(status) {
  if (["planned", "pending_makeup"].includes(status)) {
    return "planned";
  }

  if (["completed", "cancelled", "makeup_completed"].includes(status)) {
    return "actual";
  }

  return "";
}

function parseLessonImportPreviewDate(value, baseYear) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return formatLessonImportPreviewDate(value);
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    const date = new Date(Math.round((value - 25569) * 86400 * 1000));
    return Number.isNaN(date.getTime()) ? "" : formatLessonImportPreviewDate(date);
  }

  const text = String(value || "")
    .trim()
    .replace(/周|週|星期|礼拜/g, "")
    .replace(/[年月]/g, "-")
    .replace(/日/g, "")
    .replace(/\//g, "-");

  if (!text) {
    return "";
  }

  let match = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
  if (match) {
    return normalizedYmd(match[1], match[2], match[3]);
  }

  match = text.match(/^(\d{1,2})[-.](\d{1,2})$/);
  if (match) {
    return normalizedYmd(baseYear, match[1], match[2]);
  }

  return "";
}

function formatLessonImportPreviewDate(date) {
  return normalizedYmd(date.getFullYear(), date.getMonth() + 1, date.getDate());
}

function normalizedYmd(year, month, day) {
  const y = Number(year);
  const m = Number(month);
  const d = Number(day);
  const date = new Date(y, m - 1, d);

  if (
    !Number.isFinite(y)
    || !Number.isFinite(m)
    || !Number.isFinite(d)
    || date.getFullYear() !== y
    || date.getMonth() !== m - 1
    || date.getDate() !== d
  ) {
    return "";
  }

  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

function parseLessonImportPreviewTime(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return `${String(value.getHours()).padStart(2, "0")}:${String(value.getMinutes()).padStart(2, "0")}`;
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    if (value >= 0 && value < 1) {
      const minutes = Math.round(value * 24 * 60);
      return `${String(Math.floor(minutes / 60) % 24).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
    }
    return "";
  }

  const text = String(value || "").trim();
  const match = text.match(/(\d{1,2})[:：](\d{1,2})/);
  if (!match) {
    return "";
  }

  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return "";
  }

  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function applyLessonImportPreviewTimeRange(row) {
  const range = String(row.raw.timeRange || "");
  if ((!row.values.startTime || !row.values.endTime) && range) {
    const matches = Array.from(range.matchAll(/(\d{1,2})[:：](\d{1,2})/g));
    if (!row.values.startTime && matches[0]) {
      row.values.startTime = parseLessonImportPreviewTime(`${matches[0][1]}:${matches[0][2]}`);
    }
    if (!row.values.endTime && matches[1]) {
      row.values.endTime = parseLessonImportPreviewTime(`${matches[1][1]}:${matches[1][2]}`);
    }
  }

  if ((!Number.isFinite(row.values.durationHours) || row.values.durationHours <= 0) && row.values.startTime && row.values.endTime) {
    const minutes = minutesBetweenLessonImportPreviewTimes(row.values.startTime, row.values.endTime);
    if (minutes > 0) {
      row.values.durationHours = Math.round((minutes / 60) * 100) / 100;
      addLessonImportPreviewIssue(row, "warning", "durationHours", "课时为空，已按开始/结束时间做 preview 估算。");
    }
  }
}

function minutesBetweenLessonImportPreviewTimes(start, end) {
  const startMinutes = clockMinutes(start);
  const endMinutes = clockMinutes(end);
  if (startMinutes === null || endMinutes === null) {
    return 0;
  }

  let diff = endMinutes - startMinutes;
  if (diff < 0) {
    diff += 24 * 60;
  }

  return diff;
}

function clockMinutes(value) {
  const match = String(value || "").match(/^(\d{2}):(\d{2})$/);
  if (!match) {
    return null;
  }

  return Number(match[1]) * 60 + Number(match[2]);
}

function parseLessonImportPreviewNumber(value) {
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : Number.NaN;
  }

  const text = String(value ?? "").trim();
  if (!text) {
    return Number.NaN;
  }

  return Number(text.replace(/[,，円￥¥小时時間HhＨ]/g, ""));
}

function hasLessonImportPreviewValue(value) {
  if (typeof value === "number") {
    return Number.isFinite(value);
  }

  return String(value ?? "").trim() !== "";
}

function addLessonImportPreviewIssue(row, type, field, message) {
  row.invalidFields.add(field);
  if (type === "warning") {
    if (!row.warnings.includes(message)) {
      row.warnings.push(message);
    }
    return;
  }

  if (!row.errors.includes(message)) {
    row.errors.push(message);
  }
}

function isInactiveLessonImportPreviewLookup(item) {
  const status = normalizeLessonImportHeader(item.status);
  return item.is_active === false || ["inactive", "disabled", "archived", "suspended", "退会", "停用", "无效"].includes(status);
}

function formatLessonImportPreviewTime(start, end) {
  if (!start && !end) {
    return "-";
  }

  return `${start || "-"} - ${end || "-"}`;
}

function displayImportPreviewNumber(value) {
  return Number.isFinite(value) ? value : "";
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
  const actionHtml = canGenerateActualFromPlanned(planned)
    ? [
        `<button class="button button-primary table-action-button" type="button" data-generate-actual-id="${escapeAttribute(planned.id)}">生成 actual</button>`,
        `<button class="button table-action-button" type="button" data-generate-cancelled-actual-id="${escapeAttribute(planned.id)}">标记取消</button>`,
        `<button class="button table-action-button" type="button" data-generate-makeup-actual-id="${escapeAttribute(planned.id)}">补课完成</button>`,
      ].join("")
    : "";
  return `
    <div class="lesson-pair-placeholder">
      <span>${escapeHtml(statusText)}</span>
      <span class="lesson-pair-placeholder-id">planned ${escapeHtml(shortId(planned.id))}</span>
      ${actionHtml ? `<div class="lesson-pair-placeholder-actions">${actionHtml}</div>` : ""}
    </div>
  `;
}

function canGenerateActualFromPlanned(planned) {
  return planned
    && planned.lesson_type === "planned"
    && ["planned", "pending_makeup"].includes(planned.status);
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
      ${renderLessonPairText(record)}
    </article>
  `;
}

function renderLessonPairText(record) {
  const content = safeText(record.lesson_content);
  const note = safeText(record.note);
  const hasLongText = [content, note].some((value) => value.length > 80 || value.includes("\n"));
  const toggleHtml = hasLongText
    ? '<button class="button table-action-button lesson-pair-text-toggle" type="button" data-lesson-pair-text-toggle aria-expanded="false">展开</button>'
    : "";

  return `
    <div class="lesson-pair-text${hasLongText ? " lesson-pair-text-collapsible" : ""}">
      <div class="lesson-pair-text-row">
        <span class="lesson-pair-text-label">内容</span>
        <span class="lesson-pair-text-value">${escapeHtml(displayValue(content))}</span>
      </div>
      <div class="lesson-pair-text-row">
        <span class="lesson-pair-text-label">备注</span>
        <span class="lesson-pair-text-value">${escapeHtml(displayValue(note))}</span>
      </div>
      ${toggleHtml}
    </div>
  `;
}

function handleLessonPairTextToggle(button) {
  const textBlock = button.closest(".lesson-pair-text");
  if (!textBlock) {
    return;
  }

  const shouldExpand = !textBlock.classList.contains("is-expanded");
  textBlock.classList.toggle("is-expanded", shouldExpand);
  button.setAttribute("aria-expanded", String(shouldExpand));
  button.textContent = shouldExpand ? "收起" : "展开";
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

function formatInputTime(value) {
  const text = safeText(value);
  return text ? text.slice(0, 5) : "";
}

function displayInputNumber(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }

  return String(value);
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
