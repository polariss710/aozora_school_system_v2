import { supabase } from "../supabase-client.js";
import { buildFunctionError } from "./function-error.js";

const EXPENSE_DETAIL_COLUMNS = [
  "id",
  "business_entity_id",
  "teacher_id",
  "student_id",
  "salary_payment_id",
  "account_id",
  "expense_date",
  "year_month",
  "expense_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "exchange_rate",
  "payment_method",
  "status",
  "reversed_at",
  "reversal_reason",
  "reversal_account_transaction_id",
  "is_business_expense",
  "tax_category",
  "receipt_status",
  "note",
  "app_type",
  "created_at",
  "updated_at",
  "reimbursement_status",
  "reimbursement_note",
  "source_type",
  "source_id",
  "payee_name_snapshot",
  "cash_request_id",
  "cash_request_event_id",
  "cash_request_attempt_no",
  "cash_request_status",
  "cash_transaction_id",
  "cash_requested_at",
  "cash_synced_at",
  "cash_error_message",
  "cash_payment_amount",
  "cash_payment_currency",
  "cash_payment_note",
].join(",");

const PAYMENT_REQUEST_COLUMNS = [
  "id",
  "status",
  "source_type",
  "source_id",
  "request_month",
  "payee_name",
  "amount",
  "currency",
  "paid_at",
  "paid_expense_id",
  "paid_account_transaction_id",
  "account_id",
  "reversed_at",
  "reversal_transaction_id",
  "reversal_reason",
  "reissued_from_payment_request_id",
  "replacement_payment_request_id",
  "reissue_reason",
  "reissued_at",
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
  "updated_at",
].join(",");

