import assert from "node:assert/strict";
import fs from "node:fs";

const migration = fs.readFileSync("sql/current/school_part_time_work_p0_a2_writer_permission_closure_20260816.sql", "utf8");
const rollback = fs.readFileSync("sql/current/school_part_time_work_p0_a2_writer_permission_closure_exact_rollback_20260816.sql", "utf8");
const negative = fs.readFileSync("sql/current/school_part_time_work_p0_a2_writer_permission_negative_rollback_tests_20260816.sql", "utf8");
const postdeploy = fs.readFileSync("sql/current/school_part_time_work_p0_a2_writer_permission_postdeploy_readonly_20260816.sql", "utf8");
const api = fs.readFileSync("js/api/part-time-work-api.js", "utf8");
const page = fs.readFileSync("js/pages/part-time-work-page.js", "utf8");

const operational = [
  "school_create_part_time_work_planned_lesson",
  "school_update_part_time_work_lesson",
  "school_generate_part_time_work_actual_from_planned",
  "school_delete_part_time_work_lesson",
  "school_lock_part_time_work_monthly_settlement",
  "school_unlock_part_time_work_monthly_settlement",
  "school_create_part_time_work_income_record",
];
const retired = [
  "school_create_part_time_work_income_request",
  "school_mark_part_time_work_cash_request_submitted",
  "school_mark_part_time_work_cash_income_confirmed",
  "school_mark_part_time_work_cash_income_rejected",
];

const baselineSignaturePattern = /\('public\.(school_[^']+)',\s*'[0-9a-f]{32}'/g;
const baselineSignatures = (sql) =>
  [...sql.matchAll(baselineSignaturePattern)].map((match) => match[1]).sort();
const migrationSignatures = baselineSignatures(migration);
const rollbackSignatures = baselineSignatures(rollback);

assert.match(migration, /PTW_P0_A2_DML_WRITER_COUNT_MISMATCH/);
assert.match(migration, /v_dml_count <> 12/);
assert.match(migration, /school_require_current_part_time_work_operator/);
assert.match(migration, /school_require_current_part_time_work_admin/);
assert.match(migration, /PTW_WRITER_AUTH_REQUIRED/);
assert.match(migration, /PTW_WRITER_MEMBERSHIP_REQUIRED/);
assert.match(migration, /PTW_WRITER_ACTIVE_MEMBERSHIP_REQUIRED/);
assert.match(migration, /v_role not in \('admin','operator'\)/);
assert.match(migration, /v_role is distinct from 'admin'/);
assert.match(migration, /PTW_P0_A2_GUARD_ORDER_MISMATCH/);
assert.match(migration, /PTW_P0_A2_BUSINESS_BODY_CHANGED/);
assert.match(migration, /PTW_P0_A2_BUSINESS_FINGERPRINT_CHANGED/);
assert.match(migration, /PTW_P0_A2_TABLE_SECURITY_CHANGED/);
assert.doesNotMatch(migration, /\b(?:r|rec|row)\s+record\s*;/i);
assert.match(migration, /school_part_time_work_income_requests\s+legacy_req\s+where\s+legacy_req\.deleted_at/is);
assert.match(migration, /legacy_req\.cash_request_id\s+is\s+not\s+null\s+or\s+legacy_req\.cash_transaction_id/is);
assert.doesNotMatch(migration, /(?:insert\s+into|update|delete\s+from)\s+public\.school_(?:part_time_work|income_records)/i);
assert.equal(migrationSignatures.length, 12);
assert.deepEqual(migrationSignatures, rollbackSignatures);

for (const writer of operational) {
  assert.match(migration, new RegExp(`revoke all on function public\\.${writer}\\(`, "i"));
  assert.match(migration, new RegExp(`grant execute on function public\\.${writer}\\([\\s\\S]*?to authenticated`, "i"));
  assert.match(api, new RegExp(`supabase\\.rpc\\("${writer}"`));
}
for (const writer of retired) {
  assert.match(migration, new RegExp(`revoke all on function public\\.${writer}\\(`, "i"));
  assert.doesNotMatch(api, new RegExp(writer));
}

assert.match(migration, /grant execute on function public\.school_import_historical_part_time_work_batch\(jsonb\)\s+to service_role/i);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(page, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/);
assert.match(negative, /PTW_P0_A2_PRODUCTION_NEGATIVE_ROLLBACK_PASS/);
assert.match(negative, /select \* from ptw_p0_a2_negative_results/);
assert.match(postdeploy, /begin transaction isolation level repeatable read read only/);
assert.match(postdeploy, /rollback;/);
assert.match(rollback, /DO NOT EXECUTE/);
assert.match(rollback, /drop function public\.school_require_current_part_time_work_operator\(\)/);
assert.match(rollback, /drop function public\.school_require_current_part_time_work_admin\(\)/);
assert.doesNotMatch(rollback, /\b(?:r|rec|row)\s+record\s*;/i);
assert.match(rollback, /pg_get_userbyid\(p\.proowner\).*?'postgres'/s);
assert.match(rollback, /not \(select p\.prosecdef/s);
assert.doesNotMatch(negative, /\b(?:r|rec|row)\s+record\s*;/i);

console.log("PTW_P0_A2_PERMISSION_STATIC_TEST_PASS");
