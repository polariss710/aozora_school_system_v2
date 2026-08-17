const ROLE_CAPABILITIES = Object.freeze({
  admin: Object.freeze({ view: true, select: true, preview: true, locked: true }),
  operator: Object.freeze({ view: true, select: true, preview: true, locked: false }),
  read_only: Object.freeze({ view: true, select: false, preview: false, locked: false }),
});

export const LESSON_CLEARANCE_DEFAULT_FILTERS = Object.freeze({
  studentId: "",
  businessEntityId: "",
  settlementMonth: "",
  status: "",
  evidenceStatus: "",
  fifoOnly: false,
});

const clone = (value) => structuredClone(value);
const uuid = () => globalThis.crypto?.randomUUID?.() || "";

export function lessonClearanceCapabilities(role) {
  return ROLE_CAPABILITIES[role] || Object.freeze({ view: false, select: false, preview: false, locked: false });
}

export class LessonClearanceWorkspaceState {
  constructor({ role = "" } = {}) {
    this.role = role;
    this.draftFilters = clone(LESSON_CLEARANCE_DEFAULT_FILTERS);
    this.appliedFilters = clone(LESSON_CLEARANCE_DEFAULT_FILTERS);
    this.data = this.emptyData();
    this.activeTab = "pending";
    this.selection = this.emptySelection();
  }

  emptyData() {
    return {
      pendingPayload: null,
      overagePayload: null,
      packagePayload: null,
      crossMonthPayload: null,
      summary: null,
      history: [],
    };
  }

  emptySelection() {
    return {
      pendingId: "",
      overtimeId: "",
      allocatedMinutes: "",
      clearanceType: "overtime_offset",
      operationDate: new Date().toISOString().slice(0, 10),
      deviationReasonCode: "",
      deviationReasonNote: "",
      businessNote: "",
      requestIdentity: "",
      preview: null,
      previewError: "",
      crossTeacherConfirmed: false,
      crossSubjectConfirmed: false,
      forwardConfirmed: false,
      reversalPreview: null,
      reversalError: "",
    };
  }

  capabilities() {
    return lessonClearanceCapabilities(this.role);
  }

  setRole(role) {
    this.role = role || "";
    this.clearSelection();
  }

  setData({ pendingPayload, overagePayload, packagePayload, crossMonthPayload, summary, history }) {
    this.data = {
      pendingPayload: pendingPayload || null,
      overagePayload: overagePayload || null,
      packagePayload: packagePayload || null,
      crossMonthPayload: crossMonthPayload || null,
      summary: summary || null,
      history: Array.isArray(history) ? history : [],
    };
    this.clearSelection();
  }

  setTab(tab) {
    if (["pending", "overages", "packages", "history", "cross-month"].includes(tab)) {
      this.activeTab = tab;
    }
  }

  setDraftFilter(name, value) {
    if (!(name in this.draftFilters)) return;
    this.draftFilters[name] = name === "fifoOnly" ? Boolean(value) : String(value || "");
  }

  resetDraftFilters() {
    this.draftFilters = clone(LESSON_CLEARANCE_DEFAULT_FILTERS);
  }

  applyDraftFilters() {
    this.appliedFilters = clone(this.draftFilters);
    this.clearSelection();
  }

  clearSelection() {
    this.selection = this.emptySelection();
  }

  pendingRows() {
    return this.filterRows(this.data.pendingPayload?.items || [], "pending");
  }

  overageRows() {
    return this.filterRows(this.data.overagePayload?.items || [], "overage");
  }

  packageRows() {
    return this.filterRows(this.data.packagePayload?.items || [], "package");
  }

  historyRows() {
    return this.filterRows(this.data.history || [], "history");
  }

  crossMonthRows() {
    return this.filterRows(this.data.crossMonthPayload?.items || [], "cross-month");
  }

  filterRows(rows, kind) {
    const filters = this.appliedFilters;
    return rows.filter((row) => {
      const studentId = row.student_id || "";
      const entityId = row.business_entity_id || "";
      const month = kind === "pending"
        ? row.source_year_month
        : kind === "overage"
          ? row.student_settlement_month
          : kind === "package"
            ? row.student_settlement_month
            : kind === "cross-month"
              ? row.actual_month
              : row.operational_year_month || row.financial_year_month;
      const evidence = row.evidence_status || "";
      if (filters.studentId && studentId !== filters.studentId) return false;
      if (filters.businessEntityId && entityId !== filters.businessEntityId) return false;
      if (filters.settlementMonth && month !== filters.settlementMonth) return false;
      if (filters.evidenceStatus && evidence !== filters.evidenceStatus) return false;
      if (filters.status && !this.matchesStatus(row, filters.status, kind)) return false;
      if (filters.fifoOnly && kind === "pending" && Number(row.fifo_rank) !== 1) return false;
      if (filters.fifoOnly && kind === "overage" && Number(row.display_rank) !== 1) return false;
      return true;
    });
  }

