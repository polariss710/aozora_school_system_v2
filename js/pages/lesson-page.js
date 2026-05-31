import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
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
  planned: "计划",
  completed: "已完成",
  pending_makeup: "待补课",
  makeup_completed: "补课完成",
  cancelled: "已取消",
};

const dom = {};
let students = [];
let teachers = [];
let subjects = [];
let businessEntities = [];
let lessonRecords = [];
let loadedMonth = "";

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
  dom.tableBody = document.querySelector("#lessonTableBody");
  dom.loadingState = document.querySelector("#lessonLoadingState");
  dom.emptyState = document.querySelector("#lessonEmptyState");
  dom.lessonCount = document.querySelector("#lessonCount");
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

function renderLessonRecords(records) {
  dom.lessonCount.textContent = `${records.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", records.length > 0);

  if (!records.length) {
    dom.tableBody.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = records.map((record) => `
    <tr>
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
