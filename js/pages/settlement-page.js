import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchSettlementBusinessEntities,
  fetchSettlementStudents,
  fetchStudentSettlements,
  lockStudentMonthlySettlement,
} from "../api/settlement-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  studentId: "",
  businessEntityId: "",
  status: "",
  keyword: "",
};

const SETTLEMENT_STATUS_LABELS = {
  locked: "已锁定",
  preview: "未锁定 / 预览",
};

const dom = {};
let students = [];
let businessEntities = [];
let settlements = [];
let loadedMonth = "";
let currentLockSettlement = null;
let isLockSubmitting = false;

export function initSettlementPage() {
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
    renderSettlements([]);
    return;
  }

  loadInitialData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#settlementMessageArea");
  dom.filterForm = document.querySelector("#settlementFilterForm");
  dom.yearFilter = document.querySelector("#settlementYearFilter");
  dom.monthFilter = document.querySelector("#settlementMonthFilter");
  dom.studentSelect = document.querySelector("#settlementStudentSelect");
  dom.businessEntitySelect = document.querySelector("#settlementBusinessEntitySelect");
  dom.statusSelect = document.querySelector("#settlementStatusSelect");
  dom.keywordInput = document.querySelector("#settlementKeywordInput");
  dom.resetButton = document.querySelector("#settlementResetButton");
  dom.tableBody = document.querySelector("#settlementTableBody");
  dom.loadingState = document.querySelector("#settlementLoadingState");
  dom.emptyState = document.querySelector("#settlementEmptyState");
  dom.settlementCount = document.querySelector("#settlementCount");
  dom.lockDialog = document.querySelector("#lockSettlementDialog");
  dom.lockSummary = document.querySelector("#lockSettlementSummary");
  dom.lockError = document.querySelector("#lockSettlementError");
  dom.lockNoteInput = document.querySelector("#lockSettlementNoteInput");
  dom.lockConfirmCheckbox = document.querySelector("#lockSettlementConfirmCheckbox");
  dom.lockSubmitButton = document.querySelector("#lockSettlementSubmitButton");
  dom.lockCancelButton = document.querySelector("#lockSettlementCancelButton");
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

  dom.tableBody.addEventListener("click", (event) => {
    const button = event.target.closest("[data-lock-settlement-id]");
    if (!button) {
      return;
    }
    openLockDialog(button.dataset.lockSettlementId);
  });

  dom.lockCancelButton?.addEventListener("click", () => closeLockDialog());
  dom.lockSubmitButton?.addEventListener("click", handleLockSubmit);
  dom.lockDialog?.addEventListener("click", (event) => {
    if (event.target === dom.lockDialog) {
      closeLockDialog();
    }
  });
  dom.lockNoteInput?.addEventListener("input", () => hideLockErrorIfClean());
  dom.lockConfirmCheckbox?.addEventListener("change", () => {
    clearLockFieldInvalid("confirm");
    hideLockErrorIfClean();
  });
}

function setDefaultFilters() {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  dom.studentSelect.value = DEFAULT_FILTERS.studentId;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载学生月度结算数据...");

  try {
    [students, businessEntities] = await Promise.all([
      fetchSettlementStudents(),
      fetchSettlementBusinessEntities(),
    ]);

    renderMasterOptions();
    await loadSettlementMonth(currentYearMonth());
    applyCurrentFilters();
    showMessage("success", "学生月度结算数据已加载。");
  } catch (error) {
    students = [];
    businessEntities = [];
    settlements = [];
    loadedMonth = "";
    renderMasterOptions();
    renderStatusOptions([]);
    renderSettlements([]);
    showMessage("error", `读取学生月度结算数据失败：${error.message || error}`);
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
    showMessage("info", "正在加载学生月度结算记录...");

    try {
      await loadSettlementMonth(filters.month);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "学生月度结算记录已加载。");
    } catch (error) {
      settlements = [];
      loadedMonth = "";
      renderStatusOptions([]);
      renderSettlements([]);
      showMessage("error", `读取学生月度结算记录失败：${error.message || error}`);
    } finally {
      setLoading(false);
    }
    return;
  }

  applyCurrentFilters();
}

