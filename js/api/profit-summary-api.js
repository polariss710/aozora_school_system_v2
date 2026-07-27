import { supabase } from "../supabase-client.js";

const INCOME_COLUMNS = [
  "id",
  "business_entity_id",
  "income_date",
  "year_month",
  "income_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "status",
  "note",
  "app_type",
  "created_at",
].join(",");

const EXPENSE_COLUMNS = [
  "id",
  "business_entity_id",
  "expense_date",
  "year_month",
  "expense_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "status",
  "reimbursement_status",
  "note",
  "app_type",
  "created_at",
].join(",");

const REIMBURSEMENT_COLUMNS = [
  "id",
  "business_entity_id",
  "year_month",
  "currency",
  "amount",
  "status",
  "app_type",
  "created_at",
].join(",");

const PAYMENT_REQUEST_COLUMNS = [
  "id",
  "business_entity_id",
  "request_month",
  "source_type",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "status",
  "paid_at",
  "reversed_at",
  "created_at",
].join(",");

const ACCOUNT_TRANSACTION_COLUMNS = [
  "id",
  "business_entity_id",
  "transaction_date",
  "year_month",
  "transaction_type",
  "related_table",
  "related_id",
  "currency",
  "amount",
  "app_type",
  "created_at",
].join(",");

const BUSINESS_ENTITY_COLUMNS = [
  "id",
  "code",
  "name",
  "is_active",
].join(",");

export async function fetchProfitSummaryPageData(filters) {
  const [
    businessEntitiesResult,
    incomeResult,
    expenseResult,
    reimbursementResult,
    paymentRequestResult,
    accountTransactionResult,
  ] = await Promise.all([
    supabase
      .from("school_business_entities")
      .select(BUSINESS_ENTITY_COLUMNS)
      .order("name", { ascending: true }),
    buildMonthEntityQuery("school_operational_income_records", INCOME_COLUMNS, "year_month", filters)
      .order("income_date", { ascending: false })
      .order("created_at", { ascending: false }),
    buildMonthEntityQuery("school_expense_records", EXPENSE_COLUMNS, "year_month", filters)
      .order("expense_date", { ascending: false })
      .order("created_at", { ascending: false }),
    buildMonthEntityQuery("school_reimbursements", REIMBURSEMENT_COLUMNS, "year_month", filters)
      .order("created_at", { ascending: false }),
    buildMonthEntityQuery("school_payment_requests", PAYMENT_REQUEST_COLUMNS, "request_month", filters, {
      hasAppType: false,
    })
      .order("created_at", { ascending: false }),
    buildMonthEntityQuery("school_account_transactions", ACCOUNT_TRANSACTION_COLUMNS, "year_month", filters)
      .order("transaction_date", { ascending: false })
      .order("created_at", { ascending: false }),
  ]);

  throwIfError(businessEntitiesResult.error);
  throwIfError(incomeResult.error);
  throwIfError(expenseResult.error);
  throwIfError(reimbursementResult.error);
  throwIfError(paymentRequestResult.error);
  throwIfError(accountTransactionResult.error);

  return {
    businessEntities: businessEntitiesResult.data || [],
    incomeRecords: incomeResult.data || [],
    expenseRecords: expenseResult.data || [],
    reimbursements: reimbursementResult.data || [],
    paymentRequests: paymentRequestResult.data || [],
    accountTransactions: accountTransactionResult.data || [],
  };
}

function buildMonthEntityQuery(table, columns, monthColumn, filters, options = {}) {
  let query = supabase
    .from(table)
    .select(columns)
    .eq(monthColumn, filters.month);

  if (options.hasAppType !== false) {
    query = query.eq("app_type", "school");
  }

  if (filters.businessEntityId) {
    query = query.eq("business_entity_id", filters.businessEntityId);
  }

  if (filters.currency) {
    query = query.eq("currency", filters.currency);
  }

  return query;
}

function throwIfError(error) {
  if (error) {
    throw error;
  }
}
