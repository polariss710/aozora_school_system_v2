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
    .eq("app_type", "school")
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
    .eq("app_type", "school")
    .order("transaction_date", { ascending: false })
    .order("created_at", { ascending: false });

  query = applyAccountTransactionFilters(query, filters);

  const { data, error } = await query;
  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchBusinessEntitiesForAccounts() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,name")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

function applyAccountTransactionFilters(query, filters) {
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
