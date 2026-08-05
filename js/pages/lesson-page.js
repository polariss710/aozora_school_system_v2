import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { getCurrentAuthContext } from "../api/auth-api.js?v=p0-g1-a-20260804-1";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createActualLessonFromPlanned,
  createPartialCompletedActualFromPlanned,
  createCancelledActualLessonFromPlanned,
  createCrossMonthMakeupCompletedActualFromPlanned,
  createMakeupCompletedActualLessonFromPlanned,
  createPlannedLessonRecord,
  fetchCrossMonthMakeupReferences,
  fetchOpenMakeupSourceLessons,
  fetchLessonBusinessEntities,
  fetchLessonCreditSummary,
  fetchLessonImportLockPrecheck,
  fetchLessonImportPlannedReferences,
  fetchLessonManagementStats,
  fetchLessonRecords,
  fetchLessonStudents,
  fetchStudentLessonPdfExport,
  fetchLessonSubjects,
  fetchLessonTeachers,
  generatePlannedLessonRecordsBatch,
  importPlannedLessonRecordsBatch,
} from "../api/lesson-api.js?v=cancellation-hardening-20260806-1";
import { cacheLessonDeleteDialogDom, createLessonDeleteDialogController } from "../components/lesson-delete-dialog.js?v=p0f-readfix-20260803-1";
import { cacheLessonEditDialogDom, createLessonEditDialogController } from "../components/lesson-edit-dialog.js?v=p0f-readfix-20260803-1";
import { cacheLessonVoidDialogDom, createLessonVoidDialogController } from "../components/lesson-void-dialog.js?v=p0f-readfix-20260803-1";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatMonth, safeText } from "../utils/format.js";
import { lessonUserErrorMessage } from "../utils/lesson-error-message.js?v=p0f-readfix-20260803-1";
import {
  hasAuthoritativePlannedFeeBundle,
  plannedAirconConditionLabel,
  shouldDisplayPlannedAirconDetails,
} from "../utils/planned-aircon-display.js?v=p0f-readfix-20260803-1";
import {
  buildActualOverageDisplay,
  buildLessonMonthSemantics,
  hasFrozenActualOverage,
  validateActualDurationForFlow,
} from "../utils/actual-overage.js?v=p0f-readfix-20260803-1";
import {
  createLatestRequestGate,
  listStudentSettlementMonthWeeks,
  normalizeStudentSettlementWeekStart,
  partitionAuthoritativeLessonRecords,
  validateUniqueLessonRecordIds,
} from "../utils/lesson-settlement-filter.js?v=p0f-readfix-20260803-1";
import {
  defaultNewBusinessEntityId,
  isNewBusinessEntityId,
  newBusinessEntities,
} from "../utils/business-entity-policy.js";

const DEFAULT_FILTERS = {
  weekStart: "",
  studentId: "",
  teacherId: "",
  subjectId: "",
  businessEntityId: "",
  lessonType: "",
  status: "",
  isBillable: "",
  keyword: "",
};

const TUITION_HISTORY_STATE_WARNING = "课时历史状态暂时无法读取，相关修改操作已隐藏。";

const CANCELLED_ACTUAL_LESSON_ERROR_MESSAGES = new Map([
  ["LESSON_CANCELLATION_AUTH_REQUIRED", "当前登录状态无效，请重新登录。"],
  ["LESSON_CANCELLATION_MEMBERSHIP_REQUIRED", "当前账号没有课时操作权限。"],
  ["LESSON_CANCELLATION_ACTIVE_MEMBERSHIP_REQUIRED", "当前账号权限已停用，不能标记取消。"],
  ["LESSON_CANCELLATION_ROLE_REQUIRED", "仅管理员或操作员可以标记取消并转待补课。"],
  ["LESSON_CANCELLATION_SOURCE_REQUIRED", "请选择要标记取消的预定课时。"],
  ["LESSON_CANCELLATION_SOURCE_NOT_FOUND", "该预定课时不存在，请刷新后重试。"],
  ["LESSON_CANCELLATION_SOURCE_TYPE_INVALID", "只能标记取消预定课时。"],
  ["LESSON_CANCELLATION_SOURCE_VOIDED", "该预定课时已作废，不能标记取消。"],
  ["LESSON_CANCELLATION_LINKED_ACTUAL_EXISTS", "该预定课时已有关联实际课时，不能重复标记取消。"],
  ["LESSON_CANCELLATION_SOURCE_STATUS_INVALID", "仅待上课状态可以标记取消并转待补课。"],
  ["LESSON_CANCELLATION_TIME_REQUIRED", "请填写完整的开始时间和结束时间。"],
  ["LESSON_CANCELLATION_START_TIME_INVALID", "开始时间格式无效，请使用 HH:MM。"],
  ["LESSON_CANCELLATION_END_TIME_INVALID", "结束时间格式无效，请使用 HH:MM。"],
  ["LESSON_CANCELLATION_TIME_GRID_INVALID", "开始和结束时间必须使用 15 分钟刻度。"],
  ["LESSON_CANCELLATION_TIME_RANGE_INVALID", "结束时间必须晚于开始时间，暂不支持跨日。"],
  ["LESSON_CANCELLATION_DURATION_MISMATCH", "时长预览与数据库计算不一致，请重新选择开始和结束时间。"],
  ["LESSON_CANCELLATION_STUDENT_SETTLEMENT_LOCKED", "该课时所属学生月度结算已锁定，不能标记取消。"],
  ["LESSON_CANCELLATION_TEACHER_WAGE_LOCKED", "该取消日期所属老师工资月份已锁定，不能标记取消。"],
  ["LESSON_FINANCIAL_FACT_IMMUTABLE", "该课时所属结算已被历史学费账单消费，不能再标记取消。"],
  ["SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED", "该课时已被月度结算作为待补权益处理，不能重复标记取消。"],
  ["SETTLEMENT_LESSON_VARIANCE_SOURCE_IMMUTABLE", "该课时已被月度结算固化，不能再标记取消。"],
]);

const DEFAULT_LESSON_VIEW = "pair";

const WEEKDAY_LABELS = ["日", "一", "二", "三", "四", "五", "六"];

const LESSON_TYPE_LABELS = {
  planned: "预定课时",
  actual: "实际课时",
};

const LESSON_STATUS_LABELS = {
  planned: "待上课",
  completed: "已上课",
  pending_makeup: "待补课",
  makeup_completed: "已补课",
  cancelled: "已取消",
};

const FIXED_ONSITE_LESSON_VENUES = ["Regus公共区", "Regus办公室"];

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

const LESSON_BATCH_SUBJECT_ORDER_FALLBACK = 999;

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
  "授课方式",
  "上课场地",
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
  ["示例学生", "示例老师", "数学", "青空进学塾", "2026-06-10", "10:00", "11:00", "线下", "Regus公共区", "预定", "待上课", 1, 1, 5000, "是", "预定课内容", "预定-待上课 示例"],
  ["示例学生", "示例老师", "数学", "青空进学塾", "2026-06-11", "10:00", "11:00", "线上", "Zoom", "预定", "待补课", 1, 2, 5000, "是", "待补课预定内容", "预定-待补课 示例"],
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
  ["授课方式 / 上课场地", "建议", "授课方式可填 线下 / 线上；线下时只能填写 Regus公共区 或 Regus办公室，线上可自由填写平台。"],
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

const LESSON_BATCH_WEEKDAY_OPTIONS = [
  ["1", "周一"],
  ["2", "周二"],
  ["3", "周三"],
  ["4", "周四"],
  ["5", "周五"],
  ["6", "周六"],
  ["0", "周日"],
];

