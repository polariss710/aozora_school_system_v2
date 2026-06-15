import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { initSchoolAuth, isLoggedIn } from "../auth.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createPartTimeWorkRecord,
  deletePartTimeWorkRecord,
  fetchPartTimeWorkMonthlyStats,
  fetchPartTimeWorkRecords,
  updatePartTimeWorkRecord,
} from "../api/part-time-work-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, safeText } from "../utils/format.js";

const PAYMENT_STATUS_LABELS = {
  unpaid: "未支付",
  paid: "已支付",
  cancelled: "已取消",
};

const WORKPLACE_OPTIONS = ["诺应教育", "致远教育", "新领域"];
const SUBJECT_OPTIONS = [
  "EJU文数班课",
  "EJU理数班课",
  "EJU文数一对一",
  "EJU理数一对一",
  "大学院一对一",
];
const DEFAULT_TEACHER_NAME = "吴峰";
const DEFAULT_VIEW_MODE = "pair";

const SUMMARY_FIELDS = [
  { key: "total_hours", label: "总课时", type: "hours" },
  { key: "lesson_wage_jpy", label: "课时工资", type: "currency" },
  { key: "transportation_fee_jpy", label: "交通费", type: "currency" },
  { key: "adjustment_jpy", label: "调整额", type: "currency" },
  { key: "total_wage_jpy", label: "总工资", type: "currency" },
  { key: "unpaid_wage_jpy", label: "未支付金额", type: "currency" },
  { key: "paid_wage_jpy", label: "已支付金额", type: "currency" },
];

const dom = {};
let records = [];
let editingRecord = null;
let isSubmitting = false;
let activeView = DEFAULT_VIEW_MODE;

export async function initPartTimeWorkPage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  renderOptionSelect(dom.workplaceFilter, WORKPLACE_OPTIONS, { includeAll: true });
  renderOptionSelect(dom.workplaceNameInput, WORKPLACE_OPTIONS);
  renderOptionSelect(dom.subjectNameInput, SUBJECT_OPTIONS);
  bindEvents();
  renderSummary({});
  renderRows([]);

  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。");
    return;
  }

  await initSchoolAuth();
  if (!isLoggedIn()) {
    showMessage("error", "请先登录后查看或编辑私塾打工记录。");
    return;
  }

  loadPageData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#partTimeWorkMessageArea");
  dom.filterForm = document.querySelector("#partTimeWorkFilterForm");
  dom.yearFilter = document.querySelector("#partTimeWorkYearFilter");
  dom.monthFilter = document.querySelector("#partTimeWorkMonthFilter");
  dom.workplaceFilter = document.querySelector("#partTimeWorkWorkplaceFilter");
  dom.paymentStatusFilter = document.querySelector("#partTimeWorkPaymentStatusFilter");
  dom.resetButton = document.querySelector("#partTimeWorkResetButton");
  dom.summaryGrid = document.querySelector("#partTimeWorkSummaryGrid");
  dom.openCreateButton = document.querySelector("#openPartTimeWorkCreateButton");
  dom.recordCount = document.querySelector("#partTimeWorkRecordCount");
  dom.pairViewButton = document.querySelector("#partTimeWorkPairViewButton");
  dom.listViewButton = document.querySelector("#partTimeWorkListViewButton");
  dom.pairView = document.querySelector("#partTimeWorkPairView");
  dom.pairRows = document.querySelector("#partTimeWorkPairRows");
  dom.listView = document.querySelector("#partTimeWorkListView");
  dom.loadingState = document.querySelector("#partTimeWorkLoadingState");
  dom.emptyState = document.querySelector("#partTimeWorkEmptyState");
  dom.tableBody = document.querySelector("#partTimeWorkTableBody");
  dom.dialog = document.querySelector("#partTimeWorkDialog");
  dom.dialogTitle = document.querySelector("#partTimeWorkDialogTitle");
  dom.dialogError = document.querySelector("#partTimeWorkDialogError");
  dom.workDateInput = document.querySelector("#partTimeWorkDateInput");
  dom.workplaceNameInput = document.querySelector("#partTimeWorkWorkplaceInput");
  dom.subjectNameInput = document.querySelector("#partTimeWorkSubjectInput");
  dom.classDescriptionInput = document.querySelector("#partTimeWorkClassDescriptionInput");
  dom.hoursInput = document.querySelector("#partTimeWorkHoursInput");
  dom.hourlyRateInput = document.querySelector("#partTimeWorkHourlyRateInput");
  dom.transportationFeeInput = document.querySelector("#partTimeWorkTransportationFeeInput");
  dom.adjustmentInput = document.querySelector("#partTimeWorkAdjustmentInput");
  dom.memoInput = document.querySelector("#partTimeWorkMemoInput");
  dom.preview = document.querySelector("#partTimeWorkPreview");
  dom.cancelButton = document.querySelector("#partTimeWorkCancelButton");
  dom.submitButton = document.querySelector("#partTimeWorkSubmitButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    loadPageData();
  });

  dom.resetButton.addEventListener("click", () => {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
    dom.workplaceFilter.value = "";
    dom.paymentStatusFilter.value = "";
    loadPageData();
  });

  dom.openCreateButton.addEventListener("click", openCreateDialog);
  dom.cancelButton.addEventListener("click", closeDialog);
  dom.submitButton.addEventListener("click", submitDialog);
  dom.pairRows.addEventListener("click", handleRecordActionClick);
  dom.tableBody.addEventListener("click", handleRecordActionClick);

  for (const button of [dom.pairViewButton, dom.listViewButton]) {
    button.addEventListener("click", () => {
      setActiveView(button.dataset.partTimeWorkView || DEFAULT_VIEW_MODE);
    });
  }

  for (const input of [
    dom.workDateInput,
    dom.workplaceNameInput,
    dom.hoursInput,
    dom.hourlyRateInput,
    dom.transportationFeeInput,
    dom.adjustmentInput,
  ]) {
    input.addEventListener("input", () => {
      clearFieldInvalid(input);
      hideDialogErrorIfClean();
      updatePreview();
    });
  }

  setActiveView(DEFAULT_VIEW_MODE);
}

