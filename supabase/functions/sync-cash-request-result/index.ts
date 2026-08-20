// sync-cash-request-result
//
// Cash -> School callback bridge for Cash linkage v2.
// This function reads an already approved/rejected Cash pending request and
// reflects the result back to School. It must not approve/reject Cash requests,
// create Cash transactions, or create School ledger side effects.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  buildSchoolExpenseCashEvidence,
  buildSchoolExpenseFixedApprovedEvidence,
  buildSchoolExpenseFixedCashEvidence,
  inspectSchoolExpenseCashFingerprint,
} from "../_shared/expense-cash-attempt-v2.js";

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
  account_id: string | null;
  transacted_at: string;
  status: string;
  approved_at: string | null;
  rejected_at: string | null;
  rejected_reason: string | null;
  created_transaction_id: string | null;
  idempotency_key: string;
  payload_snapshot: Record<string, unknown>;
  payment_route: string;
  card_instrument_id: string | null;
  charge_date: string | null;
  suggested_fixed_month: string | null;
  target_fixed_month: string | null;
  funding_account_id: string | null;
  fixed_projection_id: string | null;
};

type CashTransactionRow = {
  id: string;
  user_id: string;
  currency: string;
  transaction_type: string;
  account_id: string;
  transacted_at: string;
  amount: number | string;
  external_source: string;
  external_source_id: string;
  external_event_type: string;
  external_idempotency_key: string;
  external_reference_type: string;
  external_reference_id: string;
  created_by_external: boolean;
  accounting_scope: string;
};

class SyncEvidenceError extends Error {
  code: string;
  status: number;
  details: string | null;

