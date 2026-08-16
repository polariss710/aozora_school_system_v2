import assert from "node:assert/strict";
import fs from "node:fs";
import {
  CROSS_MONTH_MAKEUP_DATE_MONTH_MESSAGE,
  validateCrossMonthMakeupLessonDate,
} from "../js/utils/lesson-settlement-filter.js";

const page = fs.readFileSync("js/pages/lesson-page.js", "utf8");
const api = fs.readFileSync("js/api/lesson-api.js", "utf8");
const html = fs.readFileSync("lesson.html", "utf8");
const app = fs.readFileSync("js/lesson-app.js", "utf8");
const config = fs.readFileSync("js/config.js", "utf8");
const writer = fs.readFileSync(
  "sql/current/school_replace_unconsumed_makeup_actual_v1_20260804.sql",
  "utf8"
);

const guidance = "补课完成日期必须属于当前页面月份。若补课实际发生在其他月份，请先切换到实际发生月份，再在‘来源月份’中选择原待补课程所在月份。";
assert.match(html, /请在补课实际发生月份登记；来源课程可以选择以前月份。/);
assert.doesNotMatch(html, /<small[^>]*>补课完成日期必须属于当前页面月份。<\/small>/);
assert.equal((html.match(/补课完成日期必须属于当前页面月份。/g) || []).length, 0);
assert.doesNotMatch(fs.readFileSync("lesson-detail.html", "utf8"), /补课完成日期必须属于当前页面月份。/);
assert.doesNotMatch(page, /<small[^>]*>补课完成日期必须属于当前页面月份。<\/small>/);
assert.equal(CROSS_MONTH_MAKEUP_DATE_MONTH_MESSAGE, guidance);
assert.equal(validateCrossMonthMakeupLessonDate("2026-08-11", "2026-08").status, "valid");
assert.deepEqual(validateCrossMonthMakeupLessonDate("2026-07-31", "2026-08"), {
  status: "error",
  message: guidance,
});
assert.equal(validateCrossMonthMakeupLessonDate("", "2026-08").status, "incomplete");
const untouchedInvalidDate = "2026-07-31";
validateCrossMonthMakeupLessonDate(untouchedInvalidDate, "2026-08");
assert.equal(untouchedInvalidDate, "2026-07-31");
assert.match(page, /validateCreateCrossMonthMakeupActualDateField/);
assert.match(page, /dateValidation\.status !== "valid"/);
assert.match(page, /source\.authoritative_student_month > targetMonth/);
assert.match(api, /school_list_open_lesson_credit_sources/);
assert.match(api, /school_create_lesson_credit_makeup_actual/);
assert.doesNotMatch(`${page}\n${api}`, /school_replace_unconsumed_makeup_actual_v1/);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(page, /\.from\s*\(\s*["']school_lesson_records["']\s*\)[\s\S]{0,160}\.(?:insert|update|delete|upsert)\s*\(/);
const submitFlow = page.slice(
  page.indexOf("async function handleCreateCrossMonthMakeupActualSubmit"),
  page.indexOf("async function refreshAfterCreateCrossMonthMakeupActual")
);
assert.ok(submitFlow.indexOf("if (!payload)") < submitFlow.indexOf("createCrossMonthMakeupCompletedActualFromPlanned(payload)"));

assert.match(writer, /SECURITY DEFINER/i);
assert.match(writer, /SET search_path = pg_catalog, public/i);
assert.match(writer, /MAKEUP_ACTUAL_REPLACEMENT_SERVICE_ROLE_REQUIRED/);
assert.match(writer, /DELETE FROM public\.school_lesson_records/);
assert.match(writer, /public\.school_create_lesson_credit_makeup_actual\(/);
assert.match(writer, /REVOKE ALL ON FUNCTION[\s\S]*FROM PUBLIC, anon, authenticated, service_role/i);
assert.match(writer, /GRANT EXECUTE ON FUNCTION[\s\S]*TO service_role/i);
assert.match(html, /makeup-date-hint-removal-20260816-1/);
assert.match(app, /makeup-date-hint-removal-20260816-1/);
assert.match(config, /APP_VERSION = "v10\.5\.46"/);

console.log("makeup actual correction static checks passed");
