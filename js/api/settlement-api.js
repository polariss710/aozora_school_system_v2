import { supabase } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";
import { getStudentSettlementOnlineStatus } from "./student-settlement-online-api.js?v=student-settlement-tokyo-month-close-20260810-3";

const SETTLEMENT_COLUMNS = [
  "id",
  "student_id",
  "year_month",
  "business_entity_id",
  "preset_exchange_rate",
  "source_treatment_mode",
  "settlement_exchange_rate",
  "settlement_exchange_rate_source",
  "settlement_exchange_rate_effective_date",
  "lesson_variance_calculation_version",
  "unused_planned_credit_jpy",
  "unused_planned_credit_cny",
  "pending_makeup_hours",
  "lesson_variance_display_hours",
  "net_lesson_variance_jpy",
  "net_lesson_variance_cny",
  "lesson_variance_source_count",
  "lesson_variance_manifest_sha256",
  "planned_lesson_fee_jpy",
  "planned_lesson_fee_cny",
  "actual_lesson_fee_jpy",
  "actual_lesson_fee_cny",
  "previous_balance_cny",
  "received_jpy",
  "received_cny",
  "received_equivalent_cny",
  "system_difference_cny",
  "adjustment_amount_cny",
  "adjustment_reason",
  "carryover_amount_cny",
  "duration_overage_minutes",
  "duration_overage_fee_jpy",
  "duration_overage_fee_cny",
  "duration_overage_actual_count",
  "duration_overage_policy_version",
  "duration_overage_source",
  "settlement_status",
  "locked_at",
  "unlocked_at",
  "unlock_reason",
  "note",
].join(",");

const PREVIEW_LESSON_COLUMNS = [
  "student_id",
  "business_entity_id",
  "lesson_type",
  "voided_at",
  "app_type",
].join(",");

const PREVIEW_INCOME_COLUMNS = [
  "student_id",
  "business_entity_id",
  "year_month",
  "settlement_month",
  "income_category",
  "status",
  "include_in_student_settlement",
  "app_type",
].join(",");

export async function fetchStudentSettlements(yearMonth, selectedStudentId = null) {
  const [snapshots, candidates, wageBlockers] = await Promise.all([
    fetchStudentSettlementSnapshots(yearMonth),
    fetchStudentSettlementPreviewCandidates(yearMonth),
    fetchStudentSettlementWageBlockers(yearMonth),
  ]);
  const previewRows = await fetchStudentSettlementPreviewRows(yearMonth, snapshots, candidates);
  const blockerMap = new Map(wageBlockers.map((row) => [settlementStudentKey(row.student_id, row.year_month), row]));
  const rows = [...snapshots.map(normalizeSnapshotRow), ...previewRows]
    .map((row) => mergeWageBlocker(row, blockerMap));
  const rowsWithStatuses = await attachOnlineStatuses(rows);
  if (!selectedStudentId || rowsWithStatuses.some((row) => (
    row.student_id === selectedStudentId && row.year_month === yearMonth
  ))) {
    return rowsWithStatuses;
  }
  const status = await getStudentSettlementOnlineStatus(selectedStudentId, yearMonth);
  return [...rowsWithStatuses, mapOnlineStatusOnlyRow(selectedStudentId, yearMonth, status)];
}

function mapOnlineStatusOnlyRow(studentId, yearMonth, status) {
  return mergeOnlineStatus({
    id: `online-status:${studentId}:${yearMonth}`,
    student_id: studentId,
    year_month: yearMonth,
    business_entity_id: status?.business_entity_id || null,
    is_preview: true,
  }, status);
}

async function attachOnlineStatuses(rows, concurrency = 4) {
  const results = new Array(rows.length);
  let nextIndex = 0;
  const workers = Array.from({ length: Math.min(concurrency, rows.length) }, async () => {
    while (nextIndex < rows.length) {
      const index = nextIndex;
      nextIndex += 1;
      const row = rows[index];
      try {
        const status = await getStudentSettlementOnlineStatus(row.student_id, row.year_month);
        results[index] = mergeOnlineStatus(row, status);
      } catch (error) {
        results[index] = {
          ...row,
          online_status: null,
          online_status_error: safeOnlineStatusError(error),
        };
      }
    }
  });
  await Promise.all(workers);
  return results;
}