const LESSON_BATCH_FIELD_IDS = [
  "student",
  "businessEntity",
  "startDate",
  "endDate",
  "airconRate",
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
  "lessonDeliveryMode",
  "lessonVenue",
  "durationHours",
  "unitPrice",
  "lessonFee",
  "airconRate",
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
  "lessonContent",
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
  "teacher",
  "subject",
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
  "teacher",
  "subject",
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
let rejectedLessonRecords = [];
const lessonRecordsRequestGate = createLatestRequestGate();
let crossMonthMakeupReferences = emptyCrossMonthMakeupReferences();
let loadedMonth = "";
let loadedLessonRecordMode = "";
let activeView = DEFAULT_LESSON_VIEW;
let isCreatePlannedLessonSubmitting = false;
let createPlannedLessonInitialSnapshot = null;
let isCreatePlannedLessonCloseConfirmPending = false;
let currentActualSourceLesson = null;
let isCreateActualLessonSubmitting = false;
let createActualLessonInitialSnapshot = null;
let isCreateActualLessonCloseConfirmPending = false;
let currentCancelledActualSourceLesson = null;
let isCreateCancelledActualLessonSubmitting = false;
let createCancelledActualLessonInitialSnapshot = null;
let isCreateCancelledActualLessonCloseConfirmPending = false;
let currentMakeupActualSourceLesson = null;
let isCreateMakeupActualLessonSubmitting = false;
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
let lessonDeleteController = null;
let isLessonPageInitialized = false;
let initialLessonQueryFilters = null;
let lessonStatsRequestId = 0;
let isLessonPdfExportSubmitting = false;
let importPreviewRows = [];
let importPreviewFileMeta = null;
let isLessonImportSubmitting = false;
let lastLessonImportResult = null;
const successfulLessonImportFileHashes = new Set();
let batchGeneratePatterns = [];
let batchGeneratePreviewRows = [];
let batchGenerateRemovedKeys = new Set();
let isLessonBatchGenerateSubmitting = false;
let lessonBatchGenerateInitialSnapshot = null;
let isLessonBatchGenerateCloseConfirmPending = false;
let lastLessonBatchGenerateResult = null;

export function initLessonPage() {
  if (isLessonPageInitialized) {
    return;
  }
  isLessonPageInitialized = true;

  cacheDom();
  setupLessonEditController();
  setupLessonVoidController();
  setupLessonDeleteController();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  renderWeekFilterOptions(currentYearMonth());
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

function setupLessonDeleteController() {
  lessonDeleteController = createLessonDeleteDialogController({
    dom: cacheLessonDeleteDialogDom(),
    getLessonRecords: () => lessonRecords,
    hasSupabaseConfig,
    showMessage,
    onDeleted: refreshAfterDeleteLesson,
    getLinkedActualExists: hasLinkedActualLesson,
    setExternalBusy: (isBusy) => {
      if (dom.openCreatePlannedLessonButton) {
        dom.openCreatePlannedLessonButton.disabled = isBusy;
      }
    },
  });
  lessonDeleteController.init();
}

function setupLessonEditController() {
  lessonEditController = createLessonEditDialogController({
    dom: cacheLessonEditDialogDom(),
    getLessonRecords: () => lessonRecords,
    getMasterData: () => ({ students, teachers, subjects, businessEntities }),
    hasSupabaseConfig,
    showMessage,
    onSaved: refreshAfterEditLesson,
    getRefreshContext: () => readFilters(),
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
  dom.weekFilter = document.querySelector("#lessonWeekFilter");
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
  dom.openLessonBatchGenerateButton = document.querySelector("#openLessonBatchGenerateButton");
  dom.openLessonPdfExportButton = document.querySelector("#openLessonPdfExportButton");
  dom.openWeeklyScheduleForStudentButton = document.querySelector("#openWeeklyScheduleForStudentButton");
  dom.openCrossMonthMakeupDialogButton = document.querySelector("#openCrossMonthMakeupDialogButton");
  dom.openCreatePlannedLessonButton = document.querySelector("#openCreatePlannedLessonButton");
  dom.listView = document.querySelector("#lessonListView");
  dom.pairView = document.querySelector("#lessonPairView");
  dom.pairRows = document.querySelector("#lessonPairRows");
  dom.tableBody = document.querySelector("#lessonTableBody");
  dom.loadingState = document.querySelector("#lessonLoadingState");
  dom.emptyState = document.querySelector("#lessonEmptyState");
  dom.validationWarning = document.querySelector("#lessonValidationWarning");
  dom.statsPlannedHours = document.querySelector("#lessonStatsPlannedHours");
  dom.statsActualHours = document.querySelector("#lessonStatsActualHours");
  dom.statsPlannedFee = document.querySelector("#lessonStatsPlannedFee");
  dom.statsActualFee = document.querySelector("#lessonStatsActualFee");
  dom.statsCrossMonthMakeupCompletedCount = document.querySelector("#lessonStatsCrossMonthMakeupCompletedCount");
  dom.statsCrossMonthMakeupCompletedHours = document.querySelector("#lessonStatsCrossMonthMakeupCompletedHours");
  dom.statsOpenCreditSourceCount = document.querySelector("#lessonStatsOpenCreditSourceCount");
  dom.statsOpenCreditHours = document.querySelector("#lessonStatsOpenCreditHours");
  dom.lessonPdfExportDialog = document.querySelector("#lessonPdfExportDialog");
  dom.lessonPdfExportError = document.querySelector("#lessonPdfExportError");
  dom.lessonPdfExportStudentSelect = document.querySelector("#lessonPdfExportStudentSelect");
  dom.lessonPdfExportModeSelect = document.querySelector("#lessonPdfExportModeSelect");
  dom.lessonPdfExportSummary = document.querySelector("#lessonPdfExportSummary");
  dom.lessonPdfExportSubmitButton = document.querySelector("#lessonPdfExportSubmitButton");
  dom.lessonPdfExportCancelButton = document.querySelector("#lessonPdfExportCancelButton");
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
  dom.lessonBatchGenerateDialog = document.querySelector("#lessonBatchGenerateDialog");
  dom.lessonBatchGenerateError = document.querySelector("#lessonBatchGenerateError");
  dom.lessonBatchGenerateStudentSelect = document.querySelector("#lessonBatchGenerateStudentSelect");
  dom.lessonBatchGenerateBusinessEntitySelect = document.querySelector("#lessonBatchGenerateBusinessEntitySelect");
  dom.lessonBatchGenerateStartDateInput = document.querySelector("#lessonBatchGenerateStartDateInput");
  dom.lessonBatchGenerateEndDateInput = document.querySelector("#lessonBatchGenerateEndDateInput");
  dom.lessonBatchGenerateAirconRateInput = document.querySelector("#lessonBatchGenerateAirconRateInput");
  dom.lessonBatchGenerateNoteInput = document.querySelector("#lessonBatchGenerateNoteInput");
  dom.lessonBatchGenerateAddPatternButton = document.querySelector("#lessonBatchGenerateAddPatternButton");
  dom.lessonBatchGeneratePatternList = document.querySelector("#lessonBatchGeneratePatternList");
  dom.lessonBatchGenerateSummary = document.querySelector("#lessonBatchGenerateSummary");
  dom.lessonBatchGeneratePreviewEmpty = document.querySelector("#lessonBatchGeneratePreviewEmpty");
  dom.lessonBatchGeneratePreviewRows = document.querySelector("#lessonBatchGeneratePreviewRows");
  dom.lessonBatchGeneratePreviewButton = document.querySelector("#lessonBatchGeneratePreviewButton");
  dom.lessonBatchGenerateRegenerateButton = document.querySelector("#lessonBatchGenerateRegenerateButton");
  dom.lessonBatchGenerateSubmitButton = document.querySelector("#lessonBatchGenerateSubmitButton");
  dom.lessonBatchGenerateViewMonthButton = document.querySelector("#lessonBatchGenerateViewMonthButton");
  dom.lessonBatchGenerateViewFirstDetailButton = document.querySelector("#lessonBatchGenerateViewFirstDetailButton");
  dom.lessonBatchGenerateCloseButton = document.querySelector("#lessonBatchGenerateCloseButton");
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
  dom.createPlannedLessonDeliveryModeSelect = document.querySelector("#createPlannedLessonDeliveryModeSelect");
  dom.createPlannedLessonVenueField = document.querySelector("#createPlannedLessonVenueField");
  dom.createPlannedLessonVenueSelect = document.querySelector("#createPlannedLessonVenueSelect");
  dom.createPlannedLessonOnlinePlatformField = document.querySelector("#createPlannedLessonOnlinePlatformField");
  dom.createPlannedLessonOnlinePlatformInput = document.querySelector("#createPlannedLessonOnlinePlatformInput");
  dom.createPlannedLessonDurationInput = document.querySelector("#createPlannedLessonDurationInput");
  dom.createPlannedLessonUnitPriceInput = document.querySelector("#createPlannedLessonUnitPriceInput");
  dom.createPlannedLessonFeeInput = document.querySelector("#createPlannedLessonFeeInput");
  dom.createPlannedLessonAirconRateInput = document.querySelector("#createPlannedLessonAirconRateInput");
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
  dom.createActualLessonPartialInput = document.querySelector("#createActualLessonPartialInput");
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
  dom.createMakeupActualLessonTeacherSelect = document.querySelector("#createMakeupActualLessonTeacherSelect");
  dom.createMakeupActualLessonSubjectSelect = document.querySelector("#createMakeupActualLessonSubjectSelect");
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
  dom.createCrossMonthMakeupActualTeacherSelect = document.querySelector("#createCrossMonthMakeupActualTeacherSelect");
  dom.createCrossMonthMakeupActualSubjectSelect = document.querySelector("#createCrossMonthMakeupActualSubjectSelect");
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
    restoreFilterSelections({
      ...defaultLessonFilters(),
      view: activeView,
    });
    invalidateLessonResultsForFilterChange("已重置筛选条件；点击“查询”后刷新结果。");
  });

  [dom.yearFilter, dom.monthFilter].forEach((select) => {
    select?.addEventListener("change", () => {
      const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
      renderWeekFilterOptions(month, dom.weekFilter?.value);
      invalidateLessonResultsForFilterChange();
    });
  });
  [
    dom.weekFilter,
    dom.studentSelect,
    dom.teacherSelect,
    dom.subjectSelect,
    dom.businessEntitySelect,
    dom.lessonTypeSelect,
    dom.statusSelect,
    dom.billableSelect,
  ].forEach((select) => {
    select?.addEventListener("change", () => invalidateLessonResultsForFilterChange());
  });
  dom.keywordInput?.addEventListener("input", () => invalidateLessonResultsForFilterChange());
  dom.openWeeklyScheduleForStudentButton?.addEventListener("click", openWeeklyScheduleForSelectedStudent);

  [dom.listViewButton, dom.pairViewButton].forEach((button) => {
    button?.addEventListener("click", () => {
      setActiveView(button.dataset.lessonView || "list");
      applyCurrentFilters();
    });
  });

  dom.openLessonImportPreviewButton?.addEventListener("click", openLessonImportPreviewDialog);
  dom.openLessonPdfExportButton?.addEventListener("click", openLessonPdfExportDialog);
  dom.lessonPdfExportCancelButton?.addEventListener("click", () => closeLessonPdfExportDialog());
  dom.lessonPdfExportSubmitButton?.addEventListener("click", handleLessonPdfExportSubmit);
  dom.lessonPdfExportModeSelect?.addEventListener("change", renderLessonPdfExportSummary);
  dom.lessonPdfExportStudentSelect?.addEventListener("change", () => {
    clearLessonPdfExportFieldInvalid("student");
    hideLessonPdfExportErrorIfClean();
    renderLessonPdfExportSummary();
  });
  dom.lessonPdfExportDialog?.addEventListener("click", (event) => {
    if (event.target === dom.lessonPdfExportDialog) {
      closeLessonPdfExportDialog();
    }
  });
  dom.lessonImportPreviewCloseButton?.addEventListener("click", closeLessonImportPreviewDialog);
  dom.lessonImportPreviewClearButton?.addEventListener("click", clearLessonImportPreview);
  dom.lessonImportPreviewFileInput?.addEventListener("change", handleLessonImportPreviewFileChange);
  dom.lessonImportTemplateExportButton?.addEventListener("click", handleLessonImportTemplateExport);
  dom.lessonImportViewMonthButton?.addEventListener("click", handleLessonImportViewMonthClick);
  dom.lessonImportViewFirstDetailButton?.addEventListener("click", handleLessonImportViewFirstDetailClick);
  dom.openLessonBatchGenerateButton?.addEventListener("click", openLessonBatchGenerateDialog);
  dom.lessonBatchGenerateCloseButton?.addEventListener("click", closeLessonBatchGenerateDialog);
  dom.lessonBatchGeneratePreviewButton?.addEventListener("click", handleLessonBatchGeneratePreview);
  dom.lessonBatchGenerateRegenerateButton?.addEventListener("click", handleLessonBatchGenerateRegeneratePreview);
  dom.lessonBatchGenerateSubmitButton?.addEventListener("click", handleLessonBatchGenerateSubmit);
  dom.lessonBatchGenerateAddPatternButton?.addEventListener("click", addLessonBatchGeneratePattern);
  dom.lessonBatchGenerateViewMonthButton?.addEventListener("click", handleLessonBatchGenerateViewMonthClick);
  dom.lessonBatchGenerateViewFirstDetailButton?.addEventListener("click", handleLessonBatchGenerateViewFirstDetailClick);
  dom.lessonBatchGenerateDialog?.addEventListener("click", (event) => {
    if (event.target === dom.lessonBatchGenerateDialog) {
      blockLessonBatchGenerateDirectDismiss();
    }
  });
  dom.lessonBatchGeneratePatternList?.addEventListener("input", handleLessonBatchGeneratePatternInput);
  dom.lessonBatchGeneratePatternList?.addEventListener("change", handleLessonBatchGeneratePatternInput);
  dom.lessonBatchGeneratePatternList?.addEventListener("click", handleLessonBatchGeneratePatternAction);
  dom.lessonBatchGeneratePreviewRows?.addEventListener("click", handleLessonBatchGeneratePreviewAction);
  [
    ["student", dom.lessonBatchGenerateStudentSelect],
    ["businessEntity", dom.lessonBatchGenerateBusinessEntitySelect],
    ["startDate", dom.lessonBatchGenerateStartDateInput],
    ["endDate", dom.lessonBatchGenerateEndDateInput],
    ["airconRate", dom.lessonBatchGenerateAirconRateInput],
    ["note", dom.lessonBatchGenerateNoteInput],
  ].forEach(([fieldId, element]) => {
    element?.addEventListener("input", () => {
      isLessonBatchGenerateCloseConfirmPending = false;
      clearLessonBatchGenerateFieldInvalid(fieldId);
      hideLessonBatchGenerateErrorIfClean();
      if (fieldId === "note") {
        clearLessonBatchGenerateSubmitResult();
      } else {
        clearLessonBatchGeneratePreviewState();
        renderLessonBatchGeneratePreview();
      }
    });
    element?.addEventListener("change", () => {
      isLessonBatchGenerateCloseConfirmPending = false;
      clearLessonBatchGenerateFieldInvalid(fieldId);
      hideLessonBatchGenerateErrorIfClean();
      if (fieldId === "note") {
        clearLessonBatchGenerateSubmitResult();
      } else {
        clearLessonBatchGeneratePreviewState();
        renderLessonBatchGeneratePreview();
      }
    });
  });
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
    const deleteButton = event.target.closest("[data-delete-planned-lesson-id]");
    if (deleteButton) {
      lessonDeleteController?.open(deleteButton.dataset.deletePlannedLessonId || "");
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
    ["lessonDeliveryMode", dom.createPlannedLessonDeliveryModeSelect],
    ["lessonVenue", dom.createPlannedLessonVenueSelect],
    ["lessonVenue", dom.createPlannedLessonOnlinePlatformInput],
    ["durationHours", dom.createPlannedLessonDurationInput],
    ["unitPrice", dom.createPlannedLessonUnitPriceInput],
    ["lessonFee", dom.createPlannedLessonFeeInput],
    ["airconRate", dom.createPlannedLessonAirconRateInput],
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
  dom.createPlannedLessonDeliveryModeSelect?.addEventListener("change", syncCreatePlannedLessonVenueFields);

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

    const deleteButton = event.target.closest("[data-delete-planned-lesson-id]");
    if (deleteButton) {
      lessonDeleteController?.open(deleteButton.dataset.deletePlannedLessonId || "");
      return;
    }

    const editButton = event.target.closest("[data-edit-lesson-id]");
    if (editButton) {
      lessonEditController?.open(editButton.dataset.editLessonId || "");
    }
  });

  dom.createActualLessonCancelButton?.addEventListener("click", () => closeCreateActualLessonDialog());
  dom.createActualLessonSubmitButton?.addEventListener("click", handleCreateActualLessonSubmit);
  dom.createActualLessonPartialInput?.addEventListener("change", () => {
    isCreateActualLessonCloseConfirmPending = false;
    clearCreateActualLessonFieldInvalid("durationHours");
    hideCreateActualLessonErrorIfClean();
  });

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
    ["lessonContent", dom.createActualLessonContentInput],
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
    ["teacher", dom.createMakeupActualLessonTeacherSelect],
    ["subject", dom.createMakeupActualLessonSubjectSelect],
    ["isBillable", dom.createMakeupActualLessonBillableSelect],
    ["startTime", dom.createMakeupActualLessonStartTimeInput],
    ["endTime", dom.createMakeupActualLessonEndTimeInput],
    ["durationHours", dom.createMakeupActualLessonDurationInput],
    ["unitPrice", dom.createMakeupActualLessonUnitPriceInput],
    ["lessonFee", dom.createMakeupActualLessonFeeInput],
    ["lessonCount", dom.createMakeupActualLessonCountInput],
    ["lessonContent", dom.createMakeupActualLessonContentInput],
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
    ["teacher", dom.createCrossMonthMakeupActualTeacherSelect],
    ["subject", dom.createCrossMonthMakeupActualSubjectSelect],
    ["lessonDate", dom.createCrossMonthMakeupActualDateInput],
    ["startTime", dom.createCrossMonthMakeupActualStartTimeInput],
    ["endTime", dom.createCrossMonthMakeupActualEndTimeInput],
    ["durationHours", dom.createCrossMonthMakeupActualDurationInput],
    ["unitPrice", dom.createCrossMonthMakeupActualUnitPriceInput],
    ["lessonCount", dom.createCrossMonthMakeupActualCountInput],
    ["lessonContent", dom.createCrossMonthMakeupActualContentInput],
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
  filters.weekStart = normalizeStudentSettlementWeekStart(
    filters.month,
    normalizeWeekStart(params.get("week_start") || params.get("weekStart"))
  );
  filters.view = normalizeLessonView(params.get("view"));
  filters.studentId = readLessonQueryValue(params, "student_id", "studentId");
  filters.teacherId = readLessonQueryValue(params, "teacher_id", "teacherId");
  filters.subjectId = readLessonQueryValue(params, "subject_id", "subjectId");
  filters.businessEntityId = readLessonQueryValue(params, "business_entity_id", "businessEntityId");
  filters.lessonType = readLessonQueryLessonType(params);
  filters.status = normalizeLessonStatusFilter(params.get("status"));
  filters.isBillable = readLessonQueryBillable(params);
  filters.keyword = safeText(params.get("keyword")).trim();
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

function readLessonQueryLessonType(params) {
  const value = safeText(params.get("lesson_type") || params.get("lessonType"));
  return ["planned", "actual"].includes(value) ? value : "";
}

function readLessonQueryBillable(params) {
  const value = safeText(params.get("is_billable") || params.get("isBillable"));
  return ["true", "false"].includes(value) ? value : "";
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
  if (filters.lessonType) params.set("lesson_type", filters.lessonType);
  if (filters.status) params.set("status", filters.status);
  if (filters.isBillable) params.set("is_billable", filters.isBillable);
  if (filters.keyword) params.set("keyword", filters.keyword);
  if (filters.weekStart) params.set("week_start", filters.weekStart);

  return params;
}

async function loadInitialData() {
  const requestToken = beginLessonRecordsRequest();
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
    const applied = await loadLessonMonth(filters.month, filters, requestToken);
    if (!applied) return;
    restoreFilterSelections(filters);
    applyCurrentFilters();
    showLessonRecordsReadyMessage("课时管理数据已加载。");
  } catch (error) {
    if (!lessonRecordsRequestGate.isCurrent(requestToken)) return;
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
    renderLessonStats(null);
    console.error("Lesson management initial load failed", error);
    showMessage("error", lessonUserErrorMessage(error, "读取课时管理数据失败，请稍后重试。"));
  } finally {
    if (lessonRecordsRequestGate.isCurrent(requestToken)) setLoading(false);
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
    const requestToken = beginLessonRecordsRequest();
    setLoading(true);
    showMessage("info", "正在加载课时记录...");

    try {
      const applied = await loadLessonMonth(filters.month, filters, requestToken);
      if (!applied) return;
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showLessonRecordsReadyMessage("课时记录已加载。");
    } catch (error) {
      if (!lessonRecordsRequestGate.isCurrent(requestToken)) return;
      lessonRecords = [];
      crossMonthMakeupReferences = emptyCrossMonthMakeupReferences();
      loadedMonth = "";
      renderDataOptions([]);
      renderLessonRecords([]);
      console.error("Lesson records load failed", error);
      showMessage("error", lessonUserErrorMessage(error, "读取课时记录失败，请稍后重试。"));
    } finally {
      if (lessonRecordsRequestGate.isCurrent(requestToken)) setLoading(false);
    }
    return;
  }

  applyCurrentFilters();
  showLessonRecordsReadyMessage("课时记录已加载。");
}

function showLessonRecordsReadyMessage(successMessage) {
  if (lessonRecords.some((record) => record.tuition_history_state_available === false)) {
    showMessage("warning", TUITION_HISTORY_STATE_WARNING);
    return;
  }
  showMessage("success", successMessage);
}

function beginLessonRecordsRequest() {
  const requestToken = lessonRecordsRequestGate.begin();
  lessonStatsRequestId += 1;
  lessonRecords = [];
  rejectedLessonRecords = [];
  crossMonthMakeupReferences = emptyCrossMonthMakeupReferences();
  loadedMonth = "";
  loadedLessonRecordMode = "";
  renderLessonRecords([]);
  renderLessonStats(null);
  return requestToken;
}

function invalidateLessonResultsForFilterChange(
  message = "筛选条件已变化；点击“查询”后显示新结果。"
) {
  beginLessonRecordsRequest();
  renderLessonRecords([], { emptyMessage: "筛选条件已变化，请点击“查询”显示结果。" });
  showMessage("info", message);
}

async function loadLessonMonth(month, filters = {}, requestToken) {
  const queryMode = lessonRecordQueryMode(filters);
  try {
    const validation = partitionAuthoritativeLessonRecords(
      await fetchLessonRecords(month, {
        status: filters.status,
        weekStart: filters.weekStart || "",
      }),
      { yearMonth: month, weekStart: filters.weekStart || "" }
    );
    const records = sortLessonRecords(validation.accepted);
    const rawReferences = await fetchCrossMonthMakeupReferences(month, records);
    const references = buildCrossMonthMakeupReferenceMaps({
      sourceMonthActuals: validateUniqueLessonRecordIds(
        rawReferences.sourceMonthActuals || [],
        "跨月补课实际课时读取结果"
      ),
      targetMonthSources: validateUniqueLessonRecordIds(
        rawReferences.targetMonthSources || [],
        "跨月补课来源课时读取结果"
      ),
    });
    if (!lessonRecordsRequestGate.isCurrent(requestToken)) return false;
    lessonRecords = records;
    rejectedLessonRecords = validation.rejected;
    crossMonthMakeupReferences = references;
  } catch (error) {
    if (!lessonRecordsRequestGate.isCurrent(requestToken)) return false;
    throw error;
  }
  loadedMonth = month;
  loadedLessonRecordMode = queryMode;
  renderDataOptions(lessonRecords);
  return true;
}

function lessonRecordQueryMode(filters = {}) {
  return `${filters.status === "voided" ? "voided" : "active"}:${filters.weekStart || "month"}`;
}

function normalizeWeekStart(value) {
  const text = safeText(value);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return "";
  const date = new Date(`${text}T00:00:00`);
  if (Number.isNaN(date.getTime()) || date.getDay() !== 1) return "";
  return text;
}

function renderWeekFilterOptions(yearMonth, selectedWeekStart = "") {
  if (!dom.weekFilter) return;
  const options = ['<option value="">整月</option>'];
  for (const week of listStudentSettlementMonthWeeks(yearMonth)) {
    options.push(`<option value="${escapeAttribute(week.weekStart)}">${escapeHtml(`${formatMonthDayValue(week.weekStart)} – ${formatMonthDayValue(week.weekEnd)}`)}</option>`);
  }
  dom.weekFilter.innerHTML = options.join("");
  dom.weekFilter.value = normalizeStudentSettlementWeekStart(yearMonth, selectedWeekStart);
}

function formatMonthDayValue(value) {
  return `${value.slice(5, 7)}/${value.slice(8, 10)}`;
}

function updateWeeklyScheduleButton(filters = readFilters()) {
  if (!dom.openWeeklyScheduleForStudentButton) return;
  const canOpen = Boolean(filters?.weekStart && filters?.studentId);
  dom.openWeeklyScheduleForStudentButton.disabled = !canOpen;
  dom.openWeeklyScheduleForStudentButton.title = canOpen ? "打开该学生本周周课表" : "请先选择一周和一位学生";
}

function openWeeklyScheduleForSelectedStudent() {
  const filters = readFilters();
  if (!filters?.weekStart || !filters.studentId) {
    showMessage("error", "请先选择一周和一位学生，再生成周课表。");
    return;
  }
  const params = new URLSearchParams({
    week_start: filters.weekStart,
    student_id: filters.studentId,
    auto_preview: "1",
  });
  window.location.href = `./weekly-schedule-image.html?${params.toString()}`;
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
  refreshLessonManagementStats(filters);
}

async function refreshLessonManagementStats(filters, options = {}) {
  const requestId = ++lessonStatsRequestId;
  renderLessonStats(null, { loading: true });

  try {
    const [stats, creditSummary] = await Promise.all([
      fetchLessonManagementStats(filters),
      fetchLessonCreditSummary(filters),
    ]);
    if (requestId !== lessonStatsRequestId) {
      return;
    }
    renderLessonStats(stats || {}, { creditSummary: creditSummary || {} });
  } catch (error) {
    if (requestId !== lessonStatsRequestId) {
      return;
    }
    renderLessonStats(null);
    if (options.propagateError) {
      throw error;
    }
    console.error("Lesson statistics load failed", error);
    showMessage("error", lessonUserErrorMessage(error, "读取课时统计失败，请稍后重试。"));
  }
}

function renderLessonStats(stats, options = {}) {
  const loadingText = options.loading ? "..." : "-";
  const values = stats || {};
  setText(dom.statsPlannedHours, stats ? displayValue(values.planned_hours) : loadingText);
  setText(dom.statsActualHours, stats ? displayValue(values.actual_hours) : loadingText);
  setText(dom.statsPlannedFee, stats ? formatCurrency(values.planned_fee_jpy, "JPY") : loadingText);
  setText(dom.statsActualFee, stats ? formatCurrency(values.actual_fee_jpy, "JPY") : loadingText);
  setText(dom.statsCrossMonthMakeupCompletedCount, stats ? displayValue(values.cross_month_makeup_completed_count) : loadingText);
  setText(dom.statsCrossMonthMakeupCompletedHours, stats ? displayValue(values.cross_month_makeup_completed_hours) : loadingText);
  const credit = options.creditSummary || {};
  setText(dom.statsOpenCreditSourceCount, stats ? displayValue(credit.open_source_count) : loadingText);
  setText(dom.statsOpenCreditHours, stats ? `${displayValue(credit.open_credit_hours)} 小时` : loadingText);
}

function setText(element, value) {
  if (element) {
    element.textContent = value;
  }
}

function readFilters() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    showMessage("error", "请选择正确的年月。");
    return null;
  }

  const rawWeekStart = normalizeWeekStart(dom.weekFilter?.value);
  const weekStart = normalizeStudentSettlementWeekStart(month, rawWeekStart);
  if (rawWeekStart && !weekStart) {
    showMessage("error", "所选自然周不属于当前学生结算月，请重新选择。");
    return null;
  }

  return {
    month,
    weekStart,
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
  const weekStart = normalizeStudentSettlementWeekStart(filters.month, filters.weekStart);
  renderWeekFilterOptions(filters.month, weekStart);
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
  updateWeeklyScheduleButton({ ...filters, weekStart });
}

function renderMasterOptions() {
  renderEntityOptions(dom.studentSelect, students, studentName);
  renderEntityOptions(dom.teacherSelect, teachers, teacherName);
  renderEntityOptions(dom.subjectSelect, subjects, subjectName);
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
}

