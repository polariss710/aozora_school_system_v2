import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createActualLessonFromPlanned,
  createCancelledActualLessonFromPlanned,
  createCrossMonthMakeupCompletedActualFromPlanned,
  createMakeupCompletedActualLessonFromPlanned,
  createPlannedLessonRecord,
  fetchCrossMonthMakeupReferences,
  fetchCrossMonthMakeupSourceLessons,
  fetchLessonBusinessEntities,
  fetchLessonImportLockPrecheck,
  fetchLessonImportPlannedReferences,
  fetchLessonRecords,
  fetchLessonStudents,
  fetchLessonSubjects,
  fetchLessonTeachers,
  importPlannedLessonRecordsBatch,
} from "../api/lesson-api.js";
import { cacheLessonEditDialogDom, createLessonEditDialogController } from "../components/lesson-edit-dialog.js";
import { cacheLessonVoidDialogDom, createLessonVoidDialogController } from "../components/lesson-void-dialog.js";
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

const DEFAULT_LESSON_VIEW = "pair";

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

const LESSON_STATUS_FILTER_OPTIONS = [
  ["", "全部"],
  ["planned", "待上课"],
  ["pending_makeup", "待补课"],
  ["completed", "已上课"],
  ["cancelled", "取消课"],
  ["makeup_completed", "已补课"],
  ["voided", "已作废"],
];

const SUBJECT_SORT_RULES = [
  ["日语", "日本語", "JLPT"],
  ["数学", "math"],
  ["物理", "physics"],
  ["化学", "chemistry"],
  ["文综", "综合科目", "総合科目", "文科"],
];

const LESSON_IMPORT_PREVIEW_FIELD_LABELS = {
  student: "学生",
  teacher: "老师",
  subject: "科目",
  businessEntity: "业务归属",
  lessonDate: "日期",
  lessonType: "课时类型",
  status: "状态",
  durationHours: "课时",
  lessonCount: "回数",
  lessonFee: "课时费总额 JPY",
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

const LESSON_IMPORT_FIELD_ALIAS_TEXT = {
  businessEntity: "业务归属 / business_entity",
  lessonType: "课时类型 / lesson_type / 类型",
  status: "status / 状态 / 预定状态 / 实际状态",
  durationHours: "课时 / 时长 / hours / 時間数 / 授業時間",
};

const LESSON_IMPORT_TEMPLATE_HEADERS = [
  "学生",
  "老师",
  "科目",
  "业务归属",
  "日期",
  "开始时间",
  "结束时间",
  "课时类型",
  "状态",
  "课时",
  "回数",
  "课时费总额 JPY",
  "是否计费",
  "内容",
  "备注",
];

const LESSON_IMPORT_TEMPLATE_ROWS = [
  ["示例学生", "示例老师", "数学", "青空进学塾", "2026-06-10", "10:00", "11:00", "预定", "待上课", 1, 1, 5000, "是", "预定课内容", "预定-待上课 示例"],
  ["示例学生", "示例老师", "数学", "青空进学塾", "2026-06-11", "10:00", "11:00", "预定", "待补课", 1, 2, 5000, "是", "待补课预定内容", "预定-待补课 示例"],
];

const LESSON_IMPORT_TEMPLATE_GUIDE_ROWS = [
  ["字段", "必填", "说明 / 合法值"],
  ["示例值", "说明", "主表只放预定课时示例；模板中的示例学生、示例老师、数学、青空进学塾需要替换为当前系统已有主数据。"],
  ["学生", "是", "填写学生名称；preview 仅按 trim/normalize 后完全一致匹配，不做模糊猜测。"],
  ["老师", "是", "填写老师名称；可兼容 担当老师 / teacher 等表头；lookup 仅允许完全一致。"],
  ["科目", "是", "填写科目名称；可兼容 subject / 講座 等表头；lookup 仅允许完全一致。"],
  ["业务归属", "是", "填写业务归属名称；可兼容 business_entity / entity 等表头；lookup 仅允许完全一致。"],
  ["日期", "是", "YYYY-MM-DD；也可用 Excel 日期。"],
  ["开始时间 / 结束时间", "建议", "HH:mm；课时为空时 preview 可按时间估算。"],
  ["课时类型", "是", "当前提交只支持 预定；preview 仍可识别 实际 / actual 但不会提交。"],
  ["状态", "是", "预定可填 待上课 / 待补课。"],
  ["状态英文兼容", "说明", "待上课兼容 pending / planned；待补课兼容 pending_makeup；已上课兼容 completed；取消兼容 cancelled；已补课兼容 makeup_completed。"],
  ["合法组合", "说明", "当前可提交：预定 + 待上课 / 待补课。"],
  ["当前导入范围", "说明", "第一版提交只支持预定课时；actual 行仅用于 preview，不会写入。"],
  ["课时", "是", "大于 0 的数字。"],
  ["回数", "否", "正整数；为空时不写入 lesson_count。"],
  ["课时费总额 JPY", "建议", "整条课时记录的课时费总额，不是单价；0 或正数；为空时 preview 只提示确认，不写入。"],
  ["是否计费", "建议", "是 / 否 / true / false。"],
  ["内容 / 备注", "否", "文本。"],
  ["旧模板关联预定ID", "忽略", "planned-only 导入会忽略旧模板中的关联预定ID，不写入关联。"],
  ["future actual 示例", "说明", "完整课时导入仅作为 future/history migration backlog：实际 + 已上课 / completed，关联预定ID 可选。"],
  ["future actual 示例", "说明", "完整课时导入仅作为 future/history migration backlog：实际 + 取消 / cancelled，金额通常为 0。"],
  ["future actual 示例", "说明", "完整课时导入仅作为 future/history migration backlog：实际 + 已补课 / makeup_completed，是否计费需单独规则。"],
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

const CREATE_CROSS_MONTH_MAKEUP_ACTUAL_FIELD_IDS = [
  "sourceMonthFrom",
  "sourceMonthTo",
  "sourceLesson",
  "lessonDate",
  "startTime",
  "endTime",
  "durationHours",
  "unitPrice",
  "lessonCount",
];

const dom = {};
let students = [];
let teachers = [];
let subjects = [];
let businessEntities = [];
let lessonRecords = [];
let crossMonthMakeupReferences = emptyCrossMonthMakeupReferences();
let loadedMonth = "";
let loadedLessonRecordMode = "";
let activeView = DEFAULT_LESSON_VIEW;
let isCreatePlannedLessonSubmitting = false;
let isCreateLessonFeeManual = false;
let createPlannedLessonInitialSnapshot = null;
let isCreatePlannedLessonCloseConfirmPending = false;
let currentActualSourceLesson = null;
let isCreateActualLessonSubmitting = false;
let isActualLessonFeeManual = false;
let createActualLessonInitialSnapshot = null;
let isCreateActualLessonCloseConfirmPending = false;
let currentCancelledActualSourceLesson = null;
let isCreateCancelledActualLessonSubmitting = false;
let createCancelledActualLessonInitialSnapshot = null;
let isCreateCancelledActualLessonCloseConfirmPending = false;
let currentMakeupActualSourceLesson = null;
let isCreateMakeupActualLessonSubmitting = false;
let isMakeupLessonFeeManual = false;
let createMakeupActualLessonInitialSnapshot = null;
let isCreateMakeupActualLessonCloseConfirmPending = false;
let crossMonthMakeupSourceLessons = [];
let currentCrossMonthMakeupSourceLesson = null;
let isCrossMonthMakeupSourceLoading = false;
let isCreateCrossMonthMakeupActualSubmitting = false;
let createCrossMonthMakeupActualInitialSnapshot = null;
let isCreateCrossMonthMakeupActualCloseConfirmPending = false;
let lessonEditController = null;
let lessonVoidController = null;
let isLessonPageInitialized = false;
let initialLessonQueryFilters = null;
let importPreviewRows = [];
let importPreviewFileMeta = null;
let isLessonImportSubmitting = false;
let lastLessonImportResult = null;
const successfulLessonImportFileHashes = new Set();

export function initLessonPage() {
  if (isLessonPageInitialized) {
    return;
  }
  isLessonPageInitialized = true;

  cacheDom();
  setupLessonEditController();
  setupLessonVoidController();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  [
    dom.crossMonthMakeupSourceFromYearSelect,
    dom.crossMonthMakeupSourceToYearSelect,
  ].forEach((select) => populateYearSelect(select, PAYMENT_MONTH_FILTER_YEAR_RANGE));
  [
    dom.crossMonthMakeupSourceFromMonthSelect,
    dom.crossMonthMakeupSourceToMonthSelect,
  ].forEach((select) => populateMonthSelect(select));
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

function setupLessonVoidController() {
  lessonVoidController = createLessonVoidDialogController({
    dom: cacheLessonVoidDialogDom(),
    getLessonRecords: () => lessonRecords,
    hasSupabaseConfig,
    showMessage,
    onVoided: refreshAfterVoidLesson,
    getLinkedActualExists: hasLinkedActualLesson,
    setExternalBusy: (isBusy) => {
      if (dom.openCreatePlannedLessonButton) {
        dom.openCreatePlannedLessonButton.disabled = isBusy;
      }
    },
  });
  lessonVoidController.init();
}

function setupLessonEditController() {
  lessonEditController = createLessonEditDialogController({
    dom: cacheLessonEditDialogDom(),
    getLessonRecords: () => lessonRecords,
    getMasterData: () => ({ students, teachers, subjects, businessEntities }),
    hasSupabaseConfig,
    showMessage,
    onSaved: refreshAfterEditLesson,
    setExternalBusy: (isBusy) => {
      if (dom.openCreatePlannedLessonButton) {
        dom.openCreatePlannedLessonButton.disabled = isBusy;
      }
    },
  });
  lessonEditController.init();
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
  dom.openCrossMonthMakeupDialogButton = document.querySelector("#openCrossMonthMakeupDialogButton");
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
  dom.lessonImportTemplateExportButton = document.querySelector("#lessonImportTemplateExportButton");
  dom.lessonImportPlannedSubmitButton = document.querySelector("#lessonImportPlannedSubmitButton");
  dom.lessonImportViewMonthButton = document.querySelector("#lessonImportViewMonthButton");
  dom.lessonImportViewFirstDetailButton = document.querySelector("#lessonImportViewFirstDetailButton");
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
  dom.createCrossMonthMakeupActualDialog = document.querySelector("#createCrossMonthMakeupActualDialog");
  dom.createCrossMonthMakeupActualSummary = document.querySelector("#createCrossMonthMakeupActualSummary");
  dom.createCrossMonthMakeupActualSourceSummary = document.querySelector("#createCrossMonthMakeupActualSourceSummary");
  dom.createCrossMonthMakeupActualError = document.querySelector("#createCrossMonthMakeupActualError");
  dom.crossMonthMakeupSourceFromYearSelect = document.querySelector("#crossMonthMakeupSourceFromYearSelect");
  dom.crossMonthMakeupSourceFromMonthSelect = document.querySelector("#crossMonthMakeupSourceFromMonthSelect");
  dom.crossMonthMakeupSourceToYearSelect = document.querySelector("#crossMonthMakeupSourceToYearSelect");
  dom.crossMonthMakeupSourceToMonthSelect = document.querySelector("#crossMonthMakeupSourceToMonthSelect");
  dom.crossMonthMakeupSourceRefreshButton = document.querySelector("#crossMonthMakeupSourceRefreshButton");
  dom.crossMonthMakeupSourceSelect = document.querySelector("#crossMonthMakeupSourceSelect");
  dom.crossMonthMakeupSourceCount = document.querySelector("#crossMonthMakeupSourceCount");
  dom.createCrossMonthMakeupActualDateInput = document.querySelector("#createCrossMonthMakeupActualDateInput");
  dom.createCrossMonthMakeupActualStartTimeInput = document.querySelector("#createCrossMonthMakeupActualStartTimeInput");
  dom.createCrossMonthMakeupActualEndTimeInput = document.querySelector("#createCrossMonthMakeupActualEndTimeInput");
  dom.createCrossMonthMakeupActualDurationInput = document.querySelector("#createCrossMonthMakeupActualDurationInput");
  dom.createCrossMonthMakeupActualUnitPriceInput = document.querySelector("#createCrossMonthMakeupActualUnitPriceInput");
  dom.createCrossMonthMakeupActualFeeInput = document.querySelector("#createCrossMonthMakeupActualFeeInput");
  dom.createCrossMonthMakeupActualCountInput = document.querySelector("#createCrossMonthMakeupActualCountInput");
  dom.createCrossMonthMakeupActualContentInput = document.querySelector("#createCrossMonthMakeupActualContentInput");
  dom.createCrossMonthMakeupActualNoteInput = document.querySelector("#createCrossMonthMakeupActualNoteInput");
  dom.createCrossMonthMakeupActualSubmitButton = document.querySelector("#createCrossMonthMakeupActualSubmitButton");
  dom.createCrossMonthMakeupActualCancelButton = document.querySelector("#createCrossMonthMakeupActualCancelButton");
  dom.editLessonDialog = document.querySelector("#editLessonDialog");
  dom.editLessonSummary = document.querySelector("#editLessonSummary");
  dom.editLessonWarning = document.querySelector("#editLessonWarning");
  dom.editLessonError = document.querySelector("#editLessonError");
  dom.editLessonTypeInput = document.querySelector("#editLessonTypeInput");
  dom.editLessonStatusSelect = document.querySelector("#editLessonStatusSelect");
  dom.editLessonDateInput = document.querySelector("#editLessonDateInput");
  dom.editLessonBillableSelect = document.querySelector("#editLessonBillableSelect");
  dom.editLessonStudentSelect = document.querySelector("#editLessonStudentSelect");
  dom.editLessonTeacherSelect = document.querySelector("#editLessonTeacherSelect");
  dom.editLessonSubjectSelect = document.querySelector("#editLessonSubjectSelect");
  dom.editLessonBusinessEntitySelect = document.querySelector("#editLessonBusinessEntitySelect");
  dom.editLessonStartTimeInput = document.querySelector("#editLessonStartTimeInput");
  dom.editLessonEndTimeInput = document.querySelector("#editLessonEndTimeInput");
  dom.editLessonDurationInput = document.querySelector("#editLessonDurationInput");
  dom.editLessonUnitPriceInput = document.querySelector("#editLessonUnitPriceInput");
  dom.editLessonFeeInput = document.querySelector("#editLessonFeeInput");
  dom.editLessonCountInput = document.querySelector("#editLessonCountInput");
  dom.editLessonPlannedIdInput = document.querySelector("#editLessonPlannedIdInput");
  dom.editLessonImportSourceInput = document.querySelector("#editLessonImportSourceInput");
  dom.editLessonContentInput = document.querySelector("#editLessonContentInput");
  dom.editLessonNoteInput = document.querySelector("#editLessonNoteInput");
  dom.editLessonSubmitButton = document.querySelector("#editLessonSubmitButton");
  dom.editLessonCancelButton = document.querySelector("#editLessonCancelButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    applyQuery();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters(defaultLessonFilters());
    clearLessonQueryUrl();
    applyQuery({ updateUrl: false });
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
  dom.lessonImportTemplateExportButton?.addEventListener("click", handleLessonImportTemplateExport);
  dom.lessonImportPlannedSubmitButton?.addEventListener("click", handleLessonImportPlannedSubmit);
  dom.lessonImportViewMonthButton?.addEventListener("click", handleLessonImportViewMonthClick);
  dom.lessonImportViewFirstDetailButton?.addEventListener("click", handleLessonImportViewFirstDetailClick);
  dom.openCrossMonthMakeupDialogButton?.addEventListener("click", openCreateCrossMonthMakeupActualDialog);

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") {
      return;
    }
    const activeDialog = activeLessonCreateDialog();
    if (activeDialog) {
      event.preventDefault();
      activeDialog.blockDirectDismiss();
    }
  });

  dom.tableBody?.addEventListener("click", (event) => {
    const voidButton = event.target.closest("[data-void-planned-lesson-id]");
    if (voidButton) {
      lessonVoidController?.open(voidButton.dataset.voidPlannedLessonId || "");
      return;
    }

    const editButton = event.target.closest("[data-edit-lesson-id]");
    if (editButton) {
      lessonEditController?.open(editButton.dataset.editLessonId || "");
    }
  });

  dom.openCreatePlannedLessonButton?.addEventListener("click", openCreatePlannedLessonDialog);
  dom.createPlannedLessonCancelButton?.addEventListener("click", () => closeCreatePlannedLessonDialog());
  dom.createPlannedLessonSubmitButton?.addEventListener("click", handleCreatePlannedLessonSubmit);

  dom.createPlannedLessonDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createPlannedLessonDialog) {
      blockCreatePlannedLessonDirectDismiss();
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
      isCreatePlannedLessonCloseConfirmPending = false;
      clearCreatePlannedLessonFieldInvalid(fieldId);
      hideCreatePlannedLessonErrorIfClean();
    });
    element?.addEventListener("change", () => {
      isCreatePlannedLessonCloseConfirmPending = false;
      clearCreatePlannedLessonFieldInvalid(fieldId);
      hideCreatePlannedLessonErrorIfClean();
    });
  });

  dom.createPlannedLessonStartTimeInput?.addEventListener("input", syncCreatePlannedLessonDurationFromTimeRange);
  dom.createPlannedLessonStartTimeInput?.addEventListener("change", syncCreatePlannedLessonDurationFromTimeRange);
  dom.createPlannedLessonEndTimeInput?.addEventListener("input", syncCreatePlannedLessonDurationFromTimeRange);
  dom.createPlannedLessonEndTimeInput?.addEventListener("change", syncCreatePlannedLessonDurationFromTimeRange);
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
      return;
    }

    const voidButton = event.target.closest("[data-void-planned-lesson-id]");
    if (voidButton) {
      lessonVoidController?.open(voidButton.dataset.voidPlannedLessonId || "");
      return;
    }

    const editButton = event.target.closest("[data-edit-lesson-id]");
    if (editButton) {
      lessonEditController?.open(editButton.dataset.editLessonId || "");
    }
  });

  dom.createActualLessonCancelButton?.addEventListener("click", () => closeCreateActualLessonDialog());
  dom.createActualLessonSubmitButton?.addEventListener("click", handleCreateActualLessonSubmit);

  dom.createActualLessonDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createActualLessonDialog) {
      blockCreateActualLessonDirectDismiss();
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
      isCreateActualLessonCloseConfirmPending = false;
      clearCreateActualLessonFieldInvalid(fieldId);
      hideCreateActualLessonErrorIfClean();
    });
    element?.addEventListener("change", () => {
      isCreateActualLessonCloseConfirmPending = false;
      clearCreateActualLessonFieldInvalid(fieldId);
      hideCreateActualLessonErrorIfClean();
    });
  });

  dom.createActualLessonStartTimeInput?.addEventListener("input", syncCreateActualLessonDurationFromTimeRange);
  dom.createActualLessonStartTimeInput?.addEventListener("change", syncCreateActualLessonDurationFromTimeRange);
  dom.createActualLessonEndTimeInput?.addEventListener("input", syncCreateActualLessonDurationFromTimeRange);
  dom.createActualLessonEndTimeInput?.addEventListener("change", syncCreateActualLessonDurationFromTimeRange);
  dom.createActualLessonDurationInput?.addEventListener("input", updateCreateActualLessonFeePreview);
  dom.createActualLessonUnitPriceInput?.addEventListener("input", updateCreateActualLessonFeePreview);
  dom.createActualLessonFeeInput?.addEventListener("input", () => {
    isActualLessonFeeManual = dom.createActualLessonFeeInput.value.trim() !== "";
  });

  dom.createCancelledActualLessonCancelButton?.addEventListener("click", () => closeCreateCancelledActualLessonDialog());
  dom.createCancelledActualLessonSubmitButton?.addEventListener("click", handleCreateCancelledActualLessonSubmit);

  dom.createCancelledActualLessonDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createCancelledActualLessonDialog) {
      blockCreateCancelledActualLessonDirectDismiss();
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
      isCreateCancelledActualLessonCloseConfirmPending = false;
      clearCreateCancelledActualLessonFieldInvalid(fieldId);
      hideCreateCancelledActualLessonErrorIfClean();
    });
    element?.addEventListener("change", () => {
      isCreateCancelledActualLessonCloseConfirmPending = false;
      clearCreateCancelledActualLessonFieldInvalid(fieldId);
      hideCreateCancelledActualLessonErrorIfClean();
    });
  });

  dom.createCancelledActualLessonStartTimeInput?.addEventListener("input", syncCreateCancelledActualLessonDurationFromTimeRange);
  dom.createCancelledActualLessonStartTimeInput?.addEventListener("change", syncCreateCancelledActualLessonDurationFromTimeRange);
  dom.createCancelledActualLessonEndTimeInput?.addEventListener("input", syncCreateCancelledActualLessonDurationFromTimeRange);
  dom.createCancelledActualLessonEndTimeInput?.addEventListener("change", syncCreateCancelledActualLessonDurationFromTimeRange);

  dom.createMakeupActualLessonCancelButton?.addEventListener("click", () => closeCreateMakeupActualLessonDialog());
  dom.createMakeupActualLessonSubmitButton?.addEventListener("click", handleCreateMakeupActualLessonSubmit);

  dom.createMakeupActualLessonDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createMakeupActualLessonDialog) {
      blockCreateMakeupActualLessonDirectDismiss();
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
      isCreateMakeupActualLessonCloseConfirmPending = false;
      clearCreateMakeupActualLessonFieldInvalid(fieldId);
      hideCreateMakeupActualLessonErrorIfClean();
    });
    element?.addEventListener("change", () => {
      isCreateMakeupActualLessonCloseConfirmPending = false;
      clearCreateMakeupActualLessonFieldInvalid(fieldId);
      hideCreateMakeupActualLessonErrorIfClean();
    });
  });

  dom.createMakeupActualLessonBillableSelect?.addEventListener("change", handleCreateMakeupActualLessonBillableChange);
  dom.createMakeupActualLessonStartTimeInput?.addEventListener("input", syncCreateMakeupActualLessonDurationFromTimeRange);
  dom.createMakeupActualLessonStartTimeInput?.addEventListener("change", syncCreateMakeupActualLessonDurationFromTimeRange);
  dom.createMakeupActualLessonEndTimeInput?.addEventListener("input", syncCreateMakeupActualLessonDurationFromTimeRange);
  dom.createMakeupActualLessonEndTimeInput?.addEventListener("change", syncCreateMakeupActualLessonDurationFromTimeRange);
  dom.createMakeupActualLessonDurationInput?.addEventListener("input", updateCreateMakeupActualLessonFeePreview);
  dom.createMakeupActualLessonUnitPriceInput?.addEventListener("input", updateCreateMakeupActualLessonFeePreview);
  dom.createMakeupActualLessonFeeInput?.addEventListener("input", () => {
    isMakeupLessonFeeManual = dom.createMakeupActualLessonFeeInput.value.trim() !== "";
  });

  dom.createCrossMonthMakeupActualCancelButton?.addEventListener("click", () => closeCreateCrossMonthMakeupActualDialog());
  dom.createCrossMonthMakeupActualSubmitButton?.addEventListener("click", handleCreateCrossMonthMakeupActualSubmit);
  dom.crossMonthMakeupSourceRefreshButton?.addEventListener("click", loadCrossMonthMakeupSourceCandidates);
  dom.crossMonthMakeupSourceSelect?.addEventListener("change", handleCrossMonthMakeupSourceSelectionChange);

  dom.createCrossMonthMakeupActualDialog?.addEventListener("click", (event) => {
    if (event.target === dom.createCrossMonthMakeupActualDialog) {
      blockCreateCrossMonthMakeupActualDirectDismiss();
    }
  });

  [
    ["sourceMonthFrom", dom.crossMonthMakeupSourceFromYearSelect],
    ["sourceMonthFrom", dom.crossMonthMakeupSourceFromMonthSelect],
    ["sourceMonthTo", dom.crossMonthMakeupSourceToYearSelect],
    ["sourceMonthTo", dom.crossMonthMakeupSourceToMonthSelect],
    ["sourceLesson", dom.crossMonthMakeupSourceSelect],
    ["lessonDate", dom.createCrossMonthMakeupActualDateInput],
    ["startTime", dom.createCrossMonthMakeupActualStartTimeInput],
    ["endTime", dom.createCrossMonthMakeupActualEndTimeInput],
    ["durationHours", dom.createCrossMonthMakeupActualDurationInput],
    ["unitPrice", dom.createCrossMonthMakeupActualUnitPriceInput],
    ["lessonCount", dom.createCrossMonthMakeupActualCountInput],
  ].forEach(([fieldId, element]) => {
    element?.addEventListener("input", () => {
      isCreateCrossMonthMakeupActualCloseConfirmPending = false;
      clearCreateCrossMonthMakeupActualFieldInvalid(fieldId);
      hideCreateCrossMonthMakeupActualErrorIfClean();
    });
    element?.addEventListener("change", () => {
      isCreateCrossMonthMakeupActualCloseConfirmPending = false;
      clearCreateCrossMonthMakeupActualFieldInvalid(fieldId);
      hideCreateCrossMonthMakeupActualErrorIfClean();
    });
  });

  dom.createCrossMonthMakeupActualStartTimeInput?.addEventListener("input", syncCreateCrossMonthMakeupActualDurationFromTimeRange);
  dom.createCrossMonthMakeupActualStartTimeInput?.addEventListener("change", syncCreateCrossMonthMakeupActualDurationFromTimeRange);
  dom.createCrossMonthMakeupActualEndTimeInput?.addEventListener("input", syncCreateCrossMonthMakeupActualDurationFromTimeRange);
  dom.createCrossMonthMakeupActualEndTimeInput?.addEventListener("change", syncCreateCrossMonthMakeupActualDurationFromTimeRange);

}

