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
      .select("id,account_code,name,currency,is_active,app_type")
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