function renderDataOptions(records) {
  renderValueOptions(dom.lessonTypeSelect, ["planned", "actual"], lessonTypeLabel);
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
  if (isDialogOpen(dom.lessonBatchGenerateDialog)) {
    return { blockDirectDismiss: blockLessonBatchGenerateDirectDismiss };
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

function blockLessonBatchGenerateDirectDismiss() {
  if (!isDialogOpen(dom.lessonBatchGenerateDialog) || isLessonBatchGenerateSubmitting) {
    return;
  }
  showLessonBatchGenerateError("请使用关闭按钮关闭窗口；表单已有修改时需要二次确认。");
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
    students.filter(isNewBusinessStudent),
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
    newBusinessEntities(businessEntities),
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
  const defaultBusinessEntityId = defaultNewBusinessEntityId(businessEntities);
  dom.createPlannedLessonBusinessEntitySelect.value = isNewBusinessEntityId(businessEntities, dom.businessEntitySelect.value)
    ? dom.businessEntitySelect.value
    : defaultBusinessEntityId;
  if (!students.some((student) => student.id === dom.createPlannedLessonStudentSelect.value && isNewBusinessStudent(student))) {
    dom.createPlannedLessonStudentSelect.value = "";
  }
  dom.createPlannedLessonStartTimeInput.value = "";
  dom.createPlannedLessonEndTimeInput.value = "";
  dom.createPlannedLessonDeliveryModeSelect.value = "";
  dom.createPlannedLessonVenueSelect.value = "";
  dom.createPlannedLessonOnlinePlatformInput.value = "";
  dom.createPlannedLessonDurationInput.value = "";
  dom.createPlannedLessonUnitPriceInput.value = "0";
  dom.createPlannedLessonFeeInput.value = "";
  dom.createPlannedLessonAirconRateInput.value = "0";
  dom.createPlannedLessonCountInput.value = "";
  dom.createPlannedLessonContentInput.value = "";
  dom.createPlannedLessonNoteInput.value = "";
  syncCreatePlannedLessonVenueFields();
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
    lessonDeliveryMode: dom.createPlannedLessonDeliveryModeSelect.value,
    onsiteVenue: dom.createPlannedLessonVenueSelect.value,
    onlinePlatform: dom.createPlannedLessonOnlinePlatformInput.value,
    durationHours: dom.createPlannedLessonDurationInput.value,
    unitPrice: dom.createPlannedLessonUnitPriceInput.value,
    lessonFee: dom.createPlannedLessonFeeInput.value,
    airconRate: dom.createPlannedLessonAirconRateInput.value,
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
    const filtersBeforeSubmit = readFilters();
    const createdLesson = await createPlannedLessonRecord(payload);
    closeCreatePlannedLessonDialog(true);
    await refreshAfterCreatePlannedLesson(createdLesson, filtersBeforeSubmit);
    showMessage("success", `预定课时已新增：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    console.error("Planned lesson creation failed", error);
    const message = lessonUserErrorMessage(error, "预定课时新增失败，请稍后重试。");
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
  const lessonDeliveryMode = dom.createPlannedLessonDeliveryModeSelect.value;
  const lessonVenue = lessonDeliveryMode === "onsite"
    ? dom.createPlannedLessonVenueSelect.value
    : lessonDeliveryMode === "online"
      ? dom.createPlannedLessonOnlinePlatformInput.value.trim()
      : "";
  const durationHours = numberFromInput(dom.createPlannedLessonDurationInput.value);
  const unitPrice = numberFromInput(dom.createPlannedLessonUnitPriceInput.value);
  const lessonFee = null;
  const airconRateJpyPerHour = numberFromInput(dom.createPlannedLessonAirconRateInput.value);
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
  if (lessonVenue && !lessonDeliveryMode) invalidFields.push("lessonDeliveryMode", "lessonVenue");
  if (lessonDeliveryMode === "onsite" && !lessonVenue) invalidFields.push("lessonVenue");
  if (lessonDeliveryMode === "onsite" && !FIXED_ONSITE_LESSON_VENUES.includes(lessonVenue)) invalidFields.push("lessonVenue");
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
  if (!Number.isInteger(airconRateJpyPerHour) || airconRateJpyPerHour < 0) invalidFields.push("airconRate");
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
    lessonDeliveryMode,
    lessonVenue,
    durationHours,
    unitPrice,
    lessonFee,
    airconRateJpyPerHour,
    lessonCount,
    lessonContent: dom.createPlannedLessonContentInput.value.trim(),
    note: dom.createPlannedLessonNoteInput.value.trim(),
  };
}

async function refreshAfterCreatePlannedLesson(createdLesson, previousFilters = null) {
  await refreshLessonMonthPreservingFilters(previousFilters?.month, previousFilters);
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
  dom.createPlannedLessonError.textContent = lessonUserErrorMessage(message);
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
  if (text.includes("授课方式")) fields.push("lessonDeliveryMode");
  if (text.includes("场地") || text.includes("平台")) fields.push("lessonVenue");
  if (text.includes("时长")) fields.push("durationHours");
  if (text.includes("单价")) fields.push("unitPrice");
  if (text.includes("课时费") || text.includes("金额")) fields.push("lessonFee");
  if (text.includes("空调") || text.includes("AIRCON")) fields.push("airconRate");
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

function syncCreatePlannedLessonVenueFields() {
  const mode = dom.createPlannedLessonDeliveryModeSelect?.value || "";
  const isOnsite = mode === "onsite";
  const isOnline = mode === "online";
  dom.createPlannedLessonVenueField?.classList.toggle("is-hidden", !isOnsite);
  dom.createPlannedLessonOnlinePlatformField?.classList.toggle("is-hidden", !isOnline);
  if (dom.createPlannedLessonVenueSelect) dom.createPlannedLessonVenueSelect.disabled = !isOnsite;
  if (dom.createPlannedLessonOnlinePlatformInput) dom.createPlannedLessonOnlinePlatformInput.disabled = !isOnline;
}

function updateCreatePlannedLessonFeePreview() {
  dom.createPlannedLessonFeeInput.value = "";
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

  if (plannedLesson.status !== "planned") {
    showMessage("error", "当前 planned 状态不能生成 completed actual。");
    return;
  }

  if (isVoidedPlanned(plannedLesson)) {
    showMessage("error", "该预定课时已作废，不能生成 actual。");
    return;
  }

  const venueMigrationReason = fixedOnsiteVenueMigrationReason(plannedLesson);
  if (venueMigrationReason) {
    showMessage("error", venueMigrationReason);
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
  dom.createActualLessonPartialInput.checked = false;
  dom.createActualLessonUnitPriceInput.value = displayInputNumber(plannedLesson.unit_price || 0);
  dom.createActualLessonFeeInput.value = displayInputNumber(plannedLesson.lesson_fee || 0);
  dom.createActualLessonCountInput.value = plannedLesson.lesson_count ? String(plannedLesson.lesson_count) : "";
  dom.createActualLessonContentInput.value = safeText(plannedLesson.lesson_content);
  dom.createActualLessonNoteInput.value = safeText(plannedLesson.note);
  isCreateActualLessonCloseConfirmPending = false;
  createActualLessonInitialSnapshot = readCreateActualLessonFormSnapshot();
}

function readCreateActualLessonFormSnapshot() {
  return JSON.stringify({
    lessonDate: dom.createActualLessonDateInput.value,
    startTime: dom.createActualLessonStartTimeInput.value,
    endTime: dom.createActualLessonEndTimeInput.value,
    durationHours: dom.createActualLessonDurationInput.value,
    partial: dom.createActualLessonPartialInput.checked,
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
    ["授课方式 / 场地", formatLessonVenue(plannedLesson.lesson_delivery_mode, plannedLesson.lesson_venue)],
    ["预计上课日期", formatDateOnly(plannedLesson.lesson_date)],
    ["收费归属月", formatMonth(authoritativeStudentMonth(plannedLesson))],
    ["收费自然周", formatBillingWeekRange(plannedLesson.billing_week_start_date)],
    ["计划时长", `${displayValue(plannedLesson.duration_hours)} 小时`],
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
  const filtersBeforeSubmit = readFilters();
  let createdLesson;
  try {
    createdLesson = payload.partial
      ? await createPartialCompletedActualFromPlanned(payload)
      : await createActualLessonFromPlanned(payload);
  } catch (error) {
    console.error("Actual lesson generation failed", error);
    const message = lessonUserErrorMessage(error, "实际课时生成失败，请稍后重试。");
    showCreateActualLessonError(message, createActualLessonFieldIdsForError(message));
    setCreateActualLessonSubmitting(false);
    return;
  }

  closeCreateActualLessonDialog(true);
  try {
    await refreshAfterCreateActualLesson(createdLesson, filtersBeforeSubmit);
    showMessage("success", `实际课时已生成：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    console.error("Actual lesson generation refresh failed", error);
    showMessage("error", "实际课时已生成，但列表刷新失败，请重新查询。");
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
  const lessonFee = null;
  const lessonCount = nullableIntegerFromInput(dom.createActualLessonCountInput.value);
  const lessonContent = dom.createActualLessonContentInput.value.trim();
  const invalidFields = [];

  if (!lessonDate || Number.isNaN(new Date(`${lessonDate}T00:00:00`).getTime())) invalidFields.push("lessonDate");
  if (!startTime || !isTimeValue(startTime)) invalidFields.push("startTime");
  if (!endTime || !isTimeValue(endTime)) invalidFields.push("endTime");
  if (!lessonContent) invalidFields.push("lessonContent");
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
  const durationFlow = validateActualDurationForFlow({
    actualDurationHours: durationHours,
    plannedDurationHours: currentActualSourceLesson.duration_hours,
    isPartial: dom.createActualLessonPartialInput.checked,
  });
  if (!durationFlow.valid) {
    invalidFields.push("durationHours");
    if (!validationMessage) {
      validationMessage = durationFlow.message;
    }
  }
  if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
  if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

  if (invalidFields.length) {
    showCreateActualLessonError(validationMessage || "开始时间、结束时间和内容为必填项；请检查实际课时表单中的数字格式。", invalidFields);
    return null;
  }

  return {
    plannedLessonId: currentActualSourceLesson.id,
    lessonDate,
    startTime,
    endTime,
    durationHours,
    partial: dom.createActualLessonPartialInput.checked,
    unitPrice,
    lessonFee,
    lessonCount,
    lessonContent,
    note: dom.createActualLessonNoteInput.value.trim(),
  };
}

async function refreshAfterCreateActualLesson(_createdLesson, previousFilters = null) {
  await refreshLessonMonthPreservingFilters(previousFilters?.month, previousFilters);
}

async function refreshAfterVoidLesson(result, sourceLesson) {
  const filters = readFilters() || { month: loadedMonth, status: "" };
  await refreshLessonMonthPreservingFilters(filters.month, filters);
  showMessage("success", `预定课时已作废：${shortId(result?.lesson_id || result?.id || sourceLesson?.id)}`);
}

async function refreshAfterDeleteLesson(result, sourceLesson) {
  const filters = readFilters() || { month: loadedMonth, status: "" };
  await refreshLessonMonthPreservingFilters(filters.month, filters);
  showMessage("success", `预定课时已删除：${shortId(result?.lesson_id || result?.id || sourceLesson?.id)}`);
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
  dom.createActualLessonError.textContent = lessonUserErrorMessage(message);
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
  if (text.includes("内容")) fields.push("lessonContent");
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
  dom.createActualLessonFeeInput.value = "";
}

function currentUserCanMarkLessonCancelled() {
  const membership = getCurrentAuthContext()?.membership;
  return Boolean(
    membership?.is_active === true
    && ["admin", "operator"].includes(membership.role)
  );
}

function linkedActualForPlannedLesson(plannedLessonId) {
  return lessonRecords.find((record) => (
    record.lesson_type === "actual"
    && record.planned_lesson_id === plannedLessonId
  ));
}

function cancelledActualLessonUserErrorMessage(error, fallback = "标记取消失败，请稍后重试。") {
  const errorText = [error?.message, error?.details, error?.hint, error?.code, error]
    .filter((value) => typeof value === "string")
    .join(" ");
  for (const [code, message] of CANCELLED_ACTUAL_LESSON_ERROR_MESSAGES) {
    if (errorText.includes(code)) {
      return message;
    }
  }
  return lessonUserErrorMessage(error, fallback);
}

function cancelledActualActionButton(plannedLessonId) {
  return Array.from(dom.pairRows?.querySelectorAll("[data-generate-cancelled-actual-id]") || [])
    .find((button) => button.dataset.generateCancelledActualId === plannedLessonId) || null;
}

function clearCreateCancelledActualLessonActionError(plannedLessonId) {
  cancelledActualActionButton(plannedLessonId)
    ?.closest(".lesson-pair-placeholder")
    ?.querySelector("[data-cancelled-actual-action-error]")
    ?.remove();
}

function showCreateCancelledActualLessonActionError(plannedLessonId, message) {
  const placeholder = cancelledActualActionButton(plannedLessonId)?.closest(".lesson-pair-placeholder");
  if (!placeholder) {
    showMessage("error", message);
    return;
  }
  let errorElement = placeholder.querySelector("[data-cancelled-actual-action-error]");
  if (!errorElement) {
    errorElement = document.createElement("div");
    errorElement.className = "message message-error";
    errorElement.dataset.cancelledActualActionError = "true";
    errorElement.setAttribute("role", "alert");
    placeholder.append(errorElement);
  }
  errorElement.textContent = message;
  errorElement.scrollIntoView({ block: "nearest" });
}

function openCreateCancelledActualLessonDialog(plannedLessonId) {
  clearCreateCancelledActualLessonActionError(plannedLessonId);
  if (!hasSupabaseConfig()) {
    showCreateCancelledActualLessonActionError(plannedLessonId, "当前服务配置不可用，不能标记取消。");
    return;
  }

  const plannedLesson = lessonRecords.find((record) => record.id === plannedLessonId);
  if (!plannedLesson || plannedLesson.lesson_type !== "planned") {
    showCreateCancelledActualLessonActionError(plannedLessonId, "未找到可标记取消的预定课时，请刷新后重试。");
    return;
  }

  if (!currentUserCanMarkLessonCancelled()) {
    showCreateCancelledActualLessonActionError(plannedLessonId, "仅管理员或操作员可以标记取消并转待补课。");
    return;
  }

  if (linkedActualForPlannedLesson(plannedLesson.id)) {
    showCreateCancelledActualLessonActionError(plannedLessonId, "该预定课时已有关联实际课时，不能重复标记取消。");
    return;
  }

  if (plannedLesson.status !== "planned") {
    showCreateCancelledActualLessonActionError(plannedLessonId, "仅待上课状态可以标记取消并转待补课。");
    return;
  }

  if (isVoidedPlanned(plannedLesson)) {
    showCreateCancelledActualLessonActionError(plannedLessonId, "该预定课时已作废，不能标记取消。");
    return;
  }

  const venueMigrationReason = fixedOnsiteVenueMigrationReason(plannedLesson);
  if (venueMigrationReason) {
    showCreateCancelledActualLessonActionError(plannedLessonId, venueMigrationReason);
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
    ["授课方式 / 场地", formatLessonVenue(plannedLesson.lesson_delivery_mode, plannedLesson.lesson_venue)],
    ["收费归属月", formatMonth(authoritativeStudentMonth(plannedLesson))],
    ["收费自然周", formatBillingWeekRange(plannedLesson.billing_week_start_date)],
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
  const filtersBeforeSubmit = readFilters();
  let createdLesson;
  try {
    createdLesson = await createCancelledActualLessonFromPlanned(payload);
  } catch (error) {
    console.error("Cancelled actual lesson generation failed", error);
    const message = cancelledActualLessonUserErrorMessage(error);
    showCreateCancelledActualLessonError(message, createCancelledActualLessonFieldIdsForError(message));
    setCreateCancelledActualLessonSubmitting(false);
    return;
  }

  closeCreateCancelledActualLessonDialog(true);
  try {
    await refreshAfterCreateCancelledActualLesson(createdLesson, filtersBeforeSubmit);
    showMessage("success", `取消课时已生成：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    console.error("Cancelled actual lesson refresh failed", error);
    showMessage("error", "取消课时已生成，但列表刷新失败，请重新查询。");
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

async function refreshAfterCreateCancelledActualLesson(_createdLesson, previousFilters = null) {
  await refreshLessonMonthPreservingFilters(previousFilters?.month, previousFilters);
}

function setCreateCancelledActualLessonSubmitting(isSubmitting) {
  isCreateCancelledActualLessonSubmitting = isSubmitting;
  dom.createCancelledActualLessonSubmitButton.disabled = isSubmitting;
  dom.createCancelledActualLessonCancelButton.disabled = isSubmitting;
  dom.openCreatePlannedLessonButton.disabled = isSubmitting;
  dom.createCancelledActualLessonSubmitButton.textContent = isSubmitting
    ? "处理中..."
    : "确认标记取消并转待补课";
}

function clearCreateCancelledActualLessonErrors() {
  dom.createCancelledActualLessonError.textContent = "";
  dom.createCancelledActualLessonError.classList.add("is-hidden");
  for (const fieldId of CREATE_CANCELLED_ACTUAL_LESSON_FIELD_IDS) {
    clearCreateCancelledActualLessonFieldInvalid(fieldId);
  }
}

function showCreateCancelledActualLessonError(message, fieldIds = []) {
  dom.createCancelledActualLessonError.textContent = cancelledActualLessonUserErrorMessage(message);
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

  const venueMigrationReason = fixedOnsiteVenueMigrationReason(plannedLesson);
  if (venueMigrationReason) {
    showMessage("error", venueMigrationReason);
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
  renderEntityOptionsWithPlaceholder(dom.createMakeupActualLessonTeacherSelect, teachers, teacherName, "请选择老师");
  renderEntityOptionsWithPlaceholder(dom.createMakeupActualLessonSubjectSelect, subjects, subjectName, "请选择科目");
  dom.createMakeupActualLessonDateInput.value = safeText(plannedLesson.lesson_date);
  dom.createMakeupActualLessonBillableSelect.value = "false";
  dom.createMakeupActualLessonTeacherSelect.value = plannedLesson.teacher_id || "";
  dom.createMakeupActualLessonSubjectSelect.value = plannedLesson.subject_id || "";
  dom.createMakeupActualLessonStartTimeInput.value = formatInputTime(plannedLesson.start_time);
  dom.createMakeupActualLessonEndTimeInput.value = formatInputTime(plannedLesson.end_time);
  dom.createMakeupActualLessonDurationInput.value = displayInputNumber(plannedLesson.duration_hours);
  dom.createMakeupActualLessonUnitPriceInput.value = displayInputNumber(plannedLesson.unit_price || 0);
  dom.createMakeupActualLessonFeeInput.value = displayInputNumber(plannedLesson.lesson_fee || 0);
  dom.createMakeupActualLessonCountInput.value = plannedLesson.lesson_count ? String(plannedLesson.lesson_count) : "";
  dom.createMakeupActualLessonContentInput.value = safeText(plannedLesson.lesson_content);
  dom.createMakeupActualLessonNoteInput.value = safeText(plannedLesson.note);
  syncCreateMakeupActualLessonFeeMode();
  isCreateMakeupActualLessonCloseConfirmPending = false;
  createMakeupActualLessonInitialSnapshot = readCreateMakeupActualLessonFormSnapshot();
}

function readCreateMakeupActualLessonFormSnapshot() {
  return JSON.stringify({
    lessonDate: dom.createMakeupActualLessonDateInput.value,
    teacherId: dom.createMakeupActualLessonTeacherSelect.value,
    subjectId: dom.createMakeupActualLessonSubjectSelect.value,
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
    ["授课方式 / 场地", formatLessonVenue(plannedLesson.lesson_delivery_mode, plannedLesson.lesson_venue)],
    ["收费归属月", formatMonth(authoritativeStudentMonth(plannedLesson))],
    ["收费自然周", formatBillingWeekRange(plannedLesson.billing_week_start_date)],
    ["补课完成口径", "不新增学生学费；工资按本次老师、科目、日期和时长结算"],
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
  const filtersBeforeSubmit = readFilters();
  let createdLesson;
  try {
    createdLesson = await createMakeupCompletedActualLessonFromPlanned(payload);
  } catch (error) {
    console.error("Makeup actual lesson generation failed", error);
    const message = lessonUserErrorMessage(error, "补课完成生成失败，请稍后重试。");
    showCreateMakeupActualLessonError(message, createMakeupActualLessonFieldIdsForError(message));
    setCreateMakeupActualLessonSubmitting(false);
    return;
  }

  closeCreateMakeupActualLessonDialog(true);
  try {
    await refreshAfterCreateMakeupActualLesson(createdLesson, filtersBeforeSubmit);
    showMessage("success", `补课完成已生成：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    console.error("Makeup actual lesson refresh failed", error);
    showMessage("error", "实际课时已生成，但列表刷新失败，请重新查询。");
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
  const isBillable = false;
  const teacherId = dom.createMakeupActualLessonTeacherSelect.value;
  const subjectId = dom.createMakeupActualLessonSubjectSelect.value;
  const startTime = dom.createMakeupActualLessonStartTimeInput.value;
  const endTime = dom.createMakeupActualLessonEndTimeInput.value;
  const durationHours = numberFromInput(dom.createMakeupActualLessonDurationInput.value);
  const unitPrice = numberFromInput(dom.createMakeupActualLessonUnitPriceInput.value);
  const lessonFee = null;
  const lessonCount = nullableIntegerFromInput(dom.createMakeupActualLessonCountInput.value);
  const lessonContent = dom.createMakeupActualLessonContentInput.value.trim();
  const invalidFields = [];

  if (!lessonDate || Number.isNaN(new Date(`${lessonDate}T00:00:00`).getTime())) invalidFields.push("lessonDate");
  if (!teacherId) invalidFields.push("teacher");
  if (!subjectId) invalidFields.push("subject");
  if (!startTime || !isTimeValue(startTime)) invalidFields.push("startTime");
  if (!endTime || !isTimeValue(endTime)) invalidFields.push("endTime");
  if (!lessonContent) invalidFields.push("lessonContent");
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
    showCreateMakeupActualLessonError(validationMessage || "开始时间、结束时间和内容为必填项；请检查补课完成表单中的数字格式。", invalidFields);
    return null;
  }

  return {
    plannedLessonId: currentMakeupActualSourceLesson.id,
    lessonDate,
    teacherId,
    subjectId,
    startTime,
    endTime,
    durationHours,
    unitPrice,
    lessonFee,
    isBillable,
    lessonCount,
    lessonContent,
    note: dom.createMakeupActualLessonNoteInput.value.trim(),
  };
}

async function refreshAfterCreateMakeupActualLesson(_createdLesson, previousFilters = null) {
  await refreshLessonMonthPreservingFilters(previousFilters?.month, previousFilters);
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
  dom.createMakeupActualLessonError.textContent = lessonUserErrorMessage(message);
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
  if (text.includes("老师")) fields.push("teacher");
  if (text.includes("科目")) fields.push("subject");
  if (text.includes("开始时间")) fields.push("startTime");
  if (text.includes("结束时间")) fields.push("endTime");
  if (text.includes("时长")) fields.push("durationHours");
  if (text.includes("单价")) fields.push("unitPrice");
  if (text.includes("课时费") || text.includes("金额")) fields.push("lessonFee");
  if (text.includes("回数")) fields.push("lessonCount");
  if (text.includes("内容")) fields.push("lessonContent");
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
  syncCreateMakeupActualLessonFeeMode();
  updateCreateMakeupActualLessonFeePreview();
}

function syncCreateMakeupActualLessonFeeMode() {
  const isBillable = dom.createMakeupActualLessonBillableSelect.value !== "false";
  dom.createMakeupActualLessonFeeInput.readOnly = true;
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

  dom.createMakeupActualLessonFeeInput.value = "";
}

function openCreateCrossMonthMakeupActualDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能登记待补课完成。");
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
  renderEntityOptionsWithPlaceholder(dom.createCrossMonthMakeupActualTeacherSelect, teachers, teacherName, "请选择老师");
  renderEntityOptionsWithPlaceholder(dom.createCrossMonthMakeupActualSubjectSelect, subjects, subjectName, "请选择科目");
  const defaultFromMonth = addMonthsToYearMonth(targetMonth, -3) || targetMonth;
  setYearMonthSelectValue(dom.crossMonthMakeupSourceFromYearSelect, dom.crossMonthMakeupSourceFromMonthSelect, defaultFromMonth);
  setYearMonthSelectValue(dom.crossMonthMakeupSourceToYearSelect, dom.crossMonthMakeupSourceToMonthSelect, targetMonth);
  dom.crossMonthMakeupSourceSelect.value = "";
  dom.createCrossMonthMakeupActualDateInput.value = firstDateOfMonth(targetMonth);
  dom.createCrossMonthMakeupActualTeacherSelect.value = "";
  dom.createCrossMonthMakeupActualSubjectSelect.value = "";
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
  if (toMonth && targetMonth && toMonth > targetMonth) invalidFields.push("sourceMonthTo");

  if (invalidFields.length) {
    crossMonthMakeupSourceLessons = [];
    currentCrossMonthMakeupSourceLesson = null;
    renderCrossMonthMakeupSourceOptions();
    renderCreateCrossMonthMakeupActualSummary();
    showCreateCrossMonthMakeupActualError("来源月份范围不能晚于当前补课月份。", invalidFields);
    return;
  }

  isCrossMonthMakeupSourceLoading = true;
  dom.crossMonthMakeupSourceRefreshButton.disabled = true;
  dom.crossMonthMakeupSourceSelect.disabled = true;
  dom.crossMonthMakeupSourceCount.textContent = "正在读取来源...";

  try {
    crossMonthMakeupSourceLessons = sortLessonRecords(await fetchOpenMakeupSourceLessons({
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
    console.error("Open makeup source load failed", error);
    showCreateCrossMonthMakeupActualError(
      lessonUserErrorMessage(error, "读取待补课来源失败，请稍后重试。")
    );
  } finally {
    isCrossMonthMakeupSourceLoading = false;
    dom.crossMonthMakeupSourceRefreshButton.disabled = false;
    dom.crossMonthMakeupSourceSelect.disabled = false;
    setCreateCrossMonthMakeupActualSubmitting(false);
  }
}

function renderCrossMonthMakeupSourceOptions() {
  const options = ['<option value="">请选择待补课来源</option>'];
  for (const lesson of crossMonthMakeupSourceLessons) {
    const label = [
      lesson.authoritative_student_month,
      formatDateOnly(lesson.lesson_date),
      formatTimeRange(lesson.start_time, lesson.end_time),
      nameById(students, lesson.student_id, studentName),
      nameById(teachers, lesson.teacher_id, teacherName),
      nameById(subjects, lesson.subject_id, subjectName),
      `剩余 ${displayInputNumber(lesson.remaining_hours)} 小时`,
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
  dom.createCrossMonthMakeupActualTeacherSelect.value = sourceLesson.teacher_id || "";
  dom.createCrossMonthMakeupActualSubjectSelect.value = sourceLesson.subject_id || "";
  dom.createCrossMonthMakeupActualStartTimeInput.value = formatInputTime(sourceLesson.start_time);
  dom.createCrossMonthMakeupActualEndTimeInput.value = formatInputTime(sourceLesson.end_time);
  dom.createCrossMonthMakeupActualDurationInput.value = displayInputNumber(
    sourceLesson.remaining_hours ?? sourceLesson.duration_hours
  );
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
    ["计费", "不新增学生学费；老师工资按本次登记老师、科目、日期和时长结算"],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");

  const source = currentCrossMonthMakeupSourceLesson;
  dom.createCrossMonthMakeupActualSourceSummary.classList.toggle("is-hidden", !source);
  dom.createCrossMonthMakeupActualSourceSummary.innerHTML = source ? [
    ["来源收费归属月", formatMonth(source.authoritative_student_month)],
    ["来源日期", formatDateOnly(source.lesson_date)],
    ["来源剩余时长", `${displayInputNumber(source.remaining_hours)} 小时`],
    ["学生", nameById(students, source.student_id, studentName)],
    ["老师", nameById(teachers, source.teacher_id, teacherName)],
    ["科目", nameById(subjects, source.subject_id, subjectName)],
    ["业务归属", nameById(businessEntities, source.business_entity_id, businessEntityName)],
    ["授课方式 / 场地", formatLessonVenue(source.lesson_delivery_mode, source.lesson_venue)],
    ["planned id", shortId(source.id)],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("") : "";
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
  const filtersBeforeSubmit = readFilters();
  let createdLesson;
  try {
    createdLesson = await createCrossMonthMakeupCompletedActualFromPlanned(payload);
  } catch (error) {
    console.error("Cross-month makeup actual generation failed", error);
    const message = lessonUserErrorMessage(error, "待补课完成登记失败，请稍后重试。");
    showCreateCrossMonthMakeupActualError(message, createCrossMonthMakeupActualFieldIdsForError(message));
    setCreateCrossMonthMakeupActualSubmitting(false);
    return;
  }

  closeCreateCrossMonthMakeupActualDialog(true);
  try {
    await refreshAfterCreateCrossMonthMakeupActual(createdLesson, filtersBeforeSubmit);
    showMessage("success", `待补课完成已登记：${shortId(createdLesson.lesson_id || createdLesson.id)}`);
  } catch (error) {
    console.error("Cross-month makeup actual refresh failed", error);
    showMessage("error", "实际课时已生成，但列表刷新失败，请重新查询。");
  } finally {
    setCreateCrossMonthMakeupActualSubmitting(false);
  }
}

function readCreateCrossMonthMakeupActualPayload() {
  const source = currentCrossMonthMakeupSourceLesson;
  const targetMonth = loadedMonth || getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  const lessonDate = dom.createCrossMonthMakeupActualDateInput.value;
  const lessonMonth = safeText(lessonDate).slice(0, 7);
  const teacherId = dom.createCrossMonthMakeupActualTeacherSelect.value;
  const subjectId = dom.createCrossMonthMakeupActualSubjectSelect.value;
  const startTime = dom.createCrossMonthMakeupActualStartTimeInput.value;
  const endTime = dom.createCrossMonthMakeupActualEndTimeInput.value;
  const durationHours = numberFromInput(dom.createCrossMonthMakeupActualDurationInput.value);
  const unitPrice = numberFromInput(dom.createCrossMonthMakeupActualUnitPriceInput.value);
  const lessonCount = nullableIntegerFromInput(dom.createCrossMonthMakeupActualCountInput.value);
  const lessonContent = dom.createCrossMonthMakeupActualContentInput.value.trim();
  const invalidFields = [];
  const crossMonthDateMessage = lessonDate && lessonMonth !== targetMonth
    ? "补课完成日期必须属于当前页面月份。若补课实际发生在其他月份，请先切换到实际发生月份，再在‘来源月份’中选择原待补课程所在月份。"
    : "";

  if (!source) invalidFields.push("sourceLesson");
  if (source && fixedOnsiteVenueMigrationReason(source)) invalidFields.push("sourceLesson");
  if (!lessonDate || Number.isNaN(new Date(`${lessonDate}T00:00:00`).getTime())) invalidFields.push("lessonDate");
  if (lessonMonth !== targetMonth) invalidFields.push("lessonDate");
  if (source?.authoritative_student_month
      && targetMonth
      && source.authoritative_student_month > targetMonth) invalidFields.push("sourceLesson");
  if (!teacherId) invalidFields.push("teacher");
  if (!subjectId) invalidFields.push("subject");
  if (!startTime || !isTimeValue(startTime)) invalidFields.push("startTime");
  if (!endTime || !isTimeValue(endTime)) invalidFields.push("endTime");
  if (!lessonContent) invalidFields.push("lessonContent");
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
    showCreateCrossMonthMakeupActualError(
      crossMonthDateMessage
        || (source && fixedOnsiteVenueMigrationReason(source))
        || validationMessage
        || "开始时间、结束时间和内容为必填项；补课完成日期必须属于当前页面月份，来源不能晚于当前月份。",
      invalidFields
    );
    return null;
  }

  return {
    plannedLessonId: source.id,
    lessonDate,
    teacherId,
    subjectId,
    startTime,
    endTime,
    durationHours,
    unitPrice,
    lessonCount,
    lessonContent,
    note: dom.createCrossMonthMakeupActualNoteInput.value.trim(),
  };
}

async function refreshAfterCreateCrossMonthMakeupActual(_createdLesson, previousFilters = null) {
  await refreshLessonMonthPreservingFilters(previousFilters?.month, previousFilters);
}

async function refreshLessonMonthPreservingFilters(targetMonth, previousFilters = null) {
  const baseFilters = previousFilters ? { ...previousFilters } : readFilters();
  if (!baseFilters?.month) {
    throw new Error("操作前筛选状态不可用");
  }
  const month = targetMonth || baseFilters.month || loadedMonth || currentYearMonth();
  const nextFilters = {
    ...defaultLessonFilters(),
    ...baseFilters,
    month,
    view: normalizeLessonView(baseFilters.view || activeView),
  };

  const requestToken = beginLessonRecordsRequest();
  setLoading(true);
  try {
    const applied = await loadLessonMonth(month, nextFilters, requestToken);
    if (!applied) return;
    restoreFilterSelections(nextFilters);
    syncLessonQueryUrl(nextFilters);
    renderLessonRecords(filterLessonRecords(lessonRecords, nextFilters));
    await refreshLessonManagementStats(nextFilters, { propagateError: true });
  } finally {
    if (lessonRecordsRequestGate.isCurrent(requestToken)) setLoading(false);
  }
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
  dom.createCrossMonthMakeupActualSubmitButton.textContent = isSubmitting ? "登记中..." : "登记待补课完成";
}

function readCreateCrossMonthMakeupActualFormSnapshot() {
  return JSON.stringify({
    sourceMonthFrom: getYearMonthSelectValue(dom.crossMonthMakeupSourceFromYearSelect, dom.crossMonthMakeupSourceFromMonthSelect),
    sourceMonthTo: getYearMonthSelectValue(dom.crossMonthMakeupSourceToYearSelect, dom.crossMonthMakeupSourceToMonthSelect),
    sourceLesson: dom.crossMonthMakeupSourceSelect.value,
    teacherId: dom.createCrossMonthMakeupActualTeacherSelect.value,
    subjectId: dom.createCrossMonthMakeupActualSubjectSelect.value,
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
  dom.createCrossMonthMakeupActualError.textContent = lessonUserErrorMessage(message);
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
  if (text.includes("老师")) fields.push("teacher");
  if (text.includes("科目")) fields.push("subject");
  if (text.includes("日期") || text.includes("月份") || text.includes("学生月度结算") || text.includes("老师工资")) fields.push("lessonDate");
  if (text.includes("开始时间")) fields.push("startTime");
  if (text.includes("结束时间")) fields.push("endTime");
  if (text.includes("时长")) fields.push("durationHours");
  if (text.includes("单价")) fields.push("unitPrice");
  if (text.includes("回数")) fields.push("lessonCount");
  if (text.includes("内容")) fields.push("lessonContent");
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

async function refreshAfterEditLesson(_updatedLesson, previousFilters = null) {
  await refreshLessonMonthPreservingFilters(previousFilters?.month, previousFilters);
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

function openLessonPdfExportDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能导出学生课时 PDF。");
    return;
  }

  renderEntityOptionsWithPlaceholder(
    dom.lessonPdfExportStudentSelect,
    students.filter(isActiveStudent),
    studentName,
    "请选择学生"
  );
  dom.lessonPdfExportStudentSelect.value = dom.studentSelect.value || "";
  dom.lessonPdfExportModeSelect.value = "actual_current";
  clearLessonPdfExportErrors();
  renderLessonPdfExportSummary();
  setLessonPdfExportSubmitting(false);
  dom.lessonPdfExportDialog.classList.remove("is-hidden");
  dom.lessonPdfExportDialog.setAttribute("aria-hidden", "false");
  dom.lessonPdfExportStudentSelect.focus();
}

function closeLessonPdfExportDialog(force = false) {
  if (isLessonPdfExportSubmitting && !force) {
    return;
  }

  dom.lessonPdfExportDialog?.classList.add("is-hidden");
  dom.lessonPdfExportDialog?.setAttribute("aria-hidden", "true");
  clearLessonPdfExportErrors();
}

function renderLessonPdfExportSummary() {
  const exportTarget = lessonPdfExportTarget();
  dom.lessonPdfExportSummary.innerHTML = [
    ["学生", nameById(students, dom.lessonPdfExportStudentSelect?.value, studentName)],
    ["导出月份", formatMonth(exportTarget.yearMonth)],
    ["导出内容", exportTarget.mode === "planned" ? "下月预定课时" : "本月实际课时"],
    ["数据来源", "DB 课时记录 + DB 统计 RPC"],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");
}

function lessonPdfExportTarget() {
  const baseMonth = loadedMonth || getYearMonthSelectValue(dom.yearFilter, dom.monthFilter) || currentYearMonth();
  const selectedMode = dom.lessonPdfExportModeSelect?.value === "planned_next" ? "planned_next" : "actual_current";
  return {
    mode: selectedMode === "planned_next" ? "planned" : "actual",
    yearMonth: selectedMode === "planned_next" ? addMonthsToYearMonth(baseMonth, 1) : baseMonth,
  };
}

async function handleLessonPdfExportSubmit() {
  if (isLessonPdfExportSubmitting) {
    return;
  }

  clearLessonPdfExportErrors();
  const studentId = dom.lessonPdfExportStudentSelect.value;
  const target = lessonPdfExportTarget();
  if (!studentId) {
    setLessonPdfExportFieldInvalid("student", true);
    showLessonPdfExportError("请选择学生。");
    return;
  }

  const printWindow = window.open("", "_blank");
  if (!printWindow) {
    showLessonPdfExportError("浏览器阻止了打印页窗口，请允许弹窗后重试。");
    return;
  }
  printWindow.document.open();
  printWindow.document.write(renderLessonPdfLoadingHtml());
  printWindow.document.close();

  setLessonPdfExportSubmitting(true);

  try {
    const exportData = await fetchStudentLessonPdfExport({
      studentId,
      yearMonth: target.yearMonth,
      mode: target.mode,
    });
    openLessonPdfPrintPage({
      studentId,
      yearMonth: target.yearMonth,
      mode: target.mode,
      rows: exportData.rows || [],
      plannedRows: exportData.plannedRows || [],
      actualRows: exportData.actualRows || [],
      stats: exportData.stats || {},
      printWindow,
    });
    closeLessonPdfExportDialog(true);
    showMessage("success", "学生课时打印页已生成，可在浏览器打印窗口保存为 PDF。");
  } catch (error) {
    if (!printWindow.closed) {
      printWindow.close();
    }
    console.error("Lesson PDF export failed", error);
    showLessonPdfExportError(lessonUserErrorMessage(error, "学生课时打印页生成失败，请稍后重试。"));
  } finally {
    setLessonPdfExportSubmitting(false);
  }
}

function openLessonPdfPrintPage({ studentId, yearMonth, mode, rows, plannedRows, actualRows, stats, printWindow }) {
  if (!printWindow) {
    throw new Error("浏览器阻止了打印页窗口，请允许弹窗后重试。");
  }

  printWindow.document.open();
  printWindow.document.write(renderLessonPdfPrintHtml({ studentId, yearMonth, mode, rows, plannedRows, actualRows, stats }));
  printWindow.document.close();
  printWindow.focus();
  printWindow.setTimeout(() => printWindow.print(), 250);
}

function renderLessonPdfLoadingHtml() {
  return `<!doctype html>
    <html lang="zh-CN">
      <head>
        <meta charset="utf-8">
        <title>生成学生课时打印页</title>
      </head>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif; padding: 24px;">
        正在读取 DB 课时记录与统计 RPC...
      </body>
    </html>`;
}

function renderLessonPdfPrintHtml({ studentId, yearMonth, mode, rows, plannedRows, actualRows, stats }) {
  const title = mode === "planned" ? "下月预定课时" : "本月实际课时";
  const studentDisplayName = nameById(students, studentId, studentName);
  const normalizedPlannedRows = Array.isArray(plannedRows)
    ? plannedRows
    : (mode === "planned" && Array.isArray(rows) ? rows : []);
  const normalizedActualRows = Array.isArray(actualRows)
    ? actualRows
    : (mode === "actual" && Array.isArray(rows) ? rows : []);
  const printedAt = new Date().toLocaleString("ja-JP");

  return `<!doctype html>
    <html lang="zh-CN">
      <head>
        <meta charset="utf-8">
        <title>${escapeHtml(studentDisplayName)} / ${escapeHtml(formatMonth(yearMonth))} / ${escapeHtml(title)}</title>
        <style>${renderLessonPdfPrintStyles()}</style>
      </head>
      <body>
        <main class="lesson-pdf-page">
          <header class="lesson-pdf-header">
            <div class="lesson-pdf-kicker">学生月度结算通知单</div>
            <h1>${escapeHtml(title)}</h1>
            <div class="lesson-pdf-meta">
              <span>${escapeHtml(studentDisplayName)}</span>
              <span>${escapeHtml(formatMonth(yearMonth))}</span>
              <span>数据来源：DB 课时记录与统计 RPC</span>
            </div>
          </header>
          ${renderLessonPdfSummaryCards(stats)}
          ${mode === "planned"
            ? renderLessonPdfPlannedSection(normalizedPlannedRows)
            : renderLessonPdfActualSection(normalizedPlannedRows, normalizedActualRows)}
          <footer class="lesson-pdf-footer">输出时间：${escapeHtml(printedAt)}</footer>
        </main>
      </body>
    </html>`;
}

function renderLessonPdfPrintStyles() {
  return `
    @page { size: A4 portrait; margin: 12mm; }
    * { box-sizing: border-box; }
    body {
      color: #172033;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", "Meiryo", sans-serif;
      font-size: 11px;
      line-height: 1.55;
      margin: 0;
      overflow-wrap: anywhere;
      word-break: normal;
    }
    .lesson-pdf-page { width: 100%; }
    .lesson-pdf-header { text-align: center; margin: 0 0 10px; }
    .lesson-pdf-kicker { color: #64748b; font-size: 11px; letter-spacing: 0; margin-bottom: 2px; }
    h1 { color: #0f172a; font-size: 20px; line-height: 1.25; margin: 0 0 5px; }
    .lesson-pdf-meta { color: #64748b; display: flex; flex-wrap: wrap; gap: 6px 12px; justify-content: center; }
    .lesson-pdf-summary {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 8px;
      margin: 10px 0 12px;
    }
    .lesson-pdf-summary-card {
      background: #f8fbff;
      border: 1px solid #cfe0f3;
      border-radius: 8px;
      padding: 8px 9px;
      min-height: 54px;
    }
    .lesson-pdf-summary-label { color: #64748b; display: block; font-size: 10px; margin-bottom: 3px; }
    .lesson-pdf-summary-value { color: #111827; display: block; font-size: 15px; font-weight: 700; line-height: 1.2; }
    .lesson-pdf-section-title {
      align-items: center;
      background: #eef6ff;
      border-left: 4px solid #3b82f6;
      color: #0f172a;
      display: flex;
      font-size: 14px;
      font-weight: 700;
      justify-content: space-between;
      margin: 12px 0 7px;
      padding: 5px 8px;
    }
    .lesson-pdf-section-count { color: #64748b; font-size: 10px; font-weight: 500; }
    .lesson-pdf-pair-head {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      gap: 9px;
      margin-bottom: 5px;
    }
    .lesson-pdf-pair-head div {
      background: #f8fafc;
      border: 1px solid #d8dee8;
      border-radius: 6px;
      color: #334155;
      font-weight: 700;
      padding: 5px 8px;
      text-align: center;
    }
    .lesson-pdf-pairs { display: grid; gap: 8px; }
    .lesson-pdf-pair {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      gap: 9px;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .lesson-pdf-card {
      background: #ffffff;
      border: 1px solid #d8dee8;
      border-radius: 8px;
      min-height: 112px;
      padding: 8px 9px;
    }
    .lesson-pdf-card.is-empty {
      align-items: center;
      background: #f8fafc;
      color: #94a3b8;
      display: flex;
      justify-content: center;
      text-align: center;
    }
    .lesson-pdf-card-main {
      align-items: baseline;
      display: flex;
      gap: 8px;
      justify-content: space-between;
      margin-bottom: 5px;
    }
    .lesson-pdf-card-date { color: #0f172a; font-size: 12px; font-weight: 700; }
    .lesson-pdf-card-subject { color: #0f172a; font-weight: 700; text-align: right; }
    .lesson-pdf-chip-row { display: flex; flex-wrap: wrap; gap: 4px; margin: 4px 0 6px; }
    .lesson-pdf-chip {
      background: #eef2ff;
      border: 1px solid #d9e0ff;
      border-radius: 999px;
      color: #334155;
      display: inline-block;
      font-size: 9.5px;
      line-height: 1.25;
      padding: 2px 6px;
      white-space: normal;
    }
    .lesson-pdf-chip.is-money { background: #eefdf4; border-color: #bbf7d0; color: #065f46; }
    .lesson-pdf-field { display: grid; grid-template-columns: 42px minmax(0, 1fr); gap: 6px; margin-top: 3px; }
    .lesson-pdf-field-label { color: #64748b; }
    .lesson-pdf-field-value { color: #1f2937; min-width: 0; }
    .lesson-pdf-empty { border: 1px dashed #cbd5e1; border-radius: 8px; color: #64748b; padding: 18px 10px; text-align: center; }
    table.lesson-pdf-planned-table {
      border-collapse: collapse;
      font-size: 10.5px;
      table-layout: fixed;
      width: 100%;
    }
    .lesson-pdf-planned-table th,
    .lesson-pdf-planned-table td {
      border: 1px solid #d8dee8;
      padding: 6px 7px;
      text-align: left;
      vertical-align: top;
    }
    .lesson-pdf-planned-table th { background: #eef6ff; color: #334155; font-weight: 700; }
    .lesson-pdf-planned-table .number { text-align: right; white-space: nowrap; }
    .lesson-pdf-planned-table .compact { color: #64748b; font-size: 9.5px; margin-top: 2px; }
    .lesson-pdf-footer { color: #94a3b8; font-size: 9px; margin-top: 12px; text-align: right; }
    @media print {
      body { print-color-adjust: exact; -webkit-print-color-adjust: exact; }
      .lesson-pdf-section-title,
      .lesson-pdf-pair-head,
      .lesson-pdf-card,
      tr { break-inside: avoid; page-break-inside: avoid; }
      h1, .lesson-pdf-section-title { break-after: avoid; page-break-after: avoid; }
    }
  `;
}

function renderLessonPdfSummaryCards(stats = {}) {
  const statRows = [
    ["预定课时", displayValue(stats.planned_hours)],
    ["实际课时", displayValue(stats.actual_hours)],
    ["预定课时费", formatCurrency(stats.planned_fee_jpy, "JPY")],
    ["实际课时费", formatCurrency(stats.actual_fee_jpy, "JPY")],
    ["完成跨月补课次数", displayValue(stats.cross_month_makeup_completed_count)],
    ["完成跨月补课课时", displayValue(stats.cross_month_makeup_completed_hours)],
  ];

  return `
    <section class="lesson-pdf-summary" aria-label="课时汇总">
      ${statRows.map(([label, value]) => `
        <div class="lesson-pdf-summary-card">
          <span class="lesson-pdf-summary-label">${escapeHtml(label)}</span>
          <span class="lesson-pdf-summary-value">${escapeHtml(value)}</span>
        </div>
      `).join("")}
    </section>
  `;
}

function renderLessonPdfActualSection(plannedRows, actualRows) {
  const pairs = buildLessonPdfPairs(plannedRows, actualRows);
  return `
    <section>
      <div class="lesson-pdf-section-title">
        <span>本月课时明细</span>
        <span class="lesson-pdf-section-count">${escapeHtml(String(actualRows.length))} 条实际课时</span>
      </div>
      <div class="lesson-pdf-pair-head" aria-hidden="true">
        <div>预定课时</div>
        <div>实际课时</div>
      </div>
      ${pairs.length ? `
        <div class="lesson-pdf-pairs">
          ${pairs.map(({ planned, actual }) => `
            <div class="lesson-pdf-pair">
              ${planned ? renderLessonPdfLessonCard(planned) : renderLessonPdfEmptyCard("未关联同月预定课时")}
              ${actual ? renderLessonPdfLessonCard(actual) : renderLessonPdfEmptyCard("尚未登记实际课时")}
            </div>
          `).join("")}
        </div>
      ` : '<div class="lesson-pdf-empty">暂无本月实际课时。</div>'}
    </section>
  `;
}

function renderLessonPdfPlannedSection(plannedRows) {
  return `
    <section>
      <div class="lesson-pdf-section-title">
        <span>下月预定课时</span>
        <span class="lesson-pdf-section-count">${escapeHtml(String(plannedRows.length))} 条预定课时</span>
      </div>
      ${plannedRows.length ? renderLessonPdfPlannedTable(plannedRows) : '<div class="lesson-pdf-empty">没有下月预定课时。</div>'}
    </section>
  `;
}

function buildLessonPdfPairs(plannedRows, actualRows) {
  const plannedById = new Map();
  for (const row of plannedRows) {
    if (row?.id) {
      plannedById.set(row.id, row);
    }
  }

  const actualByPlannedId = new Map();
  const unlinkedActuals = [];
  for (const actual of actualRows) {
    const plannedId = actual?.planned_lesson_id;
    if (plannedId && plannedById.has(plannedId)) {
      if (!actualByPlannedId.has(plannedId)) {
        actualByPlannedId.set(plannedId, []);
      }
      actualByPlannedId.get(plannedId).push(actual);
    } else {
      unlinkedActuals.push(actual);
    }
  }

  const pairs = [];
  for (const planned of plannedRows) {
    const actuals = actualByPlannedId.get(planned.id) || [];
    if (!actuals.length) {
      pairs.push({ planned, actual: null });
      continue;
    }
    actuals.forEach((actual, index) => {
      pairs.push({ planned: index === 0 ? planned : null, actual });
    });
  }

  unlinkedActuals.forEach((actual) => {
    pairs.push({ planned: null, actual });
  });
  return pairs;
}

function renderLessonPdfLessonCard(row) {
  return `
    <article class="lesson-pdf-card">
      <div class="lesson-pdf-card-main">
        <span class="lesson-pdf-card-date">${escapeHtml(formatDateOnly(row.lesson_date))}（${escapeHtml(formatWeekday(row.lesson_date))}）</span>
        <span class="lesson-pdf-card-subject">${escapeHtml(nameById(subjects, row.subject_id, subjectName))}</span>
      </div>
      <div class="lesson-pdf-chip-row">
        <span class="lesson-pdf-chip">${escapeHtml(nameById(teachers, row.teacher_id, teacherName))}</span>
        <span class="lesson-pdf-chip">${escapeHtml(formatTimeRange(row.start_time, row.end_time))}</span>
        <span class="lesson-pdf-chip">${escapeHtml(displayValue(row.duration_hours))}课时</span>
        <span class="lesson-pdf-chip">${escapeHtml(lessonStatusLabel(row.status))}</span>
        <span class="lesson-pdf-chip">${escapeHtml(billableLabel(row.is_billable))}</span>
        <span class="lesson-pdf-chip is-money">${escapeHtml(formatCurrency(row.lesson_fee, "JPY"))}</span>
      </div>
      ${renderLessonPdfField("内容", row.lesson_content)}
      ${renderLessonPdfField("备注", row.note)}
    </article>
  `;
}

function renderLessonPdfEmptyCard(message) {
  return `<div class="lesson-pdf-card is-empty">${escapeHtml(message)}</div>`;
}

function renderLessonPdfField(label, value) {
  return `
    <div class="lesson-pdf-field">
      <span class="lesson-pdf-field-label">${escapeHtml(label)}</span>
      <span class="lesson-pdf-field-value">${escapeHtml(displayValue(value))}</span>
    </div>
  `;
}

function renderLessonPdfPlannedTable(rows) {
  return `
    <table class="lesson-pdf-planned-table">
      <colgroup>
        <col style="width: 17%;">
        <col style="width: 18%;">
        <col style="width: 18%;">
        <col style="width: 10%;">
        <col style="width: 15%;">
        <col style="width: 22%;">
      </colgroup>
      <thead>
        <tr>
          <th>日期</th>
          <th>科目 / 老师</th>
          <th>时间</th>
          <th>课时</th>
          <th>课时费</th>
          <th>内容 / 备注</th>
        </tr>
      </thead>
      <tbody>
        ${rows.map((row) => `
          <tr>
            <td>
              <strong>${escapeHtml(formatDateOnly(row.lesson_date))}</strong>
              <div class="compact">${escapeHtml(formatWeekday(row.lesson_date))}</div>
            </td>
            <td>
              <strong>${escapeHtml(nameById(subjects, row.subject_id, subjectName))}</strong>
              <div class="compact">${escapeHtml(nameById(teachers, row.teacher_id, teacherName))}</div>
            </td>
            <td>${escapeHtml(formatTimeRange(row.start_time, row.end_time))}</td>
            <td class="number">${escapeHtml(displayValue(row.duration_hours))}</td>
            <td class="number">${escapeHtml(formatCurrency(row.lesson_fee, "JPY"))}</td>
            <td>
              ${escapeHtml(displayValue(row.lesson_content))}
              ${row.note ? `<div class="compact">${escapeHtml(row.note)}</div>` : ""}
            </td>
          </tr>
        `).join("")}
      </tbody>
    </table>
  `;
}

function setLessonPdfExportSubmitting(isSubmitting) {
  isLessonPdfExportSubmitting = isSubmitting;
  dom.lessonPdfExportSubmitButton.disabled = isSubmitting;
  dom.lessonPdfExportCancelButton.disabled = isSubmitting;
  dom.openLessonPdfExportButton.disabled = isSubmitting;
  dom.lessonPdfExportSubmitButton.textContent = isSubmitting ? "生成中..." : "生成打印页";
}

function clearLessonPdfExportErrors() {
  dom.lessonPdfExportError.textContent = "";
  dom.lessonPdfExportError.classList.add("is-hidden");
  clearLessonPdfExportFieldInvalid("student");
}

function showLessonPdfExportError(message) {
  dom.lessonPdfExportError.textContent = lessonUserErrorMessage(message, "学生课时打印页生成失败，请稍后重试。");
  dom.lessonPdfExportError.classList.remove("is-hidden");
}

function hideLessonPdfExportErrorIfClean() {
  if (!dom.lessonPdfExportDialog?.querySelector(".field.is-invalid")) {
    dom.lessonPdfExportError.textContent = "";
    dom.lessonPdfExportError.classList.add("is-hidden");
  }
}

function setLessonPdfExportFieldInvalid(fieldId, invalid) {
  const field = dom.lessonPdfExportDialog?.querySelector(`[data-lesson-pdf-export-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearLessonPdfExportFieldInvalid(fieldId) {
  setLessonPdfExportFieldInvalid(fieldId, false);
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
    console.error("Lesson import preview failed", error);
    showLessonImportPreviewError(lessonUserErrorMessage(error, "课时文件预览失败，请检查文件后重试。"));
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
    const importedAuthority = await fetchLessonImportPlannedReferences(
      lastLessonImportResult.createdLessonIds
    );
    lastLessonImportResult.authoritativeMonths = [...new Set(
      importedAuthority.plannedLessons
        .map((lesson) => lesson.authoritative_student_month)
        .filter(Boolean)
    )].sort();
    successfulLessonImportFileHashes.add(importPreviewFileMeta.hash);
    renderLessonImportPreview();

    if (loadedMonth) {
      await loadLessonMonth(loadedMonth, readFilters() || { status: "" });
      applyCurrentFilters();
    }
    const monthText = formatLessonImportMonthRange(lastLessonImportResult.authoritativeMonths);
    showMessage("success", `已导入预定课时 ${lastLessonImportResult.successCount} 行${monthText ? `（收费归属月 ${monthText}）` : ""}。`);
  } catch (error) {
    showLessonImportPreviewError(formatLessonImportSubmitError(error));
  } finally {
    setLessonImportSubmitting(false);
  }
}

async function handleLessonImportViewMonthClick() {
  const months = lastLessonImportResult?.authoritativeMonths || [];
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
    lastLessonImportResult.authoritativeMonths?.[0] || loadedMonth,
    activeView
  );
}

function openLessonBatchGenerateDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能批量生成预定课时。");
    return;
  }

  renderLessonBatchGenerateMasterOptions();
  resetLessonBatchGenerateForm();
  hideLessonBatchGenerateError();
  setLessonBatchGenerateSubmitting(false);
  dom.lessonBatchGenerateDialog.classList.remove("is-hidden");
  dom.lessonBatchGenerateDialog.setAttribute("aria-hidden", "false");
  dom.lessonBatchGenerateStudentSelect?.focus();
}

function closeLessonBatchGenerateDialog(force = false) {
  if (isLessonBatchGenerateSubmitting && !force) {
    return;
  }

  if (!force && hasLessonBatchGenerateFormChanged()) {
    if (!isLessonBatchGenerateCloseConfirmPending) {
      isLessonBatchGenerateCloseConfirmPending = true;
      showLessonBatchGenerateError("表单已有修改。再次点击关闭将放弃输入。");
      return;
    }
  }

  dom.lessonBatchGenerateDialog.classList.add("is-hidden");
  dom.lessonBatchGenerateDialog.setAttribute("aria-hidden", "true");
  lessonBatchGenerateInitialSnapshot = null;
  isLessonBatchGenerateCloseConfirmPending = false;
}

function renderLessonBatchGenerateMasterOptions() {
  renderEntityOptionsWithPlaceholder(
    dom.lessonBatchGenerateStudentSelect,
    students.filter(isNewBusinessStudent),
    studentName,
    "请选择学生"
  );
  renderEntityOptionsWithPlaceholder(
    dom.lessonBatchGenerateBusinessEntitySelect,
    newBusinessEntities(businessEntities),
    businessEntityName,
    "请选择业务归属"
  );
}

function resetLessonBatchGenerateForm() {
  const selectedMonth = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter) || currentYearMonth();
  dom.lessonBatchGenerateStudentSelect.value = dom.studentSelect.value || "";
  dom.lessonBatchGenerateBusinessEntitySelect.value = isNewBusinessEntityId(businessEntities, dom.businessEntitySelect.value)
    ? dom.businessEntitySelect.value
    : defaultNewBusinessEntityId(businessEntities);
  if (!students.some((student) => student.id === dom.lessonBatchGenerateStudentSelect.value && isNewBusinessStudent(student))) {
    dom.lessonBatchGenerateStudentSelect.value = "";
  }
  dom.lessonBatchGenerateStartDateInput.value = firstDateOfMonth(selectedMonth);
  dom.lessonBatchGenerateEndDateInput.value = lastDateOfMonth(selectedMonth);
  dom.lessonBatchGenerateAirconRateInput.value = "0";
  dom.lessonBatchGenerateNoteInput.value = "批量生成预定课时";
  batchGeneratePatterns = [defaultLessonBatchGeneratePattern(1)];
  batchGeneratePreviewRows = [];
  batchGenerateRemovedKeys = new Set();
  lastLessonBatchGenerateResult = null;
  isLessonBatchGenerateCloseConfirmPending = false;
  clearLessonBatchGenerateErrors();
  renderLessonBatchGeneratePatterns();
  renderLessonBatchGeneratePreview();
  lessonBatchGenerateInitialSnapshot = readLessonBatchGenerateFormSnapshot();
}

function defaultLessonBatchGeneratePattern(patternIndex) {
  return {
    patternIndex,
    subjectId: "",
    teacherId: "",
    weekday: "1",
    startTime: "",
    endTime: "",
    lessonDeliveryMode: "",
    lessonVenue: "",
    onlinePlatform: "",
    durationHours: "2",
    unitPrice: "10000",
    occurrenceCount: "1",
    lessonCount: "1",
    lessonContent: "",
  };
}

function addLessonBatchGeneratePattern() {
  const nextIndex = (Math.max(0, ...batchGeneratePatterns.map((pattern) => Number(pattern.patternIndex) || 0)) + 1);
  batchGeneratePatterns.push(defaultLessonBatchGeneratePattern(nextIndex));
  clearLessonBatchGeneratePreviewState();
  renderLessonBatchGeneratePatterns();
  renderLessonBatchGeneratePreview();
}

function renderLessonBatchGeneratePatterns() {
  if (!dom.lessonBatchGeneratePatternList) {
    return;
  }

  dom.lessonBatchGeneratePatternList.innerHTML = batchGeneratePatterns.map((pattern, index) => `
    <div class="lesson-batch-pattern-row" data-batch-pattern-index="${escapeAttribute(pattern.patternIndex)}">
      <label class="field">
        <span>科目</span>
        <select data-batch-pattern-field="subjectId">
          ${renderLessonBatchGenerateSubjectOptions(pattern.subjectId)}
        </select>
      </label>
      <label class="field">
        <span>老师</span>
        <select data-batch-pattern-field="teacherId">
          ${renderLessonBatchGenerateTeacherOptions(pattern.teacherId)}
        </select>
      </label>
      <label class="field">
        <span>周几</span>
        <select data-batch-pattern-field="weekday">
          ${LESSON_BATCH_WEEKDAY_OPTIONS.map(([value, label]) => (
            `<option value="${escapeAttribute(value)}" ${String(pattern.weekday) === value ? "selected" : ""}>${escapeHtml(label)}</option>`
          )).join("")}
        </select>
      </label>
      <label class="field">
        <span>开始</span>
        <input type="time" value="${escapeAttribute(pattern.startTime)}" data-batch-pattern-field="startTime">
      </label>
      <label class="field">
        <span>结束</span>
        <input type="time" value="${escapeAttribute(pattern.endTime)}" data-batch-pattern-field="endTime">
      </label>
      <label class="field">
        <span>授课方式</span>
        <select data-batch-pattern-field="lessonDeliveryMode">
          <option value="" ${!pattern.lessonDeliveryMode ? "selected" : ""}>未设置</option>
          <option value="onsite" ${pattern.lessonDeliveryMode === "onsite" ? "selected" : ""}>线下</option>
          <option value="online" ${pattern.lessonDeliveryMode === "online" ? "selected" : ""}>线上</option>
        </select>
      </label>
      <label class="field ${pattern.lessonDeliveryMode === "onsite" ? "" : "is-hidden"}">
        <span>上课场地</span>
        <select data-batch-pattern-field="lessonVenue" ${pattern.lessonDeliveryMode === "onsite" ? "" : "disabled"}>
          <option value="">请选择场地</option>
          <option value="Regus公共区" ${pattern.lessonVenue === "Regus公共区" ? "selected" : ""}>Regus公共区</option>
          <option value="Regus办公室" ${pattern.lessonVenue === "Regus办公室" ? "selected" : ""}>Regus办公室</option>
        </select>
      </label>
      <label class="field ${pattern.lessonDeliveryMode === "online" ? "" : "is-hidden"}">
        <span>线上平台</span>
        <input type="text" maxlength="100" value="${escapeAttribute(pattern.onlinePlatform)}" data-batch-pattern-field="onlinePlatform" placeholder="例：Zoom" ${pattern.lessonDeliveryMode === "online" ? "" : "disabled"}>
      </label>
      <label class="field">
        <span>课时</span>
        <input type="number" min="0.25" step="0.25" inputmode="decimal" value="${escapeAttribute(pattern.durationHours)}" data-batch-pattern-field="durationHours">
      </label>
      <label class="field">
        <span>单价 JPY</span>
        <input type="number" min="0" step="1" inputmode="numeric" value="${escapeAttribute(pattern.unitPrice)}" data-batch-pattern-field="unitPrice">
      </label>
      <label class="field">
        <span>每周次数</span>
        <input type="number" min="1" step="1" inputmode="numeric" value="${escapeAttribute(pattern.occurrenceCount)}" data-batch-pattern-field="occurrenceCount">
      </label>
      <label class="field">
        <span>起始回数</span>
        <input type="number" min="1" step="1" inputmode="numeric" value="${escapeAttribute(pattern.lessonCount)}" data-batch-pattern-field="lessonCount">
      </label>
      <label class="field">
        <span>内容</span>
        <input type="text" value="${escapeAttribute(pattern.lessonContent)}" data-batch-pattern-field="lessonContent">
      </label>
      <button class="button lesson-batch-pattern-remove-button" type="button" data-batch-pattern-action="remove" ${batchGeneratePatterns.length <= 1 ? "disabled" : ""}>移除</button>
    </div>
  `).join("");

  if (!batchGeneratePatterns.length) {
    batchGeneratePatterns = [defaultLessonBatchGeneratePattern(1)];
    renderLessonBatchGeneratePatterns();
  }
}

function renderLessonBatchGenerateSubjectOptions(selectedId) {
  const options = ['<option value="">请选择科目</option>'];
  options.push(...subjects
    .filter((subject) => subject.is_active !== false)
    .map((subject) => `<option value="${escapeAttribute(subject.id)}" ${subject.id === selectedId ? "selected" : ""}>${escapeHtml(subjectName(subject))}</option>`)
  );
  return options.join("");
}

function renderLessonBatchGenerateTeacherOptions(selectedId) {
  const options = ['<option value="">请选择老师</option>'];
  options.push(...teachers
    .filter((teacher) => !["inactive", "retired"].includes(safeText(teacher.status)))
    .map((teacher) => `<option value="${escapeAttribute(teacher.id)}" ${teacher.id === selectedId ? "selected" : ""}>${escapeHtml(teacherName(teacher))}</option>`)
  );
  return options.join("");
}

function handleLessonBatchGeneratePatternInput(event) {
  const field = event.target.closest("[data-batch-pattern-field]");
  if (!field) {
    return;
  }

  const row = event.target.closest("[data-batch-pattern-index]");
  const patternIndex = Number(row?.dataset.batchPatternIndex);
  const pattern = batchGeneratePatterns.find((item) => Number(item.patternIndex) === patternIndex);
  if (!pattern) {
    return;
  }

  const fieldName = field.dataset.batchPatternField;
  pattern[fieldName] = field.value;
  isLessonBatchGenerateCloseConfirmPending = false;
  if (fieldName === "subjectId" && !pattern.lessonContent) {
    const subject = subjects.find((item) => item.id === field.value);
    pattern.lessonContent = subject ? subjectName(subject) : "";
    renderLessonBatchGeneratePatterns();
  } else if (fieldName === "lessonDeliveryMode") {
    renderLessonBatchGeneratePatterns();
  }
  clearLessonBatchGeneratePreviewState();
  hideLessonBatchGenerateErrorIfClean();
  renderLessonBatchGeneratePreview();
}

function handleLessonBatchGeneratePatternAction(event) {
  const button = event.target.closest("[data-batch-pattern-action]");
  if (!button) {
    return;
  }

  const row = button.closest("[data-batch-pattern-index]");
  const patternIndex = Number(row?.dataset.batchPatternIndex);
  if (button.dataset.batchPatternAction === "remove" && batchGeneratePatterns.length > 1) {
    batchGeneratePatterns = batchGeneratePatterns.filter((pattern) => Number(pattern.patternIndex) !== patternIndex);
    isLessonBatchGenerateCloseConfirmPending = false;
    clearLessonBatchGeneratePreviewState();
    renderLessonBatchGeneratePatterns();
    renderLessonBatchGeneratePreview();
  }
}

function handleLessonBatchGeneratePreview() {
  hideLessonBatchGenerateError();
  clearLessonBatchGenerateErrors();
  clearLessonBatchGenerateSubmitResult();
  const draft = readLessonBatchGenerateDraft();
  if (!draft) {
    renderLessonBatchGeneratePreview();
    return;
  }

  batchGeneratePreviewRows = buildLessonBatchGeneratePreviewRows(draft);
  batchGenerateRemovedKeys = new Set();
  const duplicateRow = findDuplicateLessonBatchGeneratePreviewRow(batchGeneratePreviewRows);
  if (duplicateRow) {
    batchGeneratePreviewRows = [];
    renderLessonBatchGeneratePreview();
    showLessonBatchGenerateError(`规则 ${duplicateRow.current.patternIndex} 与规则 ${duplicateRow.first.patternIndex} 会生成重复课时，请调整日期、第几回或规则内容。`);
    return;
  }
  renderLessonBatchGeneratePreview();
  if (!visibleLessonBatchGeneratePreviewRows().length) {
    showLessonBatchGenerateError("当前规则没有可生成的预定课时。");
  }
}

function handleLessonBatchGenerateRegeneratePreview() {
  handleLessonBatchGeneratePreview();
}

function readLessonBatchGenerateDraft(options = {}) {
  const silent = Boolean(options.silent);
  const studentId = dom.lessonBatchGenerateStudentSelect.value;
  const businessEntityId = dom.lessonBatchGenerateBusinessEntitySelect.value;
  const startDate = dom.lessonBatchGenerateStartDateInput.value;
  const endDate = dom.lessonBatchGenerateEndDateInput.value;
  const airconRateJpyPerHour = numberFromInput(dom.lessonBatchGenerateAirconRateInput.value);
  const errors = [];

  if (!studentId) {
    errors.push(["student", "请选择学生。"]);
  }
  if (!businessEntityId) {
    errors.push(["businessEntity", "请选择业务归属。"]);
  }
  if (!isDateInputValue(startDate)) {
    errors.push(["startDate", "请选择有效开始日期。"]);
  }
  if (!isDateInputValue(endDate)) {
    errors.push(["endDate", "请选择有效结束日期。"]);
  }
  if (isDateInputValue(startDate) && isDateInputValue(endDate) && startDate > endDate) {
    errors.push(["endDate", "结束日期不能早于开始日期。"]);
  }
  if (!Number.isInteger(airconRateJpyPerHour) || airconRateJpyPerHour < 0) {
    errors.push(["airconRate", "默认空调费率必须是非负整数。"]);
  }

  const normalizedPatterns = batchGeneratePatterns.map((pattern) => normalizeLessonBatchGeneratePattern(pattern));
  if (!normalizedPatterns.length) {
    errors.push(["patterns", "至少需要一条课程规则。"]);
  }

  for (const pattern of normalizedPatterns) {
    if (!pattern.subjectId) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 请选择科目。`]);
    }
    if (!pattern.teacherId) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 请选择老师。`]);
    }
    if (pattern.lessonVenue && !pattern.lessonDeliveryMode) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 填写场地前请选择授课方式。`]);
    }
    if (pattern.lessonDeliveryMode === "onsite" && !pattern.lessonVenue) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 的线下课程必须填写上课场地。`]);
    }
    if (pattern.lessonDeliveryMode === "onsite" && !FIXED_ONSITE_LESSON_VENUES.includes(pattern.lessonVenue)) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 的线下场地只能选择 Regus公共区 或 Regus办公室。`]);
    }
    if (!Number.isInteger(pattern.weekday) || pattern.weekday < 0 || pattern.weekday > 6) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 请选择周几。`]);
    }
    const timeCheck = validateLessonTimeRange(pattern.startTime, pattern.endTime);
    if (timeCheck.status === "valid") {
      pattern.startTimeForSave = pattern.startTime;
      pattern.endTimeForSave = pattern.endTime;
      if (!Number.isFinite(pattern.durationHours) || pattern.durationHours <= 0) {
        pattern.durationHours = timeCheck.durationHours;
      }
    } else if (Number.isFinite(pattern.durationHours) && pattern.durationHours > 0) {
      pattern.startTimeForSave = null;
      pattern.endTimeForSave = null;
      pattern.warnings.push(`规则 ${pattern.patternIndex} 未填写有效开始/结束时间，将只按课时生成。`);
    } else {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 请填写课时，或填写有效开始和结束时间。`]);
    }
    if (Number.isFinite(pattern.durationHours) && pattern.durationHours > 0 && timeCheck.status === "valid" && !numbersEqual(pattern.durationHours, timeCheck.durationHours)) {
      pattern.warnings.push(`规则 ${pattern.patternIndex} 课时与开始/结束时间不一致，预览和提交将按开始/结束时间 ${displayInputNumber(timeCheck.durationHours)} h。`);
      pattern.durationHours = timeCheck.durationHours;
    }
    if (!Number.isFinite(pattern.durationHours) || pattern.durationHours <= 0) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 课时必须大于 0。`]);
    }
    if (!Number.isFinite(pattern.unitPrice) || pattern.unitPrice < 0) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 单价不能小于 0。`]);
    }
    if (!Number.isInteger(pattern.occurrenceCount) || pattern.occurrenceCount <= 0 || pattern.occurrenceCount > 10) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 每周次数必须是 1-10 的正整数。`]);
    }
    if (pattern.lessonCount !== null && (!Number.isInteger(pattern.lessonCount) || pattern.lessonCount <= 0)) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 起始回数必须是正整数。`]);
    }
  }

  const duplicateKeys = new Map();
  for (const pattern of normalizedPatterns) {
    const key = buildLessonBatchGeneratePatternDuplicateKey(pattern);
    const firstPatternIndex = duplicateKeys.get(key);
    if (firstPatternIndex !== undefined) {
      errors.push(["patterns", `规则 ${pattern.patternIndex} 与规则 ${firstPatternIndex} 完全相同，请删除或调整重复规则。`]);
    } else {
      duplicateKeys.set(key, pattern.patternIndex);
    }
  }

  if (errors.length) {
    if (silent) {
      return null;
    }
    for (const [fieldId] of errors) {
      if (LESSON_BATCH_FIELD_IDS.includes(fieldId)) {
        setLessonBatchGenerateFieldInvalid(fieldId, true);
      }
    }
    showLessonBatchGenerateError(errors.map(([, message]) => message).join("\n"));
    return null;
  }

  return {
    studentId,
    businessEntityId,
    startDate,
    endDate,
    airconRateJpyPerHour,
    note: dom.lessonBatchGenerateNoteInput.value.trim(),
    patterns: normalizedPatterns,
    warnings: normalizedPatterns.flatMap((pattern) => pattern.warnings),
  };
}

