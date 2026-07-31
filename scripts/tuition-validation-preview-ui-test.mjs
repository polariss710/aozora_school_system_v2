import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  createLatestTuitionPreviewRequestGate,
  formatAuthoritativeBillingWeek,
  validateTuitionValidationPreviewDetails,
} from "../js/utils/tuition-validation-preview.js";

const STUDENT_ID = "11111111-1111-4111-8111-111111111111";
const ENTITY_ID = "22222222-2222-4222-8222-222222222222";

function candidate(
  id,
  billingMonth,
  weekStart,
  lessonDate,
  lessonCount,
  durationHours,
  baseLessonFee,
  airconRate = 0,
  airconFee = 0
) {
  const lessonTotalFee = baseLessonFee + airconFee;
  return {
    planned_lesson_id: id,
    student_id: STUDENT_ID,
    business_entity_id: ENTITY_ID,
    billing_month: billingMonth,
    billing_week_start_date: weekStart,
    lesson_date: lessonDate,
    lesson_count: lessonCount,
    duration_hours: durationHours,
    unit_price_jpy: baseLessonFee / durationHours,
    base_lesson_fee_jpy: baseLessonFee,
    aircon_rate_jpy_per_hour: airconRate,
    aircon_billable_hours: airconRate ? durationHours : 0,
    aircon_fee_jpy: airconFee,
    course_total_jpy: lessonTotalFee,
    complete_row_hash: "c".repeat(64),
    candidate_line_hash: "d".repeat(64),
  };
}

function response(billingMonth, candidates, overrides = {}) {
  return {
    feature_state: "validation_preview_only",
    student_id: STUDENT_ID,
    business_entity_id: ENTITY_ID,
    billing_month: billingMonth,
    previous_settlement_month: "2026-06",
    previous_settlement_id: null,
    previous_carryover_cny: 0,
    candidate_count: candidates.length,
    total_lesson_count: candidates.reduce((sum, row) => sum + row.lesson_count, 0),
    total_duration_hours: candidates.reduce((sum, row) => sum + row.duration_hours, 0),
    total_base_lesson_fee_jpy: candidates.reduce((sum, row) => sum + row.base_lesson_fee_jpy, 0),
    total_aircon_fee_jpy: candidates.reduce((sum, row) => sum + row.aircon_fee_jpy, 0),
    total_fee_jpy: candidates.reduce((sum, row) => sum + row.course_total_jpy, 0),
    bill_amount_jpy: candidates.reduce((sum, row) => sum + row.course_total_jpy, 0),
    currency: "JPY",
    billing_exchange_rate: 0.05,
    billing_amount_cny: 1700,
    billing_amount_currency: "CNY",
    existing_tuition_bill_id: null,
    existing_tuition_bill_status: null,
    existing_income_record_id: null,
    existing_income_status: null,
    candidate_uuid_md5: "a".repeat(32),
    candidate_manifest_sha256: "b".repeat(64),
    generation_manifest_sha256: "e".repeat(64),
    candidates,
    message: "tuition validation preview",
    ...overrides,
  };
}

const expected = (billingMonth) => ({
  studentId: STUDENT_ID,
  businessEntityId: ENTITY_ID,
  billingMonth,
  billingExchangeRate: 0.05,
});

const julyCandidates = [
  candidate("30000000-0000-4000-8000-000000000001", "2026-07", "2026-07-27", "2026-07-27", 1, 2, 17000),
  candidate("30000000-0000-4000-8000-000000000002", "2026-07", "2026-07-27", "2026-08-02", 1, 2, 17000),
];
const july = validateTuitionValidationPreviewDetails(
  response("2026-07", julyCandidates),
  expected("2026-07")
);
assert.equal(july.candidate_count, 2);
assert.equal(july.total_fee_jpy, 34000);
assert.equal(july.candidates.every((row) => row.billing_month === "2026-07"), true);
assert.equal(formatAuthoritativeBillingWeek("2026-07-27"), "2026-07-27～2026-08-02");

const augustCandidates = [
  candidate("40000000-0000-4000-8000-000000000001", "2026-08", "2026-08-03", "2026-08-08", 1, 2, 17000, 330, 660),
  candidate("40000000-0000-4000-8000-000000000002", "2026-08", "2026-08-31", "2026-09-06", 1, 3, 15000, 660, 1980),
];
const august = validateTuitionValidationPreviewDetails(
  response("2026-08", augustCandidates),
  expected("2026-08")
);
assert.equal(august.total_base_lesson_fee_jpy, 32000);
assert.equal(august.total_aircon_fee_jpy, 2640);
assert.equal(august.total_fee_jpy, 34640);
assert.equal(august.candidates.some((row) => row.billing_week_start_date === "2026-07-27"), false);
assert.equal(august.candidates.some((row) => row.billing_week_start_date === "2026-08-31"), true);
assert.equal(formatAuthoritativeBillingWeek("2026-08-31"), "2026-08-31～2026-09-06");