function setDefaultFilters(filters = readInitialLessonQuery()) {
  initialLessonQueryFilters = filters;
  restoreFilterSelections(filters);
}

function defaultLessonFilters() {
  return {
    month: currentYearMonth(),
    view: DEFAULT_LESSON_VIEW,
    ...DEFAULT_FILTERS,
  };
}

function readInitialLessonQuery() {
  const params = new URLSearchParams(window.location.search);
  const filters = defaultLessonFilters();
  filters.month = readLessonQueryMonth(params);
  filters.view = normalizeLessonView(params.get("view"));
  filters.studentId = readLessonQueryValue(params, "student_id", "studentId");
  filters.teacherId = readLessonQueryValue(params, "teacher_id", "teacherId");
  filters.subjectId = readLessonQueryValue(params, "subject_id", "subjectId");
  filters.businessEntityId = readLessonQueryValue(params, "business_entity_id", "businessEntityId");
  filters.status = normalizeLessonStatusFilter(params.get("status"));
  return filters;
}

function readLessonQueryMonth(params) {
  const yearMonth = safeText(params.get("year_month") || params.get("yearMonth"));
  if (/^\d{4}-(0[1-9]|1[0-2])$/.test(yearMonth)) {
    return yearMonth;
  }

  const year = safeText(params.get("year"));
  const month = safeText(params.get("month")).padStart(2, "0");
  const hasMonth = /^\d{4}$/.test(year) && /^(0[1-9]|1[0-2])$/.test(month);
  return hasMonth ? `${year}-${month}` : currentYearMonth();
}

function readLessonQueryValue(params, snakeName, camelName) {
  return safeText(params.get(snakeName) || params.get(camelName));
}

function normalizeLessonView(value) {
  return value === "list" ? "list" : DEFAULT_LESSON_VIEW;
}

function normalizeLessonStatusFilter(value) {
  const status = safeText(value);
  return LESSON_STATUS_FILTER_OPTIONS.some(([optionValue]) => optionValue === status) ? status : "";
}

function syncLessonQueryUrl(filters) {
  if (!window.history?.replaceState) {
    return;
  }

  const params = buildLessonListQueryParams(filters);
  window.history.replaceState(null, "", `${window.location.pathname}?${params.toString()}`);
}

function buildLessonListQueryParams(filters) {
  const params = new URLSearchParams();
  const monthMatch = safeText(filters.month).match(/^(\d{4})-(0[1-9]|1[0-2])$/);
  if (monthMatch) {
    params.set("year", monthMatch[1]);
    params.set("month", monthMatch[2]);
  }
  params.set("view", normalizeLessonView(filters.view));
  if (filters.teacherId) params.set("teacher_id", filters.teacherId);
  if (filters.studentId) params.set("student_id", filters.studentId);
  if (filters.subjectId) params.set("subject_id", filters.subjectId);
  if (filters.businessEntityId) params.set("business_entity_id", filters.businessEntityId);
  if (filters.status) params.set("status", filters.status);

  return params;
}

