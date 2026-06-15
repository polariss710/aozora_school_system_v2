import { supabase } from "../supabase-client.js";

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

export async function savePartTimeWorkMonthlySettlement(payload) {
  const { data, error } = await supabase.rpc("school_save_part_time_work_monthly_settlement", {
    p_year_month: payload.yearMonth,
    p_workplace_name: payload.workplaceName,
    p_hourly_rate_jpy: payload.hourlyRateJpy,
    p_adjustment_jpy: payload.adjustmentJpy,
    p_memo: payload.memo || null,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "月度工资结算保存失败：RPC 没有返回结果。");
}

export async function lockPartTimeWorkMonthlySettlement(id) {
  const { data, error } = await supabase.rpc("school_lock_part_time_work_monthly_settlement", {
    p_settlement_id: id,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "月度工资结算锁定失败：RPC 没有返回结果。");
}

export async function createPartTimeWorkIncomeRequest(settlementId) {
  const { data, error } = await supabase.rpc("school_create_part_time_work_income_request", {
    p_settlement_id: settlementId,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "收入请求生成失败：RPC 没有返回结果。");
}
