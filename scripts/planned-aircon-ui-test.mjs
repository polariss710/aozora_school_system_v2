import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  hasAuthoritativePlannedFeeBundle,
  plannedAirconConditionLabel,
  plannedAirconPolicyLabel,
} from "../js/utils/planned-aircon-display.js";

const lessonHtml = readFileSync(new URL("../lesson.html", import.meta.url), "utf8");
const lessonPage = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const lessonDetailPage = readFileSync(new URL("../js/pages/lesson-detail-page.js", import.meta.url), "utf8");
const lessonApi = readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const lessonDetailApi = readFileSync(new URL("../js/api/lesson-detail-api.js", import.meta.url), "utf8");
const editDialog = readFileSync(new URL("../js/components/lesson-edit-dialog.js", import.meta.url), "utf8");
const incomeHtml = readFileSync(new URL("../income.html", import.meta.url), "utf8");
const incomePage = readFileSync(new URL("../js/pages/income-page.js", import.meta.url), "utf8");
const r2ffPolicy = readFileSync(new URL("../sql/current/school_tuition_r2_f_f_aircon_policy_cutover.sql", import.meta.url), "utf8");
const r2ff1Correction = readFileSync(new URL("../sql/current/school_tuition_r2_f_f1_planned_edit_aircon_recalculation_cutover.sql", import.meta.url), "utf8");

assert.match(lessonHtml, /createPlannedLessonAirconRateInput/);
assert.match(lessonHtml, /lessonBatchGenerateAirconRateInput/);
assert.match(lessonHtml, /editLessonAirconRateInput/);
assert.match(lessonHtml, /空调费率 JPY \/ planned小时/);

assert.match(lessonApi, /p_aircon_rate_jpy_per_hour:\s*payload\.airconRateJpyPerHour/);
assert.match(lessonApi, /args\.p_aircon_rate_jpy_per_hour\s*=\s*payload\.airconRateJpyPerHour/);
assert.match(lessonApi, /aircon_fee_jpy/);
assert.match(lessonApi, /lesson_total_fee_jpy/);
assert.match(lessonDetailApi, /aircon_unit_price_jpy_snapshot/);
assert.match(lessonDetailApi, /lesson_total_fee_jpy/);

assert.match(lessonPage, /aircon_rate_jpy_per_hour:\s*draft\.airconRateJpyPerHour/);
assert.match(lessonPage, /renderPlannedChargeBreakdown/);
assert.match(lessonPage, /hasAuthoritativePlannedFeeBundle/);
assert.match(lessonPage, /空调计费小时/);
assert.match(lessonPage, /record\.lesson_total_fee_jpy/);
assert.match(lessonDetailPage, /plannedAirconDetailRows/);
assert.match(lessonDetailPage, /hasAuthoritativePlannedFeeBundle/);
assert.match(lessonDetailPage, /isSource \? "来源 planned " : ""/);
assert.match(editDialog, /fee_components_frozen_at/);
assert.match(editDialog, /actual 只能展示来源 planned 的空调收费事实/);

