// Trusted School service-role bridge for P0-C Atomic Tuition dedicated Void.
// It performs a read-only Cash DB absence check before the School atomic RPC.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  generation_revision_id?: string;
  tuition_bill_id?: string;
  income_record_id?: string;
  expected_generation_manifest_sha256?: string;
  reason?: string;
  preflight_only?: boolean;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json; charset=utf-8" },
  });
}

function env(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function client(urlName: string, keyName: string) {
  return createClient(env(urlName), env(keyName), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function requiredUuid(value: unknown, name: string) {
  const text = typeof value === "string" ? value.trim() : "";
  if (!UUID.test(text)) throw new Error(`${name} must be a UUID`);
  return text;
}

function one<T>(data: T[] | T | null, context: string): T {
  if (Array.isArray(data)) {
    if (data.length !== 1) throw new Error(`${context} returned ${data.length} rows`);
    return data[0];
  }
  if (!data) throw new Error(`${context} returned no data`);
  return data;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return response({ ok: false, message: "Only POST is supported" }, 405);

  try {
    const school = client("SCHOOL_SUPABASE_URL", "SCHOOL_SERVICE_ROLE_KEY");
    const cash = client("CASH_SUPABASE_URL", "CASH_SERVICE_ROLE_KEY");
    const authorization = request.headers.get("authorization") ?? "";
    if (!authorization.toLowerCase().startsWith("bearer ")) {
      return response({ ok: false, message: "Invalid School authorization token" }, 401);
    }
    const token = authorization.replace(/^bearer\s+/i, "");
    const serviceRoleKey = env("SCHOOL_SERVICE_ROLE_KEY");
    const isLocalTrustedOwner = token === serviceRoleKey;
    if (!isLocalTrustedOwner) {
      const { data: authData, error: authError } = await school.auth.getUser(token);
      if (authError || !authData.user) {
        return response({ ok: false, message: "Invalid School authorization token" }, 401);
      }
    }

    const body = await request.json() as RequestBody;
    const revisionId = requiredUuid(body.generation_revision_id, "generation_revision_id");
    const billId = requiredUuid(body.tuition_bill_id, "tuition_bill_id");
    const incomeId = requiredUuid(body.income_record_id, "income_record_id");
    const manifest = typeof body.expected_generation_manifest_sha256 === "string"
      ? body.expected_generation_manifest_sha256.trim()
      : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    const preflightOnly = body.preflight_only === true;
    if (!SHA256.test(manifest)) throw new Error("expected_generation_manifest_sha256 is invalid");
    if (!preflightOnly && !reason) throw new Error("reason is required");

    const { data: preflightData, error: preflightError } = await school.rpc(
      "school_get_atomic_tuition_void_preflight",
      { p_income_record_id: incomeId },
    );
    if (preflightError) throw new Error(preflightError.message);
    const preflight = one<Record<string, unknown>>(preflightData, "tuition void preflight");
    if (preflight.generation_revision_id !== revisionId || preflight.tuition_bill_id !== billId ||
      preflight.generation_manifest_sha256 !== manifest) {
      return response({ ok: false, code: "TUITION_VOID_NOT_ACTIVE_REVISION", message: "页面事实已过期，请刷新。" }, 409);
    }
    if (preflight.eligible !== true) {
      return response({ ok: false, code: preflight.blocker_code, message: preflight.blocker_message }, 409);
    }

    const [requestFacts, jpyFacts, cnyFacts] = await Promise.all([
      cash.from("home_external_transaction_requests").select("id", { count: "exact", head: true })
        .eq("external_source", "aozora_school")
        .eq("external_reference_type", "school_income_records")
        .eq("external_reference_id", incomeId),
      cash.from("home_jpy_transactions").select("id", { count: "exact", head: true })
        .eq("external_source", "aozora_school")
        .eq("external_reference_type", "school_income_records")
        .eq("external_reference_id", incomeId),
      cash.from("home_cny_transactions").select("id", { count: "exact", head: true })
        .eq("external_source", "aozora_school")
        .eq("external_reference_type", "school_income_records")
        .eq("external_reference_id", incomeId),
    ]);
    for (const result of [requestFacts, jpyFacts, cnyFacts]) {
      if (result.error) throw new Error(`Cash fact verification failed: ${result.error.message}`);
    }
    const cashFactCount = (requestFacts.count ?? 0) + (jpyFacts.count ?? 0) + (cnyFacts.count ?? 0);
    if (cashFactCount !== 0) {
      return response({ ok: false, code: "TUITION_VOID_CASH_FACT_EXISTS", message: "Cash 已存在 request/transaction，禁止作废。" }, 409);
    }
    if (preflightOnly) {
      return response({ ok: true, preflight, cash_fact_count: 0 });
    }

    // The School RPC takes the shared operation lock and rechecks the committed
    // School reservation under lock, closing the race before any Cash writer can proceed.
    const { data, error } = await school.rpc(
      isLocalTrustedOwner
        ? "school_void_atomic_student_tuition_generation_local"
        : "school_void_atomic_student_tuition_generation",
      {
      p_generation_revision_id: revisionId,
      p_tuition_bill_id: billId,
      p_income_record_id: incomeId,
      p_expected_generation_manifest_sha256: manifest,
      p_reason: reason,
      },
    );
    if (error) return response({ ok: false, code: error.message.split(":")[0], message: error.message }, 409);
    return response({ ok: true, result: one(data, "atomic tuition void") });
  } catch (error) {
    return response({ ok: false, message: error instanceof Error ? error.message : String(error) }, 400);
  }
});