function normalizeLessonBatchGeneratePattern(pattern) {
  const lessonDeliveryMode = safeText(pattern.lessonDeliveryMode);
  const lessonVenue = lessonDeliveryMode === "onsite"
    ? safeText(pattern.lessonVenue)
    : lessonDeliveryMode === "online"
      ? safeText(pattern.onlinePlatform)
      : "";
  return {
    patternIndex: Number(pattern.patternIndex),
    subjectId: safeText(pattern.subjectId),
    teacherId: safeText(pattern.teacherId),
    weekday: Number(pattern.weekday),
    startTime: safeText(pattern.startTime),
    endTime: safeText(pattern.endTime),
    lessonDeliveryMode,
    lessonVenue,
    onlinePlatform: safeText(pattern.onlinePlatform),
    startTimeForSave: safeText(pattern.startTime),
    endTimeForSave: safeText(pattern.endTime),
    durationHours: numberFromInput(pattern.durationHours),
    unitPrice: Number(pattern.unitPrice),
    occurrenceCount: Number(pattern.occurrenceCount),
    lessonCount: pattern.lessonCount === "" || pattern.lessonCount === null || pattern.lessonCount === undefined
      ? null
      : Number(pattern.lessonCount),
    lessonContent: safeText(pattern.lessonContent),
    warnings: [],
  };
}

