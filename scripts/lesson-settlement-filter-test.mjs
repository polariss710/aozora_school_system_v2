import assert from "node:assert/strict";
import fs from "node:fs";
import {
  createLatestRequestGate,
  listStudentSettlementMonthWeeks,
  normalizeStudentSettlementWeekStart,
  validateAuthoritativeLessonRecords,
} from "../js/utils/lesson-settlement-filter.js";
import { buildLessonMonthSemantics } from "../js/utils/actual-overage.js";

const physicsId = "8b737b58-cd14-42c5-afd2-34730dcef963";
const chemistryId = "685ad45e-b5da-42ca-8f43-7732e8d6e40d";
const physics = {
  id: physicsId,
  lesson_type: "planned",
  lesson_date: "2026-08-01",
  year_month: "2026-07",
  billing_month: "2026-07",
  billing_week_start_date: "2026-07-27",
  student_settlement_month: "2026-07",
  authoritative_student_month: "2026-07",
  teacher_settlement_month: null,
};
const chemistry = {
  id: chemistryId,
  lesson_type: "planned",
  lesson_date: "2026-08-02",
  year_month: "2026-07",
  billing_month: "2026-07",
  billing_week_start_date: "2026-07-27",
  student_settlement_month: "2026-07",
  authoritative_student_month: "2026-07",
  teacher_settlement_month: null,
};

const julyWeeks = listStudentSettlementMonthWeeks("2026-07");
const augustWeeks = listStudentSettlementMonthWeeks("2026-08");
assert(julyWeeks.some((week) => (
  week.weekStart === "2026-07-27" && week.weekEnd === "2026-08-02"
)));
assert(!augustWeeks.some((week) => week.weekStart === "2026-07-27"));
assert(augustWeeks.some((week) => (
  week.weekStart === "2026-08-31" && week.weekEnd === "2026-09-06"
)));

assert.equal(normalizeStudentSettlementWeekStart("2026-07", "2026-07-27"), "2026-07-27");
assert.equal(normalizeStudentSettlementWeekStart("2026-08", "2026-07-27"), "");
assert.equal(normalizeStudentSettlementWeekStart("2026-08", "2026-08-31"), "2026-08-31");

const julyRows = validateAuthoritativeLessonRecords(
  [physics, chemistry],
  { yearMonth: "2026-07", weekStart: "2026-07-27" }
);
assert.deepEqual(julyRows.map((row) => row.id), [physicsId, chemistryId]);
assert.throws(
  () => validateAuthoritativeLessonRecords(
    [physics, chemistry],
    { yearMonth: "2026-08", weekStart: "2026-08-31" }
  ),
  /权威收费\/结算月与当前筛选不一致/
);
assert.throws(
  () => validateAuthoritativeLessonRecords(
    [physics, physics],
    { yearMonth: "2026-07" }
  ),
  /重复UUID/
);
assert.throws(
  () => validateAuthoritativeLessonRecords(
    [physics],
    { yearMonth: "2026-08", weekStart: "2026-07-27" }
  ),
  /自然周不属于当前学生结算月/
);

assert.deepEqual(buildLessonMonthSemantics(physics), {
  studentSettlementMonth: "2026-07",
  teacherWageMonth: "",
  occurrenceDate: "2026-08-01",
});
assert.deepEqual(buildLessonMonthSemantics(chemistry), {
  studentSettlementMonth: "2026-07",
  teacherWageMonth: "",
  occurrenceDate: "2026-08-02",
});

const requestGate = createLatestRequestGate();
const julyRequest = requestGate.begin();
const augustRequest = requestGate.begin();
assert.equal(requestGate.isCurrent(julyRequest), false);
assert.equal(requestGate.isCurrent(augustRequest), true);

const apiSource = fs.readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const pageSource = fs.readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const detailPageSource = fs.readFileSync(new URL("../js/pages/lesson-detail-page.js", import.meta.url), "utf8");
const htmlSource = fs.readFileSync(new URL("../lesson.html", import.meta.url), "utf8");
assert.match(apiSource, /school_list_lesson_management_records_authoritative/);
assert.doesNotMatch(apiSource, /\.eq\("year_month", yearMonth\)/);
assert.match(pageSource, /partitionAuthoritativeLessonRecords/);
assert.match(pageSource, /lessonRecordsRequestGate\.isCurrent/);
assert.match(pageSource, /lessonStatsRequestId \+= 1/);
assert.match(htmlSource, /收费归属 \/ 学生结算月/);
assert.match(htmlSource, /planned按DB收费月\/收费周筛选；actual按DB权威学生结算月筛选/);
assert.match(detailPageSource, /"收费归属月"/);
assert.match(detailPageSource, /"收费自然周"/);
assert.match(detailPageSource, /lesson\.lesson_type === "actual" \? "实际发生日期" : "预计上课日期"/);

for (const pageFile of [
  "../js/pages/lesson-page.js",
  "../js/pages/lesson-detail-page.js",
]) {
  const source = fs.readFileSync(new URL(pageFile, import.meta.url), "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/);
  assert.doesNotMatch(source, /\bsupabase\s*\.\s*from\s*\(/);
  assert.doesNotMatch(source, /\.(insert|update|delete|upsert)\s*\(/);
}

console.log("lesson settlement month filter fixtures: PASS");
