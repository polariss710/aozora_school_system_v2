import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchWageBusinessEntities,
  fetchWageDetailFeeSummaries,
  fetchWageLocks,
  fetchWagePaymentRequests,
  fetchWageTeachers,
  generateTeacherMonthlyWage,
} from "../api/wage-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  teacherId: "",
  businessEntityId: "",
  settlementType: "",
  status: "",
  keyword: "",
};

const WAGE_STATUS_LABELS = {
  locked: "已生成快照",
  void: "已作废",
};

const PAYMENT_REQUEST_STATUS_LABELS = {
  pending: "待支付",
  paid: "已支付",
  reversed: "已撤销",
  void: "已作废",
  cancelled: "已取消",
};

const SETTLEMENT_TYPE_LABELS = {
  jpy_hourly: "日元时给",
  no_wage: "无工资",
};

const dom = {};
let teachers = [];
let businessEntities = [];
let wageLocks = [];
let wagePaymentRequests = [];
let loadedMonth = "";
let activeFilters = null;
let startupFilters = null;

export function initWagePage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  startupFilters = readFiltersFromUrl();
  setDefaultFilters(startupFilters);
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderWageLocks([]);
    return;
  }

  loadInitialData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#wageMessageArea");
  dom.filterForm = document.querySelector("#wageFilterForm");
  dom.yearFilter = document.querySelector("#wageYearFilter");
  dom.monthFilter = document.querySelector("#wageMonthFilter");
  dom.teacherSelect = document.querySelector("#wageTeacherSelect");
  dom.businessEntitySelect = document.querySelector("#wageBusinessEntitySelect");
  dom.settlementTypeSelect = document.querySelector("#wageSettlementTypeSelect");
  dom.statusSelect = document.querySelector("#wageStatusSelect");
  dom.keywordInput = document.querySelector("#wageKeywordInput");
  dom.resetButton = document.querySelector("#wageResetButton");
  dom.tableBody = document.querySelector("#wageTableBody");
  dom.loadingState = document.querySelector("#wageLoadingState");
  dom.emptyState = document.querySelector("#wageEmptyState");
  dom.wageCount = document.querySelector("#wageCount");
  dom.exportMonthlySummaryButton = document.querySelector("#wageMonthlySummaryExportButton");
  dom.openGenerateDialogButton = document.querySelector("#openWageGenerateDialogButton");
  dom.generateDialog = document.querySelector("#wageGenerateDialog");
  dom.generateSummary = document.querySelector("#wageGenerateSummary");
  dom.generateError = document.querySelector("#wageGenerateError");
  dom.generateConfirmCheckbox = document.querySelector("#wageGenerateConfirmCheckbox");
  dom.generateSubmitButton = document.querySelector("#wageGenerateSubmitButton");
  dom.generateCancelButton = document.querySelector("#wageGenerateCancelButton");
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

  dom.openGenerateDialogButton?.addEventListener("click", openGenerateDialog);
  dom.exportMonthlySummaryButton?.addEventListener("click", handleMonthlySummaryExport);
  dom.generateCancelButton?.addEventListener("click", closeGenerateDialog);
  dom.generateSubmitButton?.addEventListener("click", handleGenerateSubmit);
  dom.generateDialog?.addEventListener("click", (event) => {
    if (event.target === dom.generateDialog) {
      closeGenerateDialog();
    }
  });
  dom.generateConfirmCheckbox?.addEventListener("change", () => {
    setGenerateFieldInvalid("confirm", false);
    hideGenerateErrorIfClean();
  });
}