function buildLessonBatchGeneratePatternDuplicateKey(pattern) {
  return [
    pattern.weekday,
    pattern.teacherId,
    pattern.subjectId,
    pattern.startTimeForSave || "",
    pattern.endTimeForSave || "",
    pattern.lessonDeliveryMode,
    pattern.lessonVenue,
    Number.isFinite(pattern.durationHours) ? Number(pattern.durationHours).toFixed(4) : "",
    Number.isFinite(pattern.unitPrice) ? Number(pattern.unitPrice).toFixed(4) : "",
    pattern.occurrenceCount,
    pattern.lessonCount ?? "",
    pattern.lessonContent,
  ].join("|");
}

function buildLessonBatchGeneratePreviewRows(draft) {
  const rows = [];
  const dates = listDateInputValues(draft.startDate, draft.endDate);
  for (const lessonDate of dates) {
    const weekday = dateInputWeekday(lessonDate);
    for (const pattern of draft.patterns) {
      if (pattern.weekday !== weekday) {
        continue;
      }
      const timeCheck = validateLessonTimeRange(pattern.startTime, pattern.endTime);
      const hasValidTime = timeCheck.status === "valid";
      const weekLessonDate = mondayOfDateInputValue(lessonDate);
      for (let occurrenceIndex = 1; occurrenceIndex <= pattern.occurrenceCount; occurrenceIndex += 1) {
        rows.push({
          rowKey: `${pattern.patternIndex}:${weekLessonDate}:${occurrenceIndex}`,
          patternIndex: pattern.patternIndex,
          occurrenceIndex,
          sourceDate: lessonDate,
          lessonDate,
          billingWeekDate: weekLessonDate,
          weekday,
          studentId: draft.studentId,
          businessEntityId: draft.businessEntityId,
          subjectId: pattern.subjectId,
          teacherId: pattern.teacherId,
          startTime: hasValidTime ? pattern.startTime : null,
          endTime: hasValidTime ? pattern.endTime : null,
          lessonDeliveryMode: pattern.lessonDeliveryMode,
          lessonVenue: pattern.lessonVenue,
          durationHours: hasValidTime ? timeCheck.durationHours : pattern.durationHours,
          unitPrice: pattern.unitPrice,
          airconRateJpyPerHour: draft.airconRateJpyPerHour,
          lessonCount: pattern.lessonCount === null ? occurrenceIndex : pattern.lessonCount + occurrenceIndex - 1,
          lessonContent: pattern.lessonContent,
        });
      }
    }
  }
  return rows.sort(compareLessonBatchGeneratePreviewRows);
}

