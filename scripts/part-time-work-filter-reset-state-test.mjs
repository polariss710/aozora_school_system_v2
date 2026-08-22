import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import {
  buildPartTimeWorkFiltersUrl,
  normalizePartTimeWorkFilters,
  partTimeWorkFiltersFromUrl,
  resolvePartTimeWorkSettlementYearMonth,
} from "../js/utils/part-time-work-filter-state.js";

const page = fs.readFileSync("js/pages/part-time-work-page.js", "utf8");
const api = fs.readFileSync("js/api/part-time-work-api.js", "utf8");
const html = fs.readFileSync("part-time-work.html", "utf8");
const css = fs.readFileSync("css/app.css", "utf8");
const workplaces = ["诺应教育", "致远教育", "新领域"];
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");

assert.equal(
  hash(api),
  "476d5364e7f32ac00b2644e0285ccd3865debd9eff455e73d57cd57d84e524a9",
  "part-time-work API/RPC contract must remain byte-identical",
);

const resetHandler = page.match(/dom\.resetButton\.addEventListener\("click", \(\) => \{([\s\S]*?)\n  \}\);/)?.[1] || "";
const submitHandler = page.match(/dom\.filterForm\.addEventListener\("submit", \(event\) => \{([\s\S]*?)\n  \}\);/)?.[1] || "";
const clearHandler = page.match(/function clearQueryResults\(\) \{([\s\S]*?)\n\}/)?.[1] || "";
const loadHandler = page.match(/async function loadPageData\(options\) \{([\s\S]*?)\n\}/)?.[1] || "";
assert.match(resetHandler, /currentYearMonth\(\)/);
assert.match(resetHandler, /syncFiltersToUrl\(defaultFilters\)/);
assert.match(resetHandler, /clearQueryResults\(\)/);
assert.match(resetHandler, /showMessage\("success", "已重置筛选条件；点击“查询”后刷新结果。"\)/);
assert.doesNotMatch(resetHandler, /applyDraftFilters|loadPageData|renderVisibleLessons|renderWageCalculation/);
assert.match(submitHandler, /applyDraftFilters\(\)/);
assert.match(submitHandler, /syncFiltersToUrl\(readAppliedFilters\(\), \{ push: true \}\)/);
assert.match(submitHandler, /loadPageData/);
assert.doesNotMatch(page, /yearFilter\.addEventListener\("change",\s*updateMonthNavigationFromCurrentSelection/);
assert.doesNotMatch(page, /monthFilter\.addEventListener\("change",\s*updateMonthNavigationFromCurrentSelection/);
assert.match(page, /window\.addEventListener\("popstate", handleFilterHistoryNavigation\)/);

for (const pattern of [
  /pageDataRequestSequence \+= 1/,
  /appliedFilters = null/,
  /lessons = \[\]/,
  /wageLessons = \[\]/,
  /settlements = \[\]/,
  /editingLesson = null/,
  /pendingIncomeGenerationSettlement = null/,
  /lessonColumns\.innerHTML = ""/,
  /wageCalculationContainer\.innerHTML = ""/,
  /setLoading\(false\)/,
]) {
  assert.match(clearHandler, pattern);
}
assert.doesNotMatch(clearHandler, /expandedWorkplaces|collapsedWageWorkplaces|loadPageData|fetchPartTimeWork|history\.|location\.|\.click\(/);
assert.match(loadHandler, /const requestId = \+\+pageDataRequestSequence/);
assert.match(loadHandler, /requestId !== pageDataRequestSequence/);
assert.match(loadHandler, /requestId === pageDataRequestSequence/);

function makeState(view) {
  return {
    view,
    draft: { yearMonth: "2026-07", workplaceName: "致远教育", classDescription: "大学院升学指导" },
    applied: { yearMonth: "2026-07", workplaceName: "致远教育", classDescription: "大学院升学指导" },
    lessonCache: [{ id: "lesson-old" }],
    wageLessonCache: [{ id: "wage-old" }],
    settlementCache: [{ id: "settlement-old" }],
    lessonDom: "<section>old lessons</section>",
    settlementDom: "<section>old settlement</section>",
    selection: "lesson-old",
    resultContext: "settlement-old",
    loading: true,
    expandedLessonWorkplaces: ["致远教育"],
    collapsedWageWorkplaces: ["诺应教育", "新领域"],
    requestSequence: 4,
    reader: 0,
    writer: 0,
    navigation: 0,
    url: `https://school.example/part-time-work.html?view=${view}&year=2026&month=07&workplace_name=%E8%87%B4%E8%BF%9C%E6%95%99%E8%82%B2&class_description=%E5%A4%A7%E5%AD%A6%E9%99%A2%E5%8D%87%E5%AD%A6%E6%8C%87%E5%AF%BC`,
    message: "ready",
  };
}

function resetState(state) {
  const defaultFilters = normalizePartTimeWorkFilters({}, "2026-08", workplaces);
  state.draft = defaultFilters;
  state.applied = null;
  state.lessonCache = [];
  state.wageLessonCache = [];
  state.settlementCache = [];
  state.lessonDom = "";
  state.settlementDom = "";
  state.selection = null;
  state.resultContext = null;
  state.loading = false;
  state.requestSequence += 1;
  state.url = buildPartTimeWorkFiltersUrl(state.url, defaultFilters).href;
  state.message = "已重置筛选条件；点击“查询”后刷新结果。";
}

for (const view of ["lessons", "settlement"]) {
  const state = makeState(view);
  const lessonCollapse = [...state.expandedLessonWorkplaces];
  const wageCollapse = [...state.collapsedWageWorkplaces];
  const staleRequestId = state.requestSequence;
  resetState(state);
  resetState(state);
  assert.deepEqual(state.draft, { yearMonth: "2026-08", workplaceName: "", classDescription: "" });
  assert.equal(state.applied, null);
  assert.deepEqual(state.lessonCache, []);
  assert.deepEqual(state.wageLessonCache, []);
  assert.deepEqual(state.settlementCache, []);
  assert.equal(state.lessonDom, "");
  assert.equal(state.settlementDom, "");
  assert.equal(state.selection, null);
  assert.equal(state.resultContext, null);
  assert.equal(state.loading, false);
  assert.equal(new URL(state.url).searchParams.get("view"), view);
  assert.equal(new URL(state.url).searchParams.get("year"), "2026");
  assert.equal(new URL(state.url).searchParams.get("month"), "08");
  assert.equal(new URL(state.url).searchParams.has("workplace_name"), false);
  assert.equal(new URL(state.url).searchParams.has("class_description"), false);
  assert.deepEqual(state.expandedLessonWorkplaces, lessonCollapse);
  assert.deepEqual(state.collapsedWageWorkplaces, wageCollapse);
  assert.equal(state.reader, 0);
  assert.equal(state.writer, 0);
  assert.equal(state.navigation, 0);
  assert.equal(state.message, "已重置筛选条件；点击“查询”后刷新结果。");

  if (staleRequestId === state.requestSequence) {
    state.lessonDom = "<section>stale lessons</section>";
    state.settlementDom = "<section>stale settlement</section>";
  }
  assert.equal(state.lessonDom, "", `${view}: stale lessons must not repaint`);
  assert.equal(state.settlementDom, "", `${view}: stale settlement must not repaint`);

  state.applied = { ...state.draft };
  state.requestSequence += 1;
  state.reader += 3;
  state.lessonDom = "<section>fresh lessons</section>";
  state.settlementDom = "<section>fresh settlement</section>";
  assert.equal(state.reader, 3);
  assert.match(state.lessonDom, /fresh/);
  assert.match(state.settlementDom, /fresh/);
}

const cold = partTimeWorkFiltersFromUrl(
  "?view=settlement&year=2026&month=07&workplace_name=%E8%87%B4%E8%BF%9C%E6%95%99%E8%82%B2&class_description=%E5%A4%A7%E5%AD%A6%E9%99%A2%E5%8D%87%E5%AD%A6%E6%8C%87%E5%AF%BC",
  "2026-08",
  workplaces,
);
assert.deepEqual(cold, { yearMonth: "2026-07", workplaceName: "致远教育", classDescription: "大学院升学指导" });
const url = buildPartTimeWorkFiltersUrl("https://school.example/part-time-work.html?view=settlement&unrelated=kept", cold);
assert.equal(url.searchParams.get("view"), "settlement");
assert.equal(url.searchParams.get("unrelated"), "kept");
assert.equal(url.searchParams.get("year"), "2026");
assert.equal(url.searchParams.get("month"), "07");
assert.equal(url.searchParams.get("workplace_name"), "致远教育");
assert.equal(url.searchParams.get("class_description"), "大学院升学指导");
assert.deepEqual(partTimeWorkFiltersFromUrl(url.search, "2026-08", workplaces), cold);

assert.equal(resolvePartTimeWorkSettlementYearMonth({
  readerYearMonth: "2026-07",
  renderedYearMonth: "2026-07",
  appliedYearMonth: "2026-07",
}), "2026-07");
for (const unsafe of [
  { readerYearMonth: "", renderedYearMonth: "2026-07", appliedYearMonth: "2026-07" },
  { readerYearMonth: "2026-7", renderedYearMonth: "2026-07", appliedYearMonth: "2026-07" },
  { readerYearMonth: "2026-07", renderedYearMonth: "2026-08", appliedYearMonth: "2026-07" },
  { readerYearMonth: "2026-07", renderedYearMonth: "2026-07", appliedYearMonth: "2026-08" },
]) {
  assert.throws(() => resolvePartTimeWorkSettlementYearMonth(unsafe), /PTW_SETTLEMENT_YEAR_MONTH_UNSAFE/);
}

const settlementPayloadReader = page.match(/function readSettlementPayload\([\s\S]*?\n\}/)?.[0] || "";
assert.match(settlementPayloadReader, /settlement\.year_month/);
assert.match(settlementPayloadReader, /row\.dataset\.settlementYearMonth/);
assert.match(settlementPayloadReader, /appliedFilters\.yearMonth/);
assert.doesNotMatch(settlementPayloadReader, /getYearMonthSelectValue|yearFilter|monthFilter/);
assert.match(page, /data-settlement-year-month=/);
assert.match(page, /PTW_SETTLEMENT_YEAR_MONTH_UNSAFE|结算月份缺失或与当前结果不一致/);

assert.match(css, /@media \(max-width: 767px\)[\s\S]*?\.part-time-work-filter-panel \.filter-grid[\s\S]*?grid-template-columns: minmax\(0, 1fr\)/);
assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(page, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/);
assert.doesNotMatch(resetHandler, /createPartTimeWork|updatePartTimeWork|generatePartTimeWork|deletePartTimeWork|lockPartTimeWork|unlockPartTimeWork/);

console.log("PTW_P1_B_FILTER_RESET_STATE_TEST_PASS");
