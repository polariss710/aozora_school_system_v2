import { supabase } from "../supabase-client.js";
import { requireUuid } from "./validation.js";

const SAVE_EDGE_NAME = "save-student-settlement-draft";
const LOCK_EDGE_NAME = "lock-student-settlement";
const DEFAULT_TIMEOUT_MS = 20_000;
const DECIMAL_RE = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/;
const SHA256_RE = /^[0-9a-f]{64}$/i;

export class StudentSettlementOnlineError extends Error {
  constructor(message, options = {}) {
    super(message);
    this.name = "StudentSettlementOnlineError";
    this.code = options.code || "SETTLEMENT_EDGE_REQUEST_FAILED";
    this.action = options.action || "stop";
    this.requestId = options.requestId || null;
    this.requiresStatusRecovery = options.requiresStatusRecovery === true;
  }
}

export async function getStudentSettlementOnlineStatus(studentId, settlementMonth) {
  const { data, error } = await supabase.rpc(
    "school_get_student_monthly_settlement_online_status",
    {
      p_student_id: requireUuid(studentId, "studentId"),
      p_year_month: requireMonth(settlementMonth),
    },
  );
  if (error) throw error;
  return data;
}

export async function saveStudentSettlementDraftOnline(input, options = {}) {
  const payload = buildSavePayload(input);
  return invokeSettlementEdge(SAVE_EDGE_NAME, payload, options.timeoutMs);
}

export async function lockStudentSettlementOnline(input, options = {}) {
  const payload = buildLockPayload(input);
  return invokeSettlementEdge(LOCK_EDGE_NAME, payload, options.timeoutMs);
}

async function invokeSettlementEdge(functionName, body, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const normalizedTimeout = requireTimeout(timeoutMs);
  let timerId;
  const timeout = new Promise((_, reject) => {
    timerId = setTimeout(() => reject(new StudentSettlementOnlineError(
      "请求结果暂不明确，请先刷新在线结算状态，确认结果后再决定下一步。",
      {
        code: "SETTLEMENT_EDGE_RESULT_UNCERTAIN",
        action: "refresh_status",
        requiresStatusRecovery: true,
      },
    )), normalizedTimeout);
  });

  try {
    const invocation = supabase.functions.invoke(functionName, { body });
    const { data, error } = await Promise.race([invocation, timeout]);
    if (error) {
      throw await normalizeFunctionError(error, data);
    }
    if (!data || data.ok !== true || !data.result) {
      throw new StudentSettlementOnlineError(
        "Edge返回格式无效，请刷新在线结算状态。",
        {
          code: "SETTLEMENT_EDGE_RESPONSE_INVALID",
          action: "refresh_status",
          requestId: safeText(data?.request_id),
          requiresStatusRecovery: true,
        },
      );
    }
    return data;
  } catch (error) {
    if (error instanceof StudentSettlementOnlineError) throw error;
    throw new StudentSettlementOnlineError(
      "网络请求未能确认结果，请先刷新在线结算状态，禁止直接重试。",
      {
        code: "SETTLEMENT_EDGE_RESULT_UNCERTAIN",
        action: "refresh_status",
        requiresStatusRecovery: true,
      },
    );
  } finally {
    clearTimeout(timerId);
  }
}

async function normalizeFunctionError(error, data) {
  let details = isRecord(data) ? data : null;
  const response = error?.context;
  if (!details && response && !response.bodyUsed) {
    try {
      const contentType = response.headers?.get?.("content-type") || "";
      if (contentType.includes("application/json")) {
        const parsed = await response.json();
        if (isRecord(parsed)) details = parsed;
      }
    } catch (_error) {
      details = null;
    }
  }
  if (details) {
    return new StudentSettlementOnlineError(
      safeText(details.message) || "在线结算操作未完成。",
      {
        code: safeText(details.code) || "SETTLEMENT_EDGE_REQUEST_FAILED",
        action: safeText(details.action) || "stop",
        requestId: safeText(details.request_id),
        requiresStatusRecovery:
          details.action === "refresh_status" || details.action === "repreview",
      },
    );
  }
  return new StudentSettlementOnlineError(
    "网络响应未能确认结果，请先刷新在线结算状态，禁止直接重试。",
    {
      code: "SETTLEMENT_EDGE_RESULT_UNCERTAIN",
      action: "refresh_status",
      requiresStatusRecovery: true,
    },
  );
}

