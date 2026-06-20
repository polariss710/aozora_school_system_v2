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

const EDITABLE_INCOME_CATEGORIES = new Set(["tuition", "material_fee", "registration_fee", "other_fee"]);

const DEFAULT_INCOME_DESCRIPTIONS = {
  tuition: "学费收入",
  material_fee: "教材费收入",
  registration_fee: "报名费收入",
  other_fee: "其他费用收入",
};

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

export async function createPendingCashIncomeRecord(payload) {
  const incomeDate = payload.incomeDate;
  const settlementMonth = payload.settlementMonth;
  const businessEntityId = payload.businessEntityId;
  const studentId = payload.studentId;
  const incomeCategory = String(payload.incomeCategory || "").trim().toLowerCase();
  const currency = String(payload.currency || "").trim().toUpperCase();
  const paymentCurrency = String(payload.paymentCurrency || payload.currency || "").trim().toUpperCase();
  const amount = Number(payload.amount);
  const exchangeRate = payload.exchangeRate ? Number(payload.exchangeRate) : null;

  if (!incomeDate) {
    throw new Error("请选择实际收款日期。");
  }

  if (!settlementMonth || !/^[0-9]{4}-(0[1-9]|1[0-2])$/.test(settlementMonth)) {
    throw new Error("结算月份格式无效。");
  }

  if (!businessEntityId) {
    throw new Error("请选择业务归属。");
  }

  if (!studentId) {
    throw new Error("请选择学生。");
  }

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error("收入金额必须大于 0。");
  }

  if (!EDITABLE_INCOME_CATEGORIES.has(incomeCategory)) {
    throw new Error("收入分类无效。");
  }

  if (!["JPY", "CNY"].includes(currency) || !["JPY", "CNY"].includes(paymentCurrency)) {
    throw new Error("Cash 收入币种仅支持 JPY / CNY。");
  }

  if (currency !== paymentCurrency) {
    throw new Error("Cash 收入要求收入币种与收款币种一致。");
  }

  if (exchangeRate !== null && (!Number.isFinite(exchangeRate) || exchangeRate <= 0)) {
    throw new Error("汇率必须大于 0。");
  }

  await assertPendingCashIncomeReferences({
    businessEntityId,
    studentId,
    settlementMonth,
    incomeCategory,
  });

  const { amountJpy, amountCny } = cashIncomeAmounts(amount, currency, exchangeRate);
  const description = nullIfBlank(payload.description) || DEFAULT_INCOME_DESCRIPTIONS[incomeCategory] || "收入";
  const now = new Date().toISOString();

  const { data, error } = await supabase
    .from("school_income_records")
    .insert({
      business_entity_id: businessEntityId,
      student_id: studentId,
      student_payment_id: null,
      account_id: null,
      income_date: incomeDate,
      year_month: settlementMonth,
      settlement_month: settlementMonth,
      income_category: incomeCategory,
      description,
      currency,
      amount,
      amount_jpy: amountJpy,
      amount_cny: amountCny,
      exchange_rate: exchangeRate,
      payment_currency: paymentCurrency,
      payment_method: null,
      status: "pending",
      is_taxable_income: Boolean(payload.isTaxableIncome),
      tax_category: nullIfBlank(payload.taxCategory),
      receipt_status: "Cash待提交",
      include_in_student_settlement: incomeCategory === "tuition",
      note: nullIfBlank(payload.note),
      app_type: "school",
      created_at: now,
      updated_at: now,
    })
    .select("id,status,receipt_status,account_id")
    .single();

  if (error) {
    throw error;
  }

  if (!data?.id) {
    throw new Error("Cash 收入记录保存成功，但没有返回收入 ID。");
  }

  return {
    income_id: data.id,
    account_transaction_id: null,
    account_id: null,
    income_status: data.status,
    cash_request_id: null,
    cash_request_status: null,
    cash_transaction_id: null,
    message: "Cash 收入记录已保存，尚未提交 Cash。",
  };
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

async function assertPendingCashIncomeReferences({
  businessEntityId,
  studentId,
  settlementMonth,
  incomeCategory,
}) {
  const [businessEntityResult, studentResult] = await Promise.all([
    supabase
      .from("school_business_entities")
      .select("id,is_active")
      .eq("id", businessEntityId)
      .maybeSingle(),
    supabase
      .from("school_students")
      .select("id,business_entity_id,app_type")
      .eq("id", studentId)
      .eq("app_type", "school")
      .maybeSingle(),
  ]);

  if (businessEntityResult.error) {
    throw businessEntityResult.error;
  }

  if (!businessEntityResult.data || businessEntityResult.data.is_active !== true) {
    throw new Error("业务归属无效或已停用。");
  }

  if (studentResult.error) {
    throw studentResult.error;
  }

  if (!studentResult.data) {
    throw new Error("学生无效或不可用。");
  }

  if (
    studentResult.data.business_entity_id &&
    studentResult.data.business_entity_id !== businessEntityId
  ) {
    throw new Error("学生业务归属与收入业务归属不一致。");
  }

  if (incomeCategory !== "tuition") {
    return;
  }

  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select("id")
    .eq("student_id", studentId)
    .eq("business_entity_id", businessEntityId)
    .eq("year_month", settlementMonth)
    .eq("settlement_status", "locked")
    .limit(1);

  if (error) {
    throw error;
  }

  if ((data || []).length > 0) {
    throw new Error("目标学生月度结算已锁定，不能直接新增收入。");
  }
}

function cashIncomeAmounts(amount, currency, exchangeRate) {
  if (currency === "JPY") {
    return {
      amountJpy: amount,
      amountCny: exchangeRate ? amount / exchangeRate : null,
    };
  }

  return {
    amountJpy: exchangeRate ? amount * exchangeRate : null,
    amountCny: amount,
  };
}

function nullIfBlank(value) {
  const text = String(value || "").trim();
  return text || null;
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
