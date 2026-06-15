// request-cash-part-time-income-confirmation
//
// Deprecated legacy bypass endpoint. External part-time work income must go
// through school_income_records and request-cash-income-confirmation.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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

Deno.serve((request: Request): Response => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  return jsonResponse(
    {
      ok: false,
      message:
        "Deprecated endpoint. Route part-time work income through school_income_records, then submit Cash confirmation from the income record.",
    },
    410,
  );
});
