// request-cash-expense-confirmation
//
// Page-triggered School -> Cash pending request bridge for canonical expense
// records. This function only creates a Cash pending request and records the
// submitted request id on School. It must not approve/reject Cash requests,
// create Cash transactions, or mutate legacy school_payment_requests.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  buildCashCreateRpcPayload,
  buildCashFixedCreateRpcPayload,
  buildSchoolExpenseCashEvidence,
  buildSchoolExpenseFixedCashEvidence,
} from "../_shared/expense-cash-attempt-v2.js";

type RequestBody = {
  expense_record_id?: string;
  payment_route?: string;
  card_instrument_id?: string;
  charge_date?: string;
  cash_account_id?: string;
  actual_payment_amount?: number | string;
  actual_payment_currency?: string;
  actual_payment_date?: string;
  exchange_rate?: number | string | null;
  rounding_mode?: string | null;
  note?: string | null;
};

type HomeFixedScheduleRow = {
  cash_user_id: string;
  card_instrument_id: string;
  settlement_currency: string;
  cutoff_day: number;
  cutoff_inclusive: boolean;
  suggested_fixed_month: string;
  target_fixed_month: string;
  funding_date: string;
  route_enabled: boolean;
};

type SchoolFixedExpenseRequestRow = {
  expense_id: string;
  request_event_id: string;
  attempt_no: number;
  idempotency_key: string;
  request_type: string;
  payment_route: string;
  expense_status: string;
  settlement_amount: number | string;
  settlement_currency: string;
  cash_user_id: string;
  card_instrument_id: string;
  charge_date: string;
  suggested_fixed_month: string;
  target_fixed_month: string;
  funding_date: string;
  cash_request_id: string | null;
  cash_request_status: string | null;
  attempt_id: string;
  attempt_status: string;
  attempt_version: number;
  request_payload_fingerprint: string;
  cash_description: string;
  cash_payload_snapshot: Record<string, unknown>;
  message: string;
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
  actual_payment_date: string;
  cash_request_id: string | null;
  cash_request_status: string | null;
  attempt_id: string;
  attempt_status: string;
  attempt_version: number;
  request_payload_fingerprint: string;
  cash_description: string;
  cash_payload_snapshot: Record<string, unknown>;
  message: string;
};