function setDefaultFilters(overrides = null) {
  const filters = {
    ...DEFAULT_FILTERS,
    ...(overrides || {}),
    month: overrides?.month || currentYearMonth(),
  };

  restoreFilterSelections(filters);
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载老师工资结算数据...");

  try {
    [teachers, businessEntities] = await Promise.all([
      fetchWageTeachers(),
      fetchWageBusinessEntities(),
    ]);

    renderMasterOptions();
    const filters = {
      ...DEFAULT_FILTERS,
      ...(startupFilters || {}),
      month: startupFilters?.month || currentYearMonth(),
    };
    restoreFilterSelections(filters);
    await loadWageMonth(filters.month);
    restoreFilterSelections(filters);
    applyCurrentFilters();
    showMessage("success", "老师工资结算数据已加载。");
  } catch (error) {
    teachers = [];
    businessEntities = [];
    wageLocks = [];
    loadedMonth = "";
    renderMasterOptions();
    renderDataOptions([]);
    renderWageLocks([]);
    showMessage("error", `读取老师工资结算数据失败：${error.message || error}`);
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
    showMessage("info", "正在加载老师工资快照记录...");

    try {
      await loadWageMonth(filters.month);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "老师工资快照记录已加载。");
    } catch (error) {
      wageLocks = [];
      loadedMonth = "";
      renderDataOptions([]);
      renderWageLocks([]);
      showMessage("error", `读取老师工资快照记录失败：${error.message || error}`);
    } finally {
      setLoading(false);
    }
    return;
  }

  applyCurrentFilters();
}

function openGenerateDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  const filters = readFilters();
  if (!filters) {
    return;
  }

  hideGenerateError();
  setGenerateFieldInvalid("confirm", false);
  dom.generateConfirmCheckbox.checked = false;
  dom.generateSummary.innerHTML = renderGenerateSummary(filters);
  dom.generateDialog.classList.remove("is-hidden");
  dom.generateDialog.setAttribute("aria-hidden", "false");
}

function closeGenerateDialog(force = false) {
  if (!force && dom.generateSubmitButton.disabled) {
    return;
  }

  dom.generateDialog.classList.add("is-hidden");
  dom.generateDialog.setAttribute("aria-hidden", "true");
  hideGenerateError();
  setGenerateFieldInvalid("confirm", false);
  dom.generateConfirmCheckbox.checked = false;
}

async function handleGenerateSubmit() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  if (!dom.generateConfirmCheckbox.checked) {
    showGenerateError("请先勾选确认说明。", ["confirm"]);
    return;
  }

  setGenerateSubmitting(true);
  hideGenerateError();

  try {
    const generatedRows = await generateTeacherMonthlyWage({
      yearMonth: filters.month,
      teacherId: filters.teacherId || null,
    });

    await loadWageMonth(filters.month);
    restoreFilterSelections(filters);
    applyCurrentFilters();
    closeGenerateDialog(true);
    showMessage("success", formatGenerateSuccess(generatedRows));
  } catch (error) {
    showGenerateError(formatGenerateError(error));
  } finally {
    setGenerateSubmitting(false);
  }
}

async function loadWageMonth(month) {
  const [locks, paymentRequests] = await Promise.all([
    fetchWageLocks(month),
    fetchWagePaymentRequests(month),
  ]);

  wageLocks = sortWageLocks(locks);
  wagePaymentRequests = paymentRequests;
  loadedMonth = month;
  renderDataOptions(wageLocks);
}

function applyCurrentFilters() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  restoreFilterSelections(filters);
  activeFilters = filters;
  updateUrlFromFilters(filters);
  renderWageLocks(filterWageLocks(wageLocks, filters));
}

function readFilters() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    showMessage("error", "请选择正确的年月。");
    return null;
  }

  return {
    month,
    teacherId: dom.teacherSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    settlementType: dom.settlementTypeSelect.value,
    status: dom.statusSelect.value,
    keyword: dom.keywordInput.value.trim(),
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.teacherSelect.value = filters.teacherId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.settlementTypeSelect.value = filters.settlementType;
  dom.statusSelect.value = filters.status;
  dom.keywordInput.value = filters.keyword;
}

function renderMasterOptions() {
  renderEntityOptions(dom.teacherSelect, teachers, teacherName);
  renderEntityOptions(dom.businessEntitySelect, businessEntities, businessEntityName);
}

