import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  listStudentSettlementMonthWeeks,
  validateAuthoritativeLessonRecords,
} from "../js/utils/lesson-settlement-filter.js";
import { buildLessonMonthSemantics } from "../js/utils/actual-overage.js";
import { lessonUserErrorMessage } from "../js/utils/lesson-error-message.js";
import {
  plannedAirconConditionLabel,
  shouldDisplayPlannedAirconDetails,
} from "../js/utils/planned-aircon-display.js";

const crossMonthPlanned = {
  id: "aa55dc2e-3b1b-4d2d-863f-9f64e84b8578",
  lesson_type: "planned",
  lesson_date: "2026-09-06",
  year_month: "2026-09",
  billing_week_start_date: "2026-08-31",
  billing_month: "2026-08",
  student_settlement_month: "2026-08",
  authoritative_student_month: "2026-08",
  fee_calculation_version: "planned_weekend_venue_whole_hour_aircon_v2",
  base_lesson_fee_jpy: 17000,
  aircon_unit_price_jpy_snapshot: 330,
  aircon_billable_hours_snapshot: 2,
  aircon_fee_jpy: 660,
  lesson_total_fee_jpy: 17660,
};

assert.deepEqual(
  validateAuthoritativeLessonRecords(
    [crossMonthPlanned],
    { yearMonth: "2026-08", weekStart: "2026-08-31" }
  ).map((row) => row.id),
  [crossMonthPlanned.id]
);
assert.throws(
  () => validateAuthoritativeLessonRecords([crossMonthPlanned], { yearMonth: "2026-09" }),
  /权威收费\/结算月与当前筛选不一致/
);
assert.equal(buildLessonMonthSemantics(crossMonthPlanned).studentSettlementMonth, "2026-08");

const augustWeeks = listStudentSettlementMonthWeeks("2026-08");
const septemberWeeks = listStudentSettlementMonthWeeks("2026-09");
assert(augustWeeks.some((week) => week.weekStart === "2026-08-31" && week.weekEnd === "2026-09-06"));
assert(!septemberWeeks.some((week) => week.weekStart === "2026-08-31"));
assert.equal(septemberWeeks[0]?.weekStart, "2026-09-07");

assert.equal(
  lessonUserErrorMessage(new Error("PLANNED_DATE_OUTSIDE_BILLING_WEEK")),
  "预计上课日期必须位于原收费自然周内。"
);
assert.equal(
  lessonUserErrorMessage(new Error("PLANNED_BILLING_ATTRIBUTION_IMMUTABLE")),
  "普通编辑不能修改课时的收费自然周或收费月份。"
);
assert.equal(
  lessonUserErrorMessage(new Error("PLANNED_BILLING_ATTRIBUTION_REQUIRED")),
  "该历史课时缺少收费归属，请先完成数据整理。"
);
assert.equal(plannedAirconConditionLabel({
  ...crossMonthPlanned,
  aircon_charge_status: "calculated",
}), "周末固定办公室计费");
assert.equal(shouldDisplayPlannedAirconDetails(crossMonthPlanned), true);

const api = readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const page = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const detail = readFileSync(new URL("../js/pages/lesson-detail-page.js", import.meta.url), "utf8");
const detailApi = readFileSync(new URL("../js/api/lesson-detail-api.js", import.meta.url), "utf8");
const editDialog = readFileSync(new URL("../js/components/lesson-edit-dialog.js", import.meta.url), "utf8");
const settlementApi = readFileSync(new URL("../js/api/settlement-api.js", import.meta.url), "utf8");
const settlementDetailApi = readFileSync(new URL("../js/api/settlement-detail-api.js", import.meta.url), "utf8");
const wageApi = readFileSync(new URL("../js/api/wage-api.js", import.meta.url), "utf8");
const voidDialog = readFileSync(new URL("../js/components/lesson-void-dialog.js", import.meta.url), "utf8");
const deleteDialog = readFileSync(new URL("../js/components/lesson-delete-dialog.js", import.meta.url), "utf8");
const closure = readFileSync(new URL(
  "../sql/current/school_lesson_r2_f_f2_b_year_month_production_closure.sql",
  import.meta.url
), "utf8");
const cutover = readFileSync(new URL(
  "../sql/current/school_lesson_r2_f_f2_billing_week_invariant_cutover.sql",
  import.meta.url
), "utf8");

assert.match(api, /school_list_lesson_management_records_authoritative/);
assert.match(api, /p_week_start:\s*options\.weekStart \|\| null/);
assert.match(api, /school_resolve_lesson_student_month_authoritative/);
assert.match(api, /authoritative_student_month/);
assert.doesNotMatch(page, /plannedAirconPolicyLabel|空调策略/);
assert.doesNotMatch(detail, /plannedAirconPolicyLabel|空调策略/);
assert.match(detail, /"收费归属月"/);
assert.match(detail, /"收费自然周"/);
assert.doesNotMatch(detail, /计划课时账期（billing_month）/);
assert.doesNotMatch(editDialog, /formatMonth\(lesson\.year_month\)/);
assert.match(detailApi, /lesson\.authoritative_student_month/);
assert.doesNotMatch(page, /displayValue\(record\.fee_calculation_version\)/);
assert.doesNotMatch(detail, /displayValue\(planned\.fee_calculation_version\)/);
assert.match(cutover, /PLANNED_DATE_OUTSIDE_BILLING_WEEK/);
assert.match(cutover, /PLANNED_BILLING_ATTRIBUTION_IMMUTABLE/);
assert.match(cutover, /school_lesson_records_planned_student_month_match_chk/);
assert.match(cutover, /school_lesson_records_planned_date_within_billing_week_chk/);
assert.match(cutover, /lesson\.billing_week_start_date=p_week_start/);
assert.match(closure, /school_resolve_r1d_e_c_lesson_student_month/);
assert.match(closure, /school_resolve_planned_billing_attribution/);
assert.doesNotMatch(page, /plannedLesson\.year_month/);
assert.doesNotMatch(page, /sourcePlanned\.year_month/);
assert.match(settlementApi, /school_list_lesson_management_records_authoritative/);
assert.doesNotMatch(
  settlementApi,
  /from\("school_lesson_records"\)[\s\S]{0,240}\.eq\("year_month", yearMonth\)/
);
assert.match(settlementDetailApi, /school_list_lesson_management_records_authoritative/);
assert.match(wageApi, /school_resolve_lesson_student_month_authoritative/);
assert.doesNotMatch(wageApi, /authoritative_student_month \|\| row\.year_month/);
assert.match(voidDialog, /formatMonth\(lesson\.authoritative_student_month\)/);
assert.match(deleteDialog, /formatMonth\(lesson\.authoritative_student_month\)/);

for (const pageSource of [page, detail]) {
  assert.doesNotMatch(pageSource, /\.rpc\s*\(/);
  assert.doesNotMatch(pageSource, /supabase\.(?:from|rpc)\s*\(/);
}

console.log("lesson billing-week invariant UI/API fixtures: PASS");
