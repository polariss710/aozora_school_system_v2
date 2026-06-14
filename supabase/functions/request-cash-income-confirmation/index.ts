// request-cash-income-confirmation
//
// Page-triggered School -> Cash pending request bridge for income records.
// This function creates a School pending income record and a Cash pending
// external request only. It must not approve/reject Cash requests, create Cash
// transactions, change Cash balances, or mark the School income confirmed.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  income_date?: string;
  settlement_month?: string;
  business_entity_id?: string;
  student_id?: string;
  cash_account_id?: string;
  amount?: number | string;
  income_category?: string;
  description?: string | null;
  currency?: string;
  exchange_rate?: number | string | null;
  payment_method?: string | null;
  is_taxable_income?: boolean;
  tax_category?: string | null;
  receipt_status?: string | null;
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

type SchoolIncomeRequestRow = {
  income_id: string;
  linkage_event_id: string;
  sync_status: string;
  attempt_no: number;
  idempotency_key: string;
  request_type: string;
  amount: number | string;
  currency: string;
  payment_currency: string;
  payment_exchange_rate: number | string | null;
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
const CASH_REFERENCE_TYPE = "school_income_records";
const CASH_TRANSACTION_TYPE = "income";
const CASH_ELIGIBLE_ACCOUNT_NAMES = new Set([
  "余额宝",
  "日元现金",
  "日元三菱卡",
  "日元乐天卡",
]);
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
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{12}$/i;

  if (!uuidPattern.test(trimmed)) {
    throw new Error(`${fieldName} must be a UUID`);
  }

  return trimmed;
}

function requireDate(value: unknown, fieldName: string): string {
  const text = typeof value === "string" ? value.trim() : "";
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(text)) {
    throw new Error(`${fieldName} must be YYYY-MM-DD`);
  }

  return text;
}

function requireSettlementMonth(value: unknown): string {
  const text = typeof value === "string" ? value.trim() : "";
  if (!/^[0-9]{4}-(0[1-9]|1[0-2])$/.test(text)) {
    throw new Error("settlement_month must be YYYY-MM");
  }

  return text;
}

function requireCurrency(value: unknown): "JPY" | "CNY" {
  const currency = typeof value === "string" ? value.trim().toUpperCase() : "";
  if (!SUPPORTED_CURRENCIES.has(currency)) {
    throw new Error("currency must be JPY or CNY");
  }

  return currency as "JPY" | "CNY";
}

function requirePositiveNumber(value: unknown, fieldName: string): number {
  const numberValue = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(numberValue) || numberValue <= 0) {
    throw new Error(`${fieldName} must be a positive number`);
  }

  return numberValue;
}

