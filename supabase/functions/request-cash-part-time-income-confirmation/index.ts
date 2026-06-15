// request-cash-part-time-income-confirmation
//
// Page-triggered School -> Cash pending request bridge for external part-time
// work income. The School settlement remains locked in JPY; this function only
// creates a Cash pending income request using the actual received amount and
// currency supplied by the user.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  action?: string;
  income_request_id?: string;
  cash_account_id?: string;
  actual_received_amount?: number | string;
  actual_received_currency?: string;
  exchange_rate?: number | string | null;
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

type SchoolContextRow = {
  income_request_id: string;
  settlement_id: string;
  year_month: string;
  workplace_name: string;
  teacher_name: string;
  original_amount_jpy: number | string;
  income_request_status: string;
  cash_request_id: string | null;
  cash_request_status: string | null;
  cash_transaction_id: string | null;
  actual_received_amount: number | string | null;
  actual_received_currency: string | null;
  actual_exchange_rate: number | string | null;
  cash_attempt_no: number;
  request_type: string;
  transaction_type: string;
  idempotency_key: string;
  memo: string | null;
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
const CASH_REFERENCE_TYPE = "school_part_time_work_income_requests";
const CASH_REQUEST_TYPE = "part_time_work_income_received";
const CASH_TRANSACTION_TYPE = "income";
const SUPPORTED_CURRENCIES = new Set(["JPY", "CNY"]);

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
  const amount = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error(`${fieldName} must be a positive number`);
  }
  return Math.round(amount * 100) / 100;
}

function optionalPositiveNumber(value: unknown, fieldName: string): number | null {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const amount = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error(`${fieldName} must be a positive number`);
  }
  return amount;
}

