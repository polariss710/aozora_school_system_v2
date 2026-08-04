// request-cash-expense-confirmation
//
// Page-triggered School -> Cash pending request bridge for canonical expense
// records. This function only creates a Cash pending request and records the
// submitted request id on School. It must not approve/reject Cash requests,
// create Cash transactions, or mutate legacy school_payment_requests.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  expense_record_id?: string;
  cash_account_id?: string;
  actual_payment_amount?: number | string;
  actual_payment_currency?: string;
  actual_payment_date?: string;
  exchange_rate?: number | string | null;
  rounding_mode?: string | null;
  note?: string | null;
};

type CashAccountRow = {
  id: string;
  user_id: string;
  name: string | null;
  currency: string;
  account_type: string | null;
  is_active: boolean;
  allow_school_requests: boolean;
};

type ExpenseRow = {
  id: string;
  expense_date: string;
  year_month: string;
  expense_category: string;
  description: string | null;
  note: string | null;
  currency: string;
  amount: number | string;
  amount_jpy: number | string | null;
  amount_cny: number | string | null;
  status: string;
  source_type: string | null;
  source_id: string | null;
  payee_name_snapshot: string | null;
};

type SchoolExpenseRequestRow = {
  expense_id: string;
  request_event_id: string;
  attempt_no: number;
  idempotency_key: string;
  request_type: string;
  expense_status: string;
  expense_category: string;
  source_type: string | null;
  source_id: string | null;
  payee_name_snapshot: string | null;
  year_month: string;
  expense_date: string;
  description: string | null;
  original_amount: number | string;
  original_currency: string;
  original_amount_jpy: number | string | null;
  original_amount_cny: number | string | null;
  payment_amount: number | string;
  payment_currency: string;
  cash_user_id: string;
  cash_account_id: string;
  cash_account_name_snapshot: string;
  cash_account_type_snapshot: string | null;
  cash_request_id: string | null;
  cash_request_status: string | null;
  message: string;
};

