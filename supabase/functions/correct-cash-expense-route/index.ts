// Correction-P dedicated coordinator. This endpoint is local-only in Phase B.
// It never accepts amount/account/card/month overrides and never calls any
// statement, funding, allocation, ordinary expense, or general fixed writer.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  assertHomePrepared,
  assertSchoolEvidence,
  assertSourceMatchesTarget,
  buildHomeCompleteArgs,
  buildHomePrepareArgs,
  buildSchoolFinalizeArgs,
  callCorrectionRpc,
  correctionPClientError,
  CorrectionPError,
  recoverWriterWithStatus,
  requireCorrectionTarget,
} from "../_shared/correction-p.js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function env(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}
function client(url: string, key: string, authorization?: string) {
  return createClient(env(url), env(key), {
    auth: { autoRefreshToken: false, persistSession: false },
    ...(authorization ? { global: { headers: { Authorization: authorization } } } : {}),
  });
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json; charset=utf-8" },
  });
}
type CorrectionRpcCall = Parameters<typeof callCorrectionRpc>[1];
async function recoverableRpc(
  db: unknown, writer: CorrectionRpcCall, reader: CorrectionRpcCall,
  recoveryCode: string,
) {
  return recoverWriterWithStatus(
    () => callCorrectionRpc(db, writer),
    () => callCorrectionRpc(db, reader),
    recoveryCode,
  );
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") {
    const failure=correctionPClientError(new CorrectionPError("METHOD_NOT_ALLOWED"));
    return json(failure.body,failure.status);
  }
  let operationId: string | null = null;
  let stage = "request";
  try {
    const authorization = request.headers.get("authorization") || "";
    if (!authorization.toLowerCase().startsWith("bearer ")) {
      const failure=correctionPClientError(new CorrectionPError("SCHOOL_AUTH_REQUIRED"));
      return json(failure.body,failure.status);
    }
    const school = client("SCHOOL_SUPABASE_URL", "SCHOOL_SERVICE_ROLE_KEY");
    const bearer = authorization.replace(/^bearer\s+/i, "");
    const { data: userData, error: userError } = await school.auth.getUser(bearer);
    if (userError || !userData.user) {
      const failure=correctionPClientError(new CorrectionPError("SCHOOL_AUTH_INVALID"));
      return json(failure.body,failure.status);
    }
    const actorId = userData.user.id;
    const scopedSchool = client("SCHOOL_SUPABASE_URL", "SUPABASE_ANON_KEY", authorization);
    const { data: adminId, error: adminError } = await scopedSchool.rpc("school_require_current_app_admin");
    if (adminError || adminId !== actorId) {
      const failure=correctionPClientError(new CorrectionPError("P0G1_ACTIVE_ADMIN_REQUIRED"));
      return json(failure.body,failure.status);
    }

    let body: unknown;
    try { body=await request.json(); }
    catch { throw new CorrectionPError("CORRECTION_P_INVALID_JSON","BODY_JSON"); }
    const target = requireCorrectionTarget(body);
    operationId=target.operation_id;
    const cash = client("CASH_SUPABASE_URL", "CASH_SERVICE_ROLE_KEY");
    stage="school_source";
    const source = await callCorrectionRpc(school, {
      name: "school_get_expense_cash_correction_source_v1",
      args: {
        p_school_expense_id: target.school_expense_id,
        p_school_attempt_id: target.school_attempt_id,
        p_actor_id: actorId,
      },
    });
    assertSourceMatchesTarget(source, target);

    stage="home_status_before_prepare";
    let home = await callCorrectionRpc(cash, {
      name: "home_get_external_transaction_correction_p",
      args: { p_operation_id: target.operation_id },
    });
    if (!home?.ok) {
      stage="home_prepare";
      home = await recoverableRpc(
        cash,
        { name: "home_prepare_external_transaction_correction_p",
          args: buildHomePrepareArgs(source, target, actorId) },
        { name: "home_get_external_transaction_correction_p",
          args: { p_operation_id: target.operation_id } },
        "CORRECTION_P_HOME_PREPARE_RECOVERABLE",
      );
    }
    assertHomePrepared(home, target);
    if (home.status === "completed") {
      return json({ ok: true, code: "CORRECTION_P_ALREADY_COMPLETED", correction: home });
    }

    stage="school_status_before_finalize";
    let evidence = await callCorrectionRpc(school, {
      name: "school_get_expense_cash_correction_p",
      args: { p_operation_id: target.operation_id },
    });
    if (!evidence?.ok) {
      stage="school_finalize";
      evidence = await recoverableRpc(
        school,
        { name: "school_finalize_expense_cash_correction_p",
          args: buildSchoolFinalizeArgs(home, actorId) },
        { name: "school_get_expense_cash_correction_p",
          args: { p_operation_id: target.operation_id } },
        "CORRECTION_P_SCHOOL_FINALIZE_RECOVERABLE",
      );
    }
    assertSchoolEvidence(evidence, home, actorId);
    stage="home_complete";
    const completed = await recoverableRpc(
      cash,
      { name: "home_complete_external_transaction_correction_p",
        args: buildHomeCompleteArgs(home, evidence, actorId) },
      { name: "home_get_external_transaction_correction_p",
        args: { p_operation_id: target.operation_id } },
      "CORRECTION_P_HOME_COMPLETE_RECOVERABLE",
    );
    if (!completed?.ok || completed.status !== "completed") {
      throw new CorrectionPError("CORRECTION_P_INTERNAL_ERROR","HOME_COMPLETE_CONTRACT");
    }
    return json({ ok: true, code: "CORRECTION_P_COMPLETED", correction: completed, school_evidence: evidence });
  } catch (error) {
    const failure=correctionPClientError(error);
    console.error(JSON.stringify({ operation_id: operationId, stage,
      category: error instanceof CorrectionPError ? error.internalCategory : "UNEXPECTED" }));
    return json(failure.body,failure.status);
  }
});
