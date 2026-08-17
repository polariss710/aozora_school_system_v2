import {
  LESSON_CLEARANCE_DEFAULT_FILTERS,
  LessonClearanceWorkspaceState,
} from "../utils/lesson-clearance-state.js?v=phase2c-d1-clearance-workspace-20260817-2";

const ERROR_MESSAGES = new Map([
  ["LESSON_CLEARANCE_SCOPE_MISMATCH", "待补与超额必须属于同一学生及业务归属。"],
  ["LESSON_CLEARANCE_STUDENT_MISMATCH", "待补与超额属于不同学生，DB已拒绝Preview。"],
  ["LESSON_CLEARANCE_BUSINESS_ENTITY_MISMATCH", "待补与超额属于不同业务归属，DB已拒绝Preview。"],
  ["LESSON_CLEARANCE_PRICE_POLICY_REQUIRED", "V2只允许相同单价来源，DB已拒绝异价Preview。"],
  ["LESSON_CLEARANCE_PENDING_BALANCE_INSUFFICIENT", "待补来源当前余额不足，请重新加载。"],
  ["LESSON_CLEARANCE_OVERTIME_BALANCE_INSUFFICIENT", "超额来源当前余额不足，请重新加载。"],
  ["LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_CLAIMED", "待补来源已被active claim占用。"],
  ["LESSON_CLEARANCE_OVERTIME_SOURCE_ALREADY_CLAIMED", "超额来源已被active claim占用。"],
  ["LESSON_CLEARANCE_REQUEST_IDENTITY_INVALID", "Preview request identity无效，请重新选择来源。"],
  ["LESSON_CLEARANCE_SOURCE_VERSION_MISMATCH", "来源事实已变化，请重新预览。系统不会使用旧预览提交。"],
  ["LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED", "当前账号权限已停用，不能读取课时余额。"],
  ["LESSON_CLEARANCE_MEMBERSHIP_REQUIRED", "当前账号没有课时余额读取权限。"],
  ["LESSON_CLEARANCE_ROLE_REQUIRED", "当前角色不能执行该Preview。"],
  ["LESSON_CLEARANCE_PACKAGE_SOURCE_FORBIDDEN", "套餐权益不能进入普通待补清偿。"],
  ["LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID", "该清偿记录不能生成Reversal Preview。"],
]);

const text = (value) => String(value ?? "");
const escapeHtml = (value) => text(value)
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#039;");
const shortId = (value) => text(value) ? text(value).slice(0, 8) : "-";
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
  current_derived: "当前DB派生",
  unavailable: "证据不可用",
}[value] || text(value) || "证据不可用");

