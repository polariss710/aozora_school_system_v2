import { supabase } from "../supabase-client.js";
import { buildFunctionError } from "./function-error.js";
import { requireUuid } from "./validation.js";

const INCOME_COLUMNS = [
  "id",
  "business_entity_id",
  "student_id",
  "student_payment_id",
  "account_id",
  "income_date",
  "year_month",
  "settlement_month",
  "income_category",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "exchange_rate",
  "payment_method",
  "status",
  "receipt_status",
  "include_in_student_settlement",
  "note",
  "source_type",
  "source_id",
  "source_label",
  "source_snapshot",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const CASH_INCOME_LINKAGE_COLUMNS = [
  "id",
  "income_record_id",
  "source_event_type",
  "sync_status",
  "cash_account_name_snapshot",
  "cash_account_type_snapshot",
  "currency",
  "amount",
  "payment_currency",
  "payment_amount",
  "payment_exchange_rate",
  "note",
  "cash_request_id",
  "cash_request_status",
  "cash_transaction_id",
  "last_error",
  "retry_count",
  "synced_at",
].join(",");

export async function fetchIncomeRecords(month) {
  const { data, error } = await supabase
    .from("school_income_records")
    .select(INCOME_COLUMNS)
    .eq("app_type", "school")
    .eq("year_month", month)
    .order("income_date", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return mergeCashIncomeLinkageEvents(data || []);
}

export async function createIncomeRecord(payload) {
  const { data, error } = await supabase.rpc("school_create_income_record", {
    p_income_date: payload.incomeDate,
    p_settlement_month: payload.settlementMonth,
    p_business_entity_id: payload.businessEntityId,
    p_student_id: payload.studentId,
    p_account_id: payload.accountId,
    p_amount: payload.amount,
    p_income_category: payload.incomeCategory,
    p_description: payload.description || null,
    p_currency: payload.currency,
    p_payment_currency: payload.paymentCurrency,
    p_exchange_rate: payload.exchangeRate || null,
    p_payment_method: payload.paymentMethod || null,
    p_is_taxable_income: Boolean(payload.isTaxableIncome),
    p_tax_category: payload.taxCategory || null,
    p_receipt_status: payload.receiptStatus || null,
    p_include_in_student_settlement: true,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("收入新增成功，但 RPC 没有返回结果。");
  }

  return result;
}

export async function createCashSystemIncome(payload) {
  const { data, error } = await supabase.functions.invoke(
    "request-cash-income-confirmation",
    {
      body: {
        income_date: payload.incomeDate,
        settlement_month: payload.settlementMonth,
        business_entity_id: payload.businessEntityId,
        student_id: payload.studentId,
        cash_account_id: payload.cashAccountId,
        amount: payload.amount,
        income_category: payload.incomeCategory,
        description: payload.description || null,
        currency: payload.currency,
        exchange_rate: payload.exchangeRate || null,
        payment_method: payload.paymentMethod || null,
        is_taxable_income: Boolean(payload.isTaxableIncome),
        tax_category: payload.taxCategory || null,
        receipt_status: payload.receiptStatus || null,
        note: payload.note || null,
      },
    }
  );

  if (error) {
    throw await buildFunctionError(error, data, "Cash System 收入提交失败。");
  }

  if (!data?.ok) {
    throw new Error(data?.details || data?.message || "Cash System 收入提交失败。");
  }

  if (data.cash_request_status !== "pending") {
    throw new Error("Cash System 收入未停留在待确认状态。");
  }

  return data;
}

export async function requestCashIncomeConfirmationForRecord(payload) {
  const incomeRecordId = requireUuid(payload.incomeRecordId, "income_record_id");

  const { data, error } = await supabase.functions.invoke(
    "request-cash-income-confirmation",
    {
      body: {
        income_record_id: incomeRecordId,
        cash_account_id: payload.cashAccountId,
        actual_received_amount: payload.actualReceivedAmount,
        actual_received_currency: payload.actualReceivedCurrency,
        actual_received_date: payload.actualReceivedDate,
        exchange_rate: payload.exchangeRate ?? null,
        note: payload.note || null,
      },
    }
  );

  if (error) {
    throw await buildFunctionError(error, data, "Cash System 收入确认请求提交失败。");
  }

  if (!data?.ok) {
    throw new Error(data?.details || data?.message || "Cash System 收入确认请求提交失败。");
  }

  if (data.cash_request_status !== "pending") {
    throw new Error("Cash System 收入确认请求未停留在待确认状态。");
  }

  return data;
}

export async function fetchIncomeLookups() {
  const [studentsResult, businessEntitiesResult, accountsResult] = await Promise.all([
    supabase
      .from("school_students")
      .select("id,name,display_name,status,business_entity_id")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_business_entities")
      .select("id,name,entity_type,is_active")
      .order("name", { ascending: true }),
    supabase
      .from("school_accounts")
      .select("id,account_code,name,currency,business_entity_id,current_balance,is_active,app_type")
      .eq("app_type", "school")
      .order("currency", { ascending: true })
      .order("name", { ascending: true }),
  ]);

  if (studentsResult.error) {
    throw studentsResult.error;
  }

  if (businessEntitiesResult.error) {
    throw businessEntitiesResult.error;
  }

  if (accountsResult.error) {
    throw accountsResult.error;
  }

  return {
    students: studentsResult.data || [],
    businessEntities: businessEntitiesResult.data || [],
    accounts: accountsResult.data || [],
  };
}

async function mergeCashIncomeLinkageEvents(incomeRows) {
  const incomeIds = incomeRows.map((row) => row.id).filter(Boolean);
  if (!incomeIds.length) {
    return incomeRows;
  }

  const { data, error } = await supabase
    .from("school_personal_cash_income_linkage_events")
    .select(CASH_INCOME_LINKAGE_COLUMNS)
    .in("income_record_id", incomeIds)
    .eq("source_table", "school_income_records")
    .in("source_event_type", ["tuition_income_received", "income_received"])
    .order("created_at", { ascending: false });

  if (error) {
    if (error.code === "42P01") {
      return incomeRows;
    }
    throw error;
  }

  const linkageByIncomeId = new Map();
  for (const event of data || []) {
    if (!linkageByIncomeId.has(event.income_record_id)) {
      linkageByIncomeId.set(event.income_record_id, event);
    }
  }

  return incomeRows.map((row) => ({
    ...row,
    cashIncomeLinkageEvent: linkageByIncomeId.get(row.id) || null,
  }));
}