function compareLessonBatchGeneratePreviewRows(left, right) {
  return left.lessonDate.localeCompare(right.lessonDate)
    || lessonBatchGenerateSubjectOrder(left.subjectId) - lessonBatchGenerateSubjectOrder(right.subjectId)
    || Number(left.lessonCount || 0) - Number(right.lessonCount || 0)
    || left.patternIndex - right.patternIndex
    || left.occurrenceIndex - right.occurrenceIndex;
}

function lessonBatchGenerateSubjectOrder(subjectId) {
  const subject = subjects.find((item) => item.id === subjectId);
  if (!subject) {
    return LESSON_BATCH_SUBJECT_ORDER_FALLBACK;
  }
  const normalizedName = normalizeLessonImportLookup(subjectName(subject));
  const matchedIndex = SUBJECT_SORT_RULES.findIndex((aliases) => (
    aliases.some((alias) => normalizedName.includes(normalizeLessonImportLookup(alias)))
  ));
  return matchedIndex >= 0 ? matchedIndex : LESSON_BATCH_SUBJECT_ORDER_FALLBACK;
}

function findDuplicateLessonBatchGeneratePreviewRow(rows) {
  const seen = new Map();
  for (const row of rows) {
    const key = [
      row.lessonDate,
      row.studentId,
      row.businessEntityId,
      row.teacherId,
      row.subjectId,
      row.startTime || "",
      row.endTime || "",
      Number(row.durationHours || 0).toFixed(4),
      Number(row.unitPrice || 0).toFixed(4),
      row.lessonCount ?? "",
      row.lessonContent || "",
    ].join("|");
    const first = seen.get(key);
    if (first) {
      return { first, current: row };
    }
    seen.set(key, row);
  }
  return null;
}