const REIMBURSEMENT_ITEM_COLUMNS = [
  "id",
  "reimbursement_id",
  "expense_id",
  "amount",
  "note",
  "app_type",
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
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const ATTACHMENT_COLUMNS = [
  "id",
  "expense_id",
  "file_name",
  "file_type",
  "file_size",
  "source_type",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

export async function fetchExpenseDetailPage(expenseId) {
  const expense = await fetchExpenseDetail(expenseId);

  const [lookups, paymentRequests, directTransactions, reimbursementItems, attachments] =
    await Promise.all([
      fetchExpenseDetailLookups(),
      fetchPaymentRequestsByExpenseId(expense.id),
      fetchDirectAccountTransactions(expense.id),
      fetchReimbursementItems(expense.id),
      fetchExpenseAttachments(expense.id),
    ]);

  const paymentTransactionIds = transactionIdsFromPaymentRequests(paymentRequests);
  const [paymentTransactions, reimbursements] = await Promise.all([
    fetchAccountTransactionsByIds(paymentTransactionIds),
    fetchReimbursementsByIds(reimbursementItems.map((item) => item.reimbursement_id)),
  ]);

  return {
    expense,
    lookups,
    paymentRequests,
    directTransactions,
    paymentTransactions,
    reimbursementItems,
    reimbursements,
    attachments,
  };
}

export async function reverseExpenseRecord(payload) {
  const { data, error } = await supabase.rpc("school_reverse_expense_record", {
    p_expense_id: payload.expenseId,
    p_reversal_date: payload.reversalDate,
    p_reason: payload.reason || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("支出撤销失败。");
  }

  return result;
}

export async function updateExpenseRecord(payload) {
  const { data, error } = await supabase.rpc("school_update_expense_record", {
    p_expense_id: payload.expenseId,
    p_expense_date: payload.expenseDate,
    p_business_entity_id: payload.businessEntityId,
    p_account_id: payload.accountId,
    p_expense_category: payload.expenseCategory,
    p_description: payload.description,
    p_currency: payload.currency,
    p_amount: payload.amount,
    p_exchange_rate: payload.exchangeRate || null,
    p_payment_method: payload.paymentMethod || null,
    p_tax_category: payload.taxCategory || null,
    p_receipt_status: payload.receiptStatus || null,
    p_reimbursement_status: payload.reimbursementStatus || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("支出编辑失败。");
  }

  return result;
}

export async function createExpenseAttachmentMetadata(payload) {
  const { data, error } = await supabase.rpc("school_create_expense_attachment_metadata", {
    p_expense_id: payload.expenseId,
    p_file_name: payload.fileName,
    p_file_type: payload.fileType || null,
    p_file_size: payload.fileSize ?? null,
    p_source_type: payload.sourceType || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("附件摘要保存失败。");
  }

  return result;
}

export async function requestCashExpenseConfirmation(payload) {
  const { data, error } = await supabase.functions.invoke("request-cash-expense-confirmation", {
    body: {
      expense_record_id: payload.expenseId,
      cash_account_id: payload.cashAccountId,
      actual_payment_amount: payload.actualPaymentAmount,
      actual_payment_currency: payload.actualPaymentCurrency,
      actual_payment_date: payload.actualPaymentDate,
      note: payload.note || null,
    },
  });

  if (error) {
    throw await buildFunctionError(error, data, "Cash System 支出确认请求提交失败。");
  }

  if (!data) {
    throw new Error("Cash System 支出确认请求提交失败：Function 没有返回结果。");
  }

  if (data.ok === false) {
    throw new Error(data.details || data.message || "Cash System 支出确认请求提交失败。");
  }

  if (data.cash_request_status !== "pending") {
    throw new Error("Cash System 支出确认请求未停留在待确认状态。");
  }

  return data;
}

async function fetchExpenseDetail(expenseId) {
  const { data, error } = await supabase
    .from("school_expense_records")
    .select(EXPENSE_DETAIL_COLUMNS)
    .eq("app_type", "school")
    .eq("id", expenseId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的支出记录。");
  }

  return data;
}

async function fetchExpenseDetailLookups() {
  const [businessEntitiesResult, accountsResult, teachersResult, studentsResult] = await Promise.all([
    supabase
      .from("school_business_entities")
      .select("id,name,is_active")
      .order("name", { ascending: true }),
    supabase
      .from("school_accounts")
      .select("id,account_code,name,currency,business_entity_id,current_balance,is_company_account,is_active,app_type")
      .eq("app_type", "school")
      .order("currency", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_teachers")
      .select("id,name,display_name,status,default_business_entity_id")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_students")
      .select("id,name,display_name,student_code,status,business_entity_id")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
  ]);

  if (businessEntitiesResult.error) throw businessEntitiesResult.error;
  if (accountsResult.error) throw accountsResult.error;
  if (teachersResult.error) throw teachersResult.error;
  if (studentsResult.error) throw studentsResult.error;

  return {
    businessEntities: businessEntitiesResult.data || [],
    accounts: accountsResult.data || [],
    teachers: teachersResult.data || [],
    students: studentsResult.data || [],
  };
}

async function fetchPaymentRequestsByExpenseId(expenseId) {
  const { data, error } = await supabase
    .from("school_payment_requests")
    .select(PAYMENT_REQUEST_COLUMNS)
    .eq("source_type", "teacher_wage")
    .eq("paid_expense_id", expenseId)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchDirectAccountTransactions(expenseId) {
  const { data, error } = await supabase
    .from("school_account_transactions")
    .select(ACCOUNT_TRANSACTION_COLUMNS)
    .eq("app_type", "school")
    .eq("related_table", "school_expense_records")
    .eq("related_id", expenseId)
    .order("transaction_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchAccountTransactionsByIds(ids) {
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

async function fetchReimbursementItems(expenseId) {
  const { data, error } = await supabase
    .from("school_reimbursement_items")
    .select(REIMBURSEMENT_ITEM_COLUMNS)
    .eq("app_type", "school")
    .eq("expense_id", expenseId)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchReimbursementsByIds(ids) {
  const reimbursementIds = Array.from(new Set((ids || []).filter(Boolean)));
  if (!reimbursementIds.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_reimbursements")
    .select(REIMBURSEMENT_COLUMNS)
    .eq("app_type", "school")
    .in("id", reimbursementIds)
    .order("reimbursement_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchExpenseAttachments(expenseId) {
  const { data, error } = await supabase
    .from("school_expense_attachments")
    .select(ATTACHMENT_COLUMNS)
    .eq("app_type", "school")
    .eq("expense_id", expenseId)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

function transactionIdsFromPaymentRequests(paymentRequests) {
  return paymentRequests.flatMap((request) => [
    request.paid_account_transaction_id,
    request.reversal_transaction_id,
  ]);
}
