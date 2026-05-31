import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchSubjects } from "../api/subject-api.js";
import { formatDate, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  keyword: "",
  activeState: "",
  primaryCategory: "",
  category: "",
  tertiaryCategory: "",
};

const UNSET_VALUE = "__unset__";
const VALID_COLOR_PATTERN = /^#[0-9a-f]{6}$/i;

const dom = {};
let allSubjects = [];

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
  dom.tertiaryCategorySelect = document.querySelector("#subjectTertiaryCategorySelect");
  dom.resetButton = document.querySelector("#subjectResetButton");
  dom.subjectGrid = document.querySelector("#subjectGrid");
  dom.subjectLoadingState = document.querySelector("#subjectLoadingState");
  dom.subjectEmptyState = document.querySelector("#subjectEmptyState");
  dom.subjectCount = document.querySelector("#subjectCount");
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
  dom.activeSelect.value = DEFAULT_FILTERS.activeState;
  dom.primaryCategorySelect.value = DEFAULT_FILTERS.primaryCategory;
  dom.categorySelect.value = DEFAULT_FILTERS.category;
  dom.tertiaryCategorySelect.value = DEFAULT_FILTERS.tertiaryCategory;
}

async function loadSubjectData() {
  if (!hasSupabaseConfig()) {
    return;
  }

  setLoading(true);
  showMessage("info", "正在加载科目管理数据...");

  try {
    allSubjects = sortSubjects(await fetchSubjects());
    renderFilterOptions(allSubjects);
    restoreFilterSelections(readFilters());
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
    tertiaryCategory: dom.tertiaryCategorySelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.keywordInput.value = filters.keyword;
  dom.activeSelect.value = filters.activeState;
  dom.primaryCategorySelect.value = filters.primaryCategory;
  dom.categorySelect.value = filters.category;
  dom.tertiaryCategorySelect.value = filters.tertiaryCategory;
}

function renderFilterOptions(subjects) {
  renderSelectOptions(dom.primaryCategorySelect, subjects, "primary_category");
  renderSelectOptions(dom.categorySelect, subjects, "category");
  renderSelectOptions(dom.tertiaryCategorySelect, subjects, "tertiary_category");
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
  dom.subjectCount.textContent = `${subjects.length} 个`;
  dom.subjectEmptyState.classList.toggle("is-hidden", subjects.length > 0);

  if (!subjects.length) {
    dom.subjectGrid.innerHTML = "";
    return;
  }

  dom.subjectGrid.innerHTML = subjects.map((subject) => {
    const colorValue = normalizedColor(subject.color);
    const colorText = colorValue ? subject.color : "";

    return `
      <article class="subject-card">
        <div class="subject-card-header">
          <div>
            <div class="subject-title">${escapeHtml(displayValue(subject.name))}</div>
            <div class="subject-color-row">
              <span class="subject-color-swatch" style="background-color: ${escapeAttribute(colorValue || "#e5e7eb")}"></span>
              <span>${escapeHtml(displayValue(colorText))}</span>
            </div>
          </div>
          <span class="status-badge ${subject.is_active === false ? "status-inactive" : "status-active"}">
            ${subject.is_active === false ? "停用" : "启用"}
          </span>
        </div>

        <dl class="subject-meta">
          <div>
            <dt>一级分类</dt>
            <dd>${escapeHtml(displayValue(subject.primary_category))}</dd>
          </div>
          <div>
            <dt>分类</dt>
            <dd>${escapeHtml(displayValue(subject.category))}</dd>
          </div>
          <div>
            <dt>三级分类</dt>
            <dd>${escapeHtml(displayValue(subject.tertiary_category))}</dd>
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

    if (!matchesSelectFilter(subject.tertiary_category, filters.tertiaryCategory)) {
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
    subject.tertiary_category,
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

function normalizedColor(value) {
  const color = safeText(value).trim();
  return VALID_COLOR_PATTERN.test(color) ? color : "";
}

function displayValue(value) {
  return safeText(value) || "未设置";
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