function clearLessonQueryUrl() {
  if (window.history?.replaceState) {
    window.history.replaceState(null, "", window.location.pathname);
  }
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
    const filters = initialLessonQueryFilters || readFilters();
    await loadLessonMonth(filters.month, filters);
    restoreFilterSelections(filters);
    applyCurrentFilters();
    showMessage("success", "课时管理数据已加载。");
  } catch (error) {
    students = [];
    teachers = [];
    subjects = [];
    businessEntities = [];
    lessonRecords = [];
    crossMonthMakeupReferences = emptyCrossMonthMakeupReferences();
    loadedMonth = "";
    renderMasterOptions();
    renderDataOptions([]);
    renderLessonRecords([]);
    showMessage("error", `读取课时管理数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

async function applyQuery(options = {}) {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  if (!filters) {
    return;
  }

  if (options.updateUrl !== false) {
    syncLessonQueryUrl(filters);
  }

  if (filters.month !== loadedMonth || lessonRecordQueryMode(filters) !== loadedLessonRecordMode) {
    setLoading(true);
    showMessage("info", "正在加载课时记录...");

    try {
      await loadLessonMonth(filters.month, filters);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "课时记录已加载。");
    } catch (error) {
      lessonRecords = [];
      crossMonthMakeupReferences = emptyCrossMonthMakeupReferences();
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

async function loadLessonMonth(month, filters = {}) {
  const queryMode = lessonRecordQueryMode(filters);
  lessonRecords = sortLessonRecords(await fetchLessonRecords(month, { status: filters.status }));
  crossMonthMakeupReferences = buildCrossMonthMakeupReferenceMaps(
    await fetchCrossMonthMakeupReferences(month, lessonRecords)
  );
  loadedMonth = month;
  loadedLessonRecordMode = queryMode;
  renderDataOptions(lessonRecords);
}

function lessonRecordQueryMode(filters = {}) {
  return filters.status === "voided" ? "voided" : "active";
}

function emptyCrossMonthMakeupReferences() {
  return {
    actualsBySourcePlannedId: new Map(),
    sourcePlannedById: new Map(),
  };
}

function buildCrossMonthMakeupReferenceMaps(references = {}) {
  const maps = emptyCrossMonthMakeupReferences();
  for (const actual of references.sourceMonthActuals || []) {
    if (!actual.planned_lesson_id) {
      continue;
    }
    const actuals = maps.actualsBySourcePlannedId.get(actual.planned_lesson_id) || [];
    actuals.push(actual);
    maps.actualsBySourcePlannedId.set(actual.planned_lesson_id, actuals);
  }
  for (const planned of references.targetMonthSources || []) {
    maps.sourcePlannedById.set(planned.id, planned);
  }
  return maps;
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
    view: activeView,
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
  dom.studentSelect.value = filters.studentId || "";
  dom.teacherSelect.value = filters.teacherId || "";
  dom.subjectSelect.value = filters.subjectId || "";
  dom.businessEntitySelect.value = filters.businessEntityId || "";
  dom.lessonTypeSelect.value = filters.lessonType || "";
  dom.statusSelect.value = filters.status || "";
  dom.billableSelect.value = filters.isBillable || "";
  dom.keywordInput.value = filters.keyword || "";
  activeView = normalizeLessonView(filters.view || activeView);
  syncViewVisibility();
}

function renderMasterOptions() {
  renderEntityOptions(dom.studentSelect, students, studentName);
  renderEntityOptions(dom.teacherSelect, teachers, teacherName);
  renderEntityOptions(dom.subjectSelect, subjects, subjectName);
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
}

function renderDataOptions(records) {
  renderValueOptions(dom.lessonTypeSelect, distinctValues(records, "lesson_type"), lessonTypeLabel);
  renderLessonStatusFilterOptions(dom.statusSelect);
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

function activeLessonCreateDialog() {
  if (isDialogOpen(dom.createPlannedLessonDialog)) {
    return { blockDirectDismiss: blockCreatePlannedLessonDirectDismiss };
  }
  if (isDialogOpen(dom.createActualLessonDialog)) {
    return { blockDirectDismiss: blockCreateActualLessonDirectDismiss };
  }
  if (isDialogOpen(dom.createCancelledActualLessonDialog)) {
    return { blockDirectDismiss: blockCreateCancelledActualLessonDirectDismiss };
  }
  if (isDialogOpen(dom.createMakeupActualLessonDialog)) {
    return { blockDirectDismiss: blockCreateMakeupActualLessonDirectDismiss };
  }
  if (isDialogOpen(dom.createCrossMonthMakeupActualDialog)) {
    return { blockDirectDismiss: blockCreateCrossMonthMakeupActualDirectDismiss };
  }
  return null;
}

function isDialogOpen(dialog) {
  return Boolean(dialog && !dialog.classList.contains("is-hidden"));
}

function blockCreatePlannedLessonDirectDismiss() {
  if (!isDialogOpen(dom.createPlannedLessonDialog) || isCreatePlannedLessonSubmitting) {
    return;
  }
  showCreatePlannedLessonError("请使用取消按钮关闭窗口；表单已有修改时需要二次确认。");
}

function blockCreateActualLessonDirectDismiss() {
  if (!isDialogOpen(dom.createActualLessonDialog) || isCreateActualLessonSubmitting) {
    return;
  }
  showCreateActualLessonError("请使用取消按钮关闭窗口；表单已有修改时需要二次确认。");
}

function blockCreateCancelledActualLessonDirectDismiss() {
  if (!isDialogOpen(dom.createCancelledActualLessonDialog) || isCreateCancelledActualLessonSubmitting) {
    return;
  }
  showCreateCancelledActualLessonError("请使用取消按钮关闭窗口；表单已有修改时需要二次确认。");
}

function blockCreateMakeupActualLessonDirectDismiss() {
  if (!isDialogOpen(dom.createMakeupActualLessonDialog) || isCreateMakeupActualLessonSubmitting) {
    return;
  }
  showCreateMakeupActualLessonError("请使用取消按钮关闭窗口；表单已有修改时需要二次确认。");
}

function blockCreateCrossMonthMakeupActualDirectDismiss() {
  if (!isDialogOpen(dom.createCrossMonthMakeupActualDialog) || isCreateCrossMonthMakeupActualSubmitting) {
    return;
  }
  showCreateCrossMonthMakeupActualError("请使用取消按钮关闭窗口；表单已有修改时需要二次确认。");
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

  if (!force && hasCreatePlannedLessonFormChanged()) {
    if (!isCreatePlannedLessonCloseConfirmPending) {
      isCreatePlannedLessonCloseConfirmPending = true;
      showCreatePlannedLessonError("表单已有修改。再次点击取消将放弃输入。");
      return;
    }
  }

  dom.createPlannedLessonDialog.classList.add("is-hidden");
  dom.createPlannedLessonDialog.setAttribute("aria-hidden", "true");
  createPlannedLessonInitialSnapshot = null;
  isCreatePlannedLessonCloseConfirmPending = false;
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
  isCreatePlannedLessonCloseConfirmPending = false;
  createPlannedLessonInitialSnapshot = readCreatePlannedLessonFormSnapshot();
}

function readCreatePlannedLessonFormSnapshot() {
  return JSON.stringify({
    lessonDate: dom.createPlannedLessonDateInput.value,
    status: dom.createPlannedLessonStatusSelect.value,
    student: dom.createPlannedLessonStudentSelect.value,
    teacher: dom.createPlannedLessonTeacherSelect.value,
    subject: dom.createPlannedLessonSubjectSelect.value,
    businessEntity: dom.createPlannedLessonBusinessEntitySelect.value,
    startTime: dom.createPlannedLessonStartTimeInput.value,
    endTime: dom.createPlannedLessonEndTimeInput.value,
    durationHours: dom.createPlannedLessonDurationInput.value,
    unitPrice: dom.createPlannedLessonUnitPriceInput.value,
    lessonFee: dom.createPlannedLessonFeeInput.value,
    lessonCount: dom.createPlannedLessonCountInput.value,
    lessonContent: dom.createPlannedLessonContentInput.value,
    note: dom.createPlannedLessonNoteInput.value,
  });
}

function hasCreatePlannedLessonFormChanged() {
  return Boolean(createPlannedLessonInitialSnapshot && readCreatePlannedLessonFormSnapshot() !== createPlannedLessonInitialSnapshot);
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
  const timeValidation = validateLessonTimeRange(startTime, endTime);
  let validationMessage = "";
  if (timeValidation.status === "error") {
    invalidFields.push("startTime", "endTime", "durationHours");
    validationMessage = timeValidation.message;
  } else if (
    timeValidation.status === "valid"
    && (!Number.isFinite(durationHours) || !numbersEqual(durationHours, timeValidation.durationHours))
  ) {
    invalidFields.push("durationHours");
    validationMessage = `时长必须按开始/结束时间自动计算为 ${displayInputNumber(timeValidation.durationHours)}。`;
  }
  if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (lessonFee !== null && (!Number.isFinite(lessonFee) || lessonFee < 0)) invalidFields.push("lessonFee");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreatePlannedLessonError(validationMessage || "请检查新增预定课时表单中的必填项和数字格式。", invalidFields);
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

  await loadLessonMonth(createdMonth || currentYearMonth(), { status: "" });
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

  if (isVoidedPlanned(plannedLesson)) {
    showMessage("error", "该预定课时已作废，不能生成 actual。");
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

  if (!force && hasCreateActualLessonFormChanged()) {
    if (!isCreateActualLessonCloseConfirmPending) {
      isCreateActualLessonCloseConfirmPending = true;
      showCreateActualLessonError("表单已有修改。再次点击取消将放弃输入。");
      return;
    }
  }

  dom.createActualLessonDialog.classList.add("is-hidden");
  dom.createActualLessonDialog.setAttribute("aria-hidden", "true");
  currentActualSourceLesson = null;
  createActualLessonInitialSnapshot = null;
  isCreateActualLessonCloseConfirmPending = false;
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
  isCreateActualLessonCloseConfirmPending = false;
  createActualLessonInitialSnapshot = readCreateActualLessonFormSnapshot();
}

function readCreateActualLessonFormSnapshot() {
  return JSON.stringify({
    lessonDate: dom.createActualLessonDateInput.value,
    startTime: dom.createActualLessonStartTimeInput.value,
    endTime: dom.createActualLessonEndTimeInput.value,
    durationHours: dom.createActualLessonDurationInput.value,
    unitPrice: dom.createActualLessonUnitPriceInput.value,
    lessonFee: dom.createActualLessonFeeInput.value,
    lessonCount: dom.createActualLessonCountInput.value,
    lessonContent: dom.createActualLessonContentInput.value,
    note: dom.createActualLessonNoteInput.value,
  });
}

function hasCreateActualLessonFormChanged() {
  return Boolean(createActualLessonInitialSnapshot && readCreateActualLessonFormSnapshot() !== createActualLessonInitialSnapshot);
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
  const timeValidation = validateLessonTimeRange(startTime, endTime);
  let validationMessage = "";
  if (timeValidation.status === "error") {
    invalidFields.push("startTime", "endTime", "durationHours");
    validationMessage = timeValidation.message;
  } else if (
    timeValidation.status === "valid"
    && (!Number.isFinite(durationHours) || !numbersEqual(durationHours, timeValidation.durationHours))
  ) {
    invalidFields.push("durationHours");
    validationMessage = `时长必须按开始/结束时间自动计算为 ${displayInputNumber(timeValidation.durationHours)}。`;
  }
  if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (lessonFee !== null && (!Number.isFinite(lessonFee) || lessonFee < 0)) invalidFields.push("lessonFee");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreateActualLessonError(validationMessage || "请检查实际课时表单中的必填项和数字格式。", invalidFields);
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

  await loadLessonMonth(createdMonth, { status: "" });
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

async function refreshAfterVoidLesson(result, sourceLesson) {
  const targetMonth = result?.year_month || sourceLesson?.year_month || loadedMonth || currentYearMonth();
  if (targetMonth) {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, targetMonth);
  }

  const filters = readFilters() || { status: "" };
  await loadLessonMonth(targetMonth, filters);
  applyCurrentFilters();
  showMessage("success", `预定课时已误录作废：${shortId(result?.lesson_id || result?.id || sourceLesson?.id)}`);
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

  if (isVoidedPlanned(plannedLesson)) {
    showMessage("error", "该预定课时已作废，不能生成 cancelled actual。");
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

  if (!force && hasCreateCancelledActualLessonFormChanged()) {
    if (!isCreateCancelledActualLessonCloseConfirmPending) {
      isCreateCancelledActualLessonCloseConfirmPending = true;
      showCreateCancelledActualLessonError("表单已有修改。再次点击取消将放弃输入。");
      return;
    }
  }

  dom.createCancelledActualLessonDialog.classList.add("is-hidden");
  dom.createCancelledActualLessonDialog.setAttribute("aria-hidden", "true");
  currentCancelledActualSourceLesson = null;
  createCancelledActualLessonInitialSnapshot = null;
  isCreateCancelledActualLessonCloseConfirmPending = false;
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
  isCreateCancelledActualLessonCloseConfirmPending = false;
  createCancelledActualLessonInitialSnapshot = readCreateCancelledActualLessonFormSnapshot();
}

function readCreateCancelledActualLessonFormSnapshot() {
  return JSON.stringify({
    lessonDate: dom.createCancelledActualLessonDateInput.value,
    startTime: dom.createCancelledActualLessonStartTimeInput.value,
    endTime: dom.createCancelledActualLessonEndTimeInput.value,
    durationHours: dom.createCancelledActualLessonDurationInput.value,
    unitPrice: dom.createCancelledActualLessonUnitPriceInput.value,
    lessonCount: dom.createCancelledActualLessonCountInput.value,
    lessonContent: dom.createCancelledActualLessonContentInput.value,
    note: dom.createCancelledActualLessonNoteInput.value,
  });
}

function hasCreateCancelledActualLessonFormChanged() {
  return Boolean(
    createCancelledActualLessonInitialSnapshot
    && readCreateCancelledActualLessonFormSnapshot() !== createCancelledActualLessonInitialSnapshot
  );
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
  const timeValidation = validateLessonTimeRange(startTime, endTime);
  let validationMessage = "";
  if (timeValidation.status === "error") {
    invalidFields.push("startTime", "endTime", "durationHours");
    validationMessage = timeValidation.message;
  } else if (
    timeValidation.status === "valid"
    && (!Number.isFinite(durationHours) || !numbersEqual(durationHours, timeValidation.durationHours))
  ) {
    invalidFields.push("durationHours");
    validationMessage = `时长必须按开始/结束时间自动计算为 ${displayInputNumber(timeValidation.durationHours)}。`;
  }
  if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreateCancelledActualLessonError(validationMessage || "请检查取消课时表单中的必填项和数字格式。", invalidFields);
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

  await loadLessonMonth(createdMonth, { status: "" });
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

  if (isVoidedPlanned(plannedLesson)) {
    showMessage("error", "该预定课时已作废，不能生成 makeup_completed actual。");
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

  if (!force && hasCreateMakeupActualLessonFormChanged()) {
    if (!isCreateMakeupActualLessonCloseConfirmPending) {
      isCreateMakeupActualLessonCloseConfirmPending = true;
      showCreateMakeupActualLessonError("表单已有修改。再次点击取消将放弃输入。");
      return;
    }
  }

  dom.createMakeupActualLessonDialog.classList.add("is-hidden");
  dom.createMakeupActualLessonDialog.setAttribute("aria-hidden", "true");
  currentMakeupActualSourceLesson = null;
  createMakeupActualLessonInitialSnapshot = null;
  isCreateMakeupActualLessonCloseConfirmPending = false;
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
  isCreateMakeupActualLessonCloseConfirmPending = false;
  createMakeupActualLessonInitialSnapshot = readCreateMakeupActualLessonFormSnapshot();
}

function readCreateMakeupActualLessonFormSnapshot() {
  return JSON.stringify({
    lessonDate: dom.createMakeupActualLessonDateInput.value,
    isBillable: dom.createMakeupActualLessonBillableSelect.value,
    startTime: dom.createMakeupActualLessonStartTimeInput.value,
    endTime: dom.createMakeupActualLessonEndTimeInput.value,
    durationHours: dom.createMakeupActualLessonDurationInput.value,
    unitPrice: dom.createMakeupActualLessonUnitPriceInput.value,
    lessonFee: dom.createMakeupActualLessonFeeInput.value,
    lessonCount: dom.createMakeupActualLessonCountInput.value,
    lessonContent: dom.createMakeupActualLessonContentInput.value,
    note: dom.createMakeupActualLessonNoteInput.value,
  });
}

function hasCreateMakeupActualLessonFormChanged() {
  return Boolean(
    createMakeupActualLessonInitialSnapshot
    && readCreateMakeupActualLessonFormSnapshot() !== createMakeupActualLessonInitialSnapshot
  );
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
  const timeValidation = validateLessonTimeRange(startTime, endTime);
  let validationMessage = "";
  if (timeValidation.status === "error") {
    invalidFields.push("startTime", "endTime", "durationHours");
    validationMessage = timeValidation.message;
  } else if (
    timeValidation.status === "valid"
    && (!Number.isFinite(durationHours) || !numbersEqual(durationHours, timeValidation.durationHours))
  ) {
    invalidFields.push("durationHours");
    validationMessage = `时长必须按开始/结束时间自动计算为 ${displayInputNumber(timeValidation.durationHours)}。`;
  }
  if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (isBillable && lessonFee !== null && (!Number.isFinite(lessonFee) || lessonFee < 0)) invalidFields.push("lessonFee");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreateMakeupActualLessonError(validationMessage || "请检查补课完成表单中的必填项和数字格式。", invalidFields);
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

  await loadLessonMonth(createdMonth, { status: "" });
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

function openCreateCrossMonthMakeupActualDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能登记跨月补课完成。");
    return;
  }

  const targetMonth = loadedMonth || getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!targetMonth) {
    showMessage("error", "请先选择补课完成月份。");
    return;
  }

  currentCrossMonthMakeupSourceLesson = null;
  crossMonthMakeupSourceLessons = [];
  resetCreateCrossMonthMakeupActualForm(targetMonth);
  clearCreateCrossMonthMakeupActualErrors();
  renderCrossMonthMakeupSourceOptions();
  renderCreateCrossMonthMakeupActualSummary();
  setCreateCrossMonthMakeupActualSubmitting(false);
  dom.createCrossMonthMakeupActualDialog.classList.remove("is-hidden");
  dom.createCrossMonthMakeupActualDialog.setAttribute("aria-hidden", "false");
  dom.crossMonthMakeupSourceRefreshButton.focus();
  loadCrossMonthMakeupSourceCandidates();
}

function closeCreateCrossMonthMakeupActualDialog(force = false) {
  if (isCreateCrossMonthMakeupActualSubmitting && !force) {
    return;
  }

  if (!force && hasCreateCrossMonthMakeupActualFormChanged()) {
    if (!isCreateCrossMonthMakeupActualCloseConfirmPending) {
      isCreateCrossMonthMakeupActualCloseConfirmPending = true;
      showCreateCrossMonthMakeupActualError("表单已有修改。再次点击取消将放弃输入。");
      return;
    }
  }

  dom.createCrossMonthMakeupActualDialog.classList.add("is-hidden");
  dom.createCrossMonthMakeupActualDialog.setAttribute("aria-hidden", "true");
  currentCrossMonthMakeupSourceLesson = null;
  crossMonthMakeupSourceLessons = [];
  createCrossMonthMakeupActualInitialSnapshot = null;
  isCreateCrossMonthMakeupActualCloseConfirmPending = false;
}

function resetCreateCrossMonthMakeupActualForm(targetMonth) {
  const previousMonth = addMonthsToYearMonth(targetMonth, -1) || targetMonth;
  const defaultFromMonth = addMonthsToYearMonth(targetMonth, -3) || previousMonth;
  setYearMonthSelectValue(dom.crossMonthMakeupSourceFromYearSelect, dom.crossMonthMakeupSourceFromMonthSelect, defaultFromMonth);
  setYearMonthSelectValue(dom.crossMonthMakeupSourceToYearSelect, dom.crossMonthMakeupSourceToMonthSelect, previousMonth);
  dom.crossMonthMakeupSourceSelect.value = "";
  dom.createCrossMonthMakeupActualDateInput.value = firstDateOfMonth(targetMonth);
  dom.createCrossMonthMakeupActualStartTimeInput.value = "";
  dom.createCrossMonthMakeupActualEndTimeInput.value = "";
  dom.createCrossMonthMakeupActualDurationInput.value = "";
  dom.createCrossMonthMakeupActualUnitPriceInput.value = "0";
  dom.createCrossMonthMakeupActualFeeInput.value = "0";
  dom.createCrossMonthMakeupActualCountInput.value = "";
  dom.createCrossMonthMakeupActualContentInput.value = "";
  dom.createCrossMonthMakeupActualNoteInput.value = "";
  dom.createCrossMonthMakeupActualFeeInput.readOnly = true;
  isCreateCrossMonthMakeupActualCloseConfirmPending = false;
  createCrossMonthMakeupActualInitialSnapshot = readCreateCrossMonthMakeupActualFormSnapshot();
}

async function loadCrossMonthMakeupSourceCandidates() {
  if (isCrossMonthMakeupSourceLoading) {
    return;
  }

  clearCreateCrossMonthMakeupActualErrors();
  const targetMonth = loadedMonth || getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  const fromMonth = getYearMonthSelectValue(dom.crossMonthMakeupSourceFromYearSelect, dom.crossMonthMakeupSourceFromMonthSelect);
  const toMonth = getYearMonthSelectValue(dom.crossMonthMakeupSourceToYearSelect, dom.crossMonthMakeupSourceToMonthSelect);
  const invalidFields = [];
  if (!fromMonth) invalidFields.push("sourceMonthFrom");
  if (!toMonth) invalidFields.push("sourceMonthTo");
  if (fromMonth && toMonth && fromMonth > toMonth) invalidFields.push("sourceMonthFrom", "sourceMonthTo");
  if (toMonth && targetMonth && toMonth >= targetMonth) invalidFields.push("sourceMonthTo");

  if (invalidFields.length) {
    crossMonthMakeupSourceLessons = [];
    currentCrossMonthMakeupSourceLesson = null;
    renderCrossMonthMakeupSourceOptions();
    renderCreateCrossMonthMakeupActualSummary();
    showCreateCrossMonthMakeupActualError("原月份范围必须早于当前补课月份。", invalidFields);
    return;
  }

  isCrossMonthMakeupSourceLoading = true;
  dom.crossMonthMakeupSourceRefreshButton.disabled = true;
  dom.crossMonthMakeupSourceSelect.disabled = true;
  dom.crossMonthMakeupSourceCount.textContent = "正在读取来源...";

  try {
    crossMonthMakeupSourceLessons = sortLessonRecords(await fetchCrossMonthMakeupSourceLessons({
      fromMonth,
      toMonth,
      targetMonth,
    }));
    currentCrossMonthMakeupSourceLesson = null;
    renderCrossMonthMakeupSourceOptions();
    renderCreateCrossMonthMakeupActualSummary();
    createCrossMonthMakeupActualInitialSnapshot = readCreateCrossMonthMakeupActualFormSnapshot();
  } catch (error) {
    crossMonthMakeupSourceLessons = [];
    currentCrossMonthMakeupSourceLesson = null;
    renderCrossMonthMakeupSourceOptions();
    renderCreateCrossMonthMakeupActualSummary();
    showCreateCrossMonthMakeupActualError(`读取跨月补课来源失败：${error.message || error}`);
  } finally {
    isCrossMonthMakeupSourceLoading = false;
    dom.crossMonthMakeupSourceRefreshButton.disabled = false;
    dom.crossMonthMakeupSourceSelect.disabled = false;
    setCreateCrossMonthMakeupActualSubmitting(false);
  }
}

function renderCrossMonthMakeupSourceOptions() {
  const options = ['<option value="">请选择原月份待补课 planned</option>'];
  for (const lesson of crossMonthMakeupSourceLessons) {
    const label = [
      lesson.year_month,
      formatDateOnly(lesson.lesson_date),
      formatTimeRange(lesson.start_time, lesson.end_time),
      nameById(students, lesson.student_id, studentName),
      nameById(teachers, lesson.teacher_id, teacherName),
      nameById(subjects, lesson.subject_id, subjectName),
      shortId(lesson.id),
    ].filter((value) => safeText(value) && value !== "-").join(" / ");
    options.push(`<option value="${escapeAttribute(lesson.id)}">${escapeHtml(label)}</option>`);
  }
  dom.crossMonthMakeupSourceSelect.innerHTML = options.join("");
  dom.crossMonthMakeupSourceCount.textContent = `${crossMonthMakeupSourceLessons.length} 条可选来源`;
}

function handleCrossMonthMakeupSourceSelectionChange() {
  const sourceId = dom.crossMonthMakeupSourceSelect.value;
  currentCrossMonthMakeupSourceLesson = crossMonthMakeupSourceLessons.find((lesson) => lesson.id === sourceId) || null;
  if (currentCrossMonthMakeupSourceLesson) {
    fillCreateCrossMonthMakeupActualFromSource(currentCrossMonthMakeupSourceLesson);
  }
  renderCreateCrossMonthMakeupActualSummary();
  setCreateCrossMonthMakeupActualSubmitting(false);
  clearCreateCrossMonthMakeupActualFieldInvalid("sourceLesson");
  hideCreateCrossMonthMakeupActualErrorIfClean();
  createCrossMonthMakeupActualInitialSnapshot = readCreateCrossMonthMakeupActualFormSnapshot();
}

function fillCreateCrossMonthMakeupActualFromSource(sourceLesson) {
  dom.createCrossMonthMakeupActualStartTimeInput.value = formatInputTime(sourceLesson.start_time);
  dom.createCrossMonthMakeupActualEndTimeInput.value = formatInputTime(sourceLesson.end_time);
  dom.createCrossMonthMakeupActualDurationInput.value = displayInputNumber(sourceLesson.duration_hours);
  dom.createCrossMonthMakeupActualUnitPriceInput.value = displayInputNumber(sourceLesson.unit_price || 0);
  dom.createCrossMonthMakeupActualFeeInput.value = "0";
  dom.createCrossMonthMakeupActualCountInput.value = sourceLesson.lesson_count ? String(sourceLesson.lesson_count) : "";
  dom.createCrossMonthMakeupActualContentInput.value = safeText(sourceLesson.lesson_content);
  dom.createCrossMonthMakeupActualNoteInput.value = safeText(sourceLesson.note);
}

function renderCreateCrossMonthMakeupActualSummary() {
  const targetMonth = loadedMonth || getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  dom.createCrossMonthMakeupActualSummary.innerHTML = [
    ["补课月份", formatMonth(targetMonth)],
    ["写入结果", "只在当前月份生成一条补课完成 actual"],
    ["计费", "默认不计费；课时费固定 0"],
    ["planned", "不会复制 planned"],
    ["来源 planned", "不会修改来源 planned"],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");

  const source = currentCrossMonthMakeupSourceLesson;
  dom.createCrossMonthMakeupActualSourceSummary.innerHTML = source ? [
    ["来源月份", formatMonth(source.year_month)],
    ["来源日期", formatDateOnly(source.lesson_date)],
    ["学生", nameById(students, source.student_id, studentName)],
    ["老师", nameById(teachers, source.teacher_id, teacherName)],
    ["科目", nameById(subjects, source.subject_id, subjectName)],
    ["业务归属", nameById(businessEntities, source.business_entity_id, businessEntityName)],
    ["planned id", shortId(source.id)],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("") : '<div class="state-text">请选择一个原月份待补课 planned。</div>';
}

async function handleCreateCrossMonthMakeupActualSubmit() {
  if (isCreateCrossMonthMakeupActualSubmitting) {
    return;
  }

  clearCreateCrossMonthMakeupActualErrors();
  const payload = readCreateCrossMonthMakeupActualPayload();
  if (!payload) {
    return;
  }

  setCreateCrossMonthMakeupActualSubmitting(true);

  try {
    const createdLesson = await createCrossMonthMakeupCompletedActualFromPlanned(payload);
    closeCreateCrossMonthMakeupActualDialog(true);
    await refreshAfterCreateCrossMonthMakeupActual(createdLesson);
    showMessage("success", `跨月补课完成已登记：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    const message = error.message || String(error);
    showCreateCrossMonthMakeupActualError(message, createCrossMonthMakeupActualFieldIdsForError(message));
  } finally {
    setCreateCrossMonthMakeupActualSubmitting(false);
  }
}

