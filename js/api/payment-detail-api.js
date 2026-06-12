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
  "account_id",
  "paid_at",
  "paid_expense_id",
  "paid_account_transaction_id",
  "reversed_at",
  "reversal_reason",
  "reversal_transaction_id",
  "reissued_from_payment_request_id",
  "replacement_payment_request_id",
  "reissue_reason",
  "reissued_at",
  "note",
  "created_at",
  "updated_at",
].join(",");

const WAGE_LOCK_COLUMNS = [
  "id",
  "settlement_month",
  "teacher_id",
  "teacher_name",
  "business_entity_id",
  "business_name",
  "settlement_type",
  "exchange_rate",
  "total_minutes",
  "pay_hours",
  "lesson_wage_jpy",
  "lesson_wage_cny",
  "fee_jpy",
  "total_jpy",
  "total_cny",
  "lesson_count",
  "status",
  "locked_at",
  "voided_at",
  "created_at",
  "updated_at",
].join(",");

const EXPENSE_COLUMNS = [
  "id",
  "expense_date",
  "year_month",
  "expense_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "status",
  "account_id",
  "reimbursement_status",
  "created_at",
  "updated_at",
].join(",");

const ACCOUNT_COLUMNS = [
  "id",
  "account_code",
  "name",
  "account_type",
  "currency",
  "business_entity_id",
  "is_company_account",
  "is_active",
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

const CHAIN_PAYMENT_REQUEST_COLUMNS = [
  "id",
  "status",
  "request_month",
  "amount",
  "currency",
  "paid_at",
  "reversed_at",
  "reissued_from_payment_request_id",
  "replacement_payment_request_id",
  "reissue_reason",
  "reissued_at",
  "paid_expense_id",
  "created_at",
  "updated_at",
].join(",");

export async function fetchPaymentDetailPage(paymentRequestId) {
  const paymentRequest = await fetchPaymentRequest(paymentRequestId);

  const [wageLock, expense, accounts, transactions, sourceRequests, cashLinkageEvents] = await Promise.all([
    fetchWageLock(paymentRequest),
    fetchExpense(paymentRequest.paid_expense_id),
    fetchAccounts(),
    fetchAccountTransactions([
      paymentRequest.paid_account_transaction_id,
      paymentRequest.reversal_transaction_id,
    ]),
    fetchSourcePaymentRequests(paymentRequest),
    fetchCashLinkageEvents(paymentRequest.id),
  ]);

  return {
    paymentRequest,
    wageLock,
    expense,
    accounts,
    transactions,
    sourceRequests,
    cashLinkageEvents,
  };
}

async function fetchPaymentRequest(paymentRequestId) {
  const { data, error } = await supabase
    .from("school_payment_requests")
    .select(PAYMENT_REQUEST_COLUMNS)
    .eq("id", paymentRequestId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的老师工资支付请求。");
  }

  return data;
}

async function fetchWageLock(paymentRequest) {
  if (paymentRequest.source_type !== "teacher_wage" || !paymentRequest.source_id) {
    return null;
  }

  const { data, error } = await supabase
    .from("school_teacher_wage_locks")
    .select(WAGE_LOCK_COLUMNS)
    .eq("id", paymentRequest.source_id)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data || null;
}

async function fetchExpense(expenseId) {
  if (!expenseId) {
    return null;
  }

  const { data, error } = await supabase
    .from("school_expense_records")
    .select(EXPENSE_COLUMNS)
    .eq("id", expenseId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data || null;
}

async function fetchAccounts() {
  const { data, error } = await supabase
    .from("school_accounts")
    .select(ACCOUNT_COLUMNS)
    .eq("app_type", "school")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchAccountTransactions(ids) {
  const transactionIds = Array.from(new Set((ids || []).filter(Boolean)));
  if (!transactionIds.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_account_transactions")
    .select(ACCOUNT_TRANSACTION_COLUMNS)
    .eq("app_type", "school")
    .in("id", transactionIds)
    .order("transaction_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchSourcePaymentRequests(paymentRequest) {
  if (!paymentRequest.source_type || !paymentRequest.source_id) {
    return [paymentRequest];
  }

  const { data, error } = await supabase
    .from("school_payment_requests")
    .select(CHAIN_PAYMENT_REQUEST_COLUMNS)
    .eq("source_type", paymentRequest.source_type)
    .eq("source_id", paymentRequest.source_id)
    .order("created_at", { ascending: true })
    .order("updated_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchCashLinkageEvents(paymentRequestId) {
  const { data, error } = await supabase.rpc("school_get_personal_cash_linkage_events", {
    p_payment_request_id: paymentRequestId,
    p_sync_status: null,
  });

  if (error) {
    throw error;
  }

  return data || [];
}
