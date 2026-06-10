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

export async function fetchWageDetailPage(wageLockId) {
  const wageLock = await fetchWageLock(wageLockId);

  const [details, paymentRequests] = await Promise.all([
    fetchWageLockDetails(wageLock.id),
    fetchPaymentRequests(wageLock.id),
  ]);

  return {
    wageLock,
    details,
    paymentRequests,
  };
}

export async function createTeacherWagePaymentRequest({
  wageLockId,
  dueDate = null,
  note = null,
}) {
  const { data, error } = await supabase.rpc("school_create_teacher_wage_payment_request", {
    p_wage_lock_id: wageLockId,
    p_due_date: dueDate || null,
    p_note: note || null,
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