function readCreateCrossMonthMakeupActualPayload() {
  const source = currentCrossMonthMakeupSourceLesson;
  const targetMonth = loadedMonth || getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  const lessonDate = dom.createCrossMonthMakeupActualDateInput.value;
  const lessonMonth = safeText(lessonDate).slice(0, 7);
  const startTime = dom.createCrossMonthMakeupActualStartTimeInput.value;
  const endTime = dom.createCrossMonthMakeupActualEndTimeInput.value;
  const durationHours = numberFromInput(dom.createCrossMonthMakeupActualDurationInput.value);
  const unitPrice = numberFromInput(dom.createCrossMonthMakeupActualUnitPriceInput.value);
  const lessonCount = nullableIntegerFromInput(dom.createCrossMonthMakeupActualCountInput.value);
  const invalidFields = [];

  if (!source) invalidFields.push("sourceLesson");
  if (!lessonDate || Number.isNaN(new Date(`${lessonDate}T00:00:00`).getTime())) invalidFields.push("lessonDate");
  if (lessonMonth !== targetMonth) invalidFields.push("lessonDate");
  if (source?.year_month && targetMonth && source.year_month >= targetMonth) invalidFields.push("sourceLesson");
  if (startTime && !isTimeValue(startTime)) invalidFields.push("startTime");
  if (endTime && !isTimeValue(endTime)) invalidFields.push("endTime");
  const timeValidation = validateLessonTimeRange(startTime, endTime);
  let validationMessage = "";
  if (timeValidation.status === "error") {
    invalidFields.push("startTime", "endTime", "durationHours");
    validationMessage = timeValidation.message;
  } else if (
    timeValidation.status === "valid"
    && (!Number.isFinite(durationHours) || !numbersEqual(durationHours, timeValidation.durationHours))
  ) {
    invalidFields.push("durationHours");
    validationMessage = `时长必须按开始/结束时间自动计算为 ${displayInputNumber(timeValidation.durationHours)}。`;
  }
  if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreateCrossMonthMakeupActualError(validationMessage || "请检查跨月补课完成表单；补课完成日期必须在当前页面月份，来源必须早于当前月份。", invalidFields);
    return null;
  }

  return {
    plannedLessonId: source.id,
    lessonDate,
    startTime,
    endTime,
    durationHours,
    unitPrice,
    lessonCount,
    lessonContent: dom.createCrossMonthMakeupActualContentInput.value.trim(),
    note: dom.createCrossMonthMakeupActualNoteInput.value.trim(),
  };
}

async function refreshAfterCreateCrossMonthMakeupActual(createdLesson) {
  const createdMonth = createdLesson.year_month || loadedMonth || currentYearMonth();
  if (createdMonth) {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, createdMonth);
  }

  await loadLessonMonth(createdMonth, { status: "" });
  renderDataOptions(lessonRecords);
  restoreFilterSelections({
    month: createdMonth,
    studentId: createdLesson.student_id || currentCrossMonthMakeupSourceLesson?.student_id || "",
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

function setCreateCrossMonthMakeupActualSubmitting(isSubmitting) {
  isCreateCrossMonthMakeupActualSubmitting = isSubmitting;
  dom.createCrossMonthMakeupActualSubmitButton.disabled = (
    isSubmitting
    || isCrossMonthMakeupSourceLoading
    || !currentCrossMonthMakeupSourceLesson
  );
  dom.createCrossMonthMakeupActualCancelButton.disabled = isSubmitting;
  dom.crossMonthMakeupSourceRefreshButton.disabled = isSubmitting || isCrossMonthMakeupSourceLoading;
  dom.crossMonthMakeupSourceSelect.disabled = isSubmitting || isCrossMonthMakeupSourceLoading;
  dom.openCreatePlannedLessonButton.disabled = isSubmitting;
  dom.openCrossMonthMakeupDialogButton.disabled = isSubmitting;
  dom.createCrossMonthMakeupActualSubmitButton.textContent = isSubmitting ? "登记中..." : "登记跨月补课完成";
}

function readCreateCrossMonthMakeupActualFormSnapshot() {
  return JSON.stringify({
    sourceMonthFrom: getYearMonthSelectValue(dom.crossMonthMakeupSourceFromYearSelect, dom.crossMonthMakeupSourceFromMonthSelect),
    sourceMonthTo: getYearMonthSelectValue(dom.crossMonthMakeupSourceToYearSelect, dom.crossMonthMakeupSourceToMonthSelect),
    sourceLesson: dom.crossMonthMakeupSourceSelect.value,
    lessonDate: dom.createCrossMonthMakeupActualDateInput.value,
    startTime: dom.createCrossMonthMakeupActualStartTimeInput.value,
    endTime: dom.createCrossMonthMakeupActualEndTimeInput.value,
    durationHours: dom.createCrossMonthMakeupActualDurationInput.value,
    unitPrice: dom.createCrossMonthMakeupActualUnitPriceInput.value,
    lessonCount: dom.createCrossMonthMakeupActualCountInput.value,
    lessonContent: dom.createCrossMonthMakeupActualContentInput.value,
    note: dom.createCrossMonthMakeupActualNoteInput.value,
  });
}

function hasCreateCrossMonthMakeupActualFormChanged() {
  return Boolean(
    createCrossMonthMakeupActualInitialSnapshot
    && readCreateCrossMonthMakeupActualFormSnapshot() !== createCrossMonthMakeupActualInitialSnapshot
  );
}

function clearCreateCrossMonthMakeupActualErrors() {
  dom.createCrossMonthMakeupActualError.textContent = "";
  dom.createCrossMonthMakeupActualError.classList.add("is-hidden");
  for (const fieldId of CREATE_CROSS_MONTH_MAKEUP_ACTUAL_FIELD_IDS) {
    clearCreateCrossMonthMakeupActualFieldInvalid(fieldId);
  }
}

function showCreateCrossMonthMakeupActualError(message, fieldIds = []) {
  dom.createCrossMonthMakeupActualError.textContent = message;
  dom.createCrossMonthMakeupActualError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCreateCrossMonthMakeupActualFieldInvalid(fieldId, true);
  }
  dom.createCrossMonthMakeupActualDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function createCrossMonthMakeupActualFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("来源") || text.includes("planned") || text.includes("关联 actual")) fields.push("sourceLesson");
  if (text.includes("日期") || text.includes("月份") || text.includes("学生月度结算") || text.includes("老师工资")) fields.push("lessonDate");
  if (text.includes("开始时间")) fields.push("startTime");
  if (text.includes("结束时间")) fields.push("endTime");
  if (text.includes("时长")) fields.push("durationHours");
  if (text.includes("单价")) fields.push("unitPrice");
  if (text.includes("回数")) fields.push("lessonCount");
  return fields;
}

