import {
  LESSON_CLEARANCE_DEFAULT_FILTERS,
  LessonClearanceWorkspaceState,
} from "../utils/lesson-clearance-state.js?v=phase2c-d2-a3-clearance-completion-20260818-1";

const ERROR_MESSAGES = new Map([
  ["LESSON_CLEARANCE_SCOPE_MISMATCH", "待补对象与可用超额不属于同一学生或业务范围，当前不能合并清偿。"],
  ["LESSON_CLEARANCE_STUDENT_MISMATCH", "待补对象与可用超额属于不同学生，当前不能合并清偿。"],
  ["LESSON_CLEARANCE_BUSINESS_ENTITY_MISMATCH", "该学生存在不同业务范围的课时余额，当前不能合并清偿，请分别处理。"],
  ["LESSON_CLEARANCE_PRICE_POLICY_REQUIRED", "当前只允许清偿相同单价的课时余额。"],
  ["LESSON_CLEARANCE_PENDING_BALANCE_INSUFFICIENT", "待补对象当前余额不足，请重新加载。"],
  ["LESSON_CLEARANCE_OVERTIME_BALANCE_INSUFFICIENT", "所选超额当前余额不足，请重新加载。"],
  ["LESSON_CLEARANCE_PENDING_ALREADY_ALLOCATED", "该待补对象已被其他清偿流程占用，请重新加载。"],
  ["LESSON_CLEARANCE_OVERTIME_ALREADY_ALLOCATED", "该超额课时已被其他结算或清偿流程占用，当前不可选择。"],
  ["LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_ALLOCATED", "该待补对象已被其他清偿流程占用，请重新加载。"],
  ["LESSON_CLEARANCE_OVERTIME_SOURCE_ALREADY_ALLOCATED", "该超额课时已被其他结算或清偿流程占用，当前不可选择。"],
  ["LESSON_CLEARANCE_PENDING_SOURCE_INVALID", "该待补对象已不符合清偿条件，请重新加载。"],
  ["LESSON_CLEARANCE_OVERTIME_SOURCE_INVALID", "该超额课时已不符合清偿条件，请重新加载。"],
  ["LESSON_CLEARANCE_ACTIVE_VARIANCE_CLAIM", "所选课时余额已被其他结算或清偿流程占用。"],
  ["LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_CLAIMED", "该待补对象已被其他结算或清偿流程占用，当前不可选择。"],
  ["LESSON_CLEARANCE_OVERTIME_SOURCE_ALREADY_CLAIMED", "该超额课时已被其他结算或清偿流程占用，当前不可选择。"],
  ["LESSON_CLEARANCE_REQUEST_IDENTITY_INVALID", "本次核对编号无效，请重新选择清偿对象。"],
  ["LESSON_CLEARANCE_SOURCE_VERSION_MISMATCH", "来源事实已变化，请重新预览。系统不会使用旧预览提交。"],
  ["LESSON_CLEARANCE_PREVIEW_STALE", "来源事实已变化，请重新预览。系统不会使用旧预览提交。"],
  ["LESSON_CLEARANCE_FINGERPRINT_MISMATCH", "来源事实已变化，请重新预览。系统不会使用旧预览提交。"],
  ["LESSON_CLEARANCE_IDEMPOTENCY_CONFLICT", "同一请求编号对应的业务内容不一致，系统已阻止重复提交。"],
  ["LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED", "当前账号权限已停用，不能读取课时余额。"],
  ["LESSON_CLEARANCE_MEMBERSHIP_REQUIRED", "当前账号没有课时余额读取权限。"],
  ["LESSON_CLEARANCE_ROLE_REQUIRED", "当前角色不能核对或提交课时清偿。"],
  ["LESSON_CLEARANCE_ADMIN_REQUIRED", "当前操作必须由active admin执行。"],
  ["LESSON_CLEARANCE_LOCKED_FORWARD_ADMIN_REQUIRED", "涉及已锁定月份的后续调整必须由管理员确认。"],
  ["LESSON_CLEARANCE_FORWARD_ADMIN_REQUIRED", "涉及已锁定月份的后续调整必须由管理员确认。"],
  ["LESSON_CLEARANCE_FIFO_DEVIATION_REASON_REQUIRED", "未采用系统建议顺序时必须填写偏离原因。"],
  ["LESSON_CLEARANCE_FIFO_DEVIATION_REASON_FORBIDDEN", "当前选择与系统建议一致，不应填写偏离原因。请重新核对。"],
  ["LESSON_CLEARANCE_PACKAGE_SOURCE_FORBIDDEN", "套餐权益不能进入普通待补清偿。"],
  ["LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID", "该清偿记录当前不能撤销。"],
  ["LESSON_CLEARANCE_REVERSAL_ADMIN_REQUIRED", "撤销清偿必须由active admin执行。"],
  ["LESSON_CLEARANCE_REVERSAL_REQUIRED_INPUT_MISSING", "请完整填写撤销日期、原因和请求编号。"],
  ["LESSON_CLEARANCE_ALREADY_REVERSED", "该清偿已经撤销，不能重复恢复余额。"],
  ["LESSON_CLEARANCE_REVERSAL_DOWNSTREAM_BLOCKED", "该清偿已被后续流程使用，当前不能撤销。"],
]);

const text = (value) => String(value ?? "");
const escapeHtml = (value) => text(value)
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#039;");
const boolLabel = (value) => value === true ? "是" : value === false ? "否" : "无法证明";
const dateLabel = (value) => text(value) || "-";
const integerLabel = (value) => Number.isFinite(Number(value)) ? String(Number(value)) : "-";
const minutesLabel = (value) => {
  if (!Number.isFinite(Number(value))) return "-";
  const minutes = Number(value);
  const hours = Number((minutes / 60).toFixed(2));
  return `${minutes}分钟（${hours}小时）`;
};
const moneyLabel = (value) => Number.isFinite(Number(value))
  ? `JPY ${Number(value).toLocaleString("ja-JP", { maximumFractionDigits: 2 })}`
  : "-";
const evidenceLabel = (value) => ({
  snapshot: "操作快照",
  immutable_reference: "不可变引用",
  current_reference: "当前主数据引用",
  current_derived: "当前系统核对",
  unavailable: "证据不可用",
}[value] || text(value) || "证据不可用");

const blockerLabel = (code, fallback = "当前不可选择") => ERROR_MESSAGES.get(text(code)) || fallback;

function systemDetails(content, className = "") {
  return `<details class="lesson-clearance-system-details${className ? ` ${className}` : ""}"><summary>系统详情</summary><div class="lesson-clearance-system-details-body">${content}</div></details>`;
}

export function lessonClearanceErrorMessage(error) {
  if (error instanceof Error && error.constructor === Error && !error.code
      && !error.details && !error.hint && /[\u3400-\u9fff]/.test(error.message || "")) {
    return error.message;
  }
  const raw = [error?.code, error?.message || error, error?.details, error?.hint].filter(Boolean).map(text).join(" ");
  for (const [code, message] of ERROR_MESSAGES) {
    if (raw.includes(code)) return message;
  }
  return "系统未能完成本次课时余额操作，请展开系统详情核对原始信息。";
}

export function lessonClearanceErrorTechnicalDetail(error) {
  return [error?.code, error?.message || error, error?.details, error?.hint]
    .filter(Boolean).map(text).join(" · ") || "无可用技术信息";
}

function fact(label, value, detail = "") {
  return `<div class="lesson-clearance-fact"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong>${detail ? `<small>${escapeHtml(detail)}</small>` : ""}</div>`;
}

function pill(label, tone = "") {
  return `<span class="lesson-clearance-pill ${tone ? `is-${tone}` : ""}">${escapeHtml(label)}</span>`;
}

function empty(message) {
  return `<div class="lesson-clearance-empty">${escapeHtml(message)}</div>`;
}

