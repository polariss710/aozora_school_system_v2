import { supabase } from "../supabase-client.js";

const PAYMENT_REQUEST_COLUMNS = [
  "id",
  "source_type",
  "source_id",
  "request_month",
  "payee_type",
  "payee_id",
  "payee_name",
  "business_entity_id",
  "business_name",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "status",
  "due_date",
  "paid_at",
  "note",
  "created_at",
  "updated_at",
  "reversed_at",
  "reversal_reason",
].join(",");

const BUSINESS_ENTITY_SELECT_CANDIDATES = [
  "id,name",
  "id,business_name",
  "id,entity_name",
  "id,label",
];

const ACCOUNT_COLUMNS = [
  "id",
  "account_code",
  "name",
  "account_type",
  "currency",
  "business_entity_id",
  "current_balance",
  "is_active",
  "app_type",
].join(",");

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

export async function fetchAccounts() {
  const { data, error } = await supabase
    .from("school_accounts")
    .select(ACCOUNT_COLUMNS)
    .eq("is_active", true)
    .eq("app_type", "school")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function confirmPaymentRequest(payload) {
  const { data, error } = await supabase.rpc("school_confirm_payment_request", {
    p_payment_request_id: payload.paymentRequestId,
    p_account_id: payload.accountId,
    p_pay_date: payload.payDate,
    p_amount: payload.amount,
    p_note: payload.note || null,
    p_payment_method: "bank_transfer",
  });

  if (error) {
    throw error;
  }

  return data;
}

export async function reversePaidPaymentRequest(payload) {
  const { data, error } = await supabase.rpc("school_reverse_paid_payment_request", {
    p_payment_request_id: payload.paymentRequestId,
    p_reason: payload.reason,
    p_reverse_date: payload.reverseDate,
  });

  if (error) {
    throw error;
  }

  return data;
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
    query = query.eq("request_month", filters.month);
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
