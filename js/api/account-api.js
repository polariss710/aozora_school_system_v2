import { supabase } from "../supabase-client.js";

const ACCOUNT_COLUMNS = [
  "id",
  "account_code",
  "name",
  "account_type",
  "currency",
  "business_entity_id",
  "current_balance",
  "is_company_account",
  "is_active",
  "app_type",
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
].join(",");

export async function fetchAccounts() {
  const { data, error } = await supabase
    .from("school_accounts")
    .select(ACCOUNT_COLUMNS)
    .in("app_type", ["school", "store", "family"])
    .order("currency", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchAccountTransactions(filters) {
  let query = supabase
    .from("school_account_transactions")
    .select(ACCOUNT_TRANSACTION_COLUMNS)
    .order("transaction_date", { ascending: false })
    .order("created_at", { ascending: false });

  query = applyAccountTransactionFilters(query, filters);

  const { data, error } = await query;
  if (error) {
    throw error;
  }

  return data || [];
}

export async function createAccountProfile(payload) {
  const { data, error } = await supabase.rpc("school_create_account_profile", {
    p_account_code: null,
    p_name: payload.name,
    p_initial_balance: payload.initialBalance,
    p_account_type: payload.accountType,
    p_currency: payload.currency,
    p_business_entity_id: payload.businessEntityId,
    p_is_company_account: payload.isCompanyAccount,
    p_is_active: payload.isActive,
    p_note: payload.note || null,
    p_app_type: payload.appType || "school",
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("账户新增失败：RPC 没有返回结果。");
  }

  return result;
}

export async function createAccountAdjustment(payload) {
  const { data, error } = await supabase.rpc("school_create_account_adjustment", {
    p_adjustment_date: payload.adjustmentDate,
    p_business_entity_id: payload.businessEntityId,
    p_account_id: payload.accountId,
    p_amount: payload.amount,
    p_reason: payload.reason,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("账户调整失败：RPC 没有返回结果。");
  }

  return result;
}

export async function createAccountTransfer(payload) {
  const { data, error } = await supabase.rpc("school_create_account_transfer", {
    p_transfer_date: payload.transferDate,
    p_business_entity_id: payload.businessEntityId,
    p_from_account_id: payload.fromAccountId,
    p_to_account_id: payload.toAccountId,
    p_amount: payload.amount,
    p_reason: payload.reason,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("账户转账失败：RPC 没有返回结果。");
  }

  return result;
}

export async function updateAccountProfile(payload) {
  const { data, error } = await supabase.rpc("school_update_account_profile", {
    p_account_id: payload.accountId,
    p_name: payload.name,
    p_currency: payload.currency,
    p_account_type: payload.accountType,
    p_business_entity_id: payload.businessEntityId,
    p_is_company_account: payload.isCompanyAccount,
    p_is_active: payload.isActive,
    p_note: payload.note || null,
    p_app_type: payload.appType || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("账户基础信息更新失败：RPC 没有返回结果。");
  }

  return result;
}

export async function fetchBusinessEntitiesForAccounts() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,code,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

function applyAccountTransactionFilters(query, filters) {
  if (filters.appType) {
    query = query.eq("app_type", filters.appType);
  }

  if (filters.month) {
    query = query.eq("year_month", filters.month);
  }

  if (filters.accountId) {
    query = query.eq("account_id", filters.accountId);
  }

  if (filters.businessEntityId) {
    query = query.eq("business_entity_id", filters.businessEntityId);
  }

  if (filters.currency) {
    query = query.eq("currency", filters.currency);
  }

  if (filters.transactionType) {
    query = query.eq("transaction_type", filters.transactionType);
  }

  return query;
}
