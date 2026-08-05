import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const core = readFileSync("sql/current/school_student_status_phase_b2_legacy_freeze_core_20260806.sql", "utf8");
const deploy = readFileSync("sql/current/school_student_status_phase_b2_legacy_freeze_deploy_20260806.sql", "utf8");
const rollback = readFileSync("sql/tests/student_status_phase_b2_legacy_freeze_rollback_test_20260806.sql", "utf8");
const postdeploy = readFileSync("sql/current/school_student_status_phase_b2_legacy_freeze_postdeploy_20260806.sql", "utf8");
const api = readFileSync("js/api/student-api.js", "utf8");
const page = readFileSync("js/pages/student-page.js", "utf8");
const html = readFileSync("student.html", "utf8");
const config = readFileSync("js/config.js", "utf8");

assert.match(core, /school_guard_legacy_student_status_immutable_v1/);
assert.match(core, /STUDENT_LEGACY_STATUS_INSERT_MUST_BE_ACTIVE/);
assert.match(core, /STUDENT_LEGACY_STATUS_IMMUTABLE/);
assert.match(core, /school_create_student_profile_v2\(\s*p_name text,[\s\S]*?p_note text default null\s*\)/);
assert.match(core, /school_update_student_profile_v2\(\s*p_student_id uuid,[\s\S]*?p_expected_updated_at timestamptz default null\s*\)/);
assert.match(core, /school_require_current_app_admin\(\)/);
assert.match(core, /for update/);
assert.match(core, /v_student\.updated_at is distinct from p_expected_updated_at/);
assert.match(core, /revoke all on function public\.school_record_student_status_event_v1[\s\S]*from public, anon, authenticated, service_role/i);
assert.match(core, /revoke all on function public\.school_correct_student_status_event_v1[\s\S]*from public, anon, authenticated, service_role/i);
assert.doesNotMatch(core, /grant execute on function public\.school_(?:record|correct)_student_status_event_v1/i);
assert.match(deploy, /begin;[\s\S]*legacy_freeze_core_20260806\.sql[\s\S]*commit;/i);
assert.match(rollback, /STUDENT_STATUS_PHASE_B2_LEGACY_FREEZE_ROLLBACK_PASS/);
assert.match(postdeploy, /STUDENT_STATUS_PHASE_B2_LEGACY_FREEZE_POSTDEPLOY_PASS/);

assert.doesNotMatch(api, /p_status\s*:/);
assert.match(api, /p_expected_updated_at:\s*payload\.expectedUpdatedAt/);
assert.doesNotMatch(page, /createStudentStatusSelect|editStudentStatusSelect|payload\.status|EDITABLE_STUDENT_STATUS_OPTIONS/);
assert.match(page, /expectedUpdatedAt:\s*editingStudent\.updated_at/);
assert.doesNotMatch(html, /id="(?:create|edit)StudentStatusSelect"/);
assert.equal((html.match(/学生状态管理正在切换为按月份生效，当前暂不可修改。/g) || []).length, 2);
assert.match(config, /APP_VERSION = "v10\.5\.7"/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(
    source,
    /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,
    `page-layer table DML regression: ${pageFile}`
  );
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker regression: js/${browserFile}`);
}

console.log("STUDENT_STATUS_PHASE_B2_LEGACY_FREEZE_STATIC_TEST_PASS");
