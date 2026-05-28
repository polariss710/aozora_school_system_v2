import { supabase } from "../supabase-client.js";

const PAYMENT_REQUEST_COLUMNS = [
  "id",
  "year_month",
  "request_month",
  "month",
  "status",
  "source_type",
  "business_entity_id",
  "business_entity_name",
  "target_name",
  "teacher_name",
  "description",
  "memo",
  "currency",
  "amount",
  "created_at",
  "paid_at",
  "reversed_at",
].join(",");

const BUSINESS_ENTITY_COLUMNS = [
  "id",
  "name",
  "display_name",
  "status",
].join(",");

function toRpcParams(filters) {
  // Adjust these names if the deployed RPC uses a different signature.
  return {
    p_year_month: filters.month || null,
    p_status: filters.status || null,
    p_source_type: filters.sourceType || null,
    p_business_entity_id: filters.businessEntityId || null,
    p_currency: filters.currency || null,
  };
}

export async function fetchPaymentSummary(filters) {
  const { data, error } = await supabase.rpc(
    "school_get_payment_management_summary",
    toRpcParams(filters)
  );

  if (error) {
    throw error;
  }

  return data;
}

export async function fetchPaymentRequests(filters) {
  let query = supabase
    .from("school_payment_requests")
    .select(PAYMENT_REQUEST_COLUMNS)
    .order("created_at", { ascending: false });

  query = applyPaymentFilters(query, filters);

  const { data, error } = await query;
  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchBusinessEntities() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select(BUSINESS_ENTITY_COLUMNS)
    .order("name", { ascending: true });

  if (error) {
    return { data: [], warning: error.message };
  }

  return { data: data || [], warning: "" };
}

function applyPaymentFilters(query, filters) {
  if (filters.month) {
    query = query.eq("year_month", filters.month);
  }

  if (filters.status) {
    query = query.eq("status", filters.status);
  } else {
    query = query.neq("status", "void");
  }

  if (filters.sourceType) {
    query = query.eq("source_type", filters.sourceType);
  }

  if (filters.businessEntityId) {
    query = query.eq("business_entity_id", filters.businessEntityId);
  }

  if (filters.currency) {
    query = query.eq("currency", filters.currency);
  }

  return query;
}
