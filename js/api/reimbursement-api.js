import { supabase } from "../supabase-client.js";

const REIMBURSEMENT_COLUMNS = [
  "id",
  "reimbursement_date",
  "year_month",
  "business_entity_id",
  "from_account_id",
  "to_account_id",
  "amount",
  "currency",
  "status",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const REIMBURSEMENT_CANDIDATE_EXPENSE_COLUMNS = [
  "id",
  "expense_date",
  "year_month",
  "business_entity_id",
  "account_id",
  "expense_category",
  "description",
  "currency",
  "amount",
  "status",
  "reimbursement_status",
  "receipt_status",
  "note",
  "app_type",
  "created_at",
].join(",");

export async function fetchReimbursementRecords(month) {
  const { data, error } = await supabase
    .from("school_reimbursements")
    .select(REIMBURSEMENT_COLUMNS)
    .eq("app_type", "school")
    .eq("year_month", month)
    .order("reimbursement_date", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchReimbursementLookups() {
  const [businessEntitiesResult, accountsResult] = await Promise.all([
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

  if (businessEntitiesResult.error) {
    throw businessEntitiesResult.error;
  }

  if (accountsResult.error) {
    throw accountsResult.error;
  }

  return {
    businessEntities: businessEntitiesResult.data || [],
    accounts: accountsResult.data || [],
  };
}

export async function fetchReimbursementCandidateExpenses(filters = {}) {
  let query = supabase
    .from("school_expense_records")
    .select(REIMBURSEMENT_CANDIDATE_EXPENSE_COLUMNS)
    .eq("app_type", "school")
    .eq("status", "paid")
    .eq("reimbursement_status", "pending")
    .neq("expense_category", "teacher_wage")
    .order("expense_date", { ascending: false })
    .order("created_at", { ascending: false });

  if (filters.month) {
    query = query.eq("year_month", filters.month);
  }

  if (filters.businessEntityId) {
    query = query.eq("business_entity_id", filters.businessEntityId);
  }

  if (filters.currency) {
    query = query.eq("currency", filters.currency);
  }

  const { data, error } = await query;
  if (error) {
    throw error;
  }

  return data || [];
}

export async function createReimbursementRecord(payload) {
  const { data, error } = await supabase.rpc("school_create_reimbursement_record", {
    p_reimbursement_date: payload.reimbursementDate,
    p_business_entity_id: payload.businessEntityId,
    p_from_account_id: payload.fromAccountId,
    p_to_account_id: payload.toAccountId,
    p_expense_ids: payload.expenseIds,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("报销确认失败。");
  }

  return result;
}

export async function fetchReimbursementItemCounts(reimbursementIds) {
  if (!reimbursementIds.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_reimbursement_items")
    .select("reimbursement_id")
    .eq("app_type", "school")
    .in("reimbursement_id", reimbursementIds);

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchReimbursementTransactionCounts(reimbursementIds) {
  if (!reimbursementIds.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_account_transactions")
    .select("related_id")
    .eq("app_type", "school")
    .eq("related_table", "school_reimbursements")
    .in("related_id", reimbursementIds);

  if (error) {
    throw error;
  }

  return data || [];
}
