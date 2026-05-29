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

const BUSINESS_ENTITY_SELECT_CANDIDATES = [
  "id,name",
  "id,business_name",
  "id,entity_name",
  "id,label",
];

function toRpcParams(filters) {
  return {
    p_request_month: filters.month || null,
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
  const errors = [];

  for (const columns of BUSINESS_ENTITY_SELECT_CANDIDATES) {
    const { data, error } = await supabase
      .from("school_business_entities")
      .select(columns);

    if (!error) {
      return {
        data: normalizeBusinessEntities(data || []),
        warning: "",
      };
    }

    errors.push(error.message);
  }

  return { data: [], warning: errors.join(" / ") };
}

function normalizeBusinessEntities(rows) {
  return rows
    .map((row) => ({
      id: row.id,
      name: row.name || row.business_name || row.entity_name || row.label || row.id,
    }))
    .sort((a, b) => String(a.name).localeCompare(String(b.name), "zh-CN"));
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
