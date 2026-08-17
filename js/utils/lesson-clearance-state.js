const ROLE_CAPABILITIES = Object.freeze({
  admin: Object.freeze({ view: true, select: true, preview: true, create: true, reverse: true, locked: true }),
  operator: Object.freeze({ view: true, select: true, preview: true, create: true, reverse: false, locked: false }),
  read_only: Object.freeze({ view: true, select: false, preview: false, create: false, reverse: false, locked: false }),
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
const currentLocalDate = () => {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

export function lessonClearanceCapabilities(role) {
  return ROLE_CAPABILITIES[role] || Object.freeze({ view: false, select: false, preview: false, create: false, reverse: false, locked: false });
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
      operationDate: currentLocalDate(),
      deviationReasonCode: "",
      deviationReasonNote: "",
      businessNote: "",
      requestIdentity: "",
      preview: null,
      previewBinding: null,
      previewError: "",
      crossTeacherConfirmed: false,
      crossSubjectConfirmed: false,
      forwardConfirmed: false,
      requiredConfirmations: { crossTeacher: false, crossSubject: false, forward: false },
      submitting: false,
      reversalClearanceId: "",
      reversalRequestIdentity: "",
      reversalDate: currentLocalDate(),
      reversalReason: "",
      reversalPreview: null,
      reversalBinding: null,
      reversalError: "",
      reversalSubmitting: false,
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

  requestKey() {
    return JSON.stringify(this.previewRequestFields());
  }

  previewRequestFields() {
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

  invalidatePreview(regenerateIdentity = false, preserveConfirmations = false) {
    this.selection.preview = null;
    this.selection.previewBinding = null;
    this.selection.previewError = "";
    if (!preserveConfirmations) {
      this.selection.crossTeacherConfirmed = false;
      this.selection.crossSubjectConfirmed = false;
      this.selection.forwardConfirmed = false;
      this.selection.requiredConfirmations = { crossTeacher: false, crossSubject: false, forward: false };
    }
    if (regenerateIdentity) {
      this.selection.requestIdentity = this.selection.pendingId && this.selection.overtimeId ? uuid() : "";
    }
  }

  setConfirmation(name, checked) {
    const fields = {
      crossTeacher: "crossTeacherConfirmed",
      crossSubject: "crossSubjectConfirmed",
      forward: "forwardConfirmed",
    };
    const field = fields[name];
    if (!field || this.selection[field] === Boolean(checked)) return false;
    this.selection[field] = Boolean(checked);
    this.invalidatePreview(true, true);
    return true;
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
    return this.previewRequestFields();
  }

  acceptPreview(preview) {
    const pending = this.selectedPending();
    const overage = this.selectedOverage();
    const sourceVersions = preview?.source_versions || {};
    const inputMatches = preview?.request_identity === this.selection.requestIdentity
      && preview?.clearance_type === this.selection.clearanceType
      && Number(preview?.requested_minutes) === Number(this.selection.allocatedMinutes)
      && preview?.operation_date === this.selection.operationDate
      && preview?.pending_source?.planned_id === this.selection.pendingId
      && preview?.overtime_source?.actual_id === this.selection.overtimeId;
    const fingerprintsMatch = Boolean(sourceVersions.pending_row_md5 && sourceVersions.overtime_row_md5)
      && sourceVersions.pending_row_md5 === pending?.source_row_md5
      && sourceVersions.overtime_row_md5 === overage?.source_row_md5;
    if (!preview || !inputMatches || !fingerprintsMatch || !preview.preview_manifest_sha256) {
      this.selection.preview = null;
      this.selection.previewBinding = null;
      this.selection.previewError = "来源事实已变化，请重新预览。系统不会使用旧预览提交。";
      return false;
    }
    this.selection.preview = preview;
    this.selection.previewBinding = {
      requestKey: this.requestKey(),
      manifest: preview.preview_manifest_sha256,
      pendingFingerprint: sourceVersions.pending_row_md5,
      overtimeFingerprint: sourceVersions.overtime_row_md5,
    };
    this.selection.requiredConfirmations = {
      crossTeacher: preview.comparison?.same_teacher === false,
      crossSubject: preview.comparison?.same_subject === false,
      forward: preview.financial?.requires_forward_adjustment === true,
    };
    this.selection.previewError = "";
    return true;
  }

  rejectPreview(error) {
    this.selection.preview = null;
    this.selection.previewBinding = null;
    this.selection.previewError = error?.message || "课时清偿Preview读取失败，请重试。";
  }

  prepareValidationMessage() {
    if (!this.capabilities().create) return "当前角色不能提交课时清偿。";
    const preview = this.selection.preview;
    const binding = this.selection.previewBinding;
    if (!preview || !binding || binding.requestKey !== this.requestKey()) {
      return "来源事实已变化，请重新预览。系统不会使用旧预览提交。";
    }
    if (preview.writer_revalidation_required !== true || preview.reservation_created !== false) {
      return "Preview合同不完整，不能准备提交。";
    }
    if (preview.authorization?.can_execute_for_current_actor !== true) {
      return preview.authorization?.blocker_message || preview.authorization?.blocker_code || "DB角色合同不允许当前操作。";
    }
    if (preview.comparison?.same_student === false) return "待补与超额属于不同学生，DB已拒绝提交。";
    if (preview.comparison?.same_business_entity === false) return "待补与超额属于不同业务归属，DB已拒绝提交。";
    if (preview.comparison?.same_unit_price === false) return "V2只允许相同单价来源，DB已拒绝异价提交。";
    if (preview.pending_source?.active_claimed || preview.overtime_source?.active_claimed) return "来源存在active variance claim，不能提交。";
    if (preview.fifo?.deviation_required && preview.fifo?.deviation_reason_valid !== true) return "FIFO偏离原因未通过DB校验。";
    if (this.selection.requiredConfirmations.crossTeacher && !this.selection.crossTeacherConfirmed) return "请确认本次清偿跨老师。";
    if (this.selection.requiredConfirmations.crossSubject && !this.selection.crossSubjectConfirmed) return "请确认本次清偿跨科目。";
    if (this.selection.requiredConfirmations.forward && !this.selection.forwardConfirmed) return "请确认locked forward处理。";
    if (this.selection.requiredConfirmations.forward && !this.capabilities().locked) return "当前角色不能处理locked forward，必须由active admin执行。";
    return "";
  }

  writerRequest() {
    const validation = this.prepareValidationMessage();
    if (validation) throw new Error(validation);
    return this.previewRequestFields();
  }

  beginReversal(clearanceId) {
    if (!this.capabilities().reverse) return false;
    const row = this.data.history.find((item) => item.clearance_id === clearanceId && item.can_reverse === true);
    if (!row) return false;
    this.selection.reversalClearanceId = clearanceId;
    this.selection.reversalRequestIdentity = uuid();
    this.selection.reversalDate = currentLocalDate();
    this.selection.reversalReason = "";
    this.selection.reversalPreview = null;
    this.selection.reversalBinding = null;
    this.selection.reversalError = "";
    return true;
  }

  reversalPreviewRequest() {
    if (!this.capabilities().reverse || !this.selection.reversalClearanceId) throw new Error("当前清偿不可撤销。");
    return {
      requestIdentity: this.selection.reversalRequestIdentity,
      clearanceId: this.selection.reversalClearanceId,
      reversalDate: this.selection.reversalDate,
    };
  }

  acceptReversalPreview(preview) {
    const valid = preview?.request_identity === this.selection.reversalRequestIdentity
      && preview?.original_clearance?.clearance_id === this.selection.reversalClearanceId
      && preview?.current_state?.is_effective === true
      && preview?.current_state?.already_reversed === false
      && preview?.authorization?.can_reverse === true
      && Boolean(preview?.reversal_manifest_sha256);
    if (!valid) {
      this.selection.reversalPreview = null;
      this.selection.reversalBinding = null;
      this.selection.reversalError = preview?.authorization?.blocker_message
        || "该清偿已失效、已撤销或不符合当前DB撤销合同。";
      return false;
    }
    this.selection.reversalPreview = preview;
    this.selection.reversalBinding = {
      requestIdentity: preview.request_identity,
      clearanceId: preview.original_clearance.clearance_id,
      manifest: preview.reversal_manifest_sha256,
    };
    this.selection.reversalError = "";
    return true;
  }

  reversalWriterRequest() {
    const preview = this.selection.reversalPreview;
    const binding = this.selection.reversalBinding;
    if (!this.capabilities().reverse || !preview || !binding
      || binding.requestIdentity !== this.selection.reversalRequestIdentity
      || binding.clearanceId !== this.selection.reversalClearanceId) {
      throw new Error("请先取得最新DB Reversal Preview。系统不会使用旧预览撤销。");
    }
    if (!this.selection.reversalReason.trim()) throw new Error("请填写撤销原因。");
    return {
      clearanceId: this.selection.reversalClearanceId,
      reversalDate: this.selection.reversalDate,
      reason: this.selection.reversalReason.trim(),
      requestIdentity: this.selection.reversalRequestIdentity,
    };
  }
}
