import { supabase } from "../supabase-client.js";

const WAGE_LOCK_COLUMNS = [
  "id",
  "settlement_month",
  "teacher_id",
  "teacher_name",
  "business_entity_id",
  "business_name",
  "settlement_type",
  "exchange_rate",
  "total_minutes",
  "pay_hours",
  "lesson_wage_jpy",
  "lesson_wage_cny",
  "fee_jpy",
  "total_jpy",
  "total_cny",
  "lesson_count",
  "status",
  "locked_at",
  "voided_at",
  "void_reason",
  "voided_by",
  "void_source",
  "created_at",
  "updated_at",
].join(",");

const WAGE_DETAIL_COLUMNS = [
  "id",
  "lock_id",
  "lesson_record_id",
  "lesson_date",
  "start_time",
  "end_time",
  "student_id",
  "student_name",
  "subject_id",
  "subject_name",
  "business_entity_id",
  "business_name",
  "pay_hours",
  "lesson_wage_jpy",
  "lesson_wage_cny",
  "transport_fee_jpy",
  "classroom_fee_jpy",
  "total_jpy",
  "total_cny",
  "settlement_type",
  "exchange_rate",
  "is_no_wage",
  "status",
  "lesson_content",
  "created_at",
].join(",");

const PAYMENT_REQUEST_COLUMNS = [
  "id",
  "status",
  "source_type",
  "source_id",
  "request_month",
  "payee_name",
  "amount",
  "currency",
  "paid_at",
  "paid_expense_id",
  "paid_account_transaction_id",
  "account_id",
  "reversed_at",
  "reversal_transaction_id",
  "reversal_reason",
  "reissued_from_payment_request_id",
  "replacement_payment_request_id",
  "reissue_reason",
  "reissued_at",
  "created_at",
  "updated_at",
].join(",");

const EXPENSE_RECORD_COLUMNS = [
  "id",
  "status",
  "cancelled_at",
  "cancelled_reason",
  "cancelled_by",
  "expense_category",
  "source_type",
  "source_id",
  "teacher_id",
  "payee_name_snapshot",
  "business_entity_id",
  "year_month",
  "expense_date",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "cash_request_id",
  "cash_request_status",
  "cash_transaction_id",
  "cash_requested_at",
  "cash_synced_at",
  "cash_error_message",
  "created_at",
  "updated_at",
].join(",");

const WAGE_DETAIL_ADJUSTMENT_COLUMNS = [
  "id",
  "wage_lock_id",
  "wage_detail_id",
  "reason",
  "old_pay_hours",
  "new_pay_hours",
  "old_lesson_wage_jpy",
  "new_lesson_wage_jpy",
  "old_lesson_wage_cny",
  "new_lesson_wage_cny",
  "old_transport_fee_jpy",
  "new_transport_fee_jpy",
  "old_classroom_fee_jpy",
  "new_classroom_fee_jpy",
  "old_total_jpy",
  "new_total_jpy",
  "old_total_cny",
  "new_total_cny",
  "old_lock_pay_hours",
  "new_lock_pay_hours",
  "old_lock_lesson_wage_jpy",
  "new_lock_lesson_wage_jpy",
  "old_lock_lesson_wage_cny",
  "new_lock_lesson_wage_cny",
  "old_lock_fee_jpy",
  "new_lock_fee_jpy",
  "old_lock_total_jpy",
  "new_lock_total_jpy",
  "old_lock_total_cny",
  "new_lock_total_cny",
  "created_at",
].join(",");

export async function fetchWageDetailPage(wageLockId) {
  const wageLock = await fetchWageLock(wageLockId);

  const [details, paymentRequests, expenseRecords, adjustments] = await Promise.all([
    fetchWageLockDetails(wageLock.id),
    fetchPaymentRequests(wageLock.id),
    fetchTeacherWageExpenseRecords(wageLock.id),
    fetchWageDetailAdjustments(wageLock.id),
  ]);

  return {
    wageLock,
    details,
    paymentRequests,
    expenseRecords,
    adjustments,
  };
}

export async function createTeacherWageExpenseRecord({
  wageLockId,
  note = null,
}) {
  const { data, error } = await supabase.rpc("school_create_teacher_wage_expense_record", {
    p_wage_lock_id: wageLockId,
    p_note: note || null,
  });

  if (error) {
    throw error;
  }

  return data?.[0] || null;
}

export async function adjustTeacherWageDetail({
  wageDetailId,
  payHours,
  transportFeeJpy,
  classroomFeeJpy,
  reason,
}) {
  const { data, error } = await supabase.rpc("school_adjust_teacher_wage_detail", {
    p_wage_detail_id: wageDetailId,
    p_pay_hours: payHours,
    p_transport_fee_jpy: transportFeeJpy,
    p_classroom_fee_jpy: classroomFeeJpy,
    p_reason: reason,
  });

  if (error) {
    throw error;
  }

  return data?.[0] || null;
}

export async function voidTeacherWageLock({
  wageLockId,
  reason,
  operator = "v2_wage_detail",
  source = "v2_wage_detail",
}) {
  const { data, error } = await supabase.rpc("school_void_teacher_wage_lock", {
    p_wage_lock_id: wageLockId,
    p_reason: reason,
    p_operator: operator,
    p_source: source,
  });

  if (error) {
    throw error;
  }

  return data?.[0] || null;
}

async function fetchWageLock(wageLockId) {
  const { data, error } = await supabase
    .from("school_teacher_wage_locks")
    .select(WAGE_LOCK_COLUMNS)
    .eq("id", wageLockId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的老师工资锁定记录。");
  }

  return data;
}

async function fetchWageLockDetails(wageLockId) {
  const { data, error } = await supabase
    .from("school_teacher_wage_lock_details")
    .select(WAGE_DETAIL_COLUMNS)
    .eq("lock_id", wageLockId)
    .order("lesson_date", { ascending: true })
    .order("start_time", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchPaymentRequests(wageLockId) {
  const { data, error } = await supabase
    .from("school_payment_requests")
    .select(PAYMENT_REQUEST_COLUMNS)
    .eq("source_type", "teacher_wage")
    .eq("source_id", wageLockId)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchTeacherWageExpenseRecords(wageLockId) {
  const { data, error } = await supabase
    .from("school_expense_records")
    .select(EXPENSE_RECORD_COLUMNS)
    .eq("app_type", "school")
    .eq("source_type", "teacher_wage")
    .eq("source_id", wageLockId)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchWageDetailAdjustments(wageLockId) {
  const { data, error } = await supabase
    .from("school_teacher_wage_detail_adjustments")
    .select(WAGE_DETAIL_ADJUSTMENT_COLUMNS)
    .eq("wage_lock_id", wageLockId)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}