async function loadPageData() {
  if (!isLoggedIn()) {
    renderSummary({});
    renderRows([]);
    showMessage("error", "请先登录后查看或编辑私塾打工记录。");
    return;
  }

  const filters = readFilters();
  setLoading(true);
  showMessage("", "");

  try {
    const [items, stats] = await Promise.all([
      fetchPartTimeWorkRecords(filters),
      fetchPartTimeWorkMonthlyStats(filters),
    ]);
    records = items || [];
    renderSummary(stats || {});
    renderRows(records);
  } catch (error) {
    renderSummary({});
    renderRows([]);
    showMessage("error", `私塾打工数据读取失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readFilters() {
  return {
    yearMonth: getYearMonthSelectValue(dom.yearFilter, dom.monthFilter),
    workplaceName: dom.workplaceFilter.value,
    paymentStatus: dom.paymentStatusFilter.value,
  };
}

function renderSummary(summary) {
  dom.summaryGrid.innerHTML = SUMMARY_FIELDS.map((field) => {
    const value = summary[field.key];
    const displayValue = field.type === "hours"
      ? `${formatHours(value)} h`
      : formatCurrency(value || 0, "JPY");

    return `
      <article class="summary-card">
        <div class="summary-card-title">${escapeHtml(field.label)}</div>
        <div class="summary-card-value">${escapeHtml(displayValue)}</div>
      </article>
    `;
  }).join("");
}

function renderRows(rows) {
  dom.recordCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);
  dom.tableBody.innerHTML = rows.map(renderRow).join("");
  renderPairRows(rows);
  syncViewVisibility();
}

function renderRow(row) {
  return `
    <tr>
      <td>${escapeHtml(formatDateOnly(row.work_date))}</td>
      <td>${escapeHtml(row.workplace_name || "-")}</td>
      <td>${escapeHtml(row.teacher_name || "-")}</td>
      <td>${escapeHtml(row.subject_name || "-")}</td>
      <td class="description-cell">${escapeHtml(row.class_description || "-")}</td>
      <td class="number-cell">${escapeHtml(formatHours(row.hours))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(row.hourly_rate_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(row.lesson_wage_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(row.transportation_fee_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(row.adjustment_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(row.total_wage_jpy, "JPY"))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.payment_status))}">${escapeHtml(paymentStatusLabel(row.payment_status))}</span></td>
      <td>${escapeHtml(formatDateOnly(row.paid_date))}</td>
      <td class="description-cell">${escapeHtml(row.memo || "-")}</td>
      <td class="action-cell">
        <div class="action-buttons">
          <button class="button table-action-button" type="button" data-part-time-work-edit-id="${escapeAttribute(row.id)}">编辑</button>
          <button class="button button-danger table-action-button" type="button" data-part-time-work-delete-id="${escapeAttribute(row.id)}">删除</button>
        </div>
      </td>
    </tr>
  `;
}

function renderPairRows(rows) {
  const unpaidRows = rows.filter((row) => row.payment_status === "unpaid");
  const completedRows = rows.filter((row) => row.payment_status === "paid" || row.payment_status === "cancelled");
  const leftHtml = unpaidRows.length
    ? unpaidRows.map((row) => renderPairCard(row, "left")).join("")
    : renderPairPlaceholder("暂无未支付 / 待确认记录");
  const rightHtml = completedRows.length
    ? completedRows.map((row) => renderPairCard(row, "right")).join("")
    : renderPairPlaceholder("暂无已支付 / 已完成记录");

  dom.pairRows.innerHTML = `
    <article class="lesson-pair-row part-time-work-pair-row">
      <div class="lesson-pair-column">
        <div class="lesson-pair-column-title">未支付 / 待确认</div>
        <div class="lesson-pair-actual-stack">${leftHtml}</div>
      </div>
      <div class="lesson-pair-column">
        <div class="lesson-pair-column-title">已支付 / 已完成</div>
        <div class="lesson-pair-actual-stack">${rightHtml}</div>
      </div>
    </article>
  `;
}

function renderPairCard(row, side) {
  const modifierClass = row.payment_status === "cancelled"
    ? "lesson-pair-card-cancelled"
    : side === "right"
      ? "lesson-pair-card-makeup"
      : "";

  return `
    <article class="lesson-pair-card part-time-work-pair-card ${escapeAttribute(modifierClass)}">
      <div class="lesson-pair-card-header">
        <div class="action-buttons">
          <button class="button table-action-button" type="button" data-part-time-work-edit-id="${escapeAttribute(row.id)}">编辑</button>
          <button class="button button-danger table-action-button" type="button" data-part-time-work-delete-id="${escapeAttribute(row.id)}">删除</button>
        </div>
        <span class="status-badge ${escapeAttribute(statusClass(row.payment_status))}">${escapeHtml(paymentStatusLabel(row.payment_status))}</span>
      </div>
      <div class="lesson-pair-main">
        <strong>${escapeHtml(formatDateOnly(row.work_date))}</strong>
        <span>${escapeHtml(row.workplace_name || "-")}</span>
        <span>${escapeHtml(row.subject_name || "-")}</span>
      </div>
      <dl class="lesson-pair-meta">
        <div><dt>课时</dt><dd>${escapeHtml(formatHours(row.hours))} h</dd></div>
        <div><dt>时给</dt><dd>${escapeHtml(formatCurrency(row.hourly_rate_jpy, "JPY"))}</dd></div>
        <div><dt>课时工资</dt><dd>${escapeHtml(formatCurrency(row.lesson_wage_jpy, "JPY"))}</dd></div>
        <div><dt>总工资</dt><dd>${escapeHtml(formatCurrency(row.total_wage_jpy, "JPY"))}</dd></div>
      </dl>
      <div class="lesson-pair-text">
        <div class="lesson-pair-text-row">
          <span class="lesson-pair-text-label">内容</span>
          <span class="lesson-pair-text-value">${escapeHtml(row.class_description || "-")}</span>
        </div>
        <div class="lesson-pair-text-row">
          <span class="lesson-pair-text-label">备注</span>
          <span class="lesson-pair-text-value">${escapeHtml(row.memo || "-")}</span>
        </div>
      </div>
    </article>
  `;
}

function renderPairPlaceholder(text) {
  return `<div class="lesson-pair-placeholder">${escapeHtml(text)}</div>`;
}

function setActiveView(view) {
  activeView = view === "list" ? "list" : DEFAULT_VIEW_MODE;
  syncViewVisibility();
}

function syncViewVisibility() {
  const isPairView = activeView === "pair";
  dom.pairView.classList.toggle("is-hidden", !isPairView);
  dom.listView.classList.toggle("is-hidden", isPairView);
  dom.pairViewButton.classList.toggle("is-active", isPairView);
  dom.listViewButton.classList.toggle("is-active", !isPairView);
  dom.pairViewButton.setAttribute("aria-pressed", String(isPairView));
  dom.listViewButton.setAttribute("aria-pressed", String(!isPairView));
}

function openCreateDialog() {
  if (!isLoggedIn()) {
    showMessage("error", "请先登录后新增私塾打工记录。");
    return;
  }

  editingRecord = null;
  dom.dialogTitle.textContent = "新增私塾打工记录";
  clearDialog();
  dom.workDateInput.value = todayDate();
  updatePreview();
  showDialog();
}

function openEditDialog(record) {
  editingRecord = record;
  dom.dialogTitle.textContent = "编辑私塾打工记录";
  clearDialog();
  dom.workDateInput.value = record.work_date || "";
  setSelectValueWithFallback(dom.workplaceNameInput, record.workplace_name || "");
  setSelectValueWithFallback(dom.subjectNameInput, record.subject_name || "");
  dom.classDescriptionInput.value = record.class_description || "";
  dom.hoursInput.value = record.hours ?? 0;
  dom.hourlyRateInput.value = record.hourly_rate_jpy ?? 0;
  dom.transportationFeeInput.value = record.transportation_fee_jpy ?? 0;
  dom.adjustmentInput.value = record.adjustment_jpy ?? 0;
  dom.memoInput.value = record.memo || "";
  updatePreview();
  showDialog();
}

function closeDialog() {
  if (isSubmitting) {
    return;
  }
  dom.dialog.classList.add("is-hidden");
  dom.dialog.setAttribute("aria-hidden", "true");
}

function showDialog() {
  dom.dialog.classList.remove("is-hidden");
  dom.dialog.setAttribute("aria-hidden", "false");
  dom.workDateInput.focus();
}

async function submitDialog() {
  if (!isLoggedIn()) {
    showDialogError("请先登录后保存私塾打工记录。");
    return;
  }

  const payload = readDialogPayload();
  const validationError = validatePayload(payload);

  if (validationError) {
    showDialogError(validationError);
    return;
  }

  setSubmitting(true);

  try {
    if (editingRecord) {
      await updatePartTimeWorkRecord({ ...payload, id: editingRecord.id });
      showMessage("success", "私塾打工记录已更新。");
    } else {
      await createPartTimeWorkRecord(payload);
      showMessage("success", "私塾打工记录已新增。");
    }
    closeDialogAfterSubmit();
    await loadPageData();
  } catch (error) {
    showDialogError(error.message || String(error));
  } finally {
    setSubmitting(false);
  }
}

async function handleRecordActionClick(event) {
  const editButton = event.target.closest("[data-part-time-work-edit-id]");
  if (editButton) {
    const record = records.find((item) => item.id === editButton.dataset.partTimeWorkEditId);
    if (record) {
      openEditDialog(record);
    }
    return;
  }

  const deleteButton = event.target.closest("[data-part-time-work-delete-id]");
  if (!deleteButton) {
    return;
  }

  const record = records.find((item) => item.id === deleteButton.dataset.partTimeWorkDeleteId);
  if (!record) {
    return;
  }

  const ok = window.confirm(`确认软删除 ${record.workplace_name || "该"} 的 ${formatDateOnly(record.work_date)} 打工记录？`);
  if (!ok) {
    return;
  }

  try {
    if (!isLoggedIn()) {
      showMessage("error", "请先登录后删除私塾打工记录。");
      return;
    }
    await deletePartTimeWorkRecord(record.id);
    showMessage("success", "私塾打工记录已删除。");
    await loadPageData();
  } catch (error) {
    showMessage("error", `私塾打工记录删除失败：${error.message || error}`);
  }
}

function readDialogPayload() {
  return {
    workDate: dom.workDateInput.value,
    workplaceName: dom.workplaceNameInput.value,
    teacherName: editingRecord?.teacher_name || DEFAULT_TEACHER_NAME,
    subjectName: dom.subjectNameInput.value,
    classDescription: dom.classDescriptionInput.value.trim(),
    hours: parseDecimal(dom.hoursInput.value),
    hourlyRateJpy: parseInteger(dom.hourlyRateInput.value),
    transportationFeeJpy: parseInteger(dom.transportationFeeInput.value),
    adjustmentJpy: parseInteger(dom.adjustmentInput.value),
    paymentStatus: editingRecord?.payment_status || "unpaid",
    paidDate: editingRecord?.paid_date || null,
    memo: dom.memoInput.value.trim(),
  };
}

function validatePayload(payload) {
  clearInvalidFields();

  if (!payload.workDate) {
    markFieldInvalid(dom.workDateInput);
    return "请选择工作日期。";
  }

  if (!payload.workplaceName) {
    markFieldInvalid(dom.workplaceNameInput);
    return "请填写打工先。";
  }

  if (!Number.isFinite(payload.hours) || payload.hours < 0) {
    markFieldInvalid(dom.hoursInput);
    return "课时必须是大于等于 0 的数字。";
  }

  if (!Number.isInteger(payload.hourlyRateJpy) || payload.hourlyRateJpy < 0) {
    markFieldInvalid(dom.hourlyRateInput);
    return "时给必须是大于等于 0 的整数。";
  }

  if (!Number.isInteger(payload.transportationFeeJpy) || payload.transportationFeeJpy < 0) {
    markFieldInvalid(dom.transportationFeeInput);
    return "交通费必须是大于等于 0 的整数。";
  }

  if (!Number.isInteger(payload.adjustmentJpy)) {
    markFieldInvalid(dom.adjustmentInput);
    return "调整额必须是整数，可填写负数。";
  }

  const preview = calculatePreview(payload);
  if (preview.totalWageJpy < 0) {
    markFieldInvalid(dom.adjustmentInput);
    return "总工资不能小于 0。";
  }

  return "";
}

function calculatePreview(payload = readDialogPayload()) {
  const hours = Number.isFinite(payload.hours) ? payload.hours : 0;
  const hourlyRate = Number.isFinite(payload.hourlyRateJpy) ? payload.hourlyRateJpy : 0;
  const transportationFee = Number.isFinite(payload.transportationFeeJpy) ? payload.transportationFeeJpy : 0;
  const adjustment = Number.isFinite(payload.adjustmentJpy) ? payload.adjustmentJpy : 0;
  const lessonWageJpy = Math.round(hours * hourlyRate);
  const totalWageJpy = lessonWageJpy + transportationFee + adjustment;

  return { lessonWageJpy, totalWageJpy };
}

function updatePreview() {
  const preview = calculatePreview();
  dom.preview.textContent = `预览：课时工资 ${formatCurrency(preview.lessonWageJpy, "JPY")} / 总工资 ${formatCurrency(preview.totalWageJpy, "JPY")}`;
}

function clearDialog() {
  for (const input of [
    dom.workDateInput,
    dom.workplaceNameInput,
    dom.subjectNameInput,
    dom.classDescriptionInput,
    dom.hoursInput,
    dom.hourlyRateInput,
    dom.transportationFeeInput,
    dom.adjustmentInput,
    dom.memoInput,
  ]) {
    input.value = "";
  }
  dom.hoursInput.value = "0";
  dom.hourlyRateInput.value = "0";
  dom.transportationFeeInput.value = "0";
  dom.adjustmentInput.value = "0";
  dom.workplaceNameInput.value = WORKPLACE_OPTIONS[0];
  dom.subjectNameInput.value = SUBJECT_OPTIONS[0];
  hideDialogError();
  clearInvalidFields();
}

function closeDialogAfterSubmit() {
  dom.dialog.classList.add("is-hidden");
  dom.dialog.setAttribute("aria-hidden", "true");
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
}

function setSubmitting(nextValue) {
  isSubmitting = nextValue;
  dom.submitButton.disabled = nextValue;
  dom.cancelButton.disabled = nextValue;
  dom.submitButton.textContent = nextValue ? "保存中..." : "保存";
}

function showMessage(type, text) {
  if (!text) {
    dom.messageArea.textContent = "";
    dom.messageArea.className = "message is-hidden";
    return;
  }

  dom.messageArea.textContent = text;
  dom.messageArea.className = `message message-${type}`;
}

function showDialogError(text) {
  dom.dialogError.textContent = text;
  dom.dialogError.classList.remove("is-hidden");
}

function hideDialogError() {
  dom.dialogError.textContent = "";
  dom.dialogError.classList.add("is-hidden");
}

function hideDialogErrorIfClean() {
  if (!dom.dialogError.textContent) {
    dom.dialogError.classList.add("is-hidden");
  }
}

function markFieldInvalid(input) {
  input?.closest(".field")?.classList.add("is-invalid");
}

function clearFieldInvalid(input) {
  input?.closest(".field")?.classList.remove("is-invalid");
}

function clearInvalidFields() {
  for (const input of [
    dom.workDateInput,
    dom.workplaceNameInput,
    dom.hoursInput,
    dom.hourlyRateInput,
    dom.transportationFeeInput,
    dom.adjustmentInput,
  ]) {
    clearFieldInvalid(input);
  }
}

function renderOptionSelect(select, options, config = {}) {
  const optionHtml = [];
  if (config.includeAll) {
    optionHtml.push('<option value="">全部</option>');
  }
  optionHtml.push(...options.map((option) => (
    `<option value="${escapeAttribute(option)}">${escapeHtml(option)}</option>`
  )));
  select.innerHTML = optionHtml.join("");
}

function setSelectValueWithFallback(select, value) {
  const normalized = safeText(value);
  if (normalized && !Array.from(select.options).some((option) => option.value === normalized)) {
    select.insertAdjacentHTML(
      "beforeend",
      `<option value="${escapeAttribute(normalized)}">${escapeHtml(normalized)}</option>`
    );
  }
  select.value = normalized || select.options[0]?.value || "";
}

function parseDecimal(value) {
  if (value === "") {
    return 0;
  }
  return Number(value);
}

function parseInteger(value) {
  if (value === "") {
    return 0;
  }
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? Math.round(numberValue) : Number.NaN;
}

function paymentStatusLabel(status) {
  return PAYMENT_STATUS_LABELS[status] || safeText(status) || "-";
}

function statusClass(status) {
  if (status === "paid") return "status-paid";
  if (status === "cancelled") return "status-cancelled";
  if (status === "unpaid") return "status-pending";
  return "status-neutral";
}

function formatHours(value) {
  const numberValue = Number(value || 0);
  if (!Number.isFinite(numberValue)) {
    return "0";
  }
  return numberValue.toLocaleString("zh-CN", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

function formatDateOnly(value) {
  if (!value) {
    return "-";
  }
  return String(value).slice(0, 10);
}

function todayDate() {
  const now = new Date();
  const offset = now.getTimezoneOffset();
  const local = new Date(now.getTime() - offset * 60 * 1000);
  return local.toISOString().slice(0, 10);
}

function escapeHtml(value) {
  return safeText(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function escapeAttribute(value) {
  return escapeHtml(value);
}
