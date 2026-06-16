import { supabase } from "../supabase-client.js";
import { buildFunctionError } from "./function-error.js";

const EXPENSE_COLUMNS = [
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
  "reversal_account_transaction_id",
  "receipt_status",
  "reimbursement_status",
  "note",
  "app_type",
  "source_type",
  "source_id",
  "payee_name_snapshot",
  "cash_request_id",
  "cash_request_status",
  "cash_transaction_id",
  "cash_requested_at",
  "cash_synced_at",
  "cash_error_message",
  "cash_payment_amount",
  "cash_payment_currency",
  "cash_payment_note",
  "created_at",
  "updated_at",
].join(",");

const WAGE_PAYMENT_REQUEST_COLUMNS = [
  "id",
  "status",
  "paid_expense_id",
  "source_id",
  "paid_account_transaction_id",
  "reversal_transaction_id",
  "replacement_payment_request_id",
  "reissued_from_payment_request_id",
  "reissued_at",
  "created_at",
].join(",");

const ATTACHMENT_LIST_COLUMNS = [
  "expense_id",
].join(",");

export async function fetchExpenseRecords(month) {
  const { data, error } = await supabase
    .from("school_expense_records")
    .select(EXPENSE_COLUMNS)
    .eq("app_type", "school")
    .eq("year_month", month)
    .order("expense_date", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchExpensePaymentRequests(expenseIds) {
  const ids = Array.from(new Set((expenseIds || []).filter(Boolean)));
  if (!ids.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_payment_requests")
    .select(WAGE_PAYMENT_REQUEST_COLUMNS)
    .eq("source_type", "teacher_wage")
    .in("paid_expense_id", ids)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchExpenseAttachmentCounts(expenseIds) {
  const ids = Array.from(new Set((expenseIds || []).filter(Boolean)));
  if (!ids.length) {
    return new Map();
  }

  const { data, error } = await supabase
    .from("school_expense_attachments")
    .select(ATTACHMENT_LIST_COLUMNS)
    .eq("app_type", "school")
    .in("expense_id", ids);

  if (error) {
    throw error;
  }

  const counts = new Map();
  for (const row of data || []) {
    counts.set(row.expense_id, (counts.get(row.expense_id) || 0) + 1);
  }

  return counts;
}

export async function createExpenseRecord(payload) {
  const { data, error } = await supabase.rpc("school_create_expense_record", {
    p_expense_date: payload.expenseDate,
    p_business_entity_id: payload.businessEntityId,
    p_account_id: payload.accountId,
    p_expense_category: payload.expenseCategory,
    p_description: payload.description,
    p_currency: payload.currency,
    p_amount: payload.amount,
    p_exchange_rate: payload.exchangeRate || null,
    p_payment_method: payload.paymentMethod || null,
    p_is_business_expense: Boolean(payload.isBusinessExpense),
    p_tax_category: payload.taxCategory || null,
    p_receipt_status: payload.receiptStatus || null,
    p_reimbursement_status: payload.reimbursementStatus || null,
    p_teacher_id: payload.teacherId || null,
    p_student_id: payload.studentId || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("支出新增成功，但 RPC 没有返回结果。");
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

export async function fetchExpenseLookups() {
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
      .select("id,name,display_name,status,business_entity_id,app_type")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
  ]);

  if (businessEntitiesResult.error) {
    throw businessEntitiesResult.error;
  }

  if (accountsResult.error) {
    throw accountsResult.error;
  }

  if (teachersResult.error) {
    throw teachersResult.error;
  }

  if (studentsResult.error) {
    throw studentsResult.error;
  }

  return {
    businessEntities: businessEntitiesResult.data || [],
    accounts: accountsResult.data || [],
    teachers: teachersResult.data || [],
    students: studentsResult.data || [],
  };
}