function optionalPositiveNumber(value: unknown, fieldName: string): number | null {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  return requirePositiveNumber(value, fieldName);
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

    const incomeDate = requireDate(body.income_date, "income_date");
    const settlementMonth = requireSettlementMonth(body.settlement_month);
    const businessEntityId = requireUuid(
      body.business_entity_id,
      "business_entity_id",
    );
    const studentId = requireUuid(body.student_id, "student_id");
    const cashAccountId = requireUuid(body.cash_account_id, "cash_account_id");
    const amount = requirePositiveNumber(body.amount, "amount");
    const currency = requireCurrency(body.currency);
    const exchangeRate = optionalPositiveNumber(body.exchange_rate, "exchange_rate");

    if (currency === "JPY" && exchangeRate !== null && exchangeRate !== 1) {
      return jsonResponse(
        { ok: false, message: "JPY income exchange_rate must be empty or 1" },
        400,
      );
    }

    const eligibleAccounts = await listEligibleAccounts(cashClient);
    const cashAccount = eligibleAccounts.find((account) => (
      account.id === cashAccountId &&
      CASH_ELIGIBLE_ACCOUNT_NAMES.has(account.name ?? "")
    ));

    if (!cashAccount) {
      return jsonResponse(
        { ok: false, message: "Selected Cash account is not School-eligible" },
        400,
      );
    }

    if (cashAccount.currency !== currency) {
      return jsonResponse(
        {
          ok: false,
          message: "Selected Cash account currency does not match income currency",
          account_currency: cashAccount.currency,
          income_currency: currency,
        },
        400,
      );
    }

    const { data: schoolRequestData, error: schoolRequestError } =
      await schoolClient.rpc("school_create_cash_income_confirmation", {
        p_income_date: incomeDate,
        p_settlement_month: settlementMonth,
        p_business_entity_id: businessEntityId,
        p_student_id: studentId,
        p_cash_user_id: cashAccount.user_id,
        p_cash_account_id: cashAccount.id,
        p_cash_account_name_snapshot: cashAccount.name ?? cashAccount.id,
        p_cash_account_type_snapshot: cashAccount.account_type ?? null,
        p_amount: amount,
        p_income_category: optionalText(body.income_category) ?? "tuition",
        p_description: optionalText(body.description),
        p_currency: currency,
        p_payment_currency: currency,
        p_exchange_rate: exchangeRate,
        p_is_taxable_income: Boolean(body.is_taxable_income),
        p_tax_category: optionalText(body.tax_category),
        p_receipt_status: optionalText(body.receipt_status),
        p_note: optionalText(body.note),
      });

    if (schoolRequestError) {
      return jsonResponse(
        {
          ok: false,
          message: "School Cash income confirmation request failed",
          details: schoolRequestError.message,
        },
        400,
      );
    }

    const schoolRequest = unwrapSingleRow<SchoolIncomeRequestRow>(
      schoolRequestData as
        | SchoolIncomeRequestRow[]
        | SchoolIncomeRequestRow
        | null,
      "school_create_cash_income_confirmation",
    );

    const cashAmount = Number(schoolRequest.amount);
    if (!Number.isFinite(cashAmount) || cashAmount <= 0) {
      return jsonResponse(
        { ok: false, message: "School income amount must be greater than 0" },
        400,
      );
    }

    const cashPayload = {
      external_source: CASH_EXTERNAL_SOURCE,
      external_event_id: schoolRequest.linkage_event_id,
      external_reference_type: CASH_REFERENCE_TYPE,
      external_reference_id: schoolRequest.income_id,
      request_type: schoolRequest.request_type,
      transaction_type: CASH_TRANSACTION_TYPE,
      income_date: incomeDate,
      settlement_month: settlementMonth,
      business_entity_id: businessEntityId,
      student_id: studentId,
      income_category: optionalText(body.income_category) ?? "tuition",
      currency: schoolRequest.currency,
      amount: cashAmount,
      account_id: schoolRequest.cash_account_id,
      cash_account_name_snapshot: schoolRequest.cash_account_name_snapshot,
      cash_account_type_snapshot: schoolRequest.cash_account_type_snapshot,
      payment_currency: schoolRequest.payment_currency,
      payment_exchange_rate: schoolRequest.payment_exchange_rate === null
        ? null
        : Number(schoolRequest.payment_exchange_rate),
      payment_amount: Number(schoolRequest.payment_amount),
      attempt_no: schoolRequest.attempt_no,
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
        p_external_reference_id: schoolRequest.income_id,
        p_request_type: schoolRequest.request_type,
        p_transaction_type: CASH_TRANSACTION_TYPE,
        p_transacted_at: incomeDate,
        p_amount: cashAmount,
        p_idempotency_key: schoolRequest.idempotency_key,
        p_description: "School income Cash confirmation request",
        p_note: optionalText(body.note) ?? "",
        p_payload_snapshot: cashPayload,
        p_currency: schoolRequest.currency,
      });

    if (cashRequestError) {
      return jsonResponse(
        {
          ok: false,
          income_id: schoolRequest.income_id,
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
          income_id: schoolRequest.income_id,
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
          income_id: schoolRequest.income_id,
          linkage_event_id: schoolRequest.linkage_event_id,
          cash_request_id: cashRequest.request_id,
          cash_request_status: cashRequest.status ?? null,
          message: "Cash request already exists but is not pending",
        },
        409,
      );
    }

    const { data: submittedData, error: submittedError } =
      await schoolClient.rpc("school_mark_cash_income_request_submitted", {
        p_event_id: schoolRequest.linkage_event_id,
        p_cash_request_id: cashRequest.request_id,
        p_cash_request_status: cashRequest.status ?? "pending",
      });

    if (submittedError) {
      return jsonResponse(
        {
          ok: false,
          income_id: schoolRequest.income_id,
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
      income_id: string;
      linkage_event_id: string;
      sync_status: string;
      cash_request_id: string;
      cash_request_status: string;
      message: string;
    }>(
      submittedData as
        | {
          income_id: string;
          linkage_event_id: string;
          sync_status: string;
          cash_request_id: string;
          cash_request_status: string;
          message: string;
        }[]
        | {
          income_id: string;
          linkage_event_id: string;
          sync_status: string;
          cash_request_id: string;
          cash_request_status: string;
          message: string;
        }
        | null,
      "school_mark_cash_income_request_submitted",
    );

    return jsonResponse({
      ok: true,
      income_id: submitted.income_id,
      linkage_event_id: submitted.linkage_event_id,
      cash_request_id: submitted.cash_request_id,
      status: submitted.sync_status,
      cash_request_status: submitted.cash_request_status,
      currency: schoolRequest.currency,
      amount: cashAmount,
      attempt_no: schoolRequest.attempt_no,
      cash_inserted: cashRequest.inserted ?? null,
      message: submitted.message,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ ok: false, message }, 500);
  }
});
