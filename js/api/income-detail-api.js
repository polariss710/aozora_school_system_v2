import { supabase } from "../supabase-client.js";

const INCOME_DETAIL_COLUMNS = [
  "id",
  "business_entity_id",
  "student_id",
  "student_payment_id",
  "account_id",
  "income_date",
  "year_month",
  "settlement_month",
  "income_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "exchange_rate",
  "payment_currency",
  "payment_method",
  "status",
  "reversed_at",
  "reversal_reason",
  "reversal_account_transaction_id",
  "is_taxable_income",
  "tax_category",
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

const STUDENT_COLUMNS = [
  "id",
  "student_code",
  "name",
  "display_name",
  "status",
  "course_track",
  "target_type",
  "default_currency",
  "business_entity_id",
  "app_type",
].join(",");

const BUSINESS_ENTITY_COLUMNS = [
  "id",
  "code",
  "name",
  "entity_type",
  "default_currency",
  "is_active",
].join(",");

const ACCOUNT_COLUMNS = [
  "id",
  "account_code",
  "name",
  "account_type",
  "currency",
  "business_entity_id",
  "is_active",
  "app_type",
  "current_balance",
].join(",");

const SETTLEMENT_COLUMNS = [
  "id",
  "student_id",
  "year_month",
  "business_entity_id",
  "preset_exchange_rate",
  "planned_lesson_fee_jpy",
  "planned_lesson_fee_cny",
  "actual_lesson_fee_jpy",
  "actual_lesson_fee_cny",
  "received_jpy",
  "received_cny",
  "received_equivalent_cny",
  "system_difference_cny",
  "adjustment_amount_cny",
  "adjustment_reason",
  "carryover_amount_cny",
  "settlement_status",
  "locked_at",
  "note",
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

const CASH_INCOME_LINKAGE_COLUMNS = [
  "id",
  "income_record_id",
  "source_event_type",
  "sync_status",
  "cash_account_id",
  "cash_account_name_snapshot",
  "cash_transaction_table",
  "cash_transaction_id",
  "currency",
  "amount",
  "payment_currency",
  "payment_exchange_rate",
  "payment_amount",
  "cash_request_id",
  "cash_request_status",
  "idempotency_key",
  "retry_count",
  "last_error",
  "created_at",
  "updated_at",
  "synced_at",
].join(",");

export async function fetchIncomeDetailPage(incomeId) {
  const income = await fetchIncomeDetail(incomeId);

  const [lookups, settlements, transactions, cashIncomeLinkageEvents] = await Promise.all([
    fetchIncomeDetailLookups(),
    fetchSettlementReferences(income),
    fetchAccountTransactions(income.id),
    fetchPersonalCashIncomeLinkageEvents(income.id),
  ]);

  return {
    income,
    lookups,
    settlements,
    transactions,
    cashIncomeLinkageEvents,
  };
}

export async function reverseIncomeRecord(payload) {
  const { data, error } = await supabase.rpc("school_reverse_income_record", {
    p_income_id: payload.incomeId,
    p_reversal_date: payload.reversalDate,
    p_reason: payload.reason || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("收入撤销失败。");
  }

  return result;
}

export async function updateIncomeRecord(payload) {
  const { data, error } = await supabase.rpc("school_update_income_record", {
    p_income_id: payload.incomeId,
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
    p_include_in_student_settlement: payload.incomeCategory === "tuition",
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("收入编辑失败。");
  }

  return result;
}

export async function retryPersonalCashIncomeLinkageEvent(eventId) {
  const { data, error } = await supabase.rpc("school_retry_personal_cash_income_linkage_event", {
    p_event_id: eventId,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("Cash 同步重试入队失败。");
  }

  return result;
}

export async function requestCashIncomeConfirmationForRecord(payload) {
  const { data, error } = await supabase.functions.invoke(
    "request-cash-income-confirmation",
    {
      body: {
        income_record_id: payload.incomeRecordId,
        cash_account_id: payload.cashAccountId,
        actual_received_amount: payload.actualReceivedAmount,
        actual_received_currency: payload.actualReceivedCurrency,
        exchange_rate: payload.exchangeRate ?? null,
        note: payload.note || null,
      },
    }
  );

  if (error) {
    throw error;
  }

  if (!data?.ok) {
    throw new Error(data?.details || data?.message || "Cash System 收入确认请求提交失败。");
  }

  if (data.cash_request_status !== "pending") {
    throw new Error("Cash System 收入确认请求未停留在待确认状态。");
  }

  return data;
}

async function fetchIncomeDetail(incomeId) {
  const { data, error } = await supabase
    .from("school_income_records")
    .select(INCOME_DETAIL_COLUMNS)
    .eq("app_type", "school")
    .eq("id", incomeId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的收入记录。");
  }

  return data;
}

async function fetchIncomeDetailLookups() {
  const [studentsResult, businessEntitiesResult, accountsResult] = await Promise.all([
    supabase
      .from("school_students")
      .select(STUDENT_COLUMNS)
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_business_entities")
      .select(BUSINESS_ENTITY_COLUMNS)
      .order("name", { ascending: true }),
    supabase
      .from("school_accounts")
      .select(ACCOUNT_COLUMNS)
      .eq("app_type", "school")
      .order("currency", { ascending: true })
      .order("name", { ascending: true }),
  ]);

  if (studentsResult.error) throw studentsResult.error;
  if (businessEntitiesResult.error) throw businessEntitiesResult.error;
  if (accountsResult.error) throw accountsResult.error;

  return {
    students: studentsResult.data || [],
    businessEntities: businessEntitiesResult.data || [],
    accounts: accountsResult.data || [],
  };
}

async function fetchSettlementReferences(income) {
  if (
    income.include_in_student_settlement !== true ||
    !income.student_id ||
    !income.settlement_month ||
    !income.business_entity_id
  ) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select(SETTLEMENT_COLUMNS)
    .eq("student_id", income.student_id)
    .eq("year_month", income.settlement_month)
    .eq("business_entity_id", income.business_entity_id)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchAccountTransactions(incomeId) {
  const { data, error } = await supabase
    .from("school_account_transactions")
    .select(ACCOUNT_TRANSACTION_COLUMNS)
    .eq("app_type", "school")
    .eq("related_table", "school_income_records")
    .eq("related_id", incomeId)
    .order("transaction_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchPersonalCashIncomeLinkageEvents(incomeId) {
  const { data, error } = await supabase
    .from("school_personal_cash_income_linkage_events")
    .select(CASH_INCOME_LINKAGE_COLUMNS)
    .eq("income_record_id", incomeId)
    .eq("source_table", "school_income_records")
    .in("source_event_type", ["tuition_income_received", "income_received"])
    .order("created_at", { ascending: false });

  if (error) {
    if (error.code === "42P01") {
      return [];
    }
    throw error;
  }

  return data || [];
}
