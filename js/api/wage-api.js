import { supabase } from "../supabase-client.js";

const WAGE_LOCK_COLUMNS = [
  "id",
  "teacher_id",
  "teacher_name",
  "settlement_month",
  "business_entity_id",
  "business_name",
  "settlement_type",
  "exchange_rate",
  "lesson_count",
  "total_minutes",
  "pay_hours",
  "fee_jpy",
  "lesson_wage_jpy",
  "lesson_wage_cny",
  "total_jpy",
  "total_cny",
  "status",
  "locked_at",
  "voided_at",
].join(",");

export async function fetchWageLocks(month) {
  const { data, error } = await supabase
    .from("school_teacher_wage_locks")
    .select(WAGE_LOCK_COLUMNS)
    .eq("settlement_month", month);

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageTeachers() {
  const { data, error } = await supabase
    .from("school_teachers")
    .select("id,name,display_name,status,default_business_entity_id")
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageBusinessEntities() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}