function mergeOnlineStatus(row, status) {
  const physical = status?.physical_settlement || {};
  const effective = status?.effective_state || {};
  return {
    ...row,
    business_entity_id: status?.business_entity_id || row.business_entity_id,
    effective_status: effective.effective_status || row.effective_status,
    physical_status: physical.settlement_status || row.physical_status,
    immutable_error_code: status?.save_blocker_code
      || status?.immutable_blocker?.code || row.immutable_error_code,
    immutable_reason: status?.save_blocker_message
      || status?.immutable_blocker?.detail || row.immutable_reason,
    online_status: status,
    online_status_error: null,
  };
}

function safeOnlineStatusError(error) {
  return {
    code: typeof error?.code === "string" ? error.code.slice(0, 100) : "SETTLEMENT_STATUS_UNAVAILABLE",
    message: "暂时无法读取DB权威在线状态，本条保持只读。",
  };
}

async function fetchStudentSettlementSnapshots(yearMonth) {
  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select(SETTLEMENT_COLUMNS)
    .eq("year_month", yearMonth);

  if (error) {
    throw error;
  }

  const rowsWithEffectiveState = await mergeSettlementEffectiveStates(data || []);
  return mergeUnlockedSnapshotPreviews(rowsWithEffectiveState);
}

async function mergeSettlementEffectiveStates(rows) {
  const ids = rows.map((row) => row.id).filter(Boolean);
  if (!ids.length) {
    return rows;
  }
  const { data, error } = await supabase.rpc(
    "school_get_student_monthly_settlement_effective_states",
    { p_settlement_ids: ids }
  );
  if (error) {
    throw error;
  }
  const byId = new Map((data || []).map((state) => [state.settlement_id, state]));
  return rows.map((row) => ({
    ...row,
    ...(byId.get(row.id) || {}),
  }));
}

async function fetchStudentSettlementPreviewCandidates(yearMonth) {
  const [lessonCandidates, incomeCandidates] = await Promise.all([
    fetchLessonPreviewCandidates(yearMonth),
    fetchIncomePreviewCandidates(yearMonth),
  ]);
  const byKey = new Map();
  [...lessonCandidates, ...incomeCandidates].forEach((candidate) => {
    if (!candidate.student_id) {
      return;
    }
    const key = settlementStudentKey(candidate.student_id, yearMonth);
    const existing = byKey.get(key);
    byKey.set(key, {
      student_id: candidate.student_id,
      year_month: yearMonth,
      fallback_business_entity_id: existing?.fallback_business_entity_id || candidate.business_entity_id || null,
    });
  });
  return [...byKey.values()];
}

async function fetchLessonPreviewCandidates(yearMonth) {
  const { data, error } = await supabase
    .rpc("school_list_lesson_management_records_authoritative", {
      p_year_month: yearMonth,
      p_week_start: null,
    })
    .select(PREVIEW_LESSON_COLUMNS);

  if (error) {
    throw error;
  }

  return (data || []).filter((row) => !(
    row.lesson_type === "planned" && row.voided_at
  ));
}

async function fetchIncomePreviewCandidates(yearMonth) {
  const { data, error } = await supabase
    .from("school_operational_income_records")
    .select(PREVIEW_INCOME_COLUMNS)
    .eq("app_type", "school")
    .eq("income_category", "tuition")
    .eq("status", "received");

  if (error) {
    throw error;
  }

  return (data || []).filter((row) => (
    (row.settlement_month || row.year_month) === yearMonth
    && row.include_in_student_settlement !== false
  ));
}

async function fetchStudentSettlementPreviewRows(yearMonth, snapshots, candidates) {
  const snapshotKeys = new Set(snapshots.map((row) => settlementStudentKey(row.student_id, row.year_month)));
  const previewCandidates = candidates.filter((candidate) => (
    !snapshotKeys.has(settlementStudentKey(candidate.student_id, yearMonth))
  ));
  const studentBusinessEntities = await fetchStudentDefaultBusinessEntities(
    previewCandidates.map((candidate) => candidate.student_id)
  );
  const summaryCache = new Map();
  const rows = [];

  for (const candidate of previewCandidates) {
    if (!summaryCache.has(candidate.student_id)) {
      summaryCache.set(candidate.student_id, await fetchStudentSettlementPreviewSummary(
        candidate.student_id,
        yearMonth
      ));
    }
    const summary = summaryCache.get(candidate.student_id);
    if (summary) {
      rows.push(mapPreviewSummaryToSettlementRow(
        summary,
        studentBusinessEntities.get(candidate.student_id) || candidate.fallback_business_entity_id
      ));
    }
  }

  return rows;
}

