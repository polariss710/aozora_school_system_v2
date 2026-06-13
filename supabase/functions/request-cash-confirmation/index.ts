// request-cash-confirmation
//
// Page-triggered School -> Cash pending request bridge for Cash linkage v2.
// This function creates a Cash pending request only. It must not create a Cash
// transaction and must not mark the School payment request paid.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  action?: string;
  payment_request_id?: string;
  cash_account_id?: string;
  payment_currency?: string;
  exchange_rate?: number | string | null;
  payment_amount?: number | string | null;
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

type SchoolRequestRow = {
  payment_request_id: string;
  linkage_event_id: string;
  sync_status: string;
  idempotency_key: string;
  amount: number | string;
  currency: string;
  school_amount_jpy: number | string;
  payment_currency: string;
  payment_exchange_rate: number | string;
  payment_amount: number | string;
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
const CASH_REFERENCE_TYPE = "school_payment_requests";
const CASH_REQUEST_TYPE = "teacher_wage_payment_confirm";
const CASH_TRANSACTION_TYPE = "expense";
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

function requireCurrency(value: unknown): "JPY" | "CNY" {
  const currency = typeof value === "string" ? value.trim().toUpperCase() : "";
  if (!SUPPORTED_CURRENCIES.has(currency)) {
    throw new Error("payment_currency must be JPY or CNY");
  }

  return currency as "JPY" | "CNY";
}

function optionalPositiveNumber(value: unknown, fieldName: string): number | null {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const numberValue = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(numberValue) || numberValue <= 0) {
    throw new Error(`${fieldName} must be a positive number`);
  }

  return numberValue;
}

function todayIsoDate(): string {
  return new Date().toISOString().slice(0, 10);
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

async function requireSchoolUser(schoolClient: ReturnType<typeof createClient>, authorization: string) {
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return null;
  }

  const bearerToken = authorization.replace(/^bearer\s+/i, "");
  const { data: userData, error: userError } = await schoolClient.auth.getUser(bearerToken);
  if (userError || !userData.user) {
    return null;
  }

  return userData.user;
}

