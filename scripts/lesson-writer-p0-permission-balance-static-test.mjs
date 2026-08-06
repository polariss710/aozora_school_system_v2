import assert from "node:assert/strict";
import fs from "node:fs";

const read = (path) => fs.readFileSync(path, "utf8");
const core = read("sql/current/school_lesson_writer_p0_permission_balance_closure_core_20260806.sql");
const deploy = read("sql/current/school_lesson_writer_p0_permission_balance_closure_deploy_20260806.sql");
const postdeploy = read("sql/current/school_lesson_writer_p0_permission_balance_closure_postdeploy_20260806.sql");
const api = read("js/api/lesson-api.js");
const page = read("js/pages/lesson-page.js");
const dialog = read("js/components/lesson-edit-dialog.js");
const lessonHtml = read("lesson.html");
const detailHtml = read("lesson-detail.html");

assert.match(core, /school_assert_active_lesson_writer\(\)/);
assert.match(core, /role not in \('admin','operator'\)/);
assert.match(core, /LESSON_WRITER_(AUTH|MEMBERSHIP|ACTIVE_MEMBERSHIP|ROLE)_REQUIRED/g);
assert.match(core, /school_get_lesson_credit_raw_remaining_hours/);
assert.match(core, /LESSON_MAKEUP_CREDIT_DATA_INCONSISTENT/);
assert.match(core, /LESSON_MAKEUP_CREDIT_EXHAUSTED/);
assert.match(core, /LESSON_MAKEUP_CREDIT_EXCEEDED/);
assert.match(core, /new\.voided_at/);
assert.match(core, /new\.is_billable,new\.lesson_fee,new\.voided_at/);
assert.match(core, /LESSON_MAKEUP_SOURCE_STATUS_INVALID/);
assert.match(core, /order by source_id/);
assert.match(core, /LESSON_TIME_GRID_INVALID/);
assert.match(core, /LESSON_DURATION_MISMATCH/);
assert.match(core, /new\.actual_minutes:=v_minutes/);
assert.match(core, /new\.status='cancelled'[\s\S]*new\.actual_minutes:=0/);
assert.match(core, /new\.status='makeup_completed'[\s\S]*new\.is_billable:=false[\s\S]*new\.lesson_fee:=0/);

for (const rpc of [
  "school_create_planned_lesson_record_with_venue",
  "school_generate_planned_lessons_batch_with_venue",
  "school_update_lesson_record_guarded_with_venue",
  "school_create_actual_lesson_from_planned",
  "school_create_cancelled_actual_lesson_from_planned",
  "school_create_lesson_credit_makeup_actual",
  "school_create_partial_completed_actual_from_planned",
  "school_void_planned_lesson",
  "school_delete_fresh_planned_lesson",
]) {
  assert.match(core, new RegExp(`grant execute on function public\\.${rpc}`));
  assert.match(core, new RegExp(`public\\.${rpc}`));
  assert.match(postdeploy, new RegExp(`public\\.${rpc}`));
}

assert.match(deploy, /begin;[\s\S]*\\ir school_lesson_writer_p0_permission_balance_closure_core_20260806\.sql[\s\S]*commit;/i);
assert.doesNotMatch(deploy, /\\ir .*tuition_atomic_void_reissue/);
assert.doesNotMatch(core, /\b(insert|update|delete)\s+(into\s+)?public\.school_(students|teachers|student_monthly_settlements|teacher_wage|income|student_tuition)/i);

assert.match(api, /supabase\.rpc\("school_create_lesson_credit_makeup_actual"/);
assert.match(api, /supabase\.rpc\(\s*"school_update_lesson_record_guarded_with_venue"/);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(page, /\.from\([^)]*\)\s*\.\s*(insert|update|delete|upsert)\s*\(/);
assert.doesNotMatch(dialog, /\.rpc\s*\(/);
assert.doesNotMatch(`${lessonHtml}\n${detailHtml}`, /BusinessEntitySelect|业务归属/);
assert.doesNotMatch(page, /lessonBusinessEntitySelect|business_entity_id\s*\)/);
assert.match(page, /requirePrimarySchoolBusinessEntityId/);
assert.equal(fs.existsSync("js/legacy-core.js"), false);

console.log("LESSON_WRITER_P0_STATIC_PASS");