function renderLessonBatchGeneratePreview() {
  const visibleRows = visibleLessonBatchGeneratePreviewRows();
  dom.lessonBatchGeneratePreviewEmpty?.classList.toggle("is-hidden", visibleRows.length > 0);
  dom.lessonBatchGeneratePreviewRows.innerHTML = visibleRows.map((row) => {
    const subject = subjects.find((item) => item.id === row.subjectId);
    const teacher = teachers.find((item) => item.id === row.teacherId);
    const student = students.find((item) => item.id === row.studentId);
    const entity = businessEntities.find((item) => item.id === row.businessEntityId);
    return `
      <tr>
        <td>${escapeHtml(formatDateOnly(row.lessonDate))}</td>
        <td>${escapeHtml(WEEKDAY_LABELS[row.weekday] || "-")}</td>
        <td>${escapeHtml(student ? studentName(student) : "-")}</td>
        <td>${escapeHtml(teacher ? teacherName(teacher) : "-")}</td>
        <td>${escapeHtml(subject ? subjectName(subject) : "-")}</td>
        <td>${escapeHtml(entity ? businessEntityName(entity) : "-")}</td>
        <td>${escapeHtml(formatTimeRange(row.startTime, row.endTime))}</td>
        <td>${escapeHtml(formatLessonVenue(row.lessonDeliveryMode, row.lessonVenue))}</td>
        <td>${escapeHtml(row.durationHours ? `${row.durationHours} h` : "-")}</td>
        <td>${escapeHtml(formatCurrency(row.unitPrice, "JPY"))}</td>
        <td>${escapeHtml(formatCurrency(row.airconRateJpyPerHour, "JPY"))}</td>
        <td>${escapeHtml(row.lessonCount ?? "-")}</td>
        <td>${escapeHtml(row.lessonContent || "-")}</td>
        <td><button class="table-action-button" type="button" data-batch-preview-remove-key="${escapeAttribute(row.rowKey)}">移除</button></td>
      </tr>
    `;
  }).join("");

  if (dom.lessonBatchGenerateSummary) {
    const months = lessonBatchGeneratePreviewMonths(visibleRows);
    const totalHours = visibleRows.reduce((sum, row) => sum + (Number(row.durationHours) || 0), 0);
    const warnings = (readLessonBatchGenerateWarnings() || []).slice(0, 3);
    const warningHtml = warnings.length
      ? `<div class="lesson-batch-generate-warning">${escapeHtml(warnings.join(" / "))}</div>`
      : "";
    dom.lessonBatchGenerateSummary.innerHTML = `
      <div><dt>预览课时数</dt><dd>${visibleRows.length}</dd></div>
      <div><dt>预览总课时</dt><dd>${totalHours.toFixed(2)} h</dd></div>
      <div><dt>月份</dt><dd>${escapeHtml(formatLessonImportMonthRange(months) || "-")}</dd></div>
      <div><dt>已移除</dt><dd>${batchGenerateRemovedKeys.size}</dd></div>
      ${warningHtml}
    `;
    dom.lessonBatchGenerateSummary.classList.toggle("is-hidden", !batchGeneratePreviewRows.length);
  }

  const hasVisibleRows = visibleRows.length > 0;
  dom.lessonBatchGenerateSubmitButton.disabled = isLessonBatchGenerateSubmitting || !hasVisibleRows || Boolean(lastLessonBatchGenerateResult?.successCount);
  dom.lessonBatchGenerateViewMonthButton.classList.toggle("is-hidden", !(lastLessonBatchGenerateResult?.months?.length === 1));
  dom.lessonBatchGenerateViewFirstDetailButton.classList.toggle("is-hidden", !(lastLessonBatchGenerateResult?.createdLessonIds?.length));
}

function visibleLessonBatchGeneratePreviewRows() {
  return batchGeneratePreviewRows.filter((row) => !batchGenerateRemovedKeys.has(row.rowKey));
}

function handleLessonBatchGeneratePreviewAction(event) {
  const button = event.target.closest("[data-batch-preview-remove-key]");
  if (!button) {
    return;
  }

  batchGenerateRemovedKeys.add(button.dataset.batchPreviewRemoveKey || "");
  clearLessonBatchGenerateSubmitResult();
  renderLessonBatchGeneratePreview();
}

async function handleLessonBatchGenerateSubmit() {
  if (isLessonBatchGenerateSubmitting) {
    return;
  }

  hideLessonBatchGenerateError();
  const draft = readLessonBatchGenerateDraft();
  if (!draft) {
    return;
  }

  if (!batchGeneratePreviewRows.length) {
    batchGeneratePreviewRows = buildLessonBatchGeneratePreviewRows(draft);
  }

  const duplicateRow = findDuplicateLessonBatchGeneratePreviewRow(batchGeneratePreviewRows);
  if (duplicateRow) {
    batchGeneratePreviewRows = [];
    renderLessonBatchGeneratePreview();
    showLessonBatchGenerateError(`规则 ${duplicateRow.current.patternIndex} 与规则 ${duplicateRow.first.patternIndex} 会生成重复课时，请调整日期、回数或规则内容。`);
    return;
  }

  const visibleRows = visibleLessonBatchGeneratePreviewRows();
  if (!visibleRows.length) {
    renderLessonBatchGeneratePreview();
    showLessonBatchGenerateError("当前没有可提交的预定课时。");
    return;
  }

  const filtersBeforeSubmit = readFilters();
  const monthBeforeSubmit = filtersBeforeSubmit?.month || loadedMonth || "";
  if (!filtersBeforeSubmit?.month || !monthBeforeSubmit) {
    showLessonBatchGenerateError("当前课时筛选状态不可用，请关闭窗口、刷新页面后重试。");
    return;
  }

  setLessonBatchGenerateSubmitting(true);
  try {
    const results = await generatePlannedLessonRecordsBatch({
      generationId: createLessonImportBatchId(),
      studentId: draft.studentId,
      businessEntityId: draft.businessEntityId,
      startDate: draft.startDate,
      endDate: draft.endDate,
      patterns: draft.patterns.map((pattern) => ({
        pattern_index: pattern.patternIndex,
        weekday: pattern.weekday,
        status: "planned",
        teacher_id: pattern.teacherId,
        subject_id: pattern.subjectId,
        start_time: pattern.startTimeForSave || null,
        end_time: pattern.endTimeForSave || null,
        lesson_delivery_mode: pattern.lessonDeliveryMode || null,
        lesson_venue: pattern.lessonVenue || null,
        duration_hours: pattern.durationHours,
        unit_price: pattern.unitPrice,
        aircon_rate_jpy_per_hour: draft.airconRateJpyPerHour,
        occurrence_count: pattern.occurrenceCount,
        lesson_count: pattern.lessonCount,
        lesson_content: pattern.lessonContent || null,
        note: null,
      })),
      excludedOccurrences: [...batchGenerateRemovedKeys].map((key) => {
        const [patternIndex, lessonDate, occurrenceIndex] = key.split(":");
        return {
          pattern_index: Number(patternIndex),
          lesson_date: lessonDate,
          occurrence_index: Number(occurrenceIndex),
        };
      }),
      note: draft.note || "lesson planned batch generator from lesson.html",
    });

    const failedRows = results.filter((row) => row.row_valid === false || row.batch_committed === false || (row.errors || []).length);
    if (failedRows.length) {
      showLessonBatchGenerateError(formatLessonBatchGenerateFailedRowsMessage(failedRows));
      renderLessonBatchGeneratePreview();
      return;
    }

    lastLessonBatchGenerateResult = buildLessonBatchGenerateResultSummary(results);
    renderLessonBatchGeneratePreview();

    const monthText = formatLessonImportMonthRange(lastLessonBatchGenerateResult.months);
    closeLessonBatchGenerateDialog(true);
    try {
      await refreshLessonMonthPreservingFilters(monthBeforeSubmit, filtersBeforeSubmit);
    } catch (refreshError) {
      console.error("Lesson list refresh failed after committed batch generation", refreshError);
      showMessage(
        "error",
        lessonUserErrorMessage(refreshError, "预定课时已生成，但列表刷新失败，请手动刷新页面。")
      );
      return;
    }
    showMessage("success", `已生成预定课时 ${lastLessonBatchGenerateResult.successCount} 行${monthText ? `（${monthText}）` : ""}。`);
  } catch (error) {
    console.error("Planned lesson batch generation failed", error);
    showLessonBatchGenerateError(lessonUserErrorMessage(error, "批量生成预定课时失败，请稍后重试。"));
  } finally {
    setLessonBatchGenerateSubmitting(false);
  }
}

function buildLessonBatchGenerateResultSummary(results) {
  const successfulResults = (results || []).filter((row) => row.batch_committed !== false && row.created_lesson_id);
  const months = [...new Set(successfulResults
    .map((row) => lessonImportYearMonth(row.lesson_date))
    .filter(Boolean))]
    .sort();
  const createdLessonIds = successfulResults
    .map((row) => row.created_lesson_id)
    .filter(Boolean);
  return {
    successCount: successfulResults.length,
    months,
    createdLessonIds,
  };
}

function formatLessonBatchGenerateFailedRowsMessage(rows) {
  const messages = rows.slice(0, 5).map((row) => {
    const errors = (row.errors || []).filter(Boolean).join(" / ") || "未知错误";
    const dateText = row.lesson_date ? ` ${row.lesson_date}` : "";
    return `规则 ${row.pattern_index || "-"}${dateText}: ${errors}`;
  });
  const suffix = rows.length > 5 ? `；另有 ${rows.length - 5} 行错误` : "";
  return `批量生成未写入：${messages.join("；")}${suffix}`;
}

async function handleLessonBatchGenerateViewMonthClick() {
  const months = lastLessonBatchGenerateResult?.months || [];
  if (months.length !== 1) {
    return;
  }

  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, months[0]);
  closeLessonBatchGenerateDialog(true);
  await applyQuery();
}

function handleLessonBatchGenerateViewFirstDetailClick() {
  const firstLessonId = lastLessonBatchGenerateResult?.createdLessonIds?.[0] || "";
  if (!firstLessonId) {
    return;
  }

  window.location.href = createLessonDetailUrl(
    firstLessonId,
    lastLessonBatchGenerateResult.months?.[0] || loadedMonth,
    activeView
  );
}

function lessonBatchGeneratePreviewMonths(rows) {
  return [...new Set(rows.map((row) => lessonImportYearMonth(row.lessonDate)).filter(Boolean))].sort();
}

function clearLessonBatchGeneratePreviewState() {
  batchGeneratePreviewRows = [];
  batchGenerateRemovedKeys = new Set();
  clearLessonBatchGenerateSubmitResult();
}

function clearLessonBatchGenerateSubmitResult() {
  lastLessonBatchGenerateResult = null;
}

function readLessonBatchGenerateWarnings() {
  const draft = readLessonBatchGenerateDraft({ silent: true });
  return draft?.warnings || [];
}

function setLessonBatchGenerateSubmitting(isSubmitting) {
  isLessonBatchGenerateSubmitting = isSubmitting;
  dom.lessonBatchGeneratePreviewButton.disabled = isSubmitting;
  dom.lessonBatchGenerateSubmitButton.disabled = isSubmitting || !visibleLessonBatchGeneratePreviewRows().length;
  dom.lessonBatchGenerateCloseButton.disabled = isSubmitting;
  dom.lessonBatchGenerateAddPatternButton.disabled = isSubmitting;
  dom.lessonBatchGenerateSubmitButton.textContent = isSubmitting ? "生成中..." : "生成预定课时";
}

