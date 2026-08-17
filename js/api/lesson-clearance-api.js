import { supabase } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";

export const LESSON_CLEARANCE_READ_RPC_NAMES = Object.freeze({
  pending: "school_list_lesson_clearance_pending_balances_v2",
  overages: "school_list_lesson_clearance_available_overages_v2",
  packages: "school_list_student_package_credit_lots_v2",
  crossMonth: "school_list_cross_month_makeup_projection_v2",
  summary: "school_get_lesson_clearance_dashboard_summary_v1",
  preview: "school_preview_lesson_clearance_v2",
  reversalPreview: "school_preview_lesson_clearance_reversal_v1",
  history: "school_list_lesson_clearance_history_v2",
});

export const LESSON_CLEARANCE_WRITE_RPC_NAMES = Object.freeze({
  create: "school_create_lesson_clearance",
  reverse: "school_reverse_lesson_clearance",
});

async function callReadRpc(name, params = {}) {
  const { data, error } = await supabase.rpc(name, params);
  if (error) throw error;
  return data;
}

async function callWriteRpc(name, params = {}) {
  const { data, error } = await supabase.rpc(name, params);
  if (error) throw error;
  return data;
}

export async function fetchLessonClearancePendingBalances({
  studentId = null,
  includeActiveClaimed = true,
} = {}) {
  return callReadRpc(LESSON_CLEARANCE_READ_RPC_NAMES.pending, {
    p_student_id: studentId || null,
    p_include_active_claimed: Boolean(includeActiveClaimed),
  });
}

export async function fetchLessonClearanceAvailableOverages({
  studentId = null,
  includeActiveClaimed = true,
} = {}) {
  return callReadRpc(LESSON_CLEARANCE_READ_RPC_NAMES.overages, {
    p_student_id: studentId || null,
    p_include_active_claimed: Boolean(includeActiveClaimed),
  });
}

export async function fetchStudentPackageCreditLots({ studentId = null } = {}) {
  return callReadRpc(LESSON_CLEARANCE_READ_RPC_NAMES.packages, {
    p_student_id: studentId || null,
  });
}

export async function fetchCrossMonthMakeupProjection({
  studentId = null,
  yearMonth = null,
} = {}) {
  return callReadRpc(LESSON_CLEARANCE_READ_RPC_NAMES.crossMonth, {
    p_student_id: studentId || null,
    p_year_month: yearMonth || null,
  });
}

export async function fetchLessonClearanceDashboardSummary({ studentId = null } = {}) {
  return callReadRpc(LESSON_CLEARANCE_READ_RPC_NAMES.summary, {
    p_student_id: studentId || null,
  });
}

export async function fetchLessonClearanceHistory({ studentId = null } = {}) {
  return callReadRpc(LESSON_CLEARANCE_READ_RPC_NAMES.history, {
    p_student_id: studentId || null,
  });
}

export async function previewLessonClearance({
  requestIdentity,
  clearanceType = "overtime_offset",
  pendingSourcePlannedId,
  overtimeSourceActualId,
  allocatedMinutes,
  operationDate,
  deviationReasonCode = null,
  deviationReasonNote = null,
  businessNote = null,
  administrativeFinancialTreatment = null,
} = {}) {
  return callReadRpc(LESSON_CLEARANCE_READ_RPC_NAMES.preview, {
    p_request_identity: requestIdentity,
    p_clearance_type: clearanceType,
    p_pending_source_planned_id: pendingSourcePlannedId,
    p_overtime_source_actual_id: overtimeSourceActualId,
    p_allocated_minutes: allocatedMinutes,
    p_operation_date: operationDate,
    p_deviation_reason_code: deviationReasonCode || null,
    p_deviation_reason_note: deviationReasonNote || null,
    p_business_note: businessNote || null,
    p_administrative_financial_treatment: administrativeFinancialTreatment || null,
  });
}

export async function previewLessonClearanceReversal({
  requestIdentity,
  clearanceId,
  reversalDate,
} = {}) {
  return callReadRpc(LESSON_CLEARANCE_READ_RPC_NAMES.reversalPreview, {
    p_request_identity: requestIdentity,
    p_clearance_id: clearanceId,
    p_reversal_date: reversalDate,
  });
}

export async function createLessonClearance({
  clearanceType = "overtime_offset",
  pendingSourcePlannedId,
  overtimeSourceActualId,
  allocatedMinutes,
  operationDate,
  deviationReasonCode = null,
  deviationReasonNote = null,
  businessNote = null,
  administrativeFinancialTreatment = null,
  requestIdentity,
} = {}) {
  return callWriteRpc(LESSON_CLEARANCE_WRITE_RPC_NAMES.create, {
    p_clearance_type: clearanceType,
    p_pending_source_planned_id: pendingSourcePlannedId,
    p_overtime_source_actual_id: overtimeSourceActualId,
    p_allocated_minutes: allocatedMinutes,
    p_operation_date: operationDate,
    p_deviation_reason_code: deviationReasonCode || null,
    p_deviation_note: deviationReasonNote || null,
    p_business_note: businessNote || null,
    p_administrative_financial_treatment: administrativeFinancialTreatment || null,
    p_idempotency_key: requestIdentity,
  });
}

export async function reverseLessonClearance({
  clearanceId,
  reversalDate,
  reason,
  requestIdentity,
} = {}) {
  return callWriteRpc(LESSON_CLEARANCE_WRITE_RPC_NAMES.reverse, {
    p_original_clearance_id: clearanceId,
    p_operation_date: reversalDate,
    p_reason: reason,
    p_idempotency_key: requestIdentity,
  });
}

export const lessonClearanceApi = Object.freeze({
  fetchPendingBalances: fetchLessonClearancePendingBalances,
  fetchAvailableOverages: fetchLessonClearanceAvailableOverages,
  fetchPackageCreditLots: fetchStudentPackageCreditLots,
  fetchCrossMonthProjection: fetchCrossMonthMakeupProjection,
  fetchDashboardSummary: fetchLessonClearanceDashboardSummary,
  fetchHistory: fetchLessonClearanceHistory,
  previewClearance: previewLessonClearance,
  previewReversal: previewLessonClearanceReversal,
  createClearance: createLessonClearance,
  reverseClearance: reverseLessonClearance,
});