function buildSavePayload(input) {
  requireRecord(input);
  return {
    student_id: requireUuid(input.studentId, "studentId"),
    settlement_month: requireMonth(input.settlementMonth),
    source_treatment_mode: requireText(input.sourceTreatmentMode, "sourceTreatmentMode"),
    settlement_exchange_rate: optionalDecimal(input.settlementExchangeRate, "settlementExchangeRate"),
    settlement_exchange_rate_source: optionalText(input.settlementExchangeRateSource),
    settlement_exchange_rate_effective_date: optionalText(input.settlementExchangeRateEffectiveDate),
    adjustment_mode: requireText(input.adjustmentMode, "adjustmentMode"),
    manual_adjustment_amount_cny: optionalDecimal(input.manualAdjustmentAmountCny, "manualAdjustmentAmountCny"),
    reason: requireText(input.reason, "reason"),
    note: optionalText(input.note),
    expected_preview_manifest_sha256: requireSha256(input.expectedPreviewManifestSha256, "expectedPreviewManifestSha256"),
    expected_lesson_variance_manifest_sha256: requireSha256(input.expectedLessonVarianceManifestSha256, "expectedLessonVarianceManifestSha256"),
    expected_source_count: requireNonnegativeInteger(input.expectedSourceCount, "expectedSourceCount"),
    expected_unused_planned_credit_jpy: requireDecimal(input.expectedUnusedPlannedCreditJpy, "expectedUnusedPlannedCreditJpy"),
    expected_overage_charge_jpy: requireDecimal(input.expectedOverageChargeJpy, "expectedOverageChargeJpy"),
    expected_net_lesson_variance_jpy: requireDecimal(input.expectedNetLessonVarianceJpy, "expectedNetLessonVarianceJpy"),
    expected_net_lesson_variance_cny: requireDecimal(input.expectedNetLessonVarianceCny, "expectedNetLessonVarianceCny"),
    expected_system_difference_cny: requireDecimal(input.expectedSystemDifferenceCny, "expectedSystemDifferenceCny"),
    expected_final_carryover_cny: requireDecimal(input.expectedFinalCarryoverCny, "expectedFinalCarryoverCny"),
    expected_source_treatment_draft_id: optionalUuid(input.expectedSourceTreatmentDraftId, "expectedSourceTreatmentDraftId"),
    expected_source_treatment_draft_updated_at: optionalText(input.expectedSourceTreatmentDraftUpdatedAt),
    expected_adjustment_draft_id: optionalUuid(input.expectedAdjustmentDraftId, "expectedAdjustmentDraftId"),
    expected_adjustment_draft_updated_at: optionalText(input.expectedAdjustmentDraftUpdatedAt),
    client_correlation_id: optionalUuid(input.clientCorrelationId, "clientCorrelationId"),
  };
}

function buildLockPayload(input) {
  requireRecord(input);
  if (input.confirmLock !== true) {
    throw new Error("confirmLock must be true");
  }
  return {
    student_id: requireUuid(input.studentId, "studentId"),
    settlement_month: requireMonth(input.settlementMonth),
    expected_source_treatment_draft_id: requireUuid(input.expectedSourceTreatmentDraftId, "expectedSourceTreatmentDraftId"),
    expected_source_treatment_draft_updated_at: requireText(input.expectedSourceTreatmentDraftUpdatedAt, "expectedSourceTreatmentDraftUpdatedAt"),
    expected_adjustment_draft_id: requireUuid(input.expectedAdjustmentDraftId, "expectedAdjustmentDraftId"),
    expected_adjustment_draft_updated_at: requireText(input.expectedAdjustmentDraftUpdatedAt, "expectedAdjustmentDraftUpdatedAt"),
    expected_preview_manifest_sha256: requireSha256(input.expectedPreviewManifestSha256, "expectedPreviewManifestSha256"),
    expected_lesson_variance_manifest_sha256: requireSha256(input.expectedLessonVarianceManifestSha256, "expectedLessonVarianceManifestSha256"),
    expected_source_count: requireNonnegativeInteger(input.expectedSourceCount, "expectedSourceCount"),
    expected_unused_planned_credit_jpy: requireDecimal(input.expectedUnusedPlannedCreditJpy, "expectedUnusedPlannedCreditJpy"),
    expected_overage_charge_jpy: requireDecimal(input.expectedOverageChargeJpy, "expectedOverageChargeJpy"),
    expected_net_lesson_variance_jpy: requireDecimal(input.expectedNetLessonVarianceJpy, "expectedNetLessonVarianceJpy"),
    expected_net_lesson_variance_cny: requireDecimal(input.expectedNetLessonVarianceCny, "expectedNetLessonVarianceCny"),
    expected_system_difference_cny: requireDecimal(input.expectedSystemDifferenceCny, "expectedSystemDifferenceCny"),
    expected_final_carryover_cny: requireDecimal(input.expectedFinalCarryoverCny, "expectedFinalCarryoverCny"),
    note: optionalText(input.note),
    confirm_lock: true,
    client_correlation_id: optionalUuid(input.clientCorrelationId, "clientCorrelationId"),
  };
}

function requireRecord(value) {
  if (!isRecord(value)) throw new Error("input must be an object");
}

function requireMonth(value) {
  const text = String(value || "").trim();
  if (!/^[0-9]{4}-(0[1-9]|1[0-2])$/.test(text)) {
    throw new Error("settlementMonth must be YYYY-MM");
  }
  return text;
}

function requireText(value, fieldName) {
  const text = typeof value === "string" ? value.trim() : "";
  if (!text) throw new Error(`${fieldName} is required`);
  return text;
}

function optionalText(value) {
  return value === null || value === undefined ? null : String(value);
}

function requireDecimal(value, fieldName) {
  if (typeof value !== "string" || !DECIMAL_RE.test(value)) {
    throw new Error(`${fieldName} must be a decimal string`);
  }
  return value;
}

function optionalDecimal(value, fieldName) {
  if (value === null || value === undefined) return null;
  return requireDecimal(value, fieldName);
}

function requireSha256(value, fieldName) {
  if (typeof value !== "string" || !SHA256_RE.test(value)) {
    throw new Error(`${fieldName} must be a SHA-256 hex string`);
  }
  return value.toLowerCase();
}

function requireNonnegativeInteger(value, fieldName) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${fieldName} must be a nonnegative integer`);
  }
  return value;
}

function optionalUuid(value, fieldName) {
  if (value === null || value === undefined) return null;
  return requireUuid(value, fieldName);
}

function requireTimeout(value) {
  if (!Number.isSafeInteger(value) || value < 1_000 || value > 60_000) {
    throw new Error("timeoutMs must be an integer between 1000 and 60000");
  }
  return value;
}

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function safeText(value) {
  return typeof value === "string" ? value.slice(0, 500) : "";
}
