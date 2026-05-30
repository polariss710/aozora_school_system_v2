import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchBusinessEntitiesForTeachers,
  fetchTeacherFilterOptions,
  fetchTeachers,
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
};

const dom = {};
let businessEntities = [];

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
    renderTeachers(filterTeachersByKeyword(teacherRows, filters.keyword));
    showMessage("success", "老师管理数据已加载。");
  } catch (error) {
    businessEntities = [];
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
