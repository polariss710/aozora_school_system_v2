import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const core = readFileSync("sql/current/school_student_master_p0_permission_closure_core_20260805.sql","utf8");
const rollback = readFileSync("sql/current/school_student_master_p0_permission_closure_rollback_tests_20260805.sql","utf8");
const postdeploy = readFileSync("sql/current/school_student_master_p0_permission_closure_postdeploy_20260805.sql","utf8");
const api = readFileSync("js/api/student-api.js","utf8");
const page = readFileSync("js/pages/student-page.js","utf8");

assert.match(core,/school_students_active_membership_select/);
assert.match(core,/school_get_current_app_membership\(\)/);
assert.match(core,/revoke all privileges on table public\.school_students[\s\S]*from public,anon,authenticated,service_role/i);
assert.match(core,/grant select on table public\.school_students to authenticated,service_role/i);
assert.match(core,/security definer\s+set search_path = pg_catalog, public[\s\S]*school_require_current_app_admin\(\)/i);
assert.match(core,/p_expected_updated_at timestamptz/);
assert.match(core,/for update/);
assert.match(core,/v_student\.updated_at is distinct from p_expected_updated_at/);
assert.match(api,/p_expected_updated_at: payload\.expectedUpdatedAt/);
assert.match(page,/expectedUpdatedAt: editingStudent\.updated_at/);
assert.match(rollback,/STUDENT_P0_PERMISSION_CLOSURE_ROLLBACK_TEST_PASS/);
assert.match(postdeploy,/STUDENT_P0_PERMISSION_CLOSURE_POSTDEPLOY_PASS/);
assert.doesNotMatch(core,/student_tuition_(?:preview|generate|cash_submit)/);

for (const pageFile of readdirSync("js/pages").filter((file)=>file.endsWith(".js"))) {
  const source=readFileSync(`js/pages/${pageFile}`,"utf8");
  assert.doesNotMatch(source,/\.rpc\s*\(/,`page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source,/\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,`page-layer table DML regression: ${pageFile}`);
}
for (const browserFile of readdirSync("js",{recursive:true}).filter((file)=>file.endsWith(".js"))) {
  const source=readFileSync(`js/${browserFile}`,"utf8");
  assert.doesNotMatch(source,/SERVICE_ROLE|service[_-]role/i,`browser service-role marker regression: js/${browserFile}`);
}

console.log("STUDENT_P0_PERMISSION_STATIC_TEST_PASS");