function showLessonBatchGenerateError(message) {
  dom.lessonBatchGenerateError.textContent = lessonUserErrorMessage(message, "批量生成预定课时失败，请稍后重试。");
  dom.lessonBatchGenerateError.classList.remove("is-hidden");
  dom.lessonBatchGenerateDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function hideLessonBatchGenerateError() {
  dom.lessonBatchGenerateError.textContent = "";
  dom.lessonBatchGenerateError.classList.add("is-hidden");
}

function hideLessonBatchGenerateErrorIfClean() {
  const hasInvalidField = Boolean(dom.lessonBatchGenerateDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    hideLessonBatchGenerateError();
  }
}

function clearLessonBatchGenerateErrors() {
  hideLessonBatchGenerateError();
  LESSON_BATCH_FIELD_IDS.forEach((fieldId) => clearLessonBatchGenerateFieldInvalid(fieldId));
}

function setLessonBatchGenerateFieldInvalid(fieldId, invalid) {
  const field = dom.lessonBatchGenerateDialog?.querySelector(`[data-batch-generate-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearLessonBatchGenerateFieldInvalid(fieldId) {
  setLessonBatchGenerateFieldInvalid(fieldId, false);
}

function readLessonBatchGenerateFormSnapshot() {
  return JSON.stringify({
    student: dom.lessonBatchGenerateStudentSelect.value,
    businessEntity: dom.lessonBatchGenerateBusinessEntitySelect.value,
    startDate: dom.lessonBatchGenerateStartDateInput.value,
    endDate: dom.lessonBatchGenerateEndDateInput.value,
    airconRate: dom.lessonBatchGenerateAirconRateInput.value,
    note: dom.lessonBatchGenerateNoteInput.value,
    patterns: batchGeneratePatterns,
    removed: [...batchGenerateRemovedKeys].sort(),
  });
}

function hasLessonBatchGenerateFormChanged() {
  return Boolean(
    lessonBatchGenerateInitialSnapshot
    && readLessonBatchGenerateFormSnapshot() !== lessonBatchGenerateInitialSnapshot
  );
}

function buildLessonImportResultSummary(results, rows) {
  const successfulResults = (results || [])
    .filter((row) => row.batch_committed !== false && row.created_lesson_id);
  const successfulRowIndexes = new Set(successfulResults
    .map((row) => Number(row.row_index))
    .filter(Number.isFinite));
  const occurrenceMonths = [...new Set(rows
    .map((row, index) => (successfulRowIndexes.has(index + 1) ? lessonImportYearMonth(row.values.lessonDate) : ""))
    .filter(Boolean))]
    .sort();
  const createdLessonIds = successfulResults
    .map((row) => row.created_lesson_id)
    .filter(Boolean);

  return {
    successCount: successfulRowIndexes.size,
    occurrenceMonths,
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
      yearMonth: plannedLesson.authoritative_student_month,
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
      yearMonth: plannedLesson.authoritative_student_month,
      businessEntityId: plannedLesson.business_entity_id,
    });
    if (lockedSettlementKeys.has(settlementKey)) {
      addLessonImportPreviewIssue(row, "error", "plannedId", `关联预定涉及已锁定收费归属月 ${plannedLesson.authoritative_student_month}，后续写入会被拒绝。`);
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
    if (/^(授课方式|上课方式|课程形式|授業形式|deliverymode|delivery_mode|lessondeliverymode|lesson_delivery_mode)$/.test(key)) set("lessonDeliveryMode");
    if (/^(上课场地|场地|教室|授業場所|venue|lessonvenue|lesson_venue|平台)$/.test(key)) set("lessonVenue");
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
      map.lessonDeliveryMode,
      map.lessonVenue,
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
    lessonDeliveryMode: columnMap.lessonDeliveryMode,
    lessonVenue: columnMap.lessonVenue,
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
    lessonDeliveryMode: readLessonImportPreviewCell(rawRow, fieldIndexes.lessonDeliveryMode),
    lessonVenue: readLessonImportPreviewCell(rawRow, fieldIndexes.lessonVenue),
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
      lessonDeliveryMode: normalizeLessonDeliveryMode(raw.lessonDeliveryMode),
      lessonVenue: importPreviewCellText(raw.lessonVenue),
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
  if (values.studentId && !isNewBusinessStudent(students.find((student) => student.id === values.studentId))) {
    addLessonImportPreviewIssue(row, "error", "student", "新导入预定课时只能选择青空进学塾在籍学生。");
  }
  validateLessonImportPreviewLookup(row, "teacher", teachers, teacherName);
  validateLessonImportPreviewLookup(row, "subject", subjects, subjectName);
  validateLessonImportPreviewLookup(row, "businessEntity", businessEntities, businessEntityName);
  if (values.businessEntityId && !isNewBusinessEntityId(businessEntities, values.businessEntityId)) {
    addLessonImportPreviewIssue(row, "error", "businessEntity", "新导入预定课时只能归属青空进学塾。个人名义仅保留历史处理。");
  }

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

  if (hasLessonImportPreviewValue(row.raw.lessonDeliveryMode) && !values.lessonDeliveryMode) {
    addLessonImportPreviewIssue(row, "error", "lessonDeliveryMode", "授课方式只支持线下 / 线上。");
  }
  if (values.lessonVenue && !values.lessonDeliveryMode) {
    addLessonImportPreviewIssue(row, "error", "lessonVenue", "填写上课场地前，请先填写授课方式。");
  }
  if (values.lessonDeliveryMode === "onsite" && !values.lessonVenue) {
    addLessonImportPreviewIssue(row, "error", "lessonVenue", "线下课程必须填写上课场地。");
  }
  if (values.lessonDeliveryMode === "onsite" && values.lessonVenue && !FIXED_ONSITE_LESSON_VENUES.includes(values.lessonVenue)) {
    addLessonImportPreviewIssue(row, "error", "lessonVenue", "线下上课场地只能填写 Regus公共区 或 Regus办公室。");
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
      addLessonImportPreviewIssue(row, "warning", "lessonFee", "课时费总额为空，导入时将由 DB/RPC 按课时 x 单价计算。");
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
    dom.lessonImportPlannedSubmitButton.disabled = true;
    dom.lessonImportPlannedSubmitButton.textContent = "历史导入已停用";
  }
  if (dom.lessonImportViewMonthButton) {
    const canViewImportMonth = !isLessonImportSubmitting && lastLessonImportResult?.authoritativeMonths?.length === 1;
    dom.lessonImportViewMonthButton.classList.toggle("is-hidden", !canViewImportMonth);
    dom.lessonImportViewMonthButton.disabled = !canViewImportMonth;
    dom.lessonImportViewMonthButton.textContent = canViewImportMonth ? `查看收费归属月 ${lastLessonImportResult.authoritativeMonths[0]}` : "查看收费归属月";
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
        renderDialogSummaryRow("预计上课日期月份", formatLessonImportMonthRange(lastLessonImportResult.occurrenceMonths) || "-"),
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
      ${renderLessonImportPreviewCell(row, "lessonVenue", formatLessonVenue(values.lessonDeliveryMode, values.lessonVenue))}
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
      const href = createLessonDetailUrl(row.importResult.createdLessonId, loadedMonth, activeView);
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
    const href = createLessonDetailUrl(lessonId, loadedMonth, activeView);
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
  dom.lessonImportPreviewError.textContent = lessonUserErrorMessage(message, "预定课时导入失败，请检查后重试。");
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
  console.error("Planned lesson import failed", error);
  return lessonUserErrorMessage(error, "预定课时导入失败，请稍后重试。");
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
    lesson_delivery_mode: row.values.lessonDeliveryMode || null,
    lesson_venue: row.values.lessonVenue || null,
    duration_hours: hasLessonImportPreviewValue(row.raw.durationHours) && Number.isFinite(row.values.durationHours) ? row.values.durationHours : null,
    lesson_count: Number.isInteger(row.values.lessonCount) ? row.values.lessonCount : null,
    unit_price: Number.isFinite(row.values.unitPrice) ? row.values.unitPrice : 0,
    lesson_fee: null,
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
    dom.lessonImportPlannedSubmitButton.disabled = true;
    dom.lessonImportPlannedSubmitButton.textContent = "历史导入已停用";
  }
  if (dom.lessonImportViewMonthButton) {
    const canViewImportMonth = !isSubmitting && lastLessonImportResult?.authoritativeMonths?.length === 1;
    dom.lessonImportViewMonthButton.classList.toggle("is-hidden", !canViewImportMonth);
    dom.lessonImportViewMonthButton.disabled = !canViewImportMonth;
    dom.lessonImportViewMonthButton.textContent = canViewImportMonth ? `查看收费归属月 ${lastLessonImportResult.authoritativeMonths[0]}` : "查看收费归属月";
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

function normalizeLessonDeliveryMode(value) {
  const normalized = normalizeLessonImportLookup(importPreviewCellText(value));
  if (["线下", "現地", "onsite", "offline", "教室"].includes(normalized)) return "onsite";
  if (["线上", "線上", "online", "zoom", "远程", "遠隔"].includes(normalized)) return "online";
  return "";
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

function renderLessonRecords(records, options = {}) {
  renderLessonValidationWarning();
  dom.emptyState.textContent = options.emptyMessage || "暂无符合条件的课时记录。";
  dom.emptyState.classList.toggle("is-hidden", records.length > 0);
  syncViewVisibility();

  if (!records.length) {
    dom.tableBody.innerHTML = "";
    dom.pairRows.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = records.map((record) => `
    <tr>
      <td class="lesson-nowrap"><a class="button table-action-button" href="${escapeAttribute(createLessonDetailUrl(record.id, loadedMonth, "list"))}">查看详情</a></td>
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
      <td class="lesson-note-cell">${renderPlannedChargeBreakdown(plannedChargeSource(record))}</td>
      <td class="lesson-content-cell">${escapeHtml(displayValue(record.lesson_content))}</td>
      <td class="lesson-note-cell">${escapeHtml(displayValue(record.note))}</td>
      <td class="lesson-nowrap">${escapeHtml(formatMonth(authoritativeStudentMonth(record)))}</td>
      <td class="lesson-nowrap">${escapeHtml(formatMonth(record.teacher_settlement_month))}</td>
      <td class="number-cell">${escapeHtml(hasFrozenActualOverage(record) ? `${displayValue(record.student_duration_overage_minutes)} 分钟` : "-")}</td>
      <td class="number-cell">${escapeHtml(hasFrozenActualOverage(record) ? formatCurrency(record.student_duration_overage_fee_jpy, "JPY") : "-")}</td>
    </tr>
  `).join("");

  renderLessonPairs(records);
}

function renderLessonValidationWarning() {
  if (!dom.validationWarning) return;
  const rejectedCount = rejectedLessonRecords.length;
  dom.validationWarning.classList.toggle("is-hidden", rejectedCount === 0);
  dom.validationWarning.textContent = rejectedCount
    ? `有 ${rejectedCount} 条课时的权威月份证据异常，已隐藏异常记录；其余合法记录和权威统计继续显示。请联系管理员核查。`
    : "";
  if (rejectedCount) {
    console.warn("Rejected lesson-management rows", rejectedLessonRecords);
  }
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
        <div class="lesson-pair-column-title">预定课时</div>
        ${renderLessonPairCard(pair.planned, "planned")}
      </div>
      <div class="lesson-pair-column lesson-pair-column-actual">
        <div class="lesson-pair-column-title">实际课时</div>
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
    : '<div class="lesson-pair-placeholder">关联：无对应预定课时</div>';

  return `
    <article class="lesson-pair-row lesson-pair-row-unlinked">
      <div class="lesson-pair-column lesson-pair-column-empty">
        <div class="lesson-pair-column-title">预定课时</div>
        ${plannedHtml}
      </div>
      <div class="lesson-pair-column lesson-pair-column-actual">
        <div class="lesson-pair-column-title">实际课时</div>
        ${renderLessonPairCard(actual, "actual")}
      </div>
    </article>
  `;
}

function renderCrossMonthMakeupCompletedReferenceCard(actual) {
  const monthSemantics = buildLessonMonthSemantics(actual);
  return `
    <article class="lesson-pair-card lesson-pair-card-makeup lesson-pair-card-reference">
      <div class="lesson-pair-card-header">
        <div>
          <a class="button table-action-button" href="${escapeAttribute(createLessonDetailUrl(actual.id, loadedMonth, "pair"))}">查看详情</a>
        </div>
        <span class="status-badge ${escapeAttribute(statusClass(actual.status))}">已于 ${escapeHtml(formatMonth(authoritativeStudentMonth(actual)))} 完成</span>
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
        <div><dt>学生结算月</dt><dd>${escapeHtml(formatMonth(monthSemantics.studentSettlementMonth))}</dd></div>
        <div><dt>老师工资月</dt><dd>${escapeHtml(formatMonth(monthSemantics.teacherWageMonth))}</dd></div>
      </dl>
      <div class="lesson-pair-reference-note">来源：跨月补课；原月份预定课时保持不变。</div>
    </article>
  `;
}

function renderCrossMonthMakeupSourceReferenceCard(sourcePlanned) {
  return `
    <article class="lesson-pair-card lesson-pair-card-reference">
      <div class="lesson-pair-card-header">
        <div>
          <a class="button table-action-button" href="${escapeAttribute(createLessonDetailUrl(sourcePlanned.id, loadedMonth, "pair"))}">查看详情</a>
        </div>
        <span class="status-badge ${escapeAttribute(statusClass(sourcePlanned.status))}">来源：${escapeHtml(formatMonth(authoritativeStudentMonth(sourcePlanned)))} 待补课</span>
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
      <div class="lesson-pair-reference-note">来源：跨月补课；当前月份只保存已补课记录。</div>
    </article>
  `;
}

function renderOtherLessonRow(record) {
  return `
    <article class="lesson-pair-row lesson-pair-row-unlinked">
      <div class="lesson-pair-column lesson-pair-column-empty">
        <div class="lesson-pair-column-title">预定课时</div>
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
  const statusText = planned.status === "pending_makeup" ? "待补课，尚无实际课时" : "尚无实际课时";
  let actionHtml = "";
  if (planned.status === "planned" && canGenerateActualFromPlanned(planned)) {
    const actions = [
      `<button class="button button-primary table-action-button" type="button" data-generate-actual-id="${escapeAttribute(planned.id)}">生成实际</button>`,
    ];
    if (canMarkCancelledActualFromPlanned(planned)) {
      actions.push(
        `<button class="button table-action-button" type="button" data-generate-cancelled-actual-id="${escapeAttribute(planned.id)}">标记取消并转待补课</button>`
      );
    }
    actionHtml = actions.join("");
  } else if (planned.status === "pending_makeup" && canGenerateActualFromPlanned(planned)) {
    actionHtml = `<button class="button button-primary table-action-button" type="button" data-generate-makeup-actual-id="${escapeAttribute(planned.id)}">登记补课完成</button>`;
  }
  return `
    <div class="lesson-pair-placeholder">
      <span>${escapeHtml(statusText)}</span>
      <span>关联：无对应实际课时</span>
      ${actionHtml ? `<div class="lesson-pair-placeholder-actions">${actionHtml}</div>` : ""}
    </div>
  `;
}

function canMarkCancelledActualFromPlanned(planned) {
  return currentUserCanMarkLessonCancelled()
    && planned?.lesson_type === "planned"
    && planned.status === "planned"
    && !isVoidedPlanned(planned)
    && !linkedActualForPlannedLesson(planned.id);
}

function canGenerateActualFromPlanned(planned) {
  return planned
    && planned.lesson_type === "planned"
    && ["planned", "pending_makeup"].includes(planned.status)
    && !isVoidedPlanned(planned);
}

function renderLessonEditAction(record) {
  if (record?.tuition_history_state_available === false) {
    return "";
  }
  if (hasTuitionRevisionHistory(record)) {
    return "";
  }
  return lessonEditController?.renderAction(record) || "";
}

function renderLessonDeleteAction(record) {
  if (record?.tuition_history_state_available === false) {
    return "";
  }
  if (hasTuitionRevisionHistory(record)) {
    return "";
  }
  return lessonDeleteController?.renderAction(record) || "";
}

function renderLessonVoidAction(record) {
  if (record?.tuition_history_state_available === false) {
    return "";
  }
  if (!hasVoidedOnlyTuitionHistory(record)) {
    return "";
  }
  return lessonVoidController?.renderAction(record) || "";
}

function hasTuitionRevisionHistory(record) {
  return record?.lesson_type === "planned" && Number(record.tuition_revision_count || 0) > 0;
}

function hasVoidedOnlyTuitionHistory(record) {
  return hasTuitionRevisionHistory(record)
    && Number(record.voided_tuition_revision_count || 0) > 0
    && Number(record.active_tuition_revision_count || 0) === 0;
}

function renderLessonActions(record) {
  return [
    renderLessonEditAction(record),
    renderLessonVoidAction(record),
    renderLessonDeleteAction(record),
  ].filter(Boolean).join(" ");
}

function hasLinkedActualLesson(plannedLessonId) {
  const hasSameMonthActual = lessonRecords.some((record) => (
    record.lesson_type === "actual"
    && record.planned_lesson_id === plannedLessonId
  ));
  const hasCrossMonthActual = (crossMonthMakeupReferences.actualsBySourcePlannedId.get(plannedLessonId) || []).length > 0;
  return hasSameMonthActual || hasCrossMonthActual;
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
  const monthSemantics = buildLessonMonthSemantics(record);
  const sourcePlanned = isActual ? plannedLessonForActual(record) : null;

  return `
    <article class="lesson-pair-card ${escapeAttribute(modifierClass)}">
      <div class="lesson-pair-card-header">
        <div>
          <a class="button table-action-button" href="${escapeAttribute(createLessonDetailUrl(record.id, loadedMonth, "pair"))}">查看详情</a>
          ${renderLessonActions(record)}
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
        ${renderPlannedChargeMeta(isActual ? sourcePlanned : record, isActual)}
        <div><dt>${isActual ? "学生结算月" : "学生收费月"}</dt><dd>${escapeHtml(formatMonth(monthSemantics.studentSettlementMonth))}</dd></div>
        ${isActual ? `<div><dt>老师工资月</dt><dd>${escapeHtml(formatMonth(monthSemantics.teacherWageMonth))}</dd></div>` : ""}
        <div><dt>关联</dt><dd>${escapeHtml(lessonPairRelationLabel(record))}</dd></div>
      </dl>
      ${isActual ? renderActualOverageDetails(record, sourcePlanned) : ""}
      ${renderLessonPairText(record)}
    </article>
  `;
}

function plannedLessonForActual(actual) {
  if (!actual?.planned_lesson_id) {
    return null;
  }
  return lessonRecords.find((record) => record.id === actual.planned_lesson_id)
    || crossMonthMakeupReferences.sourcePlannedById.get(actual.planned_lesson_id)
    || null;
}

function plannedChargeSource(record) {
  if (record?.lesson_type === "planned") {
    return record;
  }
  return record?.lesson_type === "actual" ? plannedLessonForActual(record) : null;
}

function renderPlannedChargeBreakdown(record) {
  if (!hasAuthoritativePlannedFeeBundle(record)) {
    return escapeHtml(`基础课时费 ${formatCurrency(record?.lesson_fee, "JPY")}`);
  }
  if (!shouldDisplayPlannedAirconDetails(record)) {
    return escapeHtml(`基础课时费 ${formatCurrency(record.base_lesson_fee_jpy, "JPY")}`);
  }
  const applicability = plannedAirconConditionLabel(record);
  return [
    `基础 ${formatCurrency(record.base_lesson_fee_jpy, "JPY")}`,
    `费率 ${formatCurrency(record.aircon_unit_price_jpy_snapshot, "JPY")} / h`,
    applicability,
    `计费小时 ${displayValue(record.aircon_billable_hours_snapshot)} 小时`,
    `空调 ${formatCurrency(record.aircon_fee_jpy, "JPY")}`,
    `总价 ${formatCurrency(record.lesson_total_fee_jpy, "JPY")}`,
  ].map((value) => `<div>${escapeHtml(value)}</div>`).join("");
}

function renderPlannedChargeMeta(record, isSourcePlanned = false) {
  if (!record) {
    return isSourcePlanned
      ? '<div><dt>来源 planned 空调费</dt><dd>-</dd></div>'
      : "";
  }
  if (!hasAuthoritativePlannedFeeBundle(record)) {
    return `<div><dt>${isSourcePlanned ? "来源 planned 基础课时费" : "基础课时费"}</dt><dd>${escapeHtml(formatCurrency(record.lesson_fee, "JPY"))}</dd></div>`;
  }
  if (!shouldDisplayPlannedAirconDetails(record)) {
    return `<div><dt>${isSourcePlanned ? "来源 planned 基础课时费" : "基础课时费"}</dt><dd>${escapeHtml(formatCurrency(record.base_lesson_fee_jpy, "JPY"))}</dd></div>`;
  }
  const prefix = isSourcePlanned ? "来源 planned " : "";
  const applicability = plannedAirconConditionLabel(record);
  return `
    <div><dt>${prefix}基础课时费</dt><dd>${escapeHtml(formatCurrency(record.base_lesson_fee_jpy, "JPY"))}</dd></div>
    <div><dt>${prefix}空调费率</dt><dd>${escapeHtml(`${formatCurrency(record.aircon_unit_price_jpy_snapshot, "JPY")} / h`)}</dd></div>
    <div><dt>${prefix}空调条件</dt><dd>${escapeHtml(applicability)}</dd></div>
    <div><dt>${prefix}空调计费小时</dt><dd>${escapeHtml(`${displayValue(record.aircon_billable_hours_snapshot)} 小时`)}</dd></div>
    <div><dt>${prefix}空调费</dt><dd>${escapeHtml(formatCurrency(record.aircon_fee_jpy, "JPY"))}</dd></div>
    <div><dt>${prefix}课程总价</dt><dd>${escapeHtml(formatCurrency(record.lesson_total_fee_jpy, "JPY"))}</dd></div>
  `;
}

function renderActualOverageDetails(actual, planned) {
  const overage = buildActualOverageDisplay(actual, planned);
  if (!overage) {
    return "";
  }

  return `
    <div class="lesson-overage-summary">
      <strong>冻结超额收费</strong>
      <span>计划 ${escapeHtml(displayValue(overage.plannedDurationHours))} 小时 / 实际 ${escapeHtml(displayValue(overage.actualDurationHours))} 小时</span>
      <span>超出 ${escapeHtml(displayValue(overage.overageMinutes))} 分钟</span>
      <span>冻结金额 ${escapeHtml(formatCurrency(overage.frozenFeeJpy, "JPY"))}</span>
      <span>来源学生月 ${escapeHtml(formatMonth(overage.sourceStudentMonth))}</span>
      <span>下一学生结算月（来源月锁定后结转）${escapeHtml(formatMonth(overage.nextStudentSettlementMonth))}</span>
    </div>
  `;
}

function lessonPairRelationLabel(record) {
  if (!record) {
    return "-";
  }

  if (record.lesson_type === "planned") {
    const hasSameMonthActual = hasLinkedActualLesson(record.id);
    const hasCrossMonthActual = (crossMonthMakeupReferences.actualsBySourcePlannedId.get(record.id) || []).length > 0;
    if (hasSameMonthActual || hasCrossMonthActual) {
      return "有对应实际课时";
    }
    return "无对应实际课时";
  }

  if (record.lesson_type === "actual") {
    if (!record.planned_lesson_id) {
      return "无对应预定课时";
    }
    if (crossMonthMakeupReferences.sourcePlannedById.has(record.planned_lesson_id)) {
      return "跨月补课";
    }
    return "对应预定课时";
  }

  return "-";
}

function renderLessonPairText(record) {
  const content = compactLessonPairText(record.lesson_content);
  const note = compactLessonPairText(record.note);
  const summary = [
    content ? `内容：${content}` : "",
    note ? `备注：${note}` : "",
  ].filter(Boolean).join(" / ");

  if (!summary) {
    return "";
  }

  const preview = summary.length > 96 ? `${summary.slice(0, 96)}...` : summary;
  return `<p class="lesson-pair-summary" title="${escapeAttribute(summary)}">${escapeHtml(preview)}</p>`;
}

function compactLessonPairText(value) {
  return safeText(value).replace(/\s+/g, " ").trim();
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
    return record.is_billable ? "计费（已补课）" : "不计费（已补课）";
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

function isActiveStudent(student) {
  return safeText(student?.status) === "active";
}

function isNewBusinessStudent(student) {
  return isActiveStudent(student) && isNewBusinessEntityId(businessEntities, student?.business_entity_id || "");
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

function authoritativeStudentMonth(record) {
  return safeText(record?.authoritative_student_month);
}

function formatBillingWeekRange(weekStart) {
  if (!isDateInputValue(weekStart)) {
    return "-";
  }
  const start = new Date(`${weekStart}T00:00:00`);
  if (Number.isNaN(start.getTime())) {
    return "-";
  }
  const end = new Date(start.getTime());
  end.setDate(end.getDate() + 6);
  const endValue = `${end.getFullYear()}-${String(end.getMonth() + 1).padStart(2, "0")}-${String(end.getDate()).padStart(2, "0")}`;
  return `${weekStart}至${endValue}`;
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

function formatLessonVenue(mode, venue) {
  const label = mode === "onsite" ? "线下" : mode === "online" ? "线上" : "未设置";
  return safeText(venue) ? `${label} / ${safeText(venue)}` : label;
}

function fixedOnsiteVenueMigrationReason(lesson) {
  if (lesson?.lesson_delivery_mode === "onsite" && !FIXED_ONSITE_LESSON_VENUES.includes(safeText(lesson.lesson_venue))) {
    return "该预定课时仍使用旧线下场地。请先编辑课时，并明确选择 Regus公共区 或 Regus办公室，再生成实际课时。";
  }
  return "";
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

function lastDateOfMonth(yearMonth) {
  const match = safeText(yearMonth).match(/^(\d{4})-(0[1-9]|1[0-2])$/);
  if (!match) {
    return "";
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const date = new Date(year, month, 0);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function isDateInputValue(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(safeText(value));
}

function listDateInputValues(startDate, endDate) {
  if (!isDateInputValue(startDate) || !isDateInputValue(endDate) || startDate > endDate) {
    return [];
  }

  const rows = [];
  const cursor = new Date(`${startDate}T00:00:00`);
  const end = new Date(`${endDate}T00:00:00`);
  while (!Number.isNaN(cursor.getTime()) && cursor <= end) {
    rows.push(`${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, "0")}-${String(cursor.getDate()).padStart(2, "0")}`);
    cursor.setDate(cursor.getDate() + 1);
  }
  return rows;
}

function dateInputWeekday(value) {
  const date = new Date(`${value}T00:00:00`);
  return Number.isNaN(date.getTime()) ? -1 : date.getDay();
}

function mondayOfDateInputValue(value) {
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  const offset = (date.getDay() + 6) % 7;
  date.setDate(date.getDate() - offset);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
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
