import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  partitionAuthoritativeLessonRecords,
  validateAuthoritativeLessonRecords,
} from "../js/utils/lesson-settlement-filter.js";

const targetLegacyPlanned = {
  id: "300751ba-2ea5-41f0-97dd-45251af8e9d1",
  lesson_type: "planned",
  status: "planned",
  lesson_date: "2026-08-03",
  year_month: "2026-08",
  billing_month: null,
  billing_week_start_date: null,
  student_settlement_month: null,
  teacher_settlement_month: null,
  authoritative_student_month: "2026-08",
};

const crossMonthPlanned = {
  id: "aa55dc2e-3b1b-4d2d-863f-9f64e84b8578",
  lesson_type: "planned",
  status: "planned",
  lesson_date: "2026-09-06",
  year_month: "2026-09",
  billing_month: "2026-08",
  billing_week_start_date: "2026-08-31",
  student_settlement_month: "2026-08",
  teacher_settlement_month: null,
  authoritative_student_month: "2026-08",
};

const pairedActual = {
  id: "f2fc0000-0000-4000-8000-00000000a001",
  lesson_type: "actual",
  status: "completed",
  lesson_date: "2026-09-06",
  year_month: "2026-09",
  billing_month: null,
  billing_week_start_date: null,
  student_settlement_month: "2026-08",
  teacher_settlement_month: "2026-09",
  authoritative_student_month: "2026-08",
  planned_lesson_id: crossMonthPlanned.id,
};

const augustMonth = partitionAuthoritativeLessonRecords(
  [targetLegacyPlanned, crossMonthPlanned, pairedActual],
  { yearMonth: "2026-08" }
);
assert.deepEqual(
  augustMonth.accepted.map((row) => row.id),
  [targetLegacyPlanned.id, crossMonthPlanned.id, pairedActual.id]
);
assert.deepEqual(augustMonth.rejected, []);

const augustWeek = partitionAuthoritativeLessonRecords(
  [crossMonthPlanned, pairedActual],
  { yearMonth: "2026-08", weekStart: "2026-08-31" }
);
assert.deepEqual(
  augustWeek.accepted.map((row) => row.id),
  [crossMonthPlanned.id, pairedActual.id]
);

const isolatedMismatch = {
  ...targetLegacyPlanned,
  id: "f2fc0000-0000-4000-8000-00000000a002",
  authoritative_student_month: "2026-09",
};
const isolated = partitionAuthoritativeLessonRecords(
  [targetLegacyPlanned, isolatedMismatch],
  { yearMonth: "2026-08" }
);
assert.deepEqual(isolated.accepted.map((row) => row.id), [targetLegacyPlanned.id]);
assert.equal(isolated.rejected.length, 1);
assert.equal(isolated.rejected[0].reason, "authoritative_month_mismatch");
assert.throws(
  () => validateAuthoritativeLessonRecords(
    [targetLegacyPlanned, isolatedMismatch],
    { yearMonth: "2026-08" }
  ),
  /权威收费\/结算月与当前筛选不一致/
);

const canonicalConflict = partitionAuthoritativeLessonRecords(
  [{ ...crossMonthPlanned, billing_month: "2026-09" }],
  { yearMonth: "2026-08" }
);
assert.equal(canonicalConflict.accepted.length, 0);
assert.equal(canonicalConflict.rejected[0]?.reason, "canonical_planned_month_mismatch");

const api = readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const page = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const html = readFileSync(new URL("../lesson.html", import.meta.url), "utf8");

const fetchLessonRecordsSource = api.match(
  /export async function fetchLessonRecords[\s\S]*?\n}\n\nexport async function fetchLessonManagementStats/
)?.[0] || "";
assert.match(fetchLessonRecordsSource, /attachAuthoritativeStudentMonths\(data \|\| \[\]\)/);
assert.doesNotMatch(fetchLessonRecordsSource, /authoritative_student_month:\s*yearMonth/);
assert.match(api, /school_resolve_lesson_student_month_authoritative/);
assert.match(page, /partitionAuthoritativeLessonRecords/);
assert.match(page, /rejectedLessonRecords = validation\.rejected/);
assert.match(page, /其余合法记录和权威统计继续显示/);
assert.match(page, /return safeText\(record\?\.authoritative_student_month\)/);
assert.match(html, /id="lessonValidationWarning"/);
assert.doesNotMatch(page, /record\?\.year_month\s*\|\|/);
assert.doesNotMatch(page, /record\.lesson_date\.slice\(0,\s*7\)/);

for (const pageSource of [page]) {
  assert.doesNotMatch(pageSource, /\.rpc\s*\(/);
  assert.doesNotMatch(pageSource, /supabase\.(?:from|rpc)\s*\(/);
}

console.log("lesson authoritative-month refresh regression: PASS");
