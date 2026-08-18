const ROLE_CAPABILITIES = Object.freeze({
  admin: Object.freeze({ view: true, select: true, preview: true, create: true, reverse: true, locked: true }),
  operator: Object.freeze({ view: true, select: true, preview: true, create: true, reverse: false, locked: false }),
  read_only: Object.freeze({ view: true, select: false, preview: false, create: false, reverse: false, locked: false }),
});

export const LESSON_CLEARANCE_DEFAULT_FILTERS = Object.freeze({
  studentId: "",
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
      previewInputSnapshot: null,
      previewError: "",
      previewErrorDetail: "",
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
    if (filters.studentId || filters.settlementMonth || filters.status || filters.evidenceStatus) {
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
    this.selection.previewInputSnapshot = null;
    this.selection.previewError = "";
    this.selection.previewErrorDetail = "";
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
    if (!pending || !overage) return "请选择一个待补对象和一条可用超额。";
    if (pending.student_id !== overage.student_id) {
      return "待补对象与可用超额属于不同学生，当前不能合并清偿。";
    }
    if (pending.business_entity_id !== overage.business_entity_id) {
      return "该学生存在不同业务范围的课时余额，当前不能合并清偿，请分别处理。";
    }
    const minutes = Number(this.selection.allocatedMinutes);
    if (!Number.isInteger(minutes) || minutes <= 0) return "请输入大于0的整数分钟；最终可用余额由系统核对。";
    if (!this.selection.operationDate) return "请选择清偿日期。";
    if (!this.selection.businessNote.trim()) return "请填写业务说明。";
    if (Number(pending.fifo_rank) !== 1 && !this.selection.deviationReasonCode) {
      return "未采用系统建议顺序时必须选择偏离原因。";
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

  acceptPreview(preview, sentRequest) {
    const pending = this.selectedPending();
    const overage = this.selectedOverage();
    const sourceVersions = preview?.source_versions || {};
    const request = sentRequest && typeof sentRequest === "object" ? clone(sentRequest) : null;
    const requestKey = request ? JSON.stringify(request) : "";
    const currentRequestKey = this.requestKey();
    const inputMatches = requestKey === currentRequestKey
      && preview?.request_identity === request?.requestIdentity
      && preview?.clearance_type === request?.clearanceType
      && Number(preview?.requested_minutes) === Number(request?.allocatedMinutes)
      && preview?.operation_date === request?.operationDate
      && preview?.pending_source?.planned_id === request?.pendingSourcePlannedId
      && preview?.overtime_source?.actual_id === request?.overtimeSourceActualId;
    const fingerprintsMatch = Boolean(sourceVersions.pending_row_md5 && sourceVersions.overtime_row_md5)
      && sourceVersions.pending_row_md5 === pending?.source_row_md5
      && sourceVersions.overtime_row_md5 === overage?.source_row_md5;
    if (!request?.businessNote) {
      this.selection.preview = null;
      this.selection.previewBinding = null;
      this.selection.previewInputSnapshot = null;
      this.selection.previewError = "业务说明缺失，请重新核对";
      this.selection.previewErrorDetail = "";
      return false;
    }
    if (!preview || !inputMatches || !fingerprintsMatch || !preview.preview_manifest_sha256) {
      this.selection.preview = null;
      this.selection.previewBinding = null;
      this.selection.previewInputSnapshot = null;
      this.selection.previewError = "所选对象事实已变化，请重新核对。系统不会使用旧结果提交。";
      this.selection.previewErrorDetail = "";
      return false;
    }
    this.selection.preview = preview;
    this.selection.previewInputSnapshot = Object.freeze({
      requestIdentity: request.requestIdentity,
      manifest: preview.preview_manifest_sha256,
      clearanceType: request.clearanceType,
      pendingSourcePlannedId: request.pendingSourcePlannedId,
      overtimeSourceActualId: request.overtimeSourceActualId,
      allocatedMinutes: request.allocatedMinutes,
      operationDate: request.operationDate,
      deviationReasonCode: request.deviationReasonCode,
      deviationReasonNote: request.deviationReasonNote,
      businessNote: request.businessNote,
      administrativeFinancialTreatment: request.administrativeFinancialTreatment,
      confirmations: Object.freeze({
        crossTeacher: this.selection.crossTeacherConfirmed,
        crossSubject: this.selection.crossSubjectConfirmed,
        forward: this.selection.forwardConfirmed,
      }),
    });
    this.selection.previewBinding = {
      requestKey,
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
    this.selection.previewErrorDetail = "";
    return true;
  }

  rejectPreview(error, technicalDetail = "") {
    this.selection.preview = null;
    this.selection.previewBinding = null;
    this.selection.previewInputSnapshot = null;
    this.selection.previewError = error?.message || "课时清偿核对失败，请重新读取余额。";
    this.selection.previewErrorDetail = technicalDetail;
  }

  snapshotRequestFields(snapshot = this.selection.previewInputSnapshot) {
    if (!snapshot) return null;
    return {
      requestIdentity: snapshot.requestIdentity,
      clearanceType: snapshot.clearanceType,
      pendingSourcePlannedId: snapshot.pendingSourcePlannedId,
      overtimeSourceActualId: snapshot.overtimeSourceActualId,
      allocatedMinutes: snapshot.allocatedMinutes,
      operationDate: snapshot.operationDate,
      deviationReasonCode: snapshot.deviationReasonCode,
      deviationReasonNote: snapshot.deviationReasonNote,
      businessNote: snapshot.businessNote,
      administrativeFinancialTreatment: snapshot.administrativeFinancialTreatment,
    };
  }

  prepareValidationMessage() {
    if (!this.capabilities().create) return "当前角色不能提交课时清偿。";
    const preview = this.selection.preview;
    const binding = this.selection.previewBinding;
    const snapshot = this.selection.previewInputSnapshot;
    if (preview && (!snapshot || !snapshot.businessNote)) {
      return "业务说明缺失，请重新核对";
    }
    const snapshotRequest = this.snapshotRequestFields(snapshot);
    const snapshotRequestKey = snapshotRequest ? JSON.stringify(snapshotRequest) : "";
    if (!preview || !binding || !snapshot
      || binding.requestKey !== snapshotRequestKey
      || binding.requestKey !== this.requestKey()
      || binding.manifest !== snapshot.manifest
      || preview.request_identity !== snapshot.requestIdentity
      || preview.preview_manifest_sha256 !== snapshot.manifest) {
      return "所选对象事实已变化，请重新核对。系统不会使用旧结果提交。";
    }
    if (preview.writer_revalidation_required !== true || preview.reservation_created !== false) {
      return "系统核对结果不完整，不能准备提交。";
    }
    if (preview.authorization?.can_execute_for_current_actor !== true) {
      return "当前账号权限不允许执行该操作。";
    }
    if (preview.comparison?.same_student === false) return "待补对象与可用超额属于不同学生，系统已阻止提交。";
    if (preview.comparison?.same_business_entity === false) return "该学生存在不同业务范围的课时余额，当前不能合并清偿，请分别处理。";
    if (preview.comparison?.same_unit_price === false) return "当前只允许清偿相同单价的课时余额。";
    if (preview.pending_source?.active_claimed || preview.overtime_source?.active_claimed) return "所选课时余额已被其他结算或清偿流程占用。";
    if (preview.fifo?.deviation_required && preview.fifo?.deviation_reason_valid !== true) return "偏离系统建议顺序的原因未通过核对。";
    if (this.selection.requiredConfirmations.crossTeacher && !this.selection.crossTeacherConfirmed) return "请确认本次清偿跨老师。";
    if (this.selection.requiredConfirmations.crossSubject && !this.selection.crossSubjectConfirmed) return "请确认本次清偿跨科目。";
    if (this.selection.requiredConfirmations.forward && !this.selection.forwardConfirmed) return "请确认涉及锁定月份的后续调整。";
    if (this.selection.requiredConfirmations.forward && !this.capabilities().locked) return "当前角色不能处理锁定月份的后续调整，必须由管理员执行。";
    return "";
  }

  writerRequest() {
    const validation = this.prepareValidationMessage();
    if (validation) throw new Error(validation);
    return clone(this.snapshotRequestFields());
  }

  createResultMatchesSnapshot(result) {
    const preview = this.selection.preview;
    const snapshot = this.selection.previewInputSnapshot;
    if (!result || !preview || !snapshot) return false;
    return typeof result.clearance_id === "string"
      && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result.clearance_id)
      && typeof result.idempotent_replay === "boolean"
      && Number(result.pending_remaining_minutes) === Number(preview.pending_source?.after_remaining_minutes)
      && Number(result.overtime_remaining_minutes) === Number(preview.overtime_source?.after_available_minutes)
      && result.requires_forward_adjustment === preview.financial?.requires_forward_adjustment
      && result.recommended_pending_source_id === preview.fifo?.recommended_pending_planned_id
      && result.deviated_from_recommendation === preview.fifo?.deviation_required;
  }

  historyMatchesCreateSnapshot(row, expectedClearanceId = null) {
    const snapshot = this.selection.previewInputSnapshot;
    const binding = this.selection.previewBinding;
    const preview = this.selection.preview;
    if (!row || !snapshot || !binding || !preview) return false;
    const previewBindingMatches = binding.manifest === snapshot.manifest
      && preview.preview_manifest_sha256 === snapshot.manifest
      && preview.request_identity === snapshot.requestIdentity;
    const persistedManifest = String(row.input_manifest_sha256 || "");
    return previewBindingMatches
      && (!expectedClearanceId || row.clearance_id === expectedClearanceId)
      && (row.request_identity === snapshot.requestIdentity || row.idempotency_key === snapshot.requestIdentity)
      && row.pending_source_planned_id === snapshot.pendingSourcePlannedId
      && row.overtime_source_actual_id === snapshot.overtimeSourceActualId
      && Number(row.allocated_minutes) === Number(snapshot.allocatedMinutes)
      && row.operation_date === snapshot.operationDate
      && row.clearance_type === snapshot.clearanceType
      && row.business_note === snapshot.businessNote
      && row.is_effective === true
      && row.is_reversed !== true
      && /^[0-9a-f]{64}$/.test(persistedManifest);
  }

  rejectCreate(message, technicalDetail = "") {
    this.invalidatePreview(true);
    this.selection.previewError = message || "课时清偿未建立，请重新核对。";
    this.selection.previewErrorDetail = technicalDetail;
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
        || "该清偿已失效、已撤销或不符合当前撤销条件。";
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
      throw new Error("请先取得最新撤销核对结果。系统不会使用旧结果撤销。");
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
