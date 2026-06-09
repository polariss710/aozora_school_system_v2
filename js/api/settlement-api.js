import { supabase } from "../supabase-client.js";

const SETTLEMENT_COLUMNS = [
  "id",
  "student_id",
  "year_month",
  "business_entity_id",
  "preset_exchange_rate",
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

export async function fetchStudentSettlements(yearMonth) {
  const [snapshots, candidates] = await Promise.all([
    fetchStudentSettlementSnapshots(yearMonth),
    fetchStudentSettlementPreviewCandidates(yearMonth),
  ]);
  const previewRows = await fetchStudentSettlementPreviewRows(yearMonth, snapshots, candidates);
  return [...snapshots.map(normalizeSnapshotRow), ...previewRows];
}

async function fetchStudentSettlementSnapshots(yearMonth) {
  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select(SETTLEMENT_COLUMNS)
    .eq("year_month", yearMonth);

  if (error) {
    throw error;
  }

  return data || [];
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
    .from("school_lesson_records")
    .select(PREVIEW_LESSON_COLUMNS)
    .eq("app_type", "school")
    .eq("year_month", yearMonth);

  if (error) {
    throw error;
  }

  return (data || []).filter((row) => !(
    row.lesson_type === "planned" && row.voided_at
  ));
}

async function fetchIncomePreviewCandidates(yearMonth) {
  const { data, error } = await supabase
    .from("school_income_records")
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
  const { data, error } = await supabase.rpc("school_get_student_monthly_settlement_summary", {
    p_student_id: studentId,
    p_year_month: yearMonth,
  });

  if (error) {
    throw error;
  }

  return Array.isArray(data) ? data[0] : data;
}

function normalizeSnapshotRow(row) {
  return {
    ...row,
    is_preview: false,
  };
}

function mapPreviewSummaryToSettlementRow(summary, businessEntityId) {
  return {
    id: `preview:${summary.student_id}:${summary.year_month}`,
    student_id: summary.student_id,
    year_month: summary.year_month,
    business_entity_id: businessEntityId,
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
    adjustment_amount_cny: 0,
    adjustment_reason: "",
    carryover_amount_cny: summary.locked_carryover_cny,
    settlement_status: "preview",
    locked_at: null,
    unlocked_at: null,
    unlock_reason: "",
    note: "实时预览，未锁定；按学生/月汇总，业务归属显示学生档案默认值。",
    is_preview: true,
  };
}

function settlementStudentKey(studentId, yearMonth) {
  return `${studentId || ""}::${yearMonth || ""}`;
}

export async function fetchSettlementStudents() {
  const { data, error } = await supabase
    .from("school_students")
    .select("id,name,display_name,status,business_entity_id")
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchSettlementBusinessEntities() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function lockStudentMonthlySettlement(payload) {
  const { data, error } = await supabase.rpc("school_lock_student_monthly_settlement", {
    p_student_id: payload.studentId,
    p_year_month: payload.yearMonth,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  return Array.isArray(data) ? data[0] : data;
}

export async function unlockStudentMonthlySettlement(payload) {
  const { data, error } = await supabase.rpc("school_unlock_student_monthly_settlement", {
    p_settlement_id: payload.settlementId,
    p_reason: payload.reason,
  });

  if (error) {
    throw error;
  }

  return Array.isArray(data) ? data[0] : data;
}

export async function relockStudentMonthlySettlement(payload) {
  const { data, error } = await supabase.rpc("school_relock_student_monthly_settlement", {
    p_settlement_id: payload.settlementId,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  return Array.isArray(data) ? data[0] : data;
}