assert.doesNotMatch(lessonPage, /\.rpc\s*\(/);
assert.doesNotMatch(lessonPage, /supabase\.(?:from|rpc)\s*\(/);
assert.doesNotMatch(lessonDetailPage, /\.rpc\s*\(/);
assert.doesNotMatch(editDialog, /\.rpc\s*\(/);
assert.doesNotMatch(lessonPage, /aircon_fee_jpy\s*[:=]\s*[^,\n]*\*/);
assert.doesNotMatch(editDialog, /aircon_fee_jpy\s*[:=]\s*[^,\n]*\*/);
assert.doesNotMatch(lessonPage, /fee_calculation_version\s*===\s*["']planned_weekend_aircon_v1/);
assert.doesNotMatch(lessonDetailPage, /fee_calculation_version\s*!==\s*["']planned_weekend_aircon_v1/);

const authoritativeBundle = {
  lesson_type: "planned",
  base_lesson_fee_jpy: 17000,
  aircon_unit_price_jpy_snapshot: 330,
  aircon_billable_hours_snapshot: 2,
  aircon_fee_jpy: 660,
  lesson_total_fee_jpy: 17660,
  aircon_charge_status: "calculated",
};
assert.equal(hasAuthoritativePlannedFeeBundle({
  ...authoritativeBundle,
  fee_calculation_version: "planned_weekend_aircon_v1",
  aircon_unit_price_jpy_snapshot: 0,
  aircon_billable_hours_snapshot: 2,
  aircon_fee_jpy: 0,
  lesson_total_fee_jpy: 17000,
}), true, "v1 zero bundle remains visible");
assert.equal(hasAuthoritativePlannedFeeBundle({
  ...authoritativeBundle,
  fee_calculation_version: "planned_weekend_venue_whole_hour_aircon_v2",
  aircon_unit_price_jpy_snapshot: 0,
  aircon_fee_jpy: 0,
  lesson_total_fee_jpy: 17000,
}), true, "v2 zero bundle remains visible");
assert.equal(hasAuthoritativePlannedFeeBundle({
  ...authoritativeBundle,
  fee_calculation_version: "planned_weekend_venue_whole_hour_aircon_v2",
}), true, "v2 positive bundle remains visible");
assert.equal(hasAuthoritativePlannedFeeBundle({
  ...authoritativeBundle,
  fee_calculation_version: "future_authoritative_aircon_v3",
}), true, "future authoritative positive bundle remains visible");
assert.equal(hasAuthoritativePlannedFeeBundle({
  ...authoritativeBundle,
  fee_calculation_version: "future_authoritative_aircon_v3",
  lesson_total_fee_jpy: null,
}), false, "incomplete future bundle does not masquerade as authoritative");
assert.equal(plannedAirconConditionLabel(authoritativeBundle), "周末固定办公室计费");
assert.equal(plannedAirconPolicyLabel({
  ...authoritativeBundle,
  fee_calculation_version: "planned_weekend_aircon_v1",
}), "周末固定办公室计费");
assert.equal(plannedAirconPolicyLabel({
  ...authoritativeBundle,
  fee_calculation_version: "planned_weekend_venue_whole_hour_aircon_v2",
}), "周末固定办公室计费");
assert.equal(plannedAirconPolicyLabel({
  ...authoritativeBundle,
  fee_calculation_version: "future_authoritative_aircon_v3",
}), "按课时冻结规则计费");
assert.doesNotMatch(lessonPage, /displayValue\(record\.fee_calculation_version\)/);
assert.doesNotMatch(lessonDetailPage, /displayValue\(planned\.fee_calculation_version\)/);

assert.match(incomeHtml, /基础课时费 JPY/);
assert.match(incomeHtml, /空调费 JPY/);
assert.match(incomeHtml, /课程总价 JPY/);
assert.match(incomePage, /candidate\.base_lesson_fee_jpy/);
assert.match(incomePage, /candidate\.aircon_rate_jpy_per_hour/);
assert.match(incomePage, /candidate\.aircon_fee_jpy/);
assert.match(incomePage, /candidate\.course_total_jpy/);

assert.match(r2ffPolicy, /'Regus办公室','Regus办公室',[\s\S]*?'onsite',true/);
assert.match(r2ffPolicy, /'Regus公共区','Regus公共区',[\s\S]*?'onsite',false/);
assert.match(r2ffPolicy, /v_whole_hours:=floor\(v_duration\)/);
assert.match(r2ffPolicy, /venue\.code=v_venue_code/);
assert.doesNotMatch(r2ffPolicy, /ILIKE|SIMILAR TO/);
assert.doesNotMatch(r2ffPolicy, /OLD\.fee_calculation_version IS NULL[\s\S]*?RETURN NEW/);
assert.match(r2ff1Correction, /CREATE OR REPLACE FUNCTION public\.school_enforce_r2_e_planned_aircon/);
assert.doesNotMatch(r2ff1Correction, /OLD\.fee_calculation_version IS NULL[\s\S]*?RETURN NEW/);
assert.match(r2ff1Correction, /NEW\.lesson_venue_id,NEW\.lesson_venue/);
assert.match(lessonHtml, /r2-f-f2-c-authoritative-month-refresh/);

console.log("planned aircon UI/API boundary fixtures: PASS");