export function createLessonClearanceWorkspace({ api, getRole, onCreateSuccess, onCreateRefreshFailure }) {
  const state = new LessonClearanceWorkspaceState({ role: getRole?.() || "" });
  const dom = {};
  let initialized = false;
  let loadRequestId = 0;
  let crossView = "source";
  const counters = { readers: 0, previews: 0, reversalPreviews: 0, createWriters: 0, reversalWriters: 0, renders: 0 };

  function cacheDom() {
    dom.openButton = document.querySelector("#openLessonClearanceWorkspaceButton");
    dom.dialog = document.querySelector("#lessonClearanceWorkspaceDialog");
    dom.headerClose = document.querySelector("#lessonClearanceWorkspaceCloseButton");
    dom.footerClose = document.querySelector("#lessonClearanceFooterCloseButton");
    dom.message = document.querySelector("#lessonClearanceWorkspaceMessage");
    dom.loading = document.querySelector("#lessonClearanceWorkspaceLoading");
    dom.content = document.querySelector("#lessonClearanceWorkspaceContent");
    dom.summary = document.querySelector("#lessonClearanceSummary");
    dom.filterForm = document.querySelector("#lessonClearanceFilterForm");
    dom.studentFilter = document.querySelector("#lessonClearanceStudentFilter");
    dom.monthFilter = document.querySelector("#lessonClearanceMonthFilter");
    dom.statusFilter = document.querySelector("#lessonClearanceStatusFilter");
    dom.evidenceFilter = document.querySelector("#lessonClearanceEvidenceFilter");
    dom.fifoOnlyFilter = document.querySelector("#lessonClearanceFifoOnlyFilter");
    dom.filterReset = document.querySelector("#lessonClearanceFilterResetButton");
    dom.tabs = document.querySelector("#lessonClearanceTabList");
    dom.tabPanel = document.querySelector("#lessonClearanceTabPanel");
    dom.previewSection = document.querySelector("#lessonClearancePreviewSection");
    dom.selectionPanel = document.querySelector("#lessonClearanceSelectionPanel");
    dom.previewPanel = document.querySelector("#lessonClearancePreviewPanel");
    dom.confirmButton = document.querySelector("#lessonClearanceConfirmButton");
    dom.finalDialog = document.querySelector("#lessonClearanceFinalConfirmDialog");
    dom.finalTitle = document.querySelector("#lessonClearanceFinalConfirmTitle");
    dom.finalMessage = document.querySelector("#lessonClearanceFinalConfirmMessage");
    dom.finalContent = document.querySelector("#lessonClearanceFinalConfirmContent");
    dom.finalClose = document.querySelector("#lessonClearanceFinalConfirmCloseButton");
    dom.finalCancel = document.querySelector("#lessonClearanceFinalConfirmCancelButton");
    dom.finalSubmit = document.querySelector("#lessonClearanceFinalSubmitButton");
    dom.finalActionNote = document.querySelector("#lessonClearanceFinalActionNote");
  }

  function setMessage(type, message) {
    if (!message) {
      dom.message.className = "message is-hidden";
      dom.message.textContent = "";
      return;
    }
    dom.message.className = `message message-${type}`;
    dom.message.textContent = message;
  }

  function setLoading(value) {
    dom.loading.classList.toggle("is-hidden", !value);
  }

  function openDialog() {
    state.setRole(getRole?.() || "");
    state.resetDraftFilters();
    state.appliedFilters = structuredClone(LESSON_CLEARANCE_DEFAULT_FILTERS);
    dom.dialog.classList.remove("is-hidden");
    dom.dialog.setAttribute("aria-hidden", "false");
    dom.content.classList.add("is-hidden");
    setMessage("", "");
    if (!state.capabilities().view) {
      setMessage("error", "当前账号没有可用的课时余额读取权限。页面不会请求或显示候选数据。");
      return;
    }
    loadData();
  }

  function closeDialog(force = false) {
    if (!force && (state.selection.submitting || state.selection.reversalSubmitting)) return;
    loadRequestId += 1;
    state.clearSelection();
    state.data = state.emptyData();
    dom.dialog.classList.add("is-hidden");
    dom.dialog.setAttribute("aria-hidden", "true");
    dom.content.classList.add("is-hidden");
    dom.tabPanel.replaceChildren();
    dom.selectionPanel.replaceChildren();
    dom.previewPanel.replaceChildren();
    setMessage("", "");
    setLoading(false);
    closeFinalDialog(true);
  }

  async function loadData() {
    const requestId = ++loadRequestId;
    setLoading(true);
    setMessage("", "");
    const studentId = state.appliedFilters.studentId || null;
    const yearMonth = state.appliedFilters.settlementMonth || null;
    try {
      counters.readers += 6;
      const [pendingPayload, overagePayload, packagePayload, crossMonthPayload, summary, history] = await Promise.all([
        api.fetchPendingBalances({ studentId, includeActiveClaimed: true }),
        api.fetchAvailableOverages({ studentId, includeActiveClaimed: true }),
        api.fetchPackageCreditLots({ studentId }),
        api.fetchCrossMonthProjection({ studentId, yearMonth }),
        api.fetchDashboardSummary({ studentId }),
        api.fetchHistory({ studentId }),
      ]);
      if (requestId !== loadRequestId) return;
      state.setData({ pendingPayload, overagePayload, packagePayload, crossMonthPayload, summary, history });
      populateFilterOptions();
      syncFilterControls();
      renderAll();
      dom.content.classList.remove("is-hidden");
    } catch (error) {
      if (requestId !== loadRequestId) return;
      state.data = state.emptyData();
      dom.content.classList.add("is-hidden");
      setMessage("error", `课时余额读取失败，当前结果不可用于清偿。${lessonClearanceErrorMessage(error)}`);
    } finally {
      if (requestId === loadRequestId) setLoading(false);
    }
  }

  function optionRows() {
    return [
      ...(state.data.pendingPayload?.items || []),
      ...(state.data.overagePayload?.items || []),
      ...(state.data.packagePayload?.items || []),
      ...(state.data.crossMonthPayload?.items || []),
      ...(state.data.history || []),
    ];
  }

  function populateSelect(select, options, placeholder) {
    const current = select.value;
    select.innerHTML = `<option value="">${escapeHtml(placeholder)}</option>${options
      .map(([value, label]) => `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`)
      .join("")}`;
    select.value = options.some(([value]) => value === current) ? current : "";
  }

  function populateFilterOptions() {
    const rows = optionRows();
    const students = new Map();
    const months = new Set();
    const evidence = new Set();
    rows.forEach((row) => {
      if (row.student_id) students.set(row.student_id, row.student_display_name || row.student_name || "名称不可用");
      [row.source_year_month, row.student_settlement_month, row.actual_month, row.operational_year_month, row.financial_year_month]
        .filter(Boolean).forEach((value) => months.add(value));
      if (typeof row.evidence_status === "string") evidence.add(row.evidence_status);
    });
    populateSelect(dom.studentFilter, [...students].sort((a, b) => a[1].localeCompare(b[1], "zh-CN")), "全部学生");
    populateSelect(dom.monthFilter, [...months].sort().reverse().map((value) => [value, value]), "全部月份");
    populateSelect(dom.evidenceFilter, [...evidence].sort().map((value) => [value, evidenceLabel(value)]), "全部证据");
  }

  function syncFilterControls() {
    const filters = state.draftFilters;
    dom.studentFilter.value = filters.studentId;
    dom.monthFilter.value = filters.settlementMonth;
    dom.statusFilter.value = filters.status;
    dom.evidenceFilter.value = filters.evidenceStatus;
    dom.fifoOnlyFilter.checked = filters.fifoOnly;
  }

  function readDraftFilters() {
    state.setDraftFilter("studentId", dom.studentFilter.value);
    state.setDraftFilter("settlementMonth", dom.monthFilter.value);
    state.setDraftFilter("status", dom.statusFilter.value);
    state.setDraftFilter("evidenceStatus", dom.evidenceFilter.value);
    state.setDraftFilter("fifoOnly", dom.fifoOnlyFilter.checked);
  }

  function renderAll() {
    counters.renders += 1;
    renderSummary();
    renderTabs();
    renderTabPanel();
    renderSelection();
  }

  function markedStateCounts() {
    const rows = [
      ...(state.data.pendingPayload?.items || []),
      ...(state.data.overagePayload?.items || []),
    ];
    return {
      blocked: rows.filter((row) => row.can_be_candidate !== true).length,
      claimed: rows.filter((row) => row.active_claimed === true).length,
      locked: rows.filter((row) => row.is_locked === true).length,
    };
  }

  function renderSummary() {
    const value = state.data.summary || {};
    const marked = markedStateCounts();
    const cards = [
      ["待补对象", integerLabel(value.pending_source_count), "当前余额记录"],
      ["待补余额", minutesLabel(value.pending_remaining_minutes), "当前可用"],
      ["可用超额", integerLabel(value.overage_source_count), "当前余额记录"],
      ["超额余额", minutesLabel(value.available_overtime_minutes), "当前可用"],
      ["套餐批次", integerLabel(value.package_lot_count), "只读隔离"],
      ["套餐余额", minutesLabel(value.package_remaining_minutes), "不参与普通清偿"],
      ["清偿历史", integerLabel(value.history_count), "已建立记录"],
      ["当前不可选择", integerLabel(marked.blocked), "请查看中文原因"],
      ["已被流程占用", integerLabel(marked.claimed), "当前不可选择"],
      ["涉及锁定月份", integerLabel(marked.locked), "可能需要管理员"],
    ];
    dom.summary.innerHTML = cards.map(([label, strong, detail]) => `<div class="lesson-clearance-summary-card"><span>${label}</span><strong>${strong}</strong><small>${detail}</small></div>`).join("");
  }

  function renderTabs() {
    dom.tabs.querySelectorAll("[data-clearance-tab]").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.clearanceTab === state.activeTab);
    });
  }

  function renderTabPanel() {
    const renderers = {
      pending: renderPending,
      overages: renderOverages,
      packages: renderPackages,
      history: renderHistory,
      "cross-month": renderCrossMonth,
    };
    dom.tabPanel.innerHTML = renderers[state.activeTab]();
  }

  function selectAction(kind, id, row) {
    if (!state.capabilities().select) return pill("只读角色", "warning");
    if (row.can_be_candidate !== true) return pill(blockerLabel(row.candidate_blocker_code), "danger");
    const selected = kind === "pending" ? state.selection.pendingId === id : state.selection.overtimeId === id;
    return `<button class="button ${selected ? "button-primary" : ""}" type="button" data-select-clearance-${kind}="${escapeHtml(id)}">${selected ? "已选择" : "选择"}</button>`;
  }

  function renderPending() {
    const rows = state.pendingRows();
    if (!rows.length) return empty("当前筛选下没有普通待补余额。P002不会进入本区。");
    return `<p class="lesson-clearance-guidance"><strong>建议顺序（较早产生的余额优先）</strong>仅供参考，系统不会自动选择待补对象；余额为0的对象不进入列表。</p><div class="lesson-clearance-card-list">${rows.map((row) => {
      const id = row.pending_source_planned_id;
      const status = row.can_be_candidate ? pill("可选择", "ok") : pill(blockerLabel(row.candidate_blocker_code), "danger");
      const mainFacts = [
        ["待补对象日期", dateLabel(row.operational_display_date)], ["学生结算月", row.source_year_month],
        ["初始待补", minutesLabel(row.initial_credit_minutes)], ["已完成补课", minutesLabel(row.makeup_consumed_minutes)],
        ["已清偿", minutesLabel(row.clearance_allocated_minutes)], ["撤销后恢复", minutesLabel(row.clearance_reversed_minutes)],
        ["当前可用余额", minutesLabel(row.currently_allocatable_minutes)], ["可清偿金额", moneyLabel(row.remaining_amount_jpy)],
        ["课时单价", `${moneyLabel(row.unit_price_jpy)}/小时`], ["涉及锁定月份", boolLabel(row.is_locked)],
      ].map(([label, value]) => fact(label, value)).join("");
      const auditFacts = [
        ["待补对象编号", id], ["业务范围编号", row.business_entity_id],
        ["业务范围当前名称", row.business_entity_display_name], ["原计划日期", row.source_lesson_date],
        ["运营日期依据", row.operational_display_date_basis], ["部分履约记录编号", row.origin_partial_actual_id || "无"],
        ["部分履约日期", row.origin_partial_actual_date || "无"], ["日期证据状态", row.origin_evidence_status],
        ["日期解释代码", row.operational_display_explanation], ["对象状态代码", row.source_status],
        ["对象类型代码", row.source_origin_type], ["原始阻断代码", row.candidate_blocker_code || "无"],
        ["锁定证据代码", row.lock_reason_code || "无"], ["余额证据状态", row.evidence_status],
        ["待补对象指纹", row.source_row_md5], ["对象更新时间", row.source_updated_at],
        ["排序时间", row.credit_origin_sort_at], ["排序依据代码", row.credit_origin_sort_source],
      ].map(([label, value]) => fact(label, value)).join("");
      return `<details class="lesson-clearance-source-card" data-clearance-source-id="${escapeHtml(id)}" ${state.shouldOpenRow(row, "pending") ? "open" : ""}><summary><div><strong>${escapeHtml(row.student_display_name || "名称不可用")}</strong><small>${dateLabel(row.operational_display_date)} · ${escapeHtml(row.teacher_display_name || "名称不可用")} / ${escapeHtml(row.subject_display_name || "名称不可用")}</small></div><div><strong>${minutesLabel(row.remaining_minutes)}</strong><small>当前可用余额</small></div><div><strong>${moneyLabel(row.remaining_amount_jpy)}</strong><small>可清偿金额</small></div><div><strong>建议顺序 ${integerLabel(row.fifo_rank)}</strong><small>较早产生的余额优先</small></div>${status}</summary><div class="lesson-clearance-card-body"><div class="lesson-clearance-fact-grid">${mainFacts}</div>${systemDetails(`<div class="lesson-clearance-fact-grid">${auditFacts}</div>`)}<div class="lesson-clearance-card-actions">${selectAction("pending", id, row)}</div></div></details>`;
    }).join("")}</div>`;
  }

  function renderOverages() {
    const rows = state.overageRows();
    if (!rows.length) return empty("当前筛选下没有可用超额事实。");
    return `<p class="lesson-clearance-guidance">可用超额是系统已经核对的课时差额，仍需业务人员明确选择后才能清偿待补对象。</p><div class="lesson-clearance-card-list">${rows.map((row) => {
      const id = row.overtime_source_actual_id;
      const status = row.can_be_candidate ? pill("可选择", "ok") : pill(blockerLabel(row.candidate_blocker_code), "danger");
      const mainFacts = [
        ["实际上课日期", row.actual_lesson_date], ["学生结算月", row.student_settlement_month],
        ["老师工资月", row.teacher_wage_month], ["最初超额", minutesLabel(row.frozen_overtime_minutes)],
        ["已清偿", minutesLabel(row.clearance_allocated_minutes)], ["撤销后恢复", minutesLabel(row.clearance_reversed_minutes)],
        ["当前可用余额", minutesLabel(row.currently_allocatable_minutes)], ["可清偿金额", moneyLabel(row.available_amount_jpy)],
        ["课时单价", `${moneyLabel(row.unit_price_jpy)}/小时`], ["涉及锁定月份", boolLabel(row.is_locked)],
      ].map(([label, value]) => fact(label, value)).join("");
      const auditFacts = [
        ["超额记录编号", id], ["关联计划编号", row.linked_planned_lesson_id],
        ["业务范围编号", row.business_entity_id], ["业务范围当前名称", row.business_entity_display_name],
        ["原始超额分钟", row.frozen_overtime_minutes], ["已占用分钟", row.active_claimed_minutes],
        ["规则版本", row.overage_policy_version], ["产生方式代码", row.overage_source],
        ["原始阻断代码", row.candidate_blocker_code || "无"], ["锁定证据代码", row.lock_reason_code || "无"],
        ["证据状态", row.evidence_status], ["超额记录指纹", row.source_row_md5],
        ["记录更新时间", row.source_updated_at], ["排序时间", row.overtime_sort_at],
        ["排序依据代码", row.overtime_sort_source],
      ].map(([label, value]) => fact(label, value)).join("");
      return `<details class="lesson-clearance-source-card" ${state.shouldOpenRow(row, "overage") ? "open" : ""}><summary><div><strong>${escapeHtml(row.student_display_name || "名称不可用")}</strong><small>${dateLabel(row.actual_lesson_date)} · ${escapeHtml(row.teacher_display_name || "名称不可用")} / ${escapeHtml(row.subject_display_name || "名称不可用")}</small></div><div><strong>${minutesLabel(row.available_minutes)}</strong><small>当前可用余额</small></div><div><strong>${moneyLabel(row.available_amount_jpy)}</strong><small>可清偿金额</small></div><div><strong>建议顺序 ${integerLabel(row.display_rank)}</strong><small>按超额产生时间排序</small></div>${status}</summary><div class="lesson-clearance-card-body"><div class="lesson-clearance-fact-grid">${mainFacts}</div>${systemDetails(`<div class="lesson-clearance-fact-grid">${auditFacts}</div>`)}<div class="lesson-clearance-card-actions">${selectAction("overtime", id, row)}</div></div></details>`;
    }).join("")}</div>`;
  }

  function renderPackages() {
    const rows = state.packageRows();
    if (!rows.length) return empty("当前筛选下没有套餐余额。");
    return `<p class="lesson-clearance-guidance is-package">套餐余额与普通待补余额隔离，当前只能查看，不能用于本工作台的清偿或预约。</p><div class="lesson-clearance-card-list">${rows.map((row) => {
      const mainFacts = [
        ["初始套餐", minutesLabel(row.initial_minutes)], ["已履约消费", minutesLabel(row.consumed_minutes)],
        ["当前套餐余额", minutesLabel(row.remaining_minutes)], ["学生收费月", row.student_settlement_month],
        ["课时单价", `${moneyLabel(row.unit_price_jpy)}/小时`], ["套餐总额", moneyLabel(row.total_amount_jpy)],
      ].map(([label, value]) => fact(label, value)).join("");
      const auditFacts = [
        ["套餐批次编号", row.package_lot_id], ["原计划编号", row.origin_planned_lesson_id],
        ["业务范围编号", row.business_entity_id], ["业务范围当前名称", row.business_entity_display_name],
        ["业务类型代码", row.package_business_type], ["隔离原因代码", row.classification_reason],
        ["只读", row.read_only], ["可消费", row.can_consume], ["可预约", row.can_reserve],
        ["原计划指纹", row.origin_row_md5], ["证据状态", row.evidence_status],
      ].map(([label, value]) => fact(label, value)).join("");
      return `<details class="lesson-clearance-source-card" ${state.shouldOpenRow(row, "package") ? "open" : ""}><summary><div><strong>${escapeHtml(row.student_display_name || "名称不可用")}</strong><small>${escapeHtml(row.package_display_label || "套餐余额")}</small></div><div><strong>${minutesLabel(row.remaining_minutes)}</strong><small>当前套餐余额</small></div><div><strong>${moneyLabel(row.total_amount_jpy)}</strong><small>套餐总额</small></div><div><strong>仅查看</strong><small>不参与普通清偿</small></div>${pill("只读隔离", "warning")}</summary><div class="lesson-clearance-card-body"><div class="lesson-clearance-fact-grid">${mainFacts}</div>${systemDetails(`<div class="lesson-clearance-fact-grid">${auditFacts}</div>`)}</div></details>`;
    }).join("")}</div>`;
  }

  function renderHistory() {
    const rows = state.historyRows();
    if (!rows.length) return empty("尚无课时差额清偿记录。");
    return `<div class="lesson-clearance-card-list">${rows.map((row) => {
      const mainFacts = [
        ["学生", row.student_name || "名称不可用"], ["建立时间", row.created_at],
        ["清偿分钟", minutesLabel(row.allocated_minutes)], ["清偿金额", moneyLabel(row.financial_net_amount_jpy)],
        ["操作月份", row.operational_year_month], ["后续调整月份", row.financial_year_month || "无"],
        ["符合建议顺序", boolLabel(!row.deviated_from_recommendation)], ["同一老师", boolLabel(row.same_teacher)],
        ["同一科目", boolLabel(row.same_subject)], ["需要后续调整", boolLabel(row.requires_forward_adjustment)],
      ].map(([label, value]) => fact(label, value)).join("");
      const auditFacts = [
        ["清偿记录编号", row.clearance_id], ["待补对象编号", row.pending_source_planned_id],
        ["超额记录编号", row.overtime_source_actual_id], ["业务范围编号", row.business_entity_id],
        ["业务范围快照", row.business_entity_name], ["请求编号", row.request_identity || row.idempotency_key],
        ["证据状态", row.source_comparison_evidence_status], ["撤销阻断代码", row.reverse_blocker_code || "无"],
      ].map(([label, value]) => fact(label, value)).join("");
      return `<article class="lesson-clearance-history-card"><div class="lesson-clearance-fact-grid">${mainFacts}</div>${systemDetails(`<div class="lesson-clearance-fact-grid">${auditFacts}</div>`)}<div class="lesson-clearance-card-actions">${row.can_reverse && state.capabilities().reverse ? `<button class="button" type="button" data-preview-clearance-reversal="${escapeHtml(row.clearance_id)}">核对撤销结果</button>` : pill(blockerLabel(row.reverse_blocker_code, "当前不可撤销"), "warning")}</div></article>`;
    }).join("")}</div>${state.selection.reversalError ? `<div class="lesson-clearance-error">${escapeHtml(state.selection.reversalError)}</div>` : ""}${renderReversalPreview()}`;
  }

  function renderReversalPreview() {
    const preview = state.selection.reversalPreview;
    if (!preview) return "";
    const mainFacts = [
      ["恢复分钟", minutesLabel(preview.original_clearance?.allocated_minutes)], ["已经撤销", boolLabel(preview.current_state?.already_reversed)],
      ["待补当前余额", minutesLabel(preview.current_state?.pending_before_reversal_minutes)], ["待补恢复后", minutesLabel(preview.current_state?.pending_after_reversal_minutes)],
      ["超额当前余额", minutesLabel(preview.current_state?.overtime_before_reversal_minutes)], ["超额恢复后", minutesLabel(preview.current_state?.overtime_after_reversal_minutes)],
      ["影响其他流程", boolLabel(preview.current_state?.affects_active_claim)], ["涉及锁定月份", boolLabel(preview.forward?.involves_locked_history)],
      ["仅做后续调整", boolLabel(preview.forward?.only_forward)], ["后续调整月份", preview.forward?.forward_destination_month || "无"],
    ].map(([label, value]) => fact(label, value)).join("");
    const auditFacts = [
      ["请求编号", preview.request_identity], ["原清偿记录编号", preview.original_clearance?.clearance_id],
      ["待补对象编号", preview.original_clearance?.pending_source_planned_id], ["超额记录编号", preview.original_clearance?.overtime_source_actual_id],
      ["角色阻断代码", preview.authorization?.blocker_code || "无"], ["撤销核对清单指纹", preview.reversal_manifest_sha256],
    ].map(([label, value]) => fact(label, value)).join("");
    return `<section class="lesson-clearance-preview-card"><h4>撤销核对结果</h4><div class="lesson-clearance-preview-grid">${mainFacts}</div>${systemDetails(`<div class="lesson-clearance-fact-grid">${auditFacts}</div>`)}<label class="field lesson-clearance-reversal-reason"><span>撤销原因</span><textarea id="lessonClearanceReversalReasonInput">${escapeHtml(state.selection.reversalReason)}</textarea></label><div class="lesson-clearance-card-actions"><button class="button button-danger" id="lessonClearancePrepareReversalButton" type="button">核对并准备撤销</button></div></section>`;
  }

  function renderCrossMonth() {
    const rows = state.crossMonthRows();
    if (!rows.length) return empty("当前筛选下没有跨月补课事实。");
    const ordered = [...rows].sort((left, right) => {
      const leftKey = crossView === "source" ? left.source_month : left.actual_month;
      const rightKey = crossView === "source" ? right.source_month : right.actual_month;
      return text(leftKey).localeCompare(text(rightKey)) || text(left.actual_lesson_id).localeCompare(text(right.actual_lesson_id));
    });
    return `<p class="lesson-clearance-guidance">来源月份与实际履约月份是同一条补课记录的两个业务视角；切换视角不会复制课时或改变结算归属。</p><div class="lesson-clearance-cross-toggle"><button class="button ${crossView === "source" ? "button-primary" : ""}" type="button" data-cross-month-view="source">按待补月份查看</button><button class="button ${crossView === "actual" ? "button-primary" : ""}" type="button" data-cross-month-view="actual">按履约月份查看</button></div><div class="lesson-clearance-table-wrap"><table class="lesson-clearance-table"><thead><tr><th>当前视角月份</th><th>学生</th><th>待补老师 / 科目</th><th>实际老师 / 科目</th><th>实际日期时间</th><th>分钟 / 月份</th><th>审计</th></tr></thead><tbody>${ordered.map((row) => `<tr><td><strong>${escapeHtml(crossView === "source" ? row.source_month : row.actual_month)}</strong><br>${pill(crossView === "source" ? "待补视角" : "履约视角")}</td><td>${escapeHtml(row.student_display_name || "名称不可用")}</td><td>${escapeHtml(row.source_teacher_display_name || "名称不可用")}<br>${escapeHtml(row.source_subject_display_name || "名称不可用")}</td><td>${escapeHtml(row.actual_teacher_display_name || "名称不可用")}<br>${escapeHtml(row.actual_subject_display_name || "名称不可用")}</td><td>${dateLabel(row.actual_lesson_date)}<br>${escapeHtml(row.actual_start_time || "-")}–${escapeHtml(row.actual_end_time || "-")}</td><td>${minutesLabel(row.actual_minutes)}<br>学生月 ${escapeHtml(row.student_settlement_month || "-")}<br>工资月 ${escapeHtml(row.teacher_wage_month || "-")}</td><td>${systemDetails(`<div class="lesson-clearance-fact-grid">${[["实际记录编号", row.actual_lesson_id], ["待补对象编号", row.source_planned_lesson_id], ["业务范围编号", row.business_entity_id], ["业务范围当前名称", row.business_entity_display_name], ["证据状态", row.evidence_status], ["待补对象指纹", row.source_row_md5], ["实际记录指纹", row.actual_row_md5]].map(([label, value]) => fact(label, value)).join("")}</div>`)}</td></tr>`).join("")}</tbody></table></div>`;
  }

  function selectionOptions(rows, kind) {
    const idKey = kind === "pending" ? "pending_source_planned_id" : "overtime_source_actual_id";
    const selected = kind === "pending" ? state.selection.pendingId : state.selection.overtimeId;
    return rows.filter((row) => row.can_be_candidate === true).map((row) => {
      const label = kind === "pending"
        ? `${row.student_display_name || "名称不可用"}｜${row.operational_display_date || "日期不可用"}｜${row.teacher_display_name || "老师不可用"}｜${row.subject_display_name || "科目不可用"}｜待补${minutesLabel(row.remaining_minutes)}`
        : `${row.student_display_name || "名称不可用"}｜${row.actual_lesson_date || "日期不可用"}｜${row.teacher_display_name || "老师不可用"}｜${row.subject_display_name || "科目不可用"}｜超额${minutesLabel(row.available_minutes)}`;
      return `<option value="${escapeHtml(row[idKey])}" ${selected === row[idKey] ? "selected" : ""}>${escapeHtml(label)}</option>`;
    }).join("");
  }

  function renderSelection() {
    const show = state.capabilities().select;
    dom.previewSection.classList.toggle("is-hidden", !show);
    if (!show) {
      dom.selectionPanel.replaceChildren();
      dom.previewPanel.replaceChildren();
      return;
    }
    const pending = state.selectedPending();
    const overage = state.selectedOverage();
    const needsReason = pending && Number(pending.fifo_rank) !== 1;
    const selectionAudit = [["请求编号", state.selection.requestIdentity || "选择两项后生成"], ["待补对象编号", pending?.pending_source_planned_id || "未选择"], ["超额记录编号", overage?.overtime_source_actual_id || "未选择"], ["待补业务范围编号", pending?.business_entity_id || "未选择"], ["超额业务范围编号", overage?.business_entity_id || "未选择"]].map(([label, value]) => fact(label, value)).join("");
    dom.selectionPanel.innerHTML = `<div class="lesson-clearance-selection-grid"><label class="field" for="lessonClearancePendingSelect"><span>选择待补对象 <b class="required-mark">必填</b></span><select id="lessonClearancePendingSelect"><option value="">请选择，不自动勾选</option>${selectionOptions(state.data.pendingPayload?.items || [], "pending")}</select></label><label class="field" for="lessonClearanceOverageSelect"><span>选择可用超额 <b class="required-mark">必填</b></span><select id="lessonClearanceOverageSelect"><option value="">请选择，不自动勾选</option>${selectionOptions(state.data.overagePayload?.items || [], "overage")}</select></label><label class="field" for="lessonClearanceAllocatedMinutesInput"><span>本次清偿分钟 <b class="required-mark">必填</b></span><input id="lessonClearanceAllocatedMinutesInput" type="number" min="1" step="1" value="${escapeHtml(state.selection.allocatedMinutes)}" placeholder="系统核对时校验余额"></label><label class="field" for="lessonClearanceOperationDateInput"><span>清偿日期 <b class="required-mark">必填</b></span><input id="lessonClearanceOperationDateInput" type="date" value="${escapeHtml(state.selection.operationDate)}"></label>${needsReason ? `<label class="field"><span>偏离建议顺序原因</span><select id="lessonClearanceDeviationReasonSelect"><option value="">请选择</option><option value="teacher_subject_match" ${state.selection.deviationReasonCode === "teacher_subject_match" ? "selected" : ""}>业务指定老师/科目</option><option value="customer_agreement" ${state.selection.deviationReasonCode === "customer_agreement" ? "selected" : ""}>客户约定</option><option value="other" ${state.selection.deviationReasonCode === "other" ? "selected" : ""}>其他</option></select></label>` : ""}${needsReason && state.selection.deviationReasonCode === "other" ? `<label class="field"><span>其他原因说明</span><textarea id="lessonClearanceDeviationNoteInput">${escapeHtml(state.selection.deviationReasonNote)}</textarea></label>` : ""}<label class="field is-wide" for="lessonClearanceBusinessNoteInput"><span>业务说明 <b class="required-mark">必填</b></span><textarea id="lessonClearanceBusinessNoteInput">${escapeHtml(state.selection.businessNote)}</textarea></label><div class="lesson-clearance-selection-summary"><strong>待补对象</strong><br>${pending ? `${escapeHtml(pending.student_display_name)}｜${dateLabel(pending.operational_display_date)}｜${escapeHtml(pending.teacher_display_name || "老师不可用")}｜${escapeHtml(pending.subject_display_name || "科目不可用")}｜建议顺序${integerLabel(pending.fifo_rank)}` : "未选择"}</div><div class="lesson-clearance-selection-summary"><strong>可用超额</strong><br>${overage ? `${escapeHtml(overage.student_display_name)}｜${dateLabel(overage.actual_lesson_date)}｜${escapeHtml(overage.teacher_display_name || "老师不可用")}｜${escapeHtml(overage.subject_display_name || "科目不可用")}｜建议顺序${integerLabel(overage.display_rank)}` : "未选择"}</div></div><div class="lesson-clearance-preview-actions"><span>改变对象、分钟、日期或说明后，需要重新核对。</span><button class="button button-primary" id="lessonClearancePreviewButton" type="button">${state.selection.preview ? "重新核对" : "核对清偿结果"}</button></div>${systemDetails(`<div class="lesson-clearance-fact-grid">${selectionAudit}</div>`)}${state.selection.previewError ? `<div class="lesson-clearance-error">${escapeHtml(state.selection.previewError)}</div>${state.selection.previewErrorDetail ? systemDetails(fact("原始错误信息", state.selection.previewErrorDetail), "is-error") : ""}` : ""}`;
    const previewButton = dom.selectionPanel.querySelector("#lessonClearancePreviewButton");
    if (previewButton) previewButton.addEventListener("click", requestPreview);
    renderPreview();
  }

  function renderPreview() {
    const preview = state.selection.preview;
    if (!preview) {
      dom.confirmButton.disabled = true;
      const required = state.selection.requiredConfirmations;
      const confirmations = [];
      if (required.crossTeacher) confirmations.push(confirmationInput("crossTeacher", "确认跨老师", "系统不会修改任何老师或工资事实。", state.selection.crossTeacherConfirmed));
      if (required.crossSubject) confirmations.push(confirmationInput("crossSubject", "确认跨科目", "系统不会修改任何课时科目事实。", state.selection.crossSubjectConfirmed));
      if (required.forward) confirmations.push(confirmationInput("forward", "管理员确认后续调整", "不会回写已锁月结、账单、收款或工资；目标月份由系统返回。", state.selection.forwardConfirmed, !state.capabilities().locked));
      dom.previewPanel.innerHTML = confirmations.length
        ? `<section class="lesson-clearance-preview-card"><h4>人工确认已改变</h4><p class="lesson-clearance-guidance">确认项与本次核对绑定。勾选变化已作废旧结果并更换请求编号，请完成确认后重新核对。</p><div class="lesson-clearance-confirmations">${confirmations.join("")}</div></section>`
        : "";
      return;
    }
    const comparison = preview.comparison || {};
    const financial = preview.financial || {};
    const authorization = preview.authorization || {};
    const fifo = preview.fifo || {};
    const pending = preview.pending_source || {};
    const overage = preview.overtime_source || {};
    const confirmations = [];
    if (comparison.same_teacher === false) confirmations.push(confirmationInput("crossTeacher", "确认跨老师", "系统不会修改任何老师或工资事实。", state.selection.crossTeacherConfirmed));
    if (comparison.same_subject === false) confirmations.push(confirmationInput("crossSubject", "确认跨科目", "系统不会修改任何课时科目事实。", state.selection.crossSubjectConfirmed));
    if (financial.requires_forward_adjustment) confirmations.push(confirmationInput("forward", "管理员确认后续调整", "不会回写已锁月结、账单、收款或工资；目标月份由系统返回。", state.selection.forwardConfirmed, !state.capabilities().locked));
    const selectedPending = state.selectedPending() || {};
    const selectedOverage = state.selectedOverage() || {};
    const mainFacts = [
      ["学生", pending.student_name || overage.student_name || "名称不可用"], ["待补对象日期", selectedPending.operational_display_date],
      ["待补老师 / 科目", `${selectedPending.teacher_display_name || "名称不可用"} / ${selectedPending.subject_display_name || "名称不可用"}`], ["超额日期", selectedOverage.actual_lesson_date],
      ["超额老师 / 科目", `${selectedOverage.teacher_display_name || "名称不可用"} / ${selectedOverage.subject_display_name || "名称不可用"}`], ["本次清偿", minutesLabel(preview.requested_minutes)],
      ["待补余额", `${integerLabel(pending.before_remaining_minutes)} → ${integerLabel(pending.after_remaining_minutes)}分钟`], ["超额余额", `${integerLabel(overage.before_available_minutes)} → ${integerLabel(overage.after_available_minutes)}分钟`],
      ["待补金额", moneyLabel(pending.amount_jpy)], ["超额金额", moneyLabel(overage.amount_jpy)],
      ["净金额", moneyLabel(financial.net_amount_jpy)], ["符合建议顺序", boolLabel(fifo.is_recommended_target)],
      ["同一老师", boolLabel(comparison.same_teacher)], ["同一科目", boolLabel(comparison.same_subject)],
      ["待补月份已锁定", boolLabel(pending.source_locked)], ["超额月份已锁定", boolLabel(overage.source_locked)],
      ["需要后续调整", boolLabel(financial.requires_forward_adjustment)], ["后续调整月份", financial.forward_destination_month || "无"],
    ].map(([label, value]) => fact(label, value)).join("");
    const auditFacts = [
      ["请求编号", preview.request_identity], ["核对清单指纹", preview.preview_manifest_sha256],
      ["待补对象编号", pending.planned_id], ["超额记录编号", overage.actual_id],
      ["系统建议对象编号", fifo.recommended_pending_planned_id || "无"], ["实际选择对象编号", fifo.selected_pending_planned_id || pending.planned_id],
      ["偏离原因代码", fifo.deviation_reason_code || "无"], ["待补锁定证据", pending.lock_evidence || "无"],
      ["超额锁定证据", overage.lock_evidence || "无"], ["后续调整方向", financial.forward_adjustment_direction || "无"],
      ["角色阻断代码", authorization.blocker_code || "无"], ["待补对象指纹", preview.source_versions?.pending_row_md5],
      ["超额记录指纹", preview.source_versions?.overtime_row_md5], ["提交时重新验证", preview.writer_revalidation_required],
      ["核对时未占用余额", preview.reservation_created === false],
    ].map(([label, value]) => fact(label, value)).join("");
    dom.previewPanel.innerHTML = `<section class="lesson-clearance-preview-card"><h4>系统核对结果</h4><div class="lesson-clearance-preview-grid">${mainFacts}</div>${comparison.same_teacher === false || comparison.same_subject === false ? `<p class="lesson-clearance-guidance">本次清偿跨老师或跨科目。系统允许该业务动作，但不会修改原课时的老师、科目或工资事实。</p>` : ""}${confirmations.length ? `<div class="lesson-clearance-confirmations">${confirmations.join("")}</div>` : ""}${systemDetails(`<div class="lesson-clearance-fact-grid">${auditFacts}</div>`)}<p class="section-note">正式提交时系统会再次核对全部对象事实；本次核对不会预占余额。</p></section>`;
    dom.confirmButton.disabled = Boolean(state.prepareValidationMessage());
  }

  function confirmationInput(name, title, detail, checked, disabled = false) {
    return `<label><input type="checkbox" data-clearance-confirmation="${escapeHtml(name)}" ${checked ? "checked" : ""} ${disabled ? "disabled" : ""}><span><strong>${escapeHtml(title)}</strong><br>${escapeHtml(detail)}</span></label>`;
  }

  function syncInvalidatedPreviewDisplay() {
    if (dom.finalDialog?.dataset.mode === "create" && !dom.finalDialog.classList.contains("is-hidden")) {
      closeFinalDialog(true);
    }
    const previewButton = dom.selectionPanel.querySelector("#lessonClearancePreviewButton");
    if (previewButton) previewButton.textContent = "核对清偿结果";
    dom.selectionPanel.querySelector(".lesson-clearance-error")?.remove();
    renderPreview();
  }

  function setFinalMessage(message = "") {
    dom.finalMessage.textContent = message;
    dom.finalMessage.classList.toggle("is-hidden", !message);
  }

  function closeFinalDialog(force = false) {
    if (!dom.finalDialog || ((!force && state.selection.submitting) || (!force && state.selection.reversalSubmitting))) return;
    dom.finalDialog.classList.add("is-hidden");
    dom.finalDialog.setAttribute("aria-hidden", "true");
    dom.finalDialog.dataset.mode = "";
    setFinalMessage("");
  }

  function openCreateFinalDialog() {
    const validation = state.prepareValidationMessage();
    if (validation) {
      setMessage("error", validation);
      renderPreview();
      return;
    }
    const preview = state.selection.preview;
    const pending = preview.pending_source || {};
    const overage = preview.overtime_source || {};
    const comparison = preview.comparison || {};
    const fifo = preview.fifo || {};
    const financial = preview.financial || {};
    const inputSnapshot = state.selection.previewInputSnapshot;
    const selectedPending = state.selectedPending() || {};
    const selectedOverage = state.selectedOverage() || {};
    dom.finalDialog.dataset.mode = "create";
    dom.finalTitle.textContent = "最终确认：建立课时差额清偿";
    const mainFacts = [
      ["学生", pending.student_name || overage.student_name], ["待补对象日期", selectedPending.operational_display_date],
      ["待补老师 / 科目", `${selectedPending.teacher_display_name || "名称不可用"} / ${selectedPending.subject_display_name || "名称不可用"}`], ["超额日期", selectedOverage.actual_lesson_date],
      ["超额老师 / 科目", `${selectedOverage.teacher_display_name || "名称不可用"} / ${selectedOverage.subject_display_name || "名称不可用"}`], ["清偿分钟", minutesLabel(preview.requested_minutes)],
      ["待补余额变化", `${integerLabel(pending.before_remaining_minutes)} → ${integerLabel(pending.after_remaining_minutes)}分钟`], ["超额余额变化", `${integerLabel(overage.before_available_minutes)} → ${integerLabel(overage.after_available_minutes)}分钟`],
      ["待补金额", moneyLabel(pending.amount_jpy)], ["超额金额", moneyLabel(overage.amount_jpy)],
      ["清偿后净金额", moneyLabel(financial.net_amount_jpy)], ["符合建议顺序", boolLabel(fifo.is_recommended_target)],
      ["跨老师", boolLabel(comparison.same_teacher === false)], ["跨科目", boolLabel(comparison.same_subject === false)],
      ["待补月份已锁定", boolLabel(pending.source_locked)], ["超额月份已锁定", boolLabel(overage.source_locked)],
      ["需要后续调整", boolLabel(financial.requires_forward_adjustment)], ["后续调整月份", financial.forward_destination_month || "无"],
    ].map(([label, value]) => fact(label, value)).join("");
    const auditFacts = [
      ["请求编号", inputSnapshot.requestIdentity], ["核对清单指纹", inputSnapshot.manifest],
      ["待补对象编号", pending.planned_id], ["超额记录编号", overage.actual_id],
      ["待补业务范围编号", selectedPending.business_entity_id], ["超额业务范围编号", selectedOverage.business_entity_id],
      ["系统建议对象编号", fifo.recommended_pending_planned_id || "无"], ["实际选择对象编号", fifo.selected_pending_planned_id || pending.planned_id],
      ["偏离原因代码", fifo.deviation_reason_code || "无"], ["偏离原因说明", fifo.deviation_reason_note || "无"],
      ["待补锁定证据", pending.lock_evidence || "无"], ["超额锁定证据", overage.lock_evidence || "无"],
      ["后续调整方向", financial.forward_adjustment_direction || "无"], ["后续调整金额", moneyLabel(financial.forward_adjustment_amount_jpy)],
      ["待补对象指纹", preview.source_versions?.pending_row_md5], ["超额记录指纹", preview.source_versions?.overtime_row_md5],
    ].map(([label, value]) => fact(label, value)).join("");
    dom.finalContent.innerHTML = `<div class="lesson-clearance-final-grid">${mainFacts}</div><p class="lesson-clearance-final-warning">本动作只建立课时差额清偿事实，不修改原课时、老师工资、既有账单或收款。</p>${systemDetails(`<div class="lesson-clearance-fact-grid">${auditFacts}</div>`)}`;
    const businessNote = document.createElement("div");
    businessNote.className = "lesson-clearance-final-note";
    const businessNoteLabel = document.createElement("span");
    businessNoteLabel.textContent = "业务说明";
    const businessNoteValue = document.createElement("p");
    businessNoteValue.textContent = inputSnapshot.businessNote;
    businessNote.append(businessNoteLabel, businessNoteValue);
    dom.finalContent.querySelector(".lesson-clearance-final-grid")?.after(businessNote);
    dom.finalSubmit.textContent = `确认清偿${integerLabel(preview.requested_minutes)}分钟`;
    dom.finalActionNote.textContent = "点击后会立即写入正式清偿记录。";
    dom.finalSubmit.disabled = false;
    dom.finalDialog.classList.remove("is-hidden");
    dom.finalDialog.setAttribute("aria-hidden", "false");
    setFinalMessage("");
    dom.finalClose.focus();
  }

  function openReversalFinalDialog() {
    let payload;
    try {
      payload = state.reversalWriterRequest();
    } catch (error) {
      state.selection.reversalError = lessonClearanceErrorMessage(error);
      renderTabPanel();
      return;
    }
    const preview = state.selection.reversalPreview;
    dom.finalDialog.dataset.mode = "reversal";
    dom.finalTitle.textContent = "最终确认：撤销课时差额清偿";
    const mainFacts = [
      ["恢复分钟", minutesLabel(preview.original_clearance?.allocated_minutes)], ["待补余额变化", `${integerLabel(preview.current_state?.pending_before_reversal_minutes)} → ${integerLabel(preview.current_state?.pending_after_reversal_minutes)}分钟`],
      ["超额余额变化", `${integerLabel(preview.current_state?.overtime_before_reversal_minutes)} → ${integerLabel(preview.current_state?.overtime_after_reversal_minutes)}分钟`], ["影响其他流程", boolLabel(preview.current_state?.affects_active_claim)],
      ["涉及锁定月份", boolLabel(preview.forward?.involves_locked_history)], ["仅做后续调整", boolLabel(preview.forward?.only_forward)],
      ["后续调整月份", preview.forward?.forward_destination_month || "无"], ["撤销原因", payload.reason],
    ].map(([label, value]) => fact(label, value)).join("");
    const auditFacts = [
      ["原清偿记录编号", preview.original_clearance?.clearance_id], ["待补对象编号", preview.original_clearance?.pending_source_planned_id],
      ["超额记录编号", preview.original_clearance?.overtime_source_actual_id], ["撤销请求编号", payload.requestIdentity],
      ["撤销核对清单指纹", preview.reversal_manifest_sha256],
    ].map(([label, value]) => fact(label, value)).join("");
    dom.finalContent.innerHTML = `<div class="lesson-clearance-final-grid">${mainFacts}</div><p class="lesson-clearance-final-warning">本动作将建立追加式撤销事实；不会改写原清偿记录或历史月结。</p>${systemDetails(`<div class="lesson-clearance-fact-grid">${auditFacts}</div>`)}`;
    dom.finalSubmit.textContent = "确认撤销该清偿";
    dom.finalActionNote.textContent = "点击后会立即写入正式撤销记录。";
    dom.finalSubmit.disabled = false;
    dom.finalDialog.classList.remove("is-hidden");
    dom.finalDialog.setAttribute("aria-hidden", "false");
    setFinalMessage("");
    dom.finalClose.focus();
  }

  function isNetworkResultUncertain(error) {
    const raw = `${text(error?.name)} ${text(error?.code)} ${text(error?.message)}`.toLowerCase();
    return error instanceof TypeError || /network|fetch|timeout|timed out|abort|connection|econn|gateway/.test(raw);
  }

  function normalizeCreateResult(result) {
    if (Array.isArray(result)) return result.length === 1 ? result[0] : null;
    return result && typeof result === "object" ? result : null;
  }

  async function resolveUncertainResult(requestIdentity, studentId, expectedClearanceId = null) {
    setFinalMessage("清偿结果正在确认，请勿重复提交。");
    counters.readers += 1;
    const history = await api.fetchHistory({ studentId: studentId || null });
    const matchingIdentity = (Array.isArray(history) ? history : []).filter(
      (row) => row.request_identity === requestIdentity || row.idempotency_key === requestIdentity,
    );
    if (matchingIdentity.length !== 1) return null;
    return state.historyMatchesCreateSnapshot(matchingIdentity[0], expectedClearanceId)
      ? matchingIdentity[0]
      : null;
  }

  async function completeCreateSuccess(payload, result, historyRow = null) {
    const completion = Object.freeze({
      allocatedMinutes: Number(payload.allocatedMinutes),
      requestIdentity: payload.requestIdentity,
      clearanceId: result?.clearance_id || historyRow?.clearance_id || null,
      previewManifest: state.selection.previewInputSnapshot?.manifest || null,
      inputManifest: historyRow?.input_manifest_sha256 || null,
    });
    state.selection.submitting = false;
    closeFinalDialog(true);
    closeDialog(true);
    try {
      await onCreateSuccess?.(completion);
    } catch (refreshError) {
      onCreateRefreshFailure?.(completion, refreshError);
    }
  }

  function stopForUnconfirmedResult(message = "清偿结果正在确认，请勿重复提交。") {
    state.selection.submitting = true;
    dom.finalSubmit.disabled = true;
    dom.finalSubmit.textContent = "正在确认清偿结果…";
    setFinalMessage(message);
  }

  function handleCreateRejection(error) {
    const message = lessonClearanceErrorMessage(error);
    const detail = lessonClearanceErrorTechnicalDetail(error);
    state.selection.submitting = false;
    state.rejectCreate(message, detail);
    closeFinalDialog(true);
    setMessage("error", message);
    renderSelection();
  }

  async function submitCreate() {
    if (state.selection.submitting || dom.finalDialog.dataset.mode !== "create") return;
    let payload;
    try {
      payload = state.writerRequest();
    } catch (error) {
      setFinalMessage(lessonClearanceErrorMessage(error));
      return;
    }
    state.selection.submitting = true;
    dom.finalSubmit.disabled = true;
    dom.finalSubmit.textContent = "正在建立正式清偿记录…";
    const studentId = state.selection.preview?.pending_source?.student_id;
    try {
      counters.createWriters += 1;
      const result = normalizeCreateResult(await api.createClearance(payload));
      if (!state.createResultMatchesSnapshot(result)) {
        stopForUnconfirmedResult();
        const existing = await resolveUncertainResult(payload.requestIdentity, studentId, result?.clearance_id || null);
        if (existing) await completeCreateSuccess(payload, result, existing);
        return;
      }
      if (result.idempotent_replay === true) {
        const existing = await resolveUncertainResult(payload.requestIdentity, studentId, result.clearance_id);
        if (!existing) {
          stopForUnconfirmedResult("系统无法确认幂等结果与当前核对一致，请勿重复提交。");
          return;
        }
        await completeCreateSuccess(payload, result, existing);
        return;
      }
      await completeCreateSuccess(payload, result);
    } catch (error) {
      if (isNetworkResultUncertain(error)) {
        try {
          stopForUnconfirmedResult();
          const existing = await resolveUncertainResult(payload.requestIdentity, studentId);
          if (existing) await completeCreateSuccess(payload, null, existing);
          else stopForUnconfirmedResult();
        } catch (_historyError) {
          stopForUnconfirmedResult();
        }
      } else {
        handleCreateRejection(error);
      }
    }
  }

  async function submitReversal() {
    if (state.selection.reversalSubmitting || dom.finalDialog.dataset.mode !== "reversal") return;
    let payload;
    try {
      payload = state.reversalWriterRequest();
    } catch (error) {
      setFinalMessage(lessonClearanceErrorMessage(error));
      return;
    }
    state.selection.reversalSubmitting = true;
    dom.finalSubmit.disabled = true;
    dom.finalSubmit.textContent = "正在建立正式撤销记录…";
    const original = state.data.history.find((row) => row.clearance_id === payload.clearanceId);
    try {
      counters.reversalWriters += 1;
      await api.reverseClearance(payload);
      closeFinalDialog(true);
      await loadData();
      setMessage("success", "撤销记录已建立；页面已重新读取余额与清偿历史。");
    } catch (error) {
      if (isNetworkResultUncertain(error)) {
        try {
          const existing = await resolveUncertainResult(payload.requestIdentity, original?.student_id);
          closeFinalDialog(true);
          await loadData();
          setMessage(existing ? "success" : "error", existing
            ? "清偿历史已确认本次撤销成功，系统没有重复提交。"
            : "清偿历史中尚未找到本次撤销。旧核对结果已失效，请重新读取历史并核对；系统没有重复提交。");
        } catch (historyError) {
          setFinalMessage(`无法读取清偿历史确认结果：${lessonClearanceErrorMessage(historyError)}。请勿重复提交。`);
        }
      } else {
        setFinalMessage(lessonClearanceErrorMessage(error));
      }
    } finally {
      state.selection.reversalSubmitting = false;
      if (!dom.finalDialog.classList.contains("is-hidden")) {
        dom.finalSubmit.disabled = false;
        dom.finalSubmit.textContent = "确认撤销该清偿";
      }
    }
  }

  async function requestPreview() {
    try {
      const payload = state.previewRequest();
      counters.previews += 1;
      const preview = await api.previewClearance(payload);
      state.acceptPreview(preview, payload);
    } catch (error) {
      state.rejectPreview(
        new Error(lessonClearanceErrorMessage(error)),
        lessonClearanceErrorTechnicalDetail(error),
      );
    }
    renderSelection();
  }

  async function requestReversalPreview(clearanceId) {
    if (!state.beginReversal(clearanceId)) {
      state.selection.reversalError = "当前角色或记录不符合撤销条件。";
      renderTabPanel();
      return;
    }
    try {
      counters.reversalPreviews += 1;
      const preview = await api.previewReversal(state.reversalPreviewRequest());
      state.acceptReversalPreview(preview);
    } catch (error) {
      state.selection.reversalPreview = null;
      state.selection.reversalBinding = null;
      state.selection.reversalError = lessonClearanceErrorMessage(error);
    }
    renderTabPanel();
  }

  function bindEvents() {
    dom.openButton?.addEventListener("click", openDialog);
    dom.headerClose?.addEventListener("click", closeDialog);
    dom.footerClose?.addEventListener("click", closeDialog);
    dom.dialog?.addEventListener("click", (event) => {
      if (event.target === dom.dialog) closeDialog();
    });
    dom.finalDialog?.addEventListener("click", (event) => {
      if (event.target === dom.finalDialog) closeFinalDialog();
    });
    dom.finalClose?.addEventListener("click", () => closeFinalDialog());
    dom.finalCancel?.addEventListener("click", () => closeFinalDialog());
    dom.finalSubmit?.addEventListener("click", () => {
      if (dom.finalDialog.dataset.mode === "create") submitCreate();
      if (dom.finalDialog.dataset.mode === "reversal") submitReversal();
    });
    dom.confirmButton?.addEventListener("click", openCreateFinalDialog);
    dom.filterForm?.addEventListener("submit", (event) => {
      event.preventDefault();
      readDraftFilters();
      state.applyDraftFilters();
      loadData();
    });
    dom.filterReset?.addEventListener("click", () => {
      state.resetDraftFilters();
      syncFilterControls();
      setMessage("success", "已重置筛选条件");
    });
    dom.tabs?.addEventListener("click", (event) => {
      const button = event.target.closest("[data-clearance-tab]");
      if (!button) return;
      state.setTab(button.dataset.clearanceTab);
      renderTabs();
      renderTabPanel();
    });
    dom.tabPanel?.addEventListener("click", (event) => {
      const pendingButton = event.target.closest("[data-select-clearance-pending]");
      const overtimeButton = event.target.closest("[data-select-clearance-overtime]");
      const crossButton = event.target.closest("[data-cross-month-view]");
      const reversalButton = event.target.closest("[data-preview-clearance-reversal]");
      const prepareReversalButton = event.target.closest("#lessonClearancePrepareReversalButton");
      if (!pendingButton && !overtimeButton && !crossButton && !reversalButton && !prepareReversalButton) return;
      if (pendingButton) state.selectPending(pendingButton.dataset.selectClearancePending);
      if (overtimeButton) state.selectOvertime(overtimeButton.dataset.selectClearanceOvertime);
      if (crossButton) crossView = crossButton.dataset.crossMonthView;
      if (reversalButton) {
        requestReversalPreview(reversalButton.dataset.previewClearanceReversal);
        return;
      }
      if (prepareReversalButton) {
        openReversalFinalDialog();
        return;
      }
      renderTabPanel();
      renderSelection();
    });
    dom.tabPanel?.addEventListener("input", (event) => {
      if (event.target.id === "lessonClearanceReversalReasonInput") {
        state.selection.reversalReason = event.target.value;
      }
    });
    dom.selectionPanel?.addEventListener("change", (event) => {
      if (event.target.id === "lessonClearancePendingSelect") state.selectPending(event.target.value);
      if (event.target.id === "lessonClearanceOverageSelect") state.selectOvertime(event.target.value);
      if (event.target.id === "lessonClearanceAllocatedMinutesInput") state.setPreviewInput("allocatedMinutes", event.target.value);
      if (event.target.id === "lessonClearanceOperationDateInput") state.setPreviewInput("operationDate", event.target.value);
      if (event.target.id === "lessonClearanceDeviationReasonSelect") state.setPreviewInput("deviationReasonCode", event.target.value);
      renderTabPanel();
      renderSelection();
    });
    dom.selectionPanel?.addEventListener("input", (event) => {
      if (event.target.id === "lessonClearanceAllocatedMinutesInput") {
        state.setPreviewInput("allocatedMinutes", event.target.value);
        syncInvalidatedPreviewDisplay();
      }
      if (event.target.id === "lessonClearanceDeviationNoteInput") {
        state.setPreviewInput("deviationReasonNote", event.target.value);
        syncInvalidatedPreviewDisplay();
      }
      if (event.target.id === "lessonClearanceBusinessNoteInput") {
        state.setPreviewInput("businessNote", event.target.value);
        syncInvalidatedPreviewDisplay();
      }
    });
    dom.previewPanel?.addEventListener("change", (event) => {
      const name = event.target.dataset.clearanceConfirmation;
      if (["crossTeacher", "crossSubject", "forward"].includes(name)) {
        state.setConfirmation(name, event.target.checked);
        renderSelection();
      }
    });
    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      if (!dom.finalDialog?.classList.contains("is-hidden")) closeFinalDialog();
      else if (!dom.dialog?.classList.contains("is-hidden")) closeDialog();
    });
  }

  function init() {
    if (initialized) return;
    initialized = true;
    cacheDom();
    bindEvents();
    if (dom.confirmButton) dom.confirmButton.disabled = true;
  }

  return Object.freeze({
    init,
    open: openDialog,
    close: closeDialog,
    state,
    counters,
  });
}
