import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const core = readFileSync("sql/current/school_student_status_phase_b3_writer_authority_core_20260806.sql", "utf8");
const deploy = readFileSync("sql/current/school_student_status_phase_b3_writer_authority_deploy_20260806.sql", "utf8");
const rehearsal = readFileSync("sql/tests/student_status_phase_b3_writer_authority_rehearsal_20260806.sql", "utf8");
const rollback = readFileSync("sql/tests/student_status_phase_b3_writer_authority_rollback_test_20260806.sql", "utf8");
const postdeploy = readFileSync("sql/current/school_student_status_phase_b3_writer_authority_postdeploy_20260806.sql", "utf8");
const cancellation = readFileSync("sql/current/school_create_cancelled_actual_lesson_from_planned_rpc.sql", "utf8");
const config = readFileSync("js/config.js", "utf8");

assert.equal(
  (core.match(/select pg_temp\.school_b3_replace_function_fragments\(/gi) || []).length,
  12,
  "all twelve exact production definitions must cut over atomically",
);
assert.match(core, /school_assert_student_active_at_business_month_v1[\s\S]*school_resolve_student_status_at_month_core_v1/);
assert.match(core, /security definer[\s\S]*set search_path = pg_catalog, public/i);
assert.match(core, /revoke all on function public\.school_assert_student_active_at_business_month_v1[\s\S]*from public, anon, authenticated, service_role/i);
assert.match(core, /school_resolve_planned_billing_attribution\(p_lesson_date,null\)/);
assert.match(core, /inactive_occurrences[\s\S]*school_resolve_planned_billing_attribution\(null,r\.lesson_date\)/);
assert.match(core, /inactive_import_rows[\s\S]*school_resolve_planned_billing_attribution\(r\.lesson_date,null\)/);
assert.match(core, /STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH student_id=%s lesson_date=%s billing_month=%s/);
assert.match(core, /p_student_id is distinct from v_lesson\.student_id[\s\S]*v_target_student_status_month is distinct from v_old_year_month/);
assert.match(core, /date_trunc\('month',clock_timestamp\(\) at time zone 'Asia\/Tokyo'\)::date/g);
assert.match(core, /v_rule\.is_active is not true and p_is_active is true/);
assert.doesNotMatch(core, /\b(?:insert|update|delete)\s+(?:into\s+)?public\.school_(?:students|lesson_records|student_status_events|student_monthly_settlements|income_records|student_tuition_bills|teacher_wage_rules)\b/i);

assert.doesNotMatch(cancellation, /coalesce\(student\.status/i);
assert.match(cancellation, /v_membership_role not in \('admin','operator'\)/);
assert.match(cancellation, /school_tuition_p0b1_lock_existing_lesson_scope/);
assert.match(cancellation, /extract\(epoch from \(v_end_value - v_start_value\)\)/);
assert.match(cancellation, /'actual'[\s\S]*'cancelled'[\s\S]*false[\s\S]*0[\s\S]*0/);
assert.match(cancellation, /set status = 'pending_makeup'/);

assert.match(deploy, /begin;[\s\S]*writer_authority_core_20260806\.sql[\s\S]*commit;/i);
assert.match(rehearsal, /writer_authority_postdeploy_20260806\.sql[\s\S]*rollback;/i);
assert.match(rollback, /STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_ROLLBACK_PASS[\s\S]*rollback;/i);
assert.match(postdeploy, /STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_POSTDEPLOY_PASS/);
assert.match(postdeploy, /school_get_weekly_lesson_operations\(date\)[\s\S]*e7eac5f3bb07c31ad15e750e8721c01f/);
assert.match(config, /APP_VERSION = "v10\.5\.9"/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(
    source,
    /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,
    `page-layer table DML regression: ${pageFile}`,
  );
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker: js/${browserFile}`);
}

console.log("STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_STATIC_TEST_PASS");
