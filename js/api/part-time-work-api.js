import { supabase } from "../supabase-client.js";

const ANNUAL_INCOME_COLUMNS = [
  "id",
  "income_date",
  "year_month",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "status",
  "source_type",
  "source_id",
  "source_label",
  "source_snapshot",
  "created_at",
].join(",");

const ANNUAL_CASH_INCOME_LINKAGE_COLUMNS = [
  "id",
  "income_record_id",
  "sync_status",
  "payment_currency",
  "payment_amount",
  "cash_account_name_snapshot",
  "cash_request_status",
  "cash_transaction_id",
  "synced_at",
  "created_at",
].join(",");

const MIN_PART_TIME_WORK_ANNUAL_YEAR = 2000;
const MAX_PART_TIME_WORK_ANNUAL_YEAR = 2100;

function firstResult(data, fallbackMessage) {
  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error(fallbackMessage);
  }
  return result;
}

export async function fetchPartTimeWorkLessons(filters = {}) {
  const { data, error } = await supabase.rpc("school_list_part_time_work_lessons", {
    p_year_month: filters.yearMonth || null,
    p_workplace_name: filters.workplaceName || null,
    p_record_kind: filters.recordKind || null,
  });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchPartTimeWorkMonthlySettlements(filters = {}) {
  const { data, error } = await supabase.rpc("school_list_part_time_work_monthly_settlements", {
    p_year_month: filters.yearMonth,
  });

  if (error) {
    throw error;
  }

  return data || [];
}

export function partTimeWorkAnnualMonths(year) {
  const numericYear = Number(year);
  if (
    !Number.isInteger(numericYear)
    || numericYear < MIN_PART_TIME_WORK_ANNUAL_YEAR
    || numericYear > MAX_PART_TIME_WORK_ANNUAL_YEAR
  ) {
    return [];
  }

  return [
    `${numericYear - 1}-12`,
    ...Array.from({ length: 11 }, (_, index) => `${numericYear}-${String(index + 1).padStart(2, "0")}`),
  ];
}

export async function fetchPartTimeWorkAnnualSummary(year) {
  const months = partTimeWorkAnnualMonths(year);
  if (!months.length) {
    return { months: [], settlements: [], incomeRecords: [] };
  }

  const [monthlySettlements, incomeRecords] = await Promise.all([
    Promise.all(months.map((yearMonth) => fetchPartTimeWorkMonthlySettlements({ yearMonth }))),
    fetchPartTimeWorkAnnualIncomeRecords(months[0], months[months.length - 1]),
  ]);

  return {
    months,
    settlements: monthlySettlements.flat(),
    incomeRecords,
  };
}

async function fetchPartTimeWorkAnnualIncomeRecords(startMonth, endMonth) {
  const { data, error } = await supabase
    .from("school_income_records")
    .select(ANNUAL_INCOME_COLUMNS)
    .eq("app_type", "school")
    .eq("source_type", "part_time_work")
    .gte("year_month", startMonth)
    .lte("year_month", endMonth)
    .order("year_month", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return mergeAnnualCashIncomeLinkageEvents(data || []);
}

async function mergeAnnualCashIncomeLinkageEvents(records) {
  const incomeIds = records.map((row) => row.id).filter(Boolean);
  if (!incomeIds.length) {
    return records.map((row) => ({ ...row, cashIncomeLinkageEvent: null }));
  }

  const { data, error } = await supabase
    .from("school_personal_cash_income_linkage_events")
    .select(ANNUAL_CASH_INCOME_LINKAGE_COLUMNS)
    .eq("source_table", "school_income_records")
    .in("income_record_id", incomeIds)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  const latestByIncomeId = new Map();
  for (const event of data || []) {
    if (event.income_record_id && !latestByIncomeId.has(event.income_record_id)) {
      latestByIncomeId.set(event.income_record_id, event);
    }
  }

  return records.map((row) => ({
    ...row,
    cashIncomeLinkageEvent: latestByIncomeId.get(row.id) || null,
  }));
}

export async function createPartTimeWorkPlannedLesson(payload) {
  const { data, error } = await supabase.rpc("school_create_part_time_work_planned_lesson", {
    p_work_date: payload.workDate,
    p_start_time: payload.startTime,
    p_end_time: payload.endTime,
    p_workplace_name: payload.workplaceName,
    p_subject_name: payload.subjectName,
    p_class_description: payload.classDescription || null,
    p_hourly_rate_jpy: payload.hourlyRateJpy,
    p_transportation_fee_jpy: payload.transportationFeeJpy,
    p_memo: payload.memo || null,
    p_teacher_name: payload.teacherName || "吴峰",
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "预定打工课时新增失败：RPC 没有返回结果。");
}

export async function updatePartTimeWorkLesson(payload) {
  const { data, error } = await supabase.rpc("school_update_part_time_work_lesson", {
    p_id: payload.id,
    p_work_date: payload.workDate,
    p_start_time: payload.startTime,
    p_end_time: payload.endTime,
    p_workplace_name: payload.workplaceName,
    p_subject_name: payload.subjectName,
    p_class_description: payload.classDescription || null,
    p_hourly_rate_jpy: payload.hourlyRateJpy,
    p_transportation_fee_jpy: payload.transportationFeeJpy,
    p_memo: payload.memo || null,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "打工课时更新失败：RPC 没有返回结果。");
}

export async function generatePartTimeWorkActualFromPlanned(payload) {
  const { data, error } = await supabase.rpc("school_generate_part_time_work_actual_from_planned", {
    p_planned_lesson_id: payload.plannedLessonId,
    p_actual_work_date: payload.workDate || null,
    p_start_time: payload.startTime || null,
    p_end_time: payload.endTime || null,
    p_hourly_rate_jpy: payload.hourlyRateJpy,
    p_transportation_fee_jpy: payload.transportationFeeJpy,
    p_memo: payload.memo || null,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "实际打工课时生成失败：RPC 没有返回结果。");
}

export async function deletePartTimeWorkLesson(id, options = {}) {
  const { data, error } = await supabase.rpc("school_delete_part_time_work_lesson", {
    p_id: id,
    p_confirm_generated_actual: Boolean(options.confirmGeneratedActual),
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "打工课时删除失败：RPC 没有返回结果。");
}

export async function lockPartTimeWorkMonthlySettlement(payload) {
  const { data, error } = await supabase.rpc("school_lock_part_time_work_monthly_settlement", {
    p_year_month: payload.yearMonth,
    p_workplace_name: payload.workplaceName,
    p_adjustment_jpy: payload.adjustmentJpy,
    p_memo: payload.memo || null,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "月度工资结算锁定失败：RPC 没有返回结果。");
}

export async function unlockPartTimeWorkMonthlySettlement(id) {
  const { data, error } = await supabase.rpc("school_unlock_part_time_work_monthly_settlement", {
    p_settlement_id: id,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "月度工资结算撤销锁定失败：RPC 没有返回结果。");
}

export async function createPartTimeWorkIncomeRequest(settlementId) {
  const { data, error } = await supabase.rpc("school_create_part_time_work_income_record", {
    p_settlement_id: settlementId,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "收入记录生成失败：RPC 没有返回结果。");
}

export async function fetchPartTimeWorkSettlementExport(settlementId) {
  const { data, error } = await supabase.rpc("school_get_part_time_work_settlement_export", {
    p_settlement_id: settlementId,
  });

  if (error) {
    throw error;
  }

  return data || [];
}
