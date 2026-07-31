import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const lessonHtml = readFileSync(new URL("../lesson.html", import.meta.url), "utf8");
const lessonPage = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const lessonDetailPage = readFileSync(new URL("../js/pages/lesson-detail-page.js", import.meta.url), "utf8");
const lessonApi = readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const lessonDetailApi = readFileSync(new URL("../js/api/lesson-detail-api.js", import.meta.url), "utf8");
const editDialog = readFileSync(new URL("../js/components/lesson-edit-dialog.js", import.meta.url), "utf8");
const incomeHtml = readFileSync(new URL("../income.html", import.meta.url), "utf8");
const incomePage = readFileSync(new URL("../js/pages/income-page.js", import.meta.url), "utf8");
const r2ffPolicy = readFileSync(new URL("../sql/current/school_tuition_r2_f_f_aircon_policy_cutover.sql", import.meta.url), "utf8");

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
assert.match(lessonPage, /本课非周末/);
assert.match(lessonPage, /record\.lesson_total_fee_jpy/);
assert.match(lessonDetailPage, /plannedAirconDetailRows/);
assert.match(lessonDetailPage, /isSource \? "来源 planned " : ""/);
assert.match(editDialog, /fee_components_frozen_at/);
assert.match(editDialog, /actual 只能展示来源 planned 的空调收费事实/);

assert.doesNotMatch(lessonPage, /\.rpc\s*\(/);
assert.doesNotMatch(lessonPage, /supabase\.(?:from|rpc)\s*\(/);
assert.doesNotMatch(lessonDetailPage, /\.rpc\s*\(/);
assert.doesNotMatch(editDialog, /\.rpc\s*\(/);
assert.doesNotMatch(lessonPage, /aircon_fee_jpy\s*[:=]\s*[^,\n]*\*/);
assert.doesNotMatch(editDialog, /aircon_fee_jpy\s*[:=]\s*[^,\n]*\*/);

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

console.log("planned aircon UI/API boundary fixtures: PASS");