export function lessonClearanceErrorMessage(error) {
  const raw = text(error?.message || error);
  for (const [code, message] of ERROR_MESSAGES) {
    if (raw.includes(code)) return message;
  }
  return raw || "课时余额读取失败，当前结果不可用于清偿，请重新加载。";
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

export function createLessonClearanceWorkspace({ api, getRole }) {
  const state = new LessonClearanceWorkspaceState({ role: getRole?.() || "" });
  const dom = {};
  let initialized = false;
  let loadRequestId = 0;
  let crossView = "source";
  const counters = { readers: 0, previews: 0, reversalPreviews: 0, renders: 0 };

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
    dom.entityFilter = document.querySelector("#lessonClearanceEntityFilter");
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
      setMessage("error", "当前身份没有active课时余额读取权限。页面不会请求或显示候选数据。");
      return;
    }
    loadData();
  }

  function closeDialog() {
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
      setMessage("error", `课时余额读取失败，当前结果不可用于清偿，请重新加载。${lessonClearanceErrorMessage(error)}`);
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
    const entities = new Map();
    const months = new Set();
    const evidence = new Set();
    rows.forEach((row) => {
      if (row.student_id) students.set(row.student_id, row.student_display_name || row.student_name || "名称不可用");
      if (row.business_entity_id) entities.set(row.business_entity_id, row.business_entity_display_name || row.business_entity_name || "名称不可用");
      [row.source_year_month, row.student_settlement_month, row.actual_month, row.operational_year_month, row.financial_year_month]
        .filter(Boolean).forEach((value) => months.add(value));
      if (typeof row.evidence_status === "string") evidence.add(row.evidence_status);
    });
    populateSelect(dom.studentFilter, [...students].sort((a, b) => a[1].localeCompare(b[1], "zh-CN")), "全部学生");
    populateSelect(dom.entityFilter, [...entities].sort((a, b) => a[1].localeCompare(b[1], "zh-CN")), "全部业务归属");
    populateSelect(dom.monthFilter, [...months].sort().reverse().map((value) => [value, value]), "全部月份");
    populateSelect(dom.evidenceFilter, [...evidence].sort().map((value) => [value, evidenceLabel(value)]), "全部证据");
  }

  function syncFilterControls() {
    const filters = state.draftFilters;
    dom.studentFilter.value = filters.studentId;
    dom.entityFilter.value = filters.businessEntityId;
    dom.monthFilter.value = filters.settlementMonth;
    dom.statusFilter.value = filters.status;
    dom.evidenceFilter.value = filters.evidenceStatus;
    dom.fifoOnlyFilter.checked = filters.fifoOnly;
  }

  function readDraftFilters() {
    state.setDraftFilter("studentId", dom.studentFilter.value);
    state.setDraftFilter("businessEntityId", dom.entityFilter.value);
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
      ["待补source", integerLabel(value.pending_source_count), "DB summary"],
      ["待补可用", minutesLabel(value.pending_remaining_minutes), "DB summary"],
      ["超额source", integerLabel(value.overage_source_count), "DB summary"],
      ["超额可用", minutesLabel(value.available_overtime_minutes), "DB summary"],
      ["套餐lot", integerLabel(value.package_lot_count), "DB summary"],
      ["套餐剩余", minutesLabel(value.package_remaining_minutes), "DB summary"],
      ["历史记录", integerLabel(value.history_count), "DB summary"],
      ["不可用标记", integerLabel(marked.blocked), "DB行can_be_candidate"],
      ["active claim标记", integerLabel(marked.claimed), "DB行active_claimed"],
      ["physical lock标记", integerLabel(marked.locked), "DB行is_locked"],
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
    if (row.can_be_candidate !== true) return pill(row.candidate_blocker_code || "不可选择", "danger");
    const selected = kind === "pending" ? state.selection.pendingId === id : state.selection.overtimeId === id;
    return `<button class="button ${selected ? "button-primary" : ""}" type="button" data-select-clearance-${kind}="${escapeHtml(id)}">${selected ? "已人工选择" : "人工选择"}</button>`;
  }

  function renderPending() {
    const rows = state.pendingRows();
    if (!rows.length) return empty("当前筛选下没有普通待补余额。P002不会进入本区。");
    return `<p class="lesson-clearance-guidance">FIFO仅为DB建议排序，系统不会自动选择任何待补来源。余额为0的来源不进入当前可选列表。</p><div class="lesson-clearance-card-list">${rows.map((row) => {
      const id = row.pending_source_planned_id;
      const status = row.can_be_candidate ? pill("可作为候选", "ok") : pill(row.candidate_blocker_code || "不可用", "danger");
      return `<details class="lesson-clearance-source-card" data-clearance-source-id="${escapeHtml(id)}" ${state.shouldOpenRow(row, "pending") ? "open" : ""}><summary><div><strong>${escapeHtml(row.student_display_name || "名称不可用")} · ${escapeHtml(row.business_entity_display_name || "名称不可用")}</strong><small>${dateLabel(row.source_lesson_date)} · ${escapeHtml(row.teacher_display_name || "名称不可用")} / ${escapeHtml(row.subject_display_name || "名称不可用")}</small></div><div><strong>${minutesLabel(row.remaining_minutes)}</strong><small>当前remaining</small></div><div><strong>${moneyLabel(row.remaining_amount_jpy)}</strong><small>DB剩余金额</small></div><div><strong>FIFO ${integerLabel(row.fifo_rank)}</strong><small>${escapeHtml(row.credit_origin_sort_source)}</small></div>${status}</summary><div class="lesson-clearance-card-body"><div class="lesson-clearance-fact-grid">${[
        ["来源planned", `${shortId(id)} · ${id}`], ["学生结算月", row.source_year_month],
        ["来源状态", row.source_status], ["来源方式", row.source_origin_type],
        ["初始待补", minutesLabel(row.initial_credit_minutes)], ["makeup已消费", minutesLabel(row.makeup_consumed_minutes)],
        ["clearance已分配", minutesLabel(row.clearance_allocated_minutes)], ["reversal已恢复", minutesLabel(row.clearance_reversed_minutes)],
        ["active claim", minutesLabel(row.active_claimed_minutes)], ["当前available", minutesLabel(row.currently_allocatable_minutes)],
        ["单价", `${moneyLabel(row.unit_price_jpy)}/小时`], ["初始金额", moneyLabel(row.initial_amount_jpy)],
        ["physical lock", boolLabel(row.is_locked)], ["lock reason", row.lock_reason_code || "无"],
        ["candidate blocker", row.candidate_blocker_code || "无"], ["evidence", evidenceLabel(row.evidence_status)],
        ["老师名称证据", evidenceLabel(row.teacher_name_evidence_status)], ["科目名称证据", evidenceLabel(row.subject_name_evidence_status)],
        ["source fingerprint", row.source_row_md5], ["更新时间", row.source_updated_at],
      ].map(([label, value]) => fact(label, value)).join("")}</div><div class="lesson-clearance-card-actions">${selectAction("pending", id, row)}</div></div></details>`;
    }).join("")}</div>`;
  }

  function renderOverages() {
    const rows = state.overageRows();
    if (!rows.length) return empty("当前筛选下没有可用超额事实。");
    return `<p class="lesson-clearance-guidance">超额是冻结的课时差额事实，不等于系统已自动选择用它清偿某条待补余额。</p><div class="lesson-clearance-card-list">${rows.map((row) => {
      const id = row.overtime_source_actual_id;
      const status = row.can_be_candidate ? pill("可作为候选", "ok") : pill(row.candidate_blocker_code || "不可用", "danger");
      return `<details class="lesson-clearance-source-card" ${state.shouldOpenRow(row, "overage") ? "open" : ""}><summary><div><strong>${escapeHtml(row.student_display_name || "名称不可用")} · ${escapeHtml(row.business_entity_display_name || "名称不可用")}</strong><small>${dateLabel(row.actual_lesson_date)} · ${escapeHtml(row.teacher_display_name || "名称不可用")} / ${escapeHtml(row.subject_display_name || "名称不可用")}</small></div><div><strong>${minutesLabel(row.available_minutes)}</strong><small>当前available</small></div><div><strong>${moneyLabel(row.available_amount_jpy)}</strong><small>DB可用金额</small></div><div><strong>顺序 ${integerLabel(row.display_rank)}</strong><small>${escapeHtml(row.overtime_sort_source)}</small></div>${status}</summary><div class="lesson-clearance-card-body"><div class="lesson-clearance-fact-grid">${[
        ["来源planned", `${shortId(row.linked_planned_lesson_id)} · ${row.linked_planned_lesson_id}`], ["overage actual", `${shortId(id)} · ${id}`],
        ["学生结算月", row.student_settlement_month], ["老师工资月", row.teacher_wage_month],
        ["frozen overage", minutesLabel(row.frozen_overtime_minutes)], ["active claim", minutesLabel(row.active_claimed_minutes)],
        ["clearance已分配", minutesLabel(row.clearance_allocated_minutes)], ["reversal已恢复", minutesLabel(row.clearance_reversed_minutes)],
        ["当前available", minutesLabel(row.currently_allocatable_minutes)], ["冻结单价", `${moneyLabel(row.unit_price_jpy)}/小时`],
        ["frozen JPY", moneyLabel(row.frozen_amount_jpy)], ["available JPY", moneyLabel(row.available_amount_jpy)],
        ["policy", row.overage_policy_version], ["source", row.overage_source],
        ["physical lock", boolLabel(row.is_locked)], ["lock reason", row.lock_reason_code || "无"],
        ["candidate blocker", row.candidate_blocker_code || "无"], ["evidence", evidenceLabel(row.evidence_status)],
        ["source fingerprint", row.source_row_md5], ["更新时间", row.source_updated_at],
      ].map(([label, value]) => fact(label, value)).join("")}</div><div class="lesson-clearance-card-actions">${selectAction("overtime", id, row)}</div></div></details>`;
    }).join("")}</div>`;
  }

  function renderPackages() {
    const rows = state.packageRows();
    if (!rows.length) return empty("当前筛选下没有套餐余额。");
    return `<p class="lesson-clearance-guidance is-package">套餐余额与普通待补余额隔离。当前版本尚未开放套餐消费或预约。</p><div class="lesson-clearance-card-list">${rows.map((row) => `<details class="lesson-clearance-source-card" ${state.shouldOpenRow(row, "package") ? "open" : ""}><summary><div><strong>${escapeHtml(row.student_display_name || "名称不可用")} · ${escapeHtml(row.business_entity_display_name || "名称不可用")}</strong><small>${escapeHtml(row.package_display_label)} · ${escapeHtml(row.package_business_type)}</small></div><div><strong>${minutesLabel(row.remaining_minutes)}</strong><small>套餐剩余</small></div><div><strong>${moneyLabel(row.total_amount_jpy)}</strong><small>套餐总额</small></div><div><strong>${escapeHtml(row.status)}</strong><small>${evidenceLabel(row.evidence_status)}</small></div>${pill("只读隔离", "warning")}</summary><div class="lesson-clearance-card-body"><div class="lesson-clearance-fact-grid">${[
      ["package lot", `${shortId(row.package_lot_id)} · ${row.package_lot_id}`], ["origin planned", `${shortId(row.origin_planned_lesson_id)} · ${row.origin_planned_lesson_id}`],
      ["初始分钟", minutesLabel(row.initial_minutes)], ["已消费分钟", minutesLabel(row.consumed_minutes)],
      ["剩余分钟", minutesLabel(row.remaining_minutes)], ["单价", `${moneyLabel(row.unit_price_jpy)}/小时`],
      ["学生收费月", row.student_settlement_month], ["classification", row.classification_reason],
      ["read_only", boolLabel(row.read_only)], ["can_consume", boolLabel(row.can_consume)],
      ["can_reserve", boolLabel(row.can_reserve)], ["origin fingerprint", row.origin_row_md5],
      ["名称证据", evidenceLabel(row.student_name_evidence_status)], ["业务归属证据", evidenceLabel(row.business_entity_name_evidence_status)],
    ].map(([label, value]) => fact(label, value)).join("")}</div></div></details>`).join("")}</div>`;
  }

  function renderHistory() {
    const rows = state.historyRows();
    if (!rows.length) return empty("尚无课时差额清偿记录。");
    return `<div class="lesson-clearance-table-wrap"><table class="lesson-clearance-table"><thead><tr><th>清偿</th><th>学生 / 归属</th><th>来源</th><th>分钟 / 金额</th><th>月份 / forward</th><th>FIFO / same-cross</th><th>证据 / identity</th><th>Reversal Preview</th></tr></thead><tbody>${rows.map((row) => `<tr><td><strong>${shortId(row.clearance_id)}</strong><br><small>${escapeHtml(row.created_at || "-")}</small><br>${pill(row.clearance_type || "-")}</td><td>${escapeHtml(row.student_name || "名称不可用")}<br><small>${escapeHtml(row.business_entity_name || "名称不可用")}</small></td><td>pending ${shortId(row.pending_source_planned_id)}<br>overage ${shortId(row.overtime_source_actual_id)}</td><td>${minutesLabel(row.allocated_minutes)}<br>${moneyLabel(row.financial_net_amount_jpy)}</td><td>${escapeHtml(row.operational_year_month || "-")} → ${escapeHtml(row.financial_year_month || "无forward")}<br>${row.requires_forward_adjustment ? pill("需要forward", "warning") : pill("无需forward", "ok")}</td><td>${row.deviated_from_recommendation ? pill("偏离FIFO", "warning") : pill("推荐对象", "ok")}<br>老师同源：${boolLabel(row.same_teacher)}<br>科目同源：${boolLabel(row.same_subject)}</td><td>${escapeHtml(evidenceLabel(row.source_comparison_evidence_status))}<br><small>${escapeHtml(row.request_identity || row.idempotency_key || "identity不可用")}</small></td><td>${row.can_reverse && state.role === "admin" ? `<button class="button" type="button" data-preview-clearance-reversal="${escapeHtml(row.clearance_id)}">只读Reversal Preview</button><br><button class="button button-danger" type="button" disabled>确认Reversal（暂未开放）</button>` : pill(row.reverse_blocker_code || "无可用操作", "warning")}</td></tr>`).join("")}</tbody></table></div>${state.selection.reversalError ? `<div class="lesson-clearance-error">${escapeHtml(state.selection.reversalError)}</div>` : ""}${renderReversalPreview()}`;
  }

  function renderReversalPreview() {
    const preview = state.selection.reversalPreview;
    if (!preview) return "";
    return `<section class="lesson-clearance-preview-card"><h4>DB权威Reversal Preview（只读）</h4><div class="lesson-clearance-preview-grid">${[
      ["request identity", preview.request_identity], ["原clearance", preview.original_clearance?.clearance_id],
      ["原分配分钟", minutesLabel(preview.original_clearance?.allocated_minutes)], ["是否已有reversal", boolLabel(preview.current_state?.is_reversed)],
      ["锁定历史", boolLabel(preview.forward?.involves_locked_history)], ["forward目标", preview.forward?.forward_destination_month || "无"],
      ["actor blocker", preview.authorization?.blocker_code || "无"], ["manifest", preview.reversal_manifest_sha256],
    ].map(([label, value]) => fact(label, value)).join("")}</div><p class="section-note">Reversal确认按钮始终disabled；本阶段没有reversal writer调用路径。</p></section>`;
  }

  function renderCrossMonth() {
    const rows = state.crossMonthRows();
    if (!rows.length) return empty("当前筛选下没有跨月补课事实。");
    const ordered = [...rows].sort((left, right) => {
      const leftKey = crossView === "source" ? left.source_month : left.actual_month;
      const rightKey = crossView === "source" ? right.source_month : right.actual_month;
      return text(leftKey).localeCompare(text(rightKey)) || text(left.actual_lesson_id).localeCompare(text(right.actual_lesson_id));
    });
    return `<p class="lesson-clearance-guidance">来源月份和履约月份均引用同一个makeup actual UUID；切换视角不会复制课时或改变归属。</p><div class="lesson-clearance-cross-toggle"><button class="button ${crossView === "source" ? "button-primary" : ""}" type="button" data-cross-month-view="source">按来源月份查看</button><button class="button ${crossView === "actual" ? "button-primary" : ""}" type="button" data-cross-month-view="actual">按履约月份查看</button></div><div class="lesson-clearance-table-wrap"><table class="lesson-clearance-table"><thead><tr><th>当前视角月份</th><th>actual / source</th><th>学生 / 归属</th><th>来源老师 / 科目</th><th>实际老师 / 科目</th><th>实际日期时间</th><th>分钟 / 月份</th><th>证据</th></tr></thead><tbody>${ordered.map((row) => `<tr><td><strong>${escapeHtml(crossView === "source" ? row.source_month : row.actual_month)}</strong><br>${pill(crossView === "source" ? "来源视角" : "履约视角")}</td><td>actual ${shortId(row.actual_lesson_id)}<br><small>${escapeHtml(row.actual_lesson_id)}</small><br>source ${shortId(row.source_planned_lesson_id)}</td><td>${escapeHtml(row.student_display_name || "名称不可用")}<br><small>${escapeHtml(row.business_entity_display_name || "名称不可用")}</small></td><td>${escapeHtml(row.source_teacher_display_name || "名称不可用")}<br>${escapeHtml(row.source_subject_display_name || "名称不可用")}</td><td>${escapeHtml(row.actual_teacher_display_name || "名称不可用")}<br>${escapeHtml(row.actual_subject_display_name || "名称不可用")}</td><td>${dateLabel(row.actual_lesson_date)}<br>${escapeHtml(row.actual_start_time || "-")}–${escapeHtml(row.actual_end_time || "-")}</td><td>${minutesLabel(row.actual_minutes)}<br>学生月 ${escapeHtml(row.student_settlement_month || "-")}<br>工资月 ${escapeHtml(row.teacher_wage_month || "-")}</td><td>${escapeHtml(evidenceLabel(row.evidence_status))}<br><small>source ${escapeHtml(row.source_row_md5)}<br>actual ${escapeHtml(row.actual_row_md5)}</small></td></tr>`).join("")}</tbody></table></div>`;
  }

  function selectionOptions(rows, kind) {
    const idKey = kind === "pending" ? "pending_source_planned_id" : "overtime_source_actual_id";
    const selected = kind === "pending" ? state.selection.pendingId : state.selection.overtimeId;
    return rows.filter((row) => row.can_be_candidate === true).map((row) => {
      const label = `${row.student_display_name || "名称不可用"} · ${kind === "pending" ? row.source_lesson_date : row.actual_lesson_date} · ${kind === "pending" ? row.remaining_minutes : row.available_minutes}分钟 · ${shortId(row[idKey])}`;
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
    dom.selectionPanel.innerHTML = `<div class="lesson-clearance-selection-grid"><label class="field"><span>人工选择待补来源</span><select id="lessonClearancePendingSelect"><option value="">请选择，不自动勾选</option>${selectionOptions(state.data.pendingPayload?.items || [], "pending")}</select></label><label class="field"><span>人工选择可用超额</span><select id="lessonClearanceOverageSelect"><option value="">请选择，不自动勾选</option>${selectionOptions(state.data.overagePayload?.items || [], "overage")}</select></label><label class="field"><span>本次清偿分钟（人工输入）</span><input id="lessonClearanceAllocatedMinutesInput" type="number" min="1" step="1" value="${escapeHtml(state.selection.allocatedMinutes)}" placeholder="DB Preview将校验余额"></label><label class="field"><span>清偿日期</span><input id="lessonClearanceOperationDateInput" type="date" value="${escapeHtml(state.selection.operationDate)}"></label>${needsReason ? `<label class="field"><span>偏离FIFO原因</span><select id="lessonClearanceDeviationReasonSelect"><option value="">请选择</option><option value="teacher_subject_match" ${state.selection.deviationReasonCode === "teacher_subject_match" ? "selected" : ""}>业务指定老师/科目</option><option value="customer_agreement" ${state.selection.deviationReasonCode === "customer_agreement" ? "selected" : ""}>客户约定</option><option value="other" ${state.selection.deviationReasonCode === "other" ? "selected" : ""}>其他</option></select></label>` : ""}${needsReason && state.selection.deviationReasonCode === "other" ? `<label class="field"><span>其他原因说明</span><textarea id="lessonClearanceDeviationNoteInput">${escapeHtml(state.selection.deviationReasonNote)}</textarea></label>` : ""}<label class="field is-wide"><span>业务备注（未来writer参数，本阶段不提交）</span><textarea id="lessonClearanceBusinessNoteInput">${escapeHtml(state.selection.businessNote)}</textarea></label><div class="lesson-clearance-selection-summary"><strong>待补</strong><br>${pending ? `${escapeHtml(pending.student_display_name)} · ${shortId(pending.pending_source_planned_id)} · FIFO ${integerLabel(pending.fifo_rank)}` : "未选择"}</div><div class="lesson-clearance-selection-summary"><strong>超额</strong><br>${overage ? `${escapeHtml(overage.student_display_name)} · ${shortId(overage.overtime_source_actual_id)} · 顺序 ${integerLabel(overage.display_rank)}` : "未选择"}</div></div><div class="lesson-clearance-preview-actions"><code>request identity：${escapeHtml(state.selection.requestIdentity || "选择两条source后生成")}</code><button class="button button-primary" id="lessonClearancePreviewButton" type="button">${state.selection.preview ? "重新预览" : "读取DB权威Preview"}</button></div>${state.selection.previewError ? `<div class="lesson-clearance-error">${escapeHtml(state.selection.previewError)}</div>` : ""}`;
    renderPreview();
  }

  function renderPreview() {
    const preview = state.selection.preview;
    if (!preview) {
      dom.previewPanel.innerHTML = "";
      return;
    }
    const comparison = preview.comparison || {};
    const financial = preview.financial || {};
    const authorization = preview.authorization || {};
    const fifo = preview.fifo || {};
    const pending = preview.pending_source || {};
    const overage = preview.overtime_source || {};
    const confirmations = [];
    if (comparison.same_teacher === false) confirmations.push(`<label><input type="checkbox" data-clearance-confirmation="crossTeacher" ${state.selection.crossTeacherConfirmed ? "checked" : ""}><span><strong>确认跨老师</strong><br>系统不会修改任何老师或工资事实。</span></label>`);
    if (comparison.same_subject === false) confirmations.push(`<label><input type="checkbox" data-clearance-confirmation="crossSubject" ${state.selection.crossSubjectConfirmed ? "checked" : ""}><span><strong>确认跨科目</strong><br>系统不会修改任何课时科目事实。</span></label>`);
    if (financial.requires_forward_adjustment) confirmations.push(`<label><input type="checkbox" data-clearance-confirmation="forward" ${state.selection.forwardConfirmed ? "checked" : ""} ${state.role !== "admin" ? "disabled" : ""}><span><strong>admin forward确认</strong><br>不会回写已锁月结、账单、收款或工资；目标月份由DB返回。</span></label>`);
    dom.previewPanel.innerHTML = `<section class="lesson-clearance-preview-card"><h4>DB权威Preview</h4><div class="lesson-clearance-preview-grid">${[
      ["request identity", preview.request_identity], ["manifest", preview.preview_manifest_sha256],
      ["待补来源", `${shortId(pending.planned_id)} · ${pending.student_name || "名称不可用"}`], ["超额来源", `${shortId(overage.actual_id)} · ${overage.student_name || "名称不可用"}`],
      ["本次清偿", minutesLabel(preview.requested_minutes)], ["待补处理前", minutesLabel(pending.before_remaining_minutes)],
      ["待补处理后", minutesLabel(pending.after_remaining_minutes)], ["超额处理前", minutesLabel(overage.before_available_minutes)],
      ["超额处理后", minutesLabel(overage.after_available_minutes)], ["待补金额", moneyLabel(pending.amount_jpy)],
      ["超额金额", moneyLabel(overage.amount_jpy)], ["净金额", moneyLabel(financial.net_amount_jpy)],
      ["same teacher", boolLabel(comparison.same_teacher)], ["same subject", boolLabel(comparison.same_subject)],
      ["推荐pending", fifo.recommended_pending_planned_id || "无"], ["是否推荐对象", boolLabel(fifo.is_recommended_target)],
      ["偏离原因", fifo.deviation_reason_code || "无"], ["pending lock", boolLabel(pending.source_locked)],
      ["overage lock", boolLabel(overage.source_locked)], ["forward adjustment", boolLabel(financial.requires_forward_adjustment)],
      ["forward目标月", financial.forward_destination_month || "无"], ["actor blocker", authorization.blocker_code || "无"],
      ["pending fingerprint", preview.source_versions?.pending_row_md5], ["overage fingerprint", preview.source_versions?.overtime_row_md5],
    ].map(([label, value]) => fact(label, value)).join("")}</div>${comparison.same_teacher === false || comparison.same_subject === false ? `<p class="lesson-clearance-guidance">本次清偿跨老师或跨科目。系统允许该业务动作，但需要人工确认选择无误。</p>` : ""}${confirmations.length ? `<div class="lesson-clearance-confirmations">${confirmations.join("")}</div>` : ""}<p class="section-note">writer_revalidation_required=${escapeHtml(boolLabel(preview.writer_revalidation_required))}；reservation_created=${escapeHtml(boolLabel(preview.reservation_created))}。最终按钮始终disabled，本阶段无writer调用路径。</p></section>`;
  }

  function syncInvalidatedPreviewDisplay() {
    const identity = dom.selectionPanel.querySelector(".lesson-clearance-preview-actions code");
    const previewButton = dom.selectionPanel.querySelector("#lessonClearancePreviewButton");
    if (identity) identity.textContent = `request identity：${state.selection.requestIdentity || "选择两条source后生成"}`;
    if (previewButton) previewButton.textContent = "读取DB权威Preview";
    dom.selectionPanel.querySelector(".lesson-clearance-error")?.remove();
    renderPreview();
  }

  async function requestPreview() {
    try {
      const payload = state.previewRequest();
      counters.previews += 1;
      const preview = await api.previewClearance(payload);
      state.acceptPreview(preview);
    } catch (error) {
      state.rejectPreview(new Error(lessonClearanceErrorMessage(error)));
    }
    renderSelection();
  }

  async function requestReversalPreview(clearanceId) {
    const requestIdentity = globalThis.crypto?.randomUUID?.() || "";
    try {
      counters.reversalPreviews += 1;
      state.selection.reversalPreview = await api.previewReversal({
        requestIdentity,
        clearanceId,
        reversalDate: new Date().toISOString().slice(0, 10),
      });
      state.selection.reversalError = "";
    } catch (error) {
      state.selection.reversalPreview = null;
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
      if (pendingButton) state.selectPending(pendingButton.dataset.selectClearancePending);
      if (overtimeButton) state.selectOvertime(overtimeButton.dataset.selectClearanceOvertime);
      if (crossButton) crossView = crossButton.dataset.crossMonthView;
      if (reversalButton) {
        requestReversalPreview(reversalButton.dataset.previewClearanceReversal);
        return;
      }
      renderTabPanel();
      renderSelection();
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
    dom.selectionPanel?.addEventListener("click", (event) => {
      if (event.target.id === "lessonClearancePreviewButton") requestPreview();
    });
    dom.previewPanel?.addEventListener("change", (event) => {
      const name = event.target.dataset.clearanceConfirmation;
      if (name === "crossTeacher") state.selection.crossTeacherConfirmed = event.target.checked;
      if (name === "crossSubject") state.selection.crossSubjectConfirmed = event.target.checked;
      if (name === "forward") state.selection.forwardConfirmed = event.target.checked;
    });
  }

  function init() {
    if (initialized) return;
    initialized = true;
    cacheDom();
    bindEvents();
    if (dom.confirmButton) {
      dom.confirmButton.disabled = true;
      dom.confirmButton.replaceWith(dom.confirmButton.cloneNode(true));
    }
  }

  return Object.freeze({
    init,
    open: openDialog,
    close: closeDialog,
    state,
    counters,
  });
}