async function fetchStudentDefaultBusinessEntities(studentIds) {
  const ids = [...new Set(studentIds.filter(Boolean))];
  if (!ids.length) {
    return new Map();
  }

  const { data, error } = await supabase
    .from("school_students")
    .select("id,business_entity_id")
    .eq("app_type", "school")
    .in("id", ids);

  if (error) {
    throw error;
  }

  return new Map((data || [])
    .filter((row) => row.id && row.business_entity_id)
    .map((row) => [row.id, row.business_entity_id]));
}

async function fetchStudentSettlementPreviewSummary(studentId, yearMonth) {
  const [settlementPreview, sourcePreview] = await Promise.all([
    fetchRpcSingle("school_get_student_monthly_settlement_preview", {
      p_student_id: studentId,
      p_year_month: yearMonth,
    }),
    fetchStudentSettlementSourceTreatmentPreview({ studentId, yearMonth }),
  ]);
  return settlementPreview ? { ...settlementPreview, ...sourcePreview } : settlementPreview;
}

async function fetchRpcSingle(functionName, args) {
  const { data, error } = await supabase.rpc(functionName, args);
  if (error) throw error;
  return Array.isArray(data) ? data[0] : data;
}

export async function fetchStudentSettlementSourceTreatmentPreview(payload) {
  return fetchRpcSingle("school_preview_student_settlement_source_treatment", {
    p_student_id: payload.studentId,
    p_year_month: payload.yearMonth,
    p_source_treatment_mode: payload.sourceTreatmentMode || null,
    p_settlement_exchange_rate: payload.settlementExchangeRate ?? null,
    p_settlement_exchange_rate_source: payload.settlementExchangeRateSource || null,
    p_settlement_exchange_rate_effective_date: payload.settlementExchangeRateEffectiveDate || null,
  });
}

export async function fetchStudentSettlementAdjustmentDialogPreview(payload) {
  const status = await getStudentSettlementOnlineStatus(payload.studentId, payload.yearMonth);
  return fetchRpcSingle("school_preview_student_settlement_adjustment_dialog", {
    p_student_id: payload.studentId,
    p_business_entity_id: status.business_entity_id,
    p_year_month: payload.yearMonth,
    p_source_treatment_mode: payload.sourceTreatmentMode,
    p_settlement_exchange_rate: payload.settlementExchangeRate ?? null,
    p_settlement_exchange_rate_source: payload.settlementExchangeRateSource || null,
    p_settlement_exchange_rate_effective_date: payload.settlementExchangeRateEffectiveDate || null,
    p_adjustment_mode: payload.adjustmentMode,
    p_explicit_user_amount_cny: payload.explicitUserAmountCny ?? null,
  });
}

// ===========================================================================
// Phase D —— 锁定用权威事实读取
//
// P0 边界是「用户手打的确认金额只是闸门、不进 payload」。本段收紧的是**读取侧**：
//
//   - AUTHORITATIVE_SNAPSHOTS 与 brandAuthoritative 是本模块私有、不导出。
//     在内建对象未被篡改的常规执行环境中，没有导出路径能把自造对象送进这个
//     WeakSet。（这不是绝对的：WeakSet.prototype.add 可被替换以捕获私有集合的
//     引用。能做到这一点的代码已在同一 realm 内执行，另有更直接的手段，因此
//     不为此更换机制——但也不能把它说成不可达。）
//   - 对外只有下面两个读取入口，参数表只含 scope（studentId + yearMonth）。
//     其余 RPC 参数一律在本层从 status 现取，调用方递不进任何值。
//
// 早先的版本把登记入口公开导出（页面层的 freezeAuthoritativeSnapshot），
// 那只是一道检查：先污染对象、再调该函数登记即可绕过。判断标准是
// 「这个约束的入口，调用方能不能自己构造输入」。
//
// ⚠️ 这条标准要对准**整条链**，不是只对准正在改的这一段。2026-08-26 的审查
// 证明本段之下仍有缺口：buildOnlineDraftLockInput 的产出未冻结，且
// lockStudentSettlementOnline 公开接受任意 payload，调用方改一个字段直接调它
// 即可把金额送进 Edge body。P0 因此尚未闭合，详见
// docs/school-v2-settlement-phase-d-p0-boundary-authoritative-source-20260826.md
// 第 7 节。
//
// 特别注意 fetchStudentSettlementAdjustmentDialogPreview 不可用于锁定：
// 它的 payload 含 explicitUserAmountCny，直通 p_explicit_user_amount_cny，
// 调整对话框正是拿 DOM 值走这条路。若用它取权威事实，DOM 值就能经一次 DB
// 往返影响 projected_final_carryover_cny。
// ===========================================================================

