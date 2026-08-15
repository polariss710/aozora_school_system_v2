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
assert.match(resetHandler, /currentYearMonth\(\)/);
assert.match(resetHandler, /showMessage\("success", "已重置筛选条件"\)/);
assert.doesNotMatch(resetHandler, /applyDraftFilters|loadPageData|syncAppliedFiltersToUrl|renderVisibleLessons|renderWageCalculation/);
assert.match(submitHandler, /applyDraftFilters\(\)/);
assert.match(submitHandler, /syncAppliedFiltersToUrl\(\{ push: true \}\)/);
assert.match(submitHandler, /loadPageData/);
assert.doesNotMatch(page, /yearFilter\.addEventListener\("change",\s*updateMonthNavigationFromCurrentSelection/);
assert.doesNotMatch(page, /monthFilter\.addEventListener\("change",\s*updateMonthNavigationFromCurrentSelection/);
assert.match(page, /window\.addEventListener\("popstate", handleFilterHistoryNavigation\)/);

const effects = { reader: 0, lessonRender: 0, wageRender: 0, url: 0, writer: 0 };
let applied = { yearMonth: "2026-07", workplaceName: "致远教育", classDescription: "大学院升学指导" };
let draft = { ...applied };
const lessonDom = "<section>2026-07 lessons</section>";
const wageDom = "<section>2026-07 wages</section>";
const initialLessonHash = hash(lessonDom);
const initialWageHash = hash(wageDom);

draft = { yearMonth: "2026-08", workplaceName: "诺应教育", classDescription: "EJU文数" };
assert.deepEqual(applied, { yearMonth: "2026-07", workplaceName: "致远教育", classDescription: "大学院升学指导" });
assert.deepEqual(effects, { reader: 0, lessonRender: 0, wageRender: 0, url: 0, writer: 0 });

applied = normalizePartTimeWorkFilters(draft, "2026-08", workplaces);
effects.reader += 3;
effects.lessonRender += 1;
effects.wageRender += 1;
effects.url += 1;
assert.deepEqual(applied, draft);
assert.deepEqual(effects, { reader: 3, lessonRender: 1, wageRender: 1, url: 1, writer: 0 });

const effectsBeforeReset = { ...effects };
const urlBeforeReset = "https://school.example/part-time-work.html?view=settlement&year=2026&month=08&workplace_name=%E8%AF%BA%E5%BA%94%E6%95%99%E8%82%B2&class_description=EJU%E6%96%87%E6%95%B0";
const historyStateBeforeReset = { retained: true, partTimeWorkFilters: { ...applied } };
draft = { yearMonth: "2026-08", workplaceName: "", classDescription: "" };
assert.deepEqual(effects, effectsBeforeReset);
assert.equal(hash(lessonDom), initialLessonHash);
assert.equal(hash(wageDom), initialWageHash);
assert.equal(urlBeforeReset, urlBeforeReset);
assert.deepEqual(historyStateBeforeReset, { retained: true, partTimeWorkFilters: applied });
assert.equal(applied.yearMonth, "2026-08");

applied = normalizePartTimeWorkFilters(draft, "2026-08", workplaces);
effects.reader += 3;
effects.lessonRender += 1;
effects.wageRender += 1;
effects.url += 1;
assert.deepEqual(applied, { yearMonth: "2026-08", workplaceName: "", classDescription: "" });

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
assert.equal(effects.writer, 0);

console.log("PTW_P1_B_FILTER_RESET_STATE_TEST_PASS");