function setCreateCrossMonthMakeupActualFieldInvalid(fieldId, invalid) {
  const field = dom.createCrossMonthMakeupActualDialog.querySelector(`[data-create-cross-month-makeup-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearCreateCrossMonthMakeupActualFieldInvalid(fieldId) {
  setCreateCrossMonthMakeupActualFieldInvalid(fieldId, false);
}

function hideCreateCrossMonthMakeupActualErrorIfClean() {
  const hasInvalidField = Boolean(dom.createCrossMonthMakeupActualDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.createCrossMonthMakeupActualError.textContent = "";
    dom.createCrossMonthMakeupActualError.classList.add("is-hidden");
  }
}

function syncCreateCrossMonthMakeupActualDurationFromTimeRange() {
  const result = validateLessonTimeRange(
    dom.createCrossMonthMakeupActualStartTimeInput.value,
    dom.createCrossMonthMakeupActualEndTimeInput.value
  );
  if (result.status === "incomplete") {
    return;
  }
  if (result.status === "error") {
    showCreateCrossMonthMakeupActualError(result.message, ["startTime", "endTime", "durationHours"]);
    return;
  }

  dom.createCrossMonthMakeupActualDurationInput.value = displayInputNumber(result.durationHours);
  clearCreateCrossMonthMakeupActualFieldInvalid("startTime");
  clearCreateCrossMonthMakeupActualFieldInvalid("endTime");
  clearCreateCrossMonthMakeupActualFieldInvalid("durationHours");
  hideCreateCrossMonthMakeupActualErrorIfClean();
}

function syncCreatePlannedLessonDurationFromTimeRange() {
  const result = validateLessonTimeRange(
    dom.createPlannedLessonStartTimeInput.value,
    dom.createPlannedLessonEndTimeInput.value
  );
  if (result.status === "incomplete") {
    return;
  }
  if (result.status === "error") {
    showCreatePlannedLessonError(result.message, ["startTime", "endTime", "durationHours"]);
    return;
  }

  dom.createPlannedLessonDurationInput.value = displayInputNumber(result.durationHours);
  clearCreatePlannedLessonFieldInvalid("startTime");
  clearCreatePlannedLessonFieldInvalid("endTime");
  clearCreatePlannedLessonFieldInvalid("durationHours");
  hideCreatePlannedLessonErrorIfClean();
  updateCreatePlannedLessonFeePreview();
}

function syncCreateActualLessonDurationFromTimeRange() {
  const result = validateLessonTimeRange(
    dom.createActualLessonStartTimeInput.value,
    dom.createActualLessonEndTimeInput.value
  );
  if (result.status === "incomplete") {
    return;
  }
  if (result.status === "error") {
    showCreateActualLessonError(result.message, ["startTime", "endTime", "durationHours"]);
    return;
  }

  dom.createActualLessonDurationInput.value = displayInputNumber(result.durationHours);
  clearCreateActualLessonFieldInvalid("startTime");
  clearCreateActualLessonFieldInvalid("endTime");
  clearCreateActualLessonFieldInvalid("durationHours");
  hideCreateActualLessonErrorIfClean();
  updateCreateActualLessonFeePreview();
}

function syncCreateCancelledActualLessonDurationFromTimeRange() {
  const result = validateLessonTimeRange(
    dom.createCancelledActualLessonStartTimeInput.value,
    dom.createCancelledActualLessonEndTimeInput.value
  );
  if (result.status === "incomplete") {
    return;
  }
  if (result.status === "error") {
    showCreateCancelledActualLessonError(result.message, ["startTime", "endTime", "durationHours"]);
    return;
  }

  dom.createCancelledActualLessonDurationInput.value = displayInputNumber(result.durationHours);
  clearCreateCancelledActualLessonFieldInvalid("startTime");
  clearCreateCancelledActualLessonFieldInvalid("endTime");
  clearCreateCancelledActualLessonFieldInvalid("durationHours");
  hideCreateCancelledActualLessonErrorIfClean();
}

function syncCreateMakeupActualLessonDurationFromTimeRange() {
  const result = validateLessonTimeRange(
    dom.createMakeupActualLessonStartTimeInput.value,
    dom.createMakeupActualLessonEndTimeInput.value
  );
  if (result.status === "incomplete") {
    return;
  }
  if (result.status === "error") {
    showCreateMakeupActualLessonError(result.message, ["startTime", "endTime", "durationHours"]);
    return;
  }

  dom.createMakeupActualLessonDurationInput.value = displayInputNumber(result.durationHours);
  clearCreateMakeupActualLessonFieldInvalid("startTime");
  clearCreateMakeupActualLessonFieldInvalid("endTime");
  clearCreateMakeupActualLessonFieldInvalid("durationHours");
  hideCreateMakeupActualLessonErrorIfClean();
  updateCreateMakeupActualLessonFeePreview();
}

async function refreshAfterEditLesson(updatedLesson) {
  const updatedMonth = updatedLesson.year_month || safeText(updatedLesson.lesson_date).slice(0, 7) || loadedMonth;
  if (updatedMonth) {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, updatedMonth);
  }

  const filters = readFilters() || {
    month: updatedMonth || loadedMonth,
    studentId: "",
    teacherId: "",
    subjectId: "",
    businessEntityId: "",
    lessonType: "",
    status: "",
    isBillable: "",
    keyword: "",
  };
  filters.month = updatedMonth || filters.month;

  await loadLessonMonth(filters.month, filters);
  renderDataOptions(lessonRecords);
  restoreFilterSelections(filters);
  applyCurrentFilters();
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

function renderLessonStatusFilterOptions(selectEl) {
  selectEl.innerHTML = LESSON_STATUS_FILTER_OPTIONS
    .map(([value, label]) => `<option value="${escapeAttribute(value)}">${escapeHtml(label)}</option>`)
    .join("");
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
  importPreviewFileMeta = null;
  lastLessonImportResult = null;
  if (dom.lessonImportPreviewFileInput) {
    dom.lessonImportPreviewFileInput.value = "";
  }
  hideLessonImportPreviewError();
  renderLessonImportPreview();
}

async function handleLessonImportPreviewFileChange(event) {
  const file = event.target.files?.[0];
  importPreviewRows = [];
  importPreviewFileMeta = null;
  lastLessonImportResult = null;
  hideLessonImportPreviewError();

  if (!file) {
    renderLessonImportPreview();
    return;
  }

  try {
    const rows = await parseLessonImportPreviewFile(file);
    importPreviewRows = buildLessonImportPreviewRows(rows);
    importPreviewFileMeta = {
      name: file.name,
      hash: await calculateLessonImportFileHash(file),
    };
    await addLessonImportPlannedIdPrecheck(importPreviewRows);
    if (!importPreviewRows.length) {
      showLessonImportPreviewError("没有读取到可预览的课时行。请确认文件包含表头和课时数据。");
    }
  } catch (error) {
    importPreviewRows = [];
    showLessonImportPreviewError(error.message || String(error));
  }

  renderLessonImportPreview();
}

async function handleLessonImportPlannedSubmit() {
  if (isLessonImportSubmitting) {
    return;
  }

  hideLessonImportPreviewError();

  if (lastLessonImportResult?.successCount > 0) {
    showLessonImportPreviewError("当前预览已成功导入，不能重复提交；如需导入其他课时，请先清空并重新选择文件。");
    return;
  }

  if (!importPreviewRows.length) {
    showLessonImportPreviewError("请先选择文件并生成预览。");
    return;
  }

  const actualRows = importPreviewRows.filter((row) => row.values.lessonType === "actual");
  if (actualRows.length) {
    for (const row of actualRows) {
      addLessonImportPreviewIssue(row, "error", "lessonType", "当前批量导入第一版仅支持预定课时。");
    }
    renderLessonImportPreview();
    showLessonImportPreviewError("当前批量导入第一版仅支持预定课时；请移除 actual 行后再提交。");
    return;
  }

  const invalidRows = importPreviewRows.filter((row) => row.errors.length);
  if (invalidRows.length) {
    showLessonImportPreviewError(`仍有 ${invalidRows.length} 行错误，请先修正后再导入预定课时。`);
    return;
  }

  if (!importPreviewFileMeta?.name || !importPreviewFileMeta?.hash) {
    showLessonImportPreviewError("缺少文件信息，请重新选择文件后再导入。");
    return;
  }

  if (successfulLessonImportFileHashes.has(importPreviewFileMeta.hash)) {
    showLessonImportPreviewError("该文件已在本页面成功导入过。为避免重复生成预定课时，本次提交已阻止；请重新选择未导入的文件。");
    return;
  }

  setLessonImportSubmitting(true);

  try {
    const results = await importPlannedLessonRecordsBatch({
      importBatchId: createLessonImportBatchId(),
      sourceFileName: importPreviewFileMeta.name,
      sourceFileHash: importPreviewFileMeta.hash,
      rows: buildLessonImportSubmitRows(importPreviewRows),
      note: "lesson planned-only batch import from lesson.html",
    });

    applyLessonImportSubmitResults(results);

    const failedRows = results.filter((row) => row.row_valid === false || row.batch_committed === false || (row.errors || []).length);
    if (failedRows.length) {
      renderLessonImportPreview();
      showLessonImportPreviewError(formatLessonImportFailedRowsMessage(failedRows));
      return;
    }

    lastLessonImportResult = buildLessonImportResultSummary(results, importPreviewRows);
    successfulLessonImportFileHashes.add(importPreviewFileMeta.hash);
    renderLessonImportPreview();

    if (loadedMonth) {
      await loadLessonMonth(loadedMonth, readFilters() || { status: "" });
      applyCurrentFilters();
    }
    const monthText = formatLessonImportMonthRange(lastLessonImportResult.months);
    showMessage("success", `已导入预定课时 ${lastLessonImportResult.successCount} 行${monthText ? `（${monthText}）` : ""}。`);
  } catch (error) {
    showLessonImportPreviewError(formatLessonImportSubmitError(error));
  } finally {
    setLessonImportSubmitting(false);
  }
}

async function handleLessonImportViewMonthClick() {
  const months = lastLessonImportResult?.months || [];
  if (months.length !== 1) {
    return;
  }

  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, months[0]);
  closeLessonImportPreviewDialog();
  await applyQuery();
}

function handleLessonImportViewFirstDetailClick() {
  const firstLessonId = lastLessonImportResult?.createdLessonIds?.[0] || "";
  if (!firstLessonId) {
    return;
  }

  window.location.href = createLessonDetailUrl(
    firstLessonId,
    lastLessonImportResult.months?.[0] || loadedMonth,
    activeView
  );
}

function buildLessonImportResultSummary(results, rows) {
  const successfulResults = (results || [])
    .filter((row) => row.batch_committed !== false && row.created_lesson_id);
  const successfulRowIndexes = new Set(successfulResults
    .map((row) => Number(row.row_index))
    .filter(Number.isFinite));
  const months = [...new Set(rows
    .map((row, index) => (successfulRowIndexes.has(index + 1) ? lessonImportYearMonth(row.values.lessonDate) : ""))
    .filter(Boolean))]
    .sort();
  const createdLessonIds = successfulResults
    .map((row) => row.created_lesson_id)
    .filter(Boolean);

  return {
    successCount: successfulRowIndexes.size,
    months,
    createdLessonIds,
  };
}

function formatLessonImportMonthRange(months) {
  if (!months?.length) {
    return "";
  }
  if (months.length === 1) {
    return months[0];
  }
  return `${months[0]} - ${months[months.length - 1]}`;
}

function createLessonDetailUrl(lessonId, returnMonth = loadedMonth, returnView = activeView) {
  const params = new URLSearchParams();
  params.set("id", lessonId);
  const monthText = safeText(returnMonth);
  const match = monthText.match(/^(\d{4})-(0[1-9]|1[0-2])$/);
  if (match) {
    params.set("returnYear", match[1]);
    params.set("returnMonth", match[2]);
  }
  if (returnView === "pair") {
    params.set("returnView", "pair");
  }
  const returnQuery = buildLessonReturnQuery(returnMonth, returnView);
  if (returnQuery) {
    params.set("returnQuery", returnQuery);
  }
  return `./lesson-detail.html?${params.toString()}`;
}

function buildLessonReturnQuery(returnMonth = loadedMonth, returnView = activeView) {
  const currentFilters = readFilters();
  const filters = {
    ...(currentFilters || defaultLessonFilters()),
    month: safeText(returnMonth) || currentFilters?.month || loadedMonth,
    view: normalizeLessonView(returnView || currentFilters?.view || activeView),
  };
  const query = buildLessonListQueryParams(filters).toString();
  return query || "";
}

function handleLessonImportTemplateExport() {
  hideLessonImportPreviewError();

  if (window.XLSX) {
    exportLessonImportTemplateXlsx();
    return;
  }

  exportLessonImportTemplateCsv();
  showLessonImportPreviewError("Excel 解析库尚未加载，已降级导出 CSV 预定课时模板。");
}

function exportLessonImportTemplateXlsx() {
  const workbook = window.XLSX.utils.book_new();
  const templateSheet = window.XLSX.utils.aoa_to_sheet([
    LESSON_IMPORT_TEMPLATE_HEADERS,
    ...LESSON_IMPORT_TEMPLATE_ROWS,
  ]);
  templateSheet["!cols"] = LESSON_IMPORT_TEMPLATE_HEADERS.map((header) => ({
    wch: Math.max(12, String(header).length + 8),
  }));

  const guideSheet = window.XLSX.utils.aoa_to_sheet(LESSON_IMPORT_TEMPLATE_GUIDE_ROWS);
  guideSheet["!cols"] = [{ wch: 18 }, { wch: 10 }, { wch: 72 }];

  window.XLSX.utils.book_append_sheet(workbook, templateSheet, "lesson_template");
  window.XLSX.utils.book_append_sheet(workbook, guideSheet, "说明");
  window.XLSX.writeFile(workbook, "lesson_planned_import_template_v2.xlsx");
}

function exportLessonImportTemplateCsv() {
  const csvRows = [
    LESSON_IMPORT_TEMPLATE_HEADERS,
    ...LESSON_IMPORT_TEMPLATE_ROWS,
  ];
  const csv = csvRows.map((row) => row.map(escapeCsvCell).join(",")).join("\r\n");
  downloadTextFile("lesson_planned_import_template_v2.csv", `\uFEFF${csv}`, "text/csv;charset=utf-8");
}

function escapeCsvCell(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function downloadTextFile(fileName, content, mimeType) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
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

  previewRows.forEach((row, index) => {
    row.previewRowNo = index + 1;
  });
  addLessonImportPreviewDuplicateIssues(previewRows);
  return previewRows;
}

function addLessonImportPreviewDuplicateIssues(rows) {
  const seenRows = new Map();

  for (const row of rows) {
    if (row.values.lessonType !== "planned") {
      continue;
    }

    const key = buildLessonImportPreviewDuplicateKey(row);
    if (!key) {
      continue;
    }

    const firstRow = seenRows.get(key);
    if (firstRow) {
      addLessonImportPreviewIssue(row, "error", "lessonType", `与第 ${firstRow.previewRowNo || firstRow.rowNo} 行重复；同一文件内重复预定课时不能提交。`);
      continue;
    }

    seenRows.set(key, row);
  }
}

function buildLessonImportPreviewDuplicateKey(row) {
  const values = row.values || {};
  const parts = [
    normalizeLessonImportDuplicateText(row.raw.student || values.student),
    normalizeLessonImportDuplicateText(row.raw.teacher || values.teacher),
    normalizeLessonImportDuplicateText(row.raw.subject || values.subject),
    normalizeLessonImportDuplicateText(row.raw.businessEntity || values.businessEntity),
    normalizeLessonImportDuplicateText(values.lessonDate),
    normalizeLessonImportDuplicateText(values.startTime),
    normalizeLessonImportDuplicateText(values.endTime),
    normalizeLessonImportDuplicateText(values.status),
    normalizeLessonImportDuplicateNumber(values.durationHours),
    normalizeLessonImportDuplicateNumber(values.lessonFee),
  ];

  return parts.some(Boolean) ? parts.join("|") : "";
}

async function addLessonImportPlannedIdPrecheck(rows) {
  const actualRows = rows.filter((row) => row.values.lessonType === "actual");
  if (!actualRows.length) {
    return;
  }

  for (const row of actualRows) {
    if (!row.values.plannedId) {
      addLessonImportPreviewIssue(
        row,
        "warning",
        "plannedId",
        "未填写关联预定ID；preview 阶段不会自动匹配 planned，batch import 前需决定是否允许按学生/老师/科目/日期/时间自动匹配。"
      );
    }
  }

  const rowsWithPlannedId = actualRows.filter((row) => row.values.plannedId);
  const rowsWithValidPlannedId = [];
  for (const row of rowsWithPlannedId) {
    if (!isLessonImportUuid(row.values.plannedId)) {
      addLessonImportPreviewIssue(row, "error", "plannedId", "关联预定ID格式无效；请填写系统中的 planned UUID，或留空等待后续匹配规则设计。");
      continue;
    }
    rowsWithValidPlannedId.push(row);
  }

  if (!rowsWithValidPlannedId.length) {
    return;
  }

  const plannedIdGroups = groupLessonImportRowsByPlannedId(rowsWithValidPlannedId);
  for (const groupRows of plannedIdGroups.values()) {
    if (groupRows.length <= 1) {
      continue;
    }
    for (const row of groupRows) {
      addLessonImportPreviewIssue(row, "error", "plannedId", "同一导入文件中多行 actual 使用了同一个关联预定ID，后续写入会产生重复关联风险。");
    }
  }

  const { plannedLessons, linkedActuals } = await fetchLessonImportPlannedReferences(Array.from(plannedIdGroups.keys()));
  const plannedById = new Map(plannedLessons.map((lesson) => [lesson.id, lesson]));
  const linkedActualsByPlannedId = groupRowsByField(linkedActuals, "planned_lesson_id");
  const precheckableRows = [];

  for (const row of rowsWithValidPlannedId) {
    const plannedId = normalizeLessonImportPlannedId(row.values.plannedId);
    const plannedLesson = plannedById.get(plannedId);

    if (!plannedLesson) {
      addLessonImportPreviewIssue(row, "error", "plannedId", "关联预定ID不存在，或不是当前系统 school 课时记录。");
      continue;
    }

    row.values.plannedId = plannedLesson.id;

    if (plannedLesson.lesson_type !== "planned") {
      addLessonImportPreviewIssue(row, "error", "plannedId", "关联预定ID对应课时不是 planned，不能作为 actual 的来源。");
      continue;
    }

    if (!["planned", "pending_makeup"].includes(plannedLesson.status)) {
      addLessonImportPreviewIssue(row, "error", "plannedId", "关联预定ID对应课时状态不是待上课或待补课，不能作为 actual 的来源。");
    }

    const mismatchedFields = lessonImportPlannedIdMismatchedFields(row, plannedLesson);
    if (mismatchedFields.length) {
      addLessonImportPreviewIssue(row, "error", "plannedId", `关联预定ID对应课时与导入行${mismatchedFields.join("、")}不一致。`);
    }

    const linkedActualRows = linkedActualsByPlannedId.get(plannedLesson.id) || [];
    if (linkedActualRows.length) {
      addLessonImportPreviewIssue(row, "error", "plannedId", `关联预定ID已存在 linked actual：${linkedActualRows.map((lesson) => shortId(lesson.id)).join("、")}，不能重复关联。`);
    }

    precheckableRows.push({ row, plannedLesson });
  }

  if (!precheckableRows.length) {
    return;
  }

  const studentSettlementTargets = precheckableRows
    .map(({ plannedLesson }) => ({
      studentId: plannedLesson.student_id,
      yearMonth: plannedLesson.year_month,
      businessEntityId: plannedLesson.business_entity_id,
    }))
    .filter((target) => target.studentId && target.yearMonth);
  const teacherWageTargets = precheckableRows
    .map(({ row, plannedLesson }) => ({
      teacherId: plannedLesson.teacher_id,
      settlementMonth: lessonImportYearMonth(row.values.lessonDate || plannedLesson.lesson_date),
      businessEntityId: plannedLesson.business_entity_id,
    }))
    .filter((target) => target.teacherId && target.settlementMonth);

  const { lockedStudentSettlements, lockedTeacherWageLocks } = await fetchLessonImportLockPrecheck({
    studentSettlementTargets,
    teacherWageTargets,
  });
  const lockedSettlementKeys = new Set(lockedStudentSettlements.map((row) => lessonImportSettlementKey({
    studentId: row.student_id,
    yearMonth: row.year_month,
    businessEntityId: row.business_entity_id,
  })));
  const lockedWageKeys = new Set(lockedTeacherWageLocks.map((row) => lessonImportWageLockKey({
    teacherId: row.teacher_id,
    settlementMonth: row.settlement_month,
    businessEntityId: row.business_entity_id,
  })));

  for (const { row, plannedLesson } of precheckableRows) {
    const settlementKey = lessonImportSettlementKey({
      studentId: plannedLesson.student_id,
      yearMonth: plannedLesson.year_month,
      businessEntityId: plannedLesson.business_entity_id,
    });
    if (lockedSettlementKeys.has(settlementKey)) {
      addLessonImportPreviewIssue(row, "error", "plannedId", `关联预定涉及已锁定学生结算月 ${plannedLesson.year_month}，后续写入会被拒绝。`);
    }

    const teacherSettlementMonth = lessonImportYearMonth(row.values.lessonDate || plannedLesson.lesson_date);
    const wageKey = lessonImportWageLockKey({
      teacherId: plannedLesson.teacher_id,
      settlementMonth: teacherSettlementMonth,
      businessEntityId: plannedLesson.business_entity_id,
    });
    if (lockedWageKeys.has(wageKey)) {
      addLessonImportPreviewIssue(row, "error", "plannedId", `actual 老师工资结算月 ${teacherSettlementMonth} 已锁定，后续写入会被拒绝。`);
    }
  }
}

function groupLessonImportRowsByPlannedId(rows) {
  const groups = new Map();
  for (const row of rows) {
    const plannedId = normalizeLessonImportPlannedId(row.values.plannedId);
    if (!plannedId) {
      continue;
    }
    const groupRows = groups.get(plannedId) || [];
    groupRows.push(row);
    groups.set(plannedId, groupRows);
  }
  return groups;
}

function normalizeLessonImportPlannedId(value) {
  return String(value || "").trim().toLowerCase();
}

function isLessonImportUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(value || "").trim());
}

function groupRowsByField(rows, field) {
  const groups = new Map();
  for (const row of rows || []) {
    const key = String(row?.[field] || "").trim();
    if (!key) {
      continue;
    }
    const groupRows = groups.get(key) || [];
    groupRows.push(row);
    groups.set(key, groupRows);
  }
  return groups;
}

function lessonImportPlannedIdMismatchedFields(row, plannedLesson) {
  const checks = [
    ["studentId", "student_id", "学生"],
    ["teacherId", "teacher_id", "老师"],
    ["subjectId", "subject_id", "科目"],
    ["businessEntityId", "business_entity_id", "业务归属"],
  ];

  return checks
    .filter(([rowField, lessonField]) => (
      row.values[rowField]
      && plannedLesson[lessonField]
      && row.values[rowField] !== plannedLesson[lessonField]
    ))
    .map(([, , label]) => label);
}

function lessonImportSettlementKey(target) {
  return [
    target.studentId || "",
    target.yearMonth || "",
    target.businessEntityId || "",
  ].join("|");
}

function lessonImportWageLockKey(target) {
  return [
    target.teacherId || "",
    target.settlementMonth || "",
    target.businessEntityId || "",
  ].join("|");
}

function lessonImportYearMonth(value) {
  const text = String(value || "").trim();
  const match = text.match(/^(\d{4})-(\d{2})/);
  return match ? `${match[1]}-${match[2]}` : "";
}

function findLessonImportPreviewHeaderRow(rows) {
  for (let index = 0; index < Math.min(rows.length, 30); index += 1) {
    const map = buildLessonImportPreviewColumnMap(rows[index]);
    const mappedFields = Object.entries(map)
      .filter(([, value]) => typeof value === "number")
      .map(([key]) => key);
    const hasCommon = mappedFields.includes("student") || mappedFields.includes("teacher");
    const hasLesson = mappedFields.some((key) => /date|status|duration|lessonType|time|fee|content/i.test(key));

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

    if (/^(学生|学生姓名|生徒|生徒名|姓名|student|studentname|student_name)$/.test(key)) set("student");
    if (/^(老师|教師|教师|先生|担当|担当老师|担当教師|担当先生|teacher|teachername|teacher_name)$/.test(key)) set("teacher");
    if (/^(科目|课程|講座|授業科目|subject|subjectname|subject_name)$/.test(key)) set("subject");
    if (/^(业务归属|业务归属id|归属|业务|业务主体|businessentity|business_entity|businessentityid|business_entity_id|entity|entityid)$/.test(key)) set("businessEntity");
    if (/^(lesson_type|lessontype|课时类型|课程类型|类型|recordtype|record_type)$/.test(key)) set("lessonType");
    if (/^(status|状态|ステータス|课时状态|授業状態)$/.test(key)) set("status");
    if (/^(日期|课时日期|上课日期|授業日|lessondate|lesson_date|date)$/.test(key)) set("lessonDate");
    if (/^(开始时间|开始|開始|start|starttime|start_time)$/.test(key)) set("startTime");
    if (/^(结束时间|结束|終了|end|endtime|end_time)$/.test(key)) set("endTime");
    if (/^(时间|时间段|时段|時間|時間帯|time|timerange|time_range)$/.test(key)) set("timeRange");
    if (/^(课时|课时时长|时长|時間数|授業時間|hours|hour|duration|durationhours|duration_hours)$/.test(key)) set("durationHours");
    if (/^(回数|回次|课次|課次|lessoncount|lesson_count)$/.test(key)) set("lessonCount");
    if (/^(单价|课程单价|単価|unitprice|unit_price)$/.test(key)) set("unitPrice");
    if (/^(金额|金額|课时费|课时费总额|课时费总额jpy|課時費總額|授業料|应收|应收课时费|lessonfee|lesson_fee|fee|amount|totalamount|total_amount)$/.test(key)) set("lessonFee");
    if (/^(是否计费|计费|收费|是否收费|請求|請求対象|billable|isbillable|is_billable)$/.test(key)) set("isBillable");
    if (/^(内容|授業内容|上课内容|上课内容及作业|content|lessoncontent|lesson_content)$/.test(key)) set("lessonContent");
    if (/^(备注|備考|メモ|note|memo)$/.test(key)) set("note");
    if (/^(plannedid|planned_id|plannedlessonid|planned_lesson_id|关联预定|关联预定id|预定id|预定课时id|関連予定id|关联标识|关联planned|关联plannedid)$/.test(key)) set("plannedId");

    if (/^(预定日期|预定日|予定日|planneddate|planned_date)$/.test(key)) set("plannedDate");
    if (/^(预定第几回|预定回数|予定回数|plannedcount|planned_count|plannedlessoncount|planned_lesson_count)$/.test(key)) set("plannedCount");
    if (/^(预定开始时间|预定开始|予定開始|plannedstart|planned_start|plannedstarttime|planned_start_time)$/.test(key)) set("plannedStartTime");
    if (/^(预定结束时间|预定结束|予定終了|plannedend|planned_end|plannedendtime|planned_end_time)$/.test(key)) set("plannedEndTime");
    if (/^(预定时间|预定时间段|予定時間帯|plannedtime|planned_time|plannedtimerange|planned_time_range)$/.test(key)) set("plannedTimeRange");
    if (/^(预定课时时长|预定时长|预定课时|予定時間数|予定授業時間|plannedduration|planned_duration|plannedhours|planned_hours)$/.test(key)) set("plannedDurationHours");
    if (/^(预定单价|予定単価|plannedunitprice|planned_unit_price)$/.test(key)) set("plannedUnitPrice");
    if (/^(预定课时费|预定金额|予定授業料|plannedfee|planned_fee|plannedlessonfee|planned_lesson_fee)$/.test(key)) set("plannedLessonFee");
    if (/^(预定状态|予定状態|plannedstatus|planned_status)$/.test(key)) set("plannedStatus");
    if (/^(预定计费|予定請求|plannedbillable|planned_billable)$/.test(key)) set("plannedBillable");
    if (/^(预定内容|予定内容|plannedcontent|planned_content)$/.test(key)) set("plannedContent");
    if (/^(预定备注|予定備考|plannednote|planned_note)$/.test(key)) set("plannedNote");

    if (/^(实际日期|实际上课日期|上课日|実際日|actualdate|actual_date)$/.test(key)) set("actualDate");
    if (/^(实际开始时间|实际开始|実際開始|actualstart|actual_start|actualstarttime|actual_start_time)$/.test(key)) set("actualStartTime");
    if (/^(实际结束时间|实际结束|実際終了|actualend|actual_end|actualendtime|actual_end_time)$/.test(key)) set("actualEndTime");
    if (/^(实际时间|实际时间段|実際時間帯|actualtime|actual_time|actualtimerange|actual_time_range)$/.test(key)) set("actualTimeRange");
    if (/^(实际课时时长|实际时长|实际课时|実際時間数|実際授業時間|actualduration|actual_duration|actualhours|actual_hours)$/.test(key)) set("actualDurationHours");
    if (/^(实际课时费|实际金额|実際授業料|actualfee|actual_fee|actuallessonfee|actual_lesson_fee)$/.test(key)) set("actualLessonFee");
    if (/^(实际状态|実際状態|actualstatus|actual_status)$/.test(key)) set("actualStatus");
    if (/^(实际计费|実際請求|actualbillable|actual_billable)$/.test(key)) set("actualBillable");
    if (/^(实际内容|実際内容|上课内容及作业|上课内容|actualcontent|actual_content)$/.test(key)) set("actualContent");
    if (/^(实际备注|実際備考|actualnote|actual_note)$/.test(key)) set("actualNote");
  });

  const hasPairedSpecificColumn = [
    map.plannedDate,
    map.plannedStatus,
    map.actualDate,
    map.actualStatus,
    map.actualContent,
  ].some((index) => typeof index === "number");

  if (hasPairedSpecificColumn) {
    if (map.plannedDurationHours === undefined && map.actualDurationHours === undefined && map.durationHours !== undefined) {
      map.plannedDurationHours = map.durationHours;
      map.actualDurationHours = map.durationHours;
    }
    if (map.plannedCount === undefined && map.lessonCount !== undefined) {
      map.plannedCount = map.lessonCount;
    }
    if (map.plannedStartTime === undefined && map.actualStartTime === undefined && map.startTime !== undefined) {
      map.plannedStartTime = map.startTime;
      map.actualStartTime = map.startTime;
    }
    if (map.plannedEndTime === undefined && map.actualEndTime === undefined && map.endTime !== undefined) {
      map.plannedEndTime = map.endTime;
      map.actualEndTime = map.endTime;
    }
    if (map.plannedTimeRange === undefined && map.actualTimeRange === undefined && map.timeRange !== undefined) {
      map.plannedTimeRange = map.timeRange;
      map.actualTimeRange = map.timeRange;
    }
    if (map.plannedUnitPrice === undefined && map.unitPrice !== undefined) {
      map.plannedUnitPrice = map.unitPrice;
    }
    if (map.plannedLessonFee === undefined && map.actualLessonFee === undefined && map.lessonFee !== undefined) {
      map.plannedLessonFee = map.lessonFee;
      map.actualLessonFee = map.lessonFee;
    }
    if (map.plannedStatus === undefined && map.actualStatus === undefined && map.status !== undefined) {
      map.plannedStatus = map.status;
      map.actualStatus = map.status;
    }
    if (map.plannedBillable === undefined && map.actualBillable === undefined && map.isBillable !== undefined) {
      map.plannedBillable = map.isBillable;
      map.actualBillable = map.isBillable;
    }
    if (map.plannedContent === undefined && map.actualContent === undefined && map.lessonContent !== undefined) {
      map.plannedContent = map.lessonContent;
      map.actualContent = map.lessonContent;
    }
    if (map.plannedNote === undefined && map.actualNote === undefined && map.note !== undefined) {
      map.plannedNote = map.note;
      map.actualNote = map.note;
    }
  }

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
      map.lessonCount,
      map.lessonFee,
      map.isBillable,
      map.lessonContent,
      map.note,
      map.plannedId,
    ],
    plannedSide: [
      map.plannedDate,
      map.plannedStartTime,
      map.plannedEndTime,
      map.plannedTimeRange,
      map.plannedDurationHours,
      map.plannedCount,
      map.plannedUnitPrice,
      map.plannedLessonFee,
      map.plannedStatus,
      map.plannedBillable,
      map.plannedContent,
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
      map.actualBillable,
      map.actualContent,
      map.actualNote,
      map.plannedId,
    ],
  };
}

function buildLessonImportPreviewRow(rawRow, rowNo, columnMap, mode, baseYear) {
  const paired = mode !== "generic";
  const fieldIndexes = {
    student: columnMap.student,
    teacher: columnMap.teacher,
    subject: columnMap.subject,
    businessEntity: columnMap.businessEntity,
    lessonType: paired ? -1 : columnMap.lessonType,
    status: paired
      ? (mode === "planned" ? columnMap.plannedStatus : columnMap.actualStatus)
      : columnMap.status,
    lessonDate: paired
      ? (mode === "planned" ? columnMap.plannedDate : columnMap.actualDate)
      : columnMap.lessonDate,
    startTime: paired
      ? (mode === "planned" ? columnMap.plannedStartTime : columnMap.actualStartTime)
      : columnMap.startTime,
    endTime: paired
      ? (mode === "planned" ? columnMap.plannedEndTime : columnMap.actualEndTime)
      : columnMap.endTime,
    timeRange: paired
      ? (mode === "planned" ? columnMap.plannedTimeRange : columnMap.actualTimeRange)
      : columnMap.timeRange,
    durationHours: paired
      ? (mode === "planned" ? columnMap.plannedDurationHours : columnMap.actualDurationHours)
      : columnMap.durationHours,
    lessonCount: paired
      ? (mode === "planned" ? columnMap.plannedCount : columnMap.lessonCount)
      : columnMap.lessonCount,
    unitPrice: paired
      ? (mode === "planned" ? columnMap.plannedUnitPrice : columnMap.unitPrice)
      : columnMap.unitPrice,
    lessonFee: paired
      ? (mode === "planned" ? columnMap.plannedLessonFee : columnMap.actualLessonFee)
      : columnMap.lessonFee,
    isBillable: paired
      ? (mode === "planned" ? columnMap.plannedBillable : columnMap.actualBillable)
      : columnMap.isBillable,
    lessonContent: paired
      ? (mode === "planned" ? columnMap.plannedContent : columnMap.actualContent)
      : columnMap.lessonContent,
    note: paired
      ? (mode === "planned" ? columnMap.plannedNote : columnMap.actualNote)
      : columnMap.note,
    plannedId: columnMap.plannedId,
  };
  const raw = {
    student: readLessonImportPreviewCell(rawRow, fieldIndexes.student),
    teacher: readLessonImportPreviewCell(rawRow, fieldIndexes.teacher),
    subject: readLessonImportPreviewCell(rawRow, fieldIndexes.subject),
    businessEntity: readLessonImportPreviewCell(rawRow, fieldIndexes.businessEntity),
    lessonType: paired ? mode : readLessonImportPreviewCell(rawRow, fieldIndexes.lessonType),
    status: readLessonImportPreviewCell(rawRow, fieldIndexes.status),
    lessonDate: readLessonImportPreviewCell(rawRow, fieldIndexes.lessonDate),
    startTime: readLessonImportPreviewCell(rawRow, fieldIndexes.startTime),
    endTime: readLessonImportPreviewCell(rawRow, fieldIndexes.endTime),
    timeRange: readLessonImportPreviewCell(rawRow, fieldIndexes.timeRange),
    durationHours: readLessonImportPreviewCell(rawRow, fieldIndexes.durationHours),
    lessonCount: readLessonImportPreviewCell(rawRow, fieldIndexes.lessonCount),
    unitPrice: readLessonImportPreviewCell(rawRow, fieldIndexes.unitPrice),
    lessonFee: readLessonImportPreviewCell(rawRow, fieldIndexes.lessonFee),
    isBillable: readLessonImportPreviewCell(rawRow, fieldIndexes.isBillable),
    lessonContent: readLessonImportPreviewCell(rawRow, fieldIndexes.lessonContent),
    note: readLessonImportPreviewCell(rawRow, fieldIndexes.note),
    plannedId: readLessonImportPreviewCell(rawRow, fieldIndexes.plannedId),
  };

  const row = {
    rowNo,
    mode,
    fieldIndexes,
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
      lessonCount: parseLessonImportPreviewInteger(raw.lessonCount),
      unitPrice: parseLessonImportPreviewNumber(raw.unitPrice),
      lessonFee: parseLessonImportPreviewNumber(raw.lessonFee),
      isBillable: normalizeLessonImportPreviewBillable(raw.isBillable),
      lessonContent: importPreviewCellText(raw.lessonContent),
      note: importPreviewCellText(raw.note),
      plannedId: importPreviewCellText(raw.plannedId),
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
      addLessonImportPreviewIssue(row, "error", field, lessonImportPreviewRequiredMessage(row, field));
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

  if (values.lessonType === "actual") {
    addLessonImportPreviewIssue(row, "error", "lessonType", "当前 planned-only 导入不支持 actual / completed / cancelled / makeup_completed 行。");
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

  if (hasLessonImportPreviewValue(row.raw.durationHours) && (!Number.isFinite(values.durationHours) || values.durationHours <= 0)) {
    addLessonImportPreviewIssue(row, "error", "durationHours", "课时必须是大于 0 的数字。");
  }

  if (hasLessonImportPreviewValue(row.raw.lessonCount) && (!Number.isInteger(values.lessonCount) || values.lessonCount <= 0)) {
    addLessonImportPreviewIssue(row, "error", "lessonCount", "回数必须是大于 0 的整数。");
  }

  if (hasLessonImportPreviewValue(row.raw.lessonFee) && (!Number.isFinite(values.lessonFee) || values.lessonFee < 0)) {
    addLessonImportPreviewIssue(row, "error", "lessonFee", "课时费总额必须是 0 或正数。");
  }

  if (hasLessonImportPreviewValue(row.raw.isBillable) && values.isBillable === null) {
    addLessonImportPreviewIssue(row, "warning", "isBillable", "是否计费无法识别；preview 阶段保留原值，后续导入前需确认。");
  }

  if (!hasLessonImportPreviewValue(row.raw.lessonFee)) {
    if (Number.isFinite(values.durationHours) && Number.isFinite(values.unitPrice) && values.durationHours > 0 && values.unitPrice > 0) {
      values.lessonFee = Math.round(values.durationHours * values.unitPrice);
      addLessonImportPreviewIssue(row, "warning", "lessonFee", "课时费总额为空，已按课时 x 单价做 preview 估算。");
    } else {
      addLessonImportPreviewIssue(row, "warning", "lessonFee", "课时费总额为空；preview 阶段不自动写入，后续导入前需确认。");
    }
  }

  if (values.status === "cancelled" && Number(values.lessonFee || 0) !== 0) {
    addLessonImportPreviewIssue(row, "warning", "lessonFee", "已取消 actual 通常应为 0 金额。");
  }

  if (values.status === "makeup_completed") {
    addLessonImportPreviewIssue(row, "warning", "status", "preview 阶段只标识补课完成，不建立 planned 关联。");
  }

  if (values.lessonType === "planned") {
    values.plannedId = "";
  }
}

function lessonImportPreviewRequiredMessage(row, field) {
  if (typeof row.fieldIndexes[field] !== "number") {
    const alias = LESSON_IMPORT_FIELD_ALIAS_TEXT[field];
    if (field === "lessonType") {
      return `未识别到 ${alias} 列；通用模板必须补充 预定 / 实际（或 planned / actual），旧模板分栏推断规则需后续单独设计。`;
    }
    if (field === "status") {
      return `未识别到 ${alias} 列；preview 阶段不会静默猜测状态，请补充合法状态值。`;
    }
    if (alias) {
      return `未识别到 ${alias} 列，请在模板中补充。`;
    }
  }

  if (field === "lessonType") {
    return "课时类型不能为空；请填写 预定 / 实际（兼容 planned / actual）。";
  }
  if (field === "status") {
    return "状态不能为空；预定可用 待上课 / 待补课，实际可用 已上课 / 取消 / 已补课。";
  }

  return `${LESSON_IMPORT_PREVIEW_FIELD_LABELS[field]}不能为空。`;
}

function validateLessonImportPreviewLookup(row, field, rows, labelGetter) {
  const rawValue = row.values[field];

  if (!rawValue) {
    return;
  }

  const match = findLessonImportPreviewLookup(rawValue, rows, labelGetter);
  if (!match.item) {
    addLessonImportPreviewIssue(row, "error", field, match.ambiguous ? "匹配到多个完全一致的主数据，请使用唯一名称或 ID。" : "未找到完全一致的主数据。");
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
  const exactItems = new Map();

  for (const item of rows || []) {
    const keys = [
      item.id,
      item.name,
      item.display_name,
      item.full_name,
      item.code,
      labelGetter(item),
    ].map(normalizeLessonImportLookup).filter(Boolean);

    if (keys.includes(text)) {
      exactItems.set(item.id, item);
    }
  }

  if (exactItems.size === 1) {
    return { item: Array.from(exactItems.values())[0], ambiguous: false };
  }

  return { item: null, ambiguous: exactItems.size > 1 };
}

function renderLessonImportPreview() {
  const rows = importPreviewRows;
  const errorCount = rows.filter((row) => row.errors.length).length;
  const warningCount = rows.filter((row) => row.warnings.length).length;
  const plannedCount = rows.filter((row) => row.values.lessonType === "planned").length;
  const actualCount = rows.filter((row) => row.values.lessonType === "actual").length;
  const hasCommittedPreview = Boolean(lastLessonImportResult?.successCount > 0);

  dom.lessonImportPreviewEmpty.classList.toggle("is-hidden", rows.length > 0);
  dom.lessonImportPreviewSummary.classList.toggle("is-hidden", rows.length === 0);
  dom.lessonImportPreviewRows.innerHTML = rows.map(renderLessonImportPreviewRow).join("");
  if (dom.lessonImportPlannedSubmitButton) {
    dom.lessonImportPlannedSubmitButton.disabled = isLessonImportSubmitting || rows.length === 0 || errorCount > 0 || hasCommittedPreview;
    dom.lessonImportPlannedSubmitButton.textContent = isLessonImportSubmitting ? "导入中..." : hasCommittedPreview ? "已导入" : "导入预定课时";
  }
  if (dom.lessonImportViewMonthButton) {
    const canViewImportMonth = !isLessonImportSubmitting && lastLessonImportResult?.months?.length === 1;
    dom.lessonImportViewMonthButton.classList.toggle("is-hidden", !canViewImportMonth);
    dom.lessonImportViewMonthButton.disabled = !canViewImportMonth;
    dom.lessonImportViewMonthButton.textContent = canViewImportMonth ? `查看 ${lastLessonImportResult.months[0]}` : "查看导入月份";
  }
  if (dom.lessonImportViewFirstDetailButton) {
    const canViewFirstDetail = !isLessonImportSubmitting && Boolean(lastLessonImportResult?.createdLessonIds?.[0]);
    dom.lessonImportViewFirstDetailButton.classList.toggle("is-hidden", !canViewFirstDetail);
    dom.lessonImportViewFirstDetailButton.disabled = !canViewFirstDetail;
  }

  if (rows.length) {
    const summaryRows = [
      renderDialogSummaryRow("预览行", `${rows.length} 行`),
      renderDialogSummaryRow("planned / actual", `${plannedCount} / ${actualCount}`),
      renderDialogSummaryRow("错误行", `${errorCount} 行`),
      renderDialogSummaryRow("警告行", `${warningCount} 行`),
    ];
    if (lastLessonImportResult) {
      summaryRows.push(
        renderDialogSummaryRow("成功导入", `${lastLessonImportResult.successCount} 行`),
        renderDialogSummaryRow("导入月份", formatLessonImportMonthRange(lastLessonImportResult.months) || "-"),
        renderDialogSummaryRow("导入记录", renderLessonImportResultLinks(lastLessonImportResult.createdLessonIds), true)
      );
    }
    dom.lessonImportPreviewSummary.innerHTML = summaryRows.join("");
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
      ${renderLessonImportPreviewCell(row, "isBillable", displayLessonImportPreviewBillable(values))}
      ${renderLessonImportPreviewCell(row, "durationHours", displayImportPreviewNumber(values.durationHours))}
      ${renderLessonImportPreviewCell(row, "lessonCount", Number.isInteger(values.lessonCount) ? values.lessonCount : "")}
      ${renderLessonImportPreviewCell(row, "lessonFee", displayImportPreviewNumber(values.lessonFee))}
      <td class="lesson-import-preview-content-cell">${escapeHtml(displayValue(values.lessonContent))}</td>
      <td class="lesson-import-preview-note-cell">${escapeHtml(displayValue(values.note))}</td>
      ${renderLessonImportPreviewCell(row, "plannedId", values.plannedId)}
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
    if (row.importResult?.createdLessonId) {
      const href = createLessonDetailUrl(row.importResult.createdLessonId, lessonImportYearMonth(row.values.lessonDate), activeView);
      return `<a class="table-action-button" href="${escapeAttribute(href)}">已导入 ${escapeHtml(shortId(row.importResult.createdLessonId))}</a>`;
    }
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

function renderLessonImportResultLinks(createdLessonIds = []) {
  const ids = createdLessonIds.filter(Boolean);
  if (!ids.length) {
    return "-";
  }

  const links = ids.slice(0, 3).map((lessonId, index) => {
    const href = createLessonDetailUrl(lessonId, lastLessonImportResult?.months?.[0] || loadedMonth, activeView);
    return `<a class="table-action-button" href="${escapeAttribute(href)}">${index === 0 ? "首条详情" : shortId(lessonId)}</a>`;
  });
  if (ids.length > links.length) {
    links.push(`<span>${escapeHtml(`等 ${ids.length} 条`)}</span>`);
  }
  return links.join(" ");
}

function renderDialogSummaryRow(label, value, valueIsHtml = false) {
  return `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${valueIsHtml ? value : escapeHtml(value)}</span>
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

function formatLessonImportFailedRowsMessage(failedRows) {
  const messages = (failedRows || []).flatMap((row) => row.errors || []);
  if (messages.some(isLessonImportDuplicateBatchMessage)) {
    return "检测到重复导入批次：系统已拒绝本次提交，未写入新的预定课时。请重新选择文件生成新的预览后再导入。";
  }
  return `导入被拒绝：${failedRows.length} 行需要处理。`;
}

function formatLessonImportSubmitError(error) {
  const message = error?.message || String(error);
  if (isLessonImportDuplicateBatchMessage(message)) {
    return "检测到重复导入批次：该批次已经导入过，系统没有写入新的预定课时。请重新选择文件后再导入。";
  }
  return message;
}

function isLessonImportDuplicateBatchMessage(message) {
  const text = safeText(message).toLowerCase();
  return (
    text.includes("import_batch_id") ||
    text.includes("同一批次") ||
    text.includes("重复导入") ||
    text.includes("already imported") ||
    text.includes("batch already") ||
    text.includes("batch exists") ||
    text.includes("import batch")
  );
}

function buildLessonImportSubmitRows(rows) {
  return rows.map((row, index) => ({
    row_index: index + 1,
    source_row_no: row.rowNo,
    row_key: `${row.rowNo}:${index + 1}`,
    lesson_type: row.values.lessonType,
    status: row.values.status,
    lesson_date: row.values.lessonDate,
    start_time: row.values.startTime || null,
    end_time: row.values.endTime || null,
    duration_hours: row.values.durationHours,
    lesson_count: Number.isInteger(row.values.lessonCount) ? row.values.lessonCount : null,
    unit_price: Number.isFinite(row.values.unitPrice) ? row.values.unitPrice : 0,
    lesson_fee: Number.isFinite(row.values.lessonFee) ? row.values.lessonFee : null,
    is_billable: true,
    student_id: row.values.studentId,
    teacher_id: row.values.teacherId,
    subject_id: row.values.subjectId,
    business_entity_id: row.values.businessEntityId,
    planned_lesson_id: null,
    lesson_content: row.values.lessonContent || null,
    note: row.values.note || null,
  }));
}

function applyLessonImportSubmitResults(results) {
  const rowsByIndex = new Map(importPreviewRows.map((row, index) => [index + 1, row]));

  for (const result of results || []) {
    const row = rowsByIndex.get(Number(result.row_index));
    if (!row) {
      continue;
    }
    row.importResult = {
      createdLessonId: result.created_lesson_id || "",
      batchCommitted: Boolean(result.batch_committed),
    };
    for (const message of result.errors || []) {
      addLessonImportPreviewIssue(row, "error", "lessonType", message);
    }
    for (const message of result.warnings || []) {
      addLessonImportPreviewIssue(row, "warning", "lessonType", message);
    }
  }
}

function setLessonImportSubmitting(isSubmitting) {
  isLessonImportSubmitting = isSubmitting;
  const hasCommittedPreview = Boolean(lastLessonImportResult?.successCount > 0);
  if (dom.lessonImportPlannedSubmitButton) {
    const hasErrors = importPreviewRows.some((row) => row.errors.length);
    dom.lessonImportPlannedSubmitButton.disabled = isSubmitting || importPreviewRows.length === 0 || hasErrors || hasCommittedPreview;
    dom.lessonImportPlannedSubmitButton.textContent = isSubmitting ? "导入中..." : hasCommittedPreview ? "已导入" : "导入预定课时";
  }
  if (dom.lessonImportViewMonthButton) {
    const canViewImportMonth = !isSubmitting && lastLessonImportResult?.months?.length === 1;
    dom.lessonImportViewMonthButton.classList.toggle("is-hidden", !canViewImportMonth);
    dom.lessonImportViewMonthButton.disabled = !canViewImportMonth;
    dom.lessonImportViewMonthButton.textContent = canViewImportMonth ? `查看 ${lastLessonImportResult.months[0]}` : "查看导入月份";
  }
  if (dom.lessonImportViewFirstDetailButton) {
    const canViewFirstDetail = !isSubmitting && Boolean(lastLessonImportResult?.createdLessonIds?.[0]);
    dom.lessonImportViewFirstDetailButton.classList.toggle("is-hidden", !canViewFirstDetail);
    dom.lessonImportViewFirstDetailButton.disabled = !canViewFirstDetail;
  }
}

async function calculateLessonImportFileHash(file) {
  if (window.crypto?.subtle) {
    const buffer = await file.arrayBuffer();
    const digest = await window.crypto.subtle.digest("SHA-256", buffer);
    return Array.from(new Uint8Array(digest))
      .map((value) => value.toString(16).padStart(2, "0"))
      .join("");
  }

  return `${file.name}:${file.size}:${file.lastModified || 0}`;
}

function createLessonImportBatchId() {
  if (window.crypto?.randomUUID) {
    return window.crypto.randomUUID();
  }

  return "10000000-1000-4000-8000-".replace(/[018]/g, (char) => (
    (Number(char) ^ window.crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> Number(char) / 4).toString(16)
  )) + Date.now().toString(16).padStart(12, "0").slice(-12);
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
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function normalizeLessonImportDuplicateText(value) {
  return importPreviewCellText(value)
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function normalizeLessonImportDuplicateNumber(value) {
  if (!Number.isFinite(value)) {
    return "";
  }

  return String(Number(value));
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

  if (text === "planned" || /计划|計画|預定|预定|予定/.test(text)) {
    return "planned";
  }

  if (text === "actual" || /实际|實際|実際|实绩|實績|実績/.test(text)) {
    return "actual";
  }

  return text;
}

function normalizeLessonImportPreviewStatus(value) {
  const text = normalizeLessonImportHeader(value);
  if (!text) {
    return "";
  }

  if (text === "planned" || text === "pending" || /待上课|待上課|待上|预定|預定|予定/.test(text)) {
    return "planned";
  }

  if (text === "pending_makeup" || text === "pendingmakeup" || /待补课|待補課|待补|未补/.test(text)) {
    return "pending_makeup";
  }

  if (text === "completed" || /已完成|已上课|已上課|已上|上课済|上課済|済|完成/.test(text)) {
    return "completed";
  }

  if (text === "cancelled" || text === "canceled" || /已取消|取消课|取消|请假|休|放假/.test(text)) {
    return "cancelled";
  }

  if (text === "makeup_completed" || text === "makeupcompleted" || text === "makeup" || /补课完成|補課完成|補完|已补课|已補課|已补|已補/.test(text)) {
    return "makeup_completed";
  }

  return text;
}

function normalizeLessonImportPreviewBillable(value) {
  const text = normalizeLessonImportHeader(value);
  if (!text) {
    return "";
  }

  if (/^(是|要|计费|收费|收費|yes|true|1)$/.test(text)) {
    return true;
  }

  if (/^(否|不|不计费|不收费|不收費|no|false|0)$/.test(text)) {
    return false;
  }

  return null;
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

function parseLessonImportPreviewInteger(value) {
  if (typeof value === "number") {
    return Number.isInteger(value) ? value : Number.NaN;
  }

  const text = String(value ?? "").trim();
  if (!text) {
    return Number.NaN;
  }

  const number = Number(text.replace(/[,，回次]/g, ""));
  return Number.isInteger(number) ? number : Number.NaN;
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

function displayLessonImportPreviewBillable(values) {
  if (values.isBillable === true) {
    return "计费";
  }

  if (values.isBillable === false) {
    return "不计费";
  }

  return values.isBillable === null ? "无法识别" : "";
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
      <td class="lesson-nowrap"><a class="table-action-button" href="${escapeAttribute(createLessonDetailUrl(record.id, loadedMonth, "list"))}">查看详情</a></td>
      <td class="lesson-nowrap">${renderLessonActions(record)}</td>
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
  activeView = normalizeLessonView(view);
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
      crossMonthActuals: crossMonthMakeupReferences.actualsBySourcePlannedId.get(planned.id) || [],
    })),
    unlinkedActuals,
    otherRecords,
  };
}

function renderLessonPairRow(pair) {
  const actualCards = [
    ...pair.actuals.map((actual) => renderLessonPairCard(actual, "actual")),
    ...pair.crossMonthActuals.map((actual) => renderCrossMonthMakeupCompletedReferenceCard(actual)),
  ];
  const actualHtml = actualCards.length ? actualCards.join("") : renderMissingActualCard(pair.planned);

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
  const sourcePlanned = actual.planned_lesson_id
    ? crossMonthMakeupReferences.sourcePlannedById.get(actual.planned_lesson_id)
    : null;
  const plannedHtml = sourcePlanned
    ? renderCrossMonthMakeupSourceReferenceCard(sourcePlanned)
    : '<div class="lesson-pair-placeholder">未找到对应 planned 记录</div>';

  return `
    <article class="lesson-pair-row lesson-pair-row-unlinked">
      <div class="lesson-pair-column lesson-pair-column-empty">
        <div class="lesson-pair-column-title">planned</div>
        ${plannedHtml}
      </div>
      <div class="lesson-pair-column lesson-pair-column-actual">
        <div class="lesson-pair-column-title">actual</div>
        ${renderLessonPairCard(actual, "actual")}
      </div>
    </article>
  `;
}

function renderCrossMonthMakeupCompletedReferenceCard(actual) {
  return `
    <article class="lesson-pair-card lesson-pair-card-makeup lesson-pair-card-reference">
      <div class="lesson-pair-card-header">
        <div>
          <a class="table-action-button" href="${escapeAttribute(createLessonDetailUrl(actual.id, actual.year_month, "pair"))}">查看详情</a>
          <span class="lesson-pair-id">${escapeHtml(shortId(actual.id))}</span>
        </div>
        <span class="status-badge ${escapeAttribute(statusClass(actual.status))}">已于 ${escapeHtml(formatMonth(actual.year_month))} 完成</span>
      </div>
      <div class="lesson-pair-main">
        <strong>${escapeHtml(formatDateOnly(actual.lesson_date))}</strong>
        <span>${escapeHtml(formatWeekday(actual.lesson_date))}</span>
        <span>${escapeHtml(formatTimeRange(actual.start_time, actual.end_time))}</span>
      </div>
      <dl class="lesson-pair-meta">
        <div><dt>计费</dt><dd>${escapeHtml(actualBillableSummary(actual))}</dd></div>
        <div><dt>时长</dt><dd>${escapeHtml(displayValue(actual.duration_hours))}</dd></div>
        <div><dt>金额</dt><dd>${escapeHtml(formatCurrency(actual.lesson_fee, "JPY"))}</dd></div>
        <div><dt>老师结算月</dt><dd>${escapeHtml(formatMonth(actual.teacher_settlement_month))}</dd></div>
      </dl>
      <div class="lesson-pair-reference-note">已于 ${escapeHtml(formatMonth(actual.year_month))} 完成；来源 planned 不会在原月份被修改。</div>
    </article>
  `;
}

function renderCrossMonthMakeupSourceReferenceCard(sourcePlanned) {
  return `
    <article class="lesson-pair-card lesson-pair-card-reference">
      <div class="lesson-pair-card-header">
        <div>
          <a class="table-action-button" href="${escapeAttribute(createLessonDetailUrl(sourcePlanned.id, sourcePlanned.year_month, "pair"))}">查看详情</a>
          <span class="lesson-pair-id">${escapeHtml(shortId(sourcePlanned.id))}</span>
        </div>
        <span class="status-badge ${escapeAttribute(statusClass(sourcePlanned.status))}">来源：${escapeHtml(formatMonth(sourcePlanned.year_month))} 待补课</span>
      </div>
      <div class="lesson-pair-main">
        <strong>${escapeHtml(formatDateOnly(sourcePlanned.lesson_date))}</strong>
        <span>${escapeHtml(formatWeekday(sourcePlanned.lesson_date))}</span>
        <span>${escapeHtml(formatTimeRange(sourcePlanned.start_time, sourcePlanned.end_time))}</span>
      </div>
      <dl class="lesson-pair-meta">
        <div><dt>学生</dt><dd>${escapeHtml(nameById(students, sourcePlanned.student_id, studentName))}</dd></div>
        <div><dt>老师</dt><dd>${escapeHtml(nameById(teachers, sourcePlanned.teacher_id, teacherName))}</dd></div>
        <div><dt>科目</dt><dd>${escapeHtml(nameById(subjects, sourcePlanned.subject_id, subjectName))}</dd></div>
        <div><dt>业务归属</dt><dd>${escapeHtml(nameById(businessEntities, sourcePlanned.business_entity_id, businessEntityName))}</dd></div>
      </dl>
      <div class="lesson-pair-reference-note">来源：${escapeHtml(formatMonth(sourcePlanned.year_month))} 待补课；当前月份只保存补课完成 actual。</div>
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
    && ["planned", "pending_makeup"].includes(planned.status)
    && !isVoidedPlanned(planned);
}

function renderLessonEditAction(record) {
  return lessonEditController?.renderAction(record) || "";
}

function renderLessonActions(record) {
  return [
    renderLessonEditAction(record),
  ].filter(Boolean).join(" ");
}

function hasLinkedActualLesson(plannedLessonId) {
  return lessonRecords.some((record) => (
    record.lesson_type === "actual"
    && record.planned_lesson_id === plannedLessonId
  ));
}

function isVoidedPlanned(record) {
  return Boolean(record && record.lesson_type === "planned" && record.voided_at);
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
          <a class="table-action-button" href="${escapeAttribute(createLessonDetailUrl(record.id, loadedMonth, "pair"))}">查看详情</a>
          ${renderLessonActions(record)}
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
    if (!recordMatchesStatusFilter(record, filters.status)) {
      return false;
    }

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

    if (filters.isBillable && String(record.is_billable) !== filters.isBillable) {
      return false;
    }

    return matchesKeyword(record, filters.keyword);
  });
}

function recordMatchesStatusFilter(record, statusFilter) {
  if (statusFilter === "voided") {
    return isVoidedPlanned(record);
  }

  if (isVoidedPlanned(record)) {
    return false;
  }

  if (!statusFilter) {
    return true;
  }

  return record.status === statusFilter;
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

    const leftSubjectRank = subjectSortRank(nameById(subjects, left.subject_id, subjectName));
    const rightSubjectRank = subjectSortRank(nameById(subjects, right.subject_id, subjectName));
    if (leftSubjectRank !== rightSubjectRank) {
      return leftSubjectRank - rightSubjectRank;
    }

    const subjectNameCompare = nameById(subjects, left.subject_id, subjectName)
      .localeCompare(nameById(subjects, right.subject_id, subjectName), "zh-CN");
    if (subjectNameCompare !== 0) {
      return subjectNameCompare;
    }

    const countCompare = compareNullableNumbers(left.lesson_count, right.lesson_count);
    if (countCompare !== 0) {
      return countCompare;
    }

    const timeCompare = compareNullableText(left.start_time, right.start_time);
    if (timeCompare !== 0) {
      return timeCompare;
    }

    const createdCompare = compareNullableText(left.created_at, right.created_at);
    if (createdCompare !== 0) {
      return createdCompare;
    }

    return safeText(left.id).localeCompare(safeText(right.id));
  });
}

function subjectSortRank(subjectLabel) {
  const normalized = safeText(subjectLabel).toLowerCase();
  const matchIndex = SUBJECT_SORT_RULES.findIndex((aliases) => (
    aliases.some((alias) => normalized.includes(alias.toLowerCase()))
  ));
  return matchIndex >= 0 ? matchIndex : SUBJECT_SORT_RULES.length;
}

function compareNullableNumbers(left, right) {
  const leftNumber = Number(left);
  const rightNumber = Number(right);
  const leftFinite = Number.isFinite(leftNumber);
  const rightFinite = Number.isFinite(rightNumber);
  if (leftFinite && rightFinite && leftNumber !== rightNumber) {
    return leftNumber - rightNumber;
  }
  if (leftFinite !== rightFinite) {
    return leftFinite ? -1 : 1;
  }
  return 0;
}

function compareNullableText(left, right) {
  const leftText = safeText(left);
  const rightText = safeText(right);
  if (leftText && rightText) {
    return leftText.localeCompare(rightText);
  }
  if (Boolean(leftText) !== Boolean(rightText)) {
    return leftText ? -1 : 1;
  }
  return 0;
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

function addMonthsToYearMonth(yearMonth, offset) {
  const match = safeText(yearMonth).match(/^(\d{4})-(0[1-9]|1[0-2])$/);
  if (!match) {
    return "";
  }
  const year = Number(match[1]);
  const monthIndex = Number(match[2]) - 1 + offset;
  const date = new Date(year, monthIndex, 1);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function firstDateOfMonth(yearMonth) {
  return yearMonth && /^\d{4}-(0[1-9]|1[0-2])$/.test(yearMonth) ? `${yearMonth}-01` : "";
}

function displayInputNumber(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }

  return String(value);
}

function isTimeValue(value) {
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(safeText(value));
}

function validateLessonTimeRange(startTime, endTime) {
  const startText = safeText(startTime);
  const endText = safeText(endTime);
  if (!startText && !endText) {
    return { status: "incomplete" };
  }
  if (!startText || !endText) {
    return { status: "incomplete" };
  }
  if (!isTimeValue(startText) || !isTimeValue(endText)) {
    return {
      status: "error",
      message: "请填写正确的开始时间和结束时间。",
    };
  }

  const startMinutes = clockMinutes(startText);
  const endMinutes = clockMinutes(endText);
  const diffMinutes = endMinutes - startMinutes;
  if (diffMinutes <= 0) {
    return {
      status: "error",
      message: "结束时间必须晚于开始时间。",
    };
  }
  if (diffMinutes % 15 !== 0) {
    return {
      status: "error",
      message: "开始/结束时间差必须是 15 分钟的整数倍；不会自动四舍五入。",
    };
  }

  return {
    status: "valid",
    durationHours: Number((diffMinutes / 60).toFixed(2)),
  };
}

function numbersEqual(left, right) {
  return Math.abs(Number(left) - Number(right)) < 0.000001;
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
