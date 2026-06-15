import { supabase } from "../supabase-client.js";

function firstResult(data, fallbackMessage) {
  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error(fallbackMessage);
  }
  return result;
}

export async function fetchPartTimeWorkRecords(filters = {}) {
  const { data, error } = await supabase.rpc("school_list_part_time_work_records", {
    p_year_month: filters.yearMonth || null,
    p_workplace_name: filters.workplaceName || null,
    p_payment_status: filters.paymentStatus || null,
  });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchPartTimeWorkMonthlyStats(filters = {}) {
  const { data, error } = await supabase.rpc("school_get_part_time_work_monthly_stats", {
    p_year_month: filters.yearMonth || null,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "私塾打工月度统计读取失败：RPC 没有返回结果。");
}

export async function createPartTimeWorkRecord(payload) {
  const { data, error } = await supabase.rpc("school_create_part_time_work_record", {
    p_work_date: payload.workDate,
    p_workplace_name: payload.workplaceName,
    p_teacher_name: payload.teacherName || null,
    p_subject_name: payload.subjectName || null,
    p_class_description: payload.classDescription || null,
    p_hours: payload.hours,
    p_hourly_rate_jpy: payload.hourlyRateJpy,
    p_transportation_fee_jpy: payload.transportationFeeJpy,
    p_adjustment_jpy: payload.adjustmentJpy,
    p_payment_status: payload.paymentStatus || "unpaid",
    p_paid_date: payload.paidDate || null,
    p_memo: payload.memo || null,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "私塾打工记录新增失败：RPC 没有返回结果。");
}

export async function updatePartTimeWorkRecord(payload) {
  const { data, error } = await supabase.rpc("school_update_part_time_work_record", {
    p_id: payload.id,
    p_work_date: payload.workDate,
    p_workplace_name: payload.workplaceName,
    p_teacher_name: payload.teacherName || null,
    p_subject_name: payload.subjectName || null,
    p_class_description: payload.classDescription || null,
    p_hours: payload.hours,
    p_hourly_rate_jpy: payload.hourlyRateJpy,
    p_transportation_fee_jpy: payload.transportationFeeJpy,
    p_adjustment_jpy: payload.adjustmentJpy,
    p_payment_status: payload.paymentStatus || "unpaid",
    p_paid_date: payload.paidDate || null,
    p_memo: payload.memo || null,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "私塾打工记录更新失败：RPC 没有返回结果。");
}

export async function deletePartTimeWorkRecord(id) {
  const { data, error } = await supabase.rpc("school_delete_part_time_work_record", {
    p_id: id,
  });

  if (error) {
    throw error;
  }

  return firstResult(data, "私塾打工记录删除失败：RPC 没有返回结果。");
}
