import fs from "node:fs";
import assert from "node:assert/strict";

const api = fs.readFileSync("js/api/lesson-api.js", "utf8");
const page = fs.readFileSync("js/pages/lesson-page.js", "utf8");
const edit = fs.readFileSync("js/components/lesson-edit-dialog.js", "utf8");
const html = fs.readFileSync("lesson.html", "utf8");
const migration = fs.readFileSync("sql/current/school_tuition_p0b1_lesson_authority_rpc_only_20260803.sql", "utf8");

assert.equal((api.match(/p_lesson_fee:\s*null/g) || []).length, 3);
assert.doesNotMatch(api, /p_lesson_fee:\s*payload\./);
assert.match(page, /lesson_fee:\s*null/);
assert.doesNotMatch(`${page}\n${edit}`, /Math\.round\(durationHours\s*\*\s*unitPrice\)/);
assert.doesNotMatch(`${page}\n${edit}`, /is(?:Create|Actual|Makeup)?LessonFeeManual|isFeeManual/);
assert.equal((html.match(/DB 保存后确认/g) || []).length, 4);
assert.equal((html.match(/aria-readonly="true"/g) || []).length >= 4, true);
assert.match(html, /id="lessonImportPlannedSubmitButton"[^>]*disabled[^>]*>历史导入已停用/);
assert.doesNotMatch(page, /lessonImportPlannedSubmitButton\?\.addEventListener\("click"/);

assert.doesNotMatch(`${page}\n${edit}`, /\.rpc\s*\(/);
assert.doesNotMatch(`${page}\n${edit}`, /\.from\s*\(\s*["']school_lesson_records["']\s*\)[\s\S]{0,160}\.(?:insert|update|delete|upsert)\s*\(/);

assert.match(migration, /student_tuition_operation_v1/);
assert.match(migration, /lock table public\.school_lesson_records in share row exclusive mode/i);
assert.match(migration, /lock table public\.school_student_monthly_settlements in share mode/i);
assert.match(migration, /revoke all on public\.school_lesson_records from public,anon,authenticated,service_role/i);
assert.match(migration, /for select to anon,authenticated,service_role using \(true\)/i);
assert.match(migration, /LESSON_FINANCIAL_FACT_IMMUTABLE/);
assert.match(migration, /new\.lesson_fee:=case/);

console.log("lesson P0-B1 authority static test passed");
