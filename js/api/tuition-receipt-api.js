import { supabase } from "../supabase-client.js";
import { requireUuid } from "./validation.js";

const RECEIPT_INCOME_COLUMNS = [
  "id",
  "student_id",
  "income_date",
  "year_month",
  "settlement_month",
  "income_category",
  "description",
  "currency",
  "amount",
  "status",
  "cancelled_at",
  "reversed_at",
  "receipt_status",
  "source_type",
  "source_id",
  "source_label",
  "source_snapshot",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const RECEIPT_STUDENT_COLUMNS = [
  "id",
  "name",
  "display_name",
  "app_type",
].join(",");

const RECEIPT_CASH_LINKAGE_COLUMNS = [
  "id",
  "income_record_id",
  "sync_status",
  "cash_request_status",
  "cash_account_name_snapshot",
  "payment_currency",
  "payment_amount",
  "currency",
  "amount",
  "cash_transaction_id",
  "synced_at",
  "created_at",
].join(",");

export async function fetchTuitionReceiptSource(incomeRecordId) {
  const incomeId = requireUuid(incomeRecordId, "income_record_id");

  const { data: income, error: incomeError } = await supabase
    .from("school_income_records")
    .select(RECEIPT_INCOME_COLUMNS)
    .eq("app_type", "school")
    .eq("id", incomeId)
    .maybeSingle();

  if (incomeError) {
    throw incomeError;
  }

  if (!income) {
    throw new Error("没有找到对应的收入记录。");
  }

  const [studentResult, eventResult] = await Promise.all([
    income.student_id
      ? supabase
          .from("school_students")
          .select(RECEIPT_STUDENT_COLUMNS)
          .eq("app_type", "school")
          .eq("id", income.student_id)
          .maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    supabase
      .from("school_personal_cash_income_linkage_events")
      .select(RECEIPT_CASH_LINKAGE_COLUMNS)
      .eq("income_record_id", incomeId)
      .eq("source_table", "school_income_records")
      .in("source_event_type", ["tuition_income_received", "income_received"])
      .order("created_at", { ascending: false })
      .limit(1),
  ]);

  if (studentResult.error) {
    throw studentResult.error;
  }

  if (eventResult.error) {
    if (eventResult.error.code !== "42P01") {
      throw eventResult.error;
    }
  }

  return {
    income,
    student: studentResult.data || null,
    cashIncomeLinkageEvent: (eventResult.data || [])[0] || null,
  };
}
