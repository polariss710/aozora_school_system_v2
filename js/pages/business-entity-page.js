import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchBusinessEntities } from "../api/business-entity-api.js";
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

const dom = {};
let allBusinessEntities = [];

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
