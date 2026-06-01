import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchWageRuleLookups, fetchWageRules } from "../api/wage-rule-api.js";
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

const TEACHER_STATUS_LABELS = {
  employed: "在职",
  inactive: "停用",
  retired: "退职",
};

const dom = {};
let wageRules = [];
let teachers = [];
let students = [];
let subjects = [];
let businessEntities = [];

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