type CashRequestEvidenceRow = {
  id: string;
  external_source: string;
  external_event_id: string;
  external_reference_type: string;
  external_reference_id: string;
  request_type: string;
  transaction_type: string;
  currency: string;
  amount: number | string;
  account_id: string;
  transacted_at: string;
  status: string;
  idempotency_key: string;
  payload_snapshot: Record<string, unknown>;
  payment_route?: string;
  card_instrument_id?: string | null;
  charge_date?: string | null;
  suggested_fixed_month?: string | null;
  target_fixed_month?: string | null;
  funding_account_id?: string | null;
  fixed_projection_id?: string | null;
  created_transaction_id?: string | null;
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
    const paymentRoute = optionalText(body.payment_route) ?? "immediate_account";
    if (!["immediate_account", "fixed_credit_card"].includes(paymentRoute)) {
      return jsonResponse(
        { ok: false, message: "payment_route must be immediate_account or fixed_credit_card" },
        400,
      );
    }

    if (paymentRoute === "fixed_credit_card") {
      const cardInstrumentId = requireUuid(
        body.card_instrument_id,
        "card_instrument_id",
      );
      const chargeDate = optionalDate(body.charge_date, "charge_date");
      if (!chargeDate) {
        return jsonResponse({ ok: false, message: "charge_date is required" }, 400);
      }

      const { data: scheduleData, error: scheduleError } = await cashClient.rpc(
        "home_get_school_fixed_card_schedule",
        {
          p_card_instrument_id: cardInstrumentId,
          p_charge_date: chargeDate,
        },
      );
      if (scheduleError) {
        return jsonResponse(
          {
            ok: false,
            code: "HOME_FIXED_CARD_SCHEDULE_FAILED",
            message: "Cash fixed-card schedule lookup failed",
            details: scheduleError.message,
          },
          400,
        );
      }
      const schedule = unwrapSingleRow<HomeFixedScheduleRow>(
        scheduleData as HomeFixedScheduleRow[] | HomeFixedScheduleRow | null,
        "home_get_school_fixed_card_schedule",
      );
      if (!schedule.route_enabled) {
        return jsonResponse(
          {
            ok: false,
            code: "HOME_FIXED_CARD_ROUTE_DISABLED",
            message: "School fixed credit-card route is disabled.",
          },
          409,
        );
      }

      if (!await requireCurrentActiveAdmin(userScopedSchoolClient, schoolUser.id)) {
        return jsonResponse(
          { ok: false, code: "P0G1_ACTIVE_ADMIN_REQUIRED", message: "管理员权限已失效，未创建固定支付attempt。" },
          403,
        );
      }

      const { data: fixedPrepareData, error: fixedPrepareError } =
        await schoolClient.rpc(
          "school_request_cash_fixed_expense_payment_confirmation_v2",
          {
            p_expense_record_id: expenseRecordId,
            p_cash_user_id: schedule.cash_user_id,
            p_card_instrument_id: schedule.card_instrument_id,
            p_charge_date: chargeDate,
            p_suggested_fixed_month: schedule.suggested_fixed_month,
            p_target_fixed_month: schedule.target_fixed_month,
            p_funding_date: schedule.funding_date,
            p_note: optionalText(body.note),
            p_external_source: CASH_EXTERNAL_SOURCE,
            p_external_reference_type: CASH_REFERENCE_TYPE,
            p_external_reference_id: expenseRecordId,
            p_request_type: CASH_REQUEST_TYPE,
            p_transaction_type: CASH_TRANSACTION_TYPE,
          },
        );
      if (fixedPrepareError) {
        return jsonResponse(
          {
            ok: false,
            code: fixedPrepareError.message.includes(
                "SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED"
              )
              ? "SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED"
              : "SCHOOL_FIXED_PREPARE_FAILED",
            message: "School fixed Cash expense preparation failed",
            details: fixedPrepareError.message,
          },
          400,
        );
      }
      const fixedPrepare = unwrapSingleRow<SchoolFixedExpenseRequestRow>(
        fixedPrepareData as
          | SchoolFixedExpenseRequestRow[]
          | SchoolFixedExpenseRequestRow
          | null,
        "school_request_cash_fixed_expense_payment_confirmation_v2",
      );
      const fixedCreatePayload = buildCashFixedCreateRpcPayload(fixedPrepare);

      if (!await requireCurrentActiveAdmin(userScopedSchoolClient, schoolUser.id)) {
        return jsonResponse(
          { ok: false, code: "P0G1_ACTIVE_ADMIN_REQUIRED", message: "管理员权限已失效，未创建 Cash fixed request。" },
          403,
        );
      }

      const { data: fixedRequestData, error: fixedRequestError } =
        await cashClient.rpc(
          "home_create_external_fixed_transaction_request",
          fixedCreatePayload,
        );
      if (fixedRequestError) {
        return jsonResponse(
          {
            ok: false,
            expense_id: fixedPrepare.expense_id,
            request_event_id: fixedPrepare.request_event_id,
            message: "Cash fixed pending request creation failed",
            details: fixedRequestError.message,
          },
          502,
        );
      }
      const fixedRequest = fixedRequestData as CashRequestResult;
      if (!fixedRequest?.ok || !fixedRequest.request_id) {
        return jsonResponse(
          {
            ok: false,
            expense_id: fixedPrepare.expense_id,
            request_event_id: fixedPrepare.request_event_id,
            message: fixedRequest?.message ?? "Cash fixed pending request was not created",
            cash_status: fixedRequest?.status ?? null,
          },
          409,
        );
      }
      if (fixedRequest.status !== "pending") {
        return jsonResponse(
          {
            ok: false,
            expense_id: fixedPrepare.expense_id,
            request_event_id: fixedPrepare.request_event_id,
            cash_request_id: fixedRequest.request_id,
            cash_request_status: fixedRequest.status ?? null,
            message: "Cash fixed request already exists but is not pending",
          },
          409,
        );
      }

      const { data: fixedEvidenceData, error: fixedEvidenceError } =
        await cashClient
          .from("home_external_transaction_requests")
          .select([
            "id", "external_source", "external_event_id", "external_reference_type",
            "external_reference_id", "request_type", "transaction_type", "currency",
            "amount", "account_id", "transacted_at", "status", "idempotency_key",
            "payload_snapshot", "payment_route", "card_instrument_id", "charge_date",
            "suggested_fixed_month", "target_fixed_month", "funding_account_id",
            "fixed_projection_id", "created_transaction_id",
          ].join(","))
          .eq("id", fixedRequest.request_id)
          .single();
      if (fixedEvidenceError || !fixedEvidenceData) {
        return jsonResponse(
          {
            ok: false,
            expense_id: fixedPrepare.expense_id,
            request_event_id: fixedPrepare.request_event_id,
            cash_request_id: fixedRequest.request_id,
            message: "Cash fixed request was created but complete evidence lookup failed",
            details: fixedEvidenceError?.message ?? null,
          },
          502,
        );
      }

      const fixedSubmittedEvidence = buildSchoolExpenseFixedCashEvidence(
        fixedEvidenceData as CashRequestEvidenceRow,
      );
      const { data: fixedSubmittedData, error: fixedSubmittedError } =
        await schoolClient.rpc(
          "school_mark_cash_fixed_expense_request_submitted_v2",
          fixedSubmittedEvidence,
        );
      if (fixedSubmittedError) {
        return jsonResponse(
          {
            ok: false,
            expense_id: fixedPrepare.expense_id,
            request_event_id: fixedPrepare.request_event_id,
            cash_request_id: fixedRequest.request_id,
            message: "Cash fixed request was created but School submitted writeback failed",
            details: fixedSubmittedError.message,
          },
          502,
        );
      }
      const fixedSubmitted = unwrapSingleRow<Record<string, unknown>>(
        fixedSubmittedData as Record<string, unknown>[] | Record<string, unknown> | null,
        "school_mark_cash_fixed_expense_request_submitted_v2",
      );

      return jsonResponse({
        ok: true,
        payment_route: "fixed_credit_card",
        expense_id: fixedPrepare.expense_id,
        request_event_id: fixedPrepare.request_event_id,
        cash_request_id: fixedRequest.request_id,
        status: fixedSubmitted.expense_status,
        cash_request_status: fixedSubmitted.cash_request_status,
        currency: fixedPrepare.settlement_currency,
        amount: Number(fixedPrepare.settlement_amount),
        attempt_no: fixedPrepare.attempt_no,
        cash_inserted: fixedRequest.inserted ?? null,
        message: fixedSubmitted.message,
      });
    }

    const cashAccountId = requireUuid(body.cash_account_id, "cash_account_id");
    const actualPaymentAmount = optionalPositiveNumber(
      body.actual_payment_amount,
      "actual_payment_amount",
    );
    const actualPaymentCurrency = requireCurrency(body.actual_payment_currency);
    const exchangeRate = optionalPositiveNumber(body.exchange_rate, "exchange_rate");
    const roundingMode = optionalText(body.rounding_mode);
    const requestedPaymentDate = optionalDate(body.actual_payment_date, "actual_payment_date");
    if (!requestedPaymentDate) {
      return jsonResponse(
        { ok: false, message: "actual_payment_date is required" },
        400,
      );
    }
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
      await schoolClient.rpc("school_request_cash_expense_payment_confirmation_v2", {
        p_expense_record_id: expenseRecordId,
        p_cash_user_id: cashAccount.user_id,
        p_cash_account_id: cashAccount.id,
        p_cash_account_name_snapshot: cashAccount.name ?? cashAccount.id,
        p_actual_payment_date: requestedPaymentDate,
        p_cash_account_type_snapshot: cashAccount.account_type ?? null,
        p_payment_amount: actualPaymentAmount,
        p_payment_currency: actualPaymentCurrency,
        p_note: note,
        p_exchange_rate: actualPaymentCurrency === originalCurrency ? 1 : exchangeRate,
        p_payment_rounding_mode: actualPaymentAmount === null ? roundingMode : null,
        p_external_source: CASH_EXTERNAL_SOURCE,
        p_external_reference_type: CASH_REFERENCE_TYPE,
        p_external_reference_id: expenseRecordId,
        p_request_type: CASH_REQUEST_TYPE,
        p_transaction_type: CASH_TRANSACTION_TYPE,
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
      "school_request_cash_expense_payment_confirmation_v2",
    );

    if (schoolRequest.request_type !== CASH_REQUEST_TYPE) {
      return jsonResponse(
        { ok: false, message: "School returned unsupported expense Cash request type" },
        400,
      );
    }

    const cashCreatePayload = buildCashCreateRpcPayload(schoolRequest);

    if (!await requireCurrentActiveAdmin(userScopedSchoolClient, schoolUser.id)) {
      return jsonResponse(
        { ok: false, code: "P0G1_ACTIVE_ADMIN_REQUIRED", message: "管理员权限已失效，未创建 Cash 请求。" },
        403,
      );
    }

    const { data: cashRequestData, error: cashRequestError } =
      await cashClient.rpc("home_create_external_transaction_request", cashCreatePayload);

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

    const { data: cashEvidenceData, error: cashEvidenceError } = await cashClient
      .from("home_external_transaction_requests")
      .select([
        "id", "external_source", "external_event_id", "external_reference_type",
        "external_reference_id", "request_type", "transaction_type", "currency",
        "amount", "account_id", "transacted_at", "status", "idempotency_key",
        "payload_snapshot",
      ].join(","))
      .eq("id", cashRequest.request_id)
      .single();

    if (cashEvidenceError || !cashEvidenceData) {
      return jsonResponse(
        {
          ok: false,
          expense_id: schoolRequest.expense_id,
          request_event_id: schoolRequest.request_event_id,
          cash_request_id: cashRequest.request_id,
          message: "Cash request was created but complete evidence lookup failed",
          details: cashEvidenceError?.message ?? null,
        },
        502,
      );
    }

    const submittedEvidence = buildSchoolExpenseCashEvidence(
      cashEvidenceData as CashRequestEvidenceRow,
    );
    const { data: submittedData, error: submittedError } =
      await schoolClient.rpc("school_mark_cash_expense_request_submitted_v2", submittedEvidence);

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
      "school_mark_cash_expense_request_submitted_v2",
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