const AUTHORITATIVE_SNAPSHOTS = new WeakSet();
const ADJUSTMENT_MODE_MANUAL = "manual_adjustment";

// 只有经本模块读取入口产出的快照会被登记。builder 据此判断可信与否。
// WeakSet 不阻止垃圾回收。
export function isAuthoritativeSnapshot(value) {
  return value !== null && typeof value === "object"
    && AUTHORITATIVE_SNAPSHOTS.has(value);
}

function brandAuthoritative(value) {
  const cloned = typeof structuredClone === "function"
    ? structuredClone(value)
    : JSON.parse(JSON.stringify(value ?? null));
  const frozen = deepFreeze(cloned);
  if (frozen !== null && typeof frozen === "object") {
    AUTHORITATIVE_SNAPSHOTS.add(frozen);
  }
  return frozen;
}

function deepFreeze(value) {
  if (value === null || typeof value !== "object" || Object.isFrozen(value)) return value;
  Object.freeze(value);
  for (const key of Object.keys(value)) deepFreeze(value[key]);
  return value;
}

export async function fetchAuthoritativeLockStatus(studentId, yearMonth) {
  return brandAuthoritative(
    await getStudentSettlementOnlineStatus(studentId, yearMonth),
  );
}

export async function fetchAuthoritativeLockFacts(studentId, yearMonth) {
  const status = await fetchAuthoritativeLockStatus(studentId, yearMonth);
  const source = status?.source_treatment_draft;
  const adjustment = status?.adjustment_draft;
  // 草稿不全时不预读 preview：与页面层原有的「先判 canUseOnlineDraftLock、
  // 再取 preview」同序，不多走一次 DB 往返。
  if (!source?.source_treatment_mode || !adjustment?.adjustment_mode) {
    return { status, preview: null };
  }
  // 直接走 RPC，不经 fetchStudentSettlementAdjustmentDialogPreview——
  // 那条路的 payload 有 explicitUserAmountCny 通道。此处每个参数都从 status
  // 现取，代码路径上没有外部传入的机会。
  const preview = await fetchRpcSingle("school_preview_student_settlement_adjustment_dialog", {
    p_student_id: studentId,
    p_business_entity_id: status.business_entity_id,
    p_year_month: yearMonth,
    p_source_treatment_mode: source.source_treatment_mode,
    p_settlement_exchange_rate: source.settlement_exchange_rate ?? null,
    p_settlement_exchange_rate_source: source.settlement_exchange_rate_source || null,
    p_settlement_exchange_rate_effective_date: source.settlement_exchange_rate_effective_date || null,
    p_adjustment_mode: adjustment.adjustment_mode,
    p_explicit_user_amount_cny: adjustment.adjustment_mode === ADJUSTMENT_MODE_MANUAL
      ? adjustment.adjustment_amount_cny
      : null,
  });
  return { status, preview: brandAuthoritative(preview) };
}

async function fetchStudentSettlementWageBlockers(yearMonth) {
  const { data, error } = await supabase.rpc("school_get_student_monthly_settlement_wage_blockers", {
    p_year_month: yearMonth,
  });

  if (error) {
    throw error;
  }

  return data || [];
}

async function mergeUnlockedSnapshotPreviews(rows) {
  const mergedRows = [];
  for (const row of rows) {
    if (row.settlement_status !== "unlocked" || row.editable === false) {
      mergedRows.push(row);
      continue;
    }

    const summary = await fetchStudentSettlementPreviewSummary(row.student_id, row.year_month);
    if (!summary) {
      mergedRows.push(row);
      continue;
    }

    mergedRows.push({
      ...row,
      business_entity_id: summary.business_entity_id || row.business_entity_id,
      preset_exchange_rate: summary.exchange_rate,
      planned_lesson_fee_jpy: summary.planned_fee_jpy,
      planned_lesson_fee_cny: summary.planned_fee_cny,
      actual_lesson_fee_jpy: summary.actual_fee_jpy,
      actual_lesson_fee_cny: summary.actual_fee_cny,
      previous_balance_cny: summary.carryover_cny,
      received_jpy: summary.received_jpy,
      received_cny: summary.received_cny,
      received_equivalent_cny: summary.received_equivalent_cny,
      system_difference_cny: summary.final_due_cny,
      adjustment_amount_cny: summary.adjustment_amount_cny,
      adjustment_source: summary.adjustment_source,
      adjustment_reason: summary.adjustment_reason,
      adjustment_note: summary.adjustment_note,
      carryover_amount_cny: summary.locked_carryover_cny,
      adjustment_draft_id: summary.draft_id,
      adjustment_draft_status: summary.draft_status,
      adjustment_draft_updated_at: summary.draft_updated_at,
    });
  }
  return mergedRows;
}

