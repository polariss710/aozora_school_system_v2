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

export async function fetchStudentSettlements(yearMonth) {
  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select(SETTLEMENT_COLUMNS)
    .eq("year_month", yearMonth);

  if (error) {
    throw error;
  }

  return data || [];
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