async function loadSettlementMonth(month) {
  settlements = sortSettlements(await fetchStudentSettlements(month));
  loadedMonth = month;
  renderStatusOptions(settlements);
}

function applyCurrentFilters() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  restoreFilterSelections(filters);
  renderSettlements(filterSettlements(settlements, filters));
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
    businessEntityId: dom.businessEntitySelect.value,
    status: dom.statusSelect.value,
    keyword: dom.keywordInput.value.trim(),
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.studentSelect.value = filters.studentId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.statusSelect.value = filters.status;
  dom.keywordInput.value = filters.keyword;
}

function renderMasterOptions() {
  renderEntityOptions(dom.studentSelect, students, studentName);
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
}

function renderStatusOptions(rows) {
  const options = ['<option value="">全部</option>'];

  for (const value of distinctValues(rows, "settlement_status")) {
    options.push(
      `<option value="${escapeAttribute(value)}">${escapeHtml(settlementStatusLabel(value))}</option>`
    );
  }

  dom.statusSelect.innerHTML = options.join("");
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

function renderSettlements(rows) {
  dom.settlementCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td class="settlement-nowrap">${renderSettlementDetailAction(row)}</td>
      <td class="settlement-nowrap">${escapeHtml(formatMonth(row.year_month))}</td>
      <td>${escapeHtml(nameById(students, row.student_id, studentName))}</td>
      <td>${escapeHtml(nameById(businessEntities, row.business_entity_id, businessEntityName))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.settlement_status))}">${escapeHtml(settlementStatusLabel(row.settlement_status))}</span></td>
      <td class="number-cell settlement-nowrap">${escapeHtml(displayValue(row.preset_exchange_rate))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.planned_lesson_fee_jpy, "JPY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.planned_lesson_fee_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.actual_lesson_fee_jpy, "JPY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.actual_lesson_fee_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.previous_balance_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.received_jpy, "JPY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.received_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.received_equivalent_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.system_difference_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.adjustment_amount_cny, "CNY"))}</td>
      <td class="number-cell settlement-nowrap">${escapeHtml(formatCurrency(row.carryover_amount_cny, "CNY"))}</td>
      <td class="settlement-nowrap">${escapeHtml(formatDate(row.locked_at))}</td>
      <td class="settlement-note-cell">${escapeHtml(noteText(row))}</td>
    </tr>
  `).join("");
}

function renderSettlementDetailAction(row) {
  if (row.is_preview) {
    return `
      <div class="table-action-group">
        <span class="status-badge status-pending">预览</span>
        <button class="button table-action-button button-primary" type="button" data-lock-settlement-id="${escapeAttribute(row.id)}">锁定</button>
      </div>
    `;
  }

  return `<a class="table-action-button" href="./settlement-detail.html?id=${encodeURIComponent(row.id)}">详情</a>`;
}

function openLockDialog(settlementRowId) {
  if (!hasSupabaseConfig()) {
    showMessage("error", "当前 Supabase 配置不可用，不能锁定学生月度结算。");
    return;
  }

  const row = settlements.find((item) => item.id === settlementRowId);
  if (!row || !row.is_preview) {
    showMessage("error", "未找到可锁定的实时预览记录。");
    return;
  }

  currentLockSettlement = row;
  dom.lockNoteInput.value = "";
  dom.lockConfirmCheckbox.checked = false;
  clearLockErrors();
  renderLockSummary(row);
  setLockSubmitting(false);
  dom.lockDialog.classList.remove("is-hidden");
  dom.lockDialog.setAttribute("aria-hidden", "false");
  dom.lockConfirmCheckbox.focus();
}

function closeLockDialog(force = false) {
  if (isLockSubmitting && !force) {
    return;
  }

  dom.lockDialog?.classList.add("is-hidden");
  dom.lockDialog?.setAttribute("aria-hidden", "true");
  currentLockSettlement = null;
  clearLockErrors();
}

function renderLockSummary(row) {
  dom.lockSummary.innerHTML = [
    ["学生", nameById(students, row.student_id, studentName)],
    ["结算月份", formatMonth(row.year_month)],
    ["业务归属", nameById(businessEntities, row.business_entity_id, businessEntityName)],
    ["预定课时费", formatCurrency(row.planned_lesson_fee_jpy, "JPY")],
    ["实际课时费", formatCurrency(row.actual_lesson_fee_jpy, "JPY")],
    ["系统差额", formatCurrency(row.system_difference_cny, "CNY")],
  ].map(([label, value]) => `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(displayValue(value))}</span>
    </div>
  `).join("");
}

async function handleLockSubmit() {
  if (isLockSubmitting) {
    return;
  }

  clearLockErrors();

  if (!currentLockSettlement) {
    showLockError("未找到可锁定的实时预览记录。");
    return;
  }

  if (!dom.lockConfirmCheckbox.checked) {
    setLockFieldInvalid("confirm", true);
    showLockError("请先勾选确认后再锁定。");
    return;
  }

  setLockSubmitting(true);

  try {
    const sourceRow = currentLockSettlement;
    const result = await lockStudentMonthlySettlement({
      studentId: sourceRow.student_id,
      yearMonth: sourceRow.year_month,
      note: dom.lockNoteInput.value.trim(),
    });
    closeLockDialog(true);
    await loadSettlementMonth(sourceRow.year_month);
    applyCurrentFilters();
    showMessage("success", `学生月度结算已锁定：${shortId(result?.settlement_id || result?.id)}。`);
  } catch (error) {
    showLockError(error.message || String(error));
  } finally {
    setLockSubmitting(false);
  }
}

function setLockSubmitting(isSubmitting) {
  isLockSubmitting = isSubmitting;
  if (dom.lockSubmitButton) {
    dom.lockSubmitButton.disabled = isSubmitting;
    dom.lockSubmitButton.textContent = isSubmitting ? "锁定中..." : "确认锁定";
  }
  if (dom.lockCancelButton) {
    dom.lockCancelButton.disabled = isSubmitting;
  }
}

function showLockError(message) {
  dom.lockError.textContent = message;
  dom.lockError.classList.remove("is-hidden");
}

function clearLockErrors() {
  dom.lockError.textContent = "";
  dom.lockError.classList.add("is-hidden");
  clearLockFieldInvalid("confirm");
}

function hideLockErrorIfClean() {
  if (!dom.lockDialog?.querySelector(".field.is-invalid")) {
    dom.lockError.textContent = "";
    dom.lockError.classList.add("is-hidden");
  }
}

function setLockFieldInvalid(fieldId, invalid) {
  const field = dom.lockDialog?.querySelector(`[data-lock-settlement-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", invalid);
}

