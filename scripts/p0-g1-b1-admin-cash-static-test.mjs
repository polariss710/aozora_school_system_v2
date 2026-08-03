import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const edge = readFileSync("supabase/functions/request-cash-income-confirmation/index.ts", "utf8");
const auth = readFileSync("js/auth.js", "utf8");
const api = readFileSync("js/api/income-api.js", "utf8");
const detailApi = readFileSync("js/api/income-detail-api.js", "utf8");
const incomePage = readFileSync("js/pages/income-page.js", "utf8");
const detailPage = readFileSync("js/pages/income-detail-page.js", "utf8");
const aclSql = readFileSync(
  "sql/current/school_p0_g1_b1_admin_cash_authority_acl_20260804.sql",
  "utf8"
);
const postdeploySql = readFileSync(
  "sql/current/school_p0_g1_b1_admin_cash_authority_postdeploy_20260804.sql",
  "utf8"
);

assert.match(edge, /createUserScopedSchoolClient/);
assert.match(edge, /getRequiredEnv\("SUPABASE_ANON_KEY"\)/);
assert.match(edge, /headers: \{ Authorization: authorization \}/);
assert.match(edge, /auth\.getUser\(bearerToken\)/);
assert.match(edge, /school_require_current_app_admin/);
assert.ok(
  (edge.match(/requireCurrentActiveAdmin\(userScopedSchoolClient, schoolUser\.id\)/g) || []).length >= 4,
  "admin assertion must run initially and again adjacent to both writer stages"
);
assert.ok(
  edge.indexOf("await requireCurrentActiveAdmin(userScopedSchoolClient, schoolUser.id)") <
    edge.indexOf('"SCHOOL_SERVICE_ROLE_KEY"'),
  "non-admin callers must fail before service-role clients are created"
);
assert.match(edge, /TUITION_CASH_EXPECTED_FACTS_STALE/);
assert.match(edge, /snapshot\.generation_revision_id !== expectedRevisionId/);
assert.match(edge, /preflight\.eligible !== true/);
assert.match(edge, /preflight\.gate_state !== "enabled"/);
assert.doesNotMatch(edge, /body\.(?:user_id|email|role|membership)/);
assert.doesNotMatch(edge, /details:/);

assert.match(auth, /function isActiveAdmin/);
assert.match(auth, /membership\.role === "admin"/);
assert.match(auth, /requireActiveAdminForCashConfirmation/);
assert.match(api, /fetchCashIncomeSubmissionPreflight/);
for (const field of [
  "expected_student_id",
  "expected_settlement_month",
  "expected_tuition_bill_id",
  "expected_generation_revision_id",
  "expected_payment_currency",
  "expected_payment_amount",
]) {
  assert.match(api, new RegExp(field));
  assert.match(detailApi, new RegExp(field));
}
assert.doesNotMatch(detailApi, /data\?\.details/);
assert.match(incomePage, /buildFreshCashSubmissionConfirmation/);
assert.match(incomePage, /fetchCashIncomeSubmissionPreflight/);
assert.match(incomePage, /active revision/);
assert.match(incomePage, /提交Cash后不可通过普通页面撤销/);
assert.match(incomePage, /同一income\/active attempt仅创建一个Cash request/);
assert.match(incomePage, /requireActiveAdminForCashConfirmation/);
assert.match(detailPage, /requireActiveAdminForCashConfirmation/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
}
for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(
    source,
    /SERVICE_ROLE|service[_-]role/i,
    `browser service-role marker regression: js/${browserFile}`
  );
}

assert.match(aclSql, /grant execute on function public\.school_require_current_app_admin\(\)\s+to authenticated/);
assert.match(aclSql, /revoke all on function public\.school_require_current_app_admin\(\)\s+from public,anon,authenticated,service_role/);
assert.doesNotMatch(aclSql, /school_request_cash_income_confirmation_for_record[\s\S]*grant execute/);
assert.match(postdeploySql, /P0G1B1_SCHOOL_WRITER_ACL_INVALID/);
assert.match(postdeploySql, /P0G1B1_MEMBERSHIP_TABLE_ACL_INVALID/);

console.log("P0_G1_B1_ADMIN_CASH_STATIC_TEST_PASS");
