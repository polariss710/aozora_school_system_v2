import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const edgePath = "supabase/functions/request-cash-expense-confirmation/index.ts";
const edge = readFileSync(edgePath, "utf8");
const api = readFileSync("js/api/expense-api.js", "utf8");
const core = readFileSync(
  "sql/current/school_p0_expense_permission_closure_core_20260804.sql",
  "utf8",
);
const createWriter = readFileSync(
  "sql/current/school_create_expense_record_rpc.sql",
  "utf8",
);
const rollback = readFileSync(
  "sql/current/school_p0_expense_permission_closure_rollback_tests_20260804.sql",
  "utf8",
);
const postdeploy = readFileSync(
  "sql/current/school_p0_expense_permission_closure_postdeploy_20260804.sql",
  "utf8",
);

assert.match(edge, /auth\.getUser\(bearerToken\)/);
assert.match(edge, /createUserScopedSchoolClient/);
assert.match(edge, /getRequiredEnv\("SUPABASE_ANON_KEY"\)/);
assert.match(edge, /headers: \{ Authorization: authorization \}/);
assert.match(edge, /school_require_current_app_admin/);
assert.ok(
  (edge.match(/requireCurrentActiveAdmin\(userScopedSchoolClient, schoolUser\.id\)/g) ?? [])
      .length >= 3,
  "active-admin authority must be checked initially and immediately before both write boundaries",
);
assert.ok(
  edge.indexOf("await requireCurrentActiveAdmin(userScopedSchoolClient, schoolUser.id)") <
    edge.indexOf('"CASH_SERVICE_ROLE_KEY"'),
  "unauthorized callers must fail before the Cash service-role client exists",
);
assert.ok(
  edge.lastIndexOf("await requireCurrentActiveAdmin(userScopedSchoolClient, schoolUser.id)") <
    edge.indexOf('cashClient.rpc("home_create_external_transaction_request"'),
  "authority must be rechecked immediately before the Cash write",
);
assert.doesNotMatch(edge, /body\.(?:user_id|email|role|membership|is_admin|admin)/i);

assert.match(api, /supabase\.rpc\("school_create_expense_record"/);
assert.match(api, /request-cash-expense-confirmation/);
for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(
    source,
    /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,
    `page-layer table DML regression: ${pageFile}`,
  );
}
for (const browserFile of readdirSync("js", { recursive: true }).filter((file) =>
  file.endsWith(".js")
)) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(
    source,
    /SERVICE_ROLE|service[_-]role/i,
    `browser service-role marker regression: js/${browserFile}`,
  );
}

assert.match(createWriter, /security definer\s+set search_path = pg_catalog, public/i);
assert.match(createWriter, /school_require_current_app_admin\(\)/);
assert.match(createWriter, /pg_try_advisory_xact_lock/);
assert.match(
  createWriter,
  /revoke all on function public\.school_create_expense_record[\s\S]*from public, anon, authenticated, service_role/i,
);
assert.match(
  createWriter,
  /grant execute on function public\.school_create_expense_record[\s\S]*to authenticated/i,
);

for (const writer of [
  "school_request_cash_expense_payment_confirmation",
  "school_mark_cash_expense_request_submitted",
  "school_mark_cash_expense_confirmed",
  "school_mark_cash_expense_rejected",
]) {
  assert.match(core, new RegExp(`revoke all on function public\\.${writer}[\\s\\S]*?from public, anon, authenticated, service_role`, "i"));
  assert.match(core, new RegExp(`grant execute on function public\\.${writer}[\\s\\S]*?to service_role`, "i"));
}

for (const table of [
  "school_expense_records",
  "school_accounts",
  "school_account_transactions",
]) {
  assert.match(core, new RegExp(`revoke all privileges on table public\\.${table}[\\s\\S]*?from public, anon, authenticated`, "i"));
  assert.match(core, new RegExp(`grant select on table public\\.${table} to authenticated`, "i"));
}

assert.match(core, /alter default privileges for role postgres in schema public/i);
assert.match(rollback, /P0_EXPENSE_PERMISSION_CLOSURE_ROLLBACK_TEST_PASS/);
assert.match(postdeploy, /P0_EXPENSE_PERMISSION_CLOSURE_POSTDEPLOY_PASS/);
assert.doesNotMatch(core, /student_tuition_(?:preview|generate|cash_submit)/);

console.log("P0_EXPENSE_PERMISSION_STATIC_TEST_PASS");