function renderDataOptions(rows) {
  renderValueOptions(dom.settlementTypeSelect, distinctValues(rows, "settlement_type"), settlementTypeLabel);
  renderWageStatusOptions(distinctValues(rows, "status"));
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

function renderWageStatusOptions(values) {
  const normalizedValues = Array.from(new Set(["locked", "void", ...values.filter(Boolean)]));
  const options = ['<option value="">默认（不显示已作废）</option>'];

  for (const value of normalizedValues) {
    options.push(
      `<option value="${escapeAttribute(value)}">${escapeHtml(wageStatusLabel(value))}</option>`
    );
  }

  dom.statusSelect.innerHTML = options.join("");
}

function renderWageLocks(rows) {
  dom.wageCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);
  dom.emptyState.textContent = buildWageEmptyStateText(rows);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td class="wage-nowrap"><a class="table-action-button" href="${escapeAttribute(buildWageDetailHref(row.id))}">详情</a></td>
      <td class="wage-nowrap">${escapeHtml(formatMonth(row.settlement_month))}</td>
      <td>${escapeHtml(displayTeacherName(row))}</td>
      <td>${escapeHtml(displayBusinessName(row))}</td>
      <td><span class="status-badge status-neutral">${escapeHtml(settlementTypeLabel(row.settlement_type))}</span></td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(wageStatusLabel(row.status))}</span></td>
      <td>${renderWageProcessState(row)}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(displayValue(row.exchange_rate))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(displayValue(row.lesson_count))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(displayValue(row.total_minutes))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(displayValue(row.pay_hours))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.fee_jpy, "JPY"))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.lesson_wage_jpy, "JPY"))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.lesson_wage_cny, "CNY"))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.total_jpy, "JPY"))}</td>
      <td class="number-cell wage-nowrap">${escapeHtml(formatCurrency(row.total_cny, "CNY"))}</td>
      <td class="wage-nowrap">${escapeHtml(formatDate(row.locked_at))}</td>
      <td class="wage-nowrap">${escapeHtml(formatDate(row.voided_at))}</td>
    </tr>
  `).join("");
}

function renderWageProcessState(row) {
  const state = wageProcessState(row);
  return `
    <span
      class="status-badge ${escapeAttribute(state.className)}"
      title="${escapeAttribute(state.title)}"
    >${escapeHtml(state.label)}</span>
  `;
}

function wageProcessState(row) {
  if (row.voided_at || row.status === "void") {
    return {
      label: "只读 / 已作废",
      className: "status-void",
      title: "已作废的工资快照不能调整或生成支付请求。",
    };
  }

  if (row.status !== "locked") {
    return {
      label: "只读",
      className: "status-neutral",
      title: "只有已生成且未作废的工资快照可以继续处理。",
    };
  }

  const requests = paymentRequestsForWageLock(row.id);
  if (requests.length > 0) {
    const status = effectivePaymentRequestStatus(requests);
    return {
      label: `只读 / ${paymentRequestStatusLabel(status)}`,
      className: paymentRequestStatusClass(status),
      title: "该工资快照已生成支付请求，明细调整和重复生成支付请求入口会在详情页关闭。",
    };
  }

  if (Number(row.total_jpy || 0) <= 0) {
    return {
      label: "可调整 / 无可支付金额",
      className: "status-neutral",
      title: "未生成支付请求，可调整明细；当前合计为 0，详情页不会显示生成支付请求入口。",
    };
  }

  return {
    label: "可调整 / 可生成支付",
    className: "status-paid",
    title: "未生成支付请求，可在详情页调整明细或生成支付请求。",
  };
}

function paymentRequestsForWageLock(wageLockId) {
  return wagePaymentRequests.filter((request) => request.source_id === wageLockId);
}

function effectivePaymentRequestStatus(requests) {
  if (requests.some((request) => request.status === "paid")) return "paid";
  if (requests.some((request) => request.status === "pending")) return "pending";
  if (requests.some((request) => request.status === "reversed")) return "reversed";
  if (requests.some((request) => request.status === "cancelled")) return "cancelled";
  if (requests.some((request) => request.status === "void")) return "void";
  return requests[requests.length - 1]?.status || "";
}

async function handleMonthlySummaryExport() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  if (!window.XLSX?.utils?.aoa_to_sheet || !window.XLSX?.writeFile) {
    showMessage("error", "Excel 导出库尚未加载，请刷新页面后重试。");
    return;
  }

  const filters = readFilters();
  if (!filters) {
    return;
  }

  if (filters.month !== loadedMonth) {
    showMessage("error", "请先查询当前筛选月份，再导出月度汇总。");
    return;
  }

  const rows = effectiveMonthlyWageLocks();
  if (!rows.length) {
    showMessage("error", `${formatMonth(filters.month)} 没有可导出的未作废工资快照。`);
    return;
  }

  setMonthlyExportSubmitting(true);
  showMessage("info", "正在生成老师工资月度汇总 Excel...");

  try {
    const feeSummaries = await fetchWageDetailFeeSummaries(rows.map((row) => row.id));
    exportMonthlySummaryWorkbook({
      month: filters.month,
      rows,
      feeSummaries,
    });
    showMessage("success", "老师工资月度汇总 Excel 已导出。");
  } catch (error) {
    showMessage("error", `导出老师工资月度汇总失败：${error.message || error}`);
  } finally {
    setMonthlyExportSubmitting(false);
  }
}

function effectiveMonthlyWageLocks() {
  return sortWageLocks(wageLocks).filter((row) => row.status !== "void" && !row.voided_at);
}

function exportMonthlySummaryWorkbook({ month, rows, feeSummaries }) {
  const xlsx = window.XLSX;
  const workbook = xlsx.utils.book_new();
  const report = buildMonthlySummaryReport({ month, rows, feeSummaries });
  const sheet = xlsx.utils.aoa_to_sheet(report.rows);

  sheet["!merges"] = report.merges.map((range) => xlsx.utils.decode_range(range));
  sheet["!cols"] = [
    { wch: 10 },
    { wch: 14 },
    { wch: 16 },
    { wch: 22 },
    { wch: 10 },
    { wch: 14 },
    { wch: 14 },
    { wch: 14 },
    { wch: 16 },
    { wch: 16 },
    { wch: 14 },
    { wch: 14 },
    { wch: 14 },
    { wch: 34 },
  ];
  sheet["!rows"] = report.rows.map((_, index) => ({ hpt: index === 0 ? 26 : index <= 3 ? 20 : 18 }));

  styleMonthlySummarySheet(sheet, report);
  xlsx.utils.book_append_sheet(workbook, sheet, "月度汇总");
  xlsx.writeFile(workbook, buildMonthlySummaryFileName(month), {
    bookType: "xlsx",
    cellStyles: true,
  });
}

function buildMonthlySummaryReport({ month, rows, feeSummaries }) {
  const exportRows = rows.map((row, index) => buildMonthlySummaryRow(row, index + 1, feeSummaries));
  const header = [
    "序号",
    "月份",
    "老师",
    "业务归属",
    "结算课时合计",
    "课时工资 JPY",
    "交通费 JPY",
    "教室费 JPY",
    "调整后费用合计 JPY",
    "调整后应付合计 JPY",
    "处理状态",
    "支付请求状态",
    "支付/确认日期",
    "备注",
  ];

  const firstDataRowNumber = 5;
  const totalRowNumber = firstDataRowNumber + exportRows.length;
  const rowsWithSummary = [
    [`老师工资月度汇总 / ${formatMonth(month)}`, "", "", "", "", "", "", "", "", "", "", "", "", ""],
    ["用途", "发工资前内部核对", "", "导出范围", "当前月份未作废工资快照", "", "", "生成时间", formatDate(new Date().toISOString()), "", "", "", "", ""],
    ["说明", "本表来自已保存工资快照和同月 teacher_wage 支付请求；不包含系统 UUID，不代表重新计算结果。", "", "", "", "", "", "", "", "", "", "", "", ""],
    header,
    ...exportRows,
    [
      "合计",
      "",
      "",
      "",
      { f: `SUM(E${firstDataRowNumber}:E${totalRowNumber - 1})` },
      { f: `SUM(F${firstDataRowNumber}:F${totalRowNumber - 1})` },
      { f: `SUM(G${firstDataRowNumber}:G${totalRowNumber - 1})` },
      { f: `SUM(H${firstDataRowNumber}:H${totalRowNumber - 1})` },
      { f: `SUM(I${firstDataRowNumber}:I${totalRowNumber - 1})` },
      { f: `SUM(J${firstDataRowNumber}:J${totalRowNumber - 1})` },
      "",
      "",
      "",
      "",
    ],
  ];

  return {
    rows: rowsWithSummary,
    firstDataRowIndex: firstDataRowNumber - 1,
    totalRowIndex: totalRowNumber - 1,
    merges: [
      "A1:N1",
      "B2:C2",
      "E2:G2",
      "I2:N2",
      "B3:N3",
    ],
  };
}

function buildMonthlySummaryRow(row, index, feeSummaries) {
  const paymentRequests = paymentRequestsForWageLock(row.id);
  const paymentStatus = effectivePaymentRequestStatus(paymentRequests);
  const paymentRequest = effectivePaymentRequest(paymentRequests);
  const processState = wageProcessState(row);
  const feeSummary = feeSummaries.get(row.id) || {
    transportFeeJpy: 0,
    classroomFeeJpy: 0,
  };
  const transportFeeJpy = roundNumber(feeSummary.transportFeeJpy);
  const classroomFeeJpy = roundNumber(feeSummary.classroomFeeJpy);
  const feeTotalJpy = roundNumber(transportFeeJpy + classroomFeeJpy);

  return [
    index,
    formatMonth(row.settlement_month),
    displayTeacherName(row),
    displayBusinessName(row),
    numberOrZero(row.pay_hours),
    roundNumber(row.lesson_wage_jpy),
    transportFeeJpy,
    classroomFeeJpy,
    feeTotalJpy,
    roundNumber(row.total_jpy),
    processState.label,
    paymentStatus ? paymentRequestStatusLabel(paymentStatus) : "未生成支付请求",
    dateOnly(paymentRequest?.paid_at),
    monthlySummaryNote(row, paymentStatus),
  ];
}

function effectivePaymentRequest(requests) {
  return requests.find((request) => request.status === "paid")
    || requests.find((request) => request.status === "pending")
    || requests.find((request) => request.status === "reversed")
    || requests.find((request) => request.status === "cancelled")
    || requests.find((request) => request.status === "void")
    || requests[requests.length - 1]
    || null;
}

function monthlySummaryNote(row, paymentStatus) {
  if (!paymentStatus && Number(row.total_jpy || 0) <= 0) {
    return "0 元快照，无可支付金额；如需支付请先在详情页受控调整。";
  }

  if (!paymentStatus) {
    return "未生成支付请求；发工资前仍可在详情页受控调整。";
  }

  if (paymentStatus === "pending") {
    return "已生成支付请求，工资明细只读；请到老师工资支付模块确认。";
  }

  if (paymentStatus === "paid") {
    return "已支付，工资明细只读。";
  }

  return "存在支付请求历史，工资明细只读；请按支付流程处理。";
}

function styleMonthlySummarySheet(sheet, report) {
  const allRange = `A1:N${report.rows.length}`;
  const baseStyle = {
    font: { name: "Arial", sz: 10 },
    alignment: { vertical: "center", wrapText: true },
    border: {
      top: { style: "thin", color: { rgb: "D9D9D9" } },
      bottom: { style: "thin", color: { rgb: "D9D9D9" } },
      left: { style: "thin", color: { rgb: "D9D9D9" } },
      right: { style: "thin", color: { rgb: "D9D9D9" } },
    },
  };
  const headerStyle = {
    ...baseStyle,
    font: { name: "Arial", sz: 10, bold: true },
    fill: { fgColor: { rgb: "D9EAF7" } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
  };
  const totalStyle = {
    ...baseStyle,
    font: { name: "Arial", sz: 10, bold: true },
    fill: { fgColor: { rgb: "E2F0D9" } },
  };

  applyCellStyle(sheet, allRange, baseStyle);
  applyCellStyle(sheet, "A1:N1", {
    ...baseStyle,
    font: { name: "Arial", sz: 16, bold: true },
    fill: { fgColor: { rgb: "D9EAF7" } },
    alignment: { horizontal: "center", vertical: "center" },
  });
  applyCellStyle(sheet, "A2:N3", {
    ...baseStyle,
    fill: { fgColor: { rgb: "F7F9FC" } },
  });
  applyCellStyle(sheet, "A4:N4", headerStyle);
  applyCellStyle(sheet, `A${report.totalRowIndex + 1}:N${report.totalRowIndex + 1}`, totalStyle);

  applyNumberFormat(sheet, `E${report.firstDataRowIndex + 1}:E${report.totalRowIndex + 1}`, "0.##");
  applyNumberFormat(sheet, `F${report.firstDataRowIndex + 1}:J${report.totalRowIndex + 1}`, "#,##0");

  for (let row = report.firstDataRowIndex + 1; row <= report.totalRowIndex; row += 1) {
    const processCell = sheet[`K${row}`];
    const paymentCell = sheet[`L${row}`];
    if (safeText(processCell?.v).includes("只读")) {
      processCell.s = { ...(processCell.s || {}), fill: { fgColor: { rgb: "FFF2CC" } } };
    }
    if (safeText(processCell?.v).includes("可调整")) {
      processCell.s = { ...(processCell.s || {}), fill: { fgColor: { rgb: "E2F0D9" } } };
    }
    if (safeText(paymentCell?.v).includes("已支付")) {
      paymentCell.s = { ...(paymentCell.s || {}), fill: { fgColor: { rgb: "D9EAD3" } } };
    } else if (safeText(paymentCell?.v).includes("待支付")) {
      paymentCell.s = { ...(paymentCell.s || {}), fill: { fgColor: { rgb: "FFF2CC" } } };
    }
  }

  sheet["!autofilter"] = {
    ref: `A4:N${report.totalRowIndex + 1}`,
  };
  sheet["!freeze"] = { xSplit: 0, ySplit: 4 };
}

function renderGenerateSummary(filters) {
  const teacherLabel = filters.teacherId ? teacherNameById(filters.teacherId) : "全部老师";

  return [
    renderDialogSummaryRow("工资月份", formatMonth(filters.month)),
    renderDialogSummaryRow("生成范围", teacherLabel),
    renderDialogSummaryRow("生成内容", "工资快照主表 + 工资明细"),
    renderDialogSummaryRow("支付/账户", "不生成支付请求、支出或账户流水"),
  ].join("");
}

function filterWageLocks(rows, filters) {
  return rows.filter((row) => {
    if (filters.teacherId && row.teacher_id !== filters.teacherId) {
      return false;
    }

    if (filters.businessEntityId && row.business_entity_id !== filters.businessEntityId) {
      return false;
    }

    if (filters.settlementType && row.settlement_type !== filters.settlementType) {
      return false;
    }

    if (filters.status && row.status !== filters.status) {
      return false;
    }

    if (!filters.status && row.status === "void") {
      return false;
    }

    return matchesKeyword(row, filters.keyword);
  });
}

function readFiltersFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const year = safeText(params.get("year")).trim();
  const monthPart = safeText(params.get("month")).trim();
  const parsedMonth = year && monthPart ? `${year}-${monthPart.padStart(2, "0")}` : "";

  const filters = {
    month: /^\d{4}-(0[1-9]|1[0-2])$/.test(parsedMonth) ? parsedMonth : "",
    teacherId: safeText(params.get("teacherId")).trim(),
    businessEntityId: safeText(params.get("businessEntityId")).trim(),
    settlementType: safeText(params.get("settlementType")).trim(),
    status: safeText(params.get("status")).trim(),
    keyword: safeText(params.get("keyword")).trim(),
  };

  const hasAnyFilter = Object.values(filters).some(Boolean);
  return hasAnyFilter ? filters : null;
}

function updateUrlFromFilters(filters) {
  if (!window.history?.replaceState) {
    return;
  }

  const url = new URL(window.location.href);
  const params = buildWageFilterParams(filters);
  url.search = params.toString();
  window.history.replaceState({}, "", url);
}

function buildWageDetailHref(wageLockId) {
  const params = new URLSearchParams();
  params.set("id", wageLockId);

  for (const [key, value] of buildWageFilterParams(activeFilters).entries()) {
    params.set(key, value);
  }

  return `./wage-detail.html?${params.toString()}`;
}

function buildWageFilterParams(filters) {
  const params = new URLSearchParams();
  const [year = "", monthPart = ""] = safeText(filters?.month).split("-");

  if (year && monthPart) {
    params.set("year", year);
    params.set("month", monthPart);
  }

  appendFilterParam(params, "teacherId", filters?.teacherId);
  appendFilterParam(params, "businessEntityId", filters?.businessEntityId);
  appendFilterParam(params, "settlementType", filters?.settlementType);
  appendFilterParam(params, "status", filters?.status);
  appendFilterParam(params, "keyword", filters?.keyword);

  return params;
}

function setMonthlyExportSubmitting(isSubmitting) {
  if (dom.exportMonthlySummaryButton) {
    dom.exportMonthlySummaryButton.disabled = isSubmitting;
    dom.exportMonthlySummaryButton.textContent = isSubmitting ? "导出中..." : "月度汇总导出";
  }
  if (dom.openGenerateDialogButton) {
    dom.openGenerateDialogButton.disabled = isSubmitting;
  }
}

function appendFilterParam(params, key, value) {
  const text = safeText(value).trim();
  if (text) {
    params.set(key, text);
  }
}

function matchesKeyword(row, keyword) {
  if (!keyword) {
    return true;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return [
    displayTeacherName(row),
    teacherNameById(row.teacher_id),
    displayBusinessName(row),
    businessNameById(row.business_entity_id),
    settlementTypeLabel(row.settlement_type),
    row.settlement_type,
    wageStatusLabel(row.status),
    row.status,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function sortWageLocks(rows) {
  return [...rows].sort((left, right) => {
    const teacherCompare = displayTeacherName(left).localeCompare(displayTeacherName(right), "zh-CN");
    if (teacherCompare !== 0) {
      return teacherCompare;
    }

    const businessCompare = displayBusinessName(left).localeCompare(displayBusinessName(right), "zh-CN");
    if (businessCompare !== 0) {
      return businessCompare;
    }

    const typeCompare = safeText(left.settlement_type).localeCompare(safeText(right.settlement_type), "zh-CN");
    if (typeCompare !== 0) {
      return typeCompare;
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

function displayTeacherName(row) {
  return safeText(row.teacher_name) || teacherNameById(row.teacher_id);
}

function displayBusinessName(row) {
  return safeText(row.business_name) || businessNameById(row.business_entity_id);
}

function teacherNameById(id) {
  const teacher = teachers.find((item) => item.id === id);
  if (!teacher) {
    return id ? "未知" : "未设置";
  }

  return teacherName(teacher);
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

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
}

function settlementTypeLabel(value) {
  return SETTLEMENT_TYPE_LABELS[value] || displayValue(value);
}

function wageStatusLabel(value) {
  return WAGE_STATUS_LABELS[value] || displayValue(value);
}

function paymentRequestStatusLabel(value) {
  return PAYMENT_REQUEST_STATUS_LABELS[value] || displayValue(value);
}

function paymentRequestStatusClass(value) {
  if (value === "paid") return "status-paid";
  if (value === "pending") return "status-pending";
  if (value === "reversed" || value === "cancelled" || value === "void") return "status-cancelled";
  return "status-neutral";
}

function statusClass(status) {
  if (status === "locked") {
    return "status-paid";
  }

  if (status === "void") {
    return "status-void";
  }

  return "status-neutral";
}

function displayValue(value) {
  return safeText(value) || "-";
}

function numberOrZero(value) {
  const numberValue = Number(value || 0);
  return Number.isFinite(numberValue) ? numberValue : 0;
}

function roundNumber(value) {
  return Math.round(numberOrZero(value));
}

function dateOnly(value) {
  const text = safeText(value);
  if (!text) {
    return "";
  }
  return text.slice(0, 10);
}

function buildMonthlySummaryFileName(month) {
  const normalizedMonth = formatMonth(month).replaceAll("/", "-");
  return `老师工资_${sanitizeFileName(normalizedMonth)}_月度汇总.xlsx`;
}

function sanitizeFileName(value) {
  return safeText(value).replace(/[\\/:*?"<>|]/g, "-").trim();
}

function applyCellStyle(sheet, range, style) {
  const decodedRange = window.XLSX.utils.decode_range(range);
  for (let row = decodedRange.s.r; row <= decodedRange.e.r; row += 1) {
    for (let column = decodedRange.s.c; column <= decodedRange.e.c; column += 1) {
      const address = window.XLSX.utils.encode_cell({ r: row, c: column });
      if (!sheet[address]) {
        sheet[address] = { t: "s", v: "" };
      }
      sheet[address].s = { ...(sheet[address].s || {}), ...style };
    }
  }
}

function applyNumberFormat(sheet, range, format) {
  const decodedRange = window.XLSX.utils.decode_range(range);
  for (let row = decodedRange.s.r; row <= decodedRange.e.r; row += 1) {
    for (let column = decodedRange.s.c; column <= decodedRange.e.c; column += 1) {
      const address = window.XLSX.utils.encode_cell({ r: row, c: column });
      if (sheet[address]) {
        sheet[address].z = format;
      }
    }
  }
}

function formatGenerateSuccess(rows) {
  const count = rows.length;
  const totalLessons = rows.reduce((sum, row) => sum + Number(row.lesson_count || 0), 0);
  const totalMinutes = rows.reduce((sum, row) => sum + Number(row.total_minutes || 0), 0);
  const totalJpy = rows.reduce((sum, row) => sum + Number(row.total_jpy || 0), 0);

  return `老师工资已生成：${count} 条工资快照，${totalLessons} 条明细，${totalMinutes} 分钟，合计 ${formatCurrency(totalJpy, "JPY")}。`;
}

function formatGenerateError(error) {
  const message = error?.message || String(error || "");

  if (message.includes("已有工资记录") || message.includes("已经进入老师工资明细")) {
    return `生成失败：该月份已有工资记录或课时已进入工资明细，不能重复生成。${message}`;
  }

  if (message.includes("缺少老师/学生/科目/业务归属/实际分钟")) {
    return `生成失败：存在缺少老师/学生/科目/业务归属/实际分钟的 actual 课时。请先在课时管理补齐本月 completed / makeup_completed actual 课时的实际分钟，再重新生成工资快照。${message}`;
  }

  return `生成失败：${message}`;
}

function buildWageEmptyStateText(rows) {
  if (rows.length > 0) {
    return "";
  }

  if (wageLocks.length === 0 && loadedMonth) {
    return `${formatMonth(loadedMonth)} 尚未生成老师工资快照。本页只显示已生成快照；请确认本月 actual completed / makeup_completed 课时已写入实际分钟后，再使用“生成老师工资”。`;
  }

  return "暂无符合当前筛选条件的老师工资快照。";
}

function setGenerateSubmitting(isSubmitting) {
  dom.generateSubmitButton.disabled = isSubmitting;
  dom.generateCancelButton.disabled = isSubmitting;
  dom.openGenerateDialogButton.disabled = isSubmitting;
  dom.generateSubmitButton.textContent = isSubmitting ? "生成中..." : "确认生成";
}

function showGenerateError(message, fieldIds = []) {
  dom.generateError.textContent = message;
  dom.generateError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setGenerateFieldInvalid(fieldId, true);
  }
  dom.generateDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function hideGenerateError() {
  dom.generateError.textContent = "";
  dom.generateError.classList.add("is-hidden");
}

function hideGenerateErrorIfClean() {
  const hasInvalidField = Boolean(dom.generateDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    hideGenerateError();
  }
}

function setGenerateFieldInvalid(fieldId, isInvalid) {
  const field = dom.generateDialog.querySelector(`[data-wage-generate-field="${fieldId}"]`);
  field?.classList.toggle("is-invalid", isInvalid);
}

function renderDialogSummaryRow(label, value) {
  return `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">${escapeHtml(label)}</span>
      <span>${escapeHtml(value)}</span>
    </div>
  `;
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
  if (dom.exportMonthlySummaryButton) {
    dom.exportMonthlySummaryButton.disabled = isLoading;
  }
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