function requireCurrency(value: unknown): "JPY" | "CNY" {
  const currency = typeof value === "string" ? value.trim().toUpperCase() : "";
  if (!SUPPORTED_CURRENCIES.has(currency)) {
    throw new Error("actual_received_currency must be JPY or CNY");
  }

  return currency as "JPY" | "CNY";
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

function createSupabaseClient(urlEnv: string, keyEnv: string) {
  return createClient(getRequiredEnv(urlEnv), getRequiredEnv(keyEnv), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
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

function buildDescription(
  context: SchoolContextRow,
  actualAmount: number,
  actualCurrency: "JPY" | "CNY",
): string {
  return [
    context.workplace_name,
    context.year_month,
    "外部塾打工收入",
    `JPY工资总额${Number(context.original_amount_jpy).toLocaleString("ja-JP")}`,
    `实际到账${actualAmount.toLocaleString("ja-JP")} ${actualCurrency}`,
  ].join(" / ");
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ ok: false, message: "Only POST is supported" }, 405);
  }

  try {
    const authorization = request.headers.get("authorization") ?? "";
    const body = (await request.json()) as RequestBody;
    const schoolClient = createSupabaseClient(
      "SCHOOL_SUPABASE_URL",
      "SCHOOL_SERVICE_ROLE_KEY",
    );
    const cashClient = createSupabaseClient(
      "CASH_SUPABASE_URL",
      "CASH_SERVICE_ROLE_KEY",
    );

    const schoolUser = await requireSchoolUser(schoolClient, authorization);
    if (!schoolUser) {
      return jsonResponse(
        { ok: false, message: "Invalid School authorization token" },
        401,
      );
    }

    const action = typeof body.action === "string" ? body.action.trim() : "";
    const eligibleAccounts = await listEligibleAccounts(cashClient);

    if (action === "list_eligible_accounts") {
      return jsonResponse({
        ok: true,
        accounts: eligibleAccounts.map((account) => ({
          id: account.id,
          name: account.name,
          currency: account.currency,
          account_type: account.account_type,
          is_active: account.is_active,
          allow_school_requests: account.allow_school_requests,
        })),
      });
    }

    const incomeRequestId = requireUuid(
      body.income_request_id,
      "income_request_id",
    );
    const cashAccountId = requireUuid(body.cash_account_id, "cash_account_id");
    const actualReceivedAmount = requirePositiveNumber(
      body.actual_received_amount,
      "actual_received_amount",
    );
    const actualReceivedCurrency = requireCurrency(body.actual_received_currency);
    const exchangeRate = optionalPositiveNumber(body.exchange_rate, "exchange_rate");
    const note = optionalText(body.note);

    if (actualReceivedCurrency === "CNY" && exchangeRate === null) {
      return jsonResponse(
        { ok: false, message: "CNY actual received amount requires exchange_rate" },
        400,
      );
    }

    if (actualReceivedCurrency === "JPY" && exchangeRate !== null && exchangeRate !== 1) {
      return jsonResponse(
        { ok: false, message: "JPY actual received exchange_rate must be empty or 1" },
        400,
      );
    }

    const cashAccount = eligibleAccounts.find((account) => account.id === cashAccountId);
    if (!cashAccount) {
      return jsonResponse(
        { ok: false, message: "Selected Cash account is not School-eligible" },
        400,
      );
    }

    if (cashAccount.currency !== actualReceivedCurrency) {
      return jsonResponse(
        {
          ok: false,
          message: "Selected Cash account currency does not match actual_received_currency",
          account_currency: cashAccount.currency,
          actual_received_currency: actualReceivedCurrency,
        },
        400,
      );
    }

    const { data: contextData, error: contextError } = await schoolClient.rpc(
      "school_get_part_time_work_cash_request_context",
      { p_income_request_id: incomeRequestId },
    );

    if (contextError) {
      return jsonResponse(
        {
          ok: false,
          message: "School part-time work income request lookup failed",
          details: contextError.message,
        },
        400,
      );
    }

    const context = unwrapSingleRow<SchoolContextRow>(
      contextData as SchoolContextRow[] | SchoolContextRow | null,
      "school_get_part_time_work_cash_request_context",
    );

    if (context.cash_transaction_id || context.income_request_status === "synced") {
      return jsonResponse(
        { ok: false, message: "Part-time work income request is already synced" },
        409,
      );
    }

    if (
      context.cash_request_id &&
      context.income_request_status === "awaiting_cash_confirmation"
    ) {
      return jsonResponse(
        { ok: false, message: "Part-time work income request already has an active Cash request" },
        409,
      );
    }

    if (!["pending_cash_request", "cash_rejected", "failed", "blocked"].includes(context.income_request_status)) {
      return jsonResponse(
        {
          ok: false,
          message: `Part-time work income request is not requestable: ${context.income_request_status}`,
        },
        409,
      );
    }

    const description = buildDescription(
      context,
      actualReceivedAmount,
      actualReceivedCurrency,
    );
    const cashPayload = {
      external_source: CASH_EXTERNAL_SOURCE,
      external_event_id: context.income_request_id,
      external_reference_type: CASH_REFERENCE_TYPE,
      external_reference_id: context.income_request_id,
      request_type: CASH_REQUEST_TYPE,
      transaction_type: CASH_TRANSACTION_TYPE,
      year_month: context.year_month,
      workplace_name: context.workplace_name,
      teacher_name: context.teacher_name,
      settlement_id: context.settlement_id,
      income_request_id: context.income_request_id,
      original_amount_jpy: Number(context.original_amount_jpy),
      actual_received_amount: actualReceivedAmount,
      actual_received_currency: actualReceivedCurrency,
      exchange_rate: exchangeRate,
      exchange_rate_cny_per_jpy: actualReceivedCurrency === "CNY" ? exchangeRate : null,
      account_id: cashAccount.id,
      cash_account_name_snapshot: cashAccount.name ?? cashAccount.id,
      cash_account_type_snapshot: cashAccount.account_type ?? null,
      school_sync_status: context.income_request_status,
      school_message: "Part-time work income Cash confirmation request",
      note,
    };

    const { data: cashRequestData, error: cashRequestError } =
      await cashClient.rpc("home_create_external_transaction_request", {
        p_user_id: cashAccount.user_id,
        p_account_id: cashAccount.id,
        p_external_source: CASH_EXTERNAL_SOURCE,
        p_external_event_id: context.income_request_id,
        p_external_reference_type: CASH_REFERENCE_TYPE,
        p_external_reference_id: context.income_request_id,
        p_request_type: CASH_REQUEST_TYPE,
        p_transaction_type: CASH_TRANSACTION_TYPE,
        p_transacted_at: new Date().toISOString().slice(0, 10),
        p_amount: actualReceivedAmount,
        p_idempotency_key: context.idempotency_key,
        p_description: description,
        p_note: note ?? "",
        p_payload_snapshot: cashPayload,
        p_currency: actualReceivedCurrency,
      });

    if (cashRequestError) {
      return jsonResponse(
        {
          ok: false,
          income_request_id: context.income_request_id,
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
          income_request_id: context.income_request_id,
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
          income_request_id: context.income_request_id,
          cash_request_id: cashRequest.request_id,
          cash_request_status: cashRequest.status ?? null,
          message: "Cash request already exists but is not pending",
        },
        409,
      );
    }

    const { data: submittedData, error: submittedError } =
      await schoolClient.rpc("school_mark_part_time_work_cash_request_submitted", {
        p_income_request_id: context.income_request_id,
        p_actual_received_amount: actualReceivedAmount,
        p_actual_received_currency: actualReceivedCurrency,
        p_exchange_rate: exchangeRate,
        p_cash_user_id: cashAccount.user_id,
        p_cash_account_id: cashAccount.id,
        p_cash_account_name_snapshot: cashAccount.name ?? cashAccount.id,
        p_cash_account_type_snapshot: cashAccount.account_type ?? null,
        p_cash_request_id: cashRequest.request_id,
        p_cash_request_status: cashRequest.status ?? "pending",
        p_note: note,
      });

    if (submittedError) {
      return jsonResponse(
        {
          ok: false,
          income_request_id: context.income_request_id,
          cash_request_id: cashRequest.request_id,
          message: "School part-time work Cash request submitted writeback failed",
          details: submittedError.message,
        },
        502,
      );
    }

    const submitted = unwrapSingleRow<Record<string, unknown>>(
      submittedData as Record<string, unknown>[] | Record<string, unknown> | null,
      "school_mark_part_time_work_cash_request_submitted",
    );

    return jsonResponse({
      ok: true,
      income_request_id: context.income_request_id,
      settlement_id: context.settlement_id,
      cash_request_id: cashRequest.request_id,
      cash_request_status: cashRequest.status,
      amount: actualReceivedAmount,
      currency: actualReceivedCurrency,
      original_amount_jpy: Number(context.original_amount_jpy),
      cash_inserted: cashRequest.inserted ?? null,
      school: submitted,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ ok: false, message }, 500);
  }
});
