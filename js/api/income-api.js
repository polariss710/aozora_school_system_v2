import { supabase } from "../supabase-client.js";

const INCOME_COLUMNS = [
  "id",
  "business_entity_id",
  "student_id",
  "student_payment_id",
  "account_id",
  "income_date",
  "year_month",
  "settlement_month",
  "income_category",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "exchange_rate",
  "payment_method",
  "status",
  "receipt_status",
  "include_in_student_settlement",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

export async function fetchIncomeRecords(month) {
  const { data, error } = await supabase
    .from("school_income_records")
    .select(INCOME_COLUMNS)
    .eq("app_type", "school")
    .eq("year_month", month)
    .order("income_date", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchIncomeLookups() {
  const [studentsResult, businessEntitiesResult, accountsResult] = await Promise.all([
    supabase
      .from("school_students")
      .select("id,name,display_name,status,business_entity_id")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_business_entities")
      .select("id,name,is_active")
      .order("name", { ascending: true }),
    supabase
      .from("school_accounts")
      .select("id,account_code,name,currency,is_active,app_type")
      .eq("app_type", "school")
      .order("currency", { ascending: true })
      .order("name", { ascending: true }),
  ]);

  if (studentsResult.error) {
    throw studentsResult.error;
  }

  if (businessEntitiesResult.error) {
    throw businessEntitiesResult.error;
  }

  if (accountsResult.error) {
    throw accountsResult.error;
  }

  return {
    students: studentsResult.data || [],
    businessEntities: businessEntitiesResult.data || [],
    accounts: accountsResult.data || [],
  };
}
