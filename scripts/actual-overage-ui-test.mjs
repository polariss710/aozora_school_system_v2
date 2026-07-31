import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  PARTIAL_ACTUAL_REQUIRED_MESSAGE,
  buildActualOverageDisplay,
  buildLessonMonthSemantics,
  hasFrozenActualOverage,
  hasFrozenSettlementOverage,
  nextNaturalYearMonth,
  validateActualDurationForFlow,
} from "../js/utils/actual-overage.js";

const ordinary = (actualDurationHours, plannedDurationHours = 2) => (
  validateActualDurationForFlow({ actualDurationHours, plannedDurationHours })
);

assert.equal(ordinary(2).valid, true, "actual = planned must remain valid");
assert.equal(ordinary(2.25).valid, true, "actual > planned must be valid");
assert.deepEqual(ordinary(1.75), {
  valid: false,
  message: PARTIAL_ACTUAL_REQUIRED_MESSAGE,
});
assert.match(ordinary(1.75).message, /partial/);
assert.equal(ordinary(0).valid, false, "actual must be positive");
assert.equal(validateActualDurationForFlow({
  actualDurationHours: 1.75,
  plannedDurationHours: 2,
  isPartial: true,
}).valid, true, "partial flow accepts a positive duration below planned");
assert.equal(validateActualDurationForFlow({
  actualDurationHours: 2,
  plannedDurationHours: 2,
  isPartial: true,
}).valid, false, "partial flow must not accept equal duration");

const planned = {
  id: "planned-1",
  duration_hours: 2,
  unit_price: 999999,
};
const canonicalActual = {
  id: "actual-1",
  lesson_type: "actual",
  lesson_date: "2026-08-03",
  year_month: "2026-07",
  student_settlement_month: "2026-07",
  teacher_settlement_month: "2026-08",
  duration_hours: 2.25,
  student_duration_overage_minutes: 15,
  student_duration_overage_fee_jpy: 2500,
  student_duration_overage_policy_version: "student_duration_overage_v1",
  student_duration_overage_source: "ordinary_actual_rpc",
  student_duration_overage_decided_at: "2026-07-31T01:02:03Z",
};

assert.equal(hasFrozenActualOverage(canonicalActual), true);
assert.deepEqual(buildActualOverageDisplay(canonicalActual, planned), {
  plannedDurationHours: 2,
  actualDurationHours: 2.25,
  overageMinutes: 15,
  frozenFeeJpy: 2500,
  policyVersion: "student_duration_overage_v1",
  source: "ordinary_actual_rpc",
  decidedAt: "2026-07-31T01:02:03Z",
  sourceStudentMonth: "2026-07",
  nextStudentSettlementMonth: "2026-08",
});
assert.notEqual(
  buildActualOverageDisplay(canonicalActual, planned).frozenFeeJpy,
  planned.unit_price * 0.25,
  "display must consume the frozen fee instead of deriving it from unit price"
);

const historicalActual = {
  ...canonicalActual,
  student_duration_overage_minutes: null,
  student_duration_overage_fee_jpy: null,
  student_duration_overage_policy_version: null,
  student_duration_overage_source: null,
  student_duration_overage_decided_at: null,
};
assert.equal(hasFrozenActualOverage(historicalActual), false);
assert.equal(buildActualOverageDisplay(historicalActual, planned), null);

assert.deepEqual(buildLessonMonthSemantics(canonicalActual), {
  studentSettlementMonth: "2026-07",
  teacherWageMonth: "2026-08",
  occurrenceDate: "2026-08-03",
});
assert.equal(nextNaturalYearMonth("2026-12"), "2027-01");

assert.equal(hasFrozenSettlementOverage({
  duration_overage_minutes: 15,
  duration_overage_fee_jpy: 2500,
  duration_overage_fee_cny: 120,
  duration_overage_actual_count: 1,
  duration_overage_policy_version: "student_duration_overage_v1",
  duration_overage_source: "monthly_settlement_lock",
}), true);
assert.equal(hasFrozenSettlementOverage({
  duration_overage_minutes: null,
  duration_overage_fee_jpy: null,
  duration_overage_fee_cny: null,
  duration_overage_actual_count: null,
  duration_overage_policy_version: null,
  duration_overage_source: null,
}), false, "legacy NULL snapshot must remain silent");

const lessonPageSource = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const lessonDetailSource = readFileSync(new URL("../js/pages/lesson-detail-page.js", import.meta.url), "utf8");
const settlementPageSource = readFileSync(new URL("../js/pages/settlement-page.js", import.meta.url), "utf8");
const settlementDetailSource = readFileSync(new URL("../js/pages/settlement-detail-page.js", import.meta.url), "utf8");
const editDialogSource = readFileSync(new URL("../js/components/lesson-edit-dialog.js", import.meta.url), "utf8");
const lessonApiSource = readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const actualOverageSource = readFileSync(new URL("../js/utils/actual-overage.js", import.meta.url), "utf8");

for (const source of [lessonPageSource, lessonDetailSource, settlementPageSource, settlementDetailSource, editDialogSource]) {
  assert.doesNotMatch(source, /\.rpc\s*\(/, "page/component modules must not call RPC directly");
  assert.doesNotMatch(source, /\.(?:insert|update|delete|upsert)\s*\(/, "page/component modules must not write tables directly");
}
for (const field of [
  "student_duration_overage_minutes",
  "student_duration_overage_fee_jpy",
  "student_duration_overage_policy_version",
  "student_duration_overage_source",
  "student_duration_overage_decided_at",
]) {
  assert.match(lessonApiSource, new RegExp(`\\b${field}\\b`));
}
assert.match(lessonPageSource, /validateActualDurationForFlow/);
assert.match(lessonPageSource, /lessonUserErrorMessage/, "API diagnostics must be mapped to safe user messages");
assert.doesNotMatch(lessonPageSource, /error\.message \|\| String\(error\)/, "raw API diagnostics must not be shown to users");
assert.match(editDialogSource, /既有 actual 的时间、时长和单价已冻结/);
assert.doesNotMatch(actualOverageSource, /unit_price|lesson_fee/, "overage display helper must not read price inputs");

console.log("actual overage authoritative UI fixtures: PASS");