assert.throws(
  () => validateTuitionValidationPreviewDetails(
    response("2026-08", [julyCandidates[0]]),
    expected("2026-08")
  ),
  /归属不一致/
);

const duplicate = [augustCandidates[0], { ...augustCandidates[0] }];
assert.throws(
  () => validateTuitionValidationPreviewDetails(response("2026-08", duplicate), expected("2026-08")),
  /重复planned lesson UUID/
);

assert.equal(
  validateTuitionValidationPreviewDetails(
    response("2026-08", augustCandidates, { total_fee_jpy: 999999, bill_amount_jpy: 999999 }),
    expected("2026-08")
  ).total_fee_jpy,
  999999,
  "frontend must consume the DB summary instead of recomputing it from candidate lines"
);

const serverFeeAuthority = response("2026-08", [{
  ...augustCandidates[0],
  unit_price_jpy: 999999,
  student_duration_overage_fee_jpy: 888888,
  base_lesson_fee_jpy: 17000,
  aircon_rate_jpy_per_hour: 330,
  aircon_fee_jpy: 660,
  course_total_jpy: 17660,
}], {
  total_lesson_count: 1,
  total_duration_hours: 2,
  total_base_lesson_fee_jpy: 17000,
  total_aircon_fee_jpy: 660,
  total_fee_jpy: 17660,
  bill_amount_jpy: 17660,
});
assert.equal(
  validateTuitionValidationPreviewDetails(serverFeeAuthority, expected("2026-08")).total_fee_jpy,
  17660,
  "UI contract must consume the server fee without duration, unit price, or overage recomputation"
);

const gate = createLatestTuitionPreviewRequestGate();
const julyRequest = gate.begin("student|2026-07|0.05");
const augustRequest = gate.begin("student|2026-08|0.05");
assert.equal(gate.isCurrent(julyRequest, "student|2026-07|0.05"), false);
assert.equal(gate.isCurrent(augustRequest, "student|2026-08|0.05"), true);
gate.invalidate();
assert.equal(gate.isCurrent(augustRequest, "student|2026-08|0.05"), false);

const pageSource = readFileSync(new URL("../js/pages/income-page.js", import.meta.url), "utf8");
const apiSource = readFileSync(new URL("../js/api/income-api.js", import.meta.url), "utf8");
const htmlSource = readFileSync(new URL("../income.html", import.meta.url), "utf8");
const sqlSource = readFileSync(new URL("../sql/current/school_tuition_r2_e_planned_aircon_fee_cutover.sql", import.meta.url), "utf8");

assert.doesNotMatch(pageSource, /\.rpc\s*\(/);
assert.doesNotMatch(pageSource, /supabase\.(?:from|rpc)\s*\(/);
assert.match(apiSource, /school_get_student_tuition_validation_preview_details/);
assert.match(pageSource, /validateTuitionValidationPreviewDetails/);
assert.match(pageSource, /tuitionBillPreviewRequestGate/);
assert.match(pageSource, /tuitionBillGenerationState\.isSubmitting\(\) \|\| isTuitionBillPreviewLoading/);
assert.match(pageSource, /innerHTML = preview\.candidates\.map/);
assert.doesNotMatch(pageSource, /innerHTML \+= preview\.candidates|\.concat\(preview\.candidates\)/);
assert.match(pageSource, /formatCurrency\(preview\.total_fee_jpy, "JPY"\)/);
assert.match(pageSource, /formatCurrency\(preview\.total_aircon_fee_jpy, "JPY"\)/);
assert.doesNotMatch(pageSource, /total_fee_jpy\s*=|duration_hours\s*\*\s*.*unit_price/);
assert.match(htmlSource, /validation-only RPC返回的权威学费月份/);
assert.match(htmlSource, /generateTuitionBillSubmitButton[^>]*disabled/);
assert.match(pageSource, /学费应收生成功能维护中，当前只能预览/);
assert.match(pageSource, /学费 Cash 提交正在整改，当前禁止提交/);
assert.match(pageSource, /generateStudentTuitionBillAtomic/);
assert.doesNotMatch(apiSource, /\.rpc\("school_generate_student_tuition_bill"/);
assert.doesNotMatch(apiSource, /school_create_student_tuition_bill_income_record/);
assert.match(sqlSource, /school_list_student_tuition_charge_candidates/);
assert.match(sqlSource, /GRANT EXECUTE ON FUNCTION public\.school_list_student_tuition_charge_candidates\([\s\S]*?\) TO service_role;/i);

console.log("authoritative tuition validation preview UI fixtures: PASS");