  matchesStatus(row, status, kind) {
    if (kind === "package") return status === "available" ? row.status === "active" : false;
    if (status === "available") return row.can_be_candidate === true;
    if (status === "locked") return row.is_locked === true;
    if (status === "claimed") return row.active_claimed === true;
    if (status === "blocked") return row.can_be_candidate !== true;
    return true;
  }

  shouldOpenRow(row, kind) {
    const filters = this.appliedFilters;
    if (filters.studentId || filters.businessEntityId || filters.settlementMonth || filters.status || filters.evidenceStatus) {
      return true;
    }
    if (filters.fifoOnly) {
      return kind === "pending" ? Number(row.fifo_rank) === 1 : Number(row.display_rank) === 1;
    }
    return false;
  }

  selectPending(id) {
    if (!this.capabilities().select) return false;
    const row = (this.data.pendingPayload?.items || []).find((item) => item.pending_source_planned_id === id);
    if (!row || row.can_be_candidate !== true) return false;
    if (this.selection.pendingId === id) return true;
    this.selection.pendingId = id;
    this.invalidatePreview(true);
    return true;
  }

  selectOvertime(id) {
    if (!this.capabilities().select) return false;
    const row = (this.data.overagePayload?.items || []).find((item) => item.overtime_source_actual_id === id);
    if (!row || row.can_be_candidate !== true) return false;
    if (this.selection.overtimeId === id) return true;
    this.selection.overtimeId = id;
    this.invalidatePreview(true);
    return true;
  }

  setPreviewInput(name, value) {
    if (!(name in this.selection)) return;
    const normalized = typeof this.selection[name] === "boolean" ? Boolean(value) : String(value ?? "");
    if (this.selection[name] === normalized) return;
    this.selection[name] = normalized;
    const identityFields = new Set([
      "allocatedMinutes",
      "clearanceType",
      "operationDate",
      "deviationReasonCode",
      "deviationReasonNote",
      "businessNote",
    ]);
    if (identityFields.has(name)) this.invalidatePreview(true);
  }

  invalidatePreview(regenerateIdentity = false) {
    this.selection.preview = null;
    this.selection.previewError = "";
    this.selection.crossTeacherConfirmed = false;
    this.selection.crossSubjectConfirmed = false;
    this.selection.forwardConfirmed = false;
    if (regenerateIdentity) {
      this.selection.requestIdentity = this.selection.pendingId && this.selection.overtimeId ? uuid() : "";
    }
  }

  selectedPending() {
    return (this.data.pendingPayload?.items || []).find(
      (row) => row.pending_source_planned_id === this.selection.pendingId,
    ) || null;
  }

  selectedOverage() {
    return (this.data.overagePayload?.items || []).find(
      (row) => row.overtime_source_actual_id === this.selection.overtimeId,
    ) || null;
  }

  previewValidationMessage() {
    if (!this.capabilities().preview) return "当前角色只能查看余额，不能进入清偿预览。";
    const pending = this.selectedPending();
    const overage = this.selectedOverage();
    if (!pending || !overage) return "请分别人工选择一条待补来源和一条可用超额。";
    const minutes = Number(this.selection.allocatedMinutes);
    if (!Number.isInteger(minutes) || minutes <= 0) return "请输入大于0的整数分钟；最终可用余额由DB Preview校验。";
    if (!this.selection.operationDate) return "请选择清偿日期。";
    if (Number(pending.fifo_rank) !== 1 && !this.selection.deviationReasonCode) {
      return "未采用FIFO建议时必须选择偏离原因。";
    }
    if (this.selection.deviationReasonCode === "other" && !this.selection.deviationReasonNote.trim()) {
      return "偏离原因选择“其他”时必须填写说明。";
    }
    return "";
  }

  previewRequest() {
    const validation = this.previewValidationMessage();
    if (validation) throw new Error(validation);
    if (!this.selection.requestIdentity) this.selection.requestIdentity = uuid();
    return {
      requestIdentity: this.selection.requestIdentity,
      clearanceType: this.selection.clearanceType,
      pendingSourcePlannedId: this.selection.pendingId,
      overtimeSourceActualId: this.selection.overtimeId,
      allocatedMinutes: Number(this.selection.allocatedMinutes),
      operationDate: this.selection.operationDate,
      deviationReasonCode: this.selection.deviationReasonCode || null,
      deviationReasonNote: this.selection.deviationReasonNote.trim() || null,
      businessNote: this.selection.businessNote.trim() || null,
      administrativeFinancialTreatment: null,
    };
  }

  acceptPreview(preview) {
    if (!preview || preview.request_identity !== this.selection.requestIdentity) {
      this.selection.preview = null;
      this.selection.previewError = "来源事实已变化，请重新预览。系统不会使用旧预览提交。";
      return false;
    }
    this.selection.preview = preview;
    this.selection.previewError = "";
    return true;
  }

  rejectPreview(error) {
    this.selection.preview = null;
    this.selection.previewError = error?.message || "课时清偿Preview读取失败，请重试。";
  }
}
