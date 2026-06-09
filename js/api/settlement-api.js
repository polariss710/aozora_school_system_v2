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
    if (!candidate.student_id || !candidate.business_entity_id) {
      return;
    }
    const key = settlementKey(candidate.student_id, yearMonth, candidate.business_entity_id);
    byKey.set(key, {
      student_id: candidate.student_id,
      year_month: yearMonth,
      business_entity_id: candidate.business_entity_id,
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
  const snapshotKeys = new Set(snapshots.map((row) => (
    settlementKey(row.student_id, row.year_month, row.business_entity_id)
  )));
  const previewCandidates = candidates.filter((candidate) => (
    !snapshotKeys.has(settlementKey(candidate.student_id, yearMonth, candidate.business_entity_id))
  ));
  const ambiguousStudentIds = ambiguousPreviewStudentIds(previewCandidates);
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
        candidate.business_entity_id,
        ambiguousStudentIds.has(candidate.student_id)
      ));
    }
  }

  return rows;
}

function ambiguousPreviewStudentIds(candidates) {
  const businessByStudent = new Map();
  candidates.forEach((candidate) => {
    if (!businessByStudent.has(candidate.student_id)) {
      businessByStudent.set(candidate.student_id, new Set());
    }
    businessByStudent.get(candidate.student_id).add(candidate.business_entity_id);
  });
  return new Set([...businessByStudent.entries()]
    .filter(([, businessIds]) => businessIds.size > 1)
    .map(([studentId]) => studentId));
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

function mapPreviewSummaryToSettlementRow(summary, businessEntityId, isBusinessAmbiguous) {
  return {
    id: `preview:${summary.student_id}:${summary.year_month}:${businessEntityId}`,
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
    note: isBusinessAmbiguous
      ? "实时预览，未锁定；该学生本月存在多个业务归属，当前预览按学生/月汇总。"
      : "实时预览，未锁定；尚未保存为结算快照。",
    is_preview: true,
  };
}

function settlementKey(studentId, yearMonth, businessEntityId) {
  return `${studentId || ""}::${yearMonth || ""}::${businessEntityId || ""}`;
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