type CashRequestResult = {
  ok?: boolean;
  inserted?: boolean;
  request_id?: string;
  status?: string;
  created_transaction_id?: string | null;
  message?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const CASH_EXTERNAL_SOURCE = "aozora_school";
const CASH_REFERENCE_TYPE = "school_expense_records";
const CASH_REQUEST_TYPE = "expense_paid";
const CASH_TRANSACTION_TYPE = "expense";
const SUPPORTED_CURRENCIES = new Set(["JPY", "CNY"]);
const EXPENSE_CATEGORY_LABELS: Record<string, string> = {
  advertising: "广告宣传",
  classroom: "教室费用",
  other: "其他",
  software: "软件服务",
  tax_accounting: "税务会计",
  teacher_wage: "老师工资",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function getRequiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function createSupabaseClient(urlEnv: string, keyEnv: string) {
  return createClient(getRequiredEnv(urlEnv), getRequiredEnv(keyEnv), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function createUserScopedSchoolClient(authorization: string) {
  return createClient(
    getRequiredEnv("SCHOOL_SUPABASE_URL"),
    getRequiredEnv("SUPABASE_ANON_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
      global: {
        headers: { Authorization: authorization },
      },
    },
  );
}

async function requireSchoolUser(
  schoolClient: ReturnType<typeof createClient>,
  authorization: string,
) {
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return null;
  }

  const bearerToken = authorization.replace(/^bearer\s+/i, "");
  const { data: userData, error: userError } =
    await schoolClient.auth.getUser(bearerToken);
  if (userError || !userData.user) {
    return null;
  }

  return userData.user;
}

async function requireCurrentActiveAdmin(
  userScopedSchoolClient: ReturnType<typeof createClient>,
  verifiedUserId: string,
): Promise<boolean> {
  const { data, error } = await userScopedSchoolClient.rpc(
    "school_require_current_app_admin",
  );
  const actorId = typeof data === "string" ? data : "";
  return !error && actorId.toLowerCase() === verifiedUserId.toLowerCase();
}

function requireUuid(value: unknown, fieldName: string): string {
  if (typeof value !== "string") {
    throw new Error(`${fieldName} is required`);
  }

  const trimmed = value.trim();
  const uuidPattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidPattern.test(trimmed)) {
    throw new Error(`${fieldName} must be a UUID`);
  }

  return trimmed;
}

function requirePositiveNumber(value: unknown, fieldName: string): number {
  const numberValue = typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : NaN;
  if (!Number.isFinite(numberValue) || numberValue <= 0) {
    throw new Error(`${fieldName} must be greater than 0`);
  }

  return numberValue;
}

function optionalPositiveNumber(value: unknown, fieldName: string): number | null {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  return requirePositiveNumber(value, fieldName);
}

function requireCurrency(value: unknown): string {
  if (typeof value !== "string") {
    throw new Error("actual_payment_currency is required");
  }

  const currency = value.trim().toUpperCase();
  if (!SUPPORTED_CURRENCIES.has(currency)) {
    throw new Error("actual_payment_currency must be JPY or CNY");
  }

  return currency;
}

function optionalDate(value: unknown, fieldName: string): string | null {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const text = typeof value === "string" ? value.trim() : "";
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(text)) {
    throw new Error(`${fieldName} must be YYYY-MM-DD`);
  }

  return text;
}

function optionalText(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function unwrapSingleRow<T>(data: T[] | T | null, context: string): T {
  if (Array.isArray(data)) {
    if (data.length !== 1) {
      throw new Error(`${context} returned ${data.length} rows`);
    }

    return data[0];
  }

  if (!data) {
    throw new Error(`${context} returned no data`);
  }

  return data;
}

async function listEligibleAccounts(
  cashClient: ReturnType<typeof createClient>,
): Promise<CashAccountRow[]> {
  const { data, error } = await cashClient
    .from("home_accounts")
    .select("id,user_id,name,currency,account_type,is_active,allow_school_requests")
    .eq("is_active", true)
    .eq("allow_school_requests", true)
    .order("currency", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw new Error(`Cash eligible account lookup failed: ${error.message}`);
  }

  return (data || []) as CashAccountRow[];
}

function expenseCategoryLabel(category: string | null | undefined): string {
  if (!category) return "支出";
  return EXPENSE_CATEGORY_LABELS[category] ?? category;
}

function buildCashExpenseDescription(expense: ExpenseRow, paymentCurrency: string, paymentAmount: number): string {
  const parts = [
    expenseCategoryLabel(expense.expense_category),
    expense.payee_name_snapshot,
    expense.year_month,
    `${paymentAmount.toLocaleString("ja-JP")} ${paymentCurrency}`,
  ].filter(Boolean);
  return parts.join(" / ");
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse(
      { ok: false, message: "Only POST is supported" },
      405,
    );
  }

  try {
    const authorization = request.headers.get("authorization") ?? "";
    const schoolClient = createSupabaseClient(
      "SCHOOL_SUPABASE_URL",
      "SCHOOL_SERVICE_ROLE_KEY",
    );

    const schoolUser = await requireSchoolUser(schoolClient, authorization);
    if (!schoolUser) {
      return jsonResponse(
        { ok: false, message: "Invalid School authorization token" },
        401,
      );
    }

    const userScopedSchoolClient = createUserScopedSchoolClient(authorization);
    if (!await requireCurrentActiveAdmin(userScopedSchoolClient, schoolUser.id)) {
      return jsonResponse(
        {
          ok: false,
          code: "P0G1_ACTIVE_ADMIN_REQUIRED",
          message: "仅已启用的管理员账号可以提交 Cash 支付确认请求。",
        },
        403,
      );
    }

    const body = (await request.json()) as RequestBody;
    const cashClient = createSupabaseClient(
      "CASH_SUPABASE_URL",
      "CASH_SERVICE_ROLE_KEY",
    );

    const expenseRecordId = requireUuid(body.expense_record_id, "expense_record_id");
    const cashAccountId = requireUuid(body.cash_account_id, "cash_account_id");
    const actualPaymentAmount = optionalPositiveNumber(
      body.actual_payment_amount,
      "actual_payment_amount",
    );
    const actualPaymentCurrency = requireCurrency(body.actual_payment_currency);
    const exchangeRate = optionalPositiveNumber(body.exchange_rate, "exchange_rate");
    const roundingMode = optionalText(body.rounding_mode);
    const requestedPaymentDate = optionalDate(body.actual_payment_date, "actual_payment_date");
    const note = optionalText(body.note);

    const { data: expenseData, error: expenseError } = await schoolClient
      .from("school_expense_records")
      .select("id,expense_date,year_month,expense_category,description,note,currency,amount,amount_jpy,amount_cny,status,source_type,source_id,payee_name_snapshot")
      .eq("id", expenseRecordId)
      .eq("app_type", "school")
      .maybeSingle();

    if (expenseError || !expenseData) {
      return jsonResponse(
        {
          ok: false,
          message: "School expense record lookup failed",
          details: expenseError?.message ?? null,
        },
        404,
      );
    }

    const expense = expenseData as ExpenseRow;
    const originalCurrency = requireCurrency(expense.currency);

    if (actualPaymentCurrency !== originalCurrency && exchangeRate === null) {
      return jsonResponse(
        { ok: false, message: "Cross-currency actual payment amount requires exchange_rate" },
        400,
      );
    }

    if (
      actualPaymentCurrency === originalCurrency && exchangeRate !== null &&
      exchangeRate !== 1
    ) {
      return jsonResponse(
        { ok: false, message: "Same-currency actual payment exchange_rate must be empty or 1" },
        400,
      );
    }

    if (actualPaymentAmount === null && actualPaymentCurrency !== originalCurrency) {
      if (!["round", "ceil", "floor"].includes(roundingMode ?? "")) {
        return jsonResponse(
          {
            ok: false,
            message: "Backend-calculated cross-currency payment amount requires rounding_mode",
          },
          400,
        );
      }
    }

    const eligibleAccounts = await listEligibleAccounts(cashClient);
    const cashAccount = eligibleAccounts.find((account) => account.id === cashAccountId);
    if (!cashAccount) {
      return jsonResponse(
        { ok: false, message: "Selected Cash account is not School-eligible" },
        400,
      );
    }

    if (cashAccount.currency !== actualPaymentCurrency) {
      return jsonResponse(
        {
          ok: false,
          message: "Selected Cash account currency does not match actual payment currency",
          account_currency: cashAccount.currency,
          actual_payment_currency: actualPaymentCurrency,
        },
        400,
      );
    }

    if (!await requireCurrentActiveAdmin(userScopedSchoolClient, schoolUser.id)) {
      return jsonResponse(
        { ok: false, code: "P0G1_ACTIVE_ADMIN_REQUIRED", message: "管理员权限已失效，请重新登录。" },
        403,
      );
    }

    const { data: schoolRequestData, error: schoolRequestError } =
      await schoolClient.rpc("school_request_cash_expense_payment_confirmation", {
        p_expense_record_id: expenseRecordId,
        p_cash_user_id: cashAccount.user_id,
        p_cash_account_id: cashAccount.id,
        p_cash_account_name_snapshot: cashAccount.name ?? cashAccount.id,
        p_cash_account_type_snapshot: cashAccount.account_type ?? null,
        p_payment_amount: actualPaymentAmount,
        p_payment_currency: actualPaymentCurrency,
        p_note: note,
        p_exchange_rate: actualPaymentCurrency === originalCurrency ? 1 : exchangeRate,
        p_payment_rounding_mode: actualPaymentAmount === null ? roundingMode : null,
      });

    if (schoolRequestError) {
      return jsonResponse(
        {
          ok: false,
          message: "School Cash expense confirmation request failed",
          details: schoolRequestError.message,
        },
        400,
      );
    }

    const schoolRequest = unwrapSingleRow<SchoolExpenseRequestRow>(
      schoolRequestData as
        | SchoolExpenseRequestRow[]
        | SchoolExpenseRequestRow
        | null,
      "school_request_cash_expense_payment_confirmation",
    );

    if (schoolRequest.request_type !== CASH_REQUEST_TYPE) {
      return jsonResponse(
        { ok: false, message: "School returned unsupported expense Cash request type" },
        400,
      );
    }

    const cashDescription = buildCashExpenseDescription(
      expense,
      schoolRequest.payment_currency,
      Number(schoolRequest.payment_amount),
    );
    const actualPaymentDate = requestedPaymentDate ?? schoolRequest.expense_date;
    const cashPayload = {
      external_source: CASH_EXTERNAL_SOURCE,
      external_event_id: schoolRequest.request_event_id,
      external_reference_type: CASH_REFERENCE_TYPE,
      external_reference_id: schoolRequest.expense_id,
      request_type: schoolRequest.request_type,
      transaction_type: CASH_TRANSACTION_TYPE,
      expense_record_id: schoolRequest.expense_id,
      expense_date: schoolRequest.expense_date,
      actual_payment_date: actualPaymentDate,
      year_month: schoolRequest.year_month,
      expense_category: schoolRequest.expense_category,
      expense_category_label: expenseCategoryLabel(schoolRequest.expense_category),
      source_type: schoolRequest.source_type,
      source_id: schoolRequest.source_id,
      payee_name_snapshot: schoolRequest.payee_name_snapshot,
      description: schoolRequest.description,
      original_currency: schoolRequest.original_currency,
      original_amount: Number(schoolRequest.original_amount),
      original_amount_jpy: schoolRequest.original_amount_jpy === null
        ? null
        : Number(schoolRequest.original_amount_jpy),
      original_amount_cny: schoolRequest.original_amount_cny === null
        ? null
        : Number(schoolRequest.original_amount_cny),
      actual_payment_amount: Number(schoolRequest.payment_amount),
      actual_payment_currency: schoolRequest.payment_currency,
      account_id: schoolRequest.cash_account_id,
      cash_account_name_snapshot: schoolRequest.cash_account_name_snapshot,
      cash_account_type_snapshot: schoolRequest.cash_account_type_snapshot,
      attempt_no: schoolRequest.attempt_no,
      school_expense_status: schoolRequest.expense_status,
      school_message: schoolRequest.message,
      note,
    };

    if (!await requireCurrentActiveAdmin(userScopedSchoolClient, schoolUser.id)) {
      return jsonResponse(
        { ok: false, code: "P0G1_ACTIVE_ADMIN_REQUIRED", message: "管理员权限已失效，未创建 Cash 请求。" },
        403,
      );
    }

    const { data: cashRequestData, error: cashRequestError } =
      await cashClient.rpc("home_create_external_transaction_request", {
        p_user_id: schoolRequest.cash_user_id,
        p_account_id: schoolRequest.cash_account_id,
        p_external_source: CASH_EXTERNAL_SOURCE,
        p_external_event_id: schoolRequest.request_event_id,
        p_external_reference_type: CASH_REFERENCE_TYPE,
        p_external_reference_id: schoolRequest.expense_id,
        p_request_type: schoolRequest.request_type,
        p_transaction_type: CASH_TRANSACTION_TYPE,
        p_transacted_at: actualPaymentDate,
        p_amount: Number(schoolRequest.payment_amount),
        p_idempotency_key: schoolRequest.idempotency_key,
        p_description: cashDescription,
        p_note: note ?? "",
        p_payload_snapshot: cashPayload,
        p_currency: schoolRequest.payment_currency,
      });

    if (cashRequestError) {
      return jsonResponse(
        {
          ok: false,
          expense_id: schoolRequest.expense_id,
          request_event_id: schoolRequest.request_event_id,
          message: "Cash pending request creation failed",
          details: cashRequestError.message,
        },
        502,
      );
    }

    const cashRequest = cashRequestData as CashRequestResult;
    if (!cashRequest?.ok || !cashRequest.request_id) {
      return jsonResponse(
        {
          ok: false,
          expense_id: schoolRequest.expense_id,
          request_event_id: schoolRequest.request_event_id,
          message: cashRequest?.message ?? "Cash pending request was not created",
          cash_status: cashRequest?.status ?? null,
        },
        409,
      );
    }

    if (cashRequest.status !== "pending") {
      return jsonResponse(
        {
          ok: false,
          expense_id: schoolRequest.expense_id,
          request_event_id: schoolRequest.request_event_id,
          cash_request_id: cashRequest.request_id,
          cash_request_status: cashRequest.status ?? null,
          message: "Cash request already exists but is not pending",
        },
        409,
      );
    }

    const { data: submittedData, error: submittedError } =
      await schoolClient.rpc("school_mark_cash_expense_request_submitted", {
        p_expense_record_id: schoolRequest.expense_id,
        p_cash_request_id: cashRequest.request_id,
        p_cash_request_status: cashRequest.status ?? "pending",
      });

    if (submittedError) {
      return jsonResponse(
        {
          ok: false,
          expense_id: schoolRequest.expense_id,
          request_event_id: schoolRequest.request_event_id,
          cash_request_id: cashRequest.request_id,
          cash_request_status: cashRequest.status ?? null,
          message: "Cash request was created but School submitted writeback failed",
          details: submittedError.message,
        },
        502,
      );
    }

    const submitted = unwrapSingleRow<{
      expense_id: string;
      expense_status: string;
      cash_request_id: string;
      cash_request_status: string;
      message: string;
    }>(
      submittedData as
        | {
          expense_id: string;
          expense_status: string;
          cash_request_id: string;
          cash_request_status: string;
          message: string;
        }[]
        | {
          expense_id: string;
          expense_status: string;
          cash_request_id: string;
          cash_request_status: string;
          message: string;
        }
        | null,
      "school_mark_cash_expense_request_submitted",
    );

    return jsonResponse({
      ok: true,
      expense_id: submitted.expense_id,
      request_event_id: schoolRequest.request_event_id,
      cash_request_id: submitted.cash_request_id,
      status: submitted.expense_status,
      cash_request_status: submitted.cash_request_status,
      currency: schoolRequest.payment_currency,
      amount: Number(schoolRequest.payment_amount),
      attempt_no: schoolRequest.attempt_no,
      cash_inserted: cashRequest.inserted ?? null,
      message: submitted.message,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ ok: false, message }, 500);
  }
});
