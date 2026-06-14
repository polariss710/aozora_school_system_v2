// sync-cash-request-result
//
// Cash -> School callback bridge for Cash linkage v2.
// This function reads an already approved/rejected Cash pending request and
// reflects the result back to School. It must not approve/reject Cash requests,
// create Cash transactions, or create School ledger side effects.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  cash_request_id?: string;
  action?: string;
};

type CashRequestRow = {
  id: string;
  user_id: string;
  external_source: string;
  external_event_id: string;
  external_reference_type: string;
  external_reference_id: string;
  request_type: string;
  transaction_type: string;
  currency: string;
  amount: number | string;
  status: string;
  approved_at: string | null;
  rejected_at: string | null;
  rejected_reason: string | null;
  created_transaction_id: string | null;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const EXTERNAL_SOURCE = "aozora_school";
const TEACHER_WAGE_REFERENCE_TYPE = "school_payment_requests";
const TEACHER_WAGE_REQUEST_TYPE = "teacher_wage_payment_confirm";
const TEACHER_WAGE_TRANSACTION_TYPE = "expense";
const INCOME_REFERENCE_TYPE = "school_income_records";
const INCOME_REQUEST_TYPES = new Set([
  "tuition_income_received",
  "income_received",
]);
const INCOME_TRANSACTION_TYPE = "income";
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

function requireAction(value: unknown): "approved" | "rejected" {
  if (value !== "approved" && value !== "rejected") {
    throw new Error("action must be approved or rejected");
  }

  return value;
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

function isTeacherWageRequest(cashRequest: CashRequestRow): boolean {
  return (
    cashRequest.external_source === EXTERNAL_SOURCE &&
    cashRequest.external_reference_type === TEACHER_WAGE_REFERENCE_TYPE &&
    cashRequest.request_type === TEACHER_WAGE_REQUEST_TYPE &&
    cashRequest.transaction_type === TEACHER_WAGE_TRANSACTION_TYPE &&
    SUPPORTED_CURRENCIES.has(cashRequest.currency)
  );
}

function isIncomeRequest(cashRequest: CashRequestRow): boolean {
  return (
    cashRequest.external_source === EXTERNAL_SOURCE &&
    cashRequest.external_reference_type === INCOME_REFERENCE_TYPE &&
    INCOME_REQUEST_TYPES.has(cashRequest.request_type) &&
    cashRequest.transaction_type === INCOME_TRANSACTION_TYPE &&
    SUPPORTED_CURRENCIES.has(cashRequest.currency)
  );
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
    if (!authorization.toLowerCase().startsWith("bearer ")) {
      return jsonResponse(
        { ok: false, message: "Authorization bearer token is required" },
        401,
      );
    }

    const body = (await request.json()) as RequestBody;
    const cashRequestId = requireUuid(body.cash_request_id, "cash_request_id");
    const action = requireAction(body.action);

    const cashClient = createClient(
      getRequiredEnv("CASH_SUPABASE_URL"),
      getRequiredEnv("CASH_SERVICE_ROLE_KEY"),
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );

    const schoolClient = createClient(
      getRequiredEnv("SCHOOL_SUPABASE_URL"),
      getRequiredEnv("SCHOOL_SERVICE_ROLE_KEY"),
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );

    const bearerToken = authorization.replace(/^bearer\s+/i, "");
    const { data: userData, error: userError } =
      await cashClient.auth.getUser(bearerToken);

    if (userError || !userData.user) {
      return jsonResponse(
        { ok: false, message: "Invalid Cash authorization token" },
        401,
      );
    }

    const { data: cashRequestData, error: cashRequestError } =
      await cashClient
        .from("home_external_transaction_requests")
        .select(
          [
            "id",
            "user_id",
            "external_source",
            "external_event_id",
            "external_reference_type",
            "external_reference_id",
            "request_type",
            "transaction_type",
            "currency",
            "amount",
            "status",
            "approved_at",
            "rejected_at",
            "rejected_reason",
            "created_transaction_id",
          ].join(","),
        )
        .eq("id", cashRequestId)
        .single();

    if (cashRequestError) {
      return jsonResponse(
        {
          ok: false,
          message: "Cash request lookup failed",
          details: cashRequestError.message,
        },
        404,
      );
    }

    const cashRequest = cashRequestData as CashRequestRow;

    if (cashRequest.user_id !== userData.user.id) {
      return jsonResponse(
        { ok: false, message: "Cash request does not belong to the signed-in user" },
        403,
      );
    }

    if (cashRequest.status !== action) {
      return jsonResponse(
        {
          ok: false,
          message: `Cash request status must be ${action}`,
          cash_request_status: cashRequest.status,
        },
        409,
      );
    }

    const isTeacherWage = isTeacherWageRequest(cashRequest);
    const isIncome = isIncomeRequest(cashRequest);

    if (!isTeacherWage && !isIncome) {
      return jsonResponse(
        { ok: false, message: "Cash request is not a supported School request" },
        400,
      );
    }

    if (action === "approved" && !cashRequest.created_transaction_id) {
      return jsonResponse(
        { ok: false, message: "Approved Cash request has no created transaction" },
        409,
      );
    }

    if (action === "rejected" && cashRequest.created_transaction_id) {
      return jsonResponse(
        { ok: false, message: "Rejected Cash request must not have a created transaction" },
        409,
      );
    }

    if (action === "approved") {
      const rpcName = isIncome
        ? "school_mark_cash_income_confirmed"
        : "school_mark_personal_cash_payment_request_confirmed";
      const { data: schoolData, error: schoolError } =
        await schoolClient.rpc(rpcName, {
          p_event_id: cashRequest.external_event_id,
          p_cash_request_id: cashRequest.id,
          p_cash_transaction_id: cashRequest.created_transaction_id,
          p_confirmed_at: cashRequest.approved_at,
        });

      if (schoolError) {
        return jsonResponse(
          {
            ok: false,
            cash_request_id: cashRequest.id,
            action,
            message: "School confirmed writeback failed",
            details: schoolError.message,
          },
          502,
        );
      }

      const schoolResult = unwrapSingleRow<Record<string, unknown>>(
        schoolData as Record<string, unknown>[] | Record<string, unknown> | null,
        rpcName,
      );

      return jsonResponse({
        ok: true,
        action,
        reference_type: cashRequest.external_reference_type,
        cash_request_id: cashRequest.id,
        cash_request_status: cashRequest.status,
        cash_transaction_id: cashRequest.created_transaction_id,
        school: schoolResult,
      });
    }

    const rpcName = isIncome
      ? "school_mark_cash_income_rejected"
      : "school_mark_personal_cash_payment_request_rejected";
    const { data: schoolData, error: schoolError } =
      await schoolClient.rpc(rpcName, {
        p_event_id: cashRequest.external_event_id,
        p_cash_request_id: cashRequest.id,
        p_rejected_reason: cashRequest.rejected_reason,
        p_rejected_at: cashRequest.rejected_at,
      });

    if (schoolError) {
      return jsonResponse(
        {
          ok: false,
          cash_request_id: cashRequest.id,
          action,
          message: "School rejected writeback failed",
          details: schoolError.message,
        },
        502,
      );
    }

    const schoolResult = unwrapSingleRow<Record<string, unknown>>(
      schoolData as Record<string, unknown>[] | Record<string, unknown> | null,
      rpcName,
    );

    return jsonResponse({
      ok: true,
      action,
      reference_type: cashRequest.external_reference_type,
      cash_request_id: cashRequest.id,
      cash_request_status: cashRequest.status,
      school: schoolResult,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ ok: false, message }, 500);
  }
});
