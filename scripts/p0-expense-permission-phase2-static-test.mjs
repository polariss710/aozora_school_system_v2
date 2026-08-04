import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const interactiveFiles = [
  "sql/current/school_update_expense_record_rpc.sql",
  "sql/current/school_reverse_expense_record_rpc.sql",
  "sql/current/school_create_reimbursement_record_rpc.sql",
  "sql/current/school_reverse_reimbursement_record_rpc.sql",
  "sql/current/school_create_expense_attachment_metadata_rpc.sql",
  "sql/current/school_generate_teacher_monthly_wage_business_scope.sql",
  "sql/current/school_adjust_teacher_wage_detail_rpc.sql",
  "sql/current/school_teacher_wage_expense_void_and_regenerate.sql",
  "sql/current/school_void_teacher_wage_lock_rpc.sql",
  "sql/current/school_create_teacher_wage_rule_config_rpc.sql",
  "sql/current/school_update_teacher_wage_rule_config_rpc.sql",
  "sql/current/school_set_teacher_wage_rule_active_state_rpc.sql",
  "sql/current/school_confirm_payment_request_rpc.sql",
  "sql/current/school_reverse_paid_payment_request_rpc.sql",
  "sql/current/school_payment_status_actions_rpc.sql",
  "sql/current/school_reissue_reversed_payment_request_rpc.sql",
];

for (const file of interactiveFiles) {
  const source = readFileSync(file, "utf8");
  assert.match(source, /set search_path = pg_catalog, public/i, `${file}: unsafe search_path`);
  assert.match(source, /school_require_current_app_admin\(\)/, `${file}: missing admin guard`);
}

const updateSql = readFileSync("sql/current/school_update_expense_record_rpc.sql", "utf8");
assert.match(updateSql, /p_expected_updated_at timestamptz/);
assert.match(updateSql, /v_expense\.updated_at is distinct from p_expected_updated_at/);
assert.match(updateSql, /P0_EXPENSE_UPDATE_STALE_VERSION/);
assert.match(updateSql, /revoke all on function public\.school_update_expense_record[\s\S]*?uuid,date[\s\S]*?service_role/i);

const attachmentSql = readFileSync(
  "sql/current/school_create_expense_attachment_metadata_rpc.sql",
  "utf8",
);
assert.match(attachmentSql, /for update;/i);
assert.match(attachmentSql, /P0_EXPENSE_ATTACHMENT_METADATA_DUPLICATE/);
assert.doesNotMatch(attachmentSql, /p_(?:bucket|storage_path|public_url|external_url)/i);

const api = readFileSync("js/api/expense-detail-api.js", "utf8");
const page = readFileSync("js/pages/expense-detail-page.js", "utf8");
assert.match(api, /p_expected_updated_at: payload\.expectedUpdatedAt/);
assert.match(page, /expectedUpdatedAt: expense\.updated_at/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(
    source,
    /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,
    `page-layer DML regression: ${pageFile}`,
  );
}
for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]?role/i, `browser service-role marker: ${browserFile}`);
}

const closure = readFileSync(
  "sql/current/school_p0_expense_permission_phase2_closure_20260804.sql",
  "utf8",
);
assert.match(closure, /school_void_teacher_wage_lock_admin_impl_20260804/);
assert.match(closure, /school_request_cash_expense_payment_confirmation[\s\S]*?to service_role/i);
assert.match(closure, /school_mark_cash_expense_request_submitted[\s\S]*?to service_role/i);
assert.match(closure, /school_mark_cash_expense_confirmed[\s\S]*?to service_role/i);
assert.match(closure, /school_mark_cash_expense_rejected[\s\S]*?to service_role/i);
assert.match(closure, /update storage\.buckets[\s\S]*?set public=false/i);
assert.match(closure, /school_allow_all_storage_expense_files_insert[\s\S]*?school_get_current_app_membership/i);
assert.match(closure, /school_allow_all_storage_expense_files_update[\s\S]*?using \(false\) with check \(false\)/i);
assert.match(closure, /school_allow_all_storage_expense_files_delete[\s\S]*?using \(false\)/i);
assert.doesNotMatch(closure, /student_tuition_(?:preview|generate|cash_submit)/);

for (const legacyFile of [
  "sql/current/school_deprecate_teacher_wage_payment_cash_rpc.sql",
  "sql/current/school_teacher_wage_cash_confirmation_all_scope_rpc.sql",
]) {
  const source = readFileSync(legacyFile, "utf8");
  assert.match(source, /set search_path = pg_catalog, public/i);
  assert.match(source, /from public, anon, authenticated, service_role/i);
  assert.match(source, /to service_role/i);
  assert.doesNotMatch(source, /to authenticated, service_role/i);
}

const allChangedScope = [
  ...interactiveFiles,
  "sql/current/school_p0_expense_permission_phase2_closure_20260804.sql",
  "sql/current/school_p0_expense_permission_phase2_deploy_20260804.sql",
  "sql/current/school_p0_expense_permission_phase2_amendment_20260804.sql",
].map((file) => readFileSync(file, "utf8")).join("\n");
assert.doesNotMatch(allChangedScope, /school_create_pending_cash_expense_record/);
assert.doesNotMatch(allChangedScope, /drop\s+(?:table|function|column)|truncate\s+|delete\s+from/i);

console.log("P0_EXPENSE_PERMISSION_PHASE2_STATIC_TEST_PASS");
