const DECIMAL_RE = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/;

export const ONLINE_ADJUSTMENT_MODES = Object.freeze({
  CARRY_FINAL_BALANCE: "carry_final_balance",
  CLEAR_BALANCE: "clear_balance",
  MANUAL_ADJUSTMENT: "manual_adjustment",
});

export const ONLINE_SOURCE_TREATMENT_MODES = Object.freeze({
  SEPARATE: "separate_makeup_and_overage_v1",
  NET_FINANCIAL: "net_lesson_variance_to_financial_credit_v1",
});

export function canUseOnlineDraftSave(membershipRole, status) {
  return membershipRole === "admin"
    && status?.can_save === true
    && status?.effective_state?.effective_status === "incomplete"
    && !status?.save_blocker_code
    && !status?.immutable_blocker;
}

const PREVIEW_ONLY_MONTH_BLOCKERS = new Set([
  "SETTLEMENT_MONTH_NOT_CLOSED",
  "SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED",
]);

export function canUseOnlineDraftPreview(membershipRole, status) {
  if (membershipRole !== "admin"
      || status?.effective_state?.effective_status !== "incomplete") return false;
  if (canUseOnlineDraftSave(membershipRole, status)) return true;
  return PREVIEW_ONLY_MONTH_BLOCKERS.has(status?.save_blocker_code)
    && status?.immutable_blocker?.code === status.save_blocker_code;
}

export function decimalString(value, fieldName = "decimal") {
  const text = value === null || value === undefined ? "" : String(value).trim();
  if (!DECIMAL_RE.test(text)) {
    throw new Error(`${fieldName} must be a decimal string`);
  }
  return text;
}

export function optionalDecimalString(value, fieldName = "decimal") {
  if (value === null || value === undefined || String(value).trim() === "") return null;
  return decimalString(value, fieldName);
}

export function isPositiveDecimalString(value) {
  const text = String(value || "").trim();
  if (!DECIMAL_RE.test(text) || text.startsWith("-")) return false;
  return /[1-9]/.test(text);
}

export function canonicalDecimal(value) {
  const text = decimalString(value);
  const negative = text.startsWith("-");
  const unsigned = negative ? text.slice(1) : text;
  const [integerPart, fractionPart = ""] = unsigned.split(".");
  const integer = integerPart.replace(/^0+(?=\d)/, "");
  const fraction = fractionPart.replace(/0+$/, "");
  const magnitude = fraction ? `${integer}.${fraction}` : integer;
  if (/^0(?:\.0*)?$/.test(magnitude)) return "0";
  return negative ? `-${magnitude}` : magnitude;
}

export function onlineStatusDisplay(status, statusError = null) {
  if (statusError || !status) {
    return {
      key: "unknown",
      label: "在线状态未知",
      detail: "暂时无法读取DB权威在线状态，本条保持只读。",
      className: "status-cancelled",
    };
  }
  const effective = status.effective_state?.effective_status || "incomplete";
  const blocker = status.save_blocker_code
    ? {
      code: status.save_blocker_code,
      detail: status.save_blocker_message || status.immutable_blocker?.detail,
    }
    : status.immutable_blocker;
  if (blocker) {
    return {
      key: blocker.code || "blocked",
      label: blockerLabel(blocker.code),
      detail: blocker.detail || "该月份当前不可修改。",
      className: "status-cancelled",
    };
  }
  if (effective === "ordinary_locked") {
    return { key: effective, label: "已正式锁定", detail: "该月份已正式锁定，只能查看。", className: "status-paid" };
  }
  if (effective === "historically_consumed_immutable") {
    return { key: effective, label: "历史消费只读", detail: "该月份已被历史账单或不可变事实消费，只能查看。", className: "status-paid" };
  }
  if (effective === "historical_zero_carry_complete") {
    return { key: effective, label: "历史零结转已完成", detail: "该月份已通过历史零结转证据完成，只能查看。", className: "status-paid" };
  }
  if (status.requires_repreview === false) {
    return { key: "draft_saved", label: "草稿已保存", detail: "当前草稿与DB权威预览一致。", className: "status-paid" };
  }
  return { key: "incomplete", label: "未完成", detail: "可读取DB权威预览；保存草稿后仍不会锁定。", className: "status-pending" };
}

