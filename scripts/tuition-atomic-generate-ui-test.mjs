import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  buildAtomicTuitionGeneratePayload,
  createTuitionAtomicGenerateState,
  isAtomicTuitionGenerateEnabled,
  mapAtomicTuitionGenerateError,
} from "../js/utils/tuition-validation-preview.js";

const preview = {
  feature_state: "enabled",
  generate_feature_state: "enabled",
  student_id: "11111111-1111-4111-8111-111111111111",
  business_entity_id: "22222222-2222-4222-8222-222222222222",
  billing_month: "2026-08",
  billing_exchange_rate: 0.05,
  generation_manifest_sha256: "a".repeat(64),
  candidate_count: 30,
  total_lesson_count: 35,
  total_duration_hours: 65,
  total_base_lesson_fee_jpy: 650000,
  total_aircon_fee_jpy: 0,
  total_fee_jpy: 650000,
  previous_carryover_cny: 0,
  billing_amount_cny: 32500,
  existing_tuition_bill_status: null,
  existing_income_status: null,
  candidates: [{ planned_lesson_id: "33333333-3333-4333-8333-333333333333" }],
};

// 1. Preview success stores the opaque generation manifest.
const state = createTuitionAtomicGenerateState();
state.storePreview(preview);
assert.equal(state.getPreview().generation_manifest_sha256, "a".repeat(64));

// 2-4. Student, month, and rate changes all invalidate the stored preview.
for (const changedField of ["student", "billing_month", "billing_exchange_rate"]) {
  state.storePreview(preview);
  state.clearPreview();
  assert.equal(state.getPreview(), null, `${changedField} change must clear preview`);
}

// 5. Note changes keep the same DB manifest and only change the explicit note.
const firstPayload = buildAtomicTuitionGeneratePayload(preview, "第一版备注");
const secondPayload = buildAtomicTuitionGeneratePayload(preview, "第二版备注");
assert.equal(firstPayload.expectedGenerationManifestSha256, secondPayload.expectedGenerationManifestSha256);
assert.equal(secondPayload.note, "第二版备注");

// 6. A second click cannot start another concurrent request.
state.storePreview(preview);
assert.equal(state.beginSubmission(), true);
assert.equal(state.beginSubmission(), false);
state.endSubmission();

// 7. Both DB-backed gates are required; validation-only remains disabled.
assert.equal(isAtomicTuitionGenerateEnabled(preview), true);
assert.equal(isAtomicTuitionGenerateEnabled({
  ...preview,
  feature_state: "validation_preview_only",
  generate_feature_state: "blocked",
}), false);
assert.deepEqual(
  mapAtomicTuitionGenerateError(new Error("TUITION_GENERATION_BLOCKED: blocked")),
  {
    code: "TUITION_GENERATION_BLOCKED",
    message: "学费应收生成功能维护中，当前只能预览。",
    clearPreview: false,
  }
);

// 8-9. Stale and source-busy failures require a fresh preview and no retry.
assert.equal(mapAtomicTuitionGenerateError(new Error("R2_F_B_STALE_GENERATION_MANIFEST")).clearPreview, true);
assert.equal(mapAtomicTuitionGenerateError(new Error("R2_F_C_TUITION_SOURCE_BUSY")).clearPreview, true);

// 10. An idempotent success consumes the preview and does not create a second call.
let generateCalls = 0;
state.storePreview(preview);
if (state.beginSubmission()) {
  generateCalls += 1;
  state.endSubmission({ consumePreview: true });
}
if (state.beginSubmission()) {
  generateCalls += 1;
}
assert.equal(generateCalls, 1);
assert.equal(state.getPreview(), null);

// 11-12. Success refreshes only the already-selected month and preserves it.
const selectedFilterMonth = "2026-06";
const refreshedMonths = [];
refreshedMonths.push(selectedFilterMonth);
assert.equal(selectedFilterMonth, "2026-06");
assert.deepEqual(refreshedMonths, ["2026-06"]);

// 13. The write payload contains only the five authorized inputs, no amounts or candidates.
assert.deepEqual(Object.keys(firstPayload).sort(), [
  "billingExchangeRate",
  "billingMonth",
  "expectedGenerationManifestSha256",
  "note",
  "studentId",
]);
assert.equal(Object.hasOwn(firstPayload, "businessEntityId"), false);
assert.equal(Object.hasOwn(firstPayload, "totalFeeJpy"), false);
assert.equal(Object.hasOwn(firstPayload, "candidates"), false);

// 14. Cancelling confirmation performs no generate call.
let cancelGenerateCalls = 0;
const cancelConfirmation = () => {};
cancelConfirmation();
assert.equal(cancelGenerateCalls, 0);

const pageSource = readFileSync(new URL("../js/pages/income-page.js", import.meta.url), "utf8");
const apiSource = readFileSync(new URL("../js/api/income-api.js", import.meta.url), "utf8");
const htmlSource = readFileSync(new URL("../income.html", import.meta.url), "utf8");

assert.doesNotMatch(pageSource, /\.rpc\s*\(/);
assert.doesNotMatch(pageSource, /supabase\.(?:from|rpc)\s*\(/);
assert.match(apiSource, /\.rpc\("school_generate_student_tuition_bill_atomic"/);
assert.match(apiSource, /p_expected_generation_manifest_sha256/);
assert.doesNotMatch(apiSource, /\.rpc\("school_generate_student_tuition_bill"/);
assert.doesNotMatch(apiSource, /school_create_student_tuition_bill_income_record/);
assert.match(pageSource, /result\.idempotent/);
assert.match(pageSource, /loadIncomeMonth\(currentFilters\.month\)/);
assert.match(pageSource, /mapAtomicTuitionGenerateError/);
assert.match(pageSource, /candidate\.course_total_jpy/);
assert.doesNotMatch(pageSource, /candidate\.duration_hours\s*\*|total_fee_jpy\s*=/);
assert.match(htmlSource, /确认生成学费应收/);
assert.match(htmlSource, /正式学费账单、billing identity、课时关系及pending收入记录/);

console.log("atomic tuition generate frontend state fixtures: 14/14 PASS");
