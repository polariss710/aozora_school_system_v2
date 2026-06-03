import { supabase } from "../supabase-client.js";

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

const ACCOUNT_COLUMNS = [
  "id",
  "account_code",
  "name",
  "account_type",
  "currency",
  "business_entity_id",
  "opening_balance",
  "current_balance",
  "is_company_account",
  "is_active",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const BUSINESS_ENTITY_COLUMNS = [
  "id",
  "code",
  "name",
  "entity_type",
  "default_currency",
  "is_active",
].join(",");

const INCOME_COLUMNS = [
  "id",
  "income_date",
  "year_month",
  "settlement_month",
  "income_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "status",
  "student_id",
  "account_id",
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

const PAYMENT_REQUEST_COLUMNS = [
  "id",
  "source_type",
  "source_id",
  "request_month",
  "payee_name",
  "business_name",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "status",
  "paid_at",
  "reversed_at",
  "reissued_at",
  "paid_expense_id",
  "created_at",
  "updated_at",
].join(",");

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
  "created_at",
  "updated_at",
].join(",");

export async function fetchAccountTransactionDetailPage(transactionId) {
  const transaction = await fetchAccountTransaction(transactionId);

  const [lookups, source] = await Promise.all([
    fetchAccountTransactionLookups(),
    fetchRelatedSource(transaction),
  ]);

  return {
    transaction,
    lookups,
    source,
  };
}

async function fetchAccountTransaction(transactionId) {
  const { data, error } = await supabase
    .from("school_account_transactions")
    .select(ACCOUNT_TRANSACTION_COLUMNS)
    .eq("app_type", "school")
    .eq("id", transactionId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的账户流水。");
  }

  return data;
}

async function fetchAccountTransactionLookups() {
  const [accountsResult, businessEntitiesResult] = await Promise.all([
    supabase
      .from("school_accounts")
      .select(ACCOUNT_COLUMNS)
      .eq("app_type", "school")
      .order("currency", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_business_entities")
      .select(BUSINESS_ENTITY_COLUMNS)
      .order("name", { ascending: true }),
  ]);

  if (accountsResult.error) throw accountsResult.error;
  if (businessEntitiesResult.error) throw businessEntitiesResult.error;

  return {
    accounts: accountsResult.data || [],
    businessEntities: businessEntitiesResult.data || [],
  };
}

async function fetchRelatedSource(transaction) {
  if (!transaction.related_table || !transaction.related_id) {
    return { table: transaction.related_table || "", row: null, error: "" };
  }

  const config = relatedSourceConfig(transaction.related_table);
  if (!config) {
    return { table: transaction.related_table, row: null, error: "unsupported" };
  }

  const { data, error } = await supabase
    .from(config.table)
    .select(config.columns)
    .eq("id", transaction.related_id)
    .maybeSingle();

  if (error) {
    return { table: transaction.related_table, row: null, error: error.message || String(error) };
  }

  return { table: transaction.related_table, row: data || null, error: "" };
}

function relatedSourceConfig(table) {
  const configs = {
    school_income_records: {
      table,
      columns: INCOME_COLUMNS,
    },
    school_expense_records: {
      table,
      columns: EXPENSE_COLUMNS,
    },
    school_payment_requests: {
      table,
      columns: PAYMENT_REQUEST_COLUMNS,
    },
    school_reimbursements: {
      table,
      columns: REIMBURSEMENT_COLUMNS,
    },
    school_accounts: {
      table,
      columns: ACCOUNT_COLUMNS,
    },
  };

  return configs[table] || null;
}