async function listEligibleAccounts(cashClient: ReturnType<typeof createClient>): Promise<CashAccountRow[]> {
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

    const paymentRequestId = requireUuid(
      body.payment_request_id,
      "payment_request_id",
    );
    const cashAccountId = requireUuid(body.cash_account_id, "cash_account_id");
    const paymentCurrency = requireCurrency(body.payment_currency);
    const exchangeRate = optionalPositiveNumber(body.exchange_rate, "exchange_rate");
    const requestedPaymentAmount = optionalPositiveNumber(
      body.payment_amount,
      "payment_amount",
    );
    const note =
      typeof body.note === "string" && body.note.trim()
        ? body.note.trim()
        : null;

    const cashAccount = eligibleAccounts.find((account) => account.id === cashAccountId);
    if (!cashAccount) {
      return jsonResponse(
        { ok: false, message: "Selected Cash account is not School-eligible" },
        400,
      );
    }

    if (cashAccount.currency !== paymentCurrency) {
      return jsonResponse(
        {
          ok: false,
          message: "Selected Cash account currency does not match payment_currency",
          account_currency: cashAccount.currency,
          payment_currency: paymentCurrency,
        },
        400,
      );
    }

    if (paymentCurrency === "CNY" && exchangeRate === null) {
      return jsonResponse(
        { ok: false, message: "CNY payment requires exchange_rate" },
        400,
      );
    }

    if (paymentCurrency === "JPY" && exchangeRate !== null && exchangeRate !== 1) {
      return jsonResponse(
        { ok: false, message: "JPY payment exchange_rate must be empty or 1" },
        400,
      );
    }

    const { data: schoolRequestData, error: schoolRequestError } =
      await schoolClient.rpc("school_request_cash_payment_confirmation", {
        p_payment_request_id: paymentRequestId,
        p_cash_user_id: cashAccount.user_id,
        p_cash_account_id: cashAccount.id,
        p_cash_account_name_snapshot: cashAccount.name ?? cashAccount.id,
        p_cash_account_type_snapshot: cashAccount.account_type ?? null,
        p_payment_currency: paymentCurrency,
        p_exchange_rate: paymentCurrency === "JPY" ? 1 : exchangeRate,
        p_payment_amount: requestedPaymentAmount,
        p_note: note,
      });

    if (schoolRequestError) {
      return jsonResponse(
        {
          ok: false,
          message: "School Cash confirmation request failed",
          details: schoolRequestError.message,
        },
        400,
      );
    }

    const schoolRequest = unwrapSingleRow<SchoolRequestRow>(
      schoolRequestData as SchoolRequestRow[] | SchoolRequestRow | null,
      "school_request_cash_payment_confirmation",
    );

    const amount = Number(schoolRequest.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      return jsonResponse(
        { ok: false, message: "School request amount must be greater than 0" },
        400,
      );
    }

    const cashPayload = {
      external_source: CASH_EXTERNAL_SOURCE,
      external_event_id: schoolRequest.linkage_event_id,
      external_reference_type: CASH_REFERENCE_TYPE,
      external_reference_id: schoolRequest.payment_request_id,
      request_type: CASH_REQUEST_TYPE,
      transaction_type: CASH_TRANSACTION_TYPE,
      currency: schoolRequest.currency,
      amount,
      account_id: schoolRequest.cash_account_id,
      cash_account_name_snapshot: schoolRequest.cash_account_name_snapshot,
      cash_account_type_snapshot: schoolRequest.cash_account_type_snapshot,
      school_amount_jpy: Number(schoolRequest.school_amount_jpy),
      payment_currency: schoolRequest.payment_currency,
      payment_exchange_rate: Number(schoolRequest.payment_exchange_rate),
      payment_amount: Number(schoolRequest.payment_amount),
      school_sync_status: schoolRequest.sync_status,
      school_message: schoolRequest.message,
    };

    const { data: cashRequestData, error: cashRequestError } =
      await cashClient.rpc("home_create_external_transaction_request", {
        p_user_id: schoolRequest.cash_user_id,
        p_account_id: schoolRequest.cash_account_id,
        p_external_source: CASH_EXTERNAL_SOURCE,
        p_external_event_id: schoolRequest.linkage_event_id,
        p_external_reference_type: CASH_REFERENCE_TYPE,
        p_external_reference_id: schoolRequest.payment_request_id,
        p_request_type: CASH_REQUEST_TYPE,
        p_transaction_type: CASH_TRANSACTION_TYPE,
        p_transacted_at: todayIsoDate(),
        p_amount: amount,
        p_idempotency_key: schoolRequest.idempotency_key,
        p_description: "School teacher wage payment confirmation request",
        p_note: note ?? "",
        p_payload_snapshot: cashPayload,
        p_currency: schoolRequest.currency,
      });

    if (cashRequestError) {
      return jsonResponse(
        {
          ok: false,
          payment_request_id: schoolRequest.payment_request_id,
          linkage_event_id: schoolRequest.linkage_event_id,
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
          payment_request_id: schoolRequest.payment_request_id,
          linkage_event_id: schoolRequest.linkage_event_id,
          message: cashRequest?.message ??
            "Cash pending request was not created",
          cash_status: cashRequest?.status ?? null,
        },
        409,
      );
    }

    if (cashRequest.status !== "pending") {
      return jsonResponse(
        {
          ok: false,
          payment_request_id: schoolRequest.payment_request_id,
          linkage_event_id: schoolRequest.linkage_event_id,
          cash_request_id: cashRequest.request_id,
          cash_request_status: cashRequest.status ?? null,
          message: "Cash request already exists but is not pending",
        },
        409,
      );
    }

    const { data: submittedData, error: submittedError } =
      await schoolClient.rpc("school_mark_personal_cash_payment_request_submitted", {
        p_event_id: schoolRequest.linkage_event_id,
        p_cash_request_id: cashRequest.request_id,
        p_cash_request_status: cashRequest.status ?? "pending",
      });

    if (submittedError) {
      return jsonResponse(
        {
          ok: false,
          payment_request_id: schoolRequest.payment_request_id,
          linkage_event_id: schoolRequest.linkage_event_id,
          cash_request_id: cashRequest.request_id,
          cash_request_status: cashRequest.status ?? null,
          message: "Cash request was created but School submitted writeback failed",
          details: submittedError.message,
        },
        502,
      );
    }

    const submitted = unwrapSingleRow<{
      payment_request_id: string;
      linkage_event_id: string;
      sync_status: string;
      cash_request_id: string;
      cash_request_status: string;
      message: string;
    }>(
      submittedData as
        | {
          payment_request_id: string;
          linkage_event_id: string;
          sync_status: string;
          cash_request_id: string;
          cash_request_status: string;
          message: string;
        }[]
        | {
          payment_request_id: string;
          linkage_event_id: string;
          sync_status: string;
          cash_request_id: string;
          cash_request_status: string;
          message: string;
        }
        | null,
      "school_mark_personal_cash_payment_request_submitted",
    );

    return jsonResponse({
      ok: true,
      payment_request_id: submitted.payment_request_id,
      linkage_event_id: submitted.linkage_event_id,
      cash_request_id: submitted.cash_request_id,
      status: submitted.sync_status,
      cash_request_status: submitted.cash_request_status,
      currency: schoolRequest.currency,
      amount,
      school_amount_jpy: Number(schoolRequest.school_amount_jpy),
      payment_exchange_rate: Number(schoolRequest.payment_exchange_rate),
      cash_inserted: cashRequest.inserted ?? null,
      message: submitted.message,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ ok: false, message }, 500);
  }
});
