import assert from "node:assert/strict";
import fs from "node:fs";

const migration = fs.readFileSync(
  "sql/current/school_student_settlement_registered_variance_preview_20260816.sql",
  "utf8",
);
const rollback = fs.readFileSync(
  "sql/current/school_student_settlement_registered_variance_preview_exact_rollback_20260816.sql",
  "utf8",
);
const rehearsal = fs.readFileSync(
  "sql/current/school_student_settlement_registered_variance_preview_rollback_rehearsal_20260816.sql",
  "utf8",
);
const postdeploy = fs.readFileSync(
  "sql/current/school_student_settlement_registered_variance_preview_postdeploy_readonly_20260816.sql",
  "utf8",
);

assert.equal(
  (migration.match(/create or replace function public\./gi) || []).length,
  1,
  "migration must replace exactly one reader",
);
assert.match(migration, /school_preview_student_settlement_adjustment_dialog/);
assert.doesNotMatch(migration, /\b(create|alter|drop)\s+table\b/i);
assert.doesNotMatch(migration, /\b(insert|update|delete|merge|truncate)\s+(into|public\.|storage\.)/i);
assert.match(migration, /security definer/);
assert.match(migration, /set search_path=pg_catalog,public/);
assert.match(migration, /school_tuition_p0f_source_lines/);
assert.match(migration, /school_get_student_monthly_settlement_summary_p0f_legacy/);
assert.match(migration, /registered_variance_contract_version/);
for (const field of [
  "registered_pending_hours",
  "registered_pending_amount_jpy",
  "registered_overage_hours",
  "registered_overage_amount_jpy",
  "registered_overage_amount_cny",
  "registered_net_direction",
  "registered_net_hours",
  "registered_net_amount_jpy",
  "registered_source_count",
  "unresolved_planned_count",
  "registered_overage_included_in_system_difference",
  "variance_summary_status",
  "variance_summary_manifest_sha256",
]) {
  assert.ok(migration.includes(`'${field}'`), `missing read-only field ${field}`);
}
assert.match(migration, /source_treatment_mode='separate_makeup_and_overage_v1'/);
assert.match(migration, /v_preview\.system_difference_cny/);
assert.match(migration, /v_preview\.lesson_variance_manifest_sha256/);

assert.match(rollback, /44c998671550d2288c7f4960d6d52fdc/);
assert.doesNotMatch(rollback, /registered_pending_hours/);
assert.match(rehearsal, /EXACT_ROLLBACK_REHEARSAL_PASS/);
assert.match(rehearsal, /REGISTERED_VARIANCE_TARGET_SUMMARY_MISMATCH/);
assert.match(rehearsal, /REGISTERED_VARIANCE_PENDING_ONLY_FAILED/);
assert.match(rehearsal, /REGISTERED_VARIANCE_OVERAGE_ONLY_FAILED/);
assert.match(rehearsal, /REGISTERED_VARIANCE_EMPTY_FAILED/);
assert.match(rehearsal, /REGISTERED_VARIANCE_NET_MODE_SOURCE_LINES_FAILED/);
assert.match(rehearsal, /SETTLEMENT_LESSON_SOURCE_UNRESOLVED/);
assert.match(rehearsal, /SETTLEMENT_MONTH_NOT_CLOSED/);
assert.equal(
  rehearsal.split("\n").filter((line) => /^rollback;$/i.test(line.trim())).length,
  2,
);

assert.match(postdeploy, /13fe9c288069ae785887559e6b475138/);
assert.match(postdeploy, /REGISTERED_VARIANCE_PREVIEW_OLD_FIELDS_CHANGED/);
assert.match(postdeploy, /SCHOOL_REGISTERED_VARIANCE_PREVIEW_POSTDEPLOY_READONLY_PASS/);
assert.doesNotMatch(postdeploy, /\b(insert|update|delete|merge|truncate)\b/i);

console.log("student settlement registered variance Preview SQL static contract: PASS");
