import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const source = readFileSync("sql/current/school_weekly_lesson_operations_read_rpcs.sql", "utf8");
const deploy = readFileSync("sql/current/school_student_status_phase_b1_weekly_reader_deploy_20260805.sql", "utf8");
const rollback = readFileSync("sql/tests/student_status_phase_b1_weekly_reader_rollback_test_20260805.sql", "utf8");
const postdeploy = readFileSync("sql/current/school_student_status_phase_b1_weekly_reader_postdeploy_20260805.sql", "utf8");
const api = readFileSync("js/api/lesson-api.js", "utf8");
const page = readFileSync("js/pages/weekly-lesson-dashboard-page.js", "utf8");

function weeklyDefinition(sql) {
  const match = sql.match(/create or replace function public\.school_get_weekly_lesson_operations\([\s\S]*?\n\$\$;/i);
  assert.ok(match, "weekly reader definition missing");
  return match[0].replace(/\s+/g, " ").trim().toLowerCase();
}

const sourceDefinition = weeklyDefinition(source);
const deployDefinition = weeklyDefinition(deploy);
assert.equal(sourceDefinition, deployDefinition, "source and deployment definitions diverged");
assert.match(sourceDefinition, /where s\.app_type = 'school'/);
assert.match(sourceDefinition, /from school_students s/);
assert.doesNotMatch(sourceDefinition, /s\.status|active_students/);
assert.doesNotMatch(sourceDefinition, /school_(?:resolve_student_status|list_student_(?:month|range)_candidates)/);
assert.match(sourceDefinition, /returns table \( student_id uuid, business_entity_id uuid, weekly_planned_count bigint/);
assert.match(sourceDefinition, /oldest_credit_date date \) language sql stable set search_path = public/);

assert.doesNotMatch(deploy, /\b(?:grant|revoke)\b/i, "deployment must preserve existing ACL");
assert.doesNotMatch(deploy, /\b(?:insert|update|delete|truncate|drop|alter table)\b/i);
assert.match(deploy, /Business-model expansion declaration: none/i);

assert.match(rollback, /codex-test-b1-active/);
assert.match(rollback, /codex-test-b1-paused/);
assert.match(rollback, /codex-test-b1-left/);
assert.match(rollback, /codex-test-b1-legacy-no-event/);
assert.match(rollback, /2025-06-30/);
assert.match(rollback, /2025-07-02/);
assert.match(rollback, /PHASE_B1_DUPLICATE_OR_MISSING_ROWS/);
assert.match(rollback, /PHASE_B1_STATUS_EVENT_CHANGED_HISTORY/);
assert.match(rollback, /PHASE_B1_EMPTY_WEEK_NONZERO_RESULTS/);
assert.match(rollback, /rollback;[\s\S]*STUDENT_STATUS_PHASE_B1_WEEKLY_READER_ROLLBACK_PASS/i);
assert.match(postdeploy, /STUDENT_STATUS_PHASE_B1_WEEKLY_READER_POSTDEPLOY_PASS/);

assert.match(api, /export async function fetchWeeklyLessonOperations\(weekStart\)[\s\S]*?supabase\.rpc\("school_get_weekly_lesson_operations"/);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(page, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const pageSource = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(pageSource, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(
    pageSource,
    /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,
    `page-layer DML regression: ${pageFile}`,
  );
}

for (const browserFile of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const browserSource = readFileSync(`js/${browserFile}`, "utf8");
  assert.doesNotMatch(browserSource, /SERVICE_ROLE|service[_-]role/i, `browser service-role marker: js/${browserFile}`);
}

console.log("STUDENT_STATUS_PHASE_B1_WEEKLY_READER_STATIC_TEST_PASS");