export function buildOnlineDraftSaveInput({ row, status, previewResult, input }) {
  if (!row?.student_id || !row?.year_month) throw new Error("settlement scope is required");
  if (!canUseOnlineDraftSave("admin", status)) throw new Error("status does not allow save");
  if (!previewResult?.preview || !previewResult?.preview_expected_facts) {
    throw new Error("authoritative preview is required");
  }
  const sourceMode = input.sourceTreatmentMode;
  const adjustmentMode = input.adjustmentMode;
  if (!Object.values(ONLINE_SOURCE_TREATMENT_MODES).includes(sourceMode)) {
    throw new Error("source treatment mode is invalid");
  }
  if (!Object.values(ONLINE_ADJUSTMENT_MODES).includes(adjustmentMode)) {
    throw new Error("adjustment mode is invalid");
  }
  const reason = String(input.reason || "").trim();
  const manualAmount = adjustmentMode === ONLINE_ADJUSTMENT_MODES.MANUAL_ADJUSTMENT
    ? decimalString(input.explicitUserAmountCny, "manualAdjustmentAmountCny")
    : null;
  if (!reason) throw new Error("reason is required by the save contract");
  const preview = previewResult.preview;
  const expected = previewResult.preview_expected_facts;
  return {
    studentId: row.student_id,
    settlementMonth: row.year_month,
    sourceTreatmentMode: sourceMode,
    settlementExchangeRate: optionalDecimalString(input.settlementExchangeRate, "settlementExchangeRate"),
    settlementExchangeRateSource: input.settlementExchangeRateSource || null,
    settlementExchangeRateEffectiveDate: input.settlementExchangeRateEffectiveDate || null,
    adjustmentMode,
    manualAdjustmentAmountCny: manualAmount,
    reason,
    note: String(input.note || ""),
    expectedPreviewManifestSha256: previewResult.preview_manifest_sha256,
    expectedLessonVarianceManifestSha256: expected.lesson_variance_manifest_sha256,
    expectedSourceCount: requireSourceCount(preview.lesson_variance_source_count),
    expectedUnusedPlannedCreditJpy: decimalString(preview.unused_planned_credit_jpy, "expectedUnusedPlannedCreditJpy"),
    expectedOverageChargeJpy: decimalString(preview.overage_charge_jpy, "expectedOverageChargeJpy"),
    expectedNetLessonVarianceJpy: decimalString(preview.net_lesson_variance_jpy, "expectedNetLessonVarianceJpy"),
    expectedNetLessonVarianceCny: decimalString(preview.net_lesson_variance_cny, "expectedNetLessonVarianceCny"),
    expectedSystemDifferenceCny: decimalString(expected.system_difference_cny, "expectedSystemDifferenceCny"),
    expectedFinalCarryoverCny: decimalString(preview.projected_final_carryover_cny, "expectedFinalCarryoverCny"),
    expectedSourceTreatmentDraftId: status.source_treatment_draft?.draft_id || null,
    expectedSourceTreatmentDraftUpdatedAt: status.source_treatment_draft?.updated_at || null,
    expectedAdjustmentDraftId: status.adjustment_draft?.draft_id || null,
    expectedAdjustmentDraftUpdatedAt: status.adjustment_draft?.updated_at || null,
  };
}

export function statusConfirmsDraftSave(status, previewResult, input) {
  if (!status || !previewResult?.preview || !previewResult?.preview_expected_facts) return false;
  const source = status.source_treatment_draft || {};
  const adjustment = status.adjustment_draft || {};
  const preview = previewResult.preview;
  const expected = previewResult.preview_expected_facts;
  if (!canUseOnlineDraftSave("admin", status)
      || source.status !== "active" || adjustment.status !== "active"
      || !source.draft_id || !adjustment.draft_id) return false;
  if (status.preview_manifest_sha256 !== previewResult.preview_manifest_sha256
      || status.lesson_manifest_sha256 !== expected.lesson_variance_manifest_sha256
      || source.source_manifest_sha256 !== expected.lesson_variance_manifest_sha256
      || source.source_count !== preview.lesson_variance_source_count
      || source.source_treatment_mode !== input.sourceTreatmentMode
      || adjustment.adjustment_mode !== input.adjustmentMode
      || nullableText(adjustment.reason).trim() !== nullableText(input.reason).trim()
      || nullableText(adjustment.note).trim() !== nullableText(input.note).trim()) return false;
  if (!sameNullableDecimal(source.settlement_exchange_rate, input.settlementExchangeRate)
      || nullableText(source.settlement_exchange_rate_source) !== nullableText(input.settlementExchangeRateSource)
      || nullableText(source.settlement_exchange_rate_effective_date) !== nullableText(input.settlementExchangeRateEffectiveDate)
      || canonicalDecimal(adjustment.adjustment_amount_cny) !== canonicalDecimal(preview.projected_adjustment_amount_cny)) return false;
  return status.requires_repreview === false;
}

export function classifySaveRecovery(beforeStatus, afterStatus, previewResult, input) {
  if (statusConfirmsDraftSave(afterStatus, previewResult, input)) return "confirmed";
  if (sameDraftVersions(beforeStatus, afterStatus)) return "unchanged";
  return "conflict";
}

export function sameDraftVersions(left, right) {
  return ["source_treatment_draft", "adjustment_draft"].every((key) => (
    nullableText(left?.[key]?.draft_id) === nullableText(right?.[key]?.draft_id)
    && nullableText(left?.[key]?.updated_at) === nullableText(right?.[key]?.updated_at)
  ));
}

export function createSingleFlight() {
  let active = false;
  return {
    get active() { return active; },
    async run(task) {
      if (active) return { skipped: true };
      active = true;
      try {
        return { skipped: false, value: await task() };
      } finally {
        active = false;
      }
    },
  };
}

function sameNullableDecimal(left, right) {
  if ((left === null || left === undefined || left === "")
      && (right === null || right === undefined || right === "")) return true;
  try {
    return canonicalDecimal(left) === canonicalDecimal(right);
  } catch (_error) {
    return false;
  }
}

function nullableText(value) {
  return value === null || value === undefined || value === "" ? "" : String(value);
}

function requireSourceCount(value) {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("expectedSourceCount is invalid");
  return value;
}

function blockerLabel(code) {
  return {
    SETTLEMENT_ORDINARY_ALREADY_LOCKED: "已正式锁定",
    SETTLEMENT_HISTORICALLY_CONSUMED: "历史消费只读",
    SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE: "历史零结转已完成",
    SETTLEMENT_SUCCESSOR_REVISION_BLOCKED: "后继学费事实已冻结",
    SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED: "不可变财务事实已消费",
    SETTLEMENT_WAGE_BLOCKED: "工资链路已冻结",
    SETTLEMENT_MONTH_NOT_CLOSED: "当前月份仅可预览",
    SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED: "未来月份仅可预览",
    SETTLEMENT_SOURCE_FACTS_EMPTY: "无可结算来源",
    SETTLEMENT_NOT_INCOMPLETE: "非普通未完成状态",
    SETTLEMENT_SCOPE_NOT_UNIQUE: "结算范围不唯一",
  }[code] || "当前不可修改";
}
