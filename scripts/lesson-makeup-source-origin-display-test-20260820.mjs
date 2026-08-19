import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import {
  formatMakeupSourceOriginDisplay,
  getMakeupSourceOriginDisplay,
} from "../js/utils/makeup-source-origin-display.js";

const root = fileURLToPath(new URL("../", import.meta.url));
const [api, page, html, app, config, sql] = await Promise.all([
  readFile(`${root}js/api/lesson-api.js`, "utf8"),
  readFile(`${root}js/pages/lesson-page.js`, "utf8"),
  readFile(`${root}lesson.html`, "utf8"),
  readFile(`${root}js/lesson-app.js`, "utf8"),
  readFile(`${root}js/config.js`, "utf8"),
  readFile(`${root}sql/current/school_open_lesson_credit_sources_v2_origin_display_20260820.sql`, "utf8"),
]);

const formatters = {
  formatDate: (value) => String(value || "").replaceAll("-", "/"),
  formatTimeRange: (start, end) => `${start}–${end}`,
};

function rendered(source) {
  const display = getMakeupSourceOriginDisplay(source);
  return {
    display,
    label: formatMakeupSourceOriginDisplay(display, formatters),
  };
}

const cancelled = rendered({
  origin_display_kind: "cancelled_original",
  origin_display_date: "2026-08-12",
  origin_display_start_time: "17:00",
  origin_display_end_time: "19:00",
  origin_display_selectable: true,
});
assert.equal(cancelled.label, "原定 2026/08/12 17:00–19:00");
assert.equal(cancelled.display.selectable, true);

const partialPlanned = rendered({
  origin_display_kind: "partial_planned_original",
  origin_display_date: "2026-07-29",
  origin_display_start_time: "16:30",
  origin_display_end_time: "18:30",
  origin_display_selectable: true,
});
assert.equal(partialPlanned.label, "原定 2026/07/29 16:30–18:30");

const partialActual = rendered({
  origin_display_kind: "partial_actual",
  origin_display_date: "2026-08-18",
  origin_display_start_time: "17:30",
  origin_display_end_time: "19:15",
  origin_display_selectable: true,
});
assert.equal(partialActual.label, "部分完成日 2026/08/18 17:30–19:15");

const weekFallback = rendered({
  origin_display_kind: "week_fallback",
  origin_display_date: "2026-07-06",
  origin_display_start_time: "09:00",
  origin_display_end_time: "10:00",
  origin_display_selectable: true,
});
assert.equal(weekFallback.label, "对应周 2026/07/06");

const ambiguous = rendered({
  origin_display_kind: "ambiguous",
  origin_display_date: "2026-08-01",
  origin_display_start_time: "09:00",
  origin_display_end_time: "10:00",
  origin_display_selectable: false,
});
assert.equal(ambiguous.label, "来源日期需核对");
assert.equal(ambiguous.display.selectable, false);
assert.equal(ambiguous.display.date, null);

const unknown = rendered({ origin_display_kind: "future_unknown", origin_display_selectable: true });
assert.equal(unknown.label, "来源日期需核对");
assert.equal(unknown.display.selectable, false);

const readFunction = api.match(
  /export async function fetchOpenMakeupSourceLessons[\s\S]*?\n}\n/
)?.[0] || "";
assert.match(readFunction, /school_list_open_lesson_credit_sources_v2/);
assert.doesNotMatch(readFunction, /school_list_open_lesson_credit_sources"/);

const writerFunction = api.match(
  /export async function createMakeupCompletedActualLessonFromPlanned[\s\S]*?\n}\n/
)?.[0] || "";
assert.match(writerFunction, /school_create_lesson_credit_makeup_actual/);
assert.match(writerFunction, /p_planned_lesson_id:\s*payload\.plannedLessonId/);
assert.doesNotMatch(writerFunction, /origin_(?:actual|display)/);

const fillFunction = page.match(
  /function fillCreateCrossMonthMakeupActualFromSource[\s\S]*?\n}\n/
)?.[0] || "";
assert.match(fillFunction, /sourceLesson\.start_time/);
assert.match(fillFunction, /sourceLesson\.end_time/);
assert.doesNotMatch(fillFunction, /origin_display/);

const payloadFunction = page.match(
  /function readCreateCrossMonthMakeupActualPayload[\s\S]*?\n}\n/
)?.[0] || "";
assert.match(payloadFunction, /plannedLessonId:\s*source\.id/);
assert.doesNotMatch(payloadFunction, /origin_actual_lesson_id/);
assert.doesNotMatch(page, /supabase\.rpc\s*\(/);
assert.match(page, /const disabled = originDisplay\.selectable \? "" : " disabled"/);
assert.match(page, /来源日期需核对，当前来源不能用于登记待补课完成/);

assert.match(config, /APP_VERSION = "v10\.5\.55"/);
assert.match(app, /makeup-source-origin-v2-20260820-1/);
assert.match(html, /lesson-app\.js\?v=makeup-source-origin-v2-20260820-1/);

assert.doesNotMatch(sql, /\blimit\s+1\b/i);
assert.doesNotMatch(sql, /\bfetch\s+first\s+1\b/i);
assert.match(sql, /origin_candidate_count<>1/);
assert.match(sql, /valid_complete_candidate_count<>1/);
assert.match(sql, /classified\.origin_kind<>'ambiguous'/);
assert.match(sql, /school_assert_lesson_clearance_reader\(\)/);
assert.match(sql, /revoke all[\s\S]*from public,anon,authenticated,service_role/);
assert.match(sql, /grant execute[\s\S]*to authenticated/);
assert.doesNotMatch(sql, /\b(?:insert|update|delete|truncate|drop)\b/i);

console.log("lesson makeup source origin display tests passed");
