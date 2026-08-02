import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  createLatestTuitionPreviewRequestGate,
  formatAuthoritativeBillingWeek,
  mapTuitionValidationPreviewError,
  validateTuitionValidationPreviewDetails,
} from "../js/utils/tuition-validation-preview.js";

const STUDENT_ID = "11111111-1111-4111-8111-111111111111";
const ENTITY_ID = "22222222-2222-4222-8222-222222222222";
const TEACHER_ID = "33333333-3333-4333-8333-333333333333";
const SUBJECT_ID = "44444444-4444-4444-8444-444444444444";

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
    teacher_id: TEACHER_ID,
    subject_id: SUBJECT_ID,
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
    complete_row_hash: "c".repeat(32),
    candidate_line_hash: "d".repeat(64),
  };
}

function response(billingMonth, candidates, overrides = {}) {
  return {
    feature_state: "enabled",
    generate_feature_state: "enabled",
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

const alreadyBilledMessage = mapTuitionValidationPreviewError(
  new Error("R2_F_B_ALREADY_BILLED: internal-id")
).message;
const emptyCandidateMessage = mapTuitionValidationPreviewError(
  new Error("R2_F_B_CANDIDATES_EMPTY: internal-id")
).message;
assert.equal(alreadyBilledMessage, "该学生本月学费账单已生成，不能重复生成。");
assert.equal(emptyCandidateMessage, "该学生本月没有可生成学费账单的课程。");
assert.notEqual(alreadyBilledMessage, emptyCandidateMessage);
assert.doesNotMatch(`${alreadyBilledMessage}${emptyCandidateMessage}`, /R2_F_B_|internal-id|[0-9a-f]{8}-/i);
assert.equal(
  mapTuitionValidationPreviewError(
    new Error("R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE: internal-id")
  ).message,
  "学费预览生成失败，请刷新页面后重试；如仍失败请联系管理员核对。"
);
assert.equal(
  mapTuitionValidationPreviewError(new Error("database internal diagnostics 303170f4-1c99-483b-a1ac-6ce23e27ad29")).message,
  "学费预览生成失败，请刷新页面后重试；如仍失败请联系管理员核对。"
);
assert.throws(
  () => validateTuitionValidationPreviewDetails(
    response("2026-08", [{ ...augustCandidates[0], complete_row_hash: "c".repeat(64) }]),
    expected("2026-08")
  ),
  /冻结证据无效/
);

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
const cssSource = readFileSync(new URL("../css/app.css", import.meta.url), "utf8");
const incomeAppSource = readFileSync(new URL("../js/income-app.js", import.meta.url), "utf8");
const sqlSource = readFileSync(new URL("../sql/current/school_tuition_r2_e_planned_aircon_fee_cutover.sql", import.meta.url), "utf8");
const r2ffPolicySource = readFileSync(new URL("../sql/current/school_tuition_r2_f_f_aircon_policy_cutover.sql", import.meta.url), "utf8");
const previewRendererSource = pageSource.slice(
  pageSource.indexOf("function renderTuitionBillPreview"),
  pageSource.indexOf("function clearTuitionBillPreview")
);

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
assert.match(htmlSource, /当前权威预览返回的学费月份、自然周、课程信息和服务端费用/);
assert.match(htmlSource, /generateTuitionBillSubmitButton[^>]*disabled/);
assert.match(pageSource, /preview\.generate_feature_state/);
assert.match(pageSource, /学费 Cash 提交正在整改，当前禁止提交/);
assert.match(pageSource, /generateStudentTuitionBillAtomic/);
assert.doesNotMatch(previewRendererSource, /candidate集合|生成manifest|candidate_uuid_md5|generation_manifest_sha256/);
assert.doesNotMatch(htmlSource, /planned lesson UUID|candidate集合|生成manifest/);
assert.match(htmlSource, /<th>科目<\/th>[\s\S]*<th>老师<\/th>/);
assert.match(pageSource, /subjectNameById\(candidate\.subject_id\)/);
assert.match(pageSource, /teacherNameById\(candidate\.teacher_id\)/);
assert.match(pageSource, /fetchLessonTeachers\(\)/);
assert.match(pageSource, /fetchLessonSubjects\(\)/);
assert.match(htmlSource, /<details id="tuitionBillCandidateDetails"[^>]*>/);
assert.doesNotMatch(htmlSource, /<details id="tuitionBillCandidateDetails"[^>]*\sopen(?:\s|>)/);
assert.match(htmlSource, /tuition-bill-dialog-body[\s\S]*tuitionBillCandidateDetails[\s\S]*<\/div>\s*<div class="dialog-actions">/);
assert.match(cssSource, /\.tuition-bill-preview-summary\s*\{[\s\S]*?grid-template-columns:\s*repeat\(2,\s*minmax\(0,\s*1fr\)\)/);
assert.match(cssSource, /@media \(max-width:\s*767px\)[\s\S]*?\.tuition-bill-preview-summary\s*\{[\s\S]*?grid-template-columns:\s*minmax\(0,\s*1fr\)/);
assert.match(cssSource, /\.tuition-bill-dialog-body\s*\{[\s\S]*?overflow-y:\s*auto/);
assert.match(cssSource, /\.tuition-bill-dialog-panel\s*\{[\s\S]*?overflow:\s*hidden/);
assert.doesNotMatch(pageSource, /generateTuitionBillDialog\.addEventListener\(\s*["']click/);
assert.match(incomeAppSource, /income-page\.js\?v=v2\.115\.2-tuition-duplicate-message/);
assert.match(htmlSource, /income-app\.js\?v=v2\.115\.2-tuition-duplicate-message/);
assert.match(pageSource, /tuition-validation-preview\.js\?v=v2\.115\.2-tuition-duplicate-message/);
assert.doesNotMatch(apiSource, /\.rpc\("school_generate_student_tuition_bill"/);
assert.doesNotMatch(apiSource, /school_create_student_tuition_bill_income_record/);
assert.match(sqlSource, /school_list_student_tuition_charge_candidates/);
assert.match(sqlSource, /GRANT EXECUTE ON FUNCTION public\.school_list_student_tuition_charge_candidates\([\s\S]*?\) TO service_role;/i);
assert.match(r2ffPolicySource, /planned_weekend_venue_whole_hour_aircon_v2/);
assert.match(r2ffPolicySource, /floor\(v_duration\)/);
assert.match(r2ffPolicySource, /venue\.code=v_venue_code/);
assert.doesNotMatch(r2ffPolicySource, /ILIKE|SIMILAR TO/);

console.log("authoritative tuition validation preview UI fixtures: PASS");
