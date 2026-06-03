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

export async function createIncomeRecord(payload) {
  const { data, error } = await supabase.rpc("school_create_income_record", {
    p_income_date: payload.incomeDate,
    p_settlement_month: payload.settlementMonth,
    p_business_entity_id: payload.businessEntityId,
    p_student_id: payload.studentId,
    p_account_id: payload.accountId,
    p_amount: payload.amount,
    p_income_category: "tuition",
    p_description: payload.description || null,
    p_currency: payload.currency,
    p_payment_currency: payload.paymentCurrency,
    p_exchange_rate: payload.exchangeRate || null,
    p_payment_method: payload.paymentMethod || null,
    p_is_taxable_income: Boolean(payload.isTaxableIncome),
    p_tax_category: payload.taxCategory || null,
    p_receipt_status: payload.receiptStatus || null,
    p_include_in_student_settlement: true,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("收入新增成功，但 RPC 没有返回结果。");
  }

  return result;
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
      .select("id,account_code,name,currency,business_entity_id,current_balance,is_active,app_type")
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
