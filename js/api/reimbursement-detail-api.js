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
  "reversed_at",
  "reversal_reason",
  "reversal_from_account_transaction_id",
  "reversal_to_account_transaction_id",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const REIMBURSEMENT_ITEM_COLUMNS = [
  "id",
  "reimbursement_id",
  "expense_id",
  "amount",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const EXPENSE_COLUMNS = [
  "id",
  "business_entity_id",
  "teacher_id",
  "student_id",
  "account_id",
  "expense_date",
  "year_month",
  "expense_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "status",
  "receipt_status",
  "reimbursement_status",
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

export async function fetchReimbursementDetailPage(reimbursementId) {
  const reimbursement = await fetchReimbursementDetail(reimbursementId);

  const [lookups, items, transactions] = await Promise.all([
    fetchReimbursementDetailLookups(),
    fetchReimbursementItems(reimbursement.id),
    fetchReimbursementTransactions(reimbursement.id),
  ]);

  const expenses = await fetchExpensesByIds(items.map((item) => item.expense_id));

  return {
    reimbursement,
    lookups,
    items,
    expenses,
    transactions,
  };
}

export async function reverseReimbursementRecord(payload) {
  const { data, error } = await supabase.rpc("school_reverse_reimbursement_record", {
    p_reimbursement_id: payload.reimbursementId,
    p_reversal_date: payload.reversalDate,
    p_reason: payload.reason || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("报销撤销失败。");
  }

  return result;
}

async function fetchReimbursementDetail(reimbursementId) {
  const { data, error } = await supabase
    .from("school_reimbursements")
    .select(REIMBURSEMENT_COLUMNS)
    .eq("app_type", "school")
    .eq("id", reimbursementId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的报销记录。");
  }

  return data;
}

async function fetchReimbursementItems(reimbursementId) {
  const { data, error } = await supabase
    .from("school_reimbursement_items")
    .select(REIMBURSEMENT_ITEM_COLUMNS)
    .eq("app_type", "school")
    .eq("reimbursement_id", reimbursementId)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchExpensesByIds(ids) {
  const expenseIds = Array.from(new Set((ids || []).filter(Boolean)));
  if (!expenseIds.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_expense_records")
    .select(EXPENSE_COLUMNS)
    .eq("app_type", "school")
    .in("id", expenseIds)
    .order("expense_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchReimbursementTransactions(reimbursementId) {
  const { data, error } = await supabase
    .from("school_account_transactions")
    .select(ACCOUNT_TRANSACTION_COLUMNS)
    .eq("app_type", "school")
    .eq("related_table", "school_reimbursements")
    .eq("related_id", reimbursementId)
    .order("transaction_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchReimbursementDetailLookups() {
  const [accountsResult] = await Promise.all([
    supabase
      .from("school_accounts")
      .select("id,account_code,name,account_type,currency,business_entity_id,current_balance,is_company_account,is_active,app_type")
      .eq("app_type", "school")
      .order("currency", { ascending: true })
      .order("name", { ascending: true }),
  ]);

  if (accountsResult.error) {
    throw accountsResult.error;
  }

  return {
    accounts: accountsResult.data || [],
  };
}
