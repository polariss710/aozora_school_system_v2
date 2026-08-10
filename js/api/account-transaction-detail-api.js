import { supabase } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";

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

const ACCOUNT_ADJUSTMENT_COLUMNS = [
  "id",
  "business_entity_id",
  "account_id",
  "adjustment_date",
  "year_month",
  "currency",
  "amount",
  "balance_before",
  "balance_after",
  "reason",
  "note",
  "status",
  "account_transaction_id",
  "reversed_at",
  "reversal_reason",
  "reversal_account_transaction_id",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const ACCOUNT_TRANSFER_COLUMNS = [
  "id",
  "business_entity_id",
  "from_account_id",
  "to_account_id",
  "transfer_date",
  "year_month",
  "currency",
  "amount",
  "from_balance_before",
  "from_balance_after",
  "to_balance_before",
  "to_balance_after",
  "reason",
  "note",
  "status",
  "from_account_transaction_id",
  "to_account_transaction_id",
  "reversed_at",
  "reversal_reason",
  "reversal_from_account_transaction_id",
  "reversal_to_account_transaction_id",
  "app_type",
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

export async function reverseAccountAdjustment({ adjustmentId, reversalDate, reason }) {
  const { data, error } = await supabase.rpc("school_reverse_account_adjustment", {
    p_adjustment_id: adjustmentId,
    p_reversal_date: reversalDate,
    p_reason: reason,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("账户调整撤销失败。");
  }

  return result;
}

export async function reverseAccountTransfer({ transferId, reversalDate, reason }) {
  const { data, error } = await supabase.rpc("school_reverse_account_transfer", {
    p_transfer_id: transferId,
    p_reversal_date: reversalDate,
    p_reason: reason,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("账户转账撤销失败。");
  }

  return result;
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
  const [accountsResult] = await Promise.all([
    supabase
      .from("school_accounts")
      .select(ACCOUNT_COLUMNS)
      .eq("app_type", "school")
      .order("currency", { ascending: true })
      .order("name", { ascending: true }),
  ]);

  if (accountsResult.error) throw accountsResult.error;

  return {
    accounts: accountsResult.data || [],
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
      table: "school_operational_income_records",
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
    school_account_adjustments: {
      table,
      columns: ACCOUNT_ADJUSTMENT_COLUMNS,
    },
    school_account_transfers: {
      table,
      columns: ACCOUNT_TRANSFER_COLUMNS,
    },
    school_accounts: {
      table,
      columns: ACCOUNT_COLUMNS,
    },
  };

  return configs[table] || null;
}