function clearLockFieldInvalid(fieldId) {
  setLockFieldInvalid(fieldId, false);
}

function filterSettlements(rows, filters) {
  return rows.filter((row) => {
    if (filters.studentId && row.student_id !== filters.studentId) {
      return false;
    }

    if (filters.businessEntityId && row.business_entity_id !== filters.businessEntityId) {
      return false;
    }

    if (filters.status && row.settlement_status !== filters.status) {
      return false;
    }

    return matchesKeyword(row, filters.keyword);
  });
}

function matchesKeyword(row, keyword) {
  if (!keyword) {
    return true;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return [
    nameById(students, row.student_id, studentName),
    nameById(businessEntities, row.business_entity_id, businessEntityName),
    settlementStatusLabel(row.settlement_status),
    row.settlement_status,
    row.note,
    row.adjustment_reason,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function sortSettlements(rows) {
  return [...rows].sort((left, right) => {
    const studentCompare = nameById(students, left.student_id, studentName)
      .localeCompare(nameById(students, right.student_id, studentName), "zh-CN");
    if (studentCompare !== 0) {
      return studentCompare;
    }

    const businessCompare = nameById(businessEntities, left.business_entity_id, businessEntityName)
      .localeCompare(nameById(businessEntities, right.business_entity_id, businessEntityName), "zh-CN");
    if (businessCompare !== 0) {
      return businessCompare;
    }

    return safeText(left.locked_at).localeCompare(safeText(right.locked_at));
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

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
}

function settlementStatusLabel(value) {
  return SETTLEMENT_STATUS_LABELS[value] || displayValue(value);
}

function statusClass(status) {
  if (status === "preview") {
    return "status-pending";
  }
  return status === "locked" ? "status-paid" : "status-neutral";
}

function noteText(row) {
  return displayValue([row.note, row.adjustment_reason].filter(Boolean).join(" / "));
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
