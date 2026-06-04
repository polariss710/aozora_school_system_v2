import { supabase } from "../supabase-client.js";

const INCOME_DETAIL_COLUMNS = [
  "id",
  "business_entity_id",
  "student_id",
  "student_payment_id",
  "account_id",
  "income_date",
  "year_month",
  "settlement_month",
  "income_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "exchange_rate",
  "payment_currency",
  "payment_method",
  "status",
  "reversed_at",
  "reversal_reason",
  "reversal_account_transaction_id",
  "is_taxable_income",
  "tax_category",
  "receipt_status",
  "include_in_student_settlement",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const STUDENT_COLUMNS = [
  "id",
  "student_code",
  "name",
  "display_name",
  "status",
  "course_track",
  "target_type",
  "default_currency",
  "business_entity_id",
  "app_type",
].join(",");

const BUSINESS_ENTITY_COLUMNS = [
  "id",
  "code",
  "name",
  "entity_type",
  "default_currency",
  "is_active",
].join(",");

const ACCOUNT_COLUMNS = [
  "id",
  "account_code",
  "name",
  "account_type",
  "currency",
  "business_entity_id",
  "is_active",
  "app_type",
].join(",");

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
  "created_at",
  "updated_at",
].join(",");

const ACCOUNT_TRANSACTION_COLUMNS = [
  "id",
  "account_id",
  "business_entity_id",
  "transaction_date",
  "year_month",
  "transaction_type",
  "related_table",
  "related_id",
  "currency",
  "amount",
  "balance_after",
  "description",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

export async function fetchIncomeDetailPage(incomeId) {
  const income = await fetchIncomeDetail(incomeId);

  const [lookups, settlements, transactions] = await Promise.all([
    fetchIncomeDetailLookups(),
    fetchSettlementReferences(income),
    fetchAccountTransactions(income.id),
  ]);

  return {
    income,
    lookups,
    settlements,
    transactions,
  };
}

export async function reverseIncomeRecord(payload) {
  const { data, error } = await supabase.rpc("school_reverse_income_record", {
    p_income_id: payload.incomeId,
    p_reversal_date: payload.reversalDate,
    p_reason: payload.reason || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("收入撤销失败。");
  }

  return result;
}

async function fetchIncomeDetail(incomeId) {
  const { data, error } = await supabase
    .from("school_income_records")
    .select(INCOME_DETAIL_COLUMNS)
    .eq("app_type", "school")
    .eq("id", incomeId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的收入记录。");
  }

  return data;
}

async function fetchIncomeDetailLookups() {
  const [studentsResult, businessEntitiesResult, accountsResult] = await Promise.all([
    supabase
      .from("school_students")
      .select(STUDENT_COLUMNS)
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_business_entities")
      .select(BUSINESS_ENTITY_COLUMNS)
      .order("name", { ascending: true }),
    supabase
      .from("school_accounts")
      .select(ACCOUNT_COLUMNS)
      .eq("app_type", "school")
      .order("currency", { ascending: true })
      .order("name", { ascending: true }),
  ]);

  if (studentsResult.error) throw studentsResult.error;
  if (businessEntitiesResult.error) throw businessEntitiesResult.error;
  if (accountsResult.error) throw accountsResult.error;

  return {
    students: studentsResult.data || [],
    businessEntities: businessEntitiesResult.data || [],
    accounts: accountsResult.data || [],
  };
}

async function fetchSettlementReferences(income) {
  if (
    income.include_in_student_settlement !== true ||
    !income.student_id ||
    !income.settlement_month ||
    !income.business_entity_id
  ) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select(SETTLEMENT_COLUMNS)
    .eq("student_id", income.student_id)
    .eq("year_month", income.settlement_month)
    .eq("business_entity_id", income.business_entity_id)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchAccountTransactions(incomeId) {
  const { data, error } = await supabase
    .from("school_account_transactions")
    .select(ACCOUNT_TRANSACTION_COLUMNS)
    .eq("app_type", "school")
    .eq("related_table", "school_income_records")
    .eq("related_id", incomeId)
    .order("transaction_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}