  constructor(code: string, message: string, status = 409, details: string | null = null) {
    super(message);
    this.name = "SyncEvidenceError";
    this.code = code;
    this.status = status;
    this.details = details;
  }
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const EXTERNAL_SOURCE = "aozora_school";
const INCOME_REFERENCE_TYPE = "school_income_records";
const INCOME_REQUEST_TYPES = new Set([
  "tuition_income_received",
  "income_received",
]);
const INCOME_TRANSACTION_TYPE = "income";
const EXPENSE_REFERENCE_TYPE = "school_expense_records";
const EXPENSE_REQUEST_TYPE = "expense_paid";
const EXPENSE_TRANSACTION_TYPE = "expense";
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

function isIncomeRequest(cashRequest: CashRequestRow): boolean {
  return (
    cashRequest.external_source === EXTERNAL_SOURCE &&
    cashRequest.external_reference_type === INCOME_REFERENCE_TYPE &&
    INCOME_REQUEST_TYPES.has(cashRequest.request_type) &&
    cashRequest.transaction_type === INCOME_TRANSACTION_TYPE &&
    SUPPORTED_CURRENCIES.has(cashRequest.currency)
  );
}

function isExpenseRequest(cashRequest: CashRequestRow): boolean {
  return (
    cashRequest.external_source === EXTERNAL_SOURCE &&
    cashRequest.external_reference_type === EXPENSE_REFERENCE_TYPE &&
    cashRequest.request_type === EXPENSE_REQUEST_TYPE &&
    cashRequest.transaction_type === EXPENSE_TRANSACTION_TYPE &&
    SUPPORTED_CURRENCIES.has(cashRequest.currency)
  );
}

function isImmediateExpenseRequest(cashRequest: CashRequestRow): boolean {
  return isExpenseRequest(cashRequest) &&
    cashRequest.payment_route === "immediate_account";
}

function isFixedExpenseRequest(cashRequest: CashRequestRow): boolean {
  return isExpenseRequest(cashRequest) &&
    cashRequest.payment_route === "fixed_credit_card";
}

function isLegacyDirectRequest(cashRequest: CashRequestRow): boolean {
  return (
    cashRequest.external_source === EXTERNAL_SOURCE &&
    (
      cashRequest.external_reference_type === "school_payment_requests" ||
      cashRequest.external_reference_type === "school_part_time_work_income_requests" ||
      [
        "teacher_wage_payment_confirm",
        "teacher_wage_payment_reverse",
        "part_time_work_income_received",
      ].includes(cashRequest.request_type)
    )
  );
}

function resolverErrorCode(message: string | undefined): string {
  const knownCodes = [
    "HISTORICAL_FALLBACK_NOT_ELIGIBLE",
    "HOME_REQUEST_EVIDENCE_CONFLICT",
    "HOME_TRANSACTION_MISSING",
    "HOME_TRANSACTION_EVIDENCE_CONFLICT",
    "HOME_TRANSACTION_REJECTED_CONFLICT",
    "FINGERPRINT_RECOMPUTE_CONFLICT",
    "ACTION_STATUS_CONFLICT",
    "TERMINAL_CONFLICT",
    "SCHOOL_EXPENSE_ATTEMPT_LINK_CONFLICT",
    "SCHOOL_EXPENSE_CASH_ATTEMPT_IDENTITY_AMBIGUOUS",
    "SCHOOL_EXPENSE_TERMINAL_STATE_CONFLICT",
  ];
  return knownCodes.find((code) => message?.includes(code)) ??
    "HISTORICAL_FALLBACK_NOT_ELIGIBLE";
}

async function readUniqueImmediateTransactionEvidence(
  cashClient: ReturnType<typeof createClient>,
  cashRequest: CashRequestRow,
  callbackAction: "approved" | "rejected",
): Promise<CashTransactionRow | null> {
  const filters = [
    cashRequest.created_transaction_id
      ? `id.eq.${cashRequest.created_transaction_id}`
      : null,
    `external_source_id.eq.${cashRequest.external_event_id}`,
    `external_idempotency_key.eq.${cashRequest.idempotency_key}`,
    `and(external_reference_type.eq.${cashRequest.external_reference_type},external_reference_id.eq.${cashRequest.external_reference_id})`,
  ].filter(Boolean).join(",");

  const transactionColumns = [
    "id",
    "user_id",
    "currency",
    "transaction_type",
    "account_id",
    "transacted_at",
    "amount",
    "external_source",
    "external_source_id",
    "external_event_type",
    "external_idempotency_key",
    "external_reference_type",
    "external_reference_id",
    "created_by_external",
    "accounting_scope",
  ].join(",");
  const lookups = await Promise.all(
    ["home_jpy_transactions", "home_cny_transactions"].map(async (tableName) => {
      const { data, error } = await cashClient
        .from(tableName)
        .select(transactionColumns)
        .or(filters);
      if (error) {
        throw new SyncEvidenceError(
          "HOME_TRANSACTION_LOOKUP_FAILED",
          `Cash transaction evidence lookup failed for ${tableName}`,
          502,
          error.message,
        );
      }
      return (data ?? []) as CashTransactionRow[];
    }),
  );

  const rows = lookups.flat();
  if (callbackAction === "rejected") {
    if (rows.length > 1) {
      throw new SyncEvidenceError(
        "HOME_TRANSACTION_AMBIGUOUS",
        "Rejected Cash request matched multiple transactions",
      );
    }
    if (rows.length === 1) {
      throw new SyncEvidenceError(
        "HOME_TRANSACTION_EVIDENCE_CONFLICT",
        "Rejected Cash request must not have a transaction",
      );
    }
    return null;
  }

  if (rows.length === 0) {
    throw new SyncEvidenceError(
      "HOME_TRANSACTION_MISSING",
      "Approved Cash request transaction evidence is missing",
    );
  }
  if (rows.length !== 1) {
    throw new SyncEvidenceError(
      "HOME_TRANSACTION_AMBIGUOUS",
      "Approved Cash request transaction evidence is ambiguous",
    );
  }
  return rows[0];
}

async function buildImmediateExpenseCallbackEvidence(
  cashClient: ReturnType<typeof createClient>,
  schoolClient: ReturnType<typeof createClient>,
  cashRequest: CashRequestRow,
  callbackAction: "approved" | "rejected",
): Promise<Record<string, unknown>> {
  const fingerprintState = inspectSchoolExpenseCashFingerprint(cashRequest);
  if (fingerprintState.state === "present") {
    return buildSchoolExpenseCashEvidence(cashRequest);
  }

  const transaction = await readUniqueImmediateTransactionEvidence(
    cashClient,
    cashRequest,
    callbackAction,
  );
  const snapshot = cashRequest.payload_snapshot;
  const resolverName = "school_resolve_historical_expense_cash_attempt_fingerprint_v1";
  const { data, error } = await schoolClient.rpc(resolverName, {
    p_expense_record_id: cashRequest.external_reference_id,
    p_cash_request_id: cashRequest.id,
    p_home_request_user_id: cashRequest.user_id,
    p_home_request_status: cashRequest.status,
    p_home_approved_at: cashRequest.approved_at,
    p_home_rejected_at: cashRequest.rejected_at,
    p_external_source: cashRequest.external_source,
    p_request_event_id: cashRequest.external_event_id,
    p_idempotency_key: cashRequest.idempotency_key,
    p_external_reference_type: cashRequest.external_reference_type,
    p_external_reference_id: cashRequest.external_reference_id,
    p_request_type: cashRequest.request_type,
    p_transaction_type: cashRequest.transaction_type,
    p_payment_route: cashRequest.payment_route,
    p_attempt_no: snapshot.attempt_no,
    p_original_amount: snapshot.original_amount,
    p_original_currency: snapshot.original_currency,
    p_payment_amount: cashRequest.amount,
    p_payment_currency: cashRequest.currency,
    p_cash_account_id: cashRequest.account_id,
    p_charge_date: cashRequest.transacted_at,
    p_cash_transaction_id: cashRequest.created_transaction_id,
    p_home_transaction_id: transaction?.id ?? null,
    p_home_transaction_user_id: transaction?.user_id ?? null,
    p_home_transaction_type: transaction?.transaction_type ?? null,
    p_home_transaction_amount: transaction?.amount ?? null,
    p_home_transaction_currency: transaction?.currency ?? null,
    p_home_transaction_account_id: transaction?.account_id ?? null,
    p_home_transaction_date: transaction?.transacted_at ?? null,
    p_home_transaction_scope: transaction?.accounting_scope ?? null,
    p_home_transaction_external_source: transaction?.external_source ?? null,
    p_home_transaction_event_id: transaction?.external_source_id ?? null,
    p_home_transaction_event_type: transaction?.external_event_type ?? null,
    p_home_transaction_reference_type: transaction?.external_reference_type ?? null,
    p_home_transaction_reference_id: transaction?.external_reference_id ?? null,
    p_home_transaction_idempotency_key: transaction?.external_idempotency_key ?? null,
    p_home_transaction_created_by_external: transaction?.created_by_external ?? null,
  });

  if (error) {
    const code = resolverErrorCode(error.message);
    throw new SyncEvidenceError(
      code,
      "Historical School Cash evidence resolution failed",
      409,
      error.message,
    );
  }

  const resolved = unwrapSingleRow<Record<string, unknown>>(
    data as Record<string, unknown>[] | Record<string, unknown> | null,
    resolverName,
  );
  if (
    resolved.resolved_expense_id !== cashRequest.external_reference_id ||
    typeof resolved.resolved_attempt_id !== "string"
  ) {
    throw new SyncEvidenceError(
      "HISTORICAL_FALLBACK_NOT_ELIGIBLE",
      "Historical resolver returned conflicting School identity",
    );
  }

  return buildSchoolExpenseCashEvidence(cashRequest, {
    resolvedHistoricalFingerprint: resolved.resolved_request_payload_fingerprint,
  });
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
            "account_id",
            "transacted_at",
            "status",
            "approved_at",
            "rejected_at",
            "rejected_reason",
            "created_transaction_id",
            "idempotency_key",
            "payload_snapshot",
            "payment_route",
            "card_instrument_id",
            "charge_date",
            "suggested_fixed_month",
            "target_fixed_month",
            "funding_account_id",
            "fixed_projection_id",
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

    const callbackAction = cashRequest.status === "approved"
      ? "approved"
      : "rejected";

    const isIncome = isIncomeRequest(cashRequest);
    const isExpense = isExpenseRequest(cashRequest);
    const isImmediateExpense = isImmediateExpenseRequest(cashRequest);
    const isFixedExpense = isFixedExpenseRequest(cashRequest);
    const isLegacyDirect = isLegacyDirectRequest(cashRequest);

    if (isLegacyDirect) {
      return jsonResponse(
        {
          ok: false,
          legacy: true,
          action: callbackAction,
          reference_type: cashRequest.external_reference_type,
          request_type: cashRequest.request_type,
          cash_request_id: cashRequest.id,
          cash_request_status: cashRequest.status,
          message:
            "Legacy direct Cash request type is deprecated; use school_income_records or school_expense_records.",
        },
        410,
      );
    }

    if (!isIncome && !isExpense) {
      return jsonResponse(
        { ok: false, message: "Cash request is not a supported canonical School request" },
        400,
      );
    }

    if (
      callbackAction === "approved" &&
      !isFixedExpense &&
      !cashRequest.created_transaction_id
    ) {
      return jsonResponse(
        { ok: false, message: "Approved Cash request has no created transaction" },
        409,
      );
    }

    if (callbackAction === "rejected" && cashRequest.created_transaction_id) {
      return jsonResponse(
        { ok: false, message: "Rejected Cash request must not have a created transaction" },
        409,
      );
    }

    const immediateExpenseEvidence = isImmediateExpense
      ? await buildImmediateExpenseCallbackEvidence(
        cashClient,
        schoolClient,
        cashRequest,
        callbackAction,
      )
      : null;

    if (callbackAction === "approved" && isFixedExpense) {
      const { data: approvalEvidenceData, error: approvalEvidenceError } =
        await cashClient.rpc("home_get_external_fixed_approval_evidence", {
          p_request_id: cashRequest.id,
        });

      if (approvalEvidenceError || !approvalEvidenceData) {
        return jsonResponse(
          {
            ok: false,
            code: "HOME_FIXED_APPROVAL_EVIDENCE_INCOMPLETE",
            alert: true,
            cash_request_id: cashRequest.id,
            action: callbackAction,
            message: "Cash fixed approval evidence lookup failed",
            details: approvalEvidenceError?.message ?? null,
          },
          502,
        );
      }

      const rpcName = "school_mark_cash_fixed_expense_approved_v2";
      const rpcPayload = buildSchoolExpenseFixedApprovedEvidence(
        cashRequest,
        approvalEvidenceData as Record<string, unknown>,
      );
      const { data: schoolData, error: schoolError } =
        await schoolClient.rpc(rpcName, rpcPayload);

      if (schoolError) {
        return jsonResponse(
          {
            ok: false,
            cash_request_id: cashRequest.id,
            action: callbackAction,
            message: "School fixed approved writeback failed",
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
        action: callbackAction,
        reference_type: cashRequest.external_reference_type,
        cash_request_id: cashRequest.id,
        cash_request_status: cashRequest.status,
        cash_transaction_id: null,
        fixed_projection_id: approvalEvidenceData.fixed_projection_id ?? null,
        fixed_item_id: approvalEvidenceData.fixed_item_id ?? null,
        school: schoolResult,
      });
    }

    if (callbackAction === "approved") {
      const rpcName = isImmediateExpense
        ? "school_mark_cash_expense_confirmed_v2"
        : "school_mark_cash_income_confirmed";
      const rpcPayload = isImmediateExpense
        ? {
          ...immediateExpenseEvidence,
          p_cash_transaction_id: cashRequest.created_transaction_id,
          p_confirmed_at: cashRequest.approved_at,
          p_recovery_source: "sync-cash-request-result-v2",
        }
        : {
          p_event_id: cashRequest.external_event_id,
          p_cash_request_id: cashRequest.id,
          p_cash_transaction_id: cashRequest.created_transaction_id,
          p_confirmed_at: cashRequest.approved_at,
        };
      const { data: schoolData, error: schoolError } =
        await schoolClient.rpc(rpcName, rpcPayload);

      if (schoolError) {
        return jsonResponse(
          {
            ok: false,
            cash_request_id: cashRequest.id,
            action: callbackAction,
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
        action: callbackAction,
        reference_type: cashRequest.external_reference_type,
        cash_request_id: cashRequest.id,
        cash_request_status: cashRequest.status,
        cash_transaction_id: cashRequest.created_transaction_id,
        school: schoolResult,
      });
    }

    const rpcName = isFixedExpense
      ? "school_mark_cash_fixed_expense_rejected_v2"
      : isImmediateExpense
      ? "school_mark_cash_expense_rejected_v2"
      : "school_mark_cash_income_rejected";
    const rpcPayload = isFixedExpense
      ? {
        ...buildSchoolExpenseFixedCashEvidence(cashRequest),
        p_rejected_reason: cashRequest.rejected_reason,
        p_rejected_at: cashRequest.rejected_at,
      }
      : isImmediateExpense
      ? {
        ...immediateExpenseEvidence,
        p_rejected_reason: cashRequest.rejected_reason,
        p_rejected_at: cashRequest.rejected_at,
        p_recovery_source: "sync-cash-request-result-v2",
      }
      : {
        p_event_id: cashRequest.external_event_id,
        p_cash_request_id: cashRequest.id,
        p_rejected_reason: cashRequest.rejected_reason,
        p_rejected_at: cashRequest.rejected_at,
      };
    const { data: schoolData, error: schoolError } =
      await schoolClient.rpc(rpcName, rpcPayload);

    if (schoolError) {
      return jsonResponse(
        {
          ok: false,
          cash_request_id: cashRequest.id,
          action: callbackAction,
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
      action: callbackAction,
      reference_type: cashRequest.external_reference_type,
      cash_request_id: cashRequest.id,
      cash_request_status: cashRequest.status,
      school: schoolResult,
    });
  } catch (error) {
    if (error instanceof SyncEvidenceError) {
      return jsonResponse(
        {
          ok: false,
          code: error.code,
          message: error.message,
          details: error.details,
        },
        error.status,
      );
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ ok: false, message }, 500);
  }
});