function normalizeSnapshotRow(row) {
  return {
    ...row,
    is_preview: false,
  };
}

function mergeWageBlocker(row, blockerMap) {
  const blocker = blockerMap.get(settlementStudentKey(row.student_id, row.year_month));
  if (!blocker) {
    return {
      ...row,
      teacher_wage_blocker_level: "",
      teacher_wage_blocker_reason: "",
      teacher_wage_blocker_counts: null,
    };
  }

  return {
    ...row,
    teacher_wage_blocker_level: blocker.blocker_level || "",
    teacher_wage_blocker_reason: blocker.blocker_reason || "",
    teacher_wage_blocker_counts: {
      activeWageLockCount: blocker.active_wage_lock_count || 0,
      wageDetailCount: blocker.wage_detail_count || 0,
      paymentRequestCount: blocker.payment_request_count || 0,
      paidPaymentRequestCount: blocker.paid_payment_request_count || 0,
      expenseCount: blocker.expense_count || 0,
      accountTransactionCount: blocker.account_transaction_count || 0,
      businessNames: blocker.wage_business_names || "",
    },
  };
}

function mapPreviewSummaryToSettlementRow(summary, businessEntityId) {
  return {
    id: `preview:${summary.student_id}:${summary.year_month}`,
    student_id: summary.student_id,
    year_month: summary.year_month,
    business_entity_id: summary.business_entity_id || businessEntityId,
    preset_exchange_rate: summary.exchange_rate,
    source_treatment_mode: summary.source_treatment_mode,
    settlement_exchange_rate: summary.settlement_exchange_rate,
    settlement_exchange_rate_source: summary.settlement_exchange_rate_source,
    settlement_exchange_rate_effective_date: summary.settlement_exchange_rate_effective_date,
    lesson_variance_calculation_version: summary.lesson_variance_calculation_version,
    unused_planned_credit_jpy: summary.unused_planned_credit_jpy,
    unused_planned_credit_cny: summary.unused_planned_credit_cny,
    pending_makeup_hours: summary.pending_makeup_hours,
    overage_hours: summary.overage_hours,
    overage_charge_jpy: summary.overage_charge_jpy,
    overage_charge_cny: summary.overage_charge_cny,
    lesson_variance_display_hours: summary.lesson_variance_display_hours,
    net_lesson_variance_jpy: summary.net_lesson_variance_jpy,
    net_lesson_variance_cny: summary.net_lesson_variance_cny,
    lesson_variance_source_count: summary.lesson_variance_source_count,
    lesson_variance_manifest_sha256: summary.lesson_variance_manifest_sha256,
    planned_lesson_fee_jpy: summary.planned_fee_jpy,
    planned_lesson_fee_cny: summary.planned_fee_cny,
    actual_lesson_fee_jpy: summary.actual_fee_jpy,
    actual_lesson_fee_cny: summary.actual_fee_cny,
    previous_balance_cny: summary.carryover_cny,
    received_jpy: summary.received_jpy,
    received_cny: summary.received_cny,
    received_equivalent_cny: summary.received_equivalent_cny,
    system_difference_cny: summary.final_due_cny,
    adjustment_amount_cny: summary.adjustment_amount_cny,
    adjustment_source: summary.adjustment_source,
    adjustment_reason: summary.adjustment_reason,
    adjustment_note: summary.adjustment_note,
    carryover_amount_cny: summary.locked_carryover_cny,
    adjustment_draft_id: summary.draft_id,
    adjustment_draft_status: summary.draft_status,
    adjustment_draft_updated_at: summary.draft_updated_at,
    settlement_status: "preview",
    physical_status: "preview",
    effective_status: "preview",
    editable: true,
    unlockable: false,
    relockable: false,
    locked_at: null,
    unlocked_at: null,
    unlock_reason: "",
    note: "实时预览，未锁定；按学生/月汇总。",
    is_preview: true,
  };
}

function settlementStudentKey(studentId, yearMonth) {
  return `${studentId || ""}::${yearMonth || ""}`;
}

export async function fetchSettlementStudents() {
  const { data, error } = await supabase
    .from("school_students")
    .select("id,name,display_name,student_code")
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}
