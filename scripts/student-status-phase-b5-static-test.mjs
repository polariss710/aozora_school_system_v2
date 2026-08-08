import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const core = readFileSync("sql/current/school_student_status_phase_b5_core_20260807.sql", "utf8");
const backendDeploy = readFileSync("sql/current/school_student_status_phase_b5_backend_deploy_20260807.sql", "utf8");
const enable = readFileSync("sql/current/school_student_status_phase_b5_enable_writers_20260807.sql", "utf8");
const rollback = readFileSync("sql/tests/student_status_phase_b5_rollback_test_20260807.sql", "utf8");
const postdeploy = readFileSync("sql/current/school_student_status_phase_b5_postdeploy_20260807.sql", "utf8");
const api = readFileSync("js/api/student-status-api.js", "utf8");
const studentApi = readFileSync("js/api/student-api.js", "utf8");
const page = readFileSync("js/pages/student-page.js", "utf8");
const html = readFileSync("student.html", "utf8");
const config = readFileSync("js/config.js", "utf8");

assert.match(core, /school_preview_student_status_transition_core_v1/);
assert.match(core, /statement_timestamp\(\) at time zone 'Asia\/Tokyo'/);
assert.match(core, /p_input_month \+ interval '1 month'/);
assert.match(core, /STUDENT_STATUS_TRANSITION_OUT_OF_ORDER/);
assert.match(core, /STUDENT_STATUS_FUTURE_EVENT_REQUIRES_CORRECTION/);
assert.match(core, /school_require_current_app_admin\(\)/);
assert.match(core, /for update/);
assert.match(core, /school_record_student_status_event_v1\(/);
assert.match(core, /school_correct_student_status_event_v1\(\s*p_event_id uuid,\s*p_expected_row_version uuid,\s*p_expected_current_event_id uuid/);
assert.match(core, /school_preview_student_status_correction_core_v1/);
assert.match(core, /lag\(t\.status, 1, 'active'\)/);
assert.match(core, /school_list_student_status_management_v1/);
assert.match(core, /school_list_student_status_history_v1/);
assert.match(core, /revoke all on function public\.school_record_student_status_event_v1[\s\S]*authenticated/);
assert.match(core, /revoke all on function public\.school_correct_student_status_event_v1\(uuid,uuid,date,text,text,text,text\)[\s\S]*authenticated/);
assert.doesNotMatch(core, /grant execute on function public\.school_(?:transition|correct)_student_status/);
assert.match(enable, /grant execute on function public\.school_transition_student_status_v1[\s\S]*to authenticated/);
assert.match(enable, /grant execute on function public\.school_correct_student_status_event_v1\(uuid,uuid,uuid,date,text,text,text,text\)[\s\S]*to authenticated/);
assert.doesNotMatch(enable, /grant execute[\s\S]*to service_role/i);
assert.match(backendDeploy, /school_student_status_phase_b5_core_20260807\.sql[\s\S]*commit/i);
assert.match(rollback, /STUDENT_STATUS_PHASE_B5_ROLLBACK_PASS/);
assert.match(rollback, /B5_RAW_RECORD_WRITER_EXPOSED/);
assert.match(rollback, /B5_CORRECTION_VOID_REPLACEMENT_MISSING/);
assert.match(postdeploy, /STUDENT_STATUS_PHASE_B5_POSTDEPLOY_PASS/);

for (const apiName of [
  "fetchStudentStatusManagement",
  "fetchStudentStatusHistory",
  "previewStudentStatusTransition",
  "transitionStudentStatus",
  "previewStudentStatusCorrection",
  "correctStudentStatusEvent",
]) {
  assert.match(api, new RegExp(`export async function ${apiName}\\b`));
}
assert.match(api, /p_input_month:\s*monthFirst\(payload\.inputMonth\)/);
assert.doesNotMatch(page, /setMonth|addMonth|inputMonth.*\+|new Date\([^)]*inputMonth/);
assert.doesNotMatch(studentApi, /query\s*=\s*query\.eq\("status"/);
assert.match(page, /fetchStudentStatusManagement/);
assert.match(page, /isActiveAdmin\(\)/);
assert.match(page, /设置暂停/);
assert.match(page, /恢复上课/);
assert.match(page, /重新入学/);
assert.match(page, /预览生效月份/);
assert.match(page, /更正此事件/);
assert.match(page, /原事件继续保留为已作废记录/);
assert.match(html, /id="studentStatusTransitionDialog"/);
assert.match(html, /id="studentStatusHistoryDialog"/);
assert.match(html, /id="studentStatusCorrectionDialog"/);
assert.doesNotMatch(html, /状态暂不可改|学生状态管理正在切换为按月份生效/);
assert.doesNotMatch(html, /business_entity_id|个人名义|业务归属/);
assert.match(config, /APP_VERSION = "v10\.5\.24"/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(
    source,
    /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,
    `page-layer DML regression: ${pageFile}`
  );
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker: js/${browserFile}`);
}

console.log("STUDENT_STATUS_PHASE_B5_STATIC_TEST_PASS");
